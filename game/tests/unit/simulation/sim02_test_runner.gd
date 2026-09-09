extends SceneTree
## SIM-02 测试（headless）：世界/epoch 校验、移动限速、可见状态视图、序号高水位。
## 运行：godot --headless --path game --script res://tests/unit/simulation/sim02_test_runner.gd

const ContractLimits := preload("res://src/contracts/contract_limits.gd")
const ContractError := preload("res://src/contracts/contract_error.gd")
const WorldState := preload("res://src/domain/world/world_state.gd")
const WorldRuntime := preload("res://src/application/world/world_runtime.gd")
const WorldView := preload("res://src/application/world/world_view.gd")
const ContractView := preload("res://src/contracts/contract_view.gd")

var _checks := 0
var _failures: PackedStringArray = []
var _seq := {}


func _initialize() -> void:
	_test_world_and_epoch_mismatch()
	_test_move_rate_limit()
	_test_view_filtering()
	_test_view_snapshot_metadata()
	_test_high_watermark()

	if _failures.is_empty():
		print("SIM02_OK checks=%d" % _checks)
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: " + f)
		printerr("SIM02_FAILED checks=%d failures=%d" % [_checks, _failures.size()])
		quit(1)


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(label)


func _make() -> Array:
	var world := WorldState.create("w" + "0123456789abcdef0123456789abcdef", "m" + "11111111111111111111111111111111", "房主")
	var runtime := WorldRuntime.new()
	runtime.setup(world, {})
	return [runtime, world.owner_player_id]


func _cmd(runtime: WorldRuntime, player_id: String, command_type: String, payload: Dictionary, seq := -1) -> Dictionary:
	var rid := runtime.get_instance_id()
	if not _seq.has(rid):
		_seq[rid] = {}
	if seq < 0:
		_seq[rid][player_id] = int(_seq[rid].get(player_id, 0)) + 1
		seq = _seq[rid][player_id]
	return runtime.submit({
		"protocol_version": 1,
		"world_id": runtime.world.world_id,
		"authority_epoch": runtime.world.authority_epoch,
		"client_sequence": seq,
		"command_type": command_type,
		"payload": payload,
		"_actor_player_id": player_id,
	})


# ---------- 1. 世界与 epoch 不匹配 ----------

func _test_world_and_epoch_mismatch() -> void:
	var ctx := _make()
	var runtime: WorldRuntime = ctx[0]
	var owner: String = ctx[1]
	# 错误 world_id
	var wrong_world := runtime.submit({
		"protocol_version": 1,
		"world_id": "w" + "9".repeat(32),
		"authority_epoch": runtime.world.authority_epoch,
		"client_sequence": 1,
		"command_type": "profile.update",
		"payload": {"display_name": "甲"},
		"_actor_player_id": owner,
	})
	_check(wrong_world["error_code"] == ContractError.WORLD_MISMATCH, "wrong world rejected")
	# 过期 epoch
	var stale_epoch := runtime.submit({
		"protocol_version": 1,
		"world_id": runtime.world.world_id,
		"authority_epoch": "e" + "0".repeat(32),
		"client_sequence": 1,
		"command_type": "profile.update",
		"payload": {"display_name": "甲"},
		"_actor_player_id": owner,
	})
	_check(stale_epoch["error_code"] == ContractError.STALE_EPOCH, "stale epoch rejected")
	# 正确命令仍可用
	var ok := _cmd(runtime, owner, "profile.update", {"display_name": "甲"})
	_check(ok["accepted"] and ok["error_code"] == "", "valid command still works")


# ---------- 2. 移动限速 ----------

func _test_move_rate_limit() -> void:
	var ctx := _make()
	var runtime: WorldRuntime = ctx[0]
	var owner: String = ctx[1]
	# 每帧 50ms 模拟，1 秒内最多 30 次输入；发 40 次
	var limited := 0
	for i in 40:
		var r := _cmd(runtime, owner, "world.move_input", {"dx": 1, "dy": 0, "input_sequence": i + 1})
		if r["error_code"] == ContractError.RATE_LIMITED:
			limited += 1
	_check(limited > 0, "move rate limit triggers (limited=%d)" % limited)
	_check(limited == 10, "exactly 10 over limit rejected (got %d)" % limited)


# ---------- 3. 视图过滤 ----------

func _test_view_filtering() -> void:
	var ctx := _make()
	var runtime: WorldRuntime = ctx[0]
	var owner: String = ctx[1]
	var second: Dictionary = runtime.world.add_member("队友")
	# 给两人背包放东西
	runtime.world.containers[owner] = {"capacity": 24, "slots": WorldState.empty_slots(24), "revision": 0}
	var owner_backpack := "backpack:" + owner
	runtime.world.containers[owner_backpack] = {"capacity": 24, "slots": WorldState.empty_slots(24), "revision": 0}
	runtime.world.containers[owner_backpack]["slots"][0] = {"item_definition_id": "seed.radish", "quantity": 5}
	var second_backpack: String = second["inventory_id"]
	runtime.world.containers[second_backpack] = {"capacity": 24, "slots": WorldState.empty_slots(24), "revision": 0}
	runtime.world.containers[second_backpack]["slots"][0] = {"item_definition_id": "seed.potato", "quantity": 3}

	var result := WorldView.build(runtime.world, owner, [owner])
	_check(result["ok"], "view built")
	var view: Dictionary = result["snapshot"]
	_check(view["inventories"].has(owner_backpack), "own backpack visible")
	_check(not view["inventories"].has(second_backpack), "foreign backpack hidden")
	_check(view["inventories"].has("shared_storage"), "shared storage visible to all")
	_check(ContractView.validate_player_view(view) == "", "view passes contract validation")
	# 视图不含凭据字段
	_check(not JSON.stringify(view).contains("credential_digest"), "no credential digest in view")
	# 自己行标记 is_self
	var self_row := {}
	for row: Dictionary in view["members"]:
		if row["player_id"] == owner:
			self_row = row
	_check(self_row.get("is_self", false), "self row flagged")


# ---------- 4. 快照元数据 ----------

func _test_view_snapshot_metadata() -> void:
	var ctx := _make()
	var runtime: WorldRuntime = ctx[0]
	var owner: String = ctx[1]
	var result := WorldView.build(runtime.world, owner, [owner])
	var view: Dictionary = result["snapshot"]
	_check(view["protocol_version"] == 1, "protocol version in snapshot")
	_check(view["authority_epoch"] == runtime.world.authority_epoch, "epoch in snapshot")
	_check(view["world_id"] == runtime.world.world_id, "world id in snapshot")
	_check(view["base_revision"] == runtime.world.business_revision, "base revision in snapshot")
	_check(view["sim_tick"] == runtime.world.sim_tick, "sim tick in snapshot")
	# 未知成员 → 拒绝
	var unknown := WorldView.build(runtime.world, "m" + "9".repeat(32))
	_check(not unknown["ok"] and unknown["error"] == ContractError.NOT_AUTHENTICATED, "unknown member view rejected")


# ---------- 5. 序号高水位 ----------

func _test_high_watermark() -> void:
	var ctx := _make()
	var runtime: WorldRuntime = ctx[0]
	var owner: String = ctx[1]
	_check(runtime.next_expected_sequence(owner) == 1, "initial watermark 1")
	_cmd(runtime, owner, "profile.update", {"display_name": "甲"})
	_check(runtime.next_expected_sequence(owner) == 2, "watermark advances to 2")
	_cmd(runtime, owner, "profile.update", {"display_name": "乙"})
	_check(runtime.next_expected_sequence(owner) == 3, "watermark advances to 3")
	# 业务失败也推进水位
	_cmd(runtime, owner, "profile.update", {"display_name": "   "})
	_check(runtime.next_expected_sequence(owner) == 4, "failed business also advances watermark")
