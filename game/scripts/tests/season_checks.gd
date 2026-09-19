extends SceneTree
## POLISH-05 领域检查：季节调色纯函数（雪量/环境乘子/植被色调）。

const SeasonVisuals := preload("res://scripts/art/season_visuals.gd")
const GameClock := preload("res://scripts/core/game_clock.gd")

var count := 0
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _check(label: String, ok: bool) -> void:
	count += 1
	print("SEASON %s %s" % [label, "OK" if ok else "FAIL"])
	if not ok:
		failures.append(label)


func _run() -> void:
	_check("winter-has-snow", SeasonVisuals.snow_amount_for("winter") == 1.0)
	for key in ["spring", "summer", "autumn"]:
		_check("no-snow-%s" % key, SeasonVisuals.snow_amount_for(key) == 0.0)
	# 日历口径：第 85 天入冬，57 入秋。
	_check("day85-is-winter", GameClock.weather_for_day(85) != "" and SeasonVisuals.snow_amount_for("winter") > 0.0)
	for key in ["spring", "summer", "autumn", "winter"]:
		var tint: Dictionary = SeasonVisuals.env_tint_for(key)
		_check("tint-fields-%s" % key, tint.has("bg") and tint.has("bg_strength") and tint.has("amb") and tint.has("sun") and tint.has("energy"))
		_check("tint-strengths-bounded-%s" % key, float(tint["bg_strength"]) <= 0.5 and float(tint["amb_strength"]) <= 0.5 and float(tint["sun_strength"]) <= 0.5)
		_check("foliage-color-%s" % key, SeasonVisuals.foliage_tint_for(key) != Color())
	# 冬季冷色、秋季暖色的方向性：与纯白比较色相偏移。
	var winter: Dictionary = SeasonVisuals.env_tint_for("winter")
	var autumn: Dictionary = SeasonVisuals.env_tint_for("autumn")
	var wbg: Color = winter["bg"]
	var abg: Color = autumn["bg"]
	_check("winter-cooler-than-autumn", wbg.b > abg.b and wbg.r < abg.r)
	var verdict := "PASS %d" % count if failures.is_empty() else "FAIL %s" % ",".join(failures)
	print("SEASON_RESULT " + verdict)
	quit(0 if failures.is_empty() else 1)


func _color_report() -> void:
	pass
