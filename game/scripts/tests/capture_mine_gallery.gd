extends SceneTree
## 一次启动检查多个实际场景，避免每个视图都重建山谷。

const TOOLS := ["hand", "hoe", "can", "seed", "fence", "pickaxe", "sword"]
var game: Node3D
var output_dir: String


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	output_dir = ProjectSettings.globalize_path("res://../work")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			output_dir = argument.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(output_dir)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game._shot_path = "gallery"
	game.state.clock = 10
	await _capture("entrance", 0, Vector3(-29, 0, -68.8), 2, "pickaxe")
	await _capture("valley-map", 0, Vector3(-6, 0, 16), 3, "hand", "map")
	await _capture("01-overview", 1, Vector3(0, 0, 12), 2, "pickaxe", "overview")
	await _capture("camp", 5, Vector3(-5, 0, 3), 1, "pickaxe")
	await _capture("crystal", 7, Vector3(0, 0, -4), 2, "pickaxe")
	await _capture("map", 7, Vector3(0, 0, 12), 2, "pickaxe", "map")
	await _capture("guardian", 10, Vector3(0, 0, -3), 2, "sword")
	for tool in TOOLS:
		await _capture("tool-" + tool, 1, Vector3(0, 0, 3.6), 2, tool, "equipment")
	await _capture("combat", 1, Vector3(0, 0, 3.6), 0, "sword", "combat")
	print("GALLERY_RESULT PASS 15 views")
	quit(0)


func _capture(label: String, depth: int, at: Vector3, zoom: int, tool: String, view: String = "follow") -> void:
	game.hud.dismiss_panels()
	if game.mine_depth != depth:
		game._travel_to(depth)
	if depth > 0:
		for monster in game.mine.monsters:
			monster.behavior_enabled = false
	game._camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	game.player.camera = game._camera
	game.player.zoom_index = zoom
	game.player.teleport(at)
	game._select_tool(TOOLS.find(tool))
	game.player.face_point(at + Vector3.FORWARD if depth > 0 else at + Vector3.BACK)
	if view == "overview":
		game.player.camera = null
		game._camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		game._camera.size = 56
		game._camera.position = Vector3(0, 60, 42)
		game._camera.look_at(Vector3.ZERO)
	elif view == "equipment":
		game.player.face_point(at + Vector3(0.45, 0, 1))
		game.player.camera = null
		game._camera.position = at + Vector3(2.7, 2.4, 4.8)
		game._camera.look_at(at + Vector3(0, 1, 0))
	elif view == "map":
		game.hud.toggle_map()
	game._update_targeting()
	game.hud.refresh()
	game.hud.clear_toast()
	for frame in range(30):
		await process_frame
	if view == "combat":
		game.mine.monsters[0].position = Vector3(0.4, 0, 1.65)
		game.player.face_point(game.mine.monsters[0].position)
		game.player.attack_cooldown = 0
		game._use_tool()
		for frame in range(20):
			await physics_frame
		game._update_targeting()
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image().save_png(output_dir.path_join("game-3d-mine-" + label + ".png"))
	if result != OK:
		push_error("Gallery capture failed: " + label)
		quit(1)
		return
	print("GALLERY_VIEW %s OK" % label)
