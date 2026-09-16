extends Node3D
## 一层矿洞的持久运行状态。离层时整棵树停用，回访不会重刷矿石与奖励。

signal notice(text: String)
signal loot_collected(kind: String, count: int)
signal player_attacked(amount: int, source: Vector3)
signal changed

const Layout = preload("res://scripts/mine_layout.gd")
const Models = preload("res://scripts/art/mine_models.gd")
const Rock = preload("res://scripts/mine_rock.gd")
const Monster = preload("res://scripts/mine_monster.gd")
const Drop = preload("res://scripts/mine_drop.gd")
const Feedback = preload("res://scripts/combat_feedback.gd")

var depth := 1
var player: CharacterBody3D
var layout: Dictionary = {}
var rocks: Array[Node3D] = []
var monsters: Array[CharacterBody3D] = []
var drops: Array[Node3D] = []
var descent_open := false
var chest_opened := false
var camp_used := false
var paused := false
var _grid: AStarGrid2D
var _down_ladder: Node3D
var _chest: Node3D
var _focus_ring: MeshInstance3D


func _ready() -> void:
	layout = Layout.create(depth)
	add_child(Models.shell(layout))
	_grid = AStarGrid2D.new()
	_grid.region = Rect2i(Vector2i.ZERO, Layout.GRID)
	_grid.cell_size = Vector2.ONE * Layout.CELL
	_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_grid.update()
	_build_collision()
	for entry: Dictionary in layout["rocks"]:
		var rock := Rock.new()
		rock.name = "Rock_%d_%d" % [entry["cell"].x, entry["cell"].y]
		rock.cell = entry["cell"]
		rock.kind = entry["kind"]
		rock.seal = entry["seal"]
		rock.depth = depth
		rock.position = Layout.center(rock.cell)
		add_child(rock)
		rocks.append(rock)
		_grid.set_point_solid(rock.cell)
		rock.struck.connect(func(amount: int, at: Vector3): Feedback.number(self, at, str(amount), Color("#e1d5b6")))
		rock.broken.connect(_on_rock_broken)
	for entry: Dictionary in layout["monsters"]:
		var monster := Monster.new()
		monster.kind = entry["kind"]
		monster.depth = depth
		monster.player = player
		monster.floor_world = self
		monster.position = Layout.center(entry["cell"])
		add_child(monster)
		monsters.append(monster)
		monster.struck.connect(func(amount: int, at: Vector3): Feedback.number(self, at, str(amount)))
		monster.defeated.connect(_on_monster_defeated)
		monster.attacked.connect(func(amount: int, source: Vector3): player_attacked.emit(amount, source))
	var up := Models.ladder(false, depth)
	up.position = up_position()
	add_child(up)
	if depth < Layout.FLOOR_COUNT:
		_down_ladder = Models.ladder(true, depth)
		_down_ladder.position = down_position()
		add_child(_down_ladder)
		descent_open = depth == 5
		_down_ladder.visible = descent_open
	else:
		_chest = Models.chest()
		_chest.position = down_position()
		add_child(_chest)
	if depth in Layout.CHECKPOINTS:
		var lift := Models.hoist()
		lift.position = lift_position()
		add_child(lift)
	if depth == 5:
		var camp := Models.camp()
		camp.position = Layout.center(layout["camp"])
		add_child(camp)
	_focus_ring = preload("res://scripts/art/art_mesh.gd").torus(self, Vector3.ZERO, 0.88, 0.035, "#edcf82", "MineFocus")
	_focus_ring.material_override = Models.glow_material("#eace88", 0.65)
	_focus_ring.visible = false


func spawn_position() -> Vector3:
	return Layout.center(layout["spawn"])


func up_position() -> Vector3:
	return Layout.center(layout["up"])


func down_position() -> Vector3:
	return Layout.center(layout["down"])


func lift_position() -> Vector3:
	return Layout.center(layout["lift"])


func target_at(at: Vector3, tool: String) -> Dictionary:
	_focus_ring.hide()
	var result := {}
	# 工具匹配的近距离目标优先于梯子，防止战斗中误触换层。
	var best := 2.4 if tool == "sword" else 2.25
	if tool in ["sword", "pickaxe"]:
		for monster in monsters:
			if not is_instance_valid(monster) or monster.dead:
				continue
			var distance := at.distance_to(monster.global_position)
			if distance < best and clear_line(at, monster.global_position):
				best = distance
				result = {"kind": "monster", "node": monster, "hint": "E / 空格 挥击 %s · %d/%d" % [monster.label(), monster.health, monster.max_health]}
	if tool == "pickaxe":
		for rock in rocks:
			if not is_instance_valid(rock) or rock.depleted:
				continue
			var distance := at.distance_to(rock.global_position)
			if distance < best and clear_line(at, rock.global_position, rock):
				best = distance
				result = {"kind": "ore", "node": rock, "hint": "E / 空格 开采" + rock.label()}
	if not result.is_empty():
		_focus_ring.position = result["node"].position + Vector3(0, 0.035, 0)
		_focus_ring.show()
		return result
	if at.distance_to(up_position()) < 2.05:
		return {"kind": "mine_up", "hint": "E 返回地表" if depth == 1 else "E 返回第 %d 层" % (depth - 1)}
	if depth in Layout.CHECKPOINTS and at.distance_to(lift_position()) < 2.3:
		return {"kind": "mine_lift", "hint": "E 使用升降机 · 返回地表 / 已到达的营地"}
	if at.distance_to(down_position()) < 2.3:
		if depth == Layout.FLOOR_COUNT:
			return {"kind": "mine_chest", "hint": "宝箱已领取 · 升降机可返回小镇" if chest_opened else ("E 打开地心宝箱" if monsters.is_empty() else "击败晶室中的怪物，解锁地心宝箱")}
		if descent_open:
			return {"kind": "mine_down", "hint": "E 进入第 %d 层" % (depth + 1)}
		return {"kind": "mine_sealed", "hint": "6 装备镐子 · 挖开裂隙岩石，寻找向下的梯子"}
	if depth == 5 and at.distance_to(Layout.center(layout["camp"])) < 2.2:
		return {"kind": "mine_camp", "hint": "营地已休整过" if camp_used else "E 在营地休整 · 恢复全部生命并补充口粮"}
	for rock in rocks:
		if is_instance_valid(rock) and at.distance_to(rock.global_position) < 2.3:
			return {"kind": "mine_sealed", "hint": "6 换镐子开采" + rock.label()}
	return {"kind": "mine_idle", "hint": "6 镐子 · 7 短剑 · E 交互 · 空格 / 左键挥动 · Q 口粮"}


func swing(tool: String, origin: Vector3, facing: Vector3) -> int:
	if paused or tool not in ["pickaxe", "sword"]:
		return 0
	var hit_count := 0
	var reach := 2.45 if tool == "sword" else 2.3
	var cone := 0.32 if tool == "sword" else 0.57
	if tool == "sword":
		Feedback.slash(self, origin, facing)
	for monster in monsters.duplicate():
		if not is_instance_valid(monster) or monster.dead:
			continue
		var delta: Vector3 = monster.global_position - origin
		if delta.length() <= reach and (delta.length() < 0.30 or facing.dot(delta.normalized()) >= cone) and clear_line(origin, monster.global_position):
			if monster.hit(22 if tool == "sword" else 6, origin) > 0:
				hit_count += 1
				Feedback.burst(self, monster.position + Vector3(0, 0.8, 0), "#e4d5a0", 5)
	if tool == "pickaxe":
		var closest: Node3D = null
		var best := reach + 0.01
		for rock in rocks:
			if not is_instance_valid(rock) or rock.depleted:
				continue
			var delta: Vector3 = rock.global_position - origin
			if delta.length() < best and (delta.length() < 0.3 or facing.dot(delta.normalized()) >= cone) and clear_line(origin, rock.global_position, rock):
				closest = rock
				best = delta.length()
		if closest != null and closest.hit(18) > 0:
			hit_count += 1
	return hit_count


func clear_line(from: Vector3, to: Vector3, target: CollisionObject3D = null) -> bool:
	var ray := PhysicsRayQueryParameters3D.create(from + Vector3(0, 0.65, 0), to + Vector3(0, 0.65, 0), 1)
	if target != null:
		ray.exclude = [target.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(ray).is_empty()


func next_waypoint(from: Vector3, to: Vector3) -> Vector3:
	var start := Layout.key(from).clamp(Vector2i.ZERO, Layout.GRID - Vector2i.ONE)
	var finish := Layout.key(to).clamp(Vector2i.ZERO, Layout.GRID - Vector2i.ONE)
	if _grid.is_point_solid(start) or _grid.is_point_solid(finish):
		return from
	var route := _grid.get_id_path(start, finish)
	if route.size() > 1:
		return Layout.center(route[1])
	return to if start == finish else from


func open_chest() -> bool:
	if depth != 10 or chest_opened or not monsters.is_empty():
		return false
	chest_opened = true
	remove_child(_chest)
	_chest.queue_free()
	_chest = Models.chest(true)
	_chest.position = down_position()
	add_child(_chest)
	loot_collected.emit("crystal", 12)
	loot_collected.emit("iron", 8)
	changed.emit()
	return true


func navigation() -> Dictionary:
	var ore_positions: Array[Vector2] = []
	var enemy_positions: Array[Vector2] = []
	for rock in rocks:
		if is_instance_valid(rock) and not rock.depleted:
			ore_positions.append(Vector2(rock.position.x, rock.position.z))
	for monster in monsters:
		if is_instance_valid(monster) and not monster.dead:
			enemy_positions.append(Vector2(monster.position.x, monster.position.z))
	return {"kind": "mine", "depth": depth, "title": layout["title"], "half": Vector2(Layout.GRID) * Layout.CELL * 0.5,
		"cells": layout["open"].keys(), "up": up_position(), "down": down_position(), "lift": lift_position(),
		"checkpoint": depth in Layout.CHECKPOINTS, "descent_open": descent_open, "ores": ore_positions, "enemies": enemy_positions}


func _on_rock_broken(rock: Node3D) -> void:
	rocks.erase(rock)
	_grid.set_point_solid(rock.cell, false)
	_spawn_drop(rock.kind, 2 if rock.kind != "stone" else 1, rock.position)
	if rock.seal:
		descent_open = true
		_down_ladder.show()
		notice.emit("发现向下的梯子！按 E 进入第 %d 层" % (depth + 1))
	changed.emit()


func _on_monster_defeated(monster: Node3D) -> void:
	monsters.erase(monster)
	_spawn_drop("crystal" if monster.kind == "guardian" else ("coal" if monster.kind == "bat" else "slime"), 5 if monster.kind == "guardian" else 1, monster.position)
	if depth == 10 and monsters.is_empty():
		notice.emit("晶室安静下来了，地心宝箱已解锁")
	changed.emit()


func _spawn_drop(kind: String, amount: int, at: Vector3) -> void:
	var drop := Drop.new()
	drop.kind = kind
	drop.amount = amount
	drop.player = player
	drop.position = at
	add_child(drop)
	drops.append(drop)
	drop.collected.connect(func(item: Node3D):
		drops.erase(item)
		loot_collected.emit(item.kind, item.amount)
	)


func _build_collision() -> void:
	for z in range(Layout.GRID.y):
		var start := -1
		for x in range(Layout.GRID.x + 1):
			var solid: bool = x < Layout.GRID.x and not layout["open"].has(Vector2i(x, z))
			if x < Layout.GRID.x:
				_grid.set_point_solid(Vector2i(x, z), solid)
			if solid and start < 0:
				start = x
			elif not solid and start >= 0:
				var body := StaticBody3D.new()
				body.name = "CaveWall"
				body.collision_layer = 1
				body.collision_mask = 0
				body.position = (Layout.center(Vector2i(start, z)) + Layout.center(Vector2i(x - 1, z))) * 0.5 + Vector3(0, 2, 0)
				var shape := CollisionShape3D.new()
				var box := BoxShape3D.new()
				box.size = Vector3((x - start) * Layout.CELL, 4, Layout.CELL)
				shape.shape = box
				body.add_child(shape)
				add_child(body)
				start = -1
	for cell: Vector2i in layout["decorations"]:
		_add_prop_collision(Layout.center(cell) + Vector3(0, 0.4, 0), Vector3(0.82, 0.8, 0.82))
		_grid.set_point_solid(cell)
	for z in [16, 11, 6]:
		for side in [-1, 1]:
			_add_prop_collision(Layout.center(Vector2i(12, z)) + Vector3(side * 2.8, 1.45, 0), Vector3(0.32, 2.9, 0.38))


func _add_prop_collision(at: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = "MineProp"
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = at
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	add_child(body)
