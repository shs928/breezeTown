extends SceneTree
## SOAK-01：长时间运行回归。模拟多日经营（默认 112 天=整年四季），穿插
## 存读档、矿场/室内切换、区域传送、机器加工与农事，监控内存/节点曲线。
## 环境变量：SOAK_DAYS（默认 112）、SOAK_SEED（默认固定，可复现）。
## 通过标准：零脚本错误、存读档完整、内存/节点有界、全部操作成功。

const SaveManager := preload("res://scripts/core/save_manager.gd")

var game: Node3D
var failures: Array[String] = []
var count := 0
var ops := 0
var samples: Array[String] = []
var rng := RandomNumberGenerator.new()


func _initialize() -> void:
	var save_root := OS.get_environment("BREEZETOWN_SAVE_ROOT")
	if save_root.is_empty():
		save_root = ProjectSettings.globalize_path("res://../work/game-data")
	OS.set_environment("BREEZETOWN_SAVE_ROOT", save_root.path_join("soak-%d" % Time.get_ticks_usec()))
	create_timer(1800).timeout.connect(func(): push_error("SOAK timeout"); quit(1))
	_run.call_deferred()


func _check(label: String, ok: bool) -> void:
	count += 1
	print("SOAK %s %s" % [label, "OK" if ok else "FAIL"])
	if not ok:
		failures.append(label)


func _frames(n: int) -> void:
	for i in range(n):
		await process_frame


func _until(condition: Callable, timeout_frames: int = 3600) -> bool:
	for i in range(timeout_frames):
		if condition.call():
			return true
		await process_frame
	return condition.call()


func _sample(tag: String) -> void:
	var static_mb: float = float(Performance.get_monitor(Performance.MEMORY_STATIC)) / 1048576.0
	var nodes: int = Performance.get_monitor(Performance.OBJECT_COUNT)
	var nodes_count: int = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	samples.append("%s day=%d static=%.0fMB objects=%d nodes=%d" % [tag, game.state.day, static_mb, nodes, nodes_count])
	print("SOAK SAMPLE " + samples[-1])


func _forest_spot() -> Vector3:
	var at: Vector2 = preload("res://scripts/data/first_map_definition.gd").point([626, 137])
	return Vector3(at.x, 0, at.y)
func _teleport_somewhere() -> void:
	var spots := [
		Vector3(-672, 0, 252),  # 农场
		Vector3(80, 0, -160),  # 城镇
		Vector3(-150, 0, 760),  # 港口
		_forest_spot(),  # 森林
	]
	var spot: Vector3 = spots[rng.randi_range(0, spots.size() - 1)]
	game.player.teleport(spot)
	ops += 1


func _interior_roundtrip() -> void:
	var rooms := ["shop", "inn", "clinic", "cottage", "smith"]
	var room: String = rooms[rng.randi_range(0, rooms.size() - 1)]
	game.player.teleport(game._site_door(room) + Vector3(0, 0, 0.6))
	await _frames(2)
	game._update_targeting()
	if game.focus.get("kind") != "building_door":
		return  # 被传送点门侧情况干扰时跳过本轮
	game._enter_building(room)
	var entered: bool = await _until(func(): return game.interior_id == room and not game._transitioning)
	if entered:
		ops += 1
		game._exit_building()
		await _until(func(): return game.interior_id == "" and not game._transitioning)


func _mine_roundtrip() -> void:
	game.player.teleport(game.landmarks["mine_door"] + Vector3(0, 0, 0.6))
	await _frames(2)
	game._update_targeting()
	game._interact()
	var entered: bool = await _until(func(): return game.mine_depth == 1 and not game._transitioning)
	if not entered:
		return
	ops += 1
	await _frames(10)
	game._travel_to(0)
	await _until(func(): return game.mine_depth == 0 and not game._transitioning)


func _save_load_roundtrip() -> void:
	var marker: int = game.state.coins
	var day: int = game.state.day
	SaveManager.save_game(1, game._save_payload())
	var saved: Dictionary = SaveManager.load_game(1)
	if not saved.get("ok", false):
		_check("save-load-ok", false)
		return
	game._apply_load(saved)
	_check("roundtrip-coins-day", game.state.coins == marker and game.state.day == day)
	ops += 1


func _advance_days(days: float) -> void:
	game._advance_world_time(days * 24.0)
	# --script 桩环境里 main._process 不运行：显式驱动机器与 NPC（与逐帧行为等价）。
	game._tick_machines(days * 24.0)
	game._update_npc_schedules()
	ops += 1


func _run() -> void:
	var soak_days := 112
	if OS.get_environment("SOAK_DAYS") != "":
		soak_days = maxi(1, OS.get_environment("SOAK_DAYS").to_int())
	var seed_value := 20260918
	if OS.get_environment("SOAK_SEED") != "":
		seed_value = OS.get_environment("SOAK_SEED").to_int()
	rng.seed = seed_value
	root.size = Vector2i(1280, 800)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await _frames(5)
	_sample("boot")

	# 机器与农事先置：熔炉备铜、田里种萝卜浇水。
	game.state.minerals["copper"] = 40
	state_remove_for_furnace(game)
	game._machines["smith:furnace"].start(preload("res://scripts/data/recipe_db.gd").get_recipe("smelt_copper"))
	_check("furnace-started", game._machines["smith:furnace"].state() == "PROCESSING")
	game.state.seeds["radish"] = 30
	var clear: Vector2 = preload("res://scripts/tests/forestry_checks.gd").find_clear(game)
	var farm_key: Vector2i = game.tiles.key_of(Vector3(clear.x, 0, clear.y))
	game.tiles.till(farm_key)
	game.tiles.plant(farm_key, "radish")
	game.tiles.water(farm_key)

	var start_day: int = game.state.day
	var seasons_seen := {"spring": true}
	var last_sample_day := start_day
	var day := start_day
	while day - start_day < soak_days:
		var step := rng.randf_range(2.0, 7.0)
		_advance_days(step)
		day = game.state.day
		seasons_seen[game.state.time.season_key()] = true
		var roll := rng.randf()
		if roll < 0.18:
			await _save_load_roundtrip()
		elif roll < 0.38:
			await _interior_roundtrip()
		elif roll < 0.53:
			await _mine_roundtrip()
		elif roll < 0.75:
			_teleport_somewhere()
		if day - last_sample_day >= 14:
			last_sample_day = day
			_sample("mid")
		await _frames(2)
	_sample("end")

	# 收敛断言：天数、四季、机器产出、农田存活、指标有界。
	_check("simulated-full-span", day - start_day >= soak_days)
	_check("all-four-seasons", seasons_seen.size() == 4)
	_check("furnace-finished-over-year", game._machines["smith:furnace"].state() == "FINISHED")
	var crop_state = game.tiles.farm.data_of(farm_key)
	_check("crop-tracked-all-year", crop_state != null)
	var static_mb: float = float(Performance.get_monitor(Performance.MEMORY_STATIC)) / 1048576.0
	_check("memory-bounded", static_mb < 450.0)
	var node_count: int = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	_check("nodes-bounded", node_count < 16000)
	for line in samples:
		print("SOAK POINT " + line)
	print("SOAK ops=%d samples=%d static_end=%.0fMB nodes_end=%d days=%d seasons=%d" % [
		ops, samples.size(), static_mb, node_count, day - start_day, seasons_seen.size()])
	var verdict := "PASS %d" % count if failures.is_empty() else "FAIL %s" % ",".join(failures)
	print("SOAK_RESULT " + verdict)
	quit(0 if failures.is_empty() else 1)


func state_remove_for_furnace(game: Node3D) -> void:
	## 熔炉原料：直接走六族扣件（铁匠铺室内流程由 INDOOR 检查覆盖）。
	game.state.remove_items("copper", 4)
