extends Node3D
## 微风小镇 3D 可玩原型主控：建图、昼夜循环、交互、界面与自动化验证。

const GameState := preload("res://scripts/game_state.gd")
const WorldBuilder := preload("res://scripts/world_builder.gd")
const Plot := preload("res://scripts/plot.gd")
const Player := preload("res://scripts/player.gd")
const Hud := preload("res://scripts/hud.gd")

const DAY_SECONDS := 150.0  # 现实秒 / 游戏日
const INTERACT_RANGE := 1.85
const SHOP_RANGE := 2.4
const COTTAGE_RANGE := 2.3
const TOOLS := ["hand", "hoe", "can", "seed"]

var state: RefCounted
var player: CharacterBody3D
var hud: CanvasLayer
var plots: Array = []
var landmarks: Dictionary = {}
var tool_index := 0
var selected_seed := "radish"
var targeted_plot: Node3D

var _camera: Camera3D
var _sun: DirectionalLight3D
var _fill: DirectionalLight3D
var _environment: Environment
var _night_lights: Array[OmniLight3D] = []
var _smoke := false
var _shot_path := ""
var _demo := false

# 昼夜关键帧：时刻 / 天空色 / 环境色 / 环境强度 / 阳光色 / 阳光强度
const SKY_KEYS := [
	{"t": 6.0, "bg": Color("#e6d7ba"), "amb": Color("#e8d9c2"), "ae": 0.44, "sc": Color("#ffd9a8"), "se": 0.55},
	{"t": 11.0, "bg": Color("#d9dece"), "amb": Color("#dce7ef"), "ae": 0.50, "sc": Color("#fff1dc"), "se": 1.12},
	{"t": 17.0, "bg": Color("#dde2d2"), "amb": Color("#e5e3d8"), "ae": 0.48, "sc": Color("#ffedd0"), "se": 1.0},
	{"t": 19.8, "bg": Color("#c9b3a0"), "amb": Color("#c8b39f"), "ae": 0.40, "sc": Color("#f4a45f"), "se": 0.7},
	{"t": 21.8, "bg": Color("#33465a"), "amb": Color("#9dbbda"), "ae": 0.38, "sc": Color("#acbfdf"), "se": 0.32},
	{"t": 26.0, "bg": Color("#293d4c"), "amb": Color("#9dbbda"), "ae": 0.38, "sc": Color("#acbfdf"), "se": 0.3},
]


func _ready() -> void:
	state = GameState.new()
	var built: Dictionary = WorldBuilder.build()
	landmarks = built["landmarks"]
	add_child(built["root"])
	_add_obstacles(built["obstacles"])
	for index in range(WorldBuilder.plot_positions().size()):
		var plot: Node3D = Plot.new()
		plot.name = "Plot_%d" % index
		plot.position = WorldBuilder.plot_positions()[index]
		plot.setup(11 + index * 7)
		add_child(plot)
		plots.append(plot)
	player = Player.new()
	player.name = "Player"
	player.position = landmarks["spawn"]
	add_child(player)
	_camera = Camera3D.new()
	_camera.fov = 42.0
	_camera.near = 0.1
	_camera.far = 320.0
	add_child(_camera)
	_camera.global_position = player.global_position + Vector3(0, 8.6, 7.0)
	_camera.look_at(player.global_position + Vector3(0, 0.95, 0))
	_camera.current = true
	player.camera = _camera
	_setup_environment()
	hud = Hud.new()
	add_child(hud)
	hud.state = state
	hud.buy_requested.connect(_on_buy)
	hud.sell_requested.connect(_on_sell)
	hud.shop_closed.connect(func(): player.locked = false)
	hud.refresh()
	hud.select_slot(0, selected_seed, state.seeds[selected_seed])
	var args := OS.get_cmdline_user_args()
	for argument in args:
		if argument == "--smoke":
			_smoke = true
		elif argument == "--demo":
			_demo = true
		elif argument.begins_with("--shot="):
			_shot_path = argument.trim_prefix("--shot=")
	if _smoke:
		_run_smoke()
	elif _shot_path != "":
		_run_shot()
	else:
		print("GAME_READY")


func _process(delta: float) -> void:
	if _smoke or _shot_path != "":
		pass  # 自动化模式下时钟由脚本控制
	else:
		var rolled: bool = state.advance_hour(delta * GameState.HOURS_PER_DAY / DAY_SECONDS)
		if rolled:
			_apply_rollover()
		_update_targeting()
	_apply_daylight()


func _unhandled_input(event: InputEvent) -> void:
	if _smoke or _shot_path != "":
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1, KEY_2, KEY_3, KEY_4:
				_select_tool(event.keycode - KEY_1)
			KEY_R:
				var next := GameState.CROP_ORDER.find(selected_seed) + 1
				selected_seed = GameState.CROP_ORDER[next % GameState.CROP_ORDER.size()]
				hud.select_slot(tool_index, selected_seed, state.seeds[selected_seed])
				hud.show_toast("选中种子：" + GameState.crop_label(selected_seed))
			KEY_E:
				_interact()
			KEY_TAB:
				hud.toggle_inventory()
			KEY_ESCAPE:
				hud.dismiss_panels()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
		player.zoom_index = maxi(0, player.zoom_index - 1)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		player.zoom_index = mini(player.zoom_levels.size() - 1, player.zoom_index + 1)


func _select_tool(index: int) -> void:
	tool_index = clampi(index, 0, TOOLS.size() - 1)
	hud.select_slot(tool_index, selected_seed, state.seeds[selected_seed])


func _update_targeting() -> void:
	var previous := targeted_plot
	targeted_plot = null
	var hint := ""
	var player_pos: Vector3 = player.global_position
	if hud.shop_open:
		hint = "Esc 离开商店"
	else:
		if player_pos.distance_to(landmarks["shop_door"]) <= SHOP_RANGE:
			hint = "按 E 打开种子商店"
		elif player_pos.distance_to(landmarks["cottage_door"]) <= COTTAGE_RANGE:
			hint = "按 E 回屋休息到明天"
		else:
			var best_distance := INTERACT_RANGE
			for plot in plots:
				var distance: float = player_pos.distance_to(plot.global_position)
				if distance < best_distance:
					best_distance = distance
					targeted_plot = plot
			if targeted_plot != null:
				hint = "按 E %s" % targeted_plot.action_label()
			else:
				hint = "WASD 移动 · 1-4 换工具 · 靠近田块或设施按 E"
	if previous != targeted_plot:
		if is_instance_valid(previous):
			previous.set_targeted(false)
		if targeted_plot != null:
			targeted_plot.set_targeted(true)
	hud.set_hint(hint)


func _interact() -> void:
	if hud.shop_open:
		return
	if player_pos().distance_to(landmarks["shop_door"]) <= SHOP_RANGE:
		player.locked = true
		hud.open_shop()
		return
	if player_pos().distance_to(landmarks["cottage_door"]) <= COTTAGE_RANGE:
		_sleep()
		return
	if targeted_plot == null:
		return
	var tool: String = TOOLS[tool_index]
	if tool == "seed":
		if state.seeds[selected_seed] <= 0:
			hud.show_toast("%s 种子不够了，去商店买一些" % GameState.crop_label(selected_seed))
			return
		state.seeds[selected_seed] -= 1
	if tool == "hand" and targeted_plot.is_mature():
		state.harvest[targeted_plot.crop_kind] += 1
		hud.show_toast("收获 %s ×1" % GameState.crop_label(targeted_plot.crop_kind))
	targeted_plot.apply_tool(tool, selected_seed)
	player.start_act()
	hud.refresh()
	hud.select_slot(tool_index, selected_seed, state.seeds[selected_seed])


func player_pos() -> Vector3:
	return player.global_position


func _sleep() -> void:
	hud.fade_sleep(func() -> void:
		_do_sleep()
		hud.show_toast("第 %d 天的早晨" % state.day))


func _do_sleep() -> void:
	_apply_rollover()
	state.sleep_to_next_day()
	hud.refresh()


func _apply_rollover() -> void:
	for plot in plots:
		plot.on_day_rollover()
	hud.refresh()


func _on_buy(kind: String, count: int) -> void:
	if state.buy_seed(kind, count):
		hud.show_toast("买入 %s 种子 ×%d" % [GameState.crop_label(kind), count])
	else:
		hud.show_toast("金币不足")
	hud.refresh()


func _on_sell() -> void:
	var earned: int = state.sell_all_harvest()
	hud.show_toast("卖出全部收获，+ %d 金币" % earned)
	hud.refresh()


func _setup_environment() -> void:
	var world_env := WorldEnvironment.new()
	_environment = Environment.new()
	_environment.background_mode = Environment.BG_COLOR
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_environment.tonemap_exposure = 0.96
	_environment.ssao_enabled = true
	_environment.ssao_radius = 0.74
	_environment.ssao_intensity = 1.18
	_environment.ssao_power = 1.32
	_environment.ssao_detail = 0.70
	_environment.ssao_light_affect = 0.14
	_environment.glow_enabled = false
	world_env.environment = _environment
	add_child(world_env)
	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-49.0, -38.0, 0)
	_sun.light_angular_distance = 1.4
	_sun.shadow_enabled = true
	_sun.shadow_bias = 0.024
	_sun.shadow_normal_bias = 0.65
	_sun.directional_shadow_max_distance = 70.0
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	add_child(_sun)
	_fill = DirectionalLight3D.new()
	_fill.rotation_degrees = Vector3(-29, 145, 0)
	_fill.light_color = Color("#d7ebf1")
	_fill.light_energy = 0.2
	add_child(_fill)
	for entry in [Vector3(-4.4, 1.9, -3.4), Vector3(-4.3, 1.6, -2.3), Vector3(3.3, 1.8, -3.9), Vector3(1.5, 1.5, -2.7)]:
		var lamp := OmniLight3D.new()
		lamp.position = entry
		lamp.light_color = Color("#ffc372")
		lamp.light_energy = 0.0
		lamp.omni_range = 5.2
		lamp.omni_attenuation = 1.35
		lamp.shadow_enabled = false
		lamp.light_size = 0.22
		add_child(lamp)
		_night_lights.append(lamp)
	var plane := PlaneMesh.new()
	plane.size = Vector2(300, 300)
	var ground := MeshInstance3D.new()
	ground.mesh = plane
	ground.material_override = preload("res://scripts/art/art_mesh.gd").paint("#cfdbbd")
	ground.position.y = -1.06
	add_child(ground)


func _apply_daylight() -> void:
	var clock: float = state.clock
	var a: Dictionary = SKY_KEYS[0]
	var b: Dictionary = SKY_KEYS[SKY_KEYS.size() - 1]
	for index in range(SKY_KEYS.size() - 1):
		if clock >= SKY_KEYS[index]["t"] and clock <= SKY_KEYS[index + 1]["t"]:
			a = SKY_KEYS[index]
			b = SKY_KEYS[index + 1]
			break
	var span: float = maxf(0.001, b["t"] - a["t"])
	var weight: float = clampf((clock - a["t"]) / span, 0.0, 1.0)
	_environment.background_color = (a["bg"] as Color).lerp(b["bg"], weight)
	_environment.ambient_light_color = (a["amb"] as Color).lerp(b["amb"], weight)
	_environment.ambient_light_energy = lerpf(a["ae"], b["ae"], weight)
	_sun.light_color = (a["sc"] as Color).lerp(b["sc"], weight)
	_sun.light_energy = lerpf(a["se"], b["se"], weight)
	var day_progress: float = clampf((clock - 6.0) / 16.0, 0.0, 1.0)
	var elevation: float = -20.0 - 38.0 * sin(PI * day_progress) if clock < 22.0 else -24.0
	_sun.rotation_degrees = Vector3(elevation, -38.0, 0)
	var night: float = clampf((clock - 19.0) / 2.8, 0.0, 1.0)
	_environment.glow_enabled = night > 0.4
	for lamp in _night_lights:
		lamp.light_energy = night * 1.85


func _add_obstacles(obstacles: Array) -> void:
	for entry: Dictionary in obstacles:
		var body := StaticBody3D.new()
		body.position = entry["position"]
		var shape := CollisionShape3D.new()
		if entry["shape"] == "box":
			var box := BoxShape3D.new()
			box.size = entry["size"]
			shape.shape = box
		else:
			var sphere := SphereShape3D.new()
			sphere.radius = entry["radius"]
			shape.shape = sphere
		body.add_child(shape)
		add_child(body)


# ---------- 自动化验证 ----------

var _smoke_failures: Array[String] = []


func _check(step: String, condition: bool) -> void:
	print("SMOKE %s %s" % [step, "OK" if condition else "FAIL"])
	if not condition:
		_smoke_failures.append(step)


func _run_smoke() -> void:
	print("SMOKE_BEGIN")
	await _frames(3)
	_check("boot-coins", state.coins == 20 and state.seeds["radish"] == 6)
	var plot: Node3D = plots[0]
	player.global_position = plot.global_position + Vector3(1.5, 0, 0.3)
	await _frames(2)
	_update_targeting()
	_select_tool(1)
	_interact()
	_check("till", plot.state == "tilled")
	_select_tool(3)
	_update_targeting()
	_interact()
	_check("plant", plot.state == "planted" and plot.crop_kind == "radish" and state.seeds["radish"] == 5)
	_select_tool(2)
	_update_targeting()
	_interact()
	_check("water", plot.watered)
	# 生长规则：当天浇过水的作物日切时才长一阶，所以要逐天浇水。
	plot.on_day_rollover()
	_select_tool(2)
	_update_targeting()
	_interact()
	plot.on_day_rollover()
	_check("grow", plot.is_mature() and plot.stage == 2)
	_select_tool(0)
	_update_targeting()
	_interact()
	_check("harvest", state.harvest["radish"] == 1 and plot.state == "tilled")
	player.global_position = landmarks["shop_door"] + Vector3(0.7, 0, 0.5)
	await _frames(2)
	_update_targeting()
	_interact()
	_check("shop-open", hud.shop_open)
	_on_sell()
	_check("sell", state.coins == 28)
	hud.close_shop()
	_check("shop-close", not hud.shop_open and not player.locked)
	_do_sleep()
	_check("sleep", state.day == 2 and state.clock == 6.0 and not plot.watered)
	var result := "PASS" if _smoke_failures.is_empty() else "FAIL " + ",".join(_smoke_failures)
	print("SMOKE_RESULT " + result)
	get_tree().quit(0 if _smoke_failures.is_empty() else 1)


func _run_shot() -> void:
	if _demo:
		_build_demo_state()
	for frame in range(80):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var picture := get_viewport().get_texture().get_image()
	var result := picture.save_png(_shot_path)
	print("SHOT_OK " + _shot_path + " " + error_string(result) + " " + str(picture.get_size()))
	get_tree().quit(0 if result == OK else 1)


func _build_demo_state() -> void:
	## 展示各生长阶段：萝卜苗、半熟草莓、成熟小麦与南瓜（带金圈）。
	var recipes := [["radish", 0], ["strawberry", 1], ["wheat", 3], ["pumpkin", 4]]
	for index in range(recipes.size()):
		var plot: Node3D = plots[index]
		var kind: String = recipes[index][0]
		plot.apply_tool("hoe")
		plot.apply_tool("seed", kind)
		plot.debug_set_stage(recipes[index][1])
		if recipes[index][1] < 2:
			plot.apply_tool("can")
	player.global_position = plots[0].global_position + Vector3(2.0, 0, 2.1)
	_update_targeting()
	hud.refresh()
	hud.select_slot(tool_index, selected_seed, state.seeds[selected_seed])


func _frames(count: int) -> void:
	for frame in range(count):
		await get_tree().physics_frame
