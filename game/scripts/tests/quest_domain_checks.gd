extends SceneTree
## QUEST-01 领域检查：委托数据完整性、链式前置、接受/进度/交付规则、奖励结算与存读档。

const GameState := preload("res://scripts/game_state.gd")
const QuestDB := preload("res://scripts/data/quest_db.gd")
const NpcDB := preload("res://scripts/data/npc_db.gd")
const ItemDB := preload("res://scripts/data/item_db.gd")

var failures: Array[String] = []
var count := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_data_integrity()
	_offers_and_prerequisites()
	_accept_progress_turnin()
	_visit_quests()
	_rewards_and_clamps()
	_save_roundtrip()
	print("QUEST_DOMAIN_RESULT %s %d checks" % ["PASS" if failures.is_empty() else "FAIL " + ",".join(failures), count])
	quit(0 if failures.is_empty() else 1)


func _check(label: String, result: bool) -> void:
	count += 1
	print("QUEST %s %s" % [label, "OK" if result else "FAIL"])
	if not result:
		failures.append(label)


func _data_integrity() -> void:
	for id in QuestDB.ORDER:
		var quest: Dictionary = QuestDB.QUESTS[id]
		_check("label-nonempty-" + id, String(quest["label"]).length() > 0)
		_check("brief-nonempty-" + id, String(quest["brief"]).length() > 0)
		_check("thanks-nonempty-" + id, String(quest["thanks"]).length() > 0)
		_check("giver-known-" + id, quest["giver"] in NpcDB.ORDER)
		_check("reward-coins-" + id, int(quest["reward_coins"]) > 0)
		_check("reward-friendship-" + id, int(quest["reward_friendship"]) > 0)
		var prerequisite: String = quest["requires"]
		_check("requires-known-" + id, prerequisite.is_empty() or QuestDB.QUESTS.has(prerequisite))
		if not prerequisite.is_empty():
			_check("requires-same-giver-" + id, QuestDB.QUESTS[prerequisite]["giver"] == quest["giver"])
		match String(quest["type"]):
			"collect":
				_check("collect-count-" + id, int(quest["count"]) > 0)
				var item_type: String = ItemDB.item_type(quest["item"])
				_check("collect-item-giftable-" + id, item_type in ["crop", "animal_product", "fish", "forage", "resource"])
			"visit":
				_check("visit-target-known-" + id, quest["target"] in NpcDB.ORDER)
				_check("visit-target-not-giver-" + id, quest["target"] != quest["giver"])
			_:
				_check("type-valid-" + id, false)
	# 前置链无环：沿 requires 上溯必须终止于空串。
	for id in QuestDB.ORDER:
		var seen := {}
		var cursor: String = id
		var acyclic := true
		while not QuestDB.QUESTS[cursor]["requires"].is_empty():
			if seen.has(cursor):
				acyclic = false
				break
			seen[cursor] = true
			cursor = QuestDB.QUESTS[cursor]["requires"]
		_check("chain-acyclic-" + id, acyclic)
	# 每位村民至少一条链。
	for giver in NpcDB.ORDER:
		var owned := 0
		for id in QuestDB.ORDER:
			if QuestDB.QUESTS[id]["giver"] == giver:
				owned += 1
		_check("giver-has-quests-" + giver, owned >= 2)
	_check("roster-eight-quests", QuestDB.ORDER.size() == 8)


func _offers_and_prerequisites() -> void:
	var completed := {}
	_check("offers-fresh-pierre", QuestDB.offers_for("pierre", completed) == (["pierre_veggies"] as Array[String]))
	_check("offers-fresh-marnie", QuestDB.offers_for("marnie", completed) == (["marnie_eggs"] as Array[String]))
	_check("offers-fresh-clint", QuestDB.offers_for("clint", completed) == (["clint_ore"] as Array[String]))
	_check("offers-fresh-wang", QuestDB.offers_for("wang", completed) == (["wang_message"] as Array[String]))
	completed["pierre_veggies"] = 3
	_check("offer-unlocks-after-prereq", QuestDB.offers_for("pierre", completed) == (["pierre_fish"] as Array[String]))
	_check("completed-quest-not-reoffered", not QuestDB.offers_for("pierre", completed).has("pierre_veggies"))
	_check("is-offered-unknown-false", not QuestDB.is_offered("ghost_quest", completed))
	_check("is-offered-completed-false", not QuestDB.is_offered("pierre_veggies", completed))


func _accept_progress_turnin() -> void:
	var state := GameState.new()
	_check("fresh-quest-available", state.quest_available("pierre_veggies"))
	_check("accept-records-day", state.accept_quest("pierre_veggies", 4) and int(state.quests_accepted["pierre_veggies"]) == 4)
	_check("accepted-not-available", not state.quest_available("pierre_veggies"))
	_check("double-accept-rejected", not state.accept_quest("pierre_veggies", 5))
	_check("accept-unknown-rejected", not state.accept_quest("ghost", 1))
	_check("active-before-complete", state.quest_active("pierre_veggies"))
	_check("progress-zero-empty", state.quest_progress("pierre_veggies") == 0)
	_check("turnable-false-empty", not state.quest_turnable("pierre_veggies"))
	state.add_harvest("radish", 4)
	_check("progress-counts-items", state.quest_progress("pierre_veggies") == 4)
	_check("turnable-false-partial", not state.quest_turnable("pierre_veggies"))
	_check("complete-rejects-partial", state.complete_quest("pierre_veggies", 5).is_empty())
	state.add_harvest("radish", 3)
	_check("progress-clamped-to-need", state.quest_progress("pierre_veggies") == 5)
	_check("turnable-when-full", state.quest_turnable("pierre_veggies"))
	var coins_before: int = state.coins
	var rewards: Dictionary = state.complete_quest("pierre_veggies", 5)
	_check("complete-pays-coins", int(rewards.get("coins", 0)) == 60 and state.coins == coins_before + 60)
	_check("complete-pays-friendship", int(state.npc_friendship["pierre"]) == 40)
	_check("complete-consumes-items", int(state.harvest["radish"]) == 2)
	_check("completed-no-longer-active", not state.quest_active("pierre_veggies") and int(state.quests_completed["pierre_veggies"]) == 5)
	_check("double-complete-rejected", state.complete_quest("pierre_veggies", 6).is_empty())
	_check("complete-unknown-rejected", state.complete_quest("ghost", 1).is_empty())


func _visit_quests() -> void:
	var state := GameState.new()
	state.accept_quest("wang_message", 2)
	_check("visit-never-turnable", not state.quest_turnable("wang_message"))
	_check("visit-progress-zero", state.quest_progress("wang_message") == 0)
	_check("visit-wrong-target-empty", state.visit_quest_for("pierre", 3).is_empty())
	_check("visit-keeps-active", state.quest_active("wang_message"))
	var rewards: Dictionary = state.visit_quest_for("marnie", 3)
	_check("visit-completes-at-target", String(rewards.get("id", "")) == "wang_message" and int(rewards.get("coins", 0)) == 30)
	_check("visit-pays-giver-friendship", int(state.npc_friendship["wang"]) == 30 and int(state.npc_friendship["marnie"]) == 0)
	_check("visit-completed-recorded", int(state.quests_completed["wang_message"]) == 3)
	_check("visit-second-visit-empty", state.visit_quest_for("marnie", 4).is_empty())
	# 传话完成后解锁同链收集委托。
	_check("visit-unlocks-chain", state.quest_available("wang_carp"))


func _rewards_and_clamps() -> void:
	var state := GameState.new()
	state.npc_friendship["clint"] = 990
	state.add_harvest("pumpkin", 0)
	state.minerals["copper"] = 4
	state.accept_quest("clint_ore", 1)
	state.complete_quest("clint_ore", 2)
	_check("friendship-clamped-at-max", int(state.npc_friendship["clint"]) == NpcDB.MAX_FRIENDSHIP)
	# 扣件品质对齐：2 条银鲤鱼 + 1 普通，交付 2 条后银剩 1。
	state.quests_completed["wang_message"] = 1  # 直接满足链式前置，聚焦品质扣件
	state.fish["carp"] = 3
	state.fish_quality["silver"]["carp"] = 2
	state.accept_quest("wang_carp", 3)
	_check("turnable-with-quality-mix", state.quest_turnable("wang_carp"))
	state.complete_quest("wang_carp", 4)
	_check("quality-aligned-after-turnin", int(state.fish["carp"]) == 1 and int(state.fish_quality["silver"]["carp"]) == 1)
	_check("active-collect-list", state.active_collect_quests().is_empty())


func _save_roundtrip() -> void:
	var state := GameState.new()
	state.accept_quest("marnie_eggs", 2)
	state.accept_quest("clint_ore", 2)
	state.minerals["copper"] = 4
	state.complete_quest("clint_ore", 3)
	var payload: Dictionary = state.to_dict()
	var snapshot: Dictionary = payload.duplicate(true)
	var restored := GameState.new()
	restored.from_dict(payload)
	_check("quests-survive-roundtrip", int(restored.quests_accepted["marnie_eggs"]) == 2 and int(restored.quests_completed["clint_ore"]) == 3)
	_check("roundtrip-gating-keeps", not restored.quest_available("marnie_wood") and restored.quest_available("marnie_eggs") == false and restored.quest_available("clint_coal"))
	var legacy := GameState.new()
	legacy.from_dict({"coins": 50})
	_check("legacy-save-no-quests", legacy.quests_accepted.is_empty() and legacy.quests_completed.is_empty())
	var dirty := {"quests": {"accepted": {"pierre_veggies": "someday", "ghost": 5}, "completed": {"clint_ore": -4, "wang_carp": 99999999}}}
	var dirty_copy: Dictionary = dirty.duplicate(true)
	var cleaned := GameState.new()
	cleaned.from_dict(dirty)
	_check("dirty-quests-sanitized", int(cleaned.quests_accepted.get("pierre_veggies", -1)) == 0 and not cleaned.quests_accepted.has("ghost") and int(cleaned.quests_completed.get("clint_ore", -1)) == 0 and int(cleaned.quests_completed["wang_carp"]) == 1000000)
	_check("dirty-input-untouched", dirty == dirty_copy)
	_check("payload-untouched", payload == snapshot)
