extends RefCounted
## Original procedural market dressing. Metres; Y up, front +Z, floor at Y = 0.
## No scene, imported asset, font, texture, or project singleton is required.


static func seed_display() -> Node3D:
	var root := Node3D.new()
	root.name = "SeedDisplay"
	var p := _palette()
	# The merchandise is included in the roughly 1.60 x 0.60 x 0.85 m envelope.
	for x: float in [-0.70, 0.70]:
		for z: float in [-0.215, 0.215]:
			_beam(root, "SplayedLeg", Vector3(x * 0.985, 0.007, z * 0.97), Vector3(x, 0.575, z), 0.084, 0.075, p.wood_dark)
			_bevel_box(root, "LegFoot", Vector3(0.090, 0.038, 0.082), Vector3(x * 0.985, 0.019, z * 0.97), p.wood, 0.009)
	for i in range(3):
		_bevel_box(root, "LowerShelfPlank", Vector3(1.43, 0.030, 0.129), Vector3(0.0, 0.142, (i - 1) * 0.136), p.wood_light if i == 1 else p.wood, 0.006)
	_beam(root, "BackDiagonalBrace", Vector3(-0.65, 0.185, -0.237), Vector3(0.65, 0.515, -0.237), 0.041, 0.025, p.wood_dark)
	for x: float in [-0.70, 0.70]:
		_beam(root, "SideDiagonalBrace", Vector3(x, 0.185, -0.18), Vector3(x, 0.50, 0.18), 0.039, 0.030, p.wood)
	for i in range(3):
		var y := 0.388 + i * 0.066
		_bevel_box(root, "FrontApronPlank", Vector3(1.47, 0.059, 0.034), Vector3(0.0, y, 0.247), p.wood_light if i == 1 else p.wood, 0.006)
		_bevel_box(root, "BackApronPlank", Vector3(1.47, 0.059, 0.027), Vector3(0.0, y, -0.247), p.wood, 0.005)
		for x: float in [-0.66, 0.66]:
			_rod(root, "WoodenPeg", Vector3(x, y, 0.264), Vector3(x, y, 0.274), 0.008, 0.008, p.peg, 8)
	for i in range(5):
		var z := (i - 2) * 0.119
		_bevel_box(root, "CounterPlank", Vector3(1.60, 0.048, 0.114), Vector3(0.0, 0.596, z), p.wood_light if i % 2 == 0 else p.wood, 0.008)
		_grain(root, Vector3(-0.63 + i * 0.115, 0.621, z + 0.020), 0.22 + 0.027 * i, p.grain, false)
	for i in range(5):
		_grain(root, Vector3(-0.59 + i * 0.255, 0.456, 0.265), 0.15, p.grain, true)

	for i in range(3):
		var crate := _crate(root, Vector3((i - 1) * 0.505, 0.626, -0.027), p)
		crate.name = ["SeedPacketCrate", "RadishCrate", "GrainCrate"][i]
		match i:
			0:
				for k in range(5):
					var row := 0 if k < 3 else 1
					var packet := _seed_packet(crate, p, k)
					packet.position = Vector3((k % 3 - 1) * 0.110 + row * 0.049, 0.020, -0.080 + row * 0.126)
					packet.rotation_degrees = Vector3(-6.0 + row * 7.0, (k - 2) * 5.0, (k % 3 - 1) * 4.0)
				for k in range(7):
					_ellipsoid(crate, "LooseSeed", Vector3(0.008, 0.004, 0.013), Vector3(-0.14 + k * 0.040, 0.024, 0.115 + sin(k * 2.0) * 0.013), p.seed, 8)
			1:
				for k in range(7):
					var vegetable := _radish(crate, p, k)
					vegetable.position = Vector3((k % 3 - 1) * 0.107, 0.067 + (k % 2) * 0.013, -0.102 + int(k / 3) * 0.101)
					vegetable.rotation_degrees = Vector3((k % 2) * 8.0 - 4.0, k * 53.0, (k % 3 - 1) * 11.0)
			2:
				_grain_sack(crate, p)
				for k in range(5):
					_wheat(crate, Vector3(-0.116 + k * 0.040, 0.032, -0.059 + (k % 2) * 0.038), 0.148 + (k % 3) * 0.009, p, k)
				for k in range(10):
					var grain := _ellipsoid(crate, "ScatteredGrain", Vector3(0.007, 0.0045, 0.013), Vector3(-0.15 + (k % 5) * 0.032, 0.022, 0.080 + int(k / 5) * 0.035), p.seed, 8)
					grain.rotation.y = k * 1.7
		var label := _group(root, "CarvedCrateLabel", Vector3((i - 1) * 0.505, 0.521, 0.275))
		_bevel_box(label, "LabelBoard", Vector3(0.105, 0.062, 0.010), Vector3.ZERO, p.label, 0.008)
		_relief_icon(label, Vector3(0.0, -0.009, 0.008), 0.65, p, i == 1)

	_bevel_box(root, "FoldedLinen", Vector3(0.177, 0.009, 0.100), Vector3(0.633, 0.626, 0.225), p.linen, 0.004)
	for i in range(3):
		var fruit := _group(root, "SmallFruit", Vector3(0.579 + i * 0.053, 0.655 + (i % 2) * 0.010, 0.230 + (i % 2) * 0.021))
		_ellipsoid(fruit, "FruitBody", Vector3(0.031, 0.030, 0.029), Vector3.ZERO, p.coral if i != 1 else p.apricot)
		_rod(fruit, "FruitStem", Vector3(0.0, 0.025, 0.0), Vector3(0.006, 0.046, 0.002), 0.0026, 0.0018, p.wood_dark, 6)
		_leaf(fruit, "FruitLeaf", Vector3(0.003, 0.031, 0.0), Vector3(0.030, 0.042, 0.006), 0.013, p.leaf_light)
	return root


static func flower_box(width: float = 1.0) -> Node3D:
	var root := Node3D.new()
	root.name = "FlowerBox"
	var p := _palette()
	var w := maxf(width, 0.25)
	for x: float in [-w * 0.30, w * 0.30]:
		_bevel_box(root, "PlanterFoot", Vector3(minf(0.115, w * 0.24), 0.026, 0.222), Vector3(x, 0.013, 0.0), p.wood_dark, 0.005)
	_bevel_box(root, "PlanterFloor", Vector3(w - 0.040, 0.024, 0.208), Vector3(0.0, 0.037, 0.0), p.wood_dark, 0.006)
	for i in range(3):
		var y := 0.061 + i * 0.051
		var slat_width := w - 0.034 + i * 0.013
		var z := 0.106 + i * 0.007
		for side: float in [-1.0, 1.0]:
			_bevel_box(root, "PlanterLongSlat", Vector3(slat_width, 0.046, 0.020), Vector3(0.0, y, z * side), p.wood_light if i == 1 else p.wood, 0.005)
			_bevel_box(root, "PlanterEndSlat", Vector3(0.021, 0.046, z * 2.0 - 0.015), Vector3((slat_width * 0.5 - 0.012) * side, y, 0.0), p.wood, 0.005)
			for x: float in [-w * 0.5 + 0.038, w * 0.5 - 0.038]:
				_rod(root, "PlanterPeg", Vector3(x, y, z * side), Vector3(x, y, (z + 0.013) * side), 0.005, 0.005, p.peg, 8)
		_grain(root, Vector3(-w * 0.22, y + 0.006, z + 0.0105), minf(0.26, w * 0.40), p.grain, true)
	for x: float in [-1.0, 1.0]:
		for z: float in [-1.0, 1.0]:
			_beam(root, "PlanterCorner", Vector3(x * (w * 0.5 - 0.033), 0.029, z * 0.103), Vector3(x * (w * 0.5 - 0.019), 0.194, z * 0.117), 0.026, 0.026, p.wood_dark)
	for z: float in [-0.116, 0.116]:
		_bevel_box(root, "PlanterRim", Vector3(w, 0.019, 0.028), Vector3(0.0, 0.190, z), p.wood_light, 0.005)
	for x: float in [-w * 0.5 + 0.013, w * 0.5 - 0.013]:
		_bevel_box(root, "PlanterEndRim", Vector3(0.026, 0.019, 0.215), Vector3(x, 0.190, 0.0), p.wood_light, 0.005)
	_bevel_box(root, "VisibleSoil", Vector3(w - 0.052, 0.023, 0.197), Vector3(0.0, 0.169, 0.0), p.soil, 0.009)

	var count := maxi(3, int(round(w / 0.16)))
	for i in range(count):
		var x := lerpf(-w * 0.5 + 0.086, w * 0.5 - 0.086, float(i) / float(count - 1))
		var base := Vector3(x, 0.180, sin(i * 2.4) * 0.035)
		var tip := Vector3(x + sin(i * 1.8) * 0.028, 0.411 + (i % 4) * 0.014, base.z - 0.013)
		var bend := base.lerp(tip, 0.55) + Vector3(sin(i) * 0.013, 0.0, 0.013)
		_rod(root, "FlowerStemLower", base, bend, 0.0065, 0.0050, p.leaf_dark, 7)
		_rod(root, "FlowerStemUpper", bend, tip, 0.0050, 0.0035, p.leaf_dark, 7)
		for j in range(4):
			var start := base.lerp(tip, 0.22 + j * 0.135)
			var side := -1.0 if j % 2 == 0 else 1.0
			var end := start + Vector3(side * (0.058 + (j % 2) * 0.013), 0.041 + j * 0.004, (0.047 if j < 2 else -0.025))
			_leaf(root, "PlanterLeaf", start, end, 0.033 + (j % 2) * 0.007, p.leaf_light if (i + j) % 3 == 0 else p.leaf, (i - j) * 0.31)
		_flower(root, tip, p.cream if i % 3 != 1 else p.coral, p, i)
		if i % 2 == 0:
			var bud_tip := base.lerp(tip, 0.70) + Vector3(0.029, 0.029, 0.052)
			_rod(root, "BudStem", bend, bud_tip, 0.0035, 0.0022, p.leaf_dark, 6)
			_ellipsoid(root, "FlowerBud", Vector3(0.012, 0.018, 0.011), bud_tip, p.cream if i % 3 else p.coral, 8)
	return root


static func _palette() -> Dictionary:
	return {
		"wood": _material("#AD754D"), "wood_light": _material("#C99563"),
		"wood_dark": _material("#795139"), "grain": _material("#91623F"),
		"peg": _material("#624738"), "paper": _material("#E9D6A3"),
		"paper_fold": _material("#C9AD79"), "linen": _material("#DBCAA5"),
		"label": _material("#E4C99B"), "soil": _material("#4B3C30"),
		"leaf": _material("#668652"), "leaf_light": _material("#90A768"),
		"leaf_dark": _material("#426246"), "cream": _material("#F4E5BC"),
		"coral": _material("#D98675"), "radish": _material("#C56568"),
		"root": _material("#F1DCCA"), "seed": _material("#D4AE68"),
		"straw": _material("#B99350"), "pollen": _material("#E2B45B"),
		"apricot": _material("#E1AB64"),
	}


static func _material(color: String) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color)
	material.roughness = 0.87
	material.metallic_specular = 0.22
	return material


static func _group(parent: Node3D, title: String, position: Vector3 = Vector3.ZERO) -> Node3D:
	var node := Node3D.new()
	node.name = title
	node.position = position
	parent.add_child(node)
	return node


static func _crate(parent: Node3D, position: Vector3, p: Dictionary) -> Node3D:
	var root := _group(parent, "ProduceCrate", position)
	_bevel_box(root, "CrateFloor", Vector3(0.436, 0.019, 0.345), Vector3(0.0, 0.0095, 0.0), p.wood_dark, 0.005)
	for y: float in [0.045, 0.099]:
		for z: float in [-0.172, 0.172]:
			_bevel_box(root, "CrateLongSlat", Vector3(0.446, 0.043, 0.018), Vector3(0.0, y, z), p.wood_light, 0.005)
		for x: float in [-0.214, 0.214]:
			if y < 0.06:
				_bevel_box(root, "CrateEndSlat", Vector3(0.018, 0.043, 0.327), Vector3(x, y, 0.0), p.wood, 0.004)
			else:
				# Split upper side boards leave a real open handhold.
				for z: float in [-0.120, 0.120]:
					_bevel_box(root, "CrateHandleSide", Vector3(0.018, 0.043, 0.088), Vector3(x, y, z), p.wood, 0.004)
				_bevel_box(root, "CrateHandleBridge", Vector3(0.022, 0.014, 0.162), Vector3(x, 0.115, 0.0), p.wood_light, 0.004)
	for x: float in [-0.204, 0.204]:
		for z: float in [-0.158, 0.158]:
			_bevel_box(root, "CrateCornerPost", Vector3(0.025, 0.133, 0.025), Vector3(x, 0.0665, z), p.wood_dark, 0.004)
		for y: float in [0.045, 0.099]:
			_rod(root, "CratePeg", Vector3(x, y, 0.178), Vector3(x, y, 0.184), 0.004, 0.004, p.peg, 6)
	return root


static func _seed_packet(parent: Node3D, p: Dictionary, index: int) -> Node3D:
	var root := _group(parent, "FoldedSeedPacket")
	var h := 0.151 + (index % 3) * 0.010
	var rings: Array[PackedVector3Array] = [
		_octagon(0.039, 0.012, 0.0, 0.007),
		_octagon(0.044, 0.018, 0.025, 0.007),
		_octagon(0.040, 0.015, h - 0.019, 0.005),
		_octagon(0.040, 0.009, h, 0.004),
	]
	_loft(root, "PuffedPaperBag", rings, p.paper if index % 2 == 0 else p.linen)
	_bevel_box(root, "FoldedPaperLip", Vector3(0.082, 0.016, 0.016), Vector3(0.0, h - 0.009, 0.006), p.paper_fold, 0.003)
	_relief_icon(root, Vector3(0.0, 0.078, 0.018), 0.68, p, index % 2 == 0)
	_bevel_box(root, "PacketPrintedRule", Vector3(0.043, 0.003, 0.0016), Vector3(0.0, 0.038, 0.0188), p.paper_fold, 0.0005)
	return root


static func _relief_icon(parent: Node3D, position: Vector3, size: float, p: Dictionary, radish: bool) -> void:
	var icon := _group(parent, "CropEmblem", position)
	icon.scale = Vector3.ONE * size
	_ellipsoid(icon, "EmblemBody", Vector3(0.018, 0.021, 0.0045), Vector3(0.0, 0.004, 0.0), p.radish if radish else p.seed, 8)
	_leaf(icon, "EmblemLeafLeft", Vector3(-0.002, 0.020, 0.0), Vector3(-0.024, 0.046, 0.001), 0.016, p.leaf_dark)
	_leaf(icon, "EmblemLeafRight", Vector3(0.002, 0.020, 0.0), Vector3(0.018, 0.051, 0.0), 0.015, p.leaf)
	if radish:
		_rod(icon, "EmblemRoot", Vector3(0.0, -0.013, 0.0), Vector3(0.004, -0.027, 0.0), 0.005, 0.0006, p.root, 6)


static func _radish(parent: Node3D, p: Dictionary, index: int) -> Node3D:
	var root := _group(parent, "LeafyRadish")
	_ellipsoid(root, "RadishBulb", Vector3(0.037, 0.033, 0.034), Vector3.ZERO, p.radish if index % 3 else p.coral)
	_rod(root, "RadishTaper", Vector3(0.0, -0.021, 0.0), Vector3(0.002, -0.051, 0.004), 0.014, 0.002, p.root, 8)
	_rod(root, "FineRoot", Vector3(0.002, -0.048, 0.004), Vector3(0.012, -0.057, 0.008), 0.002, 0.0004, p.root, 6)
	for j in range(4):
		var angle := j * TAU / 4.0 + index * 0.23
		var start := Vector3(sin(angle) * 0.004, 0.022, cos(angle) * 0.004)
		var tip := Vector3(sin(angle) * 0.035, 0.093 + (j % 2) * 0.012, cos(angle) * 0.029)
		_rod(root, "RadishLeafStalk", start, start.lerp(tip, 0.40), 0.0028, 0.0018, p.leaf_dark, 6)
		_leaf(root, "RadishLeaf", start.lerp(tip, 0.22), tip, 0.026, p.leaf_light if j % 2 else p.leaf, angle)
	return root


static func _grain_sack(parent: Node3D, p: Dictionary) -> void:
	var root := _group(parent, "OpenGrainSack", Vector3(0.085, 0.019, -0.025))
	var rings: Array[PackedVector3Array] = []
	for k in range(4):
		var ring := PackedVector3Array()
		var radius: float = [0.054, 0.071, 0.065, 0.061][k]
		var y: float = [0.0, 0.025, 0.073, 0.082][k]
		for i in range(10):
			var a := i * TAU / 10.0
			ring.append(Vector3(cos(a) * radius, y + (sin(a * 3.0) * 0.003 if k > 1 else 0.0), sin(a) * radius * 0.79))
		rings.append(ring)
	_loft(root, "SoftSackBody", rings, p.linen, false)
	_ellipsoid(root, "GrainMound", Vector3(0.055, 0.009, 0.041), Vector3(0.0, 0.079, 0.0), p.straw)
	for i in range(10):
		var a := i * TAU / 10.0
		var b := (i + 1) * TAU / 10.0
		_rod(root, "RolledSackLip", Vector3(cos(a) * 0.061, 0.082 + sin(a * 3.0) * 0.003, sin(a) * 0.048), Vector3(cos(b) * 0.061, 0.082 + sin(b * 3.0) * 0.003, sin(b) * 0.048), 0.0045, 0.0045, p.paper_fold, 7)
	for i in range(16):
		var angle := i * 2.399963
		var radius := sqrt(float(i) / 16.0) * 0.045
		var seed := _ellipsoid(root, "SackGrain", Vector3(0.008, 0.005, 0.014), Vector3(cos(angle) * radius, 0.082 + (1.0 - radius / 0.06) * 0.007, sin(angle) * radius * 0.75), p.seed, 8)
		seed.rotation.y = angle


static func _wheat(parent: Node3D, base: Vector3, height: float, p: Dictionary, index: int) -> void:
	var tip := base + Vector3((index - 2) * 0.007, height, -0.012)
	_rod(parent, "WheatStem", base, tip, 0.0024, 0.0012, p.straw, 6)
	for j in range(4):
		for side: float in [-1.0, 1.0]:
			var position := tip - Vector3(0.0, 0.047 - j * 0.012, 0.0) + Vector3(side * 0.007, 0.0, 0.0)
			var seed := _ellipsoid(parent, "WheatKernel", Vector3(0.007, 0.011, 0.0055), position, p.seed, 8)
			seed.rotation.z = side * -0.48
			_rod(parent, "WheatAwn", position + Vector3(side * 0.003, 0.006, 0.0), position + Vector3(side * 0.012, 0.022, -0.003), 0.00075, 0.00025, p.straw, 5)


static func _flower(parent: Node3D, position: Vector3, petal_material: StandardMaterial3D, p: Dictionary, index: int) -> void:
	var root := _group(parent, "CreamFlower" if index % 3 != 1 else "CoralFlower", position)
	root.quaternion = Quaternion(Vector3.UP, Vector3(sin(index * 1.8) * 0.18, 0.77, 0.64).normalized())
	for i in range(6):
		var a := i * TAU / 6.0 + index * 0.25
		var petal := _ellipsoid(root, "RoundedPetal", Vector3(0.0145, 0.007, 0.023), Vector3(sin(a) * 0.019, 0.003, cos(a) * 0.019), petal_material, 8)
		petal.rotation.y = a
	_ellipsoid(root, "GoldenFlowerCentre", Vector3(0.012, 0.009, 0.012), Vector3(0.0, 0.010, 0.0), p.pollen, 10)
	_ellipsoid(root, "GreenCalyx", Vector3(0.014, 0.010, 0.014), Vector3(0.0, -0.009, 0.0), p.leaf_dark, 8)


static func _leaf(parent: Node3D, title: String, start: Vector3, end: Vector3, width: float, material: StandardMaterial3D, twist: float = 0.0) -> MeshInstance3D:
	var length := start.distance_to(end)
	var thickness := maxf(width * 0.14, 0.0012)
	var perimeter := PackedVector3Array([
		Vector3(0.0, 0.0, 0.0), Vector3(width * 0.43, length * 0.28, thickness * 0.28),
		Vector3(width * 0.50, length * 0.57, thickness * 0.57), Vector3(0.0, length, thickness * 1.4),
		Vector3(-width * 0.50, length * 0.57, thickness * 0.57), Vector3(-width * 0.43, length * 0.28, thickness * 0.28),
	])
	var vertices: Array[Vector3] = []
	var normals: Array[Vector3] = []
	var front := Vector3(0.0, length * 0.47, thickness * 1.7)
	var back := Vector3(0.0, length * 0.47, -thickness * 0.65)
	for i in range(perimeter.size()):
		var next := (i + 1) % perimeter.size()
		_triangle(vertices, normals, front, perimeter[i], perimeter[next])
		_triangle(vertices, normals, back, perimeter[next], perimeter[i])
	var mesh := _surface(parent, title, vertices, normals, material)
	mesh.position = start
	mesh.quaternion = Quaternion(Vector3.UP, (end - start).normalized())
	mesh.rotate_object_local(Vector3.UP, twist)
	return mesh


static func _grain(parent: Node3D, position: Vector3, length: float, material: StandardMaterial3D, front: bool) -> void:
	# A shallow, tapered grain ridge follows the board as actual geometry.
	var grain := _leaf(parent, "SubtleWoodGrain", position, position + Vector3(length, 0.0, 0.0), 0.0022, material)
	if not front:
		grain.rotate_object_local(Vector3.UP, -PI * 0.5)


static func _ellipsoid(parent: Node3D, title: String, radii: Vector3, position: Vector3, material: StandardMaterial3D, segments: int = 10) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = segments
	mesh.rings = 5
	var node := MeshInstance3D.new()
	node.name = title
	node.mesh = mesh
	node.material_override = material
	node.position = position
	node.scale = radii
	parent.add_child(node)
	return node


static func _rod(parent: Node3D, title: String, start: Vector3, end: Vector3, bottom_radius: float, top_radius: float, material: StandardMaterial3D, segments: int = 8) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = bottom_radius
	mesh.top_radius = top_radius
	mesh.height = start.distance_to(end)
	mesh.radial_segments = segments
	mesh.rings = 1
	var node := MeshInstance3D.new()
	node.name = title
	node.mesh = mesh
	node.material_override = material
	node.position = (start + end) * 0.5
	node.quaternion = Quaternion(Vector3.UP, (end - start).normalized())
	parent.add_child(node)
	return node


static func _beam(parent: Node3D, title: String, start: Vector3, end: Vector3, width: float, depth: float, material: StandardMaterial3D) -> MeshInstance3D:
	var node := _bevel_box(parent, title, Vector3(width, start.distance_to(end), depth), (start + end) * 0.5, material, minf(width, depth) * 0.16)
	node.quaternion = Quaternion(Vector3.UP, (end - start).normalized())
	return node


static func _bevel_box(parent: Node3D, title: String, size: Vector3, position: Vector3, material: StandardMaterial3D, bevel: float = 0.006) -> MeshInstance3D:
	var b := minf(bevel, minf(minf(size.x, size.z) * 0.22, size.y * 0.28))
	var x := size.x * 0.5
	var y := size.y * 0.5
	var z := size.z * 0.5
	var rings: Array[PackedVector3Array] = [
		_octagon(x - b, z - b, -y, b * 0.45),
		_octagon(x, z, -y + b, b),
		_octagon(x, z, y - b, b),
		_octagon(x - b, z - b, y, b * 0.45),
	]
	var node := _loft(parent, title, rings, material)
	node.position = position
	return node


static func _octagon(x: float, z: float, y: float, corner: float) -> PackedVector3Array:
	return PackedVector3Array([
		Vector3(-x + corner, y, -z), Vector3(x - corner, y, -z),
		Vector3(x, y, -z + corner), Vector3(x, y, z - corner),
		Vector3(x - corner, y, z), Vector3(-x + corner, y, z),
		Vector3(-x, y, z - corner), Vector3(-x, y, -z + corner),
	])


static func _loft(parent: Node3D, title: String, rings: Array[PackedVector3Array], material: StandardMaterial3D, close_top: bool = true) -> MeshInstance3D:
	var vertices: Array[Vector3] = []
	var normals: Array[Vector3] = []
	var count := rings[0].size()
	for r in range(rings.size() - 1):
		for i in range(count):
			var next := (i + 1) % count
			_quad(vertices, normals, rings[r][i], rings[r + 1][i], rings[r + 1][next], rings[r][next])
	var bottom := Vector3.ZERO
	var top := Vector3.ZERO
	for i in range(count):
		bottom += rings[0][i] / float(count)
		top += rings[-1][i] / float(count)
	for i in range(count):
		var next := (i + 1) % count
		_triangle(vertices, normals, bottom, rings[0][i], rings[0][next])
		if close_top:
			_triangle(vertices, normals, top, rings[-1][next], rings[-1][i])
	return _surface(parent, title, vertices, normals, material)


static func _quad(vertices: Array[Vector3], normals: Array[Vector3], a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	_triangle(vertices, normals, a, b, c)
	_triangle(vertices, normals, a, c, d)


static func _triangle(vertices: Array[Vector3], normals: Array[Vector3], a: Vector3, b: Vector3, c: Vector3) -> void:
	var normal := (b - a).cross(c - a).normalized()
	# Godot front faces use clockwise winding; normals still point out of the solid.
	vertices.append_array([a, c, b])
	normals.append_array([normal, normal, normal])


static func _surface(parent: Node3D, title: String, vertices: Array[Vector3], normals: Array[Vector3], material: StandardMaterial3D) -> MeshInstance3D:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(vertices)
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array(normals)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var node := MeshInstance3D.new()
	node.name = title
	node.mesh = mesh
	node.material_override = material
	parent.add_child(node)
	return node
