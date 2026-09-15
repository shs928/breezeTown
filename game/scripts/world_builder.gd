extends RefCounted
## 组建第一张大地图（约 92×72 米）：西南农舍、东南商店、西侧大农田、
## 东侧牧场（谷仓/鸡舍/食槽/围栏草场）、北部森林与东北池塘。
## 重复道具用模板 duplicate() 复用网格；碰撞体随放置登记。

const M = preload("res://scripts/art/art_mesh.gd")
const L = preload("res://scripts/art/landscape_models.gd")
const B = preload("res://scripts/art/building_models.gd")
const Ranch = preload("res://scripts/ranch_models.gd")

const BOUND_HALF := Vector2(46.0, 36.0)
const BOUND_POW := 6
const PASTURE := Rect2(10, 4, 24, 16)
const FIELD_RECT := Rect2(-27, 1, 20, 17)
const RANCH_RECT := Rect2(9, -2, 27, 24)

static var _templates := {}


static func build() -> Dictionary:
	var root := Node3D.new()
	root.name = "World"
	var obstacles: Array = []
	root.add_child(_terrain())
	for patch in [
		Vector3(-18, 3.4, 20), Vector3(-34, 3.0, 8), Vector3(-8, 2.6, 24), Vector3(2, 3.2, 14),
		Vector3(6, 2.4, -8), Vector3(-20, 3.6, -12), Vector3(38, 2.8, -14), Vector3(-40, 2.6, 22),
		Vector3(16, 3.0, 26), Vector3(-2, 2.2, -24),
	]:
		place(root, _tpl("patch%d" % int(patch.y * 10), func(): return L.meadow_patch(patch.y, patch.y * 0.66, "#92b174", int(patch.x * 7))), Vector3(patch.x, 0, patch.z))
	# 建筑与地标。
	place(root, B.cottage(), Vector3(-30, 0.025, -16), 0.025)
	_box_obstacle(obstacles, Vector3(-30, 0.6, -16), Vector3(4.7, 1.2, 4.3))
	place(root, B.shop(), Vector3(22, 0.025, -18), -0.045)
	_box_obstacle(obstacles, Vector3(22, 0.6, -18), Vector3(5.0, 1.2, 4.3))
	place(root, Ranch.barn(), Vector3(20, 0, 0), 0.0)
	_box_obstacle(obstacles, Vector3(20, 1.2, 0), Vector3(7.2, 2.4, 5.6))
	place(root, Ranch.coop(), Vector3(31, 0, 17), 0.1)
	_box_obstacle(obstacles, Vector3(31, 0.6, 17), Vector3(3.0, 1.2, 2.6))
	for bale in [Vector3(24.5, 0, 2.6), Vector3(25.9, 0, 3.1)]:
		place(root, _tpl("haybale", func(): return Ranch.hay_bale()), bale)
		_sphere_obstacle(obstacles, bale, 0.7)
	place(root, L.well(), Vector3(4, 0, 18), -0.2)
	_sphere_obstacle(obstacles, Vector3(4, 0, 18), 0.85)
	# 小径。
	_path(root, [Vector3(0, 0, 26.5), Vector3(0.1, 0, 14), Vector3(-0.1, 0, 2), Vector3(0, 0, -6), Vector3(0, 0, -13)], 1.6)
	_path(root, [Vector3(-1.4, 0, 10), Vector3(-9, 0, 10), Vector3(-17, 0, 10.2)], 1.15)
	_path(root, [Vector3(1.4, 0, 10), Vector3(8, 0, 10), Vector3(13, 0, 10), Vector3(19, 0, 6.5)], 1.15)
	_path(root, [Vector3(-3, 0, -13.5), Vector3(-14, 0, -14.5), Vector3(-27.5, 0, -14.8)], 1.05)
	_path(root, [Vector3(3, 0, -14), Vector3(12, 0, -15.5), Vector3(20.6, 0, -15.8)], 1.05)
	# 池塘（东北）。
	place(root, L.pond(), Vector3(30, 0, -8), -0.15)
	_sphere_obstacle(obstacles, Vector3(30.9, 0, -8.2), 1.3)
	_sphere_obstacle(obstacles, Vector3(28.9, 0, -9.3), 1.15)
	# 农田围栏（北侧留闸口）。
	_fence_line(root, Vector2(-26.5, 1.5), Vector2(-26.5, 17.5), obstacles)
	_fence_line(root, Vector2(-26, 1.5), Vector2(-19, 1.5), obstacles)
	_fence_line(root, Vector2(-15, 1.5), Vector2(-9, 1.5), obstacles)
	_fence_line(root, Vector2(-26, 17.3), Vector2(-13, 17.3), obstacles)
	# 牧场围栏（西侧留闸门 z 9..12）。
	_fence_line(root, Vector2(10, 4.2), Vector2(10, 9), obstacles)
	_fence_line(root, Vector2(10, 12), Vector2(10, 19.8), obstacles)
	_fence_line(root, Vector2(10.2, 4.2), Vector2(33.8, 4.2), obstacles)
	_fence_line(root, Vector2(10.2, 19.8), Vector2(33.8, 19.8), obstacles)
	_fence_line(root, Vector2(33.8, 4.2), Vector2(33.8, 19.8), obstacles)
	for gate_x in [9.4, 12.6]:
		var post := M.box(root, Vector3(gate_x, 0.6, 10.5), Vector3(0.2, 1.2, 0.2), "#a5824f", "GatePost", 0.03)
		post.rotation.y = PI * 0.5
	# 灯柱、装饰。
	for lamp in [Vector3(1.8, 0.02, 8), Vector3(-1.8, 0.02, -2), Vector3(-12.5, 0.02, 11.2), Vector3(12.5, 0.02, 8.8)]:
		place(root, L.lantern_post(), lamp, 0.0)
		_sphere_obstacle(obstacles, lamp, 0.2)
	place(root, L.barrel(), Vector3(-27.6, 0.02, -12.2))
	place(root, L.crate(true), Vector3(19.5, 0.02, -14.5), 0.12)
	place(root, L.watering_can(), Vector3(-8.5, 0.13, 12.5), -0.6)
	# 北部森林 + 边缘树林。
	var rng := RandomNumberGenerator.new()
	rng.seed = 91518
	for i in range(26):
		var x := rng.randf_range(-42, 42)
		var z := rng.randf_range(-31, -16.5)
		if absf(x) < 2.6:
			continue
		_plant_tree(root, obstacles, x, z, rng)
	for i in range(14):
		var edge: Vector2 = [
			Vector2(rng.randf_range(-44, -36), rng.randf_range(-12, 30)),
			Vector2(rng.randf_range(36, 43), rng.randf_range(-14, 30)),
			Vector2(rng.randf_range(-30, 30), rng.randf_range(28, 33)),
		][i % 3]
		_plant_tree(root, obstacles, edge.x, edge.y, rng)
	for apple in [Vector3(5.5, 0, 2.2), Vector3(-6.5, 0, -10.5), Vector3(7, 0, -10.8)]:
		place(root, _tpl("apple", func(): return L.tree(4, true)), apple, rng.randf_range(0, TAU))
		_sphere_obstacle(obstacles, apple, 0.5)
	# 森林巨石。
	for i in range(8):
		var stone_pos := Vector3(rng.randf_range(-38, 38), 0.03, rng.randf_range(-30, -18))
		var rock := _tpl("rock", func(): return L.stone(1, Vector3(0.5, 0.28, 0.4)))
		place(root, rock, stone_pos, rng.randf_range(0, TAU))
		_sphere_obstacle(obstacles, stone_pos, 0.45)
	# 草丛与野花散布（避开功能区与小径）。
	for i in range(380):
		var x := rng.randf_range(-44, 44)
		var z := rng.randf_range(-34, 34)
		if _in_scatter_exclusion(x, z):
			continue
		var decoration: Node3D
		if i % 5 == 0:
			decoration = _tpl("flower" + str(i % 2), func(): return L.flowers(i % 2, i % 2 == 0))
		else:
			decoration = _tpl("grass", func(): return L.grass_clump(i % 7))
		place(root, decoration, Vector3(x, 0.027, z), rng.randf_range(0, TAU))
	return {
		"root": root,
		"obstacles": obstacles,
		"landmarks": {
			"shop_door": Vector3(20.6, 0, -15.6),
			"cottage_door": Vector3(-29.3, 0, -13.9),
			"spawn": Vector3(0, 0, 24),
			"trough": Vector3(13, 0, 7),
		},
		"pasture": PASTURE,
		"bounds": {"half": BOUND_HALF, "pow": BOUND_POW},
	}


static func plot_positions() -> Array[Vector3]:
	var spots: Array[Vector3] = []
	for row in range(5):
		for col in range(6):
			spots.append(Vector3(-23.6 + col * 2.85, 0.02, 3.3 + row * 2.85))
	return spots


static func _plant_tree(root: Node3D, obstacles: Array, x: float, z: float, rng: RandomNumberGenerator) -> void:
	var key := "oak" + str(rng.randi_range(0, 1))
	var tree := _tpl(key, func(): return L.tree(1 + int(key.trim_prefix("oak").to_int()) * 8))
	place(root, tree, Vector3(x, 0, z), rng.randf_range(0, TAU), rng.randf_range(0.9, 1.15))
	_sphere_obstacle(obstacles, Vector3(x, 0, z), 0.5)


static func _in_scatter_exclusion(x: float, z: float) -> bool:
	if FIELD_RECT.has_point(Vector2(x, z)) or RANCH_RECT.has_point(Vector2(x, z)):
		return true
	if Vector2(x + 30, z + 16).length() < 5.5 or Vector2(x - 22, z + 18).length() < 5.5:
		return true
	if Vector2(x - 4, z - 18).length() < 2.2 or Vector2(x - 30, z + 8).length() < 4.5:
		return true
	if absf(x) < 1.4 and z > -14.5 and z < 26.5:
		return true
	if absf(z - 10) < 1.2 and x > -19 and x < 14:
		return true
	if absf(z + 14.5) < 1.2 and x > -28 and x < -2:
		return true
	if absf(z + 15.5) < 1.2 and x > 2 and x < 22:
		return true
	if Vector2(x - 30, z + 8).length() < 4.6:
		return true
	return false


static func _tpl(key: String, builder: Callable) -> Node3D:
	if not _templates.has(key):
		_templates[key] = builder.call()
	return (_templates[key] as Node3D).duplicate()


static func place(parent: Node3D, child: Node3D, at: Vector3, yaw: float = 0.0, uniform_scale: float = 1.0) -> Node3D:
	child.position = at
	child.rotation.y = yaw
	child.scale *= uniform_scale
	parent.add_child(child)
	return child


static func _box_obstacle(list: Array, position: Vector3, size: Vector3) -> void:
	list.append({"shape": "box", "position": position, "size": size})


static func _sphere_obstacle(list: Array, position: Vector3, radius: float) -> void:
	list.append({"shape": "sphere", "position": position, "radius": radius})


static func _fence_line(root: Node3D, from: Vector2, to: Vector2, obstacles: Array) -> void:
	var length := from.distance_to(to)
	var count := maxi(1, roundi(length / 2.4))
	var along_x := absf(to.x - from.x) > absf(to.y - from.y)
	for i in range(count):
		var t := (i + 0.5) / float(count)
		var at := from.lerp(to, t)
		var fence := _tpl("fence", func(): return L.fence())
		place(root, fence, Vector3(at.x, 0.01, at.y), 0.0 if along_x else PI * 0.5)
	var center := (from + to) * 0.5
	var size := Vector2(absf(to.x - from.x) + 0.35, absf(to.y - from.y) + 0.35)
	_box_obstacle(obstacles, Vector3(center.x, 0.45, center.y), Vector3(size.x, 0.9, size.y))


static func _terrain() -> Node3D:
	var root := Node3D.new()
	root.name = "IslandTerrain"
	var surfaces: Array[SurfaceTool] = []
	for layer in range(4):
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		surfaces.append(surface)
	var outline: Array[Vector3] = []
	for i in range(120):
		var theta := float(i) / 120.0 * TAU
		var wave := 1.0 + 0.008 * sin(theta * 13.0) + 0.006 * cos(theta * 19.0)
		var super_x := signf(cos(theta)) * pow(absf(cos(theta)), 0.18) * BOUND_HALF.x * wave
		var super_z := signf(sin(theta)) * pow(absf(sin(theta)), 0.18) * BOUND_HALF.y * wave
		outline.append(Vector3(super_x, 0, super_z))
	for i in range(outline.size()):
		var a := outline[i]
		var b := outline[(i + 1) % outline.size()]
		M.polygon(surfaces[0], [Vector3.ZERO, a, b], Vector3.UP)
		var rings := [Vector2(1.0, 0.0), Vector2(1.002, -0.20), Vector2(0.997, -0.76), Vector2(0.98, -1.16)]
		for r in range(3):
			var p := Vector3(a.x * rings[r].x, rings[r].y, a.z * rings[r].x)
			var q := Vector3(b.x * rings[r].x, rings[r].y, b.z * rings[r].x)
			var p2 := Vector3(a.x * rings[r + 1].x, rings[r + 1].y, a.z * rings[r + 1].x)
			var q2 := Vector3(b.x * rings[r + 1].x, rings[r + 1].y, b.z * rings[r + 1].x)
			M.polygon(surfaces[r + 1], [p, p2, q2, q], Vector3(a.x / BOUND_HALF.x, 0.12, a.z / BOUND_HALF.y).normalized())
	var pigments := ["#98b879", "#809e59", "#af8c65", "#927351"]
	var labels := ["MeadowTop", "SodEdge", "EarthLayer", "OchreBase"]
	for layer in range(4):
		M.mesh_node(root, surfaces[layer].commit(), Vector3.ZERO, M.paint(pigments[layer]), labels[layer])
	var rng := RandomNumberGenerator.new()
	rng.seed = 4711
	for i in range(64):
		var angle := rng.randf_range(0, TAU)
		var ex := signf(cos(angle)) * pow(absf(cos(angle)), 0.18)
		var ez := signf(sin(angle)) * pow(absf(sin(angle)), 0.18)
		M.ellipsoid(root, Vector3(ex * (BOUND_HALF.x - 0.25), rng.randf_range(-0.80, -0.40), ez * (BOUND_HALF.y - 0.25)), Vector3(rng.randf_range(0.04, 0.10), 0.036, rng.randf_range(0.05, 0.12)), "#c5aa83", "EarthPebble", 8, 4)
	return root


static func _path(root: Node3D, points: Array[Vector3], width: float) -> void:
	var path_root := Node3D.new()
	path_root.name = "WornGardenPath"
	root.add_child(path_root)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(points[0].x * 800 + points[0].z * 210) + 913
	for segment in range(points.size() - 1):
		var a := points[segment]
		var b := points[segment + 1]
		var delta := b - a
		var side := Vector3(-delta.z, 0, delta.x).normalized()
		var path_piece := M.box(path_root, (a + b) * 0.5 + Vector3(0, 0.018, 0), Vector3(width, 0.025, delta.length() + 0.18), "#cbbd94", "OchrePath", 0.008)
		path_piece.rotation.y = atan2(delta.x, delta.z)
		M.ellipsoid(path_root, a + Vector3(0, 0.024, 0), Vector3(width * 0.5, 0.014, width * 0.5), "#cbbd94", "PathCurve", 20, 4)
		var rows := ceili(delta.length() / 0.42)
		for row in range(rows):
			var t := (row + 0.5) / float(rows)
			for col in range(3):
				if rng.randf() < 0.12:
					continue
				var at := a.lerp(b, t) + side * ((col - 1) * width * 0.27 + rng.randf_range(-0.055, 0.055))
				at += delta.normalized() * rng.randf_range(-0.075, 0.075)
				at.y = 0.038
				var pebble := _tpl("pebble", func(): return L.stone(1, Vector3(0.17, 0.042, 0.17)))
				place(path_root, pebble, at, rng.randf_range(0, TAU))
