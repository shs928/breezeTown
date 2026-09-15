extends SceneTree

const Compat = preload("res://scripts/gltf_color_compat.gd")
var failures: Array[String] = []
var report: Array = []
var finished := false


func _initialize() -> void:
	create_timer(45.0).timeout.connect(_timeout)
	call_deferred("_run")


func _run() -> void:
	for filename: String in ["breeze_town_farm.glb", "farmer_indigo.glb", "farmer_moss.glb"]:
		var source: String = "res://models/" + filename
		var scratch: String = "res://validation/diag_compat_test_" + filename
		var source_hash: String = FileAccess.get_sha256(source)
		var writer := FileAccess.open(scratch, FileAccess.WRITE)
		if writer == null:
			failures.append("Cannot create diagnostic copy: " + filename)
			continue
		writer.store_buffer(FileAccess.get_file_as_bytes(source))
		writer.close()
		var before: Dictionary = _inspect(scratch)
		var patch: Dictionary = Compat.patch_file(scratch)
		var after: Dictionary = _inspect(scratch) if patch.ok else {}
		var patched_hash: String = FileAccess.get_sha256(scratch)
		var repeat: Dictionary = Compat.patch_file(scratch)
		_check(patch.ok, "Patch succeeded: " + filename + " " + str(patch.get("error", "")))
		_check(patch.get("binary_unchanged", false), "Binary chunks preserved: " + filename)
		_check(patch.get("triangles_preserved", false), "Index triplets preserved: " + filename)
		_check(before.get("triangles", -1) == after.get("triangles", -2), "Imported triangle count unchanged: " + filename)
		_check(after.get("nonwhite_disabled_surfaces", -1) == 0, "Nonwhite imported vertex colors enabled: " + filename)
		_check(repeat.ok and repeat.patched_meshes == 0 and not repeat.changed, "Second patch is a no-op: " + filename)
		_check(FileAccess.get_sha256(scratch) == patched_hash, "Idempotent patch does not rewrite bytes: " + filename)
		_check(FileAccess.get_sha256(source) == source_hash, "Delivery GLB was not modified: " + filename)
		report.append({"file": filename, "before": before, "after": after, "patch": patch, "repeat": repeat, "source_sha256": source_hash, "patched_sha256": patched_hash})
		print("COLOR_COMPAT_CASE ", filename, " patched_meshes=", patch.patched_meshes, " triangles=", after.get("triangles", -1), " nonwhite_disabled=", after.get("nonwhite_disabled_surfaces", -1), " repeat_changed=", repeat.changed)
		var cleanup: Error = DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch))
		_check(cleanup == OK, "Diagnostic copy removed: " + filename)
	# Exercise a clear failure path without touching an existing asset.
	var invalid_path := "res://validation/diag_compat_invalid.glb"
	var invalid := FileAccess.open(invalid_path, FileAccess.WRITE)
	invalid.store_string("not a GLB")
	invalid.close()
	var invalid_hash: String = FileAccess.get_sha256(invalid_path)
	var invalid_result: Dictionary = Compat.patch_file(invalid_path)
	_check(not invalid_result.ok and invalid_result.has("error"), "Malformed GLB returns an explicit error")
	_check(FileAccess.get_sha256(invalid_path) == invalid_hash, "Malformed source remains unchanged")
	_check(DirAccess.remove_absolute(ProjectSettings.globalize_path(invalid_path)) == OK, "Malformed diagnostic copy removed")
	_finish()


func _inspect(path: String) -> Dictionary:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var error: Error = document.append_from_file(path, state)
	if error != OK:
		failures.append("Cannot reimport diagnostic GLB: " + path)
		return {}
	var scene: Node = document.generate_scene(state)
	if scene == null:
		failures.append("Cannot generate imported diagnostic scene: " + path)
		return {}
	var triangles: int = 0
	var nonwhite_surfaces: int = 0
	var disabled: int = 0
	for mesh: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		for surface: int in range(mesh.mesh.get_surface_count()):
			var arrays: Array = mesh.mesh.surface_get_arrays(surface)
			var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			triangles += int((indices.size() if not indices.is_empty() else positions.size()) / 3)
			var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
			var nonwhite: bool = false
			for color: Color in colors:
				if not color.is_equal_approx(Color.WHITE):
					nonwhite = true
					break
			if nonwhite:
				nonwhite_surfaces += 1
				var material: Material = mesh.get_active_material(surface)
				if not material is StandardMaterial3D or not material.vertex_color_use_as_albedo:
					disabled += 1
	scene.free()
	return {"triangles": triangles, "nonwhite_color_surfaces": nonwhite_surfaces, "nonwhite_disabled_surfaces": disabled}


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		printerr("COLOR_COMPAT_FAILURE ", message)


func _timeout() -> void:
	if not finished:
		failures.append("Diagnostic timed out or was interrupted by a script error")
		_finish()


func _finish() -> void:
	if finished:
		return
	finished = true
	var output := FileAccess.open("res://validation/diag_color_compat_result.json", FileAccess.WRITE)
	if output == null:
		failures.append("Cannot write diagnostic result JSON")
	else:
		output.store_string(JSON.stringify({"ok": failures.is_empty(), "failures": failures, "cases": report}, "\t"))
		output.close()
	print("COLOR_COMPAT_" + ("OK" if failures.is_empty() else "FAILED") + " cases=" + str(report.size()) + " failures=" + str(failures.size()))
	quit(0 if failures.is_empty() else 1)
