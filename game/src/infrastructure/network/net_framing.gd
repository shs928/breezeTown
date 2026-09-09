class_name NetFraming
## 网络消息编解码与边界校验（NET 唯一维护，M2 NET-02）。
## 契约 4.2 / 7.4：单条普通业务消息 ≤16KiB；先校验类型/长度/枚举再分配大对象；
## 不接受任意对象反序列化。消息统一为 JSON 对象，必须含字符串 type。

const ContractLimits := preload("res://src/contracts/contract_limits.gd")

## 通道分配（契约 7.4）。
const CHANNEL_CONTROL := 0
const CHANNEL_BUSINESS := 1

## 允许的消息类型白名单（未知类型一律拒绝）。
const CLIENT_MESSAGES: PackedStringArray = [
	"join_req", "command", "heartbeat", "resume_query", "leave",
]
const SERVER_MESSAGES: PackedStringArray = [
	"welcome", "pending", "rejected", "receipt", "view_delta", "view_snapshot",
	"server_closing", "approval_timeout", "duplicate_session", "server_full",
	"member_limit", "pending_full", "heartbeat_ack", "resume_state", "version_mismatch",
]


## 编码消息。超过 16KiB 返回空 PackedByteArray。
static func encode(message: Dictionary) -> PackedByteArray:
	var text := JSON.stringify(message)
	var bytes := text.to_utf8_buffer()
	if bytes.size() > ContractLimits.BUSINESS_MESSAGE_MAX_BYTES:
		push_error("net framing: message exceeds %d bytes" % ContractLimits.BUSINESS_MESSAGE_MAX_BYTES)
		return PackedByteArray()
	return bytes


## 解码并做结构校验。返回 {ok, message, error}。
static func decode(bytes: PackedByteArray, expected_direction: String) -> Dictionary:
	if bytes.size() > ContractLimits.BUSINESS_MESSAGE_MAX_BYTES:
		return {"ok": false, "message": {}, "error": "message_too_large"}
	var text := bytes.get_string_from_utf8()
	# JSON 把数字解析为 float；契约 4.2 要求解析后重新校验，故先归一化整值。
	var parsed: Variant = normalize_numbers(JSON.parse_string(text))
	if parsed is not Dictionary:
		return {"ok": false, "message": {}, "error": "not_an_object"}
	var message: Dictionary = parsed
	var message_type: Variant = message.get("type", null)
	if message_type is not String:
		return {"ok": false, "message": {}, "error": "missing_type"}
	var whitelist: PackedStringArray = CLIENT_MESSAGES if expected_direction == "client" else SERVER_MESSAGES
	if not message_type in whitelist:
		return {"ok": false, "message": {}, "error": "unknown_type:" + str(message_type)}
	return {"ok": true, "message": message, "error": ""}


## 把 JSON 解析出的整值 float 归一化为 int（非整值保留，交由校验器按小数拒绝）。
static func normalize_numbers(value: Variant) -> Variant:
	if value is Array:
		var out: Array = []
		for item: Variant in value:
			out.append(normalize_numbers(item))
		return out
	if value is Dictionary:
		var out := {}
		for key: Variant in value:
			out[key] = normalize_numbers(value[key])
		return out
	if value is float:
		var as_int := int(value)
		if is_equal_approx(value, float(as_int)):
			return as_int
	return value


static func make(message_type: String, payload: Dictionary = {}) -> Dictionary:
	var message := {"type": message_type}
	for key: String in payload:
		message[key] = payload[key]
	return message
