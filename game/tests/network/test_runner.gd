extends SceneTree
## NET-00 测试（headless）：本地身份创建/持久化/校验、创建世界后激活、继续世界复用身份。
## 运行：godot --headless --path game --script res://tests/network/test_runner.gd

const ContractLimits := preload("res://src/contracts/contract_limits.gd")
const ContractError := preload("res://src/contracts/contract_error.gd")
const LocalIdentity := preload("res://src/infrastructure/identity/local_identity.gd")
const LocalSession := preload("res://src/application/session/local_session.gd")
const WorldState := preload("res://src/domain/world/world_state.gd")

var _checks := 0
var _failures: PackedStringArray = []
var _root := ""


func _initialize() -> void:
	_root = ProjectSettings.globalize_path("res://../work/game-data/net00/%d" % Time.get_unix_time_from_system())
	DirAccess.make_dir_recursive_absolute(_root)

	_test_identity_create_and_verify()
	_test_credential_not_in_world()
	_test_create_world_activates_after_save()
	_test_continue_reuses_identity()
	_test_continue_requires_identity()
	_test_close_saves_and_releases()

	if _failures.is_empty():
		print("NET00_OK checks=%d" % _checks)
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: " + f)
		printerr("NET00_FAILED checks=%d failures=%d" % [_checks, _failures.size()])
		quit(1)


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(label)


func _fresh_dirs(name: String) -> Array:
	var base := _root + "/" + name
	var user_data := base + "/user_data"
	var worlds := base + "/worlds"
	DirAccess.make_dir_recursive_absolute(user_data)
	DirAccess.make_dir_recursive_absolute(worlds)
	return [user_data, worlds]


# ---------- 1. 身份创建与校验 ----------

func _test_identity_create_and_verify() -> void:
	var dirs := _fresh_dirs("identity")
	var world_id := "w" + "0123456789abcdef0123456789abcdef"
	var created := LocalIdentity.create(dirs[0], world_id)
	_check(created["ok"], "identity created")
	_check(created["credential"].length() == 64, "credential is 256-bit hex")
	_check(created["digest"].length() == 64, "digest is sha256 hex")
	_check(LocalIdentity.exists(dirs[0], world_id), "identity exists on disk")
	_check(LocalIdentity.verify(dirs[0], world_id, created["credential"]), "correct credential verifies")
	_check(not LocalIdentity.verify(dirs[0], world_id, "0".repeat(64)), "wrong credential rejected")
	_check(LocalIdentity.load_digest(dirs[0], world_id) == created["digest"], "digest persists")
	# 两个世界各自独立
	var world_id2 := "w" + "11111111111111111111111111111111"
	LocalIdentity.create(dirs[0], world_id2)
	_check(LocalIdentity.load_digest(dirs[0], world_id) != LocalIdentity.load_digest(dirs[0], world_id2), "identities are per-world")


# ---------- 2. 凭据不进世界明文 ----------

func _test_credential_not_in_world() -> void:
	var dirs := _fresh_dirs("no_leak")
	var session := LocalSession.new()
	var result := session.create_world(dirs[0], dirs[1], "房主", "测试世界")
	_check(result["ok"], "world created (%s)" % str(result["error"]))
	var world_id: String = result["world_id"]
	var credential: String = session.credential
	_check(not credential.is_empty(), "session holds credential")
	# 世界快照文件不得包含凭据明文
	var snapshot_path: String = dirs[1] + "/" + world_id + "/snapshots/1.json"
	var snapshot_text := FileAccess.get_file_as_string(snapshot_path)
	_check(not snapshot_text.contains(credential), "world snapshot contains no plaintext credential")
	_check(snapshot_text.contains(credential.sha256_text()), "world snapshot stores digest only")
	# 世界成员记录里有摘要
	var owner: Dictionary = session.world.find_member(session.player_id)
	_check(owner["credential_digest"] == credential.sha256_text(), "member stores digest")
	session.close()


# ---------- 3. 创建世界在首次保存后激活 ----------

func _test_create_world_activates_after_save() -> void:
	var dirs := _fresh_dirs("create")
	var session := LocalSession.new()
	_check(not session.is_active(), "session inactive before create")
	var result := session.create_world(dirs[0], dirs[1], "房主", "我的小镇")
	_check(result["ok"] and session.is_active(), "session active after successful create")
	_check(FileAccess.file_exists(dirs[1] + "/" + str(result["world_id"]) + "/snapshots/1.json"), "first save exists")
	_check(session.world.treasury == 300, "initial treasury")
	_check(session.world.members[0]["display_name"] == "房主", "owner name")
	_check(session.world.content_hash == session.world.content_hash and not session.world.content_hash.is_empty(), "content hash set")
	# 非法名称
	var session2 := LocalSession.new()
	var bad := session2.create_world(dirs[0], dirs[1], "   ", "世界")
	_check(not bad["ok"] and bad["error"] == ContractError.INVALID_ARGUMENT, "blank owner name rejected")
	var bad2 := session2.create_world(dirs[0], dirs[1], "房主", "  ")
	_check(not bad2["ok"], "blank world name rejected")
	session.close()


# ---------- 4. 继续世界复用身份 ----------

func _test_continue_reuses_identity() -> void:
	var dirs := _fresh_dirs("continue")
	var session := LocalSession.new()
	var created := session.create_world(dirs[0], dirs[1], "房主", "续玩世界")
	var world_id: String = created["world_id"]
	var original_owner: String = session.player_id
	var original_digest: String = session.world.find_member(original_owner)["credential_digest"]
	# 做一些进展
	session.world.treasury = 457
	session.world.game_day = 5
	var closed := session.close()
	_check(closed["ok"], "session closed with save")
	# 继续
	var resumed := LocalSession.new()
	var result := resumed.continue_world(dirs[0], dirs[1], world_id)
	_check(result["ok"], "world resumed (%s)" % str(result["error"]))
	_check(resumed.player_id == original_owner, "same owner player_id")
	_check(resumed.world.game_day == 5, "game day preserved")
	_check(resumed.world.treasury == 457, "treasury preserved")
	_check(resumed.world.find_member(original_owner)["credential_digest"] == original_digest, "same identity digest")
	_check(resumed.world.authority_epoch != session.world.authority_epoch if session.world != null else true, "new epoch after resume")
	resumed.close()


# ---------- 5. 继续世界必须有身份 ----------

func _test_continue_requires_identity() -> void:
	var dirs := _fresh_dirs("no_identity")
	var session := LocalSession.new()
	var created := session.create_world(dirs[0], dirs[1], "房主", "世界")
	var world_id: String = created["world_id"]
	session.close()
	# 删除身份文件后继续 → 拒绝
	DirAccess.remove_absolute(LocalIdentity.identity_path(dirs[0], world_id))
	var resumed := LocalSession.new()
	var result := resumed.continue_world(dirs[0], dirs[1], world_id)
	_check(not result["ok"] and result["error"] == ContractError.NOT_AUTHENTICATED, "resume without identity rejected")
	# 未知世界 → 拒绝
	var unknown := resumed.continue_world(dirs[0], dirs[1], "w" + "9".repeat(32))
	_check(not unknown["ok"], "unknown world rejected")


# ---------- 6. 关闭保存并释放锁 ----------

func _test_close_saves_and_releases() -> void:
	var dirs := _fresh_dirs("close")
	var session := LocalSession.new()
	var created := session.create_world(dirs[0], dirs[1], "房主", "关服世界")
	var world_id: String = created["world_id"]
	session.world.treasury = 999
	session.close()
	# 锁已释放：可以直接加载
	var lock_dir: String = dirs[1] + "/" + world_id + "/runtime.lock.d"
	_check(not DirAccess.dir_exists_absolute(lock_dir), "lock released on close")
	# 关闭后的进展已保存（取最新代，解析 envelope 而非字符串匹配）
	var snap_dir: String = dirs[1] + "/" + world_id + "/snapshots"
	var gens: Array = []
	var da := DirAccess.open(snap_dir)
	da.list_dir_begin()
	var fname := da.get_next()
	while not fname.is_empty():
		if fname.ends_with(".json") and not fname.begins_with(".tmp-"):
			gens.append(fname)
		fname = da.get_next()
	da.list_dir_end()
	gens.sort()
	var envelope: Variant = JSON.parse_string(FileAccess.get_file_as_string(snap_dir + "/" + str(gens[-1])))
	var payload: Variant = JSON.parse_string((envelope as Dictionary)["payload_json"])
	_check(int((payload as Dictionary)["treasury"]) == 999, "progress saved on close (latest gen %s)" % str(gens[-1]))
