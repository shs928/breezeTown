extends SceneTree
## INDOOR-01 领域检查：室内房间数据完整性、建筑耦合、服务规则与经济口径（不加载场景）。

const Definition := preload("res://scripts/data/first_map_definition.gd")
const InteriorDB := preload("res://scripts/data/interior_db.gd")
const RecipeDB := preload("res://scripts/data/recipe_db.gd")
const MachineState := preload("res://scripts/domain/machine_state.gd")
const GameState := preload("res://scripts/game_state.gd")

var count := 0
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _check(label: String, ok: bool) -> void:
	count += 1
	print("INDOOR %s %s" % [label, "OK" if ok else "FAIL"])
	if not ok:
		failures.append(label)


func _run() -> void:
	_check_data()
	_check_building_coupling()
	_check_state_rules()
	_check_recipes()
	_check_machines()
	_check_warehouse()
	_check_store02()
	var verdict := "PASS %d" % count if failures.is_empty() else "FAIL %s" % ",".join(failures)
	print("INDOOR_DOMAIN_RESULT " + verdict)
	quit(0 if failures.is_empty() else 1)


func _check_data() -> void:
	_check("order-covers-rooms", InteriorDB.ORDER.size() == InteriorDB.ROOMS.size())
	for id: String in InteriorDB.ORDER:
		_check("room-registered-" + id, InteriorDB.has(id))
		var room: Dictionary = InteriorDB.entry(id)
		var size: Vector2 = room["size"]
		_check("room-label-" + id, String(room["label"]).length() > 0)
		_check("room-style-" + id, String(room["style"]) in ["home", "shop", "inn", "clinic", "smith", "barn", "coop", "carpenter"])
		_check("room-size-" + id, size.x >= 6.0 and size.y >= 6.0)
		var spawn: Vector3 = room["spawn"]
		var exit_at: Vector3 = room["exit"]
		_check("room-spawn-inside-" + id, absf(spawn.x) < size.x * 0.5 and absf(spawn.z) < size.y * 0.5)
		_check("room-exit-inside-" + id, absf(exit_at.x) < size.x * 0.5 and exit_at.z <= size.y * 0.5)
		_check("room-exit-south-of-spawn-" + id, exit_at.z > spawn.z)
		var kinds := {}
		for service: Dictionary in room.get("services", []):
			var at: Vector3 = service["at"]
			kinds[String(service["kind"])] = true
			_check("service-inside-%s-%s" % [id, service["kind"]], absf(at.x) < size.x * 0.5 and absf(at.z) < size.y * 0.5)
			_check("service-range-%s-%s" % [id, service["kind"]], float(service["range"]) > 0.0)
			_check("service-hint-%s-%s" % [id, service["kind"]], String(service["hint"]).length() > 0)
		_check("service-kinds-unique-" + id, kinds.size() == room.get("services", []).size())
	_check("meal-price-positive", InteriorDB.MEAL_PRICE > 0)
	_check("meal-health-bounded", InteriorDB.MEAL_HEALTH > 0 and InteriorDB.MEAL_HEALTH <= GameState.MAX_HEALTH)
	_check("treatment-price-positive", InteriorDB.TREATMENT_PRICE > 0)


func _check_building_coupling() -> void:
	var definition: Dictionary = Definition.create()
	var by_id := {}
	for building: Dictionary in definition["buildings"]:
		by_id[building["id"]] = building
	for id: String in InteriorDB.ORDER:
		_check("building-exists-" + id, by_id.has(id))
		if by_id.has(id):
			var door: Vector2 = by_id[id]["door"]
			_check("door-resolved-" + id, door != Vector2.ZERO and is_finite(door.x))


func _check_state_rules() -> void:
	var state := GameState.new()
	state.coins = 100
	state.health = 30
	state.energy = 10.0
	_check("meal-affordable", state.buy_meal())
	_check("meal-deducts", state.coins == 100 - InteriorDB.MEAL_PRICE)
	_check("meal-restores-energy", is_equal_approx(state.energy, float(state.energy_max())))
	_check("meal-restores-health", state.health == 30 + InteriorDB.MEAL_HEALTH)
	state.health = 95
	var before := state.coins
	_check("meal-clamps-health", state.buy_meal() and state.health == GameState.MAX_HEALTH)
	_check("meal-still-charges", state.coins == before - InteriorDB.MEAL_PRICE)
	state.coins = InteriorDB.MEAL_PRICE - 1
	var snapshot := {"coins": state.coins, "health": state.health, "energy": state.energy}
	_check("meal-too-poor-refused", not state.buy_meal())
	_check("meal-too-poor-unchanged", state.coins == snapshot["coins"] and state.health == snapshot["health"] and is_equal_approx(state.energy, snapshot["energy"]))
	var clinic := GameState.new()
	clinic.coins = 100
	clinic.health = GameState.MAX_HEALTH
	_check("treatment-full-health-refused", not clinic.buy_treatment())
	clinic.health = 40
	clinic.coins = InteriorDB.TREATMENT_PRICE - 1
	_check("treatment-too-poor-refused", not clinic.buy_treatment() and clinic.health == 40)
	clinic.coins = 100
	_check("treatment-affordable", clinic.buy_treatment())
	_check("treatment-heals-full", clinic.health == GameState.MAX_HEALTH and clinic.coins == 100 - InteriorDB.TREATMENT_PRICE)


func _check_recipes() -> void:
	## PROCESS-01：配方目录自检 + 每台机器至少一个配方 + 产出口径可入库。
	var problems: Array[String] = RecipeDB.validate()
	_check("recipe-validate-clean", problems.is_empty())
	var stations := {}
	for room_id: String in InteriorDB.ORDER:
		for machine: Dictionary in InteriorDB.entry(room_id).get("machines", []):
			stations[String(machine["kind"])] = true
			_check("machine-has-recipes-%s" % machine["kind"], RecipeDB.recipes_for_station(String(machine["kind"])).size() > 0)
	for recipe: Dictionary in RecipeDB.RECIPES:
		_check("recipe-station-has-room-%s" % recipe["id"], stations.has(String(recipe["required_station"])) or String(recipe["required_station"]) == "")
	_check("requirements-text-nonempty", RecipeDB.requirements_text("furnace").length() > 0)


func _check_machines() -> void:
	## PROCESS-01：生命周期 EMPTY→PROCESSING→FINISHED→收取，含存档往返与脏档清洗。
	var state := GameState.new()
	state.minerals["copper"] = 4
	var machine := MachineState.new()
	_check("machine-starts-empty", machine.state() == "EMPTY")
	var recipe: Dictionary = machine.can_start(RecipeDB.recipes_for_station("furnace"), state.count_item)
	_check("machine-picks-recipe", String(recipe.get("id", "")) == "smelt_copper")
	for item: String in recipe["inputs"]:
		state.remove_items(item, int(recipe["inputs"][item]))
	machine.start(recipe)
	_check("machine-processing", machine.state() == "PROCESSING" and is_equal_approx(machine.hours_remaining, 2.0))
	_check("machine-not-collectable-early", machine.collect().is_empty())
	machine.tick(1.2)
	_check("machine-partial-remaining", machine.hours_remaining < 2.0 and machine.state() == "PROCESSING")
	machine.tick(5.0)
	_check("machine-finishes", machine.state() == "FINISHED" and machine.hours_remaining == 0.0)
	var saved: Dictionary = machine.to_dict()
	var outputs: Dictionary = machine.collect()
	_check("machine-collects-output", outputs.get("copper_bar", 0) == 1)
	_check("machine-resets-after-collect", machine.state() == "EMPTY")
	var restored := MachineState.new()
	restored.from_dict(saved)
	_check("machine-roundtrip-finished", restored.state() == "FINISHED" and restored.collect().get("copper_bar", 0) == 1)
	var dirty := MachineState.new()
	dirty.from_dict({"recipe": "ghost_recipe", "hours": 3.0})
	_check("machine-dirty-recipe-reset", dirty.state() == "EMPTY")
	var sleepy := MachineState.new()
	sleepy.from_dict({"recipe": "press_cheese", "hours": 2.0})
	sleepy.tick(5.0)
	_check("machine-big-step-finishes", sleepy.state() == "FINISHED")


func _check_warehouse() -> void:
	## STORE-01：共享仓库整批存取、六族口径、存档往返与脏档清洗。
	var state := GameState.new()
	state.harvest["radish"] = 3
	state.minerals["copper"] = 7
	_check("deposit-moves-all", state.warehouse_deposit("radish") == 3 and state.count_item("radish") == 0 and state.warehouse_count("radish") == 3)
	_check("deposit-nonfamily-refused", state.warehouse_deposit("chest") == 0)
	_check("deposit-empty-moves-none", state.warehouse_deposit("pumpkin") == 0)
	_check("withdraw-moves-all", state.warehouse_withdraw("radish") == 3 and state.count_item("radish") == 3 and state.warehouse_count("radish") == 0)
	_check("withdraw-empty-moves-none", state.warehouse_withdraw("radish") == 0)
	state.warehouse_deposit("copper")
	_check("warehouse-caches-partial", state.warehouse_count("copper") == 7 and state.minerals["copper"] == 0)
	var saved: Dictionary = state.to_dict()
	_check("save-carries-warehouse", saved.get("warehouse", {}).get("copper", 0) == 7)
	_check("save-carries-chests-ready", saved.get("chests_ready", -1) == 0)
	var restored := GameState.new()
	restored.from_dict(saved)
	_check("load-restores-warehouse", restored.warehouse_count("copper") == 7)
	var dirty := GameState.new()
	dirty.from_dict({"warehouse": {"radish": 4, "ghost_item": 9, "iron": -5.5, "coal": "x"}, "chests_ready": -3})
	_check("load-drops-unknown-item", not dirty.warehouse.has("ghost_item"))
	_check("load-clamps-negative", not dirty.warehouse.has("iron") and dirty.warehouse_count("coal") == 0 and dirty.warehouse_count("radish") == 4)
	_check("load-clamps-chests-ready", dirty.chests_ready == 0)
	var workbench := RecipeDB.recipes_for_station("workbench")
	_check("workbench-chest-recipe", workbench.any(func(r): return r["id"] == "craft_chest" and r["inputs"] == {"wood": 10, "stone": 5}))
	_check("workbench-fertilizer-recipe", workbench.any(func(r): return r["id"] == "recycle_fertilizer"))


func _check_store02() -> void:
	## STORE-02：仓库容量口径、丢弃、第二辈配方与存档归一。
	var state := GameState.new()
	_check("capacity-default-300", state.warehouse_capacity == 300)
	state.warehouse["wheat"] = 120
	state.warehouse["radish"] = 180
	_check("warehouse-total-sums", state.warehouse_total() == 300)
	state.warehouse_discard("radish")
	_check("discard-drops-all", state.warehouse_count("radish") == 0 and state.warehouse_total() == 120)
	_check("discard-empty-moves-none", state.warehouse_discard("pumpkin") == 0)
	state.warehouse_capacity = 600
	var saved: Dictionary = state.to_dict()
	var restored := GameState.new()
	restored.from_dict(saved)
	_check("capacity-roundtrip", restored.warehouse_capacity == 600 and restored.warehouse_total() == 120)
	var floor_limited := GameState.new()
	floor_limited.from_dict({"warehouse_capacity": 50})
	_check("capacity-floor-300", floor_limited.warehouse_capacity == 300)
	var bread: Dictionary = RecipeDB.get_recipe("bake_bread")
	_check("bread-recipe-at-inn-kitchen", bread.get("required_station", "") == "kitchen" and bread.get("inputs", {}) == {"wheat": 3})
	var blanket: Dictionary = RecipeDB.get_recipe("weave_blanket")
	_check("blanket-recipe-at-barn-loom", blanket.get("required_station", "") == "loom" and blanket.get("inputs", {}) == {"wool": 3})
	var expansion: Dictionary = RecipeDB.get_recipe("expand_warehouse")
	_check("expansion-recipe", expansion.get("outputs", {}) == {"warehouse_expansion": 1})
	_check("bread-registered-product", GameState.PRODUCT_ORDER.has("bread") and GameState.PRODUCT_ORDER.has("blanket"))
