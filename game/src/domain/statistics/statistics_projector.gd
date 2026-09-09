class_name StatisticsProjector
## 统计投影器（ECON 唯一维护，契约 9.1）。
## 统计参与同一次业务提交（由 TransactionCoordinator 保证），本类提供两个能力：
## 1. project(events, base)：从事件序列重建统计，用于校验 checkpoint 一致性（CASE-23）。
## 2. snapshot(world)：读取只读物化视图，供榜单使用。
##
## 去重依据事件序号；已裁定在事件中的金额/分数直接采用，不按当前价格重算。

const ContractLimits := preload("res://src/contracts/contract_limits.gd")
const WorldState := preload("res://src/domain/world/world_state.gd")

## 从事件列表投影统计。base 为初始统计（默认空）。
## 返回 {members: {player_id: stats}, world_total_sales, world_total_purchases, last_event_seq, applied_count}。
static func project(events: Array, base: Dictionary = {}) -> Dictionary:
	var state := {
		"members": {},
		"world_total_sales": 0,
		"world_total_purchases": 0,
		"last_event_seq": 0,
		"applied_count": 0,
	}
	if not base.is_empty():
		state["members"] = (base.get("members", {}) as Dictionary).duplicate(true)
		state["world_total_sales"] = int(base.get("world_total_sales", 0))
		state["world_total_purchases"] = int(base.get("world_total_purchases", 0))
		state["last_event_seq"] = int(base.get("last_event_seq", 0))
	var seen_sequences := {}
	for event: Dictionary in events:
		var seq := int(event["event_sequence"])
		if seen_sequences.has(seq) or seq <= int(state["last_event_seq"]):
			continue  # 去重
		seen_sequences[seq] = true
		var actor: String = event["actor_player_id"]
		if not state["members"].has(actor):
			state["members"][actor] = _empty_stats()
		var payload: Dictionary = event["payload"]
		match str(event["event_type"]):
			"ProduceSold":
				var gross := int(payload["gross_amount"])
				state["members"][actor]["total_gross_sales"] += gross
				state["world_total_sales"] = int(state["world_total_sales"]) + gross
			"SeedPurchased":
				state["world_total_purchases"] = int(state["world_total_purchases"]) + int(payload["total_amount"])
			"CropPlanted":
				state["members"][actor]["contribution"]["planting"] += ContractLimits.POINTS_PLANT
			"CropWatered":
				state["members"][actor]["contribution"]["watering"] += ContractLimits.POINTS_WATER
			"CropHarvested":
				state["members"][actor]["contribution"]["harvesting"] += ContractLimits.POINTS_HARVEST
			"ProjectDonated":
				state["members"][actor]["contribution"]["donation"] += ContractLimits.POINTS_DONATE_PER_ITEM * int(payload.get("quantity", 0))
			_:
				pass  # 非计分事件推进水位但不改统计
		state["last_event_seq"] = seq
		state["applied_count"] = int(state["applied_count"]) + 1
	return state


## 从世界物化视图导出统计（与 project 结果可直接比较）。
static func snapshot(world: WorldState) -> Dictionary:
	var members := {}
	for player_id: String in world.stats["members"]:
		members[player_id] = (world.stats["members"][player_id] as Dictionary).duplicate(true)
	return {
		"members": members,
		"world_total_sales": int(world.stats["world_total_sales"]),
		"world_total_purchases": int(world.stats["world_total_purchases"]),
		"last_event_seq": int(world.stats["last_applied_event_seq"]),
	}


## 比较投影结果与物化视图是否一致（CASE-23）。
static func compare(projected: Dictionary, materialized: Dictionary) -> String:
	if int(projected["world_total_sales"]) != int(materialized["world_total_sales"]):
		return "world_total_sales mismatch: %d vs %d" % [projected["world_total_sales"], materialized["world_total_sales"]]
	if int(projected["world_total_purchases"]) != int(materialized["world_total_purchases"]):
		return "world_total_purchases mismatch"
	for player_id: String in materialized["members"]:
		var m: Dictionary = materialized["members"][player_id]
		var p: Dictionary = projected["members"].get(player_id, _empty_stats())
		if int(m["total_gross_sales"]) != int(p["total_gross_sales"]):
			return "member %s total_gross_sales mismatch" % player_id
		for key: String in ["planting", "watering", "harvesting", "donation"]:
			if int(m["contribution"].get(key, 0)) != int(p["contribution"].get(key, 0)):
				return "member %s contribution.%s mismatch" % [player_id, key]
	return ""


static func _empty_stats() -> Dictionary:
	return {
		"total_gross_sales": 0,
		"today_gross_sales": 0,
		"contribution": {"planting": 0, "watering": 0, "harvesting": 0, "donation": 0},
	}
