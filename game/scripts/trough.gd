extends Node3D
## 牧场食槽：装满干草后，动物次日清早产出。

const RanchModels = preload("res://scripts/ranch_models.gd")

var filled := false

var _hay: Node3D


func setup() -> void:
	add_child(RanchModels.trough())
	_hay = find_children("Hay", "Node3D", true, false)[0]
	_hay.visible = false


func set_filled(value: bool) -> void:
	filled = value
	_hay.visible = value
