extends Node3D
## 地表林业/矿物的唯一入口：占地释放、物资拾取、日切补充和树苗种植。

signal loot_collected(kind: String, amount: int)
signal notice(message: String)

const ResourceNode = preload("res://scripts/surface_resource.gd")
const Drop = preload("res://scripts/surface_drop.gd")
const M = preload("res://scripts/art/art_mesh.gd")
const SURFACE_ORES := ["stone", "copper", "coal"]
const TREE_CAP := 220
const ORE_CAP := 48
const SAPLING_CHANCE := 0.30
const REACH := 2.4

var tiles: Node3D
var player: CharacterBody3D
var world: Dictionary
var actors: Callable
var resources: Array[Node3D] = []
var drops: Array[Node3D] = []
var rng := RandomNumberGenerator.new()
var paused := false
var last_rollover_day := 1
var _focus_ring: MeshInstance3D


func _ready() -> void:
	_focus_ring = M.torus(self, Vector3.ZERO, 0.88, 0.022, "#ebd99a", "ResourceFocus")
	_focus_ring.hide()
	rng.randomize()


func populate() -> void:
	for entry: Dictionary in world["resources"]:
		_add_resource(entry)
	_scatter("ore", 24, true)


func _add_resource(entry: Dictionary) -> Node3D:
	var category: String = entry.get("category", "tree")
	var kind: String = entry.get("kind", "stone")
	var species: String = entry.get("species", "oak")
	# 白名单在创建边界执行，补充、手工放置均无法生成地矿专属矿物。
	if category not in ["tree", "ore"] or (category == "ore" and kind not in SURFACE_ORES) or species not in ["oak", "pine", "apple"]:
		return null
	var resource := ResourceNode.new()
	resource.category = category
	resource.kind = kind
	resource.species = species
	resource.stage = clampi(entry.get("stage", 3), 0, 3)
	resource.variant = entry.get("variant", rng.randi_range(0, 5))
	resource.size_factor = entry.get("scale", 1.0)
	resource.yaw = entry.get("yaw", rng.randf_range(0, TAU))
	resource.planted = entry.get("planted", false)
	resource.player = player
	var at: Vector2 = entry["position"]
	resource.position = Vector3(at.x, 0, at.y)
	resource.name = "Tree" if category == "tree" else "SurfaceOre"
	resource.broken.connect(_on_broken)
	add_child(resource)
	resources.append(resource)
	tiles.occupy_resource(resource.get_instance_id(), at, resource.occupied_radius())
	return resource


func can_spawn(at: Vector2, category: String = "tree", natural: bool = true) -> bool:
	if category not in ["tree", "ore"]:
		return false
	var clearance := 1.7 if category == "tree" else 1.1
	if not tiles.is_clear_area(at, clearance):
		return false
	if natural:
		for region: Rect2 in world["reserved"]:
			# 未开垦的农场草地也可长树；真正的田块由 Tiles 永久保护。
			if region == world["navigation"]["farm"]:
				continue
			if region.grow(clearance).has_point(at):
				return false
	if actors.is_valid():
		for actor: Node3D in actors.call():
			if is_instance_valid(actor) and Vector2(actor.global_position.x, actor.global_position.z).distance_to(at) < (clearance + 1.0 if natural else 1.05):
				return false
	for drop in drops:
		if is_instance_valid(drop) and Vector2(drop.position.x, drop.position.z).distance_to(at) < clearance + 0.65:
			return false
	return true


func try_spawn(entry: Dictionary, natural: bool = true) -> Node3D:
	if not entry.has("position") or not can_spawn(entry["position"], entry.get("category", "tree"), natural):
		return null
	return _add_resource(entry)


func plant_sapling(at: Vector2) -> Node3D:
	return try_spawn({"position": at, "category": "tree", "species": "pine" if rng.randf() < 0.30 else "oak", "stage": 0, "planted": true}, false)


func on_day_rollover(day: int) -> Dictionary:
	if day <= last_rollover_day:
		return {"grown": 0, "trees": 0, "ores": 0}
	last_rollover_day = day
	var grown := 0
	for resource in resources:
		if resource.grow():
			grown += 1
	return {"grown": grown, "trees": _scatter("tree", rng.randi_range(3, 6)), "ores": _scatter("ore", rng.randi_range(2, 4))}


func count_resources(category: String) -> int:
	var count := 0
	for resource in resources:
		if resource.category == category and not resource.depleted:
			count += 1
	return count


func _scatter(category: String, requested: int, outer_only: bool = false) -> int:
	var count := 0
	var limit := mini(requested, (TREE_CAP if category == "tree" else ORE_CAP) - count_resources(category))
	for attempt in range(maxi(0, limit) * 70):
		if count >= limit:
			break
		var half: Vector2 = world["bounds"]["half"] - Vector2(5, 5)
		var at := Vector2(rng.randf_range(-half.x, half.x), rng.randf_range(-half.y, half.y))
		if (outer_only or rng.randf() < 0.75) and absf(at.x) < 62 and absf(at.y) < 54:
			continue
		var entry := {"position": at, "category": category, "stage": 0}
		if category == "tree":
			entry["species"] = "pine" if rng.randf() < 0.48 else "oak"
		else:
			var roll := rng.randf()
			entry["kind"] = "stone" if roll < 0.55 else ("copper" if roll < 0.85 else "coal")
		if try_spawn(entry) != null:
			count += 1
	return count


func clear_focus() -> void:
	_focus_ring.hide()


func target_at(at: Vector3, tool: String) -> Dictionary:
	clear_focus()
	var closest: Node3D
	var best := REACH + 0.01
	for resource in resources:
		var distance := at.distance_to(resource.position)
		if not resource.depleted and distance < best and clear_line(at, resource.position, resource):
			closest = resource
			best = distance
	if closest == null:
		return {}
	_focus_ring.position = closest.position + Vector3(0, 0.055, 0)
	_focus_ring.show()
	var hint := ""
	if tool != closest.required_tool():
		hint = ("8 换斧头 · " if closest.category == "tree" else "6 换镐子 · ") + closest.label()
	elif closest.category == "tree":
		hint = "E / 空格 / 左键 砍伐 %s · %d / %d" % [closest.label(), closest.health, closest.max_health()]
		if closest.stage < 3:
			hint = "树苗还需 %d 天长大 · E 用斧头回收" % (3 - closest.stage)
	else:
		hint = "E / 空格 / 左键 开采%s · %d / %d" % [closest.label(), closest.health, closest.max_health()]
	return {"kind": "surface_resource", "node": closest, "hint": hint}


func swing(tool: String, from: Vector3, facing: Vector3, power: float = 1.0) -> int:
	if paused or tool not in ["axe", "pickaxe"]:
		return 0
	var closest: Node3D
	var best := REACH + 0.01
	for resource in resources:
		if resource.depleted or resource.required_tool() != tool:
			continue
		var delta: Vector3 = resource.position - from
		if delta.length() < best and (delta.length() < 0.3 or facing.dot(delta.normalized()) >= 0.57) and clear_line(from, resource.position, resource):
			closest = resource
			best = delta.length()
	if closest != null:
		return closest.hit(tool, maxi(1, roundi(18 * power)), from)
	return 0


func clear_line(from: Vector3, to: Vector3, target: CollisionObject3D = null) -> bool:
	var ray := PhysicsRayQueryParameters3D.create(from + Vector3(0, 0.62, 0), to + Vector3(0, 0.62, 0), 1)
	if target != null:
		ray.exclude = [target.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(ray).is_empty()


func roll_tree_loot(mature: bool) -> Dictionary:
	if not mature:
		return {"sapling": 1}
	var result := {"wood": rng.randi_range(4, 7)}
	if rng.randf() < SAPLING_CHANCE:
		result["sapling"] = 1
	return result


func _on_broken(resource: Node3D) -> void:
	resources.erase(resource)
	tiles.release_resource(resource.get_instance_id())
	clear_focus()
	var loot: Dictionary = roll_tree_loot(resource.stage == 3) if resource.category == "tree" else {resource.kind: rng.randi_range(1, 3)}
	var offset := 0
	for kind: String in loot:
		spawn_drop(kind, loot[kind], resource.position + Vector3(offset * 0.55, 0, 0.30))
		offset += 1


func spawn_drop(kind: String, amount: int, at: Vector3) -> Node3D:
	if kind not in SURFACE_ORES and kind not in ["wood", "sapling"]:
		return null
	var drop := Drop.new()
	drop.kind = kind
	drop.amount = amount
	drop.position = at
	drop.player = player
	add_child(drop)
	drops.append(drop)
	drop.collected.connect(func(item: Node3D):
		drops.erase(item)
		loot_collected.emit(item.kind, item.amount)
	)
	return drop


## ---- 存档：地表资源与掉落物的完整状态；读档后按状态重建 ----

func to_dict() -> Dictionary:
	var entries: Array = []
	for resource in resources:
		if resource.depleted:
			continue
		entries.append({
			"category": resource.category, "kind": resource.kind, "species": resource.species,
			"stage": resource.stage, "variant": resource.variant, "scale": resource.size_factor,
			"yaw": resource.yaw, "planted": resource.planted,
			"position": [resource.position.x, resource.position.z],
		})
	var drop_entries: Array = []
	for drop in drops:
		if is_instance_valid(drop):
			drop_entries.append({"kind": drop.kind, "amount": drop.amount, "position": [drop.position.x, drop.position.y, drop.position.z]})
	return {"resources": entries, "drops": drop_entries}


func apply_state(data: Dictionary) -> void:
	for resource in resources:
		tiles.release_resource(resource.get_instance_id())
		resource.queue_free()
	resources.clear()
	for drop in drops:
		if is_instance_valid(drop):
			drop.queue_free()
	drops.clear()
	clear_focus()
	for entry: Dictionary in data.get("resources", []):
		var restored := entry.duplicate(true)
		restored["position"] = Vector2(entry["position"][0], entry["position"][1])
		_add_resource(restored)
	for entry: Dictionary in data.get("drops", []):
		var position: Array = entry.get("position", [0, 0, 0])
		spawn_drop(entry.get("kind", "wood"), int(entry.get("amount", 1)), Vector3(position[0], position[1], position[2]))
