extends SceneTree

const GameClock := preload("res://scripts/core/game_clock.gd")

var failures: Array[String] = []
var count := 0


func _initialize() -> void:
	_schedule()
	_day_progression()
	_overrides_and_load()
	_events()
	print("WEATHER_RESULT %s %d checks" % ["PASS" if failures.is_empty() else "FAIL " + ",".join(failures), count])
	quit(0 if failures.is_empty() else 1)


func _schedule() -> void:
	var clock := GameClock.new()
	_check("first-day-is-sunny", clock.day == 1 and clock.weather == "sunny")
	var first_week := ["sunny", "cloudy", "rain", "sunny", "sunny", "storm", "cloudy"]
	for index in range(first_week.size()):
		_check("first-week-day-%d" % (index + 1), GameClock.weather_for_day(index + 1) == first_week[index])
	var seen := {}
	var winter_safe := true
	var deterministic := true
	var valid := true
	for day in range(1, 113):
		var weather: String = GameClock.weather_for_day(day)
		seen[weather] = true
		deterministic = deterministic and weather == GameClock.weather_for_day(day)
		valid = valid and GameClock.WEATHERS.has(weather)
		if day >= 85:
			winter_safe = winter_safe and weather not in ["rain", "storm"]
	_check("calendar-produces-all-five-weathers", seen.size() == 5)
	_check("scheduled-weather-is-valid-and-repeatable", valid and deterministic)
	_check("winter-replaces-rain-and-storm", winter_safe)


func _day_progression() -> void:
	var same_weather := true
	var correct_dates := true
	for day in range(1, 113):
		var natural := GameClock.new()
		var sleeping := GameClock.new()
		var stored := {"day": day, "hours": 25.9, "weather": "snow"}
		natural.from_dict(stored)
		sleeping.from_dict(stored)
		var rolled: bool = natural.advance(0.2)
		sleeping.sleep_to_next_day()
		correct_dates = correct_dates and rolled and natural.day == day + 1 and sleeping.day == day + 1 and is_equal_approx(natural.hours, 6.1) and sleeping.hours == 6.0
		same_weather = same_weather and natural.weather == sleeping.weather and natural.weather == GameClock.weather_for_day(day + 1)
	_check("natural-and-sleep-rollovers-advance-calendar", correct_dates)
	_check("natural-and-sleep-rollovers-use-same-weather", same_weather)
	var clock := GameClock.new()
	var unchanged := true
	for step in range(16):
		unchanged = unchanged and not clock.advance(0.5) and clock.day == 1 and clock.weather == "sunny"
	_check("weather-does-not-change-within-day", unchanged)
	var before := clock.to_dict()
	var invalid_unchanged := true
	for delta in [0.0, -1.0, INF, -INF, NAN]:
		invalid_unchanged = invalid_unchanged and not clock.advance(delta) and clock.to_dict() == before
	_check("invalid-deltas-do-not-advance-time", invalid_unchanged)


func _overrides_and_load() -> void:
	var clock := GameClock.new()
	clock.set_weather("storm")
	clock.advance(4.0)
	_check("manual-weather-persists-during-day", clock.weather == "storm" and clock.day == 1)
	clock.sleep_to_next_day()
	_check("next-day-replaces-manual-weather", clock.day == 2 and clock.weather == "cloudy")
	clock.from_dict({"day": 3, "hours": 15.5, "weather": "snow"})
	_check("load-preserves-stored-weather-and-time", clock.day == 3 and clock.hours == 15.5 and clock.weather == "snow")
	clock.advance(1.0)
	_check("loaded-weather-persists-during-day", clock.day == 3 and clock.weather == "snow")
	var copy := GameClock.new()
	copy.from_dict(clock.to_dict())
	_check("weather-survives-save-roundtrip", copy.day == 3 and copy.hours == 16.5 and copy.weather == "snow")
	clock.sleep_to_next_day()
	_check("day-after-load-uses-calendar-weather", clock.day == 4 and clock.weather == "sunny")
	clock.from_dict({"day": 3, "hours": 12.0})
	_check("old-save-without-weather-uses-calendar", clock.weather == "rain")
	clock.from_dict({"day": 2, "weather": "invalid-weather"})
	_check("invalid-saved-weather-uses-calendar", clock.weather == "cloudy")


func _events() -> void:
	var observed: Array[String] = []
	var on_weather := func(kind: String): observed.append(kind)
	EventBus.instance().weather_changed.connect(on_weather)
	var clock := GameClock.new()
	clock.set_weather("sunny")
	clock.set_weather("invalid-weather")
	clock.advance(1.0)
	_check("unchanged-or-invalid-weather-emits-nothing", observed.is_empty() and clock.weather == "sunny")
	clock.set_weather("rain")
	clock.set_weather("rain")
	_check("manual-change-emits-exactly-once", observed == ["rain"])
	observed.clear()
	clock.from_dict({"day": 1, "hours": 25.9, "weather": "sunny"})
	_check("restore-does-not-reemit-weather-change", observed.is_empty())
	clock.advance(0.2)
	_check("natural-change-emits-exactly-once", observed == ["cloudy"])
	observed.clear()
	clock.sleep_to_next_day()
	_check("sleep-change-emits-exactly-once", observed == ["rain"])
	observed.clear()
	clock.from_dict({"day": 4, "hours": 25.9, "weather": "sunny"})
	clock.advance(0.2)
	_check("same-weather-day-rollover-emits-nothing", clock.day == 5 and observed.is_empty())
	clock.from_dict({"day": 1, "hours": 25.9, "weather": "sunny"})
	clock.advance(20.2)
	_check("multi-day-jump-uses-final-calendar-weather", clock.day == 3 and is_equal_approx(clock.hours, 6.1) and clock.weather == "rain")
	_check("multi-day-jump-emits-one-final-change", observed == ["rain"])
	EventBus.instance().weather_changed.disconnect(on_weather)


func _check(label: String, result: bool) -> void:
	count += 1
	print("WEATHER %s %s" % [label, "OK" if result else "FAIL"])
	if not result:
		failures.append(label)
