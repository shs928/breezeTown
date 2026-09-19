extends RefCounted
## QuestData 目录：NPC 委托的唯一事实来源（V2 PRD M5 任务）。
## 字段：label 标题；giver 交付 NPC；brief 接受时的任务说明；thanks 交付时的答谢；
## type "collect"（收集 count 件 item 交回 giver）| "visit"（把话带给 target NPC，交谈即完成）；
## requires 前置委托 id（空串无前置）；reward_coins/reward_friendship 交付奖励。

const NpcDB := preload("res://scripts/data/npc_db.gd")
const ItemDB := preload("res://scripts/data/item_db.gd")

const QUESTS := {
	"pierre_veggies": {
		"label": "皮埃尔的进货", "giver": "pierre", "type": "collect", "item": "radish", "count": 5,
		"requires": "", "reward_coins": 60, "reward_friendship": 40,
		"brief": "店里萝卜断货了。帮我弄 5 根小萝卜来，货款我多算你一点。",
		"thanks": "太好了，正好赶上明早开张！这是货款，辛苦费也算了进去。",
	},
	"pierre_fish": {
		"label": "鲜鱼特价招牌", "giver": "pierre", "type": "collect", "item": "sardine", "count": 3,
		"requires": "pierre_veggies", "reward_coins": 55, "reward_friendship": 40,
		"brief": "周末想挂个“鲜鱼特价”的招牌，需要 3 条沙丁鱼摆样。老王说雨天鱼口最好。",
		"thanks": "鱼真新鲜！招牌一挂，准能招来客人。",
	},
	"marnie_eggs": {
		"label": "孵窝的鸡蛋", "giver": "marnie", "type": "collect", "item": "egg", "count": 3,
		"requires": "", "reward_coins": 55, "reward_friendship": 40,
		"brief": "鸡舍想添几只新苗，帮我凑 3 枚鸡蛋来孵。",
		"thanks": "母鸡们有福了！这点心意你收好。",
	},
	"marnie_wood": {
		"label": "修缮谷仓", "giver": "marnie", "type": "collect", "item": "wood", "count": 10,
		"requires": "marnie_eggs", "reward_coins": 80, "reward_friendship": 40,
		"brief": "谷仓的北墙被风刮松了，帮我备 10 根木材，趁晴天修好它。",
		"thanks": "墙修好了，结实得很！多亏你的木材。",
	},
	"clint_ore": {
		"label": "炉子的口粮", "giver": "clint", "type": "collect", "item": "copper", "count": 4,
		"requires": "", "reward_coins": 80, "reward_friendship": 40,
		"brief": "炉子快熄了。弄 4 块铜矿石来，别让我闲着。",
		"thanks": "成色不错。炉子有救了。……谢了。",
	},
	"clint_coal": {
		"label": "锻造用的煤", "giver": "clint", "type": "collect", "item": "coal", "count": 5,
		"requires": "clint_ore", "reward_coins": 75, "reward_friendship": 40,
		"brief": "光有矿石不够，还得 5 份煤炭。矿场里随处可见，就看你肯不肯下力气。",
		"thanks": "火候到了。你这人……做事靠谱。",
	},
	"wang_message": {
		"label": "给玛尔妮捎话", "giver": "wang", "type": "visit", "target": "marnie",
		"requires": "", "reward_coins": 30, "reward_friendship": 30,
		"brief": "腿脚不便就不跑北岭了。帮我告诉玛尔妮，明早我把渔获送到她后院。",
		"thanks": "老王明早送渔获来？行，我等着。替我谢谢他。",
	},
	"wang_carp": {
		"label": "锦鲤的邻居", "giver": "wang", "type": "collect", "item": "carp", "count": 2,
		"requires": "wang_message", "reward_coins": 65, "reward_friendship": 40,
		"brief": "月湾湖的鲤鱼正肥。钓 2 条来，我教你认认码头下的鱼窝。",
		"thanks": "好鱼！改天跟我来码头，第三块板子下面就是鱼窝。",
	},
}
const ORDER := ["pierre_veggies", "pierre_fish", "marnie_eggs", "marnie_wood", "clint_ore", "clint_coal", "wang_message", "wang_carp"]


static func label(id: String) -> String:
	return QUESTS[id]["label"]


static func entry(id: String) -> Dictionary:
	return QUESTS[id]


## 某村民当前可提供的委托（前置已满足、未接受、未完成）。
static func offers_for(giver: String, completed: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for id in ORDER:
		if QUESTS[id]["giver"] == giver and is_offered(id, completed):
			result.append(id)
	return result


## 委托是否处于"可提供"状态：存在、未完成、前置已达成（是否已接受由调用方判断）。
static func is_offered(id: String, completed: Dictionary) -> bool:
	if not QUESTS.has(id) or completed.has(id):
		return false
	return _requires_met(QUESTS[id], completed)


static func _requires_met(quest: Dictionary, completed: Dictionary) -> bool:
	var prerequisite: String = quest["requires"]
	return prerequisite.is_empty() or completed.has(prerequisite)


static func gift_line_of(id: String) -> String:
	return QUESTS[id]["thanks"]
