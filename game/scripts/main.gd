extends Node3D
## 微风小镇 3D 原型主控：大地图（农田＋牧场）、昼夜循环、交互、界面与自动化验证。

const GameState := preload("res://scripts/game_state.gd")
const WorldBuilder := preload("res://scripts/world_builder.gd")
const Plot := preload("res://scripts/plot.gd")
const Player := preload("res://scripts/player.gd")
const Hud := preload("res://scripts/hud.gd")
const Animal := preload("res://scripts/animal.gd")
const Pickup := preload("res://scripts/pickup.gd")
const Trough := preload("res://scripts/trough.gd")

const DAY_SECONDS := 150.0  # 现实秒 / 游戏日
const SHOP_RANGE := 2.4
const COTTAGE_RANGE := 2.3
const PLOT_RANGE := 1.95
const ANIMAL_RANGE := 1.7
const PICKUP_RANGE := 1.35
const TROUGH_RANGE := 2.0
const TOOLS := ["hand", "hoe", "can", "seed"]
const ANIMAL_ROSTER := ["cow", "cow", "sheep", "sheep", "chicken", "chicken", "chicken"]

var state: RefCounted
var player: CharacterBody3D
var hud: CanvasLayer
var plots: Array = []
var animals: Array = []
var pickups: Array = []
var trough: Node3D
var landmarks: Dictionary = {}
var tool_index := 0
var selected_seed := "radish"
var focus: Dictionary = {}  # {"kind": "plot|animal|pickup|trough|shop|cottage", "node": ...}

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
	trough = Trough.new()
	trough.name = "Trough"
	trough.position = landmarks["trough"]
	trough.setup()
	add_child(trough)
	var pasture: Rect2 = built["pasture"]
	for index in range(ANIMAL_ROSTER.size()):
		var animal: Node3D = Animal.new()
		animal.name = "Animal_%d" % index
		animal.setup(ANIMAL_ROSTER[index], pasture, 700 + index * 131)
		add_child(animal)
		animals.append(animal)
	player = Player.new()
	player.name = "Player"
	player.position = landmarks["spawn"]
	add_child(player)
	player.set_bounds(built["bounds"]["half"], built["bounds"]["pow"])
	_camera = Camera3D.new()
	_camera.fov = 42.0
	_camera.near = 0.1
	_camera.far = 360.0
	add_child(_camera)
	_camera.global_position = player.global_position + Player.CAMERA_OFFSET
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
	var previous: Node3D = focus.get("node") if focus.has("node") else null
	if focus.get("kind") == "plot" and is_instance_valid(previous):
		previous.set_targeted(false)
	focus = {}
	var hint := ""
	var player_pos: Vector3 = player.global_position
	if hud.shop_open:
		hint = "Esc 离开商店"
	elif player_pos.distance_to(landmarks["shop_door"]) <= SHOP_RANGE:
		focus = {"kind": "shop", "node": null}
		hint = "按 E 打开种子商店"
	elif player_pos.distance_to(landmarks["cottage_door"]) <= COTTAGE_RANGE:
		focus = {"kind": "cottage", "node": null}
		hint = "按 E 回屋休息到明天"
	else:
		var best_distance := 1.0e9
		for plot in plots:
			var distance: float = player_pos.distance_to(plot.global_position)
			if distance < PLOT_RANGE and distance < best_distance:
				best_distance = distance
				focus = {"kind": "plot", "node": plot}
		for pickup in pickups:
			var distance: float = player_pos.distance_to(pickup.global_position)
			if distance < PICKUP_RANGE and distance < best_distance:
				best_distance = distance
				focus = {"kind": "pickup", "node": pickup}
		for animal in animals:
			var distance: float = player_pos.distance_to(animal.global_position)
			if distance < ANIMAL_RANGE and distance < best_distance:
				best_distance = distance
				focus = {"kind": "animal", "node": animal}
		var trough_distance: float = player_pos.distance_to(trough.global_position)
		if trough_distance < TROUGH_RANGE and trough_distance < best_distance:
			best_distance = trough_distance
			focus = {"kind": "trough", "node": trough}
		match focus.get("kind"):
			"plot":
				var plot: Node3D = focus["node"]
				plot.set_targeted(true)
				hint = "按 E %s" % plot.action_label()
			"pickup":
				var pickup: Node3D = focus["node"]
				hint = "按 E 捡起 %s" % pickup.label()
			"animal":
				var animal: Node3D = focus["node"]
				hint = "今天已经摸过 %s了" % animal.label() if animal.petted_today else "按 E 抚摸 %s" % animal.label()
			"trough":
				hint = "食槽已装满干草" if trough.filled else "按 E 填满干草（动物明早产出）"
			_:
				hint = "WASD 移动 · 1-4 换工具 · 靠近目标按 E"
	hud.set_hint(hint)


func _interact() -> void:
	if hud.shop_open:
		return
	match focus.get("kind"):
		"shop":
			player.locked = true
			hud.open_shop()
		"cottage":
			_sleep()
		"pickup":
			var pickup: Node3D = focus["node"]
			state.products[pickup.kind] += 1
			hud.show_toast("捡起 %s ×1" % pickup.label())
			pickups.erase(pickup)
			pickup.queue_free()
			hud.refresh()
		"animal":
			var animal: Node3D = focus["node"]
			if animal.pet():
				hud.show_toast("%s 很开心 ♥" % animal.label())
			else:
				hud.show_toast("%s 今天已经很开心了" % animal.label())
			player.start_act()
		"trough":
			trough.set_filled(true)
			hud.show_toast("干草已装满，动物们明早会有产出")
			player.start_act()
		"plot":
			var plot: Node3D = focus["node"]
			var tool: String = TOOLS[tool_index]
			if tool == "seed":
				if state.seeds[selected_seed] <= 0:
					hud.show_toast("%s 种子不够了，去商店买一些" % GameState.crop_label(selected_seed))
					return
				state.seeds[selected_seed] -= 1
			if tool == "hand" and plot.is_mature():
				state.harvest[plot.crop_kind] += 1
				hud.show_toast("收获 %s ×1" % GameState.crop_label(plot.crop_kind))
			plot.apply_tool(tool, selected_seed)
			player.start_act()
			hud.refresh()
			hud.select_slot(tool_index, selected_seed, state.seeds[selected_seed])


func _sleep() -> void:
	hud.fade_sleep(func(): _do_sleep_and_greet())


func _do_sleep_and_greet() -> void:
	_do_sleep()
	hud.show_toast("第 %d 天的早晨" % state.day)


func _apply_rollover() -> void:
	for plot in plots:
		plot.on_day_rollover()
	for animal in animals:
		animal.on_new_day()
	if trough.filled:
		var rng := RandomNumberGenerator.new()
		rng.seed = state.day * 977 + 13
		var pasture: Rect2 = WorldBuilder.PASTURE
		for animal in animals:
			var pickup := Pickup.new()
			pickup.setup(animal.product_kind())
			pickup.position = Vector3(
				rng.randf_range(pasture.position.x + 1.2, pasture.position.x + pasture.size.x - 1.2),
				0,
				rng.randf_range(pasture.position.y + 1.2, pasture.position.y + pasture.size.y - 1.2)
			)
			add_child(pickup)
			pickups.append(pickup)
		trough.set_filled(false)
	hud.refresh()


func _do_sleep() -> void:
	_apply_rollover()
	state.sleep_to_next_day()
	hud.refresh()


func _on_buy(kind: String, count: int) -> void:
	if state.buy_seed(kind, count):
		hud.show_toast("买入 %s 种子 ×%d" % [GameState.crop_label(kind), count])
	else:
		hud.show_toast("金币不足")
	hud.refresh()


func _on_sell() -> void:
	var earned: int = state.sell_all_harvest()
	hud.show_toast("卖出收获与产品，+ %d 金币" % earned)
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
	_sun.directional_shadow_max_distance = 150.0
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	add_child(_sun)
	_fill = DirectionalLight3D.new()
	_fill.rotation_degrees = Vector3(-29, 145, 0)
	_fill.light_color = Color("#d7ebf1")
	_fill.light_energy = 0.2
	add_child(_fill)
	for entry in [Vector3(-29.5, 2.1, -13.3), Vector3(-31.8, 1.7, -15.6), Vector3(21.0, 2.0, -15.1), Vector3(23.6, 1.6, -16.2), Vector3(2.0, 1.5, 7.9), Vector3(-2.2, 1.5, -1.9)]:
		var lamp := OmniLight3D.new()
		lamp.position = entry
		lamp.light_color = Color("#ffc372")
		lamp.light_energy = 0.0
		lamp.omni_range = 6.5
		lamp.omni_attenuation = 1.35
		lamp.shadow_enabled = false
		lamp.light_size = 0.22
		add_child(lamp)
		_night_lights.append(lamp)
	var plane := PlaneMesh.new()
	plane.size = Vector2(700, 700)
	var ground := MeshInstance3D.new()
	ground.mesh = plane
	ground.material_override = preload("res://scripts/art/art_mesh.gd").paint("#cfdbbd")
	ground.position.y = -1.20
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
	_check("world-plots", plots.size() == 30 and animals.size() == 7)
	var plot: Node3D = plots[0]
	# 站在目标田正北：到 plots[0] 最近，且不被相邻田块抢焦点。
	player.global_position = plot.global_position + Vector3(0, 0, -1.3)
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
	# 牧场流程：填食槽 → 抚摸动物 → 睡觉 → 产出 → 拾取 → 出售。
	player.global_position = landmarks["trough"] + Vector3(1.0, 0, 0.4)
	await _frames(2)
	_update_targeting()
	_interact()
	_check("trough-fill", trough.filled)
	var cow: Node3D = animals[0]
	player.global_position = cow.global_position + Vector3(1.2, 0, 0.2)
	await _frames(2)
	_update_targeting()
	_interact()
	_check("pet", cow.petted_today)
	_do_sleep()
	_check("sleep", state.day == 2 and state.clock == 6.0 and not plot.watered)
	_check("produce", pickups.size() == animals.size())
	var milk_pickup: Node3D = null
	for pickup in pickups:
		if pickup.kind == "milk":
			milk_pickup = pickup
			break
	_check("produce-milk", milk_pickup != null)
	if milk_pickup != null:
		player.global_position = milk_pickup.global_position + Vector3(0.9, 0, 0.2)
		await _frames(2)
		_update_targeting()
		_interact()
	_check("collect", state.products["milk"] == 1)
	_on_sell()
	_check("sell-ranch", state.coins == 42)
	var result := "PASS" if _smoke_failures.is_empty() else "FAIL " + ",".join(_smoke_failures)
	print("SMOKE_RESULT " + result)
	get_tree().quit(0 if _smoke_failures.is_empty() else 1)


func _run_shot() -> void:
	if _demo:
		_build_demo_state()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--at="):
			var pair := argument.trim_prefix("--at=").split(",")
			player.global_position = Vector3(pair[0].to_float(), 0, pair[1].to_float())
			_update_targeting()
	for frame in range(110):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var picture := get_viewport().get_texture().get_image()
	var result := picture.save_png(_shot_path)
	print("SHOT_OK " + _shot_path + " " + error_string(result) + " " + str(picture.get_size()))
	get_tree().quit(0 if result == OK else 1)


func _build_demo_state() -> void:
	## 展示各生长阶段与牧场（含干草食槽与一件产出物）。
	var recipes := [["radish", 0], ["strawberry", 1], ["wheat", 3], ["pumpkin", 4]]
	for index in range(recipes.size()):
		var plot: Node3D = plots[index]
		var kind: String = recipes[index][0]
		plot.apply_tool("hoe")
		plot.apply_tool("seed", kind)
		plot.debug_set_stage(recipes[index][1])
		if recipes[index][1] < 2:
			plot.apply_tool("can")
	trough.set_filled(true)
	var gift := Pickup.new()
	gift.setup("milk")
	gift.position = Vector3(14.5, 0, 9)
	add_child(gift)
	pickups.append(gift)
	player.global_position = Vector3(6, 0, 19)
	_update_targeting()
	hud.refresh()
	hud.select_slot(tool_index, selected_seed, state.seeds[selected_seed])


func _frames(count: int) -> void:
	for frame in range(count):
		await get_tree().physics_frame
