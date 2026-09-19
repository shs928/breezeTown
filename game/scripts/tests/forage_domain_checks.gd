extends SceneTree
## GATHER-01 采集系统领域检查：物种数据、条件筛选、抽选、经济与存读档。
## 不依赖场景；全部纯数据断言。

const GameState := preload("res://scripts/game_state.gd")
const ForageDB := preload("res://scripts/data/forage_db.gd")
const GameClock := preload("res://scripts/core/game_clock.gd")

var failures: Array[String] = []
var count := 0
var events_added := 0
var events_removed := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_data_integrity()
	_eligibility()
	_rolls()
	_economy()
	_save_roundtrip()
	print("FORAGE_DOMAIN_RESULT %s %d checks" % ["PASS" if failures.is_empty() else "FAIL " + ",".join(failures), count])
	quit(0 if failures.is_empty() else 1)


func _check(label: String, result: bool) -> void:
	count += 1
	print("FORAGE %s %s" % [label, "OK" if result else "FAIL"])
	if not result:
		failures.append(label)


func _data_integrity() -> void:
	var valid_habitats: Array = ForageDB.HABITATS
	for kind in ForageDB.ORDER:
		var entry: Dictionary = ForageDB.FORAGE[kind]
		_check("label-nonempty-" + kind, String(entry["label"]).length() > 0)
		_check("price-positive-" + kind, int(entry["sell_price"]) > 0)
		_check("weight-positive-" + kind, int(entry["weight"]) > 0)
		_check("habitats-known-" + kind, (entry["habitats"] as Array).filter(func(h): return h not in valid_habitats).is_empty())
		_check("seasons-known-" + kind, (entry["seasons"] as Array).filter(func(s): return s not in GameClock.SEASON_KEYS).is_empty())
		_check("weathers-known-" + kind, (entry["weathers"] as Array).filter(func(w): return w not in GameClock.WEATHERS).is_empty())
		_check("rarity-known-" + kind, entry["rarity"] in ["common", "uncommon", "rare"])
	# 每个季节至少有一个栖息地可采，全年不空窗。
	for season in GameClock.SEASON_KEYS:
		var season_total := 0
		for habitat in ForageDB.HABITATS:
			season_total += ForageDB.available(habitat, {"season": season}).size()
		_check("season-has-forage-" + season, season_total > 0)
	# 每个栖息地全年至少一种（生成器不会面对空池）。
	for habitat in ForageDB.HABITATS:
		_check("habitat-has-forage-" + habitat, ForageDB.available(habitat).size() > 0)
	_check("itemdb-registers-forage", ForageDB.ORDER.all(func(kind): return GameState.ItemDB.item_type(kind) == "forage"))
	_check("itemdb-forage-sellable", GameState.ItemDB.sell_price("mushroom") == ForageDB.sell_price("mushroom"))


func _eligibility() -> void:
	_check("daffodil-spring-forest", ForageDB.eligible("daffodil", "forest", {"season": "spring"}))
	_check("daffodil-not-autumn", not ForageDB.eligible("daffodil", "forest", {"season": "autumn"}))
	_check("daffodil-not-mountain", not ForageDB.eligible("daffodil", "mountain", {"season": "spring"}))
	_check("shell-winter-shore", ForageDB.eligible("shell", "shore", {"season": "winter"}))
	_check("cockle-not-winter", not ForageDB.eligible("cockle", "shore", {"season": "winter"}))
	_check("empty-context-allows-all-seasons", ForageDB.eligible("mushroom", "forest"))
	_check("unknown-kind-rejected", not ForageDB.eligible("not_a_forage", "forest", {"season": "spring"}))
	_check("invalid-context-key-rejected", not ForageDB.eligible("mushroom", "forest", {"hour": 12.0}))
	_check("invalid-season-rejected", not ForageDB.eligible("mushroom", "forest", {"season": "dry"}))
	# 湖畔/海岸条件物种不越界：薄荷只夏天，鸟蛤冬季缺席。
	_check("mint-summer-only", ForageDB.available("lakeside", {"season": "summer"}).has("mint") and not ForageDB.available("lakeside", {"season": "autumn"}).has("mint"))
	_check("winter-town-empty", ForageDB.available("town", {"season": "winter"}).is_empty())


func _rolls() -> void:
	var rng_a := RandomNumberGenerator.new()
	rng_a.seed = 20260918
	var rng_b := RandomNumberGenerator.new()
	rng_b.seed = 20260918
	var context := {"season": "autumn", "weather": "rain"}
	var same := true
	for attempt in range(30):
		var pick_a: Dictionary = ForageDB.roll_anywhere(rng_a, context)
		var pick_b: Dictionary = ForageDB.roll_anywhere(rng_b, context)
		same = same and pick_a == pick_b and ForageDB.eligible(pick_a.get("kind", ""), pick_a.get("habitat", ""), context)
	_check("roll-deterministic-and-eligible", same)
	var seen := {}
	var rng_wide := RandomNumberGenerator.new()
	rng_wide.seed = 77
	for attempt in range(200):
		var pick: Dictionary = ForageDB.roll_anywhere(rng_wide, {"season": "spring", "weather": "sunny"})
		if not pick.is_empty():
			seen[pick["kind"]] = true
	_check("spring-roll-covers-multiple-species", seen.size() >= 3)
	# 冬季镇区池为空；全域冬季只能抽到山地/森林/海岸物种。
	_check("empty-pool-returns-empty", ForageDB.roll("town", RandomNumberGenerator.new(), {"season": "winter"}).is_empty())
	var winter_only := true
	var rng_winter := RandomNumberGenerator.new()
	rng_winter.seed = 4242
	for attempt in range(60):
		var pick: Dictionary = ForageDB.roll_anywhere(rng_winter, {"season": "winter", "weather": "storm"})
		winter_only = winter_only and not pick.is_empty() and pick["habitat"] in ["mountain", "forest", "shore"]
	_check("winter-roll-limited-to-cold-habitats", winter_only)


func _economy() -> void:
	var state := GameState.new()
	events_added = 0
	events_removed = 0
	EventBus.instance().item_added.connect(func(_id, _n): events_added += 1)
	EventBus.instance().item_removed.connect(func(_id, _n): events_removed += 1)
	_check("forage-starts-empty", state.forage.values().all(func(v): return v == 0))
	state.add_forage("mushroom", 2)
	state.add_forage("shell")
	state.add_forage("not_a_forage")
	state.add_forage("mushroom", 0)
	_check("add-forage-counts", state.forage["mushroom"] == 2 and state.forage["shell"] == 1)
	_check("add-forage-single-events", events_added == 2 and events_removed == 0)
	var expected: int = 2 * ForageDB.sell_price("mushroom") + ForageDB.sell_price("shell")
	_check("sale-total-includes-forage", state.sale_total() == expected)
	var coins_before: int = state.coins
	var earned: int = state.sell_all_harvest()
	_check("sell-credits-forage", earned == expected and state.coins == coins_before + expected)
	_check("sell-clears-forage", state.forage.values().all(func(v): return v == 0))
	_check("sell-emits-removal-events", events_removed == 2)


func _save_roundtrip() -> void:
	var state := GameState.new()
	state.add_forage("daffodil", 3)
	state.add_forage("crystal_fruit", 1)
	var payload: Dictionary = state.to_dict()
	var snapshot: Dictionary = payload.duplicate(true)
	var restored := GameState.new()
	restored.from_dict(payload)
	_check("forage-survives-roundtrip", restored.forage["daffodil"] == 3 and restored.forage["crystal_fruit"] == 1)
	_check("to-dict-does-not-mutate-state", restored.forage == state.forage)
	# 旧档无 forage 键 → 全零；脏数据归零且不修改输入字典。
	var legacy := GameState.new()
	legacy.from_dict({"coins": 50})
	_check("legacy-save-zero-forage", legacy.forage.values().all(func(v): return v == 0))
	var dirty := {"forage": {"mushroom": "many", "daffodil": -7, "leek": 1.5, "ghost": 9, "koi": 2}}
	var dirty_copy: Dictionary = dirty.duplicate(true)
	var cleaned := GameState.new()
	cleaned.from_dict(dirty)
	_check("dirty-forage-sanitized", cleaned.forage["mushroom"] == 0 and cleaned.forage["daffodil"] == 0 and cleaned.forage["leek"] == 1 and cleaned.forage.get("ghost", 0) == 0 and not cleaned.forage.has("koi"))
	_check("from-dict-does-not-mutate-input", dirty == dirty_copy)
	_check("payload-untouched", payload == snapshot)
