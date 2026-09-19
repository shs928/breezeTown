extends RefCounted
## 动物领域状态（AnimalState）：种类、当日抚摸、归属牧场。不依赖任何 Node3D。
## 游荡动画与模型表现仍在 animal.gd（视图）。

const AnimalDB := preload("res://scripts/data/animal_db.gd")

const FRIENDSHIP_MAX := 500
const FRIENDSHIP_BONUS_AT := 400  # 达到后每日产出翻倍（确定性阈值，非概率）
const PET_JOY := 30
const FED_JOY := 20
const STARVED_SADNESS := 10

var kind := "cow"
var petted_today := false
var home_index := 0  # 归属牧场序号（0 为初始牧场）
var friendship := 0  # FARM-01：好感 0–500；抚摸+30，吃饱+20，挨饿-10


func setup(p_kind: String, p_home_index: int = 0) -> void:
	kind = p_kind
	home_index = p_home_index


func pet() -> bool:
	## 每天第一次抚摸返回 true。
	if petted_today:
		return false
	petted_today = true
	_friendship_clamped(friendship + PET_JOY)
	EventBus.instance().animal_petted.emit(kind)
	return true


func on_fed() -> void:
	_friendship_clamped(friendship + FED_JOY)


func on_starved() -> void:
	_friendship_clamped(friendship - STARVED_SADNESS)


func yields_double() -> bool:
	return friendship >= FRIENDSHIP_BONUS_AT


func _friendship_clamped(value: int) -> void:
	friendship = clampi(value, 0, FRIENDSHIP_MAX)


func new_day() -> void:
	petted_today = false


func product_kind() -> String:
	return AnimalDB.product(kind)


func label() -> String:
	return AnimalDB.label(kind)


func to_dict() -> Dictionary:
	return {"kind": kind, "petted_today": petted_today, "home_index": home_index, "friendship": friendship}


func from_dict(data: Dictionary) -> void:
	kind = data.get("kind", kind)
	petted_today = bool(data.get("petted_today", false))
	home_index = int(data.get("home_index", 0))
	friendship = int(data.get("friendship", 0))
