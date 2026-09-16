extends RefCounted
## Physical contracts shared by the real-scale map smoke and standalone map test.
const Height := preload("res://scripts/core/surface_height.gd")


static func run(game: Node3D, check: Callable) -> void:
	var player: CharacterBody3D = game.player
	var definition: Dictionary = game.world_data["definition"]
	var spawn: Vector3 = game.landmarks["spawn"]
	player.teleport(spawn)
	await game._frames(4)
	check.call("spawn-physically-clear", not solid(game, spawn))
	for site: Dictionary in game.world_data["sites"]:
		var door: Vector2 = site["door"]
		var at: Vector2 = site["position"]
		check.call("door-clear-" + site["id"], game.tiles.map.is_walkable(door, 0.35))
		check.call("building-solid-" + site["id"], solid(game, Vector3(at.x, 0, at.y)))
	for bridge: Dictionary in definition["bridges"]:
		var rect: Rect2 = bridge["rect"]
		var along_x: bool = bridge.get("axis", "x" if rect.size.x >= rect.size.y else "z") == "x"
		var center := rect.get_center()
		var axis := Vector2.RIGHT if along_x else Vector2.DOWN
		var length := rect.size.x if along_x else rect.size.y
		var approach := center - axis * (length * 0.5 + 1.5)
		var exit := center + axis * (length * 0.5 + 1.5)
		check.call("bridge-connects-banks-" + bridge["id"], game.tiles.map.segment_is_walkable(approach, exit, 0.35))
		check.call("bridge-cannot-be-farmed-" + bridge["id"], not game.tiles.is_open(game.tiles.key_of(Vector3(center.x, 0, center.y))))
		player.teleport(Vector3(center.x, 0, center.y))
		await game._frames(4)
		check.call("bridge-height-follows-deck-" + bridge["id"], absf(player.position.y - Height.deck_height(center, game.tiles.map.bridges)) < 0.015)
		# Sweep the real player shape along the deck: water colliders must be cut
		# away for its full width and no railing may bisect the crossing.
		check.call("bridge-physical-crossing-" + bridge["id"], clear_sweep(game, approach, exit))
		var path: PackedVector3Array = game.navigation.find_path(Vector3(approach.x, 0, approach.y), Vector3(exit.x, 0, exit.y))
		check.call("bridge-navigation-crossing-" + bridge["id"], not path.is_empty())
	var garden: Rect2 = definition["starter_garden"]
	var home: Vector2 = definition["buildings"][0]["position"]
	for offset in [12.0, 42.0]:
		var gate := Vector2(garden.get_center().x, home.y + offset)
		check.call("garden-gate-open-" + str(offset), clear_sweep(game, gate - Vector2(0, 2), gate + Vector2(0, 2)))
	var farm_fences: Array = game.world_data.get("farm_fences", [])
	check.call("garden-fences-have-collision", not farm_fences.is_empty())
	for index in range(farm_fences.size()):
		var line: Dictionary = farm_fences[index]
		var center: Vector2 = (line["from"] + line["to"]) * 0.5
		check.call("garden-fence-blocks-crossing-" + str(index), not clear_sweep(game, center - Vector2(0, 2), center + Vector2(0, 2)))
		check.call("garden-fence-protects-soil-" + str(index), not game.tiles.is_open(game.tiles.key_of(Vector3(center.x, 0, center.y))))
	for bridge: Dictionary in definition["bridges"]:
		if not bridge.get("stone", false):
			continue
		var rails: Array = game.world_data["obstacles"].filter(func(obstacle: Dictionary): return obstacle.get("source", "") == "bridge_parapet:" + bridge["id"])
		check.call("bridge-parapets-have-collision-" + bridge["id"], not rails.is_empty())
		if rails.is_empty():
			continue
		var at: Vector3 = rails[rails.size() / 2]["position"]
		check.call("bridge-parapet-is-physically-solid-" + bridge["id"], solid(game, at - Vector3(0, 0.62, 0)))
		check.call("bridge-parapet-blocks-domain-route-" + bridge["id"], not game.tiles.map.is_walkable(Vector2(at.x, at.z)))
	var pasture: Rect2 = game.world_data["pasture"]
	var gate := Vector2(pasture.get_center().x, pasture.end.y)
	player.teleport(Vector3(gate.x, 0, gate.y + 3))
	await game._frames(4)
	check.call("pasture-gate-physically-open", clear_sweep(game, gate + Vector2(0, 2), gate + Vector2(0, -2)))
	var fence := Vector2(pasture.position.x, pasture.get_center().y)
	check.call("pasture-fence-blocks-crossing", not clear_sweep(game, fence + Vector2(-2, 0), fence + Vector2(2, 0)))
	check.call("pasture-fence-blocks-domain-route", not game.tiles.map.segment_is_walkable(fence + Vector2(-2, 0), fence + Vector2(2, 0)))
	check.call("pasture-interior-protects-soil", not game.tiles.is_open(game.tiles.key_of(Vector3(pasture.get_center().x, 0, pasture.get_center().y))))
	var mine_door: Vector3 = game.landmarks["mine_door"]
	player.teleport(mine_door + Vector3(0, 0, 2))
	await game._frames(4)
	check.call("mine-approach-physically-open", clear_sweep(game, Vector2(mine_door.x, mine_door.z + 3), Vector2(mine_door.x, mine_door.z)))
	check.call("mine-entrance-protects-soil", not game.tiles.is_open(game.tiles.key_of(mine_door)))
	check.call("square-protects-soil", not game.tiles.is_open(game.tiles.key_of(game.landmarks["town_square"])))
	var water: Vector2 = definition["lake_center"]
	check.call("lake-protects-soil", not game.tiles.is_open(game.tiles.key_of(Vector3(water.x, 0, water.y))))
	var street: Vector2 = (definition["roads"][0]["points"][0] + definition["roads"][0]["points"][1]) * 0.5
	check.call("custom-fence-cannot-cover-street", not game._can_place_pasture(Rect2(street - Vector2(4, 4), Vector2(8, 8))))
	var buildable := find_pasture_site(game)
	check.call("custom-pasture-site-available", buildable.is_finite())
	if buildable.is_finite():
		var key: Vector2i = game.tiles.key_of(Vector3(buildable.x, 0, buildable.y))
		var before: int = game.pastures.size()
		game._place_fence_corner(key)
		game._place_fence_corner(key + Vector2i(4, 4))
		check.call("custom-pasture-builds-on-current-map", game.pastures.size() == before + 1 and game._fence_start == null)
		check.call("custom-pasture-reserves-soil", not game.tiles.is_open(key + Vector2i(2, 2)))
	var half: Vector2 = game.world_data["bounds"]["half"]
	var power: int = game.world_data["bounds"]["pow"]
	for edge in [Vector3(half.x + 10, 0, 0), Vector3(-half.x - 10, 0, 0), Vector3(0, 0, half.y + 10), Vector3(0, 0, -half.y - 10)]:
		player.teleport(edge)
		await game._frames(2)
		var at: Vector3 = player.position
		check.call("world-boundary-" + str(edge), pow(absf(at.x) / half.x, power) + pow(absf(at.z) / half.y, power) <= 1.001)
	player.teleport(spawn)


static func find_pasture_site(game: Node3D) -> Vector2:
	var spawn: Vector3 = game.landmarks["spawn"]
	var center := Vector2(roundf(spawn.x / 2) * 2, roundf(spawn.z / 2) * 2)
	for radius in range(12, 140, 8):
		for x in range(-radius, radius + 1, 8):
			for z in range(-radius, radius + 1, 8):
				if maxi(absi(x), absi(z)) != radius:
					continue
				var at := center + Vector2(x, z)
				if game._can_place_pasture(Rect2(at, Vector2(8, 8))):
					return at
	return Vector2.INF


static func solid(game: Node3D, at: Vector3) -> bool:
	var query := _query(game)
	query.transform = Transform3D(Basis.IDENTITY, at + Vector3(0, 0.62, 0))
	return not game.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


static func clear_sweep(game: Node3D, from: Vector2, to: Vector2, height: float = 0.0) -> bool:
	var query := _query(game)
	query.transform = Transform3D(Basis.IDENTITY, Vector3(from.x, height + 0.62, from.y))
	if not game.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
		return false
	query.motion = Vector3(to.x - from.x, 0, to.y - from.y)
	return game.get_world_3d().direct_space_state.cast_motion(query)[0] >= 0.999


static func _query(game: Node3D) -> PhysicsShapeQueryParameters3D:
	var query := PhysicsShapeQueryParameters3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.32
	shape.height = 1.1
	query.shape = shape
	query.collision_mask = 1
	query.exclude = [game.player.get_rid()]
	return query
