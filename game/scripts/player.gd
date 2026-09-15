extends CharacterBody3D
## 玩家农夫：WASD/方向键移动、随相机转向、行走/待机/农活动作切换。

const F = preload("res://scripts/art/farmer_model.gd")
const FarmerAnim = preload("res://scripts/farmer_anim.gd")

const SPEED := 3.6
const TURN_SPEED := 11.0
const CAMERA_OFFSET := Vector3(0, 10.4, 8.3)

var camera: Camera3D
var locked := false  # 商店面板打开或过场时锁住移动
var acting := false
var zoom_levels: Array[float] = [1.0, 0.8, 1.3, 1.8]
var zoom_index := 0

var _farmer: Node3D
var _anim: AnimationPlayer
var _bound_half := Vector2(46, 36)
var _bound_pow := 6


func set_bounds(half: Vector2, power: int) -> void:
	_bound_half = half
	_bound_pow = power


func _ready() -> void:
	_farmer = F.build(0)
	_farmer.name = "Farmer"
	add_child(_farmer)
	_anim = _farmer.get_node("AnimationPlayer")
	FarmerAnim.add_act(_farmer)
	_anim.animation_finished.connect(_on_animation_finished)
	_anim.play("idle")
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.32
	capsule.height = 1.1
	shape.shape = capsule
	shape.position = Vector3(0, 0.62, 0)
	add_child(shape)


func _physics_process(delta: float) -> void:
	var input := Vector2.ZERO
	if not locked and not acting:
		input = _move_vector()
	var direction := Vector3(input.x, 0, input.y)
	if direction.length_squared() > 0.02:
		velocity = direction.normalized() * SPEED
		move_and_slide()
		var target_yaw := atan2(direction.x, direction.z)
		_farmer.rotation.y = lerp_angle(_farmer.rotation.y, target_yaw, 1.0 - exp(-TURN_SPEED * delta))
		if _anim.current_animation != "walk":
			_anim.play("walk")
	else:
		velocity = Vector3.ZERO
		if not acting and _anim.current_animation != "idle":
			_anim.play("idle")
	# 圈定在圆角矩形岛屿范围内，脚底贴地。
	var p := global_position
	p.y = 0.0
	var edge: float = pow(absf(p.x) / _bound_half.x, _bound_pow) + pow(absf(p.z) / _bound_half.y, _bound_pow)
	if edge > 1.0:
		p *= pow(1.0 / edge, 1.0 / float(_bound_pow)) as float
	global_position = p
	if is_instance_valid(camera):
		var desired: Vector3 = global_position + CAMERA_OFFSET * zoom_levels[zoom_index]
		camera.global_position = camera.global_position.lerp(desired, 1.0 - exp(-6.0 * delta))
		camera.look_at(global_position + Vector3(0, 0.95, 0))


func _move_vector() -> Vector2:
	var x := 0.0
	var y := 0.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		x += 1.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		y += 1.0
	return Vector2(x, y)


func start_act() -> void:
	if acting:
		return
	acting = true
	_anim.play("act")


func _on_animation_finished(name: StringName) -> void:
	if name == &"act":
		acting = false
		_anim.play("idle")
