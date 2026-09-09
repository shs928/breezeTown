extends SceneTree
## DATA-03 测试（headless）：schema 迁移、未来格式拒绝、旧代恢复清空绑定、本机维护重绑。
## 运行：godot --headless --path game --script res://tests/unit/data/data03_test_runner.gd

const ContractEnvelopes := preload("res://src/contracts/contract_envelopes.gd")
const WorldState := preload("res://src/domain/world/world_state.gd")
const WorldRepository := preload("res://src/infrastructure/persistence/world_repository.gd")

var _checks := 0
var _failures: PackedStringArray = []
var _root := ""


func _initialize() -> void:
	_root = ProjectSettings.globalize_path("res://../work/game-data/data03/%d" % Time.get_unix_time_from_system())
	DirAccess.make_dir_recursive_absolute(_root)

	_test_schema_migration()
	_test_future_schema_rejected()
	_test_restore_clears_bindings()
	_test_maintenance_restore_owner()

	if _failures.is_empty():
		print("DATA03_OK checks=%d run_dir=%s" % [_checks, _root])
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: " + f)
		printerr("DATA03_FAILED checks=%d failures=%d" % [_checks, _failures.size()])
		quit(1)


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(label)


func _new_repo(name: String) -> Array:
	var world_dir := _root + "/" + name
	DirAccess.make_dir_recursive_absolute(world_dir + "/snapshots")
	var world := WorldState.create("w" + "0123456789abcdef0123456789abcdef", "m" + "11111111111111111111111111111111", "房主")
	var repo := WorldRepository.new()
	repo.world_dir = world_dir
	repo.world_id = world.world_id
	return [repo, world, world_dir]


# ---------- 1. schema 0 → 1 迁移 ----------

func _test_schema_migration() -> void:
	var parts := _new_repo("migrate")
	var repo: WorldRepository = parts[0]
	var legacy := {
		"schema_version": 0, "world_id": "w" + "0123456789abcdef0123456789abcdef",
		"owner_player_id": "m" + "11111111111111111111111111111111",
		"game_day": 3, "treasury": 100,
	}
	var result := repo.migrate_payload(legacy)
	_check(result["ok"], "schema 0 migrates")
	_check(bool(result["migrated"]), "migration flag set")
	var upgraded: Dictionary = result["payload"]
	_check(int(upgraded["schema_version"]) == 1, "schema upgraded to 1")
	_check(upgraded.has("consent_revision") and upgraded.has("publication_enabled"), "new fields added with defaults")
	_check(int(upgraded["game_day"]) == 3 and int(upgraded["treasury"]) == 100, "existing fields preserved")
	# 已是当前版本 → 不迁移
	var same := repo.migrate_payload({"schema_version": 1})
	_check(same["ok"] and not bool(same["migrated"]), "current schema not migrated")


# ---------- 2. 未来格式拒绝 ----------

func _test_future_schema_rejected() -> void:
	var parts := _new_repo("future")
	var repo: WorldRepository = parts[0]
	var future := repo.migrate_payload({"schema_version": 99})
	_check(not future["ok"] and future["error"] == "future_schema_rejected", "future schema rejected")
	# 加载未来格式代 → 跳过并记录，不丢字段继续
	var world: WorldState = parts[1]
	repo.save(world)
	var f := FileAccess.open(parts[2] + "/snapshots/2.json", FileAccess.WRITE)
	var payload := JSON.stringify(world.to_dict())
	f.store_string(JSON.stringify({
		"format_version": 99, "world_id": world.world_id, "generation": 2,
		"payload_json": payload, "payload_sha256": payload.sha256_text(),
	}))
	f.close()
	var loaded := repo.load_latest()
	_check(loaded["ok"] and loaded["generation"] == 1, "future envelope skipped on load")
	_check(FileAccess.file_exists(parts[2] + "/snapshots/2.json"), "future file preserved")


# ---------- 3. 旧代恢复清空绑定与同意 ----------

func _test_restore_clears_bindings() -> void:
	var parts := _new_repo("restore")
	var repo: WorldRepository = parts[0]
	var world: WorldState = parts[1]
	world.find_member(world.owner_player_id)["credential_digest"] = "a".repeat(64)
	world.find_member(world.owner_player_id)["publication_consent"] = true
	world.publication_enabled = true
	world.consent_revision = 5
	repo.save(world)
	# 再加一代
	world.game_day = 2
	repo.save(world)
	# 恢复到第 1 代
	var restored := repo.restore_generation(1)
	_check(restored["ok"], "restore generation 1")
	var restored_world: WorldState = restored["world"]
	_check(restored_world.find_member(restored_world.owner_player_id)["credential_digest"] == "", "credential bindings cleared")
	_check(not bool(restored_world.find_member(restored_world.owner_player_id)["publication_consent"]), "publication consent cleared")
	_check(not restored_world.publication_enabled, "world publication disabled")
	_check(restored_world.consent_revision > 5, "consent revision bumped")
	_check(restored_world.game_day == 1, "restored to generation 1 content")
	# 原件保留
	_check(FileAccess.file_exists(parts[2] + "/restore_preserved/1-before-restore.json"), "original preserved")
	# 恢复后发布为新代，不覆盖旧代
	_check(FileAccess.file_exists(parts[2] + "/snapshots/1.json"), "generation 1 not overwritten")


# ---------- 4. 本机维护恢复所有者 ----------

func _test_maintenance_restore_owner() -> void:
	var parts := _new_repo("maintenance")
	var repo: WorldRepository = parts[0]
	var world: WorldState = parts[1]
	world.find_member(world.owner_player_id)["credential_digest"] = ""
	repo.save(world)
	# 有锁时拒绝
	repo.claim_lock()
	var locked := repo.maintenance_restore_owner("b".repeat(64))
	_check(not locked["ok"] and locked["error"] == "world_still_locked", "maintenance rejected while locked")
	repo.release_lock()
	# 无锁时成功
	var result := repo.maintenance_restore_owner("b".repeat(64))
	_check(result["ok"], "maintenance restore owner succeeds")
	var loaded := repo.load_latest()
	_check(loaded["world"].find_member(loaded["world"].owner_player_id)["credential_digest"] == "b".repeat(64), "new owner digest applied")
	_check(loaded["world"].find_member(loaded["world"].owner_player_id)["status"] == "active", "owner reactivated")
	# 非法摘要拒绝
	var bad := repo.maintenance_restore_owner("short")
	_check(not bad["ok"] and bad["error"] == "bad_digest", "bad digest rejected")
