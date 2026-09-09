extends SceneTree
## DATA-05 + NET-06 测试（headless）：迁移包导出/校验/导入 + dedicated 加载已有世界。
## 运行：godot --headless --path game --script res://tests/integration/data05_test_runner.gd

const ContractLimits := preload("res://src/contracts/contract_limits.gd")
const ContractEnvelopes := preload("res://src/contracts/contract_envelopes.gd")
const WorldState := preload("res://src/domain/world/world_state.gd")
const WorldRepository := preload("res://src/infrastructure/persistence/world_repository.gd")
const MigrationPack := preload("res://src/infrastructure/persistence/migration_pack.gd")
const LocalSession := preload("res://src/application/session/local_session.gd")
const LocalIdentity := preload("res://src/infrastructure/identity/local_identity.gd")
const ClientSession := preload("res://src/application/session/client_session.gd")
const ConnectionCard := preload("res://src/infrastructure/network/connection_card.gd")
const ItemCatalog := preload("res://src/domain/economy/item_catalog.gd")

var _checks := 0
var _failures: PackedStringArray = []
var _root := ""
var _port := 24830


func _initialize() -> void:
	_root = ProjectSettings.globalize_path("res://../work/game-data/data05/%d" % Time.get_unix_time_from_system())
	DirAccess.make_dir_recursive_absolute(_root)

	_test_export_validate_import()
	_test_unsafe_pack_rejected()
	_test_dedicated_loads_migrated_world()

	if _failures.is_empty():
		print("DATA05_OK checks=%d run_dir=%s" % [_checks, _root])
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: " + f)
		printerr("DATA05_FAILED checks=%d failures=%d" % [_checks, _failures.size()])
		quit(1)


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(label)


# ---------- 1. 导出 → 校验 → 导入 ----------

func _test_export_validate_import() -> void:
	var source := LocalSession.new()
	var created := source.create_world(_root + "/src/user_data", _root + "/src/worlds", "房主", "迁移世界")
	_check(created["ok"], "source world created")
	# 生成一些进展与成员
	source.world.treasury = 457
	source.world.game_day = 10
	var member: Dictionary = source.world.add_member("队友")
	source.world.find_member(member["player_id"])["credential_digest"] = "c".repeat(64)
	source.world.stats["members"][member["player_id"]]["total_gross_sales"] = 240
	# 生成服务器证书（随迁移包分发）
	source.repository.world_dir = source.repository.world_dir
	source.start_hosting("127.0.0.1", _port, "localhost")
	source.stop_hosting()
	# 导出迁移包（先停服）
	var pack_dir := _root + "/pack"
	var exported := MigrationPack.export_pack(source.repository, source.world, pack_dir)
	_check(exported["ok"], "pack exported (%s)" % str(exported.get("error", "")))
	_check(FileAccess.file_exists(pack_dir + "/pack_manifest.json"), "manifest present")
	_check(FileAccess.file_exists(pack_dir + "/snapshot.json"), "snapshot in pack")
	_check(FileAccess.file_exists(pack_dir + "/server_certificate.pem"), "certificate in pack")
	# 校验
	var validated := MigrationPack.validate_pack(pack_dir)
	_check(validated["ok"], "pack validates (%s)" % str(validated.get("error", "")))
	_check(str(validated["manifest"]["world_id"]) == source.world.world_id, "manifest carries world_id")
	# 导入到新目录
	var target_dir := _root + "/imported/worlds/" + source.world.world_id
	var imported := MigrationPack.import_pack(pack_dir, target_dir)
	_check(imported["ok"], "pack imported (%s)" % str(imported.get("error", "")))
	# 用目标仓库加载并核对数据一致
	var target_repo := WorldRepository.new()
	target_repo.world_dir = target_dir
	target_repo.world_id = source.world.world_id
	var loaded := target_repo.load_latest()
	_check(loaded["ok"], "imported world loads")
	var restored: WorldState = loaded["world"]
	_check(restored.game_day == 10, "game day preserved")
	_check(restored.treasury == 457, "treasury preserved")
	_check(restored.members.size() == 2, "members preserved")
	_check(restored.find_member(member["player_id"])["credential_digest"] == "c".repeat(64), "member credential digest preserved")
	_check(int(restored.stats["members"][member["player_id"]]["total_gross_sales"]) == 240, "stats preserved")
	_check(restored.authority_epoch != source.world.authority_epoch, "new authority epoch on import")
	_check(FileAccess.file_exists(target_dir + "/private/server_certificate.pem"), "certificate imported")


# ---------- 2. 不安全迁移包拒绝 ----------

func _test_unsafe_pack_rejected() -> void:
	var source := LocalSession.new()
	source.create_world(_root + "/unsafe/user_data", _root + "/unsafe/worlds", "房主", "世界")
	var pack_dir := _root + "/unsafe_pack"
	MigrationPack.export_pack(source.repository, source.world, pack_dir)
	# 篡改 checksum
	var manifest_text := FileAccess.get_file_as_string(pack_dir + "/pack_manifest.json")
	var manifest: Dictionary = JSON.parse_string(manifest_text)
	manifest["checksums"]["snapshot.json"] = "0".repeat(64)
	var f := FileAccess.open(pack_dir + "/pack_manifest.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(manifest))
	f.close()
	var tampered := MigrationPack.validate_pack(pack_dir)
	_check(not tampered["ok"] and str(tampered["error"]).begins_with("checksum_mismatch"), "tampered pack rejected")
	# 路径穿越文件名
	manifest["checksums"] = {"../evil.json": "x"}
	var f2 := FileAccess.open(pack_dir + "/pack_manifest.json", FileAccess.WRITE)
	f2.store_string(JSON.stringify(manifest))
	f2.close()
	var traversal := MigrationPack.validate_pack(pack_dir)
	_check(not traversal["ok"] and str(traversal["error"]).begins_with("unsafe_filename"), "path traversal rejected")
	# 未来 schema
	var source2 := LocalSession.new()
	source2.create_world(_root + "/future/user_data", _root + "/future/worlds", "房主", "世界")
	var pack2 := _root + "/future_pack"
	MigrationPack.export_pack(source2.repository, source2.world, pack2)
	var m2: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(pack2 + "/pack_manifest.json"))
	m2["save_schema_version"] = 99
	var f3 := FileAccess.open(pack2 + "/pack_manifest.json", FileAccess.WRITE)
	f3.store_string(JSON.stringify(m2))
	f3.close()
	var future := MigrationPack.validate_pack(pack2)
	_check(not future["ok"] and future["error"] == "future_schema_rejected", "future schema pack rejected")


# ---------- 3. dedicated 加载迁移后的世界并接受原成员 ----------

func _test_dedicated_loads_migrated_world() -> void:
	# 源世界：一名历史成员
	var source := LocalSession.new()
	source.create_world(_root + "/dedi_src/user_data", _root + "/dedi_src/worlds", "房主", "专用服世界")
	var member: Dictionary = source.world.add_member("老成员")
	var member_token := "d".repeat(64)
	source.world.find_member(member["player_id"])["credential_digest"] = member_token.sha256_text()
	source.world.stats["members"][member["player_id"]]["total_gross_sales"] = 500
	# 生成证书并导出
	source.start_hosting("127.0.0.1", _port + 1, "localhost")
	source.stop_hosting()
	var pack_dir := _root + "/dedi_pack"
	MigrationPack.export_pack(source.repository, source.world, pack_dir)
	# 导入到 dedicated 目录
	var dedi_dir := _root + "/dedi/worlds/" + source.world.world_id
	MigrationPack.import_pack(pack_dir, dedi_dir)
	# dedicated 模式：加载已有世界（不自动建新世界），无本地房主席位
	# dedicated 直接用仓库加载（不经过客户端身份流程；原成员凭据已在世界中）
	var dedi_repo := WorldRepository.new()
	dedi_repo.world_dir = dedi_dir
	dedi_repo.world_id = source.world.world_id
	var claim := dedi_repo.claim_lock()
	_check(claim["ok"], "dedicated claims world lock")
	var loaded2 := dedi_repo.load_latest()
	_check(loaded2["ok"], "dedicated loads existing world")
	var world: WorldState = loaded2["world"]
	_check(world.members.size() == 2, "dedicated keeps original members")
	_check(world.find_member(member["player_id"])["credential_digest"] == member_token.sha256_text(), "original member credential preserved")
	# 起 dedicated 服务器（无本地房主席位）
	var transport := preload("res://src/infrastructure/network/net_transport.gd").new()
	var server := preload("res://src/application/session/server_session.gd").new()
	var runtime := preload("res://src/application/world/world_runtime.gd").new()
	runtime.setup(world, {})
	server.setup(runtime, transport)
	server.local_host_online = false   # dedicated 无虚拟房主占席
	server.approval_mode = server.Approval.MANUAL
	var cert_path := dedi_dir + "/private/server_certificate.pem"
	var key_path := dedi_dir + "/private/server_private_key.pem"
	var started := server.start("127.0.0.1", _port + 2, cert_path, key_path)
	_check(started["ok"], "dedicated server starts")
	# 原成员用原凭据加入
	var client := ClientSession.new()
	client.setup(preload("res://src/infrastructure/network/net_transport.gd").new())
	var card := ConnectionCard.build("127.0.0.1", _port + 2, "localhost", cert_path, "专用服世界")
	var trust := ConnectionCard.write_trusted_certificate(card, _root + "/dedi_trust")
	client.connect_to("127.0.0.1", _port + 2, "localhost", trust, member_token, "老成员")
	var deadline := Time.get_ticks_msec() + 6000
	while Time.get_ticks_msec() < deadline and client.state != ClientSession.State.ACTIVE:
		server.poll(2)
		client.poll(0)
	_check(client.state == ClientSession.State.ACTIVE, "original member joins dedicated (state=%d)" % client.state)
	_check(client.player_id == member["player_id"], "same player_id on dedicated")
	_check(int(client.snapshot.get("treasury", -1)) == world.treasury, "snapshot carries world state")
	server.shutdown()
	client.close()
	dedi_repo.release_lock()
