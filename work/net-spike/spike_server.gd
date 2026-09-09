extends SceneTree
## NET-01 实验服务器：DTLS + ENet 低层 API 的最小权威端。
## 身份规则候选：凭据原文只用于计算 SHA-256 摘要；同一摘要只允许一个活跃连接；
## 新成员需批准（auto=立即批准；manual=入待审批队列，TTL 过期拒绝）；
## 活跃席位上限 4，待审批上限 8。日志只输出摘要前缀，绝不输出凭据原文。
##
## 用法：godot --headless --path work/net-spike --script res://spike_server.gd --
##   --port=24501 --cert-file=... --key-file=... [--approval=auto|manual] [--ttl-s=2] [--max-run-s=25]
## 退出码：0=正常结束；2=启动失败。

const NetSpike := preload("res://net_spike.gd")

const SEAT_CAP := 4
const PENDING_CAP := 8

var _active := {}      # digest -> {peer, player_id}
var _pending := {}     # digest -> {peer, deadline_ms, name}
var _printed_digests := {}


func _initialize() -> void:
	var port := 0
	var cert_file := ""
	var key_file := ""
	var approval := "auto"
	var ttl_s := 2.0
	var max_run_s := 25.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--port="):
			port = int(arg.get_slice("=", 1))
		elif arg.begins_with("--cert-file="):
			cert_file = arg.get_slice("=", 1)
		elif arg.begins_with("--key-file="):
			key_file = arg.get_slice("=", 1)
		elif arg.begins_with("--approval="):
			approval = arg.get_slice("=", 1)
		elif arg.begins_with("--ttl-s="):
			ttl_s = float(arg.get_slice("=", 1))
		elif arg.begins_with("--max-run-s="):
			max_run_s = float(arg.get_slice("=", 1))
	if port == 0 or cert_file.is_empty() or key_file.is_empty():
		printerr("[srv] missing --port/--cert-file/--key-file")
		quit(2)
		return

	var host := ENetConnection.new()
	if host.create_host_bound("127.0.0.1", port, SEAT_CAP + PENDING_CAP + 4, 2, 0, 0) != OK:
		printerr("[srv] bind failed")
		quit(2)
		return
	var options := NetSpike.server_options(cert_file, key_file)
	if options == null:
		printerr("[srv] tls options failed")
		quit(2)
		return
	host.dtls_server_setup(options)
	print("[srv] listening port=%d approval=%s ttl=%.1fs" % [port, approval, ttl_s])

	var deadline_ms := Time.get_ticks_msec() + int(max_run_s * 1000)
	var closing := false
	while Time.get_ticks_msec() < deadline_ms:
		var ev: Variant = host.service(25)
		if typeof(ev) == TYPE_ARRAY:
			_handle_event(host, ev, approval, ttl_s)
		# 待审批 TTL 过期检查
		var now := Time.get_ticks_msec()
		for digest: String in _pending.keys():
			if now >= int(_pending[digest]["deadline_ms"]):
				var peer: ENetPacketPeer = _pending[digest]["peer"]
				NetSpike.send_msg(peer, {"type": "approval_timeout"})
				peer.peer_disconnect_later()
				_pending.erase(digest)
				print("[srv] approval timeout digest=%s" % digest.substr(0, 12))
		if not closing and deadline_ms - Time.get_ticks_msec() <= 500:
			closing = true
			print("[srv] closing")
			for digest: String in _active:
				NetSpike.send_msg(_active[digest]["peer"], {"type": "server_closing"})
	host.refuse_new_connections(1)
	print("[srv] done active_served=%d" % _active.size())
	quit(0)


func _handle_event(host: ENetConnection, ev: Array, approval: String, ttl_s: float) -> void:
	match int(ev[0]):
		ENetConnection.EVENT_RECEIVE:
			var peer: ENetPacketPeer = ev[1]
			var msg: Variant = NetSpike.recv_msg(peer)
			if msg is Dictionary:
				_handle_msg(host, peer, msg, approval, ttl_s)
		ENetConnection.EVENT_DISCONNECT:
			var peer: ENetPacketPeer = ev[1]
			for digest: String in _active:
				if _active[digest]["peer"] == peer:
					print("[srv] active left digest=%s" % digest.substr(0, 12))
					_active.erase(digest)
					break
			for digest: String in _pending:
				if _pending[digest]["peer"] == peer:
					_pending.erase(digest)
					break


func _handle_msg(_host: ENetConnection, peer: ENetPacketPeer, msg: Dictionary, approval: String, ttl_s: float) -> void:
	if msg.get("type") != "join_req":
		return
	var token: String = str(msg.get("token", ""))
	if token.is_empty() or token.length() != 64:
		NetSpike.send_msg(peer, {"type": "rejected", "reason": "bad_request"})
		peer.peer_disconnect_later()
		return
	var digest := NetSpike.digest_of(token)
	# 泄漏断言：摘要前缀必须存在于日志，原文绝不允许打印。见 orchestrator 扫描。
	_printed_digests[digest] = true

	if _active.has(digest):
		NetSpike.send_msg(peer, {"type": "duplicate_session"})
		peer.peer_disconnect_later()
		print("[srv] duplicate session digest=%s" % digest.substr(0, 12))
		return

	if approval == "manual":
		if _pending.has(digest):
			# 同一凭据摘要只保留一项申请（PRD 4.2）
			return
		if _pending.size() >= PENDING_CAP:
			NetSpike.send_msg(peer, {"type": "pending_full"})
			peer.peer_disconnect_later()
			print("[srv] pending full digest=%s" % digest.substr(0, 12))
			return
		_pending[digest] = {
			"peer": peer,
			"deadline_ms": Time.get_ticks_msec() + int(ttl_s * 1000),
			"name": str(msg.get("display_name", "")),
		}
		print("[srv] pending queued digest=%s total=%d" % [digest.substr(0, 12), _pending.size()])
		return

	# auto 批准
	if _active.size() >= SEAT_CAP:
		NetSpike.send_msg(peer, {"type": "server_full"})
		peer.peer_disconnect_later()
		print("[srv] server full digest=%s" % digest.substr(0, 12))
		return
	var player_id := "m" + NetSpike.new_token().substr(0, 32)
	_active[digest] = {"peer": peer, "player_id": player_id}
	NetSpike.send_msg(peer, {"type": "welcome", "player_id": player_id})
	print("[srv] approved digest=%s seats=%d" % [digest.substr(0, 12), _active.size()])
