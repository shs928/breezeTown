extends SceneTree
## BUILD-01：把当前源构建的世界烘焙进 res://prebuilt/，供导出包首启免重建。
## 用法：Godot --headless --path game --script res://scripts/bake_world.gd
## 注意：会改变 res:// 下文件；只在本机构建流程中运行，产物不入库（.gitignore）。

const Builder := preload("res://scripts/first_map_builder.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	# BUILD-01：每次构建全量重烘（约 11 秒）。不做指纹跳过——GLB 不在运行时
	# 指纹里（导出 PCK 无 .glb 源），跳过会让"只改模型"的构建带出旧世界。
	var fingerprint: String = Builder._fingerprint()
	var dir := "res://prebuilt/willow_creek_valley_v1"
	print("BAKE building world ...")
	var data: Dictionary = Builder._build_world()
	var root: Node3D = data["root"]
	Builder._set_owners(root, root)
	var scene := PackedScene.new()
	if scene.pack(root) != OK:
		push_error("BAKE pack failed")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(dir)
	var save_error := ResourceSaver.save(scene, dir + "/world.scn", ResourceSaver.FLAG_COMPRESS)
	if save_error != OK:
		push_error("BAKE save world.scn failed: %s" % error_string(save_error))
		quit(1)
		return
	var payload := {}
	for key: String in data:
		if key != "root":
			payload[key] = data[key]
	var data_file := FileAccess.open(dir + "/data.var", FileAccess.WRITE)
	data_file.store_string(var_to_str(payload))
	data_file.close()
	var mark := FileAccess.open(dir + "/fingerprint.txt", FileAccess.WRITE)
	mark.store_string(fingerprint)
	mark.close()
	root.free()
	var saved_world := FileAccess.open(dir + "/world.scn", FileAccess.READ)
	var size := (saved_world.get_length() / 1048576.0) if saved_world != null else 0.0
	print("BAKE OK world.scn=%.1fMB fingerprint=%s" % [size, fingerprint])
	quit(0)
