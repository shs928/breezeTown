extends RefCounted
## Small, exportable modeling tools. One Godot unit equals one metre.

static var _palette: Dictionary = {}

static func paint(hex: String, roughness: float = 0.91) -> StandardMaterial3D:
	var key := hex + str(roughness)
	if _palette.has(key):
		return _palette[key]
	var result := StandardMaterial3D.new()
	result.resource_name = "Paint_" + hex.trim_prefix("#")
	result.albedo_color = Color(hex)
	result.roughness = roughness
	result.vertex_color_use_as_albedo = true
	result.cull_mode = BaseMaterial3D.CULL_DISABLED
	_palette[key] = result
	return result

static func mesh_node(parent: Node3D, mesh: Mesh, at: Vector3, material: Material, label: String) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = label
	part.mesh = mesh
	part.position = at
	part.material_override = material
	parent.add_child(part)
	return part

static var _shape_cache := {}

static func _shared_shape(key: String, build_shape: Callable) -> Mesh:
	# PERF-01：同参数图元共享网格实例，静态合并时的顶点色转换与数组重建只发生一次。
	if not _shape_cache.has(key):
		_shape_cache[key] = build_shape.call()
	return _shape_cache[key]

static func box(parent: Node3D, at: Vector3, size: Vector3, hex: String, label: String = "Wood", bevel: float = 0.035) -> MeshInstance3D:
	var half := size * 0.5
	var b := minf(bevel, minf(half.x, minf(half.y, half.z)) * 0.7)
	if b < 0.001:
		var shape: Mesh = _shared_shape("box%.3f,%.3f,%.3f" % [size.x, size.y, size.z], func() -> Mesh:
			var fresh := BoxMesh.new()
			fresh.size = size
			return fresh)
		return mesh_node(parent, shape, at, paint(hex), label)
	var core := half - Vector3.ONE * b
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Six faces, twelve bevel strips, eight corner facets.
	for axis in range(3):
		var u := (axis + 1) % 3
		var v := (axis + 2) % 3
		for side in [-1.0, 1.0]:
			var normal := Vector3.ZERO
			normal[axis] = side
			var corners: Array[Vector3] = []
			for uv in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				var p := Vector3.ZERO
				p[axis] = half[axis] * side
				p[u] = core[u] * uv.x
				p[v] = core[v] * uv.y
				corners.append(p)
			polygon(surface, corners, normal)
	for axis in range(3):
		var u := (axis + 1) % 3
		var v := (axis + 2) % 3
		for su in [-1.0, 1.0]:
			for sv in [-1.0, 1.0]:
				var a := Vector3.ZERO
				var c := Vector3.ZERO
				a[u] = half[u] * su
				a[v] = core[v] * sv
				c[u] = core[u] * su
				c[v] = half[v] * sv
				var a0 := a
				var a1 := a
				var c0 := c
				var c1 := c
				a0[axis] = -core[axis]
				a1[axis] = core[axis]
				c0[axis] = -core[axis]
				c1[axis] = core[axis]
				var normal := Vector3.ZERO
				normal[u] = su
				normal[v] = sv
				polygon(surface, [a0, a1, c1, c0], normal.normalized())
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				polygon(surface, [Vector3(half.x * sx, core.y * sy, core.z * sz), Vector3(core.x * sx, half.y * sy, core.z * sz), Vector3(core.x * sx, core.y * sy, half.z * sz)], Vector3(sx, sy, sz).normalized())
	return mesh_node(parent, surface.commit(), at, paint(hex), label)

static func polygon(surface: SurfaceTool, vertices: Array, normal: Vector3, tint: Color = Color.WHITE) -> void:
	for i in range(1, vertices.size() - 1):
		var a: Vector3 = vertices[0]
		var b: Vector3 = vertices[i]
		var c: Vector3 = vertices[i + 1]
		if (b - a).cross(c - a).dot(normal) > 0.0:
			var swap := b
			b = c
			c = swap
		for vertex in [a, b, c]:
			surface.set_normal(normal)
			surface.set_color(tint.srgb_to_linear())
			surface.set_uv(Vector2(vertex.x, vertex.z))
			surface.add_vertex(vertex)

static func ellipsoid(parent: Node3D, at: Vector3, radii: Vector3, hex: String, label: String = "Organic", segments: int = 16, rings: int = 10) -> MeshInstance3D:
	var shape: Mesh = _shared_shape("sph%d,%d" % [segments, rings], func() -> Mesh:
		var fresh := SphereMesh.new()
		fresh.radius = 1.0
		fresh.height = 2.0
		fresh.radial_segments = segments
		fresh.rings = rings
		return fresh)
	var result := mesh_node(parent, shape, at, paint(hex), label)
	result.scale = radii
	return result

static func cylinder(parent: Node3D, at: Vector3, bottom: float, top: float, height: float, hex: String, label: String = "Cylinder", sides: int = 14) -> MeshInstance3D:
	var shape: Mesh = _shared_shape("cyl%.3f,%.3f,%.3f,%d" % [bottom, top, height, sides], func() -> Mesh:
		var fresh := CylinderMesh.new()
		fresh.bottom_radius = bottom
		fresh.top_radius = top
		fresh.height = height
		fresh.radial_segments = sides
		fresh.rings = 1
		return fresh)
	return mesh_node(parent, shape, at, paint(hex), label)

static func beam(parent: Node3D, start: Vector3, finish: Vector3, width: float, hex: String, label: String = "Beam", depth: float = -1.0, round: bool = false) -> MeshInstance3D:
	var delta := finish - start
	var part: MeshInstance3D
	if round:
		part = cylinder(parent, (start + finish) * 0.5, width * 0.5, width * 0.4, delta.length(), hex, label, 10)
	else:
		part = box(parent, (start + finish) * 0.5, Vector3(width, delta.length(), width if depth < 0.0 else depth), hex, label, width * 0.12)
	if delta.length_squared() > 0.0001:
		part.quaternion = Quaternion(Vector3.UP, delta.normalized())
	return part

static func torus(parent: Node3D, at: Vector3, radius: float, tube: float, hex: String, label: String = "Ring") -> MeshInstance3D:
	var shape: Mesh = _shared_shape("tor%.3f,%.3f" % [radius, tube], func() -> Mesh:
		var fresh := TorusMesh.new()
		fresh.inner_radius = radius - tube
		fresh.outer_radius = radius + tube
		fresh.rings = 24
		fresh.ring_segments = 8
		return fresh)
	return mesh_node(parent, shape, at, paint(hex, 0.75), label)

static func leaf(parent: Node3D, start: Vector3, finish: Vector3, width: float, hex: String, label: String = "Leaf") -> MeshInstance3D:
	var direction := finish - start
	var side := direction.cross(Vector3.UP).normalized()
	if side.length_squared() < 0.01:
		side = Vector3.RIGHT
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var previous: Array[Vector3] = []
	for i in range(6):
		var t := float(i) / 5.0
		var center := start.lerp(finish, t) + Vector3.UP * sin(t * PI) * width * 0.28
		var spread := pow(sin(t * PI), 0.85) * width * 0.5
		var ring: Array[Vector3] = [center - side * spread, center + Vector3.UP * spread * 0.32, center + side * spread]
		if not previous.is_empty():
			polygon(surface, [previous[0], ring[0], ring[1], previous[1]], Vector3(-side.x * 0.3, 1, -side.z * 0.3).normalized(), Color(0.90, 0.97, 0.87))
			polygon(surface, [previous[1], ring[1], ring[2], previous[2]], Vector3(side.x * 0.3, 1, side.z * 0.3).normalized())
		previous = ring
	return mesh_node(parent, surface.commit(), Vector3.ZERO, paint(hex), label)

static func blob(parent: Node3D, at: Vector3, radii: Vector3, hex: String, seed_value: float = 0.0, label: String = "Canopy") -> MeshInstance3D:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segments := 16
	var rings := 10
	for row in range(rings):
		for col in range(segments):
			var quad: Array[Vector3] = []
			var normals: Array[Vector3] = []
			for rc in [Vector2(row, col), Vector2(row + 1, col), Vector2(row + 1, col + 1), Vector2(row, col + 1)]:
				var latitude: float = rc.x / float(rings) * PI
				var longitude: float = rc.y / float(segments) * TAU
				var direction := Vector3(sin(latitude) * cos(longitude), cos(latitude), sin(latitude) * sin(longitude))
				var bump := 1.0 + 0.055 * sin(longitude * 5.0 + seed_value) * sin(latitude * 3.0 + seed_value) + 0.033 * cos(longitude * 3.0 - latitude * 5.0)
				quad.append(direction * radii * bump)
				normals.append((direction / radii).normalized())
			for corner in [0, 1, 2, 0, 2, 3]:
				var normal: Vector3 = normals[corner]
				var vertex: Vector3 = quad[corner]
				var pigment := 0.93 + 0.065 * (normal.y * 0.5 + 0.5) + 0.023 * sin(vertex.x * 8.0 + vertex.z * 5.0 + seed_value)
				surface.set_normal(normal)
				surface.set_color(Color(pigment, pigment, pigment * 0.99))
				surface.set_uv(Vector2(col / float(segments), row / float(rings)))
				surface.add_vertex(vertex)
	return mesh_node(parent, surface.commit(), at, paint(hex), label)

static func own_tree(root: Node, node: Node = null) -> void:
	var current: Node = root if node == null else node
	for child in current.get_children():
		child.owner = root
		own_tree(root, child)
