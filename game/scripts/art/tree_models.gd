extends RefCounted
## 原创枝干和叶簇网格。每棵树共用两张网格，树冠保留独立的摇曳支点。

const M = preload("res://scripts/art/art_mesh.gd")
static var _meshes := {}


static func build(species: String = "oak", variant: int = 0, stage: int = 3) -> Node3D:
	if stage == 3:
		var asset_path := "res://resources/models/foliage_%s_%d.glb" % [species, posmod(variant,2)]
		if ResourceLoader.exists(asset_path):
			var model:Node3D=(load(asset_path) as PackedScene).instantiate()
			var root:=Node3D.new()
			root.name="LivingTree"
			var crown:=Node3D.new()
			crown.name="Crown"
			crown.position.y=1.7
			root.add_child(crown)
			# The authored model is parented to the sway pivot; trunk motion remains subtle.
			model.position.y=-1.7
			crown.add_child(model)
			return root
	variant = posmod(variant, 6)
	var key := "%s_%d_%d" % [species, variant, stage]
	if not _meshes.has(key):
		var wood := SurfaceTool.new()
		var leaves := SurfaceTool.new()
		wood.begin(Mesh.PRIMITIVE_TRIANGLES)
		leaves.begin(Mesh.PRIMITIVE_TRIANGLES)
		var rng := RandomNumberGenerator.new()
		rng.seed = 96173 + variant * 617
		if stage < 3:
			_young_tree(wood, leaves, rng, stage, species)
		elif species == "pine":
			_pine(wood, leaves, rng)
		else:
			_oak(wood, leaves, rng, species == "apple", species == "blossom")
		_meshes[key] = [wood.commit(), leaves.commit()]
	var root := Node3D.new()
	root.name = "LivingTree"
	M.mesh_node(root, _meshes[key][0], Vector3.ZERO, M.paint("#ffffff"), "Branchwork")
	var crown := Node3D.new()
	crown.name = "Crown"
	crown.position.y = [0.18, 0.4, 0.8, 1.7][stage]
	root.add_child(crown)
	M.mesh_node(crown, _meshes[key][1], -crown.position, M.paint("#fffffe"), "Leaves")
	return root


static func _oak(wood: SurfaceTool, leaves: SurfaceTool, rng: RandomNumberGenerator, fruit: bool, blossom: bool = false) -> void:
	var lean := Vector3(rng.randf_range(-0.18, 0.18), 0, rng.randf_range(-0.13, 0.13))
	var trunk := [Vector3.ZERO, Vector3(0.06, 0.5, -0.02), Vector3(-0.06, 1.4, 0.04) + lean * 0.4, Vector3(0.07, 2.3, -0.05) + lean, Vector3(-0.12, 3.35, 0.02) + lean]
	_stem(wood, trunk, [0.32, 0.235, 0.18, 0.12, 0.045], Color("#73543b"), rng)
	for i in range(6):
		var angle := i * TAU / 6.0 + rng.randf_range(-0.25, 0.25)
		var tip := Vector3(cos(angle), 0, sin(angle)) * rng.randf_range(0.6, 0.88)
		_stem(wood, [Vector3(0, 0.25, 0), tip * 0.52 + Vector3(0, 0.08, 0), tip + Vector3(0, 0.025, 0)], [0.13, 0.085, 0.015], Color("#806143"), rng)
	# 每个分枝托起自己的叶簇；高度、长短和轮廓均有变化，留出透光的枝隙。
	# 开花树整冠换成粉色系叶簇（樱花式），近景一眼可读（ART-02）。
	var leaf_tints: Array = ["#3a7131", "#538c34", "#73a13e", "#92b54d"]
	var crown_tint := Color("#809c52")
	if blossom:
		leaf_tints = ["#efaac6", "#f6c6d8", "#e89ab8", "#fbe0ea"]
		crown_tint = Color("#f3bcd0")
	for branch in range(9):
		var angle := branch * 2.399 + rng.randf_range(-0.3, 0.3)
		var tier := branch % 3
		var reach := rng.randf_range(1.1, 1.7) - tier * 0.19
		var start: Vector3 = trunk[2] + Vector3(0, tier * 0.46, 0)
		var elbow := Vector3(cos(angle) * reach * 0.56, 2.2 + tier * 0.43, sin(angle) * reach * 0.56) + lean
		var tip := Vector3(cos(angle) * reach, 2.65 + tier * 0.49 + rng.randf_range(-0.14, 0.2), sin(angle) * reach) + lean
		_stem(wood, [start, elbow, tip], [0.11 - tier * 0.019, 0.064, 0.017], Color("#816040"), rng)
		for fork in range(2):
			var side := Vector3(cos(angle + 1.15 + fork * 2.3), 0.35 + fork * 0.16, sin(angle + 1.15 + fork * 2.3)) * 0.57
			var twig := tip + side
			_stem(wood, [elbow.lerp(tip, 0.7), twig], [0.04, 0.009], Color("#917046"), rng)
			var tint := Color(leaf_tints[mini(tier + fork, 3)])
			_leaf_bough(leaves, twig + Vector3(0, 0.10, 0), Vector3(rng.randf_range(0.64, 0.88), rng.randf_range(0.43, 0.66), rng.randf_range(0.62, 0.82)), tint, rng)
	_leaf_bough(leaves, Vector3(-0.15, 4.14, 0.04) + lean, Vector3(0.82, 0.66, 0.78), crown_tint, rng)
	if fruit:
		for i in range(16):
			var angle := i * 2.399
			var at := Vector3(cos(angle) * rng.randf_range(1.28, 1.80), rng.randf_range(2.45, 3.7), sin(angle) * rng.randf_range(1.3, 1.8))
			_clump(leaves, at, Vector3(0.12, 0.135, 0.12), Color("#c85d40" if i % 3 else "#d38a48"), rng, false, false)
	elif blossom:
		# 深粉花团缀在冠层外围边缘，制造"压满花"的层次。
		for i in range(20):
			var angle := i * 2.399
			var at := Vector3(cos(angle) * rng.randf_range(1.35, 1.95), rng.randf_range(2.3, 3.85), sin(angle) * rng.randf_range(1.35, 1.95))
			_clump(leaves, at, Vector3(0.19, 0.17, 0.19), Color("#e58cae" if i % 3 else "#f0bcd2"), rng, false, false)


static func _pine(wood: SurfaceTool, leaves: SurfaceTool, rng: RandomNumberGenerator) -> void:
	_stem(wood, [Vector3.ZERO,Vector3(0.06,2.0,0),Vector3(-0.06,5.5,0)], [0.32,0.20,0.025], Color("#85582f"), rng)
	# 四层宽厚的下垂叶裙，形成参考图中一眼可辨的童话松树剪影。
	for tier in range(4):
		var bottom := 1.1 + tier * 1.13
		var radius := 1.95 - tier * 0.39
		var height := 2.8 - tier * 0.25
		var rings: Array = []
		var sides := 20
		for layer in range(5):
			var ring: Array[Vector3] = []
			for side in range(sides):
				var angle := side * TAU / sides + tier * 0.51
				var reach: float = radius * [0.81,1.0,0.80,0.40,0.01][layer]
				var ripple := 1.0 + sin(side * 2.3 + tier) * 0.08
				var drop := (0.0 if layer > 1 else (0.15 if side % 2 else -0.12))
				ring.append(Vector3(cos(angle)*reach*ripple,bottom+height*[0.04,0.15,0.38,0.70,1.0][layer]+drop,sin(angle)*reach*ripple))
			rings.append(ring)
		for layer in range(4):
			for side in range(sides):
				var next := (side+1)%sides
				var angle := side * TAU / sides + tier * 0.51
				var tint := Color(["#285d39","#37753b","#508d41","#72a149"][mini(3,tier)])
				tint = tint.lightened(layer*0.025+sin(side*1.7)*0.035)
				M.polygon(leaves,[rings[layer][side],rings[layer][next],rings[layer+1][next],rings[layer+1][side]],Vector3(cos(angle)*0.7,0.6,sin(angle)*0.7).normalized(),tint)


static func _young_tree(wood: SurfaceTool, leaves: SurfaceTool, rng: RandomNumberGenerator, stage: int, species: String) -> void:
	var height: float = [0.70, 1.42, 2.60][stage]
	_stem(wood, [Vector3.ZERO, Vector3(0.025, height * 0.55, 0), Vector3(-0.06, height, 0.04)], [0.024 + stage * 0.036, 0.022 + stage * 0.020, 0.005], Color("#896b44"), rng)
	for i in range(4 + stage * 3):
		var angle := i * 2.399
		var start := Vector3(0, height * (0.36 + float(i) / (4 + stage * 3) * 0.54), 0)
		var tip := start + Vector3(cos(angle) * (0.16 + stage * 0.17), 0.1 + stage * 0.13, sin(angle) * (0.16 + stage * 0.17))
		_stem(wood, [start, tip], [0.013 + stage * 0.007, 0.003], Color("#91734a"), rng)
		var green := Color("#6f9149") if species != "pine" else Color("#507b56")
		if stage == 0:
			_leaf(leaves, tip, Vector3(cos(angle), 0.5, sin(angle)).normalized() * 0.23, 0.10, green.lightened(i * 0.035))
		else:
			_clump(leaves, tip, Vector3(0.18 + stage * 0.13, 0.15 + stage * 0.12, 0.18 + stage * 0.12), green, rng, species == "pine")


static func _stem(surface: SurfaceTool, path: Array, widths: Array, tint: Color, rng: RandomNumberGenerator) -> void:
	var rings: Array = []
	var sides := 7
	for i in range(path.size()):
		var forward: Vector3 = path[mini(i + 1, path.size() - 1)] - path[maxi(0, i - 1)]
		var basis := Basis(Quaternion(Vector3.UP, forward.normalized()))
		var ring: Array[Vector3] = []
		for side in range(sides):
			var angle := side * TAU / sides
			ring.append(path[i] + basis * Vector3(cos(angle), 0, sin(angle)) * widths[i])
		rings.append(ring)
	for i in range(rings.size() - 1):
		for side in range(sides):
			var next := (side + 1) % sides
			var normal: Vector3 = ((rings[i][side] - path[i]) + (rings[i][next] - path[i])).normalized()
			M.polygon(surface, [rings[i][side], rings[i][next], rings[i + 1][next], rings[i + 1][side]], normal, tint.lightened(rng.randf_range(-0.12, 0.12)))
	M.polygon(surface, rings[-1], (path[-1] - path[-2]).normalized(), tint.lightened(0.22))


static func _clump(surface: SurfaceTool, at: Vector3, radii: Vector3, tint: Color, rng: RandomNumberGenerator, needles: bool, fringe: bool = true) -> void:
	# 错落的小叶团配合边缘叶片，打破球体/圆锥的光滑剪影。
	var rings: Array = []
	var sides := 12
	for ring in range(4):
		var vertices: Array[Vector3] = []
		for side in range(sides):
			var angle := side * TAU / sides + ring * 0.19
			var spread: float = rng.randf_range(0.90, 1.12) * [0.50, 0.93, 0.87, 0.43][ring]
			vertices.append(at + Vector3(cos(angle) * radii.x * spread, radii.y * ([-0.6, -0.15, 0.43, 0.80][ring] + rng.randf_range(-0.10, 0.10)), sin(angle) * radii.z * spread))
		rings.append(vertices)
	for side in range(sides):
		var next := (side + 1) % sides
		for ring in range(3):
			var a: Vector3 = rings[ring][side]
			var b: Vector3 = rings[ring][next]
			var c: Vector3 = rings[ring + 1][next]
			var d: Vector3 = rings[ring + 1][side]
			var normal := ((a + b + c + d) * 0.25 - at).normalized()
			M.polygon(surface, [a, b, c, d], normal, tint.lightened(rng.randf_range(-0.04, 0.05) + ring * 0.025))
		M.polygon(surface, [at + Vector3(0, radii.y, 0), rings[3][side], rings[3][next]], Vector3.UP, tint.lightened(rng.randf_range(0.05, 0.13)))
		M.polygon(surface, [at - Vector3(0, radii.y * 0.7, 0), rings[0][side], rings[0][next]], Vector3.DOWN, tint.darkened(0.16))
		if fringe:
			for leaf_index in range(2):
				var angle := (side + leaf_index * 0.45) * TAU / sides
				var direction := Vector3(cos(angle), rng.randf_range(-0.15, 0.45), sin(angle))
				var start: Vector3 = rings[1][side].lerp(rings[2][side], leaf_index * 0.6)
				_leaf(surface, start, direction * (0.22 if needles else 0.19), 0.050 if needles else 0.075, tint.lightened(rng.randf_range(0.02, 0.12)))


static func _leaf_bough(surface: SurfaceTool, at: Vector3, radii: Vector3, tint: Color, rng: RandomNumberGenerator) -> void:
	_clump(surface, at, radii, tint, rng, false, true)
	for i in range(14):
		var angle := i * 2.399
		var elevation := rng.randf_range(-0.6,0.95)
		var normal := Vector3(cos(angle),elevation,sin(angle)).normalized()
		var direction := (normal * Vector3(1,0.4,1) + Vector3.UP*0.2).normalized()
		_leaf(surface,at+normal*radii*0.87,direction*rng.randf_range(0.28,0.44),0.16,tint.lightened(0.08))


static func _leaf(surface: SurfaceTool, start: Vector3, direction: Vector3, width: float, tint: Color) -> void:
	var side := direction.cross(Vector3.UP).normalized() * width
	var middle := start + direction * 0.52 + Vector3(0, width * 0.35, 0)
	var tip := start + direction
	var shoulder := start + direction * 0.30 + Vector3(0, width * 0.14, 0)
	var outer := start + direction * 0.68 + Vector3(0, width * 0.20, 0)
	M.polygon(surface, [start, shoulder - side * 0.80, outer - side * 0.74, tip, middle], Vector3(-side.x, 0.8, -side.z).normalized(), tint)
	M.polygon(surface, [start, middle, tip, outer + side * 0.74, shoulder + side * 0.80], Vector3(side.x, 0.8, side.z).normalized(), tint.lightened(0.05))
