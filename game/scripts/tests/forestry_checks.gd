extends RefCounted
## 使用真实主场景验证伐木、种树、刷新的保护边界与矿场隔离。

const Ecology = preload("res://scripts/surface_resources.gd")


static func run(game: Node3D) -> void:
	var forest: Node3D = game.surface_resources
	var player: CharacterBody3D = game.player
	var authored_trees: int = game.world_data["resources"].filter(func(entry: Dictionary): return entry.get("category", "tree") == "tree").size()
	game._check("forest-existing-trees-are-resources", authored_trees > 0 and forest.count_resources("tree") >= authored_trees)
	game._check("surface-ordinary-ore-populated", forest.count_resources("ore") >= 24)
	game._check("surface-ore-whitelist", forest.resources.all(func(resource: Node3D): return resource.category == "tree" or resource.kind in Ecology.SURFACE_ORES))
	var at := find_clear(game)
	var tree: Node3D = forest.try_spawn({"position": at, "category": "tree", "species": "oak"}, false)
	game._check("plant-test-location-available", tree != null)
	if tree == null:
		return
	var key: Vector2i = game.tiles.key_of(tree.position)
	var id := tree.get_instance_id()
	player.teleport(tree.position + Vector3(0, 0, 1.9))
	await game._frames(3)
	game._check("tree-trunk-collides", solid_at(game, tree.position))
	game._check("living-tree-prevents-tilling-and-pasture", not game.tiles.till(key) and not game._can_place_pasture(Rect2(at - Vector2(4, 4), Vector2(8, 8))))
	for tool in ["hand", "hoe", "pickaxe", "sword"]:
		game._check("tree-rejects-" + tool, tree.hit(tool, 18, player.position) == 0 and tree.health == 54)
	game._select_tool(7)
	player.attack_cooldown = 0
	player.face_point(player.position + Vector3.BACK)
	game._check("chop-must-face-tree", forest.swing("axe", player.position, player.facing()) == 0 and tree.health == 54)
	game._check("chop-has-limited-reach", forest.swing("axe", tree.position + Vector3(0, 0, 4), Vector3.FORWARD) == 0)
	game._update_targeting()
	game._check("axe-focus-shows-tree", game.focus.get("node") == tree and "砍伐" in game.hud._hint_label.text)
	var socket_start: Vector3 = player._socket.global_position
	game._interact()
	game._check("axe-enters-swing-with-cooldown", player.acting and not player.begin_swing())
	await game._frames(12)
	game._check("axe-windup-not-instant-hit", tree.health == 54)
	game._check("axe-follows-hand-animation", player._socket.global_position.distance_to(socket_start) > 0.08)
	await game._frames(11)
	game._check("axe-contact-damages-once", tree.health == 36)
	game._check("chop-shows-damage-and-notch", tree._notch.visible and forest.get_children().any(func(node: Node): return node is Label3D and node.text == "18"))
	await game._frames(23)
	game._check("axe-swing-not-repeated", tree.health == 36)
	player.begin_swing()
	await game._frames(5)
	game._select_tool(5)
	await game._frames(40)
	game._check("tool-switch-cancels-pending-chop", tree.health == 36 and not player.acting)
	game._select_tool(7)
	player.begin_swing()
	game.hud.toggle_map()
	await game._frames(40)
	game._check("map-pauses-chopping", player.locked and forest.paused and tree.health == 36 and forest.swing("axe", player.position, player.facing()) == 0)
	game.hud.dismiss_panels()
	game._check("map-resumes-forestry", not player.locked and not forest.paused)
	var barrier := StaticBody3D.new()
	barrier.position = tree.position + Vector3(0, 0.6, 0.95)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.8, 1.2, 0.2)
	shape.shape = box
	barrier.add_child(shape)
	game._outdoors.add_child(barrier)
	await game._frames(2)
	game._check("fences-block-chopping-line", forest.swing("axe", player.position, Vector3.FORWARD) == 0 and tree.health == 36)
	barrier.queue_free()
	await game._frames(2)
	var wood_before: int = game.state.forestry["wood"]
	forest.rng.seed = 90163
	game._update_targeting()
	game._interact()
	await game._frames(43)
	game._check("tree-needs-three-chops", tree.health == 18 and forest.resources.has(tree))
	game._update_targeting()
	game._interact()
	await game._frames(21)
	game._check("tree-falls-and-releases-occupancy", tree.depleted and not forest.resources.has(tree) and not game.tiles.map.resource_blocks.has(id))
	game._check("wood-drops-onto-ground", forest.drops.any(func(drop: Node3D): return drop.kind == "wood" and drop.amount >= 4 and drop.amount <= 7))
	var drops_once: int = forest.drops.size()
	game._check("depleted-tree-cannot-drop-twice", tree.hit("axe", 18, player.position) == 0 and forest.drops.size() == drops_once)
	await game._frames(75)
	game._check("fallen-trunk-collision-removed", not solid_at(game, Vector3(at.x, 0, at.y)))
	game._check("wood-pickup-enters-inventory", game.state.forestry["wood"] >= wood_before + 4 and game.state.forestry["wood"] <= wood_before + 7)
	game._check("cleared-tree-ground-can-be-tilled", game.tiles.till(key))
	await _farmland_checks(game, key)
	await _sapling_checks(game)
	await _ore_checks(game)
	await _map_checks(game)
	_refresh_checks(game)
	_probability_checks(game)
	game.hud.dismiss_panels()
	game._select_tool(0)


static func _farmland_checks(game: Node3D, key: Vector2i) -> void:
	var forest: Node3D = game.surface_resources
	var at := Vector2(key) * 2
	var tile: Node3D = game.tiles.node(key)
	for phase in ["tilled", "planted", "watered", "mature", "harvested"]:
		match phase:
			"planted": game.tiles.plant(key, "radish")
			"watered": game.tiles.water(key)
			"mature": tile.debug_set_stage(2)
			"harvested": game.tiles.harvest(key)
		game._check("no-regrowth-on-" + phase + "-farmland", not forest.can_spawn(at, "tree") and not forest.can_spawn(at, "ore") and forest.plant_sapling(at) == null)
	game._check("farmland-full-footprint-protected", not forest.can_spawn(at + Vector2(1.6, 0), "tree") and not forest.can_spawn(at + Vector2(1.6, 0), "ore"))
	game.player.teleport(Vector3(at.x, 0, at.y + 2))
	game.state.forestry["sapling"] = 2
	game.player.cancel_action()
	game._plant_sapling(at)
	game._check("invalid-planting-keeps-sapling", game.state.forestry["sapling"] == 2)
	for category in ["tree", "ore"]:
		var protected := true
		for blocked in [game.world_data["definition"]["square"].get_center(), game.world_data["sites"][0]["position"], game.world_data["definition"]["lake_center"], game.world_data["pasture"].get_center(), game.world_data["bounds"]["half"] + Vector2.ONE, (game.world_data["roads"][0]["points"][0] + game.world_data["roads"][0]["points"][1]) * 0.5]:
			protected = protected and not forest.can_spawn(blocked, category)
		game._check("refresh-protects-roads-buildings-water-pasture-" + category, protected)
	var clear := find_clear(game)
	game.player.teleport(Vector3(clear.x, 0, clear.y))
	game._check("refresh-does-not-spawn-on-player", not forest.can_spawn(clear, "tree") and not forest.can_spawn(clear, "ore"))
	await game._frames(2)


static func _sapling_checks(game: Node3D) -> void:
	var forest: Node3D = game.surface_resources
	var at := find_clear(game)
	game.player.teleport(Vector3(at.x, 0, at.y + 2))
	game.player.face_point(Vector3(at.x, 0, at.y))
	game._select_tool(8)
	game.state.forestry["sapling"] = 1
	game._update_targeting()
	game._check("sapling-targets-front-grid", game.focus.get("kind") == "sapling" and game.focus.get("position") == at)
	var count: int = forest.resources.size()
	game._interact()
	game._interact()
	game._check("plant-consumes-one-sapling", forest.resources.size() == count + 1 and game.state.forestry["sapling"] == 0)
	var tree: Node3D = forest.resources[-1]
	game._check("sapling-starts-small-and-reserves-space", tree.stage == 0 and tree.planted and not game.tiles.is_open(game.tiles.key_of(tree.position)))
	game.player.teleport(Vector3(at.x, 0, at.y + 4.0))
	for age in range(1, 4):
		game._do_sleep()
		await game._frames(2)
		game._check("sapling-growth-day-%d" % age, tree.stage == age)
	game._check("sapling-matures-into-choppable-tree", tree.health == 54 and tree._crown != null)
	var seed_at := find_clear(game)
	var seedling: Node3D = forest.plant_sapling(seed_at)
	game._check("young-tree-plants-on-undeveloped-ground", seedling != null)
	if seedling != null:
		var wood_before: int = game.state.forestry["wood"]
		var seedlings_before: int = game.state.forestry["sapling"]
		game.player.teleport(seedling.position + Vector3(0, 0, 1.9))
		forest.swing("axe", game.player.position, Vector3.FORWARD)
		await game._frames(90)
		game._check("young-tree-recovers-sapling-without-free-wood", game.state.forestry["sapling"] == seedlings_before + 1 and game.state.forestry["wood"] == wood_before)


static func _ore_checks(game: Node3D) -> void:
	var forest: Node3D = game.surface_resources
	var advanced_before := [game.state.minerals["iron"], game.state.minerals["crystal"]]
	for kind in Ecology.SURFACE_ORES:
		var at := find_clear(game)
		var ore: Node3D = forest.try_spawn({"position": at, "category": "ore", "kind": kind}, false)
		game.player.teleport(ore.position + Vector3(0, 0, 1.9))
		game._select_tool(5)
		await game._frames(2)
		game._update_targeting()
		game._check("surface-ore-focus-" + kind, game.focus.get("node") == ore)
		game._check("surface-ore-needs-pickaxe-" + kind, ore.hit("axe", 18, game.player.position) == 0 and ore.hit("sword", 22, game.player.position) == 0)
		var collected: int = game.state.minerals[kind]
		for hit in range(ore.health / 18):
			forest.swing("pickaxe", game.player.position, Vector3.FORWARD)
		game._check("surface-ore-depletes-once-" + kind, ore.depleted and ore.hit("pickaxe", 18, game.player.position) == 0)
		await game._frames(90)
		game._check("surface-mineral-pickup-" + kind, game.state.minerals[kind] >= collected + 1 and game.state.minerals[kind] <= collected + 3)
		game._check("mined-surface-ground-opens-" + kind, game.tiles.is_open(game.tiles.key_of(Vector3(at.x, 0, at.y))))
	for kind in ["iron", "crystal", "slime"]:
		var at := find_clear(game)
		game._check("advanced-material-rejected-on-surface-" + kind, forest.try_spawn({"position": at, "category": "ore", "kind": kind}, false) == null and forest.spawn_drop(kind, 1, Vector3(at.x, 0, at.y)) == null)
	game._check("surface-mining-never-awards-advanced-ore", [game.state.minerals["iron"], game.state.minerals["crystal"]] == advanced_before)


static func _map_checks(game: Node3D) -> void:
	var forest: Node3D = game.surface_resources
	var at := find_clear(game)
	var tree: Node3D = forest.plant_sapling(at)
	var remote: Node3D
	for resource in forest.resources:
		if absf(resource.position.x) > 50 and resource.category == "tree":
			remote = resource
			break
	var remote_position: Vector3 = remote.position
	var remote_health: int = remote.health
	var loot_at := Vector3(at.x + 5, 0, at.y + 5)
	var drop: Node3D = forest.spawn_drop("wood", 2, loot_at)
	game.player.teleport(game.landmarks["mine_door"] + Vector3(0, 0, 1.1))
	game._select_tool(7)
	var resources_before: int = forest.resources.size()
	var inventory_before: Dictionary = game.state.forestry.duplicate()
	game._travel_to(1)
	await game._frames(3)
	for monster in game.mine.monsters:
		monster.set_physics_process(false)
	game._check("surface-trees-disabled-inside-mine", not solid_at(game, remote_position) and forest.paused)
	game._check("surface-drops-pause-inside-mine", drop.position == loot_at and not drop.taken)
	game.state.clock = 25.99
	if game.state.advance_hour(0.02):
		game._apply_rollover()
	await game._frames(3)
	game._check("dawn-in-mine-grows-surface-trees", tree.stage == 1 and forest.resources.size() >= resources_before)
	game._check("dawn-keeps-surface-collision-disabled", not solid_at(game, remote_position))
	game._travel_to(0)
	await game._frames(3)
	game._check("mine-return-retains-trees-and-loot", forest.resources.has(tree) and remote.health == remote_health and forest.drops.has(drop) and game.state.forestry == inventory_before)
	game._check("mine-return-restores-tree-collision-and-axe", solid_at(game, remote_position) and game.player.equipped_tool == "axe" and not forest.paused)
	game.player.teleport(loot_at)
	await game._frames(90)
	game._check("surface-drops-collect-after-mine-return", game.state.forestry["wood"] == inventory_before["wood"] + 2)


static func _refresh_checks(game: Node3D) -> void:
	var forest: Node3D = game.surface_resources
	var tiles_before: Dictionary = game.tiles.farm.tiles.duplicate()
	var before: Array = forest.resources.duplicate()
	var tree_room: int = maxi(0, Ecology.TREE_CAP - forest.count_resources("tree"))
	var ore_room: int = maxi(0, Ecology.ORE_CAP - forest.count_resources("ore"))
	game._do_sleep()
	var new_trees := 0
	var new_ores := 0
	var safe := true
	for resource in forest.resources:
		if before.has(resource):
			continue
		if resource.category == "tree":
			new_trees += 1
			safe = safe and resource.stage == 0
		else:
			new_ores += 1
			safe = safe and resource.kind in Ecology.SURFACE_ORES
	game._check("daily-random-tree-and-ore-replenishment", new_trees >= mini(3, tree_room) and new_trees <= mini(6, tree_room) and new_ores >= mini(2, ore_room) and new_ores <= mini(4, ore_room) and safe)
	var snapshot_count: int = forest.resources.size()
	var repeated: Dictionary = forest.on_day_rollover(game.state.day)
	game._check("one-refresh-per-day", forest.resources.size() == snapshot_count and repeated == {"grown": 0, "trees": 0, "ores": 0})
	for day in range(60):
		game._do_sleep()
	safe = true
	for resource in forest.resources:
		var at := Vector2(resource.position.x, resource.position.z)
		for key: Vector2i in game.tiles.farm.tiles:
			var center := Vector2(key) * 2
			if at.distance_to(at.clamp(center - Vector2.ONE, center + Vector2.ONE)) < resource.occupied_radius():
				safe = false
	game._check("long-running-refresh-preserves-all-developed-tiles", safe and game.tiles.farm.tiles == tiles_before)
	game._check("natural-resource-density-is-bounded", forest.count_resources("tree") <= Ecology.TREE_CAP and forest.count_resources("ore") <= Ecology.ORE_CAP)
	game._check("advanced-ores-never-generated-after-sixty-days", forest.resources.all(func(resource: Node3D): return resource.category == "tree" or resource.kind in Ecology.SURFACE_ORES))


static func _probability_checks(game: Node3D) -> void:
	var forest: Node3D = game.surface_resources
	forest.rng.seed = 821537
	var saplings := 0
	var wood_valid := true
	for sample in range(1000):
		var loot: Dictionary = forest.roll_tree_loot(true)
		wood_valid = wood_valid and loot["wood"] >= 4 and loot["wood"] <= 7
		saplings += loot.get("sapling", 0)
	game._check("adult-trees-always-drop-wood", wood_valid)
	game._check("saplings-drop-with-probability-not-guaranteed", saplings > 220 and saplings < 380)
	game._check("early-sapling-recovery-does-not-duplicate-materials", forest.roll_tree_loot(false) == {"sapling": 1})


static func find_clear(game: Node3D) -> Vector2:
	# Select an undeveloped, grid-aligned patch beside the actual player farm.
	# World coordinates remain valid when the 192 m prototype is replaced by
	# the 2.6 km blueprint and when fixtures from earlier checks occupy a patch.
	var spawn: Vector3 = game.landmarks["spawn"]
	var center := Vector2(roundf(spawn.x / 2) * 2, roundf(spawn.z / 2) * 2)
	for radius in range(8, 164, 4):
		for x in range(-radius, radius + 1, 4):
			for z in range(-radius, radius + 1, 4):
				if maxi(absi(x), absi(z)) != radius:
					continue
				var at := center + Vector2(x, z)
				if not game.surface_resources.can_spawn(at, "tree", false):
					continue
				var footing := at + Vector2(0, 1.9)
				if game.tiles.map.is_walkable(footing, 0.5) and not solid_at(game, Vector3(footing.x, 0, footing.y)):
					return at
	return Vector2.INF


static func solid_at(game: Node3D, at: Vector3) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.15
	query.shape = sphere
	query.collision_mask = 1
	query.transform = Transform3D(Basis.IDENTITY, at + Vector3(0, 0.62, 0))
	return not game.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()
