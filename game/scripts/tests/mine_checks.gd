extends RefCounted
## 从真实主场景验证地图隔离、十层通路、动作命中、掉落与回访状态。

const Layout = preload("res://scripts/mine_layout.gd")
const Equipment = preload("res://scripts/art/equipment_models.gd")


static func run(game: Node3D) -> void:
	var player: CharacterBody3D = game.player
	var state: RefCounted = game.state
	var farm_key: Vector2i = game.tiles.farm.tiles.keys()[0]
	var farm_tile: Node3D = game.tiles.node(farm_key)
	var farm_state: String = farm_tile.state
	var pasture_count: int = game.pastures.size()
	for index in range(Equipment.TOOLS.size()):
		game._select_tool(index)
		var held: Node3D = player._held
		game._check("held-" + Equipment.TOOLS[index], held.get_meta("tool") == Equipment.TOOLS[index] and held.get_parent() == player._socket and (index == 0 or held.find_children("*", "MeshInstance3D", true, false).size() > 0))
	game._select_tool(3)
	var seed_model: Node3D = player._held
	player.set_tool("seed", "pumpkin")
	game._check("seed-packet-follows-crop", player._held != seed_model and player.equipped_seed == "pumpkin")
	game._select_tool(0)
	player.global_position = game.landmarks["mine_door"] + Vector3(0, 0, 0.7)
	game._update_targeting()
	game._check("mine-door-context", game.focus.get("kind") == "mine_entrance")
	game._interact()
	await game._frames(3)
	game._check("mine-enter", game.mine_depth == 1 and not game._outdoors.visible and player.equipped_tool == "pickaxe")
	game._check("surface-collision-disabled", not _solid_at(game, Vector3(game.world_data["sites"][0]["position"].x,0,game.world_data["sites"][0]["position"].y)))
	game._check("mine-wall-collision-active", _solid_at(game, Layout.center(Vector2i(12, 0))))
	game.hud.open_mine_travel(1)
	game._check("unvisited-lifts-disabled", game.hud._travel_buttons[5].disabled and game.hud._travel_buttons[10].disabled)
	game._on_travel_requested(5)
	game._check("locked-checkpoint-rejected", game.mine_depth == 1)
	game.hud.dismiss_panels()
	_freeze_monsters(game.mine)
	var first_floor: Node3D = game.mine
	var seal: Node3D
	for rock in first_floor.rocks:
		if rock.seal:
			seal = rock
	game._check("ladder-in-sealed-rock", seal != null and not first_floor.descent_open)
	player.teleport(seal.position + Vector3(0, 0, 1.8))
	player.face_point(seal.position)
	game._select_tool(5)
	player.attack_cooldown = 0
	var ore_before: int = seal.health
	var socket_before: Vector3 = player._socket.global_position
	game._check("pickaxe-action-starts", player.begin_swing())
	game._check("action-cannot-repeat-in-cooldown", not player.begin_swing())
	await game._frames(13)
	game._check("held-tool-follows-arm", player._socket.global_position.distance_to(socket_before) > 0.08)
	await game._frames(10)
	game._check("one-pick-hit-at-contact", seal.health == ore_before - 18)
	await game._frames(25)
	game._check("one-swing-one-rock-hit", seal.health == ore_before - 18)
	player.begin_swing()
	await game._frames(38)
	game._check("mining-reveals-down-ladder", first_floor.descent_open and not is_instance_valid(seal))
	await game._frames(35)
	game._check("mineral-drop-collected", state.minerals["stone"] >= 1)
	var first_rock_count: int = first_floor.rocks.size()
	await _combat_checks(game)
	for depth in range(1, Layout.FLOOR_COUNT + 1):
		var floor_node: Node3D = game.mine
		_freeze_monsters(floor_node)
		await game._frames(3)
		game._check("floor-%02d-identity" % depth, game.mine_depth == depth and floor_node.layout["depth"] == depth and game.hud._map.navigation["depth"] == depth)
		game._check("floor-%02d-walkable-route" % depth, _route_to_stairs(game, floor_node))
		game._check("floor-%02d-collision-boundary" % depth, _solid_at(game, Layout.center(Vector2i(12, 0))))
		if depth == 5:
			state.health = 41
			state.rations = 0
			player.teleport(Layout.center(floor_node.layout["camp"]))
			game._select_tool(0)
			game._update_targeting()
			game._interact()
			game._check("camp-restores-health-and-rations", state.health == 100 and state.rations == 3 and floor_node.camp_used)
			state.health = 80
			game._interact()
			game._check("camp-reward-once", state.health == 80)
		if depth < Layout.FLOOR_COUNT:
			if not floor_node.descent_open:
				player.teleport(floor_node.down_position() + Vector3(0, 0, 1.8))
				await game._frames(2)
				for hit in range(2):
					floor_node.swing("pickaxe", player.global_position, Vector3.FORWARD)
				await game._frames(2)
			game._check("floor-%02d-down-unlocked" % depth, floor_node.descent_open)
			player.teleport(floor_node.down_position() + Vector3(0, 0, 1.8))
			game._select_tool(0)
			game._update_targeting()
			game._interact()
			game._check("stairs-%02d-to-%02d" % [depth, depth + 1], game.mine_depth == depth + 1)
	game._check("all-ten-floors-built", game._mine_floors.size() == 10 and state.deepest_mine_floor == 10)
	game._travel_to(11)
	game._check("no-eleventh-floor", game.mine_depth == 10 and not game.mine.descent_open)
	await _final_floor_checks(game)
	game._travel_to(5)
	await game._frames(3)
	game._check("checkpoint-retains-camp-state", game.mine_depth == 5 and game.mine.camp_used)
	game._select_tool(0)
	player.teleport(game.mine.up_position() + Vector3(0, 0, -1.6))
	game._update_targeting()
	game._interact()
	await game._frames(3)
	game._check("upstairs-returns-to-previous-floor", game.mine_depth == 4 and player.position.distance_to(game.mine.down_position()) < 3.0)
	game._travel_to(0)
	await game._frames(3)
	game._check("return-to-valley", game.mine_depth == 0 and game._outdoors.visible and player.position.distance_to(game.landmarks["mine_door"]) < 2)
	game._check("surface-collision-restored", _solid_at(game, Vector3(game.world_data["sites"][0]["position"].x,0,game.world_data["sites"][0]["position"].y)))
	game._check("inactive-mine-collision-removed", not _solid_at(game, Layout.center(Vector2i(12, 0))))
	game._check("farm-state-preserved-across-maps", game.tiles.node(farm_key) == farm_tile and farm_tile.state == farm_state and game.pastures.size() == pasture_count and game.animals.size() == 7)
	game._check("surface-equipment-restored", player.equipped_tool == "hand")
	game._update_targeting()
	game._interact()
	game._check("entrance-offers-unlocked-lifts", game.hud.travel_open and not game.hud._travel_buttons[5].disabled and not game.hud._travel_buttons[10].disabled)
	game.hud._travel_buttons[1].pressed.emit()
	await game._frames(3)
	game._check("revisit-preserves-mining-state", game.mine == first_floor and game.mine.descent_open and game.mine.rocks.size() == first_rock_count)
	var minerals_before: Dictionary = state.minerals.duplicate()
	state.health = 1
	player.invulnerable = 0
	game._on_player_attacked(9, player.position + Vector3(1, 0, 0))
	await game._frames(3)
	game._check("defeat-recovers-at-mine-entrance", game.mine_depth == 0 and state.health == 60 and not player.locked and player.position.distance_to(game.landmarks["mine_door"]) < 2)
	game._check("defeat-keeps-collected-minerals", state.minerals == minerals_before)
	game._do_sleep()
	game._check("farmhouse-restores-exploration-supplies", state.health == 100 and state.rations >= 3)


static func _combat_checks(game: Node3D) -> void:
	var floor_node: Node3D = game.mine
	var monster: CharacterBody3D = floor_node.monsters[0]
	var player: CharacterBody3D = game.player
	monster.position = Vector3(0, 0, 3)
	player.teleport(Vector3(0, 0, 4.8))
	await game._frames(3)
	var hp_before: int = monster.health
	game._check("farm-tools-do-not-damage-monsters", floor_node.swing("hoe", player.position, Vector3.FORWARD) == 0 and monster.health == hp_before)
	game._select_tool(6)
	player.attack_cooldown = 0
	player.face_point(player.position + Vector3.BACK)
	player.begin_swing()
	await game._frames(33)
	game._check("sword-direction-matters", monster.health == hp_before)
	player.face_point(monster.position)
	player.begin_swing()
	await game._frames(16)
	game._check("sword-damages-monster", monster.health == hp_before - 22)
	var number_found := false
	for child in floor_node.get_children():
		if child is Label3D and child.text == "22" and child.modulate.a > 0.5:
			number_found = true
	game._check("monster-hit-shows-damage-number", number_found)
	await game._frames(28)
	game._check("sword-does-not-repeat-same-hit", monster.health == hp_before - 22)
	game._check("walls-block-attack-line", not floor_node.clear_line(Layout.center(Vector2i(5, 8)), Layout.center(Vector2i(7, 8))))
	player.invulnerable = 0
	game.state.health = 100
	game._on_player_attacked(9, player.position + Vector3(1, 0, 0))
	game._on_player_attacked(9, player.position + Vector3(1, 0, 0))
	game._check("player-hit-and-invulnerability", game.state.health == 91)
	game.hud.toggle_map()
	player.invulnerable = 0
	game._on_player_attacked(9, player.position)
	game._check("mine-map-pauses-combat", game.hud.map_open and player.locked and floor_node.paused and game.state.health == 91)
	game.hud.dismiss_panels()
	game._check("mine-map-resumes-combat", not player.locked and not floor_node.paused)
	var rations: int = game.state.rations
	game._eat_ration()
	game._check("ration-heals-and-consumes-once", game.state.health == 100 and game.state.rations == rations - 1)
	game._eat_ration()
	game._check("full-health-keeps-ration", game.state.rations == rations - 1)
	# 由怪物自己的物理更新完成追踪、预警和命中，避免只验证直接调用。
	monster.health = monster.max_health
	monster.position = Vector3(0, 0, 1)
	monster._knockback = Vector3.ZERO
	monster._cooldown = 0
	monster._stun = 0
	player.teleport(Vector3(0, 0, 6.2))
	player.invulnerable = 0
	game.state.health = 100
	monster.set_physics_process(true)
	await game._frames(110)
	game._check("monster-chases-through-cavern", monster.position.distance_to(player.position) < 3.5)
	await game._frames(110)
	game._check("monster-telegraphs-and-hits-player", game.state.health < 100)
	monster.set_physics_process(false)
	game.state.health = 100


static func _final_floor_checks(game: Node3D) -> void:
	var floor_node: Node3D = game.mine
	game._check("floor-ten-guardian-present", floor_node.monsters.any(func(monster: Node3D): return monster.kind == "guardian"))
	var coins: int = game.state.coins
	game._check("final-chest-locked-by-monsters", not floor_node.open_chest() and game.state.coins == coins)
	for monster in floor_node.monsters.duplicate():
		var origin: Vector3 = monster.position + Vector3(0, 0, 1.8)
		while monster.health > 0:
			var before: int = monster.health
			floor_node.swing("sword", origin, Vector3.FORWARD)
			if monster.health == before:
				game._check("guardian-combat-accessible", false)
				break
		game._check("defeated-monster-cannot-drop-twice", monster.hit(22, origin) == 0)
	game._check("crystal-chamber-cleared", floor_node.monsters.is_empty())
	var crystals: int = game.state.minerals["crystal"]
	game._select_tool(0)
	game.player.teleport(floor_node.down_position() + Vector3(0, 0, 1.7))
	game._update_targeting()
	game._interact()
	game._interact()
	game._check("final-chest-reward-once", game.state.mine_completed and floor_node.chest_opened and game.state.coins == coins + 150 and game.state.minerals["crystal"] == crystals + 12)
	await game._frames(3)


static func _freeze_monsters(floor_node: Node3D) -> void:
	for monster in floor_node.monsters:
		monster.set_physics_process(false)


static func _solid_at(game: Node3D, at: Vector3) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.34
	shape.height = 1.1
	query.shape = shape
	query.collision_mask = 1
	query.transform = Transform3D(Basis.IDENTITY, at + Vector3(0, 0.62, 0))
	return not game.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


static func _route_to_stairs(game: Node3D, floor_node: Node3D) -> bool:
	var walkable := {}
	for cell: Vector2i in floor_node.layout["open"]:
		if not _solid_at(game, Layout.center(cell)):
			walkable[cell] = true
	var start: Vector2i = floor_node.layout["spawn"]
	var queue: Array[Vector2i] = [start]
	var reached := {start: true}
	var cursor := 0
	while cursor < queue.size():
		var here := queue[cursor]
		cursor += 1
		for step in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var next: Vector2i = here + step
			if walkable.has(next) and not reached.has(next):
				reached[next] = true
				queue.append(next)
	var destination: Vector2i = floor_node.layout["down"] + Vector2i.DOWN
	return reached.has(destination) and reached.has(floor_node.layout["up"]) and reached.size() > walkable.size() * 0.94
