extends SceneTree
## M2 端到端集成测试（headless）：房主开服 → 连接卡 → 客户端加入 → 审批 → 远端命令 → 状态一致。
## 运行：godot --headless --path game --script res://tests/integration/m2_e2e_test_runner.gd
## 覆盖 CASE-03/06/49（本机拓扑）+ 远端命令经同一权威路径。

const ContractLimits := preload("res://src/contracts/contract_limits.gd")
const ContractError := preload("res://src/contracts/contract_error.gd")
const LocalSession := preload("res://src/application/session/local_session.gd")
const ClientSession := preload("res://src/application/session/client_session.gd")
const NetTransport := preload("res://src/infrastructure/network/net_transport.gd")
const ConnectionCard := preload("res://src/infrastructure/network/connection_card.gd")
const ItemCatalog := preload("res://src/domain/economy/item_catalog.gd")
const EconomyHandlers := preload("res://src/application/economy/economy_handlers.gd")
const WorldState := preload("res://src/domain/world/world_state.gd")

var _checks := 0
var _failures: PackedStringArray = []
var _root := ""
var _port := 24710


func _initialize() -> void:
	_root = ProjectSettings.globalize_path("res://../work/game-data/m2e2e/%d" % Time.get_unix_time_from_system())
	DirAccess.make_dir_recursive_absolute(_root)
	_test_host_and_join()
	_test_connection_card_validation()
	if _failures.is_empty():
		print("M2E2E_OK checks=%d run_dir=%s" % [_checks, _root])
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: " + f)
		printerr("M2E2E_FAILED checks=%d failures=%d" % [_checks, _failures.size()])
		quit(1)


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(label)


func _pump(host: LocalSession, clients: Array, condition: Callable, budget_ms := 5000) -> bool:
	var deadline := Time.get_ticks_msec() + budget_ms
	while Time.get_ticks_msec() < deadline:
		host.poll_hosting(2)
		for client: ClientSession in clients:
			client.poll(0)
		if bool(condition.call()):
			return true
	return false


# ---------- 1. 开服 + 加入 + 审批 + 远端命令 ----------

func _test_host_and_join() -> void:
	var host := LocalSession.new()
	var created := host.create_world(_root + "/host/user_data", _root + "/host/worlds", "房主", "联机小镇")
	_check(created["ok"], "host creates world")
	# 开服
	var port := _port
	var hosting := host.start_hosting("127.0.0.1", port, "localhost")
	_check(hosting["ok"], "host starts listening (%s)" % str(hosting["error"]))
	_check(not hosting["card"].is_empty(), "connection card produced")
	var card: Dictionary = hosting["card"]
	_check(ConnectionCard.validate(card) == "", "card passes validation")
	_check(card["port"] == port, "card carries port")
	# 客户端：从连接卡取证书并连接
	var trust_path := ConnectionCard.write_trusted_certificate(card, _root + "/client/trust")
	_check(not trust_path.is_empty(), "client writes trusted cert")
	var client := ClientSession.new()
	client.setup(NetTransport.new())
	var token := Crypto.new().generate_random_bytes(32).hex_encode()
	var connected := client.connect_to("127.0.0.1", port, "localhost", trust_path, token, "朋友")
	_check(connected["ok"], "client connects")
	var pending := _pump(host, [client], func() -> bool: return host.pending_approvals().size() == 1)
	_check(pending, "join request reaches pending queue")
	_check(client.snapshot.is_empty(), "no snapshot before approval")
	# 房主批准
	var approved := host.approve_join(host.pending_approvals()[0])
	_check(approved["ok"], "host approves member")
	var active := _pump(host, [client], func() -> bool: return client.state == ClientSession.State.ACTIVE)
	_check(active, "client active after approval")
	_check(not client.snapshot.is_empty(), "client received snapshot")
	# 远端命令经同一权威路径
	var before_treasury: int = host.world.treasury
	var receipt_seq := client.send_command("profile.update", {"display_name": "好朋友"})
	_check(receipt_seq["accepted"], "client sends command")
	var got_receipt := _pump(host, [client], func() -> bool: return client.receipts.size() == 1)
	_check(got_receipt, "client receives receipt")
	var receipt: Dictionary = client.receipts[1]
	_check(receipt["accepted"] and str(receipt["error_code"]).is_empty(), "remote command accepted (%s)" % str(receipt.get("error_code", "")))
	# 服务器状态确实改变
	var member: Dictionary = host.world.find_member(client.player_id)
	_check(member["display_name"] == "好朋友", "server applied remote rename")
	_check(host.world.members.size() == 2, "member added to world")
	# 房主的本地状态与远端一致（同一权威）
	_check(host.world.treasury == before_treasury, "no treasury change from profile update")
	# 关闭
	host.stop_hosting()
	client.close()
	host.close()


# ---------- 2. 连接卡安全校验 ----------

func _test_connection_card_validation() -> void:
	var fake := {
		"card_schema_version": 1,
		"address": "192.0.2.1",
		"port": 24642,
		"tls_hostname": "localhost",
		"server_certificate_pem": "-----BEGIN CERTIFICATE-----\nabc\n-----END CERTIFICATE-----",
		"world_display_name": "测试",
		"protocol_version": 1,
		"created_at_utc": "2026-09-09T00:00:00Z",
	}
	_check(ConnectionCard.validate(fake) == "", "well-formed card valid")
	# 额外字段 → 拒绝
	var extra := fake.duplicate(true)
	extra["internal_note"] = "x"
	_check(ConnectionCard.validate(extra).begins_with("CARD_UNKNOWN_FIELD"), "extra field rejected")
	# 含凭据 → 拒绝
	var leaky := fake.duplicate(true)
	leaky["world_display_name"] = "token=abc"
	_check(ConnectionCard.validate(leaky).begins_with("CARD_FORBIDDEN_CONTENT"), "credential-like content rejected")
	# 私钥 → 拒绝
	var with_key := fake.duplicate(true)
	with_key["server_certificate_pem"] = "-----BEGIN CERTIFICATE-----\nx\n-----END CERTIFICATE-----\nPRIVATE KEY"
	_check(ConnectionCard.validate(with_key).begins_with("CARD_FORBIDDEN_CONTENT"), "private key rejected")
	# 端口越界 → 拒绝
	var bad_port := fake.duplicate(true)
	bad_port["port"] = 80
	_check(ConnectionCard.validate(bad_port) == "CARD_PORT", "bad port rejected")
	# 解析往返
	var parsed := ConnectionCard.parse(ConnectionCard.to_text(fake))
	_check(parsed["ok"] and parsed["card"]["address"] == "192.0.2.1", "card round-trips through text")
