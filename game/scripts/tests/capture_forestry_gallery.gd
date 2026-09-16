extends SceneTree
## 同一个运行场景中的视觉验收。砍树与掉落经过真实动作结算。

var game: Node3D
var output_dir: String
var captures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	output_dir = ProjectSettings.globalize_path("res://../work")
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game._shot_path = "forestry-gallery"
	game.state.clock = 10
	await _view(Vector3(-18, 0, 41), 2, "axe")
	await _capture("grove")
	await _view(Vector3(-29, 0, 42.8), 1, "axe")
	await _capture("pine")
	await _view(Vector3(-55.5, 0, 41.7), 2, "axe")
	await _capture("orchard")
	for tool in ["axe", "sapling"]:
		await _view(Vector3(-6, 0, 16), 1, tool)
		game.player.camera = null
		game.player.face_point(game.player.position + Vector3(0.45, 0, 1))
		game._camera.position = game.player.position + Vector3(2.7, 2.4, 4.8)
		game._camera.look_at(game.player.position + Vector3(0, 1, 0))
		await _capture("tool-" + tool)
	await _view(Vector3(-18, 0, 39.8), 1, "axe")
	var tree: Node3D
	for resource in game.surface_resources.resources:
		if resource.position.distance_to(Vector3(-18, 0, 38)) < 0.1:
			tree = resource
	game.player.face_point(tree.position)
	game.player.attack_cooldown = 0
	game._use_tool()
	await _frames(22)
	await _capture("chop", false)
	await _frames(24)
	# 固定随机序列以复现同时掉落木材和树苗的画面。
	game.surface_resources.rng.seed = 17893
	for attempt in range(30):
		var rng_state: int = game.surface_resources.rng.state
		if game.surface_resources.roll_tree_loot(true).has("sapling"):
			game.surface_resources.rng.state = rng_state
			break
	game._use_tool()
	await _frames(43)
	game._use_tool()
	await _frames(23)
	game.player.locked = true
	await _frames(45)
	game._update_targeting()
	game.hud.set_hint("砍倒成年树 · 木材与树苗掉落到地面 · 靠近后自动拾取")
	await _capture("drops", false)
	game.player.locked = false
	await _frames(80)
	game.hud.toggle_inventory()
	await _capture("inventory")
	game.hud.dismiss_panels()
	for stage in range(4):
		game.surface_resources.try_spawn({"position": Vector2(-40 + stage * 6, 22), "category": "tree", "species": "oak", "stage": stage, "variant": 2}, false)
	await _view(Vector3(-30, 0, 26), 3, "sapling")
	game.hud.set_hint("树苗成长：初种 → 第 1 天 → 第 2 天 → 第 3 天成年")
	await _capture("growth")
	game._build_demo_state()
	await _view(Vector3(-25, 0, 15), 3, "hoe")
	await _capture("farm")
	await _view(Vector3(-14, 0, 39.8), 0, "pickaxe")
	game.player.face_point(Vector3(-14, 0, 38))
	game.player.attack_cooldown = 0
	game._use_tool()
	await _frames(22)
	await _capture("ore", false)
	print("FORESTRY_GALLERY_RESULT PASS %d views" % captures)
	quit(0)


func _view(at: Vector3, zoom: int, tool: String) -> void:
	game.player.locked = false
	game.player.camera = game._camera
	game.player.zoom_index = zoom
	game.player.teleport(at)
	game.player.face_point(at + Vector3(0.3, 0, 1))
	game._select_tool(game.TOOLS.find(tool))
	game._update_targeting()
	game.hud.refresh()
	game.hud.clear_toast()
	await _frames(20)


func _capture(label: String, settle: bool = true) -> void:
	if settle:
		await _frames(18)
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(output_dir.path_join("game-3d-forestry-" + label + ".png"))
	if error != OK:
		push_error("Forestry capture failed: " + label)
		quit(1)
		return
	captures += 1
	print("FORESTRY_VIEW %s OK" % label)


func _frames(count: int) -> void:
	for frame in range(count):
		await physics_frame
