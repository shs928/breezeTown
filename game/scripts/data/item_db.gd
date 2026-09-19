extends RefCounted
## ItemData 目录：全部物品的唯一事实来源（V2 PRD 第 16/17 节）。
## id 命名：seed_<crop> 种子；其余与产物/资源 id 相同。
## 字段：label 显示名；type 物品类型；buy/sell 单价（-1 表示不可买/卖）；stack 最大堆叠。
## 作物与动物产品的价格引自 CropDB / AnimalDB，本表不重复维护数值。

const CropDB := preload("res://scripts/data/crop_db.gd")
const AnimalDB := preload("res://scripts/data/animal_db.gd")
const FishDB := preload("res://scripts/data/fish_db.gd")
const ForageDB := preload("res://scripts/data/forage_db.gd")

const MINERALS := {
	"stone": {"label": "石料", "sell_price": 1},
	"copper": {"label": "铜矿石", "sell_price": 5},
	"iron": {"label": "铁矿石", "sell_price": 9},
	"coal": {"label": "煤炭", "sell_price": 4},
	"crystal": {"label": "水晶", "sell_price": 18},
	"slime": {"label": "史莱姆凝胶", "sell_price": 3},
	"copper_bar": {"label": "铜锭", "sell_price": 25},
	"iron_bar": {"label": "铁锭", "sell_price": 45},
}
const MINERAL_ORDER := ["stone", "copper", "iron", "coal", "crystal", "slime", "copper_bar", "iron_bar"]

const FORESTRY := {
	"wood": {"label": "木材", "sell_price": 2},
	"sapling": {"label": "树苗", "sell_price": -1},
}

const PRODUCTS := {
	"milk": {"label": "牛奶", "sell_price": 14},
	"wool": {"label": "羊毛", "sell_price": 10},
	"egg": {"label": "鸡蛋", "sell_price": 5},
	"cheese": {"label": "奶酪", "sell_price": 32},
	"mayonnaise": {"label": "蛋黄酱", "sell_price": 12},
	"bread": {"label": "面包", "sell_price": 24},
	"blanket": {"label": "毛毯", "sell_price": 48},
}
const PRODUCT_ORDER := ["milk", "wool", "egg", "cheese", "mayonnaise", "bread", "blanket"]

const TYPE_SEED := "seed"
const TYPE_CROP := "crop"
const TYPE_RESOURCE := "resource"
const TYPE_TOOL := "tool"
const TYPE_ANIMAL_PRODUCT := "animal_product"
const TYPE_FORAGE := "forage"  # GATHER-01：野外采集物

static var ITEMS: Dictionary = _build()


static func _build() -> Dictionary:
	var table := {}
	for kind in CropDB.CROPS:
		var crop: Dictionary = CropDB.CROPS[kind]
		table["seed_" + kind] = {"label": crop["label"] + "种子", "type": TYPE_SEED, "buy": crop["seed_price"], "sell": -1, "stack": 999}
		table[kind] = {"label": crop["label"], "type": TYPE_CROP, "buy": -1, "sell": crop["sell_price"], "stack": 999}
	for kind in PRODUCT_ORDER:
		table[kind] = {"label": PRODUCTS[kind]["label"], "type": TYPE_ANIMAL_PRODUCT, "buy": -1, "sell": PRODUCTS[kind]["sell_price"], "stack": 999}
	for kind in FishDB.ORDER:
		table[kind] = {"label": FishDB.label(kind), "type": "fish", "buy": -1, "sell": FishDB.sell_price(kind), "stack": 999}
	for kind in ForageDB.ORDER:
		table[kind] = {"label": ForageDB.label(kind), "type": TYPE_FORAGE, "buy": -1, "sell": ForageDB.sell_price(kind), "stack": 999}
	for kind in MINERAL_ORDER:
		table[kind] = {"label": MINERALS[kind]["label"], "type": TYPE_RESOURCE, "buy": -1, "sell": MINERALS[kind]["sell_price"], "stack": 999}
	for kind in FORESTRY:
		table[kind] = {"label": FORESTRY[kind]["label"], "type": TYPE_RESOURCE, "buy": -1, "sell": FORESTRY[kind]["sell_price"], "stack": 999}
	# STORE-01：特殊物品——宝箱是放置物（不计六族背包，走 chests_ready 计数），
	# 肥料是纯计数器（state.fertilizer）；仅入目录供配方校验，不进商店/背包列表。
	# 肥料单价 8 与 GameState.FERTILIZER_PRICE 一致（此处不能反向引用避免循环预载）。
	table["chest"] = {"label": "宝箱", "type": "placeable", "buy": -1, "sell": -1, "stack": 99}
	table["fertilizer"] = {"label": "肥料", "type": "resource", "buy": 8, "sell": -1, "stack": 999}
	# STORE-02：仓库扩容为一次性消耗制作（state.warehouse_capacity +300）。
	table["warehouse_expansion"] = {"label": "仓库扩容", "type": "placeable", "buy": -1, "sell": -1, "stack": 99}
	for tool in ["hand", "hoe", "can", "seed", "fence", "pickaxe", "sword", "axe", "sapling", "rod"]:
		table["tool_" + tool] = {"label": tool, "type": TYPE_TOOL, "buy": -1, "sell": -1, "stack": 1}
	return table


static func item(id: String) -> Dictionary:
	return ITEMS.get(id, {})


static func label(id: String) -> String:
	return item(id).get("label", id)


static func sell_price(id: String) -> int:
	return int(item(id).get("sell", -1))


static func buy_price(id: String) -> int:
	return int(item(id).get("buy", -1))


static func item_type(id: String) -> String:
	return item(id).get("type", "")
