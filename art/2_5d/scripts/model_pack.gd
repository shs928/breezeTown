extends RefCounted
## Native glTF 2.0 export plus a real import round trip.

const M = preload("res://scripts/art_mesh.gd")
const L = preload("res://scripts/landscape_models.gd")
const B = preload("res://scripts/building_models.gd")
const F = preload("res://scripts/farmer_model.gd")
const S = preload("res://scripts/scene_builder.gd")
const ColorCompat = preload("res://scripts/gltf_color_compat.gd")

static func compact_scenery(root: Node3D) -> void:
	# Preserve animated joint hierarchies. Only static scenery is consolidated.
	for child in root.get_children():
		if not child is Node3D or child is MeshInstance3D:
			continue
		if child.find_child("AnimationPlayer", true, false) != null:
			continue
		var groups: Dictionary = {}
		_gather_meshes(child, Transform3D.IDENTITY, groups, true)
		if groups.is_empty():
			continue
		var merged := ArrayMesh.new()
		for group in groups.values():
			var surface: SurfaceTool = group.surface
			surface.index()
			surface.commit(merged)
			merged.surface_set_material(merged.get_surface_count() - 1, group.material)
		for part in child.get_children():
			part.free()
		var combined := MeshInstance3D.new()
		combined.name = "ModeledSurfaces"
		combined.mesh = merged
		child.add_child(combined)

static func _gather_meshes(node: Node, inherited: Transform3D, groups: Dictionary, root: bool = false) -> void:
	var transform := inherited
	if node is Node3D and not root:
		transform *= node.transform
	if node is MeshInstance3D and node.mesh != null:
		var instance: MeshInstance3D = node
		for surface_index in range(instance.mesh.get_surface_count()):
			var material: Material = instance.get_active_material(surface_index)
			var key: int = material.get_instance_id() if material != null else 0
			if not groups.has(key):
				var surface := SurfaceTool.new()
				surface.begin(Mesh.PRIMITIVE_TRIANGLES)
				groups[key] = {"surface": surface, "material": material, "vertices": 0}
			var writer: SurfaceTool = groups[key].surface
			var arrays: Array = instance.mesh.surface_get_arrays(surface_index)
			var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
			var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
			var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var base: int = groups[key].vertices
			var normal_basis := transform.basis.inverse().transposed()
			# append_from uses the position basis on normals and cannot safely mix
			# meshes with/without vertex colours. Explicit attributes preserve both.
			for i in range(positions.size()):
				writer.set_normal((normal_basis * normals[i]).normalized() if i < normals.size() else Vector3.UP)
				writer.set_color(colors[i] if i < colors.size() else Color.WHITE)
				writer.set_uv(uvs[i] if i < uvs.size() else Vector2.ZERO)
				writer.add_vertex(transform * positions[i])
			if indices.is_empty():
				for i in range(positions.size()):
					writer.add_index(base + i)
			else:
				for i in indices:
					writer.add_index(base + i)
			groups[key].vertices += positions.size()
	for child in node.get_children():
		_gather_meshes(child, transform, groups)

static func export_all(output_dir: String) -> Dictionary:
	DirAccess.make_dir_recursive_absolute(output_dir)
	var manifest := {"format": "glTF 2.0 / GLB", "units": "metres", "up": "+Y", "front": "+Z", "generated_by": "Godot 4.7.2, original parametric modeling scripts", "models": [], "ok": true}
	var models := {
		"farmer_indigo": F.build(0),
		"farmer_moss": F.build(1),
		"willow_cottage": B.cottage(),
		"seed_market": B.shop(),
		"meadow_oak": L.tree(1),
		"apple_tree": L.tree(4, true),
		"garden_fence": L.fence(),
		"garden_well": L.well(),
		"footbridge": L.footbridge(),
		"watering_can": L.watering_can(),
		"harvest_crate": L.crate(true),
		"wooden_barrel": L.barrel(),
		"duck_pond": L.pond(),
		"plot_radish": L.crop_bed("radish"),
		"plot_strawberry": L.crop_bed("strawberry"),
		"plot_wheat": L.crop_bed("wheat"),
		"plot_pumpkin": L.crop_bed("pumpkin"),
		"breeze_town_farm": S.farm(),
	}
	for slug in models:
		var model: Node3D = models[slug]
		if slug == "breeze_town_farm":
			compact_scenery(model)
		M.own_tree(model)
		var result := export_model(model, output_dir.path_join(slug + ".glb"))
		result["name"] = slug
		manifest.models.append(result)
		if not result.ok:
			manifest.ok = false
		model.free()
	var file := FileAccess.open(output_dir.path_join("manifest.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(manifest, "\t"))
	print("ART_EXPORT_RESULT ", JSON.stringify({"ok": manifest.ok, "count": manifest.models.size()}))
	return manifest

static func export_model(root: Node3D, path: String) -> Dictionary:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var append_error := document.append_from_scene(root, state)
	var write_error := document.write_to_filesystem(state, path) if append_error == OK else append_error
	var result := {"file": path.get_file(), "ok": false, "export_error": write_error, "source": inspect(root)}
	if write_error != OK:
		push_error("Cannot export " + path + ": " + error_string(write_error))
		return result
	var color_compatibility: Dictionary = ColorCompat.patch_file(path)
	result["vertex_color_compatibility"] = color_compatibility
	if not color_compatibility.ok:
		push_error("Cannot prepare vertex colours for " + path + ": " + str(color_compatibility))
		return result
	result["sha256"] = FileAccess.get_sha256(path)
	var imported_state := GLTFState.new()
	var imported_doc := GLTFDocument.new()
	var import_error := imported_doc.append_from_file(path, imported_state)
	result["import_error"] = import_error
	if import_error == OK:
		var imported_root := imported_doc.generate_scene(imported_state)
		if imported_root != null:
			result["imported"] = inspect(imported_root)
			result["bytes"] = FileAccess.get_file_as_bytes(path).size()
			result.ok = result.imported.meshes > 0 and result.imported.triangles == result.source.triangles and result.imported.finite and result.source.finite and result.imported.disabled_vertex_colors == 0
			if result.source.animations > 0:
				result.ok = result.ok and result.imported.animations >= result.source.animations
			imported_root.free()
	print("ART_MODEL ", path.get_file(), " ", "OK" if result.ok else "FAILED", " ", result.source.triangles, " triangles")
	return result

static func inspect(root: Node) -> Dictionary:
	var stats := {"meshes": 0, "triangles": 0, "vertices": 0, "animations": 0, "finite": true, "colored_surfaces": 0, "disabled_vertex_colors": 0}
	_inspect_node(root, stats)
	return stats

static func _inspect_node(node: Node, stats: Dictionary) -> void:
	if node is Node3D and not node.transform.is_finite():
		stats.finite = false
	if node is AnimationPlayer:
		stats.animations += node.get_animation_list().size()
	if node is MeshInstance3D and node.mesh != null:
		stats.meshes += 1
		for surface_index in range(node.mesh.get_surface_count()):
			var arrays: Array = node.mesh.surface_get_arrays(surface_index)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			stats.vertices += vertices.size()
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			stats.triangles += (vertices.size() if indices.is_empty() else indices.size()) / 3
			var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
			var contains_pigment := false
			for pigment in colors:
				if not pigment.is_equal_approx(Color.WHITE):
					contains_pigment = true
					break
			if contains_pigment:
				stats.colored_surfaces += 1
				var material: Material = node.get_active_material(surface_index)
				if not material is BaseMaterial3D or not material.vertex_color_use_as_albedo:
					stats.disabled_vertex_colors += 1
			for vertex in vertices:
				if not vertex.is_finite():
					stats.finite = false
	for child in node.get_children():
		_inspect_node(child, stats)
