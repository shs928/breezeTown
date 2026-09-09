class_name ProjectHandler
## 公共建设（FARM 唯一维护，M3 FARM-02；PRD 第 8 章 / CASE-19）。
## 三项目按顺序解锁，需求物品来自操作者背包：
## - 请求数量超过尚缺数量 → 整笔拒绝并返回最新缺口（不暗中截短）；
## - 合法请求要么全部成功要么不改任何状态；
## - 完成效果只生效一次，重复消息不重复扩容或奖励；
## - 捐赠每个产物 +2 贡献（FARM 计分，ECON 只管物品事务）。

const ContractLimits := preload("res://src/contracts/contract_limits.gd")
const ContractError := preload("res://src/contracts/contract_error.gd")
const InventoryOps := preload("res://src/domain/inventory/inventory_ops.gd")
const ItemCatalog := preload("res://src/domain/economy/item_catalog.gd")
const WorldState := preload("res://src/domain/world/world_state.gd")
const WorldRuntime := preload("res://src/application/world/world_runtime.gd")
const TransactionCoordinator := preload("res://src/application/core/transaction_coordinator.gd")

var catalog: ItemCatalog
var _runtime: WorldRuntime


func setup(runtime: WorldRuntime, item_catalog: ItemCatalog) -> void:
	_runtime = runtime
	catalog = item_catalog
	_ensure_project_state()
	_runtime.register_handler("projects.donate", _handle_donate)


## 初始化项目状态（世界创建后调用；已存在则保留）。
func _ensure_project_state() -> void:
	var world: WorldState = _runtime.world
	if not world.projects.is_empty():
		return
	var ordered: Array = catalog.projects.values()
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["order"]) < int(b["order"]))
	for project: Dictionary in ordered:
		var accepted := {}
		for req: Dictionary in project["requires"]:
			accepted[req["item_id"]] = 0
		world.projects.append({
			"project_id": project["id"],
			"accepted_quantities": accepted,
			"completed": false,
			"completion_day": 0,
		})


## 返回项目的当前进度视图（供 UI）。
func progress(project_id: String) -> Dictionary:
	var definition: Dictionary = catalog.projects.get(project_id, {})
	var state := _project_state(project_id)
	if definition.is_empty() or state.is_empty():
		return {}
	var requirements: Array = []
	for req: Dictionary in definition["requires"]:
		var accepted := int((state["accepted_quantities"] as Dictionary).get(req["item_id"], 0))
		requirements.append({
			"item_id": req["item_id"], "required": int(req["quantity"]),
			"accepted": accepted, "remaining": int(req["quantity"]) - accepted,
		})
	return {
		"project_id": project_id,
		"name": definition["name"],
		"order": int(definition["order"]),
		"unlocked": _is_unlocked(project_id),
		"completed": bool(state["completed"]),
		"completion_day": int(state["completion_day"]),
		"requirements": requirements,
	}


func all_progress() -> Array:
	var result: Array = []
	for project: Dictionary in catalog.projects.values():
		result.append(progress(project["id"]))
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["order"]) < int(b["order"]))
	return result


# ---------- 捐赠 ----------

func _handle_donate(payload: Dictionary, player_id: String, batch: TransactionCoordinator.Batch) -> String:
	var project_id: String = payload["project_id"]
	var item_id: String = payload["item_definition_id"]
	var quantity: int = int(payload["quantity"])
	var definition: Dictionary = catalog.projects.get(project_id, {})
	if definition.is_empty():
		return ContractError.INVALID_ARGUMENT
	if not _is_unlocked(project_id):
		return ContractError.NOT_ALLOWED
	var state := _project_state(project_id)
	if bool(state["completed"]):
		return ContractError.TARGET_CHANGED  # 已完成项目不再接受
	# 该项目是否需要该物品
	var requirement := {}
	for req: Dictionary in definition["requires"]:
		if req["item_id"] == item_id:
			requirement = req
			break
	if requirement.is_empty():
		return ContractError.INVALID_ARGUMENT
	var accepted_now := int((state["accepted_quantities"] as Dictionary).get(item_id, 0))
	var remaining := int(requirement["quantity"]) - accepted_now
	if quantity > remaining:
		return ContractError.OUT_OF_RANGE  # 超过缺口整笔拒绝，返回最新缺口
	# 检查并扣除操作者背包
	var member: Dictionary = _runtime.world.find_member(player_id)
	var backpack_id: String = member["inventory_id"]
	if not _runtime.world.containers.has(backpack_id):
		return ContractError.INSUFFICIENT_ITEMS
	var remove_plan := InventoryOps.plan_remove(_runtime.world.containers[backpack_id], item_id, quantity)
	if not remove_plan["ok"]:
		return remove_plan["reason"]
	for change: Dictionary in remove_plan["changes"]:
		batch.add_op({"op": "container_set", "container_id": backpack_id, "slot": change["slot"], "item": change["item"]})
	# 更新项目接受数量
	var updated_accepted: Dictionary = (state["accepted_quantities"] as Dictionary).duplicate(true)
	updated_accepted[item_id] = accepted_now + quantity
	var completed := _is_fully_accepted(definition, updated_accepted)
	batch.add_op({
		"op": "project_state", "project_id": project_id,
		"accepted_quantities": updated_accepted,
		"completed": completed,
	})
	batch.add_contribution(player_id, "donation", ContractLimits.POINTS_DONATE_PER_ITEM * quantity)
	batch.add_event("ProjectDonated", {"project_id": project_id, "item_definition_id": item_id, "quantity": quantity}, player_id)
	# 完成：应用效果（只生效一次，由 completed 标志保证）
	if completed:
		_apply_effect(definition, batch)
		batch.add_event("ProjectCompleted", {"project_id": project_id, "game_day": _runtime.world.game_day}, player_id)
	return ""


## 应用项目效果。同一项目只在首次完成时调用（调用方以 completed 转换保证）。
func _apply_effect(definition: Dictionary, batch: TransactionCoordinator.Batch) -> void:
	var effect: Dictionary = definition["effect"]
	match str(effect["type"]):
		"expand_farm":
			# 耕地容量扩至 256：由地图数据决定可耕格；此处记录解锁上限
			batch.add_op({"op": "farm_capacity", "capacity": int(effect["to_plots"])})
		"expand_storage":
			batch.add_op({"op": "container_resize", "container_id": "shared_storage", "capacity": int(effect["to_slots"])})
		"monument":
			batch.add_op({"op": "mark_monument", "game_day": _runtime.world.game_day})


func _project_state(project_id: String) -> Dictionary:
	for state: Dictionary in _runtime.world.projects:
		if state["project_id"] == project_id:
			return state
	return {}


func _is_unlocked(project_id: String) -> bool:
	var definition: Dictionary = catalog.projects.get(project_id, {})
	if definition.is_empty():
		return false
	var requires_after: Variant = definition["requires_after"]
	if requires_after == null:
		return true
	var previous := _project_state(str(requires_after))
	return not previous.is_empty() and bool(previous["completed"])


func _is_fully_accepted(definition: Dictionary, accepted: Dictionary) -> bool:
	for req: Dictionary in definition["requires"]:
		if int(accepted.get(req["item_id"], 0)) < int(req["quantity"]):
			return false
	return true
