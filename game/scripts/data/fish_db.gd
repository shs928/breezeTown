extends RefCounted
## FishData 目录：鱼类定义的唯一事实来源（V2 PRD M4 钓鱼）。
## 字段：label 显示名；sell_price 卖价；difficulty 咬钩与张力难度（1–3）；
## weight 在鱼获池中的权重；waters 可钓水域类型（lake/river，两者皆可写两个）。
## hours 是左闭右开的 [开始, 结束] 时段，跨午夜时开始值大于结束值。

const GameClock := preload("res://scripts/core/game_clock.gd")
const ALL_WEATHERS := ["sunny", "cloudy", "rain", "storm", "snow"]

const FISH := {
	"sardine": {"label": "沙丁鱼", "sell_price": 6, "difficulty": 1, "weight": 30, "waters": ["lake", "river"], "seasons": GameClock.SEASON_KEYS, "weathers": ALL_WEATHERS, "hours": [0.0, 24.0], "rarity": "common", "behavior": "steady"},
	"carp": {"label": "鲤鱼", "sell_price": 12, "difficulty": 1, "weight": 24, "waters": ["lake"], "seasons": GameClock.SEASON_KEYS, "weathers": ALL_WEATHERS, "hours": [6.0, 20.0], "rarity": "common", "behavior": "steady"},
	"perch": {"label": "河鲈", "sell_price": 14, "difficulty": 2, "weight": 18, "waters": ["river"], "seasons": ["spring", "summer", "autumn"], "weathers": ALL_WEATHERS, "hours": [6.0, 19.0], "rarity": "uncommon", "behavior": "dart"},
	"catfish": {"label": "鲶鱼", "sell_price": 22, "difficulty": 2, "weight": 10, "waters": ["river", "lake"], "seasons": ["spring", "summer", "autumn"], "weathers": ["rain", "storm"], "hours": [18.0, 2.0], "rarity": "uncommon", "behavior": "surge"},
	"rainbow_trout": {"label": "虹鳟", "sell_price": 30, "difficulty": 3, "weight": 6, "waters": ["river"], "seasons": ["autumn", "winter"], "weathers": ALL_WEATHERS, "hours": [6.0, 18.0], "rarity": "rare", "behavior": "dart"},
	"koi": {"label": "锦鲤", "sell_price": 45, "difficulty": 3, "weight": 4, "waters": ["lake"], "seasons": ["spring", "summer"], "weathers": ["sunny", "cloudy"], "hours": [9.0, 17.0], "rarity": "rare", "behavior": "surge"},
}
const ORDER := ["sardine", "carp", "perch", "catfish", "rainbow_trout", "koi"]


static func label(kind: String) -> String:
	return FISH[kind]["label"]


static func sell_price(kind: String) -> int:
	return int(FISH[kind]["sell_price"])


static func difficulty(kind: String) -> int:
	return int(FISH[kind]["difficulty"])


static func behavior(kind: String) -> String:
	return FISH[kind]["behavior"]


static func supports_water(water_kind: String) -> bool:
	for kind in ORDER:
		if water_kind in FISH[kind]["waters"]:
			return true
	return false


static func eligible(kind: String, water: String, context: Dictionary = {}) -> bool:
	if not FISH.has(kind) or not _valid_context(context):
		return false
	var fish: Dictionary = FISH[kind]
	if water not in fish["waters"]:
		return false
	if context.has("season") and context["season"] not in fish["seasons"]:
		return false
	if context.has("weather") and context["weather"] not in fish["weathers"]:
		return false
	if context.has("hour"):
		var hour := fmod(float(context["hour"]), 24.0)
		var start: float = fish["hours"][0]
		var end: float = fish["hours"][1]
		if start < end:
			return hour >= start and hour < end
		return hour >= start or hour < end
	return true


static func available(water: String, context: Dictionary = {}) -> Array[String]:
	var result: Array[String] = []
	for kind: String in ORDER:
		if eligible(kind, water, context):
			result.append(kind)
	return result


static func _valid_context(context: Dictionary) -> bool:
	for key in context:
		match key:
			"season":
				if context[key] not in GameClock.SEASON_KEYS:
					return false
			"weather":
				if not GameClock.WEATHERS.has(context[key]):
					return false
			"hour":
				var hour = context[key]
				if not (hour is int or hour is float) or not is_finite(float(hour)) or hour < 0.0 or hour > 26.0:
					return false
			_:
				return false
	return true


## 从指定水域类型的鱼获池抽一种鱼（权重随机；rng 可注入以便测试）。
static func roll(water_kind: String, rng: RandomNumberGenerator, context: Dictionary = {}) -> String:
	var pool := available(water_kind, context)
	var total := 0
	for kind: String in pool:
		total += int(FISH[kind]["weight"])
	if pool.is_empty() or total <= 0:
		return ""
	var ticket := rng.randi_range(1, total)
	for kind: String in pool:
		ticket -= int(FISH[kind]["weight"])
		if ticket <= 0:
			return kind
	return pool[0]
