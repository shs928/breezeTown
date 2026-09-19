extends RefCounted
## 统一交互系统（V2 PRD 第 8.2/M0-05 节）：
## 每帧由主场景调用 update_targeting() 解析 InteractionTarget（focus 字典），
## E/左键时调用 interact() 执行对应动作。目标种类：
## tile / animal / pickup / trough / fence / sapling / surface_resource /
## forage / npc / shop / cottage / mine_entrance / ore / monster / mine_up / mine_down /
## mine_lift / mine_camp / mine_chest / mine_sealed
## 未来 NPC / Door / Chest / FishingSpot 在此注册，不再散落硬编码。

const GameState := preload("res://scripts/game_state.gd")
const ForageDB := preload("res://scripts/data/forage_db.gd")
const InteriorDB := preload("res://scripts/data/interior_db.gd")

var game: Node3D  # 主场景（应用层上下文：tiles/player/hud/state/landmarks...）


func update_targeting() -> Dictionary:
	## 解析当前可交互目标；返回 focus 字典并负责高亮与情境提示。
	var tiles = game.tiles
	var hud = game.hud
	var player = game.player
	var state = game.state
	tiles.set_highlight(null)
	game.surface_resources.clear_focus()
	if game.forage != null:
		game.forage.clear_focus()
	if game.scenery != null:
		game.scenery.clear_focus()
	var focus := {}
	var player_pos: Vector3 = player.global_position
	if hud.modal_open() or game._transitioning:
		hud.set_hint("M / Esc 收起地图" if hud.map_open else "Esc 关闭面板")
		return focus
	if game.mine_depth > 0:
		focus = game.mine.target_at(player_pos, game.TOOLS[game.tool_index])
		hud.set_hint(focus.get("hint", ""))
		return focus
	# INDOOR-01：室内只解析出口门与服务点；值守村民优先（柜台后的店主可交谈）。
	if game.interior_id != "" and game.current_interior != null:
		for npc in game.npcs:
			if is_instance_valid(npc) and npc.is_stationed() and player_pos.distance_to(npc.global_position) < 2.2:
				var npc_hint := "按 E 和 %s（%s）交谈" % [npc.label(), npc.role()]
				focus = {"kind": "npc", "node": npc, "hint": npc_hint}
				hud.set_hint(npc_hint)
				return focus
		focus = game.current_interior.target_at(player_pos)
		hud.set_hint(focus.get("hint", ""))
		return focus
	if player_pos.distance_to(game.landmarks["mine_door"]) <= 2.7:
		focus = {"kind": "mine_entrance"}
		hud.set_hint("E 进入星辉矿场 · 共 10 层 · 6 镐子 / 7 短剑")
		return focus
	# INDOOR-01：可进入建筑的门点（数据驱动；室外 E 进室内，服务在柜台/床铺办理）。
	for site: Dictionary in game.world_data["sites"]:
		if not InteriorDB.has(site["id"]):
			continue
		if player_pos.distance_to(Vector3(site["door"].x, 0, site["door"].y)) <= 2.4:
			focus = {"kind": "building_door", "id": site["id"], "label": site["label"]}
			hud.set_hint("按 E 进入 %s" % site["label"])
			return focus
	var tool: String = game.TOOLS[game.tool_index]
	if tool == "fence":
		var key: Vector2i = tiles.key_of(player_pos)
		focus = {"kind": "fence", "key": key}
		tiles.set_highlight(tiles.center_of(key))
		hud.set_hint("按 E 选择牧场第一角" if game._fence_start == null else "走到对角按 E 围起牧场 · Esc 取消")
		game._update_fence_preview(key)
		return focus
	if tool == "sapling":
		var key: Vector2i = tiles.key_of(player_pos + player.facing() * 2.1)
		var at: Vector3 = tiles.center_of(key)
		var clear: bool = game.surface_resources.can_spawn(Vector2(at.x, at.z), "tree", false)
		focus = {"kind": "sapling", "position": Vector2(at.x, at.z)}
		tiles.set_highlight(at, clear and state.forestry["sapling"] > 0)
		hud.set_hint("树苗已用完 · 用 8 斧头砍成年树，有机会获得树苗" if state.forestry["sapling"] <= 0 else ("E / 左键 种树苗 · 三个清晨后长大 · 需空草地" if clear else "此处无法种树 · 避开耕地、道路、建筑和其他树木"))
		return focus
	# 钓点和鱼漂共用同一处水面采样。
	if tool == "rod" and game.fishing_state == "idle" and game.water_kind_nearby() != "":
		focus = {"kind": "water"}
		hud.set_hint("湖泊钓点" if game.water_kind_nearby() == "lake" else "河流钓点")
		return focus
	if game.fishing_state != "idle":
		focus = {"kind": "fishing"}
		hud.set_hint("")
		return focus
	var resource_focus: Dictionary = game.surface_resources.target_at(player_pos, tool)
	if resource_focus.is_empty() and game.scenery != null:
		resource_focus = game.scenery.target_at(player_pos, tool)
	if not resource_focus.is_empty():
		focus = resource_focus
		hud.set_hint(focus["hint"])
		return focus
	# GATHER-01：采集物徒手可采，优先级低于工具目标、高于捡拾/动物/地块。
	if game.forage != null:
		var forage_focus: Dictionary = game.forage.target_at(player_pos)
		if not forage_focus.is_empty():
			focus = forage_focus
			hud.set_hint(focus["hint"])
			return focus
	# STORE-01：宝箱（共享仓库存取点）与待放置宝箱。
	if game.chests != null:
		var chest_focus: Dictionary = game.chests.target_at(player_pos)
		if not chest_focus.is_empty():
			focus = chest_focus
			hud.set_hint("按 E 打开农场共享仓库")
			return focus
	if state.chests_ready > 0 and game.mine_depth == 0:
		var place_key: Vector2i = tiles.key_of(player_pos + player.facing() * 1.4)
		if tiles.is_open(place_key) and not tiles.has_tile(place_key):
			focus = {"kind": "chest_place", "key": place_key}
			tiles.set_highlight(tiles.center_of(place_key))
			hud.set_hint("按 E 放置宝箱 · 连通农场共享仓库")
			return focus
	# NPC-01：村民交谈，低于门点/工具/采集目标（锚点带门侧偏移，不与进店冲突）。
	for npc in game.npcs:
		if not is_instance_valid(npc):
			continue
		if player_pos.distance_to(npc.global_position) < 2.2:
			var npc_hint := "按 E 和 %s（%s）交谈" % [npc.label(), npc.role()]
			focus = {"kind": "npc", "node": npc, "hint": npc_hint}
			hud.set_hint(npc_hint)
			return focus
	var best_distance := 1.0e9
	for pickup in game.pickups:
		var distance: float = player_pos.distance_to(pickup.global_position)
		if distance < game.PICKUP_RANGE and distance < best_distance:
			best_distance = distance
			focus = {"kind": "pickup", "node": pickup}
	for animal in game.animals:
		var distance: float = player_pos.distance_to(animal.global_position)
		if distance < game.ANIMAL_RANGE and distance < best_distance:
			best_distance = distance
			focus = {"kind": "animal", "node": animal}
	for enclosure in game.pastures:
		var distance: float = player_pos.distance_to(enclosure.trough.global_position)
		if distance < game.TROUGH_RANGE and distance < best_distance:
			best_distance = distance
			focus = {"kind": "trough", "node": enclosure.trough}
	var tile_key: Variant = tiles.nearest_key(player_pos, game.PLOT_RANGE, tool)
	if tile_key != null and player_pos.distance_to(tiles.center_of(tile_key)) < best_distance:
		focus = {"kind": "tile", "key": tile_key}
		tiles.set_highlight(tiles.center_of(tile_key))
	_update_hint(focus, tool)
	return focus


func _update_hint(focus: Dictionary, tool: String) -> void:
	var hud = game.hud
	var player_pos: Vector3 = game.player.global_position
	match focus.get("kind"):
		"tile":
			hud.set_hint("按 E " + {"hand": "收获作物", "hoe": "开垦土地", "can": "浇水", "seed": "播种"}[tool])
		"pickup":
			hud.set_hint("按 E 捡起 %s" % focus["node"].label())
		"animal":
			var animal: Node3D = focus["node"]
			hud.set_hint("今天已经摸过 %s了" % animal.label() if animal.petted_today else "按 E 抚摸 %s" % animal.label())
		"trough":
			hud.set_hint("食槽是满的，明早有产出" if focus["node"].filled else "按 E 填食槽（消耗 1 份饲料）")
		_:
			var hint := "WASD 移动 · Shift 快跑 · M 地图 · 6 采矿 · 8 砍树 · 9 种树 · Tab 背包"
			for site: Dictionary in game.world_data["sites"]:
				if Vector2(player_pos.x, player_pos.z).distance_to(site["door"]) < 3.7:
					hint = site["label"] + " · M 查看山谷地图"
					break
			hud.set_hint(hint)


func interact() -> void:
	## 执行当前 focus 对应的动作。
	if game.hud.modal_open() or game._transitioning:
		return
	if game.mine_depth > 0:
		game._interact_mine()
		return
	var focus: Dictionary = game.focus
	var state = game.state
	var hud = game.hud
	var tiles = game.tiles
	var tool: String = game.TOOLS[game.tool_index]
	match focus.get("kind"):
		"surface_resource":
			var resource: Node3D = focus.get("node")
			if not is_instance_valid(resource) or resource.depleted:
				return
			if tool != resource.required_tool():
				hud.show_toast(focus["hint"])
				return
			if not game.player.acting:
				game.player.face_point(resource.global_position)
			game._use_tool()
		"sapling":
			game._plant_sapling(focus["position"])
		"chunk_tree":
			if tool != "axe":
				hud.show_toast(focus["hint"])
				return
			if not game.player.acting:
				game.player.face_point(focus["position"])
			game._use_tool()
		"mine_entrance":
			if state.deepest_mine_floor >= 5:
				hud.open_mine_travel(0)
			else:
				game._travel_to(1)
		"building_door":
			game._enter_building(focus["id"])
		"interior_exit":
			game._exit_building()
		"interior_service":
			game._interior_service(focus["service"])
		"interior_machine":
			game._interior_machine(focus["machine"])
		"warehouse_chest":
			game.open_warehouse()
		"chest_place":
			game.place_chest(focus["key"])
		"pickup":
			var pickup: Node3D = focus["node"]
			state.add_product(pickup.kind)
			hud.show_toast("捡起 %s ×1" % pickup.label())
			_notify_level(state.gain_xp(5))
			game.pickups.erase(pickup)
			pickup.queue_free()
			hud.refresh()
		"forage":
			var plant: Node3D = focus.get("node")
			if not is_instance_valid(plant):
				return
			var kind: String = game.forage.gather(plant)
			if kind.is_empty():
				return
			state.add_forage(kind)
			hud.show_toast("采集 %s ×1" % ForageDB.label(kind))
			_notify_level(state.gain_xp(5))
			game.player.start_act()
			hud.refresh()
		"npc":
			var npc: Node3D = focus.get("node")
			if is_instance_valid(npc):
				game._open_dialogue(npc)
		"animal":
			var animal: Node3D = focus["node"]
			hud.show_toast("%s 很开心 ♥" % animal.label() if animal.pet() else "%s 今天已经很开心了" % animal.label())
			game.player.start_act()
		"trough":
			game.fill_trough(focus["node"])
		"water":
			_interact_fishing()
		"fishing":
			_interact_fishing()
		"tile":
			_interact_tile(focus["key"], tool)
		"fence":
			game._place_fence_corner(focus["key"])


func _interact_fishing() -> void:
	## LIFE-01 钓鱼：E 在抛竿/拉杆间切换；状态机在 main._tick_fishing 推进。
	if game.fishing_state == "idle":
		game.start_fishing()
	else:
		game._reel_in()


func _notify_level(gained: int) -> void:
	## FARM-01 二轮：升级提示（每级体力上限 +10）。
	if gained > 0:
		game.hud.show_toast("升级到 Lv.%d！体力上限 +%d" % [game.state.level, gained * 10])


func _interact_tile(key: Vector2i, tool: String) -> void:
	## 农事动作：经领域状态裁决，成功后同步表现与界面。
	## FARM-01：工具动作消耗体力；播种做宜种季节裁决；水壶 2 级起一次浇 3×3。
	var game := self.game
	var state = game.state
	var hud = game.hud
	var success := false
	match tool:
		"hoe":
			if not game.spend_tool_energy("hoe"):
				return
			success = game.tiles.till(key)
		"seed":
			if state.seeds[game.selected_seed] <= 0:
				hud.show_toast("种子不够了，去商店买一些")
				return
			if not game.can_plant_now(game.selected_seed):
				return
			if not game.spend_tool_energy("seed"):
				return
			success = game.tiles.plant(key, game.selected_seed)
			if success:
				state.take_seed(game.selected_seed)
				var planted = game.tiles.farm.data_of(key)
				if state.fertilizer > 0 and planted != null:
					# FARM-01 二轮：有肥料则自动施用，收获前每夜多长一阶。
					state.fertilizer -= 1
					planted.fertilized = true
					hud.show_toast("已施肥：%s 成长更快" % GameState.crop_label(game.selected_seed))
				elif planted != null and planted.rotation_pending:
					hud.show_toast("连作 %s 会慢一天成熟，换茬可恢复" % GameState.crop_label(game.selected_seed))
		"can":
			if not game.spend_tool_energy("can"):
				return
			success = game.tiles.water(key)
			if state.tool_level("can") >= 2:
				for offset in [Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2), Vector2i(2, 2), Vector2i(-2, -2), Vector2i(2, -2), Vector2i(-2, 2)]:
					if game.tiles.water(key + offset):
						success = true
		"hand":
			var data = game.tiles.farm.data_of(key)
			var kind: String = game.tiles.harvest(key)
			if kind != "":
				var quality: String = state.roll_harvest_quality(data != null and data.fertilized)
				state.add_harvest(kind, 1, quality)
				var quality_text: String = {"normal": "", "silver": "（银）", "gold": "（金！）"}[quality]
				hud.show_toast("收获 %s×1%s" % [GameState.crop_label(kind), quality_text])
				_notify_level(state.gain_xp(int(GameState.crop_field(kind, "exp"))))
				success = true
	if success:
		game.player.start_act()
		hud.refresh()
		hud.select_slot(game.tool_index, game.selected_seed, state.seeds[game.selected_seed])
