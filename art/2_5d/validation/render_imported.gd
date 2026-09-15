extends SceneTree
## Render the exported farm, under the same workshop lighting as the source.

const Workshop = preload("res://scripts/showcase.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1920, 1200)
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.use_taa = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var workshop := Workshop.new()
	viewport.add_child(workshop)
	workshop._overlay.hide()
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var error := document.append_from_file("res://models/breeze_town_farm.glb", state)
	if error != OK:
		push_error("Exported farm could not be imported: " + error_string(error))
		quit(1)
		return
	var imported := document.generate_scene(state)
	if imported == null:
		push_error("Exported farm generated no scene")
		quit(1)
		return
	workshop._asset.free()
	workshop._asset = imported
	workshop._stage.add_child(imported)
	for frame in range(48):
		await process_frame
	await RenderingServer.frame_post_draw
	var picture := viewport.get_texture().get_image()
	var result := picture.save_png("res://validation/imported-farm.png")
	print("ART_IMPORTED_RENDER ", picture.get_size(), " ", error_string(result))
	quit(0 if result == OK else 1)
