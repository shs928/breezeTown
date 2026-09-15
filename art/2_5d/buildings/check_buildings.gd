extends SceneTree

const Buildings = preload("../scripts/building_models.gd")

var _errors := 0


func _initialize() -> void:
	var entries := {"cottage": Buildings.cottage(), "shop": Buildings.shop()}
	var report := {}
	for label: String in entries:
		var model: Node3D = entries[label]
		root.add_child(model)
		var meshes: Array[MeshInstance3D] = []
		_collect_meshes(model, meshes)
		var bounds := AABB()
		var first := true
		var triangles := 0
		for part in meshes:
			if part.mesh == null or part.material_override is not StandardMaterial3D:
				_errors += 1
				printerr("INVALID_BUILDING_MESH " + str(part.get_path()))
				continue
			var part_bounds: AABB = _model_transform(part) * part.mesh.get_aabb()
			bounds = part_bounds if first else bounds.merge(part_bounds)
			first = false
			for surface in part.mesh.get_surface_count():
				var data := part.mesh.surface_get_arrays(surface)
				var points: PackedVector3Array = data[Mesh.ARRAY_VERTEX]
				if data[Mesh.ARRAY_INDEX] != null and data[Mesh.ARRAY_INDEX].size() > 0:
					triangles += data[Mesh.ARRAY_INDEX].size() / 3
				else:
					triangles += points.size() / 3
				for point in points:
					if not point.is_finite():
						_errors += 1
						printerr("NONFINITE_VERTEX " + str(part.get_path()))
		report[label] = {
			"mesh_instances": meshes.size(), "triangles": triangles,
			"minimum": [bounds.position.x, bounds.position.y, bounds.position.z],
			"maximum": [bounds.end.x, bounds.end.y, bounds.end.z],
			"size": [bounds.size.x, bounds.size.y, bounds.size.z],
		}
		print("BUILDING_MODEL " + label + " " + JSON.stringify(report[label]))
		model.free()
	var output := FileAccess.open("res://buildings/model-dimensions.json", FileAccess.WRITE)
	if output != null:
		output.store_string(JSON.stringify(report, "  "))
		output.close()
	else:
		_errors += 1
	print("BUILDINGS_OK" if _errors == 0 else "BUILDINGS_FAILED")
	quit(0 if _errors == 0 else 1)


func _collect_meshes(node: Node, output: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		output.append(node)
	for child in node.get_children():
		_collect_meshes(child, output)


func _model_transform(node: Node3D) -> Transform3D:
	var transform := node.transform
	var ancestor := node.get_parent()
	while ancestor is Node3D:
		transform = ancestor.transform * transform
		ancestor = ancestor.get_parent()
	return transform
