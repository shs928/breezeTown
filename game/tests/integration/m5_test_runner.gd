extends SceneTree
## M5 测试（headless）：ART-01 素材加载、UI-06 引导与键位重绑定、PERF-01 基础性能采集。
## 说明：CASE-37 的真人可用性由 QA-03/M6 执行，本测试只做内部预验与素材/性能证据。
## 运行：godot --headless --path game --script res://tests/integration/m5_test_runner.gd

const ContractLimits := preload("res://src/contracts/contract_limits.gd")
const ContractError := preload("res://src/contracts/contract_error.gd")
const ClientRoot := preload("res://src/client/client_root.gd")
const InputSettings := preload("res://src/client/input_settings.gd")
const ItemCatalog := preload("res://src/domain/economy/item_catalog.gd")
const WorldState := preload("res://src/domain/world/world_state.gd")
const SaveScheduler := preload("res://src/infrastructure/persistence/save_scheduler.gd")
const WorldRepository := preload("res://src/infrastructure/persistence/world_repository.gd")

var _checks := 0
var _failures: PackedStringArray = []
var _root := ""


func _initialize() -> void:
	_root = ProjectSettings.globalize_path("res://../work/game-data/m5/%d" % Time.get_unix_time_from_system())
	DirAccess.make_dir_recursive_absolute(_root)

	_test_assets_present()
	_test_tutorial_flow()
	_test_rebinding_and_persistence()
	_test_settings_persistence()
	_test_performance_baseline()

	if _failures.is_empty():
		print("M5_OK checks=%d run_dir=%s" % [_checks, _root])
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: " + f)
		printerr("M5_FAILED checks=%d failures=%d" % [_checks, _failures.size()])
		quit(1)


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(label)


func _make_client(name: String) -> ClientRoot:
	var client := ClientRoot.new()
	client.mode = "solo"
	client.catalog = ItemCatalog.load_from_disk()
	client._user_data_dir = _root + "/" + name + "/user_data"
	client._worlds_dir = _root + "/" + name + "/worlds"
	DirAccess.make_dir_recursive_absolute(client._user_data_dir)
	DirAccess.make_dir_recursive_absolute(client._worlds_dir)
	client.settings.load_or_default(client._user_data_dir)
	return client


# ---------- 1. 素材存在且可加载 ----------

func _test_assets_present() -> void:
	var required: Array[String] = [
		"tile_grass", "tile_soil", "tile_soil_tilled", "tile_soil_wet", "tile_path",
		"tile_blocked", "tile_facility", "tile_spawn",
		"avatar_1", "avatar_2", "avatar_3", "avatar_4",
		"crop_radish_sown", "crop_radish_mature",
		"crop_potato_mature", "crop_wheat_mature", "crop_carrot_mature", "crop_strawberry_mature",
		"tool_hoe", "tool_watering_can", "tool_hand",
		"icon_seed", "icon_coin", "building_shop", "building_storage", "building_monument",
	]
	var missing := 0
	for name: String in required:
		var path := "res://assets/generated/%s.png" % name
		if not ResourceLoader.exists(path):
			missing += 1
			printerr("missing asset: " + name)
	_check(missing == 0, "all required assets present (missing=%d)" % missing)
	# 四个角色配色各不相同
	var seen := {}
	for i in range(1, 5):
		var tex: Texture2D = load("res://assets/generated/avatar_%d.png" % i)
		_check(tex != null and tex.get_width() == 32 and tex.get_height() == 32, "avatar %d is 32x32" % i)
		seen[tex.get_image().get_pixel(16, 20).to_html()] = true
	_check(seen.size() == 4, "four distinct avatar colors (got %d)" % seen.size())


# ---------- 2. 引导流程 ----------

func _test_tutorial_flow() -> void:
	var client := _make_client("tutorial")
	_check(not client.tutorial_done(), "tutorial not done initially")
	var steps := client.tutorial_steps()
	_check(steps.size() >= 8, "at least 8 tutorial steps (got %d)" % steps.size())
	# 逐步推进
	for i in steps.size():
		var result := client.action_advance_tutorial()
		_check(not bool(result["done"]), "step %d advanced" % i)
		_check(not str(result["text"]).is_empty(), "step %d has text" % i)
	_check(client.tutorial_done(), "tutorial completes")
	var finished := client.action_advance_tutorial()
	_check(bool(finished["done"]), "further advance reports done")
	# 引导涵盖核心动作
	var actions: Array = []
	for step: Dictionary in steps:
		actions.append(step["action"])
	for required: String in ["move", "till", "plant", "water", "harvest", "sell", "board"]:
		_check(required in actions, "tutorial covers %s" % required)


# ---------- 3. 键位重绑定与冲突 ----------

func _test_rebinding_and_persistence() -> void:
	var settings := InputSettings.new()
	var dir := _root + "/rebind"
	DirAccess.make_dir_recursive_absolute(dir)
	settings.load_or_default(dir)
	_check(settings.binding_of("move_up") == "W", "default move_up is W")
	# 重绑定成功
	var ok := settings.rebind("move_up", "UP")
	_check(ok["ok"] and settings.binding_of("move_up") == "UP", "rebind move_up to UP")
	# 冲突拒绝且不改动
	var conflict := settings.rebind("move_down", "UP")
	_check(not conflict["ok"] and conflict["error"] == "conflict" and conflict["conflict_with"] == "move_up", "conflict detected")
	_check(settings.binding_of("move_down") == "S", "conflict did not change binding")
	# 不可重绑定动作
	var invalid := settings.rebind("attack", "X")
	_check(not invalid["ok"] and invalid["error"] == "not_rebindable", "unknown action not rebindable")
	# 空键
	var empty := settings.rebind("move_left", "")
	_check(not empty["ok"], "empty key rejected")
	# 持久化：重新加载
	var reloaded := InputSettings.new()
	reloaded.load_or_default(dir)
	_check(reloaded.binding_of("move_up") == "UP", "binding persisted")
	# 恢复默认
	reloaded.restore_defaults()
	_check(reloaded.binding_of("move_up") == "W", "defaults restored")
	# 冲突检查器
	var dup := InputSettings.new()
	dup.load_or_default(_root + "/rebind_dup")
	dup.bindings["move_up"] = "S"   # 人为制造重复
	_check(dup.conflicts().size() == 1, "conflict inspector finds duplicate")


# ---------- 4. 设置持久化 ----------

func _test_settings_persistence() -> void:
	var client := _make_client("settings")
	client.action_apply_settings(0.5, 0.25, 1.25, false)
	var state := client.settings_state()
	_check(absf(float(state["master_volume"]) - 0.5) < 0.01, "master volume applied")
	_check(absf(float(state["sfx_volume"]) - 0.25) < 0.01, "sfx volume applied")
	_check(absf(float(state["ui_scale"]) - 1.25) < 0.01, "ui scale applied")
	# 越界钳制
	client.action_apply_settings(2.0, -1.0, 5.0, false)
	state = client.settings_state()
	_check(absf(float(state["master_volume"]) - 1.0) < 0.01, "master clamped to 1.0")
	_check(absf(float(state["sfx_volume"]) - 0.0) < 0.01, "sfx clamped to 0.0")
	_check(absf(float(state["ui_scale"]) - 1.5) < 0.01, "ui scale clamped to 1.5")
	# 重新加载后保持
	var reloaded := _make_client("settings_reload")
	reloaded._user_data_dir = client._user_data_dir
	reloaded.settings.load_or_default(reloaded._user_data_dir)
	_check(absf(reloaded.settings.master_volume - 1.0) < 0.01, "settings persisted across load")


# ---------- 5. 性能基准采集 ----------

func _test_performance_baseline() -> void:
	var client := _make_client("perf")
	client.action_create_world("房主", "性能世界")
	# 构造 256 株作物（NFR-02 的满载场景）
	var planted := 0
	var tiles: Array[int] = []
	for y in range(26, 38):
		for x in range(26, 38):
			tiles.append(y * ContractLimits.MAP_W + x)
	# 扩到 256 格需要 16x16，这里用 144 格 + 复制到其他可耕格
	for y in range(24, 40):
		for x in range(24, 40):
			var tid := y * ContractLimits.MAP_W + x
			if tiles.size() >= 256:
				break
			tiles.append(tid)
	for i in min(256, tiles.size()):
		var tid: int = tiles[i]
		var crop_id := "ci%032x" % i
		client.session.world.plots[str(tid)] = {"state": "planted", "crop_instance_id": crop_id}
		client.session.world.crops[crop_id] = {
			"crop_instance_id": crop_id, "crop_definition_id": "crop.radish",
			"tile_id": tid, "growth_days": 1, "planted_day": 1, "watered_day": 1,
		}
		planted += 1
	_check(planted >= 256, "256 crops planted for perf baseline (got %d)" % planted)
	# 模拟 30 秒权威 tick（600 次 50ms）。注意：常规 tick 是 O(1)，仅日切时遍历作物；
	# 这里额外强制一次日切以覆盖满载结算路径（NFR-02 的最坏情况）。
	var start := Time.get_ticks_usec()
	var ticks := 0
	for i in 600:
		client.session.runtime.tick(50)
		ticks += 1
	# 强制日切一次（256 株全部结算生长）
	var day_start := Time.get_ticks_usec()
	client.session.runtime.tick(ContractLimits.GAME_DAY_MS)
	var day_us := Time.get_ticks_usec() - day_start
	print("PERF day-advance with 256 crops: %.1fms" % (day_us / 1000.0))
	_check(day_us < 50000, "day advance under 50ms with 256 crops (%.1fms)" % (day_us / 1000.0))
	var elapsed_us := Time.get_ticks_usec() - start
	var per_tick_us := float(elapsed_us) / float(ticks)
	print("PERF tick: %d ticks in %.1fms, %.0fus/tick, crops=%d" % [ticks, elapsed_us / 1000.0, per_tick_us, planted])
	# 20Hz 目标：单 tick 处理应远低于 50ms
	_check(per_tick_us < 50000.0, "tick under 50ms budget (%.0fus)" % per_tick_us)
	# 保存耗时
	var repo: WorldRepository = client.session.repository
	var save_start := Time.get_ticks_usec()
	var save_result := repo.save(client.session.world)
	var save_us := Time.get_ticks_usec() - save_start
	print("PERF save: %.1fms for 256 crops (ok=%s)" % [save_us / 1000.0, str(save_result["ok"])])
	_check(save_result["ok"], "save succeeds with 256 crops")
	_check(save_us < 1_000_000, "save under 1s P95 budget (%.1fms)" % (save_us / 1000.0))
	# 内存：粗测进程 RSS
	var rss_kb := _rss_kb()
	print("PERF rss: %d KiB" % rss_kb)
	_check(rss_kb < 1024 * 1024, "RSS under 1GiB (got %d KiB)" % rss_kb)
	client.action_quit()


## 测量**本进程**的 RSS（不是 shell 的）。
func _rss_kb() -> int:
	var output: Array = []
	OS.execute("ps", PackedStringArray(["-o", "rss=", "-p", str(OS.get_process_id())]), output, true)
	if output.is_empty():
		return 0
	return int(str(output[0]).strip_edges())
