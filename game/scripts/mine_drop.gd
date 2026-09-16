extends Node3D
## 矿物先落地，再吸附到靠近的玩家；离层后保留尚未拾取的物品。

signal collected(drop: Node3D)

const Models = preload("res://scripts/art/mine_models.gd")
var kind := "stone"
var amount := 1
var player: CharacterBody3D
var taken := false
var _age := 0.0
var _model: Node3D


func _ready() -> void:
	_model = build_model()
	add_child(_model)


func build_model() -> Node3D:
	return Models.loot(kind)


func _physics_process(delta: float) -> void:
	if taken or not is_instance_valid(player):
		return
	_age += delta
	_model.rotation.y += delta * 1.5
	_model.position.y = 0.16 + absf(sin(minf(_age, 0.8) * PI / 0.8)) * 0.65 if _age < 0.8 else 0.16 + sin(_age * 3) * 0.05
	if _age < 0.45 or player.locked:
		return
	var flat_player := Vector3(player.global_position.x, 0, player.global_position.z)
	var distance := position.distance_to(flat_player)
	if distance < 3.2:
		position = position.move_toward(flat_player, delta * (4.0 + 6.0 / maxf(distance, 0.3)))
	if position.distance_to(flat_player) < 0.65:
		taken = true
		collected.emit(self)
		queue_free()
