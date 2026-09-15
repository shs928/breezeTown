extends Node3D
## 牧场产出物：飘浮旋转的小物件，走近按 E 拾取。

const RanchModels = preload("res://scripts/ranch_models.gd")

var kind := "milk"

var _clock := 0.0
var _base_y := 0.24


func setup(p_kind: String) -> void:
	kind = p_kind
	var model := RanchModels.product_model(kind)
	add_child(model)


func _process(delta: float) -> void:
	_clock += delta
	rotate_y(delta * 1.5)
	position.y = _base_y + sin(_clock * 2.2) * 0.045


func label() -> String:
	match kind:
		"wool":
			return "羊毛"
		"egg":
			return "鸡蛋"
		_:
			return "牛奶"
