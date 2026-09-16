extends RefCounted
## 玩家/经营领域状态（PlayerState + 经济）：金币、背包计数、健康与游戏时钟。
## 纯数据类，不依赖任何 Node3D；数值定义统一引自 data/ 目录，时钟逻辑在 core/game_clock.gd。

const GameClock := preload("res://scripts/core/game_clock.gd")
const CropDB := preload("res://scripts/data/crop_db.gd")
const ItemDB := preload("res://scripts/data/item_db.gd")
const AnimalDB := preload("res://scripts/data/animal_db.gd")

## 兼容导出：旧代码以 GameState.XXX 类级访问的目录表（唯一来源在 data/）。
const CROPS := CropDB.CROPS
const CROP_ORDER := CropDB.ORDER
const PRODUCTS := ItemDB.PRODUCTS
const PRODUCT_ORDER := ItemDB.PRODUCT_ORDER
const MINERALS := ItemDB.MINERALS
const MINERAL_ORDER := ItemDB.MINERAL_ORDER
const ANIMALS := AnimalDB.ANIMALS
const ANIMAL_ORDER := AnimalDB.ORDER
const START_COINS := 20
const HOURS_PER_DAY := GameClock.HOURS_PER_DAY
const MAX_HEALTH := 100

var time := GameClock.new()
var coins: int = START_COINS
var seeds := {"radish": 6, "strawberry": 0, "wheat": 0, "pumpkin": 0}
var harvest := {"radish": 0, "strawberry": 0, "wheat": 0, "pumpkin": 0}
var products := {"milk": 0, "wool": 0, "egg": 0}
var ranch_unlocked := false
var health := MAX_HEALTH
var rations := 3
var minerals := {"stone": 0, "copper": 0, "iron": 0, "coal": 0, "crystal": 0, "slime": 0}
var forestry := {"wood": 0, "sapling": 0}
var deepest_mine_floor := 0
var mine_completed := false

## 时钟兼容接口：旧代码以 state.day / state.clock / state.advance_hour 直接访问。
var day: int:
	get: return time.day
	set(value): time.day = value
var clock: float:
	get: return time.hours
	set(value): time.hours = value


static func crop_label(kind: String) -> String:
	return CropDB.label(kind)


static func crop_field(kind: String, field: String) -> Variant:
	return CropDB.field(kind, field)


static func product_label(kind: String) -> String:
	return ItemDB.PRODUCTS[kind]["label"]


func season_label() -> String:
	return time.season()


func add_coins(amount: int) -> void:
	coins += amount
	EventBus.instance().money_changed.emit(coins, amount)


func take_seed(kind: String, count: int = 1) -> bool:
	## 扣除种子并在不足时失败；统一入口保证背包事件与数值一致。
	if seeds[kind] < count:
		return false
	seeds[kind] -= count
	EventBus.instance().item_removed.emit("seed_" + kind, count)
	return true


func add_harvest(kind: String, count: int = 1) -> void:
	harvest[kind] += count
	EventBus.instance().item_added.emit(kind, count)


func add_product(kind: String, count: int = 1) -> void:
	products[kind] += count
	EventBus.instance().item_added.emit(kind, count)


func buy_seed(kind: String, count: int) -> bool:
	var cost: int = CropDB.field(kind, "seed_price") * count
	if coins < cost:
		return false
	coins -= cost
	seeds[kind] += count
	EventBus.instance().money_changed.emit(coins, -cost)
	EventBus.instance().item_added.emit("seed_" + kind, count)
	return true


func sell_all_harvest() -> int:
	var earned := 0
	for kind in harvest:
		earned += harvest[kind] * CropDB.field(kind, "sell_price")
		if harvest[kind] > 0:
			EventBus.instance().item_removed.emit(kind, harvest[kind])
		harvest[kind] = 0
	for kind in products:
		earned += products[kind] * ItemDB.PRODUCTS[kind]["sell_price"]
		if products[kind] > 0:
			EventBus.instance().item_removed.emit(kind, products[kind])
		products[kind] = 0
	coins += earned
	if earned > 0:
		EventBus.instance().money_changed.emit(coins, earned)
	return earned


func advance_hour(delta_hours: float) -> bool:
	## 返回 true 表示发生了日切（调用方需结算生长并广播日事件）。
	return time.advance(delta_hours)


func sleep_to_next_day() -> void:
	time.sleep_to_next_day()
	health = MAX_HEALTH
	rations = maxi(rations, 3)


func eat_ration() -> int:
	if rations <= 0 or health >= MAX_HEALTH:
		return 0
	rations -= 1
	var restored := mini(35, MAX_HEALTH - health)
	health += restored
	EventBus.instance().item_removed.emit("ration", 1)
	return restored


func clock_text() -> String:
	return time.clock_text()


func to_dict() -> Dictionary:
	return {
		"coins": coins, "seeds": seeds, "harvest": harvest, "products": products,
		"health": health, "rations": rations, "minerals": minerals, "forestry": forestry,
		"deepest_mine_floor": deepest_mine_floor, "mine_completed": mine_completed,
	}


func from_dict(data: Dictionary) -> void:
	coins = int(data.get("coins", START_COINS))
	for table_key in ["seeds", "harvest", "products", "minerals", "forestry"]:
		var saved: Dictionary = data.get(table_key, {})
		for kind in get(table_key):
			if saved.has(kind):
				get(table_key)[kind] = int(saved[kind])
	health = int(data.get("health", MAX_HEALTH))
	rations = int(data.get("rations", 3))
	deepest_mine_floor = int(data.get("deepest_mine_floor", 0))
	mine_completed = bool(data.get("mine_completed", false))
