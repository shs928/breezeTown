extends Node3D
## 牧场动物：在草场矩形内随机游荡，每天可抚摸一次，喂食后次日产出。

const RanchModels = preload("res://scripts/ranch_models.gd")

const SPEEDS := {"cow": 0.72, "sheep": 0.95, "chicken": 1.35}
const BOB_AMPS := {"cow": 0.030, "sheep": 0.026, "chicken": 0.055}
const HEAD_HEIGHTS := {"cow": 1.45, "sheep": 1.10, "chicken": 0.72}

var kind := "cow"
var petted_today := false
var pasture := Rect2(11, 5, 22, 14)

var _model: Node3D
var _target := Vector2.ZERO
var _idle := 0.0
var _phase := 0.0
var _clock := 0.0
var _rng := RandomNumberGenerator.new()


func setup(p_kind: String, p_pasture: Rect2, seed_value: int) -> void:
	kind = p_kind
	pasture = p_pasture
	_rng.seed = seed_value
	_model = RanchModels.animal_model(kind, seed_value)
	add_child(_model)
	_target = _random_spot()
	position = Vector3(_target.x, 0, _target.y)
	_pick_target()


func _process(delta: float) -> void:
	_clock += delta
	if _idle > 0.0:
		_idle -= delta
		_model.position.y = 0.0
		if kind == "chicken":
			_model.rotation.x = maxf(0.0, sin(_clock * 7.0)) * 0.22
		else:
			_model.rotation.x = 0.0
		return
	_model.rotation.x = 0.0
	var here := Vector2(position.x, position.z)
	var offset := _target - here
	if offset.length() < 0.12:
		_idle = _rng.randf_range(1.6, 4.5)
		_pick_target()
		return
	var step: float = SPEEDS[kind] * delta
	var heading := offset.normalized()
	position.x += heading.x * step
	position.z += heading.y * step
	_phase += delta * (7.0 + SPEEDS[kind] * 3.0)
	_model.position.y = absf(sin(_phase)) * BOB_AMPS[kind]
	rotation.y = lerp_angle(rotation.y, atan2(heading.x, heading.y), 1.0 - exp(-8.0 * delta))


func _pick_target() -> void:
	_target = _random_spot()


func _random_spot() -> Vector2:
	return Vector2(
		_rng.randf_range(pasture.position.x + 0.8, pasture.position.x + pasture.size.x - 0.8),
		_rng.randf_range(pasture.position.y + 0.8, pasture.position.y + pasture.size.y - 0.8)
	)


func pet() -> bool:
	## 每天第一次抚摸返回 true 并跳一下示爱。
	if petted_today:
		return false
	petted_today = true
	_spawn_heart()
	var tween := create_tween()
	tween.tween_property(self, "position:y", 0.12, 0.14).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "position:y", 0.0, 0.16).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	return true


func on_new_day() -> void:
	petted_today = false


func product_kind() -> String:
	return RanchModels.ANIMAL_PRODUCTS[kind]


func label() -> String:
	return RanchModels.ANIMAL_LABELS[kind]


func _spawn_heart() -> void:
	var heart := Node3D.new()
	heart.name = "LoveHeart"
	heart.position = Vector3(0, HEAD_HEIGHTS[kind], 0)
	add_child(heart)
	var m := preload("res://scripts/art/art_mesh.gd")
	for side in [-1.0, 1.0]:
		var lobe := m.ellipsoid(heart, Vector3(side * 0.035, 0.03, 0), Vector3(0.042, 0.042, 0.03), "#e88a80", "Lobe", 10, 6)
		lobe.rotation.z = side * 0.5
	var tip := m.ellipsoid(heart, Vector3(0, -0.03, 0), Vector3(0.055, 0.05, 0.03), "#d9635c", "Tip", 4, 3)
	tip.rotation.x = PI
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(heart, "position:y", HEAD_HEIGHTS[kind] + 0.55, 0.9).set_ease(Tween.EASE_OUT)
	tween.tween_property(heart, "scale", Vector3.ONE * 0.6, 0.9)
	tween.chain().tween_callback(heart.queue_free)
