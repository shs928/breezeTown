extends SceneTree
## NPC-01 领域检查：人设数据完整性、日程数学、好感规则、送礼扣件与存读档。

const GameState := preload("res://scripts/game_state.gd")
const NpcDB := preload("res://scripts/data/npc_db.gd")
const ItemDB := preload("res://scripts/data/item_db.gd")

var failures: Array[String] = []
var count := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_data_integrity()
	_schedule_math()
	_friendship_rules()
	_gift_items()
	_save_roundtrip()
	print("NPC_DOMAIN_RESULT %s %d checks" % ["PASS" if failures.is_empty() else "FAIL " + ",".join(failures), count])
	quit(0 if failures.is_empty() else 1)


func _check(label: String, result: bool) -> void:
	count += 1
	print("NPC %s %s" % [label, "OK" if result else "FAIL"])
	if not result:
		failures.append(label)


func _data_integrity() -> void:
	for id in NpcDB.ORDER:
		var entry: Dictionary = NpcDB.NPCS[id]
		_check("label-nonempty-" + id, String(entry["label"]).length() > 0)
		_check("role-nonempty-" + id, String(entry["role"]).length() > 0)
		_check("greet-nonempty-" + id, String(entry["greet"]).length() > 0)
		# 色板齐全（帽子允许为空）。
		for key in ["coat", "pants", "hair"]:
			_check("palette-" + key + "-" + id, String(entry["palette"].get(key, "")).length() > 0)
		# 日程锚点与时段。
		var schedule: Array = entry["schedule"]
		_check("schedule-sorted-" + id, float(schedule[0]["from"]) == 6.0)
		for index in range(schedule.size() - 1):
			_check("schedule-contiguous-" + id, float(schedule[index]["to"]) == float(schedule[index + 1]["from"]))
		_check("schedule-covers-day-" + id, float(schedule[schedule.size() - 1]["to"]) == 30.0)
		for slot: Dictionary in schedule:
			_check("schedule-anchor-" + id + "-" + slot["anchor"], String(slot["anchor"]).length() > 0 and float(slot.get("wander", 1.0)) > 0.0)
		# 闲聊池三档非空，受礼四档非空。
		for tier in ["low", "mid", "high"]:
			_check("chat-" + tier + "-" + id, (entry["chat"][tier] as Array).size() >= 2)
		for tier in ["loves", "likes", "neutral", "hates"]:
			_check("gift-react-" + tier + "-" + id, String(entry["gift_react"][tier]).length() > 0)
		# 喜好物品必须是可赠送物品 id（六族之一）。
		for tier in ["loves", "likes", "hates"]:
			for item in entry[tier]:
				var item_type: String = ItemDB.item_type(item)
				_check("gift-id-valid-" + id + "-" + item, item_type in ["crop", "animal_product", "fish", "forage", "resource"])
	_check("roster-four-npcs", NpcDB.ORDER.size() == 4)


func _schedule_math() -> void:
	_check("morning-first-slot", NpcDB.schedule_at("pierre", 7.5)["anchor"] == "site:shop")
	_check("workday-noon", NpcDB.schedule_at("pierre", 12.0)["anchor"] == "site:shop")
	_check("evening-square", NpcDB.schedule_at("pierre", 18.0)["anchor"] == "town_square")
	_check("night-returns", NpcDB.schedule_at("pierre", 22.0)["anchor"] == "site:shop")
	_check("late-night-folds-to-last", NpcDB.schedule_at("pierre", 28.0)["anchor"] == "site:shop")
	_check("dawn-before-six-folds", NpcDB.schedule_at("pierre", 3.0)["anchor"] == NpcDB.entry("pierre")["schedule"][0]["anchor"])
	_check("marnie-barn-morning", NpcDB.schedule_at("marnie", 8.0)["anchor"] == "site:npc_barn")
	_check("marnie-lunch-home", NpcDB.schedule_at("marnie", 13.0)["anchor"] == "site:npc_farmhouse")
	_check("clint-inn-evening", NpcDB.schedule_at("clint", 19.0)["anchor"] == "site:inn")
	_check("wang-lake-day", NpcDB.schedule_at("wang", 10.0)["anchor"] == "lake_view")
	# 边界左闭右开。
	_check("boundary-inclusive-start", NpcDB.schedule_at("pierre", 17.0)["anchor"] == "town_square")
	_check("boundary-exclusive-end", NpcDB.schedule_at("pierre", 21.0)["anchor"] == "site:shop")


func _friendship_rules() -> void:
	var state := GameState.new()
	_check("friendship-starts-zero", int(state.npc_friendship["pierre"]) == 0 and state.npc_hearts("pierre") == 0)
	_check("first-talk-gains", state.npc_talk("pierre", 1) == NpcDB.TALK_FRIENDSHIP and int(state.npc_friendship["pierre"]) == NpcDB.TALK_FRIENDSHIP)
	_check("same-day-talk-no-gain", state.npc_talk("pierre", 1) == 0 and int(state.npc_friendship["pierre"]) == NpcDB.TALK_FRIENDSHIP)
	_check("next-day-talk-gains", state.npc_talk("pierre", 2) == NpcDB.TALK_FRIENDSHIP)
	_check("unknown-npc-rejected", state.npc_talk("ghost", 1) == 0)
	state.npc_friendship["pierre"] = NpcDB.MAX_FRIENDSHIP - 3
	state.npc_talk("pierre", 3)
	_check("friendship-capped", int(state.npc_friendship["pierre"]) == NpcDB.MAX_FRIENDSHIP)
	_check("hearts-ten-at-max", state.npc_hearts("pierre") == 10)
	state.npc_friendship["clint"] = 299
	_check("tier-low", NpcDB.friendship_tier(int(state.npc_friendship["clint"])) == "low")
	state.npc_friendship["clint"] = 300
	_check("tier-mid", NpcDB.friendship_tier(int(state.npc_friendship["clint"])) == "mid")
	state.npc_friendship["clint"] = 700
	_check("tier-high", NpcDB.friendship_tier(int(state.npc_friendship["clint"])) == "high")
	_check("met-flag", state.npc_met("pierre") and not state.npc_met("wang"))


func _gift_items() -> void:
	var state := GameState.new()
	state.add_harvest("radish", 2)
	state.add_fish("koi", 1)
	state.add_forage("mushroom", 3)
	state.products["milk"] = 1
	var giftable := state.giftable_items()
	_check("giftable-lists-families", giftable.has("radish") and giftable.has("koi") and giftable.has("mushroom") and giftable.has("milk"))
	_check("giftable-excludes-empty", not giftable.has("pumpkin"))
	_check("remove-harvest", state.remove_gift_item("radish") and int(state.harvest["radish"]) == 1)
	_check("remove-fish", state.remove_gift_item("koi") and int(state.fish["koi"]) == 0)
	_check("remove-forage", state.remove_gift_item("mushroom") and int(state.forage["mushroom"]) == 2)
	_check("remove-product", state.remove_gift_item("milk") and int(state.products["milk"]) == 0)
	_check("remove-empty-fails", not state.remove_gift_item("koi"))
	# 送礼好感：每日一份、四档数值、hates 可下降但不清零下限。
	var before: int = state.npc_gift("wang", 5, "loves")
	_check("gift-loves", before == 60 and int(state.npc_friendship["wang"]) == 60)
	_check("gift-once-per-day", state.npc_gift("wang", 5, "likes") == 0 and int(state.npc_friendship["wang"]) == 60)
	_check("gifted-today-flag", state.npc_gifted_today("wang", 5) and not state.npc_gifted_today("wang", 6))
	_check("gift-next-day", state.npc_gift("wang", 6, "hates") == -30 and int(state.npc_friendship["wang"]) == 30)
	state.npc_friendship["wang"] = 10
	state.npc_gift("wang", 7, "hates")
	_check("gift-hates-floored", int(state.npc_friendship["wang"]) == 0)
	_check("gift-unknown-tier", state.npc_gift("wang", 8, "wild") == 0)
	_check("tier-lookup", NpcDB.gift_tier("wang", "koi") == "loves" and NpcDB.gift_tier("wang", "shell") == "likes" and NpcDB.gift_tier("wang", "stone") == "hates" and NpcDB.gift_tier("wang", "radish") == "neutral")
	# 台词接口：三档取池、受礼四档。
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var lines := {}
	for attempt in range(20):
		lines[NpcDB.chat_line("pierre", 0, rng)] = true
	_check("chat-line-from-low-pool", lines.size() >= 2)
	_check("gift-line-loves", NpcDB.gift_line("pierre", "loves") == NpcDB.NPCS["pierre"]["gift_react"]["loves"])
	# 银品质鱼扣件时优先扣普通。
	state.fish["carp"] = 2
	state.fish_quality["silver"]["carp"] = 1
	state.remove_gift_item("carp")
	_check("quality-take-normal-first", int(state.fish["carp"]) == 1 and int(state.fish_quality["silver"]["carp"]) == 1)
	state.remove_gift_item("carp")
	_check("quality-take-silver-next", int(state.fish["carp"]) == 0 and int(state.fish_quality["silver"]["carp"]) == 0)


func _save_roundtrip() -> void:
	var state := GameState.new()
	state.npc_friendship["pierre"] = 420
	state.npc_last_talk["pierre"] = 12
	state.npc_last_gift["wang"] = 12
	var payload: Dictionary = state.to_dict()
	var snapshot: Dictionary = payload.duplicate(true)
	var restored := GameState.new()
	restored.from_dict(payload)
	_check("npc-survives-roundtrip", int(restored.npc_friendship["pierre"]) == 420 and int(restored.npc_last_talk["pierre"]) == 12 and int(restored.npc_last_gift["wang"]) == 12)
	_check("roundtrip-zero-untouched", int(restored.npc_friendship["wang"]) == 0)
	var legacy := GameState.new()
	legacy.from_dict({"coins": 50})
	_check("legacy-save-zero-npc", int(legacy.npc_friendship["pierre"]) == 0 and int(legacy.npc_last_talk["pierre"]) == 0 and int(legacy.npc_last_gift["pierre"]) == 0)
	var dirty := {"npc": {"friendship": {"pierre": "high", "ghost": 900, "wang": 5000}, "talk": {"wang": "yesterday"}, "gift": {}}}
	var dirty_copy: Dictionary = dirty.duplicate(true)
	var cleaned := GameState.new()
	cleaned.from_dict(dirty)
	_check("dirty-npc-sanitized", int(cleaned.npc_friendship["pierre"]) == 0 and int(cleaned.npc_friendship["wang"]) == NpcDB.MAX_FRIENDSHIP and not cleaned.npc_friendship.has("ghost") and int(cleaned.npc_last_talk["wang"]) == 0)
	_check("dirty-input-untouched", dirty == dirty_copy)
	_check("payload-untouched", payload == snapshot)
