extends RefCounted
## 牧场区程序化模型：红谷仓、鸡舍、食槽、干草垛，以及牛/羊/鸡与产出物。
## 全部几何原创生成；单位米，Y 向上，正面朝 +Z。

const M = preload("res://scripts/art/art_mesh.gd")
const B = preload("res://scripts/art/building_models.gd")
const AnimalDB = preload("res://scripts/data/animal_db.gd")

## 兼容导出：唯一来源已迁至 data/animal_db.gd。
static var ANIMAL_LABELS: Dictionary = AnimalDB.ANIMAL_LABELS
static var ANIMAL_PRODUCTS: Dictionary = AnimalDB.ANIMAL_PRODUCTS


static func barn() -> Node3D:
	var root := Node3D.new()
	root.name = "Red_Barn"
	root.set_meta("main_footprint_m", Vector2(6.5, 5.0))
	root.set_meta("front", "+Z")
	var p := B._palette()
	p["plaster"] = B._material("Barn_Deep_Red_Board_Gaps", Color("#76372C"))
	p["plaster_light"] = B._material("Barn_Red_Gable", Color("#AE4E39"))
	p["wood"] = B._material("Barn_Cream_Frame", Color("#D6C8A3"))
	p["wood_light"] = B._material("Barn_Sunlit_Frame", Color("#F0DFC0"))
	B._house_shell(root, 6.5, 5.0, 3.12, 5.18, p)
	# 连续三角山墙与两面板瓦构成闭合屋顶，舍弃彼此悬空的屋面薄片。
	B._slate_roof(root, 3.62, 2.86, 3.13, 5.28, p)
	var boards := [B._material("Barn_Cedar_Red", Color("#AC4D37")), B._material("Barn_Cedar_Light", Color("#BD5B40")), B._material("Barn_Cedar_Shadow", Color("#98422F"))]
	for face in [-1.0, 1.0]:
		for i in range(21):
			var x := -3.10 + i * 0.31
			B._box(root, "Vertical_Red_Front_Board", Vector3(0.292, 2.53, 0.085), Vector3(x, 1.66, face * 2.53), boards[i % boards.size()], 0.022)
		for i in range(16):
			var z := -2.35 + i * 0.31
			B._box(root, "Vertical_Red_Side_Board", Vector3(0.085, 2.53, 0.292), Vector3(face * 3.27, 1.66, z), boards[(i + 1) % boards.size()], 0.022)
		for x in [-3.25, 3.25]:
			B._box(root, "Cream_Corner_Post", Vector3(0.25, 2.86, 0.25), Vector3(x, 1.72, face * 2.52), p["wood_light"], 0.035)
		B._box(root, "Broad_Barn_Tie_Beam", Vector3(6.7, 0.23, 0.24), Vector3(0, 3.01, face * 2.58), p["wood_light"], 0.028)
		for side in [-1.0, 1.0]:
			B._beam(root, "Gable_Diagonal_Brace", Vector3(side * 2.70, 3.20, face * 2.58), Vector3(side * 0.67, 4.58, face * 2.58), 0.15, 0.16, p["wood"])
	B._box(root, "Sliding_Door_Deep_Opening", Vector3(2.68, 2.54, 0.13), Vector3(0.80, 1.58, 2.63), p["wood_dark"], 0.035)
	for side in [-1.0, 1.0]:
		var door_x: float = 0.80 + side * 0.62
		B._box(root, "Sliding_Door_Leaf", Vector3(1.20, 2.34, 0.14), Vector3(door_x, 1.57, 2.74), boards[0], 0.02)
		for i in range(4):
			B._box(root, "Door_Red_Plank", Vector3(0.274, 2.26, 0.038), Vector3(door_x - 0.44 + i * 0.293, 1.57, 2.83), boards[(i + 1) % boards.size()], 0.014)
		for x in [-0.54, 0.54]:
			B._box(root, "Door_Vertical_Trim", Vector3(0.11, 2.39, 0.095), Vector3(door_x + x, 1.57, 2.89), p["wood_light"], 0.012)
		for y in [0.43, 2.72]:
			B._box(root, "Door_Horizontal_Trim", Vector3(1.20, 0.13, 0.095), Vector3(door_x, y, 2.89), p["wood_light"], 0.014)
		B._beam(root, "Barn_Door_Cross_Brace", Vector3(door_x - 0.51, 0.49, 2.91), Vector3(door_x + 0.51, 2.66, 2.91), 0.11, 0.075, p["wood_light"])
		B._beam(root, "Barn_Door_Cross_Brace", Vector3(door_x + 0.51, 0.49, 2.91), Vector3(door_x - 0.51, 2.66, 2.91), 0.11, 0.075, p["wood_light"])
		B._box(root, "Iron_Door_Handle", Vector3(0.055, 0.24, 0.11), Vector3(0.80 + side * 0.14, 1.56, 3.0), p["iron"], 0.015)
	B._box(root, "Black_Sliding_Door_Rail", Vector3(3.74, 0.075, 0.11), Vector3(0.80, 2.91, 2.93), p["iron"], 0.01)
	B._front_window(root, "Hayloft_Window", Vector3(0.45, 3.92, 2.57), 0.94, 0.78, p, false)
	B._front_window(root, "Barn_Front_Window", Vector3(-2.07, 1.88, 2.62), 0.75, 0.81, p, false)
	for side in [-1.0, 1.0]:
		var windows := Node3D.new()
		windows.position = Vector3(side * 3.33, 1.86, 0)
		windows.rotation.y = side * PI * 0.5
		root.add_child(windows)
		for x in [-1.25, 1.22]:
			B._front_window(windows, "Barn_Side_Window", Vector3(x, 0, 0), 0.87, 0.83, p, false)
	B._box(root, "Barn_Stone_Threshold", Vector3(2.91, 0.18, 0.61), Vector3(0.80, 0.14, 2.95), p["stone_light"], 0.04)
	B._lantern(root, Vector3(2.45, 2.64, 2.76), p)
	for i in range(2):
		var bale := hay_bale()
		bale.position = Vector3(-2.24, 0.43 + i * 0.71, 3.12 - i * 0.12)
		bale.rotation.y = 0.12 if i == 0 else -0.08
		bale.scale = Vector3.ONE * (1.0 if i == 0 else 0.88)
		root.add_child(bale)
	var fork := Node3D.new()
	fork.name = "Barn_Wall_Pitchfork"
	fork.position = Vector3(-2.98, 0.21, 2.72)
	fork.rotation.z = -0.18
	root.add_child(fork)
	B._cylinder(fork, "Pitchfork_Oak_Handle", 0.03, 0.036, 1.61, Vector3(0, 1.0, 0), p["wood_warm"])
	B._box(fork, "Pitchfork_Iron_Shoulder", Vector3(0.36, 0.09, 0.07), Vector3(0, 0.26, 0), p["iron"], 0.01)
	for i in range(4):
		B._beam(fork, "Pitchfork_Tine", Vector3(-0.135 + i * 0.09, 0.27, 0), Vector3(-0.15 + i * 0.10, 0.03, 0.05), 0.025, 0.025, p["iron"])
	return root


static func coop() -> Node3D:
	var root := Node3D.new()
	root.name = "Chicken_Coop"
	root.set_meta("main_footprint_m", Vector2(2.6, 2.0))
	root.set_meta("front", "+Z")
	var p := B._palette()
	p["plaster"] = B._material("Coop_Honey_Plank_Gaps", Color("#755332"))
	p["plaster_light"] = B._material("Coop_Honey_Gable", Color("#C29356"))
	B._house_shell(root, 2.6, 2.0, 1.47, 2.41, p)
	B._slate_roof(root, 1.55, 1.24, 1.48, 2.48, p)
	for face in [-1.0, 1.0]:
		for i in range(9):
			B._box(root, "Coop_Front_Oak_Board", Vector3(0.273, 1.03, 0.065), Vector3(-1.15 + i * 0.286, 0.91, face * 1.033), p["wood_light"] if i % 3 else p["wood_warm"], 0.018)
		for i in range(7):
			B._box(root, "Coop_Side_Oak_Board", Vector3(0.065, 1.03, 0.267), Vector3(face * 1.325, 0.91, -0.86 + i * 0.286), p["wood_light"] if i % 3 else p["wood_warm"], 0.018)
	# 鸡门的轮廓沿 XY 挤出，正面朝 +Z；深黑洞口不会再画成水平圆盘。
	B._extruded_outline(root, "Chicken_Door_Heavy_Arch", B._arch_outline(0.72, 0.94), 0.18, Vector3(0.53, 0.25, 1.11), p["wood_dark"])
	B._extruded_outline(root, "Chicken_Door_Dark_Interior", B._arch_outline(0.51, 0.75), 0.045, Vector3(0.53, 0.28, 1.225), B._material("Coop_Door_Interior", Color("#24281F")))
	B._box(root, "Raised_Chicken_Hatch", Vector3(0.62, 0.24, 0.07), Vector3(0.53, 1.28, 1.21), p["wood_warm"], 0.022)
	for side in [-1.0, 1.0]:
		B._box(root, "Hatch_Slide_Rail", Vector3(0.07, 1.05, 0.10), Vector3(0.53 + side * 0.36, 0.85, 1.22), p["wood"], 0.013)
	var ramp := B._box(root, "Sloping_Chicken_Ramp", Vector3(0.66, 0.085, 1.12), Vector3(0.53, 0.20, 1.69), p["wood_light"], 0.018)
	ramp.rotation.x = 0.28
	for step in range(5):
		var t := step / 4.0
		var cleat := B._box(root, "Ramp_Cleat", Vector3(0.68, 0.045, 0.08), Vector3(0.53, lerpf(0.38, 0.09, t), lerpf(1.18, 2.22, t)), p["wood"], 0.008)
		cleat.rotation.x = 0.28
	B._front_window(root, "Coop_Square_Window", Vector3(-0.73, 1.02, 1.08), 0.54, 0.46, p, false)
	B._box(root, "Projecting_Nesting_Box", Vector3(0.66, 0.64, 1.29), Vector3(-1.51, 0.76, -0.15), p["wood_warm"], 0.04)
	var lid := B._box(root, "Slanted_Nest_Box_Lid", Vector3(0.86, 0.10, 1.47), Vector3(-1.59, 1.12, -0.15), B._material("Nest_Blue_Lid", Color("#49718A")), 0.025)
	lid.rotation.z = 0.15
	for z in [-0.60, 0.3]:
		B._box(root, "Nest_Box_Iron_Hinge", Vector3(0.16, 0.05, 0.07), Vector3(-1.30, 1.17, z), p["iron"], 0.01)
	B._cylinder(root, "Coop_Feed_Bowl", 0.27, 0.22, 0.13, Vector3(-0.85, 0.13, 1.58), p["terra"])
	B._cylinder(root, "Coop_Bowl_Shadow", 0.23, 0.23, 0.015, Vector3(-0.85, 0.194, 1.58), p["soil"])
	for i in range(13):
		var angle := i * 2.399
		var radius := 0.046 + (i % 4) * 0.041
		var grain := B._sphere(root, "Scattered_Chicken_Grain", 0.025, Vector3(-0.85 + cos(angle) * radius, 0.211, 1.58 + sin(angle) * radius), p["canvas_gold"])
		grain.scale = Vector3(0.65, 0.45, 1.0)
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
	# 花斑用暖棕大块面包裹体侧并盖过背脊，俯视相机下也能一眼认出奶牛（参考图牲畜可读性）。
	var patch_tones := ["#8a5a3f", "#7b4e35", "#93644a"]
	for i in range(6):
		var patch := M.blob(root, Vector3(
			rng.randf_range(-0.42, 0.42), rng.randf_range(0.92, 1.24), rng.randf_range(-0.72, 0.66)
		), Vector3(0.32, 0.26, 0.38), patch_tones[(variant_seed + i) % patch_tones.size()], variant_seed + i, "HidePatch")
		patch.scale = Vector3(1, 0.82, 1)
	var neck := M.ellipsoid(root, Vector3(0, 1.10, 0.72), Vector3(0.24, 0.26, 0.30), "#ece7db", "Neck")
	var head := Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, 1.22, 0.98)
	root.add_child(head)
	M.ellipsoid(head, Vector3.ZERO, Vector3(0.24, 0.21, 0.29), "#ece7db", "Skull")
	M.ellipsoid(head, Vector3(0, 0.10, -0.10), Vector3(0.17, 0.12, 0.16), patch_tones[variant_seed % patch_tones.size()], "HeadPatch", 12, 7)
	M.ellipsoid(head, Vector3(0, -0.06, 0.20), Vector3(0.17, 0.13, 0.14), "#d9a28f", "Muzzle", 16, 8)
	M.ellipsoid(head, Vector3(0, -0.13, 0.27), Vector3(0.08, 0.035, 0.05), "#c78f7d", "MuzzleTip", 10, 5)
	for side in [-1, 1]:
		M.ellipsoid(head, Vector3(side * 0.25, 0.06, -0.02), Vector3(0.11, 0.065, 0.045), "#e0d9c9", "Ear", 10, 5)
		var horn := M.cylinder(head, Vector3(side * 0.13, 0.20, -0.02), 0.021, 0.038, 0.19, "#d8c9a8", "Horn", 8)
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
