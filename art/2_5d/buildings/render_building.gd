extends SceneTree

const Buildings = preload("../scripts/building_models.gd")


func _initialize() -> void:
	_render.call_deferred()


func _render() -> void:
	root.size = Vector2i(1280, 1024)
	var scene := Node3D.new()
	root.add_child(scene)
	var shop_preview := "--shop" in OS.get_cmdline_user_args()
	var model := Buildings.shop() if shop_preview else Buildings.cottage()
	scene.add_child(model)
	var floor_node := MeshInstance3D.new()
	var floor_mesh := BoxMesh.new()
	floor_mesh.size = Vector3(11, 0.18, 11)
	floor_node.mesh = floor_mesh
	floor_node.position.y = -0.095
	var ground := StandardMaterial3D.new()
	ground.albedo_color = Color("#B4B18B")
	ground.roughness = 1.0
	floor_node.material_override = ground
	scene.add_child(floor_node)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#E7E1C9")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#E3EACA")
	environment.ambient_light_energy = 0.55
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.ssao_enabled = true
	environment.ssao_radius = 1.0
	environment.ssao_intensity = 1.6
	var world := WorldEnvironment.new()
	world.environment = environment
	scene.add_child(world)
	var light := DirectionalLight3D.new()
	light.light_color = Color("#FFEACB")
	light.light_energy = 1.8
	light.rotation_degrees = Vector3(-43, -32, 0)
	light.shadow_enabled = true
	light.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	scene.add_child(light)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 7.4
	camera.position = Vector3(7.5, 5.6, 10.5)
	scene.add_child(camera)
	camera.look_at(Vector3(0, 1.73, 0.21))
	camera.current = true
	for i in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	var label := "shop" if shop_preview else "cottage"
	var target := "res://buildings/" + label + "-preview.png"
	var result := root.get_texture().get_image().save_png(target)
	print("BUILDING_PREVIEW " + label + " saved=" + str(result == OK) + " path=" + ProjectSettings.globalize_path(target))
	quit(0 if result == OK else 1)
