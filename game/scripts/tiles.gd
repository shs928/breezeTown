extends Node3D
## 网格土地管理器：领域状态（MapData + FarmState）的 3D 视图层。
## 整张大地图的普通草地都可开垦（建筑、小径、池塘、森林等禁区除外）。
## 按 2 米网格组织；荒地无节点，整地后才创建 tile 视图节点；高亮圈全局共享一个。

const M = preload("res://scripts/art/art_mesh.gd")
const MapData := preload("res://scripts/core/map_data.gd")
const FarmState := preload("res://scripts/domain/farm_state.gd")
const TILE_NODE := preload("res://scripts/tile.gd")

var map: MapData
var farm: FarmState
var views := {}  # Vector2i -> tile.gd 视图节点

var _highlight: MeshInstance3D


func _ready() -> void:
	if map == null:
		map = MapData.new()
	if farm == null:
		farm = FarmState.new()
	_highlight = M.cylinder(self, Vector3.ZERO, 1.22, 1.22, 0.02, "#f5f1dc", "TileHighlight", 36)
	var spot_material: StandardMaterial3D = M.paint("#f7f3de", 0.8).duplicate()
	spot_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	spot_material.albedo_color = Color(1.0, 0.98, 0.88, 0.30)
	_highlight.material_override = spot_material
	_highlight.visible = false


func set_region(half: Vector2, power: int = 6) -> void:
	map.bounds_half = half
	map.bounds_power = power


func block_rect(rect: Rect2) -> void:
	map.blocked_rects.append(rect)


func block_circle(at: Vector2, radius: float) -> void:
	map.blocked_circles.append({"position": at, "radius": radius})


var blocked_paths: Array:
	get: return map.blocked_paths
	set(value): map.blocked_paths = value


func occupy_resource(id: int, at: Vector2, radius: float) -> void:
	map.occupy_resource(id, at, radius)


func release_resource(id: int) -> void:
	map.release_resource(id)


func key_of(world: Vector3) -> Vector2i:
	return map.key_of(world)


func center_of(key: Vector2i) -> Vector3:
	return map.center_of(key)


func is_open(key: Vector2i) -> bool:
	return map.is_open(key)


func is_clear_area(at: Vector2, radius: float) -> bool:
	## 刷新与种树按完整占地检测，包含已收获但仍保留的耕地。
	if map.is_water(at, radius + 0.3):
		return false
	for deck: Dictionary in map.bridges + map.docks:
		if (deck["rect"] as Rect2).grow(radius).has_point(at):
			return false
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var point: Vector2 = at + corner * (radius + 0.5)
		if pow(absf(point.x) / map.bounds_half.x, map.bounds_power) + pow(absf(point.y) / map.bounds_half.y, map.bounds_power) >= 1.0:
			return false
	for rect in map.blocked_rects:
		if at.distance_to(at.clamp(rect.position, rect.end)) <= radius:
			return false
	for entry: Dictionary in map.blocked_circles + map.resource_blocks.values():
		if at.distance_to(entry["position"]) <= radius + entry["radius"]:
			return false
	for path: Dictionary in map.blocked_paths:
		if Geometry2D.get_closest_point_to_segment(at, path["from"], path["to"]).distance_to(at) <= path["width"] * 0.5 + radius:
			return false
	for key: Vector2i in farm.tiles:
		var center := Vector2(key) * MapData.GRID
		if at.distance_to(at.clamp(center - Vector2.ONE, center + Vector2.ONE)) <= radius:
			return false
	return true


func has_tile(key: Vector2i) -> bool:
	return farm.has_tile(key)


func node(key: Vector2i) -> Node3D:
	return views.get(key)


func nearest_key(from: Vector3, max_range: float, tool: String = "hoe") -> Variant:
	var base := key_of(from)
	var best: Variant = null
	var best_distance := max_range
	for dx in range(-2, 3):
		for dy in range(-2, 3):
			var key := base + Vector2i(dx, dy)
			var distance := from.distance_to(center_of(key))
			if distance < best_distance and is_open(key) and accepts_tool(key, tool):
				best_distance = distance
				best = key
	return best


func accepts_tool(key: Vector2i, tool: String) -> bool:
	var data: FarmState.FarmTileData = farm.data_of(key)
	match tool:
		"hoe":
			return data == null
		"seed":
			return data != null and data.state == "tilled"
		"can":
			return data != null and data.state == "planted" and not data.watered and not data.is_mature()
		"hand":
			return data != null and data.is_mature()
	return false


func till(key: Vector2i) -> bool:
	if not is_open(key):
		return false
	var data: FarmState.FarmTileData = farm.till(key)
	if data == null:
		return false
	_spawn_view(key, data)
	return true


func plant(key: Vector2i, kind: String) -> bool:
	if not farm.plant(key, kind):
		return false
	_sync_view(key)
	return true


func water(key: Vector2i) -> bool:
	if not farm.water(key):
		return false
	_sync_view(key)
	return true


func harvest(key: Vector2i) -> String:
	var kind: String = farm.harvest(key)
	if kind != "":
		_sync_view(key)
	return kind


func water_all() -> int:
	## POLISH-01：雨天自动浇灌——所有可浇的已种植耕地，返回浇灌格数。
	var count := 0
	for key: Vector2i in farm.tiles:
		if farm.water(key):
			_sync_view(key)
			count += 1
	return count


func rollover() -> void:
	farm.rollover()
	for key: Vector2i in farm.tiles:
		_sync_view(key)


func restore_views() -> void:
	## 存档恢复：为领域状态里已存在的每块耕地补建视图节点。
	for key: Vector2i in views.keys():
		if not farm.has_tile(key):
			remove_child(views[key])
			views[key].queue_free()
			views.erase(key)
	for key: Vector2i in farm.tiles:
		if views.has(key):
			views[key].setup(farm.tiles[key], farm)
			views[key].sync_visual()
		else:
			_spawn_view(key, farm.tiles[key])


func _spawn_view(key: Vector2i, data: FarmState.FarmTileData) -> void:
	var view: Node3D = TILE_NODE.new()
	view.name = "Tile_%d_%d" % [key.x, key.y]
	view.position = center_of(key)
	add_child(view)
	view.setup(data, farm)
	view.sync_visual()
	views[key] = view


func _sync_view(key: Vector2i) -> void:
	if views.has(key):
		views[key].sync_visual()


func set_highlight(world_pos: Variant, available: bool = true) -> void:
	if world_pos == null:
		_highlight.visible = false
	else:
		_highlight.visible = true
		(_highlight.material_override as StandardMaterial3D).albedo_color = Color(1.0, 0.98, 0.88, 0.30) if available else Color(0.90, 0.32, 0.22, 0.38)
		_highlight.position = world_pos + Vector3(0, 0.10, 0)
