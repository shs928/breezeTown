extends RefCounted
## 与山谷共用的低饱和几何美术：切面岩壁、木支架、矿轨与发光晶簇。

const M = preload("res://scripts/art/art_mesh.gd")
const Layout = preload("res://scripts/mine_layout.gd")
const StaticGeometry = preload("res://scripts/art/static_geometry.gd")
const FONT = preload("res://resources/ui_font.tres")
const ORE_COLORS := {"stone": "#a7a49a", "copper": "#e4a16b", "iron": "#b6cad8", "coal": "#424850", "crystal": "#afa7f3", "slime": "#8bbb79"}
static var _glow_materials := {}


static func glow_material(color: String, energy: float = 0.6) -> StandardMaterial3D:
	var key := color + str(energy)
	if not _glow_materials.has(key):
		var material := M.paint(color, 0.55).duplicate() as StandardMaterial3D
		material.emission_enabled = true
		material.emission = Color(color)
		material.emission_energy_multiplier = energy
		_glow_materials[key] = material
	return _glow_materials[key]


static func crystal(root: Node3D, at: Vector3, height: float, color: String, lean: float = 0.0) -> void:
	var cluster := Node3D.new()
	cluster.position = at
	cluster.rotation.z = lean
	root.add_child(cluster)
	M.cylinder(cluster, Vector3(0, height * 0.34, 0), height * 0.18, height * 0.15, height * 0.68, color, "CrystalPrism", 6).material_override = glow_material(color, 0.3)
	M.cylinder(cluster, Vector3(0, height * 0.83, 0), height * 0.15, 0, height * 0.32, color, "CrystalPoint", 6).material_override = glow_material(color, 0.4)


static func signboard(root: Node3D, text: String, at: Vector3, width: float = 2.4) -> Label3D:
	M.box(root, at, Vector3(width, 0.56, 0.13), "#72593e", "WoodSign", 0.06)
	var label := Label3D.new()
	label.font = FONT
	label.text = text
	label.font_size = 42
	label.pixel_size = 0.009
	label.modulate = Color("#ffe3aa")
	label.outline_size = 3
	label.position = at + Vector3(0, 0, 0.08)
	root.add_child(label)
	return label


static func lantern(root: Node3D, at: Vector3, color: Color = Color("#ffd393"), light: bool = true) -> void:
	var hex := "#" + color.to_html(false)
	M.box(root, at, Vector3(0.24, 0.36, 0.24), hex, "LanternGlass", 0.025).material_override = glow_material(hex, 1.1)
	for y in [-0.20, 0.20]:
		M.box(root, at + Vector3(0, y, 0), Vector3(0.31, 0.065, 0.31), "#514739", "LanternCap")
	for x in [-0.13, 0.13]:
		M.beam(root, at + Vector3(x, -0.18, 0.13), at + Vector3(x, 0.18, 0.13), 0.024, "#625442", "LanternFrame")
	if light:
		var lamp := OmniLight3D.new()
		lamp.position = at + Vector3(0, 0.2, 0.15)
		lamp.light_color = color
		lamp.light_energy = 1.7
		lamp.omni_range = 7.5
		lamp.omni_attenuation = 1.4
		root.add_child(lamp)


static func entrance() -> Node3D:
	var root := Node3D.new()
	root.name = "MountainMineEntrance"
	for i in range(9):
		var x := (i - 4) * 1.25
		var height := 5.5 - absf(x) * 0.37
		M.ellipsoid(root, Vector3(x, height * 0.45, -0.5), Vector3(2.2, height * 0.7, 3.0), "#858c7d" if i % 2 else "#727c70", "MineCliff", 9, 5)
	M.box(root, Vector3(0, 1.6, 2.68), Vector3(3.3, 3.2, 0.18), "#222b2c", "DarkTunnel", 0.13)
	for x in [-1.83, 1.83]:
		M.box(root, Vector3(x, 1.65, 2.8), Vector3(0.44, 3.3, 0.62), "#98774f", "PortalPost", 0.06)
		M.box(root, Vector3(x, 0.2, 2.8), Vector3(0.70, 0.40, 0.90), "#aca891", "PortalFoot", 0.05)
		lantern(root, Vector3(x * 1.45, 1.8, 2.55), Color("#ffd393"), false)
	M.box(root, Vector3(0, 3.3, 2.8), Vector3(4.5, 0.5, 0.70), "#b19162", "PortalLintel", 0.07)
	M.beam(root, Vector3(-1.6, 2.45, 3.16), Vector3(-0.75, 3.08, 3.16), 0.2, "#765b40", "DiagonalBrace")
	M.beam(root, Vector3(1.6, 2.45, 3.16), Vector3(0.75, 3.08, 3.16), 0.2, "#765b40", "DiagonalBrace")
	signboard(root, "星辉矿场", Vector3(0, 3.9, 3.2), 3.2)
	M.box(root, Vector3(0, 0.025, 3.8), Vector3(5.0, 0.05, 5.0), "#a29477", "MineApron", 0.01)
	for i in range(7):
		M.box(root, Vector3(0, 0.09, 1.4 + i * 0.65), Vector3(1.55, 0.12, 0.19), "#807052", "Sleeper")
	for x in [-0.55, 0.55]:
		M.box(root, Vector3(x, 0.18, 3.45), Vector3(0.08, 0.12, 4.8), "#69746c", "MineRail")
	var cart := minecart()
	cart.position = Vector3(3.65, 0, 3.25)
	cart.rotation.y = -0.25
	root.add_child(cart)
	return root


static func shell(layout: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "CavernShell"
	var open: Dictionary = layout["open"]
	var palette: Dictionary = layout["theme"]
	var depth: int = layout["depth"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 749 + depth * 7919
	M.box(root, Vector3(0, -0.7, 0), Vector3(220, 0.4, 220), "#262b36", "UndergroundBackdrop", 0)
	var floor_surface := SurfaceTool.new()
	floor_surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for x in range(Layout.GRID.x):
		for z in range(Layout.GRID.y):
			var cell := Vector2i(x, z)
			var at := Layout.center(cell)
			if open.has(cell):
				M.box(root, at + Vector3(0, -0.11, 0), Vector3(2.02, 0.21, 2.02), palette["floor"], "CaveFloor", 0.015)
				var midpoint := at + Vector3(rng.randf_range(-0.35, 0.35), 0.006, rng.randf_range(-0.35, 0.35))
				var corners := [at + Vector3(-1, 0.006, -1), at + Vector3(1, 0.006, -1), at + Vector3(1, 0.006, 1), at + Vector3(-1, 0.006, 1)]
				for i in range(4):
					var shade := rng.randf_range(0.97, 1.02)
					M.polygon(floor_surface, [midpoint, corners[i], corners[(i + 1) % 4]], Vector3.UP, Color(shade, shade, shade))
				if rng.randf() < 0.14:
					var scratch := at + Vector3(rng.randf_range(-0.6, 0.6), 0.02, rng.randf_range(-0.6, 0.6))
					M.beam(root, scratch, scratch + Vector3(0.24, 0, 0.17), 0.018, palette["wall"], "StoneFissure")
				if rng.randf() < 0.24:
					for i in range(3):
						M.ellipsoid(root, at + Vector3(rng.randf_range(-0.8, 0.8), 0.035, rng.randf_range(-0.8, 0.8)), Vector3(0.09, 0.035, 0.07), palette["cap"], "Gravel", 6, 3)
				continue
			var near_floor := false
			for dx in range(-2, 3):
				for dz in range(-2, 3):
					if open.has(cell + Vector2i(dx, dz)):
						near_floor = true
			if not near_floor:
				continue
			var height := rng.randf_range(2.7, 3.7)
			# 面向相机的南侧岩壁采用切面剖视，避免挡住玩家与可采矿石。
			if open.has(cell + Vector2i.UP) or open.has(cell + Vector2i.UP * 2):
				height = 0.9 if z > 14 else 1.25
			rock_column(root, at, Vector3(1.12, height, 1.12), palette["wall"], palette["cap"], x * 37 + z * 13 + depth)
			if depth >= 4 and (x * 3 + z) % 7 == 0:
				crystal(root, at + Vector3(0.30, height, 0.15), rng.randf_range(0.45, 1.0), "#99c2c6" if depth <= 6 else "#aaa1df", -0.12)
	M.mesh_node(root, floor_surface.commit(), Vector3.ZERO, M.paint(palette["floor"]), "UnevenStoneFloor")
	# 入口轨道与主矿室之间留有明显的行进方向。
	for z in range(12, 20):
		var at := Layout.center(Vector2i(12, z))
		for offset in [-0.62, 0.0, 0.62]:
			M.box(root, at + Vector3(0, 0.038, offset), Vector3(1.5, 0.07, 0.17), "#786148", "RailSleeper", 0.01)
		for side in [-0.53, 0.53]:
			M.box(root, at + Vector3(side, 0.10, 0), Vector3(0.075, 0.08, 2.02), "#9b9d90", "Rail", 0.01)
	for z in [16, 11, 6]:
		var at := Layout.center(Vector2i(12, z))
		for side in [-1, 1]:
			M.box(root, at + Vector3(side * 2.8, 1.45, 0), Vector3(0.30, 2.9, 0.36), "#856747", "TunnelSupport", 0.045)
			M.beam(root, at + Vector3(side * 2.7, 2.45, 0), at + Vector3(side * 1.85, 3.05, 0), 0.22, "#9d7b51", "RoofBrace")
			lantern(root, at + Vector3(side * 2.65, 2.15, 0.18), Color("#ffd393") if z != 6 else palette["light"])
		# 只有细梁跨越通道，镜头仍能看清人物。
		M.box(root, at + Vector3(0, 3.15, 0), Vector3(6.0, 0.26, 0.34), "#a5885a", "TunnelBeam", 0.03)
	for cell: Vector2i in layout["decorations"]:
		var corner := Layout.center(cell)
		if depth >= 4:
			M.cylinder(root, corner + Vector3(0, 0.016, 0), 1.2, 1.2, 0.02, "#527d85" if depth <= 6 else "#716ca1", "ShallowMineralPool", 16)
			for i in range(3):
				crystal(root, corner + Vector3(i * 0.38 - 0.4, 0, -0.3), 0.45 + i * 0.2, "#89c5c9" if depth <= 6 else "#b7a5ee", (i - 1) * 0.2)
		else:
			M.box(root, corner + Vector3(0, 0.32, 0), Vector3(0.8, 0.64, 0.8), "#927654", "OldCrate", 0.04)
			for y in [0.08, 0.55]:
				M.box(root, corner + Vector3(0, y, 0), Vector3(0.85, 0.075, 0.85), "#b19363", "CrateBand", 0.01)
	StaticGeometry.bake(root)
	return root


static func ore(kind: String, seal: bool, depth: int) -> Node3D:
	var root := Node3D.new()
	root.name = "OreModel"
	var color: String = Layout.theme(depth)["wall"]
	rock_column(root, Vector3.ZERO, Vector3(0.64, 0.78, 0.60), color, Layout.theme(depth)["cap"], depth + (3 if seal else 0))
	M.ellipsoid(root, Vector3(-0.34, 0.16, 0.24), Vector3(0.42, 0.25, 0.35), Layout.theme(depth)["cap"], "RockFoot", 7, 4)
	var pigment: String = ORE_COLORS[kind]
	for i in range(5):
		var angle := i * 2.4
		var at := Vector3(cos(angle) * 0.32, 0.78 + (i % 2) * 0.065, sin(angle) * 0.30)
		if kind == "crystal":
			crystal(root, at, 0.30 + i % 3 * 0.1, pigment, cos(angle) * 0.3)
		else:
			M.ellipsoid(root, at, Vector3(0.19, 0.13, 0.17), pigment, "OreVein", 6, 3)
	if seal:
		for i in range(3):
			M.beam(root, Vector3(-0.35 + i * 0.25, 0.87, -0.2), Vector3(-0.20 + i * 0.22, 0.89, 0.26), 0.045, "#ffdf98", "GoldenCrack")
		var marker := Label3D.new()
		marker.font = FONT
		marker.text = "裂隙岩石\n镐子挖开通道"
		marker.font_size = 26
		marker.pixel_size = 0.013
		marker.position = Vector3(0, 1.55, 0)
		marker.modulate = Color("#ffdf98")
		marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		root.add_child(marker)
	StaticGeometry.bake(root)
	return root


static func rock_column(root: Node3D, at: Vector3, scale: Vector3, wall_color: String, cap_color: String, seed_value: int) -> void:
	var outline := [Vector2(-0.67, -1.0), Vector2(0.70, -1.0), Vector2(1, -0.66), Vector2(1, 0.66), Vector2(0.71, 1), Vector2(-0.68, 1), Vector2(-1, 0.69), Vector2(-1, -0.67)]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 907 + 811
	var rings: Array = []
	for ring in range(3):
		var vertices: Array[Vector3] = []
		var shift := Vector2(rng.randf_range(-0.10, 0.10), rng.randf_range(-0.10, 0.10)) if ring > 0 else Vector2.ZERO
		for point: Vector2 in outline:
			var flat: Vector2 = point * [1.04, 1.0, 0.92][ring] + shift
			var elevation: float = [0.0, 0.49, 1.0][ring] * scale.y
			if ring > 0:
				elevation += rng.randf_range(-0.09, 0.09) * scale.y
			vertices.append(Vector3(flat.x * scale.x, elevation, flat.y * scale.z))
		rings.append(vertices)
	var sides := SurfaceTool.new()
	sides.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ring in range(2):
		for i in range(8):
			var next := (i + 1) % 8
			var normal := Vector3(outline[i].x + outline[next].x, 0.22, outline[i].y + outline[next].y).normalized()
			var shade := rng.randf_range(0.89, 1.04)
			var pigment := Color(wall_color)
			M.polygon(sides, [rings[ring][i], rings[ring][next], rings[ring + 1][next], rings[ring + 1][i]], normal, Color(pigment.r * shade, pigment.g * shade, pigment.b * shade))
	# 顶面与侧面使用同一张封闭网格，并以节点位置参与静态分块。
	for i in range(8):
		M.polygon(sides, [Vector3(0, scale.y * 1.035, 0), rings[2][i], rings[2][(i + 1) % 8]], Vector3.UP, Color(cap_color))
		M.polygon(sides, [Vector3.ZERO, rings[0][i], rings[0][(i + 1) % 8]], Vector3.DOWN, Color(wall_color))
	M.mesh_node(root, sides.commit(), at, M.paint("#ffffff"), "SolidFacetedRock")


static func ladder(descending: bool, depth: int) -> Node3D:
	var root := Node3D.new()
	root.name = "DownLadder" if descending else "UpLadder"
	if descending:
		M.box(root, Vector3(0, 0.025, 0), Vector3(1.65, 0.08, 1.85), "#252734", "ShaftOpening", 0.09)
		for side in [-1, 1]:
			M.box(root, Vector3(side * 0.88, 0.14, 0), Vector3(0.20, 0.20, 2.1), "#b79c6b", "ShaftFrame")
			M.box(root, Vector3(side * 0.46, 0.34, -0.3), Vector3(0.12, 0.74, 0.15), "#c2a478", "LadderRail")
		for y in [0.08, 0.33, 0.58]:
			M.box(root, Vector3(0, y, -0.28), Vector3(1.0, 0.09, 0.12), "#d2b98b", "LadderRung")
	else:
		for side in [-1, 1]:
			M.beam(root, Vector3(side * 0.48, 0.10, 0.1), Vector3(side * 0.48, 2.85, -0.45), 0.12, "#b9a075", "ExitLadderRail")
		for i in range(9):
			M.box(root, Vector3(0, 0.24 + i * 0.28, 0.07 - i * 0.056), Vector3(1.08, 0.11, 0.15), "#d3b885", "ExitLadderRung")
		M.box(root, Vector3(0, 3.0, -0.4), Vector3(1.7, 0.16, 1.55), "#4d4842", "UpperShaft")
	var label := Label3D.new()
	label.font = FONT
	label.text = "↓ 第 %d 层" % (depth + 1) if descending else ("↑ 返回地表" if depth == 1 else "↑ 第 %d 层" % (depth - 1))
	label.font_size = 32
	label.pixel_size = 0.013
	label.position = Vector3(0, 1.5 if descending else 3.25, 0)
	label.modulate = Color("#ffe0a1")
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	root.add_child(label)
	return root


static func hoist() -> Node3D:
	var root := Node3D.new()
	root.name = "MineLift"
	M.box(root, Vector3(0, 0.06, 0), Vector3(2.25, 0.14, 1.85), "#9d815b", "LiftPlatform", 0.045)
	for side in [-1, 1]:
		M.box(root, Vector3(side * 1.0, 1.35, -0.7), Vector3(0.22, 2.7, 0.24), "#866647", "LiftPost")
	M.box(root, Vector3(0, 2.7, -0.7), Vector3(2.6, 0.26, 0.35), "#af915f", "LiftBeam")
	var wheel := M.torus(root, Vector3(0, 2.65, -0.48), 0.31, 0.07, "#78898b", "Pulley")
	wheel.rotation.x = PI * 0.5
	M.beam(root, Vector3(0, 0.25, -0.4), Vector3(0, 2.7, -0.4), 0.035, "#dec89b", "LiftRope")
	signboard(root, "升降机", Vector3(0, 3.1, -0.45), 2.1)
	lantern(root, Vector3(-1.0, 1.85, -0.32))
	return root


static func minecart() -> Node3D:
	var root := Node3D.new()
	for x in [-0.60, 0.60]:
		for z in [-0.47, 0.47]:
			var wheel := M.cylinder(root, Vector3(x, 0.23, z), 0.25, 0.25, 0.12, "#4e5553", "CartWheel", 12)
			wheel.rotation.z = PI * 0.5
	M.box(root, Vector3(0, 0.45, 0), Vector3(1.3, 0.18, 1.5), "#62706c", "CartBase")
	for x in [-0.6, 0.6]:
		M.box(root, Vector3(x, 0.76, 0), Vector3(0.12, 0.65, 1.5), "#899387", "CartSide")
	for z in [-0.70, 0.70]:
		M.box(root, Vector3(0, 0.76, z), Vector3(1.3, 0.65, 0.12), "#9c9f8b", "CartEnd")
	for i in range(4):
		M.ellipsoid(root, Vector3((i % 2) * 0.5 - 0.25, 0.88, (i / 2) * 0.6 - 0.3), Vector3(0.36, 0.29, 0.38), "#777d72", "CartOre", 7, 4)
	return root


static func camp() -> Node3D:
	var root := Node3D.new()
	root.name = "RestCamp"
	M.box(root, Vector3(0, 0.14, 0), Vector3(1.6, 0.25, 2.1), "#a99770", "Bedroll", 0.1)
	M.box(root, Vector3(0, 0.29, -0.1), Vector3(1.54, 0.17, 1.4), "#668f88", "CampBlanket", 0.07)
	M.box(root, Vector3(0, 0.35, -0.78), Vector3(1.05, 0.24, 0.4), "#d6ccb0", "CampPillow", 0.08)
	for x in [-1.2, 1.2]:
		M.box(root, Vector3(x, 0.82, -1.4), Vector3(0.12, 1.64, 0.14), "#987b55", "CampSignpost")
	signboard(root, "矿工营地 · 休整", Vector3(0, 1.7, -1.4), 3.0)
	M.box(root, Vector3(1.2, 0.22, -0.7), Vector3(0.55, 0.44, 0.55), "#9f8058", "CampLanternCrate")
	lantern(root, Vector3(1.2, 0.7, -0.7))
	return root


static func chest(opened: bool = false) -> Node3D:
	var root := Node3D.new()
	root.name = "CrystalChest"
	M.box(root, Vector3(0, 0.34, 0), Vector3(1.4, 0.68, 0.9), "#846348", "ChestBody", 0.08)
	var lid := M.box(root, Vector3(0, 0.75, -0.2 if opened else 0.0), Vector3(1.5, 0.25, 1.0), "#b39060", "ChestLid", 0.09)
	lid.rotation.x = -1.1 if opened else 0.0
	for x in [-0.5, 0.5]:
		M.box(root, Vector3(x, 0.38, 0.46), Vector3(0.11, 0.7, 0.05), "#e3c276", "ChestBand", 0.009)
	M.box(root, Vector3(0, 0.53, 0.50), Vector3(0.22, 0.26, 0.06), "#ead28c", "ChestLock")
	crystal(root, Vector3(0, 1.1, 0), 0.62, "#cab5fb")
	return root


static func loot(kind: String) -> Node3D:
	var root := Node3D.new()
	if kind == "crystal":
		crystal(root, Vector3.ZERO, 0.42, ORE_COLORS[kind])
	else:
		M.ellipsoid(root, Vector3(0, 0.17, 0), Vector3(0.24, 0.19, 0.20), ORE_COLORS.get(kind, "#c5b47b"), "DroppedOre", 8, 4)
	return root
