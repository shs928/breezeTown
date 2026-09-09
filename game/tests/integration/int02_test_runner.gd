extends SceneTree
## INT-02 集成测试（headless，本机多进程/多会话）：房主 + 客户端的完整联机流程。
## 通过 ClientRoot 的真实动作方法驱动（不是 mock），覆盖 CASE-02 联机继续、03..08、33..35、49 的本机子场景。
## 真实 LAN/异地证据仍需 INT-02 的物理双机执行（见 docs/testing/resources.md）。
## 运行：godot --headless --path game --script res://tests/integration/int02_test_runner.gd

const ContractLimits := preload("res://src/contracts/contract_limits.gd")
const ContractError := preload("res://src/contracts/contract_error.gd")
const ClientRoot := preload("res://src/client/client_root.gd")
const ClientSession := preload("res://src/application/session/client_session.gd")
const ConnectionCard := preload("res://src/infrastructure/network/connection_card.gd")
const ItemCatalog := preload("res://src/domain/economy/item_catalog.gd")

var _checks := 0
var _failures: PackedStringArray = []
var _root := ""
var _port := 24740


func _initialize() -> void:
	_root = ProjectSettings.globalize_path("res://../work/game-data/int02/%d" % Time.get_unix_time_from_system())
	DirAccess.make_dir_recursive_absolute(_root)
	_test_host_and_remote_full_flow()
	_test_remote_disconnect_and_reconnect_hint()
	_test_version_mismatch_rejected()

	if _failures.is_empty():
		print("INT02_OK checks=%d run_dir=%s" % [_checks, _root])
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: " + f)
		printerr("INT02_FAILED checks=%d failures=%d" % [_checks, _failures.size()])
		quit(1)


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(label)


func _make_client(name: String, mode: String) -> ClientRoot:
	var client := ClientRoot.new()
	client.mode = mode
	client.world_dir_override = _root + "/" + name + "/worlds"
	client.catalog = ItemCatalog.load_from_disk()
	client._user_data_dir = _root + "/" + name + "/user_data"
	client._worlds_dir = client.world_dir_override
	DirAccess.make_dir_recursive_absolute(client._user_data_dir)
	DirAccess.make_dir_recursive_absolute(client._worlds_dir)
	return client


func _pump(host_client: ClientRoot, remote_client: ClientRoot, condition: Callable, budget_ms := 6000) -> bool:
	var deadline := Time.get_ticks_msec() + budget_ms
	while Time.get_ticks_msec() < deadline:
		if host_client != null:
			host_client.action_poll_hosting()
		if remote_client != null:
			remote_client.action_poll_remote()
		if bool(condition.call()):
			return true
	return false


# ---------- 1. 房主开服 + 客户端加入 + 远端操作 ----------

func _test_host_and_remote_full_flow() -> void:
	var host := _make_client("host", "listen_host")
	host.host_port = _port
	var created := host.action_create_world("房主", "联机世界")
	_check(created["ok"], "host creates world")
	_check(host.session.server_session != null, "listen_host auto-starts hosting")
	var card: Dictionary = host.session.connection_card
	_check(not card.is_empty(), "connection card available")
	_check(card["port"] == _port, "hosting on expected port")
	# 客户端加入
	var remote := _make_client("remote", "client")
	var token := Crypto.new().generate_random_bytes(32).hex_encode()
	var joined := remote.action_join_world(ConnectionCard.to_text(card), token, "朋友")
	_check(joined["ok"], "client joins with card")
	# 房主看到待审批
	var pending := _pump(host, remote, func() -> bool: return host.pending_approvals().size() == 1)
	_check(pending, "host sees pending request")
	# 服务器已发出 pending 消息，再 pump 一轮让客户端收到
	_pump(host, remote, func() -> bool: return remote.remote_state() == ClientSession.State.WAIT_APPROVAL, 2000)
	_check(remote.remote_state() == ClientSession.State.WAIT_APPROVAL, "client waits for approval (state=%d)" % remote.remote_state())
	# 批准
	var approved := host.action_approve_join(host.pending_approvals()[0])
	_check(approved["ok"], "host approves")
	var active := _pump(host, remote, func() -> bool: return remote.remote_state() == ClientSession.State.ACTIVE)
	_check(active, "client becomes active")
	_check(not remote.remote_session.snapshot.is_empty(), "client has snapshot")
	# 远端命令：改昵称
	var before_name := remote.remote_session.player_id
	var cmd := remote.action_remote_command("profile.update", {"display_name": "好朋友"})
	_check(cmd["accepted"], "remote command submitted")
	var got_receipt := _pump(host, remote, func() -> bool: return remote.remote_session.receipts.size() == 1)
	_check(got_receipt, "remote receipt received")
	var receipt: Dictionary = remote.remote_session.receipts[1]
	_check(receipt["accepted"] and str(receipt["error_code"]).is_empty(), "remote rename accepted (%s)" % str(receipt.get("error_code", "")))
	_check(host.session.world.find_member(before_name)["display_name"] == "好朋友", "host world reflects remote change")
	# 房主本地操作与远端共存（同一权威）
	var host_member: Dictionary = host.session.world.find_member(host.session.player_id)
	host_member["last_valid_position"] = {"x": 976.0, "y": 976.0}
	host.action_select_tool("hoe")
	var till_receipt := host.action_click_tile(1950)
	_check(till_receipt.get("accepted", false), "host till accepted (%s)" % str(till_receipt.get("error_code", "")))
	_check(host.session.world.plots.has("1950"), "host local action applied")
	# 远端看到房主操作后的差量，并收敛到与房主相同的 revision
	var synced := _pump(host, remote, func() -> bool:
		return remote.remote_session.applied_revision() == host.session.world.business_revision, 4000
	)
	_check(synced, "client converges to host revision")
	_check(remote.remote_session.applied_revision() == host.session.world.business_revision, "client revision matches host (client=%d host=%d)" % [remote.remote_session.applied_revision(), host.session.world.business_revision])
	# 清理
	host.action_quit()
	remote.remote_session.close()


# ---------- 2. 断线提示与重连 ----------

func _test_remote_disconnect_and_reconnect_hint() -> void:
	var host := _make_client("host2", "listen_host")
	host.host_port = _port + 1
	host.action_create_world("房主", "断线世界")
	var card: Dictionary = host.session.connection_card
	var remote := _make_client("remote2", "client")
	var token := Crypto.new().generate_random_bytes(32).hex_encode()
	remote.action_join_world(ConnectionCard.to_text(card), token, "朋友")
	_pump(host, remote, func() -> bool: return host.pending_approvals().size() == 1)
	host.action_approve_join(host.pending_approvals()[0])
	_pump(host, remote, func() -> bool: return remote.remote_state() == ClientSession.State.ACTIVE)
	_check(remote.remote_state() == ClientSession.State.ACTIVE, "remote active before shutdown")
	# 房主关服 → 客户端收到 server_closing
	host.session.stop_hosting()
	var disconnected := _pump(host, remote, func() -> bool: return remote.remote_state() == ClientSession.State.DISCONNECTED, 3000)
	_check(disconnected, "client notified of host closing")
	_check(remote.remote_session.last_error == ContractError.SERVER_CLOSING, "server_closing reason (got %s)" % remote.remote_session.last_error)
	# 断线期间命令被拒
	var cmd := remote.action_remote_command("profile.update", {"display_name": "离线改"})
	_check(not cmd["accepted"], "command rejected while disconnected")
	remote.remote_session.close()
	host.action_quit()


# ---------- 3. 版本不匹配在同步前拒绝 ----------

func _test_version_mismatch_rejected() -> void:
	var host := _make_client("host3", "listen_host")
	host.host_port = _port + 2
	host.action_create_world("房主", "版本世界")
	var card: Dictionary = host.session.connection_card
	# 客户端用连接卡，但手工发送错误协议版本
	var remote := _make_client("remote3", "client")
	var trust := ConnectionCard.write_trusted_certificate(card, remote._user_data_dir + "/trust")
	var transport := preload("res://src/infrastructure/network/net_transport.gd").new()
	var connect_result := transport.connect_to("127.0.0.1", int(card["port"]), "localhost", trust)
	_check(connect_result["ok"], "raw transport connects for version test")
	var sent := false
	var rejected := false
	var deadline := Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < deadline and not rejected:
		host.action_poll_hosting()
		var event := transport.poll(0)
		# CONNECTED=1, MESSAGE=3（见 NetTransport.Event）
		if int(event["event"]) == 1 and not sent:
			transport.send({"type": "join_req", "protocol_version": 99, "token": "a".repeat(64), "display_name": "旧版"})
			sent = true
		if int(event["event"]) == 3 and str(event["message"].get("type", "")) == "version_mismatch":
			rejected = true
	_check(sent, "mismatched join sent")
	_check(rejected, "version mismatch rejected before sync")
	_check(host.pending_approvals().is_empty(), "no pending created for mismatched client")
	transport.close()
	host.action_quit()
