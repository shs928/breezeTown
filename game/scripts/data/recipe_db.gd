extends RefCounted
## RecipeData 目录：制作配方的唯一事实来源（V2 PRD 第 13 节）。
## 结构：id；inputs {item_id: 数量}；outputs {item_id: 数量}；time 加工秒数；
## required_station 需要的设施（workbench/kitchen/furnace/""）；unlock_level 解锁等级。
## 玩法接线安排在 M6（制作 + 加工 + 经济）；当前仅建立数据结构与校验，
## 首批配方示例（后续正式化）：
##   木材×10 + 石料×5 → 宝箱（workbench）
##   小麦×3 → 口粮（kitchen）

const RECIPES := []

const STATIONS := ["", "workbench", "kitchen", "furnace"]


static func get_recipe(id: String) -> Dictionary:
	for recipe in RECIPES:
		if recipe["id"] == id:
			return recipe
	return {}


static func recipes_for_station(station: String) -> Array:
	return RECIPES.filter(func(recipe: Dictionary): return recipe["required_station"] == station)


static func validate() -> Array[String]:
	## 目录自检：station 合法、产出可被 ItemDB 解释。返回问题列表。
	const ItemDB := preload("res://scripts/data/item_db.gd")
	var problems: Array[String] = []
	for recipe in RECIPES:
		if recipe["required_station"] not in STATIONS:
			problems.append("%s: 未知设施 %s" % [recipe["id"], recipe["required_station"]])
		for output in recipe["outputs"]:
			if ItemDB.item(output).is_empty():
				problems.append("%s: 未知产出物品 %s" % [recipe["id"], output])
	return problems
