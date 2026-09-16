extends CharacterBody3D
## 史莱姆、蝙蝠与第十层守卫：沿可通行格追踪，预警后攻击，可闪避。

signal struck(amount: int, at: Vector3)
signal defeated(monster: Node3D)
signal attacked(amount: int, source: Vector3)

const M = preload("res://scripts/art/art_mesh.gd")
const Models = preload("res://scripts/art/mine_models.gd")
const StaticGeometry = preload("res://scripts/art/static_geometry.gd")
const FONT = preload("res://resources/ui_font.tres")

var kind := "slime"
var depth := 1
var player: CharacterBody3D
var floor_world: Node3D
var health := 30
var max_health := 30
var dead := false
var behavior_enabled := true # 截图时保留待机和受击动画，仅冻结 AI 决策。
var damage := 7
var speed := 1.6
var _body: Node3D
var _wings: Array[Node3D] = []
var _hp_label: Label3D
var _warning: Label3D
var _tell: MeshInstance3D
var _meshes: Array = []
var _flash: StandardMaterial3D
var _age := 0.0
var _cooldown := 0.9
var _windup := -1.0
var _stun := 0.0
var _flash_left := 0.0
var _path_clock := 0.0
var _waypoint := Vector3.ZERO
var _knockback := Vector3.ZERO
var _home := Vector3.ZERO


func _ready() -> void:
	collision_layer = 4
	collision_mask = 1 | 2 | 4
	max_health = 28 + depth * 3
	damage = 6 + depth / 2
	if kind == "bat":
		max_health = 20 + depth * 2
		speed = 2.5
	elif kind == "guardian":
		max_health = 176
		damage = 17
		speed = 1.35
	health = max_health
	_home = position
	_waypoint = position
	var collision := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.67 if kind == "guardian" else 0.43
	shape.height = 1.6 if kind == "guardian" else 1.0
	collision.shape = shape
	collision.position.y = shape.height * 0.5
	add_child(collision)
	_build_model()
	_hp_label = Label3D.new()
	_hp_label.font = FONT
	_hp_label.font_size = 23
	_hp_label.pixel_size = 0.010
	_hp_label.outline_size = 6
	_hp_label.position.y = 2.5 if kind == "guardian" else (1.95 if kind == "bat" else 1.5)
	_hp_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_hp_label.modulate = Color("#dae4c7")
	_hp_label.visible = false
	add_child(_hp_label)
	_refresh_health()
	_warning = Label3D.new()
	_warning.font = FONT
	_warning.text = "!"
	_warning.font_size = 68
	_warning.pixel_size = 0.013
	_warning.position.y = _hp_label.position.y + 0.58
	_warning.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_warning.modulate = Color("#ffc36e")
	_warning.visible = false
	add_child(_warning)
	_tell = M.torus(self, Vector3(0, 0.05, 0), 1.8 if kind == "guardian" else 1.2, 0.035, "#f19b72", "AttackTell")
	_tell.material_override = Models.glow_material("#f0a875", 0.8)
	_tell.visible = false
	_flash = StandardMaterial3D.new()
	_flash.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash.albedo_color = Color(1, 0.96, 0.75, 0.72)
	_meshes = _body.find_children("*", "MeshInstance3D", true, false)


func label() -> String:
	return {"slime": "苔藓史莱姆" if depth <= 3 else "晶石史莱姆", "bat": "洞穴蝙蝠", "guardian": "晶岩守卫"}[kind]


func _physics_process(delta: float) -> void:
	if dead or floor_world.paused or player.locked:
		return
	_age += delta
	_cooldown = maxf(0, _cooldown - delta)
	_stun = maxf(0, _stun - delta)
	if _flash_left > 0:
		_flash_left -= delta
		if _flash_left <= 0:
			for mesh: MeshInstance3D in _meshes:
				mesh.material_overlay = null
	_animate()
	var distance := global_position.distance_to(player.global_position)
	_hp_label.visible = health < max_health or distance < 5.5
	if not behavior_enabled:
		return
	var safe_spawn: bool = player.global_position.distance_to(floor_world.spawn_position()) < 3.0
	var target := player.global_position if distance < 12.0 and not safe_spawn else _home
	var reach := 2.25 if kind == "guardian" else 1.55
	velocity = Vector3.ZERO
	if _windup >= 0:
		_windup -= delta
		if _windup < 0:
			_warning.hide()
			_tell.hide()
			if distance <= reach + 0.25 and not safe_spawn and floor_world.clear_line(global_position, player.global_position):
				attacked.emit(damage, global_position)
			_cooldown = 1.5 if kind == "guardian" else 1.1
	elif _stun <= 0:
		if distance < reach and _cooldown <= 0 and not safe_spawn and floor_world.clear_line(global_position, player.global_position):
			_windup = 0.78 if kind == "guardian" else 0.52
			_warning.show()
			_tell.show()
		elif position.distance_to(target) > 0.35:
			_path_clock -= delta
			if _path_clock <= 0 or position.distance_to(_waypoint) < 0.3:
				_waypoint = floor_world.next_waypoint(position, target)
				_path_clock = 0.35
			var direction := (_waypoint - position).normalized()
			velocity = direction * speed
			if direction.length_squared() > 0.01:
				_body.rotation.y = lerp_angle(_body.rotation.y, atan2(direction.x, direction.z), delta * 7)
	velocity += _knockback
	_knockback = _knockback.move_toward(Vector3.ZERO, delta * 14.0)
	move_and_slide()
	position.y = 0


func hit(amount: int, from: Vector3) -> int:
	if dead or amount <= 0:
		return 0
	var dealt := mini(amount, health)
	health -= dealt
	struck.emit(dealt, global_position + Vector3(0, 1.15 if kind != "guardian" else 2.0, 0))
	_refresh_health()
	_stun = 0.20
	_hp_label.show()
	_windup = -1
	_warning.hide()
	_tell.hide()
	_cooldown = maxf(_cooldown, 0.65)
	_knockback = (global_position - from).normalized() * (2.0 if kind == "guardian" else 5.0)
	_flash_left = 0.13
	for mesh: MeshInstance3D in _meshes:
		mesh.material_overlay = _flash
	if health == 0:
		dead = true
		collision_layer = 0
		collision_mask = 0
		_hp_label.hide()
		defeated.emit(self)
		var tween := create_tween()
		tween.tween_property(_body, "scale", Vector3.ONE * 0.015, 0.24)
		tween.tween_callback(queue_free)
	return dealt


func _refresh_health() -> void:
	_hp_label.text = "%s  %d / %d" % [label(), health, max_health]


func _animate() -> void:
	if kind == "slime":
		var hop := maxf(0, sin(_age * 5.3))
		_body.position.y = hop * 0.23
		_body.scale = Vector3(1.0 + hop * 0.06, 0.93 + hop * 0.15, 1.0 + hop * 0.06)
	elif kind == "bat":
		_body.position.y = 1.0 + sin(_age * 4.0) * 0.12
		for i in range(_wings.size()):
			_wings[i].rotation.z = sin(_age * 13.0) * 0.7 * (-1 if i == 0 else 1)
	else:
		_body.position.y = absf(sin(_age * 3.5)) * 0.04


func _build_model() -> void:
	_body = Node3D.new()
	_body.name = "MonsterBody"
	add_child(_body)
	if kind == "slime":
		var color := "#86ae79" if depth <= 3 else ("#7caab9" if depth <= 6 else "#b09ccd")
		M.ellipsoid(_body, Vector3(0, 0.46, 0), Vector3(0.61, 0.47, 0.53), color, "SlimeBody", 14, 8)
		M.ellipsoid(_body, Vector3(-0.16, 0.72, 0.20), Vector3(0.19, 0.09, 0.13), "#c9dfb0" if depth <= 3 else "#cad9ee", "SlimeShine", 10, 6)
		for x in [-0.19, 0.19]:
			M.ellipsoid(_body, Vector3(x, 0.49, 0.47), Vector3(0.052, 0.082, 0.035), "#273c3d", "SlimeEye", 10, 6)
			M.ellipsoid(_body, Vector3(x - 0.014, 0.52, 0.501), Vector3(0.015, 0.020, 0.01), "#eef3cf", "EyeGlint", 8, 4)
		M.ellipsoid(_body, Vector3(0, 0.32, 0.50), Vector3(0.075, 0.026, 0.02), "#536956", "SlimeMouth", 8, 4)
		if depth >= 7:
			Models.crystal(_body, Vector3(0, 0.83, 0), 0.32, "#d0bafa")
	elif kind == "bat":
		_body.position.y = 1.0
		M.ellipsoid(_body, Vector3.ZERO, Vector3(0.25, 0.32, 0.20), "#877da1", "BatBody", 12, 7)
		for side in [-1, 1]:
			var wing := Node3D.new()
			_body.add_child(wing)
			_wings.append(wing)
			var surface := SurfaceTool.new()
			surface.begin(Mesh.PRIMITIVE_TRIANGLES)
			M.polygon(surface, [Vector3(side * 0.12, 0.12, 0), Vector3(side * 0.91, 0.27, -0.08), Vector3(side * 0.69, -0.24, 0.01), Vector3(side * 0.44, -0.12, 0.04), Vector3(side * 0.18, -0.24, 0.03)], Vector3.FORWARD)
			M.mesh_node(wing, surface.commit(), Vector3.ZERO, M.paint("#77728f"), "BatWing")
			M.beam(wing, Vector3(side * 0.14, 0.12, 0), Vector3(side * 0.91, 0.27, -0.08), 0.035, "#b2a4c5", "WingBone")
			M.cylinder(_body, Vector3(side * 0.15, 0.32, 0), 0.13, 0, 0.32, "#a69ab9", "BatEar", 5)
			M.ellipsoid(_body, Vector3(side * 0.10, 0.045, 0.19), Vector3(0.046, 0.044, 0.025), "#ffe2a1", "BatEye", 8, 4)
		return # 翅膀保持独立关节，不合并到身体。
	else:
		M.ellipsoid(_body, Vector3(0, 0.97, 0), Vector3(0.80, 0.90, 0.60), "#7b809b", "GuardianTorso", 8, 5)
		M.ellipsoid(_body, Vector3(0, 1.85, 0.04), Vector3(0.54, 0.48, 0.46), "#9d99b8", "GuardianHead", 7, 4)
		for side in [-1, 1]:
			M.ellipsoid(_body, Vector3(side * 0.9, 0.95, 0), Vector3(0.33, 0.64, 0.34), "#696f87", "GuardianArm", 7, 4)
			M.ellipsoid(_body, Vector3(side * 0.42, 0.27, 0.14), Vector3(0.34, 0.3, 0.43), "#626980", "GuardianFoot", 7, 4)
			M.box(_body, Vector3(side * 0.18, 1.92, 0.44), Vector3(0.13, 0.07, 0.045), "#ffe2a1", "GuardianEye").material_override = Models.glow_material("#ffd796", 1.0)
			Models.crystal(_body, Vector3(side * 0.52, 1.62, -0.13), 0.74, "#b8a3ee", side * -0.25)
		Models.crystal(_body, Vector3(0, 0.82, 0.58), 0.58, "#d9bafa")
	StaticGeometry.bake(_body)
