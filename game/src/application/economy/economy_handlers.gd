class_name EconomyHandlers
## ECON 命令处理器（ECON 唯一维护）。注册到 WorldRuntime 后与本地/远端命令共用同一路径。
## 处理器只构造提交计划；价格、金额一律取自服务端 ItemCatalog，客户端不得提交。

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
	_runtime.register_handler("inventory.transfer", _handle_transfer)
	_runtime.register_handler("economy.buy_seed", _handle_buy_seed)
	_runtime.register_handler("economy.sell", _handle_sell)


## 确保成员背包存在（ECON 按合法成员 ID 初始化，不生成凭据）。
func ensure_backpack(player_id: String) -> String:
	var world: WorldState = _runtime.world
	var member: Dictionary = world.find_member(player_id)
	if member.is_empty():
		return ContractError.NOT_AUTHENTICATED
	var inventory_id: String = member["inventory_id"]
	if not world.containers.has(inventory_id):
		world.containers[inventory_id] = {
			"capacity": ContractLimits.BACKPACK_SLOTS,
			"slots": WorldState.empty_slots(ContractLimits.BACKPACK_SLOTS),
			"revision": 0,
		}
	return ""


func _resolve_container(ref: String, player_id: String) -> Dictionary:
	if ref == "shared_storage":
		return _runtime.world.containers["shared_storage"]
	var member: Dictionary = _runtime.world.find_member(player_id)
	if not member.is_empty() and ref == "backpack:" + player_id:
		return _runtime.world.containers.get(member["inventory_id"], {})
	return {}


# ---------- inventory.transfer ----------

func _handle_transfer(payload: Dictionary, player_id: String, batch: TransactionCoordinator.Batch) -> String:
	var err := ensure_backpack(player_id)
	if not err.is_empty():
		return err
	var from_ref: String = payload["from_container"]
	var to_ref: String = payload["to_container"]
	# 转移只允许本人背包内部、本人背包与共享仓库之间（PRD 7.1）。
	for ref: String in [from_ref, to_ref]:
		if ref != "shared_storage" and ref != "backpack:" + player_id:
			return ContractError.NOT_ALLOWED
	var from_container := _resolve_container(from_ref, player_id)
	var to_container := _resolve_container(to_ref, player_id)
	if from_container.is_empty() or to_container.is_empty():
		return ContractError.INVALID_ARGUMENT
	var plan := InventoryOps.plan_transfer(from_container, int(payload["from_slot"]), to_container, int(payload["to_slot"]), int(payload["quantity"]))
	if not plan["ok"]:
		return plan["reason"]
	batch.add_op({"op": "container_set", "container_id": from_ref if from_ref == "shared_storage" else "backpack:" + player_id, "slot": plan["from_change"]["slot"], "item": plan["from_change"]["item"]})
	batch.add_op({"op": "container_set", "container_id": to_ref if to_ref == "shared_storage" else "backpack:" + player_id, "slot": plan["to_change"]["slot"], "item": plan["to_change"]["item"]})
	batch.add_event("ItemsTransferred", {
		"from_container": from_ref, "to_container": to_ref,
		"item_definition_id": plan["to_change"]["item"]["item_definition_id"],
		"quantity": int(payload["quantity"]),
	}, player_id)
	return ""


# ---------- economy.buy_seed ----------

func _handle_buy_seed(payload: Dictionary, player_id: String, batch: TransactionCoordinator.Batch) -> String:
	var err := ensure_backpack(player_id)
	if not err.is_empty():
		return err
	var seed_id: String = payload["seed_definition_id"]
	if not catalog.is_seed(seed_id):
		return ContractError.INVALID_ARGUMENT
	var quantity: int = int(payload["quantity"])
	var unit_price := catalog.seed_price(seed_id)
	if unit_price <= 0:
		return ContractError.INVALID_ARGUMENT
	var total := unit_price * quantity
	if _runtime.world.treasury < total:
		return ContractError.INSUFFICIENT_FUNDS
	var backpack_id := "backpack:" + player_id
	var plan := InventoryOps.plan_insert(_runtime.world.containers[backpack_id], seed_id, quantity)
	if not plan["ok"]:
		return plan["reason"]
	for change: Dictionary in plan["changes"]:
		batch.add_op({"op": "container_set", "container_id": backpack_id, "slot": change["slot"], "item": change["item"]})
	batch.add_op({"op": "treasury_delta", "delta": -total})
	batch.add_op({"op": "world_total_purchases", "delta": total})
	batch.add_event("SeedPurchased", {
		"seed_definition_id": seed_id, "quantity": quantity,
		"unit_price": unit_price, "total_amount": total,
	}, player_id)
	return ""


# ---------- economy.sell ----------

func _handle_sell(payload: Dictionary, player_id: String, batch: TransactionCoordinator.Batch) -> String:
	var err := ensure_backpack(player_id)
	if not err.is_empty():
		return err
	var item_id: String = payload["item_definition_id"]
	# 只接受作物产物；种子/工具不可售（PRD 7.2、CASE-14）。
	if not catalog.is_produce(item_id):
		return ContractError.INVALID_ARGUMENT
	var quantity: int = int(payload["quantity"])
	var unit_price := catalog.sell_price(item_id)
	if unit_price <= 0:
		return ContractError.INVALID_ARGUMENT
	var backpack_id := "backpack:" + player_id
	var slot: int = int(payload["slot"])
	var slots: Array = _runtime.world.containers[backpack_id]["slots"]
	if slot < 0 or slot >= slots.size() or slots[slot] == null:
		return ContractError.INVALID_ARGUMENT
	if slots[slot]["item_definition_id"] != item_id:
		return ContractError.INVALID_ARGUMENT
	if int(slots[slot]["quantity"]) < quantity:
		return ContractError.INSUFFICIENT_ITEMS
	var gross := unit_price * quantity
	var left := int(slots[slot]["quantity"]) - quantity
	batch.add_op({"op": "container_set", "container_id": backpack_id, "slot": slot, "item": null if left == 0 else {"item_definition_id": item_id, "quantity": left}})
	batch.add_op({"op": "treasury_delta", "delta": gross})
	batch.add_op({"op": "world_total_sales", "delta": gross})
	batch.add_stat(player_id, "total_gross_sales", gross)
	batch.add_stat(player_id, "today_gross_sales", gross)
	batch.add_event("ProduceSold", {
		"item_definition_id": item_id, "quantity": quantity,
		"unit_price": unit_price, "gross_amount": gross,
	}, player_id)
	return ""
