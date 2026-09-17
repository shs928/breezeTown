extends Node3D
## 一格可开垦土地的 3D 视图（2 米网格）：绑定 FarmTileData 领域状态并渲染土垄、
## 作物模型与成熟光环。全部状态读写都经由 farm 领域对象，本节点不做数据裁决。
## PERF-01：土壤/木框/作物网格按种类静态缓存，作物用 MultiMesh 实例化——
## 每格不再各自构建并烘焙几十个网格（此前每格约 0.45 秒、28 个绘制）。

const M = preload("res://scripts/art/art_mesh.gd")
const CropDB = preload("res://scripts/data/crop_db.gd")
const StaticGeometry := preload("res://scripts/art/static_geometry.gd")
const Landscape := preload("res://scripts/art/landscape_models.gd")

var data  # FarmState.FarmTileData
var farm  # FarmState

var _soil: Node3D
var _soil_parts: Array[MeshInstance3D] = []
var _edges: Array[MeshInstance3D] = []
var _crop_root: Node3D
var _ring: MeshInstance3D
var _rng := RandomNumberGenerator.new()

static var _crop_meshes := {}
static var _soil_mesh_cache := {}
static var _board_mesh: Mesh
static var _ring_mesh: Mesh
static var _ring_material: StandardMaterial3D


func setup(tile_data, farm_state) -> void:
	data = tile_data
	farm = farm_state


## ---- 领域状态透传（供既有调用方与测试读取） ----

var state: String:
	get: return data.state if data != null else "wild"
var crop_kind: String:
	get: return data.crop if data != null else ""
var stage: int:
	get: return data.stage if data != null else 0
var watered: bool:
	get: return data.watered if data != null else false


func is_mature() -> bool:
	return data != null and data.is_mature()


## ---- 领域操作入口：转给 FarmState 裁决，再同步视图 ----

func till() -> bool:
	if data == null or farm == null:
		return false
	if data.state != "wild":
		return false
	data.state = "tilled"
	_build_soil()
	return true


func plant(kind: String) -> bool:
	if farm == null or data == null:
		return false
	if not farm.plant_data(data, key(), kind):
		return false
	sync_visual()
	return true


func water() -> bool:
	if farm == null or data == null:
		return false
	if not farm.water_data(data, key()):
		return false
	sync_visual()
	return true


func harvest() -> String:
	if farm == null or data == null:
		return ""
	var kind: String = farm.harvest_data(data, key())
	if kind != "":
		sync_visual()
	return kind


func on_day_rollover() -> void:
	if farm == null or data == null:
		return
	farm.rollover_data(data, key())
	sync_visual()


func debug_set_stage(value: int) -> void:
	if data == null:
		return
	var max_stage := CropDB.grow_days(data.crop) if data.state == "planted" else 1
	data.stage = clampi(value, 0, maxi(1, max_stage))
	sync_visual()


func key() -> Vector2i:
	return Vector2i(roundi(position.x / 2.0), roundi(position.z / 2.0))


## ---- 视觉同步 ----

func sync_visual() -> void:
	if _soil == null and data != null and data.state != "wild":
		_build_soil()
	if _soil != null and data != null and data.state != "wild":
		_refresh_timber_edges()
	_refresh_crop()
	_apply_moisture()


const BAKE_CENTER := Vector3(12, 0, 12)

static func _bake_model(model: Node3D) -> Array:
	# 把多部件模型烘成按材质分组的少量网格；材质随批次一起返回，结果全局共享。
	# 模型包进 (12,0,12) 容器确保所有部件落进同一 24 米烘焙格；烘焙后把顶点平移
	# 回原点——否则实例的随机朝向会把这个偏移绕原点甩出十几米。
	var container := Node3D.new()
	model.position = BAKE_CENTER
	container.add_child(model)
	StaticGeometry.bake(container)
	var result: Array = []
	var baked: Node = container.get_node_or_null("StaticGeometry")
	if baked != null:
		for child in baked.get_children():
			var batch := child as MeshInstance3D
			var source := batch.mesh as ArrayMesh
			var shifted := ArrayMesh.new()
			for surface in range(source.get_surface_count()):
				var arrays := source.surface_get_arrays(surface)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				for i in range(vertices.size()):
					vertices[i] -= BAKE_CENTER
				arrays[Mesh.ARRAY_VERTEX] = vertices
				shifted.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			result.append({"mesh": shifted, "material": batch.material_override})
	return result


static func _crop_mesh(kind: String) -> Array:
	if not _crop_meshes.has(kind):
		_crop_meshes[kind] = _bake_model(Landscape.crop(kind, 7))
	return _crop_meshes[kind]


static func _soil_mesh(wet: bool) -> Array:
	var slot: String = "wet" if wet else "dry"
	if not _soil_mesh_cache.has(slot):
		var root := Node3D.new()
		# 湿土用暗化色号生成独立缓存材质，绝不改动共享材质。
		var shade := Color(0.68, 0.68, 0.68) if wet else Color.WHITE
		var patch_hex := (Color("#7e5a3b") * shade).to_html(false)
		M.box(root, Vector3(0, 0.045, 0), Vector3(1.96, 0.09, 1.96), patch_hex, "SoilPatch", 0.07)
		for row in range(3):
			var hex := (Color("#654331" if row % 2 == 0 else "#735035") * shade).to_html(false)
			M.ellipsoid(root, Vector3(0, 0.085, (row - 1) * 0.52), Vector3(0.82, 0.062, 0.24), hex, "SoilRidge", 16, 7)
		var pebble_hex := (Color("#c5aa83") * shade).to_html(false)
		for i in range(3):
			var pebble_at: Vector3 = [Vector3(-0.55, 0.02, -0.42), Vector3(0.48, 0.02, 0.10), Vector3(-0.10, 0.02, 0.55)][i]
			var pebble: MeshInstance3D = M.ellipsoid(root, pebble_at, Vector3(0.055, 0.025, 0.05), pebble_hex, "SoilPebble", 8, 4)
			pebble.rotation.y = 0.7 * i
		_soil_mesh_cache[slot] = _bake_model(root)
	return _soil_mesh_cache[slot]


static func _timber_mesh() -> Mesh:
	if _board_mesh == null:
		var shape := BoxMesh.new()
		shape.size = Vector3(0.09, 0.19, 1.98)
		_board_mesh = shape
	return _board_mesh


func _build_soil() -> void:
	_rng.seed = hash(name) + int(global_position.x * 13.0 + global_position.z * 7.0)
	_soil = Node3D.new()
	_soil.name = "Soil"
	add_child(_soil)
	for entry in _soil_mesh(false):
		var part := MeshInstance3D.new()
		part.mesh = entry["mesh"]
		part.material_override = entry["material"]
		_soil.add_child(part)
		_soil_parts.append(part)
	for direction in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var board := MeshInstance3D.new()
		board.name = "BedTimber"
		board.mesh = _timber_mesh()
		board.material_override = M.paint("#8a6a44" if direction.x + direction.y < 0 else "#7d5f3c")
		board.position = Vector3(direction.x * 1.005, 0.10, direction.y * 1.005)
		# 网格长轴沿 Z：东西边缘板保持 Z 向，南北边缘板转 90° 使长轴沿 X。
		board.rotation.y = 0.0 if direction.x != 0 else PI * 0.5
		_soil.add_child(board)
		_edges.append(board)


func _refresh_timber_edges() -> void:
	var directions := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for i in range(_edges.size()):
		_edges[i].visible = farm == null or not farm.has_tile(key() + directions[i])


func _refresh_crop() -> void:
	if _crop_root != null and is_instance_valid(_crop_root):
		_crop_root.free()
	_crop_root = null
	if _ring != null:
		_ring.visible = false
	if data != null and data.state == "planted":
		_crop_root = Node3D.new()
		_crop_root.name = "Crop"
		var growth: float = lerpf(0.40, 1.0, clampf(float(data.stage) / float(CropDB.grow_days(data.crop)), 0.0, 1.0))
		var offsets: Array = [-0.60, 0.0, 0.60] if data.crop == "wheat" else [-0.44, 0.44]
		for entry: Dictionary in _crop_mesh(data.crop):
			var multi := MultiMesh.new()
			multi.transform_format = MultiMesh.TRANSFORM_3D
			multi.mesh = entry["mesh"]
			multi.instance_count = offsets.size() * offsets.size()
			var index := 0
			for x in offsets:
				for z in offsets:
					# 轻微错位与高矮差，避免整片田读成复印章。
					var basis := Basis(Vector3.UP, _rng.randf_range(0, TAU))
					var variance: float = _rng.randf_range(0.9, 1.12)
					var stretch: float = growth * variance * (1.05 if data.crop == "wheat" else 1.12)
					basis = basis.scaled(Vector3(stretch, stretch * _rng.randf_range(0.92, 1.18), stretch))
					multi.set_instance_transform(index, Transform3D(basis, Vector3(x + _rng.randf_range(-0.13, 0.13), 0.08, z + _rng.randf_range(-0.13, 0.13))))
					index += 1
			var instance := MultiMeshInstance3D.new()
			instance.multimesh = multi
			instance.material_override = entry["material"]
			_crop_root.add_child(instance)
		add_child(_crop_root)
		if _ring_mesh == null:
			var ring_shape := TorusMesh.new()
			ring_shape.inner_radius = 0.16 - 0.007
			ring_shape.outer_radius = 0.16 + 0.007
			ring_shape.rings = 24
			ring_shape.ring_segments = 8
			_ring_mesh = ring_shape
			_ring_material = M.paint("#ffcf6e", 0.55).duplicate()
			_ring_material.emission_enabled = true
			_ring_material.emission = Color("#ffc679")
			_ring_material.emission_energy_multiplier = 0.25
		if _ring == null:
			_ring = MeshInstance3D.new()
			_ring.name = "MatureRing"
			_ring.mesh = _ring_mesh
			_ring.material_override = _ring_material
			_ring.scale = Vector3(1.0, 0.45, 1.0)
			add_child(_ring)
	if _ring != null:
		_ring.visible = is_mature()


func _apply_moisture() -> void:
	if _soil_parts.is_empty():
		return
	var wet: bool = data != null and data.watered
	var entries: Array = _soil_mesh(wet)
	for i in range(mini(_soil_parts.size(), entries.size())):
		_soil_parts[i].mesh = entries[i]["mesh"]
		_soil_parts[i].material_override = entries[i]["material"]


func _process(delta: float) -> void:
	if _ring != null and _ring.visible:
		_ring.rotate_y(delta * 1.1)
		_ring.position.y = 0.105
