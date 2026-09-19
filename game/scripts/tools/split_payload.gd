extends SceneTree
## POLISH-04：把 prebuilt data.var 按顶层键拆成子集文件，供退出崩溃二分。

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var f := FileAccess.open("res://prebuilt/willow_creek_valley_v1/data.var", FileAccess.READ)
	var payload: Dictionary = str_to_var(f.get_as_text())
	f.close()
	DirAccess.make_dir_recursive_absolute("res://payload_subsets")
	for key: String in payload:
		var out := FileAccess.open("res://payload_subsets/" + key + ".var", FileAccess.WRITE)
		out.store_string(var_to_str(payload[key]))
		out.close()
		print("WROTE ", key, " len=", FileAccess.open("res://payload_subsets/" + key + ".var", FileAccess.READ).get_length())
	quit(0)
