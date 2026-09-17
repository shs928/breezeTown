extends CanvasLayer
## 界面（Art Bible 第四节版式）：木质面板 + 羊皮纸内衬。
## 左上状态板（头像/生命/口粮）· 右上信息排（季节/日期/天气/时钟/金币）
## · 底部快捷栏与情境提示 · 背包/商店/矿场/升降机面板。

signal shop_closed
signal map_toggled(open: bool)
signal panels_changed
signal travel_requested(depth: int)

const GameState := preload("res://scripts/game_state.gd")
const TownMap := preload("res://scripts/town_map.gd")
const Equipment := preload("res://scripts/art/equipment_models.gd")
const MineLayout := preload("res://scripts/mine_layout.gd")

# Art Bible UI 色板
const INK := Color("#5a4632")
const INK_SOFT := Color("#8a7358")
const CREAM := Color(0.965, 0.914, 0.808, 0.97)
const CREAM_SOFT := Color(0.941, 0.878, 0.749, 0.94)
const WOOD := Color("#8b5a3c")
const WOOD_DARK := Color("#5f3d24")
const WOOD_LIGHT := Color("#a0693f")
const GOLD := Color("#e8bf62")
const HP_RED := Color("#d9534f")
const LEAF_GREEN := Color("#7bb661")

var state: RefCounted
var shop_open := false
var map_open := false
var travel_open := false
var inventory_open := false
var _map: Control

var _coins_label: Label
var _clock_label: Label
var _season_chip: Label
var _day_chip: Label
var _weather_chip: Label
var _hp_bar: ProgressBar
var _hp_value: Label
var _ration_value: Label
var _ration_hint: Label
var _hint_label: Label
var _toolbar: PanelContainer
var _slots: Array[Label] = []
var _slot_counts: Array[Label] = []
var _slot_markers: Array[ColorRect] = []
var _slot_styles: Array[StyleBoxFlat] = []
var _inventory_panel: PanelContainer
var _inventory_lines: VBoxContainer
var _shop_panel: PanelContainer
var _fade: ColorRect
var _toast_panel: PanelContainer
var _toast: Label
var _toast_tween: Tween
var _mine_panel: PanelContainer
var _mine_title: Label
var _mine_objective: Label
var _health_label: Label
var _health_bar: ProgressBar
var _ration_label: Label
var _travel_panel: PanelContainer
var _travel_buttons: Dictionary = {}
var _mine_depth := 0
var _header: Control
var _money: Control
var _slot_panels: Array[PanelContainer] = []


func _ready() -> void:
	layer = 10
	_build_status()
	_build_info_chips()
	_build_toolbar()
	_build_inventory()
	_build_shop()
	_build_mine_status()
	_build_travel_panel()
	_fade = ColorRect.new()
	_fade.color = Color(0.08, 0.10, 0.09, 1.0)
	_fade.modulate.a = 0.0
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_fade)
	_build_toast()
	EventBus.instance().money_changed.connect(_on_money_changed)
	EventBus.instance().day_started.connect(_on_day_started_event)


# ---------- Art Bible 样式 ----------

func _wood_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = WOOD
	style.border_color = WOOD_DARK
	style.set_border_width_all(3)
	style.set_corner_radius_all(14)
	style.shadow_color = Color(0.24, 0.14, 0.07, 0.32)
	style.shadow_size = 6
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 10.0
	return style


func _parchment_style(radius: float = 10.0, background: Color = CREAM) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = WOOD_DARK
	style.set_border_width_all(2)
	style.set_corner_radius_all(int(radius))
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 8.0
	return style


func _label(text: String, size: int, color: Color = INK) -> Label:
	var result := Label.new()
	result.text = text
	result.add_theme_font_size_override("font_size", size)
	result.add_theme_color_override("font_color", color)
	return result


func _button(text: String, size: int = 14) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", size)
	button.add_theme_color_override("font_color", INK)
	button.add_theme_color_override("font_hover_color", Color("#3d2f1f"))
	button.add_theme_color_override("font_pressed_color", INK_SOFT)
	var normal := _parchment_style(8.0, CREAM_SOFT)
	normal.set_border_width_all(2)
	var hover := _parchment_style(8.0, Color(0.972, 0.929, 0.82))
	hover.border_color = GOLD
	hover.set_border_width_all(3)
	var pressed := _parchment_style(8.0, Color(0.90, 0.84, 0.70))
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return button


static func _fmt_number(value: int) -> String:
	var digits := str(value)
	var out := ""
	for index in range(digits.length()):
		out += digits[index]
		var remaining := digits.length() - 1 - index
		if remaining > 0 and remaining % 3 == 0:
			out += ","
	return out


# ---------- 左上：状态板 ----------

func _skin(kind: String, edge: int = 20) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = load("res://resources/ui/" + kind + ".png")
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		style.set_texture_margin(side, edge)
		style.set_content_margin(side, edge * 0.7)
	return style


func _icon(kind: String, dimensions: Vector2) -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = load("res://resources/ui/" + kind + ".png")
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = dimensions
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon


func _build_status() -> void:
	var panel := Control.new()
	panel.position = Vector2(20,18)
	panel.size = Vector2(355,113)
	add_child(panel)
	var background := _icon("status", panel.size)
	background.size = panel.size
	panel.add_child(background)
	var title := _label("微风农场",18)
	title.position = Vector2(104,15)
	panel.add_child(title)
	_hp_bar = _stat_bar(HP_RED)
	_hp_bar.position = Vector2(119,44)
	_hp_bar.size = Vector2(211,21)
	panel.add_child(_hp_bar)
	_hp_value = _label("100 / 100",14,Color("#fff1d1"))
	_hp_value.position = Vector2(119,44)
	_hp_value.size = Vector2(211,21)
	_hp_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(_hp_value)
	var heart := _label("♥",23,Color("#b94b40"))
	heart.position = Vector2(94,39)
	panel.add_child(heart)
	var food := _icon("ration", Vector2(26, 25))
	food.position = Vector2(93, 71)
	food.size = Vector2(26, 25)
	panel.add_child(food)
	_ration_value = _label("口粮 ×3", 15, INK)
	_ration_value.position = Vector2(122, 73)
	_ration_value.size = Vector2(123, 24)
	_ration_value.tooltip_text = "每份口粮恢复 35 生命，Q 食用"
	panel.add_child(_ration_value)
	_ration_hint = _label("Q 食用", 12, INK_SOFT)
	_ration_hint.position = Vector2(265, 76)
	_ration_hint.size = Vector2(65, 20)
	_ration_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	panel.add_child(_ration_hint)


func _stat_bar(fill_color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(158, 15)
	bar.max_value = GameState.MAX_HEALTH
	bar.value = GameState.MAX_HEALTH
	bar.show_percentage = false
	var back := StyleBoxFlat.new()
	back.bg_color = Color("#a17a50")
	back.set_corner_radius_all(10)
	back.border_color = WOOD_DARK
	back.set_border_width_all(1)
	var fill := StyleBoxFlat.new()
	fill.bg_color = fill_color
	fill.set_corner_radius_all(10)
	fill.border_color = fill_color.lightened(0.2)
	fill.set_border_width_all(1)
	bar.add_theme_stylebox_override("background", back)
	bar.add_theme_stylebox_override("fill", fill)
	return bar


func _bar_row(title: String, bar: ProgressBar) -> Array:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.add_child(_label(title, 12, INK_SOFT))
	row.add_child(bar)
	var value := _label("", 12, INK)
	row.add_child(value)
	return [row, value]


# ---------- 右上：季节 / 日期 / 天气 / 时钟 / 金币 ----------

func _build_info_chips() -> void:
	_header = PanelContainer.new()
	_header.add_theme_stylebox_override("panel", _skin("paper",24))
	_header.custom_minimum_size = Vector2(560,70)
	add_child(_header)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",12)
	_header.add_child(row)
	_season_chip = _label("春季",21)
	_day_chip = _label("第 1 天",19)
	_weather_chip = _label("晴",20)
	_clock_label = _label("08:00",24)
	# 参考图的分段信息药丸：季节/日期/天气/时钟各自成格，配小图标点。
	var palettes: Array[Color] = [Color("#e78fb0"), Color("#e5604c"), Color("#f2c14e"), Color("#8fc3e8")]
	for i in range(4):
		var chip: Label = [_season_chip,_day_chip,_weather_chip,_clock_label][i]
		chip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var box := HBoxContainer.new()
		box.add_theme_constant_override("separation",8)
		var dot := PanelContainer.new()
		var dot_style := StyleBoxFlat.new()
		dot_style.bg_color = palettes[i]
		dot_style.set_corner_radius_all(7)
		dot.add_theme_stylebox_override("panel", dot_style)
		dot.custom_minimum_size = Vector2(14,14)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(dot)
		box.add_child(chip)
		row.add_child(_chip(box))
	_money = PanelContainer.new()
	var money_skin := _skin("money", 18)
	money_skin.set_texture_margin(SIDE_LEFT, 84)
	money_skin.set_texture_margin(SIDE_RIGHT, 24)
	money_skin.set_content_margin(SIDE_LEFT, 84)
	money_skin.set_content_margin(SIDE_RIGHT, 26)
	money_skin.set_content_margin(SIDE_TOP, 12)
	money_skin.set_content_margin(SIDE_BOTTOM, 12)
	_money.add_theme_stylebox_override("panel", money_skin)
	_money.custom_minimum_size = Vector2(210, 62)
	add_child(_money)
	_money.add_child(_coins_label_row())
	get_viewport().size_changed.connect(_layout_header)
	call_deferred("_layout_header")


func _layout_header() -> void:
	var width := get_viewport().get_visible_rect().size.x
	_header.position = Vector2(maxf(380,width-maxf(560,_header.size.x)-24),20)
	_money.position = Vector2(maxf(380,width-maxf(210,_money.size.x)-24),98)


func _chip(content: Control) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _parchment_style(13.0))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(content)
	return panel


func _coins_label_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",12)
	_coins_label = _label("20", 23, Color("#fff0ce"))
	_coins_label.add_theme_color_override("font_shadow_color", Color("#513519"))
	_coins_label.add_theme_constant_override("shadow_offset_y", 1)
	_coins_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_coins_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_coins_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_coins_label)
	return row


# ---------- 底部：快捷栏与情境提示 ----------

func _build_toolbar() -> void:
	var bar := PanelContainer.new()
	_toolbar = bar
	bar.add_theme_stylebox_override("panel",_skin("wood",32))
	bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bar.position.y -= 25.0
	add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",5)
	bar.add_child(row)
	for i in range(Equipment.TOOLS.size()):
		var slot := PanelContainer.new()
		slot.custom_minimum_size = Vector2(73,79)
		slot.tooltip_text = "%d · %s" % [i+1,Equipment.LABELS[i]]
		var style := StyleBoxFlat.new()
		style.bg_color = Color.TRANSPARENT
		style.border_color = Color.TRANSPARENT
		style.set_corner_radius_all(12)
		style.set_border_width_all(2)
		for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
			style.set_content_margin(side, 2)
		slot.add_theme_stylebox_override("panel",style)
		_slot_styles.append(style)
		_slot_panels.append(slot)
		var content := Control.new()
		content.custom_minimum_size = Vector2(69,75)
		content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(content)
		var background := _icon("slot",Vector2(69,75))
		background.size = Vector2(69,75)
		content.add_child(background)
		var icon := _icon(Equipment.TOOLS[i],Vector2(55,54))
		icon.position = Vector2(7,6)
		icon.size = Vector2(55,54)
		content.add_child(icon)
		var text := _label(str(i + 1), 12, INK_SOFT)
		text.position = Vector2(8, 55)
		text.size = Vector2(16, 18)
		content.add_child(text)
		_slots.append(text)
		var count := _label("", 12, INK)
		count.position = Vector2(24, 55)
		count.size = Vector2(37, 18)
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		content.add_child(count)
		_slot_counts.append(count)
		var marker := ColorRect.new()
		marker.color = Color("#e5bc55")
		marker.position = Vector2(22, 72)
		marker.size = Vector2(25, 3)
		marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
		marker.visible = false
		content.add_child(marker)
		_slot_markers.append(marker)
		row.add_child(slot)
	var hint_panel := PanelContainer.new()
	hint_panel.add_theme_stylebox_override("panel",_skin("paper",18))
	hint_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hint_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hint_panel.position.y -= 145.0
	hint_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hint_panel)
	_hint_label = _label("",14,INK)
	_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_panel.add_child(_hint_label)


func _build_toast() -> void:
	_toast_panel = PanelContainer.new()
	_toast_panel.add_theme_stylebox_override("panel", _skin("paper",24))
	_toast_panel.modulate.a = 0.0
	_toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toast_panel)
	_toast = _label("", 22, INK)
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_panel.add_child(_toast)


# ---------- 背包 / 商店 / 矿场 / 升降机面板 ----------

func _framed_panel() -> PanelContainer:
	## 木质厚框 + 羊皮纸内衬的面板。
	var panel := PanelContainer.new()
	var frame := StyleBoxFlat.new()
	frame.bg_color = CREAM
	frame.border_color = WOOD
	frame.set_border_width_all(6)
	frame.set_corner_radius_all(14)
	frame.border_color = WOOD
	frame.shadow_color = Color(0.24, 0.14, 0.07, 0.4)
	frame.shadow_size = 10
	frame.content_margin_left = 18.0
	frame.content_margin_right = 18.0
	frame.content_margin_top = 14.0
	frame.content_margin_bottom = 16.0
	panel.add_theme_stylebox_override("panel", frame)
	return panel


func _build_inventory() -> void:
	_inventory_panel = _framed_panel()
	_inventory_panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_inventory_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_inventory_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_inventory_panel.position.x -= 18.0
	_inventory_panel.visible = false
	add_child(_inventory_panel)
	_inventory_lines = VBoxContainer.new()
	_inventory_lines.add_theme_constant_override("separation", 4)
	_inventory_panel.add_child(_inventory_lines)


func _build_shop() -> void:
	_shop_panel = _framed_panel()
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
			var button := _button("买 %d" % count)
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
	var sell_button := _button("卖出全部")
	sell_button.pressed.connect(func(): sell_requested.emit())
	sell_row.add_child(sell_button)
	column.add_child(sell_row)
	var close := _button("离开（Esc）")
	close.pressed.connect(close_shop)
	column.add_child(close)


func _build_mine_status() -> void:
	_mine_panel = _framed_panel()
	_mine_panel.position = Vector2(18, 118)
	_mine_panel.visible = false
	add_child(_mine_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 7)
	_mine_panel.add_child(column)
	_mine_title = _label("星辉矿场 · 01 / 10", 22)
	column.add_child(_mine_title)
	_mine_objective = _label("挖开裂隙岩石，寻找向下的梯子", 14, INK_SOFT)
	column.add_child(_mine_objective)
	_health_label = _label("生命 100 / 100", 16)
	column.add_child(_health_label)
	_health_bar = ProgressBar.new()
	_health_bar.custom_minimum_size = Vector2(260, 12)
	_health_bar.max_value = GameState.MAX_HEALTH
	_health_bar.show_percentage = false
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0.89, 0.83, 0.70)
	back.set_corner_radius_all(5)
	back.border_color = WOOD_DARK
	back.set_border_width_all(1)
	_health_bar.add_theme_stylebox_override("background", back)
	var fill := StyleBoxFlat.new()
	fill.bg_color = LEAF_GREEN
	fill.set_corner_radius_all(5)
	_health_bar.add_theme_stylebox_override("fill", fill)
	column.add_child(_health_bar)
	_ration_label = _label("Q 口粮 ×3 · 恢复 35 生命", 14, INK_SOFT)
	column.add_child(_ration_label)
	column.add_child(_label("6 镐子   7 短剑   Tab 查看矿物", 13, INK_SOFT))


func _build_travel_panel() -> void:
	_travel_panel = _framed_panel()
	_travel_panel.set_anchors_preset(Control.PRESET_CENTER)
	_travel_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_travel_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_travel_panel.visible = false
	add_child(_travel_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	_travel_panel.add_child(column)
	column.add_child(_label("矿场升降机", 27))
	column.add_child(_label("到达第 5、10 层后，自动接通升降机", 15, INK_SOFT))
	for depth in [0, 1, 5, 10]:
		var button := _button("", 18)
		button.custom_minimum_size = Vector2(375, 47)
		button.pressed.connect(func(): travel_requested.emit(depth))
		column.add_child(button)
		_travel_buttons[depth] = button
	var close := _button("留在这里（Esc）")
	close.pressed.connect(close_travel)
	column.add_child(close)


signal buy_requested(kind: String, count: int)
signal sell_requested


# ---------- 刷新 ----------

func refresh() -> void:
	_coins_label.text = _fmt_number(state.coins)
	update_clock()
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
	_inventory_lines.add_child(HSeparator.new())
	_inventory_lines.add_child(_label("林业物资", 18))
	_inventory_lines.add_child(_label("木材 ×%d     树苗 ×%d" % [state.forestry["wood"], state.forestry["sapling"]], 15))
	_inventory_lines.add_child(_label("8 斧头砍树 · 9 种树苗 · 三个清晨后长大", 13, INK_SOFT))
	_slot_counts[8].text = "×%d" % state.forestry["sapling"]
	_inventory_lines.add_child(HSeparator.new())
	_inventory_lines.add_child(_label("矿石与探索物资", 18))
	for row in range(2):
		var mineral_line := ""
		for index in range(row * 3, row * 3 + 3):
			var kind: String = GameState.MINERAL_ORDER[index]
			mineral_line += "%s ×%d   " % [GameState.MINERALS[kind]["label"], state.minerals[kind]]
		_inventory_lines.add_child(_label(mineral_line, 14))
	_inventory_lines.add_child(_label("口粮 ×%d · Q 食用 · 最深到达 %d / 10 层" % [state.rations, state.deepest_mine_floor], 14, INK_SOFT))
	_inventory_lines.add_child(_label("地表：石料 / 铜矿 / 煤矿 · 铁矿和水晶在地矿中开采", 13, INK_SOFT))
	refresh_health()
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
		_slot_styles[i].bg_color = Color(1.0, 0.93, 0.66, 0.12) if selected else Color.TRANSPARENT
		_slot_styles[i].border_color = Color("#ffd970") if selected else Color.TRANSPARENT
		_slot_styles[i].set_border_width_all(4 if selected else 2)
		_slot_styles[i].shadow_color = Color(0.98, 0.78, 0.22, 0.68) if selected else Color.TRANSPARENT
		_slot_styles[i].shadow_size = 9 if selected else 0
		_slot_markers[i].visible = selected
		if i == 3:
			_slot_counts[i].text = "×%d" % seed_count
			_slot_counts[i].add_theme_color_override("font_color", INK if seed_count > 0 else INK_SOFT)
			_slot_panels[i].tooltip_text = "4 · %s种子 ×%d" % [GameState.crop_label(seed_kind), seed_count]


func toggle_inventory() -> void:
	if shop_open or travel_open or map_open:
		return
	_inventory_panel.visible = not _inventory_panel.visible
	inventory_open = _inventory_panel.visible
	if _inventory_panel.visible:
		refresh()
	panels_changed.emit()


func open_shop() -> void:
	shop_open = true
	_inventory_panel.visible = false
	inventory_open = false
	_shop_panel.visible = true
	refresh()
	panels_changed.emit()


func close_shop() -> void:
	if not shop_open:
		return
	shop_open = false
	_shop_panel.visible = false
	shop_closed.emit()
	panels_changed.emit()


func dismiss_panels() -> void:
	close_shop()
	close_travel()
	if map_open:
		toggle_map()
	if _inventory_panel.visible:
		_inventory_panel.visible = false
	inventory_open = false
	panels_changed.emit()


func modal_open() -> bool:
	return shop_open or map_open or travel_open or inventory_open


func open_mine_travel(current_depth: int) -> void:
	travel_open = true
	_travel_panel.show()
	for depth: int in _travel_buttons:
		var button: Button = _travel_buttons[depth]
		var unlocked: bool = depth <= 1 or state.deepest_mine_floor >= depth
		button.text = "地表 · 山谷矿口" if depth == 0 else "第 %d 层 · %s" % [depth, MineLayout.TITLES[depth - 1]]
		if not unlocked:
			button.text += "（尚未到达）"
		elif depth == current_depth:
			button.text += "（当前）"
		button.disabled = not unlocked or depth == current_depth
	panels_changed.emit()


func close_travel() -> void:
	travel_open = false
	_travel_panel.hide()
	panels_changed.emit()


func set_mine_status(depth: int, title: String = "", objective: String = "") -> void:
	_mine_depth = depth
	_mine_panel.visible = depth > 0 and not map_open
	_mine_title.text = "星辉矿场 · %02d / 10  %s" % [depth, title]
	_mine_objective.text = objective
	_hint_label.add_theme_color_override("font_color", Color("#f1dfb4") if depth > 0 else INK)
	_hint_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8) if depth > 0 else Color.TRANSPARENT)
	_hint_label.add_theme_constant_override("shadow_offset_y", 2 if depth > 0 else 0)
	refresh_health()


func refresh_health() -> void:
	if state == null:
		return
	_health_label.text = "生命 %d / %d" % [state.health, GameState.MAX_HEALTH]
	_health_bar.value = state.health
	(_health_bar.get_theme_stylebox("fill") as StyleBoxFlat).bg_color = HP_RED if state.health < 30 else LEAF_GREEN
	_ration_label.text = "Q 口粮 ×%d · 恢复 35 生命" % state.rations
	_hp_bar.value = state.health
	_hp_value.text = "%d / %d" % [state.health, GameState.MAX_HEALTH]
	_ration_value.text = "口粮 ×%d" % state.rations
	_ration_value.add_theme_color_override("font_color", INK if state.rations > 0 else INK_SOFT)
	_ration_hint.text = "Q 食用" if state.rations > 0 else "已用完"


func _on_money_changed(total: int, _delta: int) -> void:
	if _coins_label != null:
		_coins_label.text = _fmt_number(total)


func _on_day_started_event(_day: int) -> void:
	if state != null:
		update_clock()


# ---------- 导览图 ----------

func setup_navigation(data: Dictionary) -> void:
	_map = TownMap.new()
	add_child(_map)
	_map.configure(data)
	_layout_map()
	get_viewport().size_changed.connect(_layout_map)


func set_navigation(data: Dictionary) -> void:
	_map.configure(data)


func _layout_map() -> void:
	if _map == null:
		return
	_map.visible = map_open
	if map_open:
		_map.set_anchors_preset(Control.PRESET_CENTER)
		var available := get_viewport().get_visible_rect().size
		_map.size = Vector2(clampf(available.x - 80, 160, 920), clampf(available.y - 60, 160, 740))
		_map.position = (available - _map.size) * 0.5
	else:
		_map.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		_map.size = Vector2(236, 220)
		_map.position = Vector2(get_viewport().get_visible_rect().size.x - 254, 16)
	_map.queue_redraw()


func toggle_map() -> void:
	if shop_open or travel_open:
		return
	map_open = not map_open
	_hint_label.visible = not map_open
	_toolbar.visible = not map_open
	_inventory_panel.visible = false
	inventory_open = false
	_mine_panel.visible = _mine_depth > 0 and not map_open
	_map.set_expanded(map_open)
	_layout_map()
	map_toggled.emit(map_open)


func track_position(at: Vector3) -> void:
	if _map != null:
		_map.track(at)


func update_clock() -> void:
	if state == null:
		return
	_clock_label.text = state.clock_text()
	_day_chip.text = "第 %d 天 · %s" % [state.day, state.time.weekday()]
	_season_chip.text = state.time.season()
	_weather_chip.text = state.time.weather_label()


# ---------- 提示与过场 ----------

func show_toast(text: String) -> void:
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast.text = text
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var viewport_size := get_viewport().get_visible_rect().size
	_toast.custom_minimum_size = Vector2(minf(600, viewport_size.x - 140), 0)
	_toast_panel.size = _toast_panel.get_combined_minimum_size()
	_toast_panel.position = Vector2((viewport_size.x - _toast_panel.size.x) * 0.5, 24)
	_toast_tween = create_tween()
	_toast_panel.modulate.a = 1.0
	_toast_tween.tween_interval(1.8)
	_toast_tween.tween_property(_toast_panel, "modulate:a", 0.0, 0.5)


func clear_toast() -> void:
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_panel.modulate.a = 0


func fade_transition(change: Callable, finished: Callable) -> void:
	var tween := create_tween()
	tween.tween_property(_fade, "modulate:a", 1.0, 0.16)
	tween.tween_callback(change)
	tween.tween_interval(0.10)
	tween.tween_property(_fade, "modulate:a", 0.0, 0.22)
	tween.tween_callback(finished)


func fade_sleep(wake_up: Callable) -> void:
	var tween := create_tween()
	tween.tween_property(_fade, "modulate:a", 1.0, 0.55)
	tween.tween_callback(wake_up)
	tween.tween_interval(0.35)
	tween.tween_property(_fade, "modulate:a", 0.0, 0.7)
