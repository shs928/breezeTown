extends Node3D
## 干净探针 v21：MODE=buffer_utf8 / get_utf8_string / get_line / astext_control

func _ready() -> void:
	var mode := OS.get_environment("BREEZETOWN_PROBE")
	print("CLEAN_READY mode=", mode)
	var f := FileAccess.open("res://payload_subsets/pasture.var", FileAccess.READ)
	if mode == "buffer_utf8":
		var bytes := f.get_buffer(f.get_length())
		f.close()
		var text := bytes.get_string_from_utf8()
		print("LEN=", text.length())
	elif mode == "get_utf8_string":
		var text := f.get_as_utf8_string()
		f.close()
		print("LEN=", text.length())
	elif mode == "get_line":
		var line := f.get_line()
		f.close()
		print("LINE=", line.length())
