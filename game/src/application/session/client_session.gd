class_name ClientSession
## 客户端会话（NET 唯一维护，M2 NET-02）。
## 状态机：DISCONNECTED → CONNECTING → TRUST_CHECK/AUTHENTICATING → WAIT_APPROVAL → SYNCING → ACTIVE
##        → RECONNECTING / CLOSED（契约 7.3）。
## 职责：连接与凭据认证、等待批准、接收快照、发送命令、重连退避；不修改权威状态。

const ContractLimits := preload("res://src/contracts/contract_limits.gd")
const ContractError := preload("res://src/contracts/contract_error.gd")
const NetFraming := preload("res://src/infrastructure/network/net_framing.gd")
const NetTransport := preload("res://src/infrastructure/network/net_transport.gd")
const LocalIdentity := preload("res://src/infrastructure/identity/local_identity.gd")
const SyncBuffer := preload("res://src/application/sync/sync_buffer.gd")

enum State { DISCONNECTED, CONNECTING, WAIT_APPROVAL, ACTIVE, RECONNECTING, CLOSED }

const RECONNECT_BACKOFF_MS: PackedInt32Array = [1000, 2000, 4000, 8000]

var state: int = State.DISCONNECTED
var player_id := ""
var connection_generation := 0
var last_error := ""
var snapshot: Dictionary = {}
var receipts: Dictionary = {}
var server_messages: Array = []

var _transport: NetTransport
var _token := ""
var _address := ""
var _port := 0
var _tls_hostname := "localhost"
var _trust_cert := ""
var _deadline_ms := 0
var _reconnect_attempts := 0
var _reconnect_deadline_ms := 0
var _sequence := 0
var _display_name := ""
var _applied_revision := 0
var _needs_resync := false


func setup(transport: NetTransport) -> void:
	_transport = transport


## 开始连接。返回 {ok, error}。
func connect_to(address: String, port: int, tls_hostname: String, trust_cert_path: String, token: String, display_name: String) -> Dictionary:
	_address = address
	_port = port
	_tls_hostname = tls_hostname
	_trust_cert = trust_cert_path
	_token = token
	var result := _transport.connect_to(address, port, tls_hostname, trust_cert_path)
	if not result["ok"]:
		last_error = str(result["error"])
		state = State.DISCONNECTED
		return result
	state = State.CONNECTING
	_deadline_ms = Time.get_ticks_msec() + ContractLimits.CONNECT_TRUST_AUTH_BUDGET_S * 1000
	_display_name = display_name
	return {"ok": true, "error": ""}


## 轮询网络。返回本次处理的消息数。
func poll(timeout_ms := 0) -> int:
	if _transport == null:
		return 0
	_check_timeouts()
	var event := _transport.poll(timeout_ms)
	var handled := 0
	match int(event["event"]):
		NetTransport.Event.CONNECTED:
			# 受信连接建立 → 发送加入申请
			_transport.send(NetFraming.make("join_req", {
				"protocol_version": 1,
				"token": _token,
				"display_name": _display_name,
			}))
			handled += 1
		NetTransport.Event.DISCONNECTED:
			if state == State.ACTIVE:
				_begin_reconnect()
			elif state != State.CLOSED:
				state = State.DISCONNECTED
				last_error = "connection_lost"
			handled += 1
		NetTransport.Event.MESSAGE:
			_handle_message(event["message"])
			handled += 1
		_:
			pass
	# 重连退避
	if state == State.RECONNECTING and Time.get_ticks_msec() >= _reconnect_deadline_ms:
		_try_reconnect()
	return handled


## 发送业务命令。返回本地记录的回执（最终回执异步到达）。
func send_command(command_type: String, payload: Dictionary) -> Dictionary:
	if state != State.ACTIVE:
		return {"accepted": false, "error_code": ContractError.NOT_AUTHENTICATED}
	_sequence += 1
	var command := {
		"protocol_version": 1,
		"world_id": str(snapshot.get("world_id", "")),
		"authority_epoch": str(snapshot.get("authority_epoch", "")),
		"client_sequence": _sequence,
		"command_type": command_type,
		"payload": payload,
	}
	_transport.send(NetFraming.make("command", {"command": command}))
	return {"accepted": true, "error_code": "", "client_sequence": _sequence, "pending": true}


## 查询服务器高水位（重连后决定是否重发，契约 6.1）。
func query_resume_state() -> void:
	if _transport != null:
		_transport.send(NetFraming.make("resume_query", {"token": _token}))


func current_sequence() -> int:
	return _sequence


func set_sequence(value: int) -> void:
	_sequence = value


## 本地已应用的权威 revision。
func applied_revision() -> int:
	return _applied_revision


func needs_resync() -> bool:
	return _needs_resync


## 把差量中的可见视图合并到本地快照（只覆盖可见字段）。
func _merge_view(view: Dictionary) -> void:
	for key in ["treasury", "game_day", "day_elapsed_ms", "members", "inventories", "crops", "projects", "leaderboard"]:
		if view.has(key):
			snapshot[key] = view[key]
	snapshot["base_revision"] = int(view.get("base_revision", _applied_revision))


func is_active() -> bool:
	return state == State.ACTIVE


func close() -> void:
	if _transport != null:
		if state == State.ACTIVE:
			_transport.send(NetFraming.make("leave"))
		_transport.close()
	state = State.CLOSED


# ================= 内部 =================

func _handle_message(message: Dictionary) -> void:
	if message.is_empty():
		return
	var message_type := str(message["type"])
	server_messages.append(message_type)
	match message_type:
		"welcome":
			player_id = str(message.get("player_id", ""))
			connection_generation = int(message.get("connection_generation", 0))
			snapshot = message.get("snapshot", {})
			_applied_revision = int(snapshot.get("base_revision", 0))
			_needs_resync = false
			state = State.ACTIVE
			last_error = ""
			_reconnect_attempts = 0
		"pending":
			state = State.WAIT_APPROVAL
			_deadline_ms = Time.get_ticks_msec() + ContractLimits.APPROVAL_TIMEOUT_S * 1000
		"rejected":
			last_error = str(message.get("reason", "rejected"))
			state = State.DISCONNECTED
		"version_mismatch":
			last_error = ContractError.VERSION_MISMATCH
			state = State.DISCONNECTED
		"duplicate_session":
			last_error = ContractError.DUPLICATE_SESSION
			state = State.DISCONNECTED
		"server_full":
			last_error = ContractError.ONLINE_LIMIT
			state = State.DISCONNECTED
		"member_limit":
			last_error = ContractError.MEMBER_LIMIT
			state = State.DISCONNECTED
		"pending_full":
			last_error = "pending_full"
			state = State.DISCONNECTED
		"approval_timeout":
			last_error = "approval_timeout"
			state = State.DISCONNECTED
		"server_closing":
			last_error = ContractError.SERVER_CLOSING
			state = State.DISCONNECTED
		"view_delta":
			var delta: Dictionary = message.get("delta", {})
			var buffer := SyncBuffer.new()
			var result := buffer.apply_delta(_applied_revision, delta)
			if result["ok"]:
				_applied_revision = int(result["target_revision"])
				if delta.get("view", null) != null:
					_merge_view(delta["view"])
			else:
				_needs_resync = true
		"receipt":
			var receipt: Dictionary = message.get("receipt", {})
			receipts[int(receipt.get("client_sequence", 0))] = receipt
		"resume_state":
			if bool(message.get("found", false)):
				_sequence = int(message.get("next_sequence", 1)) - 1
		"heartbeat_ack":
			pass
		_:
			pass


func _check_timeouts() -> void:
	if state == State.CONNECTING and Time.get_ticks_msec() > _deadline_ms:
		state = State.DISCONNECTED
		last_error = "connect_timeout"
	elif state == State.WAIT_APPROVAL and Time.get_ticks_msec() > _deadline_ms:
		state = State.DISCONNECTED
		last_error = "approval_timeout"


func _begin_reconnect() -> void:
	state = State.RECONNECTING
	last_error = "disconnected"
	_reconnect_deadline_ms = Time.get_ticks_msec() + RECONNECT_BACKOFF_MS[_reconnect_attempts]
	_reconnect_attempts += 1


func _try_reconnect() -> void:
	if _reconnect_attempts > RECONNECT_BACKOFF_MS.size():
		state = State.DISCONNECTED
		last_error = "reconnect_exhausted"
		return
	var result := _transport.connect_to(_address, _port, _tls_hostname, _trust_cert)
	if not result["ok"]:
		_begin_reconnect()
