extends CharacterBody3D
## 玩家农夫：移动、关节挂点装备、挥动命中时机与受击保护。

signal tool_hit(tool: String)

const F = preload("res://scripts/art/farmer_model.gd")
const FarmerAnim = preload("res://scripts/farmer_anim.gd")
const Equipment = preload("res://scripts/art/equipment_models.gd")

const SPEED := 3.6
const RUN_SPEED := 6.4
const TURN_SPEED := 11.0
const CAMERA_OFFSET := Vector3(12, 17, 15)

var camera_target_offset:=Vector3.ZERO
var camera: Camera3D
var surface_map: RefCounted
var locked := false  # 商店面板打开或过场时锁住移动
var acting := false
var zoom_levels: Array[float] = [0.8, 1.0, 1.35, 1.8, 2.3]
var zoom_index := 3
var equipped_tool := "hand"
var equipped_seed := "radish"
var attack_cooldown := 0.0
var invulnerable := 0.0

var _farmer: Node3D
var _anim: AnimationPlayer
var _bound_half := Vector2(46, 36)
var _bound_pow := 6
var _socket: Node3D
var _held: Node3D
var _swing_tool := ""
var _swing_elapsed := 0.0
var _hit_pending := false
var _knockback := Vector3.ZERO
var _lantern: OmniLight3D
var _flash_left := 0.0
var _flash_material: StandardMaterial3D
var _visual_meshes: Array = []


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
	collision_layer = 2
	collision_mask = 1 | 4
	_socket = Node3D.new()
	_socket.name = "ToolSocket"
	_socket.position = Vector3(0.010, -0.180, 0.034)
	_farmer.get_node("Body/Arm_R/Elbow_R").add_child(_socket)
	set_tool("hand")
	_lantern = OmniLight3D.new()
	_lantern.position = Vector3(0, 2.3, 0.7)
	_lantern.light_color = Color("#ffddaa")
	_lantern.light_energy = 1.35
	_lantern.omni_range = 9.0
	_lantern.omni_attenuation = 1.3
	_lantern.visible = false
	add_child(_lantern)
	_flash_material = StandardMaterial3D.new()
	_flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash_material.albedo_color = Color(1, 0.53, 0.46, 0.5)
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.32
	capsule.height = 1.1
	shape.shape = capsule
	shape.position = Vector3(0, 0.62, 0)
	add_child(shape)


func _physics_process(delta: float) -> void:
	attack_cooldown = maxf(0, attack_cooldown - delta)
	invulnerable = maxf(0, invulnerable - delta)
	if _flash_left > 0:
		_flash_left -= delta
		if _flash_left <= 0:
			for mesh: MeshInstance3D in _visual_meshes:
				if is_instance_valid(mesh):
					mesh.material_overlay = null
	if _hit_pending:
		_swing_elapsed += delta
		if locked:
			cancel_action()
		elif _swing_elapsed >= (0.29 if _swing_tool in ["pickaxe", "axe"] else 0.18):
			_hit_pending = false
			tool_hit.emit(_swing_tool)
	var input := Vector2.ZERO
	if not locked and not acting:
		input = _move_vector()
	var direction := Vector3(input.x, 0, input.y)
	if direction.length_squared() > 0.02:
		velocity = direction.normalized() * (RUN_SPEED if Input.is_physical_key_pressed(KEY_SHIFT) else SPEED)
		var target_yaw := atan2(direction.x, direction.z)
		_farmer.rotation.y = lerp_angle(_farmer.rotation.y, target_yaw, 1.0 - exp(-TURN_SPEED * delta))
		if _anim.current_animation != "walk":
			_anim.play("walk")
	else:
		velocity = Vector3.ZERO
		if not acting and _anim.current_animation != "idle":
			_anim.play("idle")
	velocity += _knockback
	_knockback = _knockback.move_toward(Vector3.ZERO, delta * 18.0)
	var before_move := global_position
	if not velocity.is_zero_approx():
		move_and_slide()
	if surface_map != null:
		var flat := Vector2(global_position.x, global_position.z)
		if surface_map.is_water(flat, 0.25) and not surface_map.on_deck(flat, 0.25):
			global_position = before_move
			velocity = Vector3.ZERO
	# 圈定在山脚以内，与山谷地形及可开垦区域共用同一条边界。
	var p := global_position
	p.y = preload("res://scripts/core/surface_height.gd").deck_height(Vector2(p.x,p.z),surface_map.bridges,surface_map.ramps) if surface_map != null else 0.0
	var edge: float = pow(absf(p.x) / _bound_half.x, _bound_pow) + pow(absf(p.z) / _bound_half.y, _bound_pow)
	if edge > 1.0:
		p *= pow(1.0 / edge, 1.0 / float(_bound_pow)) as float
	global_position = p
	if is_instance_valid(camera):
		var desired: Vector3 = global_position + camera_target_offset + CAMERA_OFFSET * zoom_levels[zoom_index]
		camera.global_position = camera.global_position.lerp(desired, 1.0 - exp(-6.0 * delta))
		camera.look_at(global_position + camera_target_offset + Vector3(0, 0.95, 0))
		camera.size = lerpf(camera.size, 20.0 * zoom_levels[zoom_index], 0.12)


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
	var forward := Vector2(-CAMERA_OFFSET.x, -CAMERA_OFFSET.z).normalized()
	var right := Vector2(-forward.y, forward.x)
	return right * x - forward * y


func start_act() -> void:
	if acting:
		return
	acting = true
	_anim.play("act")


func set_tool(tool: String, seed_kind: String = "radish") -> void:
	if _socket == null or tool not in Equipment.TOOLS:
		return
	if _held != null and equipped_tool == tool and equipped_seed == seed_kind:
		return
	cancel_action()
	equipped_tool = tool
	equipped_seed = seed_kind
	if is_instance_valid(_held):
		_socket.remove_child(_held)
		_held.queue_free()
	_held = Equipment.build(tool, seed_kind)
	if tool in ["hoe", "pickaxe", "sword", "axe"]:
		_held.rotation = Vector3(0.55, 0.75, 0)
	_socket.add_child(_held)
	_visual_meshes = _farmer.find_children("*", "MeshInstance3D", true, false)


func begin_swing() -> bool:
	if locked or acting or attack_cooldown > 0 or equipped_tool not in ["sword", "pickaxe", "axe"]:
		return false
	acting = true
	_swing_tool = equipped_tool
	_swing_elapsed = 0.0
	_hit_pending = true
	attack_cooldown = 0.66 if equipped_tool in ["pickaxe", "axe"] else 0.5
	_anim.play("mine" if equipped_tool in ["pickaxe", "axe"] else "slash")
	return true


func facing() -> Vector3:
	return Vector3(sin(_farmer.rotation.y), 0, cos(_farmer.rotation.y))


func face_point(at: Vector3) -> void:
	var delta := at - global_position
	if delta.length_squared() > 0.01:
		_farmer.rotation.y = atan2(delta.x, delta.z)


func cancel_action() -> void:
	_hit_pending = false
	_swing_tool = ""
	acting = false
	if is_instance_valid(_anim):
		_anim.play("idle")


func receive_hit(from: Vector3) -> bool:
	if locked or invulnerable > 0:
		return false
	invulnerable = 0.95
	_knockback = (global_position - from).normalized() * 4.0
	_flash_left = 0.17
	for mesh: MeshInstance3D in _visual_meshes:
		if is_instance_valid(mesh):
			mesh.material_overlay = _flash_material
	return true


func teleport(at: Vector3) -> void:
	cancel_action()
	velocity = Vector3.ZERO
	_knockback = Vector3.ZERO
	global_position = at
	invulnerable = 1.0
	snap_camera()


func snap_camera() -> void:
	if is_instance_valid(camera):
		camera.global_position = global_position + camera_target_offset + CAMERA_OFFSET * zoom_levels[zoom_index]
		camera.look_at(global_position + camera_target_offset + Vector3(0, 0.95, 0))
		camera.size = 20.0 * zoom_levels[zoom_index]


func set_underground(value: bool) -> void:
	_lantern.visible = value
	camera_target_offset=Vector3.ZERO if value or _bound_half.x<200 else Vector3(0,0,-4)


func _on_animation_finished(name: StringName) -> void:
	if name in [&"act", &"mine", &"slash"]:
		acting = false
		_anim.play("idle")
