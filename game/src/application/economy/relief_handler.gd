class_name ReliefHandler
## 经营救济（ECON 唯一维护，M3 ECON-04；PRD 7.3 / CASE-20）。
## 领取条件必须同时满足：
##   1. 农场资金 < 最低种子价格（12）；
##   2. 没有任何存活作物；
##   3. 所有成员背包（含离线）与共享仓库都没有种子或可出售产物。
## 每世界每游戏日最多成功领取一次；发放 5 粒萝卜种子到共享仓库；仓库无空间不消耗资格。
## 发放本身不产生收益和贡献。

const ContractLimits := preload("res://src/contracts/contract_limits.gd")
const ContractError := preload("res://src/contracts/contract_error.gd")
const InventoryOps := preload("res://src/domain/inventory/inventory_ops.gd")
const ItemCatalog := preload("res://src/domain/economy/item_catalog.gd")
const WorldState := preload("res://src/domain/world/world_state.gd")
const WorldRuntime := preload("res://src/application/world/world_runtime.gd")
const TransactionCoordinator := preload("res://src/application/core/transaction_coordinator.gd")

const RELIEF_SEEDS := 5
const RELIEF_SEED_ID := "seed.radish"

var catalog: ItemCatalog
var _runtime: WorldRuntime
var _last_claim_day := 0   # 每个世界一个实例；持久化由 DATA-01 快照携带


func setup(runtime: WorldRuntime, item_catalog: ItemCatalog) -> void:
	_runtime = runtime
	catalog = item_catalog
	_runtime.register_handler("economy.claim_relief", _handle_claim)


## 检查领取条件。返回 {ok, reason}。
func can_claim() -> Dictionary:
	var world: WorldState = _runtime.world
	# 当日已领优先判定：否则资金仍为 0 时会误报“资金不足”，掩盖真正的重复领取。
	if _last_claim_day == world.game_day:
		return {"ok": false, "reason": "already_claimed_today"}
	var min_seed_price := _min_seed_price()
	if world.treasury >= min_seed_price:
		return {"ok": false, "reason": "still_has_funds"}
	if not world.crops.is_empty():
		return {"ok": false, "reason": "living_crops"}
	if _has_seeds_or_produce():
		return {"ok": false, "reason": "has_items"}
	return {"ok": true, "reason": ""}


func _handle_claim(_payload: Dictionary, player_id: String, batch: TransactionCoordinator.Batch) -> String:
	var check := can_claim()
	if not check["ok"]:
		# 已领取过当日 → 视为业务失败；条件不满足 → 明确拒绝
		return ContractError.NOT_ALLOWED if check["reason"] == "already_claimed_today" else ContractError.INSUFFICIENT_FUNDS
	var storage: Dictionary = _runtime.world.containers["shared_storage"]
	var plan := InventoryOps.plan_insert(storage, RELIEF_SEED_ID, RELIEF_SEEDS)
	if not plan["ok"]:
		return ContractError.INVENTORY_FULL  # 仓库无空间不消耗领取资格
	for change: Dictionary in plan["changes"]:
		batch.add_op({"op": "container_set", "container_id": "shared_storage", "slot": change["slot"], "item": change["item"]})
	# 发放本身不产生收益和贡献（PRD 7.3）
	batch.add_event("ReliefGranted", {"seed_definition_id": RELIEF_SEED_ID, "quantity": RELIEF_SEEDS}, player_id)
	_last_claim_day = _runtime.world.game_day
	return ""


func last_claim_day() -> int:
	return _last_claim_day


func _min_seed_price() -> int:
	var minimum := ContractLimits.MAX_BUSINESS_INT
	for crop: Dictionary in catalog.crops.values():
		minimum = min(minimum, int(crop["seed_price"]))
	return minimum


## 所有成员背包（含离线）与共享仓库中是否有种子或可出售产物。
func _has_seeds_or_produce() -> bool:
	for container_id: String in _runtime.world.containers:
		var container: Dictionary = _runtime.world.containers[container_id]
		for slot: Variant in container["slots"]:
			if slot == null:
				continue
			var item_id: String = slot["item_definition_id"]
			if catalog.is_seed(item_id) or catalog.is_produce(item_id):
				return true
	return false
