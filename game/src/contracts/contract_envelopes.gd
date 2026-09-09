class_name ContractEnvelopes
## 命令信封、事件信封、存档 envelope 的结构与语义校验（契约第 5/8 章，M0 候选）。
##
## 原则：
## - 信封不含可授权的 player_id、客户端价格、最终金额或贡献分（操作者由服务器会话绑定）。
## - 所有结构校验先过类型/长度/枚举，再谈业务；未知字段一律拒绝，不用未受控字典兜底。
## - 载荷校验只覆盖结构性边界；玩法前置条件（距离/库存/资金）属于 M1+ 的领域处理器。

const ContractLimits := preload("res://src/contracts/contract_limits.gd")
const ContractIds := preload("res://src/contracts/contract_ids.gd")

const PROTOCOL_VERSION_CANDIDATE := 1  # LEAD-01 冻结：契约 v1
const SAVE_FORMAT_VERSION_CANDIDATE := 1
const RULESET_VERSION_CANDIDATE := "v1.0"

# ---- 命令白名单（契约 5.2）----
const COMMANDS: PackedStringArray = [
	"world.move_input",
	"farming.till", "farming.plant", "farming.water", "farming.harvest",
	"inventory.transfer",
	"economy.buy_seed", "economy.sell", "economy.claim_relief",
	"projects.donate",
	"profile.update",
	"privacy.set_publication",
	"owner.set_publication", "owner.member_action",
	"owner.save", "owner.export", "owner.close",
]

# ---- 事件白名单（契约 5.5 / PRD 第 5-10 章的事实）----
const EVENTS: PackedStringArray = [
	"PlotTilled", "CropPlanted", "CropWatered", "CropHarvested",
	"ItemsTransferred", "SeedPurchased", "ProduceSold",
	"ProjectDonated", "ProjectCompleted", "ReliefGranted",
	"MemberProfileChanged", "PublicationPreferenceChanged",
	"WorldPublicationChanged", "DayAdvanced",
	"MemberApproved", "MemberRevoked", "MemberRebound",
]


# ================= 命令信封 =================

## 返回空串表示合法；否则返回以 CONTRACTS_ 开头的失败原因。
static func validate_command(cmd: Dictionary) -> String:
	if cmd.size() != 6 and cmd.size() != 7:
		return "CONTRACTS_COMMAND_FIELD_SET: expected [protocol_version, world_id, authority_epoch, client_sequence, command_type, payload] plus optional expected_versions; got %d fields" % cmd.size()
	if not cmd.has_all(["protocol_version", "world_id", "authority_epoch", "client_sequence", "command_type", "payload"]):
		return "CONTRACTS_COMMAND_MISSING_FIELD"
	if cmd["protocol_version"] is not int or cmd["protocol_version"] != PROTOCOL_VERSION_CANDIDATE:
		return "CONTRACTS_COMMAND_PROTOCOL_VERSION"
	if cmd["world_id"] is not String or not ContractIds.is_world_id(cmd["world_id"]):
		return "CONTRACTS_COMMAND_WORLD_ID"
	if cmd["authority_epoch"] is not String or not ContractIds.is_authority_epoch(cmd["authority_epoch"]):
		return "CONTRACTS_COMMAND_EPOCH"
	if cmd["client_sequence"] is not int or cmd["client_sequence"] < 1 or cmd["client_sequence"] > ContractLimits.MAX_BUSINESS_INT:
		return "CONTRACTS_COMMAND_SEQUENCE"
	if cmd["command_type"] is not String or not cmd["command_type"] in COMMANDS:
		return "CONTRACTS_COMMAND_UNKNOWN_TYPE"
	# 信封里出现任何身份/价格/金额/贡献字段即拒绝（客户端无权主张这些值）。
	for forbidden in ["player_id", "actor_player_id", "price", "unit_price", "amount", "points", "contribution"]:
		if cmd.has(forbidden):
			return "CONTRACTS_COMMAND_FORBIDDEN_FIELD:" + forbidden
	if cmd.has("expected_versions"):
		var ev: Variant = cmd["expected_versions"]
		if ev is not Dictionary:
			return "CONTRACTS_COMMAND_EXPECTED_VERSIONS_TYPE"
		for k: Variant in ev:
			if k is not String or ev[k] is not int or ev[k] < 0:
				return "CONTRACTS_COMMAND_EXPECTED_VERSIONS_VALUE"
	var payload_err := _validate_payload(cmd["command_type"], cmd["payload"])
	if not payload_err.is_empty():
		return payload_err
	return ""


## 载荷结构性边界：键集合精确匹配 + 类型/范围校验。
static func _validate_payload(command_type: String, payload: Variant) -> String:
	if payload is not Dictionary:
		return "CONTRACTS_PAYLOAD_NOT_OBJECT"
	var spec: Variant = _payload_specs(command_type)
	if spec == null:
		return "CONTRACTS_PAYLOAD_NO_SPEC:" + command_type
	for k: Variant in payload:
		if not spec.has(k):
			return "CONTRACTS_PAYLOAD_UNKNOWN_KEY:" + str(k)
	for k: String in spec:
		if not payload.has(k):
			return "CONTRACTS_PAYLOAD_MISSING_KEY:" + k
		var rule: Array = spec[k]  # [类型字符串, 最小, 最大] 或 ["string"] 或 ["bool"]
		var v: Variant = payload[k]
		match rule[0]:
			"bool":
				if v is not bool:
					return "CONTRACTS_PAYLOAD_TYPE:" + k
			"string":
				if v is not String:
					return "CONTRACTS_PAYLOAD_TYPE:" + k
			"definition_id":
				if v is not String or not ContractIds.is_definition_id(v):
					return "CONTRACTS_PAYLOAD_DEFINITION_ID:" + k
			"int":
				if v is not int or v < int(rule[1]) or v > int(rule[2]):
					return "CONTRACTS_PAYLOAD_RANGE:" + k
			"member_id":
				if v is not String or not ContractIds.is_player_id(v):
					return "CONTRACTS_PAYLOAD_MEMBER_ID:" + k
			"project_id":
				if v is not String or not ContractIds.is_definition_id(v):
					return "CONTRACTS_PAYLOAD_PROJECT_ID:" + k
			"container_ref":
				if v is not String:
					return "CONTRACTS_PAYLOAD_TYPE:" + k
				if not (v == "shared_storage" or v.begins_with("backpack:")):
					return "CONTRACTS_PAYLOAD_CONTAINER_REF:" + k
			_:
				return "CONTRACTS_PAYLOAD_BAD_SPEC:" + k
	return ""


## 各命令的载荷键与边界。spec: key -> [类型, args...]。
## 返回 null 表示该命令未定义 spec；返回 {} 表示合法空载荷（如 claim_relief）。
static func _payload_specs(command_type: String) -> Variant:
	match command_type:
		"world.move_input":
			return {
				"dx": ["int", -1, 1], "dy": ["int", -1, 1],
				"input_sequence": ["int", 1, ContractLimits.MAX_BUSINESS_INT],
			}
		"farming.till", "farming.water", "farming.harvest":
			return {"tile_id": ["int", 0, ContractLimits.MAP_W * ContractLimits.MAP_H - 1]}
		"farming.plant":
			return {
				"tile_id": ["int", 0, ContractLimits.MAP_W * ContractLimits.MAP_H - 1],
				"seed_slot": ["int", 0, ContractLimits.BACKPACK_SLOTS - 1],
				"seed_definition_id": ["definition_id"],
			}
		"inventory.transfer":
			return {
				"from_container": ["container_ref"], "to_container": ["container_ref"],
				"from_slot": ["int", 0, ContractLimits.CONTAINER_SLOT_MAX],
				"to_slot": ["int", 0, ContractLimits.CONTAINER_SLOT_MAX],
				"quantity": ["int", ContractLimits.TRADE_QUANTITY_MIN, ContractLimits.TRADE_QUANTITY_MAX],
			}
		"economy.buy_seed":
			return {
				"seed_definition_id": ["definition_id"],
				"quantity": ["int", ContractLimits.TRADE_QUANTITY_MIN, ContractLimits.TRADE_QUANTITY_MAX],
			}
		"economy.sell":
			return {
				"slot": ["int", 0, ContractLimits.BACKPACK_SLOTS - 1],
				"item_definition_id": ["definition_id"],
				"quantity": ["int", ContractLimits.TRADE_QUANTITY_MIN, ContractLimits.TRADE_QUANTITY_MAX],
			}
		"projects.donate":
			return {
				"project_id": ["project_id"],
				"item_definition_id": ["definition_id"],
				"quantity": ["int", ContractLimits.TRADE_QUANTITY_MIN, ContractLimits.TRADE_QUANTITY_MAX],
			}
		"economy.claim_relief":
			return {}
		"profile.update":
			return {"display_name": ["string"]}
		"privacy.set_publication":
			return {"consent": ["bool"], "use_alias": ["bool"], "alias": ["string"]}
		"owner.set_publication":
			return {"enabled": ["bool"]}
		"owner.member_action":
			return {
				"action": ["string"],  # approve/kick/revoke/rebind 枚举由 M2 处理器收窄
				"target_player_id": ["member_id"],
			}
		"owner.save", "owner.export", "owner.close":
			return {}
		_:
			return null


# ================= 事件信封 =================

static func validate_event(event: Dictionary) -> String:
	var required := ["event_id", "event_sequence", "world_id", "business_revision", "actor_player_id", "game_day", "event_type", "ruleset_version", "payload"]
	if event.size() != required.size():
		return "CONTRACTS_EVENT_FIELD_SET"
	if not event.has_all(required):
		return "CONTRACTS_EVENT_MISSING_FIELD"
	if not ContractIds.is_event_id(event["event_id"]):
		return "CONTRACTS_EVENT_ID"
	if event["event_sequence"] is not int or event["event_sequence"] < 1:
		return "CONTRACTS_EVENT_SEQUENCE"
	if not ContractIds.is_world_id(event["world_id"]):
		return "CONTRACTS_EVENT_WORLD_ID"
	if event["business_revision"] is not int or event["business_revision"] < 0 or event["business_revision"] > ContractLimits.MAX_BUSINESS_INT:
		return "CONTRACTS_EVENT_REVISION"
	if not ContractIds.is_player_id(event["actor_player_id"]):
		return "CONTRACTS_EVENT_ACTOR"
	if event["game_day"] is not int or event["game_day"] < 1:
		return "CONTRACTS_EVENT_GAME_DAY"
	if event["event_type"] is not String or not event["event_type"] in EVENTS:
		return "CONTRACTS_EVENT_UNKNOWN_TYPE"
	if event["ruleset_version"] is not String or (event["ruleset_version"] as String).is_empty():
		return "CONTRACTS_EVENT_RULESET"
	if event["payload"] is not Dictionary:
		return "CONTRACTS_EVENT_PAYLOAD"
	return ""


# ================= 存档 envelope =================

## envelope: format_version, world_id, generation, payload_json, payload_sha256
## payload_json 按原字节保存；sha256 对应其 UTF-8 字节（String.sha256_text 即 UTF-8 摘要）。
static func validate_save_envelope(env: Dictionary) -> String:
	var required := ["format_version", "world_id", "generation", "payload_json", "payload_sha256"]
	if env.size() != required.size():
		return "CONTRACTS_ENVELOPE_FIELD_SET"
	if not env.has_all(required):
		return "CONTRACTS_ENVELOPE_MISSING_FIELD"
	if env["format_version"] is not int or env["format_version"] != SAVE_FORMAT_VERSION_CANDIDATE:
		return "CONTRACTS_ENVELOPE_FORMAT_VERSION"
	if not ContractIds.is_world_id(env["world_id"]):
		return "CONTRACTS_ENVELOPE_WORLD_ID"
	if env["generation"] is not int or env["generation"] < 1:
		return "CONTRACTS_ENVELOPE_GENERATION"
	if env["payload_json"] is not String:
		return "CONTRACTS_ENVELOPE_PAYLOAD_TYPE"
	if (env["payload_json"] as String).to_utf8_buffer().size() > ContractLimits.SAVE_FILE_MAX_BYTES:
		return "CONTRACTS_ENVELOPE_PAYLOAD_TOO_LARGE"
	if env["payload_sha256"] is not String:
		return "CONTRACTS_ENVELOPE_CHECKSUM_TYPE"
	var actual: String = (env["payload_json"] as String).sha256_text()
	if actual != env["payload_sha256"]:
		return "CONTRACTS_ENVELOPE_CHECKSUM_MISMATCH"
	if JSON.parse_string(env["payload_json"]) == null:
		return "CONTRACTS_ENVELOPE_PAYLOAD_NOT_JSON"
	return ""


static func make_save_envelope(world_id: String, generation: int, payload_json: String) -> Dictionary:
	return {
		"format_version": SAVE_FORMAT_VERSION_CANDIDATE,
		"world_id": world_id,
		"generation": generation,
		"payload_json": payload_json,
		"payload_sha256": payload_json.sha256_text(),
	}
