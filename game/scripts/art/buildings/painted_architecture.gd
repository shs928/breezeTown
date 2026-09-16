extends RefCounted
## 原创笔触贴图与统一 UV 生成；仍使用标准材质，可烘焙、合批与导出。
## 材质按木/灰泥/石/瓦共享，纹理方向沿木构最长轴排列。

const MAPS := {
	"wood": [preload("res://resources/architecture/painted_oak.png"), preload("res://resources/architecture/painted_oak_normal.png")],
	"plaster": [preload("res://resources/architecture/painted_limewash.png"), preload("res://resources/architecture/painted_limewash_normal.png")],
	"stone": [preload("res://resources/architecture/painted_stone.png"), preload("res://resources/architecture/painted_stone_normal.png")],
	"slate": [preload("res://resources/architecture/painted_slate.png"), preload("res://resources/architecture/painted_slate_normal.png")],
}


static func configure(material: StandardMaterial3D, label: String) -> void:
	var name := label.to_lower()
	var kind := ""
	if "oak" in name or "wood" in name or "timber" in name or "shutter" in name or "cedar" in name or "plank" in name or "barn_cream" in name or "barn_sunlit" in name or "gable" in name and "coop" in name:
		kind = "wood"
	elif "plaster" in name or "limewash" in name or "gable" in name:
		kind = "plaster"
	elif "stone" in name or "mortar" in name or "brick" in name:
		kind = "stone"
	elif "slate" in name or "ceramic" in name or "nest_blue" in name:
		kind = "slate"
	if kind.is_empty():
		return
	material.set_meta("painted_kind", kind)
	material.albedo_texture = MAPS[kind][0]
	material.normal_enabled = true
	material.normal_texture = MAPS[kind][1]
	material.normal_scale = 0.44 if kind == "wood" else 0.26
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	material.uv1_scale = Vector3(2.5, 0.66, 1) if kind == "wood" else Vector3(1.4, 1.4, 1)
	# 纹理中的自然暗部保留，轻微补偿平均明度以免全镇统一变暗。
	material.albedo_color = material.albedo_color.lightened(0.035)


static func uv_mesh(mesh: Mesh, material: StandardMaterial3D, at: Vector3) -> Mesh:
	if not material.has_meta("painted_kind"):
		return mesh
	var longest := mesh.get_aabb().size.max_axis_index()
	var offset := Vector2(sin(at.x * 17.1 + at.y * 6.7) * 2.0, cos(at.z * 13.2 + at.y * 8.1) * 2.0)
	var painted := ArrayMesh.new()
	for surface_index in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(surface_index)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var uv := PackedVector2Array()
		uv.resize(vertices.size())
		for index in range(vertices.size()):
			var point := vertices[index]
			var face := normals[index].abs().max_axis_index()
			var coord: Vector2
			match face:
				0: coord = Vector2(point.y, point.z) if longest == 2 else Vector2(point.z, point.y)
				1: coord = Vector2(point.z, point.x) if longest == 0 else Vector2(point.x, point.z)
				_: coord = Vector2(point.y, point.x) if longest == 0 else Vector2(point.x, point.y)
			uv[index] = coord + offset
		arrays[Mesh.ARRAY_TEX_UV] = uv
		painted.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var result := ArrayMesh.new()
	for surface_index in range(painted.get_surface_count()):
		var surface := SurfaceTool.new()
		surface.create_from(painted, surface_index)
		surface.generate_tangents()
		surface.commit(result)
	return result
