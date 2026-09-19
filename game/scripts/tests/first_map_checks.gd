extends SceneTree
## Calibrated geography, physical crossings and an on-disk save/load across maps.
const Definition := preload("res://scripts/data/first_map_definition.gd")
const SurfaceChecks := preload("res://scripts/tests/surface_world_checks.gd")
const SaveManager := preload("res://scripts/core/save_manager.gd")
const Restore := preload("res://scripts/core/map_restore.gd")
var failures: Array[String] = []
var count := 0
var game: Node3D


func _initialize() -> void:
	create_timer(240).timeout.connect(func(): push_error("FIRST_MAP timeout"); quit(1))
	_run.call_deferred()


func _run() -> void:
	var layout := Definition.create()
	_check("400m-calibration", absf(Definition.point([1270, 1166]).distance_to(Definition.point([1068, 1166])) - 400) < .001)
	_check("full-world-extent", layout["bounds"]["half"].is_equal_approx(Vector2(1299.0099, 1187.1287)))
	_check("player-in-southwest-farm", layout["farm"].get_center().x < 0 and layout["farm"].get_center().y > 0)
	_check("npc-in-northeast-farm", layout["ranch"].get_center().x > 0 and layout["ranch"].get_center().y < 0)
	_check("farm-ownership-keeps-spawn", layout["farm"].has_point(Vector2(layout["landmarks"]["spawn"].x, layout["landmarks"]["spawn"].z)))
	var symbol_size_ok := true
	for building: Dictionary in layout["buildings"]:
		symbol_size_ok = symbol_size_ok and building["size"].x <= 35 and building["size"].y <= 35
	_check("buildings-have-physical-not-symbol-size", symbol_size_ok)
	_check("traced-bridges-and-harbor", layout["bridges"].size() == 4 and layout["docks"].size() == 7)
	root.size = Vector2i(1600, 1000)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await _frames(5)
	_check("default-starts-scaled-map", game.world_data["definition"]["id"] == layout["id"])
	_check("sea-cannot-be-walked-or-tilled", not game.tiles.map.is_walkable(Vector2(0, 1100)) and not game.tiles.is_open(Vector2i(0, 550)))
	_check("player-farm-has-crops", game.tiles.farm.tiles.size() >= 40)
	var npc_ground := Definition.point([840, 150])
	_check("npc-farm-still-walkable", game.tiles.map.is_walkable(npc_ground))
	_check("npc-farm-not-player-tillable", not game.tiles.is_open(Vector2i((npc_ground / 2).round())))
	_check("npc-farm-rejects-player-enclosure", not game._can_place_pasture(Rect2(npc_ground, Vector2(8, 8))))
	# MAP-01：三条主干路线连续可达（农场→镇区→矿口、镇区→NPC 农庄、镇区→港口）。
	# 途经点大致沿道路，跨河只经桥；每跳 ≤250m 以保持寻路分辨率。
	var farm_gate := Vector2(layout["landmarks"]["spawn"].x, layout["landmarks"]["spawn"].z)
	var square := (layout["square"] as Rect2).get_center()
	var mine := Vector2(layout["landmarks"]["mine_door"].x, layout["landmarks"]["mine_door"].z)
	var npc_home := Vector2.ZERO
	var harbor := Vector2.ZERO
	for building: Dictionary in layout["buildings"]:
		if building["id"] == "npc_farmhouse": npc_home = building["door"]
		if building["id"] == "harbor_house": harbor = building["door"]
	var north_bridge := Vector2(-276.0, -600.0)
	var npc_bridge := Vector2(499.0, -520.0)
	var harbor_bridge := Vector2(100.0, 595.0)
	var routes := {
		"farm-to-town": [farm_gate, Vector2(-350, 60), Vector2(-100, -90), Vector2(square.x, square.y + 76.0)],
		"town-to-mine": [Vector2(square.x, square.y + 12.0), Vector2(-150, -380), north_bridge, Vector2(-450, -650), Vector2(-650, -740), mine],
		"town-to-npc-farm": [Vector2(square.x, square.y + 12.0), Vector2(250, -350), Vector2(420, -470), npc_bridge, Vector2(480, -650), npc_home],
		"town-to-harbor": [Vector2(square.x, square.y + 12.0), Vector2(0, 100), Vector2(80, 450), harbor_bridge, Vector2(0, 640), harbor],
	}
	for key: String in routes:
		var waypoints: Array = routes[key]
		var connected := true
		for i in range(waypoints.size() - 1):
			var a: Vector2 = waypoints[i]
			var b: Vector2 = waypoints[i + 1]
			if game.navigation.find_path(Vector3(a.x, 0, a.y), Vector3(b.x, 0, b.y)).is_empty():
				connected = false
				push_error("FIRST_MAP route %s broken between (%.0f,%.0f) and (%.0f,%.0f)" % [key, a.x, a.y, b.x, b.y])
		_check("route-" + key, connected)
	var active_slot := SaveManager.slot_dir(1)
	SaveManager.select_world("breeze_valley")
	var legacy_slot := SaveManager.slot_dir(1)
	SaveManager.select_world(layout["id"])
	_check("map-save-slots-are-isolated", legacy_slot != active_slot and SaveManager.slot_dir(1) == active_slot)
	var unrelated: Dictionary = game._save_payload()
	unrelated["ok"] = true
	unrelated["map"]["id"] = "breeze_valley"
	var before: Dictionary = game._save_payload()
	var rejected: Dictionary = Restore.plan(unrelated, game.world_data)
	_check("foreign-map-save-rejected", not rejected.get("ok", true))
	game._apply_load(unrelated)
	_check("foreign-map-load-preserves-live-state", game._save_payload() == before)
	unrelated.erase("map")
	unrelated["pastures"].erase("map_id")
	_check("unidentified-legacy-save-rejected", not Restore.plan(unrelated, game.world_data).get("ok", true))
	game.player.teleport(game.landmarks["shop_door"] + Vector3(0, 0, .6))
	await _frames(3)
	_press(KEY_E)
	await _frames(55)
	_check("town-shop-interactive", game.interior_id == "shop" and game.current_interior != null)
	game.player.teleport(game.current_interior.service_world_position("counter_shop") + Vector3(0, 0, 1.4))
	await _frames(3)
	_press(KEY_E)
	await _frames(2)
	_check("town-shop-counter-opens-shop", game.hud.shop_open)
	_press(KEY_ESCAPE)
	await _frames(2)
	game._exit_building()
	await _frames(55)
	_check("town-shop-exit-outdoors", game.interior_id == "" and game._outdoors.visible)
	game.player.teleport(game.landmarks["cottage_door"] + Vector3(0, 0, .6))
	await _frames(3)
	game._update_targeting()
	_check("southwest-home-interactive", game.focus.get("kind") == "building_door")
	await SurfaceChecks.run(game, _check)
	_check("navigation-grid-is-bounded", game.navigation._grid.region.size.x <= 194 and game.navigation._grid.region.size.y <= 194)
	await _bridge_input(layout["bridges"][0])
	await _bridge_input(layout["bridges"][3])
	await _bank_input()
	await _save_roundtrip()
	await _world_cache_checks(layout)
	game.player.teleport(Vector3(500, 0, -800))
	await _frames(35)
	_check("forest-chunks-bounded", game._outdoors.get_node("StreamedScenery")._chunks.size() <= 9)
	print("FIRST_MAP_RESULT %s %d checks" % ["PASS" if failures.is_empty() else "FAIL " + ",".join(failures), count])
	quit(0 if failures.is_empty() else 1)


func _world_cache_checks(layout: Dictionary) -> void:
	# PERF-02：世界缓存——写盘齐全、指纹与源一致、篡改即失效、重建恢复、再次命中。
	var Builder = preload("res://scripts/first_map_builder.gd")
	var cache: String = Builder._cache_root()
	_check("cache-files-written", FileAccess.file_exists(cache + "/fingerprint.txt") and FileAccess.file_exists(cache + "/world.scn") and FileAccess.file_exists(cache + "/data.var"))
	var fingerprint: String = Builder._fingerprint()
	var stored: String = FileAccess.open(cache + "/fingerprint.txt", FileAccess.READ).get_as_text().strip_edges()
	_check("cache-fingerprint-matches-sources", stored == fingerprint)
	FileAccess.open(cache + "/fingerprint.txt", FileAccess.WRITE).store_string("tampered")
	_check("cache-misses-on-fingerprint-change", Builder._load_cache(fingerprint).is_empty())
	var rebuilt: Dictionary = Builder.build()
	_check("cache-rebuild-restores-world", rebuilt["sites"].size() == layout["buildings"].size() and rebuilt["definition"]["id"] == layout["id"])
	_check("cache-restored-on-disk", FileAccess.open(cache + "/fingerprint.txt", FileAccess.READ).get_as_text().strip_edges() == fingerprint)
	var hit: Dictionary = Builder.build()
	_check("cache-hit-returns-equivalent-world", not hit.is_empty() and hit["root"].get_child_count() == rebuilt["root"].get_child_count() and hit["sites"].size() == layout["buildings"].size())


func _bridge_input(bridge: Dictionary) -> void:
	var rect: Rect2 = bridge["rect"]
	var along_x: bool = bridge["axis"] == "x"
	var center := rect.get_center()
	var axis := Vector2.RIGHT if along_x else Vector2.DOWN
	var length := rect.size.x if along_x else rect.size.y
	var approach := center - axis * (length * .5 + 1)
	var exit := center + axis * (length * .5 + .6)
	# Camera-relative paired keys move almost along a world axis. Center the
	# small lateral drift so the test stays within the depicted deck width.
	var drift := length / 9.0
	approach += Vector2(0, -drift * .5) if along_x else Vector2(drift * .5, 0)
	game.player.teleport(Vector3(approach.x, 0, approach.y))
	await _frames(4)
	_key(KEY_SHIFT, true)
	_key(KEY_S, true)
	_key(KEY_D if along_x else KEY_A, true)
	var highest := 0.0
	var limit := ceili((length + 6) / game.player.RUN_SPEED * 60)
	for frame in range(limit):
		await physics_frame
		highest = maxf(highest, game.player.position.y)
		var here: float = game.player.position.x if along_x else game.player.position.z
		if here >= (exit.x if along_x else exit.y):
			break
	_key(KEY_S, false)
	_key(KEY_D if along_x else KEY_A, false)
	_key(KEY_SHIFT, false)
	await _frames(3)
	var finish: float = game.player.position.x if along_x else game.player.position.z
	_check("normal-input-crosses-" + bridge["id"], finish >= (exit.x if along_x else exit.y))
	_check("normal-input-follows-height-" + bridge["id"], highest > (1.7 if bridge.get("stone", false) else .12) and game.player.position.y < .2)


func _bank_input() -> void:
	# The open north bank of the farm pond is deliberately away from any bridge.
	var lake: Dictionary = game.world_data["definition"]["waters"].filter(func(water: Dictionary): return water["id"] == "farm_pond")[0]
	var polygon: PackedVector2Array = lake["polygon"]
	var bank := polygon[0]
	for point in polygon:
		if point.y < bank.y:
			bank = point
	game.player.teleport(Vector3(bank.x, 0, bank.y - 1.5))
	await _frames(4)
	_key(KEY_S, true)
	_key(KEY_A, true)
	await _frames(85)
	_key(KEY_S, false)
	_key(KEY_A, false)
	await _frames(3)
	var actual := Vector2(game.player.position.x, game.player.position.z)
	_check("normal-input-stops-at-water-bank", not game.tiles.map.is_water(actual, .20) and actual.y < bank.y + 1.0)


func _save_roundtrip() -> void:
	game.player.teleport(game.landmarks["cottage_door"] + Vector3(0, 0, .6))
	await _frames(4)
	game.state.coins = 137
	game.state.forestry["wood"] = 17
	var key: Vector2i = game.tiles.farm.tiles.keys()[0]
	game.tiles.farm.tiles[key]["watered"] = true
	var farm: Dictionary = game.tiles.farm.to_dict()
	var pastures: int = game.pastures.size()
	var saved_at: Vector3 = game.player.position
	_press(KEY_F5)
	await _frames(3)
	var saved := SaveManager.load_game(1)
	_check("save-writes-calibrated-map-identity", saved.get("ok", false) and saved.get("map", {}).get("id") == Definition.create()["id"])
	game.player.teleport(game.landmarks["mine_door"] + Vector3(0, 0, .6))
	await _frames(4)
	_press(KEY_E)
	await _frames(55)
	_check("normal-mine-entry-from-new-landmark", game.mine_depth == 1 and not game._transitioning)
	game.state.coins = 3
	game.state.forestry["wood"] = 0
	game.tiles.farm.from_dict({"tiles": []})
	_press(KEY_F9)
	await _frames(5)
	_check("load-from-mine-restores-surface-controls", game.mine_depth == 0 and game._outdoors.visible and not game.player.locked)
	_check("load-restores-economy-and-inventory", game.state.coins == 137 and game.state.forestry["wood"] == 17)
	_check("load-restores-crop-growth-and-water", game.tiles.farm.to_dict() == farm)
	_check("load-restores-fences-without-duplicates", game.pastures.size() == pastures)
	_check("load-restores-calibrated-player-position", game.player.position.distance_to(saved_at) < .1)
	_press(KEY_F9)
	await _frames(4)
	_check("repeated-load-is-idempotent", game.tiles.farm.to_dict() == farm and game.pastures.size() == pastures)


func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _press(code: Key) -> void:
	_key(code, true)
	_key(code, false)


func _frames(frames: int) -> void:
	for frame in range(frames):
		await physics_frame
	await process_frame


func _check(label: String, result: bool) -> void:
	count += 1
	print("FIRST_MAP ", label, " ", "OK" if result else "FAIL")
	if not result:
		failures.append(label)
