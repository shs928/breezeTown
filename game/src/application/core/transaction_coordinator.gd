class_name TransactionCoordinator
## 原子业务提交（契约 5.3、NFR-01）。处理器不直接改权威状态，而是返回一个“提交计划”；
## 本类先整体校验计划，再一次性应用状态、统计与事件，任一环节失败则整批丢弃。
##
## 这样做的原因：Godot 单线程写队列下，逐字段回滚容易遗漏；先构造后应用更易证明“全有或全无”。
## 提交计划的语义：所有操作都针对“应用后的状态”进行前置校验，不允许半提交。

const ContractLimits := preload("res://src/contracts/contract_limits.gd")
const WorldState := preload("res://src/domain/world/world_state.gd")

## 计划结构：
## {
##   "ops": [ {op, ...}, ... ],   # 见 _apply_op
##   "events": [ {event_type, payload, actor_player_id}, ... ],
##   "stat_ops": [ {player_id, field, amount} | {player_id, contribution_key, amount} ],
## }
class Batch:
	var ops: Array = []
	var events: Array = []
	var stat_ops: Array = []

	func add_op(op: Dictionary) -> void:
		ops.append(op)

	func add_event(event_type: String, payload: Dictionary, actor_player_id: String) -> void:
		events.append({"event_type": event_type, "payload": payload, "actor_player_id": actor_player_id})

	func add_stat(player_id: String, field: String, amount: int) -> void:
		stat_ops.append({"player_id": player_id, "field": field, "amount": amount})

	## 贡献计分（分类明确，避免调用方手工拼 stat_op）。
	func add_contribution(player_id: String, contribution_key: String, amount: int) -> void:
		stat_ops.append({"player_id": player_id, "field": "contribution", "contribution_key": contribution_key, "amount": amount})


## 校验计划（不修改状态）。返回空串=合法。
static func validate(world: WorldState, batch: Batch) -> String:
	for op: Dictionary in batch.ops:
		var err := _validate_op(world, op)
		if not err.is_empty():
			return err
	for stat_op: Dictionary in batch.stat_ops:
		if not world.member_exists(stat_op["player_id"]):
			return "CONTRACTS_STAT_UNKNOWN_MEMBER"
		if stat_op["field"] == "contribution":
			if not ContractLimits.POINTS_NON_SCORING <= int(stat_op["amount"]):
				return "CONTRACTS_STAT_NEGATIVE"
		elif int(stat_op["amount"]) < 0 and stat_op["field"] in ["total_gross_sales", "today_gross_sales"]:
			return "CONTRACTS_STAT_NEGATIVE"
	return ""


## 应用计划：调用方必须先 validate 成功。返回新的事件序号列表。
static func apply(world: WorldState, batch: Batch, game_day: int) -> Array:
	var committed_events: Array = []
	for op: Dictionary in batch.ops:
		_apply_op(world, op)
	for stat_op: Dictionary in batch.stat_ops:
		_apply_stat(world, stat_op)
	for event_spec: Dictionary in batch.events:
		var event := {
			"event_id": "ev" + Crypto.new().generate_random_bytes(16).hex_encode(),
			"event_sequence": world.next_event_seq,
			"world_id": world.world_id,
			"business_revision": world.business_revision + 1,
			"actor_player_id": event_spec["actor_player_id"],
			"game_day": game_day,
			"event_type": event_spec["event_type"],
			"ruleset_version": world.ruleset_version,
			"payload": event_spec["payload"],
		}
		world.next_event_seq += 1
		committed_events.append(event)
	world.stats["last_applied_event_seq"] = world.next_event_seq - 1
	world.business_revision += 1
	return committed_events


static func _validate_op(world: WorldState, op: Dictionary) -> String:
	match str(op.get("op", "")):
		"set_plot":
			if not op.has_all(["tile_id", "plot"]):
				return "CONTRACTS_OP_FIELD"
			var tile := int(op["tile_id"])
			if tile < 0 or tile >= ContractLimits.MAP_W * ContractLimits.MAP_H:
				return "CONTRACTS_OP_TILE_RANGE"
		"set_crop":
			if not op.has_all(["crop_instance_id", "crop"]):
				return "CONTRACTS_OP_FIELD"
			if not (op["crop"] as Dictionary).has_all(["crop_definition_id", "tile_id", "growth_days"]):
				return "CONTRACTS_OP_CROP_FIELD"
		"remove_crop":
			if not op.has("crop_instance_id"):
				return "CONTRACTS_OP_FIELD"
		"container_set":
			if not op.has_all(["container_id", "slot", "item"]):
				return "CONTRACTS_OP_FIELD"
			var container: Variant = world.containers.get(op["container_id"], null)
			if container == null:
				return "CONTRACTS_OP_UNKNOWN_CONTAINER"
			var slot := int(op["slot"])
			if slot < 0 or slot >= int(container["capacity"]):
				return "CONTRACTS_OP_SLOT_RANGE"
			var item: Variant = op["item"]
			if item != null:
				if not (item as Dictionary).has_all(["item_definition_id", "quantity"]):
					return "CONTRACTS_OP_ITEM_FIELD"
				var qty := int((item as Dictionary)["quantity"])
				if qty < 1 or qty > ContractLimits.TRADE_QUANTITY_MAX:
					return "CONTRACTS_OP_ITEM_QTY"
		"container_resize":
			if not op.has_all(["container_id", "capacity"]):
				return "CONTRACTS_OP_FIELD"
			if int(op["capacity"]) < 1 or int(op["capacity"]) > ContractLimits.SHARED_STORAGE_SLOTS_EXPANDED:
				return "CONTRACTS_OP_CAPACITY"
		"treasury_delta":
			if not op.has("delta"):
				return "CONTRACTS_OP_FIELD"
			if world.treasury + int(op["delta"]) < 0:
				return "INSUFFICIENT_FUNDS"
		"world_total_sales":
			if not op.has("delta") or int(op["delta"]) < 0:
				return "CONTRACTS_OP_FIELD"
		"world_total_purchases":
			if not op.has("delta") or int(op["delta"]) < 0:
				return "CONTRACTS_OP_FIELD"
		"member_position":
			if not op.has_all(["player_id", "x", "y"]):
				return "CONTRACTS_OP_FIELD"
			if not world.member_exists(op["player_id"]):
				return "CONTRACTS_OP_UNKNOWN_MEMBER"
		"member_display_name":
			if not op.has_all(["player_id", "display_name"]):
				return "CONTRACTS_OP_FIELD"
			if ContractLimits.sanitize_display_name(op["display_name"]).is_empty():
				return "INVALID_ARGUMENT"
		"project_state":
			if not op.has_all(["project_id", "accepted_quantities"]):
				return "CONTRACTS_OP_FIELD"
		"farm_capacity":
			if not op.has("capacity") or int(op["capacity"]) != ContractLimits.TILLABLE_EXPANDED:
				return "CONTRACTS_OP_CAPACITY"
		"mark_monument":
			if not op.has("game_day"):
				return "CONTRACTS_OP_FIELD"
		_:
			return "CONTRACTS_OP_UNKNOWN:" + str(op.get("op", ""))
	return ""


static func _apply_op(world: WorldState, op: Dictionary) -> void:
	match str(op["op"]):
		"set_plot":
			world.plots[str(int(op["tile_id"]))] = op["plot"]
		"set_crop":
			world.crops[op["crop_instance_id"]] = op["crop"]
		"remove_crop":
			world.crops.erase(op["crop_instance_id"])
		"container_set":
			var container: Dictionary = world.containers[op["container_id"]]
			container["slots"][int(op["slot"])] = op["item"]
			container["revision"] = int(container["revision"]) + 1
		"container_resize":
			var container2: Dictionary = world.containers[op["container_id"]]
			var new_capacity := int(op["capacity"])
			var slots: Array = container2["slots"]
			while slots.size() < new_capacity:
				slots.append(null)
			container2["capacity"] = new_capacity
			container2["revision"] = int(container2["revision"]) + 1
		"treasury_delta":
			world.treasury += int(op["delta"])
		"world_total_sales":
			world.stats["world_total_sales"] = int(world.stats["world_total_sales"]) + int(op["delta"])
		"world_total_purchases":
			world.stats["world_total_purchases"] = int(world.stats["world_total_purchases"]) + int(op["delta"])
		"member_position":
			var member := world.find_member(op["player_id"])
			if not member.is_empty():
				member["last_valid_position"] = {"x": float(op["x"]), "y": float(op["y"])}
		"member_display_name":
			var member2 := world.find_member(op["player_id"])
			if not member2.is_empty():
				member2["display_name"] = ContractLimits.sanitize_display_name(op["display_name"])
		"project_state":
			for i in world.projects.size():
				if world.projects[i]["project_id"] == op["project_id"]:
					world.projects[i]["accepted_quantities"] = op["accepted_quantities"]
					if op.has("completed") and op["completed"]:
						world.projects[i]["completed"] = true
						world.projects[i]["completion_day"] = world.game_day
					return
		"farm_capacity":
			world.stats["farm_capacity"] = int(op["capacity"])
		"mark_monument":
			world.stats["monument_completed_day"] = int(op["game_day"])


static func _apply_stat(world: WorldState, stat_op: Dictionary) -> void:
	var member_stats: Dictionary = world.stats["members"][stat_op["player_id"]]
	if stat_op["field"] == "contribution":
		var key: String = stat_op["contribution_key"]
		member_stats["contribution"][key] = int(member_stats["contribution"][key]) + int(stat_op["amount"])
	else:
		member_stats[stat_op["field"]] = int(member_stats[stat_op["field"]]) + int(stat_op["amount"])


## 长期不变量校验（契约 5.4）。返回空串=全部成立。
static func check_invariants(world: WorldState) -> String:
	if world.treasury != ContractLimits.INITIAL_TREASURY + int(world.stats["world_total_sales"]) - int(world.stats["world_total_purchases"]):
		return "INVARIANT_TREASURY: %d != %d + %d - %d" % [world.treasury, ContractLimits.INITIAL_TREASURY, world.stats["world_total_sales"], world.stats["world_total_purchases"]]
	var sum_sales := 0
	for player_id: String in world.stats["members"]:
		sum_sales += int(world.stats["members"][player_id]["total_gross_sales"])
	if sum_sales != int(world.stats["world_total_sales"]):
		return "INVARIANT_MEMBER_SALES_SUM"
	for container_id: String in world.containers:
		var container: Dictionary = world.containers[container_id]
		if container["slots"].size() > int(container["capacity"]):
			return "INVARIANT_CONTAINER_CAPACITY:" + container_id
		for slot: Variant in container["slots"]:
			if slot == null:
				continue
			var qty := int((slot as Dictionary)["quantity"])
			if qty < 1 or qty > ContractLimits.TRADE_QUANTITY_MAX:
				return "INVARIANT_SLOT_QTY:" + container_id
	return ""
