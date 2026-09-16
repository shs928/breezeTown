extends StaticBody3D
## 地表资源的碰撞、受击、成长与倒树反馈；占地和掉落由管理器统一结算。

signal broken(resource: Node3D)

const Trees = preload("res://scripts/art/tree_models.gd")
const OreModels = preload("res://scripts/art/mine_models.gd")
const StaticGeometry = preload("res://scripts/art/static_geometry.gd")
const Feedback = preload("res://scripts/combat_feedback.gd")
const M = preload("res://scripts/art/art_mesh.gd")

var category := "tree"
var species := "oak"
var kind := "stone"
var variant := 0
var stage := 3
var size_factor := 1.0
var yaw := 0.0
var health := 54
var depleted := false
var player: CharacterBody3D
var planted := false
var _model: Node3D
var _crown: Node3D
var _shape: CollisionShape3D
var _notch: Node3D
var _time := 0.0
var _shake := 0.0


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	_time = variant * 3.72 + position.x * 0.19
	health = max_health()
	_shape = CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = physical_radius()
	cylinder.height = 1.3 if category == "tree" else 1.0
	_shape.shape = cylinder
	_shape.position.y = cylinder.height * 0.5
	add_child(_shape)
	_rebuild_visual()


func max_health() -> int:
	return (54 if stage == 3 else 18) if category == "tree" else (18 if kind == "stone" else 36)


func physical_radius() -> float:
	return (0.35 if stage == 3 else 0.16) * size_factor if category == "tree" else 0.72


func occupied_radius() -> float:
	# 树苗提前预留成年树的根系，成长时不会挤占后来开发的田块。
	return 1.25 * size_factor if category == "tree" else 0.85


func label() -> String:
	if category == "ore":
		return {"stone": "岩石", "copper": "铜矿", "coal": "煤矿"}.get(kind, "矿石")
	var title: String = {"oak": "橡树", "pine": "山松", "apple": "苹果树"}[species]
	return title if stage == 3 else "%s树苗 · %d / 3 天" % [title, stage]


func required_tool() -> String:
	return "axe" if category == "tree" else "pickaxe"


func _rebuild_visual() -> void:
	if is_instance_valid(_model):
		remove_child(_model)
		_model.queue_free()
	_model = Trees.build(species, variant, stage) if category == "tree" else OreModels.ore(kind, false, 1)
	_model.rotation.y = yaw
	_model.scale = Vector3.ONE * size_factor
	add_child(_model)
	if category == "tree":
		_crown = _model.get_node("Crown")
		_notch = M.box(_model, Vector3(0, 0.62, 0.22), Vector3(0.27, 0.11, 0.055), "#d1b27e", "AxeNotch", 0.014)
		_notch.hide()
	else:
		StaticGeometry.bake(_model)
		set_process(false)


func _process(delta: float) -> void:
	if depleted:
		return
	_time += delta
	_shake = maxf(0, _shake - delta * 2.4)
	if not is_instance_valid(player) or global_position.distance_squared_to(player.global_position) > 2500:
		return
	if is_instance_valid(_crown):
		_crown.rotation.z = sin(_time * 1.15) * 0.018 + sin(_time * 26) * _shake * 0.10
		_crown.rotation.x = cos(_time * 0.85) * 0.012


func grow() -> bool:
	if depleted or category != "tree" or stage >= 3:
		return false
	stage += 1
	health = max_health()
	(_shape.shape as CylinderShape3D).radius = physical_radius()
	_rebuild_visual()
	return true


func hit(tool: String, power: int, from: Vector3) -> int:
	if depleted or tool != required_tool() or power <= 0:
		return 0
	var amount := mini(health, power)
	health -= amount
	_shake = 1.0
	Feedback.number(get_parent(), position + Vector3(0, 0.8, 0), str(amount), Color("#f3d695") if category == "tree" else Color("#e7d8aa"))
	Feedback.burst(get_parent(), position + Vector3(0, 0.6, 0), "#b58d57" if category == "tree" else OreModels.ORE_COLORS[kind], 9)
	if category == "tree" and stage == 3:
		_notch.show()
		_notch.scale.x = 1.0 + (54 - health) / 54.0 * 0.5
	if health <= 0:
		depleted = true
		collision_layer = 0
		_shape.set_deferred("disabled", true)
		broken.emit(self)
		if category == "tree":
			_fall(from)
		else:
			_model.hide()
			queue_free()
	elif category == "ore":
		var tween := create_tween()
		tween.tween_property(_model, "rotation:z", 0.11, 0.04)
		tween.tween_property(_model, "rotation:z", -0.07, 0.06)
		tween.tween_property(_model, "rotation:z", 0.0, 0.07)
	return amount


func _fall(from: Vector3) -> void:
	var direction := (global_position - from).normalized()
	direction.y = 0
	if direction.length_squared() < 0.01:
		direction = Vector3.FORWARD
	var axis := Vector3.UP.cross(direction).normalized()
	var initial := _model.quaternion
	var tween := create_tween()
	tween.tween_method(func(angle: float): _model.quaternion = Quaternion(axis, angle) * initial, 0.0, 1.3, 0.65).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(func(): Feedback.burst(get_parent(), position + direction * size_factor, "#8f9c56", 14))
	tween.tween_property(_model, "scale", Vector3.ONE * 0.001, 0.25)
	tween.tween_callback(queue_free)
