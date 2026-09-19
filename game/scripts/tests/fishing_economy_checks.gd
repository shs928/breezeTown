extends SceneTree

const GameState := preload("res://scripts/game_state.gd")
const FishDB := preload("res://scripts/data/fish_db.gd")
const SaveManager := preload("res://scripts/core/save_manager.gd")

var failures: Array[String] = []
var checks := 0
var added: Array = []
var removed: Array = []
var money: Array = []
var saved_paths: Array = []


func _initialize() -> void:
	var save_root := ProjectSettings.globalize_path("res://../work/game-data/fishing-economy-%d" % Time.get_ticks_usec())
	OS.set_environment("BREEZETOWN_SAVE_ROOT", save_root)
	_run.call_deferred()


func _run() -> void:
	EventBus.instance().reset_for_tests()
	EventBus.instance().item_added.connect(func(kind: String, count: int): added.append([kind, count]))
	EventBus.instance().item_removed.connect(func(kind: String, count: int): removed.append([kind, count]))
	EventBus.instance().money_changed.connect(func(total: int, delta: int): money.append([total, delta]))
	EventBus.instance().save_written.connect(func(path: String): saved_paths.append(path))
	_defaults_and_awards()
	_prices_and_sale()
	_progression_and_quality()
	_roundtrips()
	_legacy_and_malformed()
	print("FISHING_ECONOMY_RESULT %s %d checks" % ["PASS" if failures.is_empty() else "FAIL " + ",".join(failures), checks])
	quit(0 if failures.is_empty() else 1)


func _defaults_and_awards() -> void:
	var state := GameState.new()
	_check("default-skill", state.fishing_level == 1 and state.fishing_xp == 0 and state.fishing_xp_needed() == 100)
	_check("default-catalog", state.fish.size() == 6 and state.fish_quality.size() == 2)
	for kind in FishDB.ORDER:
		_check("default-grade-" + kind, state.fish[kind] == 0 and state.fish_quality.silver[kind] == 0 and state.fish_quality.gold[kind] == 0)
	added.clear()
	state.add_fish("koi")
	_check("legacy-add-signature", state.fish.koi == 1 and state.fish_quality.silver.koi == 0 and state.fish_quality.gold.koi == 0 and added == [["koi", 1]])
	state.add_fish("koi", 3, "silver")
	_check("silver-add-metadata-once", state.fish.koi == 4 and state.fish_quality.silver.koi == 3 and added == [["koi", 1], ["koi", 3]])
	state.add_fish("koi", 2, "gold")
	_check("gold-add-metadata-once", state.fish.koi == 6 and state.fish_quality.gold.koi == 2 and added == [["koi", 1], ["koi", 3], ["koi", 2]])
	state.add_fish("unknown", 4, "gold")
	state.add_fish("koi", 0, "silver")
	state.add_fish("koi", -1, "gold")
	_check("invalid-awards-have-no-mutation-or-event", state.fish.koi == 6 and added.size() == 3 and not state.fish.has("unknown"))
	state.add_fish("koi", 1, "unknown")
	_check("unknown-quality-is-normal", state.fish.koi == 7 and state.fish_quality.silver.koi == 3 and state.fish_quality.gold.koi == 2 and added.size() == 4)


func _prices_and_sale() -> void:
	var state := GameState.new()
	state.add_fish("koi", 2)
	state.add_fish("koi", 3, "silver")
	state.add_fish("koi", 1, "gold")
	state.add_fish("sardine", 1)
	state.add_fish("sardine", 2, "silver")
	state.add_fish("sardine", 3, "gold")
	_check("koi-silver-rounds-per-fish", state.fish_sale_value("koi") == 381)
	_check("mixed-grade-sardine-price", state.fish_sale_value("sardine") == 60)
	_check("unknown-fish-value-zero", state.fish_sale_value("unknown") == 0)
	state.add_harvest("wheat", 3, "silver")
	state.add_harvest("strawberry", 2, "gold")
	state.add_harvest("radish", 2)
	state.add_product("milk", 2)
	removed.clear()
	money.clear()
	var before := state.to_dict().duplicate(true)
	_check("sale-preview-preserves-crop-stack-rounding", state.sale_total() == 594)
	_check("sale-preview-read-only", state.to_dict() == before and removed.is_empty() and money.is_empty())
	_check("sale-matches-preview", state.sell_all_harvest() == 594 and state.coins == 614)
	_check("sale-money-event-once", money == [[614, 594]])
	_check("sale-removal-events-once", removed == [["radish", 2], ["strawberry", 2], ["wheat", 3], ["milk", 2], ["sardine", 6], ["koi", 6]])
	for kind in FishDB.ORDER:
		_check("sale-clears-fish-and-quality-" + kind, state.fish[kind] == 0 and state.fish_quality.silver[kind] == 0 and state.fish_quality.gold[kind] == 0)
	_check("sale-clears-crop-quality", state.harvest_quality.silver.wheat == 0 and state.harvest_quality.gold.strawberry == 0)
	_check("empty-repeat-sale-has-no-events", state.sell_all_harvest() == 0 and state.sale_total() == 0 and removed.size() == 6 and money.size() == 1)
	for kind in FishDB.ORDER:
		state.add_fish(kind, 1, "silver")
		_check("catalog-silver-unit-value-" + kind, state.fish_sale_value(kind) == int(FishDB.sell_price(kind) * 1.5))


func _progression_and_quality() -> void:
	var state := GameState.new()
	var energy_before := state.energy
	_check("negative-xp-ignored", state.gain_fishing_xp(-1) == 0 and state.fishing_xp == 0)
	_check("zero-xp-ignored", state.gain_fishing_xp(0) == 0 and state.fishing_level == 1)
	_check("xp-before-threshold", state.gain_fishing_xp(99) == 0 and state.fishing_xp == 99)
	_check("xp-exact-level", state.gain_fishing_xp(1) == 1 and state.fishing_level == 2 and state.fishing_xp == 0 and state.fishing_xp_needed() == 200)
	_check("multi-level-remainder", state.gain_fishing_xp(550) == 2 and state.fishing_level == 4 and state.fishing_xp == 50 and state.fishing_xp_needed() == 400)
	_check("independent-fishing-skill", state.xp == 0 and state.level == 1 and state.energy == energy_before and state.tool_energy_cost("rod") == 5.0)
	_check("large-award-caps-without-overflow", state.gain_fishing_xp(9223372036854775807) == 6 and state.fishing_level == 10 and state.fishing_xp == 0 and state.fishing_xp_needed() == 0)
	_check("capped-skill-stays-capped", state.gain_fishing_xp(10) == 0 and state.fishing_xp == 0)
	state = GameState.new()
	_check("level-one-control-threshold", state.fish_quality_for(0.819) == "normal" and state.fish_quality_for(0.82) == "silver")
	_check("level-one-cannot-gold", state.fish_quality_for(1.0) == "silver" and state.fish_quality_for(999.0) == "silver")
	_check("control-lower-bound", state.fish_quality_for(-9.0) == "normal" and state.fish_quality_for(NAN) == "normal")
	state.fishing_level = 4
	_check("level-four-cannot-gold", state.fish_quality_for(1.0) == "silver")
	state.fishing_level = 5
	_check("level-five-gold-needs-control", state.fish_quality_for(0.97) == "silver" and state.fish_quality_for(0.98) == "gold")
	state.fishing_level = 10
	_check("level-ten-still-requires-control", state.fish_quality_for(0.0) == "normal" and state.fish_quality_for(0.79) == "gold")
	_check("quality-is-deterministic", state.fish_quality_for(0.79) == state.fish_quality_for(0.79))


func _roundtrips() -> void:
	var state := GameState.new()
	for kind in FishDB.ORDER:
		state.add_fish(kind, 1)
		state.add_fish(kind, 2, "silver")
		state.add_fish(kind, 3, "gold")
	state.gain_fishing_xp(765)
	var data := state.to_dict()
	var expected_fish := state.fish.duplicate()
	var expected_quality := state.fish_quality.duplicate(true)
	state.add_fish("koi", 1, "silver")
	_check("serialized-fish-is-snapshot", data.fish == expected_fish and data.fish_quality == expected_quality)
	state.from_dict(data)
	_check("in-memory-roundtrip", state.fish == expected_fish and state.fish_quality == expected_quality and state.fishing_level == 4 and state.fishing_xp == 165)
	data.fish.koi = 99
	data.fish_quality.gold.koi = 99
	_check("loaded-state-does-not-alias-input", state.fish.koi == 6 and state.fish_quality.gold.koi == 3)
	var direct := {"fish": state.fish, "fish_quality": state.fish_quality, "fishing_level": state.fishing_level, "fishing_xp": state.fishing_xp}
	state.from_dict(direct)
	_check("direct-reference-load-preserves-input", direct.fish == expected_fish and direct.fish_quality == expected_quality)
	state.add_fish("koi", 1, "gold")
	_check("direct-reference-load-detaches-tables", direct.fish.koi == 6 and direct.fish_quality.gold.koi == 3)
	state.from_dict(direct)
	var restored := GameState.new()
	var json_data: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict()))
	restored.from_dict(json_data)
	_check("json-roundtrip-all-fish-and-grades", restored.fish == expected_fish and restored.fish_quality == expected_quality)
	_check("json-roundtrip-progression-and-value", restored.fishing_level == 4 and restored.fishing_xp == 165 and restored.sale_total() == state.sale_total())
	var result := SaveManager.save_game(1, {"economy": state.to_dict()})
	_check("disk-save-succeeds-and-signals-once", result.ok and saved_paths == [result.path])
	var loaded := SaveManager.load_game(1)
	_check("disk-load-succeeds", loaded.get("ok", false))
	if loaded.get("ok", false):
		restored.from_dict(loaded.get("economy", {}))
		_check("disk-roundtrip", restored.fish == expected_fish and restored.fish_quality == expected_quality and restored.fishing_level == 4 and restored.fishing_xp == 165)


func _legacy_and_malformed() -> void:
	var state := GameState.new()
	state.add_fish("koi", 3, "gold")
	state.gain_fishing_xp(1100)
	state.from_dict({"fish": {"koi": 4}})
	_check("legacy-fish-load-resets-new-fields", state.fish.koi == 4 and state.fish_quality.gold.koi == 0 and state.fish_quality.silver.koi == 0 and state.fishing_level == 1 and state.fishing_xp == 0)
	state.add_fish("sardine", 2, "silver")
	state.from_dict({})
	_check("pre-fishing-load-clears-catches", state.fish.koi == 0 and state.fish.sardine == 0 and state.fish_quality.silver.sardine == 0 and state.fishing_level == 1)
	var malformed := {
		"fish": {"sardine": -4, "carp": 3.9, "perch": "8", "catfish": true, "rainbow_trout": 1e30, "koi": 5, "unknown": 100},
		"fish_quality": {"gold": {"carp": 8, "koi": 2, "unknown": 5}, "silver": {"carp": 3, "koi": 10, "sardine": -2}, "unknown": {"koi": 5}},
		"fishing_level": 4.9, "fishing_xp": 5000,
	}
	var before := malformed.duplicate(true)
	state.from_dict(malformed)
	_check("malformed-input-not-mutated", malformed == before)
	_check("load-normalizes-numeric-counts", state.fish.sardine == 0 and state.fish.carp == 3 and state.fish.rainbow_trout == GameState.MAX_FISH_COUNT)
	_check("load-rejects-nonnumeric-counts", state.fish.perch == 0 and state.fish.catfish == 0)
	_check("load-ignores-unknown-catalog-entries", state.fish.size() == 6 and state.fish_quality.size() == 2 and state.fish_quality.gold.size() == 6)
	_check("load-quality-is-subset-with-gold-priority", state.fish_quality.gold.carp == 3 and state.fish_quality.silver.carp == 0 and state.fish_quality.gold.koi == 2 and state.fish_quality.silver.koi == 3)
	_check("load-normalizes-skill-progress", state.fishing_level == 4 and state.fishing_xp == 399)
	state.from_dict({"fish": {"koi": NAN, "carp": INF}, "fish_quality": {"gold": [], "silver": {"koi": INF}}, "fishing_level": INF, "fishing_xp": NAN})
	_check("nonfinite-and-invalid-subtable-defaults", state.fish.koi == 0 and state.fish.carp == 0 and state.fish_quality.gold.koi == 0 and state.fishing_level == 1 and state.fishing_xp == 0)
	for invalid in [null, [], "bad", true, 7]:
		state.from_dict({"fish": invalid, "fish_quality": invalid, "fishing_level": invalid, "fishing_xp": invalid})
		_check("invalid-table-safe-" + str(invalid), state.fish.koi == 0 and state.fish_quality.gold.koi == 0)
	state.from_dict({"fishing_level": 99, "fishing_xp": 999999})
	_check("loaded-cap-discards-unused-xp", state.fishing_level == 10 and state.fishing_xp == 0 and state.fishing_xp_needed() == 0)
	state.from_dict({"fishing_level": -1, "fishing_xp": -99})
	_check("loaded-lower-bounds", state.fishing_level == 1 and state.fishing_xp == 0)
	state.from_dict({"fishing_level": "7", "fishing_xp": "9"})
	_check("loaded-skill-rejects-string-coercion", state.fishing_level == 1 and state.fishing_xp == 0)


func _check(label: String, condition: bool) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error(label)
