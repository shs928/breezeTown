extends RefCounted
## 按空间格与材质合并静态道具，扩大城镇后仍能按区域裁剪网格。
## 动物、作物、角色和文字不参与合并。

const CHUNK_SIZE := 24.0


static func bake(root: Node3D) -> void:
	var batches := {}
	_collect(root, root.transform.affine_inverse(), batches, {})
	var batch_root := Node3D.new()
	batch_root.name = "StaticGeometry"
	root.add_child(batch_root)
	for key: String in batches:
		var batch: Dictionary = batches[key]
		var mesh := MeshInstance3D.new()
		mesh.name = "Batch_" + key.replace(":", "_")
		mesh.mesh = (batch["surface"] as SurfaceTool).commit()
		mesh.material_override = batch["material"]
		mesh.position = batch["origin"]
		batch_root.add_child(mesh)
	root.set_meta("static_batches", batches.size())


static func _collect(node: Node3D, parent_transform: Transform3D, batches: Dictionary, source_meshes: Dictionary) -> void:
	if node.get_meta("keep_meshes", false):
		return
	var transform := parent_transform * node.transform
	for child in node.get_children():
		if child is Node3D:
			_collect(child, transform, batches, source_meshes)
	if not node is MeshInstance3D:
		return
	var instance := node as MeshInstance3D
	if instance.mesh == null:
		return
	var chunk := Vector2i(floori(transform.origin.x / CHUNK_SIZE), floori(transform.origin.z / CHUNK_SIZE))
	var origin := Vector3(chunk.x * CHUNK_SIZE, 0, chunk.y * CHUNK_SIZE)
	var local := transform
	local.origin -= origin
	for index in range(instance.mesh.get_surface_count()):
		var material := instance.get_active_material(index)
		var key := "%d:%d:%d" % [chunk.x, chunk.y, material.get_instance_id() if material else 0]
		if not batches.has(key):
			var surface := SurfaceTool.new()
			surface.begin(Mesh.PRIMITIVE_TRIANGLES)
			batches[key] = {"surface": surface, "material": material, "origin": origin}
		(batches[key]["surface"] as SurfaceTool).append_from(_with_vertex_colors(instance.mesh, source_meshes), index, local)
	instance.free()


static func _with_vertex_colors(mesh: Mesh, cache: Dictionary) -> Mesh:
	var key := mesh.get_instance_id()
	if cache.has(key):
		return cache[key]
	# PrimitiveMesh 没有顶点色。与有顶点色的手工网格合并时须补白色，
	# 否则 SurfaceTool 的缺省黑色会把奶牛身体、玻璃等整块染黑。
	var result := ArrayMesh.new()
	for index in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(index)
		if arrays[Mesh.ARRAY_COLOR] == null or arrays[Mesh.ARRAY_COLOR].is_empty():
			var colors := PackedColorArray()
			colors.resize(arrays[Mesh.ARRAY_VERTEX].size())
			colors.fill(Color.WHITE)
			arrays[Mesh.ARRAY_COLOR] = colors
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	cache[key] = result
	return result
