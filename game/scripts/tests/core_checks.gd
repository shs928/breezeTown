extends SceneTree
## M0 领域层单元测试（headless，不加载 3D 场景）：
## 覆盖 V2 PRD 第 41 节 TEST-001~007 的数据逻辑与数据目录完整性。
## 运行：Godot --headless --path game --script res://scripts/tests/core_checks.gd

const GameClock := preload("res://scripts/core/game_clock.gd")
const SaveManager := preload("res://scripts/core/save_manager.gd")
const CropDB := preload("res://scripts/data/crop_db.gd")
const ItemDB := preload("res://scripts/data/item_db.gd")
const AnimalDB := preload("res://scripts/data/animal_db.gd")
const RecipeDB := preload("res://scripts/data/recipe_db.gd")
const MapData := preload("res://scripts/core/map_data.gd")
const GameState := preload("res://scripts/game_state.gd")
const FarmState := preload("res://scripts/domain/farm_state.gd")
const AnimalState := preload("res://scripts/domain/animal_state.gd")

const TEST_SLOT := 98  # 单测专用存档槽

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(step: String, condition: bool) -> void:
	if not condition:
		failures.append(step)
	print("CORE %s %s" % [step, "OK" if condition else "FAIL"])


func _run() -> void:
	_test_data_catalogs()
	_test_new_world()
	_test_planting()
	_test_growth_and_harvest()
	_test_clock_and_season()
	_test_animal()
	_test_economy()
	_test_save_roundtrip()
	_test_event_bus()
	var result := "PASS" if failures.is_empty() else "FAIL " + ",".join(failures)
	print("CORE_RESULT " + result)
	quit(0 if failures.is_empty() else 1)


func _test_data_catalogs() -> void:
	EventBus.instance().reset_for_tests()
	_check("catalog-crops", CropDB.CROPS.size() == 4 and CropDB.ORDER.size() == 4)
	var crops_valid := true
	for kind in CropDB.CROPS:
		if CropDB.grow_days(kind) < 1 or CropDB.field(kind, "seed_price") <= 0:
			crops_valid = false
	_check("catalog-crop-fields", crops_valid)
	_check("catalog-items-registered", ItemDB.item("seed_radish")["buy"] == 3 and ItemDB.sell_price("radish") == 8)
	_check("catalog-items-count", ItemDB.ITEMS.size() >= 4 + 4 + 3 + 6 + 2)
	_check("catalog-animal-products", AnimalDB.product("cow") == "milk" and AnimalDB.product("chicken") == "egg")
	_check("catalog-recipes-valid", RecipeDB.validate().is_empty())


func _test_new_world() -> void:
	# TEST-001：新建世界
	EventBus.instance().reset_for_tests()
	var state := GameState.new()
	_check("new-world-player", state != null)
	_check("new-world-money", state.coins == 20)
	_check("new-world-inventory", state.seeds["radish"] == 6 and state.seeds["strawberry"] == 0)
	_check("new-world-day", state.day == 1 and state.health == 100)


func _test_planting() -> void:
	# TEST-002：整地 → 播种 → 浇水
	EventBus.instance().reset_for_tests()
	var farm := FarmState.new()
	var key := Vector2i(3, -4)
	_check("plant-till", farm.till(key) != null and farm.data_of(key).state == "tilled")
	_check("plant-till-twice-rejected", farm.till(key) == null)
	_check("plant-on-wild-rejected", farm.plant(Vector2i(0, 0), "radish") == false)
	_check("plant-seed", farm.plant(key, "radish") and farm.data_of(key).crop == "radish")
	_check("plant-water", farm.water(key) and farm.data_of(key).watered)


func _test_growth_and_harvest() -> void:
	# TEST-003 / TEST-004：跨天生长 → 收获
	EventBus.instance().reset_for_tests()
	var farm := FarmState.new()
	var key := Vector2i(-2, 6)
	farm.till(key)
	farm.plant(key, "radish")
	farm.water(key)
	farm.rollover()
	_check("grow-stage", farm.data_of(key).stage == 1 and not farm.data_of(key).watered)
	farm.water(key)
	farm.rollover()
	_check("grow-mature", farm.data_of(key).is_mature())
	var kind: String = farm.harvest(key)
	_check("harvest-item", kind == "radish")
	_check("harvest-resets-plot", farm.data_of(key).state == "tilled" and farm.harvest(key) == "")
	_check("harvest-unmature-rejected", farm.plant(key, "pumpkin") and farm.harvest(key) == "")


func _test_clock_and_season() -> void:
	EventBus.instance().reset_for_tests()
	var clock := GameClock.new()
	var rolled: bool = false
	for i in range(180):
		if clock.advance(0.1):
			rolled = true
			break
	_check("clock-day-rollover", rolled and clock.day == 2)
	_check("clock-wraps-to-morning", absf(clock.hours - 6.0) < 0.01)
	clock.sleep_to_next_day()
	_check("clock-sleep", clock.hours == 6.0 and clock.day == 3)
	_check("clock-season-spring", clock.season() == "春季" and clock.weekday() == "周三")
	clock.day = 29
	_check("clock-season-summer", clock.season() == "夏季")
	clock.day = 85
	_check("clock-season-winter", clock.season() == "冬季")
	clock.hours = 8.5
	_check("clock-text", clock.clock_text() == "08:30")
	clock.set_weather("rain")
	_check("clock-weather", clock.weather_label() == "雨")


func _test_animal() -> void:
	EventBus.instance().reset_for_tests()
	var animal := AnimalState.new()
	animal.setup("cow")
	_check("animal-pet-once", animal.pet() and animal.petted_today)
	_check("animal-pet-twice-rejected", not animal.pet())
	animal.new_day()
	_check("animal-new-day-resets", animal.pet())
	_check("animal-product", animal.product_kind() == "milk" and animal.label() == "奶牛")


func _test_economy() -> void:
	EventBus.instance().reset_for_tests()
	var state := GameState.new()
	_check("economy-buy-insufficient", not state.buy_seed("pumpkin", 100))
	_check("economy-buy", state.buy_seed("radish", 2) and state.coins == 14 and state.seeds["radish"] == 8)
	_check("economy-take-seed", state.take_seed("radish") and state.seeds["radish"] == 7)
	_check("economy-take-seed-empty", state.take_seed("pumpkin") == false)
	state.add_harvest("radish", 1)
	state.add_product("milk", 2)
	var earned: int = state.sell_all_harvest()
	_check("economy-sell", earned == 8 + 2 * 14 and state.coins == 14 + 8 + 28)
	_check("economy-sell-empties", state.harvest["radish"] == 0 and state.products["milk"] == 0)
	_check("economy-eat-full-health", state.eat_ration() == 0 and state.rations == 3)


func _test_save_roundtrip() -> void:
	# TEST-007：存档 → 读档 → 状态一致
	EventBus.instance().reset_for_tests()
	var state := GameState.new()
	state.coins = 123
	state.day = 5
	state.time.hours = 12.5
	state.minerals["iron"] = 7
	state.forestry["wood"] = 11
	state.deepest_mine_floor = 4
	var farm := FarmState.new()
	farm.till(Vector2i(1, 1))
	farm.till(Vector2i(2, 2))
	farm.plant(Vector2i(2, 2), "strawberry")
	farm.water(Vector2i(2, 2))
	farm.rollover()
	var map := MapData.new()
	map.pastures.append(Rect2(4, 4, 10, 8))
	var animal := AnimalState.new()
	animal.setup("sheep", 1)
	animal.pet()
	var clock_data: Dictionary = state.time.to_dict()
	clock_data["season"] = state.time.season()
	var payload := {
		"version": 1,
		"clock": clock_data,
		"economy": state.to_dict(),
		"farm": farm.to_dict(),
		"pastures": map.to_dict(),
		"animals": [animal.to_dict()],
	}
	var save_result: Dictionary = SaveManager.save_game(TEST_SLOT, payload)
	_check("save-writes", bool(save_result["ok"]))
	var loaded: Dictionary = SaveManager.load_game(TEST_SLOT)
	_check("save-loads", bool(loaded.get("ok", false)))
	var restored := GameState.new()
	restored.time.from_dict(loaded["clock"])
	restored.from_dict(loaded["economy"])
	_check("save-day-money", restored.day == 5 and restored.coins == 123 and absf(restored.time.hours - 12.5) < 0.001)
	_check("save-resources", restored.minerals["iron"] == 7 and restored.forestry["wood"] == 11 and restored.deepest_mine_floor == 4)
	var restored_farm := FarmState.new()
	restored_farm.from_dict(loaded["farm"])
	_check("save-farm", restored_farm.data_of(Vector2i(2, 2)) != null and restored_farm.data_of(Vector2i(2, 2)).crop == "strawberry" and restored_farm.data_of(Vector2i(2, 2)).stage == 1)
	var restored_map := MapData.new()
	restored_map.from_dict(loaded["pastures"])
	_check("save-pastures", restored_map.pastures.size() == 1 and restored_map.pastures[0] == Rect2(4, 4, 10, 8))
	var restored_animal := AnimalState.new()
	restored_animal.from_dict(loaded["animals"][0])
	_check("save-animal", restored_animal.kind == "sheep" and restored_animal.petted_today and restored_animal.home_index == 1)
	_check("save-missing-slot", SaveManager.load_game(97).has("error") and not bool(SaveManager.load_game(97).get("ok", true)))


func _test_event_bus() -> void:
	EventBus.instance().reset_for_tests()
	var planted_count := {"n": 0}
	var money_events := {"n": 0}
	EventBus.instance().crop_planted.connect(func(_key: Vector2i, _kind: String): planted_count["n"] += 1)
	EventBus.instance().money_changed.connect(func(_total: int, _delta: int): money_events["n"] += 1)
	var farm := FarmState.new()
	farm.till(Vector2i(5, 5))
	farm.plant(Vector2i(5, 5), "wheat")
	_check("event-crop-planted", planted_count["n"] == 1)
	var state := GameState.new()
	state.add_coins(5)
	_check("event-money-changed", money_events["n"] == 1)
	EventBus.instance().reset_for_tests()
