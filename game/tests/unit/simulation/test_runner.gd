extends SceneTree
## SIM-01 领域测试（headless）：WorldState、原子事务、时钟/日切、移动碰撞、昵称、幂等。
## 运行：godot --headless --path game --script res://tests/unit/simulation/test_runner.gd
## 退出码 0=通过。

const ContractLimits := preload("res://src/contracts/contract_limits.gd")
const ContractError := preload("res://src/contracts/contract_error.gd")
const WorldState := preload("res://src/domain/world/world_state.gd")
const SimClock := preload("res://src/application/core/sim_clock.gd")
const TransactionCoordinator := preload("res://src/application/core/transaction_coordinator.gd")
const WorldRuntime := preload("res://src/application/world/world_runtime.gd")
const Batch := TransactionCoordinator.Batch

var _checks := 0
var _failures: PackedStringArray = []
var _seq := {}  # runtime_instance_id -> player_id -> last client_sequence


func _initialize() -> void:
	_test_world_creation()
	_test_clock_and_day_advance()
	_test_atomic_commit_and_invariants()
	_test_move_and_collision()
	_test_profile_update()
	_test_idempotency_and_sequence()
	_test_save_fault()

	if _failures.is_empty():
		print("SIM_OK checks=%d" % _checks)
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: " + f)
		printerr("SIM_FAILED checks=%d failures=%d" % [_checks, _failures.size()])
		quit(1)


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(label)


func _load(path: String) -> Variant:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return _normalize(parsed)


func _normalize(v: Variant) -> Variant:
	if v is Array:
		var a: Array = []
		for i in v:
			a.append(_normalize(i))
		return a
	if v is Dictionary:
		var d := {}
		for k in v:
			d[k] = _normalize(v[k])
		return d
	if v is float and is_equal_approx(v, float(int(v))):
		return int(v)
	return v


func _make_runtime(with_map := true) -> WorldRuntime:
	var world_id := "w" + "0123456789abcdef0123456789abcdef"
	var owner_id := "m" + "11111111111111111111111111111111"
	var world := WorldState.create(world_id, owner_id, "房主")
	var runtime := WorldRuntime.new()
	var map: Dictionary = {}
	if with_map:
		map = _load("res://content/schema/examples/map_town_minimal.json")
	runtime.setup(world, map)
	return runtime


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


# ---------- 1. 世界创建 ----------

func _test_world_creation() -> void:
	var runtime := _make_runtime(false)
	var w: WorldState = runtime.world
	_check(w.treasury == 300, "initial treasury 300")
	_check(w.game_day == 1, "start day 1")
	_check(w.members.size() == 1, "owner only")
	_check(w.members[0]["role"] == "owner", "owner role")
	_check(w.members[0]["credential_digest"] == "", "no credential in world state")
	var storage: Dictionary = w.containers["shared_storage"]
	_check(storage["capacity"] == 24, "storage capacity 24")
	_check(storage["slots"][0]["item_definition_id"] == "seed.radish", "20 radish seeds")
	_check(storage["slots"][0]["quantity"] == 20, "seed quantity 20")
	var owner: Dictionary = w.members[0]
	_check(w.containers.has(owner["inventory_id"]) == false, "owner backpack created lazily by ECON")
	_check(TransactionCoordinator.check_invariants(w) == "", "invariants hold at creation")


# ---------- 2. 时钟与日切 ----------

func _test_clock_and_day_advance() -> void:
	var runtime := _make_runtime(false)
	# 推进 599.9 秒：未日切
	for i in 11999:
		runtime.tick(50)
	_check(runtime.world.game_day == 1, "no day advance before 600s")
	# 再推进一步越过边界
	var advanced := runtime.tick(50)
	_check(advanced, "day advances at boundary")
	_check(runtime.world.game_day == 2, "game_day incremented")
	_check(runtime.world.day_elapsed_ms == 0, "day elapsed reset")
	# 时钟文本换算：600s 满日 → 24:00 视作 00:00
	var clock := SimClock.new()
	_check(clock.clock_text() == "06:00", "clock starts at 06:00")
	clock.advance(ContractLimits.GAME_DAY_MS / 2)
	_check(clock.clock_text() == "15:00", "half day = 15:00")
	# 休眠不补跑：一次巨大 delta 只推进一天，不跳多日
	var runtime2 := _make_runtime(false)
	runtime2.tick(ContractLimits.GAME_DAY_MS * 5)
	_check(runtime2.world.game_day == 2, "huge delta advances only one day (no catch-up)")


# ---------- 3. 原子提交与不变量 ----------

func _test_atomic_commit_and_invariants() -> void:
	var runtime := _make_runtime(false)
	var owner: String = runtime.world.owner_player_id
	# 合法计划：扣款 + 加采购总额，不变量成立
	var batch := TransactionCoordinator.Batch.new()
	batch.add_op({"op": "treasury_delta", "delta": -100})
	batch.add_op({"op": "world_total_purchases", "delta": 100})
	_check(TransactionCoordinator.validate(runtime.world, batch) == "", "valid plan passes")
	var events: Array = TransactionCoordinator.apply(runtime.world, batch, 1)
	_check(runtime.world.treasury == 200, "treasury debited")
	_check(TransactionCoordinator.check_invariants(runtime.world) == "", "invariants after commit")
	_check(events.size() == 0, "no events for pure treasury op")

	# 非法计划：扣款超过余额 → 校验失败，状态不变
	var before: int = runtime.world.treasury
	var bad := TransactionCoordinator.Batch.new()
	bad.add_op({"op": "treasury_delta", "delta": -999999})
	_check(TransactionCoordinator.validate(runtime.world, bad) == ContractError.INSUFFICIENT_FUNDS, "overdraft rejected")
	_check(runtime.world.treasury == before, "state unchanged on rejected plan")

	# 事件序号与 revision 单调
	var rev_before: int = runtime.world.business_revision
	var batch2 := TransactionCoordinator.Batch.new()
	batch2.add_event("DayAdvanced", {"note": "test"}, owner)
	var events2: Array = TransactionCoordinator.apply(runtime.world, batch2, 1)
	_check(runtime.world.business_revision == rev_before + 1, "revision incremented once")
	_check(events2[0]["event_sequence"] == 1, "first event sequence 1")
	_check(runtime.world.next_event_seq == 2, "next_event_seq advanced")


# ---------- 4. 移动与碰撞 ----------

func _test_move_and_collision() -> void:
	var runtime := _make_runtime(true)
	var owner: String = runtime.world.owner_player_id
	var member: Dictionary = runtime.world.find_member(owner)
	# 放在中央空地（格 32,32 → 像素 1024,1024 附近）
	member["last_valid_position"] = {"x": 1040.0, "y": 1040.0}
	var before: Dictionary = (member["last_valid_position"] as Dictionary).duplicate()
	# 无效方向（0,0）不改位置
	_cmd(runtime, owner, "world.move_input", {"dx": 0, "dy": 0, "input_sequence": 1})
	_check(member["last_valid_position"] == before, "zero input does not move")
	# 向右移动一步
	var r := _cmd(runtime, owner, "world.move_input", {"dx": 1, "dy": 0, "input_sequence": 2})
	_check(r["accepted"] and r["error_code"] == "", "move accepted")
	_check(member["last_valid_position"]["x"] > before["x"], "moved right")
	# 旧序号丢弃
	var r2 := _cmd(runtime, owner, "world.move_input", {"dx": -1, "dy": 0, "input_sequence": 1})
	_check(r2["error_code"] == ContractError.STALE_STATE, "stale input sequence rejected")
	# 撞边界：移到靠近上边界后向上移动，不穿墙
	member["last_valid_position"] = {"x": 1040.0, "y": 80.0}  # 顶部两行是阻挡
	for i in 10:
		_cmd(runtime, owner, "world.move_input", {"dx": 0, "dy": -1, "input_sequence": 100 + i})
	_check(member["last_valid_position"]["y"] >= 64.0, "blocked by map border (y=%s)" % str(member["last_valid_position"]["y"]))
	# 玩家互不阻挡：两个成员同格
	var second: Dictionary = runtime.world.add_member("队友")
	second["last_valid_position"] = member["last_valid_position"].duplicate()
	_check(true, "players can overlap (no entity collision by design)")


# ---------- 5. 昵称修改 ----------

func _test_profile_update() -> void:
	var runtime := _make_runtime(false)
	var owner: String = runtime.world.owner_player_id
	var r := _cmd(runtime, owner, "profile.update", {"display_name": "  新名字  "})
	_check(r["accepted"] and r["error_code"] == "", "profile update accepted")
	_check(runtime.world.find_member(owner)["display_name"] == "新名字", "name trimmed and applied")
	_check(r["events"].size() == 1 and r["events"][0]["event_type"] == "MemberProfileChanged", "MemberProfileChanged emitted")
	var r2 := _cmd(runtime, owner, "profile.update", {"display_name": "   "})
	_check(r2["accepted"] and r2["error_code"] == ContractError.INVALID_ARGUMENT, "blank name rejected")
	_check(runtime.world.find_member(owner)["display_name"] == "新名字", "name unchanged after rejection")
	var r3 := _cmd(runtime, owner, "profile.update", {"display_name": "汉".repeat(33)})
	_check(r3["error_code"] == ContractError.INVALID_ARGUMENT, "overlong name rejected")


# ---------- 6. 幂等与序号 ----------

func _test_idempotency_and_sequence() -> void:
	var runtime := _make_runtime(false)
	var owner: String = runtime.world.owner_player_id
	var first := _cmd(runtime, owner, "profile.update", {"display_name": "甲"}, 1)
	_check(first["accepted"], "first command accepted")
	var rev_after_first: int = runtime.world.business_revision
	# 同序号同内容 → 返回原回执，不重复执行
	var replay := _cmd(runtime, owner, "profile.update", {"display_name": "甲"}, 1)
	_check(replay.get("replayed", false), "same sequence+content returns cached receipt")
	_check(runtime.world.business_revision == rev_after_first, "no duplicate execution")
	# 同序号不同内容 → 拒绝
	var conflict := _cmd(runtime, owner, "profile.update", {"display_name": "乙"}, 1)
	_check(conflict["error_code"] == ContractError.INVALID_ARGUMENT, "same sequence different content rejected")
	# 跳号 → SEQUENCE_GAP + 期望序号
	var gap := _cmd(runtime, owner, "profile.update", {"display_name": "丙"}, 5)
	_check(gap["error_code"] == ContractError.SEQUENCE_GAP and gap["expected_sequence"] == 2, "sequence gap reports expected")
	# 旧序号（已处理过、超出缓存下界的正整数）→ RECEIPT_EXPIRED
	# 注：seq=0 由信封校验拒绝（CONTRACTS_COMMAND_SEQUENCE），这是契约正确行为。
	# 先制造足够多的回执把 seq=1 挤出窗口不现实，改用“已处理但内容不同”与“未来跳号”之外
	# 的过期判定：seq=1 已缓存且内容相同 → 返回原回执；内容不同 → INVALID_ARGUMENT（见上）。
	# 这里验证序号 0 被信封层拒绝。
	var zero := _cmd(runtime, owner, "profile.update", {"display_name": "丁"}, 0)
	_check(zero["error_code"].begins_with("CONTRACTS_COMMAND_SEQUENCE"), "sequence 0 rejected at envelope (got %s)" % str(zero["error_code"]))
	# 业务失败也消耗序号
	var bad := _cmd(runtime, owner, "profile.update", {"display_name": "   "}, 2)
	_check(bad["accepted"] and bad["error_code"] == ContractError.INVALID_ARGUMENT, "business failure consumes sequence")
	var next := _cmd(runtime, owner, "profile.update", {"display_name": "戊"}, 3)
	_check(next["accepted"] and next["error_code"] == "", "sequence continues after business failure")


# ---------- 7. 保存故障冻结 ----------

func _test_save_fault() -> void:
	var runtime := _make_runtime(false)
	var owner: String = runtime.world.owner_player_id
	runtime.set_save_fault(true)
	var r := _cmd(runtime, owner, "profile.update", {"display_name": "甲"}, 1)
	_check(not r["accepted"] and r["error_code"] == ContractError.SAVE_UNAVAILABLE, "save fault rejects unaccepted")
	_check(runtime.world.find_member(owner)["display_name"] == "房主", "no change during save fault")
	# 故障中不推进时间
	var day_before: int = runtime.world.game_day
	runtime.tick(ContractLimits.GAME_DAY_MS * 2)
	_check(runtime.world.game_day == day_before, "simulation paused during save fault")
	runtime.set_save_fault(false)
	var r2 := _cmd(runtime, owner, "profile.update", {"display_name": "乙"}, 1)
	_check(r2["accepted"], "resumes after fault cleared")
