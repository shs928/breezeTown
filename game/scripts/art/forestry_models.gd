extends RefCounted
## 木材、带土树苗和斧头均为代码生成的原创模型。

const M = preload("res://scripts/art/art_mesh.gd")
const Trees = preload("res://scripts/art/tree_models.gd")
const StaticGeometry = preload("res://scripts/art/static_geometry.gd")


static func axe(root: Node3D) -> void:
	M.beam(root, Vector3(0, -0.08, -0.15), Vector3(0, 0.12, 0.77), 0.075, "#b18851", "AxeHandle", -1, true)
	for z in [-0.04, 0.03, 0.10]:
		M.box(root, Vector3(0, -0.042 + z * 0.21, z), Vector3(0.081, 0.083, 0.024), "#665042", "LeatherBinding", 0.006)
	M.box(root, Vector3(0.0, 0.10, 0.73), Vector3(0.18, 0.18, 0.18), "#53636a", "AxeSocket", 0.02)
	# 斧刃朝向持握平面的外侧，与双尖镐和锄头的形状区分。
	var blade := SurfaceTool.new()
	blade.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in [-1.0, 1.0]:
		M.polygon(blade, [Vector3(0.04, 0.045, 0.63), Vector3(0.04, 0.045, 0.83), Vector3(0.42, 0.10, 0.94), Vector3(0.46, 0.10, 0.55)], Vector3(0, side, 0), Color("#a6b9bb") if side > 0 else Color("#788e96"))
		M.polygon(blade, [Vector3(0.35, 0.10, 0.58), Vector3(0.34, 0.10, 0.90), Vector3(0.42, 0.10, 0.94), Vector3(0.46, 0.10, 0.55)], Vector3(0, side, 0), Color("#e0e4d7"))
	M.mesh_node(root, blade.commit(), Vector3.ZERO, M.paint("#ffffff", 0.46), "ForgedAxeBlade")


static func wood() -> Node3D:
	var root := Node3D.new()
	root.name = "WoodBundle"
	for i in range(3):
		var at := Vector3((i - 1) * 0.12, 0.16 + (i % 2) * 0.14, 0)
		var log := Node3D.new()
		log.position = at
		log.rotation = Vector3(PI * 0.5, 0.1 * (i - 1), 0.15 * (i - 1))
		root.add_child(log)
		M.cylinder(log, Vector3.ZERO, 0.13, 0.12, 0.62, "#775637", "Bark", 9)
		for side in [-1.0, 1.0]:
			M.cylinder(log, Vector3(0, side * 0.315, 0), 0.107, 0.107, 0.012, "#d5b67a", "CutEnd", 12)
			M.torus(log, Vector3(0, side * 0.322, 0), 0.064, 0.007, "#a48150", "GrowthRing")
		for angle in [0.0, 2.1, 4.2]:
			M.beam(log, Vector3(cos(angle) * 0.124, -0.24, sin(angle) * 0.124), Vector3(cos(angle) * 0.124, 0.25, sin(angle) * 0.124), 0.013, "#a17a49", "BarkGrain")
	StaticGeometry.bake(root)
	return root


static func sapling() -> Node3D:
	var root := Trees.build("oak", 2, 0)
	root.name = "SaplingWithRootBall"
	M.ellipsoid(root, Vector3(0, 0.085, 0), Vector3(0.15, 0.11, 0.13), "#89704b", "RootBall", 8, 5)
	M.torus(root, Vector3(0, 0.13, 0), 0.12, 0.012, "#d3bb7d", "RootTwine")
	return root
