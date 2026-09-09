extends SceneTree
## SEC-01 安全测试（headless）：越权命令、消息防护、公开/私有文件边界、UI-05 授权流程。
## 覆盖 CASE-24..36、39..41、45..48 的关键子场景。
## 运行：godot --headless --path game --script res://tests/integration/sec01_test_runner.gd

const ContractLimits := preload("res://src/contracts/contract_limits.gd")
const ContractError := preload("res://src/contracts/contract_error.gd")
const ContractPublicSnapshot := preload("res://src/contracts/contract_public_snapshot.gd")
const NetFraming := preload("res://src/infrastructure/network/net_framing.gd")
const SafeLog := preload("res://src/infrastructure/network/safe_log.gd")
const ClientRoot := preload("res://src/client/client_root.gd")
const ClientSession := preload("res://src/application/session/client_session.gd")
const ConnectionCard := preload("res://src/infrastructure/network/connection_card.gd")
const ItemCatalog := preload("res://src/domain/economy/item_catalog.gd")
const WorldState := preload("res://src/domain/world/world_state.gd")
const WorldRuntime := preload("res://src/application/world/world_runtime.gd")
const PublicExporter := preload("res://src/infrastructure/public_export/public_exporter.gd")
const MigrationPack := preload("res://src/infrastructure/persistence/migration_pack.gd")
const LocalSession := preload("res://src/application/session/local_session.gd")

var _checks := 0
var _failures: PackedStringArray = []
var _root := ""
var _port := 24860


func _initialize() -> void:
	_root = ProjectSettings.globalize_path("res://../work/game-data/sec01/%d" % Time.get_unix_time_from_system())
	DirAccess.make_dir_recursive_absolute(_root)

	_test_privilege_escalation()
	_test_message_hardening()
	_test_public_private_boundary()
	_test_ui05_authorization_flow()
	_test_ui04_owner_only_actions()

	if _failures.is_empty():
		print("SEC01_OK checks=%d run_dir=%s" % [_checks, _root])
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: " + f)
		printerr("SEC01_FAILED checks=%d failures=%d" % [_checks, _failures.size()])
		quit(1)


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(label)


func _make_client(name: String, mode: String, port := 0) -> ClientRoot:
	var client := ClientRoot.new()
	client.mode = mode
	if port > 0:
		client.host_port = port
	client.world_dir_override = _root + "/" + name + "/worlds"
	client.catalog = ItemCatalog.load_from_disk()
	client._user_data_dir = _root + "/" + name + "/user_data"
	client._worlds_dir = client.world_dir_override
	DirAccess.make_dir_recursive_absolute(client._user_data_dir)
	DirAccess.make_dir_recursive_absolute(client._worlds_dir)
	return client


# ---------- 1. 越权命令 ----------

func _test_privilege_escalation() -> void:
	var world := WorldState.create("w" + "0".repeat(32), "m" + "1".repeat(32), "房主")
	var runtime := WorldRuntime.new()
	runtime.setup(world, {})
	var intruder := "m" + "9".repeat(32)
	# 未认证成员
	var unauthenticated := runtime.submit({
		"protocol_version": 1, "world_id": world.world_id, "authority_epoch": world.authority_epoch,
		"client_sequence": 1, "command_type": "profile.update", "payload": {"display_name": "冒充"},
		"_actor_player_id": intruder,
	})
	_check(not unauthenticated["accepted"] and unauthenticated["error_code"] == ContractError.NOT_AUTHENTICATED, "unknown member rejected")
	# 客户端不能自报 player_id（信封禁止字段）
	var forged := runtime.submit({
		"protocol_version": 1, "world_id": world.world_id, "authority_epoch": world.authority_epoch,
		"client_sequence": 1, "command_type": "economy.sell",
		"payload": {"slot": 0, "item_definition_id": "produce.radish", "quantity": 1, "unit_price": 999},
		"_actor_player_id": world.owner_player_id,
	})
	_check(str(forged["error_code"]).begins_with("CONTRACTS_PAYLOAD_UNKNOWN_KEY"), "client-submitted price rejected")
	# 客户端不能改贡献分
	var points := runtime.submit({
		"protocol_version": 1, "world_id": world.world_id, "authority_epoch": world.authority_epoch,
		"client_sequence": 1, "command_type": "profile.update",
		"payload": {"display_name": "甲", "contribution": 9999},
		"_actor_player_id": world.owner_player_id,
	})
	_check(str(points["error_code"]).begins_with("CONTRACTS_PAYLOAD_UNKNOWN_KEY"), "client-submitted contribution rejected")
	# 未知命令类型
	var unknown := runtime.submit({
		"protocol_version": 1, "world_id": world.world_id, "authority_epoch": world.authority_epoch,
		"client_sequence": 1, "command_type": "owner.grant_admin", "payload": {},
		"_actor_player_id": world.owner_player_id,
	})
	_check(str(unknown["error_code"]).begins_with("CONTRACTS_COMMAND_UNKNOWN_TYPE"), "unknown command rejected")


# ---------- 2. 消息防护 ----------

func _test_message_hardening() -> void:
	# 超长消息
	var huge := {"type": "command", "command": {"payload": {"data": "x".repeat(20000)}}}
	_check(NetFraming.encode(huge).is_empty(), "oversized message refused")
	# 未知类型
	var unknown := NetFraming.decode(JSON.stringify({"type": "rm -rf"}).to_utf8_buffer(), "client")
	_check(not unknown["ok"] and str(unknown["error"]).begins_with("unknown_type"), "unknown message type rejected")
	# 非对象
	var not_object := NetFraming.decode("[]".to_utf8_buffer(), "client")
	_check(not not_object["ok"], "non-object message rejected")
	# 缺 type
	var missing := NetFraming.decode(JSON.stringify({"command": {}}).to_utf8_buffer(), "client")
	_check(not missing["ok"] and missing["error"] == "missing_type", "missing type rejected")
	# 方向白名单：客户端不能伪装服务器消息
	var wrong_direction := NetFraming.decode(JSON.stringify({"type": "welcome"}).to_utf8_buffer(), "client")
	_check(not wrong_direction["ok"], "server-only message rejected from client direction")
	# 合法消息通过
	var ok := NetFraming.decode(JSON.stringify({"type": "heartbeat"}).to_utf8_buffer(), "client")
	_check(ok["ok"], "valid message accepted")
	# 日志脱敏
	var log := SafeLog.new()
	log.log("info", "auth", {"token": "a".repeat(64), "note": "ok"})
	_check(not log.to_text().contains("a".repeat(64)), "credential not logged")


# ---------- 3. 公开/私有文件边界 ----------

func _test_public_private_boundary() -> void:
	var parts := _make_world_with_stats()
	var world: WorldState = parts[0]
	world.publication_enabled = true
	world.find_member(world.owner_player_id)["publication_consent"] = true
	# 公开快照不得含私有字段
	var built := PublicExporter.build_snapshot(world, "2026-09-09T00:00:00Z")
	var snapshot_text := JSON.stringify(built["snapshot"])
	for forbidden: String in ["credential_digest", "connection_id", "private_key", "ip_address", "inventories", "server_certificate"]:
		_check(not snapshot_text.contains(forbidden), "public snapshot has no '%s'" % forbidden)
	# 白名单外字段拒绝
	var tampered: Dictionary = built["snapshot"].duplicate(true)
	tampered["internal_note"] = "x"
	_check(ContractPublicSnapshot.validate(tampered).begins_with("CONTRACTS_SNAPSHOT_UNKNOWN_FIELD"), "extra public field rejected")
	# 连接卡不得含私钥/凭据
	var card := ConnectionCard.build("192.0.2.1", 24642, "localhost", "", "世界")
	_check(card.is_empty(), "card without certificate refused")
	# 迁移包允许含私钥（私有产物），但公开包禁止
	var session := LocalSession.new()
	session.create_world(_root + "/boundary/ud", _root + "/boundary/worlds", "房主", "边界世界")
	session.start_hosting("127.0.0.1", _port, "localhost")
	session.stop_hosting()
	var pack_dir := _root + "/boundary_pack"
	MigrationPack.export_pack(session.repository, session.world, pack_dir)
	var pack_text := FileAccess.get_file_as_string(pack_dir + "/server_private_key.pem")
	_check(pack_text.contains("PRIVATE KEY"), "migration pack may contain private key (private artifact)")
	# 公开导出目录中不得出现私钥
	session.world.publication_enabled = true
	session.world.find_member(session.player_id)["publication_consent"] = true
	var export_result := PublicExporter.export(session.world, _root + "/boundary_exports", session.world.consent_revision)
	if export_result["ok"]:
		var json_text := FileAccess.get_file_as_string(export_result["json_path"])
		_check(not json_text.contains("PRIVATE KEY"), "public export has no private key")
		_check(not json_text.contains("credential"), "public export has no credential")


# ---------- 4. UI-05 授权流程 ----------

func _test_ui05_authorization_flow() -> void:
	var client := _make_client("ui05", "solo")
	client.action_create_world("房主", "授权世界")
	# 默认关闭
	var state := client.publication_state()
	_check(not bool(state["world_enabled"]), "publication off by default")
	_check(not bool(state["consent"]), "consent off by default")
	# 世界开关（所有者）
	var enabled := client.action_set_world_publication(true)
	_check(enabled["ok"], "owner enables world publication")
	# 本人同意 + 别名
	client.action_set_publication(true, "园丁一号")
	state = client.publication_state()
	_check(bool(state["consent"]) and str(state["alias"]) == "园丁一号", "consent and alias set")
	# 预览
	var preview := client.action_preview_public()
	_check(preview["ok"] and (preview["snapshot"]["entries"] as Array).size() == 1, "preview shows consenting member")
	# 导出
	var exported := client.action_export_public()
	_check(exported["ok"], "export succeeds")
	_check(FileAccess.file_exists(exported["html_path"]) and FileAccess.file_exists(exported["json_path"]), "paired files")
	# 撤回后导出不含该行
	client.action_set_publication(false)
	var after_revoke := client.action_export_public()
	_check(after_revoke["ok"], "export after revoke succeeds (err=%s)" % str(after_revoke.get("error", "none")))
	var json_text := FileAccess.get_file_as_string(after_revoke["json_path"])
	_check(not json_text.contains("园丁一号"), "revoked member absent from new export")
	# 关闭总开关 → 导出被拒
	client.action_set_world_publication(false)
	var blocked := client.action_export_public()
	_check(not blocked["ok"], "export blocked when world switch off")
	client.action_quit()


# ---------- 5. 所有者专属操作 ----------

func _test_ui04_owner_only_actions() -> void:
	var host := _make_client("owner", "listen_host", _port + 1)
	host.action_create_world("房主", "所有者世界")
	var card: Dictionary = host.session.connection_card
	var remote := _make_client("member", "client")
	remote.action_join_world(ConnectionCard.to_text(card), Crypto.new().generate_random_bytes(32).hex_encode(), "成员")
	var deadline := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < deadline:
		host.action_poll_hosting()
		remote.action_poll_remote()
		if host.pending_approvals().size() > 0:
			break
	host.action_approve_join(host.pending_approvals()[0])
	deadline = Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < deadline:
		host.action_poll_hosting()
		remote.action_poll_remote()
		if remote.remote_state() == ClientSession.State.ACTIVE:
			break
	# 远端成员不能操作所有者命令（本地动作方法校验 is_owner）
	var remote_client := _make_client("remote_local", "solo")
	remote_client.action_create_world("成员", "自己的世界")
	# 用非所有者身份尝试世界公开开关
	var member_world := remote_client.session.world
	var other_member: Dictionary = member_world.add_member("普通成员")
	# 直接把当前会话切到普通成员身份来测试权限判定
	remote_client.session.player_id = other_member["player_id"]
	var denied := remote_client.action_set_world_publication(true)
	_check(not denied["ok"] and denied["error"] == ContractError.NOT_ALLOWED, "non-owner cannot toggle world publication")
	var denied_pack := remote_client.action_export_migration_pack(_root + "/denied_pack")
	_check(not denied_pack["ok"] and denied_pack["error"] == ContractError.NOT_ALLOWED, "non-owner cannot export migration pack")
	host.action_quit()
	remote.remote_session.close()
	remote_client.action_quit()


func _make_world_with_stats() -> Array:
	var world := WorldState.create("w" + "0123456789abcdef0123456789abcdef", "m" + "11111111111111111111111111111111", "房主")
	world.stats["members"][world.owner_player_id]["total_gross_sales"] = 240
	world.stats["world_total_sales"] = 240
	return [world, [world.owner_player_id]]
