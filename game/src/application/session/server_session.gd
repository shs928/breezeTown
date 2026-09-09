class_name ServerSession
## 权威服务器会话（NET 唯一维护，M2 NET-02）。
## 负责：DTLS 握手后的加入申请、批准/拒绝、凭据摘要认证、席位与待审批上限、
## 撤销/重绑、连接生命周期与版本校验。业务命令转交 WorldRuntime（不在此处实现玩法）。
##
## 安全要点：凭据原文只用于计算摘要；日志只输出摘要前缀；认证前不下发私有世界快照。

const ContractLimits := preload("res://src/contracts/contract_limits.gd")
const ContractError := preload("res://src/contracts/contract_error.gd")
const NetFraming := preload("res://src/infrastructure/network/net_framing.gd")
const NetTransport := preload("res://src/infrastructure/network/net_transport.gd")
const WorldRuntime := preload("res://src/application/world/world_runtime.gd")
const WorldView := preload("res://src/application/world/world_view.gd")
const WorldState := preload("res://src/domain/world/world_state.gd")
const LocalIdentity := preload("res://src/infrastructure/identity/local_identity.gd")
const SyncBuffer := preload("res://src/application/sync/sync_buffer.gd")
const RateLimiter := preload("res://src/infrastructure/network/rate_limiter.gd")
const SafeLog := preload("res://src/infrastructure/network/safe_log.gd")

enum Approval { AUTO, MANUAL }

var runtime: WorldRuntime
var transport: NetTransport
var approval_mode: int = Approval.MANUAL
var port := 0
## 房主是否以本地角色占一个在线席位（listen_host/solo 为 true，dedicated 为 false）。
## 契约 CASE-47：4 人上限含房主。
var local_host_online := true
## 已撤销的凭据摘要：撤销后必须阻止该凭据再次自动加入（PRD 4.2 / CASE-45）。
var _revoked_digests: Dictionary = {}

# connection_id -> {peer, digest, player_id, generation, joined_at_ms, state}
var _connections: Dictionary = {}
# digest -> {peer, display_name, deadline_ms}  待审批
var _pending: Dictionary = {}
# player_id -> connection_id  活跃成员
var _active_by_player: Dictionary = {}
var _next_connection := 1
var _now_ms := 0
var _logs: Array[String] = []
var _limiter := RateLimiter.new()
var safe_log := SafeLog.new()


func setup(world_runtime: WorldRuntime, net_transport: NetTransport) -> void:
	runtime = world_runtime
	transport = net_transport


## 启动监听。返回 {ok, error}。
func start(bind_address: String, bind_port: int, cert_path: String, key_path: String) -> Dictionary:
	var result := transport.listen(bind_address, bind_port, cert_path, key_path)
	if result["ok"]:
		port = int(result["port"])
	return result


## 轮询并处理网络事件。返回处理的事件数。
func poll(timeout_ms := 0) -> int:
	if _now_ms == 0:
		_now_ms = Time.get_ticks_msec()
	_expire_pending()
	var handled := 0
	var event := transport.poll(timeout_ms)
	match int(event["event"]):
		NetTransport.Event.CONNECTED:
			var connection_id := "c%08x" % _next_connection
			_next_connection += 1
			_connections[connection_id] = {
				"peer": event["peer"], "digest": "", "player_id": "",
				"generation": 0, "state": "AUTHENTICATING", "connection_id": connection_id,
				"sync": SyncBuffer.new(),
			}
			_log("connect " + connection_id)
			handled += 1
		NetTransport.Event.DISCONNECTED:
			_handle_disconnect(event["peer"])
			handled += 1
		NetTransport.Event.MESSAGE:
			if not str(event["error"]).is_empty():
				_log("bad_message " + str(event["error"]))
			else:
				_handle_message(event["peer"], event["message"])
			handled += 1
	return handled


## 批准待审批申请。返回 {ok, error, player_id}。
func approve(connection_id_or_digest: String) -> Dictionary:
	var digest := _resolve_digest(connection_id_or_digest)
	if digest.is_empty() or not _pending.has(digest):
		return {"ok": false, "error": "no_such_pending", "player_id": ""}
	var entry: Dictionary = _pending[digest]
	# 历史成员上限（撤销不释放历史槽位）
	if runtime.world.members.size() >= ContractLimits.MEMBER_HISTORY_CAP:
		transport.send_to(entry["peer"], NetFraming.make("member_limit"))
		_pending.erase(digest)
		return {"ok": false, "error": ContractError.MEMBER_LIMIT, "player_id": ""}
	var display_name := ContractLimits.sanitize_display_name(str(entry["display_name"]))
	if display_name.is_empty():
		display_name = "玩家%d" % (runtime.world.members.size() + 1)
	var member: Dictionary = runtime.world.add_member(display_name)
	member["credential_digest"] = digest
	var player_id: String = member["player_id"]
	# 注：批准属于控制事务，正式流程需经持久化端口保存成功后再激活（契约 5.3）。
	# M2 的保存确认由 DATA-01 的 WorldRepository 在调用方完成；此处只做会话激活。
	_pending.erase(digest)
	var connection_id := _find_connection_by_digest(digest)
	if not connection_id.is_empty():
		var connection: Dictionary = _connections[connection_id]
		connection["digest"] = digest
		connection["player_id"] = player_id
		connection["generation"] = int(connection["generation"]) + 1
		connection["state"] = "ACTIVE"
		_active_by_player[player_id] = connection_id
		var sync: SyncBuffer = connection["sync"]
		var captured := sync.capture(runtime.world, player_id, _online_players())
		if captured["ok"]:
			transport.send_to(connection["peer"], NetFraming.make("welcome", {
				"player_id": player_id,
				"connection_generation": connection["generation"],
				"snapshot": captured["snapshot"],
			}))
		else:
			transport.send_to(connection["peer"], NetFraming.make("rejected", {"reason": captured["error"]}))
	_log("approved %s as %s" % [digest.substr(0, 12), player_id.substr(0, 4)])
	return {"ok": true, "error": "", "player_id": player_id}


## 拒绝待审批申请。
func reject(connection_id_or_digest: String) -> Dictionary:
	var digest := _resolve_digest(connection_id_or_digest)
	if digest.is_empty() or not _pending.has(digest):
		return {"ok": false, "error": "no_such_pending"}
	var entry: Dictionary = _pending[digest]
	transport.send_to(entry["peer"], NetFraming.make("rejected", {"reason": "declined"}))
	entry["peer"].peer_disconnect_later()
	_pending.erase(digest)
	_log("rejected " + digest.substr(0, 12))
	return {"ok": true, "error": ""}


## 踢出（只结束当前连接，不删除历史）。
func kick(player_id: String) -> Dictionary:
	if not _active_by_player.has(player_id):
		return {"ok": false, "error": "not_online"}
	var connection: Dictionary = _connections[_active_by_player[player_id]]
	transport.send_to(connection["peer"], NetFraming.make("server_closing"))
	connection["peer"].peer_disconnect_later()
	_log("kicked " + player_id.substr(0, 4))
	return {"ok": true, "error": ""}


## 撤销成员凭据（阻止再次自动加入，保留经济与贡献历史）。
func revoke(player_id: String) -> Dictionary:
	var member: Dictionary = runtime.world.find_member(player_id)
	if member.is_empty():
		return {"ok": false, "error": "unknown_member"}
	if not str(member["credential_digest"]).is_empty():
		_revoked_digests[member["credential_digest"]] = true
	member["status"] = "revoked"
	member["credential_digest"] = ""  # 旧凭据立即失效
	if _active_by_player.has(player_id):
		var connection: Dictionary = _connections[_active_by_player[player_id]]
		connection["peer"].peer_disconnect_later()
		_active_by_player.erase(player_id)
	_log("revoked " + player_id.substr(0, 4))
	return {"ok": true, "error": ""}


## 重新绑定：把新请求的凭据绑定到既有成员（保留 ID/背包/统计）。
func rebind(player_id: String, new_digest: String) -> Dictionary:
	var member: Dictionary = runtime.world.find_member(player_id)
	if member.is_empty():
		return {"ok": false, "error": "unknown_member"}
	# 新摘要不能已属于其他成员
	for other: Dictionary in runtime.world.members:
		if other["player_id"] != player_id and other["credential_digest"] == new_digest:
			return {"ok": false, "error": "digest_in_use"}
	member["credential_digest"] = new_digest
	member["status"] = "active"
	if _active_by_player.has(player_id):
		var old_connection: Dictionary = _connections[_active_by_player[player_id]]
		old_connection["peer"].peer_disconnect_later()
		_active_by_player.erase(player_id)
	_log("rebound " + player_id.substr(0, 4))
	return {"ok": true, "error": ""}


## 关闭服务器：通知全部客户端后停止接受新连接。
func shutdown(reason := "server_closing") -> void:
	for connection_id: String in _connections:
		var connection: Dictionary = _connections[connection_id]
		transport.send_to(connection["peer"], NetFraming.make("server_closing", {"reason": reason}))
		connection["peer"].peer_disconnect_later()
	_connections.clear()
	_pending.clear()
	_active_by_player.clear()
	_log("shutdown")


## 已占用的在线席位（含本地房主）。
func _online_seats_used() -> int:
	return _active_by_player.size() + (1 if local_host_online else 0)


func online_players() -> Array:
	return _active_by_player.keys()


func pending_count() -> int:
	return _pending.size()


func pending_digests() -> Array:
	return _pending.keys()


func connection_for_player(player_id: String) -> String:
	return _active_by_player.get(player_id, "")


func logs() -> Array[String]:
	return _logs


# ================= 内部 =================

func _handle_message(peer: ENetPacketPeer, message: Dictionary) -> void:
	var message_type := str(message["type"])
	# 限流：认证前按连接、认证后按成员；业务与移动分别计数（契约 10.3）。
	var connection_id := _find_connection_by_peer(peer)
	var connection: Dictionary = _connections.get(connection_id, {})
	var bucket_key := "conn:" + connection_id
	if not str(connection.get("player_id", "")).is_empty():
		bucket_key = "member:" + str(connection["player_id"])
	var rate := ContractLimits.RATE_MOVE_PER_S if message_type == "heartbeat" else ContractLimits.RATE_BUSINESS_PER_S
	var burst := ContractLimits.RATE_MOVE_BURST if message_type == "heartbeat" else ContractLimits.RATE_BUSINESS_BURST
	if not _limiter.allow(bucket_key, rate, burst):
		transport.send_to(peer, NetFraming.make("receipt", {"receipt": {"accepted": false, "error_code": ContractError.RATE_LIMITED}}))
		safe_log.log("warn", "rate_limited", {"bucket": bucket_key})
		return
	match message_type:
		"join_req":
			_handle_join(peer, message)
		"command":
			_handle_command(peer, message)
		"heartbeat":
			transport.send_to(peer, NetFraming.make("heartbeat_ack"))
		"resume_query":
			_handle_resume_query(peer, message)
		"leave":
			_log("client_left")
		_:
			pass


func _handle_join(peer: ENetPacketPeer, message: Dictionary) -> void:
	# 协议版本校验先于任何私有数据下发（CASE-49）
	if int(message.get("protocol_version", 0)) != 1:
		transport.send_to(peer, NetFraming.make("version_mismatch", {"expected": 1}))
		peer.peer_disconnect_later()
		return
	var token := str(message.get("token", ""))
	if token.length() != 64:
		transport.send_to(peer, NetFraming.make("rejected", {"reason": "bad_request"}))
		peer.peer_disconnect_later()
		return
	var digest := token.sha256_text()
	var connection_id := _find_connection_by_peer(peer)
	if connection_id.is_empty():
		return
	# 已撤销的凭据必须被拒绝，不能当作新成员重新加入（CASE-45）。
	if _revoked_digests.has(digest):
		transport.send_to(peer, NetFraming.make("rejected", {"reason": "revoked"}))
		peer.peer_disconnect_later()
		_log("revoked_credential " + digest.substr(0, 12))
		return
	# 先把摘要写到连接记录上，后续 approve/resume/重复检测都依赖它。
	_connections[connection_id]["digest"] = digest
	# 重复身份：同一摘要已有活跃连接 → 拒绝新连接（不踢掉正在游玩的）
	if _digest_active(digest):
		transport.send_to(peer, NetFraming.make("duplicate_session"))
		peer.peer_disconnect_later()
		_log("duplicate " + digest.substr(0, 12))
		return
	# 历史成员：凭据摘要匹配则直接恢复身份
	var existing := _member_by_digest(digest)
	if not existing.is_empty():
		if existing["status"] == "revoked":
			transport.send_to(peer, NetFraming.make("rejected", {"reason": "revoked"}))
			peer.peer_disconnect_later()
			return
		if _online_seats_used() >= ContractLimits.ONLINE_CAP:
			transport.send_to(peer, NetFraming.make("server_full"))
			peer.peer_disconnect_later()
			return
		var connection: Dictionary = _connections[connection_id]
		connection["player_id"] = existing["player_id"]
		connection["generation"] = int(connection["generation"]) + 1
		connection["state"] = "ACTIVE"
		_active_by_player[existing["player_id"]] = connection_id
		var sync: SyncBuffer = connection["sync"]
		var captured := sync.capture(runtime.world, existing["player_id"], _online_players())
		transport.send_to(peer, NetFraming.make("welcome", {
			"player_id": existing["player_id"],
			"connection_generation": connection["generation"],
			"snapshot": captured["snapshot"],
			"resumed": true,
		}))
		_log("resumed " + digest.substr(0, 12))
		return
	# 新成员
	if _online_seats_used() >= ContractLimits.ONLINE_CAP:
		transport.send_to(peer, NetFraming.make("server_full"))
		peer.peer_disconnect_later()
		_log("server_full " + digest.substr(0, 12))
		return
	if runtime.world.members.size() >= ContractLimits.MEMBER_HISTORY_CAP:
		transport.send_to(peer, NetFraming.make("member_limit"))
		peer.peer_disconnect_later()
		return
	if approval_mode == Approval.AUTO:
		_pending[digest] = {"peer": peer, "display_name": str(message.get("display_name", "")), "deadline_ms": _now_ms + 60000}
		approve(digest)
		return
	# 手动审批：同一摘要只保留一项；队列上限 8
	if _pending.has(digest):
		return
	if _pending.size() >= ContractLimits.PENDING_APPROVAL_CAP:
		transport.send_to(peer, NetFraming.make("pending_full"))
		peer.peer_disconnect_later()
		_log("pending_full " + digest.substr(0, 12))
		return
	_pending[digest] = {
		"peer": peer,
		"display_name": str(message.get("display_name", "")),
		"deadline_ms": _now_ms + ContractLimits.PENDING_APPROVAL_TTL_MS,
	}
	var connection2: Dictionary = _connections[connection_id]
	connection2["state"] = "WAIT_APPROVAL"
	transport.send_to(peer, NetFraming.make("pending", {"ttl_s": ContractLimits.PENDING_APPROVAL_TTL_MS / 1000}))
	_log("pending " + digest.substr(0, 12))


func _handle_command(peer: ENetPacketPeer, message: Dictionary) -> void:
	var connection_id := _find_connection_by_peer(peer)
	if connection_id.is_empty():
		return
	var connection: Dictionary = _connections[connection_id]
	if connection["state"] != "ACTIVE":
		transport.send_to(peer, NetFraming.make("receipt", {"accepted": false, "error_code": ContractError.NOT_AUTHENTICATED}))
		return
	var command: Dictionary = message.get("command", {})
	command["_actor_player_id"] = connection["player_id"]
	var receipt := runtime.submit(command)
	transport.send_to(peer, NetFraming.make("receipt", {"receipt": receipt}))
	# 提交成功后向所有活跃连接推送差量（含无可见变化的轻量推进标记）。
	if receipt.get("accepted", false) and str(receipt.get("error_code", "")).is_empty():
		_broadcast_delta()


## 向所有活跃连接推送一次差量（本地房主操作与远端命令共用）。
func broadcast_delta() -> void:
	_broadcast_delta()


func _broadcast_delta() -> void:
	for player_id: String in _active_by_player.keys():
		var connection_id: String = _active_by_player[player_id]
		var connection: Dictionary = _connections[connection_id]
		var sync: SyncBuffer = connection["sync"]
		var result := sync.push(runtime.world, player_id, _online_players())
		if not result["ok"]:
			transport.send_to(connection["peer"], NetFraming.make("rejected", {"reason": "resync_required", "detail": result["reason"]}))
			continue
		if bool(result.get("skipped", false)):
			continue
		transport.send_to(connection["peer"], NetFraming.make("view_delta", {"delta": result["delta"]}))


func _handle_resume_query(peer: ENetPacketPeer, message: Dictionary) -> void:
	var token := str(message.get("token", ""))
	var digest := token.sha256_text() if token.length() == 64 else ""
	var member := _member_by_digest(digest)
	if member.is_empty():
		transport.send_to(peer, NetFraming.make("resume_state", {"found": false}))
		return
	transport.send_to(peer, NetFraming.make("resume_state", {
		"found": true,
		"player_id": member["player_id"],
		"next_sequence": runtime.next_expected_sequence(member["player_id"]),
		"status": member["status"],
	}))


func _handle_disconnect(peer: ENetPacketPeer) -> void:
	var connection_id := _find_connection_by_peer(peer)
	if connection_id.is_empty():
		return
	var connection: Dictionary = _connections[connection_id]
	if not str(connection["player_id"]).is_empty():
		_active_by_player.erase(connection["player_id"])
	_connections.erase(connection_id)
	# 断开时清理其待审批项
	for digest: String in _pending.keys():
		if _pending[digest]["peer"] == peer:
			_pending.erase(digest)
	_log("disconnect " + connection_id)


func _expire_pending() -> void:
	for digest: String in _pending.keys():
		if _now_ms >= int(_pending[digest]["deadline_ms"]):
			var peer: ENetPacketPeer = _pending[digest]["peer"]
			transport.send_to(peer, NetFraming.make("approval_timeout"))
			peer.peer_disconnect_later()
			_pending.erase(digest)
			_log("approval_timeout " + digest.substr(0, 12))


func _resolve_digest(connection_id_or_digest: String) -> String:
	if _pending.has(connection_id_or_digest):
		return connection_id_or_digest
	if _connections.has(connection_id_or_digest):
		return str(_connections[connection_id_or_digest]["digest"])
	return ""


func _find_connection_by_peer(peer: ENetPacketPeer) -> String:
	for connection_id: String in _connections:
		if _connections[connection_id]["peer"] == peer:
			return connection_id
	return ""


func _find_connection_by_digest(digest: String) -> String:
	for connection_id: String in _connections:
		if _connections[connection_id]["digest"] == digest:
			return connection_id
	return ""


func _digest_active(digest: String) -> bool:
	for player_id: String in _active_by_player:
		var connection: Dictionary = _connections[_active_by_player[player_id]]
		if connection["digest"] == digest:
			return true
	return false


func _member_by_digest(digest: String) -> Dictionary:
	if digest.is_empty():
		return {}
	for member: Dictionary in runtime.world.members:
		if member["credential_digest"] == digest:
			return member
	return {}


func _online_players() -> Array:
	return _active_by_player.keys()


func _log(line: String) -> void:
	# 只允许摘要前缀，绝不允许凭据原文（NFR-07）。
	_logs.append(line)
	if _logs.size() > 1000:
		_logs.remove_at(0)
	safe_log.log("info", "session", {"detail": line})
