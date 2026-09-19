extends RefCounted
## 全局游戏时钟：日期、时刻、季节与天气的唯一事实来源（V2 PRD 第 20/21/22 节）。
## 纯数据逻辑，不依赖任何 Node；日切结算编排由主场景完成，本类只负责时间数学。

const HOURS_PER_DAY := 20.0  # 每天 06:00 开始，26:00（次日 02:00）日切
const DAY_START_HOUR := 6.0
const SEASON_LENGTH := 28
const SEASON_KEYS := ["spring", "summer", "autumn", "winter"]
const SEASON_NAMES := ["春季", "夏季", "秋季", "冬季"]
const WEEKDAY_NAMES := ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]
const WEATHERS := {"sunny": "晴", "cloudy": "多云", "rain": "雨", "storm": "暴风雨", "snow": "雪"}
const WEATHER_CYCLE := ["sunny", "cloudy", "rain", "sunny", "sunny", "storm", "cloudy"]

var day := 1
var hours := 8.0  # 当日时刻，取值 [DAY_START_HOUR, DAY_START_HOUR + HOURS_PER_DAY)
var weather := "sunny"


func advance(delta_hours: float) -> bool:
	## 推进时间；返回 true 表示发生日切（调用方需完成日结算并发事件）。
	if not is_finite(delta_hours) or delta_hours <= 0.0:
		return false
	hours += delta_hours
	if hours >= DAY_START_HOUR + HOURS_PER_DAY:
		var crossed_days := floori((hours - DAY_START_HOUR) / HOURS_PER_DAY)
		hours -= crossed_days * HOURS_PER_DAY
		day += crossed_days
		set_weather(weather_for_day(day))
		return true
	return false


func sleep_to_next_day() -> void:
	hours = DAY_START_HOUR
	day += 1
	set_weather(weather_for_day(day))


static func weather_for_day(calendar_day: int) -> String:
	var safe_day := maxi(1, calendar_day)
	var kind: String = WEATHER_CYCLE[(safe_day - 1) % WEATHER_CYCLE.size()]
	var season: int = ((safe_day - 1) / SEASON_LENGTH) % SEASON_KEYS.size()
	if season == 3 and kind in ["rain", "storm"]:
		return "snow"
	return kind


static func is_rainy(kind: String) -> bool:
	## POLISH-01：该天气是否浇灌耕地（雪不浇——冬季作物枯萎，规则无歧义）。
	return kind == "rain" or kind == "storm"


func season_index() -> int:
	return (day - 1) / SEASON_LENGTH % SEASON_NAMES.size()


func season() -> String:
	return SEASON_NAMES[season_index()]


func season_key() -> String:
	## 数据层季节键（crop_db.gd 的 season 字段口径）；season() 是中文显示名。
	return SEASON_KEYS[season_index()]


func weekday() -> String:
	return WEEKDAY_NAMES[(day - 1) % WEEKDAY_NAMES.size()]


func weather_label() -> String:
	return WEATHERS.get(weather, weather)


func set_weather(kind: String) -> void:
	if not WEATHERS.has(kind) or kind == weather:
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
	var saved_weather: String = str(data.get("weather", weather_for_day(day)))
	weather = saved_weather if WEATHERS.has(saved_weather) else weather_for_day(day)
