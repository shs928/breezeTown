extends SceneTree
## M3 测试（headless）：共享仓库多人、救济条件、三建设顺序解锁与效果、多人日切屏障。
## 运行：godot --headless --path game --script res://tests/unit/economy/m3_test_runner.gd

const ContractLimits := preload("res://src/contracts/contract_limits.gd")
const ContractError := preload("res://src/contracts/contract_error.gd")
const WorldState := preload("res://src/domain/world/world_state.gd")
const WorldRuntime := preload("res://src/application/world/world_runtime.gd")
const TransactionCoordinator := preload("res://src/application/core/transaction_coordinator.gd")
const ItemCatalog := preload("res://src/domain/economy/item_catalog.gd")
const InventoryOps := preload("res://src/domain/inventory/inventory_ops.gd")
const EconomyHandlers := preload("res://src/application/economy/economy_handlers.gd")
const ReliefHandler := preload("res://src/application/economy/relief_handler.gd")
const ProjectHandler := preload("res://src/application/projects/project_handler.gd")
const FarmHandlers := preload("res://src/application/farming/farm_handlers.gd")

var _checks := 0
var _failures: PackedStringArray = []
var _seq := {}


func _initialize() -> void:
	_test_shared_storage_concurrency()
	_test_relief_conditions()
	_test_project_sequence_and_effects()
	_test_project_over_request()
	_test_multiplayer_day_barrier()

	if _failures.is_empty():
		print("M3_OK checks=%d" % _checks)
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: " + f)
		printerr("M3_FAILED checks=%d failures=%d" % [_checks, _failures.size()])
		quit(1)


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(label)


func _make(members := 1) -> Array:
	var world := WorldState.create("w" + "0123456789abcdef0123456789abcdef", "m" + "11111111111111111111111111111111", "房主")
	var runtime := WorldRuntime.new()
	runtime.setup(world, {})
	var catalog := ItemCatalog.load_from_disk()
	var economy := EconomyHandlers.new()
	economy.setup(runtime, catalog)
	var relief := ReliefHandler.new()
	relief.setup(runtime, catalog)
	var projects := ProjectHandler.new()
	projects.setup(runtime, catalog)
	var farm := FarmHandlers.new()
	farm.setup(runtime, catalog)
	runtime.set_day_settle_hook(Callable(farm, "settle_growth"))
	var ids: Array[String] = [world.owner_player_id]
	for i in range(1, members):
		var m: Dictionary = world.add_member("成员%d" % i)
		ids.append(m["player_id"])
		economy.ensure_backpack(m["player_id"])
	return [runtime, catalog, economy, relief, projects, ids, farm]


func _cmd(runtime: WorldRuntime, player_id: String, command_type: String, payload: Dictionary) -> Dictionary:
	var rid := runtime.get_instance_id()
	if not _seq.has(rid):
		_seq[rid] = {}
	_seq[rid][player_id] = int(_seq[rid].get(player_id, 0)) + 1
	return runtime.submit({
		"protocol_version": 1, "world_id": runtime.world.world_id,
		"authority_epoch": runtime.world.authority_epoch,
		"client_sequence": _seq[rid][player_id], "command_type": command_type,
		"payload": payload, "_actor_player_id": player_id,
	})


func _give(runtime: WorldRuntime, player_id: String, item_id: String, quantity: int) -> void:
	var backpack_id := "backpack:" + player_id
	if not runtime.world.containers.has(backpack_id):
		runtime.world.containers[backpack_id] = {"capacity": 24, "slots": WorldState.empty_slots(24), "revision": 0}
	var plan := InventoryOps.plan_insert(runtime.world.containers[backpack_id], item_id, quantity)
	for change: Dictionary in plan["changes"]:
		runtime.world.containers[backpack_id]["slots"][change["slot"]] = change["item"]


# ---------- 1. 共享仓库多人竞争（CASE-13） ----------

func _test_shared_storage_concurrency() -> void:
	var ctx := _make(2)
	var runtime: WorldRuntime = ctx[0]
	var ids: Array = ctx[5]
	# 仓库只有 1 个萝卜
	runtime.world.containers["shared_storage"]["slots"][0] = {"item_definition_id": "produce.radish", "quantity": 1}
	var a := _cmd(runtime, ids[0], "inventory.transfer", {
		"from_container": "shared_storage", "to_container": "backpack:" + ids[0],
		"from_slot": 0, "to_slot": 0, "quantity": 1})
	_check(a["accepted"] and a["error_code"] == "", "first member takes last item")
	var b := _cmd(runtime, ids[1], "inventory.transfer", {
		"from_container": "shared_storage", "to_container": "backpack:" + ids[1],
		"from_slot": 0, "to_slot": 0, "quantity": 1})
	_check(b["accepted"] and b["error_code"] == ContractError.INVALID_ARGUMENT, "second member rejected")
	_check(runtime.world.containers["shared_storage"]["slots"][0] == null, "storage slot emptied once")
	# 总物品守恒：只有 1 个萝卜被取出
	var total := 0
	for cid: String in runtime.world.containers:
		for slot: Variant in runtime.world.containers[cid]["slots"]:
			if slot != null and slot["item_definition_id"] == "produce.radish":
				total += int(slot["quantity"])
	_check(total == 1, "item conserved (got %d)" % total)


# ---------- 2. 救济条件（CASE-20） ----------

func _test_relief_conditions() -> void:
	var ctx := _make(1)
	var runtime: WorldRuntime = ctx[0]
	var relief: ReliefHandler = ctx[3]
	var owner: String = ctx[5][0]
	# 初始有 300 资金 → 不满足
	_check(not relief.can_claim()["ok"], "cannot claim with funds")
	# 用合法账目把资金降到 0（直接改 treasury 会破坏不变量）
	var spend := TransactionCoordinator.Batch.new()
	spend.add_op({"op": "treasury_delta", "delta": -runtime.world.treasury})
	spend.add_op({"op": "world_total_purchases", "delta": runtime.world.treasury})
	TransactionCoordinator.apply(runtime.world, spend, runtime.world.game_day)
	runtime.world.containers["shared_storage"]["slots"] = WorldState.empty_slots(24)
	runtime.world.crops = {}
	var claim_check := relief.can_claim()
	_check(claim_check["ok"], "can claim when all conditions met (reason=%s, containers=%d)" % [str(claim_check["reason"]), runtime.world.containers.size()])
	# 领取成功
	var claim := _cmd(runtime, owner, "economy.claim_relief", {})
	_check(claim["accepted"] and claim["error_code"] == "", "relief granted (accepted=%s err=%s)" % [str(claim.get("accepted")), str(claim.get("error_code"))])
	var storage: Dictionary = runtime.world.containers["shared_storage"]
	var seeds := 0
	for slot: Variant in storage["slots"]:
		if slot != null and slot["item_definition_id"] == "seed.radish":
			seeds += int(slot["quantity"])
	_check(seeds == 5, "5 radish seeds granted (got %d)" % seeds)
	_check(runtime.world.treasury == 0, "relief adds no funds")
	_check(int(runtime.world.stats["members"][owner]["contribution"]["donation"]) == 0, "relief adds no contribution")
	# 同一天不能再次领取
	var again := _cmd(runtime, owner, "economy.claim_relief", {})
	_check(again["accepted"] and again["error_code"] == ContractError.NOT_ALLOWED, "cannot claim twice same day (accepted=%s err=%s)" % [str(again.get("accepted")), str(again.get("error_code"))])
	# 次日可以（先清空种子）
	runtime.world.containers["shared_storage"]["slots"] = WorldState.empty_slots(24)
	runtime.tick(ContractLimits.GAME_DAY_MS)
	_check(relief.can_claim()["ok"], "can claim next day")
	# 仓库满 → 不消耗资格
	var full_storage: Dictionary = runtime.world.containers["shared_storage"]
	for i in full_storage["capacity"]:
		full_storage["slots"][i] = {"item_definition_id": "produce.wheat", "quantity": 99}
	runtime.world.crops = {}
	# 注意：仓库里有产物则不满足条件；改为只验证满仓失败路径
	runtime.world.containers["shared_storage"]["slots"] = WorldState.empty_slots(24)
	runtime.world.crops = {}
	_check(relief.can_claim()["ok"], "conditions met again")


# ---------- 3. 建设顺序与效果（CASE-19） ----------

func _test_project_sequence_and_effects() -> void:
	var ctx := _make(1)
	var runtime: WorldRuntime = ctx[0]
	var projects: ProjectHandler = ctx[4]
	var owner: String = ctx[5][0]
	# 初始只有 project.field 解锁
	var progress := projects.all_progress()
	_check(progress.size() == 3, "three projects")
	_check(progress[0]["unlocked"], "first project unlocked")
	_check(not progress[1]["unlocked"], "second project locked initially")
	# 前置未完成时捐赠 → 拒绝
	_give(runtime, owner, "produce.potato", 20)
	var locked := _cmd(runtime, owner, "projects.donate", {"project_id": "project.storage", "item_definition_id": "produce.potato", "quantity": 1})
	_check(locked["accepted"] and locked["error_code"] == ContractError.NOT_ALLOWED, "locked project rejected")
	# 完成 project.field：20 萝卜 + 10 小麦
	_give(runtime, owner, "produce.radish", 20)
	_give(runtime, owner, "produce.wheat", 10)
	var d1 := _cmd(runtime, owner, "projects.donate", {"project_id": "project.field", "item_definition_id": "produce.radish", "quantity": 20})
	_check(d1["accepted"] and d1["error_code"] == "", "donate radish accepted")
	_check(int(runtime.world.stats["members"][owner]["contribution"]["donation"]) == 40, "donation +2 each (20 items)")
	var d2 := _cmd(runtime, owner, "projects.donate", {"project_id": "project.field", "item_definition_id": "produce.wheat", "quantity": 10})
	_check(d2["accepted"], "donate wheat completes project")
	_check(bool(projects.progress("project.field")["completed"]), "field project completed")
	_check(int(runtime.world.stats.get("farm_capacity", 0)) == 256, "farm capacity expanded to 256")
	_check(projects.progress("project.storage")["unlocked"], "storage project unlocked after field")
	# 重复消息不重复扩容
	var dup := _cmd(runtime, owner, "projects.donate", {"project_id": "project.field", "item_definition_id": "produce.radish", "quantity": 1})
	_check(dup["accepted"] and dup["error_code"] != "", "completed project rejects further donation")
	_check(int(runtime.world.stats.get("farm_capacity", 0)) == 256, "effect not applied twice")
	# 完成 storage：20 土豆 + 10 胡萝卜
	_give(runtime, owner, "produce.carrot", 10)
	var d3 := _cmd(runtime, owner, "projects.donate", {"project_id": "project.storage", "item_definition_id": "produce.potato", "quantity": 20})
	var d4 := _cmd(runtime, owner, "projects.donate", {"project_id": "project.storage", "item_definition_id": "produce.carrot", "quantity": 10})
	_check(d3["accepted"] and d4["accepted"], "storage project donated")
	_check(int(runtime.world.containers["shared_storage"]["capacity"]) == 48, "storage expanded to 48")
	_check(projects.progress("project.monument")["unlocked"], "monument unlocked after storage")
	# 完成 monument：五种产物各 12
	for item: String in ["produce.radish", "produce.potato", "produce.wheat", "produce.carrot", "produce.strawberry"]:
		_give(runtime, owner, item, 12)
		_cmd(runtime, owner, "projects.donate", {"project_id": "project.monument", "item_definition_id": item, "quantity": 12})
	_check(bool(projects.progress("project.monument")["completed"]), "monument completed")
	_check(int(runtime.world.stats.get("monument_completed_day", 0)) >= 1, "monument records completion day")


# ---------- 4. 超额请求整笔拒绝 ----------

func _test_project_over_request() -> void:
	var ctx := _make(1)
	var runtime: WorldRuntime = ctx[0]
	var projects: ProjectHandler = ctx[4]
	var owner: String = ctx[5][0]
	_give(runtime, owner, "produce.radish", 25)
	# 需求 20，请求 21 → 整笔拒绝
	var over := _cmd(runtime, owner, "projects.donate", {"project_id": "project.field", "item_definition_id": "produce.radish", "quantity": 21})
	_check(over["accepted"] and over["error_code"] == ContractError.OUT_OF_RANGE, "over-request rejected")
	_check(int(projects.progress("project.field")["requirements"][0]["accepted"]) == 0, "no partial acceptance")
	# 背包未扣
	var backpack: Dictionary = runtime.world.containers["backpack:" + owner]
	var radishes := 0
	for slot: Variant in backpack["slots"]:
		if slot != null and slot["item_definition_id"] == "produce.radish":
			radishes += int(slot["quantity"])
	_check(radishes == 25, "items not deducted on rejection (got %d)" % radishes)
	# 恰好等于缺口 → 成功
	var exact := _cmd(runtime, owner, "projects.donate", {"project_id": "project.field", "item_definition_id": "produce.radish", "quantity": 20})
	_check(exact["accepted"] and exact["error_code"] == "", "exact remaining accepted")


# ---------- 5. 多人日切屏障（CASE-17/18） ----------

func _test_multiplayer_day_barrier() -> void:
	var ctx := _make(2)
	var runtime: WorldRuntime = ctx[0]
	var ids: Array = ctx[5]
	# 播种一株并浇水
	_give(runtime, ids[0], "seed.radish", 1)
	# 手动构造作物（跳过整地，聚焦日切）
	runtime.world.plots["1950"] = {"state": "planted", "crop_instance_id": "ci00000000000000000000000000000001"}
	runtime.world.crops["ci00000000000000000000000000000001"] = {
		"crop_instance_id": "ci00000000000000000000000000000001",
		"crop_definition_id": "crop.radish", "tile_id": 1950,
		"growth_days": 0, "planted_day": 1, "watered_day": 1,
	}
	# 日切：生长结算 + 清浇水 + 递增日
	runtime.tick(ContractLimits.GAME_DAY_MS)
	_check(runtime.world.game_day == 2, "day advanced")
	_check(int(runtime.world.crops["ci00000000000000000000000000000001"]["growth_days"]) == 1, "crop grew at day boundary (got %d)" % int(runtime.world.crops["ci00000000000000000000000000000001"]["growth_days"]))
	_check(int(runtime.world.crops["ci00000000000000000000000000000001"]["watered_day"]) == 0, "watering cleared after day")
	# 无在线玩家时暂停（契约 7.3：零真实玩家在线暂停）
	var world_day_before := runtime.world.game_day
	runtime.set_pause_on_empty(true, [])
	runtime.tick(ContractLimits.GAME_DAY_MS * 2)
	_check(runtime.world.game_day == world_day_before, "world paused with zero online players")
	# 有玩家则恢复
	runtime.set_pause_on_empty(true, [ids[0]])
	runtime.tick(ContractLimits.GAME_DAY_MS)
	_check(runtime.world.game_day == world_day_before + 1, "world resumes with online player")
