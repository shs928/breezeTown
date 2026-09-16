class_name EventBus
extends RefCounted
## 全局事件总线：系统之间不直接引用，数据系统发布事件，UI 与其他系统监听。
## 全局类（class_name）+ 静态单例 EventBus.instance()——不注册 autoload，
## 保证 headless 单测同样可用。

static var _instance: EventBus = null


static func instance() -> EventBus:
	if _instance == null:
		_instance = EventBus.new()
	return _instance


## ---------- 时间与世界 ----------
## day_ended 在日切计数翻转后、日结算前发出，参数为新的一天序号。
## day_started 在日结算完成后发出，订阅方可安全刷新界面。
signal day_ended(day: int)
signal day_started(day: int)
signal season_changed(season: String)
signal weather_changed(weather: String)

## ---------- 农业 / 牧场 ----------
signal crop_tilled(key: Vector2i)
signal crop_planted(key: Vector2i, kind: String)
signal crop_watered(key: Vector2i)
signal crop_harvested(key: Vector2i, kind: String)
signal animal_petted(kind: String)
signal trough_filled

## ---------- 背包 / 经济 ----------
signal item_added(item_id: String, count: int)
signal item_removed(item_id: String, count: int)
signal money_changed(total: int, delta: int)

## ---------- 流程 ----------
signal player_slept
signal map_switched(from_depth: int, to_depth: int)
signal save_written(path: String)


func reset_for_tests() -> void:
	## 单测间隔离：断开所有订阅，避免跨用例串扰。
	for info in get_signal_list():
		var name: StringName = info["name"]
		for connection in get_signal_connection_list(name):
			disconnect(name, connection["callable"])
