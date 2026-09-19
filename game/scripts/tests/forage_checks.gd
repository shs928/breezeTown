extends SceneTree
## GATHER-01 采集系统场景检查：真实大地图上的生成、落点规则、采集流程、日切/换季与存读档。
## 实机画面验证加 --capture=路径 --capture-size=WxH（窗口模式）。

const SaveManager := preload("res://scripts/core/save_manager.gd")
const ForageDB := preload("res://scripts/data/forage_db.gd")

var game: Node3D
var failures: Array[String] = []
var count := 0
var capture_path := ""
var capture_size := Vector2i(1600, 1000)


func _initialize() -> void:
	var save_root := OS.get_environment("BREEZETOWN_SAVE_ROOT")
	if save_root.is_empty():
		save_root = ProjectSettings.globalize_path("res://../work/game-data")
	OS.set_environment("BREEZETOWN_SAVE_ROOT", save_root.path_join("forage-checks-%d" % Time.get_ticks_usec()))
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):
			capture_path = argument.trim_prefix("--capture=")
		elif argument.begins_with("--capture-size="):
			var dimensions := argument.trim_prefix("--capture-size=").split("x")
			if dimensions.size() == 2 and dimensions[0].is_valid_int() and dimensions[1].is_valid_int():
				capture_size = Vector2i(maxi(640, dimensions[0].to_int()), maxi(480, dimensions[1].to_int()))
	create_timer(180).timeout.connect(func(): push_error("FORAGE_CHECKS timeout"); quit(1))
	_run.call_deferred()


func _run() -> void:
	root.size = capture_size
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await _frames(5)
	game.set_process(false)
	game.player.set_physics_process(false)
	_spawn_health()
	_placement_rules()
	_deterministic_refresh()
	await _gather_flow()
	await _save_restore()
	_season_cleanup()
	await _capture()
	await _finish()


func _check(label: String, result: bool) -> void:
	count += 1
	print("FORAGE %s %s" % [label, "OK" if result else "FAIL"])
	if not result:
		failures.append(label)


func _spawn_health() -> void:
	_check("forage-manager-present", game.forage != null)
	_check("first-day-forage-populated", game.forage.count() >= 5)
	_check("manager-count-matches-nodes", game.forage.count() == (game.forage.nodes as Array).size())
	var kinds := {}
	for node: Node3D in game.forage.nodes:
		kinds[node.kind] = true
	_check("kinds-legal", kinds.keys().filter(func(kind): return kind not in ForageDB.ORDER).is_empty())
	_check("visual-built", game.forage.nodes[0].get_child_count() > 0)


func _placement_rules() -> void:
	var map = game.tiles.map
	var npc_rect: Rect2 = Rect2()
	for entry: Dictionary in game.world_data["definition"]["regions"]:
		if entry["id"] == "npc_farm":
			npc_rect = entry["rect"]
	var positions: Array[Vector2] = []
	for node: Node3D in game.forage.nodes:
		var at := Vector2(node.position.x, node.position.z)
		positions.append(at)
		_check("on-land-" + node.kind, not map.is_water(at, 0.3) and not map.on_deck(at, 0.3))
		_check("walkable-spot-" + node.kind, map.is_walkable(at, 0.4))
		_check("not-on-farm-tile-" + node.kind, not game.tiles.farm.tiles.has(map.key_of(Vector3(at.x, 0, at.y))))
		_check("away-from-npc-farm-" + node.kind, not (npc_rect.size != Vector2.ZERO and npc_rect.grow(2.0).has_point(at)))
		var in_pasture := false
		for rect: Rect2 in map.pastures:
			if rect.grow(0.9).has_point(at):
				in_pasture = true
		_check("away-from-pastures-" + node.kind, not in_pasture)
		var anchored := false
		for habitat in ForageDB.FORAGE[node.kind]["habitats"]:
			if _point_in_areas(at, game.forage._habitat_areas(habitat)):
				anchored = true
		_check("inside-habitat-" + node.kind, anchored)
	var crowded := 0
	for i in range(positions.size()):
		for j in range(i + 1, positions.size()):
			if positions[i].distance_to(positions[j]) < 2.5:
				crowded += 1
	_check("spawn-spacing-respected", crowded == 0)


func _deterministic_refresh() -> void:
	var run_a := _refresh_run(2)
	var run_b := _refresh_run(2)
	_check("daily-spawn-deterministic", run_a["spawned"] == run_b["spawned"] and run_a["kinds"] == run_b["kinds"] and run_a["spots"] == run_b["spots"])
	_check("daily-spawn-plants", int(run_a["spawned"]) >= 4)
	_check("daily-spawn-same-season-no-removal", int(run_a["removed"]) == 0)


func _refresh_run(day: int) -> Dictionary:
	game.forage.apply_state({"season": "spring", "nodes": []}, "spring")
	var result: Dictionary = game.forage.on_day_rollover(day, "spring", "sunny")
	var kinds := {}
	var spots: Array = []
	for node: Node3D in game.forage.nodes:
		kinds[node.kind] = true
		spots.append([node.kind, snappedf(node.position.x, 0.01), snappedf(node.position.z, 0.01)])
	spots.sort()
	return {"removed": result["removed"], "spawned": result["spawned"], "kinds": kinds, "spots": spots}


func _gather_flow() -> void:
	var node: Node3D = game.forage.nodes[0]
	var kind: String = node.kind
	var stocked: int = game.state.forage[kind]
	var xp_before: int = game.state.xp
	var nodes_before: int = game.forage.count()
	game.player.teleport(node.global_position + Vector3(0, 0, 2.0))
	game._update_targeting()
	_check("focus-targets-forage", game.focus.get("kind") == "forage" and game.focus.get("node") == node)
	_check("hint-names-forage", String(game.focus.get("hint", "")).contains(ForageDB.label(kind)))
	_check("hint-shows-price", String(game.focus.get("hint", "")).contains(str(ForageDB.sell_price(kind))))
	game._interact()
	await _frames(1)
	_check("gather-adds-to-inventory", game.state.forage[kind] == stocked + 1)
	_check("gather-removes-node", game.forage.count() == nodes_before - 1)
	_check("gather-grants-xp", game.state.xp == xp_before + 5)
	_check("gathered-node-freed", not is_instance_valid(node))
	# 原地再按 E：该物种不会再凭空增加（目标已消失）。
	game._update_targeting()
	if game.focus.get("kind") == "forage":
		game._interact()
	_check("no-double-gather", game.state.forage[kind] == stocked + 1)


func _save_restore() -> void:
	var payload: Dictionary = game._save_payload()
	_check("payload-has-forage-key", payload.has("forage") and (payload["forage"]["nodes"] as Array).size() == game.forage.count())
	_check("payload-season-matches-clock", String(payload["forage"]["season"]) == game.state.time.season_key())
	var victim: Node3D = game.forage.nodes[0]
	var victim_kind: String = victim.kind
	var victim_at := Vector2(victim.position.x, victim.position.z)
	var nodes_before: int = game.forage.count()
	var expected_stock: int = int(payload["economy"]["forage"][victim_kind])
	SaveManager.save_game(1, payload)
	game.forage.gather(victim)
	_check("gather-before-load-removes-node", game.forage.count() == nodes_before - 1)
	game._apply_load(SaveManager.load_game(1))
	await _frames(2)
	_check("load-restores-node-count", game.forage.count() == nodes_before)
	var restored := false
	for node: Node3D in game.forage.nodes:
		if node.kind == victim_kind and Vector2(node.position.x, node.position.z).distance_to(victim_at) < 0.1:
			restored = true
	_check("load-restores-same-spot", restored)
	_check("load-restores-inventory", game.state.forage[victim_kind] == expected_stock)


func _season_cleanup() -> void:
	game.forage.apply_state({"season": "spring", "nodes": []}, "spring")
	var spot: Vector2 = game.forage._find_spot("forest", game.forage.rng)
	_check("test-spot-found", spot.is_finite())
	if not spot.is_finite():
		return
	game.forage._spawn_entry("sweet_pea", spot)
	_check("offseason-plant-placed", game.forage.count() >= 1)
	var result: Dictionary = game.forage.on_day_rollover(300, "winter", "snow")
	_check("season-change-removes-summer", int(result["removed"]) >= 1)
	_check("winter-spawn-happens", int(result["spawned"]) >= 1)
	var kinds := {}
	for node: Node3D in game.forage.nodes:
		kinds[node.kind] = true
	_check("offseason-species-gone", not kinds.has("sweet_pea"))
	var all_winter := true
	for kind in kinds:
		if "winter" not in ForageDB.FORAGE[kind]["seasons"]:
			all_winter = false
	_check("remaining-species-in-season", all_winter)


func _capture() -> void:
	if capture_path.is_empty() or DisplayServer.get_name() == "headless":
		return
	if game.forage.count() == 0:
		_check("capture-requires-forage", false)
		return
	var node: Node3D = game.forage.nodes[0]
	game.player.teleport(node.global_position + Vector3(0, 0, 2.2))
	await _frames(6)
	game._update_targeting()
	game.hud.update_clock()
	await _frames(4)
	DirAccess.make_dir_recursive_absolute(capture_path.get_base_dir())
	var image := root.get_texture().get_image()
	_check("capture-saved", image.save_png(capture_path) == OK)
	game.hud.toggle_inventory()
	game.hud.refresh()
	await _frames(4)
	var inventory := root.get_texture().get_image()
	_check("capture-inventory-saved", inventory.save_png(capture_path.get_basename() + "-inventory.png") == OK)
	game.hud.toggle_inventory()


func _point_in_areas(at: Vector2, areas: Array) -> bool:
	for area: Dictionary in areas:
		if area.has("rect"):
			if (area["rect"] as Rect2).has_point(at):
				return true
		elif at.distance_to(area["center"]) <= float(area["radius"]):
			return true
	return false


func _frames(amount: int) -> void:
	for index in range(amount):
		await process_frame


func _finish() -> void:
	print("FORAGE_RESULT %s %d checks" % ["PASS" if failures.is_empty() else "FAIL " + ",".join(failures), count])
	game.queue_free()
	await process_frame
	await process_frame
	quit(0 if failures.is_empty() else 1)
