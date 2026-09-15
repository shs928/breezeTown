extends RefCounted
## 组建可玩的 3D 农场地图：地形、建筑、农田、装饰、碰撞体与地标。
## 布局改编自 art/2_5d 的农场微缩景观，单位：米。

const M = preload("res://scripts/art/art_mesh.gd")
const L = preload("res://scripts/art/landscape_models.gd")
const B = preload("res://scripts/art/building_models.gd")

## 玩家活动范围（岛屿椭圆略内收）。
const BOUND_A := 10.0
const BOUND_B := 7.55


static func build() -> Dictionary:
	var root := Node3D.new()
	root.name = "World"
	root.add_child(L.terrain())
	for patch in [Vector3(-7.9, 1.4, -5.6), Vector3(4.6, 2.8, -3.5), Vector3(-6.0, 2.8, 4.5), Vector3(3.8, 1.8, 6.7), Vector3(8.7, 1.1, -4.6)]:
		place(root, L.meadow_patch(patch.y, patch.y * 0.7, "#92b174", int(patch.x * 7)), Vector3(patch.x, 0, patch.z))
	place(root, B.cottage(), Vector3(-5.15, 0.025, -4.20), 0.025)
	place(root, B.shop(), Vector3(2.70, 0.025, -4.65), -0.045)
	_path(root, [Vector3(0.05, 0, 7.5), Vector3(-0.20, 0, 5.9), Vector3(0.13, 0, 3.7), Vector3(-0.1, 0, 1.5), Vector3(0.2, 0, -0.75)], 1.52)
	_path(root, [Vector3(-7.8, 0, -0.62), Vector3(-4.7, 0, -0.52), Vector3(0.2, 0, -0.75), Vector3(3.7, 0, -0.8), Vector3(6.9, 0, -0.35)], 1.15)
	_path(root, [Vector3(0.17, 0, 2.7), Vector3(2.4, 0, 2.60), Vector3(4.4, 0, 2.70)], 0.94)
	place(root, L.pond(), Vector3(5.6, 0.0, 4.1), -0.15)
	place(root, L.footbridge(), Vector3(5.48, 0.04, 2.72), 0.06)
	place(root, L.well(), Vector3(6.30, 0.0, 1.10), -0.2)
	for item in [Vector4(-8.6, -5.95, 1.08, 1), Vector4(-0.15, -6.6, 1.12, 2), Vector4(7.9, -5.8, 1.2, 3), Vector4(-9.0, -0.25, 0.88, 4), Vector4(9.0, 0.7, 0.88, 5)]:
		place(root, L.tree(int(item.w), item.w == 4), Vector3(item.x, 0, item.y), item.w * 0.49, item.z)
	for x in [-8.4, -6.0, -3.6, -1.2, 1.2, 3.6, 6.0, 8.4]:
		place(root, L.fence(), Vector3(x, 0.01, -7.1))
	for z in [-4.8, -2.4, 0.0, 2.4, 4.8, 6.8]:
		place(root, L.fence(2.4 if z < 6.0 else 1.6), Vector3(-9.8, 0.01, z), PI * 0.5)
	for z in [-4.8, -2.4, 0.0]:
		place(root, L.fence(), Vector3(9.7, 0.01, z), PI * 0.5)
	for x in [-7.1, -4.7, 3.4, 5.8, 8.2]:
		place(root, L.fence(), Vector3(x, 0, 7.3))
	place(root, L.barrel(), Vector3(-7.64, 0.02, -2.17))
	place(root, L.barrel(), Vector3(5.34, 0.02, -3.52))
	place(root, L.crate(true), Vector3(5.58, 0.02, -2.27), 0.12)
	place(root, L.crate(false), Vector3(-2.55, 0.02, -1.75), -0.10)
	place(root, L.watering_can(), Vector3(-1.7, 0.13, 2.1), -0.6)
	place(root, L.lantern_post(), Vector3(1.18, 0.02, 5.7), -0.1)
	place(root, L.lantern_post(), Vector3(5.76, 0.02, -0.35), PI)
	var rng := RandomNumberGenerator.new()
	rng.seed = 220914
	for i in range(200):
		var x := rng.randf_range(-10.2, 10.1)
		var z := rng.randf_range(-7.65, 7.65)
		if absf(x) < 1.1 or absf(z + 0.64) < 0.91:
			continue
		if z < -1.0 and x > -7.8 and x < 5.5:
			continue
		# 玩家农田区（x -7.7..-2.0，z -0.4..6.2）里不撒杂草。
		if x > -7.7 and x < -2.0 and z > -0.4 and z < 6.2:
			continue
		if Vector2((x - 5.6) / 3.0, (z - 4.1) / 2.4).length() < 1.08:
			continue
		if x > 1.0 and x < 6.6 and z > 1.9 and z < 3.5:
			continue
		place(root, L.flowers(i, i % 3 == 0) if i % 4 == 0 else L.grass_clump(i), Vector3(x, 0.027, z), rng.randf_range(0, TAU))
	for i in range(7):
		place(root, L.flowers(i + 1, i % 2 == 0), Vector3(-7.0 + i * 0.61, 0.03, 6.39), i * 0.66)
	return {
		"root": root,
		"obstacles": _obstacles(),
		"landmarks": {
			"shop_door": Vector3(1.15, 0, -2.5),
			"cottage_door": Vector3(-4.43, 0, -1.9),
			"spawn": Vector3(0.72, 0, 1.9),
		},
	}


static func plot_positions() -> Array[Vector3]:
	var spots: Array[Vector3] = []
	for z in [0.9, 2.9, 4.9]:
		for x in [-6.3, -3.3]:
			spots.append(Vector3(x, 0.02, z))
	return spots


static func place(parent: Node3D, child: Node3D, at: Vector3, yaw: float = 0.0, uniform_scale: float = 1.0) -> Node3D:
	child.position = at
	child.rotation.y = yaw
	child.scale *= uniform_scale
	parent.add_child(child)
	return child


static func _obstacles() -> Array:
	## 每项：{"shape": "box"/"sphere", "position", "size"(box) 或 "radius"(sphere)}。
	return [
		{"shape": "box", "position": Vector3(-5.15, 0.6, -4.2), "size": Vector3(4.7, 1.2, 4.3)},
		{"shape": "box", "position": Vector3(2.7, 0.6, -4.65), "size": Vector3(5.0, 1.2, 4.3)},
		{"shape": "sphere", "position": Vector3(6.3, 0.0, 1.1), "radius": 0.85},
		{"shape": "sphere", "position": Vector3(-7.64, 0.0, -2.17), "radius": 0.45},
		{"shape": "sphere", "position": Vector3(5.34, 0.0, -3.52), "radius": 0.45},
		{"shape": "sphere", "position": Vector3(5.58, 0.0, -2.27), "radius": 0.5},
		{"shape": "sphere", "position": Vector3(-2.55, 0.0, -1.75), "radius": 0.5},
		{"shape": "sphere", "position": Vector3(1.18, 0.0, 5.7), "radius": 0.2},
		{"shape": "sphere", "position": Vector3(5.76, 0.0, -0.35), "radius": 0.2},
		# 池塘：两枚圆近似椭圆，给木桥留出通道。
		{"shape": "sphere", "position": Vector3(6.44, 0.0, 4.23), "radius": 1.25},
		{"shape": "sphere", "position": Vector3(4.76, 0.0, 3.97), "radius": 1.25},
		# 五棵树。
		{"shape": "sphere", "position": Vector3(-8.6, 0.0, -5.95), "radius": 0.5},
		{"shape": "sphere", "position": Vector3(-0.15, 0.0, -6.6), "radius": 0.52},
		{"shape": "sphere", "position": Vector3(7.9, 0.0, -5.8), "radius": 0.55},
		{"shape": "sphere", "position": Vector3(-9.0, 0.0, -0.25), "radius": 0.42},
		{"shape": "sphere", "position": Vector3(9.0, 0.0, 0.7), "radius": 0.42},
		# 栅栏（留出缺口）。
		{"shape": "box", "position": Vector3(0, 0.45, -7.1), "size": Vector3(19.4, 0.9, 0.35)},
		{"shape": "box", "position": Vector3(-9.8, 0.45, 1.0), "size": Vector3(0.35, 0.9, 14.2)},
		{"shape": "box", "position": Vector3(9.7, 0.45, -2.4), "size": Vector3(0.35, 0.9, 7.4)},
		{"shape": "box", "position": Vector3(-5.9, 0.45, 7.3), "size": Vector3(4.9, 0.9, 0.35)},
		{"shape": "box", "position": Vector3(5.8, 0.45, 7.3), "size": Vector3(7.3, 0.9, 0.35)},
	]


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
				var pebble := L.stone(rng.randi_range(0, 3), Vector3(rng.randf_range(0.14, 0.205), 0.040, rng.randf_range(0.14, 0.205)))
				place(path_root, pebble, at, rng.randf_range(0, TAU))
