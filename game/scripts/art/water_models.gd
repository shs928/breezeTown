extends RefCounted
## 地图水系的纯视觉层。先合并相交水面，河湖接缝不会生成草圈或假岸线。
## 碰撞、耕种限制与寻路由同一份 definition 在领域层处理。

const M = preload("res://scripts/art/art_mesh.gd")
const L = preload("res://scripts/art/landscape_models.gd")
const Valley = preload("res://scripts/art/valley_terrain.gd")
const WATER_Y := -0.28


static func build(definition: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "ValleyWaterways"
	var polygons := _joined_water(definition.get("waters", []))
	var sand := _surface()
	var water := _surface()
	var foam := _surface()
	var bank_details := _surface()
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260916
	var water_material := _water_material()
	for polygon: PackedVector2Array in polygons:
		for outer: PackedVector2Array in Geometry2D.offset_polygon(polygon, 0.64, Geometry2D.JOIN_ROUND):
			_fill(sand, outer, -0.32, Color("#cec199"))
		_fill(water, polygon, WATER_Y, Color("#7fd4d2"))
		for deeper: PackedVector2Array in Geometry2D.offset_polygon(polygon, -0.82, Geometry2D.JOIN_ROUND):
			_fill(water, deeper, WATER_Y + 0.005, Color("#3fb8c8"))
		_shore_details(root, bank_details, foam, polygon, polygons, definition, rng)
		_ripples(foam, polygon, definition, rng)
	_keep_mesh(root, sand, M.paint("#ffffff"), "SoftSandBanks")
	_keep_mesh(root, water, water_material, "ConnectedRiverAndLakes")
	_keep_mesh(root, foam, M.paint("#ffffff", 0.72), "HandPaintedRipples")
	_keep_mesh(root, bank_details, M.paint("#ffffff"), "ShorelineGrasses")
	for bridge: Dictionary in definition.get("bridges", []):
		if bridge.get("stone",false):
			root.add_child(preload("res://scripts/art/stone_bridge.gd").build(bridge["rect"],bridge.get("rise",.52),bridge.get("axis",""),bridge.get("rail_openings",[])))
		else:
			_walkway(root, bridge["rect"], false, str(bridge.get("id", "bridge")))
	for dock: Dictionary in definition.get("docks", []):
		_walkway(root, dock["rect"], true, str(dock.get("id", "dock")))
	if definition["bounds"]["half"].x < 200:
		_build_source(root, water_material)
		_build_outlet(root, water_material, polygons)
	elif definition.get("landmarks", {}).has("waterfall"):
		var fall: Vector3 = definition["landmarks"]["waterfall"]
		_cascade(root, water_material, Vector2(fall.x, fall.z), Vector2(0.06, 1.0), 24.0, 13.0)
	return root


static func _surface() -> SurfaceTool:
	var result := SurfaceTool.new()
	result.begin(Mesh.PRIMITIVE_TRIANGLES)
	return result


static func _keep_mesh(root: Node3D, surface: SurfaceTool, material: Material, label: String) -> void:
	var mesh := surface.commit()
	if mesh == null or mesh.get_surface_count() == 0:
		return
	var node := M.mesh_node(root, mesh, Vector3.ZERO, material, label)
	node.set_meta("keep_meshes", true)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


static func _fill(surface: SurfaceTool, polygon: PackedVector2Array, height: float, tint: Color) -> void:
	var indices := Geometry2D.triangulate_polygon(polygon)
	for i in range(0, indices.size(), 3):
		var triangle: Array[Vector3] = []
		for j in range(3):
			var point := polygon[indices[i + j]]
			triangle.append(Vector3(point.x, height, point.y))
		M.polygon(surface, triangle, Vector3.UP, tint)


static func _joined_water(waters: Array) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	for body: Dictionary in waters:
		var polygon: PackedVector2Array = body.get("polygon", PackedVector2Array())
		if polygon.size() >= 3:
			result.append(polygon)
	var merged := true
	while merged:
		merged = false
		for i in range(result.size()):
			for j in range(i + 1, result.size()):
				var joined := Geometry2D.merge_polygons(result[i], result[j])
				if joined.size() == 1:
					result[i] = joined[0]
					result.remove_at(j)
					merged = true
					break
			if merged:
				break
	return result


static func _water_material() -> ShaderMaterial:
	var result := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = """shader_type spatial;
render_mode cull_disabled;
varying vec2 world_xz;
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.54);}
float noise(vec2 p){vec2 i=floor(p);vec2 f=fract(p);f=f*f*(3.-2.*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1)),f.x),f.y);}
void vertex(){world_xz=(MODEL_MATRIX*vec4(VERTEX,1.)).xz;}
void fragment(){
 vec2 p=world_xz;
 float cloud=noise(p*.31+vec2(TIME*.012,0));
 float flow=sin(p.x*.9+p.y*1.2+TIME*.33)*.5+.5;
 float depth=smoothstep(.12,.34,COLOR.r);
 vec3 deep=mix(vec3(.008,.11,.19),vec3(.015,.19,.26),cloud);
 vec3 shallow=vec3(.06,.26,.29);
 vec3 base=mix(deep,shallow,depth*.62);
 float caustic=pow(1.-abs(sin(p.x*2.5+sin(p.y*1.5+TIME*.28))*sin(p.y*2.2+cos(p.x+TIME*.2))),18.);
 base+=vec3(.02,.05,.04)*caustic;
 float reflection=smoothstep(.97,.997,noise(p*vec2(1.1,5.)+TIME*.02));
 ALBEDO=base+vec3(.12,.15,.14)*reflection;
 ROUGHNESS=.28;SPECULAR=.45;
 NORMAL_MAP=vec3(.5+sin(p.x*1.4+TIME*.3)*.025,.5+cos(p.y*2.+TIME*.4)*.018,1.);
}
"""
	result.shader = shader
	return result


static func _covered_by_walkway(at: Vector2, definition: Dictionary, margin: float = 0.0) -> bool:
	for key in ["bridges", "docks"]:
		for walkway: Dictionary in definition.get(key, []):
			var rect: Rect2 = walkway["rect"]
			if rect.grow(margin).has_point(at):
				return true
	return false


static func _in_water(at: Vector2, polygons: Array[PackedVector2Array]) -> bool:
	for polygon: PackedVector2Array in polygons:
		if Geometry2D.is_point_in_polygon(at, polygon):
			return true
	return false


static func _shore_details(root: Node3D, grass: SurfaceTool, foam: SurfaceTool, polygon: PackedVector2Array, all_water: Array[PackedVector2Array], definition: Dictionary, rng: RandomNumberGenerator) -> void:
	var travelled := 0.0
	for i in range(polygon.size()):
		var start := polygon[i]
		var finish := polygon[(i + 1) % polygon.size()]
		var delta := finish - start
		var length := delta.length()
		if length < 0.08:
			continue
		var along := delta / length
		var inward := Vector2(-along.y, along.x)
		if not Geometry2D.is_point_in_polygon((start + finish) * 0.5 + inward * 0.18, polygon):
			inward = -inward
		var sample := fmod(5.2 - fmod(travelled, 5.2), 5.2)
		while sample < length:
			var shore := start + along * sample
			# 桥头保留清爽的通行宽度，不放芦苇和装饰石。
			if not _covered_by_walkway(shore, definition, 1.0) and absf(shore.y) < definition["bounds"]["half"].y-1.0:
				var outside := shore - inward * 0.22
				if not _in_water(outside, all_water):
					# PERF-01：岸石并入共享网格（此前每颗一个 320 顶点实例，海岸线全程 1500+ 次）。
					if rng.randf() < 0.58:
						_pebble(grass, outside, rng)
					if rng.randf() < 0.42:
						_reeds(grass, outside - inward * 0.25, rng)
					var crest := shore + inward * 0.22
					_stroke(foam, crest, along, rng.randf_range(0.45, 1.1), 0.045, Color("#c0e8d8"), WATER_Y + 0.009)
			sample += 5.2
			travelled += length


static func _pebble(surface: SurfaceTool, at: Vector2, rng: RandomNumberGenerator) -> void:
	# 岸线卵石：七边形轮廓加矮裙边，直接写进共享网格，替代逐颗实例化。
	var radius := Vector3(rng.randf_range(0.20, 0.34), rng.randf_range(0.07, 0.13), rng.randf_range(0.18, 0.30))
	var tint := Color(["#b6b29a", "#c9c2a7", "#9aab9b", "#b8baa4"][rng.randi_range(0, 3)])
	var top: Array[Vector3] = []
	var base: Array[Vector3] = []
	for corner in range(7):
		var angle := corner * TAU / 7.0 + rng.randf_range(-0.15, 0.15)
		var reach := 1.0 + rng.randf_range(-0.18, 0.18)
		var offset := Vector3(cos(angle) * radius.x * reach, 0, sin(angle) * radius.z * reach)
		top.append(Vector3(at.x, 0.02, at.y) + offset + Vector3(0, radius.y, 0))
		base.append(Vector3(at.x, 0.0, at.y) + offset)
	M.polygon(surface, top, Vector3.UP, tint)
	for corner in range(7):
		var next := (corner + 1) % 7
		M.polygon(surface, [base[corner], base[next], top[next], top[corner]], Vector3.RIGHT, tint.darkened(0.14))


static func _reeds(surface: SurfaceTool, at: Vector2, rng: RandomNumberGenerator) -> void:
	for i in range(6):
		var base := Vector3(at.x + rng.randf_range(-0.23, 0.23), 0.016, at.y + rng.randf_range(-0.23, 0.23))
		var angle := rng.randf_range(0.0, TAU)
		var side := Vector3(cos(angle), 0, sin(angle)) * rng.randf_range(0.035, 0.065)
		var tip := base + Vector3(side.x * 2.4, rng.randf_range(0.28, 0.68), side.z * 2.4)
		M.polygon(surface, [base - side, base + side, tip], Vector3.UP, Color("#7b9d55") if i % 2 else Color("#b1b36b"))


static func _ripples(surface: SurfaceTool, polygon: PackedVector2Array, definition: Dictionary, rng: RandomNumberGenerator) -> void:
	var rect := Rect2(polygon[0], Vector2.ZERO)
	for point in polygon:
		rect = rect.expand(point)
	var spacing:=12.0 if definition["bounds"]["half"].x>200 else 3.5
	for x in range(floori(rect.position.x / spacing), ceili(rect.end.x / spacing)):
		for z in range(floori(rect.position.y / spacing), ceili(rect.end.y / spacing)):
			var at := Vector2(x * spacing + rng.randf_range(-0.8, 0.8), z * spacing + rng.randf_range(-0.8, 0.8))
			if not Geometry2D.is_point_in_polygon(at, polygon) or _covered_by_walkway(at, definition, 0.7):
				continue
			var direction := Vector2(1.0, 0.18 + sin(z * 0.7) * 0.16).normalized()
			var length := rng.randf_range(0.30, 0.84)
			if not Geometry2D.is_point_in_polygon(at + direction * length, polygon) or not Geometry2D.is_point_in_polygon(at - direction * length, polygon):
				continue
			_stroke(surface, at, direction, length, 0.032, Color("#7fc6c5") if (x + z) % 3 else Color("#54b4bc"), WATER_Y + 0.012)
			if (x * 3 + z) % 5 == 0:
				_stroke(surface, at + Vector2(-0.12, 0.22), direction, length * 0.48, 0.028, Color("#6cbfc0"), WATER_Y + 0.012)


static func _stroke(surface: SurfaceTool, at: Vector2, direction: Vector2, length: float, width: float, tint: Color, height: float) -> void:
	var side := Vector2(-direction.y, direction.x)
	for i in range(4):
		var a := float(i) / 4.0
		var b := float(i + 1) / 4.0
		var p := at + direction * (a - 0.5) * length + side * sin(a * PI) * length * 0.08
		var q := at + direction * (b - 0.5) * length + side * sin(b * PI) * length * 0.08
		var spread := side * width
		M.polygon(surface, [Vector3(p.x, height, p.y), Vector3(q.x, height, q.y), Vector3(q.x + spread.x, height, q.y + spread.y), Vector3(p.x + spread.x, height, p.y + spread.y)], Vector3.UP, tint)


static func _walkway(root: Node3D, rect: Rect2, dock: bool, label: String) -> void:
	var deck := Node3D.new()
	deck.name = "Dock_" + label if dock else "Bridge_" + label
	deck.position = Vector3(rect.get_center().x, 0, rect.get_center().y)
	root.add_child(deck)
	var horizontal := rect.size.x >= rect.size.y
	var length := rect.size.x if horizontal else rect.size.y
	var width := rect.size.y if horizontal else rect.size.x
	if not horizontal:
		deck.rotation.y = PI * 0.5
	var count := maxi(1, ceili(length / 0.40))
	var plank_length := length / float(count)
	for i in range(count):
		var x := -length * 0.5 + (i + 0.5) * plank_length
		M.box(deck, Vector3(x, 0.085, 0), Vector3(plank_length - 0.023, 0.10, width), ["#b68d58", "#c49d66", "#b99462", "#c6a272"][i % 4], "DeckPlank", 0.016)
		# 木纹和嵌钉只占少量几何，保持俯视下的手作质感。
		if i % 3 == 0:
			M.box(deck, Vector3(x, 0.138, width * 0.11), Vector3(plank_length * 0.035, 0.003, width * 0.52), "#9c784f", "PlankGrain", 0)
	for side in [-1.0, 1.0]:
		var z: float = side * (width * 0.5 - 0.17)
		M.box(deck, Vector3(0, 0.026, z), Vector3(length, 0.18, 0.18), "#806247", "UnderDeckBeam")
		var post_count := maxi(2, ceili(length / 2.6) + 1)
		for i in range(post_count):
			var x := lerpf(-length * 0.5 + 0.18, length * 0.5 - 0.18, float(i) / (post_count - 1))
			M.box(deck, Vector3(x, 0.55 if not dock else 0.40, z), Vector3(0.22, 1.10 if not dock else 0.80, 0.22), "#8b6845", "BridgePost")
			M.box(deck, Vector3(x, 1.12 if not dock else 0.82, z), Vector3(0.26, 0.055, 0.26), "#c19c65", "PostCap")
		if not dock:
			M.box(deck, Vector3(0, 0.87, z), Vector3(length - 0.2, 0.14, 0.14), "#a5804f", "Handrail")
			M.box(deck, Vector3(0, 0.46, z), Vector3(length - 0.2, 0.11, 0.10), "#997649", "LowerRail")
	if dock:
		for side in [-1.0, 1.0]:
			M.torus(deck, Vector3(length * 0.31, 0.16, side * width * 0.29), 0.18, 0.035, "#cfb681", "CoiledMooringRope")


static func _cascade(root: Node3D, material: ShaderMaterial, at: Vector2, dir: Vector2, drop: float, width: float) -> void:
	# 大图北岭瀑布：沿溪流方向从山体多级跌入 north_creek，两侧以岩峰收口。
	var cascade := _surface()
	var froth := _surface()
	var forward := Vector3(dir.x, 0, dir.y).normalized()
	var side := Vector3(-forward.z, 0, forward.x)
	var run := drop * 1.35
	var stages := 5
	for i in range(stages):
		var t0 := float(i) / stages
		var t1 := float(i + 1) / stages
		var y0 := lerpf(drop, WATER_Y + 0.012, pow(t0, 1.55))
		var y1 := lerpf(drop, WATER_Y + 0.012, pow(t1, 1.55))
		var from := Vector3(at.x, y0, at.y) + forward * (t0 - 0.5) * run
		var to := Vector3(at.x, y1, at.y) + forward * (t1 - 0.5) * run
		var span := width * (0.80 + 0.42 * t1)
		var cross := side * span * 0.5
		var normal := (to - from).cross(side).normalized()
		if normal.y < 0:
			normal = -normal
		M.polygon(cascade, [from - cross, from + cross, to + cross, to - cross], normal, Color("#72cfd4"))
		for lane in range(9):
			var offset := side * ((lane / 8.0 - 0.5) * span * 0.86)
			var top := from + offset + forward * 0.05
			var foot := to + offset + forward * 0.05
			var spread := side * (0.05 if lane % 2 else 0.16)
			M.polygon(froth, [top - spread, top + spread, foot + spread, foot - spread], normal, Color("#d6eee0") if lane % 2 else Color("#b4e3de"))
		for side_sign in [-1.0, 1.0]:
			if i % 2 == 0:
				var rock := Valley.crag(610 + i + int(side_sign), Vector2(2.6 + i * 0.3, 3.6 + i * 0.35), maxf(2.4, y0 * 0.5))
				rock.position = Vector3(at.x, 0, at.y) + forward * ((t0 + t1) * 0.5 - 0.5) * run + side * side_sign * (span * 0.5 + 2.6)
				root.add_child(rock)
		if i >= stages - 2:
			for wave in range(3):
				_stroke(froth, Vector2(to.x, to.z) + Vector2(forward.x, forward.z) * wave * 0.55, Vector2(side.x, side.z), span * (0.8 + wave * 0.2), 0.14 - wave * 0.03, Color("#d2ede0"), to.y + 0.02)
	_keep_mesh(root, cascade, material, "NorthernRidgeWaterfall")
	_keep_mesh(root, froth, M.paint("#ffffff", 0.72), "RidgeWaterfallFoam")


static func _build_source(root: Node3D, material: ShaderMaterial) -> void:
	var cascade := _surface()
	var froth := _surface()
	var stages := [Vector3(16, 8.1, -92), Vector3(16.3, 5.9, -87.2), Vector3(15.8, 2.4, -83.4), Vector3(16, WATER_Y + 0.007, -78.4)]
	for i in range(stages.size() - 1):
		var from: Vector3 = stages[i]
		var to: Vector3 = stages[i + 1]
		var width := 3.4 + i * 0.50
		var cross := Vector3.RIGHT * width * 0.5
		var normal := Vector3(0, 0.7, 0.7).normalized()
		M.polygon(cascade, [from - cross, from + cross, to + cross, to - cross], normal, Color("#72cfd4"))
		for lane in range(7):
			var offset := Vector3.RIGHT * ((lane / 6.0 - 0.5) * width * 0.84)
			var top := from + offset + Vector3(0, 0.03, 0.035)
			var foot := to + offset + Vector3(0, 0.045, 0.035)
			var spread := Vector3.RIGHT * (0.028 if lane % 2 else 0.072)
			M.polygon(froth, [top - spread, top + spread, foot + spread, foot - spread], normal, Color("#d6eee0") if lane % 2 else Color("#b4e3de"))
		for side in [-1.0, 1.0]:
			var stone := Valley.crag(84 + i, Vector2(2.2 + i * 0.25, 3.0), maxf(1.7, from.y + 0.45))
			stone.position = Vector3(from.x + side * (width * 0.5 + 1.2), 0.0, (from.z + to.z) * 0.5)
			root.add_child(stone)
		for wave in range(3):
			_stroke(froth, Vector2(to.x, to.z + wave * 0.22), Vector2.RIGHT, width * (0.86 + wave * 0.14), 0.10 - wave * 0.025, Color("#d2ede0"), to.y + 0.018)
	_keep_mesh(root, cascade, material, "NorthernSpringWaterfall")
	_keep_mesh(root, froth, M.paint("#ffffff", 0.72), "WaterfallFoam")


static func _build_outlet(root: Node3D, material: ShaderMaterial, polygons: Array[PackedVector2Array]) -> void:
	# 河流越过南部海崖后流入海面，补足 0 米谷底与低位海面的高度差。
	var coast_point := Vector2(-11, 79.8)
	if not _in_water(coast_point, polygons):
		return
	var cascade := _surface()
	var foam := _surface()
	for i in range(8):
		var t0 := float(i) / 8.0
		var t1 := float(i + 1) / 8.0
		var z0 := lerpf(79.5, 87.0, t0)
		var z1 := lerpf(79.5, 87.0, t1)
		var y0 := lerpf(WATER_Y, -1.96, t0 * t0)
		var y1 := lerpf(WATER_Y, -1.96, t1 * t1)
		M.polygon(cascade, [Vector3(-14, y0, z0), Vector3(-8, y0, z0), Vector3(-8, y1, z1), Vector3(-14, y1, z1)], Vector3.UP, Color("#7fd4d2"))
	for i in range(8):
		_stroke(foam, Vector2(-11.0 + sin(i * 2.4) * 0.6, 86.9 + i * 0.25), Vector2.RIGHT, 5.7 + i * 0.16, 0.075, Color("#c6e7d8"), -1.94)
	_keep_mesh(root, cascade, material, "RiverMeetsCoast")
	_keep_mesh(root, foam, M.paint("#ffffff"), "CoastalOutletFoam")
