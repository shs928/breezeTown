extends SceneTree
## SETTINGS-01 领域检查：设置存储往返、键位重绑与恢复默认、动作层联动。

const GameSettings := preload("res://scripts/core/game_settings.gd")
const InputActions := preload("res://scripts/core/input_actions.gd")

var failures: Array[String] = []
var count := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(label: String, ok: bool) -> void:
	count += 1
	print("SETTINGS %s %s" % [label, "OK" if ok else "FAIL"])
	if not ok:
		failures.append(label)


func _run() -> void:
	InputActions.register()
	_check("actions-registered", InputMap.has_action("interact") and InputMap.has_action("settings"))
	# 存储往返（写入独立文件，测试后清理）。
	GameSettings.config_path = "user://settings-checks.cfg"
	GameSettings.display_mode = 1
	GameSettings.vsync = false
	GameSettings.master_volume = 35
	GameSettings.keybinds = {"interact": KEY_K}
	GameSettings.save_settings(true)
	GameSettings.display_mode = 0
	GameSettings.vsync = true
	GameSettings.master_volume = 80
	GameSettings.keybinds = {}
	GameSettings.load_settings()
	_check("roundtrip-display", GameSettings.display_mode == 1)
	_check("roundtrip-vsync", GameSettings.vsync == false)
	_check("roundtrip-volume", GameSettings.master_volume == 35)
	_check("roundtrip-keybind", int(GameSettings.keybinds.get("interact", 0)) == KEY_K)
	# 重绑联动：interact 换 K 后 InputMap 键盘事件变化，E 被移除。
	GameSettings.rebind("interact", KEY_K)
	var codes: Array = []
	for event in InputMap.action_get_events("interact"):
		if event is InputEventKey:
			codes.append(int((event as InputEventKey).keycode))
	_check("rebind-inputmap-has-new-key", codes.has(KEY_K))
	_check("rebind-inputmap-drops-old-key", not codes.has(KEY_E))
	_check("rebind-keeps-joypad", InputMap.action_get_events("interact").any(func(ev): return ev is InputEventJoypadButton))
	_check("key-label-reflects-rebind", GameSettings.key_label("interact") == "K")
	# 恢复默认：回到 E。
	GameSettings.reset_keybinds()
	var restored: Array = []
	for event in InputMap.action_get_events("interact"):
		if event is InputEventKey:
			restored.append(int((event as InputEventKey).keycode))
	_check("reset-restores-default-key", restored.has(KEY_E) and not restored.has(KEY_K))
	_check("reset-clears-record", GameSettings.keybinds.is_empty())
	# 脏值归一：把越界值写进文件再读回，应被夹取。
	GameSettings.display_mode = 7
	GameSettings.master_volume = -5
	GameSettings.save_settings(true)
	GameSettings.display_mode = 0
	GameSettings.master_volume = 80
	GameSettings.load_settings()
	_check("load-clamps-display", GameSettings.display_mode == 1)
	_check("load-clamps-volume", GameSettings.master_volume == 0)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://settings-checks.cfg"))
	var verdict := "PASS %d" % count if failures.is_empty() else "FAIL %s" % ",".join(failures)
	print("SETTINGS_RESULT " + verdict)
	quit(0 if failures.is_empty() else 1)
