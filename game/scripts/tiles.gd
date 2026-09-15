extends Node3D
## 网格土地管理器：整张大地图的普通草地都可开垦（建筑、小径、池塘、森林等禁区除外）。
## 按 2 米网格组织；荒地无节点，整地后才创建 tile 节点；高亮圈全局共享一个。

const M = preload("res://scripts/art/art_mesh.gd")
const TILE := 2.0
const TILE_NODE := preload("res://scripts/tile.gd")

var region_half := Vector2(44.0, 34.0)
var blocked_rects: Array[Rect2] = []
var blocked_circles: Array = []  # {"position": Vector2, "radius": float}
var tiles := {}  # Vector2i -> tile.gd

var _highlight: MeshInstance3D


func _ready() -> void:
	_highlight = M.cylinder(self, Vector3.ZERO, 1.22, 1.22, 0.02, "#f5f1dc", "TileHighlight", 36)
	var spot_material: StandardMaterial3D = M.paint("#f7f3de", 0.8).duplicate()
	spot_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	spot_material.albedo_color = Color(1.0, 0.98, 0.88, 0.30)
	_highlight.material_override = spot_material
	_highlight.visible = false


func set_region(half: Vector2) -> void:
	region_half = half


func block_rect(rect: Rect2) -> void:
	blocked_rects.append(rect)


func block_circle(at: Vector2, radius: float) -> void:
	blocked_circles.append({"position": at, "radius": radius})


func key_of(world: Vector3) -> Vector2i:
	return Vector2i(roundi(world.x / TILE), roundi(world.z / TILE))


func center_of(key: Vector2i) -> Vector3:
	return Vector3(key.x * TILE, 0, key.y * TILE)


func is_open(key: Vector2i) -> bool:
	var center := center_of(key)
	if absf(center.x) > region_half.x - 1.2 or absf(center.z) > region_half.y - 1.2:
		return false
	var flat := Vector2(center.x, center.z)
	for rect in blocked_rects:
		if rect.has_point(flat):
			return false
	for entry in blocked_circles:
		if flat.distance_to(entry["position"]) < entry["radius"]:
			return false
	return true


func has_tile(key: Vector2i) -> bool:
	return tiles.has(key)


func node(key: Vector2i) -> Node3D:
	return tiles.get(key)


func nearest_key(from: Vector3, max_range: float) -> Variant:
	var base := key_of(from)
	var best: Variant = null
	var best_distance := max_range
	for dx in range(-2, 3):
		for dy in range(-2, 3):
			var key := base + Vector2i(dx, dy)
			var distance := from.distance_to(center_of(key))
			if distance < best_distance and is_open(key):
				best_distance = distance
				best = key
	return best


func till(key: Vector2i) -> bool:
	if tiles.has(key) or not is_open(key):
		return false
	var tile: Node3D = TILE_NODE.new()
	tile.name = "Tile_%d_%d" % [key.x, key.y]
	tile.position = center_of(key)
	add_child(tile)
	tile.till()
	tiles[key] = tile
	return true


func plant(key: Vector2i, kind: String) -> bool:
	if not tiles.has(key):
		return false
	return tiles[key].plant(kind)


func water(key: Vector2i) -> bool:
	if not tiles.has(key):
		return false
	return tiles[key].water()


func harvest(key: Vector2i) -> String:
	if not tiles.has(key):
		return ""
	return tiles[key].harvest()


func rollover() -> void:
	for tile in tiles.values():
		tile.on_day_rollover()


func set_highlight(world_pos: Variant) -> void:
	if world_pos == null:
		_highlight.visible = false
	else:
		_highlight.visible = true
		_highlight.position = world_pos + Vector3(0, 0.10, 0)
