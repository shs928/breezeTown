extends SceneTree
const B = preload("res://scripts/art/building_models.gd")
const R = preload("res://scripts/ranch_models.gd")
const StaticGeometry = preload("res://scripts/art/static_geometry.gd")
## Run with Godot --path game --script ../tools/art/render_architecture.gd
## GPU rendering is required; output is work/style-rebuild/architecture/.
var stage: Node3D
var camera: Camera3D
func _initialize() -> void:
	root.size = Vector2i(900, 900)
	stage = Node3D.new()
	root.add_child(stage)
	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#C9D7C3")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#C4D4D9")
	env.ambient_light_energy = 0.32
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	world.environment = env
	stage.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -35, 0)
	sun.light_color = Color("#FFE8BD")
	sun.light_energy = 0.75
	sun.shadow_enabled = true
	stage.add_child(sun)
	B._box(stage, "Ground", Vector3(70, 0.1, 70), Vector3(0, -0.12, 0), B._material("Studio_Grass", Color("#9BAB70")), 0.0)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	stage.add_child(camera)
	camera.current = true
	_run.call_deferred()
func _run() -> void:
	var models := [B.cottage(), R.barn(), R.coop(), B.cottage()]
	var labels := ["cottage-painted", "barn-painted", "coop-painted", "cottage-east-painted"]
	var output := ProjectSettings.globalize_path("res://../work/style-rebuild/architecture")
	DirAccess.make_dir_recursive_absolute(output)
	for index in range(models.size()):
		var model: Node3D = models[index]
		StaticGeometry.bake(model)
		stage.add_child(model)
		camera.size = [8.9, 10.8, 5.9, 8.9][index]
		camera.position = Vector3(9 if index == 3 else -9, 8.0, 13)
		camera.look_at(Vector3(0, [2.25, 2.4, 1.0, 2.25][index], 0.35))
		for frame in range(12):
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join(labels[index] + ".png"))
		print("ARCHITECTURE_RENDER ", labels[index])
		model.free()
	quit()
