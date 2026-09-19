extends RefCounted
## RecipeData 目录：制作/加工配方的唯一事实来源（V2 PRD 第 13 节）。
## 字段：id；label 显示名；inputs {item_id: 数量}；outputs {item_id: 数量}；
## time 加工时长（游戏小时）；required_station 需要的设施（与 interior_db 的机器 kind 一致）。
## PROCESS-01（INDOOR-02）首批接线：熔炉熔锭、奶酪压榨、蛋黄酱（设施在铁匠铺/谷仓/鸡舍室内）。

const RECIPES := [
	{"id": "smelt_copper", "label": "铜锭", "required_station": "furnace", "inputs": {"copper": 4}, "outputs": {"copper_bar": 1}, "time": 2.0},
	{"id": "smelt_iron", "label": "铁锭", "required_station": "furnace", "inputs": {"iron": 4}, "outputs": {"iron_bar": 1}, "time": 3.0},
	{"id": "press_cheese", "label": "奶酪", "required_station": "cheese_press", "inputs": {"milk": 1}, "outputs": {"cheese": 1}, "time": 8.0},
	{"id": "make_mayo", "label": "蛋黄酱", "required_station": "mayo_maker", "inputs": {"egg": 1}, "outputs": {"mayonnaise": 1}, "time": 4.0},
	{"id": "craft_chest", "label": "宝箱", "required_station": "workbench", "inputs": {"wood": 10, "stone": 5}, "outputs": {"chest": 1}, "time": 2.0},
	{"id": "recycle_fertilizer", "label": "肥料", "required_station": "workbench", "inputs": {"wood": 6}, "outputs": {"fertilizer": 2}, "time": 1.0},
	{"id": "expand_warehouse", "label": "仓库扩容", "required_station": "workbench", "inputs": {"wood": 15, "stone": 10}, "outputs": {"warehouse_expansion": 1}, "time": 4.0},
	{"id": "bake_bread", "label": "面包", "required_station": "kitchen", "inputs": {"wheat": 3}, "outputs": {"bread": 1}, "time": 3.0},
	{"id": "weave_blanket", "label": "毛毯", "required_station": "loom", "inputs": {"wool": 3}, "outputs": {"blanket": 1}, "time": 6.0},
]

const STATIONS := ["", "workbench", "kitchen", "furnace", "cheese_press", "mayo_maker", "loom"]


static func get_recipe(id: String) -> Dictionary:
	for recipe in RECIPES:
		if recipe["id"] == id:
			return recipe
	return {}


static func recipes_for_station(station: String) -> Array:
	return RECIPES.filter(func(recipe: Dictionary): return recipe["required_station"] == station)


static func requirements_text(station: String) -> String:
	## 机器空转时的原料提示："铜矿石×4 / 铁矿石×4"。
	const ItemDB := preload("res://scripts/data/item_db.gd")
	var parts: Array[String] = []
	for recipe: Dictionary in recipes_for_station(station):
		var need: Array[String] = []
		for item in recipe["inputs"]:
			need.append("%s×%d" % [ItemDB.label(item), int(recipe["inputs"][item])])
		parts.append("、".join(need))
	return " / ".join(parts)


static func validate() -> Array[String]:
	## 目录自检：station 合法、产出可被 ItemDB 解释、数量与时长为正。返回问题列表。
	const ItemDB := preload("res://scripts/data/item_db.gd")
	var problems: Array[String] = []
	for recipe in RECIPES:
		if recipe["required_station"] not in STATIONS:
			problems.append("%s: 未知设施 %s" % [recipe["id"], recipe["required_station"]])
		if float(recipe["time"]) <= 0.0:
			problems.append("%s: 加工时长必须为正" % recipe["id"])
		for input in recipe["inputs"]:
			if ItemDB.item(input).is_empty():
				problems.append("%s: 未知原料 %s" % [recipe["id"], input])
			if int(recipe["inputs"][input]) <= 0:
				problems.append("%s: 原料数量必须为正 %s" % [recipe["id"], input])
		for output in recipe["outputs"]:
			if ItemDB.item(output).is_empty():
				problems.append("%s: 未知产出物品 %s" % [recipe["id"], output])
			if int(recipe["outputs"][output]) <= 0:
				problems.append("%s: 产出数量必须为正 %s" % [recipe["id"], output])
	return problems
