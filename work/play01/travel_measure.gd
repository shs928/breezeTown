extends SceneTree
## PLAY-01：真实比例地图的长途行程实测。
## 沿已验收的主干路线途经点，以精确步行/快跑速度逐步推进玩家位置，
## 读取游戏时钟换算消耗的游戏时长。仅测量，不改玩法。
const WALK := 3.6
const RUN := 6.4
var game: Node3D

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1600, 1000)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	for i in range(5):
		await process_frame
	var layout: Dictionary = game.world_data["definition"]
	var farm_gate := Vector2(layout["landmarks"]["spawn"].x, layout["landmarks"]["spawn"].z)
	var square: Vector2 = (layout["square"] as Rect2).get_center()
	var mine := Vector2(layout["landmarks"]["mine_door"].x, layout["landmarks"]["mine_door"].z)
	var npc_home := Vector2.ZERO
	var harbor := Vector2.ZERO
	var shop := Vector2.ZERO
	for building: Dictionary in layout["buildings"]:
		if building["id"] == "npc_farmhouse": npc_home = building["door"]
		elif building["id"] == "harbor_house": harbor = building["door"]
		elif building["id"] == "shop": shop = building["door"]
	var sq_edge := Vector2(square.x, square.y + 76.0)
	var sq_near := Vector2(square.x, square.y + 12.0)
	var routes := {
		"farm-to-town": [farm_gate, Vector2(-350, 60), Vector2(-100, -90), sq_edge],
		"town-to-mine": [sq_near, Vector2(-150, -380), Vector2(-276, -600), Vector2(-450, -650), Vector2(-650, -740), mine],
		"town-to-npc-farm": [sq_near, Vector2(250, -350), Vector2(420, -470), Vector2(499, -520), Vector2(480, -650), npc_home],
		"town-to-harbor": [sq_near, Vector2(0, 100), Vector2(80, 450), Vector2(100, 595), Vector2(0, 640), harbor],
		"farm-to-shop": [farm_gate, Vector2(-350, 60), Vector2(-100, -90), sq_edge, shop],
		"farm-to-mine": [farm_gate, Vector2(-350, 60), Vector2(-100, -90), sq_near, Vector2(-150, -380), Vector2(-276, -600), Vector2(-450, -650), Vector2(-650, -740), mine],
	}
	for key: String in routes:
		for mode in [["walk", WALK], ["run", RUN]]:
			var result: Dictionary = await _travel(routes[key], mode[1])
			_emit("ROUTE %s %s meters=%.0f real_s=%.1f game_h=%.2f game_days=%.2f" % [
				key, mode[0], result["meters"], result["real_s"], result["game_h"], result["game_h"] / 20.0])
	# 一天活动预算：白天 06:00-19:48 = 13.8 游戏小时 = 103.5 现实秒
	_emit("DAY daylight=13.8 game_h (103.5 real s); walk range/day=%.0f m; run range/day=%.0f m (round-trip half: %.0f / %.0f m)" % [
		3.6 * 103.5, 6.4 * 103.5, 3.6 * 103.5 * 0.5, 6.4 * 103.5 * 0.5])
	quit(0)

func _travel(points: Array, speed: float) -> Dictionary:
	var from := Vector3(points[0].x, 0, points[0].y)
	game.player.teleport(from)
	await physics_frame
	await physics_frame
	var hours0: float = game.state.time.hours
	var day0: int = game.state.time.day
	var total := 0.0
	for i in range(1, points.size()):
		var target := Vector3(points[i].x, 0, points[i].y)
		var remain := from.distance_to(target)
		total += remain
		var dir := (target - from).normalized()
		while remain > 0.02:
			var step: float = minf(speed / 60.0, remain)
			game.player.position = game.player.position + dir * step
			remain -= step
			await physics_frame
		from = target
	var consumed: float = (game.state.time.day - day0) * 20.0 + (game.state.time.hours - hours0)
	return {"meters": total, "game_h": consumed, "real_s": consumed * 150.0 / 20.0}

func _emit(line: String) -> void:
	print("PLAY01 " + line)
