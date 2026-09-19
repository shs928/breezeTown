extends SceneTree

const Hud := preload("res://scripts/hud.gd")
const GameState := preload("res://scripts/game_state.gd")
var count := 0
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for dimensions in [Vector2i(1600, 1000), Vector2i(1280, 800)]:
		root.size = dimensions
		root.content_scale_size = dimensions
		var hud := Hud.new()
		hud.state = GameState.new()
		hud.state.fishing_level = 6
		hud.state.fishing_xp = 2
		for kind in GameState.FishDB.ORDER:
			hud.state.add_fish(kind, 3, "gold")
			hud.state.add_fish(kind, 2, "silver")
			hud.state.add_fish(kind, 4)
		root.add_child(hud)
		hud.toggle_inventory()
		await _frames()
		var viewport := Rect2(Vector2.ZERO, Vector2(dimensions))
		for tab in range(2):
			hud._inventory_tabs.current_tab = tab
			await _frames()
			var panel: Rect2 = hud._inventory_panel.get_global_rect()
			_check("inventory-contained-%s-%d" % [dimensions, tab], viewport.encloses(panel))
			_check("header-clear-%s-%d" % [dimensions, tab], not panel.intersects(hud._money.get_global_rect()) and not panel.intersects(hud._header.get_global_rect()))
			_check("toolbar-clear-%s-%d" % [dimensions, tab], not panel.intersects(hud._toolbar.get_global_rect()))
			var scroll: ScrollContainer = hud._inventory_tabs.get_child(tab)
			scroll.scroll_vertical = 100000
			await _frames()
			var lines: VBoxContainer = scroll.get_child(0)
			var last_row: Control = lines.get_child(lines.get_child_count() - 1)
			_check("last-row-reachable-%s-%d" % [dimensions, tab], scroll.get_global_rect().grow(1).encloses(last_row.get_global_rect()))
			var no_overflow := true
			for row in lines.get_children():
				if row is Label:
					no_overflow = no_overflow and row.size.x <= scroll.size.x
			_check("labels-fit-width-%s-%d" % [dimensions, tab], no_overflow)
		var tab_bar: TabBar = hud._inventory_tabs.get_tab_bar()
		_check("tabs-use-paper-theme-%s" % dimensions, tab_bar.get_theme_stylebox("tab_selected").bg_color == Color("#f8edcf") and tab_bar.get_theme_color("font_selected_color") == Hud.INK)
		hud.free()
	print("FISHING_HUD_RESULT %s %d checks" % ["PASS" if failures.is_empty() else "FAIL " + ",".join(failures), count])
	quit(0 if failures.is_empty() else 1)


func _frames() -> void:
	for frame in range(4):
		await process_frame


func _check(label: String, condition: bool) -> void:
	count += 1
	if not condition:
		failures.append(label)
		push_error(label)
