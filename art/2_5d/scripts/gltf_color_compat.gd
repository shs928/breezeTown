extends RefCounted
## Godot 4.7.2 runtime GLTFDocument vertex-color compatibility.
## Split one indexed triangle from a colored first primitive while reusing its
## material and attributes. Only JSON changes: all following GLB chunks stay exact.

const GLB_MAGIC := 0x46546c67
const JSON_CHUNK := 0x4e4f534a


static func patch_file(path: String) -> Dictionary:
	var absolute_path: String = ProjectSettings.globalize_path(path)
	if not absolute_path.is_absolute_path():
		absolute_path = ProjectSettings.globalize_path("res://").path_join(path).simplify_path()
	var result: Dictionary = {
		"ok": false, "file": absolute_path, "changed": false,
		"patched_meshes": 0, "already_compatible_meshes": 0,
		"white_color_meshes_skipped": 0, "other_meshes_skipped": 0,
		"binary_unchanged": false, "triangles_preserved": false,
	}
	var input := FileAccess.open(absolute_path, FileAccess.READ)
	if input == null:
		return _fail(result, FileAccess.get_open_error(), "Cannot read GLB")
	var expected_length: int = input.get_length()
	var source: PackedByteArray = input.get_buffer(expected_length)
	input.close()
	if source.size() != expected_length or source.size() < 20:
		return _fail(result, ERR_FILE_CORRUPT, "GLB is truncated or could not be read completely")
	if source.decode_u32(0) != GLB_MAGIC or source.decode_u32(4) != 2:
		return _fail(result, ERR_FILE_UNRECOGNIZED, "Expected a glTF 2.0 binary file")
	if source.decode_u32(8) != source.size():
		return _fail(result, ERR_FILE_CORRUPT, "GLB header length differs from the file length")
	var json_length: int = source.decode_u32(12)
	if source.decode_u32(16) != JSON_CHUNK or json_length % 4 != 0 or json_length < 2 or 20 + json_length > source.size():
		return _fail(result, ERR_FILE_CORRUPT, "First GLB chunk is not a valid aligned JSON chunk")
	var tail_offset: int = 20 + json_length
	var chunk_cursor: int = tail_offset
	while chunk_cursor < source.size():
		if chunk_cursor + 8 > source.size():
			return _fail(result, ERR_FILE_CORRUPT, "A trailing GLB chunk header is truncated")
		var chunk_length: int = source.decode_u32(chunk_cursor)
		if chunk_length % 4 != 0 or chunk_cursor + 8 + chunk_length > source.size():
			return _fail(result, ERR_FILE_CORRUPT, "A trailing GLB chunk has an invalid length")
		chunk_cursor += 8 + chunk_length
	var json := JSON.new()
	if json.parse(source.slice(20, tail_offset).get_string_from_utf8()) != OK or not json.data is Dictionary:
		return _fail(result, ERR_PARSE_ERROR, "Cannot parse GLB JSON: " + json.get_error_message())
	var document: Dictionary = json.data
	if not document.get("meshes", []) is Array or not document.get("accessors", []) is Array or not document.get("bufferViews", []) is Array:
		return _fail(result, ERR_FILE_CORRUPT, "GLB meshes, accessors, and bufferViews must be arrays")
	var meshes: Array = document.get("meshes", [])
	var accessors: Array = document.get("accessors", [])
	var buffer_views: Array = document.get("bufferViews", [])
	var patches: Array = []
	for mesh_index: int in range(meshes.size()):
		if not meshes[mesh_index] is Dictionary:
			return _fail(result, ERR_FILE_CORRUPT, "Mesh is not an object: " + str(mesh_index))
		var mesh: Dictionary = meshes[mesh_index]
		if not mesh.get("primitives", []) is Array:
			return _fail(result, ERR_FILE_CORRUPT, "Mesh primitives are not an array: " + str(mesh_index))
		var primitives: Array = mesh.get("primitives", [])
		if primitives.is_empty():
			result.other_meshes_skipped += 1
			continue
		if not primitives[0] is Dictionary or not primitives[0].get("attributes", {}) is Dictionary:
			return _fail(result, ERR_FILE_CORRUPT, "First primitive or its attributes are invalid: " + str(mesh_index))
		var first: Dictionary = primitives[0]
		var attributes: Dictionary = first.get("attributes", {})
		if not attributes.has("COLOR_0") or _nonnegative_integer(first.get("mode", 4)) != 4 or not first.has("indices"):
			result.other_meshes_skipped += 1
			continue
		# A previously split primitive already shares the material with the next
		# colored primitive. Do not split it, or other equivalent assets, again.
		if primitives.size() >= 2 and primitives[1] is Dictionary:
			var second: Dictionary = primitives[1]
			if second.get("material", -1) == first.get("material", -1) and second.get("attributes", {}) is Dictionary and second.get("attributes", {}).has("COLOR_0"):
				result.already_compatible_meshes += 1
				continue
		var color_index: int = _nonnegative_integer(attributes.COLOR_0)
		if color_index < 0 or color_index >= accessors.size() or not accessors[color_index] is Dictionary:
			return _fail(result, ERR_FILE_CORRUPT, "COLOR_0 accessor is invalid for mesh " + str(mesh_index))
		var color: Dictionary = accessors[color_index]
		var white: Dictionary = _white_color_bounds(color)
		if not white.ok:
			return _fail(result, ERR_FILE_CORRUPT, "Invalid COLOR_0 bounds for mesh " + str(mesh_index) + ": " + white.error)
		if white.white:
			result.white_color_meshes_skipped += 1
			continue
		var index_id: int = _nonnegative_integer(first.indices)
		if index_id < 0 or index_id >= accessors.size() or not accessors[index_id] is Dictionary:
			return _fail(result, ERR_FILE_CORRUPT, "Index accessor is invalid for mesh " + str(mesh_index))
		var original_indices: Dictionary = accessors[index_id]
		var count: int = _nonnegative_integer(original_indices.get("count", -1))
		if count < 0:
			return _fail(result, ERR_FILE_CORRUPT, "Index count is invalid for mesh " + str(mesh_index))
		if count < 6:
			result.other_meshes_skipped += 1
			continue
		if count % 3 != 0 or original_indices.get("type", "") != "SCALAR":
			return _fail(result, ERR_FILE_CORRUPT, "Triangle indices must be scalar triplets for mesh " + str(mesh_index))
		if original_indices.has("sparse"):
			return _fail(result, ERR_UNAVAILABLE, "Sparse index accessors cannot be split without rewriting binary data")
		var component_type: int = _nonnegative_integer(original_indices.get("componentType", -1))
		var component_bytes: int = {5121: 1, 5123: 2, 5125: 4}.get(component_type, 0)
		if component_bytes == 0:
			return _fail(result, ERR_FILE_CORRUPT, "Indices must use unsigned byte, unsigned short, or unsigned int")
		var offset: int = _nonnegative_integer(original_indices.get("byteOffset", 0))
		var view_index: int = _nonnegative_integer(original_indices.get("bufferView", -1))
		if offset < 0 or offset % component_bytes != 0 or view_index < 0 or view_index >= buffer_views.size() or not buffer_views[view_index] is Dictionary:
			return _fail(result, ERR_FILE_CORRUPT, "Index accessor bufferView or alignment is invalid")
		var view: Dictionary = buffer_views[view_index]
		var view_length: int = _nonnegative_integer(view.get("byteLength", -1))
		var stride: int = _nonnegative_integer(view.get("byteStride", 0))
		if stride != 0 and stride != component_bytes:
			return _fail(result, ERR_UNAVAILABLE, "Interleaved index data is not supported by the JSON-only split")
		if view_length < 0 or offset + count * component_bytes > view_length:
			return _fail(result, ERR_FILE_CORRUPT, "Index accessor extends beyond its bufferView")
		var first_indices: Dictionary = original_indices.duplicate(true)
		var rest_indices: Dictionary = original_indices.duplicate(true)
		first_indices.count = 3
		first_indices.byteOffset = offset
		rest_indices.count = count - 3
		rest_indices.byteOffset = offset + 3 * component_bytes
		for accessor: Dictionary in [first_indices, rest_indices]:
			accessor.erase("min")
			accessor.erase("max")
		var first_accessor: int = accessors.size()
		accessors.append(first_indices)
		accessors.append(rest_indices)
		var first_triangle: Dictionary = first.duplicate(true)
		var remaining: Dictionary = first.duplicate(true)
		first_triangle.indices = first_accessor
		remaining.indices = first_accessor + 1
		var replacement: Array = [first_triangle, remaining]
		replacement.append_array(primitives.slice(1))
		mesh.primitives = replacement
		patches.append({"mesh": mesh_index, "index_component_bytes": component_bytes, "source_index_count": count, "split_index_counts": [3, count - 3]})
	var tail: PackedByteArray = source.slice(tail_offset)
	result.bytes_before = source.size()
	result.bytes_after = source.size()
	result.tail_sha256_before = _sha256(tail)
	result.tail_sha256_after = result.tail_sha256_before
	result.binary_unchanged = true
	result.triangles_preserved = true
	result.patches = patches
	if patches.is_empty():
		result.ok = true
		return result
	document.accessors = accessors
	var encoded_json: PackedByteArray = JSON.stringify(document, "", false, true).to_utf8_buffer()
	while encoded_json.size() % 4 != 0:
		encoded_json.append(32)
	var output := PackedByteArray()
	output.resize(20)
	output.encode_u32(0, GLB_MAGIC)
	output.encode_u32(4, 2)
	output.encode_u32(8, 20 + encoded_json.size() + tail.size())
	output.encode_u32(12, encoded_json.size())
	output.encode_u32(16, JSON_CHUNK)
	output.append_array(encoded_json)
	output.append_array(tail)
	# Validate a complete temporary file before replacing the requested GLB.
	var temporary: String = absolute_path + ".color-compat-" + str(OS.get_process_id()) + "-" + str(Time.get_ticks_usec()) + ".tmp"
	var writer := FileAccess.open(temporary, FileAccess.WRITE)
	if writer == null:
		return _fail(result, FileAccess.get_open_error(), "Cannot create temporary GLB beside the original")
	writer.store_buffer(output)
	writer.flush()
	var write_error: Error = writer.get_error()
	writer.close()
	if write_error != OK:
		return _temporary_failure(result, temporary, write_error, "Cannot write the complete temporary GLB")
	var written: PackedByteArray = FileAccess.get_file_as_bytes(temporary)
	if written != output or written.slice(20 + encoded_json.size()) != tail:
		return _temporary_failure(result, temporary, ERR_FILE_CORRUPT, "Temporary GLB verification failed; original was kept")
	var commit_error: Error = DirAccess.rename_absolute(temporary, absolute_path)
	if commit_error != OK:
		return _temporary_failure(result, temporary, commit_error, "Cannot replace the original GLB with the verified file")
	result.ok = true
	result.changed = true
	result.patched_meshes = patches.size()
	result.bytes_after = output.size()
	result.tail_sha256_after = _sha256(written.slice(20 + encoded_json.size()))
	result.binary_unchanged = result.tail_sha256_before == result.tail_sha256_after
	return result


static func _nonnegative_integer(value: Variant) -> int:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return -1
	var number: float = float(value)
	if not is_finite(number) or number < 0 or number > 4294967295.0 or number != floor(number):
		return -1
	return int(number)


static func _white_color_bounds(accessor: Dictionary) -> Dictionary:
	var components: int = 3 if accessor.get("type", "") == "VEC3" else (4 if accessor.get("type", "") == "VEC4" else 0)
	if components == 0:
		return {"ok": false, "error": "Color accessor must be VEC3 or VEC4", "white": false}
	# Without both extrema, keep color data conservatively even if a sampled
	# vertex happens to be white. Alpha modulation also counts as nonwhite.
	if not accessor.has("min") or not accessor.has("max"):
		return {"ok": true, "white": false}
	var white: bool = true
	for key: String in ["min", "max"]:
		if not accessor[key] is Array or accessor[key].size() != components:
			return {"ok": false, "error": "Color bound dimensions are invalid", "white": false}
		for value: Variant in accessor[key]:
			if (typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT) or not is_finite(float(value)):
				return {"ok": false, "error": "Color bounds must be finite numbers", "white": false}
			if not is_equal_approx(float(value), 1.0):
				white = false
	return {"ok": true, "white": white}


static func _sha256(bytes: PackedByteArray) -> String:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(bytes)
	return hashing.finish().hex_encode()


static func _fail(result: Dictionary, code: Error, message: String) -> Dictionary:
	result.ok = false
	result.error_code = code
	result.error = message + " (" + error_string(code) + ")"
	return result


static func _temporary_failure(result: Dictionary, path: String, code: Error, message: String) -> Dictionary:
	var cleanup: Error = DirAccess.remove_absolute(path)
	if cleanup != OK:
		result.temporary_file = path
		result.cleanup_error = error_string(cleanup)
	return _fail(result, code, message)
