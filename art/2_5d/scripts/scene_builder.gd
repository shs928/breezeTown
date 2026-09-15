extends RefCounted

const M = preload("res://scripts/art_mesh.gd")
const L = preload("res://scripts/landscape_models.gd")
const B = preload("res://scripts/building_models.gd")
const F = preload("res://scripts/farmer_model.gd")

const VIEWS := ["farm", "cottage", "characters", "dusk", "market", "portraits"]
const TITLES := ["微风小镇 · 春日农场", "住进一间温暖的小屋", "农夫 · 四面造型", "灯亮了，慢慢回家", "街角的种子商店", "一起种下新的生活"]
const FILENAMES := ["01-farm-day.png", "02-cottage.png", "03-farmer-turnaround.png", "04-farm-dusk.png", "05-seed-market.png", "06-farmer-pair.png"]

static func view(index: int) -> Dictionary:
	match index:
		1:
			return {"root": cottage_study(), "target": Vector3(0, 1.40, 0.65), "camera": Vector3(8.4, 6.6, 12.3), "size": 8.3, "night": false}
		2:
			return {"root": character_study(false), "target": Vector3(0, 0.88, 0), "camera": Vector3(0, 2.7, 12.0), "size": 3.6, "night": false}
		3:
			return {"root": farm(), "target": Vector3(0, 0.75, 0), "camera": Vector3(19, 21, 26), "size": 21.8, "night": true}
		4:
			return {"root": market_study(), "target": Vector3(0, 1.3, 0.6), "camera": Vector3(8.6, 6.7, 12.5), "size": 8.7, "night": false}
		5:
			return {"root": character_study(true), "target": Vector3(0, 0.90, 0), "camera": Vector3(0, 2.15, 10.0), "size": 2.85, "night": false}
		_:
			return {"root": farm(), "target": Vector3(0, 0.75, 0), "camera": Vector3(19, 21, 26), "size": 21.8, "night": false}

static func place(parent: Node3D, child: Node3D, at: Vector3, yaw: float = 0.0, uniform_scale: float = 1.0) -> Node3D:
	child.position = at
	child.rotation.y = yaw
	child.scale *= uniform_scale
	parent.add_child(child)
	return child

static func farm() -> Node3D:
	var root := Node3D.new()
	root.name = "BreezeTown_Farm_Diorama"
	root.add_child(L.terrain())
	for patch in [Vector3(-7.9, 1.4, -5.6), Vector3(4.6, 2.8, -3.5), Vector3(-6.0, 2.8, 4.5), Vector3(3.8, 1.8, 6.7), Vector3(8.7, 1.1, -4.6)]:
		place(root, L.meadow_patch(patch.y, patch.y * 0.7, "#92b174", int(patch.x * 7)), Vector3(patch.x, 0, patch.z))
	place(root, B.cottage(), Vector3(-5.15, 0.025, -4.20), 0.025)
	place(root, B.shop(), Vector3(2.70, 0.025, -4.65), -0.045)
	_path(root, [Vector3(0.05, 0, 7.5), Vector3(-0.20, 0, 5.9), Vector3(0.13, 0, 3.7), Vector3(-0.1, 0, 1.5), Vector3(0.2, 0, -0.75)], 1.52)
	_path(root, [Vector3(-7.8, 0, -0.62), Vector3(-4.7, 0, -0.52), Vector3(0.2, 0, -0.75), Vector3(3.7, 0, -0.8), Vector3(6.9, 0, -0.35)], 1.15)
	_path(root, [Vector3(0.17, 0, 2.7), Vector3(2.4, 0, 2.60), Vector3(4.4, 0, 2.70)], 0.94)
	place(root, L.crop_bed("radish"), Vector3(-6.25, 0, 1.45))
	place(root, L.crop_bed("strawberry"), Vector3(-3.32, 0, 1.45))
	place(root, L.crop_bed("wheat"), Vector3(-6.25, 0, 4.45))
	place(root, L.crop_bed("pumpkin"), Vector3(-3.32, 0, 4.45))
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
	place(root, F.build(0), Vector3(0.72, 0.08, 1.48), 0.34)
	place(root, F.build(1), Vector3(1.92, 0.08, -0.65), -0.8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 220914
	for i in range(200):
		var x := rng.randf_range(-10.2, 10.1)
		var z := rng.randf_range(-7.65, 7.65)
		if absf(x) < 1.1 or absf(z + 0.64) < 0.91:
			continue
		if z < -1.0 and x > -7.8 and x < 5.5:
			continue
		if x > -7.6 and x < -1.6 and z > -0.1 and z < 5.9:
			continue
		if Vector2((x - 5.6) / 3.0, (z - 4.1) / 2.4).length() < 1.08:
			continue
		if x > 1.0 and x < 6.6 and z > 1.9 and z < 3.5:
			continue
		place(root, L.flowers(i, i % 3 == 0) if i % 4 == 0 else L.grass_clump(i), Vector3(x, 0.027, z), rng.randf_range(0, TAU))
	for i in range(7):
		place(root, L.flowers(i + 1, i % 2 == 0), Vector3(-7.0 + i * 0.61, 0.03, 6.39), i * 0.66)
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
				var pebble := L.stone(rng.randi_range(0, 3), Vector3(rng.randf_range(0.14, 0.205), 0.040, rng.randf_range(0.14, 0.205)))
				place(path_root, pebble, at, rng.randf_range(0, TAU))

static func cottage_study() -> Node3D:
	var root := Node3D.new()
	root.name = "CottageStudy"
	M.box(root, Vector3(0, -0.16, 0.4), Vector3(7.7, 0.3, 7.4), "#9db87e", "GardenPlinth", 0.13)
	place(root, B.cottage(), Vector3(0, 0, -0.2))
	_path(root, [Vector3(0.68, 0, 2.4), Vector3(0.6, 0, 3.86)], 1.20)
	place(root, L.tree(34, true), Vector3(-3.2, 0, -1.3), -0.5, 0.73)
	place(root, L.barrel(), Vector3(2.63, 0, -0.25))
	place(root, L.watering_can(), Vector3(2.74, 0, 1.30), 0.3)
	place(root, L.crate(true), Vector3(-2.58, 0, 2.50), -0.18)
	place(root, F.build(0), Vector3(2.25, 0, 2.45), -0.24)
	for i in range(5):
		place(root, L.flowers(i, true), Vector3(-2.7 + i * 0.52, 0, 3.25), i * 1.2)
	for i in range(12):
		place(root, L.grass_clump(i), Vector3(3.05 + sin(i * 2.4) * 0.22, 0, -2.5 + i * 0.43))
	return root

static func market_study() -> Node3D:
	var root := Node3D.new()
	root.name = "SeedMarketStudy"
	M.box(root, Vector3(0, -0.16, 0.4), Vector3(8.0, 0.3, 7.7), "#a2b884", "MarketGarden", 0.13)
	place(root, B.shop(), Vector3(0, 0, -0.35))
	_path(root, [Vector3(-3.7, 0, 3.35), Vector3(3.7, 0, 3.35)], 1.10)
	place(root, L.tree(76), Vector3(3.50, 0, -2.50), 0.1, 0.66)
	place(root, L.barrel(), Vector3(-2.8, 0, -0.3))
	place(root, L.crate(true), Vector3(2.83, 0, 1.18), -0.1)
	place(root, L.crate(false), Vector3(3.30, 0, 1.75), 0.08)
	place(root, F.build(1), Vector3(-2.29, 0, 2.51), -0.12)
	place(root, L.watering_can(), Vector3(3.17, 0.5, 1.73), -0.42)
	for i in range(5):
		place(root, L.flowers(i, false), Vector3(-3.32, 0, -1.9 + i * 0.51), i * 0.2)
	return root

static func character_study(pair: bool) -> Node3D:
	var root := Node3D.new()
	root.name = "FarmerPair" if pair else "FarmerTurnaround"
	var positions := [-0.67, 0.67] if pair else [-2.1, -0.7, 0.7, 2.1]
	var rotations := [0.18, -0.25] if pair else [0.0, PI * 0.5, PI, -PI * 0.24]
	for i in range(positions.size()):
		var x: float = positions[i]
		M.cylinder(root, Vector3(x, -0.02, 0), 0.53, 0.53, 0.038, "#d3ccb5", "DisplayDisc", 64)
		place(root, F.build(i if pair else 0), Vector3(x, 0, 0), rotations[i])
	if pair:
		place(root, L.crate(true), Vector3(-1.37, 0, 0.12), 0.10, 0.78)
		place(root, L.watering_can(), Vector3(1.18, 0, 0.12), -0.55, 0.9)
	return root
