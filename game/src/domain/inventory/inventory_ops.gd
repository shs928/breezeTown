class_name InventoryOps
## 容器操作（ECON 唯一维护）：堆叠、整组移动、指定数量拆分、自动入包。
## 所有函数只**读取**状态并返回容器变更描述，由 TransactionCoordinator 原子应用。
## 规则（PRD 7.1 / 契约 5.4）：
## - 每格最多 99，只有相同定义 ID 可堆叠；空格无定义 ID。
## - 无指定目标格的入包：先补同类未满格，再按格序用空格；容量不足整笔失败。
## - 一次转移只递增该容器 revision 一次（来源=目标时视为一次）。

const ContractLimits := preload("res://src/contracts/contract_limits.gd")


## 计算把 (item_definition_id, quantity) 放入容器所需的槽位变更。
## 返回 {ok, changes: [{slot, item}], reason}。不修改传入容器。
static func plan_insert(container: Dictionary, item_definition_id: String, quantity: int) -> Dictionary:
	if quantity < 1 or quantity > ContractLimits.TRADE_QUANTITY_MAX:
		return {"ok": false, "changes": [], "reason": "OUT_OF_RANGE"}
	var slots: Array = container["slots"]
	var capacity: int = int(container["capacity"])
	var remaining := quantity
	var changes: Array = []
	# 1) 先补同类未满格
	for i in capacity:
		if remaining <= 0:
			break
		var slot: Variant = slots[i]
		if slot == null:
			continue
		if slot["item_definition_id"] == item_definition_id and int(slot["quantity"]) < ContractLimits.TRADE_QUANTITY_MAX:
			var space: int = ContractLimits.TRADE_QUANTITY_MAX - int(slot["quantity"])
			var add: int = min(space, remaining)
			changes.append({"slot": i, "item": {"item_definition_id": item_definition_id, "quantity": int(slot["quantity"]) + add}})
			remaining -= add
	# 2) 再用空格
	for i in capacity:
		if remaining <= 0:
			break
		if slots[i] == null:
			var put: int = min(ContractLimits.TRADE_QUANTITY_MAX, remaining)
			changes.append({"slot": i, "item": {"item_definition_id": item_definition_id, "quantity": put}})
			remaining -= put
	if remaining > 0:
		return {"ok": false, "changes": [], "reason": "INVENTORY_FULL"}
	return {"ok": true, "changes": changes, "reason": ""}


## 检查容器是否有足够的指定物品（用于出售/捐赠/播种扣减）。
## 返回 {ok, total, slots: [{slot, quantity}]}。
static func count_item(container: Dictionary, item_definition_id: String) -> Dictionary:
	var total := 0
	var hits: Array = []
	var slots: Array = container["slots"]
	for i in int(container["capacity"]):
		var slot: Variant = slots[i]
		if slot != null and slot["item_definition_id"] == item_definition_id:
			total += int(slot["quantity"])
			hits.append({"slot": i, "quantity": int(slot["quantity"])})
	return {"ok": total > 0, "total": total, "slots": hits}


## 计划从容器扣除 quantity 个指定物品（跨格扣减）。
## 返回 {ok, changes, reason}；changes 中 quantity=0 表示该格清空（应用时置 null）。
static func plan_remove(container: Dictionary, item_definition_id: String, quantity: int) -> Dictionary:
	if quantity < 1 or quantity > ContractLimits.TRADE_QUANTITY_MAX:
		return {"ok": false, "changes": [], "reason": "OUT_OF_RANGE"}
	var counted := count_item(container, item_definition_id)
	if int(counted["total"]) < quantity:
		return {"ok": false, "changes": [], "reason": "INSUFFICIENT_ITEMS"}
	var remaining := quantity
	var changes: Array = []
	for hit: Dictionary in counted["slots"]:
		if remaining <= 0:
			break
		var take: int = min(int(hit["quantity"]), remaining)
		var left := int(hit["quantity"]) - take
		changes.append({"slot": int(hit["slot"]), "item": null if left == 0 else {"item_definition_id": item_definition_id, "quantity": left}})
		remaining -= take
	return {"ok": true, "changes": changes, "reason": ""}


## 指定格的整组移动或拆分。返回 {ok, from_change, to_change, reason}。
## 拆分时 to_slot 必须为空格或同类未满格；整组移动要求目标格可容纳全部数量。
static func plan_transfer(from_container: Dictionary, from_slot: int, to_container: Dictionary, to_slot: int, quantity: int) -> Dictionary:
	if quantity < 1 or quantity > ContractLimits.TRADE_QUANTITY_MAX:
		return {"ok": false, "reason": "OUT_OF_RANGE"}
	var from_slots: Array = from_container["slots"]
	if from_slot < 0 or from_slot >= int(from_container["capacity"]) or from_slots[from_slot] == null:
		return {"ok": false, "reason": "INVALID_ARGUMENT"}
	var source: Dictionary = from_slots[from_slot]
	if int(source["quantity"]) < quantity:
		return {"ok": false, "reason": "INSUFFICIENT_ITEMS"}
	var item_id: String = source["item_definition_id"]
	var to_slots: Array = to_container["slots"]
	if to_slot < 0 or to_slot >= int(to_container["capacity"]):
		return {"ok": false, "reason": "INVALID_ARGUMENT"}
	var target: Variant = to_slots[to_slot]
	if target != null:
		if target["item_definition_id"] != item_id:
			return {"ok": false, "reason": "INVALID_ARGUMENT"}
		if int(target["quantity"]) + quantity > ContractLimits.TRADE_QUANTITY_MAX:
			return {"ok": false, "reason": "INVENTORY_FULL"}
	var source_left: int = int(source["quantity"]) - quantity
	var target_qty: int = (int(target["quantity"]) if target != null else 0) + quantity
	return {
		"ok": true,
		"reason": "",
		"from_change": {"slot": from_slot, "item": null if source_left == 0 else {"item_definition_id": item_id, "quantity": source_left}},
		"to_change": {"slot": to_slot, "item": {"item_definition_id": item_id, "quantity": target_qty}},
	}
