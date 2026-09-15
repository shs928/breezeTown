extends RefCounted
## 牧场区程序化模型：红谷仓、鸡舍、食槽、干草垛，以及牛/羊/鸡与产出物。
## 全部几何原创生成；单位米，Y 向上，正面朝 +Z。

const M = preload("res://scripts/art/art_mesh.gd")

const ANIMAL_LABELS := {"cow": "奶牛", "sheep": "绵羊", "chicken": "母鸡"}
const ANIMAL_PRODUCTS := {"cow": "milk", "sheep": "wool", "chicken": "egg"}


static func barn() -> Node3D:
	var root := Node3D.new()
	root.name = "Red_Barn"
	root.set_meta("main_footprint_m", Vector2(6.5, 5.0))
	root.set_meta("front", "+Z")
	var stone := M.paint("#8c8977")
	var red := M.paint("#a84b3d")
	var red_light := M.paint("#b85c4c")
	var white := M.paint("#ece5d8")
	var wood := M.paint("#8e6040")
	var wood_dark := M.paint("#654737")
	var roof_paint := M.paint("#5d6b66")
	var glass := M.paint("#739e9f", 0.38)
	M.box(root, Vector3(0, 0.17, 0), Vector3(7.0, 0.34, 5.5), "#8c8977", "StoneFoundation", 0.07)
	M.box(root, Vector3(0, 1.60, 0), Vector3(6.5, 2.55, 5.0), "#a84b3d", "BarnWalls", 0.06)
	# 四角白色包边与横向饰条。
	for x in [-3.25, 3.25]:
		M.box(root, Vector3(x, 1.62, 0), Vector3(0.17, 2.6, 0.17), "#ece5d8", "CornerTrim", 0.02)
	for z in [-2.5, 2.5]:
		M.box(root, Vector3(0, 2.62, z), Vector3(6.55, 0.16, 0.16), "#ece5d8", "WallTrim", 0.02)
	# 复折式（gambrel）屋顶：下坡陡、上坡缓。
	for side in [-1.0, 1.0]:
		var lower := M.box(root, Vector3(0, 2.55 + 0.72, side * 2.62), Vector3(6.9, 0.13, 1.92), "#5d6b66", "LowerRoofSlope", 0.03)
		lower.rotation.x = side * 0.86
		var upper := M.box(root, Vector3(0, 3.62, side * 1.32), Vector3(6.7, 0.12, 1.62), "#66756f", "UpperRoofSlope", 0.03)
		upper.rotation.x = side * 0.42
		M.box(root, Vector3(side * 3.45, 3.30, 0), Vector3(0.14, 0.9, 5.3), "#596762", "RoofGable", 0.02)
	M.box(root, Vector3(0, 3.98, 0), Vector3(6.85, 0.16, 0.3), "#4d5a55", "RoofRidge", 0.03)
	# 前脸：大滑门（白边 + 交叉木撑）、上面草料门与通风窗。
	M.box(root, Vector3(0.9, 1.42, 2.51), Vector3(2.5, 2.3, 0.1), "#8e6040", "DoorOpening", 0.02)
	var door := Node3D.new()
	door.name = "SlidingDoor"
	door.position = Vector3(0.9, 1.42, 2.56)
	root.add_child(door)
	M.box(door, Vector3.ZERO, Vector3(2.3, 2.1, 0.09), "#9c4f41", "DoorPanel", 0.02)
	for brace in [-1.0, 1.0]:
		var plank := M.box(door, Vector3.ZERO, Vector3(2.55, 0.18, 0.05), "#ece5d8", "DoorBrace", 0.012)
		plank.rotation.z = brace * 0.72
	M.box(door, Vector3(0, 0.75, 0.06), Vector3(2.4, 0.16, 0.05), "#ece5d8", "DoorTopTrim", 0.012)
	M.box(door, Vector3(0, -0.05, 0.06), Vector3(1.5, 0.5, 0.03), "#654737", "DoorSlats", 0.01)
	M.box(root, Vector3(0.9, 3.55, 2.48), Vector3(1.15, 1.0, 0.12), "#654737", "HayloftOpening", 0.02)
	M.box(root, Vector3(0.9, 3.55, 2.53), Vector3(1.3, 1.15, 0.08), "#9c4f41", "HayloftDoor", 0.02)
	var loft_trim := M.box(root, Vector3(0.9, 4.18, 2.54), Vector3(1.35, 0.12, 0.1), "#ece5d8", "HayloftTrim", 0.015)
	loft_trim.rotation.z = 0.0
	for x in [-2.0, 2.6]:
		M.box(root, Vector3(x, 1.85, 2.52), Vector3(0.72, 0.72, 0.08), "#739e9f", "WindowGlass", 0.012)
		M.box(root, Vector3(x, 1.85, 2.56), Vector3(0.84, 0.84, 0.05), "#ece5d8", "WindowFrame", 0.012)
		M.box(root, Vector3(x, 1.85, 2.58), Vector3(0.05, 0.72, 0.03), "#ece5d8", "WindowMullion", 0.008)
	return root


static func coop() -> Node3D:
	var root := Node3D.new()
	root.name = "Chicken_Coop"
	root.set_meta("main_footprint_m", Vector2(2.6, 2.0))
	M.box(root, Vector3(0, 0.10, 0), Vector3(2.85, 0.2, 2.25), "#8c8977", "CoopFoundation", 0.05)
	M.box(root, Vector3(0, 0.78, 0), Vector3(2.6, 1.05, 2.0), "#b48658", "CoopWalls", 0.04)
	var roof := M.box(root, Vector3(0, 1.55, -0.12), Vector3(2.95, 0.1, 2.5), "#68998a", "CoopRoof", 0.03)
	roof.rotation.x = -0.22
	M.box(root, Vector3(0, 1.95, 0.95), Vector3(2.95, 0.42, 0.1), "#8e6040", "RoofGable", 0.02)
	M.cylinder(root, Vector3(0.62, 0.46, 1.01), 0.20, 0.20, 0.05, "#654737", "RoundDoor", 16)
	var ramp := M.box(root, Vector3(0.62, 0.20, 1.45), Vector3(0.42, 0.05, 0.95), "#b48658", "CoopRamp", 0.012)
	ramp.rotation.x = -0.18
	for strip in range(3):
		M.box(root, Vector3(0.62, 0.30 + strip * 0.014, 1.18 + strip * 0.22), Vector3(0.44, 0.03, 0.05), "#8e6040", "RampCleat", 0.008)
	M.box(root, Vector3(-0.85, 0.95, 0.6), Vector3(0.7, 0.45, 0.5), "#b48658", "NestBox", 0.03)
	var lid := M.box(root, Vector3(-0.85, 1.22, 0.6), Vector3(0.78, 0.06, 0.55), "#68998a", "NestLid", 0.015)
	lid.rotation.x = 0.28
	M.box(root, Vector3(-1.12, 1.06, 0.86), Vector3(0.5, 0.16, 0.1), "#8e6040", "NestLedge", 0.012)
	return root


static func trough() -> Node3D:
	var root := Node3D.new()
	root.name = "Feeding_Trough"
	M.box(root, Vector3(0, 0.34, 0), Vector3(1.9, 0.30, 0.58), "#8b6a49", "TroughBody", 0.035)
	M.box(root, Vector3(0, 0.50, 0), Vector3(1.72, 0.05, 0.44), "#654737", "TroughInner", 0.015)
	for x in [-0.82, 0.82]:
		for z in [-0.22, 0.22]:
			M.box(root, Vector3(x, 0.10, z), Vector3(0.10, 0.20, 0.10), "#654737", "TroughLeg", 0.012)
	var hay := Node3D.new()
	hay.name = "Hay"
	root.add_child(hay)
	for i in range(5):
		var wisp := M.ellipsoid(hay, Vector3(-0.72 + i * 0.36, 0.52 + 0.04 * (i % 2), (i % 3 - 1) * 0.09), Vector3(0.13, 0.055, 0.15), "#d8b35b", "HayWisp", 8, 4)
		wisp.rotation.y = i * 0.7
	return root


static func hay_bale() -> Node3D:
	var root := Node3D.new()
	root.name = "Hay_Bale"
	var roll := M.cylinder(root, Vector3.ZERO, 0.42, 0.42, 0.82, "#cfa552", "BaleCore", 18)
	roll.rotation.z = PI * 0.5
	for x in [-0.26, 0.26]:
		var strap := M.torus(root, Vector3(x, 0, 0), 0.43, 0.022, "#8a6b3f", "BaleStrap")
		strap.rotation.z = PI * 0.5
	for i in range(10):
		var strand := M.beam(root, Vector3(0.42, 0, 0), Vector3(0.47, 0.12 * (i % 3 - 1), 0.05 * (i - 5)), 0.02, "#bd9445", "BaleStrand", -1, true)
		strand.position.x = 0.42
		strand.quaternion = Quaternion(Vector3.RIGHT, Vector3(0.47, 0.12 * (i % 3 - 1), 0.05 * (i - 5)).normalized())
	return root


static func animal_model(kind: String, variant_seed: int = 0) -> Node3D:
	match kind:
		"sheep":
			return _sheep(variant_seed)
		"chicken":
			return _chicken(variant_seed)
		_:
			return _cow(variant_seed)


static func _cow(variant_seed: int) -> Node3D:
	var root := Node3D.new()
	root.name = "Dairy_Cow"
	var rng := RandomNumberGenerator.new()
	rng.seed = variant_seed
	var white := M.paint("#ece7db")
	var white_dim := M.paint("#e0d9c9")
	for x in [-0.30, 0.30]:
		for z in [-0.34, 0.38]:
			M.box(root, Vector3(x, 0.30, z), Vector3(0.19, 0.62, 0.22), "#ece7db", "Leg", 0.03)
			M.box(root, Vector3(x, 0.02, z), Vector3(0.20, 0.06, 0.23), "#4a423a", "Hoof", 0.015)
	M.ellipsoid(root, Vector3(0, 0.88, 0), Vector3(0.62, 0.56, 0.98), "#ece7db", "Body")
	M.ellipsoid(root, Vector3(0, 0.52, -0.28), Vector3(0.26, 0.10, 0.22), "#e8b7ad", "Udder", 14, 7)
	for i in range(3):
		var patch := M.blob(root, Vector3(rng.randf_range(-0.3, 0.3), 0.98 + rng.randf_range(0.0, 0.14), rng.randf_range(-0.5, 0.5)), Vector3(0.26, 0.14, 0.30), "#3c3a36", variant_seed + i, "HidePatch")
		patch.scale = Vector3(1, 0.5, 1)
	var neck := M.ellipsoid(root, Vector3(0, 1.10, 0.72), Vector3(0.24, 0.26, 0.30), "#ece7db", "Neck")
	var head := Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, 1.22, 0.98)
	root.add_child(head)
	M.ellipsoid(head, Vector3.ZERO, Vector3(0.22, 0.20, 0.28), "#ece7db", "Skull")
	M.ellipsoid(head, Vector3(0, -0.06, 0.20), Vector3(0.17, 0.13, 0.14), "#d9a28f", "Muzzle", 16, 8)
	M.ellipsoid(head, Vector3(0, -0.13, 0.27), Vector3(0.08, 0.035, 0.05), "#c78f7d", "MuzzleTip", 10, 5)
	for side in [-1, 1]:
		M.ellipsoid(head, Vector3(side * 0.23, 0.06, -0.02), Vector3(0.10, 0.06, 0.04), "#e0d9c9", "Ear", 10, 5)
		var horn := M.cylinder(head, Vector3(side * 0.12, 0.20, -0.02), 0.018, 0.035, 0.16, "#d8c9a8", "Horn", 8)
		horn.rotation.z = side * -0.5
		M.ellipsoid(head, Vector3(side * 0.13, 0.06, 0.17), Vector3(0.028, 0.033, 0.02), "#39332d", "Eye", 8, 5)
	var tail := M.beam(root, Vector3(0, 1.05, -0.92), Vector3(0, 0.55, -1.12), 0.035, "#e0d9c9", "Tail", -1, true)
	tail.quaternion = Quaternion(Vector3.UP, Vector3(0, -0.5, -0.2).normalized())
	M.blob(root, Vector3(0, 0.5, -1.14), Vector3(0.07, 0.09, 0.07), "#3c3a36", variant_seed + 9, "TailTuft")
	return root


static func _sheep(variant_seed: int) -> Node3D:
	var root := Node3D.new()
	root.name = "Woolly_Sheep"
	var dark := M.paint("#4a4640")
	for x in [-0.22, 0.22]:
		for z in [-0.28, 0.30]:
			M.box(root, Vector3(x, 0.24, z), Vector3(0.13, 0.50, 0.14), "#4a4640", "Leg", 0.02)
	M.blob(root, Vector3(0, 0.72, 0), Vector3(0.52, 0.44, 0.68), "#e8e2d2", variant_seed, "Fleece")
	M.blob(root, Vector3(0, 0.86, 0.12), Vector3(0.44, 0.30, 0.44), "#efe9dc", variant_seed + 3, "FleeceCrown")
	var head := Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, 0.92, 0.60)
	root.add_child(head)
	M.ellipsoid(head, Vector3.ZERO, Vector3(0.13, 0.14, 0.20), "#4a4640", "Face")
	M.ellipsoid(head, Vector3(0, -0.05, 0.15), Vector3(0.09, 0.07, 0.08), "#5c564e", "Muzzle", 10, 6)
	M.blob(head, Vector3(0, 0.10, -0.06), Vector3(0.15, 0.12, 0.12), "#e8e2d2", variant_seed + 5, "Forelock")
	for side in [-1, 1]:
		var ear := M.ellipsoid(head, Vector3(side * 0.14, 0.03, 0.0), Vector3(0.075, 0.032, 0.035), "#5c564e", "Ear", 8, 4)
		ear.rotation.z = side * 0.5
		M.ellipsoid(head, Vector3(side * 0.08, 0.05, 0.12), Vector3(0.02, 0.025, 0.015), "#211f1c", "Eye", 6, 4)
	M.ellipsoid(root, Vector3(0, 0.72, -0.62), Vector3(0.10, 0.10, 0.14), "#e8e2d2", "TailNub", 8, 5)
	return root


static func _chicken(variant_seed: int) -> Node3D:
	var root := Node3D.new()
	root.name = "Hen"
	var feather := "#efe9dc"
	var feather_dim := "#ddd5c2"
	for x in [-0.055, 0.055]:
		M.cylinder(root, Vector3(x, 0.09, 0.01), 0.016, 0.013, 0.19, "#d69e56", "Leg", 6)
		M.ellipsoid(root, Vector3(x, 0.012, 0.05), Vector3(0.045, 0.012, 0.02), "#d69e56", "Foot", 6, 3)
	M.ellipsoid(root, Vector3(0, 0.31, 0), Vector3(0.16, 0.17, 0.21), "#efe9dc", "Body", 18, 10)
	var head := Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, 0.50, 0.11)
	root.add_child(head)
	M.ellipsoid(head, Vector3.ZERO, Vector3(0.075, 0.085, 0.08), "#efe9dc", "Skull", 14, 8)
	var beak := M.cylinder(head, Vector3(0, -0.005, 0.09), 0.012, 0.03, 0.07, "#e0862f", "Beak", 6)
	beak.rotation.x = PI * 0.5
	M.ellipsoid(head, Vector3(0, -0.045, 0.075), Vector3(0.018, 0.025, 0.015), "#c9432f", "Wattle", 6, 4)
	for i in range(3):
		M.ellipsoid(head, Vector3(0, 0.088, 0.02 - i * 0.028), Vector3(0.014, 0.028 - i * 0.005, 0.022), "#c9432f", "Comb", 6, 4)
	for side in [-1, 1]:
		M.ellipsoid(head, Vector3(side * 0.072, 0.01, -0.01), Vector3(0.008, 0.022, 0.022), "#e0862f", "EyePatch", 6, 4)
	var tail := Node3D.new()
	tail.name = "Tail"
	tail.position = Vector3(0, 0.36, -0.17)
	tail.rotation.x = -0.6
	root.add_child(tail)
	for i in range(3):
		var feather_node := M.ellipsoid(tail, Vector3(0, 0.02, -0.02 - i * 0.015), Vector3(0.035, 0.12 - i * 0.02, 0.02), feather_dim if i % 2 else feather, "TailFeather", 8, 4)
		feather_node.rotation.x = i * 0.25
	for side in [-1, 1]:
		var wing := M.ellipsoid(root, Vector3(side * 0.145, 0.32, -0.02), Vector3(0.035, 0.11, 0.15), "#ddd5c2", "Wing", 10, 6)
		wing.rotation.z = side * 0.2
	return root


static func product_model(kind: String) -> Node3D:
	var root := Node3D.new()
	match kind:
		"wool":
			root.name = "Wool_Bundle"
			M.blob(root, Vector3(0, 0.10, 0), Vector3(0.14, 0.10, 0.14), "#efe9dc", 31, "WoolFluff")
			var band := M.torus(root, Vector3(0, 0.10, 0), 0.11, 0.014, "#b5874f", "WoolBand")
			band.rotation.x = PI * 0.5
		"egg":
			root.name = "Farm_Egg"
			M.ellipsoid(root, Vector3(0, 0.075, 0), Vector3(0.055, 0.072, 0.055), "#f3ead6", "Shell", 14, 9)
			M.ellipsoid(root, Vector3(0, 0.118, 0.02), Vector3(0.03, 0.018, 0.03), "#faf3e3", "ShellSheen", 8, 4)
		_:
			root.name = "Milk_Jug"
			M.cylinder(root, Vector3(0, 0.11, 0), 0.085, 0.095, 0.22, "#e8e4da", "JugBody", 16)
			M.cylinder(root, Vector3(0, 0.235, 0), 0.062, 0.082, 0.06, "#dcd7ca", "JugShoulder", 14)
			M.cylinder(root, Vector3(0, 0.28, 0), 0.032, 0.032, 0.055, "#cfc9ba", "JugNeck", 10)
			var handle := M.torus(root, Vector3(0.085, 0.20, 0), 0.045, 0.011, "#dcd7ca", "JugHandle")
			handle.rotation.y = PI * 0.5
			M.ellipsoid(root, Vector3(0, 0.012, 0), Vector3(0.09, 0.015, 0.09), "#c2bcae", "JugBase", 12, 5)
	return root
