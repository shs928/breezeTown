extends SceneTree
## NET-01 实验客户端：DTLS 受信握手 + 加入流程。
## 退出码：0=welcome（含 hold 结束后正常退出）；2=未能在时限内建立受信连接（含证书错误）；
## 3=服务器明确拒绝（duplicate_session/server_full/pending_full）；4=审批超时/等待超时；5=服务器关闭。
##
## 用法：godot --headless --path work/net-spike --script res://spike_client.gd --
##   --port=24501 --trust-cert=<server.pem> [--tls-host=localhost] [--wait-s=8] [--hold-s=0] [--name=测试]
## 凭据原文经环境变量 NET_SPIKE_TOKEN 传入，不出现在命令行与日志。

const NetSpike := preload("res://net_spike.gd")

const EXIT_WELCOME := 0
const EXIT_CONNECT_FAIL := 2
const EXIT_REJECTED := 3
const EXIT_TIMEOUT := 4
const EXIT_CLOSING := 5


func _initialize() -> void:
	var port := 0
	var trust_cert := ""
	var tls_host := "localhost"
	var wait_s := 8.0
	var hold_s := 0.0
	var display_name := "测试员"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--port="):
			port = int(arg.get_slice("=", 1))
		elif arg.begins_with("--trust-cert="):
			trust_cert = arg.get_slice("=", 1)
		elif arg.begins_with("--tls-host="):
			tls_host = arg.get_slice("=", 1)
		elif arg.begins_with("--wait-s="):
			wait_s = float(arg.get_slice("=", 1))
		elif arg.begins_with("--hold-s="):
			hold_s = float(arg.get_slice("=", 1))
		elif arg.begins_with("--name="):
			display_name = arg.get_slice("=", 1)
	var token := OS.get_environment("NET_SPIKE_TOKEN")
	if port == 0 or trust_cert.is_empty() or token.length() != 64:
		printerr("[cli] missing --port/--trust-cert or NET_SPIKE_TOKEN")
		quit(EXIT_CONNECT_FAIL)
		return

	var options := NetSpike.client_options(trust_cert)
	if options == null:
		printerr("[cli] trust cert load failed")
		quit(EXIT_CONNECT_FAIL)
		return
	var host := ENetConnection.new()
	host.create_host(1, 2, 0, 0)
	host.dtls_client_setup(tls_host, options)
	var peer: ENetPacketPeer = host.connect_to_host("127.0.0.1", port, 2)

	var deadline := Time.get_ticks_msec() + int(wait_s * 1000)
	var connected := false
	var welcomed := false
	var hold_until := 0
	while Time.get_ticks_msec() < deadline:
		var ev: Variant = host.service(25)
		if typeof(ev) != TYPE_ARRAY:
			continue
		match int(ev[0]):
			ENetConnection.EVENT_CONNECT:
				connected = true
				NetSpike.send_msg(peer, {"type": "join_req", "token": token, "display_name": display_name})
				hold_until = Time.get_ticks_msec() + int(hold_s * 1000)
			ENetConnection.EVENT_RECEIVE:
				var msg_v: Variant = NetSpike.recv_msg(peer)
				if msg_v is not Dictionary:
					continue
				var msg: Dictionary = msg_v
				match str(msg.get("type", "")):
					"welcome":
						welcomed = true
						var pid: String = str(msg.get("player_id", ""))
						print("[cli] welcome player_id_prefix=%s" % pid.substr(0, 4))
						if hold_s <= 0.0:
							peer.peer_disconnect_later()
							print("[cli] EXIT_OK")
							quit(EXIT_WELCOME)
							return
						deadline = hold_until + 3000  # hold 场景延长预算
					"duplicate_session":
						print("[cli] EXIT_REJECTED duplicate_session")
						quit(EXIT_REJECTED)
						return
					"server_full":
						print("[cli] EXIT_REJECTED server_full")
						quit(EXIT_REJECTED)
						return
					"pending_full":
						print("[cli] EXIT_REJECTED pending_full")
						quit(EXIT_REJECTED)
						return
					"approval_timeout":
						print("[cli] EXIT_TIMEOUT approval_timeout")
						quit(EXIT_TIMEOUT)
						return
					"server_closing":
						print("[cli] EXIT_CLOSING server_closing")
						quit(EXIT_CLOSING)
						return
			ENetConnection.EVENT_DISCONNECT:
				if not welcomed:
					print("[cli] disconnected before welcome (connected=%s)" % connected)
					quit(EXIT_CONNECT_FAIL)
					return
			_:
				pass
		# hold 模式：welcome 后保持连接并发心跳
		if welcomed and hold_s > 0.0:
			if Time.get_ticks_msec() < hold_until:
				peer.ping()
			else:
				peer.peer_disconnect_later()
				print("[cli] hold done EXIT_OK")
				quit(EXIT_WELCOME)
				return
	if not connected:
		print("[cli] EXIT_CONNECT_FAIL (no trusted connection within %.1fs)" % wait_s)
		quit(EXIT_CONNECT_FAIL)
	else:
		print("[cli] EXIT_TIMEOUT (no verdict within budget)")
		quit(EXIT_TIMEOUT)
