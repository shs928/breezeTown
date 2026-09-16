extends RefCounted
## 平坦生活区与同一边界上的北方雪岭、西侧林坡、南东海岸。
## 只构建表现；可行走边界仍由地图领域数据统一管理。

const M = preload("res://scripts/art/art_mesh.gd")
const SEGMENTS := 256
const OFFSETS := [0.0, 2.8, 4.6, 7.2, 11.8, 16.0, 24.0, 34.0, 49.0, 65.0, 86.0, 118.0, 170.0]
const HEIGHTS := [0.0, 0.65, 3.4, 3.55, 6.8, 6.5, 13.0, 20.5, 14.0, 29.0, 20.0, 11.0, -0.8]
const COLORS := ["#809f61", "#aaa18a", "#8a9c6b", "#9a9783", "#748b5b", "#74836b", "#7a897c", "#86948a", "#94a199", "#b5c0b6", "#cbd4cb", "#aabca9"]
const COAST_HEIGHTS := [0.0, 0.18, -0.65, -1.8, -2.9, -3.6, -4.0, -4.0, -4.0, -4.0, -4.0, -4.0, -4.0]
const COAST_COLORS := ["#a4b979", "#d5c8a0", "#b8b7a2", "#8fa5a0", "#77a5a2", "#589995", "#529590", "#529590", "#529590", "#529590", "#529590", "#529590"]


static func boundary_point(angle: float, half: Vector2, power: int, offset: float = 0.0) -> Vector3:
	var direction := Vector2(cos(angle), sin(angle))
	var extent := half + Vector2.ONE * offset
	var radius := pow(pow(absf(direction.x) / extent.x, power) + pow(absf(direction.y) / extent.y, power), -1.0 / float(power))
	return Vector3(direction.x * radius, 0, direction.y * radius)


static func ring_point(angle: float, band: int, half: Vector2, power: int) -> Vector3:
	var offset: float = OFFSETS[band]
	var wave := sin(angle * 11.0 + 0.8) * 0.7 + cos(angle * 19.0) * 0.4
	var at := boundary_point(angle, half, power, offset + wave * minf(offset * 0.24, 13.0))
	var peaks := 0.85 + sin(angle * 7.0 + band * 0.65) * 0.24 + cos(angle * 13.0 - band * 0.82) * 0.16
	var ridge := _ridge_weight(angle)
	at.y = lerpf(COAST_HEIGHTS[band], HEIGHTS[band] * peaks, ridge)
	# 河源在北缘留出一条连续岩谷，瀑布不会穿入山体。
	if at.z < -half.y + 1.0 and absf(at.x - 16.0) < 8.0 and offset < 17.0:
		var channel := 1.0 - smoothstep(3.8, 8.0, absf(at.x - 16.0))
		at.y = lerpf(at.y, maxf(0.0, offset * 0.32), channel)
	return at


static func _ridge_weight(angle: float) -> float:
	var north := 1.0 - smoothstep(-0.86, -0.12, sin(angle))
	var west := (1.0 - smoothstep(-0.94, -0.48, cos(angle))) * 0.56
	return maxf(north, west)


static func build(half: Vector2, power: int) -> Node3D:
	var definition:Dictionary=preload("res://scripts/data/valley_map_definition.gd").create()
	var root := Node3D.new()
	root.name = "CoastalValley"
	# 已经是合并后的大网格，无需再拆分到静态道具批次中。
	root.set_meta("keep_meshes", true)
	var meadow := SurfaceTool.new()
	meadow.begin(Mesh.PRIMITIVE_TRIANGLES)
	var mountain := SurfaceTool.new()
	mountain.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(SEGMENTS):
		var a := float(i) / SEGMENTS * TAU
		var b := float(i + 1) / SEGMENTS * TAU
		var edge_a := boundary_point(a, half, power)
		var edge_b := boundary_point(b, half, power)
		# The interior is meshed below with recessed waterways; no flat fan covers the stream.
		for band in range(OFFSETS.size() - 1):
			var p := ring_point(a, band, half, power)
			var q := ring_point(b, band, half, power)
			var r := ring_point(a, band + 1, half, power)
			var s := ring_point(b, band + 1, half, power)
			var tint := Color(COAST_COLORS[band]).lerp(Color(COLORS[band]), _ridge_weight(a))
			var shade := sin(a * 41.0 + band * 2.4) * 0.022
			tint = tint.lightened(shade) if shade > 0 else tint.darkened(-shade)
			# 分开计算三角面法线，保留山石的棱面和起伏。
			var n1 := (r - p).cross(q - p).normalized()
			var n2 := (r - q).cross(s - q).normalized()
			if n1.y < 0:
				n1 = -n1
			if n2.y < 0:
				n2 = -n2
			M.polygon(mountain, [p, r, q], n1, tint)
			M.polygon(mountain, [q, r, s], n2, tint.lightened(0.018))
	_meadow_mesh(meadow,half,power,definition)
	M.mesh_node(root, meadow.commit(), Vector3.ZERO, preload("res://scripts/art/cozy_landscape.gd").ground_material(), "ValleyFloor")
	M.mesh_node(root, mountain.commit(), Vector3.ZERO, M.paint("#ffffff"), "RidgesAndCoastalCliffs")
	_build_sea(root, half)
	return root


static func _build_sea(root: Node3D, half: Vector2) -> void:
	var shape := PlaneMesh.new()
	shape.size = (half + Vector2.ONE * 310.0) * 2.0
	var material := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = """shader_type spatial;
render_mode cull_disabled;
varying vec2 world_xz;
void vertex() { world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz; }
void fragment() {
	float wave = sin(world_xz.x * 0.17 + world_xz.y * 0.24 + TIME * 0.34);
	float glint = pow(max(0.0, sin(world_xz.x * 0.61 - world_xz.y * 0.42 + TIME * 0.48)), 16.0);
	ALBEDO = mix(vec3(0.055, 0.31, 0.40), vec3(0.075, 0.43, 0.49), wave * 0.5 + 0.5) + glint * 0.024;
	ROUGHNESS = 0.52;
	SPECULAR = 0.32;
}
"""
	material.shader = shader
	var ocean := M.mesh_node(root, shape, Vector3(0, -2.0, 0), material, "DistantBlueSea")
	ocean.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# 低矮离岸礁岛延续海岸剪影，南方保留开阔的水天线。
	for i in range(7):
		var angle := 0.16 + float(i) * 0.43
		var at := boundary_point(angle, half, 6, 18.0 + sin(i * 4.3) * 8.0)
		at.y = -2.7
		var rock := crag(310 + i, Vector2(4.0 + i % 3, 3.5 + i % 2), 3.4 + (i % 3) * 1.4)
		rock.position = at
		root.add_child(rock)


static func crag(seed_value: int, radius: Vector2, height: float) -> Node3D:
	var root := Node3D.new()
	root.name = "RockyMountainPeak"
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var levels := [Vector2(1.0, 0.0), Vector2(0.81, 0.24), Vector2(0.58, 0.48), Vector2(0.32, 0.73), Vector2(0.08, 1.0)]
	var ring_count := 13
	var rings: Array = []
	for layer in range(levels.size()):
		var ring: Array[Vector3] = []
		for i in range(ring_count):
			var angle := i * TAU / ring_count
			var ripple := 1.0 + sin(angle * 3.0 + seed_value) * 0.18 + cos(angle * 5.0 - seed_value * 0.8) * 0.10
			var at: Vector3 = Vector3(cos(angle) * radius.x, 0, sin(angle) * radius.y) * levels[layer].x * ripple
			at.x += levels[layer].y * radius.x * sin(seed_value * 1.3) * 0.37
			at.z += levels[layer].y * radius.y * cos(seed_value * 0.9) * 0.30
			at.y = height * levels[layer].y * (0.89 + sin(angle * 4.0 + seed_value + layer * 0.7) * 0.11)
			ring.append(at)
		rings.append(ring)
	for layer in range(levels.size() - 1):
		for i in range(ring_count):
			var j := (i + 1) % ring_count
			var a: Vector3 = rings[layer][i]
			var b: Vector3 = rings[layer][j]
			var c: Vector3 = rings[layer + 1][i]
			var d: Vector3 = rings[layer + 1][j]
			var tint := Color(["#778763", "#8b9583", "#a0a798", "#b2b8a9"][layer])
			if height > 28.0 and layer >= 2:
				tint = Color("#d9e4de") if layer == 3 else tint.lerp(Color("#d3ded7"), 0.36 if i % 3 else 0.78)
			if (i + seed_value) % 4 == 0:
				tint = tint.darkened(0.12)
			var normal := (c - a).cross(b - a).normalized()
			if normal.y < 0:
				normal = -normal
			M.polygon(surface, [a, c, b], normal, tint)
			normal = (c - b).cross(d - b).normalized()
			if normal.y < 0:
				normal = -normal
			M.polygon(surface, [b, c, d], normal, tint.lightened(0.04))
	var summit: Vector3 = rings[-1][0]
	for i in range(1, ring_count - 1):
		M.polygon(surface, [summit, rings[-1][i], rings[-1][i + 1]], Vector3.UP, Color("#e5ece3" if height > 28.0 else "#b9baa2"))
	M.mesh_node(root, surface.commit(), Vector3.ZERO, M.paint("#ffffff"), "MountainFacets")
	return root


static func pine(seed_value: int = 0) -> Node3D:
	return preload("res://scripts/art/tree_models.gd").build("pine", seed_value)


static func _bed_height(at:Vector2,waters:Array) -> float:
	for water:Dictionary in waters:
		var polygon:PackedVector2Array=water["polygon"]
		if Geometry2D.is_point_in_polygon(at,polygon):
			var edge_distance:=100.0
			for i in range(polygon.size()):
				edge_distance=minf(edge_distance,at.distance_to(Geometry2D.get_closest_point_to_segment(at,polygon[i],polygon[(i+1)%polygon.size()])))
			return -.38-minf(edge_distance*.62,.7)
	return 0.0


static func _meadow_mesh(surface:SurfaceTool,half:Vector2,power:int,definition:Dictionary) -> void:
	var step:=1.0
	var heights:Dictionary={}
	for z in range(-int(half.y),int(half.y)+1):
		for x in range(-int(half.x),int(half.x)+1):
			heights[Vector2i(x,z)]=_bed_height(Vector2(x,z),definition["waters"])
	for z in range(-int(half.y),int(half.y)):
		for x in range(-int(half.x),int(half.x)):
			if pow(absf(x+.5)/half.x,power)+pow(absf(z+.5)/half.y,power)>1.: continue
			var corners:Array=[]
			for offset:Vector2i in [Vector2i(0,0),Vector2i(0,1),Vector2i(1,1),Vector2i(1,0)]:
				var key:=Vector2i(x,z)+offset
				corners.append(Vector3(key.x,heights[key],key.y))
			M.polygon(surface,corners,Vector3.UP)
