extends SceneTree
## TRANSPORT-02 场景检查：六站存在、踩点解锁、呼叫面板、乘车计费计时长、
## 存读档含解锁状态、免费教学线路。实机画面加 --capture。

const SaveManager := preload("res://scripts/core/save_manager.gd")
const CarriageDB := preload("res://scripts/data/carriage_db.gd")

var game: Node3D
var failures: Array[String] = []
var count := 0
var capture_path := ""
var capture_size := Vector2i(1600, 1000)


func _initialize() -> void:
	var save_root := OS.get_environment("BREEZETOWN_SAVE_ROOT")
	if save_root.is_empty():
		save_root = ProjectSettings.globalize_path("res://../work/game-data")
	OS.set_environment("BREEZETOWN_SAVE_ROOT", save_root.path_join("carriage-checks-%d" % Time.get_ticks_usec()))
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):
			capture_path = argument.trim_prefix("--capture=")
		elif argument.begins_with("--capture-size="):
			var dimensions := argument.trim_prefix("--capture-size=").split("x")
			if dimensions.size() == 2 and dimensions[0].is_valid_int() and dimensions[1].is_valid_int():
				capture_size = Vector2i(maxi(640, dimensions[0].to_int()), maxi(480, dimensions[1].to_int()))
	create_timer(300).timeout.connect(func(): push_error("CARRIAGE_CHECKS timeout"); quit(1))
	_run.call_deferred()


func _check(label: String, ok: bool) -> void:
	count += 1
	print("CARRIAGE %s %s" % [label, "OK" if ok else "FAIL"])
	if not ok:
		failures.append(label)


func _frames(n: int) -> void:
	for i in range(n):
		await process_frame


func _until(condition: Callable, timeout_frames: int = 2400) -> bool:
	for i in range(timeout_frames):
		if condition.call():
			return true
		await process_frame
	return condition.call()


func _run() -> void:
	root.size = capture_size
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await _frames(5)
	await _stations_exist()
	await _unlock_and_ride()
	await _fee_and_matrix()
	await _save_restore()
	await _capture()
	var verdict := "PASS %d" % count if failures.is_empty() else "FAIL %s" % ",".join(failures)
	print("CARRIAGE_RESULT " + verdict)
	quit(0 if failures.is_empty() else 1)


func _stations_exist() -> void:
	for id: String in CarriageDB.ORDER:
		var pos: Vector3 = game.carriages.position_of(id)
		_check("station-positioned-" + id, pos.length() > 10.0 and is_finite(pos.x))
	# 站牌节点与停驻马车均已构建。
	_check("station-nodes-built", game._outdoors.find_children("CarriageStation_*", "Node3D", true, false).size() == CarriageDB.ORDER.size())
	# 默认仅农场/镇区解锁。
	_check("default-unlocks", game.carriages.is_unlocked("farm") and game.carriages.is_unlocked("town") and not game.carriages.is_unlocked("mine"))


func _unlock_and_ride() -> void:
	# 踩点解锁：走到矿口站旁 → 焦点出现并自动解锁。
	game.player.teleport(game.carriages.position_of("mine") + Vector3(0.8, 0, 0.6))
	await _frames(2)
	game._update_targeting()
	_check("mine-station-focus", game.focus.get("kind") == "carriage_station" and game.focus.get("id") == "mine")
	_check("mine-unlocked-on-visit", game.carriages.is_unlocked("mine"))
	# 呼叫面板：从矿口乘车回农场（4 时 10 币）。
	game.open_carriage("mine")
	_check("panel-opens", game.hud.carriage_open and game.player.locked)
	_check("panel-from-mine", game.hud.carriage_from_id == "mine")
	game.state.coins = 100
	var day: int = game.state.day
	var clock: float = game.state.clock
	game.hud.carriage_travel_requested.emit("farm")
	# 以"玩家到达车站坐标"为准轮询（淡出回调真实完成）。
	var rode: bool = await _until(func(): return game.player.global_position.distance_to(game.carriages.position_of("farm")) < 1.0)
	_check("rode-to-farm", rode)
	_check("time-charged", game.state.day > day or game.state.clock != clock)
	_check("fee-charged", game.state.coins == 100 - CarriageDB.RIDE_FEE)
	# 免费教学线路：农场↔镇区。
	game.player.teleport(game.carriages.position_of("farm") + Vector3(0.8, 0, 0.6))
	await _frames(2)
	game._update_targeting()
	_check("farm-station-focus", game.focus.get("kind") == "carriage_station")
	game.open_carriage("farm")
	game.hud.carriage_travel_requested.emit("town")
	var rode_free: bool = await _until(func(): return game.player.global_position.distance_to(game.carriages.position_of("town")) < 1.0)
	_check("free-line-no-fee", game.state.coins == 100 - CarriageDB.RIDE_FEE)
	_check("arrived-town", rode_free)
	# 穷旅客拒载。
	game.state.coins = 3
	game.open_carriage("town")
	game.hud.carriage_travel_requested.emit("mine")
	await _frames(2)
	_check("poor-refused", game.state.coins == 3 and game.hud.carriage_open)
	game.hud.close_carriage()


func _fee_and_matrix() -> void:
	# 矩阵对称且对角为零；免费线路仅农场—镇区。
	var symmetric := true
	for a: String in CarriageDB.ORDER:
		for b: String in CarriageDB.ORDER:
			if CarriageDB.hours_between(a, b) != CarriageDB.hours_between(b, a):
				symmetric = false
	_check("hours-matrix-symmetric", symmetric)
	_check("free-pair-only", CarriageDB.fee_between("farm", "town") == 0 and CarriageDB.fee_between("town", "farm") == 0 and CarriageDB.fee_between("mine", "lake") == CarriageDB.RIDE_FEE)


func _save_restore() -> void:
	# 解锁状态进存档：矿口已解锁（前段踩点），湖畔未解锁。
	game.state.coins = 250
	SaveManager.save_game(1, game._save_payload())
	await _frames(2)
	var saved: Dictionary = SaveManager.load_game(1)
	var unlocked: Array = saved.get("travel", {}).get("unlocked", [])
	_check("save-has-unlocks", unlocked.has("mine") and unlocked.has("farm") and not unlocked.has("lake"))
	game.carriages.from_dict({"unlocked": ["farm", "town"]})
	_check("pre-restore-locked", not game.carriages.is_unlocked("mine"))
	game._apply_load(saved)
	await _frames(3)
	_check("load-restores-unlocks", game.carriages.is_unlocked("mine") and not game.carriages.is_unlocked("lake"))
	# 解锁后的站点可直接乘车（读档后仍可用）。
	game.player.teleport(game.carriages.position_of("farm") + Vector3(0.8, 0, 0.6))
	await _frames(2)
	game._update_targeting()
	game.open_carriage("farm")
	var ride_button_ready: bool = game.hud.carriage_open
	game.hud.close_carriage()
	_check("post-load-panel-ready", ride_button_ready)


func _capture() -> void:
	if capture_path.is_empty():
		return
	game.player.teleport(game.carriages.position_of("farm") + Vector3(2.2, 0, 2.0))
	game._update_targeting()
	await _frames(8)
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var result := image.save_png(capture_path)
	print("CARRIAGE capture=%s %s" % [capture_path, error_string(result)])
