extends SceneTree
## Headless geometry/animation smoke check. Does not launch or alter the game.


func _initialize() -> void:
	call_deferred("_check")


func _check() -> void:
	var script_path: String = get_script().resource_path.get_base_dir().path_join("../scripts/farmer_model.gd").simplify_path()
	var model_script: GDScript = load(script_path)
	if model_script == null:
		push_error("Farmer model failed to load")
		quit(1)
		return
	var report: Array = []
	for variant: int in range(2):
		var model: Node3D = model_script.build(variant)
		root.add_child(model)
		var meshes: Array[Node] = model.find_children("*", "MeshInstance3D", true, false)
		var mesh_count: int = 0
		var triangles: int = 0
		var vertices: int = 0
		var reversed_triangles: int = 0
		var reversed_by_mesh: Dictionary = {}
		var bounds := AABB()
		var first: bool = true
		for child: MeshInstance3D in meshes:
			assert(child.mesh != null, "Missing mesh: " + str(child.get_path()))
			assert(child.material_override is StandardMaterial3D, "Material must export to glTF")
			assert(child.owner == model, "Model must pack with all descendants")
			var transformed: AABB = child.global_transform * child.get_aabb()
			bounds = transformed if first else bounds.merge(transformed)
			first = false
			mesh_count += 1
			for surface: int in range(child.mesh.get_surface_count()):
				var arrays: Array = child.mesh.surface_get_arrays(surface)
				var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
				vertices += positions.size()
				triangles += int(indices.size() / 3)
				for vertex: Vector3 in positions:
					assert(vertex.is_finite(), "Non-finite mesh vertex")
				for index: int in range(0, indices.size(), 3):
					var a: int = indices[index]
					var b: int = indices[index + 1]
					var c: int = indices[index + 2]
					var face_normal: Vector3 = (positions[b] - positions[a]).cross(positions[c] - positions[a])
					var normal: Vector3 = normals[a] + normals[b] + normals[c]
					if face_normal.length_squared() > 0.000000000000001 and face_normal.normalized().dot(normal.normalized()) > 0.1:
						reversed_triangles += 1
						reversed_by_mesh[child.name] = int(reversed_by_mesh.get(child.name, 0)) + 1
		assert(bounds.position.y >= -0.002, "Feet must stand on the origin plane")
		assert(bounds.position.y <= 0.002, "Feet must touch the origin plane")
		assert(bounds.size.y > 1.65 and bounds.size.y < 1.78, "Unexpected character height")
		if reversed_triangles > 0:
			push_error("FARMER_MODEL_WINDING_FAILURE variant=" + str(variant) + " " + JSON.stringify(reversed_by_mesh))
			model.free()
			quit(1)
			return
		assert(reversed_triangles == 0, "Mesh winding must agree with its outward normals")
		for path: String in model_script.JOINT_PATHS:
			assert(model.get_node_or_null(path) is Node3D, "Missing joint: " + path)
		var animation_player: AnimationPlayer = model.get_node("AnimationPlayer")
		for name: String in ["idle", "walk"]:
			assert(animation_player.has_animation(name), "Missing animation: " + name)
			var animation: Animation = animation_player.get_animation(name)
			for track: int in range(animation.get_track_count()):
				assert(model.get_node_or_null(animation.track_get_path(track)) is Node3D, "Invalid animation target")
			animation_player.play(name)
			animation_player.advance(animation.length * 0.25)
			for path: String in model_script.JOINT_PATHS:
				assert((model.get_node(path) as Node3D).global_transform.is_finite(), "Invalid animated transform")
		animation_player.stop()
		var scene := PackedScene.new()
		assert(scene.pack(model) == OK, "Could not pack model for scene reuse")
		report.append({
			"variant": variant, "mesh_instances": mesh_count, "vertices": vertices,
			"triangles": triangles, "reversed_triangle_normals": reversed_triangles,
			"reversed_by_mesh": reversed_by_mesh,
			"bounds_min": [bounds.position.x, bounds.position.y, bounds.position.z],
			"bounds_max": [bounds.end.x, bounds.end.y, bounds.end.z],
			"dimensions_metres": [bounds.size.x, bounds.size.y, bounds.size.z],
			"animations": ["idle", "walk"], "joints": model_script.JOINT_PATHS,
		})
		model.free()
	print("FARMER_MODEL_CHECK_OK " + JSON.stringify(report))
	var output_path: String = get_script().resource_path.get_base_dir().path_join("validation.json")
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
	quit(0)
