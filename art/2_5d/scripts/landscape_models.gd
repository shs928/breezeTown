extends RefCounted
## Original modeled plants, terrain and farm props. No third-party art.

const M = preload("res://scripts/art_mesh.gd")
const GREENS := ["#709656", "#88a65d", "#91af66", "#618951", "#a4b975"]

static func terrain() -> Node3D:
	var root := Node3D.new()
	root.name = "MeadowDiorama"
	var surfaces: Array[SurfaceTool] = []
	for layer in range(4):
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		surfaces.append(surface)
	var outline: Array[Vector3] = []
	for i in range(96):
		var theta := float(i) / 96.0 * TAU
		var wave := 1.0 + 0.009 * sin(theta * 11.0) + 0.006 * cos(theta * 17.0)
		outline.append(Vector3(signf(cos(theta)) * pow(absf(cos(theta)), 0.34) * 10.8 * wave, 0, signf(sin(theta)) * pow(absf(sin(theta)), 0.34) * 8.4 * wave))
	for i in range(outline.size()):
		var a := outline[i]
		var b := outline[(i + 1) % outline.size()]
		M.polygon(surfaces[0], [Vector3.ZERO, a, b], Vector3.UP)
		var rings := [Vector2(1.0, 0.0), Vector2(1.002, -0.18), Vector2(0.997, -0.68), Vector2(0.98, -1.04)]
		for r in range(3):
			var p := Vector3(a.x * rings[r].x, rings[r].y, a.z * rings[r].x)
			var q := Vector3(b.x * rings[r].x, rings[r].y, b.z * rings[r].x)
			var p2 := Vector3(a.x * rings[r + 1].x, rings[r + 1].y, a.z * rings[r + 1].x)
			var q2 := Vector3(b.x * rings[r + 1].x, rings[r + 1].y, b.z * rings[r + 1].x)
			M.polygon(surfaces[r + 1], [p, p2, q2, q], Vector3(a.x / 10.8, 0.12, a.z / 8.4).normalized())
	var pigments := ["#98b879", "#809e59", "#af8c65", "#927351"]
	var labels := ["MeadowTop", "SodEdge", "EarthLayer", "OchreBase"]
	for layer in range(4):
		M.mesh_node(root, surfaces[layer].commit(), Vector3.ZERO, M.paint(pigments[layer]), labels[layer])
	var rng := RandomNumberGenerator.new()
	rng.seed = 73913
	for i in range(42):
		var angle := rng.randf_range(0, TAU)
		var x := signf(cos(angle)) * pow(absf(cos(angle)), 0.34) * 10.77
		var z := signf(sin(angle)) * pow(absf(sin(angle)), 0.34) * 8.37
		M.ellipsoid(root, Vector3(x, rng.randf_range(-0.70, -0.35), z), Vector3(rng.randf_range(0.035, 0.09), 0.033, rng.randf_range(0.04, 0.1)), "#c5aa83", "EarthPebble", 8, 4)
	return root

static func meadow_patch(radius_x: float, radius_z: float, hex: String, seed_value: int) -> Node3D:
	var root := Node3D.new()
	root.name = "MeadowPigment"
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(28):
		var a := float(i) / 28.0 * TAU
		var b := float(i + 1) / 28.0 * TAU
		var ar := 1.0 + 0.08 * sin(a * 7 + seed_value)
		var br := 1.0 + 0.08 * sin(b * 7 + seed_value)
		M.polygon(surface, [Vector3(0, 0.013, 0), Vector3(cos(a) * radius_x * ar, 0.013, sin(a) * radius_z * ar), Vector3(cos(b) * radius_x * br, 0.013, sin(b) * radius_z * br)], Vector3.UP)
	M.mesh_node(root, surface.commit(), Vector3.ZERO, M.paint(hex), "TonalWash")
	return root

static func tree(seed_value: int = 1, fruit: bool = false) -> Node3D:
	var root := Node3D.new()
	root.name = "AppleTree" if fruit else "MeadowOak"
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	M.cylinder(root, Vector3(0, 1.15, 0), 0.23, 0.14, 2.30, "#816448", "Trunk", 11)
	for i in range(5):
		var theta := i * TAU / 5.0 + 0.3
		M.beam(root, Vector3(0, 0.14, 0), Vector3(cos(theta) * 0.62, 0.035, sin(theta) * 0.62), 0.19, "#8b6a49", "RootFlare", -1, true)
		var endpoint := Vector3(cos(theta) * 1.02, rng.randf_range(2.45, 2.85), sin(theta) * 0.92)
		M.beam(root, Vector3(0, 1.1 + rng.randf() * 0.45, 0), endpoint, 0.18, "#8d6a48", "Branch", -1, true)
		M.blob(root, endpoint + Vector3(0, 0.17, 0), Vector3(1.08, 0.82, 1.03), GREENS[i], seed_value + i, "LeafCrown")
	M.blob(root, Vector3(-0.07, 3.24, -0.04), Vector3(1.13, 0.88, 1.06), "#9bb86e", seed_value + 8, "SunlitCrown")
	M.blob(root, Vector3(0.34, 2.65, 0.72), Vector3(0.74, 0.58, 0.7), "#87a359", seed_value + 10, "FrontCrown")
	for i in range(22):
		var angle := rng.randf_range(0, TAU)
		var y := rng.randf_range(2.05, 3.4)
		var radius := sqrt(maxf(0.1, 1.0 - pow((y - 2.65) / 1.2, 2))) * rng.randf_range(1.35, 1.68)
		var p := Vector3(cos(angle) * radius, y, sin(angle) * radius)
		if fruit and i % 2 == 0:
			M.ellipsoid(root, p, Vector3(0.135, 0.14, 0.125), "#d67450" if i % 4 == 0 else "#bf5842", "Apple", 12, 7)
			M.beam(root, p + Vector3(0, 0.10, 0), p + Vector3(0.015, 0.19, 0), 0.027, "#715331", "AppleStem", -1, true)
		else:
			var tip := p + Vector3(cos(angle) * 0.18, 0.10, sin(angle) * 0.18)
			M.leaf(root, p, tip, 0.18, "#a8b978", "CrownLeaf")
	return root

static func grass_clump(seed_value: int = 0, height: float = 0.22) -> Node3D:
	var root := Node3D.new()
	root.name = "MeadowGrass"
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 290
	for blade in range(5):
		var angle := rng.randf_range(0, TAU)
		var start := Vector3(rng.randf_range(-0.06, 0.06), 0, rng.randf_range(-0.06, 0.06))
		M.leaf(root, start, Vector3(cos(angle) * height * 0.52, height * rng.randf_range(0.7, 1.3), sin(angle) * height * 0.52), height * 0.36, "#729854" if blade % 2 == 0 else "#a9bc72", "GrassBlade")
	return root

static func flowers(seed_value: int = 0, peach: bool = false) -> Node3D:
	var root := Node3D.new()
	root.name = "Wildflowers"
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 709
	for flower in range(3):
		var p := Vector3(rng.randf_range(-0.22, 0.22), rng.randf_range(0.20, 0.44), rng.randf_range(-0.22, 0.22))
		M.beam(root, Vector3(p.x, 0, p.z), p, 0.018, "#6f8b52", "Stem", -1, true)
		for petal in range(5):
			var angle := petal * TAU / 5.0
			var part := M.ellipsoid(root, p + Vector3(cos(angle) * 0.066, 0, sin(angle) * 0.066), Vector3(0.070, 0.020, 0.035), "#e6a780" if peach else "#fff3cb", "Petal", 8, 4)
			part.rotation.y = -angle
		M.ellipsoid(root, p + Vector3(0, 0.016, 0), Vector3(0.038, 0.027, 0.038), "#dca84c", "Pollen", 8, 4)
	return root

static func fence(length: float = 2.4) -> Node3D:
	var root := Node3D.new()
	root.name = "GardenFence"
	for x in [-length * 0.5, length * 0.5]:
		M.box(root, Vector3(x, 0.45, 0), Vector3(0.17, 0.9, 0.17), "#b89464", "FencePost")
		M.cylinder(root, Vector3(x, 0.94, 0), 0.145, 0.028, 0.16, "#cfb085", "PostCap", 4).rotation.y = PI * 0.25
	for height in [0.29, 0.64]:
		M.box(root, Vector3(0, height, 0.014), Vector3(length, 0.13, 0.105), "#d1b388", "HorizontalRail", 0.024)
	M.beam(root, Vector3(-length * 0.48, 0.27, 0.04), Vector3(length * 0.48, 0.67, 0.04), 0.09, "#bea074", "DiagonalBrace", 0.075)
	for x in [-length * 0.5, length * 0.5]:
		for y in [0.3, 0.65]:
			M.ellipsoid(root, Vector3(x, y, 0.094), Vector3(0.018, 0.018, 0.006), "#796d59", "Peg", 8, 4)
	return root

static func stone(seed_value: int = 0, scale_value: Vector3 = Vector3(0.35, 0.16, 0.26)) -> Node3D:
	var root := Node3D.new()
	root.name = "Fieldstone"
	M.blob(root, Vector3(0, scale_value.y * 0.6, 0), scale_value, ["#b6b29a", "#c9c2a7", "#9aab9b", "#b8baa4"][posmod(seed_value, 4)], seed_value, "WaterwornStone")
	return root

static func crop(kind: String = "radish", seed_value: int = 0) -> Node3D:
	var root := Node3D.new()
	root.name = kind.capitalize()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 532
	match kind:
		"wheat":
			for stalk in range(5):
				var x := rng.randf_range(-0.14, 0.14)
				var z := rng.randf_range(-0.14, 0.14)
				var h := rng.randf_range(0.63, 0.91)
				var bend := rng.randf_range(-0.1, 0.1)
				M.beam(root, Vector3(x, 0, z), Vector3(x + bend, h, z), 0.022, "#b99e52", "WheatStalk", -1, true)
				for tier in range(5):
					for side in [-1, 1]:
						var grain := M.ellipsoid(root, Vector3(x + bend + side * 0.037, h - 0.17 + tier * 0.045, z), Vector3(0.027, 0.052, 0.026), "#dfbd6b" if tier % 2 == 0 else "#ebcf88", "Grain", 8, 4)
						grain.rotation.z = -side * 0.49
				M.leaf(root, Vector3(x, h * 0.45, z), Vector3(x - 0.20, h * 0.75, z + 0.02), 0.06, "#b1ac58", "WheatLeaf")
		"pumpkin":
			for lobe in range(9):
				var angle := lobe * TAU / 9.0
				var piece := M.ellipsoid(root, Vector3(cos(angle) * 0.16, 0.24, sin(angle) * 0.16), Vector3(0.16, 0.25, 0.195), "#df8c40" if lobe % 3 != 0 else "#e89d49", "PumpkinLobe", 12, 8)
				piece.rotation.y = -angle
			M.beam(root, Vector3(0, 0.42, 0), Vector3(0.035, 0.61, -0.02), 0.075, "#6d7541", "Stem", -1, true)
			M.leaf(root, Vector3(0.07, 0.09, 0.03), Vector3(0.42, 0.17, 0.26), 0.34, "#7c944e", "PumpkinLeaf")
			M.leaf(root, Vector3(0.01, 0.08, -0.03), Vector3(-0.39, 0.19, -0.31), 0.31, "#829c54", "PumpkinLeaf")
		"strawberry":
			for l in range(7):
				var angle := l * TAU / 7.0
				M.leaf(root, Vector3(0, 0.05, 0), Vector3(cos(angle) * 0.31, 0.27 + rng.randf() * 0.07, sin(angle) * 0.31), 0.23, "#72964b" if l % 2 == 0 else "#8eac5a", "StrawberryLeaf")
			for b in range(3):
				var angle := b * TAU / 3.0 + 0.5
				var p := Vector3(cos(angle) * 0.22, 0.115, sin(angle) * 0.22)
				M.ellipsoid(root, p, Vector3(0.08, 0.105, 0.075), "#ce6554", "Berry", 12, 7)
				for dot in range(4):
					var theta := dot * TAU / 4.0
					M.ellipsoid(root, p + Vector3(cos(theta) * 0.075, 0.024, sin(theta) * 0.071), Vector3(0.006, 0.013, 0.006), "#f2d494", "BerrySeed", 6, 3)
		_:
			var carrot := kind == "carrot"
			M.ellipsoid(root, Vector3(0, 0.09, 0), Vector3(0.12 if carrot else 0.165, 0.17, 0.12 if carrot else 0.15), "#dd9957" if carrot else "#ca6b71", "RootVegetable", 14, 8)
			for l in range(6):
				var angle := l * TAU / 6.0 + rng.randf() * 0.3
				M.leaf(root, Vector3(0, 0.19, 0), Vector3(cos(angle) * 0.27, rng.randf_range(0.44, 0.58), sin(angle) * 0.27), 0.16 if carrot else 0.21, "#68954f" if l % 2 == 0 else "#8cad61", "VegetableLeaf")
	return root

static func crop_bed(kind: String = "radish", count: int = 3) -> Node3D:
	var root := Node3D.new()
	root.name = "Plot_" + kind
	M.box(root, Vector3(0, 0.052, 0), Vector3(2.30, 0.14, 2.30), "#9e7954", "CultivatedSoil", 0.09)
	for row in range(count):
		var z := (row - (count - 1) * 0.5) * 0.66
		M.ellipsoid(root, Vector3(0, 0.10, z), Vector3(1.04, 0.079, 0.27), "#8b6748" if row % 2 == 0 else "#926d4c", "SoftSoilRidge", 16, 7)
		for col in range(count):
			var plant := crop(kind, col + row * 10)
			plant.position = Vector3((col - (count - 1) * 0.5) * 0.66, 0.10, z)
			plant.rotation.y = (row * 7 + col) * 0.48
			root.add_child(plant)
	for x in [-1.16, 1.16]:
		M.box(root, Vector3(x, 0.10, 0), Vector3(0.10, 0.20, 2.46), "#b0966d", "BedEdging")
	for z in [-1.16, 1.16]:
		M.box(root, Vector3(0, 0.10, z), Vector3(2.42, 0.20, 0.10), "#ba9e75", "BedEdging")
	return root

static func barrel() -> Node3D:
	var root := Node3D.new()
	root.name = "CooperedBarrel"
	M.cylinder(root, Vector3(0, 0.40, 0), 0.32, 0.32, 0.75, "#ac8052", "BarrelCore", 16)
	for i in range(16):
		var theta := i * TAU / 16.0
		var stave := M.box(root, Vector3(cos(theta) * 0.318, 0.4, sin(theta) * 0.318), Vector3(0.12, 0.75, 0.045), "#bf9867" if i % 3 else "#a77d50", "Stave", 0.012)
		stave.rotation.y = PI * 0.5 - theta
	for y in [0.13, 0.64]:
		M.torus(root, Vector3(0, y, 0), 0.346, 0.025, "#60766e", "IronHoop")
	for plank in range(5):
		var x := (plank - 2) * 0.12
		var depth := sqrt(maxf(0.01, 0.30 * 0.30 - x * x)) * 2
		M.box(root, Vector3(x, 0.793, 0), Vector3(0.115, 0.037, depth), "#cfad7b", "LidSlat", 0.009)
	return root

static func crate(filled: bool = false) -> Node3D:
	var root := Node3D.new()
	root.name = "HarvestCrate"
	M.box(root, Vector3(0, 0.045, 0), Vector3(0.75, 0.075, 0.58), "#b58e5f", "CrateFloor")
	for x in [-0.34, 0.34]:
		for z in [-0.255, 0.255]:
			M.box(root, Vector3(x, 0.24, z), Vector3(0.065, 0.48, 0.065), "#cda879", "Corner")
	for row in range(3):
		for z in [-0.27, 0.27]:
			M.box(root, Vector3(0, 0.11 + row * 0.145, z), Vector3(0.72, 0.105, 0.045), "#d1af80" if row % 2 == 0 else "#c39e6e", "CrateSlat", 0.008)
		for x in [-0.36, 0.36]:
			M.box(root, Vector3(x, 0.11 + row * 0.145, 0), Vector3(0.045, 0.105, 0.54), "#cba574", "EndSlat", 0.008)
	if filled:
		for i in range(6):
			M.ellipsoid(root, Vector3((i % 3 - 1) * 0.19, 0.38, (i / 3 - 0.5) * 0.24), Vector3(0.115, 0.12, 0.11), "#c76953" if i % 2 == 0 else "#dbb666", "Harvest", 12, 6)
	return root

static func watering_can() -> Node3D:
	var root := Node3D.new()
	root.name = "SageWateringCan"
	M.cylinder(root, Vector3(0, 0.24, 0), 0.24, 0.20, 0.43, "#82a99b", "CanBody", 20)
	M.torus(root, Vector3(0, 0.458, 0), 0.19, 0.026, "#b8c8ad", "RolledRim")
	M.cylinder(root, Vector3(0, 0.445, 0), 0.16, 0.16, 0.012, "#536f69", "Opening", 20)
	M.beam(root, Vector3(0.18, 0.14, 0), Vector3(0.57, 0.50, 0), 0.13, "#8cb2a4", "Spout", -1, true)
	var nozzle := M.cylinder(root, Vector3(0.60, 0.54, 0), 0.07, 0.16, 0.16, "#b8cbbb", "SprinklerRose", 16)
	nozzle.rotation.z = -0.88
	var handle := M.torus(root, Vector3(-0.22, 0.34, 0), 0.24, 0.034, "#658c81", "Handle")
	handle.rotation.x = PI * 0.5
	return root

static func pond() -> Node3D:
	var root := Node3D.new()
	root.name = "DuckPond"
	M.ellipsoid(root, Vector3(0, -0.07, 0), Vector3(2.65, 0.095, 1.85), "#c3b48a", "ClayBank", 48, 6)
	var water := M.ellipsoid(root, Vector3(0, 0.040, 0), Vector3(2.44, 0.022, 1.66), "#77b3b0", "StillWater", 64, 8)
	var water_material: StandardMaterial3D = M.paint("#77b3b0", 0.31).duplicate()
	water_material.metallic = 0.12
	water.material_override = water_material
	var rng := RandomNumberGenerator.new()
	rng.seed = 727
	for i in range(23):
		var angle := i * TAU / 23.0 + rng.randf() * 0.12
		var pebble := stone(i, Vector3(rng.randf_range(0.14, 0.27), rng.randf_range(0.08, 0.17), rng.randf_range(0.13, 0.24)))
		pebble.position = Vector3(cos(angle) * 2.5, 0.019, sin(angle) * 1.71)
		pebble.rotation.y = angle
		root.add_child(pebble)
	for i in range(4):
		var p := Vector3(-0.55 + i * 0.38, 0.06, 0.63 + sin(i * 3) * 0.24)
		M.ellipsoid(root, p, Vector3(0.20, 0.014, 0.15), "#789d68", "LilyPad", 16, 4)
		if i == 1:
			for petal in range(6):
				var theta := petal * TAU / 6.0
				M.ellipsoid(root, p + Vector3(cos(theta) * 0.045, 0.036, sin(theta) * 0.045), Vector3(0.04, 0.035, 0.028), "#f5d9b8", "WaterLily", 8, 5)
	for i in range(3):
		var ripple := M.torus(root, Vector3(0.65, 0.066, 0.25), 0.28 + i * 0.22, 0.008, "#b2d2c3", "Ripple")
		ripple.scale = Vector3(1.45, 0.4, 0.8)
	var duck := duck_model()
	duck.position = Vector3(0.65, 0.073, 0.22)
	duck.rotation.y = -0.7
	root.add_child(duck)
	var duckling := duck_model()
	duckling.position = Vector3(1.3, 0.073, 0.68)
	duckling.scale = Vector3.ONE * 0.58
	duckling.rotation.y = -0.9
	root.add_child(duckling)
	for p in [Vector3(-2.0, 0.03, -0.9), Vector3(1.85, 0.03, 1.12), Vector3(2.35, 0.03, -0.22)]:
		var reeds := grass_clump(int(p.x * 100), 0.65)
		reeds.position = p
		root.add_child(reeds)
		for i in range(3):
			var tip: Vector3 = p + Vector3(i * 0.07 - 0.07, 0.85 + i * 0.10, i * 0.06)
			M.beam(root, Vector3(tip.x, 0, tip.z), tip, 0.018, "#7d8c53", "ReedStem", -1, true)
			M.ellipsoid(root, tip, Vector3(0.035, 0.13, 0.035), "#987748", "ReedHead", 8, 5)
	return root

static func duck_model() -> Node3D:
	var root := Node3D.new()
	root.name = "PondDuck"
	M.ellipsoid(root, Vector3(0, 0.12, 0), Vector3(0.20, 0.18, 0.30), "#f0ead3", "DuckBody")
	M.ellipsoid(root, Vector3(0, 0.35, 0.18), Vector3(0.125, 0.14, 0.12), "#f4f0dd", "DuckHead")
	M.box(root, Vector3(0, 0.325, 0.32), Vector3(0.105, 0.046, 0.15), "#d69e56", "DuckBill", 0.024)
	for x in [-0.112, 0.112]:
		M.ellipsoid(root, Vector3(x, 0.38, 0.225), Vector3(0.014, 0.018, 0.019), "#39443c", "DuckEye", 8, 4)
		M.ellipsoid(root, Vector3(x * 1.48, 0.15, -0.04), Vector3(0.062, 0.10, 0.18), "#dedac0", "DuckWing", 12, 6)
	return root

static func footbridge() -> Node3D:
	var root := Node3D.new()
	root.name = "ArchedFootbridge"
	for i in range(15):
		var t := i / 14.0
		var x := lerpf(-1.8, 1.8, t)
		var y := 0.13 + sin(t * PI) * 0.29
		var plank := M.box(root, Vector3(x, y, 0), Vector3(0.235, 0.095, 1.12), "#c6a373" if i % 3 == 0 else "#b99664", "BridgePlank", 0.024)
		plank.rotation.z = cos(t * PI) * 0.19
	for side in [-1, 1]:
		for i in range(5):
			var t := i / 4.0
			var x := lerpf(-1.72, 1.72, t)
			var y := 0.15 + sin(t * PI) * 0.29
			M.box(root, Vector3(x, y + 0.34, side * 0.51), Vector3(0.095, 0.79, 0.095), "#ab875a", "BridgePost", 0.023)
			if i < 4:
				var next_t := (i + 1) / 4.0
				M.beam(root, Vector3(x, y + 0.66, side * 0.51), Vector3(lerpf(-1.72, 1.72, next_t), 0.81 + sin(next_t * PI) * 0.29, side * 0.51), 0.095, "#d1b387", "Handrail")
	return root

static func lantern_post() -> Node3D:
	var root := Node3D.new()
	root.name = "LanternPost"
	M.box(root, Vector3(0, 0.89, 0), Vector3(0.15, 1.78, 0.15), "#9d815c", "Post")
	M.box(root, Vector3(0.21, 1.75, 0), Vector3(0.55, 0.12, 0.12), "#b19467", "Arm")
	M.beam(root, Vector3(0, 1.38, 0), Vector3(0.40, 1.75, 0), 0.074, "#a3845a", "Brace")
	M.box(root, Vector3(0.37, 1.4, 0), Vector3(0.23, 0.31, 0.21), "#edcc83", "LanternGlass", 0.04)
	for y in [1.22, 1.58]:
		M.box(root, Vector3(0.37, y, 0), Vector3(0.29, 0.066, 0.27), "#4d7168", "LanternCap")
	for x in [0.265, 0.475]:
		for z in [-0.096, 0.096]:
			M.beam(root, Vector3(x, 1.23, z), Vector3(x, 1.58, z), 0.027, "#5c7467", "LanternFrame")
	return root

static func well() -> Node3D:
	var root := Node3D.new()
	root.name = "GardenWell"
	M.cylinder(root, Vector3(0, 0.35, 0), 0.53, 0.53, 0.7, "#687a6b", "WellInterior", 24)
	for row in range(3):
		for i in range(12):
			var angle := (i + row * 0.5) * TAU / 12.0
			var rock := M.box(root, Vector3(cos(angle) * 0.53, 0.14 + row * 0.23, sin(angle) * 0.53), Vector3(0.26, 0.215, 0.21), ["#b4b5a0", "#c7c3a8", "#a7b09b"][i % 3], "WellStone", 0.055)
			rock.rotation.y = PI * 0.5 - angle
	for x in [-0.71, 0.71]:
		M.box(root, Vector3(x, 0.92, 0), Vector3(0.14, 1.84, 0.16), "#ab895b", "WellPost")
	M.beam(root, Vector3(-0.75, 1.44, 0), Vector3(0.83, 1.44, 0), 0.12, "#886d4c", "Winch", -1, true)
	M.beam(root, Vector3(0, 1.44, 0), Vector3(0, 0.62, 0), 0.025, "#d5bd86", "Rope", -1, true)
	for side in [-1, 1]:
		for tile in range(4):
			var panel := M.box(root, Vector3(side * (0.13 + tile * 0.18), 2.03 - tile * 0.092, 0), Vector3(0.25, 0.078, 1.10), "#698f83" if tile % 2 else "#86a398", "WellRoofTile", 0.033)
			panel.rotation.z = -side * 0.47
	return root
