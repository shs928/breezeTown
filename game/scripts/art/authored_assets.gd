extends RefCounted
## Runtime entry for offline GLB assets. Restore glTF vertex colour flags on Godot 4.7.
static func instantiate(path:String) -> Node3D:
	var root:Node3D=(load(path) as PackedScene).instantiate()
	for mesh:MeshInstance3D in root.find_children("*","MeshInstance3D",true,false):
		for surface in range(mesh.mesh.get_surface_count()):
			var arrays:=mesh.mesh.surface_get_arrays(surface)
			var colors:PackedColorArray=arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR]!=null else PackedColorArray()
			if colors.is_empty():continue
			var material:=mesh.get_active_material(surface)
			if material is StandardMaterial3D:
				material.vertex_color_use_as_albedo=true
	root.set_meta("keep_meshes",true)
	return root
