extends SceneTree
## Scene coverage uses real map polygons and ordinary input events.

const SaveManager := preload("res://scripts/core/save_manager.gd")
const FishDB := preload("res://scripts/data/fish_db.gd")
const ItemDB := preload("res://scripts/data/item_db.gd")
const ForestryChecks := preload("res://scripts/tests/forestry_checks.gd")

var game: Node3D
var failures: Array[String] = []
var count := 0
var lake_bank := {}
var river_bank := {}
var capture_path := ""
var capture_size := Vector2i(1600, 1000)


func _initialize() -> void:
	var save_root := OS.get_environment("BREEZETOWN_SAVE_ROOT")
	if save_root.is_empty():
		save_root = ProjectSettings.globalize_path("res://../work/game-data")
	OS.set_environment("BREEZETOWN_SAVE_ROOT", save_root.path_join("fishing-checks-%d" % Time.get_ticks_usec()))
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):
			capture_path = argument.trim_prefix("--capture=")
		elif argument.begins_with("--capture-size="):
			var dimensions := argument.trim_prefix("--capture-size=").split("x")
			if dimensions.size() == 2 and dimensions[0].is_valid_int() and dimensions[1].is_valid_int():
				capture_size = Vector2i(maxi(640, dimensions[0].to_int()), maxi(480, dimensions[1].to_int()))
	create_timer(180).timeout.connect(func(): push_error("FISHING_CHECKS timeout"); quit(1))
	_run.call_deferred()


func _run() -> void:
	root.size = capture_size
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await _frames(5)
	game.set_process(false)
	game.player.set_physics_process(false)
	lake_bank = _find_bank("lake")
	river_bank = _find_bank("river")
	_check("real-lake-bank-found", not lake_bank.is_empty())
	_check("real-river-bank-found", not river_bank.is_empty())
	_check("rod-registered-as-unstackable-tool", ItemDB.item_type("tool_rod") == ItemDB.TYPE_TOOL and ItemDB.item("tool_rod").get("stack") == 1)
	if lake_bank.is_empty() or river_bank.is_empty():
		await _finish()
		return
	_water_targets()
	_cast_guards()
	_cast_conditions()
	await _input_and_catch()
	_failures_and_cancellation()
	_save_and_restore()
	await _sell_and_events()
	await _map_transition()
	_multi_day_rollover()
	await _finish()


func _water_targets() -> void:
	for kind in ["lake", "river"]:
		_place(lake_bank if kind == "lake" else river_bank)
		_check(kind + "-bank-detects-water", game.water_kind_nearby() == kind)
		var target: Dictionary = game._fishing_target()
		_check(kind + "-target-is-wet-and-reachable", _valid_target(target, kind))
		_check(kind + "-cast-starts", game.start_fishing())
		_check(kind + "-bobber-is-on-target", game._bobber != null and game._bobber.global_position.distance_to(target.get("position", Vector3.INF)) < 0.05)
		game._cancel_fishing("")
		game.player.face_point(game.player.global_position - game.player.facing() * 5.0)
		_check(kind + "-facing-land-rejects-cast", game.water_kind_nearby() == "" and not game.start_fishing())
	var sea_bank := _find_bank("sea")
	_check("real-sea-bank-found", not sea_bank.is_empty())
	if not sea_bank.is_empty():
		_place(sea_bank)
		var energy: float = game.state.energy
		_check("sea-is-not-freshwater", game.water_kind_nearby() == "" and not game.start_fishing() and game.state.energy == energy)
	var deck_inside := _find_deck(false)
	_check("water-covered-by-deck-found", not deck_inside.is_empty())
	if not deck_inside.is_empty():
		_place(deck_inside)
		_check("deck-surface-rejects-bobber", game._fishing_target().is_empty() and not game.start_fishing())
	var deck_edge := _find_deck(true)
	_check("freshwater-deck-edge-found", not deck_edge.is_empty())
	if not deck_edge.is_empty():
		_place(deck_edge)
		_check("can-cast-from-deck-into-water", game.start_fishing() and _valid_target(game._fishing_target(), "river"))
		game._cancel_fishing("")


func _cast_guards() -> void:
	_place(lake_bank)
	game._select_tool(0)
	_check("non-rod-cannot-cast", not game.start_fishing() and game._bobber == null)
	game._select_tool(9)
	game.state.energy = 4.0
	_check("tired-cast-rejected-without-charge", not game.start_fishing() and game.state.energy == 4.0 and game._bobber == null)
	game.state.energy = 100.0
	game._transitioning = true
	_check("transition-blocks-cast", not game.start_fishing() and game.state.energy == 100.0)
	game._transitioning = false
	game.hud.toggle_inventory()
	_check("modal-blocks-cast", not game.start_fishing() and game.state.energy == 100.0)
	game.hud.dismiss_panels()
	_check("cast-charges-five-energy", game.start_fishing() and game.state.energy == 95.0)
	var bobber: Node3D = game._bobber
	_check("early-reel-has-no-award-or-second-charge", not game._reel_in() and _fish_total() == 0 and game.state.energy == 95.0 and game._bobber == bobber)
	game.start_fishing()
	_check("repeated-cast-does-not-recharge", game.state.energy == 95.0 and game._bobber == bobber)
	game._cancel_fishing("")


func _cast_conditions() -> void:
	_place(lake_bank)
	var clock_before: Dictionary = game.state.time.to_dict()
	game.state.time.from_dict({"day": 85, "hours": 24.0, "weather": "snow"})
	var matches_context := true
	for attempt in range(8):
		var started: bool = game.start_fishing()
		matches_context = matches_context and started and game._pending_fish == "sardine"
		game._cancel_fishing("")
	_check("winter-snow-midnight-casts-use-restricted-pool", matches_context)
	game.state.time.from_dict(clock_before)


func _input_and_catch() -> void:
	_place(lake_bank)
	game.state.time.from_dict({"day": 85, "hours": 24.0, "weather": "snow"})
	game.state.fishing_level = 5
	game.state.fishing_xp = 490
	var added: Array = []
	var on_added := func(kind: String, amount: int): added.append([kind, amount])
	EventBus.instance().item_added.connect(on_added)
	game._select_tool(0)
	_press(KEY_0)
	_check("zero-equips-visible-rod", game.tool_index == 9 and game.player.equipped_tool == "rod" and game.player._held.get_meta("tool") == "rod")
	_press(KEY_E)
	_check("e-casts-at-real-bank", game.fishing_state == "cast")
	var caught_kind: String = game._pending_fish
	_check("cast-fish-is-eligible-in-snapshot-context", caught_kind == "sardine" and FishDB.eligible(caught_kind, "lake", {"season": "winter", "weather": "snow", "hour": 24.0}))
	game.state.time.from_dict({"day": 29, "hours": 10.0, "weather": "sunny"})
	game._tick_fishing(float(game._fishing.remaining) + 0.001)
	_check("cast-advances-to-bite", game.fishing_state == "bite")
	_check("skill-level-lengthens-bite-window", game._fishing.remaining > 1.5)
	_check("midcast-season-weather-time-change-keeps-fish", game._pending_fish == caught_kind)
	var fish_before: int = _fish_total()
	var xp_before: int = game.state.xp
	_press(KEY_SPACE)
	_check("space-hooks-without-instant-fish", game.fishing_state == "fight" and _fish_total() == fish_before)
	_check("hooking-does-not-emit-item-added", added.is_empty())
	_check("hooking-does-not-award-skill-xp", game.state.fishing_level == 5 and game.state.fishing_xp == 490)
	var energy: float = game.state.energy
	var progress: float = game._fishing.progress
	_key(KEY_E, true)
	game._process(0.20)
	_key(KEY_E, false)
	_check("held-e-reels-through-normal-process", game.fishing_state == "fight" and game._fishing.progress > progress)
	progress = game._fishing.progress
	_key(KEY_SPACE, true)
	game._process(0.20)
	_key(KEY_SPACE, false)
	_check("held-space-reels-through-normal-process", game.fishing_state == "fight" and game._fishing.progress > progress)
	progress = game._fishing.progress
	_mouse(true)
	game._process(0.20)
	_mouse(false)
	_check("held-left-mouse-reels-through-normal-process", game.fishing_state == "fight" and game._fishing.progress > progress)
	var tension: float = game._fishing.tension
	game._process(0.20)
	_check("released-input-relaxes-tension", game.fishing_state == "fight" and game._fishing.tension < tension)
	_check("controlled-reeling-records-high-control-score", game._fishing.control_score() >= 0.98)
	if not capture_path.is_empty():
		await _capture_fight()
	for step in range(2400):
		if game.fishing_state != "fight":
			break
		game._tick_fishing(1.0 / 60.0, game._fishing.tension < 0.55)
	_check("managed-fight-awards-one-fish", game.fishing_state == "idle" and _fish_total() == fish_before + 1 and game.state.fish[caught_kind] == 1)
	_check("caught-fish-emits-one-item-added", added == [[caught_kind, 1]])
	_check("successful-fish-awards-xp-once", game.state.xp == xp_before + 4 * FishDB.difficulty(caught_kind))
	_check("clean-catch-at-skill-five-awards-gold", game.state.fish_quality["gold"][caught_kind] == 1 and game.state.fish_quality["silver"][caught_kind] == 0)
	_check("successful-fish-awards-skill-xp-and-level-once", game.state.fishing_level == 6 and game.state.fishing_xp == 2)
	_check("fight-costs-no-extra-energy", game.state.energy == energy)
	_check("successful-catch-removes-bobber", game._bobber == null and game._pending_fish == "")
	game._tick_fishing(2.0, true)
	game._reel_in()
	_check("finished-catch-cannot-double-award", _fish_total() == fish_before + 1)
	_check("finished-catch-cannot-repeat-item-added", added == [[caught_kind, 1]])
	_check("finished-catch-cannot-repeat-grade-or-skill-xp", game.state.fishing_level == 6 and game.state.fishing_xp == 2 and game.state.fish_quality["gold"][caught_kind] == 1)
	EventBus.instance().item_added.disconnect(on_added)
	_place(river_bank)
	_press(KEY_SPACE)
	_check("space-also-casts", game.fishing_state == "cast")
	_press(KEY_ESCAPE)
	_check("escape-cancels-cast", game.fishing_state == "idle" and game._bobber == null)
	_press(KEY_E)
	_press(KEY_TAB)
	_check("inventory-cancels-immediately", game.hud.inventory_open and game.fishing_state == "idle" and game._bobber == null)
	_press(KEY_ESCAPE)
	_check("escape-closes-inventory", not game.hud.modal_open())


func _failures_and_cancellation() -> void:
	var fish_before: int = _fish_total()
	var xp_before: int = game.state.xp
	var skill_before := Vector2i(game.state.fishing_level, game.state.fishing_xp)
	var quality_before: Dictionary = game.state.fish_quality.duplicate(true)
	_cast_to_bite()
	game._tick_fishing(float(game._fishing.remaining) + 0.001)
	_check("missed-bite-cleans-up", game.fishing_state == "idle" and game._bobber == null)
	_cast_to_bite()
	game._reel_in()
	for step in range(2400):
		if game.fishing_state != "fight":
			break
		game._tick_fishing(1.0 / 60.0, true)
	_check("constant-reel-can-break-line", game.fishing_state == "idle" and game._bobber == null)
	_cast_to_bite()
	game._reel_in()
	for step in range(2400):
		if game.fishing_state != "fight":
			break
		game._tick_fishing(1.0 / 60.0, false)
	_check("never-reeling-loses-fish", game.fishing_state == "idle" and game._bobber == null)
	_check("failed-attempts-award-neither-fish-nor-xp", _fish_total() == fish_before and game.state.xp == xp_before)
	_check("failed-attempts-award-neither-grade-nor-skill-xp", _same_quality(game.state.fish_quality, quality_before) and Vector2i(game.state.fishing_level, game.state.fishing_xp) == skill_before)
	_place(lake_bank)
	game.start_fishing()
	game.player.global_position -= game.player.facing() * 0.8
	game._tick_fishing(0.01)
	_check("walking-away-cancels-cast", game.fishing_state == "idle" and game._bobber == null)
	_place(lake_bank)
	game.start_fishing()
	game.player.face_point(game.player.global_position - game.player.facing() * 2.0)
	game._tick_fishing(0.01)
	_check("turning-away-cancels-cast", game.fishing_state == "idle" and game._bobber == null)
	_place(lake_bank)
	game.start_fishing()
	game._select_tool(0)
	_check("changing-tool-cancels-immediately", game.fishing_state == "idle" and game._bobber == null)
	_place(lake_bank)
	game.start_fishing()
	game.state.clock = 25.999
	var day: int = game.state.day
	game._process(1.0)
	_check("natural-day-rollover-cancels-cast", game.state.day == day + 1 and game.fishing_state == "idle" and game._bobber == null)
	_place(lake_bank)
	game.start_fishing()
	game._do_sleep()
	_check("sleep-cancels-cast", game.fishing_state == "idle" and game._bobber == null)
	_check("interrupted-casts-award-no-grade-or-skill-xp", _same_quality(game.state.fish_quality, quality_before) and Vector2i(game.state.fishing_level, game.state.fishing_xp) == skill_before)


func _save_and_restore() -> void:
	_place(lake_bank)
	game.state.add_fish("carp", 2, "silver")
	game.state.add_fish("koi", 1, "gold")
	var expected: Dictionary = game.state.fish.duplicate(true)
	var quality_expected: Dictionary = game.state.fish_quality.duplicate(true)
	var skill_expected := Vector2i(game.state.fishing_level, game.state.fishing_xp)
	_check("fish-exist-before-save", _fish_total() > 0)
	game.state.from_dict(game.state.to_dict())
	_check("in-memory-roundtrip-preserves-fish", _same_fish(game.state.fish, expected))
	_check("in-memory-roundtrip-preserves-grade-and-skill", _same_quality(game.state.fish_quality, quality_expected) and Vector2i(game.state.fishing_level, game.state.fishing_xp) == skill_expected)
	var saved_result: Dictionary = SaveManager.save_game(1, game._save_payload())
	var saved: Dictionary = SaveManager.load_game(1)
	_check("fish-save-written-and-readable", saved_result.get("ok", false) and saved.get("ok", false) and _same_fish(saved.get("economy", {}).get("fish", {}), expected))
	_check("fish-save-includes-grade-and-skill", _same_quality(saved.get("economy", {}).get("fish_quality", {}), quality_expected) and int(saved["economy"].get("fishing_level", 0)) == skill_expected.x and int(saved["economy"].get("fishing_xp", -1)) == skill_expected.y)
	game.start_fishing()
	var bobber: Node3D = game._bobber
	game._apply_load({"ok": false, "error": "intentional test failure"})
	_check("failed-load-preserves-cast", game.fishing_state == "cast" and game._bobber == bobber)
	var foreign := saved.duplicate(true)
	foreign["map"]["id"] = "unrelated-test-map"
	game._apply_load(foreign)
	_check("foreign-map-load-preserves-cast", game.fishing_state == "cast" and game._bobber == bobber)
	game.state.add_fish("koi")
	game.state.fishing_level = 1
	game.state.fishing_xp = 0
	game._apply_load(saved)
	_check("successful-load-restores-fish-and-cancels-cast", _same_fish(game.state.fish, expected) and game.fishing_state == "idle" and game._bobber == null)
	_check("successful-load-restores-grade-and-skill", _same_quality(game.state.fish_quality, quality_expected) and Vector2i(game.state.fishing_level, game.state.fishing_xp) == skill_expected)
	var legacy := saved.duplicate(true)
	for key in ["fish_quality", "fishing_level", "fishing_xp"]:
		legacy["economy"].erase(key)
	game._apply_load(legacy)
	_check("legacy-fish-save-resets-grade-and-skill", _same_fish(game.state.fish, expected) and _grade_total() == 0 and game.state.fishing_level == 1 and game.state.fishing_xp == 0)
	legacy["economy"].erase("fish")
	game._apply_load(legacy)
	_check("legacy-save-without-fish-clears-old-counts", _fish_total() == 0 and game.state.fish.size() == FishDB.ORDER.size())
	game._apply_load(saved)
	_check("fish-save-can-be-reloaded-repeatedly", _same_fish(game.state.fish, expected))
	_check("grade-and-skill-can-be-reloaded-repeatedly", _same_quality(game.state.fish_quality, quality_expected) and Vector2i(game.state.fishing_level, game.state.fishing_xp) == skill_expected)


func _map_transition() -> void:
	_place(lake_bank)
	game.start_fishing()
	game._travel_to(1)
	_check("travel-cancels-before-fade", game.fishing_state == "idle" and game._bobber == null)
	for frame in range(180):
		if not game._transitioning:
			break
		await _frames(1)
	_check("mine-transition-completes", game.mine_depth == 1 and not game._transitioning)
	game._select_tool(9)
	var energy: float = game.state.energy
	_check("mine-cannot-cast", not game.start_fishing() and game._bobber == null and game.state.energy == energy)
	game._travel_to(0)
	for frame in range(180):
		if not game._transitioning:
			break
		await _frames(1)
	_check("return-to-surface-completes", game.mine_depth == 0 and not game._transitioning)


func _multi_day_rollover() -> void:
	var at := ForestryChecks.find_clear(game)
	var sapling: Node3D = game.surface_resources.plant_sapling(at) if is_finite(at.x) else null
	_check("multi-day-sapling-fixture-created", sapling != null and sapling.stage == 0)
	game.state.time.from_dict({"day": 28, "hours": 25.9, "weather": "cloudy"})
	game.surface_resources.last_rollover_day = 28
	var days: Array[int] = []
	var stages: Array[int] = []
	var seasons: Array[String] = []
	var weathers: Array[String] = []
	var on_day := func(day: int):
		days.append(day)
		if is_instance_valid(sapling):
			stages.append(sapling.stage)
	var on_season := func(season: String): seasons.append(season)
	var on_weather := func(weather: String): weathers.append(weather)
	EventBus.instance().day_started.connect(on_day)
	EventBus.instance().season_changed.connect(on_season)
	EventBus.instance().weather_changed.connect(on_weather)
	game._advance_world_time(20.2)
	_check("multi-day-jump-emits-each-day-in-order", days == [29, 30])
	_check("multi-day-jump-settles-sapling-growth-each-day", stages == [1, 2] and sapling != null and sapling.stage == 2)
	_check("multi-day-jump-keeps-final-calendar-time", game.state.day == 30 and is_equal_approx(game.state.time.hours, 6.1))
	_check("multi-day-jump-crosses-season-once", game.state.time.season_key() == "summer" and seasons == [game.state.time.season()])
	_check("multi-day-jump-applies-each-daily-weather", weathers == ["sunny", "cloudy"] and game.state.time.weather == "cloudy")
	EventBus.instance().day_started.disconnect(on_day)
	EventBus.instance().season_changed.disconnect(on_season)
	EventBus.instance().weather_changed.disconnect(on_weather)


func _sell_and_events() -> void:
	# Independent prices: sardines 42, koi 336, quality radishes 48, milk 28.
	for kind in game.state.harvest:
		game.state.harvest[kind] = 0
		game.state.harvest_quality["silver"][kind] = 0
		game.state.harvest_quality["gold"][kind] = 0
	for kind in game.state.products:
		game.state.products[kind] = 0
	for kind in game.state.fish:
		game.state.fish[kind] = 0
		game.state.fish_quality["silver"][kind] = 0
		game.state.fish_quality["gold"][kind] = 0
	game.state.add_fish("sardine", 2)
	game.state.add_fish("sardine", 2, "silver")
	game.state.add_fish("sardine", 1, "gold")
	game.state.add_fish("koi", 1)
	game.state.add_fish("koi", 3, "silver")
	game.state.add_fish("koi", 1, "gold")
	game.state.harvest["radish"] = 4
	game.state.harvest_quality["silver"]["radish"] = 2
	game.state.harvest_quality["gold"]["radish"] = 1
	game.state.products["milk"] = 2
	var expected_removed: Array = [["radish", 4], ["milk", 2], ["sardine", 5], ["koi", 5]]
	var expected_earned := 454
	_check("mixed-fish-grade-prices-and-rounding", game.state.fish_sale_value("sardine") == 42 and game.state.fish_sale_value("koi") == 336)
	_check("combined-sale-total-includes-crop-and-fish-grades", game.state.sale_total() == expected_earned)
	var coins_before: int = game.state.coins
	var removed: Array = []
	var money: Array = []
	var on_removed := func(kind: String, amount: int): removed.append([kind, amount])
	var on_money := func(total: int, delta: int): money.append([total, delta])
	EventBus.instance().item_removed.connect(on_removed)
	EventBus.instance().money_changed.connect(on_money)
	game.hud.toggle_inventory()
	game.hud._inventory_tabs.current_tab = 1
	game.hud.clear_toast()
	await _frames(2)
	var stock_text := _label_text(game.hud._inventory_lines)
	var catalog_text := _label_text(game.hud._fish_catalog_lines)
	_check("inventory-shows-earned-fishing-level-and-xp", stock_text.contains("Lv.6") and stock_text.contains("2 / 600"))
	_check("inventory-shows-mixed-grade-fish-stocks", stock_text.contains(game.hud._fish_stock_text("sardine")) and stock_text.contains(game.hud._fish_stock_text("koi")))
	var all_species_visible := true
	for kind in FishDB.ORDER:
		all_species_visible = all_species_visible and catalog_text.contains(FishDB.label(kind))
	_check("fish-catalog-includes-all-six-species-and-skill", all_species_visible and catalog_text.contains("Lv.6") and catalog_text.contains("2 / 600"))
	_check("inventory-panel-fits-viewport", root.get_visible_rect().encloses(game.hud._inventory_panel.get_global_rect()))
	if not capture_path.is_empty() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var result := root.get_texture().get_image().save_png(capture_path.get_basename() + "-inventory.png")
		_check("graded-fish-and-skill-inventory-screenshot-written", result == OK)
	game.hud.open_shop()
	await _frames(2)
	var sell_info: Label = game.hud._shop_panel.find_child("SellInfo", true, false)
	_check("shop-estimate-includes-entire-fish-value", sell_info.is_visible_in_tree() and sell_info.text.contains(" %d " % expected_earned))
	_check("shop-estimate-stays-within-panel", game.hud._shop_panel.get_global_rect().encloses(sell_info.get_global_rect()))
	if not capture_path.is_empty() and DisplayServer.get_name() != "headless":
		game.hud.clear_toast()
		await _frames(2)
		await RenderingServer.frame_post_draw
		var result := root.get_texture().get_image().save_png(capture_path.get_basename() + "-shop.png")
		_check("shop-screenshot-written", result == OK)
	game.hud.sell_requested.emit()
	_check("shop-sale-converts-all-fish-to-coins", _fish_total() == 0 and game.state.coins == coins_before + expected_earned)
	_check("shop-sale-clears-fish-grades", _grade_total() == 0)
	_check("sale-emits-one-removal-per-fish-stack", removed == expected_removed)
	_check("sale-emits-matching-money-change-once", money == [[coins_before + expected_earned, expected_earned]])
	_check("shop-estimate-clears-after-sale", sell_info.text.contains(" 0 "))
	game.hud.sell_requested.emit()
	_check("second-sale-earns-zero", _fish_total() == 0 and game.state.coins == coins_before + expected_earned)
	_check("second-sale-emits-no-extra-economic-events", removed == expected_removed and money == [[coins_before + expected_earned, expected_earned]])
	EventBus.instance().item_removed.disconnect(on_removed)
	EventBus.instance().money_changed.disconnect(on_money)
	game.hud.close_shop()


func _find_bank(kind: String) -> Dictionary:
	for water: Dictionary in game.tiles.map.waters:
		if water.get("kind", "") != kind:
			continue
		var polygon: PackedVector2Array = water["polygon"]
		for index in range(polygon.size()):
			var a := polygon[index]
			var b := polygon[(index + 1) % polygon.size()]
			var along := (b - a).normalized()
			for fraction in [0.5, 0.25, 0.75]:
				var edge := a.lerp(b, fraction)
				for side in [-1.0, 1.0]:
					var normal: Vector2 = Vector2(-along.y, along.x) * side
					var stand: Vector2 = edge + normal * 1.2
					var target: Vector2 = edge - normal * 1.4
					if game.tiles.map.is_walkable(stand, 0.4) and not game.tiles.map.is_water(stand) and Geometry2D.is_point_in_polygon(target, polygon) and not game.tiles.map.on_deck(target):
						return {"stand": stand, "target": target}
	return {}


func _find_deck(outward: bool) -> Dictionary:
	for deck: Dictionary in game.tiles.map.bridges + game.tiles.map.docks:
		var rect: Rect2 = deck["rect"]
		var center := rect.get_center()
		for direction in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
			var half_extent := rect.size.x * 0.5 if direction.x != 0 else rect.size.y * 0.5
			var stand: Vector2 = center + direction * (half_extent - 0.8) if outward else center
			var target: Vector2 = stand + direction * 2.6
			if not game.tiles.map.is_walkable(stand, 0.4):
				continue
			if outward and game.tiles.map.on_deck(target):
				continue
			if not outward and not rect.grow(-0.1).has_point(stand + direction * 4.4):
				continue
			for water: Dictionary in game.tiles.map.waters:
				if water.get("kind", "") == "river" and Geometry2D.is_point_in_polygon(target, water["polygon"]):
					return {"stand": stand, "target": target}
	return {}


func _valid_target(target: Dictionary, kind: String) -> bool:
	if target.is_empty() or target.get("kind", "") != kind:
		return false
	var position: Vector3 = target["position"]
	var flat := Vector2(position.x, position.z)
	var player_flat := Vector2(game.player.global_position.x, game.player.global_position.z)
	if flat.distance_to(player_flat) > 4.401 or game.tiles.map.on_deck(flat):
		return false
	for water: Dictionary in game.tiles.map.waters:
		if water.get("kind", "") == kind and Geometry2D.is_point_in_polygon(flat, water["polygon"]):
			return true
	return false


func _place(spot: Dictionary) -> void:
	game._cancel_fishing("")
	game.hud.dismiss_panels()
	game.state.energy = 100.0
	game._select_tool(9)
	var stand: Vector2 = spot["stand"]
	var target: Vector2 = spot["target"]
	game.player.teleport(Vector3(stand.x, 0, stand.y))
	game.player.face_point(Vector3(target.x, 0, target.y))
	game._update_targeting()


func _cast_to_bite() -> void:
	_place(lake_bank)
	game.start_fishing()
	game._tick_fishing(float(game._fishing.remaining) + 0.001)


func _fish_total() -> int:
	var result := 0
	for amount in game.state.fish.values():
		result += int(amount)
	return result


func _same_fish(actual: Dictionary, expected: Dictionary) -> bool:
	if actual.size() != expected.size():
		return false
	for kind in expected:
		if not actual.has(kind) or int(actual[kind]) != int(expected[kind]):
			return false
	return true


func _same_quality(actual: Dictionary, expected: Dictionary) -> bool:
	return actual.size() == 2 and _same_fish(actual.get("silver", {}), expected["silver"]) and _same_fish(actual.get("gold", {}), expected["gold"])


func _grade_total() -> int:
	var result := 0
	for grade in ["silver", "gold"]:
		for amount in game.state.fish_quality[grade].values():
			result += int(amount)
	return result


func _label_text(container: Node) -> String:
	var result := ""
	for child in container.get_children():
		if child is Label:
			result += child.text + "\n"
	return result


func _capture_fight() -> void:
	if DisplayServer.get_name() == "headless":
		_check("capture-requires-rendering", false)
		return
	_check("capture-is-fight-phase", game.fishing_state == "fight")
	for step in range(54):
		game._tick_fishing(1.0 / 60.0, game._fishing.tension < 0.55)
	game.player.zoom_index = 1
	game.player.snap_camera()
	game.state.clock = 10.0
	game._apply_daylight()
	game.hud.clear_toast()
	await _frames(3)
	await RenderingServer.frame_post_draw
	var bobber_screen: Vector2 = game._camera.unproject_position(game._bobber.global_position)
	_check("fishing-panel-does-not-obscure-bobber", not game.hud._fishing_panel.get_global_rect().has_point(bobber_screen))
	DirAccess.make_dir_recursive_absolute(capture_path.get_base_dir())
	var result := root.get_texture().get_image().save_png(capture_path)
	_check("fight-screenshot-written", result == OK)


func _press(code: Key) -> void:
	_key(code, true)
	_key(code, false)


func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _mouse(pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = game._camera.unproject_position(game._bobber.global_position)
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _frames(amount: int) -> void:
	for frame in range(amount):
		await physics_frame
	await process_frame


func _check(label: String, result: bool) -> void:
	count += 1
	print("FISHING %s %s" % [label, "OK" if result else "FAIL"])
	if not result:
		failures.append(label)


func _finish() -> void:
	print("FISHING_RESULT %s %d checks" % ["PASS" if failures.is_empty() else "FAIL " + ",".join(failures), count])
	game.queue_free()
	await process_frame
	await process_frame
	quit(0 if failures.is_empty() else 1)
