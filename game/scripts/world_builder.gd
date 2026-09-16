extends RefCounted
## 192×160 米的微风山谷：农场、牧场、镇中心、住宅街、果园和山林湖畔。
## 道路、建筑占地与地标只登记一次，供碰撞、开垦限制和导览图共同使用。

const M = preload("res://scripts/art/art_mesh.gd")
const L = preload("res://scripts/art/landscape_models.gd")
const B = preload("res://scripts/art/building_models.gd")
const Town = preload("res://scripts/art/town_models.gd")
const Valley = preload("res://scripts/art/valley_terrain.gd")
const StaticGeometry = preload("res://scripts/art/static_geometry.gd")
const Ranch = preload("res://scripts/ranch_models.gd")
const MineModels = preload("res://scripts/art/mine_models.gd")
const Definition = preload("res://scripts/data/valley_map_definition.gd")
const WaterModels = preload("res://scripts/art/water_models.gd")

static var _templates := {}


static func build() -> Dictionary:
	if "--reference-farm" not in OS.get_cmdline_user_args():
		return preload("res://scripts/first_map_builder.gd").build()
	return build_reference_farm()


static func build_reference_farm() -> Dictionary:
	var definition := Definition.create()
	var root := Node3D.new()
	root.name = "World"
	var water_polygons: Array[PackedVector2Array] = []
	for water: Dictionary in definition["waters"]:
		water_polygons.append(water["polygon"])
	var data := {
		"root": root, "definition": definition,
		"obstacles": [], "sites": [], "roads": [], "lights": [], "resources": [],
		"blocked": {"rects": [], "circles": [], "paths": [], "polygons": water_polygons},
		"reserved": definition["reserved"].duplicate(),
		"bounds": definition["bounds"].duplicate(),
		"landmarks": definition["landmarks"].duplicate(),
		"pasture": definition["pasture"],
	}
	root.add_child(Valley.build(definition["bounds"]["half"], definition["bounds"]["pow"]))
	_build_roads(data)
	_build_farm(data)
	_build_town(data)
	_build_square(data)
	_build_mine_entrance(data)
	root.add_child(WaterModels.build(definition))
	for bridge:Dictionary in definition["bridges"]:
		if not bridge.get("stone",false):continue
		var bridge_rect:Rect2=bridge["rect"]
		for z in [bridge_rect.position.y+.16,bridge_rect.end.y-.16]:
			_box(data,Vector3(bridge_rect.get_center().x,.6,z),Vector3(bridge_rect.size.x,1.5,.40))
	_build_landscape(data)
	root.add_child(preload("res://scripts/art/cozy_landscape.gd").build(definition, data))
	_build_mountain_details(data)
	StaticGeometry.bake(root)
	data["navigation"] = {
		"half": definition["bounds"]["half"], "power": definition["bounds"]["pow"],
		"sites": data["sites"], "roads": data["roads"],
		"farm": definition["farm"], "ranch": definition["ranch"],
		"lake_center": definition["lake_center"], "lake_radius": definition["lake_radius"],
		"mine": Vector2(-29, -73), "waters": definition["waters"],
		"bridges": definition["bridges"], "regions": definition["regions"],
		"forests": definition["forests"], "docks": definition["docks"],
		"bounds": definition["bounds"], "map_id": definition["id"], "revision": definition["revision"],
	}
	# 模板仅用于本次构建，释放离树节点；已放置的副本继续共享网格资源。
	for template: Node3D in _templates.values():
		template.free()
	_templates.clear()
	return data


static func _build_roads(data: Dictionary) -> void:
	for road: Dictionary in data["definition"]["roads"]:
		_path(data, road["points"], road["width"], road["paved"], road["id"])


static func _build_mine_entrance(data: Dictionary) -> void:
	place(data["root"], MineModels.entrance(), Vector3(-29, 0, -74))
	_box(data, Vector3(-29, 2.8, -74), Vector3(11, 5.6, 5.4))
	_box(data, Vector3(-25.35, 0.6, -70.75), Vector3(1.65, 1.2, 1.8))
	data["blocked"]["rects"].append(Rect2(-36, -78, 15, 10))
	data["lights"].append(Vector3(-31.65, 1.8, -71.3))
	data["lights"].append(Vector3(-26.35, 1.8, -71.3))
	_signpost(data, Vector2(-26.5, -62), "↑ 星辉矿场 · 10 层", 4.1)
	_signpost(data, Vector2(-24, -39), "↑ 星辉矿场", 3.1)


static func _build_farm(data: Dictionary) -> void:
	var root: Node3D = data["root"]
	for entry: Dictionary in data["definition"]["buildings"]:
		var model: Node3D
		match entry["kind"]:
			"cottage":
				model = preload("res://scripts/art/authored_assets.gd").instantiate("res://resources/models/cottage.glb")
				model.set_meta("keep_meshes",true)
				model.scale = Vector3.ONE * 1.7
			"shop": model = B.shop()
			"barn": model = Ranch.barn()
			"coop": model = Ranch.coop()
			_: continue
		var at: Vector2 = entry["position"]
		model.name = entry["id"]
		place(root, model, Vector3(at.x, 0.025, at.y))
		_register_building(data, entry["id"], entry["label"], at, entry["size"], entry["door"])
	for bale in [Vector3(26, 0.44, 1.1), Vector3(27.3, 0.44, 1.5)]:
		place(root, _tpl("hay", func(): return Ranch.hay_bale()), bale)
		_sphere(data, bale, 0.7)
	# 农田围栏分别在东侧和南侧留出可通行的大门。
	for endpoints in [
		[Vector2(-44, 2), Vector2(-44, 29)], [Vector2(-44, 2), Vector2(-31, 2)], [Vector2(-26, 2), Vector2(-15, 2)],
		[Vector2(-15, 2), Vector2(-15, 7.3)], [Vector2(-15, 12.4), Vector2(-15, 29)],
		[Vector2(-44, 29), Vector2(-28.5, 29)], [Vector2(-23.5, 29), Vector2(-15, 29)],
	]:
		_fence_line(data, endpoints[0], endpoints[1])
	place(root, L.well(), Vector3(-5.5, 0, 22), -0.2)
	_sphere(data, Vector3(-5.5, 0, 22), 0.95)
	place(root, L.barrel(), Vector3(-25.5, 0, -0.5))
	_sphere(data, Vector3(-25.5, 0, -0.5), 0.48)
	place(root, L.crate(true), Vector3(24.3, 0, -14.5), 0.12)
	_sphere(data, Vector3(24.3, 0, -14.5), 0.6)
	place(root, L.watering_can(), Vector3(-11, 0.13, 13.5), -0.6)
	_signpost(data, Vector2(-9.5, -15.6), "↑ 镇中心   ← 农舍", 3.4)
	_signpost(data, Vector2(8.3, 25.1), "← 农田   牧场 →", 3.0)


static func _build_town(data: Dictionary) -> void:
	var root: Node3D = data["root"]
	for entry: Dictionary in data["definition"]["buildings"]:
		var kind: String = entry["kind"]
		if kind in ["cottage", "shop", "barn", "coop"]:
			continue
		var at: Vector2 = entry["position"]
		var size: Vector2 = entry["size"]
		var door: Vector2 = entry["door"]
		var model := Town.building(kind)
		model.name = entry["id"]
		place(root, model, Vector3(at.x, 0, at.y))
		_register_building(data, entry["id"], entry["label"], at, size, door)
		# 石坪、庭院均从地图足印构造，不反向读取美术节点尺寸。
		M.box(root, Vector3(at.x, 0.018, door.y - 0.1), Vector3(size.x + 0.6, 0.035, 2.5), "#c5bea0", "DoorstepPaving", 0.04)
		data["blocked"]["rects"].append(Rect2(Vector2(at.x - size.x * 0.5 - 0.35, door.y - 1.35), Vector2(size.x + 0.7, 2.5)))
		if kind in ["smith", "carpenter"]:
			_box(data, Vector3(at.x + size.x * 0.5 + 1.5, 0.6, at.y + 0.1), Vector3(2.7, 1.2, 3.4))
		if kind.begins_with("home"):
			var garden := Rect2(at - Vector2(size.x * 0.5 + 1.05, size.y * 0.5 + 0.9), size + Vector2(2.1, 4.5))
			data["reserved"].append(garden)
			data["blocked"]["rects"].append(garden)
			_fence_line(data, garden.position, Vector2(garden.position.x, garden.end.y))
			_fence_line(data, Vector2(garden.end.x, garden.position.y), garden.end)
			for side in [-1.0, 1.0]:
				place(root, _tpl("front_flowers", func(): return L.flowers(3, true)), Vector3(at.x + side * (size.x * 0.5 + 0.4), 0, at.y + 1.1))
		data["lights"].append(Vector3(door.x + 0.8, 2, at.y + size.y * 0.5 + 0.05))


static func _build_square(data: Dictionary) -> void:
	var root: Node3D = data["root"]
	var square: Rect2 = data["definition"]["square"]
	var center := square.get_center()
	data["blocked"]["rects"].append(square)
	M.box(root, Vector3(center.x, 0.027, center.y), Vector3(square.size.x, 0.052, square.size.y), "#c7c3a7", "TownSquarePaving", 0.05)
	for row in range(12):
		for col in range(13):
			var at := Vector3(square.position.x + 0.85 + col * 1.5 + (row % 2) * 0.12, 0.057, square.position.y + 0.85 + row * 1.5)
			M.box(root, at, Vector3(1.40, 0.026, 1.40), "#d0c9ad" if (row + col) % 4 else "#b9b9a0", "SquareFlagstone", 0.025)
	# 中轴贯通桥与镇公所，喷泉和公告板布置在通行路线两侧。
	var fountain := Vector3(center.x + 5.4, 0, center.y + 0.5)
	M.cylinder(root, fountain + Vector3(0, 0.16, 0), 2.0, 1.9, 0.32, "#999d87", "FountainBase", 24)
	M.cylinder(root, fountain + Vector3(0, 0.37, 0), 1.65, 1.65, 0.12, "#7faea6", "FountainWater", 32)
	M.torus(root, fountain + Vector3(0, 0.38, 0), 1.81, 0.17, "#cbc6a9", "FountainRim")
	M.cylinder(root, fountain + Vector3(0, 0.80, 0), 0.32, 0.20, 1.3, "#b5b79e", "FountainPillar", 12)
	M.cylinder(root, fountain + Vector3(0, 1.35, 0), 0.85, 0.95, 0.16, "#c6c6ab", "FountainBowl", 24)
	_sphere(data, fountain, 2.0)
	place(root, Town.noticeboard(), Vector3(center.x - 6.5, 0, center.y - 5.4))
	_box(data, Vector3(center.x - 6.5, 0.9, center.y - 5.4), Vector3(2.3, 1.8, 0.45))
	for bench in [Vector3(center.x - 6.3, 0, center.y + 4), Vector3(center.x + 5.6, 0, center.y + 5.7), Vector3(10, 0, 54), Vector3(73, 0, 42)]:
		place(root, _tpl("bench", func(): return Town.bench()), bench)
		_box(data, bench + Vector3(0, 0.42, 0), Vector3(2.0, 0.84, 0.65))
	for at in [Vector2(26.3, -47.6), Vector2(43.7, -47.6), Vector2(26.3, -32.7), Vector2(43.7, -32.7), Vector2(-5, 7), Vector2(11, -21), Vector2(57, -43), Vector2(72, -18), Vector2(-39, -38), Vector2(-10, 35), Vector2(36, 29)]:
		_lamp(data, at)
	_signpost(data, Vector2(56, -37), "← 广场   住宅街 →", 3.6)
	_signpost(data, Vector2(-48, -37), "← 山林   微风镇 →", 3.5)
	_signpost(data, Vector2(43, 22), "↓ 月湾湖   ← 牧场", 3.2)


static func _build_landscape(data: Dictionary) -> void:
	var root: Node3D = data["root"]
	var half: Vector2 = data["bounds"]["half"]
	var power: int = data["bounds"]["pow"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 91626
	# 园圃与果园为农区补上可辨认的景观层次。
	for row in range(3):
		for col in range(4):
			var at := Vector3(-61 + col * 5.0, 0, 37 + row * 5.0)
			_resource(data, Vector2(at.x, at.z), "apple", rng)
	for at in [Vector3(-15, 0, -19), Vector3(7, 0, -18), Vector3(-38, 0, -19), Vector3(34, 0, -12), Vector3(-19, 0, -33), Vector3(22, 0, -62)]:
		if not _scatter_excluded(data, Vector2(at.x, at.z), 2.2):
			_resource(data, Vector2(at.x, at.z), "oak", rng)
	# 农田南侧的小树林让刚起步的玩家也能找到木材与普通矿石。
	for at in [Vector2(-18, 38), Vector2(-23, 42), Vector2(-16, 44), Vector2(-9, 47), Vector2(-29, 41), Vector2(-30, 47)]:
		if not _scatter_excluded(data, at, 2.2):
			_resource(data, at, "oak" if at.x > -25 else "pine", rng)
	for entry in [{"at": Vector2(-14, 38), "kind": "copper"}, {"at": Vector2(-10, 40), "kind": "stone"}, {"at": Vector2(-24, 47), "kind": "coal"}]:
		if not _scatter_excluded(data, entry["at"], 1.1):
			data["resources"].append({"category": "ore", "position": entry["at"], "kind": entry["kind"]})
	var trees: Array[Vector2] = []
	for i in range(820):
		var at := Vector2(rng.randf_range(-90, 90), rng.randf_range(-75, 74))
		var edge := pow(absf(at.x) / half.x, power) + pow(absf(at.y) / half.y, power)
		if edge > 0.91 or (absf(at.x) < 69 and at.y > -58 and at.y < 62):
			continue
		if _scatter_excluded(data, at, 2.2):
			continue
		var too_close := false
		for prior in trees:
			if prior.distance_to(at) < 3.5:
				too_close = true
				break
		if too_close:
			continue
		trees.append(at)
		_resource(data, at, "pine" if i % 3 != 0 else "oak", rng, rng.randf_range(0.95, 1.3))
	for i in range(1150):
		var at := Vector2(rng.randf_range(-90, 90), rng.randf_range(-74, 74))
		if _scatter_excluded(data, at, 0.3):
			continue
		var decoration: Node3D
		if i % 6 == 0:
			decoration = _tpl("flowers%d" % (i % 2), func(): return L.flowers(i % 2, i % 2 == 0))
		else:
			decoration = _tpl("grass", func(): return L.grass_clump(3))
		place(root, decoration, Vector3(at.x, 0.026, at.y), rng.randf_range(0, TAU))
	for i in range(34):
		var at := Vector2(rng.randf_range(-86, 86), rng.randf_range(-73, 69))
		if _scatter_excluded(data, at, 1.0) or (absf(at.x) < 68 and absf(at.y) < 58):
			continue
		data["resources"].append({"category": "ore", "position": at, "kind": "stone"})


static func _resource(data: Dictionary, at: Vector2, species: String, rng: RandomNumberGenerator, factor: float = 1.0) -> void:
	# 只记录位置；砍伐资源不可合并进整张地图，也不登记永久碰撞。
	data["resources"].append({"category": "tree", "position": at, "species": species, "variant": rng.randi_range(0, 5), "yaw": rng.randf_range(0, TAU), "scale": factor})


static func _build_mountain_details(data: Dictionary) -> void:
	var root: Node3D = data["root"]
	var half: Vector2 = data["bounds"]["half"]
	var power: int = data["bounds"]["pow"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 77192
	for i in range(18):
		# 参考图的高峰集中北方，南部海岸保留天际线与湖湾视野。
		var angle := PI + (i + 0.5) * PI / 18.0 + rng.randf_range(-0.04, 0.04)
		var at := Valley.boundary_point(angle, half, power, rng.randf_range(30, 63))
		if absf(at.x - 16) < 12:
			continue
		var peak := Valley.crag(i + 71, Vector2(rng.randf_range(21, 29), rng.randf_range(19, 27)), rng.randf_range(30, 47))
		place(root, peak, at, rng.randf_range(0, TAU))
	for i in range(280):
		var angle := rng.randf_range(0, TAU)
		# 南侧近景保留低矮山脚，避免跟随相机穿入树冠。
		var band := 3 if sin(angle) < 0.25 else 4
		var at := Valley.ring_point(angle, band, half, power).lerp(Valley.ring_point(angle, band + 1, half, power), rng.randf())
		if at.y > 0.7 and (sin(angle) < -0.35 or cos(angle) < -0.7) and absf(at.x - 16) > 8:
			place(root, _tpl("mountain_pine", func(): return Valley.pine(7)), at, angle, rng.randf_range(0.85, 1.65))
	for cluster in range(31):
		var center_angle := rng.randf_range(0, TAU)
		for i in range(rng.randi_range(2, 5)):
			var angle := center_angle + rng.randf_range(-0.045, 0.045)
			var at := Valley.boundary_point(angle, half, power, rng.randf_range(-1.5, 1.0))
			if _near_water(data, Vector2(at.x, at.z), 2.0):
				continue
			var factor := rng.randf_range(0.85, 1.65)
			place(root, _tpl("foot_rock", func(): return L.stone(2, Vector3(1.5, 1.05, 1.2))), at, angle, factor)
			_sphere(data, at, factor * 1.1)


static func _register_building(data: Dictionary, id: String, label: String, at: Vector2, size: Vector2, door: Vector2) -> void:
	_box(data, Vector3(at.x, 1.25, at.y), Vector3(size.x, 2.5, size.y))
	data["blocked"]["rects"].append(Rect2(at - size * 0.5 - Vector2.ONE * 0.65, size + Vector2.ONE * 1.3))
	data["sites"].append({"id": id, "label": label, "position": at, "size": size, "door": door})


static func _lamp(data: Dictionary, at: Vector2) -> void:
	place(data["root"], _tpl("lamp", func(): return L.lantern_post()), Vector3(at.x, 0, at.y))
	_sphere(data, Vector3(at.x, 0, at.y), 0.20)
	data["lights"].append(Vector3(at.x + 0.37, 1.45, at.y))


static func _signpost(data: Dictionary, at: Vector2, title: String, width: float) -> void:
	var sign := Node3D.new()
	M.box(sign, Vector3(0, 0.75, 0), Vector3(0.16, 1.5, 0.16), "#a58960", "Signpost")
	Town.signboard(sign, title, Vector3(0, 1.35, 0), width)
	place(data["root"], sign, Vector3(at.x, 0, at.y))
	_sphere(data, Vector3(at.x, 0, at.y), 0.22)


static func _scatter_excluded(data: Dictionary, at: Vector2, margin: float) -> bool:
	var half: Vector2 = data["bounds"]["half"]
	var power: int = data["bounds"]["pow"]
	var edge := pow(absf(at.x) / (half.x - 3), power) + pow(absf(at.y) / (half.y - 3), power)
	if edge > 1:
		return true
	if _near_water(data, at, margin):
		return true
	for bridge: Dictionary in data["definition"]["bridges"]:
		if (bridge["rect"] as Rect2).grow(margin).has_point(at):
			return true
	for rect: Rect2 in data["reserved"]:
		if rect.grow(margin).has_point(at):
			return true
	for rect: Rect2 in data["blocked"]["rects"]:
		if rect.grow(margin).has_point(at):
			return true
	for circle: Dictionary in data["blocked"]["circles"]:
		if at.distance_to(circle["position"]) < circle["radius"] + margin:
			return true
	for resource: Dictionary in data["resources"]:
		if at.distance_to(resource["position"]) < 0.6 + margin:
			return true
	for path: Dictionary in data["blocked"]["paths"]:
		if Geometry2D.get_closest_point_to_segment(at, path["from"], path["to"]).distance_to(at) < path["width"] * 0.5 + margin:
			return true
	return false


static func _near_water(data: Dictionary, at: Vector2, margin: float) -> bool:
	for polygon: PackedVector2Array in data["blocked"]["polygons"]:
		if Geometry2D.is_point_in_polygon(at, polygon):
			return true
		for edge_index in range(polygon.size()):
			if Geometry2D.get_closest_point_to_segment(at, polygon[edge_index], polygon[(edge_index + 1) % polygon.size()]).distance_to(at) < margin + 0.7:
				return true
	return false


static func _path(data: Dictionary, points: Array, width: float, paved: bool = false, id: String = "") -> void:
	data["roads"].append({"id": id, "points": points, "width": width, "paved": paved})
	for segment in range(points.size() - 1):
		data["blocked"]["paths"].append({"from": points[segment], "to": points[segment+1], "width": width})
	data["root"].add_child(preload("res://scripts/art/painted_paths.gd").build(points,width,paved,int(points[0].x*800+points[0].y*210)+913))


static func _fence_line(data: Dictionary, from: Vector2, to: Vector2) -> void:
	var length := from.distance_to(to)
	var count := maxi(1, roundi(length / 2.4))
	var along_x := absf(to.x - from.x) > absf(to.y - from.y)
	for i in range(count):
		var at := from.lerp(to, (i + 0.5) / float(count))
		var fence := _tpl("fence", func(): return L.fence())
		fence.scale.x = length / count / 2.4
		place(data["root"], fence, Vector3(at.x, 0.01, at.y), 0.0 if along_x else PI * 0.5)
	var center := (from + to) * 0.5
	_box(data, Vector3(center.x, 0.45, center.y), Vector3(absf(to.x - from.x) + 0.18, 0.9, absf(to.y - from.y) + 0.18))


static func _box(data: Dictionary, at: Vector3, size: Vector3) -> void:
	data["obstacles"].append({"shape": "box", "position": at, "size": size})
	data["blocked"]["rects"].append(Rect2(Vector2(at.x, at.z) - Vector2(size.x, size.z) * 0.5, Vector2(size.x, size.z)))


static func _sphere(data: Dictionary, at: Vector3, radius: float) -> void:
	data["obstacles"].append({"shape": "sphere", "position": Vector3(at.x, 0.55, at.z), "radius": radius})
	data["blocked"]["circles"].append({"position": Vector2(at.x, at.z), "radius": radius})


static func _tpl(key: String, builder: Callable) -> Node3D:
	if not _templates.has(key):
		_templates[key] = builder.call()
	return (_templates[key] as Node3D).duplicate()


static func place(parent: Node3D, child: Node3D, at: Vector3, yaw: float = 0.0, uniform_scale: float = 1.0) -> Node3D:
	child.position = at
	child.rotation.y = yaw
	child.scale *= uniform_scale
	parent.add_child(child)
	return child
