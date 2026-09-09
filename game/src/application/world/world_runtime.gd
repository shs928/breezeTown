class_name WorldRuntime
## 权威世界运行时（契约 3.1 WorldRuntime / 5.3 提交顺序）。
## 单写队列：所有命令串行处理；处理器返回提交计划 → 校验 → 原子应用 → 回执。
## 不读键盘、不开窗口、不依赖渲染场景（headless 可运行）。

const ContractLimits := preload("res://src/contracts/contract_limits.gd")
const ContractIds := preload("res://src/contracts/contract_ids.gd")
const ContractEnvelopes := preload("res://src/contracts/contract_envelopes.gd")
const ContractError := preload("res://src/contracts/contract_error.gd")
const TransactionCoordinator := preload("res://src/application/core/transaction_coordinator.gd")
const SimClock := preload("res://src/application/core/sim_clock.gd")
const WorldState := preload("res://src/domain/world/world_state.gd")

signal state_changed(revision: int)
signal day_advanced(game_day: int)
signal save_requested(reason: String)

var world: WorldState
var clock := SimClock.new()
var map_data: Dictionary = {}

var _day_barrier := false
var _pending_movement: Dictionary = {}   # player_id -> {x, y, input_sequence}
var _last_receipts: Dictionary = {}      # player_id -> {sequence: receipt}
var _save_fault := false
var _move_windows: Dictionary = {}   # player_id -> {window_start_ms, count}
var _handlers: Dictionary = {}           # command_type -> Callable(payload, player_id, batch) -> String
var _day_settle_hook: Callable = Callable()  # FARM 注册：settle_growth(ended_day, batch)
## 零真实玩家在线时暂停世界（契约 7.3；dedicated 同样遵守）。
## 未认证连接、机器人探针不算玩家。
var _pause_on_empty := false
var _online_players: Array = []


## 注册日切生长结算钩子（FARM 提供）。结算与日切在同一原子批次内完成。
func set_day_settle_hook(hook: Callable) -> void:
	_day_settle_hook = hook


## 设置“零在线暂停”策略与当前真实在线玩家列表（服务器每帧更新）。
func set_pause_on_empty(enabled: bool, online_players: Array) -> void:
	_pause_on_empty = enabled
	_online_players = online_players


func is_paused_for_empty() -> bool:
	return _pause_on_empty and _online_players.is_empty()


## 注册命令处理器（ECON/FARM 各注册自己的命令，避免 SIM 越界实现他人领域）。
func register_handler(command_type: String, handler: Callable) -> void:
	_handlers[command_type] = handler


func has_handler(command_type: String) -> bool:
	return _handlers.has(command_type) or command_type in ["world.move_input", "profile.update", "owner.save"]


func setup(world_state: WorldState, map: Dictionary) -> void:
	world = world_state
	map_data = map


## 推进模拟一步。返回本次是否发生日切。
func tick(delta_ms: int) -> bool:
	if _save_fault:
		return false
	if is_paused_for_empty():
		return false
	world.sim_tick += 1
	var advanced := clock.advance(delta_ms)
	world.day_elapsed_ms = clock.day_elapsed_ms
	if advanced > 0:
		_perform_day_advance()
	return advanced > 0


## 日切屏障：先完成当前批次，再结算生长/清浇水/递增日/重置当日桶，最后恢复命令。
## 生长结算由 FARM 在 M1 后续接入；此处负责顺序与状态边界。
func _perform_day_advance() -> void:
	_day_barrier = true
	var ended_day := world.game_day
	# 生长结算先于清浇水：结算依据是刚结束的游戏日是否浇过水。
	if _day_settle_hook.is_valid():
		var batch := TransactionCoordinator.Batch.new()
		_day_settle_hook.call(ended_day, batch)
		if not batch.ops.is_empty():
			var err := TransactionCoordinator.validate(world, batch)
			if err.is_empty():
				TransactionCoordinator.apply(world, batch, ended_day)
			else:
				push_error("day settle plan rejected: " + err)
	world.advance_day()
	# 日切也是业务提交：推进 business_revision，让客户端能通过差量看到新的一天。
	world.business_revision += 1
	_day_barrier = false
	day_advanced.emit(world.game_day)
	state_changed.emit(world.business_revision)
	save_requested.emit("day_advanced")


## 命令入口（本地与远端共用同一路由/校验/事务）。
func submit(command: Dictionary) -> Dictionary:
	var envelope_err := ContractEnvelopes.validate_command(command)
	if not envelope_err.is_empty():
		return _receipt(command, false, envelope_err)
	if command["world_id"] != world.world_id:
		return _receipt(command, false, ContractError.WORLD_MISMATCH)
	if command["authority_epoch"] != world.authority_epoch:
		return _receipt(command, false, ContractError.STALE_EPOCH)
	var player_id: String = str(command.get("_actor_player_id", ""))
	if player_id.is_empty() or not world.member_exists(player_id):
		return _receipt(command, false, ContractError.NOT_AUTHENTICATED)
	if _save_fault:
		return _receipt(command, false, ContractError.SAVE_UNAVAILABLE)
	if _day_barrier:
		return _receipt(command, false, ContractError.STALE_STATE)

	var seq := int(command["client_sequence"])
	var cached := _cached_receipt(player_id, seq)
	if not cached.is_empty():
		# 同序号同内容返回原回执；同序号不同内容拒绝。
		if cached["content_digest"] == JSON.stringify(command["payload"]).sha256_text():
			var replay: Dictionary = cached["receipt"].duplicate()
			replay["replayed"] = true
			return replay
		return _receipt(command, false, ContractError.INVALID_ARGUMENT)

	var expected := _next_expected(player_id)
	if seq < expected:
		return _receipt(command, false, ContractError.RECEIPT_EXPIRED)
	if seq > expected:
		var gap := _receipt(command, false, ContractError.SEQUENCE_GAP)
		gap["expected_sequence"] = expected
		return gap

	var batch := TransactionCoordinator.Batch.new()
	var handler_err := _handle(command["command_type"], command["payload"], player_id, batch)
	if not handler_err.is_empty():
		# 已受理的业务失败：消耗序号并缓存回执（契约 6.1）。
		var fail_receipt := _receipt(command, true, handler_err)
		_cache_receipt(player_id, seq, JSON.stringify(command["payload"]).sha256_text(), fail_receipt)
		return fail_receipt

	var plan_err := TransactionCoordinator.validate(world, batch)
	if not plan_err.is_empty():
		var plan_receipt := _receipt(command, true, plan_err)
		_cache_receipt(player_id, seq, JSON.stringify(command["payload"]).sha256_text(), plan_receipt)
		return plan_receipt

	var events := TransactionCoordinator.apply(world, batch, world.game_day)
	var invariant_err := TransactionCoordinator.check_invariants(world)
	if not invariant_err.is_empty():
		# 不变量失败说明计划有缺陷；M1 阶段直接报错，不静默继续。
		push_error("invariant violation after commit: " + invariant_err)
		return _receipt(command, true, ContractError.INVALID_ARGUMENT)

	var ok_receipt := _receipt(command, true, "")
	ok_receipt["events"] = events
	_cache_receipt(player_id, seq, JSON.stringify(command["payload"]).sha256_text(), ok_receipt)
	state_changed.emit(world.business_revision)
	if command["command_type"] == "inventory.transfer" or command["command_type"] == "economy.buy_seed" or command["command_type"] == "economy.sell":
		save_requested.emit("business")
	return ok_receipt


# ---------- 命令处理器（SIM 范围） ----------

func _handle(command_type: String, payload: Dictionary, player_id: String, batch: TransactionCoordinator.Batch) -> String:
	if _handlers.has(command_type):
		return str(_handlers[command_type].call(payload, player_id, batch))
	match command_type:
		"world.move_input":
			return _handle_move(payload, player_id, batch)
		"profile.update":
			return _handle_profile(payload, player_id, batch)
		"owner.save":
			save_requested.emit("manual")
			return ""
		_:
			return ContractError.NOT_ALLOWED


## 移动：归一化、限速、静态碰撞、玩家互不阻挡。位置不进经济日志。
func _handle_move(payload: Dictionary, player_id: String, _batch: TransactionCoordinator.Batch) -> String:
	# 移动限速：每秒最多 30 次输入（契约 10.3），超限丢弃（不消耗业务序号语义由 submit 层处理）。
	var now := Time.get_ticks_msec()
	var window: Dictionary = _move_windows.get(player_id, {"window_start_ms": now, "count": 0})
	if now - int(window["window_start_ms"]) >= 1000:
		window = {"window_start_ms": now, "count": 0}
	window["count"] = int(window["count"]) + 1
	_move_windows[player_id] = window
	if int(window["count"]) > ContractLimits.RATE_MOVE_PER_S:
		return ContractError.RATE_LIMITED
	var dx := float(payload["dx"])
	var dy := float(payload["dy"])
	var input_sequence := int(payload["input_sequence"])
	var member := world.find_member(player_id)
	var pos: Dictionary = member["last_valid_position"]
	# 服务端限速：按 input_sequence 单调，丢弃旧包。
	var last_seq := int(_pending_movement.get(player_id, {}).get("input_sequence", 0))
	if input_sequence <= last_seq:
		return ContractError.STALE_STATE
	var length := sqrt(dx * dx + dy * dy)
	if length <= 0.0:
		_pending_movement[player_id] = {"input_sequence": input_sequence}
		return ""
	var step := ContractLimits.PLAYER_SPEED_PX_PER_S * 0.05  # 20Hz 单步
	var nx := float(pos["x"]) + dx / length * step
	var ny := float(pos["y"]) + dy / length * step
	if not _is_walkable_px(nx, ny):
		# 尝试单轴滑动，仍不可行则原地不动。
		if _is_walkable_px(nx, float(pos["y"])):
			ny = float(pos["y"])
		elif _is_walkable_px(float(pos["x"]), ny):
			nx = float(pos["x"])
		else:
			nx = float(pos["x"])
			ny = float(pos["y"])
	member["last_valid_position"] = {"x": nx, "y": ny}
	_pending_movement[player_id] = {"input_sequence": input_sequence}
	return ""


func _handle_profile(payload: Dictionary, player_id: String, batch: TransactionCoordinator.Batch) -> String:
	var cleaned := ContractLimits.sanitize_display_name(str(payload["display_name"]))
	if cleaned.is_empty():
		return ContractError.INVALID_ARGUMENT
	batch.add_op({"op": "member_display_name", "player_id": player_id, "display_name": cleaned})
	batch.add_event("MemberProfileChanged", {"display_name": cleaned}, player_id)
	return ""


# ---------- 地图碰撞 ----------

## 像素坐标是否可行走。玩家有半径，检查脚下格与四角。
func _is_walkable_px(x: float, y: float) -> bool:
	var tiles: Array = map_data.get("tiles", [])
	if tiles.is_empty():
		return true  # 无地图数据时（单测）不阻挡
	var half := 12.0  # 玩家半宽（32px 角色留出边距）
	for offset in [Vector2(-half, -half), Vector2(half, -half), Vector2(-half, half), Vector2(half, half)]:
		var tx := int(floor((x + offset.x) / float(ContractLimits.TILE_SIZE_PX)))
		var ty := int(floor((y + offset.y) / float(ContractLimits.TILE_SIZE_PX)))
		if ty < 0 or ty >= tiles.size():
			return false
		var row: String = tiles[ty]
		if tx < 0 or tx >= row.length():
			return false
		if row[tx] == "B":
			return false
	return true


func is_tile_walkable(tile_id: int) -> bool:
	var tiles: Array = map_data.get("tiles", [])
	if tiles.is_empty():
		return true
	var tx := tile_id % ContractLimits.MAP_W
	var ty := tile_id / ContractLimits.MAP_W
	if ty < 0 or ty >= tiles.size():
		return false
	var row: String = tiles[ty]
	if tx < 0 or tx >= row.length():
		return false
	return row[tx] != "B"


# ---------- 回执与故障 ----------

func _receipt(command: Dictionary, accepted: bool, error_code: String) -> Dictionary:
	return {
		"client_sequence": int(command.get("client_sequence", 0)),
		"accepted": accepted,
		"error_code": error_code,
	}


func _cached_receipt(player_id: String, seq: int) -> Dictionary:
	return _last_receipts.get(player_id, {}).get(seq, {})


func _cache_receipt(player_id: String, seq: int, content_digest: String, receipt: Dictionary) -> void:
	if not _last_receipts.has(player_id):
		_last_receipts[player_id] = {}
	var cache: Dictionary = _last_receipts[player_id]
	cache[seq] = {"content_digest": content_digest, "receipt": receipt}
	# 每成员缓存最近 256 条
	if cache.size() > ContractLimits.RECEIPT_CACHE_PER_MEMBER:
		var keys := cache.keys()
		keys.sort()
		for i in keys.size() - ContractLimits.RECEIPT_CACHE_PER_MEMBER:
			cache.erase(keys[i])


## 成员当前应使用的下一个业务序号（客户端重连时查询高水位，契约 6.1）。
func next_expected_sequence(player_id: String) -> int:
	return _next_expected(player_id)


func _next_expected(player_id: String) -> int:
	var cache: Dictionary = _last_receipts.get(player_id, {})
	if cache.is_empty():
		return 1
	var keys := cache.keys()
	keys.sort()
	return int(keys[-1]) + 1


func set_save_fault(active: bool) -> void:
	_save_fault = active


func is_save_fault() -> bool:
	return _save_fault
