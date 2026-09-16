extends StaticBody3D
## 只有镐子能破坏矿石；裂隙岩石固定揭开本层向下的梯子。

signal struck(amount: int, at: Vector3)
signal broken(rock: Node3D)

const Models = preload("res://scripts/art/mine_models.gd")
const Feedback = preload("res://scripts/combat_feedback.gd")

var kind := "stone"
var seal := false
var depth := 1
var cell := Vector2i.ZERO
var health := 36
var depleted := false
var _model: Node3D
var _shape: CollisionShape3D


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	health = 36 if seal else (18 if kind == "stone" else (54 if kind == "iron" else 36))
	_model = Models.ore(kind, seal, depth)
	_model.rotation.y = float(posmod(cell.x * 31 + cell.y * 17, 628)) * 0.01
	_model.scale = Vector3(0.92 + posmod(cell.x, 4) * 0.035, 0.91 + posmod(cell.y, 4) * 0.045, 1.0)
	add_child(_model)
	_shape = CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.70
	shape.height = 1.1
	_shape.shape = shape
	_shape.position.y = 0.5
	add_child(_shape)


func label() -> String:
	return "裂隙岩石" if seal else {"stone": "岩石", "copper": "铜矿", "iron": "铁矿", "coal": "煤矿", "crystal": "水晶矿"}[kind]


func hit(power: int) -> int:
	if depleted or power <= 0:
		return 0
	var amount := mini(health, power)
	health -= amount
	struck.emit(amount, global_position + Vector3(0, 0.9, 0))
	Feedback.burst(get_parent(), position + Vector3(0, 0.5, 0), Models.ORE_COLORS[kind])
	if health <= 0:
		depleted = true
		collision_layer = 0
		_shape.set_deferred("disabled", true)
		_model.hide()
		broken.emit(self)
		queue_free()
	else:
		var tween := create_tween()
		tween.tween_property(_model, "rotation:z", 0.13, 0.045)
		tween.tween_property(_model, "rotation:z", -0.09, 0.06)
		tween.tween_property(_model, "rotation:z", 0.0, 0.07)
	return amount
