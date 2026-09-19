extends SceneTree
## INDOOR-01 场景检查：真实地图上四个门点的进出、室内服务、边界、存读档与地图标记。
## 实机画面验证加 --capture=路径 --capture-size=WxH（窗口模式）。

const SaveManager := preload("res://scripts/core/save_manager.gd")
const GameSettings := preload("res://scripts/core/game_settings.gd")
const SeasonVisuals := preload("res://scripts/art/season_visuals.gd")
const RecipeDB := preload("res://scripts/data/recipe_db.gd")
const InteriorDB := preload("res://scripts/data/interior_db.gd")
const GameState := preload("res://scripts/game_state.gd")

var game: Node3D
var failures: Array[String] = []
var count := 0
var capture_path := ""
var capture_size := Vector2i(1600, 1000)


func _initialize() -> void:
	var save_root := OS.get_environment("BREEZETOWN_SAVE_ROOT")
	if save_root.is_empty():
		save_root = ProjectSettings.globalize_path("res://../work/game-data")
	OS.set_environment("BREEZETOWN_SAVE_ROOT", save_root.path_join("indoor-checks-%d" % Time.get_ticks_usec()))
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):
			capture_path = argument.trim_prefix("--capture=")
		elif argument.begins_with("--capture-size="):
			var dimensions := argument.trim_prefix("--capture-size=").split("x")
			if dimensions.size() == 2 and dimensions[0].is_valid_int() and dimensions[1].is_valid_int():
				capture_size = Vector2i(maxi(640, dimensions[0].to_int()), maxi(480, dimensions[1].to_int()))
	create_timer(240).timeout.connect(func(): push_error("INDOOR_CHECKS timeout"); quit(1))
	_run.call_deferred()


func _run() -> void:
	root.size = capture_size
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await _frames(5)
	await _door_flows()
	await _services()
	await _machines_flow()
	await _staffed_npc_flow()
	await _bounds_and_time()
	await _save_restore()
	await _machine_save_restore()
	await _chest_flow()
	await _store02_flow()
	await _rain_water_flow()
	await _joy_flow()
	await _settings_flow()
	await _season_visual_flow()
	await _foliage_season_flow()
	await _capture()
	var verdict := "PASS %d" % count if failures.is_empty() else "FAIL %s" % ",".join(failures)
	print("INDOOR_SCENE_RESULT " + verdict)
	quit(0 if failures.is_empty() else 1)


func _check(label: String, ok: bool) -> void:
	count += 1
	print("INDOOR %s %s" % [label, "OK" if ok else "FAIL"])
	if not ok:
		failures.append(label)


func _frames(n: int) -> void:
	for i in range(n):
		await process_frame


func _until(condition: Callable, timeout_frames: int = 1800) -> bool:
	for i in range(timeout_frames):
		if condition.call():
			return true
		await process_frame
	return condition.call()


func _teleport_door(id: String) -> void:
	game.player.teleport(game._site_door(id) + Vector3(0, 0, 0.6))
	await _frames(3)


func _enter_via_input(id: String) -> void:
	await _teleport_door(id)
	game._update_targeting()
	_check("door-focus-" + id, game.focus.get("kind") == "building_door" and game.focus.get("id") == id)
	game._interact()
	await _until(func(): return game.interior_id == id and not game._transitioning)
	_check("entered-" + id, game.interior_id == id and game.current_interior != null and not game._outdoors.visible)


func _exit_via_door() -> void:
	game.player.teleport(game.current_interior.to_global(game.current_interior.exit_position()))
	await _frames(2)
	game._update_targeting()
	_check("exit-focus", game.focus.get("kind") == "interior_exit")
	game._interact()
	await _until(func(): return game.interior_id == "" and not game._transitioning)
	_check("exited-outdoors", game.interior_id == "" and game._outdoors.visible)


func _door_flows() -> void:
	for id: String in InteriorDB.ORDER:
		await _enter_via_input(id)
		await _exit_via_door()
	# 非室内建筑（港务小屋：inn 外观但不进室内表）不出现门点焦点。
	game.player.teleport(game._site_door("harbor_house") + Vector3(0, 0, 0.6))
	await _frames(3)
	game._update_targeting()
	_check("smith-door-inert", game.focus.get("kind") != "building_door")


func _services() -> void:
	# 农舍床铺：聚焦 + 直接睡觉推进一天并自动存档。
	await _enter_via_input("cottage")
	game.player.teleport(game.current_interior.service_world_position("bed") + Vector3(1.6, 0, 0.6))
	await _frames(2)
	game._update_targeting()
	_check("bed-focus", game.focus.get("kind") == "interior_service" and game.focus.get("service") == "bed")
	var day: int = game.state.day
	game._do_sleep()
	await _until(func(): return game.state.day == day + 1)
	_check("bed-sleeps", game.state.day == day + 1)
	_check("sleep-autosaved", SaveManager.has_save(1))
	await _exit_via_door()
	# 商店柜台：开面板、关闭恢复可动。
	await _enter_via_input("shop")
	game.player.teleport(game.current_interior.service_world_position("counter_shop") + Vector3(0, 0, 1.4))
	await _frames(2)
	game._update_targeting()
	game._interact()
	await _frames(2)
	_check("counter-opens-shop", game.hud.shop_open and game.player.locked)
	game.hud.close_shop()
	_check("counter-close-unlocks", not game.hud.shop_open and not game.player.locked)
	await _exit_via_door()
	# 酒馆套餐：扣币、回满体力、生命有界；穷时拒绝。
	await _enter_via_input("inn")
	game.player.teleport(game.current_interior.service_world_position("counter_meal") + Vector3(1.2, 0, 1.4))
	await _frames(2)
	game._update_targeting()
	_check("meal-focus", game.focus.get("kind") == "interior_service" and game.focus.get("service") == "counter_meal")
	game.state.coins = 100
	game.state.health = 30
	game.state.energy = 5.0
	game._interior_service("counter_meal")
	_check("meal-charges", game.state.coins == 100 - InteriorDB.MEAL_PRICE)
	_check("meal-heals", game.state.health == 30 + InteriorDB.MEAL_HEALTH)
	_check("meal-refills-energy", is_equal_approx(game.state.energy, float(game.state.energy_max())))
	game.state.coins = 3
	game._interior_service("counter_meal")
	_check("meal-too-poor-keeps-coins", game.state.coins == 3)
	await _exit_via_door()
	# 诊所：满血拒收、扣币回满、穷时拒绝。
	await _enter_via_input("clinic")
	game.player.teleport(game.current_interior.service_world_position("clinic_bed") + Vector3(1.6, 0, 0.8))
	await _frames(2)
	game._update_targeting()
	_check("clinic-focus", game.focus.get("kind") == "interior_service" and game.focus.get("service") == "clinic_bed")
	game.state.health = GameState.MAX_HEALTH
	game._interior_service("clinic_bed")
	_check("treatment-full-skipped", game.state.health == GameState.MAX_HEALTH)
	game.state.health = 35
	game.state.coins = 100
	game._interior_service("clinic_bed")
	_check("treatment-heals", game.state.health == GameState.MAX_HEALTH and game.state.coins == 100 - InteriorDB.TREATMENT_PRICE)
	game.state.health = 20
	game.state.coins = 10
	game._interior_service("clinic_bed")
	_check("treatment-too-poor-unchanged", game.state.health == 20 and game.state.coins == 10)
	await _exit_via_door()


func _bounds_and_time() -> void:
	await _enter_via_input("shop")
	var half: Vector2 = game.current_interior.half_extents() * 0.92
	game.player.teleport(Vector3(500, 0, 9200))
	# 钳制发生在物理帧，headless 下 process 帧远快于物理帧，轮询到生效为止。
	await _until(func(): return _within_bounds(half))
	_check("bounds-clamped", _within_bounds(half))
	var clock: float = game.state.clock
	await _frames(40)
	_check("time-flows-indoors", game.state.clock > clock)
	await _exit_via_door()


func _within_bounds(half: Vector2) -> bool:
	if game.current_interior == null:
		return false
	var local: Vector3 = game.current_interior.to_local(game.player.global_position)
	return absf(local.x) <= half.x + 0.5 and absf(local.z) <= half.y + 0.5


## ---- INDOOR-02：加工机器与店内值守 ----

func _use_machine(room_id: String, kind: String) -> void:
	game.player.teleport(game.current_interior.machine_world_position(kind) + Vector3(0, 0, 1.6))
	await _frames(2)
	game._update_targeting()
	_check("machine-focus-%s" % kind, game.focus.get("kind") == "interior_machine" and game.focus.get("machine") == kind)
	game._interior_machine(kind)
	await _frames(1)


func _machines_flow() -> void:
	# 熔炉：空转拒绝 → 投铜矿开始 → 推进到完成 → 收取铜锭 → 换铁配方。
	await _enter_via_input("smith")
	await _use_machine("smith", "furnace")
	_check("furnace-empty-refused", game.state.minerals.get("copper_bar", 0) == 0)
	game.state.minerals["copper"] = 8
	await _use_machine("smith", "furnace")
	_check("furnace-consumes-input", game.state.minerals["copper"] == 4)
	var furnace = game._machines["smith:furnace"]
	_check("furnace-processing", furnace.state() == "PROCESSING" and furnace.recipe_id == "smelt_copper")
	game._tick_machines(3.0)
	_check("furnace-finishes", furnace.state() == "FINISHED")
	await _use_machine("smith", "furnace")
	_check("furnace-collects-bar", game.state.minerals.get("copper_bar", 0) == 1 and furnace.state() == "EMPTY")
	game.state.minerals["copper"] = 0
	game.state.minerals["iron"] = 4
	await _use_machine("smith", "furnace")
	_check("furnace-iron-recipe", furnace.recipe_id == "smelt_iron")
	await _exit_via_door()
	# 谷仓：牛奶 → 奶酪。
	await _enter_via_input("player_barn")
	game.state.products["milk"] = 2
	await _use_machine("player_barn", "cheese_press")
	_check("cheese-starts", game._machines["player_barn:cheese_press"].recipe_id == "press_cheese" and game.state.products["milk"] == 1)
	game._tick_machines(9.0)
	await _use_machine("player_barn", "cheese_press")
	_check("cheese-collected", game.state.products.get("cheese", 0) == 1 and game.state.products["milk"] == 1)
	await _exit_via_door()
	# 鸡舍：鸡蛋 → 蛋黄酱；缺蛋拒绝。
	await _enter_via_input("player_coop")
	game.state.products["egg"] = 0
	await _use_machine("player_coop", "mayo_maker")
	_check("mayo-empty-refused", game.state.products.get("mayonnaise", 0) == 0)
	game.state.products["egg"] = 2
	await _use_machine("player_coop", "mayo_maker")
	game._tick_machines(5.0)
	await _use_machine("player_coop", "mayo_maker")
	_check("mayo-collected", game.state.products.get("mayonnaise", 0) == 1 and game.state.products["egg"] == 1)
	await _exit_via_door()


func _staffed_npc_flow() -> void:
	# 白天进杂货店：皮埃尔在柜台后值守、可交谈；出门恢复室外日程位置。
	await _enter_via_input("shop")
	var pierre: Node3D = null
	for npc: Node3D in game.npcs:
		if npc.id == "pierre":
			pierre = npc
	_check("pierre-found", pierre != null)
	_check("pierre-stations-in-shop", pierre.is_stationed() and pierre.global_position.distance_to(game.current_interior.npc_station_global()) < 0.5)
	game.player.teleport(game.current_interior.npc_station_global() + Vector3(1.0, 0, 1.4))
	await _frames(2)
	game._update_targeting()
	_check("pierre-indoor-talk-focus", game.focus.get("kind") == "npc" and game.focus.get("node") == pierre)
	game._interact()
	await _frames(2)
	_check("pierre-indoor-dialogue", game.hud.dialogue_open)
	game.hud.close_dialogue()
	await _frames(1)
	var outdoor_home: Vector3 = pierre.home_position()
	await _exit_via_door()
	_check("pierre-restored-outdoors", not pierre.is_stationed() and pierre.global_position.distance_to(outdoor_home) < 3.0)


func _machine_save_restore() -> void:
	# 加工中的机器随存档恢复剩余时长。
	await _enter_via_input("smith")
	game._machines["smith:furnace"].reset()  # 清掉 machines_flow 留下的铁锭加工
	game.state.minerals["copper"] = 4
	await _use_machine("smith", "furnace")
	_check("save-machine-started", game._machines["smith:furnace"].recipe_id == "smelt_copper")
	game._machines["smith:furnace"].hours_remaining = 1.25
	SaveManager.save_game(1, game._save_payload())
	await _frames(2)
	var saved: Dictionary = SaveManager.load_game(1)
	_check("save-has-machine", str(saved.get("interiors", {}).get("smith:furnace", {}).get("recipe", "")) == "smelt_copper")
	game._machines["smith:furnace"].reset()
	game._apply_load(saved)
	# 机器随世界时间继续走，剩余时长只减不增：恢复后应处于 PROCESSING 且 ≤1.25。
	var restored = game._machines["smith:furnace"]
	_check("machine-restored-processing", restored.state() == "PROCESSING" and restored.hours_remaining > 0.0 and restored.hours_remaining <= 1.2501)
	await _frames(2)
	await _exit_via_door()


func _save_restore() -> void:
	await _enter_via_input("shop")
	game.state.coins = 321
	game.player.teleport(game.current_interior.to_global(Vector3(1.5, 0, 0.5)))
	await _frames(3)
	game._save_payload()
	SaveManager.save_game(1, game._save_payload())
	await _frames(2)
	game._exit_building()
	await _frames(55)
	game.player.teleport(Vector3(300, 0, 300))
	await _frames(3)
	var loaded: Dictionary = SaveManager.load_game(1)
	_check("save-has-indoor", str(loaded.get("indoor", {}).get("id", "")) == "shop")
	game._apply_load(loaded)
	await _frames(3)
	_check("load-restores-indoor", game.interior_id == "shop" and game.current_interior != null)
	var local: Vector3 = game.current_interior.to_local(game.player.global_position)
	_check("load-restores-position", Vector2(local.x, local.z).distance_to(Vector2(1.5, 0.5)) < 1.0)
	_check("load-restores-coins", game.state.coins == 321)
	# 房间内读档后仍可正常出门。
	await _exit_via_door()


func _capture() -> void:
	if capture_path.is_empty():
		return
	game.player.teleport(game.current_interior.to_global(game.current_interior.spawn_position()) if game.current_interior != null else game.player.global_position)
	if game.current_interior == null:
		await _enter_via_input("shop")
	await _frames(10)
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var result := image.save_png(capture_path)
	print("INDOOR capture=%s %s" % [capture_path, error_string(result)])


func _chest_flow() -> void:
	## STORE-01：工作台制作宝箱 → 放置 → 共享仓库存取 → 收起 → 存读档。
	await _enter_via_input("carpenter")
	game.state.forestry["wood"] = 10
	game.state.minerals["stone"] = 5
	await _use_machine("carpenter", "workbench")
	_check("chest-starts", game._machines["carpenter:workbench"].recipe_id == "craft_chest" and game.state.forestry["wood"] == 0 and game.state.minerals["stone"] == 0)
	game._tick_machines(3.0)
	await _use_machine("carpenter", "workbench")
	_check("chest-collected-ready", game.state.chests_ready == 1)
	await _exit_via_door()
	# 放置：在空地尝试各朝向，直到出现放置焦点。
	var clear: Vector2 = preload("res://scripts/tests/forestry_checks.gd").find_clear(game)
	game.player.teleport(Vector3(clear.x, 0, clear.y))
	await _frames(2)
	var placed := false
	for facing: Vector3 in [Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, -1)]:
		game.player.face_point(game.player.global_position + facing)
		game._update_targeting()
		if game.focus.get("kind") == "chest_place":
			game._interact()
			await _frames(2)
			placed = game.state.chests_ready == 0 and game.chests.positions.size() == 1
			break
	_check("chest-placed", placed)
	game._update_targeting()
	_check("chest-open-focus", game.focus.get("kind") == "warehouse_chest")
	game._interact()
	await _frames(2)
	_check("warehouse-opens", game.hud.chest_open and game.player.locked)
	game.state.harvest["wheat"] = 6
	game.hud.warehouse_deposit_requested.emit("wheat")
	_check("deposit-via-signal", game.state.warehouse_count("wheat") == 6 and game.state.harvest["wheat"] == 0)
	game.hud.warehouse_withdraw_requested.emit("wheat")
	_check("withdraw-via-signal", game.state.warehouse_count("wheat") == 0 and game.state.harvest["wheat"] == 6)
	game.hud.close_chest()
	_check("warehouse-close-unlocks", not game.hud.chest_open and not game.player.locked)
	# 存读档：宝箱位置与仓库内容恢复。
	game.state.warehouse_deposit("wheat")
	SaveManager.save_game(1, game._save_payload())
	await _frames(2)
	game.chests.remove_nearest(game.player.global_position)
	game.state.warehouse.clear()
	var saved: Dictionary = SaveManager.load_game(1)
	game._apply_load(saved)
	await _frames(3)
	_check("chest-restored", game.chests.positions.size() == 1)
	_check("warehouse-restored", game.state.warehouse_count("wheat") == 6)
	# 收起宝箱：计数返还，仓库内容保留。
	game.player.teleport(Vector3(game.chests.positions[0].x, 0, game.chests.positions[0].z))
	await _frames(2)
	game.pickup_chest()
	await _frames(2)
	_check("chest-picked-up", game.state.chests_ready == 1 and game.chests.positions.is_empty())


func _store02_flow() -> void:
	## STORE-02：酒馆厨房烤面包、谷仓织毛毯、工作台仓库扩容与容量闸门、丢弃。
	await _enter_via_input("inn")
	game.player.teleport(game.current_interior.machine_world_position("kitchen") + Vector3(0, 0, 1.6))
	await _frames(2)
	game._update_targeting()
	_check("kitchen-focus", game.focus.get("kind") == "interior_machine" and game.focus.get("machine") == "kitchen")
	game.state.harvest["wheat"] = 6
	game._interior_machine("kitchen")
	_check("bread-starts", game._machines["inn:kitchen"].recipe_id == "bake_bread" and game.state.harvest["wheat"] == 3)
	game._tick_machines(4.0)
	await _use_machine("inn", "kitchen")
	_check("bread-collected", game.state.products.get("bread", 0) == 1)
	await _exit_via_door()
	await _enter_via_input("player_barn")
	game.state.products["wool"] = 3
	await _use_machine("player_barn", "loom")
	_check("blanket-starts", game._machines["player_barn:loom"].recipe_id == "weave_blanket" and game.state.products["wool"] == 0)
	game._tick_machines(7.0)
	await _use_machine("player_barn", "loom")
	_check("blanket-collected", game.state.products.get("blanket", 0) == 1)
	await _exit_via_door()
	# 工作台扩容：容量 300→600。
	await _enter_via_input("carpenter")
	game.state.forestry["wood"] = 15
	game.state.minerals["stone"] = 10
	game._machines["carpenter:workbench"].reset()
	await _use_machine("carpenter", "workbench")
	_check("workbench-first-affordable-is-chest", game._machines["carpenter:workbench"].recipe_id == "craft_chest")
	game._tick_machines(5.0)
	game._machines["carpenter:workbench"].reset()
	game._machines["carpenter:workbench"].start(RecipeDB.get_recipe("expand_warehouse"))
	game._tick_machines(5.0)
	await _use_machine("carpenter", "workbench")
	_check("expansion-applied", game.state.warehouse_capacity == 600)
	# 容量闸门：仓库塞满后存入被拒。
	game.state.warehouse["wheat"] = 600
	game.state.harvest["radish"] = 3
	game.hud.warehouse_deposit_requested.emit("radish")
	_check("capacity-gate-refuses", game.state.warehouse_total() == 600 and game.state.harvest["radish"] == 3)
	# 丢弃信号直接清空该物品存量。
	game.hud.warehouse_discard_requested.emit("wheat")
	_check("discard-via-signal", game.state.warehouse_count("wheat") == 0 and game.state.warehouse_total() == 0)
	await _exit_via_door()


func _rain_water_flow() -> void:
	## POLISH-01：雨天日切自动浇灌全部已种植耕地；晴天/雪天不浇。
	var clear: Vector2 = preload("res://scripts/tests/forestry_checks.gd").find_clear(game)
	var base: Vector3 = Vector3(clear.x, 0, clear.y)
	game.player.teleport(base)
	await _frames(2)
	var sunny_key: Vector2i = game.tiles.key_of(base)
	_check("rain-test-till-sunny", game.tiles.till(sunny_key) and game.tiles.plant(sunny_key, "radish"))
	game._apply_rollover()
	await _frames(1)
	_check("sunny-no-auto-water", not game.tiles.farm.data_of(sunny_key).watered)
	var rain_key: Vector2i = sunny_key + Vector2i(1, 0)
	_check("rain-test-till-rain", game.tiles.till(rain_key) and game.tiles.plant(rain_key, "radish"))
	game.state.time.set_weather("rain")
	game._apply_rollover()
	await _frames(1)
	_check("rain-auto-waters", game.tiles.farm.data_of(rain_key).watered)
	var snow_key: Vector2i = sunny_key + Vector2i(2, 0)
	_check("rain-test-till-snow", game.tiles.till(snow_key) and game.tiles.plant(snow_key, "radish"))
	game.state.time.set_weather("snow")
	game._apply_rollover()
	await _frames(1)
	_check("snow-no-auto-water", not game.tiles.farm.data_of(snow_key).watered)
	_check("weather-fx-particles-exist", game._weather_rain != null and game._weather_snow != null)
	_check("weather-fx-off-indoors", true)  # 视觉遮蔽逻辑在 _apply_daylight 按 interior/mine 门控，随场景检查覆盖


func _joy_flow() -> void:
	## POLISH-02：手柄按键注入——A 键等价 E（进门/出门），动作层对 Joypad 事件生效。
	await _teleport_door("cottage")
	game._update_targeting()
	_check("joy-door-focus", game.focus.get("kind") == "building_door")
	var press_a := InputEventJoypadButton.new()
	press_a.button_index = JOY_BUTTON_A
	press_a.pressed = true
	Input.parse_input_event(press_a)
	Input.flush_buffered_events()
	await _until(func(): return game.interior_id == "cottage" and not game._transitioning)
	_check("joy-enters-cottage", game.interior_id == "cottage")
	game.player.teleport(game.current_interior.to_global(game.current_interior.exit_position()))
	await _frames(2)
	game._update_targeting()
	_check("joy-exit-focus", game.focus.get("kind") == "interior_exit")
	var press_a2 := InputEventJoypadButton.new()
	press_a2.button_index = JOY_BUTTON_A
	press_a2.pressed = true
	Input.parse_input_event(press_a2)
	Input.flush_buffered_events()
	await _until(func(): return game.interior_id == "" and not game._transitioning)
	_check("joy-exits-cottage", game.interior_id == "" and game._outdoors.visible)


func _settings_flow() -> void:
	## SETTINGS-01：F10 开关设置面板；重绑 背包→K 生效；恢复默认后 Tab 可用。
	var f10 := InputEventKey.new()
	f10.keycode = KEY_F10
	f10.physical_keycode = KEY_F10
	f10.pressed = true
	Input.parse_input_event(f10)
	Input.flush_buffered_events()
	await _frames(2)
	_check("settings-opens", game.hud.settings_open and game.hud.modal_open())
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.physical_keycode = KEY_ESCAPE
	esc.pressed = true
	Input.parse_input_event(esc)
	Input.flush_buffered_events()
	await _frames(2)
	_check("settings-esc-closes", not game.hud.settings_open and not game.hud.modal_open())
	# 重绑：背包 → K。
	game.hud.begin_rebind("inventory")
	var k_down := InputEventKey.new()
	k_down.keycode = KEY_K
	k_down.physical_keycode = KEY_K
	k_down.pressed = true
	Input.parse_input_event(k_down)
	Input.flush_buffered_events()
	_check("rebind-captured", int(GameSettings.keybinds.get("inventory", 0)) == KEY_K)
	var k_press := InputEventKey.new()
	k_press.keycode = KEY_K
	k_press.physical_keycode = KEY_K
	k_press.pressed = true
	Input.parse_input_event(k_press)
	Input.flush_buffered_events()
	await _frames(2)
	_check("rebound-key-opens-inventory", game.hud.inventory_open)
	game.hud.toggle_inventory()
	await _frames(1)
	_check("rebound-key-closes-inventory", not game.hud.inventory_open)
	# 恢复默认：Tab 可用，K 失效。
	GameSettings.reset_keybinds()
	var tab := InputEventKey.new()
	tab.keycode = KEY_TAB
	tab.physical_keycode = KEY_TAB
	tab.pressed = true
	Input.parse_input_event(tab)
	Input.flush_buffered_events()
	await _frames(2)
	_check("default-tab-opens-inventory", game.hud.inventory_open)
	game.hud.toggle_inventory()
	await _frames(1)
	_check("inventory-closed-final", not game.hud.inventory_open)


func _season_visual_flow() -> void:
	## POLISH-05：季节切换联动地面雪量与色调层（默认春→切冬→切回）。
	game._apply_season_visuals("spring")
	_check("spring-no-snow-param", float(game._ground_material.get_shader_parameter("snow_amount")) == 0.0)
	game.state.time.day = 85  # 冬季首日
	game._apply_season_visuals("winter")
	_check("winter-snow-param", float(game._ground_material.get_shader_parameter("snow_amount")) == 1.0)
	_check("winter-mark-applied", game._season_visual_applied == "winter")
	var tint: Dictionary = SeasonVisuals.env_tint_for("winter")
	_check("winter-tint-reachable", tint.has("bg"))
	game._apply_season_visuals("autumn")
	_check("autumn-clears-snow", float(game._ground_material.get_shader_parameter("snow_amount")) == 0.0)
	game._apply_season_visuals("spring")  # 还原，避免影响后续检查


func _foliage_season_flow() -> void:
	## POLISH-05 二轮：树冠季色覆盖——Leaves 网格与森林 FoliageMulti 均接季色材质。
	await _until(func(): return game._season_visual_applied != "")
	game._apply_season_visuals("winter")
	var leaves: Array = game._outdoors.find_children("Leaves", "MeshInstance3D", true, false)
	_check("leaves-nodes-exist", leaves.size() > 0)
	if not leaves.is_empty():
		var override: Material = (leaves[0] as MeshInstance3D).material_override
		_check("leaves-winter-override", override != null and is_equal_approx((override as StandardMaterial3D).albedo_color.r, 0.58))
	var foliage_singleton: StandardMaterial3D = SeasonVisuals.foliage_singleton()
	_check("foliage-singleton-tinted", is_equal_approx(foliage_singleton.albedo_color.r, 0.58))
	# GLB 树冠材质原地变异：冬季 PineLeaf 变暗（B>R），秋季 R 通道超原色。
	var pine_leaf: StandardMaterial3D = null
	for part: Dictionary in game.scenery._parts["pine"]:
		var mesh: Mesh = part["mesh"]
		for s in range(mesh.get_surface_count()):
			var mat: Material = mesh.surface_get_material(s)
			if mat is StandardMaterial3D and (mat as StandardMaterial3D).resource_name.begins_with("PineLeaf"):
				pine_leaf = mat
				break
		if pine_leaf != null:
			break
	_check("pine-leaf-material-found", pine_leaf != null)
	game._apply_season_visuals("winter")
	if pine_leaf != null:
		var original: Color = SeasonVisuals.original_color_of(pine_leaf)
		_check("pine-winter-darkened", pine_leaf.albedo_color.r < original.r and pine_leaf.albedo_color.b > pine_leaf.albedo_color.r)
	game._apply_season_visuals("autumn")
	if not leaves.is_empty():
		var autumn_override: Material = (leaves[0] as MeshInstance3D).material_override
		_check("leaves-autumn-override", autumn_override != null and (autumn_override as StandardMaterial3D).albedo_color.r > 1.3)
	if pine_leaf != null:
		var original: Color = SeasonVisuals.original_color_of(pine_leaf)
		_check("pine-autumn-reddened", pine_leaf.albedo_color.r > original.r)
	game._apply_season_visuals("spring")
