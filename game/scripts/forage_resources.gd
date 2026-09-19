extends Node3D
## 采集系统（GATHER-01 / PRD 第 12 节）：野外植物与海贝的唯一入口。
## 每天按栖息地确定性刷新一小批，跨季清理不合季物种；节点无碰撞，不影响寻路。
## 对应 PRD ResourceNode 三接口：can_harvest→target_at 命中、harvest→gather、respawn→on_day_rollover。

signal forage_picked(kind: String)

const Plant := preload("res://scripts/forage_resource.gd")
const ForageDB := preload("res://scripts/data/forage_db.gd")
const M := preload("res://scripts/art/art_mesh.gd")

const REACH := 2.3
const MIN_SPACING := 2.6
const TOTAL_CAP := 90
const FIRST_DAY_SPAWNS := Vector2i(7, 10)
const DAILY_SPAWNS := Vector2i(4, 7)

var tiles: Node3D
var world: Dictionary
var rng := RandomNumberGenerator.new()
var nodes: Array[Node3D] = []
var last_season := "spring"
var _focus_ring: MeshInstance3D


func _ready() -> void:
	_focus_ring = M.torus(self, Vector3.ZERO, 0.95, 0.028, "#f2c94c", "ForageFocus")
	_focus_ring.hide()
	rng.randomize()


func populate(context: Dictionary) -> void:
	last_season = context.get("season", "spring")
	_spawn_batch(context, rng.randi_range(FIRST_DAY_SPAWNS.x, FIRST_DAY_SPAWNS.y))


## 日切：换季清理不合季物种，再按新的一天补种一批。返回 {"removed","spawned"}。
func on_day_rollover(day: int, season: String, weather: String) -> Dictionary:
	var removed := 0
	if season != last_season:
		for node in nodes.duplicate():
			if is_instance_valid(node) and season not in ForageDB.seasons_of(node.kind):
				removed += 1
				_remove(node)
	last_season = season
	rng.seed = day * 7919 + 137
	var spawned := _spawn_batch({"season": season, "weather": weather}, rng.randi_range(DAILY_SPAWNS.x, DAILY_SPAWNS.y))
	return {"removed": removed, "spawned": spawned}


func count() -> int:
	var result := 0
	for node in nodes:
		if is_instance_valid(node):
			result += 1
	return result


func clear_focus() -> void:
	_focus_ring.hide()


func target_at(at: Vector3) -> Dictionary:
	clear_focus()
	var closest: Node3D
	var best := REACH
	for node in nodes:
		if not is_instance_valid(node):
			continue
		var distance := Vector2(at.x - node.position.x, at.z - node.position.z).length()
		if distance < best:
			closest = node
			best = distance
	if closest == null:
		return {}
	_focus_ring.position = closest.position + Vector3(0, 0.06, 0)
	_focus_ring.show()
	var rarity_text := ""
	match ForageDB.rarity(closest.kind):
		"uncommon":
			rarity_text = " · 少见"
		"rare":
			rarity_text = " · 稀有"
	return {"kind": "forage", "node": closest, "hint": "E 采集 %s · %d 币%s" % [closest.label(), ForageDB.sell_price(closest.kind), rarity_text]}


## 徒手采收：返回物种 id；节点不属于本管理器时返回空串。
func gather(node: Node3D) -> String:
	if not is_instance_valid(node) or node not in nodes:
		return ""
	var kind: String = node.kind
	nodes.erase(node)
	clear_focus()
	node.queue_free()
	forage_picked.emit(kind)
	return kind


func _spawn_batch(context: Dictionary, requested: int) -> int:
	var spawned := 0
	for attempt in range(maxi(0, requested) * 6):
		if spawned >= requested or nodes.size() >= TOTAL_CAP:
			break
		var pick: Dictionary = ForageDB.roll_anywhere(rng, context)
		if pick.is_empty():
			break
		var at := _find_spot(pick["habitat"], rng)
		if not at.is_finite():
			continue
		_spawn_entry(pick["kind"], at)
		spawned += 1
	return spawned


func _spawn_entry(kind: String, at: Vector2) -> Node3D:
	var plant := Plant.new()
	plant.setup({"kind": kind, "yaw": rng.randf_range(0.0, TAU), "scale": rng.randf_range(0.9, 1.15)})
	plant.position = Vector3(at.x, 0, at.y)
	add_child(plant)
	nodes.append(plant)
	return plant


func _remove(node: Node3D) -> void:
	nodes.erase(node)
	if is_instance_valid(node):
		node.queue_free()


## 在栖息地范围内随机取点；找不到合法位置返回 Vector2.INF。
func _find_spot(habitat: String, rng: RandomNumberGenerator) -> Vector2:
	var areas := _habitat_areas(habitat)
	if areas.is_empty():
		return Vector2.INF
	for attempt in range(40):
		var area: Dictionary = areas[rng.randi_range(0, areas.size() - 1)]
		var at: Vector2
		if area.has("rect"):
			var rect: Rect2 = area["rect"]
			at = Vector2(rng.randf_range(rect.position.x, rect.end.x), rng.randf_range(rect.position.y, rect.end.y))
		else:
			at = (area["center"] as Vector2) + Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * float(area["radius"])
		if _is_valid_spot(at, habitat):
			return at
	return Vector2.INF


func _habitat_areas(habitat: String) -> Array:
	var definition: Dictionary = world.get("definition", {})
	var rect_of := {}
	for entry: Dictionary in definition.get("regions", []):
		rect_of[entry["id"]] = entry["rect"]
	match habitat:
		"forest":
			return _rect_area(rect_of, "forest")
		"orchard":
			return _rect_area(rect_of, "orchard")
		"town":
			return _rect_area(rect_of, "town")
		"lakeside":
			var areas := _rect_area(rect_of, "lake")
			for area: Dictionary in areas:
				area["rect"] = (area["rect"] as Rect2).grow(16.0)
			return areas
		"shore":
			return _rect_area(rect_of, "harbor")
		"mountain":
			var result := _rect_area(rect_of, "mine")
			for area: Dictionary in result:
				area["rect"] = (area["rect"] as Rect2).grow(24.0)
			var waterfall: Vector3 = world.get("landmarks", {}).get("waterfall", Vector3.INF)
			if is_finite(waterfall.x):
				result.append({"center": Vector2(waterfall.x, waterfall.z), "radius": 70.0})
			return result
	return []


func _rect_area(rect_of: Dictionary, id: String) -> Array:
	if not rect_of.has(id):
		return []
	var rect: Rect2 = rect_of[id]
	if rect.size.x <= 1.0 or rect.size.y <= 1.0:
		return []
	return [{"rect": rect}]


func _is_valid_spot(at: Vector2, habitat: String) -> bool:
	if not at.is_finite() or tiles == null:
		return false
	var map = tiles.map
	if not map.contains(at, 0.5) or map.is_water(at, 0.3) or map.on_deck(at, 0.3):
		return false
	if not map.is_walkable(at, 0.4):
		return false
	if tiles.farm.tiles.has(map.key_of(Vector3(at.x, 0, at.y))):
		return false
	for rect: Rect2 in map.pastures:
		if rect.grow(0.9).has_point(at):
			return false
	for entry: Dictionary in world.get("definition", {}).get("regions", []):
		if entry["id"] == "npc_farm" and (entry["rect"] as Rect2).grow(2.0).has_point(at):
			return false
	for road: Dictionary in world.get("definition", {}).get("roads", []):
		var half_width: float = float(road.get("width", 6.0)) * 0.5 + 0.9
		var points: Array = road["points"]
		for index in range(points.size() - 1):
			if Geometry2D.get_closest_point_to_segment(at, points[index], points[index + 1]).distance_to(at) < half_width:
				return false
	match habitat:
		"lakeside":
			if not map.is_water(at, 9.0):
				return false
		"shore":
			if not map.is_water(at, 11.0):
				return false
	for node in nodes:
		if is_instance_valid(node) and Vector2(node.position.x, node.position.z).distance_to(at) < MIN_SPACING:
			return false
	return true


## ---- 存档：只持久化当前活着的采集物；读档后按状态重建并丢弃不合季物种 ----

func to_dict() -> Dictionary:
	var entries: Array = []
	for node in nodes:
		if is_instance_valid(node):
			entries.append({"kind": node.kind, "position": [node.position.x, node.position.z]})
	return {"season": last_season, "nodes": entries}


func apply_state(data: Dictionary, season: String) -> void:
	for node in nodes:
		if is_instance_valid(node):
			node.queue_free()
	nodes.clear()
	clear_focus()
	last_season = season
	for entry: Dictionary in data.get("nodes", []):
		var kind: String = entry.get("kind", "")
		var position: Array = entry.get("position", [])
		if kind not in ForageDB.ORDER or position.size() != 2:
			continue
		if season not in ForageDB.seasons_of(kind):
			continue
		var at := Vector2(float(position[0]), float(position[1]))
		if not at.is_finite():
			continue
		var crowded := false
		for node in nodes:
			if Vector2(node.position.x, node.position.z).distance_to(at) < MIN_SPACING * 0.5:
				crowded = true
				break
		if not crowded:
			_spawn_entry(kind, at)
