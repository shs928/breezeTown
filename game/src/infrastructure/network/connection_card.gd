class_name ConnectionCard
## 连接卡（NET 唯一维护，M2 NET-02；格式候选见 docs/adr/NET-01.md §2）。
## 含地址/端口/证书/世界显示名/协议版本；不含成员凭据、私钥或任何私有 ID。
## 与 PublicSnapshot 严格分离：不共用序列化器或导出入口（契约 7.2）。

const CARD_SCHEMA_VERSION := 1

const ALLOWED_FIELDS: PackedStringArray = [
	"card_schema_version", "address", "port", "tls_hostname",
	"server_certificate_pem", "world_display_name", "protocol_version", "created_at_utc",
]
const FORBIDDEN_SUBSTRINGS: PackedStringArray = [
	"token", "credential", "private_key", "PRIVATE KEY", "player_id", "connection_id",
]


static func build(address: String, port: int, tls_hostname: String, cert_path: String, world_display_name: String) -> Dictionary:
	var pem := FileAccess.get_file_as_string(cert_path)
	if pem.is_empty():
		return {}
	return {
		"card_schema_version": CARD_SCHEMA_VERSION,
		"address": address,
		"port": port,
		"tls_hostname": tls_hostname,
		"server_certificate_pem": pem,
		"world_display_name": world_display_name,
		"protocol_version": 1,
		"created_at_utc": Time.get_datetime_string_from_system(true) + "Z",
	}


## 校验连接卡：字段白名单 + 不得含敏感内容。返回空串=合法。
static func validate(card: Dictionary) -> String:
	for key: Variant in card:
		if not key in ALLOWED_FIELDS:
			return "CARD_UNKNOWN_FIELD:" + str(key)
	for key: String in ALLOWED_FIELDS:
		if not card.has(key):
			return "CARD_MISSING_FIELD:" + key
	if card["card_schema_version"] != CARD_SCHEMA_VERSION:
		return "CARD_SCHEMA_VERSION"
	if card["protocol_version"] is not int or card["protocol_version"] < 1:
		return "CARD_PROTOCOL_VERSION"
	if int(card["port"]) < 1024 or int(card["port"]) > 65535:
		return "CARD_PORT"
	if not str(card["server_certificate_pem"]).contains("BEGIN CERTIFICATE"):
		return "CARD_CERTIFICATE"
	var text := JSON.stringify(card)
	for forbidden: String in FORBIDDEN_SUBSTRINGS:
		if text.contains(forbidden):
			return "CARD_FORBIDDEN_CONTENT:" + forbidden
	return ""


## 序列化为可分享文本（JSON）。
static func to_text(card: Dictionary) -> String:
	return JSON.stringify(card)


## 从文本解析并校验。返回 {ok, card, error}。
static func parse(text: String) -> Dictionary:
	# JSON 数字解析为 float；契约 4.2 要求解析后重新校验。
	var parsed: Variant = _normalize_numbers(JSON.parse_string(text))
	if parsed is not Dictionary:
		return {"ok": false, "card": {}, "error": "not_a_card"}
	var err := validate(parsed)
	if not err.is_empty():
		return {"ok": false, "card": {}, "error": err}
	return {"ok": true, "card": parsed, "error": ""}


static func _normalize_numbers(value: Variant) -> Variant:
	if value is Array:
		var out: Array = []
		for item: Variant in value:
			out.append(_normalize_numbers(item))
		return out
	if value is Dictionary:
		var out := {}
		for key: Variant in value:
			out[key] = _normalize_numbers(value[key])
		return out
	if value is float:
		var as_int := int(value)
		if is_equal_approx(value, float(as_int)):
			return as_int
	return value


## 把证书写入本地信任目录（客户端用连接卡里的证书作唯一信任锚）。
static func write_trusted_certificate(card: Dictionary, out_dir: String) -> String:
	DirAccess.make_dir_recursive_absolute(out_dir)
	var path := out_dir + "/trusted_server.pem"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(str(card["server_certificate_pem"]))
	f.flush()
	f.close()
	return path
