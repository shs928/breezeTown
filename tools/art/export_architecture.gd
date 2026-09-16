extends SceneTree
## Author the master meshes, merge static material batches and export runtime GLBs.
const B=preload("res://scripts/art/building_models.gd")
const R=preload("res://scripts/ranch_models.gd")
const Batch=preload("res://scripts/art/static_geometry.gd")
func _initialize() -> void:
	for spec in [["cottage",B.cottage()],["seed_shop",B.shop()],["barn",R.barn()],["coop",R.coop()]]:
		var model:Node3D=spec[1]
		root.add_child(model)
		Batch.bake(model)
		var document:=GLTFDocument.new()
		var state:=GLTFState.new()
		var error:=document.append_from_scene(model,state)
		if error!=OK:quit(error);return
		error=document.write_to_filesystem(state,"res://resources/models/%s.glb"%spec[0])
		print("ARCHITECTURE_EXPORTED ",spec[0]," ",error)
		model.free()
	quit()
