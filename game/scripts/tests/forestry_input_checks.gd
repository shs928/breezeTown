extends SceneTree
## 经正常输入事件验证 8/9、E、空格、左键和暂停，不使用冒烟模式。

const Checks = preload("res://scripts/tests/forestry_checks.gd")
var game: Node3D
var failures: Array[String] = []


func _initialize() -> void:
	create_timer(120).timeout.connect(func(): push_error("FORESTRY_INPUT timeout"); quit(1))
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1600, 1000)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await _frames(4)
	var at := Checks.find_clear(game)
	var tree: Node3D = game.surface_resources.try_spawn({"position": at, "category": "tree"}, false)
	game.player.teleport(tree.position + Vector3(0, 0, 1.9))
	await _frames(3)
	_press(KEY_8)
	await _frames(2)
	_check("eight-equips-visible-axe", game.player.equipped_tool == "axe" and game.player._held.get_meta("tool") == "axe")
	_press(KEY_E)
	_press(KEY_E)
	_press(KEY_SPACE)
	await _frames(43)
	_check("repeated-keys-produce-one-chop", tree.health == 36)
	_press(KEY_SPACE)
	_press(KEY_TAB)
	await _frames(43)
	_check("inventory-cancels-chop", game.hud.inventory_open and game.player.locked and tree.health == 36)
	_press(KEY_ESCAPE)
	await _frames(2)
	_click(game._camera.unproject_position(tree.position + Vector3(0, 0.7, 0)))
	await _frames(43)
	_check("left-click-faces-and-chops-tree", tree.health == 18)
	var wood_before: int = game.state.forestry["wood"]
	for wait_frame in range(60):
		if not game.player.acting and game.player.attack_cooldown <= 0:
			break
		await _frames(1)
	_press(KEY_SPACE)
	await _frames(110)
	_check("space-fells-tree-and-collects-wood", not is_instance_valid(tree) and game.state.forestry["wood"] >= wood_before + 4)
	_check("felling-opens-ground-in-normal-play", game.tiles.is_open(game.tiles.key_of(Vector3(at.x, 0, at.y))))
	game.state.forestry["sapling"] = 1
	game.hud.refresh()
	var plant_at := Checks.find_clear(game)
	game.player.teleport(Vector3(plant_at.x, 0, plant_at.y + 2))
	game.player.face_point(Vector3(plant_at.x, 0, plant_at.y))
	_press(KEY_9)
	await _frames(3)
	_check("nine-equips-visible-sapling", game.player.equipped_tool == "sapling" and game.focus.get("kind") == "sapling")
	var count: int = game.surface_resources.resources.size()
	_click(game._camera.unproject_position(Vector3(plant_at.x, 0.7, plant_at.y)))
	await _frames(44)
	_check("left-click-plants-and-consumes-sapling", game.state.forestry["sapling"] == 0 and game.surface_resources.resources.size() == count + 1)
	var planted: Node3D = game.surface_resources.resources[-1]
	_press(KEY_E)
	await _frames(2)
	_check("empty-inventory-cannot-plant-again", game.state.forestry["sapling"] == 0 and game.surface_resources.resources.size() == count + 1)
	game.state.clock = 25.99
	var day: int = game.state.day
	await _frames(14)
	_check("normal-clock-rollover-grows-sapling", game.state.day == day + 1 and planted.stage == 1)
	_press(KEY_TAB)
	await _frames(2)
	var inventory_text := ""
	for label in game.hud._inventory_lines.get_children():
		if label is Label:
			inventory_text += label.text
	_check("inventory-shows-wood-saplings-and-ore-rules", "木材" in inventory_text and "树苗" in inventory_text and "铁矿和水晶" in inventory_text)
	_press(KEY_ESCAPE)
	game.player.teleport(planted.position + Vector3(0, 0, 1.9))
	_press(KEY_8)
	await _frames(3)
	_press(KEY_E)
	await _frames(110)
	_check("young-tree-recovery-uses-normal-input", not is_instance_valid(planted) and game.state.forestry["sapling"] == 1)
	print("FORESTRY_INPUT_RESULT " + ("PASS" if failures.is_empty() else "FAIL " + ",".join(failures)))
	quit(0 if failures.is_empty() else 1)


func _press(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
	Input.flush_buffered_events()


func _click(at: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = at
		event.pressed = pressed
		Input.parse_input_event(event)
	Input.flush_buffered_events()


func _frames(count: int) -> void:
	for frame in range(count):
		await physics_frame
	await process_frame


func _check(label: String, result: bool) -> void:
	print("FORESTRY_INPUT %s %s" % [label, "OK" if result else "FAIL"])
	if not result:
		failures.append(label)
