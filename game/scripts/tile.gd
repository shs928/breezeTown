extends Node3D
## 一格可开垦土地（2 米网格）：荒地 → 整地 → 播种 → 浇水 → 生长 → 收获。
## 荒地没有节点；整地时才由 tiles 管理器创建本节点并生成土垄视觉。

const M = preload("res://scripts/art/art_mesh.gd")
const GameState := preload("res://scripts/game_state.gd")

var state := "wild"  # wild | tilled | planted
var crop_kind := ""
var stage := 0
var watered := false

var _soil: Node3D
var _ridges: Array[MeshInstance3D] = []
var _ridge_dry: Array[StandardMaterial3D] = []
var _ridge_wet: Array[StandardMaterial3D] = []
var _crop_root: Node3D
var _ring: MeshInstance3D
var _rng := RandomNumberGenerator.new()


func till() -> bool:
	if state != "wild":
		return false
	state = "tilled"
	_build_soil()
	return true


func _build_soil() -> void:
	_rng.seed = hash(name) + int(global_position.x * 13.0 + global_position.z * 7.0)
	_soil = Node3D.new()
	_soil.name = "Soil"
	add_child(_soil)
	M.box(_soil, Vector3(0, 0.045, 0), Vector3(1.86, 0.09, 1.86), "#9e7954", "SoilPatch", 0.07)
	for row in range(3):
		var ridge: MeshInstance3D = M.ellipsoid(_soil, Vector3(0, 0.085, (row - 1) * 0.52), Vector3(0.82, 0.062, 0.24), "#8b6748" if row % 2 == 0 else "#926d4c", "SoilRidge", 16, 7)
		_ridges.append(ridge)
		_ridge_dry.append(ridge.material_override)
	for i in range(3):
		var pebble := M.ellipsoid(_soil, Vector3(_rng.randf_range(-0.8, 0.8), 0.02, _rng.randf_range(-0.8, 0.8)), Vector3(0.055, 0.025, 0.05), "#c5aa83", "SoilPebble", 8, 4)
		pebble.rotation.y = _rng.randf_range(0, TAU)


func plant(kind: String) -> bool:
	if state != "tilled":
		return false
	state = "planted"
	crop_kind = kind
	stage = 0
	watered = false
	_refresh_crop()
	return true


func water() -> bool:
	if state != "planted" or watered or is_mature():
		return false
	watered = true
	_apply_moisture()
	return true


func is_mature() -> bool:
	return state == "planted" and stage >= GameState.crop_field(crop_kind, "grow_days")


func harvest() -> String:
	if not is_mature():
		return ""
	var kind := crop_kind
	state = "tilled"
	crop_kind = ""
	stage = 0
	watered = false
	_refresh_crop()
	_apply_moisture()
	return kind


func on_day_rollover() -> void:
	if state == "planted" and watered and not is_mature():
		stage += 1
	watered = false
	_apply_moisture()


func debug_set_stage(value: int) -> void:
	var max_stage := GameState.crop_field(crop_kind, "grow_days") if state == "planted" else 1
	stage = clampi(value, 0, maxi(1, max_stage))
	_refresh_crop()


func _refresh_crop() -> void:
	if is_instance_valid(_crop_root):
		_crop_root.free()
		_crop_root = null
	if _ring != null:
		_ring.visible = false
	if state == "planted":
		var landscape := preload("res://scripts/art/landscape_models.gd")
		_crop_root = landscape.crop(crop_kind, _rng.randi_range(0, 99))
		_crop_root.position = Vector3(0, 0.08, 0)
		_crop_root.rotation.y = _rng.randf_range(0, TAU)
		var growth: float = lerpf(0.30, 1.0, clampf(float(stage) / float(GameState.crop_field(crop_kind, "grow_days")), 0.0, 1.0))
		_crop_root.scale = Vector3.ONE * growth
		add_child(_crop_root)
		if _ring == null:
			_ring = M.torus(self, Vector3(0, 0.95, 0), 0.55, 0.04, "#e8bf62", "MatureRing")
			_ring.scale = Vector3(1.0, 0.45, 1.0)
			var glow: StandardMaterial3D = M.paint("#ffcf6e", 0.55).duplicate()
			glow.emission_enabled = true
			glow.emission = Color("#ffc679")
			glow.emission_energy_multiplier = 0.9
			_ring.material_override = glow
	_ring.visible = is_mature()


func _apply_moisture() -> void:
	if _soil == null:
		return
	var wet := watered
	for i in range(_ridges.size()):
		if wet and _ridge_wet.size() <= i:
			var damp: StandardMaterial3D = (_ridge_dry[i] as StandardMaterial3D).duplicate()
			damp.albedo_color = damp.albedo_color.darkened(0.32)
			_ridge_wet.append(damp)
		_ridges[i].material_override = _ridge_wet[i] if wet else _ridge_dry[i]


func _process(delta: float) -> void:
	if _ring != null and _ring.visible:
		_ring.rotate_y(delta * 1.1)
		_ring.position.y = 0.95 + sin(Time.get_ticks_msec() * 0.0023) * 0.05
