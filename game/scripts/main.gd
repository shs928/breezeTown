extends Node3D
## 微风山谷主控：地表经营、十层矿场、装备战斗、昼夜循环与地图切换。

const GameState := preload("res://scripts/game_state.gd")
const WorldBuilder := preload("res://scripts/world_builder.gd")
const Tiles := preload("res://scripts/tiles.gd")
const Pasture := preload("res://scripts/pasture.gd")
const Player := preload("res://scripts/player.gd")
const Hud := preload("res://scripts/hud.gd")
const Animal := preload("res://scripts/animal.gd")
const Pickup := preload("res://scripts/pickup.gd")
const Trough := preload("res://scripts/trough.gd")
const Equipment := preload("res://scripts/art/equipment_models.gd")
const MineFloor := preload("res://scripts/mine_floor.gd")
const MineLayout := preload("res://scripts/mine_layout.gd")
const Feedback := preload("res://scripts/combat_feedback.gd")
const SurfaceResources := preload("res://scripts/surface_resources.gd")
const InteractionSystem := preload("res://scripts/core/interaction_system.gd")
const SaveManager := preload("res://scripts/core/save_manager.gd")
const WorldNavigation := preload("res://scripts/core/world_navigation.gd")
const MapRestore := preload("res://scripts/core/map_restore.gd")

const DAY_SECONDS := 150.0  # 现实秒 / 游戏日
const SHOP_RANGE := 2.4
const COTTAGE_RANGE := 2.3
const PLOT_RANGE := 1.95
const ANIMAL_RANGE := 1.7
const PICKUP_RANGE := 1.35
const TROUGH_RANGE := 2.0
const TOOLS := Equipment.TOOLS
const ANIMAL_ROSTER := ["cow", "cow", "sheep", "sheep", "chicken", "chicken", "chicken"]

var state: RefCounted
var player: CharacterBody3D
var hud: CanvasLayer
var tiles: Node3D
var surface_resources: Node3D
var pastures: Array = []
var world_data: Dictionary = {}
var navigation: RefCounted
var _fence_start: Variant = null
var _fence_preview: MeshInstance3D
var animals: Array = []
var pickups: Array = []
var trough: Node3D
var landmarks: Dictionary = {}
var tool_index := 0
var selected_seed := "radish"
var focus: Dictionary = {}  # tile / animal / pickup / trough / shop / cottage / fence

var _camera: Camera3D
var _sun: DirectionalLight3D
var _fill: DirectionalLight3D
var _environment: Environment
var _night_lights: Array[OmniLight3D] = []
var _smoke := false
var _shot_path := ""
var _demo := false
var _load_requested := false
var _interaction
var _outdoors: Node3D
var _mine_root: Node3D
var mine: Node3D
var mine_depth := 0
var _mine_floors: Dictionary = {}
var scenery: Node3D
var _pending_mine_state: Dictionary = {}
var _transitioning := false
var _surface_tool := 0
var _surface_zoom := 3
var _mine_zoom := 2
var _surface_return := Vector3.ZERO
var _mine_map_timer := 0.0
var _recovery_pending := false
var _start_mine_depth := 0
var _water_sector:=Vector2i(2147483647,2147483647)

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
	_interaction = InteractionSystem.new()
	_interaction.game = self
	_outdoors = Node3D.new()
	_outdoors.name = "OutdoorMap"
	add_child(_outdoors)
	_mine_root = Node3D.new()
	_mine_root.name = "MineFloors"
	add_child(_mine_root)
	world_data = WorldBuilder.build()
	SaveManager.select_world(world_data["definition"]["id"])
	landmarks = world_data["landmarks"]
	_outdoors.add_child(world_data["root"])
	_add_obstacles(world_data["obstacles"])
	tiles = Tiles.new()
	tiles.name = "Farmland"
	_outdoors.add_child(tiles)
	tiles.map.load_from_world(world_data)
	_add_water_obstacles()
	navigation = WorldNavigation.new()
	navigation.configure(tiles.map)
	var enclosure := _create_pasture(world_data["pasture"])
	trough = enclosure.trough
	for index in range(ANIMAL_ROSTER.size()):
		var animal: Node3D = Animal.new()
		animal.name = "Animal_%d" % index
		animal.setup(ANIMAL_ROSTER[index], enclosure.interior, 700 + index * 131)
		_outdoors.add_child(animal)
		animals.append(animal)
		enclosure.animals.append(animal)
	player = Player.new()
	player.name = "Player"
	player.position = landmarks["spawn"]
	add_child(player)
	player.tool_hit.connect(_on_tool_hit)
	player.surface_map = tiles.map
	if world_data["definition"]["id"]=="willow_creek_valley_v1":
		player.camera_target_offset=Vector3(0,0,-4)
		scenery=preload("res://scripts/first_map_scenery.gd").new()
		scenery.name="StreamedScenery"
		_outdoors.add_child(scenery)
		scenery.farm_tiles=tiles.farm
		scenery.tree_broken.connect(_on_forest_tree_broken)
		scenery.configure(player,tiles.map,world_data["definition"])
	player.set_bounds(world_data["bounds"]["half"], world_data["bounds"]["pow"])
	_camera = Camera3D.new()
	_camera.fov = 42.0
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 27.0
	_camera.near = 0.1
	_camera.far = 700.0
	add_child(_camera)
	_camera.global_position = player.global_position + Player.CAMERA_OFFSET * player.zoom_levels[player.zoom_index]
	_camera.look_at(player.global_position + Vector3(0, 0.95, 0))
	_camera.current = true
	player.camera = _camera
	_setup_environment()
	hud = Hud.new()
	add_child(hud)
	hud.state = state
	hud.buy_requested.connect(_on_buy)
	hud.sell_requested.connect(_on_sell)
	hud.panels_changed.connect(_sync_player_lock)
	hud.map_toggled.connect(func(_open: bool): _sync_player_lock())
	hud.travel_requested.connect(_on_travel_requested)
	hud.setup_navigation(world_data["navigation"])
	hud.refresh()
	hud.select_slot(0, selected_seed, state.seeds[selected_seed])
	var args := OS.get_cmdline_user_args()
	surface_resources = SurfaceResources.new()
	surface_resources.name = "SurfaceResources"
	surface_resources.tiles = tiles
	surface_resources.player = player
	surface_resources.world = world_data
	surface_resources.actors = _surface_actors
	surface_resources.loot_collected.connect(_on_surface_loot)
	_outdoors.add_child(surface_resources)
	if "--smoke" in args:
		surface_resources.rng.seed = 741829
	surface_resources.populate()
	for animal in animals:
		animal.set_navigation(navigation)
	_plant_initial_garden()
	for argument in args:
		if argument == "--smoke":
			_smoke = true
		elif argument == "--demo":
			_demo = true
		elif argument == "--load":
			_load_requested = true
		elif argument.begins_with("--shot="):
			_shot_path = argument.trim_prefix("--shot=")
		elif argument.begins_with("--mine="):
			_start_mine_depth = clampi(argument.trim_prefix("--mine=").to_int(), 1, MineLayout.FLOOR_COUNT)
	if _smoke:
		_run_smoke()
	elif _shot_path != "":
		_run_shot()
	else:
		if _load_requested and SaveManager.has_save(1):
			_apply_load(SaveManager.load_game(1))
		if _start_mine_depth > 0:
			_travel_to(_start_mine_depth)
		print("GAME_READY")


func _process(delta: float) -> void:
	if is_instance_valid(player) and mine_depth==0 and world_data["bounds"]["half"].x>200:
		var sector:=Vector2i(floori(player.position.x/64),floori(player.position.z/64))
		if sector!=_water_sector:
			_water_sector=sector
			_add_water_obstacles()
	if not _smoke and _shot_path == "":
		if not hud.modal_open() and not _transitioning:
			var season_before: String = state.time.season()
			var rolled: bool = state.advance_hour(delta * GameState.HOURS_PER_DAY / DAY_SECONDS)
			if rolled:
				_finish_natural_day(season_before)
		_update_targeting()
		hud.update_clock()
	if mine_depth > 0:
		mine.paused = hud.modal_open() or _transitioning
		_mine_map_timer -= delta
		if _mine_map_timer <= 0:
			hud.set_navigation(mine.navigation())
			_mine_map_timer = 0.25
	hud.track_position(player.global_position)
	_apply_daylight()


func _unhandled_input(event: InputEvent) -> void:
	if _smoke or _shot_path != "" or _transitioning:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if hud.modal_open() and event.keycode not in [KEY_M, KEY_ESCAPE, KEY_TAB]:
			return
		match event.keycode:
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9:
				_select_tool(event.keycode - KEY_1)
			KEY_R:
				var next := GameState.CROP_ORDER.find(selected_seed) + 1
				selected_seed = GameState.CROP_ORDER[next % GameState.CROP_ORDER.size()]
				player.set_tool(TOOLS[tool_index], selected_seed)
				hud.select_slot(tool_index, selected_seed, state.seeds[selected_seed])
				hud.show_toast("选中种子：" + GameState.crop_label(selected_seed))
			KEY_E:
				_update_targeting()
				_interact()
			KEY_SPACE:
				_use_tool()
			KEY_Q:
				_eat_ration()
			KEY_TAB:
				hud.toggle_inventory()
			KEY_M:
				hud.toggle_map()
			KEY_F5:
				SaveManager.save_game(1, _save_payload())
				hud.show_toast("已保存 · 第 %d 天 %s" % [state.day, state.time.season()])
			KEY_F9:
				_apply_load(SaveManager.load_game(1))
			KEY_ESCAPE:
				hud.dismiss_panels()
				_cancel_fence()
	elif event is InputEventMouseButton and event.pressed and not hud.modal_open():
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			player.zoom_index = maxi(0, player.zoom_index - 1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			player.zoom_index = mini(player.zoom_levels.size() - 1, player.zoom_index + 1)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			var ray_from := _camera.project_ray_origin(event.position)
			var ray_direction := _camera.project_ray_normal(event.position)
			var point: Variant = Plane(Vector3.UP, 0.7).intersects_ray(ray_from, ray_direction)
			if point != null and not player.acting:
				player.face_point(point)
			_use_tool()


func _select_tool(index: int) -> void:
	_cancel_fence()
	tool_index = clampi(index, 0, TOOLS.size() - 1)
	player.set_tool(TOOLS[tool_index], selected_seed)
	hud.select_slot(tool_index, selected_seed, state.seeds[selected_seed])


func _update_targeting() -> void:
	## 目标解析统一在 InteractionSystem；主场景只保留 focus 缓存。
	focus = _interaction.update_targeting()


func _interact() -> void:
	_interaction.interact()


func _create_pasture(rect: Rect2) -> Node3D:
	var enclosure := Pasture.new()
	enclosure.name = "Pasture_%d" % pastures.size()
	_outdoors.add_child(enclosure)
	enclosure.setup(rect)
	pastures.append(enclosure)
	tiles.map.add_pasture(rect)
	tiles.block_rect(rect.grow(0.25))
	return enclosure


func _pasture_rect(key: Vector2i) -> Rect2:
	var a: Vector3 = tiles.center_of(_fence_start)
	var b: Vector3 = tiles.center_of(key)
	return Rect2(Vector2(minf(a.x, b.x), minf(a.z, b.z)), Vector2(absf(a.x - b.x), absf(a.z - b.z)))


func _can_place_pasture(rect: Rect2) -> bool:
	if rect.size.x < 6 or rect.size.y < 6 or rect.size.x > 28 or rect.size.y > 28:
		return false
	for x in range(int(rect.position.x), int(rect.end.x) + 1, 2):
		for z in range(int(rect.position.y), int(rect.end.y) + 1, 2):
			var key: Vector2i = tiles.key_of(Vector3(x, 0, z))
			if not tiles.is_open(key) or tiles.has_tile(key):
				return false
	return true


func _place_fence_corner(key: Vector2i) -> void:
	if _fence_start == null:
		if not tiles.is_open(key):
			hud.show_toast("在平坦的空草地上选择牧场位置")
			return
		_fence_start = key
		return
	var rect := _pasture_rect(key)
	if not _can_place_pasture(rect):
		hud.show_toast("牧场每边需 6–28 米，避开道路、建筑和田块")
		return
	_create_pasture(rect)
	_cancel_fence()
	hud.show_toast("牧场围好了，南侧留有大门和食槽")


func _update_fence_preview(key: Vector2i) -> void:
	if _fence_start == null:
		return
	if _fence_preview == null:
		_fence_preview = MeshInstance3D.new()
		_fence_preview.mesh = BoxMesh.new()
		var material := StandardMaterial3D.new()
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color = Color(0.95, 0.80, 0.42, 0.25)
		_fence_preview.material_override = material
		_outdoors.add_child(_fence_preview)
	var rect := _pasture_rect(key)
	(_fence_preview.mesh as BoxMesh).size = Vector3(maxf(0.1, rect.size.x), 0.03, maxf(0.1, rect.size.y))
	_fence_preview.position = Vector3(rect.get_center().x, 0.15, rect.get_center().y)


func _cancel_fence() -> void:
	_fence_start = null
	if is_instance_valid(_fence_preview):
		_fence_preview.queue_free()
	_fence_preview = null


func _sleep() -> void:
	hud.fade_sleep(func(): _do_sleep_and_greet())


func _do_sleep_and_greet() -> void:
	_do_sleep()
	hud.show_toast("第 %d 天的早晨" % state.day)


func _finish_natural_day(season_before: String) -> void:
	## 深夜 02:00 自然日切：结算但不触发睡眠恢复。
	_pass_day(season_before, false)


func _pass_day(season_before: String, sleep_recovery: bool) -> void:
	## 日切编排：广播 day_ended → 结算（生长/产出/资源）→ 季节/新一天事件。
	var bus := EventBus.instance()
	bus.day_ended.emit(state.day)
	if sleep_recovery:
		state.sleep_to_next_day()
	_apply_rollover()
	if state.time.season() != season_before:
		bus.season_changed.emit(state.time.season())
	if sleep_recovery:
		bus.player_slept.emit()
	bus.day_started.emit(state.day)


func _autosave() -> void:
	if _smoke or _shot_path != "":
		return
	SaveManager.save_game(1, _save_payload())


func _mine_state_payload() -> Dictionary:
	var floors := {}
	for depth: int in _mine_floors:
		floors[str(depth)] = _mine_floors[depth].to_dict()
	return {"depth": mine_depth, "floors": floors}


func _on_forest_tree_broken(species: String, at: Vector3) -> void:
	# 分块森林的战利品走与地表树相同的掉落通道。
	var loot: Dictionary = surface_resources.roll_tree_loot(true)
	var offset := 0
	for kind: String in loot:
		surface_resources.spawn_drop(kind, loot[kind], at + Vector3(offset * 0.55, 0, 0.30))
		offset += 1


func _save_payload() -> Dictionary:
	## 存档内容代表游戏世界状态，而不是场景树（V2 PRD 第 28 节）。
	var clock_data: Dictionary = state.time.to_dict()
	clock_data["season"] = state.time.season()
	var animals_data := []
	for animal in animals:
		animals_data.append(animal.data.to_dict())
	var troughs := []
	for enclosure in pastures:
		troughs.append({"filled": enclosure.trough.filled})
	return {
		"version": 1,
		"map": {"id": tiles.map.map_id, "revision": tiles.map.revision},
		"clock": clock_data,
		"economy": state.to_dict(),
		"player": {"position": [player.global_position.x, player.global_position.z], "zoom_index": player.zoom_index},
		"farm": tiles.farm.to_dict(),
		"pastures": tiles.map.to_dict(),
		"animals": animals_data,
		"troughs": troughs,
		"surface": surface_resources.to_dict(),
		"forest": scenery.to_dict() if scenery != null else {"removed": []},
		"mine": _mine_state_payload(),
	}


func _apply_load(saved: Dictionary) -> void:
	if not saved.get("ok", false):
		hud.show_toast("读取存档失败：" + saved.get("error", "未知错误"))
		return
	var restore: Dictionary = MapRestore.plan(saved, world_data)
	if not restore.get("ok", false):
		hud.show_toast(restore["error"])
		return
	if mine_depth > 0:
		_switch_map(0)
	state.time.from_dict(restore.get("clock", {}))
	state.from_dict(restore.get("economy", {}))
	tiles.farm.from_dict(restore.get("farm", {}))
	# 读档重建围栏和占地，避免重复读取时残留旧牧场及视图。
	for enclosure in pastures:
		_outdoors.remove_child(enclosure)
		enclosure.queue_free()
	pastures.clear()
	tiles.map.pastures.clear()
	tiles.map.load_from_world(world_data)
	var scenery:=_outdoors.get_node_or_null("StreamedScenery")
	if scenery!=null:scenery.reset()
	for entry: Array in restore["pastures"]["pastures"]:
		_create_pasture(Rect2(entry[0], entry[1], entry[2], entry[3]))
	trough = pastures[0].trough
	tiles.restore_views()
	# WORLD-01：地表资源/掉落物与分块森林按存档重建，再执行田块/圈地冲突清理。
	if restore.has("surface"):
		surface_resources.apply_state(restore["surface"])
	if scenery != null and restore.has("forest"):
		scenery.farm_tiles = tiles.farm
		scenery.apply_state(restore["forest"])
	_pending_mine_state = restore.get("mine", {})
	for depth: int in _mine_floors:
		if _pending_mine_state.get("floors", {}).has(str(depth)):
			_mine_floors[depth].apply_state(_pending_mine_state["floors"][str(depth)])
	# 初始资源不能覆盖存档中的田块/圈地。清理的是加载时重新生成的资源。
	for resource: Node3D in surface_resources.resources.duplicate():
		var at := Vector2(resource.position.x, resource.position.z)
		var conflicts := false
		for key: Vector2i in tiles.farm.tiles:
			if at.distance_to(Vector2(key) * 2.0) < resource.occupied_radius() + 1.5:
				conflicts = true
				break
		for rect: Rect2 in tiles.map.pastures:
			if rect.grow(1.0).has_point(at):
				conflicts = true
		if conflicts:
			surface_resources.resources.erase(resource)
			surface_resources.remove_child(resource)
			resource.queue_free()
		else:
			tiles.occupy_resource(resource.get_instance_id(), at, resource.occupied_radius())
	var animals_data: Array = restore.get("animals", [])
	for index in range(animals.size()):
		var animal: Node3D = animals[index]
		if index < animals_data.size():
			animal.data.from_dict(animals_data[index])
		var home_index: int = clampi(animal.data.home_index, 0, pastures.size() - 1)
		animal.pasture = pastures[home_index].interior
		pastures[home_index].animals.append(animal)
		if not animal.pasture.grow(-0.8).has_point(Vector2(animal.position.x, animal.position.z)):
			animal.position = pastures[home_index].random_point()
		animal.set_navigation(navigation)
	var troughs: Array = restore.get("troughs", [])
	for index in range(mini(troughs.size(), pastures.size())):
		pastures[index].trough.set_filled(bool(troughs[index].get("filled", false)))
	var pos: Array = restore.get("player", {}).get("position", [])
	var arrival: Vector3 = landmarks["spawn"]
	if pos.size() == 2:
		arrival = Vector3(float(pos[0]), 0.0, float(pos[1]))
	if not tiles.map.is_walkable(Vector2(arrival.x, arrival.z), 0.4):
		arrival = navigation.nearest_open(arrival, 12.0)
		if not is_finite(arrival.x):
			arrival = landmarks["spawn"]
	player.teleport(arrival)
	player.zoom_index = clampi(restore.get("player", {}).get("zoom_index", 3), 0, player.zoom_levels.size() - 1)
	# 存档在矿场时回到对应层与原位置；地表传送被矿内坐标跳过。
	var saved_mine_depth := int(restore.get("mine", {}).get("depth", 0))
	if saved_mine_depth > 0:
		_switch_map(saved_mine_depth, "entry")
		_finish_transition()
		if pos.size() == 2:
			player.teleport(Vector3(float(pos[0]), 0.0, float(pos[1])))
	hud.refresh()
	var notice := "已读取存档 · 第 %d 天 %s" % [state.day, state.time.season()]
	if restore["relocated"] > 0:
		notice += " · %d 处旧田地/牧场已迁至空地" % restore["relocated"]
	if saved_mine_depth > 0:
		notice += " · 矿场第 %d 层进度已恢复" % saved_mine_depth
	hud.show_toast(notice)


func _apply_rollover() -> void:
	tiles.rollover()
	surface_resources.on_day_rollover(state.day)
	for animal in animals:
		animal.on_new_day()
	var rng := RandomNumberGenerator.new()
	rng.seed = state.day * 977 + 13
	for enclosure in pastures:
		if not enclosure.trough.filled:
			continue
		var pasture: Rect2 = enclosure.interior
		for animal in enclosure.animals:
			var pickup := Pickup.new()
			pickup.setup(animal.product_kind())
			pickup.position = Vector3(
				rng.randf_range(pasture.position.x + 1.2, pasture.end.x - 1.2), 0,
				rng.randf_range(pasture.position.y + 1.2, pasture.end.y - 2.2)
			)
			_outdoors.add_child(pickup)
			pickups.append(pickup)
		enclosure.trough.set_filled(false)
	hud.refresh()


func _do_sleep() -> void:
	_pass_day(state.time.season(), true)
	_autosave()


func _surface_actors() -> Array:
	var result := animals + pickups
	if mine_depth == 0:
		result.append(player)
	return result


func _plant_sapling(at: Vector2) -> void:
	if player.acting or mine_depth > 0:
		return
	if state.forestry["sapling"] <= 0:
		hud.show_toast("树苗用完了 · 砍成年树有 30% 的机会掉落")
		return
	if Vector2(player.global_position.x, player.global_position.z).distance_to(at) > 3.2 or surface_resources.plant_sapling(at) == null:
		hud.show_toast("这里无法种树 · 选择前方空草地，避开耕地和道路")
		return
	state.forestry["sapling"] -= 1
	player.start_act()
	hud.refresh()
	hud.show_toast("种下树苗 · 三个清晨后长大 · 无需浇水")
	_update_targeting()


func _on_surface_loot(kind: String, amount: int) -> void:
	var label := ""
	if kind in state.forestry:
		state.forestry[kind] += amount
		label = "木材" if kind == "wood" else "树苗"
	else:
		state.minerals[kind] += amount
		label = GameState.MINERALS[kind]["label"]
	hud.refresh()
	hud.show_toast("%s +%d" % [label, amount])


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
	_environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	_environment.tonemap_exposure = 0.92
	_environment.ssao_enabled = true
	_environment.ssao_radius = 0.74
	_environment.ssao_intensity = 1.18
	_environment.ssao_power = 1.32
	_environment.ssao_detail = 0.70
	_environment.ssao_light_affect = 0.35
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
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	add_child(_sun)
	_fill = DirectionalLight3D.new()
	_fill.rotation_degrees = Vector3(-29, 145, 0)
	_fill.light_color = Color("#d7ebf1")
	_fill.light_energy = 0.08
	add_child(_fill)
	for entry in world_data["lights"] + [Vector3(-29.5, 2.1, -13.3), Vector3(21, 2, -15.1)]:
		var lamp := OmniLight3D.new()
		lamp.position = entry
		lamp.light_color = Color("#ffc372")
		lamp.light_energy = 0.0
		lamp.omni_range = 6.5
		lamp.omni_attenuation = 1.35
		lamp.shadow_enabled = false
		lamp.light_size = 0.22
		_outdoors.add_child(lamp)
		_night_lights.append(lamp)


func _apply_daylight() -> void:
	if mine_depth > 0:
		var palette: Dictionary = MineLayout.theme(mine_depth)
		_environment.background_color = Color("#262b36")
		_environment.ambient_light_color = palette["ambient"]
		_environment.ambient_light_energy = 0.46
		_environment.glow_enabled = true
		_sun.light_color = palette["ambient"]
		_sun.light_energy = 0.38
		_sun.rotation_degrees = Vector3(-67, -25, 0)
		_fill.light_color = Color("#cfcedd")
		_fill.light_energy = 0.18
		return
	_fill.light_color = Color("#d7ebf1")
	_fill.light_energy = 0.08
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
		_outdoors.add_child(body)


func _add_water_obstacles() -> void:
	var previous:=_outdoors.get_node_or_null("WaterBoundaries")
	if previous!=null:previous.free()
	var water_body := StaticBody3D.new()
	water_body.name = "WaterBoundaries"
	var collision_area:=Rect2()
	if world_data["bounds"]["half"].x>200:
		var at:Vector3=player.position if is_instance_valid(player) else landmarks["spawn"]
		collision_area=Rect2(Vector2(at.x,at.z)-Vector2(70,70),Vector2(140,140))
	for rect: Rect2 in tiles.map.water_collision_rects(collision_area):
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(rect.size.x, 2, rect.size.y)
		shape.shape = box
		shape.position = Vector3(rect.get_center().x, 0.5, rect.get_center().y)
		water_body.add_child(shape)
	_outdoors.add_child(water_body)


func _sync_player_lock() -> void:
	player.locked = hud.modal_open() or _transitioning
	if player.locked:
		player.cancel_action()
	if is_instance_valid(mine):
		mine.paused = player.locked
	if is_instance_valid(surface_resources):
		surface_resources.paused = player.locked or mine_depth > 0


func _interact_mine() -> void:
	match focus.get("kind"):
		"ore", "monster":
			if is_instance_valid(focus.get("node")) and not player.acting:
				player.face_point(focus["node"].global_position)
			_use_tool()
		"mine_up":
			_travel_to(mine_depth - 1, "from_below")
		"mine_down":
			if mine.descent_open:
				_travel_to(mine_depth + 1)
		"mine_lift":
			hud.open_mine_travel(mine_depth)
		"mine_camp":
			if not mine.camp_used:
				mine.camp_used = true
				state.health = GameState.MAX_HEALTH
				state.rations = maxi(state.rations, 3)
				hud.refresh()
				hud.show_toast("营地休整完毕 · 生命恢复 · 口粮补足 3 份")
		"mine_chest":
			if mine.open_chest():
				state.mine_completed = true
				state.coins += 150
				hud.refresh()
				hud.show_toast("完成 10 层探索！水晶 ×12 · 铁矿 ×8 · 金币 +150")
				_refresh_mine_hud()
		"mine_sealed":
			hud.show_toast(focus.get("hint", "按 6 装备镐子"))
		_:
			_use_tool()


func _use_tool() -> void:
	if hud.modal_open() or _transitioning:
		return
	if TOOLS[tool_index] in ["sword", "pickaxe", "axe"]:
		player.begin_swing()
	elif mine_depth > 0:
		hud.show_toast("按 6 使用镐子采矿，按 7 使用短剑战斗")
	elif TOOLS[tool_index] == "sapling":
		_update_targeting()
		_interact()


func _on_tool_hit(tool: String) -> void:
	if _transitioning or hud.modal_open():
		return
	if mine_depth > 0:
		mine.swing(tool, player.global_position, player.facing())
	else:
		var dealt: int = surface_resources.swing(tool, player.global_position, player.facing())
		if dealt <= 0 and scenery != null:
			scenery.swing(tool, player.global_position, player.facing())


func _eat_ration() -> void:
	var restored: int = state.eat_ration()
	if restored > 0:
		Feedback.number(mine if mine_depth > 0 else _outdoors, player.global_position + Vector3(0, 1.7, 0), "+%d" % restored, Color("#a6e0a0"))
		hud.show_toast("吃了一份口粮，恢复 %d 生命" % restored)
	elif state.health == GameState.MAX_HEALTH:
		hud.show_toast("生命已满，口粮留待需要时使用")
	else:
		hud.show_toast("口粮用完了 · 第 5 层营地或回农舍休息可补充")
	hud.refresh()


func _on_player_attacked(amount: int, source: Vector3) -> void:
	if mine_depth <= 0 or _transitioning or not player.receive_hit(source):
		return
	var dealt := mini(state.health, amount)
	state.health -= dealt
	Feedback.number(mine, player.global_position + Vector3(0, 1.7, 0), "-%d" % dealt, Color("#ff9c84"))
	hud.refresh_health()
	if state.health <= 0:
		_recovery_pending = true
		_travel_to(0)


func _on_mine_loot(kind: String, count: int) -> void:
	state.minerals[kind] += count
	hud.refresh()
	hud.show_toast("%s +%d" % [GameState.MINERALS[kind]["label"], count])


func _on_travel_requested(depth: int) -> void:
	if depth not in [0, 1, 5, 10] or (depth > 1 and state.deepest_mine_floor < depth):
		return
	_travel_to(depth)


func _travel_to(depth: int, arrival: String = "entry") -> void:
	if _transitioning or depth < 0 or depth > MineLayout.FLOOR_COUNT or depth == mine_depth:
		return
	_transitioning = true
	hud.dismiss_panels()
	_cancel_fence()
	_sync_player_lock()
	if _smoke or _shot_path != "":
		_switch_map(depth, arrival)
		_finish_transition()
	else:
		hud.fade_transition(func(): _switch_map(depth, arrival), _finish_transition)


func _switch_map(depth: int, arrival: String = "entry") -> void:
	if mine_depth == 0 and depth > 0:
		_surface_tool = tool_index
		_surface_zoom = player.zoom_index
		_surface_return = landmarks["mine_door"] + Vector3(0, 0, 1.4)
		_select_tool(5)
	if mine_depth > 0:
		_mine_zoom = player.zoom_index
		mine.hide()
		mine.process_mode = Node.PROCESS_MODE_DISABLED
		mine.paused = true
	_outdoors.visible = depth == 0
	_outdoors.process_mode = Node.PROCESS_MODE_INHERIT if depth == 0 else Node.PROCESS_MODE_DISABLED
	EventBus.instance().map_switched.emit(mine_depth, depth)
	mine_depth = depth
	if depth == 0:
		mine = null
		player.set_bounds(world_data["bounds"]["half"], world_data["bounds"]["pow"])
		player.zoom_index = _surface_zoom
		_select_tool(_surface_tool)
		player.teleport(_surface_return)
		player.set_underground(false)
		player.surface_map = tiles.map
		hud.set_navigation(world_data["navigation"])
		hud.set_mine_status(0)
		if _recovery_pending:
			state.health = 60
			_recovery_pending = false
			hud.show_toast("你被送回矿口 · 生命恢复至 60 · 已收集矿物保留")
		else:
			hud.show_toast("回到微风山谷 · 矿场进度已保留")
	else:
		if not _mine_floors.has(depth):
			var floor_node := MineFloor.new()
			floor_node.name = "MineFloor_%02d" % depth
			floor_node.depth = depth
			floor_node.player = player
			floor_node.notice.connect(func(message: String): hud.show_toast(message))
			floor_node.loot_collected.connect(_on_mine_loot)
			floor_node.player_attacked.connect(_on_player_attacked)
			floor_node.changed.connect(_refresh_mine_hud)
			_mine_root.add_child(floor_node)
			_mine_floors[depth] = floor_node
			if _pending_mine_state.get("floors", {}).has(str(depth)):
				floor_node.apply_state(_pending_mine_state["floors"][str(depth)])
		mine = _mine_floors[depth]
		mine.show()
		mine.process_mode = Node.PROCESS_MODE_INHERIT
		mine.paused = _transitioning
		player.set_bounds(Vector2(MineLayout.GRID) * MineLayout.CELL * 0.5, 24)
		player.zoom_index = _mine_zoom
		player.teleport(mine.down_position() + Vector3(0, 0, 2.5) if arrival == "from_below" else mine.spawn_position())
		player.face_point(player.global_position + Vector3.FORWARD)
		player.set_underground(true)
		player.surface_map = null
		state.deepest_mine_floor = maxi(state.deepest_mine_floor, depth)
		hud.set_navigation(mine.navigation())
		_refresh_mine_hud()
		hud.show_toast("第 %d / 10 层 · %s%s" % [depth, MineLayout.TITLES[depth - 1], " · 升降机已接通" if depth in [5, 10] else ""])
	hud.refresh()
	focus = {}
	_apply_daylight()


func _finish_transition() -> void:
	_transitioning = false
	_sync_player_lock()
	_update_targeting()


func _refresh_mine_hud() -> void:
	if mine_depth <= 0 or not is_instance_valid(mine):
		return
	var objective := "挖开北端裂隙岩石，寻找向下的梯子"
	if mine_depth == 10:
		objective = "地心宝箱已领取 · 升降机可返回小镇" if mine.chest_opened else ("晶室已清理 · 前往北端领取宝箱" if mine.monsters.is_empty() else "击败晶室怪物，解锁宝箱 · 剩余 %d" % mine.monsters.size())
	elif mine_depth == 5:
		objective = "安全营地 · 床铺休整 · 升降机已接通"
	elif mine.descent_open:
		objective = "已发现下行梯 · E 进入第 %d 层" % (mine_depth + 1)
	hud.set_mine_status(mine_depth, MineLayout.TITLES[mine_depth - 1], objective)
	hud.set_navigation(mine.navigation())


# ---------- 自动化验证 ----------

var _smoke_failures: Array[String] = []


func _check(step: String, condition: bool) -> void:
	print("SMOKE %s %s" % [step, "OK" if condition else "FAIL"])
	if not condition:
		_smoke_failures.append(step)


func _run_smoke() -> void:
	print("SMOKE_BEGIN")
	for animal in animals:
		animal.set_process(false)
	await _frames(3)
	_check("boot-coins", state.coins == 20 and state.seeds["radish"] == 6)
	_check("world-ready", animals.size() == 7 and world_data["sites"].size() == world_data["definition"]["buildings"].size())
	var clear: Vector2 = preload("res://scripts/tests/forestry_checks.gd").find_clear(self)
	_check("smoke-farm-site-available", clear.is_finite())
	if not clear.is_finite():
		get_tree().quit(1)
		return
	var key: Vector2i = tiles.key_of(Vector3(clear.x, 0, clear.y))
	player.global_position = tiles.center_of(key) + Vector3(0, 0, 0.3)
	await _frames(2)
	_select_tool(1)
	_update_targeting()
	_interact()
	var plot: Node3D = tiles.node(key)
	_check("till", plot != null and plot.state == "tilled")
	if plot == null:
		get_tree().quit(1)
		return
	_select_tool(3)
	_update_targeting()
	_interact()
	_check("plant", plot.state == "planted" and plot.crop_kind == "radish" and state.seeds["radish"] == 5)
	var seed_count: int = state.seeds["radish"]
	_interact()
	_check("invalid-plant-keeps-seeds", state.seeds["radish"] == seed_count)
	_select_tool(2)
	_update_targeting()
	_interact()
	_check("water", plot.watered)
	plot.on_day_rollover()
	_update_targeting()
	_interact()
	plot.on_day_rollover()
	_check("grow", plot.is_mature() and plot.stage == 2 and plot.get_node("MatureRing").visible)
	_select_tool(0)
	_update_targeting()
	_interact()
	_check("harvest", state.harvest["radish"] == 1 and plot.state == "tilled")
	player.global_position = landmarks["shop_door"] + Vector3(0, 0, 0.6)
	await _frames(2)
	_update_targeting()
	_interact()
	_check("shop-open", hud.shop_open)
	_on_sell()
	_check("sell", state.coins == 28)
	hud.close_shop()
	_check("shop-close", not hud.shop_open and not player.locked)
	player.global_position = trough.global_position + Vector3(0, 0, 0.6)
	await _frames(2)
	_update_targeting()
	_interact()
	_check("trough-fill", trough.filled)
	var cow: Node3D = animals[0]
	player.global_position = cow.global_position + Vector3(0, 0, 0.6)
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
		player.global_position = milk_pickup.global_position + Vector3(0, 0, 0.2)
		await _frames(2)
		_update_targeting()
		_interact()
	_check("collect", state.products["milk"] == 1)
	_on_sell()
	_check("sell-ranch", state.coins == 42)
	hud.toggle_map()
	_check("map-opens-locks-player", hud.map_open and player.locked)
	hud.dismiss_panels()
	_check("map-closes-unlocks-player", not hud.map_open and not player.locked)
	await _verify_world()
	await preload("res://scripts/tests/mine_checks.gd").run(self)
	await preload("res://scripts/tests/forestry_checks.gd").run(self)
	var result := "PASS" if _smoke_failures.is_empty() else "FAIL " + ",".join(_smoke_failures)
	print("SMOKE_RESULT " + result)
	get_tree().quit(0 if _smoke_failures.is_empty() else 1)


func _run_shot() -> void:
	if _demo:
		_build_demo_state()
	if _start_mine_depth > 0:
		_travel_to(_start_mine_depth)
		for monster in mine.monsters:
			monster.behavior_enabled = false
	state.clock = 10.0
	var overview := false
	var map_view := false
	var mine_overview := false
	var combat_view := false
	var equipment_view := false
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--at="):
			var pair := argument.trim_prefix("--at=").split(",")
			if pair.size() == 2:
				player.global_position = Vector3(pair[0].to_float(), 0, pair[1].to_float())
		elif argument == "--clean":
			hud.hide()
		elif argument == "--view=overview":
			overview = true
		elif argument == "--view=map":
			map_view = true
		elif argument == "--view=mine-overview":
			mine_overview = true
		elif argument == "--view=combat":
			combat_view = true
		elif argument == "--view=equipment":
			equipment_view = true
		elif argument.begins_with("--tool="):
			var chosen := TOOLS.find(argument.trim_prefix("--tool="))
			if chosen >= 0:
				_select_tool(chosen)
		elif argument.begins_with("--zoom="):
			var zoom := argument.trim_prefix("--zoom=").to_float()
			for i in range(player.zoom_levels.size()):
				if absf(player.zoom_levels[i] - zoom) < 0.02:
					player.zoom_index = i
		elif argument.begins_with("--hour="):
			state.clock = argument.trim_prefix("--hour=").to_float()
	_update_targeting()
	hud.refresh()
	if mine_depth > 0 and (combat_view or equipment_view):
		player.teleport(Vector3(0, 0, 3.6))
		if combat_view:
			_select_tool(6)
			mine.monsters[0].position = Vector3(0.4, 0, 1.65)
			player.face_point(mine.monsters[0].position)
			player.zoom_index = 0
		else:
			player.face_point(player.global_position + Vector3(0.45, 0, 1))
			player.camera = null
			_camera.global_position = player.global_position + Vector3(2.7, 2.4, 4.8)
			_camera.look_at(player.global_position + Vector3(0, 1, 0))
		_update_targeting()
	if mine_overview and mine_depth > 0:
		player.camera = null
		_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		_camera.size = 56.0
		_camera.global_position = Vector3(0, 60, 42)
		_camera.look_at(Vector3.ZERO)
	elif overview:
		player.camera = null
		_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		_camera.size = world_data["bounds"]["half"].x*2.2
		_camera.far=6000
		_camera.global_position = Vector3(0, 3100, 2200) if world_data["bounds"]["half"].x>200 else Vector3(0,180,122)
		_camera.look_at(Vector3(0, 0, -4))
		hud.hide()
	elif map_view:
		hud.toggle_map()
	for frame in range(35):
		await get_tree().process_frame
	var sample_start := Time.get_ticks_usec()
	for frame in range(60):
		await get_tree().process_frame
	var sample_fps := 60000000.0 / maxf(1, Time.get_ticks_usec() - sample_start)
	hud.clear_toast()
	if combat_view and mine_depth > 0:
		player.attack_cooldown = 0
		_use_tool()
		await _frames(20)
		_update_targeting()
	await RenderingServer.frame_post_draw
	var picture := get_viewport().get_texture().get_image()
	var result := picture.save_png(_shot_path)
	print("SHOT_OK " + _shot_path + " " + error_string(result) + " " + str(picture.get_size()))
	var active_batches: int = mine.get_node("CavernShell").get_meta("static_batches", 0) if mine_depth > 0 else world_data["root"].get_meta("static_batches", 0)
	print("RENDER_INFO static_batches=%d draws=%d objects=%d primitives=%d sampled_fps=%.1f" % [active_batches, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), sample_fps])
	get_tree().quit(0 if result == OK else 1)


func _plant_initial_garden() -> void:
	# Four tended beds are part of every new game, with real growth and harvest state.
	var beds := [
		{"from": Vector2i(-20,4), "size":Vector2i(4,4),"crop":"wheat","stage":3},
		{"from": Vector2i(-20,9), "size":Vector2i(4,4),"crop":"pumpkin","stage":3},
		{"from": Vector2i(-12,7), "size":Vector2i(3,3),"crop":"strawberry","stage":2},
		{"from": Vector2i(-14,11), "size":Vector2i(5,2),"crop":"radish","stage":2},
	]
	if world_data["definition"].has("starter_garden"):
		var garden:Rect2=world_data["definition"]["starter_garden"]
		var base:=Vector2i((garden.position/2.0).ceil())
		beds=[{"from":base,"size":Vector2i(4,4),"crop":"wheat","stage":3},{"from":base+Vector2i(0,5),"size":Vector2i(4,4),"crop":"pumpkin","stage":3},{"from":base+Vector2i(5,0),"size":Vector2i(4,4),"crop":"radish","stage":2},{"from":base+Vector2i(5,5),"size":Vector2i(4,4),"crop":"strawberry","stage":2}]
	for bed:Dictionary in beds:
		for z in range(bed["size"].y):
			for x in range(bed["size"].x):
				var key:Vector2i=bed["from"]+Vector2i(x,z)
				if not tiles.till(key): continue
				tiles.plant(key,bed["crop"])
				tiles.node(key).debug_set_stage(bed["stage"])
				if z%2==1: tiles.water(key)


func _build_demo_state() -> void:
	var recipes := [["radish", 0], ["strawberry", 1], ["wheat", 3], ["pumpkin", 4]]
	for row in range(5):
		for col in range(8):
			var key := Vector2i(-20 + col, 3 + row * 2)
			if not tiles.till(key):
				continue
			var recipe: Array = recipes[(row + col) % recipes.size()]
			tiles.plant(key, recipe[0])
			tiles.node(key).debug_set_stage(recipe[1])
			if recipe[1] < 2:
				tiles.water(key)
	trough.set_filled(true)
	player.global_position = landmarks["spawn"]
	hud.refresh()
	hud.select_slot(tool_index, selected_seed, state.seeds[selected_seed])


func _frames(count: int) -> void:
	for frame in range(count):
		await get_tree().physics_frame


func _verify_world() -> void:
	if world_data["bounds"]["half"].x > 200:
		await preload("res://scripts/tests/surface_world_checks.gd").run(self, _check)
		return
	var space := get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.34
	capsule.height = 1.1
	query.shape = capsule
	query.exclude = [player.get_rid()]
	var reachable := {}
	var open := {}
	var step := 1.5
	# A flood fill from the actual spawn verifies that every front door can be
	# reached without teleporting through a building, fence, lake or mountain.
	for x in range(-63, 64):
		for z in range(-52, 53):
			var at := Vector2(x * step, z * step)
			if pow(absf(at.x) / (world_data["bounds"]["half"].x - 1), 6) + pow(absf(at.y) / (world_data["bounds"]["half"].y - 1), 6) >= 1:
				continue
			query.transform = Transform3D(Basis.IDENTITY, Vector3(at.x, 0.62, at.y))
			if space.intersect_shape(query, 1).is_empty():
				open[Vector2i(x, z)] = true
	var spawn: Vector3 = landmarks["spawn"]
	var start := Vector2i(roundi(spawn.x / step), roundi(spawn.z / step))
	_check("spawn-clear", open.has(start))
	var queue: Array[Vector2i] = [start]
	reachable[start] = true
	var cursor := 0
	while cursor < queue.size():
		var here := queue[cursor]
		cursor += 1
		for direction in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var next: Vector2i = here + direction
			if open.has(next) and not reachable.has(next):
				query.transform = Transform3D(Basis.IDENTITY, Vector3(here.x * step, 0.62, here.y * step))
				query.motion = Vector3(direction.x * step, 0, direction.y * step)
				var sweep := space.cast_motion(query)
				if sweep[0] < 0.999:
					continue
				reachable[next] = true
				queue.append(next)
	query.motion = Vector3.ZERO
	for site: Dictionary in world_data["sites"]:
		var door: Vector2 = site["door"]
		var accessible := false
		for key: Vector2i in reachable:
			if (Vector2(key) * step).distance_to(door) < 1.8:
				accessible = true
				break
		_check("route-" + site["id"], accessible)
		query.transform = Transform3D(Basis.IDENTITY, Vector3(site["position"].x, 0.62, site["position"].y))
		_check("solid-" + site["id"], not space.intersect_shape(query, 1).is_empty())
	var mine_reachable := false
	var mine_door: Vector3 = landmarks["mine_door"]
	for key: Vector2i in reachable:
		if (Vector2(key) * step).distance_to(Vector2(mine_door.x, mine_door.z)) < 2.0:
			mine_reachable = true
			break
	_check("route-mine-entrance", mine_reachable)
	_check("mine-entrance-not-tillable", not tiles.is_open(tiles.key_of(mine_door)))
	_check("farm-gate-connected", reachable.has(Vector2i(-18, 8)))
	_check("pasture-gate-connected", reachable.has(Vector2i(16, 13)))
	_check("expanded-west-accessible", reachable.has(Vector2i(-45, 2)))
	_check("expanded-east-accessible", reachable.has(Vector2i(30, -15)))
	_check("square-not-tillable", not tiles.is_open(tiles.key_of(landmarks["town_square"])))
	_check("lake-not-tillable", not tiles.is_open(Vector2i(world_data["definition"]["lake_center"] / 2.0)))
	_check("rounded-corner-not-tillable", not tiles.is_open(Vector2i(47, 39)))
	_check("outer-meadow-tillable", tiles.is_open(Vector2i(-22, 31)))
	_check("fence-cannot-cover-street", not _can_place_pasture(Rect2(-4, -20, 8, 8)))
	var count := pastures.size()
	var buildable:Variant=null
	for x in range(-29,20):
		for z in range(24,35):
			var candidate:=Rect2(Vector2(x,z)*2,Vector2(8,8))
			if _can_place_pasture(candidate):
				buildable=Vector2i(x,z)
				break
		if buildable!=null:break
	_check("custom-pasture-site-available",buildable!=null)
	if buildable!=null:
		_place_fence_corner(buildable)
		_place_fence_corner(buildable+Vector2i(4,4))
		_check("custom-pasture-built",pastures.size()==count+1 and _fence_start==null)
		_check("pasture-ground-protected",not tiles.is_open(buildable+Vector2i(2,2)))
	for edge in [Vector3(110, 0, 0), Vector3(-110, 0, 0), Vector3(0, 0, 94), Vector3(0, 0, -94)]:
		player.global_position = edge
		await _frames(2)
		var p := player.global_position
		_check("mountain-boundary-%s" % str(edge), pow(absf(p.x) / world_data["bounds"]["half"].x, 6) + pow(absf(p.z) / world_data["bounds"]["half"].y, 6) <= 1.001)
