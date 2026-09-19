extends SceneTree

const Hud := preload("res://scripts/hud.gd")
const GameState := preload("res://scripts/game_state.gd")
var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for dimensions in [Vector2i(1600, 1000), Vector2i(1280, 800)]:
		root.size = dimensions
		root.content_scale_size = dimensions
		var hud := Hud.new()
		hud.state = GameState.new()
		root.add_child(hud)
		hud.open_shop()
		for frame in range(5):
			await process_frame
		var panel: PanelContainer = hud._shop_panel
		var buttons: Array[Node] = panel.find_children("*", "Button", true, false)
		var viewport := Rect2(Vector2.ZERO, Vector2(dimensions))
		_check("shop-contained-%s" % dimensions, viewport.encloses(panel.get_global_rect()))
		print("SHOP_LAYOUT viewport=%s panel=%s" % [dimensions, panel.get_global_rect()])
		for button: Button in buttons:
			if button.text in ["卖出全部", "离开（Esc）"]:
				print("SHOP_ACTION %s rect=%s" % [button.text, button.get_global_rect()])
				_check("footer-contained-%s-%s" % [dimensions, button.text], viewport.encloses(button.get_global_rect()))
			else:
				button.grab_focus()
				for frame in range(2):
					await process_frame
				_check("catalog-focus-visible-%s-%s" % [dimensions, button.text], hud._shop_scroll.get_global_rect().encloses(button.get_global_rect()))
		hud.close_shop()
		hud.set_fishing_status("bite", 0.0, 0.0, 1.2)
		await process_frame
		_check("bite-contained-%s" % dimensions, viewport.encloses(hud._fishing_panel.get_global_rect()))
		_check("bite-timer-%s" % dimensions, hud._fishing_remaining_label.text == "1.2s")
		hud.set_fishing_status("fight", 0.87, 0.64)
		await process_frame
		_check("fight-contained-%s" % dimensions, viewport.encloses(hud._fishing_panel.get_global_rect()))
		_check("fight-values-%s" % dimensions, is_equal_approx(hud._fishing_tension_bar.value, 0.87) and is_equal_approx(hud._fishing_progress_bar.value, 0.64))
		hud.free()
	print("HUD_LAYOUT_RESULT %s %d checks" % ["PASS" if failures == 0 else "FAIL", checks])
	quit(0 if failures == 0 else 1)

func _check(label: String, condition: bool) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)
