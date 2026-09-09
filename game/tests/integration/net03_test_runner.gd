extends SceneTree
## NET-03 测试（headless）：快照捕获、差量应用、revision 缺口检测、缓冲上限、轻量推进标记。
## 运行：godot --headless --path game --script res://tests/integration/net03_test_runner.gd

const ContractLimits := preload("res://src/contracts/contract_limits.gd")
const SyncBuffer := preload("res://src/application/sync/sync_buffer.gd")
const WorldState := preload("res://src/domain/world/world_state.gd")
const WorldRuntime := preload("res://src/application/world/world_runtime.gd")
const TransactionCoordinator := preload("res://src/application/core/transaction_coordinator.gd")

var _checks := 0
var _failures: PackedStringArray = []


func _initialize() -> void:
	_test_capture_and_apply()
	_test_revision_gap_detection()
	_test_lightweight_advance_marker()
	_test_buffer_limits()
	_test_private_filtering_no_false_gap()

	if _failures.is_empty():
		print("NET03_OK checks=%d" % _checks)
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: " + f)
		printerr("NET03_FAILED checks=%d failures=%d" % [_checks, _failures.size()])
		quit(1)


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(label)


func _make() -> Array:
	var world := WorldState.create("w" + "0123456789abcdef0123456789abcdef", "m" + "11111111111111111111111111111111", "房主")
	var runtime := WorldRuntime.new()
	runtime.setup(world, {})
	return [world, runtime, world.owner_player_id]


func _commit_treasury(world: WorldState, delta: int) -> void:
	var batch := TransactionCoordinator.Batch.new()
	batch.add_op({"op": "treasury_delta", "delta": delta})
	batch.add_op({"op": "world_total_sales", "delta": delta})
	TransactionCoordinator.apply(world, batch, world.game_day)


# ---------- 1. 捕获与按序应用 ----------

func _test_capture_and_apply() -> void:
	var ctx := _make()
	var world: WorldState = ctx[0]
	var owner: String = ctx[2]
	var buffer := SyncBuffer.new()
	var captured := buffer.capture(world, owner, [owner])
	_check(captured["ok"], "capture baseline")
	var base_rev := int(captured["snapshot"]["base_revision"])
	_check(base_rev == 0, "baseline revision 0")
	# 三次提交 → 三个差量
	_commit_treasury(world, 10)
	buffer.push(world, owner, [owner])
	_commit_treasury(world, 20)
	buffer.push(world, owner, [owner])
	_commit_treasury(world, 30)
	buffer.push(world, owner, [owner])
	_check(buffer.delta_count() == 3, "three deltas buffered")
	var applied := buffer.apply_all(base_rev)
	_check(applied["ok"], "all deltas apply in order")
	_check(int(applied["applied"]) == 3, "three deltas applied")
	_check(int(applied["revision"]) == 3, "final revision 3")
	_check(not applied["needs_resync"], "no resync needed")


# ---------- 2. revision 缺口检测 ----------

func _test_revision_gap_detection() -> void:
	var ctx := _make()
	var world: WorldState = ctx[0]
	var owner: String = ctx[2]
	var buffer := SyncBuffer.new()
	buffer.capture(world, owner, [owner])
	_commit_treasury(world, 10)
	buffer.push(world, owner, [owner])
	# 客户端本地 revision 与差量 base 不连续 → 要求重同步
	var delta: Dictionary = buffer.deltas[0]
	var result := buffer.apply_delta(99, delta)
	_check(not result["ok"] and result["needs_resync"], "gap detected")
	_check(result["reason"] == "revision_gap", "gap reason")
	# 正确 revision 可应用
	var ok := buffer.apply_delta(0, delta)
	_check(ok["ok"] and int(ok["target_revision"]) == 1, "correct revision applies")


# ---------- 3. 轻量推进标记（无可见变化） ----------

func _test_lightweight_advance_marker() -> void:
	var ctx := _make()
	var world: WorldState = ctx[0]
	var owner: String = ctx[2]
	var second: Dictionary = world.add_member("队友")
	var buffer := SyncBuffer.new()
	buffer.capture(world, owner, [owner])
	# 给第二名成员改昵称：owner 的可见视图里 members 会变，因此是有可见变化的
	var batch := TransactionCoordinator.Batch.new()
	batch.add_op({"op": "member_display_name", "player_id": second["player_id"], "display_name": "新名"})
	TransactionCoordinator.apply(world, batch, 1)
	var pushed := buffer.push(world, owner, [owner])
	_check(pushed["ok"], "delta pushed after visible change")
	_check(pushed["delta"]["view"] != null, "visible change carries view")
	# 一次纯内部提交（revision 推进但 owner 视图无变化）：模拟只有 sim_tick 变化
	var batch2 := TransactionCoordinator.Batch.new()
	batch2.add_op({"op": "member_display_name", "player_id": owner, "display_name": world.find_member(owner)["display_name"]})
	TransactionCoordinator.apply(world, batch2, 1)
	var pushed2 := buffer.push(world, owner, [owner])
	_check(pushed2["ok"], "second delta pushed")
	_check(pushed2["delta"]["view"] == null, "no visible change → lightweight marker (view null)")
	# 轻量标记仍推进 revision，不制造虚假缺口
	var applied := buffer.apply_all(0)
	_check(applied["ok"] and int(applied["revision"]) == 2, "lightweight markers keep revision continuous")


# ---------- 4. 缓冲上限 ----------

func _test_buffer_limits() -> void:
	var ctx := _make()
	var world: WorldState = ctx[0]
	var owner: String = ctx[2]
	var buffer := SyncBuffer.new()
	buffer.capture(world, owner, [owner])
	# 直接注入超限字节数，验证中止语义
	buffer.buffer_bytes = SyncBuffer.BUFFER_MAX_BYTES + 1
	buffer.aborted = true
	buffer.abort_reason = "buffer_bytes_exceeded"
	var pushed := buffer.push(world, owner, [owner])
	_check(not pushed["ok"] and pushed["reason"] == "buffer_bytes_exceeded", "aborted buffer refuses push")
	_check(buffer.delta_count() == 0, "no delta added after abort")
	# 重新捕获可恢复
	var recaptured := buffer.capture(world, owner, [owner])
	_check(recaptured["ok"] and not buffer.aborted, "recapture recovers from abort")


# ---------- 5. 私有过滤不制造虚假缺口 ----------

func _test_private_filtering_no_false_gap() -> void:
	var ctx := _make()
	var world: WorldState = ctx[0]
	var owner: String = ctx[2]
	var second: Dictionary = world.add_member("队友")
	world.containers[second["inventory_id"]] = {"capacity": 24, "slots": WorldState.empty_slots(24), "revision": 0}
	var buffer := SyncBuffer.new()
	buffer.capture(world, owner, [owner])
	# 修改第二名成员的背包：owner 视图看不到（私有数据过滤），但 revision 推进
	world.containers[second["inventory_id"]]["slots"][0] = {"item_definition_id": "seed.radish", "quantity": 5}
	world.business_revision += 1
	var pushed := buffer.push(world, owner, [owner])
	_check(pushed["ok"], "push after foreign private change")
	_check(pushed["delta"]["view"] == null, "foreign private change invisible to owner")
	var applied := buffer.apply_all(0)
	_check(applied["ok"], "no false gap from private filtering")
