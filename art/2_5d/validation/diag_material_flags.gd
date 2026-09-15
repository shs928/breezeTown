extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var report: Array = []
	for path: String in ["res://models/breeze_town_farm.glb", "res://validation/diag_material_shift.glb", "res://validation/diag_material_primitive_prefix.glb", "res://validation/diag_material_triangle_split.glb", "res://models/farmer_indigo.glb", "res://models/farmer_moss.glb"]:
		var document := GLTFDocument.new()
		var state := GLTFState.new()
		var error: Error = document.append_from_file(path, state)
		if error != OK:
			printerr("DIAGNOSTIC_IMPORT_FAILED ", path, " ", error)
			quit(1)
			return
		var materials: Array = state.get_materials()
		var material_flags: Array = []
		for index: int in range(materials.size()):
			var material: Material = materials[index]
			if material is StandardMaterial3D:
				material_flags.append({"index": index, "name": material.resource_name, "vertex_color_use_as_albedo": material.vertex_color_use_as_albedo})
		var scene: Node = document.generate_scene(state)
		if scene == null:
			quit(1)
			return
		var sampled: Array = []
		var triangle_count: int = 0
		var disabled_colored_surfaces: int = 0
		for node: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
			for surface: int in range(node.mesh.get_surface_count()):
				var material: Material = node.get_active_material(surface)
				if material == null or not material is StandardMaterial3D:
					continue
				var arrays: Array = node.mesh.surface_get_arrays(surface)
				var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
				triangle_count += int((indices.size() if not indices.is_empty() else positions.size()) / 3)
				var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
				if not colors.is_empty() and not material.vertex_color_use_as_albedo:
					disabled_colored_surfaces += 1
				if not colors.is_empty() and (not material.vertex_color_use_as_albedo or material.resource_name == "Paint_ffffff"):
					sampled.append({"mesh": node.name, "parent": node.get_parent().name, "material": material.resource_name, "vertex_flag": material.vertex_color_use_as_albedo, "color_count": colors.size(), "first_color": [colors[0].r, colors[0].g, colors[0].b, colors[0].a]})
		var result: Dictionary = {"file": path, "triangles": triangle_count, "disabled_colored_surfaces": disabled_colored_surfaces, "materials": material_flags, "colored_surfaces_with_disabled_flag_or_white_material": sampled}
		report.append(result)
		print("DIAGNOSTIC_MATERIAL_FLAGS ", path, " triangles=", triangle_count, " disabled_colored_surfaces=", disabled_colored_surfaces, " first_materials=", JSON.stringify(material_flags.slice(0, 4)))
		scene.free()
	var file := FileAccess.open("res://validation/diag_material_flags.json", FileAccess.WRITE)
	if file == null:
		quit(1)
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("DIAGNOSTIC_MATERIAL_FLAGS_OK")
	quit(0)
