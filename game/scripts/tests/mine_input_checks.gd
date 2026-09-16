extends SceneTree
## 普通游戏模式中的按键/过场回归，不开启 --smoke 的即时换层分支。

var game: Node3D
var failures: Array[String] = []
var _saw_transition_lock := false


func _initialize() -> void:
	create_timer(120).timeout.connect(func(): push_error("INPUT timeout"); quit(1))
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1600, 1000)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.hud.panels_changed.connect(func():
		if game._transitioning and game.player.locked:
			_saw_transition_lock = true
	)
	await _frames(4)
	game.player.teleport(game.landmarks["mine_door"] + Vector3(0, 0, 0.6))
	await _frames(2)
	_press(KEY_E)
	_press(KEY_E)
	_press(KEY_7)
	await _frames(55)
	_check("enter-fade-locks-player", _saw_transition_lock)
	_check("repeated-input-does-not-double-transition", game.mine_depth == 1 and not game._transitioning and not game.player.locked)
	_press(KEY_7)
	await _frames(2)
	_check("number-seven-equips-sword", game.player.equipped_tool == "sword")
	_press(KEY_M)
	_press(KEY_SPACE)
	await _frames(2)
	_check("map-key-pauses-actions", game.hud.map_open and game.player.locked and not game.player.acting)
	_press(KEY_ESCAPE)
	_press(KEY_6)
	await _frames(2)
	_check("escape-and-number-six-work", not game.player.locked and game.player.equipped_tool == "pickaxe")
	var seal: Node3D
	for rock in game.mine.rocks:
		if rock.seal:
			seal = rock
	game.player.teleport(seal.position + Vector3(0, 0, 1.8))
	await _frames(2)
	_press(KEY_E)
	await _frames(44)
	_check("interaction-key-mines-once", is_instance_valid(seal) and seal.health == 18 and not game.mine.descent_open)
	_press(KEY_E)
	await _frames(44)
	_check("interaction-key-reveals-stairs", game.mine.descent_open)
	_press(KEY_E)
	await _frames(55)
	_check("downstairs-fade-finishes", game.mine_depth == 2 and not game.player.locked)
	var start_z: float = game.player.position.z
	_key(KEY_S, true)
	await _frames(40)
	_key(KEY_S, false)
	await _frames(2)
	_check("physical-wasd-moves-player", game.player.position.z > start_z + 1.8)
	# Walking remains an input assertion; the following stair interaction uses
	# the floor's real upstairs location rather than a fixed movement duration.
	game.player.teleport(game.mine.up_position() + Vector3(0, 0, -1.6))
	await _frames(3)
	_press(KEY_E)
	await _frames(55)
	_check("upstairs-key-and-fade-work", game.mine_depth == 1)
	game.player.teleport(game.mine.up_position() + Vector3(0, 0, -1.6))
	await _frames(2)
	_press(KEY_E)
	await _frames(55)
	_check("exit-restores-normal-controls", game.mine_depth == 0 and not game.player.locked and not game._transitioning and game.player.equipped_tool == "hand")
	print("INPUT_RESULT " + ("PASS" if failures.is_empty() else "FAIL " + ",".join(failures)))
	quit(0 if failures.is_empty() else 1)


func _press(code: Key) -> void:
	_key(code, true)
	_key(code, false)


func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _frames(count: int) -> void:
	for frame in range(count):
		await physics_frame
	await process_frame


func _check(label: String, result: bool) -> void:
	print("INPUT %s %s" % [label, "OK" if result else "FAIL"])
	if not result:
		failures.append(label)
