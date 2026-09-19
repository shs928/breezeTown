extends SceneTree
## BUILD-01：从原始截图生成 256×256 图标（中心方形裁剪）。
## 用法：Godot --headless --path game --script res://scripts/tools/make_icon.gd -- <src> <dst>

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var src := args[0] if args.size() > 0 else "res://icon_raw.png"
	var dst := args[1] if args.size() > 1 else "res://icon.png"
	var image := Image.load_from_file(ProjectSettings.globalize_path(src))
	if image == null:
		push_error("ICON source missing: " + src)
		quit(1)
		return
	var side := mini(image.get_width(), image.get_height())
	var offset := Vector2i((image.get_width() - side) / 2, (image.get_height() - side) / 2)
	var cropped := image.get_region(Rect2i(offset, Vector2i(side, side)))
	cropped.resize(256, 256, Image.INTERPOLATE_LANCZOS)
	var err := cropped.save_png(ProjectSettings.globalize_path(dst))
	print("ICON %s -> %s %s" % [src, dst, error_string(err)])
	quit(0 if err == OK else 1)
