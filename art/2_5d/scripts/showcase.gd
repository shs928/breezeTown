extends Node3D

const M = preload("res://scripts/art_mesh.gd")
const S = preload("res://scripts/scene_builder.gd")
const Pack = preload("res://scripts/model_pack.gd")

var _stage: Node3D
var _asset: Node3D
var _camera: Camera3D
var _view_index := 0
var _target := Vector3.ZERO
var _overlay: CanvasLayer
var _title: Label
var _subtitle: Label
var _dragging := false
var _batch := false
var _orbit := false
var _base_size := 20.0
var _batch_viewport: SubViewport

func _ready() -> void:
	_build_ui()
	var args := OS.get_cmdline_user_args()
	_batch = "--render" in args or "--export" in args
	if _batch:
		_overlay.hide()
		_batch_viewport = SubViewport.new()
		_batch_viewport.name = "PrintResolution"
		_batch_viewport.size = Vector2i(1920, 1200)
		_batch_viewport.own_world_3d = true
		_batch_viewport.msaa_3d = Viewport.MSAA_4X
		_batch_viewport.use_taa = true
		_batch_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(_batch_viewport)
		call_deferred("_run_batch", args)
	else:
		_show_view(0)
		print("ART_PREVIEW_READY")

func _build_ui() -> void:
	_overlay = CanvasLayer.new()
	add_child(_overlay)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	margin.add_theme_constant_override("margin_left", 34)
	margin.add_theme_constant_override("margin_top", 28)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(margin)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(column)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 26)
	_title.add_theme_color_override("font_color", Color("#344e48"))
	column.add_child(_title)
	_subtitle = Label.new()
	_subtitle.text = "1–6 切换场景   ·   鼠标拖动旋转   ·   滚轮缩放   ·   空格播放动作   ·   R 自动旋转   ·   F 保存图片"
	_subtitle.add_theme_font_size_override("font_size", 15)
	_subtitle.add_theme_color_override("font_color", Color("#61756c"))
	column.add_child(_subtitle)
	var footer := Label.new()
	footer.text = "B R E E Z E   T O W N     /     温暖手绘 · 立体小镇"
	footer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	footer.position = Vector2(34, 958)
	footer.add_theme_font_size_override("font_size", 13)
	footer.add_theme_color_override("font_color", Color("#61756c"))
	_overlay.add_child(footer)

func _show_view(index: int) -> void:
	_view_index = posmod(index, S.VIEWS.size())
	if is_instance_valid(_stage):
		_stage.free()
	_stage = Node3D.new()
	_stage.name = "LightingStudio"
	if is_instance_valid(_batch_viewport):
		_batch_viewport.add_child(_stage)
	else:
		add_child(_stage)
	var definition := S.view(_view_index)
	_asset = definition.root
	Pack.compact_scenery(_asset)
	_stage.add_child(_asset)
	_target = definition.target
	_base_size = definition.size
	_setup_lighting(definition.night, _view_index in [2, 5])
	_camera = Camera3D.new()
	_camera.name = "OrthographicCamera"
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = _base_size
	_camera.near = 0.05
	_camera.far = 240.0
	_camera.position = definition.camera
	_stage.add_child(_camera)
	_camera.look_at(_target)
	_camera.current = true
	_title.text = S.TITLES[_view_index]
	_title.add_theme_color_override("font_color", Color("#f1ddaa") if definition.night else Color("#344e48"))
	_subtitle.add_theme_color_override("font_color", Color("#d5d5c0") if definition.night else Color("#61756c"))

func _setup_lighting(night: bool, portrait: bool) -> void:
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#293d4c") if night else Color("#d9dece")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#9dbbda") if night else Color("#dce7ef")
	environment.ambient_light_energy = 0.38 if night else 0.50
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 0.96
	environment.ssao_enabled = true
	environment.ssao_radius = 0.40 if portrait else 0.74
	environment.ssao_intensity = 1.18
	environment.ssao_power = 1.32
	environment.ssao_detail = 0.70
	environment.ssao_light_affect = 0.14
	environment.ssil_enabled = false
	environment.ssil_radius = 2.7
	environment.ssil_intensity = 0.38
	environment.glow_enabled = night
	environment.glow_intensity = 0.5
	environment.glow_bloom = 0.025 if night else 0.0
	world.environment = environment
	_stage.add_child(world)
	var sunlight := DirectionalLight3D.new()
	sunlight.name = "EveningMoon" if night else "LateMorningSun"
	sunlight.rotation_degrees = Vector3(-36.0, -36.0, 0) if night else Vector3(-49.0, -38.0, 0)
	sunlight.light_color = Color("#acbfdf") if night else Color("#fff1dc")
	sunlight.light_energy = 0.62 if night else 1.12
	sunlight.light_angular_distance = 1.4
	sunlight.shadow_enabled = true
	sunlight.shadow_bias = 0.024
	sunlight.shadow_normal_bias = 0.65
	sunlight.directional_shadow_max_distance = 28.0 if portrait else 70.0
	sunlight.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	_stage.add_child(sunlight)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-29, 145, 0)
	fill.light_color = Color("#bad7e8") if night else Color("#d7ebf1")
	fill.light_energy = 0.16 if night else 0.20
	_stage.add_child(fill)
	var ground_y := -1.09 if _view_index in [0, 3] else (-0.34 if _view_index in [1, 4] else -0.045)
	var plane := PlaneMesh.new()
	plane.size = Vector2(250, 250)
	M.mesh_node(_stage, plane, Vector3(0, ground_y, 0), M.paint("#54706c" if night else ("#e7dfc9" if portrait else "#cfdbbd")), "StudioGround")
	if night:
		_light_windows(_asset)
		for entry in [Vector4(-3.69, 1.92, -2.12, 1.85), Vector4(2.10, 1.82, -2.50, 2.3), Vector4(1.55, 1.52, 5.7, 1.8), Vector4(5.39, 1.51, -0.35, 1.8), Vector4(-6.16, 1.30, -2.21, 1.3)]:
			var light := OmniLight3D.new()
			light.position = Vector3(entry.x, entry.y, entry.z)
			light.light_color = Color("#ffc372")
			light.light_energy = entry.w
			light.omni_range = 4.7
			light.omni_attenuation = 1.35
			light.shadow_enabled = true
			light.light_size = 0.22
			_stage.add_child(light)

func _light_windows(node: Node) -> void:
	if node is MeshInstance3D:
		for surface_index in range(node.mesh.get_surface_count()):
			var source: Material = node.get_active_material(surface_index)
			if source is StandardMaterial3D and ("glass" in source.resource_name.to_lower() or source.resource_name == "Paint_edcc83"):
				var lamp: StandardMaterial3D = source.duplicate()
				lamp.albedo_color = Color("#ffd99b")
				lamp.emission_enabled = true
				lamp.emission = Color("#ffc679")
				lamp.emission_energy_multiplier = 1.0
				node.set_surface_override_material(surface_index, lamp)
	for child in node.get_children():
		_light_windows(child)

func _run_batch(args: PackedStringArray) -> void:
	var ok := true
	var output := ProjectSettings.globalize_path("res://renders")
	DirAccess.make_dir_recursive_absolute(output)
	if "--export" in args:
		var report := Pack.export_all(ProjectSettings.globalize_path("res://models"))
		ok = report.ok and ok
	if "--render" in args:
		var only := -1
		for argument in args:
			if argument.begins_with("--view="):
				only = argument.trim_prefix("--view=").to_int()
		for index in range(S.VIEWS.size()):
			if only >= 0 and index != only:
				continue
			_show_view(index)
			for frame in range(48):
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var picture := _batch_viewport.get_texture().get_image()
			var result := picture.save_png(output.path_join(S.FILENAMES[index]))
			print("ART_RENDER ", S.FILENAMES[index], " ", picture.get_size(), " ", error_string(result))
			ok = result == OK and ok
	print("ART_WORKSHOP_COMPLETE ", "OK" if ok else "FAILED")
	get_tree().quit(0 if ok else 1)

func _process(delta: float) -> void:
	if _orbit and not _batch and is_instance_valid(_camera):
		_camera.position = _target + (_camera.position - _target).rotated(Vector3.UP, delta * 0.16)
		_camera.look_at(_target)

func _unhandled_input(event: InputEvent) -> void:
	if _batch:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode >= KEY_1 and event.keycode <= KEY_6:
			_show_view(event.keycode - KEY_1)
		elif event.keycode == KEY_TAB:
			_show_view(_view_index + 1)
		elif event.keycode == KEY_R:
			_orbit = not _orbit
		elif event.keycode == KEY_SPACE:
			for animator in _asset.find_children("AnimationPlayer", "AnimationPlayer", true, false):
				animator.play("walk" if animator.current_animation != "walk" else "idle")
		elif event.keycode == KEY_F:
			_overlay.hide()
			await RenderingServer.frame_post_draw
			var output := ProjectSettings.globalize_path("res://renders")
			DirAccess.make_dir_recursive_absolute(output)
			get_viewport().get_texture().get_image().save_png(output.path_join("my-" + S.FILENAMES[_view_index]))
			_overlay.show()
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_dragging = event.pressed
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_camera.size = maxf(_base_size * 0.45, _camera.size * 0.93)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_camera.size = minf(_base_size * 1.7, _camera.size * 1.07)
	if event is InputEventMouseMotion and _dragging:
		_camera.position = _target + (_camera.position - _target).rotated(Vector3.UP, -event.relative.x * 0.006)
		_camera.look_at(_target)
