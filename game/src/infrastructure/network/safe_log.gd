class_name SafeLog
## 脱敏日志（NET 唯一维护，M2 NET-04；契约 10.2 / NFR-07）。
## 记录版本、运行模式、请求关联号、错误码、耗时、保存状态、重连原因；
## **禁止**记录凭据、认证信封全文、私钥或公开成员 IP。
## 有界轮转：内存保留最近 N 条；落盘建议 5×5MiB（由调用方按需实现）。

const ContractLimits := preload("res://src/contracts/contract_limits.gd")

const FORBIDDEN_SUBSTRINGS: PackedStringArray = [
	"token", "credential", "private_key", "PRIVATE KEY", "BEGIN RSA", "BEGIN PRIVATE",
]

var max_entries := 2000
var _entries: Array[Dictionary] = []


## 记录一条日志。fields 中的敏感值会被替换为 [redacted]。
func log(level: String, event: String, fields: Dictionary = {}) -> void:
	var sanitized := {}
	for key: String in fields:
		sanitized[key] = _sanitize(key, fields[key])
	_entries.append({
		"ts": Time.get_unix_time_from_system(),
		"level": level,
		"event": event,
		"fields": sanitized,
	})
	if _entries.size() > max_entries:
		_entries.remove_at(0)


func entries() -> Array[Dictionary]:
	return _entries


## 导出为文本（用于证据归档）；同样经过脱敏。
func to_text() -> String:
	var lines: PackedStringArray = []
	for entry: Dictionary in _entries:
		lines.append(JSON.stringify(entry))
	return "\n".join(lines)


## 检查一段文本是否含敏感内容（测试与自检用）。
static func contains_sensitive(text: String) -> bool:
	var lowered := text.to_lower()
	for forbidden: String in FORBIDDEN_SUBSTRINGS:
		if lowered.contains(forbidden.to_lower()):
			return true
	# 常见私钥头
	if text.contains("-----BEGIN") and text.contains("PRIVATE KEY"):
		return true
	return false


func _sanitize(key: String, value: Variant) -> Variant:
	var key_lower := key.to_lower()
	for forbidden: String in FORBIDDEN_SUBSTRINGS:
		if key_lower.contains(forbidden.to_lower()):
			return "[redacted]"
	if value is String:
		var text: String = value
		if contains_sensitive(text):
			return "[redacted]"
		# 凭据形态（64 位 hex）也视为敏感
		if text.length() == 64 and _is_hex(text):
			return text.substr(0, 8) + "…[digest-prefix-only]"
		return text
	if value is Dictionary:
		var out := {}
		for k: Variant in value:
			out[k] = _sanitize(str(k), value[k])
		return out
	if value is Array:
		var arr: Array = []
		for item: Variant in value:
			arr.append(_sanitize("", item))
		return arr
	return value


static func _is_hex(text: String) -> bool:
	for i in text.length():
		var c := text[i]
		if not ((c >= "0" and c <= "9") or (c >= "a" and c <= "f")):
			return false
	return true
