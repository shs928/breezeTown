class_name NetTransport
## 正式传输层（NET 唯一维护，M2 NET-02）。
## 基于 NET-01 验证的低层 ENetConnection + DTLS（高层 ENetMultiplayerPeer 无 DTLS 选项）。
## 只负责连接/收发有界消息/断线事件；不决定价格、归属或贡献（契约 3.1 的禁止事项）。

const NetFraming := preload("res://src/infrastructure/network/net_framing.gd")

enum Event { NONE, CONNECTED, DISCONNECTED, MESSAGE }

var _host: ENetConnection = null
var _peer: ENetPacketPeer = null
var _is_server := false
var _connected := false
var _peer_connected := false


# ---------- 服务器侧 ----------

## 创建监听服务器。返回 {ok, error}。
func listen(bind_address: String, port: int, cert_path: String, key_path: String, max_peers := 12) -> Dictionary:
	if port < 1024 or port > 65535:
		return {"ok": false, "error": "bad_port"}
	var key := CryptoKey.new()
	var cert := X509Certificate.new()
	if key.load(key_path) != OK or cert.load(cert_path) != OK:
		return {"ok": false, "error": "certificate_load_failed"}
	_host = ENetConnection.new()
	if _host.create_host_bound(bind_address, port, max_peers, 2, 0, 0) != OK:
		return {"ok": false, "error": "bind_failed"}
	_host.dtls_server_setup(TLSOptions.server(key, cert))
	_is_server = true
	return {"ok": true, "error": "", "port": _host.get_local_port()}


# ---------- 客户端侧 ----------

## 连接服务器。返回 {ok, error}。tls_hostname 必须与服务器证书 CN 一致。
func connect_to(address: String, port: int, tls_hostname: String, trusted_cert_path: String) -> Dictionary:
	var cert := X509Certificate.new()
	if cert.load(trusted_cert_path) != OK:
		return {"ok": false, "error": "trust_certificate_load_failed"}
	_host = ENetConnection.new()
	_host.create_host(1, 2, 0, 0)
	_host.dtls_client_setup(tls_hostname, TLSOptions.client(cert, ""))
	_peer = _host.connect_to_host(address, port, 2)
	_is_server = false
	return {"ok": true, "error": ""}


# ---------- 事件轮询 ----------

## 轮询一次。返回 {event, peer, message, error}。
func poll(timeout_ms := 0) -> Dictionary:
	if _host == null:
		return {"event": Event.NONE, "peer": null, "message": {}, "error": ""}
	var raw: Variant = _host.service(timeout_ms)
	if typeof(raw) != TYPE_ARRAY:
		return {"event": Event.NONE, "peer": null, "message": {}, "error": ""}
	var peer: ENetPacketPeer = raw[1]
	match int(raw[0]):
		ENetConnection.EVENT_CONNECT:
			if _is_server:
				_peer_connected = true
			else:
				_connected = true
			return {"event": Event.CONNECTED, "peer": peer, "message": {}, "error": ""}
		ENetConnection.EVENT_DISCONNECT:
			if _is_server:
				_peer_connected = false
			else:
				_connected = false
				_peer = null
			return {"event": Event.DISCONNECTED, "peer": peer, "message": {}, "error": ""}
		ENetConnection.EVENT_RECEIVE:
			var direction := "client" if _is_server else "server"
			var decoded := NetFraming.decode(peer.get_packet(), direction)
			if not decoded["ok"]:
				return {"event": Event.MESSAGE, "peer": peer, "message": {}, "error": str(decoded["error"])}
			return {"event": Event.MESSAGE, "peer": peer, "message": decoded["message"], "error": ""}
	return {"event": Event.NONE, "peer": null, "message": {}, "error": ""}


# ---------- 发送 ----------

func send_to(peer: ENetPacketPeer, message: Dictionary, _channel := NetFraming.CHANNEL_CONTROL) -> bool:
	var bytes := NetFraming.encode(message)
	if bytes.is_empty():
		return false
	# 低层 put_packet 不带通道参数；逻辑通道语义由消息 type 区分（契约 7.4）。
	peer.put_packet(bytes)
	return true


func send(message: Dictionary) -> bool:
	if _peer == null:
		return false
	return send_to(_peer, message)


func is_link_up() -> bool:
	return _connected or _peer_connected


func close() -> void:
	if _peer != null:
		_peer.peer_disconnect_later()
	if _host != null:
		_host.flush()
		_host.destroy()
		_host = null
	_peer = null
	_connected = false
	_peer_connected = false
