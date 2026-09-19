extends RefCounted
## SETTINGS-01：设置存储与应用（显示模式/垂直同步/主音量/键位重绑）。
## 静态存取；ConfigFile 持久化到 user://settings.cfg。
## 测试环境（BREEZETOWN_SAVE_ROOT 非空）不落盘、且启动时不应用键位——
## 避免开发者改键后 headless 检查的按键注入失配。

const InputActions := preload("res://scripts/core/input_actions.gd")

const REBINDABLE := {
	"interact": "交互",
	"tool_use": "使用工具",
	"run": "奔跑",
	"eat_ration": "吃口粮",
	"seed_cycle": "换种子",
	"inventory": "背包",
	"map": "地图",
	"quick_save": "快速存档",
	"quick_load": "快速读取",
	"move_up": "向上移动",
	"move_down": "向下移动",
	"move_left": "向左移动",
	"move_right": "向右移动",
}

const CAPACITY_STEP := 300

static var config_path := "user://settings.cfg"
static var display_mode := 0  # 0 窗口 1 全屏
static var vsync := true
static var master_volume := 80  # 0-100（主音量总线）
static var keybinds := {}  # 动作名 -> 物理键码；空 = 使用默认绑定
static var persist_enabled := true


static func test_env() -> bool:
	return not OS.get_environment("BREEZETOWN_SAVE_ROOT").is_empty()


static func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(config_path) != OK:
		return
	display_mode = clampi(int(cfg.get_value("video", "display_mode", display_mode)), 0, 1)
	vsync = bool(cfg.get_value("video", "vsync", vsync))
	master_volume = clampi(int(cfg.get_value("audio", "master_volume", master_volume)), 0, 100)
	var saved_binds: Dictionary = cfg.get_value("keys", "bindings", {})
	if saved_binds is Dictionary:
		for action: String in saved_binds:
			if REBINDABLE.has(action):
				keybinds[action] = int(saved_binds[action])


static func save_settings(force: bool = false) -> void:
	if test_env() and not force:
		return
	var cfg := ConfigFile.new()
	cfg.set_value("video", "display_mode", display_mode)
	cfg.set_value("video", "vsync", vsync)
	cfg.set_value("audio", "master_volume", master_volume)
	cfg.set_value("keys", "bindings", keybinds)
	cfg.save(config_path)


static func apply_all() -> void:
	apply_display()
	apply_volume()
	if not test_env():
		for action: String in keybinds:
			apply_keybind(action, int(keybinds[action]))


static func apply_display() -> void:
	var mode := DisplayServer.WINDOW_MODE_WINDOWED if display_mode == 0 else DisplayServer.WINDOW_MODE_FULLSCREEN
	DisplayServer.window_set_mode(mode)


static func apply_vsync() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)


static func apply_volume() -> void:
	var db := linear_to_db(clampf(float(master_volume) / 100.0, 0.0001, 1.0)) if master_volume > 0 else -80.0
	AudioServer.set_bus_volume_db(0, db)


static func apply_keybind(action: String, keycode: int) -> void:
	## 只替换动作的键盘事件（keycode+physical 双形态），保留手柄绑定。
	if not InputMap.has_action(action):
		return
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			InputMap.action_erase_event(action, event)
	var keyed_code := InputEventKey.new()
	keyed_code.keycode = keycode as Key
	InputMap.action_add_event(action, keyed_code)
	var keyed_physical := InputEventKey.new()
	keyed_physical.physical_keycode = keycode as Key
	InputMap.action_add_event(action, keyed_physical)


static func rebind(action: String, keycode: int) -> void:
	keybinds[action] = keycode
	apply_keybind(action, keycode)
	save_settings()


static func reset_keybinds() -> void:
	keybinds.clear()
	InputActions.register()
	save_settings()


static func key_label(action: String) -> String:
	## 当前键盘键位的显示名：优先用户重绑，否则取 InputMap 现有绑定。
	if keybinds.has(action):
		return OS.get_keycode_string(int(keybinds[action]) as Key)
	for event in InputMap.action_get_events(action):
		if event is InputEventKey and int(event.keycode) != 0:
			return OS.get_keycode_string((event as InputEventKey).keycode)
	return "未绑定"
