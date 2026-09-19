extends RefCounted
## ForageData 目录：野外可采集物种的唯一事实来源（V2 PRD 第 12 节采集系统 / M4）。
## 字段：label 显示名；sell_price 卖价；weight 在栖息地生成池中的权重；
## habitats 可生成栖息地（forest 森林 / orchard 果园 / mountain 山地 / lakeside 湖畔 / shore 海岸 / town 镇区）；
## seasons 出现季节（GameClock.SEASON_KEYS 子集）；weathers 出现天气（缺省为全部天气）；
## rarity 稀有度（common/uncommon/rare）。采集全天可用，因此不设时段字段。

const GameClock := preload("res://scripts/core/game_clock.gd")
const ALL_WEATHERS := ["sunny", "cloudy", "rain", "storm", "snow"]

const FORAGE := {
	"daffodil": {"label": "黄水仙", "sell_price": 6, "weight": 24, "habitats": ["forest", "town"], "seasons": ["spring"], "weathers": ALL_WEATHERS, "rarity": "common", "form": "flower"},
	"dandelion": {"label": "蒲公英", "sell_price": 5, "weight": 26, "habitats": ["forest", "lakeside", "town"], "seasons": ["spring"], "weathers": ALL_WEATHERS, "rarity": "common", "form": "flower"},
	"wild_radish": {"label": "野萝卜", "sell_price": 9, "weight": 20, "habitats": ["forest"], "seasons": ["spring"], "weathers": ALL_WEATHERS, "rarity": "common", "form": "root"},
	"leek": {"label": "韭葱", "sell_price": 11, "weight": 18, "habitats": ["mountain"], "seasons": ["spring"], "weathers": ALL_WEATHERS, "rarity": "common", "form": "root"},
	"sweet_pea": {"label": "甜豌豆", "sell_price": 7, "weight": 24, "habitats": ["lakeside", "town"], "seasons": ["summer"], "weathers": ALL_WEATHERS, "rarity": "common", "form": "flower"},
	"wild_berry": {"label": "野莓", "sell_price": 10, "weight": 22, "habitats": ["forest", "orchard"], "seasons": ["summer"], "weathers": ALL_WEATHERS, "rarity": "common", "form": "bush"},
	"mint": {"label": "薄荷", "sell_price": 13, "weight": 14, "habitats": ["lakeside"], "seasons": ["summer"], "weathers": ALL_WEATHERS, "rarity": "uncommon", "form": "root"},
	"mushroom": {"label": "野蘑菇", "sell_price": 12, "weight": 24, "habitats": ["forest"], "seasons": ["autumn"], "weathers": ALL_WEATHERS, "rarity": "common", "form": "mushroom"},
	"blackberry": {"label": "黑莓", "sell_price": 9, "weight": 22, "habitats": ["forest", "orchard"], "seasons": ["autumn"], "weathers": ALL_WEATHERS, "rarity": "common", "form": "bush"},
	"hazel": {"label": "榛子", "sell_price": 15, "weight": 14, "habitats": ["forest", "mountain"], "seasons": ["autumn"], "weathers": ALL_WEATHERS, "rarity": "uncommon", "form": "root"},
	"winter_root": {"label": "冬根", "sell_price": 12, "weight": 20, "habitats": ["mountain", "forest"], "seasons": ["winter"], "weathers": ALL_WEATHERS, "rarity": "common", "form": "root"},
	"crystal_fruit": {"label": "晶果", "sell_price": 32, "weight": 6, "habitats": ["mountain"], "seasons": ["winter"], "weathers": ALL_WEATHERS, "rarity": "rare", "form": "crystal"},
	"shell": {"label": "贝壳", "sell_price": 6, "weight": 26, "habitats": ["shore"], "seasons": GameClock.SEASON_KEYS, "weathers": ALL_WEATHERS, "rarity": "common", "form": "shell"},
	"cockle": {"label": "鸟蛤", "sell_price": 12, "weight": 14, "habitats": ["shore"], "seasons": ["spring", "summer", "autumn"], "weathers": ALL_WEATHERS, "rarity": "uncommon", "form": "shell"},
}
const ORDER := ["daffodil", "dandelion", "wild_radish", "leek", "sweet_pea", "wild_berry", "mint", "mushroom", "blackberry", "hazel", "winter_root", "crystal_fruit", "shell", "cockle"]
const HABITATS := ["forest", "orchard", "mountain", "lakeside", "shore", "town"]


static func label(kind: String) -> String:
	return FORAGE[kind]["label"]


static func sell_price(kind: String) -> int:
	return int(FORAGE[kind]["sell_price"])


static func form(kind: String) -> String:
	return FORAGE[kind]["form"]


static func rarity(kind: String) -> String:
	return FORAGE[kind]["rarity"]


static func seasons_of(kind: String) -> Array:
	return FORAGE[kind]["seasons"]


static func eligible(kind: String, habitat: String, context: Dictionary = {}) -> bool:
	if not FORAGE.has(kind) or not _valid_context(context):
		return false
	var entry: Dictionary = FORAGE[kind]
	if habitat not in entry["habitats"]:
		return false
	if context.has("season") and context["season"] not in entry["seasons"]:
		return false
	if context.has("weather") and context["weather"] not in entry["weathers"]:
		return false
	return true


static func available(habitat: String, context: Dictionary = {}) -> Array[String]:
	var result: Array[String] = []
	for kind: String in ORDER:
		if eligible(kind, habitat, context):
			result.append(kind)
	return result


## 栖息地选择权重：等于该栖息地当季可采物种的权重和，物种多的栖息地自然更常被选中。
static func habitat_weights(context: Dictionary = {}) -> Dictionary:
	var result := {}
	for habitat: String in HABITATS:
		var total := 0
		for kind: String in available(habitat, context):
			total += int(FORAGE[kind]["weight"])
		if total > 0:
			result[habitat] = total
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
			_:
				return false
	return true


## 从某栖息地的当季物种池抽一种（权重随机；rng 可注入以便测试）。
static func roll(habitat: String, rng: RandomNumberGenerator, context: Dictionary = {}) -> String:
	var pool := available(habitat, context)
	var total := 0
	for kind: String in pool:
		total += int(FORAGE[kind]["weight"])
	if pool.is_empty() or total <= 0:
		return ""
	var ticket := rng.randi_range(1, total)
	for kind: String in pool:
		ticket -= int(FORAGE[kind]["weight"])
		if ticket <= 0:
			return kind
	return pool[0]


## 抽一个栖息地再抽物种，返回 {"kind","habitat"}；无任何可采物种时返回空表。
static func roll_anywhere(rng: RandomNumberGenerator, context: Dictionary = {}) -> Dictionary:
	var weights := habitat_weights(context)
	if weights.is_empty():
		return {}
	var total := 0
	for habitat: String in weights:
		total += weights[habitat]
	var ticket := rng.randi_range(1, total)
	var chosen: String = weights.keys()[0]
	for habitat: String in weights:
		ticket -= weights[habitat]
		if ticket <= 0:
			chosen = habitat
			break
	var kind := roll(chosen, rng, context)
	return {} if kind.is_empty() else {"kind": kind, "habitat": chosen}
