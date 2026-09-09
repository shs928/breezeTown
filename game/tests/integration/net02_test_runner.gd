extends SceneTree
## NET-02 集成测试（headless，真实 DTLS 多进程）：认证、审批、席位、重复身份、撤销/重绑、版本拒绝。
## 运行：godot --headless --path game --script res://tests/integration/net02_test_runner.gd
##
## 拓扑：本进程内起服务器会话 + 1..N 个客户端会话（各自独立 ENetConnection 与 DTLS 上下文）。
## 覆盖 CASE-03/04/05/06/45/47 的协议与身份子场景；真实 LAN/异地证据由 INT-02 补。

const ContractLimits := preload("res://src/contracts/contract_limits.gd")
const ContractError := preload("res://src/contracts/contract_error.gd")
const NetTransport := preload("res://src/infrastructure/network/net_transport.gd")
const NetFraming := preload("res://src/infrastructure/network/net_framing.gd")
const ServerSession := preload("res://src/application/session/server_session.gd")
const ClientSession := preload("res://src/application/session/client_session.gd")
const WorldState := preload("res://src/domain/world/world_state.gd")
const WorldRuntime := preload("res://src/application/world/world_runtime.gd")
const LocalIdentity := preload("res://src/infrastructure/identity/local_identity.gd")

var _checks := 0
var _failures: PackedStringArray = []
var _root := ""
var _port := 24600


func _initialize() -> void:
	_root = ProjectSettings.globalize_path("res://../work/game-data/net02/%d" % Time.get_unix_time_from_system())
	DirAccess.make_dir_recursive_absolute(_root)
	var certs := _make_certs()
	if certs.is_empty():
		printerr("NET02_FAILED: cert generation failed")
		quit(1)
		return

	_test_trusted_join_and_approval(certs)
	_test_wrong_certificate(certs)
	_test_duplicate_identity(certs)
	_test_online_capacity(certs)
	_test_revoke_and_rebind(certs)
	_test_version_mismatch(certs)
	_test_pending_queue_and_ttl(certs)
	_test_resume_query(certs)

	if _failures.is_empty():
		print("NET02_OK checks=%d run_dir=%s" % [_checks, _root])
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: " + f)
		printerr("NET02_FAILED checks=%d failures=%d" % [_checks, _failures.size()])
		quit(1)


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(label)


func _make_certs() -> Dictionary:
	var spike_path := ProjectSettings.globalize_path("res://../work/net-spike")
	var gen := _run_child([
		"--headless", "--path", spike_path, "--script", "res://gen_certs.gd",
		"--", "--out-dir=" + _root + "/certs",
	])
	if not gen.contains("CERTS_OK"):
		return {}
	return {
		"main_cert": _root + "/certs/main/server.pem",
		"main_key": _root + "/certs/main/server.key",
		"decoy_cert": _root + "/certs/decoy/server.pem",
	}


func _run_child(args: Array) -> String:
	var full := PackedStringArray()
	for a: String in args:
		full.append(a)
	var output: Array = []
	OS.execute(OS.get_executable_path(), full, output, true)
	return "\n".join(output)


func _next_port() -> int:
	_port += 1
	return _port


## 组装一个服务器（隔离世界）与任意数量客户端。
func _make_server(port: int, certs: Dictionary, approval := ServerSession.Approval.MANUAL) -> Array:
	var world := WorldState.create("w" + _hex(32), "m" + _hex(32), "房主")
	var runtime := WorldRuntime.new()
	runtime.setup(world, {})
	var transport := NetTransport.new()
	var server := ServerSession.new()
	server.setup(runtime, transport)
	server.approval_mode = approval
	var start := server.start("127.0.0.1", port, certs["main_cert"], certs["main_key"])
	return [server, runtime, start]


func _make_client(certs: Dictionary, cert_key := "main_cert") -> ClientSession:
	var transport := NetTransport.new()
	var client := ClientSession.new()
	client.setup(transport)
	return client


func _hex(chars: int) -> String:
	return Crypto.new().generate_random_bytes(chars / 2).hex_encode()


## 双端推进若干轮，直到条件满足或超时。
func _pump(server: ServerSession, clients: Array, condition: Callable, budget_ms := 4000) -> bool:
	var deadline := Time.get_ticks_msec() + budget_ms
	while Time.get_ticks_msec() < deadline:
		server.poll(2)
		for client: ClientSession in clients:
			client.poll(0)
		if bool(condition.call()):
			return true
	return false


# ---------- 1. 受信连接 + 审批（CASE-03） ----------

func _test_trusted_join_and_approval(certs: Dictionary) -> void:
	var port := _next_port()
	var parts := _make_server(port, certs, ServerSession.Approval.MANUAL)
	var server: ServerSession = parts[0]
	_check(parts[2]["ok"], "server listens on %d" % port)
	var client := _make_client(certs)
	var token := _hex(64)
	var result := client.connect_to("127.0.0.1", port, "localhost", certs["main_cert"], token, "测试员")
	_check(result["ok"], "client initiates connection")
	var reached_pending := _pump(server, [client], func() -> bool: return server.pending_count() == 1 and client.state == ClientSession.State.WAIT_APPROVAL)
	_check(reached_pending, "new member enters WAIT_APPROVAL")
	# 审批前不得下发私有快照
	_check(client.snapshot.is_empty(), "no private snapshot before approval")
	var approved := server.approve(server.pending_digests()[0])
	_check(approved["ok"], "owner approves")
	var became_active := _pump(server, [client], func() -> bool: return client.state == ClientSession.State.ACTIVE)
	_check(became_active, "client becomes ACTIVE after approval")
	_check(client.player_id == approved["player_id"], "client receives its stable player_id")
	_check(not client.snapshot.is_empty(), "snapshot delivered after approval")
	_check(client.snapshot.get("inventories", {}).has("backpack:" + client.player_id), "own backpack in snapshot")
	# 日志不含凭据原文
	var logs := "\n".join(server.logs())
	_check(not logs.contains(token), "no credential in server logs")
	_check(logs.contains(token.sha256_text().substr(0, 12)), "digest prefix logged")
	server.shutdown()
	client.close()


# ---------- 2. 错误证书拒绝（CASE-04） ----------

func _test_wrong_certificate(certs: Dictionary) -> void:
	var port := _next_port()
	var parts := _make_server(port, certs)
	var server: ServerSession = parts[0]
	var client := _make_client(certs)
	client.connect_to("127.0.0.1", port, "localhost", certs["decoy_cert"], _hex(64), "冒充者")
	# 错误证书下不应进入 ACTIVE，也不应收到快照
	_pump(server, [client], func() -> bool: return client.state == ClientSession.State.ACTIVE, 2500)
	_check(client.state != ClientSession.State.ACTIVE, "wrong cert never reaches ACTIVE")
	_check(client.snapshot.is_empty(), "no snapshot under wrong cert")
	_check(server.pending_count() == 0, "no pending created under wrong cert")
	server.shutdown()
	client.close()


# ---------- 3. 重复身份（CASE-03/47） ----------

func _test_duplicate_identity(certs: Dictionary) -> void:
	var port := _next_port()
	var parts := _make_server(port, certs, ServerSession.Approval.AUTO)
	var server: ServerSession = parts[0]
	var token := _hex(64)
	var first := _make_client(certs)
	first.connect_to("127.0.0.1", port, "localhost", certs["main_cert"], token, "甲")
	_check(_pump(server, [first], func() -> bool: return first.state == ClientSession.State.ACTIVE), "first connection active")
	var second := _make_client(certs)
	second.connect_to("127.0.0.1", port, "localhost", certs["main_cert"], token, "甲")
	_check(_pump(server, [first, second], func() -> bool: return second.state == ClientSession.State.DISCONNECTED), "second connection rejected")
	_check(second.last_error == ContractError.DUPLICATE_SESSION, "duplicate_session reason (got %s)" % second.last_error)
	_check(first.state == ClientSession.State.ACTIVE, "first connection not kicked")
	server.shutdown()
	first.close()
	second.close()


# ---------- 4. 在线席位上限（CASE-05） ----------

func _test_online_capacity(certs: Dictionary) -> void:
	var port := _next_port()
	var parts := _make_server(port, certs, ServerSession.Approval.AUTO)
	var server: ServerSession = parts[0]
	var clients: Array = []
	var tokens: Array[String] = []
	# 房主占 1 席；再加 3 名远端到满（共 4 席）
	for i in 3:
		var token := _hex(64)
		tokens.append(token)
		var client := _make_client(certs)
		client.connect_to("127.0.0.1", port, "localhost", certs["main_cert"], token, "成员%d" % i)
		clients.append(client)
	# 注：房主本身不在 _active_by_player 中（无远端连接），因此远端上限按 ONLINE_CAP 计算。
	var all_active := _pump(server, clients, func() -> bool:
		for c: ClientSession in clients:
			if c.state != ClientSession.State.ACTIVE:
				return false
		return true
	)
	_check(all_active, "3 remote clients active")
	var fifth := _make_client(certs)
	fifth.connect_to("127.0.0.1", port, "localhost", certs["main_cert"], _hex(64), "第五人")
	_pump(server, [fifth], func() -> bool: return fifth.state == ClientSession.State.DISCONNECTED)
	_check(fifth.state == ClientSession.State.DISCONNECTED, "connection beyond capacity rejected")
	_check(fifth.last_error == ContractError.ONLINE_LIMIT, "server_full reason (got %s)" % fifth.last_error)
	server.shutdown()
	for c: ClientSession in clients:
		c.close()
	fifth.close()


# ---------- 5. 撤销与重新绑定（CASE-45） ----------

func _test_revoke_and_rebind(certs: Dictionary) -> void:
	var port := _next_port()
	var parts := _make_server(port, certs, ServerSession.Approval.AUTO)
	var server: ServerSession = parts[0]
	var token := _hex(64)
	var client := _make_client(certs)
	client.connect_to("127.0.0.1", port, "localhost", certs["main_cert"], token, "成员")
	_pump(server, [client], func() -> bool: return client.state == ClientSession.State.ACTIVE)
	var player_id: String = client.player_id
	# 记录一些进展
	server.runtime.world.stats["members"][player_id]["contribution"]["planting"] = 10
	client.close()
	_pump(server, [], func() -> bool: return server.online_players().is_empty())
	# 撤销 → 旧凭据不能再加入
	var revoked := server.revoke(player_id)
	_check(revoked["ok"], "revoke succeeds")
	var rejoin := _make_client(certs)
	rejoin.connect_to("127.0.0.1", port, "localhost", certs["main_cert"], token, "成员")
	_pump(server, [rejoin], func() -> bool: return rejoin.state == ClientSession.State.DISCONNECTED)
	_check(rejoin.state == ClientSession.State.DISCONNECTED, "revoked credential rejected")
	# 撤销后保留历史与统计
	var member: Dictionary = server.runtime.world.find_member(player_id)
	_check(member["status"] == "revoked", "member marked revoked")
	_check(member["credential_digest"].is_empty(), "credential digest cleared")
	_check(int(server.runtime.world.stats["members"][player_id]["contribution"]["planting"]) == 10, "stats preserved after revoke")
	# 重新绑定：新凭据可加入且沿用同一 player_id
	var new_token := _hex(64)
	var rebound := server.rebind(player_id, new_token.sha256_text())
	_check(rebound["ok"], "rebind succeeds")
	var rebound_client := _make_client(certs)
	rebound_client.connect_to("127.0.0.1", port, "localhost", certs["main_cert"], new_token, "成员")
	_check(_pump(server, [rebound_client], func() -> bool: return rebound_client.state == ClientSession.State.ACTIVE), "rebound credential joins")
	_check(rebound_client.player_id == player_id, "same player_id after rebind")
	_check(int(server.runtime.world.stats["members"][player_id]["contribution"]["planting"]) == 10, "stats preserved after rebind")
	server.shutdown()
	rejoin.close()
	rebound_client.close()


# ---------- 6. 协议版本不匹配（CASE-49 子场景） ----------

func _test_version_mismatch(certs: Dictionary) -> void:
	var port := _next_port()
	var parts := _make_server(port, certs, ServerSession.Approval.AUTO)
	var server: ServerSession = parts[0]
	var transport := NetTransport.new()
	transport.connect_to("127.0.0.1", port, "localhost", certs["main_cert"])
	# 手工发送 protocol_version=99 的申请
	var sent := false
	var rejected := false
	var deadline := Time.get_ticks_msec() + 4000
	while Time.get_ticks_msec() < deadline and not rejected:
		server.poll(2)
		var event := transport.poll(0)
		if int(event["event"]) == NetTransport.Event.CONNECTED and not sent:
			transport.send(NetFraming.make("join_req", {"protocol_version": 99, "token": _hex(64), "display_name": "旧版本"}))
			sent = true
		if int(event["event"]) == NetTransport.Event.MESSAGE and str(event["message"].get("type", "")) == "version_mismatch":
			rejected = true
	_check(sent, "mismatched version request sent")
	_check(rejected, "server rejects mismatched protocol version")
	_check(server.pending_count() == 0, "no pending created for mismatched version")
	server.shutdown()
	transport.close()


# ---------- 7. 待审批队列与 TTL（CASE-47） ----------

func _test_pending_queue_and_ttl(certs: Dictionary) -> void:
	var port := _next_port()
	var parts := _make_server(port, certs, ServerSession.Approval.MANUAL)
	var server: ServerSession = parts[0]
	var clients: Array = []
	# 8 个不同凭据进入待审批
	for i in 8:
		var client := _make_client(certs)
		client.connect_to("127.0.0.1", port, "localhost", certs["main_cert"], _hex(64), "待审%d" % i)
		clients.append(client)
	_pump(server, clients, func() -> bool: return server.pending_count() == 8)
	_check(server.pending_count() == 8, "8 pending requests queued")
	# 第 9 个被拒（pending_full）
	var ninth := _make_client(certs)
	ninth.connect_to("127.0.0.1", port, "localhost", certs["main_cert"], _hex(64), "第九人")
	_pump(server, [ninth], func() -> bool: return ninth.state == ClientSession.State.DISCONNECTED)
	_check(ninth.last_error == "pending_full", "ninth request rejected pending_full (got %s)" % ninth.last_error)
	# 拒绝其中一项不占历史槽位
	var before_members := server.runtime.world.members.size()
	server.reject(server.pending_digests()[0])
	_check(server.runtime.world.members.size() == before_members, "reject does not consume history slot")
	# 批准一项才占槽位
	var approve_result := server.approve(server.pending_digests()[0])
	_check(approve_result["ok"] and server.runtime.world.members.size() == before_members + 1, "approve consumes history slot")
	server.shutdown()
	for c: ClientSession in clients:
		c.close()
	ninth.close()


# ---------- 8. 重连高水位查询（CASE-33 子场景） ----------

func _test_resume_query(certs: Dictionary) -> void:
	var port := _next_port()
	var parts := _make_server(port, certs, ServerSession.Approval.AUTO)
	var server: ServerSession = parts[0]
	var token := _hex(64)
	var client := _make_client(certs)
	client.connect_to("127.0.0.1", port, "localhost", certs["main_cert"], token, "成员")
	_pump(server, [client], func() -> bool: return client.state == ClientSession.State.ACTIVE)
	# 发两条命令推进序号
	client.send_command("profile.update", {"display_name": "新名"})
	_pump(server, [client], func() -> bool: return client.receipts.size() == 1)
	client.send_command("profile.update", {"display_name": "新名2"})
	_pump(server, [client], func() -> bool: return client.receipts.size() == 2)
	_check(client.receipts.size() == 2, "two receipts received")
	# 查询高水位
	client.query_resume_state()
	_pump(server, [client], func() -> bool: return client.current_sequence() == 2)
	_check(client.current_sequence() == 2, "resume state reports next sequence 3 (current 2)")
	_check(server.runtime.next_expected_sequence(client.player_id) == 3, "server high watermark is 3 (got %d, pid=%s)" % [server.runtime.next_expected_sequence(client.player_id), client.player_id.substr(0, 4)])
	server.shutdown()
	client.close()
