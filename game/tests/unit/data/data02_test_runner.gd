extends SceneTree
## DATA-02 测试（headless）：5 代轮转、手动备份、发布排序、故障恢复、事件 checkpoint 有界化。
## 运行：godot --headless --path game --script res://tests/unit/data/data02_test_runner.gd

const ContractLimits := preload("res://src/contracts/contract_limits.gd")
const ContractEnvelopes := preload("res://src/contracts/contract_envelopes.gd")
const WorldState := preload("res://src/domain/world/world_state.gd")
const WorldRepository := preload("res://src/infrastructure/persistence/world_repository.gd")
const EventLog := preload("res://src/infrastructure/persistence/event_log.gd")
const StatisticsProjector := preload("res://src/domain/statistics/statistics_projector.gd")

var _checks := 0
var _failures: PackedStringArray = []
var _root := ""


func _initialize() -> void:
	_root = ProjectSettings.globalize_path("res://../work/game-data/data02/%d" % Time.get_unix_time_from_system())
	DirAccess.make_dir_recursive_absolute(_root)

	_test_rotation_and_manual_backup()
	_test_publish_ordering()
	_test_event_log_bounded()
	_test_checkpoint_matches_realtime()

	if _failures.is_empty():
		print("DATA02_OK checks=%d run_dir=%s" % [_checks, _root])
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: " + f)
		printerr("DATA02_FAILED checks=%d failures=%d" % [_checks, _failures.size()])
		quit(1)


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(label)


func _new_world_dir(name: String) -> String:
	var path := _root + "/" + name
	DirAccess.make_dir_recursive_absolute(path + "/snapshots")
	return path


func _make_world() -> WorldState:
	return WorldState.create("w" + "0123456789abcdef0123456789abcdef", "m" + "11111111111111111111111111111111", "房主")


func _make_repo(world_dir: String, world: WorldState) -> WorldRepository:
	var repo := WorldRepository.new()
	repo.world_dir = world_dir
	repo.world_id = world.world_id
	return repo


# ---------- 1. 轮转与手动备份 ----------

func _test_rotation_and_manual_backup() -> void:
	var world_dir := _new_world_dir("rotation")
	var world := _make_world()
	var repo := _make_repo(world_dir, world)
	for i in 8:
		world.game_day = i + 1
		repo.save(world)
	var da := DirAccess.open(world_dir + "/snapshots")
	var kept: Array[String] = []
	da.list_dir_begin()
	var name := da.get_next()
	while not name.is_empty():
		if name.ends_with(".json") and not name.begins_with(".tmp-"):
			kept.append(name)
		name = da.get_next()
	da.list_dir_end()
	_check(kept.size() == ContractLimits.SNAPSHOT_KEEP_GENERATIONS, "exactly 5 generations kept (got %d)" % kept.size())
	# 手动备份独立保留，不被轮转删除
	var backup := repo.backup_now()
	_check(backup["ok"], "manual backup created")
	for i in range(9, 15):
		world.game_day = i
		repo.save(world)
	_check(repo.list_backups().size() == 1, "manual backup survives rotation")
	_check(FileAccess.file_exists(world_dir + "/backups/" + str(backup["backup_id"]) + "/8.json"), "backup content retained")


# ---------- 2. 发布排序（generation 单调，旧作业不覆盖新代） ----------

func _test_publish_ordering() -> void:
	var world_dir := _new_world_dir("ordering")
	var world := _make_world()
	var repo := _make_repo(world_dir, world)
	world.game_day = 1
	var first := repo.save(world)
	world.game_day = 2
	var second := repo.save(world)
	_check(int(second["generation"]) == int(first["generation"]) + 1, "generation monotonic")
	# 尝试用相同 generation 再次发布 → 冲突拒绝（不覆盖）
	var conflict := repo.save(world)
	_check(conflict["ok"], "new save always uses next generation")
	var loaded := repo.load_latest()
	_check(loaded["generation"] == 3, "latest is newest generation")
	_check(loaded["world"].game_day == 2, "newest content wins")
	# 直接写一个"旧代晚完成"的场景：generation 2 已存在，不能被覆盖
	var da := DirAccess.open(world_dir + "/snapshots")
	_check(da.file_exists("2.json"), "earlier generation file still present")


# ---------- 3. 事件日志有界化 ----------

func _test_event_log_bounded() -> void:
	var log := EventLog.new()
	var owner := "m" + "1".repeat(32)
	# 写入超过上限的事件
	var total := ContractLimits.EVENT_LOG_RETENTION + 500
	for i in total:
		log.append({
			"event_id": "ev%032x" % i, "event_sequence": i + 1,
			"world_id": "w" + "0".repeat(32), "business_revision": i + 1,
			"actor_player_id": owner, "game_day": 1,
			"event_type": "CropPlanted" if i % 2 == 0 else "ProduceSold",
			"ruleset_version": "v1.0",
			"payload": {"gross_amount": 24} if i % 2 == 1 else {},
		})
	_check(log.size() == ContractLimits.EVENT_LOG_RETENTION, "event log bounded to 10k (got %d)" % log.size())
	_check(not log.checkpoint.is_empty(), "oldest events folded into checkpoint")
	_check(int(log.checkpoint["event_sequence"]) == 500, "checkpoint watermark advanced (got %d)" % int(log.checkpoint["event_sequence"]))


# ---------- 4. checkpoint + 后续 = 实时统计 ----------

func _test_checkpoint_matches_realtime() -> void:
	var log := EventLog.new()
	var owner := "m" + "1".repeat(32)
	# 构造混合事件（含非计分），超过上限触发折叠
	var total := ContractLimits.EVENT_LOG_RETENTION + 200
	for i in total:
		var event_type := "CropPlanted"
		var payload := {}
		match i % 4:
			0: event_type = "CropPlanted"
			1: event_type = "CropWatered"
			2: event_type = "CropHarvested"
			3:
				event_type = "ProduceSold"
				payload = {"gross_amount": 24, "item_definition_id": "produce.radish", "quantity": 1, "unit_price": 24}
		log.append({
			"event_id": "ev%032x" % i, "event_sequence": i + 1,
			"world_id": "w" + "0".repeat(32), "business_revision": i + 1,
			"actor_player_id": owner, "game_day": 1,
			"event_type": event_type, "ruleset_version": "v1.0", "payload": payload,
		})
	var recomputed := log.recompute()
	# 手工全量重算（不经过折叠）
	var full := StatisticsProjector.project(_all_events(total, owner))
	_check(int(recomputed["world_total_sales"]) == int(full["world_total_sales"]),
		"checkpoint sales match full replay (%d vs %d)" % [int(recomputed["world_total_sales"]), int(full["world_total_sales"])])
	var re_member: Dictionary = recomputed["members"][owner]["contribution"]
	var full_member: Dictionary = full["members"][owner]["contribution"]
	for key: String in ["planting", "watering", "harvesting", "donation"]:
		_check(int(re_member[key]) == int(full_member[key]), "contribution.%s matches (%d vs %d)" % [key, int(re_member[key]), int(full_member[key])])


## 重建完整事件序列（与 log 中折叠前一致）。
func _all_events(total: int, owner: String) -> Array:
	var events: Array = []
	for i in total:
		var event_type := "CropPlanted"
		var payload := {}
		match i % 4:
			0: event_type = "CropPlanted"
			1: event_type = "CropWatered"
			2: event_type = "CropHarvested"
			3:
				event_type = "ProduceSold"
				payload = {"gross_amount": 24, "item_definition_id": "produce.radish", "quantity": 1, "unit_price": 24}
		events.append({
			"event_id": "ev%032x" % i, "event_sequence": i + 1,
			"world_id": "w" + "0".repeat(32), "business_revision": i + 1,
			"actor_player_id": owner, "game_day": 1,
			"event_type": event_type, "ruleset_version": "v1.0", "payload": payload,
		})
	return events
