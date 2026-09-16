extends RefCounted
## 动物领域状态（AnimalState）：种类、当日抚摸、归属牧场。不依赖任何 Node3D。
## 游荡动画与模型表现仍在 animal.gd（视图）。

const AnimalDB := preload("res://scripts/data/animal_db.gd")

var kind := "cow"
var petted_today := false
var home_index := 0  # 归属牧场序号（0 为初始牧场）


func setup(p_kind: String, p_home_index: int = 0) -> void:
	kind = p_kind
	home_index = p_home_index


func pet() -> bool:
	## 每天第一次抚摸返回 true。
	if petted_today:
		return false
	petted_today = true
	EventBus.instance().animal_petted.emit(kind)
	return true


func new_day() -> void:
	petted_today = false


func product_kind() -> String:
	return AnimalDB.product(kind)


func label() -> String:
	return AnimalDB.label(kind)


func to_dict() -> Dictionary:
	return {"kind": kind, "petted_today": petted_today, "home_index": home_index}


func from_dict(data: Dictionary) -> void:
	kind = data.get("kind", kind)
	petted_today = bool(data.get("petted_today", false))
	home_index = int(data.get("home_index", 0))
