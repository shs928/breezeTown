extends SceneTree
## ECON-01 测试（headless）：背包/堆叠/转移、共享资金、购买种子、出售作物、对账不变量。
## 运行：godot --headless --path game --script res://tests/unit/economy/test_runner.gd

const ContractLimits := preload("res://src/contracts/contract_limits.gd")
const ContractError := preload("res://src/contracts/contract_error.gd")
const WorldState := preload("res://src/domain/world/world_state.gd")
const WorldRuntime := preload("res://src/application/world/world_runtime.gd")
const TransactionCoordinator := preload("res://src/application/core/transaction_coordinator.gd")
const ItemCatalog := preload("res://src/domain/economy/item_catalog.gd")
const InventoryOps := preload("res://src/domain/inventory/inventory_ops.gd")
const EconomyHandlers := preload("res://src/application/economy/economy_handlers.gd")

var _checks := 0
var _failures: PackedStringArray = []
var _seq := {}


func _initialize() -> void:
	_test_catalog()
	_test_inventory_planning()
	_test_buy_seed()
	_test_sell_produce()
	_test_transfer_and_storage()
	_test_reconciliation()

	if _failures.is_empty():
		print("ECON_OK checks=%d" % _checks)
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: " + f)
		printerr("ECON_FAILED checks=%d failures=%d" % [_checks, _failures.size()])
		quit(1)


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(label)


func _make() -> Array:
	var world_id := "w" + "0123456789abcdef0123456789abcdef"
	var owner_id := "m" + "11111111111111111111111111111111"
	var world := WorldState.create(world_id, owner_id, "房主")
	var runtime := WorldRuntime.new()
	runtime.setup(world, {})
	var catalog := ItemCatalog.load_from_disk()
	var handlers := EconomyHandlers.new()
	handlers.setup(runtime, catalog)
	return [runtime, catalog, handlers, owner_id]


func _cmd(runtime: WorldRuntime, player_id: String, command_type: String, payload: Dictionary) -> Dictionary:
	var rid := runtime.get_instance_id()
	if not _seq.has(rid):
		_seq[rid] = {}
	_seq[rid][player_id] = int(_seq[rid].get(player_id, 0)) + 1
	return runtime.submit({
		"protocol_version": 1,
		"world_id": runtime.world.world_id,
		"authority_epoch": runtime.world.authority_epoch,
		"client_sequence": _seq[rid][player_id],
		"command_type": command_type,
		"payload": payload,
		"_actor_player_id": player_id,
	})


# ---------- 1. 目录 ----------

func _test_catalog() -> void:
	var ctx := _make()
	var catalog: ItemCatalog = ctx[1]
	_check(catalog.items.size() == 10, "10 items loaded")
	_check(catalog.crops.size() == 5, "5 crops loaded")
	_check(catalog.seed_price("seed.radish") == 15, "radish seed price 15")
	_check(catalog.sell_price("produce.radish") == 24, "radish sell price 24")
	_check(catalog.seed_price("seed.strawberry") == 50, "strawberry seed price 50")
	_check(catalog.is_seed("seed.wheat") and not catalog.is_produce("seed.wheat"), "seed kind")
	_check(catalog.is_produce("produce.potato") and not catalog.is_seed("produce.potato"), "produce kind")
	_check(catalog.crop_id_of("seed.carrot") == "crop.carrot", "seed maps to crop")
	_check(not ItemCatalog.content_hash().is_empty(), "content hash available")


# ---------- 2. 库存计划（纯函数） ----------

func _test_inventory_planning() -> void:
	var container := {"capacity": 3, "slots": [
		{"item_definition_id": "seed.radish", "quantity": 98},
		null,
		{"item_definition_id": "produce.wheat", "quantity": 5},
	]}
	# 先补同类未满格（+1 到 99），其余入空格
	var plan := InventoryOps.plan_insert(container, "seed.radish", 5)
	_check(plan["ok"], "insert plan ok")
	_check(plan["changes"].size() == 2, "insert fills stack then empty slot")
	_check(plan["changes"][0]["item"]["quantity"] == 99, "stack topped to 99")
	_check(plan["changes"][1]["item"]["quantity"] == 4, "remainder to empty slot")
	# 容量不足整笔失败
	var full := {"capacity": 1, "slots": [{"item_definition_id": "seed.radish", "quantity": 99}]}
	var fail := InventoryOps.plan_insert(full, "seed.potato", 1)
	_check(not fail["ok"] and fail["reason"] == ContractError.INVENTORY_FULL, "full container rejects whole insert")
	# 跨格扣减
	var two_stacks := {"capacity": 2, "slots": [
		{"item_definition_id": "produce.radish", "quantity": 3},
		{"item_definition_id": "produce.radish", "quantity": 4},
	]}
	var remove := InventoryOps.plan_remove(two_stacks, "produce.radish", 5)
	_check(remove["ok"] and remove["changes"].size() == 2, "remove spans stacks")
	_check(remove["changes"][0]["item"] == null, "first stack emptied")
	_check(remove["changes"][1]["item"]["quantity"] == 2, "second stack reduced")
	var short := InventoryOps.plan_remove(two_stacks, "produce.radish", 8)
	_check(not short["ok"] and short["reason"] == ContractError.INSUFFICIENT_ITEMS, "insufficient rejected")
	# 转移：整组与拆分
	var src := {"capacity": 2, "slots": [{"item_definition_id": "seed.wheat", "quantity": 10}, null]}
	var dst := {"capacity": 2, "slots": [null, null]}
	var move := InventoryOps.plan_transfer(src, 0, dst, 1, 10)
	_check(move["ok"] and move["from_change"]["item"] == null and move["to_change"]["item"]["quantity"] == 10, "whole stack transfer")
	var split := InventoryOps.plan_transfer(src, 0, dst, 0, 4)
	_check(split["ok"] and split["from_change"]["item"]["quantity"] == 6 and split["to_change"]["item"]["quantity"] == 4, "split transfer")
	# 拆分到不同类格 → 拒绝
	var wrong := InventoryOps.plan_transfer(src, 0, {"capacity": 1, "slots": [{"item_definition_id": "seed.radish", "quantity": 1}]}, 0, 1)
	_check(not wrong["ok"], "transfer to different item rejected")


# ---------- 3. 购买种子 ----------

func _test_buy_seed() -> void:
	var ctx := _make()
	var runtime: WorldRuntime = ctx[0]
	var owner: String = ctx[3]
	_check(runtime.world.treasury == 300, "start 300")
	var r := _cmd(runtime, owner, "economy.buy_seed", {"seed_definition_id": "seed.radish", "quantity": 10})
	_check(r["accepted"] and r["error_code"] == "", "buy accepted")
	_check(runtime.world.treasury == 300 - 150, "treasury debited 150")
	var backpack: Dictionary = runtime.world.containers["backpack:" + owner]
	_check(backpack["slots"][0]["item_definition_id"] == "seed.radish" and backpack["slots"][0]["quantity"] == 10, "seeds in backpack")
	_check(int(runtime.world.stats["world_total_purchases"]) == 150, "purchase total recorded")
	_check(r["events"].size() == 1 and r["events"][0]["event_type"] == "SeedPurchased", "SeedPurchased event")
	_check(int(r["events"][0]["payload"]["unit_price"]) == 15, "event carries server price")
	# 资金不足
	var poor := _cmd(runtime, owner, "economy.buy_seed", {"seed_definition_id": "seed.strawberry", "quantity": 99})
	_check(poor["error_code"] == ContractError.INSUFFICIENT_FUNDS, "insufficient funds rejected")
	_check(runtime.world.treasury == 150, "treasury unchanged after rejection")
	# 非种子不可买
	var non_seed := _cmd(runtime, owner, "economy.buy_seed", {"seed_definition_id": "produce.radish", "quantity": 1})
	_check(non_seed["error_code"] == ContractError.INVALID_ARGUMENT, "non-seed rejected (got %s)" % str(non_seed["error_code"]))
	# 数量越界
	var too_many := _cmd(runtime, owner, "economy.buy_seed", {"seed_definition_id": "seed.radish", "quantity": 100})
	_check(too_many["error_code"].begins_with("CONTRACTS_PAYLOAD_RANGE"), "quantity 100 rejected at envelope")


# ---------- 4. 出售作物 ----------

func _test_sell_produce() -> void:
	var ctx := _make()
	var runtime: WorldRuntime = ctx[0]
	var owner: String = ctx[3]
	# 直接放入产物（模拟收获结果）
	var backpack: Dictionary = runtime.world.containers.get("backpack:" + owner, {})
	if backpack.is_empty():
		runtime.world.containers["backpack:" + owner] = {"capacity": 24, "slots": WorldState.empty_slots(24), "revision": 0}
	backpack = runtime.world.containers["backpack:" + owner]
	backpack["slots"][2] = {"item_definition_id": "produce.radish", "quantity": 10}
	var r := _cmd(runtime, owner, "economy.sell", {"slot": 2, "item_definition_id": "produce.radish", "quantity": 10})
	_check(r["accepted"] and r["error_code"] == "", "sell accepted")
	_check(runtime.world.treasury == 300 + 240, "treasury +240")
	_check(backpack["slots"][2] == null, "slot emptied")
	var member_stats: Dictionary = runtime.world.stats["members"][owner]
	_check(int(member_stats["total_gross_sales"]) == 240, "member total sales 240")
	_check(int(member_stats["today_gross_sales"]) == 240, "member today sales 240")
	_check(int(member_stats["contribution"]["harvesting"]) == 0, "selling adds no contribution")
	_check(r["events"][0]["payload"]["gross_amount"] == 240, "event gross amount 240")
	# 出售种子 → 拒绝
	backpack["slots"][3] = {"item_definition_id": "seed.radish", "quantity": 5}
	var seed_sell := _cmd(runtime, owner, "economy.sell", {"slot": 3, "item_definition_id": "seed.radish", "quantity": 1})
	_check(not seed_sell["error_code"].is_empty(), "selling seed rejected")
	# 数量超过持有 → 拒绝
	var too_much := _cmd(runtime, owner, "economy.sell", {"slot": 3, "item_definition_id": "seed.radish", "quantity": 99})
	_check(not too_much["error_code"].is_empty(), "oversell rejected")


# ---------- 5. 背包与仓库转移 ----------

func _test_transfer_and_storage() -> void:
	var ctx := _make()
	var runtime: WorldRuntime = ctx[0]
	var owner: String = ctx[3]
	# 先买种子进背包
	_cmd(runtime, owner, "economy.buy_seed", {"seed_definition_id": "seed.potato", "quantity": 5})
	var backpack: Dictionary = runtime.world.containers["backpack:" + owner]
	var slot := -1
	for i in backpack["slots"].size():
		if backpack["slots"][i] != null and backpack["slots"][i]["item_definition_id"] == "seed.potato":
			slot = i
			break
	_check(slot >= 0, "bought seeds located in backpack")
	var storage_before: Dictionary = runtime.world.containers["shared_storage"]
	var rev_before := int(storage_before["revision"])
	var r := _cmd(runtime, owner, "inventory.transfer", {
		"from_container": "backpack:" + owner, "to_container": "shared_storage",
		"from_slot": slot, "to_slot": 1, "quantity": 5,
	})
	_check(r["accepted"] and r["error_code"] == "", "transfer to storage accepted")
	_check(runtime.world.containers["shared_storage"]["slots"][1]["item_definition_id"] == "seed.potato", "item in storage")
	_check(int(runtime.world.containers["shared_storage"]["revision"]) == rev_before + 1, "storage revision +1")
	_check(r["events"][0]["event_type"] == "ItemsTransferred", "ItemsTransferred event")
	# 取回
	var r2 := _cmd(runtime, owner, "inventory.transfer", {
		"from_container": "shared_storage", "to_container": "backpack:" + owner,
		"from_slot": 1, "to_slot": slot, "quantity": 5,
	})
	_check(r2["accepted"], "transfer back accepted")
	_check(runtime.world.containers["shared_storage"]["slots"][1] == null, "storage slot emptied")
	# 不能操作他人背包
	var other: Dictionary = runtime.world.add_member("队友")
	var r3 := _cmd(runtime, owner, "inventory.transfer", {
		"from_container": "backpack:" + other["player_id"], "to_container": "shared_storage",
		"from_slot": 0, "to_slot": 2, "quantity": 1,
	})
	_check(r3["error_code"] == ContractError.NOT_ALLOWED, "cannot touch other's backpack")


# ---------- 6. 对账不变量 ----------

func _test_reconciliation() -> void:
	var ctx := _make()
	var runtime: WorldRuntime = ctx[0]
	var owner: String = ctx[3]
	_cmd(runtime, owner, "economy.buy_seed", {"seed_definition_id": "seed.wheat", "quantity": 8})   # -96
	var backpack: Dictionary = runtime.world.containers["backpack:" + owner]
	backpack["slots"][5] = {"item_definition_id": "produce.wheat", "quantity": 8}
	_cmd(runtime, owner, "economy.sell", {"slot": 5, "item_definition_id": "produce.wheat", "quantity": 8})  # +240
	var w: WorldState = runtime.world
	_check(w.treasury == 300 - 96 + 240, "treasury matches ledger")
	_check(TransactionCoordinator.check_invariants(w) == "", "invariants hold after mixed operations")
	_check(int(w.stats["world_total_sales"]) == 240 and int(w.stats["world_total_purchases"]) == 96, "world totals recorded")
	var member_stats: Dictionary = w.stats["members"][owner]
	_check(int(member_stats["total_gross_sales"]) == 240, "member sales sum equals world sales")
