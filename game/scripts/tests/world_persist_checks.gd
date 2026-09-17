extends SceneTree
## WORLD-01 重启持久化专项：阶段 A 修改世界并存档，阶段 B 以新进程读档验证。
## 用法：-- --phase=write / -- --phase=verify （BREEZETOWN_SAVE_ROOT 指向同一目录）
const SaveManager := preload("res://scripts/core/save_manager.gd")
const Definition := preload("res://scripts/data/first_map_definition.gd")
var failures: Array[String] = []
var count := 0
var phase := "write"
var game: Node3D


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--phase="):
			phase = argument.trim_prefix("--phase=")
	create_timer(180).timeout.connect(func(): push_error("WORLD_PERSIST timeout"); quit(1))
	_run.call_deferred()


func check(label: String, value: bool) -> void:
	count += 1
	if not value:
		failures.append(label)
	print("WORLD_PERSIST %s %s" % [label, "OK" if value else "FAIL"])


func _run() -> void:
	root.size = Vector2i(1600, 1000)
	SaveManager.select_world("willow_creek_valley_v1")
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	for i in range(6):
		await process_frame
	if phase == "write":
		await _phase_write()
	else:
		await _phase_verify()
	print("WORLD_PERSIST_RESULT %s %d checks" % ["PASS" if failures.is_empty() else "FAIL " + ",".join(failures), count])
	quit(0 if failures.is_empty() else 1)


func _phase_write() -> void:
	# 1) 砍掉一棵分块森林树（两次斧击）。
	var forest := Definition.point([626, 137])
	game.player.teleport(Vector3(forest.x, 0, forest.y))
	game.scenery._refresh()
	await process_frame
	var registry: Dictionary = game.scenery._registry
	check("forest-tree-loaded-near-player", registry.size() > 0)
	var id: int = registry.keys()[0]
	var entry: Dictionary = registry[id]
	var stable: String = entry["stable"]
	var at: Vector3 = Vector3(entry["position"].x, 0, entry["position"].y)
	var from := at + Vector3(0, 0, 1.6)
	game.scenery.swing("axe", from, Vector3(0, 0, -1))
	check("forest-tree-first-swing-damages", int(game.scenery._registry.get(id, {}).get("hp", 99)) < 36)
	var broken: bool = game.scenery.swing("axe", from, Vector3(0, 0, -1)) >= 18 and not game.scenery._registry.has(id)
	check("forest-tree-breaks-and-unregisters", broken)
	check("forest-tree-wood-dropped", game.surface_resources.drops.size() >= 1)
	# 2) 种一棵树苗。
	var sapling_at := Vector2(forest.x + 30, forest.y + 30)
	var attempts := 0
	while not game.surface_resources.can_spawn(sapling_at, "tree", false) and attempts < 40:
		sapling_at += Vector2(3.7, 2.3)
		attempts += 1
	var sapling: Node3D = game.surface_resources.plant_sapling(sapling_at)
	check("sapling-planted", sapling != null)
	# 3) 开垦并播种一块地。
	var farm_key := Vector2i(-20, 4)
	var tilled: bool = game.tiles.till(farm_key)
	check("tile-tilled", tilled and game.tiles.plant(farm_key, "radish"))
	# 4) 进矿场破坏一块岩石，留在矿场存档。
	game._switch_map(1, "entry")
	game._finish_transition()
	await process_frame
	game.mine.paused = true
	var rock_count: int = game.mine.rocks.size()
	check("mine-floor-has-rocks", rock_count > 0)
	var rock: Node3D = game.mine.rocks[0]
	var cell: Vector2i = rock.cell
	rock.hit(999)
	check("mine-rock-broken", game.mine.rocks.size() == rock_count - 1)
	var saved: Dictionary = SaveManager.save_game(1, game._save_payload())
	check("save-written", saved.get("ok", false))
	var payload: Dictionary = game._save_payload()
	check("save-covers-new-state", payload.has("surface") and payload.has("forest") and payload.get("mine", {}).get("depth", 0) == 1)
	print("WORLD_PERSIST memo stable=%s sapling=(%.1f,%.1f) cell=%s key=%s" % [stable, sapling_at.x, sapling_at.y, [cell.x, cell.y], [farm_key.x, farm_key.y]])


func _phase_verify() -> void:
	var saved: Dictionary = SaveManager.load_game(1)
	check("save-loaded", saved.get("ok", false))
	game._apply_load(saved)
	for i in range(4):
		await process_frame
	# 读取阶段 A 的备忘（同一终端输出人工核对；断言用结构化数据本身）。
	var memo := _memo_from_log()
	# 1) 森林树未复活：稳定 ID 仍在 removed，且未重新注册。
	var removed: Dictionary = game.scenery.removed
	check("forest-removal-persisted", removed.has(memo["stable"]))
	if memo.has("position"):
		game.player.teleport(memo["position"])
		game.scenery._refresh()
		await process_frame
		var still_registered := false
		for key in game.scenery._registry:
			if (game.scenery._registry[key]["stable"] as String) == (memo["stable"] as String):
				still_registered = true
		check("forest-tree-not-reregistered", not still_registered)
	# 2) 树苗仍在且状态完整。
	var sapling_found := false
	for resource in game.surface_resources.resources:
		if resource.planted and resource.stage == 0 and Vector2(resource.position.x, resource.position.z).distance_to(memo["sapling"]) < 0.6:
			sapling_found = true
	check("sapling-persisted", sapling_found)
	# 3) 耕地与作物保留。
	check("farm-tile-persisted", game.tiles.farm.tiles.has(memo["farm_key"]) and game.tiles.farm.tiles[memo["farm_key"]].state == "planted")
	# 4) 矿场：回到第 1 层，岩格未复活。
	check("mine-depth-restored", game.mine_depth == 1)
	var cell_reborn := false
	for rock in game.mine.rocks:
		if rock.cell == memo["mine_cell"]:
			cell_reborn = true
	check("mine-rock-not-reborn", not cell_reborn)
	# 5) 重复读档幂等。
	var again: Dictionary = SaveManager.load_game(1)
	game._apply_load(again)
	for i in range(4):
		await process_frame
	check("double-load-keeps-mine-depth", game.mine_depth == 1)
	check("double-load-keeps-forest-removal", game.scenery.removed.has(memo["stable"]))


func _memo_from_log() -> Dictionary:
	# 阶段数据通过存档本身回传：从 removed/耕地推导，无须跨进程文件。
	var memo := {"stable": ""}
	var saved: Dictionary = SaveManager.load_game(1)
	for stable: String in saved.get("forest", {}).get("removed", []):
		memo["stable"] = stable
	var tiles: Array = saved.get("farm", {}).get("tiles", [])
	for entry: Dictionary in tiles:
		if entry.get("state", "") == "planted" and entry.get("crop", "") == "radish":
			memo["farm_key"] = Vector2i(entry["key"][0], entry["key"][1])
	memo["sapling"] = Vector2(0, 0)
	for entry: Dictionary in saved.get("surface", {}).get("resources", []):
		if entry.get("planted", false) and entry.get("stage", 3) == 0:
			memo["sapling"] = Vector2(entry["position"][0], entry["position"][1])
	var floors: Dictionary = saved.get("mine", {}).get("floors", {})
	var broken: Array = floors.get("1", {}).get("broken", [])
	if not broken.is_empty():
		memo["mine_cell"] = Vector2i(broken[0][0], broken[0][1])
	# removed 树的原始位置无法从存档取回；用果园/森林区中心近似区域验证不复活即可。
	memo["position"] = Vector3(Definition.point([626, 137]).x, 0, Definition.point([626, 137]).y)
	return memo
