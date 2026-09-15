extends CanvasLayer
## 界面：状态栏、工具栏、情境提示、背包面板、商店面板、睡觉淡出。

signal shop_closed

const GameState := preload("res://scripts/game_state.gd")

const INK := Color("#3a4a3f")
const INK_SOFT := Color("#61756c")
const CREAM := Color(0.97, 0.94, 0.86, 0.94)

var state: RefCounted
var shop_open := false

var _coins_label: Label
var _clock_label: Label
var _hint_label: Label
var _slots: Array[Label] = []
var _slot_styles: Array[StyleBoxFlat] = []
var _inventory_panel: PanelContainer
var _inventory_lines: VBoxContainer
var _shop_panel: PanelContainer
var _fade: ColorRect
var _toast: Label


func _ready() -> void:
	layer = 10
	_build_status()
	_build_toolbar()
	_build_inventory()
	_build_shop()
	_fade = ColorRect.new()
	_fade.color = Color(0.08, 0.10, 0.09, 1.0)
	_fade.modulate.a = 0.0
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_fade)
	_toast = Label.new()
	_toast.set_anchors_preset(Control.PRESET_CENTER)
	_toast.add_theme_font_size_override("font_size", 34)
	_toast.add_theme_color_override("font_color", Color("#f4ecd4"))
	_toast.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
	_toast.add_theme_constant_override("shadow_offset_y", 2)
	_toast.modulate.a = 0.0
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toast)


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = CREAM
	style.set_corner_radius_all(12)
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 10.0
	style.shadow_color = Color(0, 0, 0, 0.18)
	style.shadow_size = 6
	return style


func _label(text: String, size: int, color: Color = INK) -> Label:
	var result := Label.new()
	result.text = text
	result.add_theme_font_size_override("font_size", size)
	result.add_theme_color_override("font_color", color)
	return result


func _build_status() -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style())
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.position = Vector2(18, 16)
	add_child(panel)
	var column := VBoxContainer.new()
	panel.add_child(column)
	_coins_label = _label("金币 20", 22)
	column.add_child(_coins_label)
	_clock_label = _label("第 1 天 · 08:00", 15, INK_SOFT)
	column.add_child(_clock_label)


func _build_toolbar() -> void:
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", _panel_style())
	bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bar.position.y -= 64.0
	add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	bar.add_child(row)
	for i in range(5):
		var slot := PanelContainer.new()
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.90, 0.87, 0.78, 0.9)
		style.set_corner_radius_all(9)
		style.content_margin_left = 12.0
		style.content_margin_right = 12.0
		style.content_margin_top = 5.0
		style.content_margin_bottom = 5.0
		slot.add_theme_stylebox_override("panel", style)
		_slot_styles.append(style)
		var text := _label(["1 空手", "2 锄头", "3 水壶", "4 种子", "5 围栏"][i], 17)
		text.custom_minimum_size.x = 96.0
		text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		slot.add_child(text)
		_slots.append(text)
		row.add_child(slot)
	_hint_label = _label("", 16, INK_SOFT)
	_hint_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_hint_label.offset_top = -142.0
	_hint_label.offset_bottom = -112.0
	_hint_label.offset_left = 24.0
	_hint_label.offset_right = -24.0
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_hint_label)


func _build_inventory() -> void:
	_inventory_panel = PanelContainer.new()
	_inventory_panel.add_theme_stylebox_override("panel", _panel_style())
	_inventory_panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_inventory_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_inventory_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_inventory_panel.position.x -= 18.0
	_inventory_panel.visible = false
	add_child(_inventory_panel)
	_inventory_lines = VBoxContainer.new()
	_inventory_panel.add_child(_inventory_lines)


func _build_shop() -> void:
	_shop_panel = PanelContainer.new()
	_shop_panel.add_theme_stylebox_override("panel", _panel_style())
	_shop_panel.set_anchors_preset(Control.PRESET_CENTER)
	_shop_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_shop_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_shop_panel.visible = false
	add_child(_shop_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	_shop_panel.add_child(column)
	column.add_child(_label("种子商店", 24))
	column.add_child(_label("钱货两讫，童叟无欺", 13, INK_SOFT))
	for kind in GameState.CROP_ORDER:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var info := _label("", 16)
		info.name = "Shop_" + kind
		info.custom_minimum_size.x = 250.0
		row.add_child(info)
		for count in [1, 5]:
			var button := Button.new()
			button.text = "买 %d" % count
			button.add_theme_font_size_override("font_size", 14)
			var crop: String = kind
			var amount: int = count
			button.pressed.connect(func(): buy_requested.emit(crop, amount))
			row.add_child(button)
		column.add_child(row)
	column.add_child(HSeparator.new())
	var sell_row := HBoxContainer.new()
	var sell_info := _label("", 16)
	sell_info.name = "SellInfo"
	sell_info.custom_minimum_size.x = 250.0
	sell_row.add_child(sell_info)
	var sell_button := Button.new()
	sell_button.text = "卖出全部"
	sell_button.add_theme_font_size_override("font_size", 14)
	sell_button.pressed.connect(func(): sell_requested.emit())
	sell_row.add_child(sell_button)
	column.add_child(sell_row)
	var close := Button.new()
	close.text = "离开（Esc）"
	close.add_theme_font_size_override("font_size", 14)
	close.pressed.connect(close_shop)
	column.add_child(close)


signal buy_requested(kind: String, count: int)
signal sell_requested


func refresh() -> void:
	_coins_label.text = "金币 %d" % state.coins
	_clock_label.text = "第 %d 天 · %s" % [state.day, state.clock_text()]
	for child in _inventory_lines.get_children():
		_inventory_lines.remove_child(child)
		child.free()
	_inventory_lines.add_child(_label("背包（Tab 关闭）", 18))
	var seed_line := "种子  "
	for kind in GameState.CROP_ORDER:
		seed_line += "%s ×%d   " % [GameState.crop_label(kind), state.seeds[kind]]
	_inventory_lines.add_child(_label(seed_line, 14))
	var harvest_line := "收获  "
	var any := false
	for kind in GameState.CROP_ORDER:
		if state.harvest[kind] > 0:
			any = true
		harvest_line += "%s ×%d   " % [GameState.crop_label(kind), state.harvest[kind]]
	_inventory_lines.add_child(_label(harvest_line, 14))
	var product_line := "产品  "
	for kind in GameState.PRODUCT_ORDER:
		product_line += "%s ×%d   " % [GameState.product_label(kind), state.products[kind]]
	_inventory_lines.add_child(_label(product_line, 14))
	if not any:
		_inventory_lines.add_child(_label("（还没有收成，去田里试试）", 13, INK_SOFT))
	for kind in GameState.CROP_ORDER:
		var info: Label = _shop_panel.find_child("Shop_" + kind, true, false)
		info.text = "%s 种子  %d 金币/粒（存 %d）" % [GameState.crop_label(kind), GameState.crop_field(kind, "seed_price"), state.seeds[kind]]
	var sell_info: Label = _shop_panel.find_child("SellInfo", true, false)
	var total := 0
	for kind in GameState.CROP_ORDER:
		total += state.harvest[kind] * GameState.crop_field(kind, "sell_price")
	for kind in GameState.PRODUCT_ORDER:
		total += state.products[kind] * GameState.PRODUCTS[kind]["sell_price"]
	sell_info.text = "收获与产品折价 %d 金币" % total


func set_hint(text: String) -> void:
	_hint_label.text = text


func select_slot(index: int, seed_kind: String, seed_count: int) -> void:
	for i in range(_slots.size()):
		var selected := i == index
		_slot_styles[i].bg_color = Color("#e9c97c", 0.95) if selected else Color(0.90, 0.87, 0.78, 0.9)
		if i == 3:
			_slots[i].text = "4 种子·%s ×%d" % [GameState.crop_label(seed_kind), seed_count]
			_slots[i].add_theme_color_override("font_color", INK if seed_count > 0 else Color("#a09a86"))


func toggle_inventory() -> void:
	_inventory_panel.visible = not _inventory_panel.visible
	if _inventory_panel.visible:
		refresh()


func open_shop() -> void:
	shop_open = true
	_inventory_panel.visible = false
	_shop_panel.visible = true
	refresh()


func close_shop() -> void:
	if not shop_open:
		return
	shop_open = false
	_shop_panel.visible = false
	shop_closed.emit()


func dismiss_panels() -> void:
	close_shop()
	if _inventory_panel.visible:
		_inventory_panel.visible = false


func show_toast(text: String) -> void:
	_toast.text = text
	var tween := create_tween()
	_toast.modulate.a = 1.0
	tween.tween_interval(1.1)
	tween.tween_property(_toast, "modulate:a", 0.0, 0.5)


func fade_sleep(wake_up: Callable) -> void:
	var tween := create_tween()
	tween.tween_property(_fade, "modulate:a", 1.0, 0.55)
	tween.tween_callback(wake_up)
	tween.tween_interval(0.35)
	tween.tween_property(_fade, "modulate:a", 0.0, 0.7)
