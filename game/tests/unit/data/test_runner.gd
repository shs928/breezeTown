extends SceneTree
## DATA-01 测试（headless）：正式 WorldRepository 保存/加载、锁、轮转、故障状态、恢复包。
## 运行：godot --headless --path game --script res://tests/unit/data/test_runner.gd

const ContractLimits := preload("res://src/contracts/contract_limits.gd")
const ContractEnvelopes := preload("res://src/contracts/contract_envelopes.gd")
const WorldState := preload("res://src/domain/world/world_state.gd")
const WorldRuntime := preload("res://src/application/world/world_runtime.gd")
const WorldRepository := preload("res://src/infrastructure/persistence/world_repository.gd")
const SaveScheduler := preload("res://src/infrastructure/persistence/save_scheduler.gd")
const ItemCatalog := preload("res://src/domain/economy/item_catalog.gd")
const EconomyHandlers := preload("res://src/application/economy/economy_handlers.gd")

var _checks := 0
var _failures: PackedStringArray = []
var _run_root := ""


func _initialize() -> void:
	_run_root = ProjectSettings.globalize_path("res://../work/game-data/data01/%d" % Time.get_unix_time_from_system())
	DirAccess.make_dir_recursive_absolute(_run_root)

	_test_save_and_load_roundtrip()
	_test_generation_rotation()
	_test_lock_conflict()
	_test_corrupt_latest_fallback()
	_test_save_fault_and_retry()
	_test_manual_backup_survives_rotation()

	if _failures.is_empty():
		print("DATA_OK checks=%d run_dir=%s" % [_checks, _run_root])
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: " + f)
		printerr("DATA_FAILED checks=%d failures=%d" % [_checks, _failures.size()])
		quit(1)


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(label)


func _new_world_dir(name: String) -> String:
	var path := _run_root + "/" + name
	DirAccess.make_dir_recursive_absolute(path + "/snapshots")
	return path


func _make_world() -> WorldState:
	var world_id := "w" + "0123456789abcdef0123456789abcdef"
	return WorldState.create(world_id, "m" + "11111111111111111111111111111111", "房主")


func _make_repo(world_dir: String, world_id: String) -> WorldRepository:
	var repo := WorldRepository.new()
	repo.world_dir = world_dir
	repo.world_id = world_id
	return repo


# ---------- 1. 保存/加载往返 ----------

func _test_save_and_load_roundtrip() -> void:
	var world_dir := _new_world_dir("roundtrip")
	var world := _make_world()
	world.treasury = 457
	world.game_day = 10
	world.containers["backpack:" + world.owner_player_id] = {"capacity": 24, "slots": WorldState.empty_slots(24), "revision": 3}
	world.containers["backpack:" + world.owner_player_id]["slots"][0] = {"item_definition_id": "produce.strawberry", "quantity": 7}
	world.stats["members"][world.owner_player_id]["total_gross_sales"] = 1234
	world.stats["members"][world.owner_player_id]["contribution"]["planting"] = 20
	world.stats["world_total_sales"] = 1234
	world.treasury = 300 + 1234

	var repo := _make_repo(world_dir, world.world_id)
	var save := repo.save(world)
	_check(save["ok"], "save ok (%s)" % str(save["error"]))
	_check(int(save["generation"]) == 1, "first generation is 1")
	var loaded := repo.load_latest()
	_check(loaded["ok"], "load ok")
	var restored: WorldState = loaded["world"]
	_check(restored.game_day == 10, "game_day restored")
	_check(restored.treasury == 300 + 1234, "treasury restored")
	_check(restored.stats["members"][world.owner_player_id]["total_gross_sales"] == 1234, "stats restored")
	_check(restored.containers["backpack:" + world.owner_player_id]["slots"][0]["quantity"] == 7, "inventory restored")
	_check(restored.authority_epoch != world.authority_epoch, "new epoch after load")
	_check(ContractEnvelopes.validate_save_envelope(WorldRepository.normalize_numbers(JSON.parse_string(FileAccess.get_file_as_string(world_dir + "/snapshots/1.json")))) == "", "envelope valid on disk")


# ---------- 2. 轮转 ----------

func _test_generation_rotation() -> void:
	var world_dir := _new_world_dir("rotation")
	var world := _make_world()
	var repo := _make_repo(world_dir, world.world_id)
	for i in 7:
		world.game_day = i + 1
		var result := repo.save(world)
		_check(result["ok"], "save %d" % (i + 1))
	var loaded := repo.load_latest()
	_check(loaded["generation"] == 7, "latest is 7")
	var da := DirAccess.open(world_dir + "/snapshots")
	_check(not da.file_exists("1.json") and not da.file_exists("2.json"), "old generations rotated")
	for gen in [3, 4, 5, 6, 7]:
		_check(da.file_exists("%d.json" % gen), "generation %d kept" % gen)


# ---------- 3. 锁冲突 ----------

func _test_lock_conflict() -> void:
	var world_dir := _new_world_dir("lock")
	var world := _make_world()
	var repo_a := _make_repo(world_dir, world.world_id)
	var claim_a := repo_a.claim_lock()
	_check(claim_a["ok"], "first instance claims lock")
	var repo_b := _make_repo(world_dir, world.world_id)
	var claim_b := repo_b.claim_lock()
	_check(not claim_b["ok"] and claim_b["reason"] == "locked_alive", "second instance rejected")
	repo_a.release_lock()
	var claim_c := repo_b.claim_lock()
	_check(claim_c["ok"], "lock available after release")
	repo_b.release_lock()


# ---------- 4. 损坏最新代回退 ----------

func _test_corrupt_latest_fallback() -> void:
	var world_dir := _new_world_dir("corrupt")
	var world := _make_world()
	var repo := _make_repo(world_dir, world.world_id)
	world.game_day = 1
	repo.save(world)
	world.game_day = 2
	repo.save(world)
	# 破坏最新代
	var f := FileAccess.open(world_dir + "/snapshots/2.json", FileAccess.WRITE)
	f.store_string("{\"format_version\":1,tru")
	f.close()
	var loaded := repo.load_latest()
	_check(loaded["ok"] and loaded["generation"] == 1, "falls back to generation 1")
	_check(loaded["world"].game_day == 1, "restored day 1")
	var da := DirAccess.open(world_dir + "/snapshots")
	_check(da.file_exists("2.json"), "corrupt file preserved")


# ---------- 5. 保存故障与重试 ----------

func _test_save_fault_and_retry() -> void:
	var world_dir := _new_world_dir("fault")
	var world := _make_world()
	var runtime := WorldRuntime.new()
	runtime.setup(world, {})
	var catalog := ItemCatalog.load_from_disk()
	var handlers := EconomyHandlers.new()
	handlers.setup(runtime, catalog)
	var repo := _make_repo(world_dir, world.world_id)
	var scheduler := SaveScheduler.new()
	scheduler.setup(repo, runtime)
	# 正常保存
	_check(scheduler.save_now("test"), "scheduler saves normally")
	_check(not scheduler.is_fault(), "no fault after success")
	# 让仓库指向不可写目录 → 明确失败 → 立即冻结
	repo.world_dir = world_dir + "/snapshots/1.json/nested"  # 非法路径
	var failed := scheduler.save_now("test_fail")
	_check(not failed, "save fails on bad dir")
	_check(scheduler.is_fault(), "immediately enters save fault (no 35s wait)")
	_check(runtime.is_save_fault(), "runtime frozen")
	# 故障时命令被拒
	var receipt := runtime.submit({
		"protocol_version": 1, "world_id": world.world_id, "authority_epoch": world.authority_epoch,
		"client_sequence": 1, "command_type": "profile.update", "payload": {"display_name": "甲"},
		"_actor_player_id": world.owner_player_id,
	})
	_check(not receipt["accepted"], "commands rejected during fault")
	# 恢复路径后重试成功
	repo.world_dir = world_dir
	_check(scheduler.retry(), "retry succeeds after path fixed")
	_check(not scheduler.is_fault() and not runtime.is_save_fault(), "fault cleared")


# ---------- 6. 手动备份不被轮转 ----------

func _test_manual_backup_survives_rotation() -> void:
	var world_dir := _new_world_dir("backup")
	var world := _make_world()
	var repo := _make_repo(world_dir, world.world_id)
	world.game_day = 1
	repo.save(world)
	var backup := repo.backup_now()
	_check(backup["ok"], "manual backup created")
	# 再存 7 代，第 1 代会被轮转
	for i in range(2, 9):
		world.game_day = i
		repo.save(world)
	var da := DirAccess.open(world_dir + "/snapshots")
	_check(not da.file_exists("1.json"), "generation 1 rotated away")
	_check(repo.list_backups().size() == 1, "manual backup retained")
	var backup_file := world_dir + "/backups/" + str(backup["backup_id"]) + "/1.json"
	_check(FileAccess.file_exists(backup_file), "backup content still readable")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(backup_file))
	_check(parsed is Dictionary and ContractEnvelopes.validate_save_envelope(WorldRepository.normalize_numbers(parsed)) == "", "backup envelope valid")
