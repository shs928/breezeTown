extends SceneTree
## FARM-01：季节种植/轮作、体力、工具升级、动物饲养/购买/产出的玩法验证。
## 用法：BREEZETOWN_SAVE_ROOT="$PWD/work/game-data/farm" \
##   Godot --headless --path game --script res://scripts/tests/farm_checks.gd

const SaveManager := preload("res://scripts/core/save_manager.gd")
const GameState := preload("res://scripts/game_state.gd")
const Definition := preload("res://scripts/data/first_map_definition.gd")
var failures: Array[String] = []
var count := 0
var game: Node3D


func _initialize() -> void:
	create_timer(180).timeout.connect(func(): push_error("FARM_CHECKS timeout"); quit(1))
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1600, 1000)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	for i in range(5):
		await physics_frame
	await process_frame
	_check("new-game-trough-prefilled", game.trough.filled)
	_check("new-game-energy-full", game.state.energy == GameState.MAX_ENERGY)
	_check("new-game-feed-stocked", game.state.feed == 4)
	_season_and_rotation()
	_energy_and_upgrades()
	_fertilizer_quality_xp()
	await _animals_and_save()
	print("FARM_RESULT %s %d checks" % ["PASS" if failures.is_empty() else "FAIL " + ",".join(failures), count])
	quit(0 if failures.is_empty() else 1)


func _till_fresh() -> Vector2i:
	## 在农场菜园附近找一块空草格整地，返回键。
	for gx in range(-345, -300):
		for gz in range(118, 135):
			var key := Vector2i(gx, gz)
			if not game.tiles.farm.has_tile(key) and game.tiles.is_open(key):
				if game.tiles.till(key):
					return key
	return Vector2i.ZERO


func _season_and_rotation() -> void:
	var farm = game.tiles.farm
	var key := _till_fresh()
	_check("tillage-works-on-open-grass", key != Vector2i.ZERO and farm.data_of(key).state == "tilled")
	_check("plant-in-season", farm.plant(key, "radish", "spring"))
	var bad_key := _till_fresh()
	_check("plant-out-of-season-rejected", bad_key != Vector2i.ZERO and not farm.plant(bad_key, "wheat", "spring"))
	# 换季枯萎：夏小麦长着，入冬即枯回裸土。
	var wheat_key := _till_fresh()
	farm.plant(wheat_key, "wheat")
	var data = farm.data_of(wheat_key)
	data.watered = true
	farm.rollover()
	_check("crop-alive-before-season-change", farm.data_of(wheat_key).state == "planted")
	var withered: int = farm.wither_out_of_season("winter")
	_check("season-change-withers-crop", withered >= 1 and farm.data_of(wheat_key).state == "tilled")
	# 轮作：萝卜 2 天熟；连作同茬首夜不生长，换茬恢复。
	var rotate_key := _till_fresh()
	farm.plant(rotate_key, "radish", "spring")
	var rd = farm.data_of(rotate_key)
	rd.watered = true
	farm.rollover()
	farm.data_of(rotate_key).watered = true
	farm.rollover()
	_check("rotation-first-crop-matures", farm.data_of(rotate_key).is_mature())
	var kind: String = farm.harvest(rotate_key)
	_check("rotation-harvest-records-last-crop", kind == "radish" and farm.data_of(rotate_key).last_crop == "radish")
	farm.plant(rotate_key, "radish", "spring")
	var rd2 = farm.data_of(rotate_key)
	_check("rotation-replant-marked", rd2.rotation_pending)
	rd2.watered = true
	farm.rollover()
	_check("rotation-delays-growth", not farm.data_of(rotate_key).is_mature())
	rd2 = farm.data_of(rotate_key)
	rd2.watered = true
	farm.rollover()
	_check("rotation-growth-resumes", farm.data_of(rotate_key).stage == 1 and not farm.data_of(rotate_key).is_mature())
	farm.data_of(rotate_key).watered = true
	farm.rollover()
	_check("rotation-recovers-next-night", farm.data_of(rotate_key).is_mature())


func _energy_and_upgrades() -> void:
	var state = game.state
	state.energy = 100.0
	_check("hoe-energy-cost-base", absf(state.tool_energy_cost("hoe") - 2.0) < 0.001)
	state.spend_energy(state.tool_energy_cost("hoe"))
	_check("spend-energy-deducts", absf(state.energy - 98.0) < 0.001)
	state.energy = 1.0
	_check("spend-energy-blocks-when-tired", not state.spend_energy(2.0))
	var rations_before: int = state.rations
	state.eat_ration()
	_check("ration-restores-energy", state.energy > 1.0 and state.rations == rations_before - 1)
	# 工具升级：金币+铜双扣费，2 级系数 0.6。
	state.coins = 1000
	state.minerals["copper"] = 10
	_check("buy-upgrade-succeeds", state.buy_tool_upgrade("can"))
	_check("tool-level-raised", state.tool_level("can") == 2)
	_check("upgrade-costs-deducted", state.coins == 750 and state.minerals["copper"] == 7)
	_check("upgraded-tool-cheaper", absf(state.tool_energy_cost("can") - 0.6) < 0.001)
	state.coins = 10
	_check("buy-upgrade-without-funds-fails", not state.buy_tool_upgrade("can"))
	state.coins = 5000
	state.minerals["iron"] = 5
	_check("buy-upgrade-to-max", state.buy_tool_upgrade("can"))
	_check("buy-upgrade-at-max-fails", not state.buy_tool_upgrade("can"))
	_check("max-tool-cheapest", absf(state.tool_energy_cost("can") - 0.3) < 0.001)


func _fertilizer_quality_xp() -> void:
	var state = game.state
	var farm = game.tiles.farm
	# 肥料：施肥作物每个浇水的夜晚多长一阶（萝卜 2 天 → 一夜成熟）。
	var fert_key := _till_fresh()
	farm.plant(fert_key, "radish", "spring", true)
	var fd = farm.data_of(fert_key)
	_check("fertilized-flag-set", fd.fertilized)
	fd.watered = true
	farm.rollover()
	_check("fertilizer-speeds-growth", farm.data_of(fert_key).is_mature())
	# 品质折价：4 株萝卜（银 2 金 1）售价 = 8 + 2×12 + 1×16 = 44。
	state.harvest["radish"] = 4
	state.harvest_quality["silver"]["radish"] = 2
	state.harvest_quality["gold"]["radish"] = 1
	var coins_before: int = state.coins
	var earned: int = state.sell_all_harvest()
	_check("quality-sell-math", earned == 48 and state.coins == coins_before + 48)
	_check("quality-cleared-on-sell", state.harvest_quality["gold"]["radish"] == 0)
	var rng := RandomNumberGenerator.new()
	_check("quality-roll-returns-tier", state.roll_harvest_quality(true, rng) in ["normal", "silver", "gold"])
	# 经验与等级：每级 100 经验，升级 +10 体力上限。
	state.xp = 90
	state.level = 1
	state.energy = state.energy_max()
	var gained: int = state.gain_xp(20)
	_check("xp-levels-up", gained == 1 and state.level == 2 and state.xp == 10)
	_check("level-raises-energy-cap", state.energy_max() == 110)
	# 建筑扩容：金币+木材+石料，谷仓每级 4 格。
	state.coins = 1000
	state.forestry["wood"] = 20
	state.minerals["stone"] = 10
	_check("buy-building-upgrade", state.buy_building_upgrade("barn"))
	_check("building-level-and-costs", state.building_levels["barn"] == 2 and state.coins == 200 and state.forestry["wood"] == 0 and state.minerals["stone"] == 0)
	_check("barn-capacity-raised", state.building_capacity("barn") == 8)
	state.coins = 5
	_check("building-upgrade-without-funds-fails", not state.buy_building_upgrade("coop"))
	# 伤害倍率：镐/斧 1.0/1.5/2.0 随等级。
	_check("tool-power-base", state.tool_power("pickaxe") == 1.0)
	state.tool_levels["pickaxe"] = 2
	_check("tool-power-scaled", absf(state.tool_power("pickaxe") - 1.5) < 0.001)
	state.tool_levels["pickaxe"] = 1


func _animals_and_save() -> void:
	var state = game.state
	var animals_before: int = game.animals.size()
	state.coins = 500
	game._on_buy("animal:chicken", 1)
	_check("buy-animal-adds-to-pasture", game.animals.size() == animals_before + 1 and game.pastures[0].animals.size() == animals_before + 1)
	var new_animal = game.animals[game.animals.size() - 1]
	_check("bought-animal-is-chicken-in-home", new_animal.data.kind == "chicken" and new_animal.data.home_index == 0)
	# 喂养产出：清空预填槽 → 花饲料填槽 → 睡觉产出、好感+20、槽清空。
	game.pastures[0].trough.set_filled(false)
	state.feed = 3
	state.coins = 0
	game.fill_trough(game.pastures[0].trough)
	_check("fill-trough-consumes-feed", state.feed == 2 and game.pastures[0].trough.filled)
	var friendship_before: int = new_animal.data.friendship
	game._do_sleep()
	_check("fed-night-produces", game.pickups.size() >= game.animals.size())
	_check("fed-night-raises-friendship", new_animal.data.friendship == friendship_before + 20)
	_check("trough-cleared-after-night", not game.pastures[0].trough.filled)
	var pickups_before: int = game.pickups.size()
	game._do_sleep()
	_check("starved-night-produces-nothing", game.pickups.size() == pickups_before)
	_check("starved-night-lowers-friendship", new_animal.data.friendship == friendship_before + 10)
	# 好感 ≥400：产出翻倍（确定性阈值）。
	new_animal.data.friendship = 400
	state.feed = 1
	game.fill_trough(game.pastures[0].trough)
	pickups_before = game.pickups.size()
	game._do_sleep()
	_check("high-friendship-doubles-output", game.pickups.size() == pickups_before + game.animals.size() + 1)
	# 存读档闭环：经济/体力/饲料/矿物/工具等级/动物/二轮字段往返一致。
	state.coins = 777
	state.energy = 55.0
	state.feed = 9
	state.fertilizer = 7
	state.level = 3
	state.minerals["iron"] = 4
	SaveManager.save_game(1, game._save_payload())
	var saved: Dictionary = SaveManager.load_game(1)
	_check("save-writes-ok", saved.get("ok", false))
	game._apply_load(saved)
	_check("load-restores-economy", game.state.coins == 777 and int(game.state.energy) == 55 and game.state.feed == 9 and game.state.minerals["iron"] == 4)
	_check("load-restores-round-two", game.state.fertilizer == 7 and game.state.level == 3 and game.state.building_levels["barn"] == 2)
	_check("load-restores-tool-levels", game.state.tool_level("can") == 3)
	_check("load-restores-animals", game.animals.size() == animals_before + 1)
	var npc_ground := Definition.point([840, 150])
	_check("npc-land-still-protected", not game.tiles.is_open(Vector2i((npc_ground / 2.0).round())))


func _check(label: String, result: bool) -> void:
	count += 1
	print("FARM ", label, " ", "OK" if result else "FAIL")
	if not result:
		failures.append(label)
