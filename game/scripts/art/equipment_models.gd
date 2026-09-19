extends RefCounted
## 掌心为原点的原创手持模型，挂在右手关节下并随动作一起运动。

const M = preload("res://scripts/art/art_mesh.gd")
const StaticGeometry = preload("res://scripts/art/static_geometry.gd")
const Forestry = preload("res://scripts/art/forestry_models.gd")
const TOOLS := ["hand", "hoe", "can", "seed", "fence", "pickaxe", "sword", "axe", "sapling", "rod"]
const LABELS := ["空手", "锄头", "水壶", "种子", "围栏", "镐子", "短剑", "斧头", "树苗", "鱼竿"]
const TOOL_LABELS := {"hand": "空手", "hoe": "锄头", "can": "水壶", "seed": "种子", "fence": "围栏", "pickaxe": "镐子", "sword": "短剑", "axe": "斧头", "sapling": "树苗", "rod": "鱼竿"}
const SEED_COLORS := {"radish": "#ce797e", "strawberry": "#c7555a", "wheat": "#ddb655", "pumpkin": "#da8b47"}


static func build(kind: String, seed_kind: String = "radish") -> Node3D:
	var root := Node3D.new()
	root.name = "Held_" + kind
	root.set_meta("tool", kind)
	if kind in ["hoe", "pickaxe"]:
		M.beam(root, Vector3(0, -0.15, -0.08), Vector3(0, 0.10, 0.80), 0.065, "#b68a52", "AshHandle", -1, true)
		for z in [-0.04, 0.05, 0.14]:
			M.box(root, Vector3(0, z * 0.27 - 0.025, z), Vector3(0.078, 0.078, 0.025), "#685746", "GripBand", 0.007)
		if kind == "pickaxe":
			M.beam(root, Vector3(-0.34, 0.07, 0.83), Vector3(0, 0.14, 0.77), 0.12, "#b0c5c9", "SteelPickLeft", 0.10)
			M.beam(root, Vector3(0, 0.14, 0.77), Vector3(0.38, 0.02, 0.86), 0.10, "#879fa9", "SteelPickRight", 0.085)
			M.box(root, Vector3(0, 0.10, 0.78), Vector3(0.17, 0.17, 0.14), "#56656c", "PickSocket")
		else:
			M.box(root, Vector3(0, -0.015, 0.83), Vector3(0.36, 0.28, 0.065), "#95acac", "HoeBlade", 0.027)
			M.box(root, Vector3(0, -0.13, 0.84), Vector3(0.38, 0.025, 0.045), "#ced8ce", "HoeEdge", 0.006)
	elif kind == "axe":
		Forestry.axe(root)
	elif kind == "sapling":
		var sprout := Forestry.sapling()
		sprout.position = Vector3(0, -0.12, 0.14)
		sprout.scale = Vector3.ONE * 0.72
		root.add_child(sprout)
	elif kind == "sword":
		M.beam(root, Vector3(0, 0, -0.15), Vector3(0, 0, 0.12), 0.085, "#695249", "LeatherGrip", -1, true)
		M.ellipsoid(root, Vector3(0, 0, -0.18), Vector3(0.075, 0.07, 0.065), "#dab96b", "Pommel", 10, 6)
		M.box(root, Vector3(0, 0, 0.16), Vector3(0.40, 0.075, 0.065), "#d9b267", "BrassGuard", 0.018)
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for side in [-1.0, 1.0]:
			M.polygon(surface, [Vector3(-0.10, 0, 0.20), Vector3(0, 0.034 * side, 0.20), Vector3(0, 0, 1.08), Vector3(-0.075, 0, 0.88)], Vector3(0, side, 0))
			M.polygon(surface, [Vector3(0.10, 0, 0.20), Vector3(0, 0.034 * side, 0.20), Vector3(0, 0, 1.08), Vector3(0.075, 0, 0.88)], Vector3(0, side, 0), Color("#b0cbd8"))
		M.mesh_node(root, surface.commit(), Vector3.ZERO, M.paint("#e6eeed", 0.4), "ShortswordBlade")
	elif kind == "can":
		M.cylinder(root, Vector3(0.06, -0.14, 0.21), 0.19, 0.17, 0.30, "#669da0", "WateringCan", 16)
		M.torus(root, Vector3(0.06, 0.03, 0.21), 0.17, 0.023, "#a5c8bf", "CanRim")
		M.beam(root, Vector3(0.04, -0.13, 0.34), Vector3(0.04, 0.02, 0.65), 0.073, "#81b3b0", "Spout", -1, true)
		M.ellipsoid(root, Vector3(0.04, 0.025, 0.67), Vector3(0.095, 0.055, 0.055), "#bdd4c0", "Rose")
		var handle := M.torus(root, Vector3(0.06, 0.05, 0.19), 0.14, 0.024, "#c0cfb4", "CarryHandle")
		handle.rotation.x = PI * 0.5
	elif kind == "seed":
		M.box(root, Vector3(0, -0.09, 0.14), Vector3(0.27, 0.34, 0.15), "#e8cb89", "SeedPacket", 0.033)
		M.box(root, Vector3(0, 0.075, 0.14), Vector3(0.28, 0.045, 0.17), "#ad8c5a", "PacketFold", 0.011)
		M.ellipsoid(root, Vector3(0, -0.08, 0.225), Vector3(0.073, 0.092, 0.013), SEED_COLORS.get(seed_kind, "#ce797e"), "CropPicture", 10, 6)
		M.beam(root, Vector3(0, -0.01, 0.228), Vector3(0.028, 0.035, 0.228), 0.033, "#708653", "LeafPicture")
	elif kind == "fence":
		for x in [-0.16, 0.0, 0.16]:
			M.box(root, Vector3(x, 0, 0.17), Vector3(0.10, 0.57, 0.10), "#c89e62", "FenceStake", 0.018)
		for y in [-0.10, 0.10]:
			M.box(root, Vector3(0, y, 0.11), Vector3(0.48, 0.075, 0.065), "#a37b48", "FenceRail", 0.013)
	elif kind == "rod":
		# 钓鱼竿（LIFE-01）：竹节长杆 + 缠线轮 + 导线环，竿尖前倾。
		M.beam(root, Vector3(0, -0.10, -0.30), Vector3(0, 0.16, 1.05), 0.042, "#a9834f", "RodBamboo", -1, true)
		M.beam(root, Vector3(0, 0.16, 1.05), Vector3(0, 0.30, 1.55), 0.022, "#bd9560", "RodTip", -1, true)
		for z in [0.10, 0.55]:
			M.torus(root, Vector3(0, 0.05 + z * 0.24, z), 0.055, 0.012, "#6d5233", "RodBinding")
		M.cylinder(root, Vector3(0.0, -0.02, 0.16), 0.055, 0.05, 0.13, "#5f4a33", "ReelSeat", 10)
		var reel := M.cylinder(root, Vector3(0.075, -0.05, 0.18), 0.075, 0.075, 0.045, "#8a6f4a", "ReelDrum", 14)
		reel.rotation.z = PI * 0.5
		M.torus(root, Vector3(0.075, -0.05, 0.205), 0.030, 0.008, "#c9c2b4", "ReelKnob")
		M.beam(root, Vector3(0, 0.295, 1.52), Vector3(0, 0.22, 1.45), 0.006, "#e8e4da", "RodLine", -1, true)
	if kind != "hand":
		StaticGeometry.bake(root)
	return root
