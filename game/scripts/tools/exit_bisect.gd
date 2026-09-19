extends SceneTree
## POLISH-04：退出堆损坏二分探针。退出前按 BREEZETOWN_FREE 提前释放目标。
## 取值逗号分隔：hud,weather,outdoors,lights,player,interiors,mine,statics

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var game: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	for i in range(8):
		await process_frame
	var targets := OS.get_environment("BREEZETOWN_FREE").split(",")
	for target: String in targets:
		match target:
			"hud":
				var hud: Node = game.get("hud")
				if hud != null:
					game.remove_child(hud)
					hud.free()
					game.set("hud", null)
			"weather":
				var rig: Node = game.get("_weather_rig")
				if rig != null:
					game.remove_child(rig)
					rig.free()
					game.set("_weather_rig", null)
			"outdoors":
				var out: Node = game.get_node_or_null("OutdoorMap")
				if out != null:
					game.remove_child(out)
					out.free()
			"lights":
				for child in game.get_children():
					if child is DirectionalLight3D or child is WorldEnvironment:
						game.remove_child(child)
						child.free()
			"player":
				var player: Node = game.get("player")
				if player != null:
					game.remove_child(player)
					player.free()
			"interiors":
				var inter: Node = game.get_node_or_null("Interiors")
				if inter != null:
					game.remove_child(inter)
					inter.free()
			"mine":
				var mine_root: Node = game.get_node_or_null("MineFloors")
				if mine_root != null:
					game.remove_child(mine_root)
					mine_root.free()
			"statics":
				_clear_statics()
	await process_frame
	print("BISECT freed=", OS.get_environment("BREEZETOWN_FREE"))
	quit(0)


func _clear_statics() -> void:
	var art_mesh := load("res://scripts/art/art_mesh.gd")
	art_mesh._palette.clear()
	art_mesh._shape_cache.clear()
	var tile := load("res://scripts/tile.gd")
	tile._crop_meshes.clear()
	tile._soil_mesh_cache.clear()
	tile._board_mesh = null
	tile._ring_mesh = null
	tile._ring_material = null
	var tree := load("res://scripts/art/tree_models.gd")
	tree._meshes.clear()
	var building := load("res://scripts/art/building_models.gd")
	building._material_cache.clear()
	var paths := load("res://scripts/art/painted_paths.gd")
	paths._materials.clear()
	var mine_models := load("res://scripts/art/mine_models.gd")
	mine_models._glow_materials.clear()
	var landscape := load("res://scripts/art/landscape_models.gd")
	landscape._stone_material = null
	var pasture := load("res://scripts/pasture.gd")
	if pasture._fence_template != null:
		pasture._fence_template.free()
		pasture._fence_template = null
	var wb := load("res://scripts/world_builder.gd")
	wb._templates.clear()
