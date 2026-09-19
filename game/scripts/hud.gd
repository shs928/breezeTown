extends CanvasLayer
## 界面（Art Bible 第四节版式）：木质面板 + 羊皮纸内衬。
## 左上状态板（头像/生命/口粮）· 右上信息排（季节/日期/天气/时钟/金币）
## · 底部快捷栏与情境提示 · 背包/商店/矿场/升降机面板。

signal shop_closed
signal map_toggled(open: bool)
signal panels_changed
signal travel_requested(depth: int)
signal dialogue_gift_requested(item: String)  # NPC-01：对话面板送礼
signal quest_accept_requested(quest_id: String)  # QUEST-01：对话面板接受委托
signal quest_turnin_requested(quest_id: String)  # QUEST-01：对话面板交付委托

const GameState := preload("res://scripts/game_state.gd")
const AnimalDB := preload("res://scripts/data/animal_db.gd")
const ItemDB := preload("res://scripts/data/item_db.gd")
const FishDB := preload("res://scripts/data/fish_db.gd")
const ForageDB := preload("res://scripts/data/forage_db.gd")
const QuestDB := preload("res://scripts/data/quest_db.gd")
const NpcDB := preload("res://scripts/data/npc_db.gd")
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
const ENERGY_GOLD := Color("#d9a53c")

var state: RefCounted
var shop_open := false
var map_open := false
var travel_open := false
var inventory_open := false
var dialogue_open := false  # NPC-01：对话面板
var chest_open := false  # STORE-01：共享仓库面板
var _map: Control

var _coins_label: Label
var _clock_label: Label
var _season_chip: Label
var _day_chip: Label
var _weather_chip: Label
var _hp_bar: ProgressBar
var _hp_value: Label
var _energy_bar: ProgressBar
var _energy_value: Label
var _ration_value: Label
var _ration_hint: Label
var _status_title: Label
var _hint_label: Label
var _hint_panel: PanelContainer
var _toolbar: PanelContainer
var _fishing_panel: PanelContainer
var _fishing_phase_label: Label
var _fishing_remaining_label: Label
var _fishing_meters: VBoxContainer
var _fishing_tension_bar: ProgressBar
var _fishing_progress_bar: ProgressBar
var _fishing_tension_value: Label
var _fishing_progress_value: Label
var _fishing_phase := "idle"
var _slots: Array[Label] = []
var _slot_counts: Array[Label] = []
var _slot_markers: Array[ColorRect] = []
var _slot_styles: Array[StyleBoxFlat] = []
var _inventory_panel: PanelContainer
var _inventory_lines: VBoxContainer
var _dialogue_panel: PanelContainer
var _dialogue_name: Label
var _dialogue_role: Label
var _dialogue_hearts: Label
var _dialogue_text: Label
var _dialogue_hint: Label
var _dialogue_gift_button: Button
var _dialogue_gift_scroll: ScrollContainer
var _dialogue_gift_lines: VBoxContainer
var _dialogue_quest_button: Button
var _dialogue_quest_id := ""  # 当前按钮对应的委托；空串表示隐藏
var _dialogue_quest_mode := ""  # accept / turnin
var _inventory_tabs: TabContainer
var _fish_catalog_lines: VBoxContainer
var _shop_panel: PanelContainer
var _shop_scroll: ScrollContainer
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
var _upgrade_labels: Dictionary = {}
var _mine_depth := 0
var _header: Control
var _money: Control
var _quest_tracker: PanelContainer
var _quest_tracker_label: Label
var _slot_panels: Array[PanelContainer] = []


func _ready() -> void:
	layer = 10
	_build_status()
	_build_info_chips()
	_build_toolbar()
	_build_fishing_status()
	_build_inventory()
	_build_shop()
	_build_dialogue()
	_build_chest_panel()
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
	panel.size = Vector2(355,138)
	add_child(panel)
	var background := _icon("status", panel.size)
	background.size = panel.size
	panel.add_child(background)
	var title := _label("微风农场 · Lv.1",18)
	title.position = Vector2(104,15)
	title.name = "StatusTitle"
	panel.add_child(title)
	_status_title = title
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
	# FARM-01：体力条（⚡）；工具动作消耗，睡觉回满。
	_energy_bar = _stat_bar(ENERGY_GOLD)
	_energy_bar.max_value = GameState.MAX_ENERGY
	_energy_bar.position = Vector2(119,72)
	_energy_bar.size = Vector2(211,17)
	panel.add_child(_energy_bar)
	_energy_value = _label("100 / 100",12,Color("#fff1d1"))
	_energy_value.position = Vector2(119,72)
	_energy_value.size = Vector2(211,17)
	_energy_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(_energy_value)
	var bolt := _label("⚡",19,Color("#c9942c"))
	bolt.position = Vector2(96,68)
	panel.add_child(bolt)
	var food := _icon("ration", Vector2(26, 25))
	food.position = Vector2(93, 96)
	food.size = Vector2(26, 25)
	panel.add_child(food)
	_ration_value = _label("口粮 ×3", 15, INK)
	_ration_value.position = Vector2(122, 98)
	_ration_value.size = Vector2(123, 24)
	_ration_value.tooltip_text = "每份口粮恢复 35 生命与体力，Q 食用"
	panel.add_child(_ration_value)
	_ration_hint = _label("Q 食用", 12, INK_SOFT)
	_ration_hint.position = Vector2(265, 101)
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
	# QUEST-01：活动委托追踪药丸，挂在金额栏下方。
	_quest_tracker = PanelContainer.new()
	_quest_tracker.add_theme_stylebox_override("panel", _parchment_style(13.0))
	_quest_tracker.visible = false
	_quest_tracker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_quest_tracker)
	_quest_tracker_label = _label("", 15, INK)
	_quest_tracker.add_child(_quest_tracker_label)
	get_viewport().size_changed.connect(_layout_header)
	call_deferred("_layout_header")


func _layout_header() -> void:
	var width := get_viewport().get_visible_rect().size.x
	_header.position = Vector2(maxf(380,width-maxf(560,_header.size.x)-24),20)
	_money.position = Vector2(maxf(380,width-maxf(210,_money.size.x)-24),98)
	_quest_tracker.position = Vector2(maxf(380, width - maxf(210.0, _quest_tracker.size.x) - 24.0), 170.0)


## QUEST-01：追踪药丸显示最老的进行中委托；无进行中委托时隐藏。
func update_quest_tracker() -> void:
	var lines: PackedStringArray = []
	for id in state.quests_accepted:
		if state.quest_active(id):
			var quest: Dictionary = QuestDB.entry(id)
			var progress := ""
			if quest["type"] == "collect":
				progress = " %d/%d" % [state.quest_progress(id), int(quest["count"])]
			lines.append("%s%s" % [quest["label"], progress])
	if lines.is_empty():
		_quest_tracker.visible = false
		return
	_quest_tracker_label.text = "📌 " + " · ".join(lines)
	_quest_tracker.visible = true
	_quest_tracker.reset_size()
	_layout_header()


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
		var shortcut := (i + 1) % 10
		slot.tooltip_text = "%d · %s" % [shortcut,Equipment.LABELS[i]]
		if i == 9:
			slot.tooltip_text += "\n面向水边按 E / 空格 / 鼠标左键抛竿\n咬钩时再按一次提竿；按住收线，松开放线\nEsc 取消钓鱼"
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
		var text := _label(str(shortcut), 12, INK_SOFT)
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
	_hint_panel = hint_panel
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


func _build_fishing_status() -> void:
	_fishing_panel = PanelContainer.new()
	_fishing_panel.name = "FishingStatus"
	var frame := _parchment_style(8.0)
	frame.border_color = WOOD
	frame.set_border_width_all(4)
	frame.content_margin_left = 14.0
	frame.content_margin_right = 14.0
	_fishing_panel.add_theme_stylebox_override("panel", frame)
	_fishing_panel.custom_minimum_size = Vector2(360, 108)
	_fishing_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_fishing_panel.offset_left = -384.0
	_fishing_panel.offset_right = -24.0
	_fishing_panel.offset_top = -296.0
	_fishing_panel.offset_bottom = -188.0
	_fishing_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	_fishing_panel.tooltip_text = "E / 空格 / 鼠标左键抛竿；咬钩时再按一次提竿\n按住收线，松开放线；Esc 取消钓鱼"
	_fishing_panel.hide()
	add_child(_fishing_panel)
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 5)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fishing_panel.add_child(column)
	var heading := HBoxContainer.new()
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(heading)
	_fishing_phase_label = _label("等待咬钩", 17)
	_fishing_phase_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fishing_phase_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heading.add_child(_fishing_phase_label)
	_fishing_remaining_label = _label("", 15, INK_SOFT)
	_fishing_remaining_label.custom_minimum_size.x = 56.0
	_fishing_remaining_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_fishing_remaining_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heading.add_child(_fishing_remaining_label)
	_fishing_meters = VBoxContainer.new()
	_fishing_meters.add_theme_constant_override("separation", 5)
	_fishing_meters.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_fishing_meters)
	for meter_name in ["张力", "收线"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_fishing_meters.add_child(row)
		var title := _label(meter_name, 14, INK_SOFT)
		title.custom_minimum_size.x = 36.0
		title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(title)
		var bar := _stat_bar(ENERGY_GOLD if meter_name == "张力" else LEAF_GREEN)
		bar.max_value = 1.0
		bar.step = 0.001
		bar.value = 0.0
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(bar)
		var value := _label("0%", 13, INK)
		value.custom_minimum_size.x = 38.0
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(value)
		if meter_name == "张力":
			_fishing_tension_bar = bar
			_fishing_tension_value = value
		else:
			_fishing_progress_bar = bar
			_fishing_progress_value = value


func set_fishing_status(phase: String, tension: float = 0.0, progress: float = 0.0, remaining: float = 0.0) -> void:
	_fishing_phase = phase
	var active := phase in ["cast", "bite", "fight"]
	_fishing_panel.visible = active and not modal_open()
	_hint_panel.visible = not active and not map_open
	_fishing_meters.visible = phase == "fight"
	_fishing_remaining_label.visible = phase == "bite"
	match phase:
		"cast":
			_fishing_phase_label.text = "等待咬钩"
		"bite":
			_fishing_phase_label.text = "鱼儿咬钩"
		"fight":
			_fishing_phase_label.text = "与鱼角力" if tension < 0.8 else "鱼线绷紧"
	_fishing_remaining_label.text = "%.1fs" % maxf(0.0, remaining)
	_fishing_tension_bar.value = clampf(tension, 0.0, 1.0)
	_fishing_progress_bar.value = clampf(progress, 0.0, 1.0)
	_fishing_tension_value.text = "%d%%" % roundi(_fishing_tension_bar.value * 100.0)
	_fishing_progress_value.text = "%d%%" % roundi(_fishing_progress_bar.value * 100.0)
	(_fishing_tension_bar.get_theme_stylebox("fill") as StyleBoxFlat).bg_color = HP_RED if tension >= 0.8 else ENERGY_GOLD


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
	_inventory_tabs = TabContainer.new()
	_inventory_tabs.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var tab_bar := _inventory_tabs.get_tab_bar()
	for mode in ["tab_selected", "tab_unselected", "tab_hovered", "tab_disabled"]:
		var tab_style := StyleBoxFlat.new()
		tab_style.bg_color = Color("#f8edcf") if mode == "tab_selected" else Color.TRANSPARENT
		tab_style.border_color = ENERGY_GOLD
		tab_style.border_width_bottom = 3 if mode == "tab_selected" else 0
		tab_style.content_margin_left = 16.0
		tab_style.content_margin_right = 16.0
		tab_style.content_margin_top = 8.0
		tab_style.content_margin_bottom = 8.0
		_inventory_tabs.add_theme_stylebox_override(mode, tab_style)
		tab_bar.add_theme_stylebox_override(mode, tab_style)
	for color_name in ["font_selected_color", "font_unselected_color", "font_hovered_color"]:
		_inventory_tabs.add_theme_color_override(color_name, INK)
		tab_bar.add_theme_color_override(color_name, INK)
	_inventory_tabs.add_theme_font_size_override("font_size", 16)
	tab_bar.add_theme_font_size_override("font_size", 16)
	_inventory_panel.add_child(_inventory_tabs)
	var inventory_scroll := ScrollContainer.new()
	inventory_scroll.name = "物品"
	inventory_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_inventory_tabs.add_child(inventory_scroll)
	_inventory_lines = VBoxContainer.new()
	_inventory_lines.add_theme_constant_override("separation", 4)
	_inventory_lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inventory_scroll.add_child(_inventory_lines)
	var fish_scroll := ScrollContainer.new()
	fish_scroll.name = "鱼类"
	fish_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_inventory_tabs.add_child(fish_scroll)
	_fish_catalog_lines = VBoxContainer.new()
	_fish_catalog_lines.add_theme_constant_override("separation", 8)
	_fish_catalog_lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fish_scroll.add_child(_fish_catalog_lines)
	get_viewport().size_changed.connect(_layout_inventory)
	call_deferred("_layout_inventory")


func _layout_inventory() -> void:
	var available := get_viewport().get_visible_rect().size
	_inventory_panel.size = Vector2(minf(640.0, available.x - 36.0), minf(680.0, available.y - 342.0))
	_inventory_panel.position = Vector2(available.x - _inventory_panel.size.x - 18.0, 178.0)


func _fish_stock_text(kind: String) -> String:
	var silver: int = state.fish_quality["silver"].get(kind, 0)
	var gold: int = state.fish_quality["gold"].get(kind, 0)
	var normal: int = state.fish.get(kind, 0) - silver - gold
	var entries: PackedStringArray = []
	if normal > 0: entries.append("普通 ×%d" % normal)
	if silver > 0: entries.append("银 ×%d" % silver)
	if gold > 0: entries.append("金 ×%d" % gold)
	return "   ".join(entries) if not entries.is_empty() else "暂无鱼获"


func _fishing_skill_text() -> String:
	var needed: int = state.fishing_xp_needed()
	return "钓鱼 Lv.%d  ·  %s" % [state.fishing_level, "%d / %d 经验" % [state.fishing_xp, needed] if needed > 0 else "已精通"]


func _refresh_fish_catalog() -> void:
	for child in _fish_catalog_lines.get_children():
		_fish_catalog_lines.remove_child(child)
		child.free()
	_fish_catalog_lines.add_child(_label(_fishing_skill_text(), 18))
	_fish_catalog_lines.add_child(_label("%s · %s · %s" % [state.time.season(), state.time.weather_label(), state.time.clock_text()], 14, INK_SOFT))
	var context := {"season": state.time.season_key(), "weather": state.time.weather, "hour": state.time.hours}
	for kind in FishDB.ORDER:
		var entry: Dictionary = FishDB.FISH[kind]
		var rarity: String = {"common": "常见", "uncommon": "少见", "rare": "稀有"}.get(entry["rarity"], "")
		var title := _label("%s · %s" % [FishDB.label(kind), rarity], 17)
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_fish_catalog_lines.add_child(title)
		var waters: PackedStringArray = []
		var available := false
		for water: String in entry["waters"]:
			waters.append("湖泊" if water == "lake" else "河流")
			available = available or FishDB.eligible(kind, water, context)
		var seasons: PackedStringArray = []
		for season: String in entry["seasons"]:
			seasons.append(GameState.GameClock.SEASON_NAMES[GameState.GameClock.SEASON_KEYS.find(season)])
		var weathers: PackedStringArray = []
		for weather: String in entry["weathers"]:
			weathers.append(GameState.GameClock.WEATHERS[weather])
		var hours: Array = entry["hours"]
		var all_day := is_zero_approx(float(hours[0])) and is_equal_approx(float(hours[1]), 24.0)
		var period := "全天" if all_day else "%02d:00-%02d:00" % [int(hours[0]), int(hours[1])]
		var condition := _label("%s · %s · %s · %s" % ["、".join(waters), "四季" if seasons.size() == 4 else "、".join(seasons), "所有天气" if weathers.size() == 5 else "、".join(weathers), period], 14, INK_SOFT)
		condition.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_fish_catalog_lines.add_child(condition)
		var stock := _label("%s  ·  %s" % ["此时可钓" if available else "此时无鱼讯", _fish_stock_text(kind)], 14, LEAF_GREEN if available else INK_SOFT)
		stock.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_fish_catalog_lines.add_child(stock)
		var price := FishDB.sell_price(kind)
		_fish_catalog_lines.add_child(_label("售价  普通 %d · 银 %d · 金 %d" % [price, int(floor(price * 1.5)), price * 2], 13, INK_SOFT))
		_fish_catalog_lines.add_child(HSeparator.new())


func _build_shop() -> void:
	_shop_panel = _framed_panel()
	_shop_panel.set_anchors_preset(Control.PRESET_CENTER)
	_shop_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_shop_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_shop_panel.visible = false
	add_child(_shop_panel)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 8)
	_shop_panel.add_child(layout)
	layout.add_child(_label("皮埃尔杂货店", 24))
	layout.add_child(_label("钱货两讫，童叟无欺", 13, INK_SOFT))
	_shop_scroll = ScrollContainer.new()
	_shop_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_shop_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_shop_scroll.follow_focus = true
	layout.add_child(_shop_scroll)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_shop_scroll.add_child(column)
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
	column.add_child(_label("物资", 19))
	for entry in [["feed", "饲料", GameState.FEED_PRICE, 1], ["feed", "饲料", GameState.FEED_PRICE, 5], ["ration", "口粮", GameState.RATION_PRICE, 1], ["ration", "口粮", GameState.RATION_PRICE, 3], ["fertilizer", "肥料", GameState.FERTILIZER_PRICE, 1], ["fertilizer", "肥料", GameState.FERTILIZER_PRICE, 5]]:
		var ware: Array = entry
		var ware_row := HBoxContainer.new()
		ware_row.add_theme_constant_override("separation", 10)
		ware_row.add_child(_label("%s ×%d（%d 币）" % [ware[1], ware[3], ware[2]], 16))
		var ware_button := _button("买 %d" % ware[3])
		var ware_kind: String = ware[0]
		var ware_amount: int = ware[3]
		ware_button.pressed.connect(func(): buy_requested.emit(ware_kind, ware_amount))
		ware_row.add_child(ware_button)
		column.add_child(ware_row)
	column.add_child(HSeparator.new())
	column.add_child(_label("工具升级（金币 + 矿物）", 19))
	for tool_name in ["hoe", "can", "pickaxe", "axe"]:
		var upgrade_row := HBoxContainer.new()
		upgrade_row.add_theme_constant_override("separation", 10)
		var upgrade_info := _label("", 15)
		upgrade_info.name = "Upgrade_" + tool_name
		upgrade_info.custom_minimum_size.x = 285.0
		upgrade_row.add_child(upgrade_info)
		_upgrade_labels[tool_name] = upgrade_info
		var upgrade_button := _button("升级")
		var upgrade_kind: String = "upgrade:" + tool_name
		upgrade_button.pressed.connect(func(): buy_requested.emit(upgrade_kind, 1))
		upgrade_row.add_child(upgrade_button)
		column.add_child(upgrade_row)
	column.add_child(HSeparator.new())
	column.add_child(_label("建筑扩容（谷仓住牛羊 每级4，鸡舍住鸡 每级6）", 19))
	for building_name in ["barn", "coop"]:
		var building_row := HBoxContainer.new()
		building_row.add_theme_constant_override("separation", 10)
		var building_info := _label("", 15)
		building_info.name = "Building_" + building_name
		building_info.custom_minimum_size.x = 285.0
		building_row.add_child(building_info)
		_upgrade_labels[building_name] = building_info
		var building_button := _button("扩容")
		var building_kind: String = "building:" + building_name
		building_button.pressed.connect(func(): buy_requested.emit(building_kind, 1))
		building_row.add_child(building_button)
		column.add_child(building_row)
	column.add_child(HSeparator.new())
	column.add_child(_label("牧场伙伴（入住初始牧场）", 19))
	for kind in GameState.ANIMAL_ORDER:
		var animal_row := HBoxContainer.new()
		animal_row.add_theme_constant_override("separation", 10)
		animal_row.add_child(_label("%s（%d 币）· 每日产出 %s" % [AnimalDB.label(kind), AnimalDB.price(kind), ItemDB.PRODUCTS[AnimalDB.product(kind)]["label"]], 16))
		var animal_button := _button("买 1")
		var animal_kind: String = "animal:" + kind
		animal_button.pressed.connect(func(): buy_requested.emit(animal_kind, 1))
		animal_row.add_child(animal_button)
		column.add_child(animal_row)
	layout.add_child(HSeparator.new())
	var sell_row := HBoxContainer.new()
	var sell_info := _label("", 16)
	sell_info.name = "SellInfo"
	sell_info.custom_minimum_size.x = 250.0
	sell_row.add_child(sell_info)
	var sell_button := _button("卖出全部")
	sell_button.pressed.connect(func(): sell_requested.emit())
	sell_row.add_child(sell_button)
	layout.add_child(sell_row)
	var close := _button("离开（Esc）")
	close.pressed.connect(close_shop)
	layout.add_child(close)
	get_viewport().size_changed.connect(_layout_shop)
	call_deferred("_layout_shop")


func _layout_shop() -> void:
	var available := get_viewport().get_visible_rect().size
	var panel_width := minf(maxf(520.0, _shop_panel.get_combined_minimum_size().x), available.x - 48.0)
	_shop_panel.size = Vector2(panel_width, minf(820.0, available.y - 64.0))
	_shop_panel.position = (available - _shop_panel.size) * 0.5


## ---- STORE-01：农场共享仓库面板（所有宝箱连通；整批存取） ----

var _chest_panel: PanelContainer
var _chest_scroll: ScrollContainer
var _chest_column: VBoxContainer
var _chest_status: Label
var _chest_pickup_button: Button


func _build_chest_panel() -> void:
	_chest_panel = _framed_panel()
	_chest_panel.set_anchors_preset(Control.PRESET_CENTER)
	_chest_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_chest_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_chest_panel.visible = false
	add_child(_chest_panel)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 8)
	_chest_panel.add_child(layout)
	layout.add_child(_label("农场共享仓库", 24))
	_chest_status = _label("所有宝箱连通同一仓库 · 整批存取", 13, INK_SOFT)
	layout.add_child(_chest_status)
	_chest_scroll = ScrollContainer.new()
	_chest_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_chest_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(_chest_scroll)
	_chest_column = VBoxContainer.new()
	_chest_column.add_theme_constant_override("separation", 6)
	_chest_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chest_scroll.add_child(_chest_column)
	layout.add_child(HSeparator.new())
	_chest_pickup_button = _button("收起这个宝箱（箱内无物，仓库内容不受影响）")
	_chest_pickup_button.pressed.connect(func(): chest_pickup_requested.emit())
	layout.add_child(_chest_pickup_button)
	var close := _button("离开（Esc）")
	close.pressed.connect(close_chest)
	layout.add_child(close)
	get_viewport().size_changed.connect(_layout_chest)


func _layout_chest() -> void:
	var available := get_viewport().get_visible_rect().size
	var panel_width := minf(maxf(520.0, _chest_panel.get_combined_minimum_size().x), available.x - 48.0)
	_chest_panel.size = Vector2(panel_width, minf(760.0, available.y - 64.0))
	_chest_panel.position = (available - _chest_panel.size) * 0.5


func open_chest() -> void:
	chest_open = true
	_focus_first_button.call_deferred(_chest_panel)
	_chest_panel.visible = true
	refresh_chest()
	call_deferred("_layout_chest")
	panels_changed.emit()


func close_chest() -> void:
	if not chest_open:
		return
	chest_open = false
	_chest_panel.visible = false
	panels_changed.emit()


func refresh_chest() -> void:
	_discard_armed_item = ""
	for child in _chest_column.get_children():
		child.queue_free()
	var items := _warehouse_row_items()
	if items.is_empty():
		var empty := _label("背包和仓库都空空如也 · 收获或采集后回来存放", 15, INK_SOFT)
		_chest_column.add_child(empty)
	for row_data: Dictionary in items:
		if row_data.has("header"):
			_chest_column.add_child(HSeparator.new())
			_chest_column.add_child(_label(String(row_data["header"]), 17))
			continue
		var item: String = String(row_data["item"])
		var carried: int = state.count_item(item) if state != null else 0
		var stored: int = state.warehouse_count(item) if state != null else 0
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var info := _label("%s · 背包 %d / 仓库 %d" % [ItemDB.label(item), carried, stored], 16)
		info.custom_minimum_size.x = 250.0
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		var deposit := _button("存入")
		deposit.disabled = carried <= 0
		var deposit_item: String = item
		deposit.pressed.connect(func(): warehouse_deposit_requested.emit(deposit_item))
		row.add_child(deposit)
		var withdraw := _button("取出")
		withdraw.disabled = stored <= 0
		var withdraw_item: String = item
		withdraw.pressed.connect(func(): warehouse_withdraw_requested.emit(withdraw_item))
		row.add_child(withdraw)
		var discard := _button("丢弃")
		discard.disabled = stored <= 0
		discard.pressed.connect(func(): _arm_discard(item, discard))
		row.add_child(discard)
		_chest_column.add_child(row)
	if state != null and state.chests_ready > 0:
		_chest_status.text = "仓库 %d/%d 件 · 待放置的宝箱 ×%d · 走到室外空地按 E 放置" % [state.warehouse_total(), state.warehouse_capacity, state.chests_ready]
	else:
		_chest_status.text = "仓库 %d/%d 件 · 所有宝箱连通 · 整批存取" % [state.warehouse_total(), state.warehouse_capacity] if state != null else "所有宝箱连通同一仓库"
	_layout_chest.call_deferred()


var _discard_armed_item := ""


func _arm_discard(item: String, button: Button) -> void:
	## STORE-02：丢弃两步确认——第一次点变为"确认丢弃？"，再点才执行。
	if _discard_armed_item == item:
		_discard_armed_item = ""
		warehouse_discard_requested.emit(item)
	else:
		_discard_armed_item = item
		button.text = "确认丢弃？"


func _warehouse_row_items() -> Array:
	## 背包或仓库中出现的六族物品，按目录顺序分组，带分类标题行。
	var rows: Array = []
	if state == null:
		return rows
	for family: Array in [["收获", state.harvest], ["产品", state.products], ["鱼类", state.fish], ["采集", state.forage], ["矿石", state.minerals], ["林业", state.forestry]]:
		var title: String = family[0]
		var table: Dictionary = family[1]
		var group: Array[String] = []
		for item: String in table:
			if (int(table[item]) > 0 or state.warehouse_count(item) > 0) and group.size() < 40:
				group.append(item)
		if group.is_empty():
			continue
		rows.append({"header": title})
		for item: String in group:
			rows.append({"item": item})
	return rows


func _build_dialogue() -> void:
	## NPC-01：底部中央对话框（木框+羊皮纸），支持闲聊文本与送礼列表切换。
	_dialogue_panel = _framed_panel()
	_dialogue_panel.visible = false
	add_child(_dialogue_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	_dialogue_panel.add_child(column)
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 12)
	column.add_child(heading)
	_dialogue_name = _label("", 21)
	heading.add_child(_dialogue_name)
	_dialogue_role = _label("", 14, INK_SOFT)
	heading.add_child(_dialogue_role)
	_dialogue_hearts = _label("", 16)
	_dialogue_hearts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dialogue_hearts.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	heading.add_child(_dialogue_hearts)
	_dialogue_text = _label("", 16)
	_dialogue_text.custom_minimum_size = Vector2(0, 66)
	column.add_child(_dialogue_text)
	_dialogue_hint = _label("", 13, INK_SOFT)
	column.add_child(_dialogue_hint)
	_dialogue_gift_scroll = ScrollContainer.new()
	_dialogue_gift_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_dialogue_gift_scroll.custom_minimum_size = Vector2(0, 150)
	_dialogue_gift_scroll.visible = false
	column.add_child(_dialogue_gift_scroll)
	_dialogue_gift_lines = VBoxContainer.new()
	_dialogue_gift_lines.add_theme_constant_override("separation", 4)
	_dialogue_gift_lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dialogue_gift_scroll.add_child(_dialogue_gift_lines)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	column.add_child(actions)
	_dialogue_quest_button = _button("")
	_dialogue_quest_button.visible = false
	_dialogue_quest_button.pressed.connect(func():
		if _dialogue_quest_mode == "accept":
			quest_accept_requested.emit(_dialogue_quest_id)
		elif _dialogue_quest_mode == "turnin":
			quest_turnin_requested.emit(_dialogue_quest_id))
	actions.add_child(_dialogue_quest_button)
	_dialogue_gift_button = _button("送礼")
	_dialogue_gift_button.pressed.connect(_toggle_gift_list)
	actions.add_child(_dialogue_gift_button)
	var close := _button("离开（Esc）")
	close.pressed.connect(close_dialogue)
	actions.add_child(close)
	get_viewport().size_changed.connect(_layout_dialogue)
	call_deferred("_layout_dialogue")


func _layout_dialogue() -> void:
	var available := get_viewport().get_visible_rect().size
	_dialogue_panel.size = Vector2(minf(640.0, available.x - 36.0), 0)
	_dialogue_panel.position = Vector2((available.x - _dialogue_panel.size.x) * 0.5, available.y - _dialogue_panel.size.y - 132.0)


func _toggle_gift_list() -> void:
	_dialogue_gift_scroll.visible = not _dialogue_gift_scroll.visible
	_dialogue_gift_button.text = "收起礼物" if _dialogue_gift_scroll.visible else "送礼"


## 打开对话：entries 为 [{id,label,count}] 可送物品；gifted 表示今日已送礼；
## quest_offer/quest_turnin 为 {id,label[,progress,ready]} 时显示对应委托按钮。
func open_dialogue(npc_label: String, npc_role: String, hearts: int, max_hearts: int, text: String, entries: Array, gifted: bool, quest_offer: Dictionary = {}, quest_turnin: Dictionary = {}) -> void:
	dialogue_open = true
	_focus_first_button.call_deferred(_dialogue_panel)
	_dialogue_name.text = npc_label
	_dialogue_role.text = npc_role
	set_dialogue_hearts(hearts, max_hearts)
	_dialogue_text.text = text
	set_dialogue_quest(quest_offer, quest_turnin)
	_dialogue_gift_scroll.visible = false
	_dialogue_gift_button.text = "送礼"
	_dialogue_gift_button.disabled = entries.is_empty() and gifted
	for child in _dialogue_gift_lines.get_children():
		_dialogue_gift_lines.remove_child(child)
		child.free()
	if gifted:
		_dialogue_hint.text = "今天已经送过礼了，明天再来吧"
	elif entries.is_empty():
		_dialogue_hint.text = "背包里没有能送的礼物（作物、鱼获、采集物都可以送）"
	else:
		_dialogue_hint.text = "%d 种物品可以赠送 · 每天限一份" % entries.size()
	for entry: Dictionary in entries:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.add_child(_label("%s ×%d" % [entry["label"], entry["count"]], 15))
		var give := _button("送出")
		var item_id: String = entry["id"]
		give.pressed.connect(func(): dialogue_gift_requested.emit(item_id))
		row.add_child(give)
		_dialogue_gift_lines.add_child(row)
	_dialogue_panel.visible = true
	_layout_dialogue()
	panels_changed.emit()


func set_dialogue_hearts(hearts: int, max_hearts: int) -> void:
	var text := ""
	for index in range(max_hearts):
		text += "♥" if index < hearts else "♡"
	_dialogue_hearts.text = text
	_dialogue_hearts.add_theme_color_override("font_color", Color("#d4547a"))


func set_dialogue_text(text: String) -> void:
	_dialogue_text.text = text


## QUEST-01：配置对话面板的委托按钮（接受/交付/进度提示），无委托时隐藏。
func set_dialogue_quest(quest_offer: Dictionary, quest_turnin: Dictionary) -> void:
	if not quest_offer.is_empty():
		_dialogue_quest_id = String(quest_offer["id"])
		_dialogue_quest_mode = "accept"
		_dialogue_quest_button.text = "接受委托：%s" % quest_offer["label"]
		_dialogue_quest_button.disabled = false
		_dialogue_quest_button.visible = true
	elif not quest_turnin.is_empty():
		_dialogue_quest_id = String(quest_turnin["id"])
		_dialogue_quest_mode = "turnin"
		var ready: bool = bool(quest_turnin.get("ready", true))
		var progress: String = String(quest_turnin.get("progress", ""))
		_dialogue_quest_button.text = "交付：%s" % quest_turnin["label"] + ("（%s）" % progress if not progress.is_empty() else "")
		_dialogue_quest_button.disabled = not ready
		_dialogue_quest_button.visible = true
	else:
		_dialogue_quest_id = ""
		_dialogue_quest_mode = ""
		_dialogue_quest_button.visible = false


func close_dialogue() -> void:
	if not dialogue_open:
		return
	dialogue_open = false
	_dialogue_panel.visible = false
	panels_changed.emit()


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
signal warehouse_deposit_requested(item: String)  # STORE-01：共享仓库存入
signal warehouse_withdraw_requested(item: String)  # STORE-01：共享仓库取出
signal warehouse_discard_requested(item: String)  # STORE-02：丢弃仓库存量（UI 两步确认）
signal chest_pickup_requested  # STORE-01：收起宝箱
signal sell_requested


# ---------- 刷新 ----------

func refresh() -> void:
	_coins_label.text = _fmt_number(state.coins)
	update_clock()
	if _quest_tracker != null:
		update_quest_tracker()
	for child in _inventory_lines.get_children():
		_inventory_lines.remove_child(child)
		child.free()
	_inventory_lines.add_child(_label("背包（Tab 关闭）", 18))
	# QUEST-01：任务区置于背包顶部，进行中委托带进度。
	var quest_lines := 0
	for id in state.quests_accepted:
		if not state.quest_active(id):
			continue
		quest_lines += 1
		var quest: Dictionary = QuestDB.entry(id)
		var progress := ""
		if quest["type"] == "collect":
			progress = "（%d/%d %s）" % [state.quest_progress(id), int(quest["count"]), GameState.ItemDB.label(quest["item"])]
		else:
			progress = "（找 %s 传话）" % NpcDB.label(quest["target"])
		_inventory_lines.add_child(_label("▸ %s%s" % [quest["label"], progress], 14))
	if quest_lines == 0:
		_inventory_lines.add_child(_label("任务  暂无进行中委托 · 和村民聊聊也许有新委托", 13, INK_SOFT))
	if not state.quests_completed.is_empty():
		_inventory_lines.add_child(_label("已完成委托 %d 项" % state.quests_completed.size(), 13, INK_SOFT))
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
	var quality_line := ""
	for kind in GameState.CROP_ORDER:
		var silver: int = state.harvest_quality["silver"][kind]
		var gold: int = state.harvest_quality["gold"][kind]
		if silver > 0 or gold > 0:
			quality_line += "%s 银%d/金%d   " % [GameState.crop_label(kind), silver, gold]
	if quality_line != "":
		_inventory_lines.add_child(_label("品质  " + quality_line, 14, Color("#b8860b")))
	var product_line := "产品  "
	for kind in GameState.PRODUCT_ORDER:
		product_line += "%s ×%d   " % [GameState.product_label(kind), state.products[kind]]
	_inventory_lines.add_child(_label(product_line, 14))
	_inventory_lines.add_child(HSeparator.new())
	_inventory_lines.add_child(_label(_fishing_skill_text(), 18))
	var fish_total := 0
	for kind in FishDB.ORDER:
		var count: int = state.fish.get(kind, 0)
		fish_total += count
		if count > 0:
			_inventory_lines.add_child(_label("%s  %s" % [FishDB.label(kind), _fish_stock_text(kind)], 14))
	if fish_total == 0:
		_inventory_lines.add_child(_label("鱼获  暂无", 14, INK_SOFT))
	_slot_counts[9].text = ("×%d" % fish_total) if fish_total > 0 else ""
	_inventory_lines.add_child(HSeparator.new())
	_inventory_lines.add_child(_label("林业物资", 18))
	_inventory_lines.add_child(_label("木材 ×%d     树苗 ×%d" % [state.forestry["wood"], state.forestry["sapling"]], 15))
	_inventory_lines.add_child(_label("8 斧头砍树 · 9 种树苗 · 三个清晨后长大", 13, INK_SOFT))
	_slot_counts[8].text = "×%d" % state.forestry["sapling"]
	_inventory_lines.add_child(HSeparator.new())
	_inventory_lines.add_child(_label("采集", 18))
	var forage_total := 0
	for kind in ForageDB.ORDER:
		var held: int = state.forage.get(kind, 0)
		if held > 0:
			forage_total += held
			_inventory_lines.add_child(_label("%s ×%d · %d 币" % [ForageDB.label(kind), held, ForageDB.sell_price(kind)], 14))
	if forage_total == 0:
		_inventory_lines.add_child(_label("还没有采集 · 森林/山地/湖畔/海岸可徒手拾取", 13, INK_SOFT))
	_inventory_lines.add_child(HSeparator.new())
	_inventory_lines.add_child(_label("矿石与探索物资", 18))
	for row in range(2):
		var mineral_line := ""
		for index in range(row * 3, row * 3 + 3):
			var kind: String = GameState.MINERAL_ORDER[index]
			mineral_line += "%s ×%d   " % [GameState.MINERALS[kind]["label"], state.minerals[kind]]
		_inventory_lines.add_child(_label(mineral_line, 14))
	_inventory_lines.add_child(_label("口粮 ×%d · Q 食用 · 最深到达 %d / 10 层" % [state.rations, state.deepest_mine_floor], 14, INK_SOFT))
	_inventory_lines.add_child(_label("饲料 ×%d · 对食槽按 E 填充 · 商店有售" % state.feed, 14, INK_SOFT))
	_inventory_lines.add_child(_label("肥料 ×%d · 播种时自动施用（成长更快、品质更好）" % state.fertilizer, 14, INK_SOFT))
	_inventory_lines.add_child(_label("地表：石料 / 铜矿 / 煤矿 · 铁矿和水晶在地矿中开采", 13, INK_SOFT))
	refresh_health()
	if not any:
		_inventory_lines.add_child(_label("（还没有收成，去田里试试）", 13, INK_SOFT))
	for kind in GameState.CROP_ORDER:
		var info: Label = _shop_panel.find_child("Shop_" + kind, true, false)
		info.text = "%s 种子  %d 金币/粒（存 %d）" % [GameState.crop_label(kind), GameState.crop_field(kind, "seed_price"), state.seeds[kind]]
	var sell_info: Label = _shop_panel.find_child("SellInfo", true, false)
	var total: int = state.sale_total()
	sell_info.text = "收获、产品、鱼获与采集物折价 %d 金币" % total
	_refresh_fish_catalog()
	for child in _inventory_lines.get_children():
		if child is Label:
			child.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	call_deferred("_layout_inventory")
	for tool_name in _upgrade_labels:
		var label: Label = _upgrade_labels[tool_name]
		if tool_name in ["barn", "coop"]:
			var b_level: int = int(state.building_levels[tool_name])
			var b_name: String = "谷仓" if tool_name == "barn" else "鸡舍"
			if b_level >= 3:
				label.text = "%s · 已满级（容量 %d）" % [b_name, state.building_capacity(tool_name)]
			else:
				var b_cost: Dictionary = GameState.BUILDING_UPGRADE_COSTS[tool_name]
				label.text = "%s %d 级 → %d 级（%d 币+%d 木+%d 石，容量 %d→%d）" % [
					b_name, b_level, b_level + 1, b_cost["coins"], b_cost["wood"], b_cost["stone"],
					state.building_capacity(tool_name), state.building_capacity(tool_name) + (4 if tool_name == "barn" else 6)]
			continue
		var level: int = state.tool_level(tool_name)
		if level >= 3:
			label.text = "%s · 已满级（体力消耗 ×0.3）" % Equipment.TOOL_LABELS[tool_name]
		else:
			var cost: Dictionary = GameState.TOOL_UPGRADE_COSTS[tool_name][level - 1]
			var mineral_text := ""
			for mineral_key in cost:
				if mineral_key != "coins":
					mineral_text = "+%d%s" % [cost[mineral_key], GameState.MINERALS[mineral_key]["label"]]
			label.text = "%s %d 级 → %d 级（%d 币%s）" % [Equipment.TOOL_LABELS[tool_name], level, level + 1, cost["coins"], mineral_text]


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
	if shop_open or travel_open or map_open or dialogue_open:
		return
	_inventory_panel.visible = not _inventory_panel.visible
	inventory_open = _inventory_panel.visible
	if _inventory_panel.visible:
		refresh()
	panels_changed.emit()


func open_shop() -> void:
	shop_open = true
	_focus_first_button.call_deferred(_shop_panel)
	_inventory_panel.visible = false
	inventory_open = false
	_shop_panel.visible = true
	refresh()
	_shop_scroll.scroll_vertical = 0
	call_deferred("_layout_shop")
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
	close_dialogue()
	close_chest()
	if map_open:
		toggle_map()
	if _inventory_panel.visible:
		_inventory_panel.visible = false
	inventory_open = false
	panels_changed.emit()


func modal_open() -> bool:
	return shop_open or map_open or travel_open or inventory_open or dialogue_open or chest_open


func open_mine_travel(current_depth: int) -> void:
	travel_open = true
	_focus_first_button.call_deferred(_travel_panel)
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
	_energy_bar.max_value = state.energy_max()
	_energy_bar.value = state.energy
	_energy_value.text = "%d / %d" % [int(state.energy), state.energy_max()]
	_status_title.text = "微风农场 · Lv.%d" % state.level
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


func _focus_first_button(panel: Control) -> void:
	## POLISH-02：手柄导航——仅在连接了手柄时把焦点交给第一个可用按钮，
	## 键盘/鼠标用户的 Space 等按键行为保持与旧版一致。
	if Input.get_connected_joypads().is_empty():
		return
	if panel == null or not panel.visible:
		return
	for node in panel.find_children("*", "BaseButton", true, false):
		var button := node as BaseButton
		if button != null and button.visible and not button.disabled:
			button.grab_focus()
			return
