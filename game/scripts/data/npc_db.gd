extends RefCounted
## NpcData 目录：村民人设的唯一事实来源（V2 PRD M5 NPC：日程/对话/好感/送礼）。
## 字段：label 姓名；role 身份；schedule 日程（左闭右开时段 → 锚点，覆盖全天 6:00–30:00）；
## 锚点词表：landmarks 键（shop_door/town_square/lake_view/mine_door/...）或 "site:建筑id"（取该建筑 door）。
## palette 造型色板；loves/likes/hates 送礼喜好（物品 id）；greet 初见台词；
## chat 按好感档（low <300 / mid <700 / high ≥700）的闲聊池；gift_react 四档受礼反应。

const GameClock := preload("res://scripts/core/game_clock.gd")

const NPCS := {
	"pierre": {
		"label": "皮埃尔",
		"role": "杂货店主",
		"schedule": [
			{"from": 6.0, "to": 9.0, "anchor": "site:shop", "offset": [3.0, 1.2], "wander": 2.0},
			{"from": 9.0, "to": 17.0, "anchor": "site:shop", "offset": [3.0, 1.2], "wander": 1.4},
			{"from": 17.0, "to": 21.0, "anchor": "town_square", "wander": 3.0},
			{"from": 21.0, "to": 30.0, "anchor": "site:shop", "offset": [3.0, 1.2], "wander": 1.0},
		],
		"palette": {"coat": "#3f6ea5", "pants": "#5a4632", "hat": "#c8a24a", "hair": "#4a2f1b"},
		"loves": ["radish", "strawberry", "pumpkin"],
		"likes": ["wheat", "egg", "sweet_pea"],
		"hates": ["slime"],
		"greet": "欢迎来到微风镇！我的店里种子齐全，有需要随时来。",
		"chat": {
			"low": ["新鲜的种子刚到货，看看有没有中意的？", "种地这行当，靠的是耐心。", "镇上好久没来新面孔了。"],
			"mid": ["你田里的收成不错吧？拿到店里来，我给你好价钱。", "这季节的作物要抓紧，错过了可要再等一年。", "镇子不大，但大家都很照顾我的生意，谢谢你们。"],
			"high": ["你是我最信任的供货人，店里一半的货架都靠你撑着。", "有空多来坐坐，生意之外咱们也能聊聊镇上的事。", "把这片土地交给你这样的人，我放心。"],
		},
		"gift_react": {
			"loves": "这、这正是我最想要的！你太懂我了。",
			"likes": "哦，我很喜欢，谢谢你。",
			"neutral": "谢谢你的心意。",
			"hates": "呃……这个你还是自己留着吧。",
		},
	},
	"marnie": {
		"label": "玛尔妮",
		"role": "北岭农庄牧场主",
		"schedule": [
			{"from": 6.0, "to": 12.0, "anchor": "site:npc_barn", "offset": [2.4, -1.6], "wander": 3.0},
			{"from": 12.0, "to": 15.0, "anchor": "site:npc_farmhouse", "offset": [2.6, 1.0], "wander": 1.6},
			{"from": 15.0, "to": 21.0, "anchor": "site:npc_barn", "offset": [2.4, -1.6], "wander": 3.0},
			{"from": 21.0, "to": 30.0, "anchor": "site:npc_farmhouse", "offset": [2.6, 1.0], "wander": 1.2},
		],
		"palette": {"coat": "#b05a76", "pants": "#6b4a8a", "hat": "", "hair": "#7a3b1f"},
		"loves": ["milk", "egg"],
		"likes": ["wool", "wheat", "dandelion"],
		"hates": ["sardine"],
		"greet": "你好呀，我是玛尔妮。想养点什么的时候就到北岭来找我。",
		"chat": {
			"low": ["牛羊要按时喂食，好感才涨得快。", "农庄的牲口都是我一手带大的。", "城里的空气可没这儿好。"],
			"mid": ["你牧场的动物养得不错嘛，有一手。", "小鸡出栏的时候最热闹，你有空来看看。", "记得给食槽添料，别让它们饿着。"],
			"high": ["你这孩子比我的亲侄子还勤快。", "哪天把你的牧场扩大了，我这儿的好牲口随便挑。", "有你在，这山谷的日子越来越有奔头了。"],
		},
		"gift_react": {
			"loves": "哎呀，我最爱这个！你真是个贴心的孩子。",
			"likes": "很实用，谢谢你想着我。",
			"neutral": "谢谢你，心意我领了。",
			"hates": "这……不适合我，你拿回去吧。",
		},
	},
	"clint": {
		"label": "巴特",
		"role": "铁匠",
		"schedule": [
			{"from": 6.0, "to": 17.0, "anchor": "site:smith", "offset": [2.6, 1.2], "wander": 2.2},
			{"from": 17.0, "to": 21.0, "anchor": "site:inn", "offset": [2.2, -1.8], "wander": 2.6},
			{"from": 21.0, "to": 30.0, "anchor": "site:smith", "offset": [2.6, 1.2], "wander": 1.4},
		],
		"palette": {"coat": "#5a4a3a", "pants": "#3a3a3a", "hat": "", "hair": "#2a2a2a"},
		"loves": ["copper", "iron", "crystal"],
		"likes": ["coal", "stone", "mushroom"],
		"hates": ["daffodil"],
		"greet": "……铁匠铺。要修工具就拿来，别客气。",
		"chat": {
			"low": ["炉子不能熄，一熄就是一天的活。", "矿场深处的矿石成色最好，也最危险。", "别在铺子里乱碰东西。"],
			"mid": ["你送来的矿石成色不错，打了好几件称手的家伙。", "矿场那地方，装备不行就别下太深。", "你的镐子最近用得挺勤，需要保养就说。"],
			"high": ["这山谷里，就数你最懂好矿石。", "等我手头这批活干完，给你打件称心的东西。", "……朋友。这话我不常说。"],
		},
		"gift_react": {
			"loves": "好料子！这成色……你从哪挖来的？",
			"likes": "嗯，用得上。",
			"neutral": "……谢了。",
			"hates": "花？你拿这个来见我？",
		},
	},
	"wang": {
		"label": "老王",
		"role": "渔夫",
		"schedule": [
			{"from": 6.0, "to": 18.0, "anchor": "lake_view", "offset": [2.0, 1.2], "wander": 2.8},
			{"from": 18.0, "to": 21.0, "anchor": "site:inn", "offset": [2.2, -1.8], "wander": 2.4},
			{"from": 21.0, "to": 30.0, "anchor": "site:home_town", "offset": [2.0, 1.0], "wander": 1.4},
		],
		"palette": {"coat": "#3a7a6a", "pants": "#4a5568", "hat": "#d9cba8", "hair": "#9a9a9a"},
		"loves": ["koi", "catfish"],
		"likes": ["perch", "rainbow_trout", "shell", "cockle"],
		"hates": ["stone"],
		"greet": "嘿，新来的？这月湾湖里的鱼，可比我岁数都大。",
		"chat": {
			"low": ["雨天鱼口最好，别嫌麻烦。", "虹鳟要等天冷了才肯咬钩。", "锦鲤那家伙精得很，急不来。"],
			"mid": ["你的竿法有长进啊，收线稳多了。", "码头第三块板下面有个大家伙，我只告诉你。", "雨夜钓鲶鱼，这可是老一辈传下来的门道。"],
			"high": ["我钓了一辈子鱼，就服你这样的年轻人。", "哪天我钓不动了，这码头就传给你。", "来，陪老朽坐会儿，看会儿水。"],
		},
		"gift_react": {
			"loves": "好家伙！这鱼我十年没见着了！",
			"likes": "不错的鱼获，懂行。",
			"neutral": "谢谢，放鱼篓里了。",
			"hates": "石头……你是从矿场顺路来的吧。",
		},
	},
}
const ORDER := ["pierre", "marnie", "clint", "wang"]

## 送礼好感：loves/likes/neutral/hates。
const GIFT_TIERS := {"loves": 60, "likes": 30, "neutral": 15, "hates": -30}
const TALK_FRIENDSHIP := 8
const MAX_FRIENDSHIP := 1000
const HEART_UNIT := 100


static func label(id: String) -> String:
	return NPCS[id]["label"]


static func role(id: String) -> String:
	return NPCS[id]["role"]


static func entry(id: String) -> Dictionary:
	return NPCS[id]


## 当前小时的日程条目；小时数按 6:00 起的一天折算（26 表示次日 2:00）。
static func schedule_at(id: String, hours: float) -> Dictionary:
	var entries: Array = NPCS[id]["schedule"]
	var clock := fposmod(hours - 6.0 + 24.0, 24.0) + 6.0
	for index in range(entries.size()):
		var slot: Dictionary = entries[index]
		if float(slot["from"]) <= clock and clock < float(slot["to"]):
			return slot
	return entries[entries.size() - 1]


static func gift_tier(id: String, item: String) -> String:
	if item in NPCS[id]["loves"]:
		return "loves"
	if item in NPCS[id]["likes"]:
		return "likes"
	if item in NPCS[id]["hates"]:
		return "hates"
	return "neutral"


static func friendship_tier(value: int) -> String:
	if value >= 700:
		return "high"
	if value >= 300:
		return "mid"
	return "low"


static func chat_line(id: String, friendship: int, rng: RandomNumberGenerator) -> String:
	var pool: Array = NPCS[id]["chat"][friendship_tier(friendship)]
	return pool[rng.randi_range(0, pool.size() - 1)]


static func gift_line(id: String, tier: String) -> String:
	return NPCS[id]["gift_react"][tier]
