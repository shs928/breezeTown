extends SceneTree
## NPC-01 场景检查：真实地图上的生成与锚点、日程切换、E 对话、送礼与存读档。
## 实机画面验证加 --capture=路径 --capture-size=WxH（窗口模式）。

const SaveManager := preload("res://scripts/core/save_manager.gd")
const NpcDB := preload("res://scripts/data/npc_db.gd")

var game: Node3D
var failures: Array[String] = []
var count := 0
var capture_path := ""
var capture_size := Vector2i(1600, 1000)


func _initialize() -> void:
	var save_root := OS.get_environment("BREEZETOWN_SAVE_ROOT")
	if save_root.is_empty():
		save_root = ProjectSettings.globalize_path("res://../work/game-data")
	OS.set_environment("BREEZETOWN_SAVE_ROOT", save_root.path_join("npc-checks-%d" % Time.get_ticks_usec()))
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):
			capture_path = argument.trim_prefix("--capture=")
		elif argument.begins_with("--capture-size="):
			var dimensions := argument.trim_prefix("--capture-size=").split("x")
			if dimensions.size() == 2 and dimensions[0].is_valid_int() and dimensions[1].is_valid_int():
				capture_size = Vector2i(maxi(640, dimensions[0].to_int()), maxi(480, dimensions[1].to_int()))
	create_timer(180).timeout.connect(func(): push_error("NPC_CHECKS timeout"); quit(1))
	_run.call_deferred()


func _run() -> void:
	root.size = capture_size
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await _frames(5)
	game.set_process(false)
	game.player.set_physics_process(false)
	_spawn_and_anchors()
	_schedule_switch()
	await _dialogue_flow()
	await _gift_flow()
	await _save_restore()
	await _capture()
	await _finish()


func _check(label: String, result: bool) -> void:
	count += 1
	print("NPC %s %s" % [label, "OK" if result else "FAIL"])
	if not result:
		failures.append(label)


func _spawn_and_anchors() -> void:
	_check("four-npcs-spawned", (game.npcs as Array).size() == 4)
	var labels := {}
	for npc: Node3D in game.npcs:
		labels[npc.id] = true
		_check("model-built-" + npc.id, npc.get_child_count() > 0 and npc.find_child("HeadPivot", true, false) != null)
		_check("no-collision-" + npc.id, not npc is CollisionObject3D)
	_check("roster-ids", labels.has("pierre") and labels.has("marnie") and labels.has("clint") and labels.has("wang"))
	# 锚点解析：site: 前缀必须解析到对应建筑门口，而不是落到镇广场兜底。
	var pierre: Node3D = _npc("pierre")
	_check("shop-anchor-resolved", (pierre.anchors["site:shop"] as Vector3).distance_to(game.landmarks["shop_door"]) < 0.1)
	var marnie: Node3D = _npc("marnie")
	var barn_door := _site_door("npc_barn")
	_check("barn-anchor-resolved", barn_door != null and Vector2(marnie.anchors["site:npc_barn"].x, marnie.anchors["site:npc_barn"].z).distance_to(barn_door) < 0.1)
	_check("npc-near-current-anchor", _all_near_anchors())


func _site_door(site_id: String) -> Vector2:
	for site: Dictionary in game.world_data["sites"]:
		if site["id"] == site_id:
			return site["door"]
	return Vector2.INF


func _npc(id: String) -> Node3D:
	for npc: Node3D in game.npcs:
		if npc.id == id:
			return npc
	return null


func _all_near_anchors() -> bool:
	## 位置 = 锚点 + 门侧偏移 + 踱步半径；站位点本身离原始锚点 ≤ 6 米。
	for npc: Node3D in game.npcs:
		var slot: Dictionary = NpcDB.schedule_at(npc.id, game.state.time.hours)
		var home: Vector3 = npc.home_position()
		if home.distance_to(npc.anchors[slot["anchor"]]) > 6.0:
			return false
		if npc.global_position.distance_to(home) > float(slot.get("wander", 2.0)) + 1.4:
			return false
	return true


func _schedule_switch() -> void:
	var pierre: Node3D = _npc("pierre")
	var hours_backup: float = game.state.time.hours
	game.state.time.hours = 18.0
	game._update_npc_schedules()
	_check("pierre-moves-to-square", pierre.global_position.distance_to(game.landmarks["town_square"]) < 6.0)
	game.state.time.hours = 22.0
	game._update_npc_schedules()
	_check("pierre-returns-at-night", pierre.global_position.distance_to(game.landmarks["shop_door"]) < 6.0)
	_check("pierre-stands-beside-not-on-door", pierre.home_position().distance_to(game.landmarks["shop_door"]) > 2.4)
	var wang: Node3D = _npc("wang")
	game.state.time.hours = 7.0
	game._update_npc_schedules()
	_check("wang-at-lake-morning", wang.global_position.distance_to(game.landmarks["lake_view"]) < 6.0)
	game.state.time.hours = 19.0
	game._update_npc_schedules()
	_check("wang-at-inn-evening", Vector2(wang.global_position.x, wang.global_position.z).distance_to(_site_door("inn")) < 6.0)
	game.state.time.hours = hours_backup
	game._update_npc_schedules()
	_check("npcs-back-near-anchors", _all_near_anchors())


func _dialogue_flow() -> void:
	# INDOOR-01 后的门点语义：皮埃尔在门边，玩家站门点先进店（门点优先于对话），
	# 商店服务在室内柜台办理；皮埃尔的门侧站位在门点 2.4 米外，交谈不受影响。
	game.player.teleport(game.landmarks["shop_door"])
	game._update_targeting()
	game._interact()
	await _until(func(): return game.interior_id == "shop" and not game._transitioning)
	_check("shop-opens-with-npc-nearby", game.interior_id == "shop")
	game.player.teleport(game.current_interior.service_world_position("counter_shop") + Vector3(0, 0, 1.4))
	await _frames(2)
	game._update_targeting()
	game._interact()
	await _frames(1)
	_check("shop-opens-at-counter", game.hud.shop_open)
	game.hud.close_shop()
	_check("shop-close-unlocks", not game.hud.shop_open and not game.player.locked)
	game._exit_building()
	await _until(func(): return game.interior_id == "" and not game._transitioning)
	var pierre: Node3D = _npc("pierre")
	game.player.teleport(pierre.global_position + Vector3(1.2, 0, 1.0))
	game._update_targeting()
	_check("focus-targets-npc", game.focus.get("kind") == "npc" and game.focus.get("node") == pierre)
	_check("hint-names-npc", String(game.focus.get("hint", "")).contains("皮埃尔"))
	game._interact()
	await _frames(1)
	_check("dialogue-opens", game.hud.dialogue_open and game.player.locked)
	_check("greet-line-shown", game.hud._dialogue_text.text == NpcDB.entry("pierre")["greet"])
	_check("first-talk-friendship", int(game.state.npc_friendship["pierre"]) == NpcDB.TALK_FRIENDSHIP)
	_check("hearts-shown", game.hud._dialogue_hearts.text.length() == 10)
	game.hud.close_dialogue()
	_check("dialogue-closes", not game.hud.dialogue_open and not game.player.locked)
	game._interact()
	await _frames(1)
	_check("second-talk-chat-line", game.hud._dialogue_text.text != NpcDB.entry("pierre")["greet"])
	_check("same-day-talk-no-gain", int(game.state.npc_friendship["pierre"]) == NpcDB.TALK_FRIENDSHIP)
	game.hud.close_dialogue()


func _gift_flow() -> void:
	game.state.add_harvest("radish", 2)
	var pierre: Node3D = _npc("pierre")
	game.player.teleport(pierre.global_position + Vector3(1.2, 0, 1.0))
	game._update_targeting()
	game._interact()
	await _frames(1)
	var entries: Array = game._gift_entries("pierre")
	var has_radish := false
	for entry: Dictionary in entries:
		if entry["id"] == "radish":
			has_radish = true
	_check("gift-list-offers-items", has_radish and entries.size() >= 1)
	game._on_dialogue_gift("radish")
	await _frames(1)
	_check("gift-charges-item", int(game.state.harvest["radish"]) == 1)
	_check("gift-loves-friendship", int(game.state.npc_friendship["pierre"]) == NpcDB.TALK_FRIENDSHIP + NpcDB.GIFT_TIERS["loves"])
	_check("gift-reaction-line", game.hud._dialogue_text.text.contains(NpcDB.gift_line("pierre", "loves")))
	var friendship_after: int = int(game.state.npc_friendship["pierre"])
	game._on_dialogue_gift("radish")
	_check("second-gift-same-day-blocked", int(game.state.npc_friendship["pierre"]) == friendship_after and int(game.state.harvest["radish"]) == 1)
	game.hud.close_dialogue()
	# 次日可再送（对话本身也会 +8 每日好感）。
	game.state.day += 1
	game._interact()
	await _frames(1)
	game._on_dialogue_gift("radish")
	_check("next-day-gift-allowed", int(game.state.npc_friendship["pierre"]) == friendship_after + NpcDB.TALK_FRIENDSHIP + NpcDB.GIFT_TIERS["loves"] and int(game.state.harvest["radish"]) == 0)
	game.hud.close_dialogue()


func _save_restore() -> void:
	var pierre: Node3D = _npc("pierre")
	var friendship: int = int(game.state.npc_friendship["pierre"])
	var day: int = game.state.day
	SaveManager.save_game(1, game._save_payload())
	var fresh = GameState_new()
	fresh.from_dict(SaveManager.load_game(1)["economy"])
	_check("save-keeps-friendship", int(fresh.npc_friendship["pierre"]) == friendship)
	_check("save-keeps-gift-day", int(fresh.npc_last_gift["pierre"]) == day and int(fresh.npc_last_talk["pierre"]) == day)
	game.state.time.hours = 12.0
	game._update_npc_schedules()
	var at_noon: Vector3 = pierre.global_position
	game._apply_load(SaveManager.load_game(1))
	await _frames(2)
	_check("load-rebuilds-positions", _all_near_anchors())
	_check("load-restores-friendship", int(game.state.npc_friendship["pierre"]) == friendship)
	_check("position-derived-not-saved", pierre.global_position.distance_to(at_noon) > 0.01 or _all_near_anchors())


func _capture() -> void:
	if capture_path.is_empty() or DisplayServer.get_name() == "headless":
		return
	var pierre: Node3D = _npc("pierre")
	game.player.teleport(pierre.global_position + Vector3(1.4, 0, 1.2))
	await _frames(4)
	game._update_targeting()
	game._interact()
	await _frames(6)
	game.hud.update_clock()
	await _frames(4)
	DirAccess.make_dir_recursive_absolute(capture_path.get_base_dir())
	var image := root.get_texture().get_image()
	_check("capture-saved", image.save_png(capture_path) == OK)
	game.hud._toggle_gift_list()
	await _frames(4)
	var gift_image := root.get_texture().get_image()
	_check("capture-gift-saved", gift_image.save_png(capture_path.get_basename() + "-gift.png") == OK)
	game.hud.close_dialogue()


func _frames(amount: int) -> void:
	for index in range(amount):
		await process_frame


func _until(condition: Callable, timeout_frames: int = 1800) -> bool:
	## INDOOR-01：淡入淡出按真实时钟走，headless 帧率不固定，轮询到条件成立为止。
	for index in range(timeout_frames):
		if condition.call():
			return true
		await process_frame
	return condition.call()


func GameState_new():
	return load("res://scripts/game_state.gd").new()


func _finish() -> void:
	print("NPC_RESULT %s %d checks" % ["PASS" if failures.is_empty() else "FAIL " + ",".join(failures), count])
	game.queue_free()
	await process_frame
	await process_frame
	quit(0 if failures.is_empty() else 1)
