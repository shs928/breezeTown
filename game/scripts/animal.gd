extends Node3D
## 牧场动物视图：在草场矩形内随机游荡，抚摸示爱动画。
## 抚摸次数、产出种类等数据都在 AnimalState 领域对象上。

const RanchModels = preload("res://scripts/ranch_models.gd")
const StaticGeometry = preload("res://scripts/art/static_geometry.gd")

const SPEEDS := {"cow": 0.72, "sheep": 0.95, "chicken": 1.35}
const BOB_AMPS := {"cow": 0.030, "sheep": 0.026, "chicken": 0.055}
const HEAD_HEIGHTS := {"cow": 1.45, "sheep": 1.10, "chicken": 0.72}

var data  # AnimalState（domain/animal_state.gd）
var pasture := Rect2(11, 5, 22, 14)
var navigation: RefCounted
var _path := PackedVector3Array()
var _waypoint := 0

var _model: Node3D
var _target := Vector2.ZERO
var _idle := 0.0
var _phase := 0.0
var _clock := 0.0
var _nav_wait := -1.0  # PERF-02：>0 时延迟首次寻路，避免开机时 7 只动物×全图寻路卡死启动。
var _rng := RandomNumberGenerator.new()


func setup(p_kind: String, p_pasture: Rect2, seed_value: int) -> void:
	if data == null:
		data = load("res://scripts/domain/animal_state.gd").new()
	data.setup(p_kind)
	pasture = p_pasture
	_rng.seed = seed_value
	_model = RanchModels.animal_model(kind, seed_value)
	# 合并单只动物的静态部件，整体的走动、摆头和跳跃仍由本节点驱动。
	StaticGeometry.bake(_model)
	add_child(_model)
	_target = _random_spot()
	position = Vector3(_target.x, 0, _target.y)
	_pick_target()


var kind: String:
	get: return data.kind if data != null else "cow"
var petted_today: bool:
	get: return data.petted_today if data != null else false


func _process(delta: float) -> void:
	_clock += delta
	if _nav_wait > 0.0:
		_nav_wait -= delta
		if _nav_wait <= 0.0:
			_pick_target()
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
	if not _path.is_empty() and _waypoint < _path.size():
		if position.distance_to(_path[_waypoint]) < 0.15:
			_waypoint += 1
		if _waypoint < _path.size():
			_target = Vector2(_path[_waypoint].x, _path[_waypoint].z)
	var offset := _target - here
	if offset.length() < 0.12:
		_idle = _rng.randf_range(1.6, 4.5)
		_pick_target()
		return
	var step: float = minf(SPEEDS[kind] * delta, offset.length())
	var heading := offset.normalized()
	position.x += heading.x * step
	position.z += heading.y * step
	_phase += delta * (7.0 + SPEEDS[kind] * 3.0)
	_model.position.y = absf(sin(_phase)) * BOB_AMPS[kind]
	rotation.y = lerp_angle(rotation.y, atan2(heading.x, heading.y), 1.0 - exp(-8.0 * delta))


func set_navigation(service: RefCounted) -> void:
	navigation = service
	# 启动时先直奔场内随机点（矩形内直线必然在场内，安全），
	# 错峰延迟再做带寻路的目标挑选，把寻路成本摊出启动窗口。
	_nav_wait = _rng.randf_range(0.6, 2.6)
	_target = _random_spot()


func _pick_target() -> void:
	_path.clear()
	_waypoint = 0
	for attempt in range(8):
		var candidate := _random_spot()
		if navigation == null:
			_target = candidate
			return
		var route: PackedVector3Array = navigation.find_path(position, Vector3(candidate.x, 0, candidate.y))
		if route.is_empty():
			continue
		var stays_home := true
		for point in route:
			if not pasture.grow(-0.4).has_point(Vector2(point.x, point.z)):
				stays_home = false
				break
		if stays_home:
			_path = route
			_waypoint = mini(1, route.size() - 1)
			_target = Vector2(route[_waypoint].x, route[_waypoint].z)
			return
	_target = Vector2(position.x, position.z)
	_idle = 2.0


func _random_spot() -> Vector2:
	return Vector2(
		_rng.randf_range(pasture.position.x + 0.8, pasture.position.x + pasture.size.x - 0.8),
		_rng.randf_range(pasture.position.y + 0.8, pasture.position.y + pasture.size.y - 0.8)
	)


func pet() -> bool:
	## 每天第一次抚摸返回 true 并跳一下示爱。
	if data == null or not data.pet():
		return false
	_spawn_heart()
	var tween := create_tween()
	tween.tween_property(self, "position:y", 0.12, 0.14).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "position:y", 0.0, 0.16).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	return true


func on_new_day() -> void:
	if data != null:
		data.new_day()


func product_kind() -> String:
	return data.product_kind() if data != null else "milk"


func label() -> String:
	return data.label() if data != null else "动物"


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
