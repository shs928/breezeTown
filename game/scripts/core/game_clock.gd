extends RefCounted
## 全局游戏时钟：日期、时刻、季节与天气的唯一事实来源（V2 PRD 第 20/21/22 节）。
## 纯数据逻辑，不依赖任何 Node；日切结算编排由主场景完成，本类只负责时间数学。

const HOURS_PER_DAY := 20.0  # 每天 06:00 开始，26:00（次日 02:00）日切
const DAY_START_HOUR := 6.0
const SEASON_LENGTH := 28
const SEASON_NAMES := ["春季", "夏季", "秋季", "冬季"]
const WEEKDAY_NAMES := ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]
const WEATHERS := {"sunny": "晴", "cloudy": "多云", "rain": "雨", "storm": "暴风雨", "snow": "雪"}

var day := 1
var hours := 8.0  # 当日时刻，取值 [DAY_START_HOUR, DAY_START_HOUR + HOURS_PER_DAY)
var weather := "sunny"


func advance(delta_hours: float) -> bool:
	## 推进时间；返回 true 表示发生日切（调用方需完成日结算并发事件）。
	hours += delta_hours
	if hours >= DAY_START_HOUR + HOURS_PER_DAY:
		hours -= HOURS_PER_DAY
		day += 1
		return true
	return false


func sleep_to_next_day() -> void:
	hours = DAY_START_HOUR
	day += 1


func season_index() -> int:
	return (day - 1) / SEASON_LENGTH % SEASON_NAMES.size()


func season() -> String:
	return SEASON_NAMES[season_index()]


func weekday() -> String:
	return WEEKDAY_NAMES[(day - 1) % WEEKDAY_NAMES.size()]


func weather_label() -> String:
	return WEATHERS.get(weather, weather)


func set_weather(kind: String) -> void:
	if kind == weather:
		return
	weather = kind
	EventBus.instance().weather_changed.emit(kind)


func clock_text() -> String:
	var hour := int(hours) % 24
	var minute := int(fmod(hours, 1.0) * 60.0)
	return "%02d:%02d" % [hour, minute]


func to_dict() -> Dictionary:
	return {"day": day, "hours": hours, "weather": weather}


func from_dict(data: Dictionary) -> void:
	day = int(data.get("day", 1))
	hours = float(data.get("hours", DAY_START_HOUR + 2.0))
	weather = data.get("weather", "sunny")
