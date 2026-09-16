extends Node3D
## 一格可开垦土地的 3D 视图（2 米网格）：绑定 FarmTileData 领域状态并渲染土垄、
## 作物模型与成熟光环。全部状态读写都经由 farm 领域对象，本节点不做数据裁决。

const M = preload("res://scripts/art/art_mesh.gd")
const CropDB = preload("res://scripts/data/crop_db.gd")
const StaticGeometry := preload("res://scripts/art/static_geometry.gd")

var data  # FarmState.FarmTileData
var farm  # FarmState

var _soil: Node3D
var _ridges: Array[MeshInstance3D] = []
var _ridge_dry: Array[StandardMaterial3D] = []
var _ridge_wet: Array[StandardMaterial3D] = []
var _crop_root: Node3D
var _ring: MeshInstance3D
var _rng := RandomNumberGenerator.new()


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
	_refresh_crop()
	_apply_moisture()


func _build_soil() -> void:
	_rng.seed = hash(name) + int(global_position.x * 13.0 + global_position.z * 7.0)
	_soil = Node3D.new()
	_soil.name = "Soil"
	add_child(_soil)
	M.box(_soil, Vector3(0, 0.045, 0), Vector3(1.96, 0.09, 1.96), "#765335", "SoilPatch", 0.07)
	for row in range(3):
		var ridge: MeshInstance3D = M.ellipsoid(_soil, Vector3(0, 0.085, (row - 1) * 0.52), Vector3(0.82, 0.062, 0.24), "#5e3d29" if row % 2 == 0 else "#6b482e", "SoilRidge", 16, 7)
		_ridges.append(ridge)
		_ridge_dry.append(ridge.material_override)
	for i in range(3):
		var pebble := M.ellipsoid(_soil, Vector3(_rng.randf_range(-0.8, 0.8), 0.02, _rng.randf_range(-0.8, 0.8)), Vector3(0.055, 0.025, 0.05), "#c5aa83", "SoilPebble", 8, 4)
		pebble.rotation.y = _rng.randf_range(0, TAU)


func _refresh_crop() -> void:
	if _crop_root != null and is_instance_valid(_crop_root):
		_crop_root.free()
	_crop_root = null
	if _ring != null:
		_ring.visible = false
	if data != null and data.state == "planted":
		var landscape := preload("res://scripts/art/landscape_models.gd")
		_crop_root = Node3D.new()
		var growth: float = lerpf(0.40, 1.0, clampf(float(data.stage) / float(CropDB.grow_days(data.crop)), 0.0, 1.0))
		var offsets:Array = [-0.60,0.0,0.60] if data.crop == "wheat" else [-0.44,0.44]
		for x in offsets:
			for z in offsets:
				var plant_model: Node3D = landscape.crop(data.crop, _rng.randi_range(0,99))
				plant_model.position = Vector3(x,0.08,z)
				plant_model.rotation.y = _rng.randf_range(0,TAU)
				plant_model.scale = Vector3.ONE * growth * (1.05 if data.crop == "wheat" else 1.12)
				_crop_root.add_child(plant_model)
		StaticGeometry.bake(_crop_root)
		add_child(_crop_root)
		if _ring == null:
			_ring = M.torus(self, Vector3(0, 0.10, 0), 0.16, 0.007, "#e8bf62", "MatureRing")
			_ring.scale = Vector3(1.0, 0.45, 1.0)
			var glow: StandardMaterial3D = M.paint("#ffcf6e", 0.55).duplicate()
			glow.emission_enabled = true
			glow.emission = Color("#ffc679")
			glow.emission_energy_multiplier = 0.25
			_ring.material_override = glow
	if _ring != null:
		_ring.visible = is_mature()


func _apply_moisture() -> void:
	if _soil == null:
		return
	var wet: bool = data != null and data.watered
	for i in range(_ridges.size()):
		if wet and _ridge_wet.size() <= i:
			var damp: StandardMaterial3D = (_ridge_dry[i] as StandardMaterial3D).duplicate()
			damp.albedo_color = damp.albedo_color.darkened(0.32)
			_ridge_wet.append(damp)
		_ridges[i].material_override = _ridge_wet[i] if wet else _ridge_dry[i]


func _process(delta: float) -> void:
	if _ring != null and _ring.visible:
		_ring.rotate_y(delta * 1.1)
		_ring.position.y = 0.105
