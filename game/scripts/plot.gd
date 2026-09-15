extends Node3D
## 一块可耕种的菜畦：荒地 → 整地 → 播种 → 浇水 → 生长 → 收获。
## 视觉全部由 art/ 下的程序化建模脚本拼装；生长用成熟株模型缩放近似。

const M = preload("res://scripts/art/art_mesh.gd")
const L = preload("res://scripts/art/landscape_models.gd")
const GameState := preload("res://scripts/game_state.gd")

signal changed

var state := "wild"  # wild | tilled | planted
var crop_kind := ""
var stage := 0
var watered := false
var targeted := false

var _soil: Node3D
var _ridges: Array[MeshInstance3D] = []
var _ridge_dry: Array[StandardMaterial3D] = []
var _ridge_wet: Array[StandardMaterial3D] = []
var _wild_top: Node3D
var _crop_root: Node3D
var _ring: MeshInstance3D
var _spot: MeshInstance3D
var _rng := RandomNumberGenerator.new()


func setup(kind_seed: int) -> void:
	_rng.seed = kind_seed
	_soil = Node3D.new()
	_soil.name = "Bed"
	add_child(_soil)
	M.box(_soil, Vector3(0, 0.052, 0), Vector3(2.30, 0.14, 2.30), "#9e7954", "CultivatedSoil", 0.09)
	for row in range(3):
		var ridge: MeshInstance3D = M.ellipsoid(_soil, Vector3(0, 0.10, (row - 1) * 0.66), Vector3(1.04, 0.079, 0.27), "#8b6748" if row % 2 == 0 else "#926d4c", "SoftSoilRidge", 16, 7)
		_ridges.append(ridge)
		_ridge_dry.append(ridge.material_override)
	for edge_x in [-1.16, 1.16]:
		M.box(_soil, Vector3(edge_x, 0.10, 0), Vector3(0.10, 0.20, 2.46), "#b0966d", "BedEdging")
	for edge_z in [-1.16, 1.16]:
		M.box(_soil, Vector3(0, 0.10, edge_z), Vector3(2.42, 0.20, 0.10), "#ba9e75", "BedEdging")
	_wild_top = Node3D.new()
	_wild_top.name = "WildTop"
	add_child(_wild_top)
	var turf: MeshInstance3D = M.ellipsoid(_wild_top, Vector3(0, 0.115, 0), Vector3(1.02, 0.085, 1.02), "#8fae68", "FallowTurf", 20, 6)
	turf.material_override = M.paint("#87a862", 0.95)
	for i in range(6):
		var clump := L.grass_clump(kind_seed * 13 + i, 0.30)
		clump.position = Vector3(_rng.randf_range(-0.85, 0.85), 0.13, _rng.randf_range(-0.85, 0.85))
		_wild_top.add_child(clump)
	_ring = M.torus(self, Vector3(0, 1.05, 0), 0.62, 0.045, "#e8bf62", "MatureRing")
	_ring.scale = Vector3(1.0, 0.45, 1.0)
	var glow: StandardMaterial3D = M.paint("#ffcf6e", 0.55).duplicate()
	glow.emission_enabled = true
	glow.emission = Color("#ffc679")
	glow.emission_energy_multiplier = 0.9
	_ring.material_override = glow
	_spot = M.cylinder(self, Vector3(0, 0.145, 0), 1.32, 1.32, 0.02, "#f5f1dc", "TargetSpot", 36)
	var spot_material: StandardMaterial3D = M.paint("#f7f3de", 0.8).duplicate()
	spot_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	spot_material.albedo_color = Color(1.0, 0.98, 0.88, 0.34)
	_spot.material_override = spot_material
	_refresh()


func _process(delta: float) -> void:
	if _ring.visible:
		_ring.rotate_y(delta * 1.1)
		_ring.position.y = 1.05 + sin(Time.get_ticks_msec() * 0.0023) * 0.05


func grow_days() -> int:
	return GameState.crop_field(crop_kind, "grow_days") if state == "planted" else 0


func is_mature() -> bool:
	return state == "planted" and stage >= grow_days()


func action_label() -> String:
	match state:
		"wild":
			return "整地"
		"tilled":
			return "播种"
		"planted":
			if is_mature():
				return "收获 " + GameState.crop_label(crop_kind)
			return "浇水" if not watered else "已浇过水"
	return ""


func can_apply(tool: String) -> bool:
	match tool:
		"hoe":
			return state == "wild"
		"seed":
			return state == "tilled"
		"can":
			return state == "planted" and not watered and not is_mature()
		"hand":
			return state == "planted" and is_mature()
	return false


func apply_tool(tool: String, kind: String = "") -> bool:
	match tool:
		"hoe":
			if not can_apply(tool):
				return false
			state = "tilled"
		"seed":
			if not can_apply(tool):
				return false
			state = "planted"
			crop_kind = kind
			stage = 0
			watered = false
		"can":
			if not can_apply(tool):
				return false
			watered = true
		"hand":
			if not can_apply(tool):
				return false
			state = "tilled"
			crop_kind = ""
			stage = 0
			watered = false
		_:
			return false
	_refresh()
	changed.emit()
	return true


func on_day_rollover() -> void:
	if state == "planted" and watered and not is_mature():
		stage += 1
	watered = false
	_refresh()


func set_targeted(value: bool) -> void:
	targeted = value
	_spot.visible = targeted and state != "wild"


func debug_set_stage(value: int) -> void:
	## 仅供展示与自动化：直接设定生长阶段。
	stage = clampi(value, 0, grow_days())
	_refresh()


func _refresh() -> void:
	_wild_top.visible = state == "wild"
	for ridge in _ridges:
		ridge.visible = state != "wild"
	if state == "planted":
		if is_instance_valid(_crop_root):
			_crop_root.free()
		_crop_root = L.crop(crop_kind, _rng.randi_range(0, 99))
		_crop_root.position = Vector3(0, 0.10, 0)
		_crop_root.rotation.y = _rng.randf_range(0, TAU)
		var growth: float = lerpf(0.30, 1.0, clampf(float(stage) / float(grow_days()), 0.0, 1.0))
		_crop_root.scale = Vector3.ONE * growth
		add_child(_crop_root)
	else:
		if is_instance_valid(_crop_root):
			_crop_root.free()
	var wet: bool = state == "planted" and watered
	for i in range(_ridges.size()):
		if wet and _ridge_wet.size() <= i:
			var damp: StandardMaterial3D = (_ridge_dry[i] as StandardMaterial3D).duplicate()
			damp.albedo_color = damp.albedo_color.darkened(0.32)
			_ridge_wet.append(damp)
		_ridges[i].material_override = _ridge_wet[i] if wet else _ridge_dry[i]
	_ring.visible = is_mature()
	_spot.visible = targeted
