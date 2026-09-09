extends SceneTree
## ECON-02 测试（headless）：三榜定义、并列竞赛名次、稳定顺序、贡献分类、事件投影一致性。
## 运行：godot --headless --path game --script res://tests/unit/economy/stats_test_runner.gd

const ContractLimits := preload("res://src/contracts/contract_limits.gd")
const WorldState := preload("res://src/domain/world/world_state.gd")
const Leaderboard := preload("res://src/domain/statistics/leaderboard.gd")
const StatisticsProjector := preload("res://src/domain/statistics/statistics_projector.gd")

var _checks := 0
var _failures: PackedStringArray = []


func _initialize() -> void:
	_test_ranking_and_ties()
	_test_stable_order()
	_test_member_detail()
	_test_projection_matches_materialized()
	_test_revoke_and_offline_kept()
	_test_sales_do_not_add_contribution()

	if _failures.is_empty():
		print("STATS_OK checks=%d" % _checks)
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: " + f)
		printerr("STATS_FAILED checks=%d failures=%d" % [_checks, _failures.size()])
		quit(1)


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(label)


func _make_world_with_members(count: int) -> Array:
	var world := WorldState.create("w" + "0123456789abcdef0123456789abcdef", "m" + "11111111111111111111111111111111", "房主")
	var ids: Array[String] = [world.owner_player_id]
	for i in range(1, count):
		var member: Dictionary = world.add_member("成员%d" % i)
		ids.append(member["player_id"])
	return [world, ids]


func _set_sales(world: WorldState, player_id: String, total: int, today: int) -> void:
	world.stats["members"][player_id]["total_gross_sales"] = total
	world.stats["members"][player_id]["today_gross_sales"] = today


func _set_contribution(world: WorldState, player_id: String, key: String, value: int) -> void:
	world.stats["members"][player_id]["contribution"][key] = value


# ---------- 1. 名次与并列 ----------

func _test_ranking_and_ties() -> void:
	var ctx := _make_world_with_members(4)
	var world: WorldState = ctx[0]
	var ids: Array = ctx[1]
	_set_sales(world, ids[0], 240, 96)
	_set_sales(world, ids[1], 240, 144)
	_set_sales(world, ids[2], 48, 0)
	_set_sales(world, ids[3], 0, 0)
	_set_contribution(world, ids[0], "planting", 10)
	_set_contribution(world, ids[1], "planting", 6)
	_set_contribution(world, ids[2], "harvesting", 3)
	var boards := Leaderboard.build(world)
	var total_rows: Array = boards["total_gross_sales"]
	_check(total_rows.size() == 4, "all members listed including 0-score")
	_check(total_rows[0]["rank"] == 1 and total_rows[1]["rank"] == 1, "tie both rank 1")
	_check(total_rows[2]["rank"] == 3, "next rank skips to 3")
	_check(total_rows[3]["rank"] == 4 and total_rows[3]["value"] == 0, "zero-score member keeps rank 4")
	var today_rows: Array = boards["today_gross_sales"]
	_check(today_rows[0]["value"] == 144 and today_rows[0]["rank"] == 1, "today board sorted by today value")
	_check(today_rows[1]["value"] == 96 and today_rows[1]["rank"] == 2, "today board distinct from total")
	var contribution_rows: Array = boards["contribution_total"]
	_check(contribution_rows[0]["value"] == 10, "contribution board uses contribution total")


# ---------- 2. 并列内稳定顺序 ----------

func _test_stable_order() -> void:
	var ctx := _make_world_with_members(3)
	var world: WorldState = ctx[0]
	var ids: Array = ctx[1]
	# 三人同分：应按加入顺序稳定（ids[0] 先加入）
	for id: String in ids:
		_set_sales(world, id, 100, 50)
	var boards := Leaderboard.build(world)
	var rows: Array = boards["total_gross_sales"]
	_check(rows[0]["player_id"] == ids[0] and rows[1]["player_id"] == ids[1] and rows[2]["player_id"] == ids[2],
		"ties ordered by join_order")
	_check(rows[0]["rank"] == 1 and rows[1]["rank"] == 1 and rows[2]["rank"] == 1, "all tied at rank 1")


# ---------- 3. 个人明细 ----------

func _test_member_detail() -> void:
	var ctx := _make_world_with_members(1)
	var world: WorldState = ctx[0]
	var owner: String = ctx[1][0]
	_set_contribution(world, owner, "planting", 8)
	_set_contribution(world, owner, "watering", 4)
	_set_contribution(world, owner, "harvesting", 6)
	_set_contribution(world, owner, "donation", 2)
	var detail := Leaderboard.member_detail(world, owner)
	_check(detail["contribution_breakdown"]["planting"] == 8, "detail planting")
	_check(detail["contribution_breakdown"]["watering"] == 4, "detail watering")
	_check(detail["contribution_breakdown"]["harvesting"] == 6, "detail harvesting")
	_check(detail["contribution_breakdown"]["donation"] == 2, "detail donation")
	_check(detail["ruleset_version"] == world.ruleset_version, "detail carries ruleset version")
	_check(detail["game_day"] == world.game_day, "detail carries game day")


# ---------- 4. 投影与物化一致 ----------

func _test_projection_matches_materialized() -> void:
	var ctx := _make_world_with_members(2)
	var world: WorldState = ctx[0]
	var ids: Array = ctx[1]
	var events: Array = [
		{"event_id": "ev1", "event_sequence": 1, "world_id": world.world_id, "business_revision": 1,
			"actor_player_id": ids[0], "game_day": 1, "event_type": "CropPlanted", "ruleset_version": "v1.0",
			"payload": {"tile_id": 1950, "crop_instance_id": "ci1", "crop_definition_id": "crop.radish"}},
		{"event_id": "ev2", "event_sequence": 2, "world_id": world.world_id, "business_revision": 2,
			"actor_player_id": ids[0], "game_day": 1, "event_type": "CropWatered", "ruleset_version": "v1.0",
			"payload": {"tile_id": 1950, "crop_instance_id": "ci1", "game_day": 1}},
		{"event_id": "ev3", "event_sequence": 3, "world_id": world.world_id, "business_revision": 3,
			"actor_player_id": ids[1], "game_day": 2, "event_type": "CropHarvested", "ruleset_version": "v1.0",
			"payload": {"tile_id": 1950, "crop_instance_id": "ci1", "produce_definition_id": "produce.radish", "quantity": 1}},
		{"event_id": "ev4", "event_sequence": 4, "world_id": world.world_id, "business_revision": 4,
			"actor_player_id": ids[1], "game_day": 2, "event_type": "ProduceSold", "ruleset_version": "v1.0",
			"payload": {"item_definition_id": "produce.radish", "quantity": 10, "unit_price": 24, "gross_amount": 240}},
		{"event_id": "ev5", "event_sequence": 5, "world_id": world.world_id, "business_revision": 5,
			"actor_player_id": ids[0], "game_day": 2, "event_type": "SeedPurchased", "ruleset_version": "v1.0",
			"payload": {"seed_definition_id": "seed.radish", "quantity": 10, "unit_price": 15, "total_amount": 150}},
	]
	var projected := StatisticsProjector.project(events)
	# 手工构造与投影一致的物化视图
	world.stats["members"][ids[0]]["contribution"]["planting"] = 2
	world.stats["members"][ids[0]]["contribution"]["watering"] = 1
	world.stats["members"][ids[1]]["contribution"]["harvesting"] = 3
	world.stats["members"][ids[1]]["total_gross_sales"] = 240
	world.stats["world_total_sales"] = 240
	world.stats["world_total_purchases"] = 150
	world.stats["last_applied_event_seq"] = 5
	var materialized := StatisticsProjector.snapshot(world)
	_check(StatisticsProjector.compare(projected, materialized) == "", "projection matches materialized")
	# 重复投影同一批事件不重复计数
	var again := StatisticsProjector.project(events, {"members": projected["members"], "world_total_sales": projected["world_total_sales"], "world_total_purchases": projected["world_total_purchases"], "last_event_seq": projected["last_event_seq"]})
	_check(int(again["world_total_sales"]) == 240, "re-projection is idempotent")
	_check(int(again["applied_count"]) == 0, "duplicate events not applied again")
	# 对账
	var recon := Leaderboard.reconcile(world)
	_check(recon["ok"], "reconciliation ok")


# ---------- 5. 撤销与离线保留历史行 ----------

func _test_revoke_and_offline_kept() -> void:
	var ctx := _make_world_with_members(3)
	var world: WorldState = ctx[0]
	var ids: Array = ctx[1]
	_set_sales(world, ids[0], 100, 50)
	_set_sales(world, ids[1], 200, 60)
	_set_sales(world, ids[2], 50, 10)
	# 撤销成员 ids[1]：保留历史行并标记
	world.find_member(ids[1])["status"] = "revoked"
	# 离线成员：online 列表为空
	var boards := Leaderboard.build(world, [])
	var rows: Array = boards["total_gross_sales"]
	var revoked_row := {}
	for row: Dictionary in rows:
		if row["player_id"] == ids[1]:
			revoked_row = row
	_check(not revoked_row.is_empty(), "revoked member keeps history row")
	_check(revoked_row["status"] == "revoked", "revoked member marked")
	_check(revoked_row["value"] == 200, "revoked member keeps score")
	_check(rows[0]["online"] == false, "offline members shown as offline")
	# 改名不新建行
	world.find_member(ids[0])["display_name"] = "新昵称"
	var boards2 := Leaderboard.build(world, [])
	_check((boards2["total_gross_sales"] as Array).size() == 3, "rename does not create new row")


# ---------- 6. 出售不计贡献 ----------

func _test_sales_do_not_add_contribution() -> void:
	var ctx := _make_world_with_members(1)
	var world: WorldState = ctx[0]
	var owner: String = ctx[1][0]
	var events: Array = [
		{"event_id": "ev1", "event_sequence": 1, "world_id": world.world_id, "business_revision": 1,
			"actor_player_id": owner, "game_day": 1, "event_type": "ProduceSold", "ruleset_version": "v1.0",
			"payload": {"item_definition_id": "produce.radish", "quantity": 10, "unit_price": 24, "gross_amount": 240}},
	]
	var projected := StatisticsProjector.project(events)
	var contribution: Dictionary = projected["members"][owner]["contribution"]
	var total := 0
	for key: String in contribution:
		total += int(contribution[key])
	_check(total == 0, "selling adds zero contribution")
	_check(int(projected["members"][owner]["total_gross_sales"]) == 240, "selling still adds gross sales")
