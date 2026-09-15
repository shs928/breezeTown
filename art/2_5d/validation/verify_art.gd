extends SceneTree
## Read-only regression and delivery checks. Only this directory receives output.
## Run with --headless --path art/2_5d --script res://validation/verify_art.gd
## and --log-file <absolute-path>/art/2_5d/validation/verify_art.log.

var _checks := 0
var _failure_count := 0
var _failures: Array[String] = []
var _finished := false
var _started_ms := Time.get_ticks_msec()
var _report: Dictionary = {}


func _initialize() -> void:
	# A runtime script error must not leave an idle headless process behind.
	create_timer(45.0).timeout.connect(_deadline)
	call_deferred("_run")


func _run() -> void:
	_report["manifest"] = _verify_manifest()
	var pack: GDScript = load("res://scripts/model_pack.gd")
	if _expect(pack != null, "model_pack.gd must load"):
		_report["compaction"] = _verify_compaction(pack)
	var animations: Array = []
	for filename: String in ["farmer_indigo.glb", "farmer_moss.glb"]:
		animations.append(await _verify_animations(filename))
	_report["animation_round_trips"] = animations
	_finish()


func _expect(condition: bool, message: String) -> bool:
	_checks += 1
	if not condition:
		_failure_count += 1
		if _failures.size() < 30:
			_failures.append(message)
			printerr("ART_VERIFY_FAILURE " + message)
	return condition


func _deadline() -> void:
	if _finished:
		return
	_expect(false, "Verification exceeded 45 seconds or a script error interrupted it")
	_finish()


func _finish() -> void:
	if _finished:
		return
	_finished = true
	_report["ok"] = _failure_count == 0
	_report["checks"] = _checks
	_report["failure_count"] = _failure_count
	_report["failures"] = _failures
	_report["elapsed_ms"] = Time.get_ticks_msec() - _started_ms
	_report["engine"] = Engine.get_version_info().string
	_report["verified_utc"] = Time.get_datetime_string_from_system(true)
	_report["scope"] = "Existing GLBs and manifest; in-memory merge regression; no rendering or exports"
	var output := FileAccess.open("res://validation/verification.json", FileAccess.WRITE)
	if output == null:
		_expect(false, "Cannot write validation/verification.json")
	else:
		output.store_string(JSON.stringify(_report, "\t"))
		output.close()
	print("ART_VERIFY_" + ("OK" if _failure_count == 0 else "FAILED") + " checks=" + str(_checks) + " failures=" + str(_failure_count) + " elapsed_ms=" + str(Time.get_ticks_msec() - _started_ms))
	quit(0 if _failure_count == 0 else 1)


func _verify_manifest() -> Dictionary:
	var result: Dictionary = {"files": [], "expected_count": 18}
	var path := "res://models/manifest.json"
	if not _expect(FileAccess.file_exists(path), "Export manifest exists"):
		return result
	var parser := JSON.new()
	if not _expect(parser.parse(FileAccess.get_file_as_string(path)) == OK, "Export manifest is valid JSON"):
		return result
	if not _expect(parser.data is Dictionary, "Export manifest has an object root"):
		return result
	var manifest: Dictionary = parser.data
	_expect(manifest.get("ok", false) == true, "Manifest reports overall success")
	var entries: Array = manifest.get("models", [])
	_expect(entries.size() == 18, "Manifest contains exactly 18 models")
	var seen: Dictionary = {}
	for value: Variant in entries:
		if not _expect(value is Dictionary, "Every model manifest entry is an object"):
			continue
		var entry: Dictionary = value
		var filename: String = str(entry.get("file", ""))
		if not _expect(filename.get_file() == filename and filename.ends_with(".glb"), "Manifest filename is a local GLB: " + filename):
			continue
		_expect(not seen.has(filename), "Manifest filename is unique: " + filename)
		seen[filename] = true
		_expect(entry.get("ok", false) == true, "Manifest entry succeeded: " + filename)
		var model_path: String = "res://models/" + filename
		if not _expect(FileAccess.file_exists(model_path), "Model file exists: " + filename):
			continue
		var file := FileAccess.open(model_path, FileAccess.READ)
		if not _expect(file != null, "Model file can be read: " + filename):
			continue
		var byte_count: int = file.get_length()
		_expect(byte_count >= 20, "GLB has a nonempty header and chunks: " + filename)
		_expect(byte_count == int(entry.get("bytes", -1)), "GLB length matches manifest: " + filename)
		_expect(str(entry.get("sha256", "")) == FileAccess.get_sha256(model_path), "GLB SHA-256 matches manifest: " + filename)
		_expect(file.get_32() == 0x46546c67, "GLB magic matches: " + filename)
		_expect(file.get_32() == 2, "GLB version is 2: " + filename)
		_expect(file.get_32() == byte_count, "GLB header length matches file: " + filename)
		file.close()
		result.files.append({"file": filename, "bytes": byte_count, "manifest_ok": entry.get("ok", false), "sha256": FileAccess.get_sha256(model_path)})
	result["actual_count"] = entries.size()
	result["manifest_sha256"] = FileAccess.get_sha256(path)
	return result


func _verify_compaction(pack: GDScript) -> Dictionary:
	var fixture := Node3D.new()
	fixture.name = "CompactionFixture"
	root.add_child(fixture)
	var prop := Node3D.new()
	prop.name = "SharedMaterialProp"
	prop.position = Vector3(3.0, -1.0, 2.0)
	prop.rotation = Vector3(0.16, -0.23, 0.09)
	fixture.add_child(prop)
	var shared_material := StandardMaterial3D.new()
	shared_material.vertex_color_use_as_albedo = true
	shared_material.albedo_color = Color.WHITE
	var box_source := BoxMesh.new()
	box_source.size = Vector3(0.8, 1.0, 0.6)
	var box_arrays: Array = box_source.surface_get_arrays(0)
	var box_positions: PackedVector3Array = box_arrays[Mesh.ARRAY_VERTEX]
	var box_colors := PackedColorArray()
	for i: int in range(box_positions.size()):
		box_colors.append(Color(0.20 + 0.07 * (i % 3), 0.46 + 0.04 * (i % 4), 0.12 + 0.05 * (i % 2), 1.0))
	box_arrays[Mesh.ARRAY_COLOR] = box_colors
	var colored_box := ArrayMesh.new()
	colored_box.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, box_arrays)
	var box := MeshInstance3D.new()
	box.name = "ColoredArrayMeshBox"
	box.mesh = colored_box
	box.material_override = shared_material
	box.position = Vector3(-2.6, 0.35, 0.1)
	box.rotation = Vector3(0.12, 0.22, -0.09)
	prop.add_child(box)
	var nested := Node3D.new()
	nested.name = "NestedTransform"
	nested.position = Vector3(2.7, 0.55, -0.2)
	nested.rotation = Vector3(0.08, -0.29, 0.11)
	nested.scale = Vector3(1.2, 0.88, 1.1)
	prop.add_child(nested)
	var sphere_source := SphereMesh.new()
	sphere_source.radius = 0.5
	sphere_source.height = 1.0
	sphere_source.radial_segments = 16
	sphere_source.rings = 8
	var sphere_arrays: Array = sphere_source.surface_get_arrays(0)
	_expect(sphere_arrays[Mesh.ARRAY_COLOR] == null, "Regression sphere intentionally has no vertex colors")
	var sphere := MeshInstance3D.new()
	sphere.name = "UncoloredScaledSphere"
	sphere.mesh = sphere_source
	sphere.material_override = shared_material
	sphere.rotation = Vector3(0.31, 0.47, -0.18)
	sphere.scale = Vector3(2.3, 0.45, 1.25)
	nested.add_child(sphere)
	var before_triangles: int = _triangle_count(box.mesh) + _triangle_count(sphere.mesh)
	var expected: Dictionary = {}
	var source_vertex_count: int = 0
	var naive_error_deg: float = 0.0
	# Source meshes are spatially separated. Matching by position tolerates vertex
	# reordering/deduplication while face normals distinguish box corner vertices.
	for instance: MeshInstance3D in [box, sphere]:
		var arrays: Array = instance.mesh.surface_get_arrays(0)
		var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
		var transform: Transform3D = prop.global_transform.affine_inverse() * instance.global_transform
		var normal_matrix: Basis = transform.basis.inverse().transposed()
		for i: int in range(positions.size()):
			var position: Vector3 = transform * positions[i]
			var normal: Vector3 = (normal_matrix * normals[i]).normalized()
			var reference: Vector3 = Vector3.RIGHT if absf(normals[i].dot(Vector3.UP)) > 0.9 else Vector3.UP
			var tangent: Vector3 = normals[i].cross(reference).normalized()
			var sphere_vertex: bool = instance == sphere
			var point: Dictionary = {
				"position": position, "normal": normal,
				"color": colors[i] if i < colors.size() else Color.WHITE,
				"sphere": sphere_vertex,
				"tangent_u": (transform.basis * tangent).normalized(),
				"tangent_v": (transform.basis * normals[i].cross(tangent)).normalized(),
			}
			var key: String = _position_key(position)
			if not expected.has(key):
				expected[key] = []
			expected[key].append(point)
			source_vertex_count += 1
			if sphere_vertex:
				var wrong_normal: Vector3 = (transform.basis * normals[i]).normalized()
				naive_error_deg = maxf(naive_error_deg, rad_to_deg(acos(clampf(normal.dot(wrong_normal), -1.0, 1.0))))
	_expect(naive_error_deg > 15.0, "Regression fixture distinguishes the wrong position-basis normal transform")
	var original_prop_transform: Transform3D = prop.transform
	pack.compact_scenery(fixture)
	_expect(prop.transform.is_equal_approx(original_prop_transform), "Compaction preserves the static prop transform")
	var combined: MeshInstance3D = prop.get_node_or_null("ModeledSurfaces") as MeshInstance3D
	if not _expect(combined != null and combined.mesh != null, "Compaction creates one merged mesh"):
		fixture.free()
		return {}
	_expect(prop.get_child_count() == 1, "Compaction replaces the source mesh hierarchy")
	_expect(combined.mesh.get_surface_count() == 1, "The common material is merged into one surface")
	_expect(combined.get_active_material(0) == shared_material, "Compaction preserves the material")
	var after_triangles: int = _triangle_count(combined.mesh)
	_expect(before_triangles == after_triangles, "Compaction preserves the triangle count")
	var merged_arrays: Array = combined.mesh.surface_get_arrays(0)
	var merged_positions: PackedVector3Array = merged_arrays[Mesh.ARRAY_VERTEX]
	var merged_normals: PackedVector3Array = merged_arrays[Mesh.ARRAY_NORMAL]
	var merged_colors: PackedColorArray = merged_arrays[Mesh.ARRAY_COLOR] if merged_arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
	_expect(merged_normals.size() == merged_positions.size(), "Every merged vertex has a normal")
	_expect(merged_colors.size() == merged_positions.size(), "Every merged vertex has an explicit color")
	var minimum_normal_dot: float = 1.0
	var maximum_tangent_dot: float = 0.0
	var maximum_normal_length_error: float = 0.0
	var maximum_position_error: float = 0.0
	var sphere_checked: int = 0
	var box_checked: int = 0
	for i: int in range(merged_positions.size()):
		var key: String = _position_key(merged_positions[i])
		var candidates: Array = expected.get(key, [])
		if candidates.is_empty():
			# Computing a reference from global transforms introduces sub-micron
			# rounding. Search adjacent position bins instead of treating a value
			# crossing a quantization boundary as a changed vertex.
			for group: Array in expected.values():
				for candidate: Dictionary in group:
					if merged_positions[i].distance_to(candidate.position) < 0.00002:
						candidates.append(candidate)
		if not _expect(not candidates.is_empty(), "Merged vertex remains at the transformed source position: " + str(i)):
			continue
		if i >= merged_normals.size() or i >= merged_colors.size():
			continue
		var match_point: Dictionary = candidates[0]
		for candidate: Dictionary in candidates:
			if merged_normals[i].dot(candidate.normal) > merged_normals[i].dot(match_point.normal):
				match_point = candidate
		var actual_normal: Vector3 = merged_normals[i]
		maximum_position_error = maxf(maximum_position_error, merged_positions[i].distance_to(match_point.position))
		_expect(actual_normal.is_finite(), "Merged normal is finite: " + str(i))
		_expect(merged_colors[i].is_equal_approx(match_point.color), "Merged color preserves explicit color or defaults to white: " + str(i))
		if match_point.sphere:
			sphere_checked += 1
			_expect(merged_colors[i].is_equal_approx(Color.WHITE), "Uncolored sphere does not inherit the preceding box color: " + str(i))
			minimum_normal_dot = minf(minimum_normal_dot, actual_normal.dot(match_point.normal))
			maximum_tangent_dot = maxf(maximum_tangent_dot, maxf(absf(actual_normal.dot(match_point.tangent_u)), absf(actual_normal.dot(match_point.tangent_v))))
			maximum_normal_length_error = maxf(maximum_normal_length_error, absf(actual_normal.length() - 1.0))
		else:
			box_checked += 1
	_expect(sphere_checked > 100, "Scaled sphere vertices were actually checked")
	_expect(box_checked >= 24, "Colored box face vertices were actually checked")
	_expect(maximum_position_error < 0.00002, "Compaction preserves transformed positions within floating-point precision")
	_expect(minimum_normal_dot > 0.9999, "Scaled sphere normals agree with the inverse transpose")
	_expect(maximum_tangent_dot < 0.002, "Scaled sphere normals remain perpendicular to both transformed tangent directions")
	_expect(maximum_normal_length_error < 0.0002, "Scaled sphere normals remain unit length")
	var result: Dictionary = {
		"triangles_before": before_triangles, "triangles_after": after_triangles,
		"source_vertices": source_vertex_count, "merged_vertices": merged_positions.size(),
		"surfaces_after": combined.mesh.get_surface_count(), "colored_box_vertices_checked": box_checked,
		"white_sphere_vertices_checked": sphere_checked,
		"minimum_inverse_transpose_normal_dot": minimum_normal_dot,
		"maximum_transformed_tangent_dot": maximum_tangent_dot,
		"maximum_normal_length_error": maximum_normal_length_error,
		"maximum_position_error_metres": maximum_position_error,
		"wrong_position_basis_maximum_error_degrees": naive_error_deg,
	}
	fixture.free()
	print("ART_VERIFY_COMPACTION " + JSON.stringify(result))
	return result


func _verify_animations(filename: String) -> Dictionary:
	var result: Dictionary = {"file": filename, "animations": []}
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var error: Error = document.append_from_file("res://models/" + filename, state)
	if not _expect(error == OK, "Fresh GLTFDocument imports " + filename):
		return result
	var imported: Node = document.generate_scene(state)
	if not _expect(imported != null, "GLTFDocument generates a scene for " + filename):
		return result
	root.add_child(imported)
	await process_frame
	var players: Array[Node] = imported.find_children("*", "AnimationPlayer", true, false)
	if not _expect(not players.is_empty(), "Imported character has an AnimationPlayer: " + filename):
		imported.free()
		return result
	var nodes: Array[Node3D] = []
	_collect_nodes(imported, nodes)
	var rest: Dictionary = _snapshot(imported, nodes)
	for name: String in ["idle", "walk"]:
		var player: AnimationPlayer = null
		for candidate: AnimationPlayer in players:
			if candidate.has_animation(name):
				player = candidate
		if not _expect(player != null, "Imported animation exists: " + filename + "/" + name):
			continue
		for other: AnimationPlayer in players:
			other.stop()
			other.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		for node: Node3D in nodes:
			node.transform = rest[str(imported.get_path_to(node))]
		var animation: Animation = player.get_animation(name)
		_expect(animation.length > 0.0 and animation.get_track_count() > 0, "Imported animation has playable tracks: " + filename + "/" + name)
		var animation_root: Node = player.get_node_or_null(player.root_node)
		if not _expect(animation_root != null, "Imported AnimationPlayer root resolves: " + filename):
			continue
		for track: int in range(animation.get_track_count()):
			var track_path: NodePath = animation.track_get_path(track)
			var target_path := NodePath(track_path.get_concatenated_names())
			_expect(animation_root.get_node_or_null(target_path) != null, "Imported animation target resolves: " + str(track_path))
		player.active = true
		player.play(name)
		player.advance(0.0)
		var initial: Dictionary = _snapshot(imported, nodes)
		var changed: Dictionary = {}
		var maximum_position_delta: float = 0.0
		var maximum_rotation_delta: float = 0.0
		for sample: int in range(3):
			player.advance(animation.length * 0.25)
			await process_frame
			for node: Node3D in nodes:
				var path: String = str(imported.get_path_to(node))
				var before: Transform3D = initial[path]
				var after: Transform3D = node.transform
				_expect(after.is_finite() and node.global_transform.is_finite(), "Imported animated transform stays finite: " + filename + "/" + name + "/" + path)
				var position_delta: float = before.origin.distance_to(after.origin)
				var rotation_delta: float = before.basis.orthonormalized().get_rotation_quaternion().angle_to(after.basis.orthonormalized().get_rotation_quaternion())
				maximum_position_delta = maxf(maximum_position_delta, position_delta)
				maximum_rotation_delta = maxf(maximum_rotation_delta, rotation_delta)
				if not before.is_equal_approx(after):
					changed[path] = true
		var changed_paths: Array = changed.keys()
		changed_paths.sort()
		_expect(changed_paths.size() >= (4 if name == "walk" else 1), "Playback changes local node transforms: " + filename + "/" + name)
		if name == "walk":
			var limbs_changed: int = 0
			for path: String in changed_paths:
				if path.get_file() in ["Arm_L", "Arm_R", "Leg_L", "Leg_R"]:
					limbs_changed += 1
			_expect(limbs_changed == 4, "Imported walk actually drives both arms and both legs: " + filename)
		var animation_result: Dictionary = {
			"name": name, "duration_seconds": animation.length, "tracks": animation.get_track_count(),
			"sample_times": [0.0, animation.length * 0.25, animation.length * 0.50, animation.length * 0.75],
			"changed_local_nodes": changed_paths, "maximum_position_delta_metres": maximum_position_delta,
			"maximum_rotation_delta_degrees": rad_to_deg(maximum_rotation_delta),
		}
		result.animations.append(animation_result)
		print("ART_VERIFY_ANIMATION " + filename + " " + JSON.stringify(animation_result))
		player.stop()
	imported.free()
	return result


func _snapshot(scene: Node, nodes: Array[Node3D]) -> Dictionary:
	var values: Dictionary = {}
	for node: Node3D in nodes:
		values[str(scene.get_path_to(node))] = node.transform
	return values


func _collect_nodes(node: Node, nodes: Array[Node3D]) -> void:
	if node is Node3D:
		nodes.append(node)
	for child: Node in node.get_children():
		_collect_nodes(child, nodes)


func _triangle_count(mesh: Mesh) -> int:
	var count: int = 0
	for surface: int in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(surface)
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		count += int((indices.size() if not indices.is_empty() else vertices.size()) / 3)
	return count


func _position_key(position: Vector3) -> String:
	return "%d,%d,%d" % [roundi(position.x * 100000.0), roundi(position.y * 100000.0), roundi(position.z * 100000.0)]
