class_name ContractIds
## 三种身份与随机标识的格式契约（契约 1.3 / 4.1，M0 候选格式）。
##
## 关键规则：player_id（成员稳定 ID）、connection_id（单次连接临时 ID）、
## public_player_id（公开榜专用 ID）三者互不相通；world_id 同理区分 public_world_id。
## 昵称、场景节点名、IP 一律不是身份。
##
## M0 候选格式（LEAD-01 冻结）：
##   player_id        "m"  + 32 个小写十六进制（128 bit 随机）
##   public_player_id "pm" + 32 hex
##   world_id         "w"  + 32 hex
##   public_world_id  "pw" + 32 hex
##   connection_id    "c"  + 8..32 hex（临时）
##   authority_epoch  "e"  + 32 hex（每次权威进程启动重新生成）
##   event_id         "ev" + 32 hex
##   crop_instance_id "ci" + 32 hex

const _HEX_RE := "[0-9a-f]"


static func _make_regex(prefix: String, min_hex: int, max_hex: int) -> RegEx:
	var re := RegEx.new()
	re.compile("^%s%s{%d,%d}$" % [prefix, _HEX_RE, min_hex, max_hex])
	return re


static func is_player_id(v: String) -> bool:
	return _make_regex("m", 32, 32).search(v) != null


static func is_public_player_id(v: String) -> bool:
	return _make_regex("pm", 32, 32).search(v) != null


static func is_world_id(v: String) -> bool:
	return _make_regex("w", 32, 32).search(v) != null


static func is_public_world_id(v: String) -> bool:
	return _make_regex("pw", 32, 32).search(v) != null


static func is_connection_id(v: String) -> bool:
	return _make_regex("c", 8, 32).search(v) != null


static func is_authority_epoch(v: String) -> bool:
	return _make_regex("e", 32, 32).search(v) != null


static func is_event_id(v: String) -> bool:
	return _make_regex("ev", 32, 32).search(v) != null


static func is_crop_instance_id(v: String) -> bool:
	return _make_regex("ci", 32, 32).search(v) != null


## 受控定义 ID：小写字母开头，小写字母/数字/点/下划线组成，1..64 字符。
## 实际取值必须命中内容目录白名单（ContentValidator 负责交叉核对）。
static func is_definition_id(v: String) -> bool:
	if v.is_empty() or v.length() > 64:
		return false
	var re := RegEx.new()
	if re.compile("^[a-z][a-z0-9_.]{0,63}$") != OK:
		return false
	return re.search(v) != null
