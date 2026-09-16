extends RefCounted
## 十层矿洞的确定性布局。地板、碰撞、寻路与小地图共用同一张格网。

const FLOOR_COUNT := 10
const CELL := 2.0
const GRID := Vector2i(25, 23)
const CHECKPOINTS := [1, 5, 10]
const TITLES := ["旧矿道", "铜脉回廊", "矿车岔路", "滴水岩窟", "矿工营地", "幽蓝石窟", "水晶矿脉", "回声深井", "星辉回廊", "地心晶室"]
const THEMES := [
	{"name": "浅层铜矿", "floor": "#8b795f", "tile": "#a28a66", "wall": "#6f6d60", "cap": "#8d8a73", "ore": "copper", "light": Color("#ffc979"), "ambient": Color("#c9c3b5")},
	{"name": "地下岩洞", "floor": "#626e70", "tile": "#7a8988", "wall": "#505f68", "cap": "#75848b", "ore": "iron", "light": Color("#97e0dd"), "ambient": Color("#b6d4dc")},
	{"name": "深层水晶", "floor": "#68647b", "tile": "#898198", "wall": "#504f67", "cap": "#77758e", "ore": "crystal", "light": Color("#b6bbff"), "ambient": Color("#c6c6ed")},
]


static func theme(depth: int) -> Dictionary:
	return THEMES[0 if depth <= 3 else (1 if depth <= 6 else 2)]


static func center(cell: Vector2i) -> Vector3:
	return Vector3((cell.x - GRID.x / 2) * CELL, 0, (cell.y - GRID.y / 2) * CELL)


static func key(at: Vector3) -> Vector2i:
	return Vector2i(roundi(at.x / CELL) + GRID.x / 2, roundi(at.z / CELL) + GRID.y / 2)


static func create(depth: int) -> Dictionary:
	assert(depth >= 1 and depth <= FLOOR_COUNT)
	var open := {}
	var rooms: Array[Rect2i] = []
	var variation := (depth - 1) % 3
	if depth == 10:
		rooms = [Rect2i(8, 17, 9, 4), Rect2i(4, 3, 17, 13), Rect2i(9, 1, 7, 5)]
	elif depth == 5:
		rooms = [Rect2i(8, 16, 9, 5), Rect2i(5, 7, 15, 10), Rect2i(9, 2, 7, 6)]
	elif variation == 0:
		rooms = [Rect2i(9, 17, 7, 4), Rect2i(8, 10, 9, 7), Rect2i(2, 5, 8, 8), Rect2i(16, 6, 7, 7), Rect2i(9, 2, 7, 6)]
	elif variation == 1:
		rooms = [Rect2i(9, 17, 7, 4), Rect2i(3, 12, 9, 6), Rect2i(3, 4, 8, 7), Rect2i(14, 6, 8, 10), Rect2i(9, 2, 7, 6)]
	else:
		rooms = [Rect2i(9, 17, 7, 4), Rect2i(14, 12, 8, 6), Rect2i(14, 3, 8, 8), Rect2i(3, 6, 8, 9), Rect2i(9, 2, 7, 6)]
	for room in rooms:
		_carve(open, room)
	# 连续的三格宽通道连接所有房间，支路也不会被装饰或随机矿石封死。
	for i in range(rooms.size() - 1):
		_corridor(open, rooms[i].get_center(), rooms[i + 1].get_center())
	_corridor(open, rooms[0].get_center(), Vector2i(12, 13))
	_corridor(open, Vector2i(12, 13), rooms[-1].get_center())
	if depth != 5 and depth != 10:
		# 岩柱保留一格绕行余量，各层改变位置形成不同的岔路。
		for pillar in [Vector2i(6, 8), Vector2i(18, 9), Vector2i(7, 15) if variation == 1 else Vector2i(19, 14)]:
			if open.has(pillar):
				open.erase(pillar)
	var up := Vector2i(12, 19)
	var down := Vector2i(12, 3)
	var lift := Vector2i(15, 19)
	var spawn := Vector2i(12, 17)
	var reserved := [up, down, lift, spawn, Vector2i(12, 5), Vector2i(9, 12)]
	if depth == 10:
		reserved.append_array([Vector2i(12, 8), Vector2i(7, 6), Vector2i(18, 6)])
	var decorations: Array[Vector2i] = []
	for room in rooms:
		var cell := room.position + Vector2i(1, 1)
		decorations.append(cell)
		reserved.append(cell)
	var rng := RandomNumberGenerator.new()
	rng.seed = 83179 + depth * 923
	var candidates: Array[Vector2i] = []
	for cell: Vector2i in open:
		var keep_clear := false
		for point: Vector2i in reserved:
			if Vector2(cell).distance_to(Vector2(point)) < 2.3:
				keep_clear = true
		if keep_clear or cell.x in [11, 12, 13] or cell.y >= 17:
			continue
		var adjacent := 0
		for direction in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			if open.has(cell + direction):
				adjacent += 1
		if adjacent == 4:
			candidates.append(cell)
	# Fisher–Yates with a local RNG keeps tests and repeat visits reproducible.
	for i in range(candidates.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var previous := candidates[i]
		candidates[i] = candidates[j]
		candidates[j] = previous
	var rocks: Array[Dictionary] = []
	var occupied := {}
	for cell in candidates:
		if rocks.size() >= (10 if depth == 5 else 17 + depth):
			break
		var crowded := false
		for prior: Vector2i in occupied:
			if Vector2(prior).distance_to(Vector2(cell)) < 1.8:
				crowded = true
		if crowded:
			continue
		var kind: String = theme(depth)["ore"] if rocks.size() % 3 != 0 else "stone"
		if rocks.size() % 7 == 5:
			kind = "coal"
		rocks.append({"cell": cell, "kind": kind, "seal": false})
		occupied[cell] = true
	if depth not in [5, 10]:
		rocks.append({"cell": down, "kind": "stone", "seal": true})
	var monsters: Array[Dictionary] = []
	var count := 0 if depth == 5 else mini(6, 2 + depth / 2)
	for cell in candidates:
		if monsters.size() >= count:
			break
		if occupied.has(cell) or center(cell).distance_to(center(spawn)) < 9.0:
			continue
		var crowded := false
		for prior in monsters:
			if center(cell).distance_to(center(prior["cell"])) < 4.5:
				crowded = true
		if crowded:
			continue
		monsters.append({"cell": cell, "kind": "bat" if depth >= 3 and monsters.size() % 3 == 1 else "slime"})
	if depth == 10:
		monsters = [{"cell": Vector2i(12, 8), "kind": "guardian"}, {"cell": Vector2i(7, 6), "kind": "bat"}, {"cell": Vector2i(18, 6), "kind": "bat"}]
	return {"depth": depth, "open": open, "rooms": rooms, "rocks": rocks, "monsters": monsters, "decorations": decorations,
		"up": up, "down": down, "lift": lift, "spawn": spawn, "camp": Vector2i(9, 12),
		"title": TITLES[depth - 1], "theme": theme(depth)}


static func _carve(open: Dictionary, rect: Rect2i) -> void:
	for x in range(rect.position.x, rect.end.x):
		for z in range(rect.position.y, rect.end.y):
			if x > 0 and z > 0 and x < GRID.x - 1 and z < GRID.y - 1:
				open[Vector2i(x, z)] = true


static func _corridor(open: Dictionary, a: Vector2i, b: Vector2i) -> void:
	_carve(open, Rect2i(mini(a.x, b.x) - 1, a.y - 1, absi(a.x - b.x) + 3, 3))
	_carve(open, Rect2i(b.x - 1, mini(a.y, b.y) - 1, 3, absi(a.y - b.y) + 3))
