extends RefCounted
## POLISH-02：输入动作层——把散落的物理键直查收敛为 InputMap 动作，键位与手柄统一。
## 由 main._ready 最先注册（幂等）；键盘绑定与旧直查键一一对应（既有测试的
## parse_input_event 注入不受影响），手柄为标准 Xbox 布局。
## ui_cancel 使用引擎内置动作（Esc + 手柄 B）。

const MOVE_DEADZONE := 0.3


static func register() -> void:
	_bind_axis("move_left", [KEY_A, KEY_LEFT], JOY_AXIS_LEFT_X, -1.0)
	_bind_axis("move_right", [KEY_D, KEY_RIGHT], JOY_AXIS_LEFT_X, 1.0)
	_bind_axis("move_up", [KEY_W, KEY_UP], JOY_AXIS_LEFT_Y, -1.0)
	_bind_axis("move_down", [KEY_S, KEY_DOWN], JOY_AXIS_LEFT_Y, 1.0)
	_bind("run", [KEY_SHIFT], JOY_BUTTON_LEFT_STICK)
	_bind("interact", [KEY_E], JOY_BUTTON_A)
	_bind("tool_use", [KEY_SPACE], JOY_BUTTON_X)
	_bind("eat_ration", [KEY_Q], JOY_BUTTON_BACK)
	_bind("seed_cycle", [KEY_R], JOY_BUTTON_DPAD_DOWN)
	_bind("inventory", [KEY_TAB], JOY_BUTTON_Y)
	_bind("map", [KEY_M], JOY_BUTTON_DPAD_UP)
	_bind("quick_save", [KEY_F5])
	_bind("quick_load", [KEY_F9])
	_bind("settings", [KEY_F10], JOY_BUTTON_START)
	_bind("tool_prev", [], JOY_BUTTON_LEFT_SHOULDER)
	_bind("tool_next", [], JOY_BUTTON_RIGHT_SHOULDER)
	_bind("zoom_out", [], JOY_BUTTON_DPAD_LEFT)
	_bind("zoom_in", [], JOY_BUTTON_DPAD_RIGHT)
	for index in range(10):
		var key: Key = KEY_0 if index == 9 else (KEY_1 + index)
		_bind("slot_%d" % (index + 1), [key])


static func _bind(action: String, keys: Array, joypad_button: JoyButton = JOY_BUTTON_INVALID) -> void:
	_ensure(action)
	for key: Key in keys:
		# 同时绑定 keycode 与 physical_keycode：兼容真实键盘事件与测试注入两种形态。
		var keyed := InputEventKey.new()
		keyed.keycode = key
		InputMap.action_add_event(action, keyed)
		var physical := InputEventKey.new()
		physical.physical_keycode = key
		InputMap.action_add_event(action, physical)
	if joypad_button != JOY_BUTTON_INVALID:
		var button := InputEventJoypadButton.new()
		button.button_index = joypad_button
		InputMap.action_add_event(action, button)


static func _bind_axis(action: String, keys: Array, axis: JoyAxis, value: float) -> void:
	_ensure(action, MOVE_DEADZONE)
	for key: Key in keys:
		var keyed := InputEventKey.new()
		keyed.keycode = key
		InputMap.action_add_event(action, keyed)
		var physical := InputEventKey.new()
		physical.physical_keycode = key
		InputMap.action_add_event(action, physical)
	var motion := InputEventJoypadMotion.new()
	motion.axis = axis
	motion.axis_value = value
	InputMap.action_add_event(action, motion)


static func _ensure(action: String, deadzone: float = 0.5) -> void:
	if InputMap.has_action(action):
		InputMap.action_erase_events(action)
	else:
		InputMap.add_action(action, deadzone)
