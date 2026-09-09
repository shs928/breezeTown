extends SceneTree
## FARM-01 测试（headless）：整地/播种/浇水/生长/收获，五作物生长日，贡献去重，抢收。
## 运行：godot --headless --path game --script res://tests/unit/farming/test_runner.gd

const ContractLimits := preload("res://src/contracts/contract_limits.gd")
const ContractError := preload("res://src/contracts/contract_error.gd")
const WorldState := preload("res://src/domain/world/world_state.gd")
const WorldRuntime := preload("res://src/application/world/world_runtime.gd")
const TransactionCoordinator := preload("res://src/application/core/transaction_coordinator.gd")
const ItemCatalog := preload("res://src/domain/economy/item_catalog.gd")
const FarmHandlers := preload("res://src/application/farming/farm_handlers.gd")

const FARM_TILE := 1950          # x=30,y=30 → 30*64+30，位于 12x12 耕地内
const FARM_TILE_2 := 1951        # x=31,y=30
const PLAYER_X := 976.0          # (30.5)*32
const PLAYER_Y := 976.0

var _checks := 0
var _failures: PackedStringArray = []
var _seq := {}


func _initialize() -> void:
	_test_full_radish_cycle()
	_test_five_crop_growth_days()
	_test_water_dedup_and_mature()
	_test_harvest_concurrency()
	_test_range_and_blocking()
	_test_untilled_and_planted_states()

	if _failures.is_empty():
		print("FARM_OK checks=%d" % _checks)
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: " + f)
		printerr("FARM_FAILED checks=%d failures=%d" % [_checks, _failures.size()])
		quit(1)


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(label)


func _load(path: String) -> Variant:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return _normalize(parsed)


func _normalize(v: Variant) -> Variant:
	if v is Array:
		var a: Array = []
		for i in v:
			a.append(_normalize(i))
		return a
	if v is Dictionary:
		var d := {}
		for k in v:
			d[k] = _normalize(v[k])
		return d
	if v is float and is_equal_approx(v, float(int(v))):
		return int(v)
	return v


func _make() -> Array:
	var world_id := "w" + "0123456789abcdef0123456789abcdef"
	var owner_id := "m" + "11111111111111111111111111111111"
	var world := WorldState.create(world_id, owner_id, "房主")
	var runtime := WorldRuntime.new()
	runtime.setup(world, _load("res://content/schema/examples/map_town_minimal.json"))
	var catalog := ItemCatalog.load_from_disk()
	var farm := FarmHandlers.new()
	farm.setup(runtime, catalog, 12345)
	runtime.set_day_settle_hook(Callable(farm, "settle_growth"))
	# 给所有者一个背包和常用种子（模拟 ECON 已初始化）
	var backpack := {"capacity": 24, "slots": WorldState.empty_slots(24), "revision": 0}
	world.containers["backpack:" + owner_id] = backpack
	for i in 5:
		var seed_ids := ["seed.radish", "seed.potato", "seed.wheat", "seed.carrot", "seed.strawberry"]
		backpack["slots"][i] = {"item_definition_id": seed_ids[i], "quantity": 20}
	world.find_member(owner_id)["last_valid_position"] = {"x": PLAYER_X, "y": PLAYER_Y}
	return [runtime, catalog, farm, owner_id]


func _cmd(runtime: WorldRuntime, player_id: String, command_type: String, payload: Dictionary) -> Dictionary:
	var rid := runtime.get_instance_id()
	if not _seq.has(rid):
		_seq[rid] = {}
	_seq[rid][player_id] = int(_seq[rid].get(player_id, 0)) + 1
	return runtime.submit({
		"protocol_version": 1,
		"world_id": runtime.world.world_id,
		"authority_epoch": runtime.world.authority_epoch,
		"client_sequence": _seq[rid][player_id],
		"command_type": command_type,
		"payload": payload,
		"_actor_player_id": player_id,
	})


func _advance_day(runtime: WorldRuntime) -> void:
	runtime.tick(ContractLimits.GAME_DAY_MS)


func _contribution(world: WorldState, player_id: String) -> Dictionary:
	return world.stats["members"][player_id]["contribution"]


# ---------- 1. 萝卜完整循环 ----------

func _test_full_radish_cycle() -> void:
	var ctx := _make()
	var runtime: WorldRuntime = ctx[0]
	var owner: String = ctx[3]
	# 整地
	var t := _cmd(runtime, owner, "farming.till", {"tile_id": FARM_TILE})
	_check(t["accepted"] and t["error_code"] == "", "till accepted")
	_check(runtime.world.plots[str(FARM_TILE)]["state"] == "empty", "plot now empty-tilled")
	_check(t["events"][0]["event_type"] == "PlotTilled", "PlotTilled event")
	_check(int(_contribution(runtime.world, owner)["planting"]) == 0, "tilling adds no contribution")
	# 播种
	var p := _cmd(runtime, owner, "farming.plant", {"tile_id": FARM_TILE, "seed_slot": 0, "seed_definition_id": "seed.radish"})
	_check(p["accepted"] and p["error_code"] == "", "plant accepted")
	_check(runtime.world.containers["backpack:" + owner]["slots"][0]["quantity"] == 19, "seed decremented")
	_check(int(_contribution(runtime.world, owner)["planting"]) == 2, "plant +2 contribution")
	var crop_id: String = runtime.world.plots[str(FARM_TILE)]["crop_instance_id"]
	_check(not crop_id.is_empty(), "crop instance created")
	# 未浇水 → 日切不生长
	_advance_day(runtime)
	_check(int(runtime.world.crops[crop_id]["growth_days"]) == 0, "no growth without watering")
	# 浇水 → 日切生长 1 日（萝卜成熟）
	var w := _cmd(runtime, owner, "farming.water", {"tile_id": FARM_TILE})
	_check(w["accepted"] and w["error_code"] == "", "water accepted")
	_check(int(_contribution(runtime.world, owner)["watering"]) == 1, "water +1 contribution")
	_advance_day(runtime)
	_check(int(runtime.world.crops[crop_id]["growth_days"]) == 1, "growth +1 after watering")
	_check(ctx[2].stage_of(runtime.world.crops[crop_id]) == "mature", "radish mature at 1 day")
	# 收获
	var h := _cmd(runtime, owner, "farming.harvest", {"tile_id": FARM_TILE})
	_check(h["accepted"] and h["error_code"] == "", "harvest accepted")
	_check(not runtime.world.crops.has(crop_id), "crop removed")
	_check(runtime.world.plots[str(FARM_TILE)]["state"] == "empty", "plot stays tilled")
	var produce_found := false
	for slot: Variant in runtime.world.containers["backpack:" + owner]["slots"]:
		if slot != null and slot["item_definition_id"] == "produce.radish" and int(slot["quantity"]) == 1:
			produce_found = true
	_check(produce_found, "produce in backpack")
	_check(int(_contribution(runtime.world, owner)["harvesting"]) == 3, "harvest +3 contribution")
	_check(TransactionCoordinator.check_invariants(runtime.world) == "", "invariants hold")


# ---------- 2. 五作物生长日 ----------

func _test_five_crop_growth_days() -> void:
	var ctx := _make()
	var runtime: WorldRuntime = ctx[0]
	var farm: FarmHandlers = ctx[2]
	var owner: String = ctx[3]
	var cases := [
		["seed.radish", 0, 1, "mature"],
		["seed.potato", 1, 2, "mature"],
		["seed.wheat", 2, 2, "mature"],
		["seed.carrot", 3, 3, "mature"],
		["seed.strawberry", 4, 4, "mature"],
	]
	var tile := FARM_TILE
	for entry: Array in cases:
		var seed_id: String = entry[0]
		var slot: int = entry[1]
		var growth_days: int = entry[2]
		_cmd(runtime, owner, "farming.till", {"tile_id": tile})
		var p := _cmd(runtime, owner, "farming.plant", {"tile_id": tile, "seed_slot": slot, "seed_definition_id": seed_id})
		_check(p["accepted"], "plant %s" % seed_id)
		var crop_id: String = runtime.world.plots[str(tile)]["crop_instance_id"]
		# 每日浇水 + 日切，直到成熟
		for day in growth_days:
			_cmd(runtime, owner, "farming.water", {"tile_id": tile})
			_advance_day(runtime)
		_check(int(runtime.world.crops[crop_id]["growth_days"]) == growth_days,
			"%s reaches %d growth days (got %d)" % [seed_id, growth_days, int(runtime.world.crops[crop_id]["growth_days"])])
		_check(farm.stage_of(runtime.world.crops[crop_id]) == "mature", "%s mature stage" % seed_id)
		# 收获并清理，进入下一作物
		var h := _cmd(runtime, owner, "farming.harvest", {"tile_id": tile})
		_check(h["accepted"], "harvest %s" % seed_id)
	# 中途阶段抽查：胡萝卜 2 日应为 growing
	_cmd(runtime, owner, "farming.till", {"tile_id": tile})
	_cmd(runtime, owner, "farming.plant", {"tile_id": tile, "seed_slot": 3, "seed_definition_id": "seed.carrot"})
	var carrot_id: String = runtime.world.plots[str(tile)]["crop_instance_id"]
	for day in 2:
		_cmd(runtime, owner, "farming.water", {"tile_id": tile})
		_advance_day(runtime)
	_check(farm.stage_of(runtime.world.crops[carrot_id]) == "growing", "carrot growing stage at 2 days")
	_check(farm.stage_of(runtime.world.crops[carrot_id]) != "mature", "carrot not mature at 2 days")


# ---------- 3. 浇水去重与成熟后浇水 ----------

func _test_water_dedup_and_mature() -> void:
	var ctx := _make()
	var runtime: WorldRuntime = ctx[0]
	var owner: String = ctx[3]
	_cmd(runtime, owner, "farming.till", {"tile_id": FARM_TILE})
	_cmd(runtime, owner, "farming.plant", {"tile_id": FARM_TILE, "seed_slot": 0, "seed_definition_id": "seed.radish"})
	var first := _cmd(runtime, owner, "farming.water", {"tile_id": FARM_TILE})
	_check(first["accepted"], "first water accepted")
	var second := _cmd(runtime, owner, "farming.water", {"tile_id": FARM_TILE})
	_check(second["accepted"] and second["error_code"] == ContractError.STALE_STATE, "second water same day rejected")
	_check(int(_contribution(runtime.world, owner)["watering"]) == 1, "water counted once")
	# 成熟后浇水不计分
	_advance_day(runtime)
	var mature_water := _cmd(runtime, owner, "farming.water", {"tile_id": FARM_TILE})
	_check(mature_water["error_code"] == ContractError.TARGET_CHANGED, "watering mature crop rejected")
	_check(int(_contribution(runtime.world, owner)["watering"]) == 1, "watering contribution unchanged")
	# 未成熟收获 → 拒绝
	var crop_id: String = runtime.world.plots[str(FARM_TILE)]["crop_instance_id"]
	# 换成草莓（4 天）测试未成熟收获
	_cmd(runtime, owner, "farming.harvest", {"tile_id": FARM_TILE})  # 先收掉萝卜
	_cmd(runtime, owner, "farming.plant", {"tile_id": FARM_TILE, "seed_slot": 4, "seed_definition_id": "seed.strawberry"})
	var early := _cmd(runtime, owner, "farming.harvest", {"tile_id": FARM_TILE})
	_check(early["error_code"] == ContractError.TARGET_CHANGED, "harvest immature rejected")


# ---------- 4. 抢收 ----------

func _test_harvest_concurrency() -> void:
	var ctx := _make()
	var runtime: WorldRuntime = ctx[0]
	var owner: String = ctx[3]
	var second: Dictionary = runtime.world.add_member("队友")
	runtime.world.containers[second["inventory_id"]] = {"capacity": 24, "slots": WorldState.empty_slots(24), "revision": 0}
	second["last_valid_position"] = {"x": PLAYER_X, "y": PLAYER_Y}
	_cmd(runtime, owner, "farming.till", {"tile_id": FARM_TILE})
	_cmd(runtime, owner, "farming.plant", {"tile_id": FARM_TILE, "seed_slot": 0, "seed_definition_id": "seed.radish"})
	_cmd(runtime, owner, "farming.water", {"tile_id": FARM_TILE})
	_advance_day(runtime)
	# 同一作物：第一个成功，第二个 TARGET_CHANGED
	var h1 := _cmd(runtime, owner, "farming.harvest", {"tile_id": FARM_TILE})
	var h2 := _cmd(runtime, second["player_id"], "farming.harvest", {"tile_id": FARM_TILE})
	_check(h1["accepted"] and h1["error_code"] == "", "first harvest succeeds")
	_check(h2["accepted"] and h2["error_code"] == ContractError.TARGET_CHANGED, "second harvest gets TARGET_CHANGED")
	_check(int(_contribution(runtime.world, owner)["harvesting"]) == 3, "only first gets harvest points")
	_check(int(_contribution(runtime.world, second["player_id"])["harvesting"]) == 0, "loser gets no points")
	# 只产生 1 个产物
	var total := 0
	for slot: Variant in runtime.world.containers["backpack:" + owner]["slots"]:
		if slot != null and slot["item_definition_id"] == "produce.radish":
			total += int(slot["quantity"])
	_check(total == 1, "exactly one produce (got %d)" % total)


# ---------- 5. 距离与阻挡 ----------

func _test_range_and_blocking() -> void:
	var ctx := _make()
	var runtime: WorldRuntime = ctx[0]
	var owner: String = ctx[3]
	# 距离过远（远离耕地）
	runtime.world.find_member(owner)["last_valid_position"] = {"x": 200.0, "y": 200.0}
	var far := _cmd(runtime, owner, "farming.till", {"tile_id": FARM_TILE})
	_check(far["error_code"] == ContractError.OUT_OF_RANGE, "too far rejected")
	# 非耕地格（草地）不可整地：站到该格旁（距离校验通过，类型校验拒绝）
	var grass_tile := 30 * 64 + 20  # x=20,y=30 → 草地
	runtime.world.find_member(owner)["last_valid_position"] = {"x": 656.0, "y": 976.0}  # (20.5,30.5)*32
	var grass := _cmd(runtime, owner, "farming.till", {"tile_id": grass_tile})
	_check(grass["error_code"] == ContractError.NOT_ALLOWED, "grass not farmable (got %s)" % str(grass["error_code"]))
	# 阻挡格不可整地（边界）
	var blocked_tile := 0  # x=0,y=0 是阻挡
	runtime.world.find_member(owner)["last_valid_position"] = {"x": 16.0, "y": 16.0}
	var blocked := _cmd(runtime, owner, "farming.till", {"tile_id": blocked_tile})
	_check(blocked["error_code"] != "", "blocked tile rejected")


# ---------- 6. 土地状态 ----------

func _test_untilled_and_planted_states() -> void:
	var ctx := _make()
	var runtime: WorldRuntime = ctx[0]
	var owner: String = ctx[3]
	# 重复整地 → STALE_STATE
	_cmd(runtime, owner, "farming.till", {"tile_id": FARM_TILE})
	var again := _cmd(runtime, owner, "farming.till", {"tile_id": FARM_TILE})
	_check(again["error_code"] == ContractError.STALE_STATE, "tilling tilled plot rejected")
	# 未整地直接播种 → TARGET_CHANGED
	var plant_raw := _cmd(runtime, owner, "farming.plant", {"tile_id": FARM_TILE_2, "seed_slot": 0, "seed_definition_id": "seed.radish"})
	_check(plant_raw["error_code"] == ContractError.TARGET_CHANGED, "plant on untilled rejected")
	# 播种占用后整地 → TARGET_CHANGED
	_cmd(runtime, owner, "farming.plant", {"tile_id": FARM_TILE, "seed_slot": 0, "seed_definition_id": "seed.radish"})
	var till_planted := _cmd(runtime, owner, "farming.till", {"tile_id": FARM_TILE})
	_check(till_planted["error_code"] == ContractError.TARGET_CHANGED, "tilling planted plot rejected")
	# 无种子库存 → 拒绝且不扣物
	var backpack: Dictionary = runtime.world.containers["backpack:" + owner]
	var empty_slot := -1
	for i in backpack["slots"].size():
		if backpack["slots"][i] == null:
			empty_slot = i
			break
	if empty_slot >= 0:
		_cmd(runtime, owner, "farming.till", {"tile_id": FARM_TILE_2})
		var no_seed := _cmd(runtime, owner, "farming.plant", {"tile_id": FARM_TILE_2, "seed_slot": empty_slot, "seed_definition_id": "seed.radish"})
		_check(no_seed["error_code"] == ContractError.INVALID_ARGUMENT, "empty seed slot rejected")
