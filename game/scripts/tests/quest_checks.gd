extends SceneTree
## QUEST-01 场景检查：真实地图上的对话委托入口、接受/进度/交付、传话自动完成与存读档。
## 实机画面验证加 --capture=路径 --capture-size=WxH（窗口模式）。

const SaveManager := preload("res://scripts/core/save_manager.gd")
const QuestDB := preload("res://scripts/data/quest_db.gd")
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
	OS.set_environment("BREEZETOWN_SAVE_ROOT", save_root.path_join("quest-checks-%d" % Time.get_ticks_usec()))
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):
			capture_path = argument.trim_prefix("--capture=")
		elif argument.begins_with("--capture-size="):
			var dimensions := argument.trim_prefix("--capture-size=").split("x")
			if dimensions.size() == 2 and dimensions[0].is_valid_int() and dimensions[1].is_valid_int():
				capture_size = Vector2i(maxi(640, dimensions[0].to_int()), maxi(480, dimensions[1].to_int()))
	create_timer(180).timeout.connect(func(): push_error("QUEST_CHECKS timeout"); quit(1))
	_run.call_deferred()


func _run() -> void:
	root.size = capture_size
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await _frames(5)
	game.set_process(false)
	game.player.set_physics_process(false)
	await _collect_quest_flow()
	await _visit_quest_flow()
	await _save_restore()
	await _capture()
	await _finish()


func _check(label: String, result: bool) -> void:
	count += 1
	print("QUEST %s %s" % [label, "OK" if result else "FAIL"])
	if not result:
		failures.append(label)


func _npc(id: String) -> Node3D:
	for npc: Node3D in game.npcs:
		if npc.id == id:
			return npc
	return null


func _talk_to(id: String) -> void:
	var npc: Node3D = _npc(id)
	game.player.teleport(npc.global_position + Vector3(1.0, 0, 0.9))
	game._update_targeting()
	_check("focus-npc-" + id, game.focus.get("kind") == "npc" and game.focus.get("node") == npc)
	game._interact()
	await _frames(1)


func _collect_quest_flow() -> void:
	await _talk_to("pierre")
	_check("offer-button-shown", game.hud._dialogue_quest_button.visible and game.hud._dialogue_quest_mode == "accept")
	_check("offer-is-first-quest", game.hud._dialogue_quest_id == "pierre_veggies")
	_check("dialogue-locks-player", game.player.locked)
	# 进度不足时交付按钮不可用。
	game._on_quest_accept("pierre_veggies")
	_check("accept-records", int(game.state.quests_accepted.get("pierre_veggies", 0)) == game.state.day)
	_check("brief-shown", game.hud._dialogue_text.text == String(QuestDB.entry("pierre_veggies")["brief"]))
	_check("turnin-shown-not-ready", game.hud._dialogue_quest_mode == "turnin" and game.hud._dialogue_quest_button.disabled)
	_check("turnin-progress-text", game.hud._dialogue_quest_button.text.contains("0/5"))
	game.hud.close_dialogue()
	_check("tracker-visible-after-accept", game.hud._quest_tracker.visible and game.hud._quest_tracker_label.text.contains("皮埃尔的进货"))
	# 凑齐货物：item_added 事件触发可交付 toast。
	game.state.add_harvest("radish", 5)
	await _frames(1)
	_check("turnable-after-collect", game.state.quest_turnable("pierre_veggies"))
	_check("tracker-shows-progress", game.hud._quest_tracker_label.text.contains("5/5"))
	_check("collect-toast-shown", game.hud._toast.text.contains("可交付"))
	# 交付：扣货、发奖、答谢、解锁下一位委托。
	var coins_before: int = game.state.coins
	var friendship_before: int = int(game.state.npc_friendship["pierre"])
	await _talk_to("pierre")
	_check("turnin-ready-on-reopen", game.hud._dialogue_quest_mode == "turnin" and not game.hud._dialogue_quest_button.disabled)
	game._on_quest_turnin("pierre_veggies")
	_check("turnin-pays", game.state.coins == coins_before + 60 and int(game.state.npc_friendship["pierre"]) == friendship_before + 40)
	_check("turnin-consumes", int(game.state.harvest["radish"]) == 0)
	_check("thanks-shown", game.hud._dialogue_text.text == String(QuestDB.entry("pierre_veggies")["thanks"]))
	_check("completed-recorded", int(game.state.quests_completed.get("pierre_veggies", 0)) == game.state.day)
	_check("chain-unlocked-in-dialogue", game.hud._dialogue_quest_mode == "accept" and game.hud._dialogue_quest_id == "pierre_fish")
	game.hud.close_dialogue()
	_check("tracker-hidden-after-chain-end", not game.hud._quest_tracker.visible)
	# 错误防护：对非 giver 交付无效。
	game.state.accept_quest("marnie_eggs", game.state.day)
	var marnie_friendship: int = int(game.state.npc_friendship["marnie"])
	game._on_quest_turnin("marnie_eggs")
	_check("cross-giver-turnin-rejected", int(game.state.npc_friendship["marnie"]) == marnie_friendship and game.state.quest_active("marnie_eggs"))


func _visit_quest_flow() -> void:
	await _talk_to("wang")
	_check("wang-offers-message", game.hud._dialogue_quest_mode == "accept" and game.hud._dialogue_quest_id == "wang_message")
	game._on_quest_accept("wang_message")
	_check("visit-accepted", game.state.quest_active("wang_message"))
	game.hud.close_dialogue()
	var coins_before: int = game.state.coins
	var wang_before: int = int(game.state.npc_friendship["wang"])
	await _talk_to("marnie")
	_check("visit-auto-completes", not game.state.quest_active("wang_message") and game.state.coins == coins_before + 30)
	_check("visit-thanks-from-target", game.hud._dialogue_text.text == String(QuestDB.entry("wang_message")["thanks"]))
	_check("visit-pays-wang-friendship", int(game.state.npc_friendship["wang"]) == wang_before + 30)
	game.hud.close_dialogue()


func _save_restore() -> void:
	game.state.accept_quest("clint_ore", game.state.day)
	SaveManager.save_game(1, game._save_payload())
	var saved: Dictionary = SaveManager.load_game(1)
	_check("payload-has-quests", (saved["economy"]["quests"]["accepted"] as Dictionary).has("clint_ore") and (saved["economy"]["quests"]["completed"] as Dictionary).has("pierre_veggies"))
	game.state.quests_accepted.clear()
	game.state.quests_completed.clear()
	game._apply_load(saved)
	await _frames(2)
	_check("load-restores-active", game.state.quest_active("clint_ore"))
	_check("load-restores-completed", not game.state.quest_available("pierre_veggies") and game.state.quest_available("pierre_fish"))


func _capture() -> void:
	if capture_path.is_empty() or DisplayServer.get_name() == "headless":
		return
	await _talk_to("pierre")
	await _frames(6)
	game.hud.update_clock()
	await _frames(4)
	DirAccess.make_dir_recursive_absolute(capture_path.get_base_dir())
	var image := root.get_texture().get_image()
	_check("capture-saved", image.save_png(capture_path) == OK)
	game.hud.close_dialogue()
	game.hud.toggle_inventory()
	game.hud.refresh()
	await _frames(4)
	var inventory := root.get_texture().get_image()
	_check("capture-inventory-saved", inventory.save_png(capture_path.get_basename() + "-inventory.png") == OK)
	game.hud.toggle_inventory()


func _frames(amount: int) -> void:
	for index in range(amount):
		await process_frame


func _finish() -> void:
	print("QUEST_RESULT %s %d checks" % ["PASS" if failures.is_empty() else "FAIL " + ",".join(failures), count])
	game.queue_free()
	await process_frame
	await process_frame
	quit(0 if failures.is_empty() else 1)
