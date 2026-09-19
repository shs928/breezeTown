extends RefCounted
## 玩家/经营领域状态（PlayerState + 经济）：金币、背包计数、健康与游戏时钟。
## 纯数据类，不依赖任何 Node3D；数值定义统一引自 data/ 目录，时钟逻辑在 core/game_clock.gd。

const GameClock := preload("res://scripts/core/game_clock.gd")
const CropDB := preload("res://scripts/data/crop_db.gd")
const ItemDB := preload("res://scripts/data/item_db.gd")
const AnimalDB := preload("res://scripts/data/animal_db.gd")
const FishDB := preload("res://scripts/data/fish_db.gd")
const ForageDB := preload("res://scripts/data/forage_db.gd")
const NpcDB := preload("res://scripts/data/npc_db.gd")
const QuestDB := preload("res://scripts/data/quest_db.gd")
const InteriorDB := preload("res://scripts/data/interior_db.gd")

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
const MAX_ENERGY := 100  # FARM-01：体力上限；工具动作消耗，睡觉回满
const MAX_FISHING_LEVEL := 10
const MAX_FISH_COUNT := 1000000
const FEED_PRICE := 8  # 饲料单价；一份填满一个食槽一夜
const RATION_PRICE := 12
const FERTILIZER_PRICE := 8  # FARM-01 二轮：肥料；播种时自动消耗，当日生长+1
const TOOL_UPGRADE_COSTS := {  # 等级 1→2→3 的金币+矿物造价；效果：体力消耗 ×1.0/0.6/0.3
	"hoe": [{"coins": 300, "copper": 4}, {"coins": 1200, "iron": 6}],
	"can": [{"coins": 250, "copper": 3}, {"coins": 1000, "iron": 5}],
	"pickaxe": [{"coins": 350, "copper": 5}, {"coins": 1400, "iron": 7}],
	"axe": [{"coins": 350, "copper": 5}, {"coins": 1400, "iron": 7}],
}
const TOOL_ENERGY_COSTS := {"hoe": 2.0, "seed": 0.5, "can": 1.0, "pickaxe": 2.0, "axe": 2.0, "sword": 1.0, "rod": 5.0}
const BUILDING_UPGRADE_COSTS := {  # FARM-01 二轮：建筑扩容（金币+木材+石料）
	"barn": {"coins": 800, "wood": 20, "stone": 10},
	"coop": {"coins": 500, "wood": 12, "stone": 6},
}

var time := GameClock.new()
var coins: int = START_COINS
var seeds := {"radish": 6, "strawberry": 0, "wheat": 0, "pumpkin": 0}
var harvest := {"radish": 0, "strawberry": 0, "wheat": 0, "pumpkin": 0}
var fish := {"sardine": 0, "carp": 0, "perch": 0, "catfish": 0, "rainbow_trout": 0, "koi": 0}  # LIFE-01 钓鱼
var fish_quality := {"silver": {"sardine": 0, "carp": 0, "perch": 0, "catfish": 0, "rainbow_trout": 0, "koi": 0}, "gold": {"sardine": 0, "carp": 0, "perch": 0, "catfish": 0, "rainbow_trout": 0, "koi": 0}}
var forage: Dictionary = _zero_forage()  # GATHER-01：采集物库存，键见 ForageDB.ORDER
var fishing_level := 1
var fishing_xp := 0
var harvest_quality := {"silver": {"radish": 0, "strawberry": 0, "wheat": 0, "pumpkin": 0}, "gold": {"radish": 0, "strawberry": 0, "wheat": 0, "pumpkin": 0}}
var products := {"milk": 0, "wool": 0, "egg": 0, "cheese": 0, "mayonnaise": 0, "bread": 0, "blanket": 0}
var chests_ready := 0  # STORE-01：已制作待放置的宝箱
var warehouse := {}  # STORE-01：农场共享仓库（六族物品 id → 数量），所有宝箱连通
var warehouse_capacity := 300  # STORE-02：仓库总件数上限，工作台"仓库扩容"每级 +300
var ranch_unlocked := false
var health := MAX_HEALTH
var energy := MAX_ENERGY  # FARM-01：体力
var feed := 4  # 饲料库存；一份可填满一个食槽一夜
var fertilizer := 2  # FARM-01 二轮：肥料库存
var rations := 3
var minerals := {"stone": 0, "copper": 0, "iron": 0, "coal": 0, "crystal": 0, "slime": 0, "copper_bar": 0, "iron_bar": 0}
var forestry := {"wood": 0, "sapling": 0}
var deepest_mine_floor := 0
var mine_completed := false
var tool_levels := {"hoe": 1, "can": 1, "pickaxe": 1, "axe": 1}  # FARM-01：工具等级
var xp := 0  # FARM-01 二轮：收获/拾取产出积累经验
var level := 1
var building_levels := {"barn": 1, "coop": 1}  # 谷仓容量=4×等级（牛羊），鸡舍=6×等级（鸡）
var npc_friendship: Dictionary = _zero_npc()  # NPC-01：好感 0–1000
var npc_last_talk: Dictionary = _zero_npc()  # 每日首次对话才有好感，记录上次对话日
var npc_last_gift: Dictionary = _zero_npc()  # 每日最多送一份礼
var quests_accepted: Dictionary = {}  # QUEST-01：委托 id → 接受日
var quests_completed: Dictionary = {}  # 委托 id → 完成日

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


func add_product(kind: String, count: int = 1) -> void:
	products[kind] += count
	EventBus.instance().item_added.emit(kind, count)


func add_mineral(kind: String, count: int = 1) -> void:
	## PROCESS-01：矿石族产出（熔炉锭等）与挖矿掉落共用库存与事件口径。
	minerals[kind] += count
	EventBus.instance().item_added.emit(kind, count)


## ---- STORE-01：农场共享仓库（所有宝箱连通同一仓库；整批存取） ----

func is_storable(item: String) -> bool:
	## 六族物品可入仓（与 count_item 口径一致）；宝箱/肥料等特殊计数不进仓。
	return count_item(item) > 0 or _in_backpack_tables(item)


func _in_backpack_tables(item: String) -> bool:
	return item in harvest or item in products or item in fish or item in forage or item in minerals or item in forestry


func warehouse_count(item: String) -> int:
	return int(warehouse.get(item, 0))


func warehouse_total() -> int:
	## STORE-02：仓库现有总件数（容量口径）。
	var total := 0
	for item in warehouse:
		total += int(warehouse[item])
	return total


func warehouse_discard(item: String) -> int:
	## STORE-02：丢弃仓库内该物品全部存量（两步确认由 UI 负责），返回丢弃数量。
	var dropped := warehouse_count(item)
	if dropped <= 0:
		return 0
	warehouse[item] = 0
	return dropped


func warehouse_deposit(item: String) -> int:
	## 把背包里该物品全部入仓，返回实际入仓数量；非六族物品拒绝。
	if not _in_backpack_tables(item):
		return 0
	var moved := count_item(item)
	if moved <= 0:
		return 0
	remove_items(item, moved)
	warehouse[item] = warehouse_count(item) + moved
	EventBus.instance().item_removed.emit(item, moved)
	return moved


func warehouse_withdraw(item: String) -> int:
	## 把仓库里该物品全部取回背包，返回实际取出数量。
	var moved := warehouse_count(item)
	if moved <= 0:
		return 0
	warehouse[item] = 0
	_add_to_backpack(item, moved)
	EventBus.instance().item_added.emit(item, moved)
	return moved


func _add_to_backpack(item: String, count: int) -> void:
	## warehouse_withdraw 的落袋路由（与 count_item 六族口径一致）。
	if item in harvest:
		harvest[item] += count
	elif item in products:
		products[item] += count
	elif item in fish:
		fish[item] += count
	elif item in forage:
		forage[item] += count
	elif item in minerals:
		minerals[item] += count
	elif item in forestry:
		forestry[item] += count


func _load_warehouse(data: Dictionary) -> Dictionary:
	## STORE-01：仓库旧档缺键为空；未知物品与脏数值清洗；上限与背包一致。
	var saved_value: Variant = data.get("warehouse", {})
	var saved: Dictionary = saved_value if saved_value is Dictionary else {}
	var result := {}
	for item: String in saved:
		if not _in_backpack_tables(item):
			continue
		var value = saved[item]
		if value is not int and value is not float:
			continue
		if not is_finite(float(value)) or float(value) < 0.0:
			continue
		result[item] = clampi(int(value), 0, 1000000)
	return result


func add_fish(kind: String, count: int = 1, quality: String = "normal") -> void:
	if not fish.has(kind) or count <= 0:
		return
	fish[kind] += count
	if fish_quality.has(quality):
		fish_quality[quality][kind] += count
	EventBus.instance().item_added.emit(kind, count)


func add_forage(kind: String, count: int = 1) -> void:
	## GATHER-01：徒手采集入包；未知物种忽略，保证事件与库存一致。
	if not forage.has(kind) or count <= 0:
		return
	forage[kind] += count
	EventBus.instance().item_added.emit(kind, count)


## ---- NPC-01：好感、每日对话与送礼 ----

func npc_talk(id: String, day: int) -> int:
	## 每日首次对话 +TALK_FRIENDSHIP；返回本次获得的好感。
	if not NpcDB.NPCS.has(id) or int(npc_last_talk.get(id, 0)) == day:
		return 0
	npc_last_talk[id] = day
	npc_friendship[id] = clampi(int(npc_friendship.get(id, 0)) + NpcDB.TALK_FRIENDSHIP, 0, NpcDB.MAX_FRIENDSHIP)
	return NpcDB.TALK_FRIENDSHIP


func npc_gift(id: String, day: int, tier: String) -> int:
	## 每日最多一份礼；hates 可为负。返回好感变化，当日已送返回 0。
	if not NpcDB.NPCS.has(id) or not NpcDB.GIFT_TIERS.has(tier) or int(npc_last_gift.get(id, 0)) == day:
		return 0
	npc_last_gift[id] = day
	var delta: int = NpcDB.GIFT_TIERS[tier]
	npc_friendship[id] = clampi(int(npc_friendship.get(id, 0)) + delta, 0, NpcDB.MAX_FRIENDSHIP)
	return delta


func npc_gifted_today(id: String, day: int) -> bool:
	return int(npc_last_gift.get(id, 0)) == day


func npc_hearts(id: String) -> int:
	return clampi(int(npc_friendship.get(id, 0)), 0, NpcDB.MAX_FRIENDSHIP) / NpcDB.HEART_UNIT


func npc_met(id: String) -> bool:
	return int(npc_last_talk.get(id, 0)) > 0


## ---- QUEST-01：NPC 委托 ----

func quest_available(id: String) -> bool:
	return QuestDB.is_offered(id, quests_completed) and not quests_accepted.has(id)


func accept_quest(id: String, day: int) -> bool:
	if not quest_available(id):
		return false
	quests_accepted[id] = day
	return true


func quest_active(id: String) -> bool:
	return quests_accepted.has(id) and not quests_completed.has(id)


func quest_progress(id: String) -> int:
	if not quest_active(id) or QuestDB.entry(id)["type"] != "collect":
		return 0
	var need: int = int(QuestDB.entry(id)["count"])
	return mini(count_item(QuestDB.entry(id)["item"]), need)


func quest_turnable(id: String) -> bool:
	if not quest_active(id) or QuestDB.entry(id)["type"] != "collect":
		return false
	return count_item(QuestDB.entry(id)["item"]) >= int(QuestDB.entry(id)["count"])


## 交付：扣货、发奖励（金币+好感）、记录完成日。不可交付时返回空表。
func complete_quest(id: String, day: int) -> Dictionary:
	var quest: Dictionary = QuestDB.entry(id) if QuestDB.QUESTS.has(id) else {}
	if quest.is_empty() or not quest_active(id):
		return {}
	if quest["type"] == "collect" and not remove_items(quest["item"], int(quest["count"])):
		return {}
	var coins_reward: int = int(quest["reward_coins"])
	add_coins(coins_reward)
	var giver: String = quest["giver"]
	if npc_friendship.has(giver):
		npc_friendship[giver] = clampi(int(npc_friendship[giver]) + int(quest["reward_friendship"]), 0, NpcDB.MAX_FRIENDSHIP)
	quests_completed[id] = day
	return {"coins": coins_reward, "friendship": int(quest["reward_friendship"])}


## 传话委托：与目标 NPC 交谈时自动完成，返回 {id,coins,friendship}；不匹配返回空表。
func visit_quest_for(target: String, day: int) -> Dictionary:
	for id in quests_accepted:
		if not quest_active(id):
			continue
		var quest: Dictionary = QuestDB.entry(id)
		if quest["type"] == "visit" and quest["target"] == target:
			var rewards: Dictionary = complete_quest(id, day)
			if not rewards.is_empty():
				rewards["id"] = id
			return rewards
	return {}


func active_collect_quests() -> Array[String]:
	var result: Array[String] = []
	for id in quests_accepted:
		if quest_active(id) and QuestDB.entry(id)["type"] == "collect":
			result.append(id)
	return result


func count_item(item: String) -> int:
	## 六族背包统一计数（收获/产品/鱼获/采集/矿石/林业）。
	if item in harvest:
		return int(harvest[item])
	if item in products:
		return int(products[item])
	if fish.has(item):
		return int(fish[item])
	if forage.has(item):
		return int(forage[item])
	if minerals.has(item):
		return int(minerals[item])
	if forestry.has(item):
		return int(forestry[item])
	return 0


func remove_items(item: String, count: int = 1) -> bool:
	## 扣 n 件（不足整批拒绝）；品质计数对齐剩余总数。QUEST-01 交付与送礼共用。
	if count <= 0 or count_item(item) < count:
		return false
	if item in harvest:
		harvest[item] = int(harvest[item]) - count
		_take_quality(harvest_quality, item, int(harvest[item]))
	elif item in products:
		products[item] = int(products[item]) - count
	elif fish.has(item):
		fish[item] = int(fish[item]) - count
		_take_quality(fish_quality, item, int(fish[item]))
	elif forage.has(item):
		forage[item] = int(forage[item]) - count
	elif minerals.has(item):
		minerals[item] = int(minerals[item]) - count
	elif forestry.has(item):
		forestry[item] = int(forestry[item]) - count
	else:
		return false
	EventBus.instance().item_removed.emit(item, count)
	return true


func remove_gift_item(item: String) -> bool:
	## 送礼扣一件；保留为 NPC-01 语义入口。
	return remove_items(item, 1)


func giftable_items() -> Array[String]:
	## 可送礼物品（持有量 > 0），用于对话面板列表。
	var result: Array[String] = []
	for kind in harvest:
		if harvest[kind] > 0:
			result.append(kind)
	for kind in products:
		if products[kind] > 0:
			result.append(kind)
	for kind in fish:
		if fish[kind] > 0:
			result.append(kind)
	for kind in forage:
		if forage[kind] > 0:
			result.append(kind)
	for kind in minerals:
		if minerals[kind] > 0:
			result.append(kind)
	for kind in forestry:
		if forestry[kind] > 0:
			result.append(kind)
	return result


func _take_quality(quality: Dictionary, kind: String, remaining: int) -> void:
	## 品质计数对齐单件扣除：先普通、再银、后金（普通 = 总数 − 银 − 金）。
	var silver: int = int(quality["silver"].get(kind, 0))
	var gold: int = int(quality["gold"].get(kind, 0))
	var tracked := silver + gold
	if tracked <= remaining:
		return
	if silver > 0:
		quality["silver"][kind] = silver - 1
	else:
		quality["gold"][kind] = maxi(0, gold - 1)


func fishing_xp_needed() -> int:
	return 0 if fishing_level >= MAX_FISHING_LEVEL else fishing_level * 100


func gain_fishing_xp(amount: int) -> int:
	if fishing_level >= MAX_FISHING_LEVEL:
		fishing_xp = 0
		return 0
	if amount <= 0:
		return 0
	var remaining := amount
	var gained := 0
	while fishing_level < MAX_FISHING_LEVEL and remaining >= fishing_xp_needed() - fishing_xp:
		remaining -= fishing_xp_needed() - fishing_xp
		fishing_level += 1
		fishing_xp = 0
		gained += 1
	fishing_xp = fishing_xp + remaining if fishing_level < MAX_FISHING_LEVEL else 0
	return gained


func fish_quality_for(control_score: float) -> String:
	var score := clampf(0.0 if is_nan(control_score) else control_score, 0.0, 1.0)
	score += 0.04 * (clampi(fishing_level, 1, MAX_FISHING_LEVEL) - 1)
	if score >= 1.14:
		return "gold"
	if score >= 0.82:
		return "silver"
	return "normal"


func fish_sale_value(kind: String) -> int:
	if not FishDB.FISH.has(kind):
		return 0
	var total: int = maxi(0, fish.get(kind, 0))
	var gold: int = clampi(fish_quality["gold"].get(kind, 0), 0, total)
	var silver: int = clampi(fish_quality["silver"].get(kind, 0), 0, total - gold)
	var price := FishDB.sell_price(kind)
	return (total - gold - silver) * price + silver * int(price * 1.5) + gold * price * 2


func buy_seed(kind: String, count: int) -> bool:
	var cost: int = CropDB.field(kind, "seed_price") * count
	if coins < cost:
		return false
	coins -= cost
	seeds[kind] += count
	EventBus.instance().money_changed.emit(coins, -cost)
	EventBus.instance().item_added.emit("seed_" + kind, count)
	return true


func sale_total() -> int:
	var total := 0
	for kind in harvest:
		var price: int = CropDB.field(kind, "sell_price")
		var gold: int = mini(harvest_quality["gold"][kind], harvest[kind])
		var silver: int = mini(harvest_quality["silver"][kind], harvest[kind] - gold)
		var plain: int = harvest[kind] - gold - silver
		total += plain * price + int(silver * price * 1.5) + gold * price * 2
	for kind in products:
		total += products[kind] * ItemDB.PRODUCTS[kind]["sell_price"]
	for kind in FishDB.ORDER:
		total += fish_sale_value(kind)
	for kind in ForageDB.ORDER:
		total += forage.get(kind, 0) * ForageDB.sell_price(kind)
	return total


func sell_all_harvest() -> int:
	var earned := sale_total()
	for kind in harvest:
		if harvest[kind] > 0:
			EventBus.instance().item_removed.emit(kind, harvest[kind])
		harvest[kind] = 0
		harvest_quality["gold"][kind] = 0
		harvest_quality["silver"][kind] = 0
	for kind in products:
		if products[kind] > 0:
			EventBus.instance().item_removed.emit(kind, products[kind])
		products[kind] = 0
	for kind in fish:
		if fish[kind] > 0:
			EventBus.instance().item_removed.emit(kind, fish[kind])
		fish[kind] = 0
		fish_quality["gold"][kind] = 0
		fish_quality["silver"][kind] = 0
	for kind in ForageDB.ORDER:
		if forage.get(kind, 0) > 0:
			EventBus.instance().item_removed.emit(kind, forage[kind])
		forage[kind] = 0
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
	energy = energy_max()
	rations = maxi(rations, 3)


func tool_energy_cost(tool: String) -> float:
	## FARM-01：基础消耗 × 等级系数（1/2/3 级 → ×1.0/0.6/0.3）。
	var base: float = TOOL_ENERGY_COSTS.get(tool, 0.0)
	var level: int = tool_levels.get(tool, 1) if tool_levels.has(tool) else 1
	return base * [1.0, 0.6, 0.3][clampi(level, 1, 3) - 1]


func spend_energy(amount: float) -> bool:
	if energy < amount:
		return false
	energy -= amount
	return true


func tool_level(tool: String) -> int:
	return int(tool_levels.get(tool, 1))


func tool_power(tool: String) -> float:
	## FARM-01 二轮：镐/斧伤害倍率随等级 1.0/1.5/2.0；其他工具恒 1.0。
	if tool_levels.has(tool):
		return [1.0, 1.5, 2.0][clampi(int(tool_levels[tool]), 1, 3) - 1]
	return 1.0


func energy_max() -> int:
	return MAX_ENERGY + (level - 1) * 10


func gain_xp(amount: int) -> int:
	## 返回升到的等级变化量；由调用方提示。
	xp += amount
	var gained := 0
	while xp >= level * 100:
		xp -= level * 100
		level += 1
		gained += 1
	energy = minf(energy, energy_max())
	return gained


func roll_harvest_quality(fertilized: bool, rng: RandomNumberGenerator = null) -> String:
	## FARM-01 二轮：收获品质。施肥提高银/金占比；rng 可注入以便测试。
	if rng == null:
		rng = _quality_rng
	var roll := rng.randf()
	var gold := 0.10 if fertilized else 0.03
	var silver := 0.35 if fertilized else 0.17
	if roll < gold:
		return "gold"
	if roll < gold + silver:
		return "silver"
	return "normal"


var _quality_rng := RandomNumberGenerator.new()


func add_harvest(kind: String, count: int = 1, quality: String = "normal") -> void:
	harvest[kind] += count
	if harvest_quality.has(quality):
		harvest_quality[quality][kind] += count
	EventBus.instance().item_added.emit(kind, count)


func buy_fertilizer(count: int) -> bool:
	return _purchase(FERTILIZER_PRICE * count, func(): fertilizer += count)


func building_capacity(kind: String) -> int:
	## 谷仓（牛羊）每级 4 格，鸡舍（鸡）每级 6 格。
	return (4 if kind == "barn" else 6) * int(building_levels.get(kind, 1))


func buy_building_upgrade(kind: String) -> bool:
	## 建筑扩容：金币+木材+石料；上限 3 级。
	if not BUILDING_UPGRADE_COSTS.has(kind) or int(building_levels.get(kind, 1)) >= 3:
		return false
	var cost: Dictionary = BUILDING_UPGRADE_COSTS[kind]
	if coins < int(cost["coins"]):
		return false
	for key in cost:
		if key == "coins":
			continue
		var table: String = "forestry" if key == "wood" else "minerals"
		if get(table).get(key, 0) < int(cost[key]):
			return false
	coins -= int(cost["coins"])
	for key in cost:
		if key == "coins":
			continue
		var table: String = "forestry" if key == "wood" else "minerals"
		get(table)[key] -= int(cost[key])
	building_levels[kind] = int(building_levels[kind]) + 1
	EventBus.instance().money_changed.emit(coins, -int(cost["coins"]))
	return true


func buy_feed(count: int) -> bool:
	return _purchase(FEED_PRICE * count, func(): feed += count)


func buy_ration(count: int) -> bool:
	return _purchase(RATION_PRICE * count, func(): rations += count)


func buy_animal(kind: String) -> bool:
	## 购买动物：成功只扣钱并发出信号，节点生成由主场景完成。
	var ok := _purchase(AnimalDB.ANIMALS[kind]["price"], func(): pass)
	if ok:
		EventBus.instance().item_added.emit("animal_" + kind, 1)
	return ok


func buy_tool_upgrade(tool: String) -> bool:
	## 升级工具：金币+矿物双扣费；满级失败。
	var level := tool_level(tool)
	if level >= 3 or not TOOL_UPGRADE_COSTS.has(tool):
		return false
	var cost: Dictionary = TOOL_UPGRADE_COSTS[tool][level - 1]
	if coins < int(cost["coins"]):
		return false
	for mineral_key in cost:
		if mineral_key == "coins":
			continue
		if minerals.get(mineral_key, 0) < int(cost[mineral_key]):
			return false
	coins -= int(cost["coins"])
	for mineral_key in cost:
		if mineral_key != "coins":
			minerals[mineral_key] -= int(cost[mineral_key])
	tool_levels[tool] = level + 1
	EventBus.instance().money_changed.emit(coins, -int(cost["coins"]))
	return true


func _purchase(cost: int, apply: Callable) -> bool:
	if coins < cost:
		return false
	coins -= cost
	apply.call()
	EventBus.instance().money_changed.emit(coins, -cost)
	return true


func eat_ration() -> int:
	if rations <= 0 or (health >= MAX_HEALTH and energy >= MAX_ENERGY):
		return 0
	rations -= 1
	var restored := mini(35, MAX_HEALTH - health)
	health += restored
	energy = minf(MAX_ENERGY, energy + 35.0)
	EventBus.instance().item_removed.emit("ration", 1)
	return maxi(restored, 1)


func buy_meal() -> bool:
	## INDOOR-01：酒馆套餐——付费回满体力并恢复生命；金币不足拒绝。
	return _purchase(InteriorDB.MEAL_PRICE, func():
		energy = float(energy_max())
		health = mini(MAX_HEALTH, health + InteriorDB.MEAL_HEALTH))


func buy_treatment() -> bool:
	## INDOOR-01：诊所治疗——付费回满生命；生命已满或金币不足均拒绝。
	if health >= MAX_HEALTH:
		return false
	return _purchase(InteriorDB.TREATMENT_PRICE, func(): health = MAX_HEALTH)


func clock_text() -> String:
	return time.clock_text()


func to_dict() -> Dictionary:
	return {
		"coins": coins, "seeds": seeds, "harvest": harvest, "products": products,
		"health": health, "energy": energy, "feed": feed, "rations": rations,
		"minerals": minerals, "forestry": forestry, "tool_levels": tool_levels,
		"deepest_mine_floor": deepest_mine_floor, "mine_completed": mine_completed,
		"xp": xp, "level": level, "fertilizer": fertilizer, "fish": fish.duplicate(),
		"harvest_quality": harvest_quality, "building_levels": building_levels,
		"fish_quality": fish_quality.duplicate(true), "fishing_level": fishing_level, "fishing_xp": fishing_xp,
		"forage": forage.duplicate(),
		"npc": {"friendship": npc_friendship.duplicate(), "talk": npc_last_talk.duplicate(), "gift": npc_last_gift.duplicate()},
		"quests": {"accepted": quests_accepted.duplicate(), "completed": quests_completed.duplicate()},
		"chests_ready": chests_ready, "warehouse": warehouse.duplicate(),
		"warehouse_capacity": warehouse_capacity,
	}


func from_dict(data: Dictionary) -> void:
	coins = int(data.get("coins", START_COINS))
	_load_fishing(data)
	_load_forage(data)
	_load_npc(data)
	_load_quests(data)
	for table_key in ["seeds", "harvest", "products", "minerals", "forestry", "tool_levels", "harvest_quality", "building_levels"]:
		var saved: Dictionary = data.get(table_key, {})
		for kind in get(table_key):
			if saved.has(kind):
				var value = saved[kind]
				if value is Dictionary:
					for sub in value:
						get(table_key)[kind][sub] = value[sub]
				else:
					get(table_key)[kind] = value
	health = int(data.get("health", MAX_HEALTH))
	energy = float(data.get("energy", MAX_ENERGY))
	chests_ready = maxi(0, int(data.get("chests_ready", 0)))
	warehouse_capacity = clampi(int(data.get("warehouse_capacity", 300)), 300, 1000000)
	warehouse = _load_warehouse(data)
	feed = int(data.get("feed", 4))
	fertilizer = int(data.get("fertilizer", 2))
	xp = int(data.get("xp", 0))
	level = int(data.get("level", 1))
	rations = int(data.get("rations", 3))
	deepest_mine_floor = int(data.get("deepest_mine_floor", 0))
	mine_completed = bool(data.get("mine_completed", false))


func _load_forage(data: Dictionary) -> void:
	## GATHER-01：旧档缺少采集字段时清零；未知物种与非有限数量不修改默认表。
	var saved_value: Variant = data.get("forage", {})
	var saved: Dictionary = saved_value if saved_value is Dictionary else {}
	for kind in ForageDB.ORDER:
		forage[kind] = _fishing_int(saved.get(kind, 0), 0, 0, MAX_FISH_COUNT)


static func _zero_forage() -> Dictionary:
	var result := {}
	for kind in ForageDB.ORDER:
		result[kind] = 0
	return result


static func _zero_npc() -> Dictionary:
	var result := {}
	for id in NpcDB.ORDER:
		result[id] = 0
	return result


func _load_npc(data: Dictionary) -> void:
	## NPC-01：旧档无 npc 键时全零；未知 id 忽略，数值夹取，输入不改。
	var saved_value: Variant = data.get("npc", {})
	var saved: Dictionary = saved_value if saved_value is Dictionary else {}
	var tables := {"friendship": {}, "talk": {}, "gift": {}}
	for key in tables:
		var raw: Variant = saved.get(key, {})
		var table: Dictionary = raw if raw is Dictionary else {}
		var upper := NpcDB.MAX_FRIENDSHIP if key == "friendship" else 1000000
		for id in NpcDB.ORDER:
			tables[key][id] = _fishing_int(table.get(id, 0), 0, 0, upper)
	npc_friendship = tables["friendship"]
	npc_last_talk = tables["talk"]
	npc_last_gift = tables["gift"]


func _load_quests(data: Dictionary) -> void:
	## QUEST-01：旧档无 quests 键时为空；未知委托 id 忽略，日戳夹取，输入不改。
	var saved_value: Variant = data.get("quests", {})
	var saved: Dictionary = saved_value if saved_value is Dictionary else {}
	var tables := {"accepted": {}, "completed": {}}
	for key in tables:
		var raw: Variant = saved.get(key, {})
		var table: Dictionary = raw if raw is Dictionary else {}
		for id in QuestDB.ORDER:
			if table.has(id):
				tables[key][id] = _fishing_int(table[id], 0, 0, 1000000)
	quests_accepted = tables["accepted"]
	quests_completed = tables["completed"]


func _load_fishing(data: Dictionary) -> void:
	var fish_value: Variant = data.get("fish", {})
	var saved_fish: Dictionary = fish_value if fish_value is Dictionary else {}
	var quality_value: Variant = data.get("fish_quality", {})
	var saved_quality: Dictionary = quality_value if quality_value is Dictionary else {}
	var gold_value: Variant = saved_quality.get("gold", {})
	var saved_gold: Dictionary = gold_value if gold_value is Dictionary else {}
	var silver_value: Variant = saved_quality.get("silver", {})
	var saved_silver: Dictionary = silver_value if silver_value is Dictionary else {}
	var loaded_fish := {}
	var loaded_quality := {"silver": {}, "gold": {}}
	for kind in FishDB.ORDER:
		var total := _fishing_int(saved_fish.get(kind, 0), 0, 0, MAX_FISH_COUNT)
		var gold := _fishing_int(saved_gold.get(kind, 0), 0, 0, total)
		var silver := _fishing_int(saved_silver.get(kind, 0), 0, 0, total - gold)
		loaded_fish[kind] = total
		loaded_quality["gold"][kind] = gold
		loaded_quality["silver"][kind] = silver
	fish = loaded_fish
	fish_quality = loaded_quality
	fishing_level = _fishing_int(data.get("fishing_level", 1), 1, 1, MAX_FISHING_LEVEL)
	fishing_xp = _fishing_int(data.get("fishing_xp", 0), 0, 0, maxi(0, fishing_xp_needed() - 1))


static func _fishing_int(value: Variant, fallback: int, minimum: int, maximum: int) -> int:
	if not (value is int or value is float) or not is_finite(float(value)):
		return fallback
	return int(clampf(float(value), minimum, maximum))
