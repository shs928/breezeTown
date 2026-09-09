extends SceneTree
## FND-02 契约候选最小测试探针（headless）。
## 运行：godot --headless --path game --script res://tests/unit/contracts/test_runner.gd
## （QA-01 建成统一检查入口后由其纳管。）
## 合法样例必须通过校验；非法样例必须被拒绝；退出码 0=通过，1=失败。
## 注意：--script 模式不注册全局类名，跨文件引用必须显式 preload。

const ContractLimits := preload("res://src/contracts/contract_limits.gd")
const ContractIds := preload("res://src/contracts/contract_ids.gd")
const ContractError := preload("res://src/contracts/contract_error.gd")
const ContractEnvelopes := preload("res://src/contracts/contract_envelopes.gd")
const ContractPublicSnapshot := preload("res://src/contracts/contract_public_snapshot.gd")
const ContractView := preload("res://src/contracts/contract_view.gd")
const ContentValidator := preload("res://src/contracts/content_validator.gd")

var _checks := 0
var _failures: PackedStringArray = []


func _initialize() -> void:
	_test_legal_samples()
	_test_illegal_samples()
	_test_name_and_quantity()
	_test_id_formats()
	_test_snapshot_ranks()
	_test_player_view()
	_test_content_bundle()

	if _failures.is_empty():
		print("CONTRACTS_OK checks=%d" % _checks)
		quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: " + failure)
		printerr("CONTRACTS_FAILED checks=%d failures=%d" % [_checks, _failures.size()])
		quit(1)


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(label)


func _load(path: String) -> Variant:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return _normalize_numbers(parsed)


## JSON 把所有数字解析为 float；契约 4.2 要求“解析后重新校验，不依赖隐式类型转换”。
## 这里把整值 float 归一化为 int（非整值保留 float，交由校验器按小数拒绝）。
func _normalize_numbers(value: Variant) -> Variant:
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


# ---------- 合法样例 ----------

func _test_legal_samples() -> void:
	var cmd: Dictionary = _load("res://content/schema/examples/legal/command_plant.json")
	_check(ContractEnvelopes.validate_command(cmd) == "", "legal command_plant should pass")

	var event: Dictionary = _load("res://content/schema/examples/legal/event_produce_sold.json")
	_check(ContractEnvelopes.validate_event(event) == "", "legal event_produce_sold should pass")

	var snapshot: Dictionary = _load("res://content/schema/examples/legal/public_snapshot.json")
	_check(ContractPublicSnapshot.validate(snapshot) == "", "legal public_snapshot should pass")

	var envelope: Dictionary = _load("res://content/schema/examples/legal/save_envelope.json")
	_check(ContractEnvelopes.validate_save_envelope(envelope) == "", "legal save_envelope should pass")

	var map: Dictionary = _load("res://content/schema/examples/map_town_minimal.json")
	_check(ContentValidator.validate_map(map) == "", "legal map_town_minimal should pass")


# ---------- 非法样例 ----------

func _test_illegal_samples() -> void:
	var cases := {
		"res://content/schema/examples/illegal/command_unknown_type.json":
			func(d: Variant) -> bool: return ContractEnvelopes.validate_command(d).begins_with("CONTRACTS_COMMAND_UNKNOWN_TYPE"),
		"res://content/schema/examples/illegal/command_carries_actor.json":
			func(d: Variant) -> bool: return ContractEnvelopes.validate_command(d).begins_with("CONTRACTS_COMMAND_FORBIDDEN_FIELD"),
		"res://content/schema/examples/illegal/command_price_in_payload.json":
			func(d: Variant) -> bool: return ContractEnvelopes.validate_command(d).begins_with("CONTRACTS_PAYLOAD_UNKNOWN_KEY"),
		"res://content/schema/examples/illegal/command_quantity_out_of_range.json":
			func(d: Variant) -> bool: return ContractEnvelopes.validate_command(d).begins_with("CONTRACTS_PAYLOAD_RANGE"),
		"res://content/schema/examples/illegal/command_unknown_payload_key.json":
			func(d: Variant) -> bool: return ContractEnvelopes.validate_command(d).begins_with("CONTRACTS_PAYLOAD_UNKNOWN_KEY"),
		"res://content/schema/examples/illegal/event_unknown_type.json":
			func(d: Variant) -> bool: return ContractEnvelopes.validate_event(d).begins_with("CONTRACTS_EVENT_UNKNOWN_TYPE"),
		"res://content/schema/examples/illegal/snapshot_extra_field.json":
			func(d: Variant) -> bool: return ContractPublicSnapshot.validate(d).begins_with("CONTRACTS_SNAPSHOT_UNKNOWN_FIELD"),
		"res://content/schema/examples/illegal/snapshot_forbidden_ip.json":
			func(d: Variant) -> bool: return ContractPublicSnapshot.validate(d).begins_with("CONTRACTS_SNAPSHOT_ENTRY_UNKNOWN_FIELD"),
		"res://content/schema/examples/illegal/snapshot_negative_value.json":
			func(d: Variant) -> bool: return ContractPublicSnapshot.validate(d).begins_with("CONTRACTS_SNAPSHOT_ENTRY_VALUE"),
		"res://content/schema/examples/illegal/snapshot_private_id.json":
			func(d: Variant) -> bool: return ContractPublicSnapshot.validate(d).begins_with("CONTRACTS_SNAPSHOT_ENTRY_PUBLIC_ID"),
		"res://content/schema/examples/illegal/envelope_checksum_mismatch.json":
			func(d: Variant) -> bool: return ContractEnvelopes.validate_save_envelope(d).begins_with("CONTRACTS_ENVELOPE_CHECKSUM_MISMATCH"),
		"res://content/schema/examples/illegal/envelope_future_format.json":
			func(d: Variant) -> bool: return ContractEnvelopes.validate_save_envelope(d).begins_with("CONTRACTS_ENVELOPE_FORMAT_VERSION"),
		"res://content/schema/examples/illegal/envelope_extra_field.json":
			func(d: Variant) -> bool: return ContractEnvelopes.validate_save_envelope(d).begins_with("CONTRACTS_ENVELOPE_FIELD_SET"),
		"res://content/schema/examples/illegal/map_row_too_short.json":
			func(d: Variant) -> bool: return ContentValidator.validate_map(d).begins_with("CONTENT_MAP_ROW_WIDTH"),
		"res://content/schema/examples/illegal/map_missing_spawn.json":
			func(d: Variant) -> bool: return ContentValidator.validate_map(d).begins_with("CONTENT_MAP_SPAWN_COUNT"),
		"res://content/schema/examples/illegal/map_facility_out_of_bounds.json":
			func(d: Variant) -> bool: return ContentValidator.validate_map(d).begins_with("CONTENT_MAP_FACILITY_BOUNDS"),
		"res://content/schema/examples/illegal/map_farmable_outside_rect.json":
			func(d: Variant) -> bool: return ContentValidator.validate_map(d).begins_with("CONTENT_MAP_FARMABLE_OUTSIDE_RECT"),
	}
	for path: String in cases:
		var doc: Variant = _load(path)
		var judge: Callable = cases[path]
		var rejected := false
		var detail := "no data"
		if doc == null:
			detail = "JSON parse failed"
		else:
			detail = str(judge.call(doc))
			rejected = detail == "true"
		_check(rejected, "illegal sample must be rejected: %s (judge=%s)" % [path, detail])


# ---------- 名称与数量边界 ----------

func _test_name_and_quantity() -> void:
	_check(ContractLimits.sanitize_display_name("  园丁一号  ") == "园丁一号", "name trimmed")
	_check(ContractLimits.sanitize_display_name("a\nb") == "ab", "control char removed")
	_check(ContractLimits.sanitize_display_name("   ") == "", "blank name rejected")
	_check(ContractLimits.sanitize_display_name("123456789012345678901234567890123") == "", "33 chars rejected")
	_check(ContractLimits.sanitize_display_name("汉汉汉汉汉汉汉汉汉汉汉汉汉汉汉汉汉汉汉汉汉汉汉汉汉汉汉汉汉汉汉汉汉") == "", "33 CJK chars rejected")
	var long_bytes := "á".repeat(32)  # 64 bytes utf-8, 32 chars — legal
	_check(ContractLimits.sanitize_display_name(long_bytes) == long_bytes, "32 accented chars ok")
	_check(not ContractLimits.is_valid_trade_quantity(0), "quantity 0 rejected")
	_check(not ContractLimits.is_valid_trade_quantity(-1), "quantity -1 rejected")
	_check(not ContractLimits.is_valid_trade_quantity(100), "quantity 100 rejected")
	_check(not ContractLimits.is_valid_trade_quantity(1.5), "quantity float rejected")
	_check(not ContractLimits.is_valid_trade_quantity("10"), "quantity string rejected")
	_check(ContractLimits.is_valid_trade_quantity(1) and ContractLimits.is_valid_trade_quantity(99), "quantity 1..99 accepted")


# ---------- ID 格式 ----------

func _test_id_formats() -> void:
	_check(ContractIds.is_player_id("m" + "0123456789abcdef0123456789abcdef"), "player_id ok")
	_check(not ContractIds.is_player_id("pm0123456789abcdef0123456789abcdef"), "public prefix rejected as player_id")
	_check(not ContractIds.is_player_id("M0123456789ABCDEF0123456789ABCDEF"), "uppercase rejected")
	_check(not ContractIds.is_player_id("m0123456789abcdef"), "short hex rejected")
	_check(ContractIds.is_public_player_id("pm" + "0123456789abcdef0123456789abcdef"), "public_player_id ok")
	_check(ContractIds.is_world_id("w" + "0123456789abcdef0123456789abcdef"), "world_id ok")
	_check(ContractIds.is_public_world_id("pw" + "0123456789abcdef0123456789abcdef"), "public_world_id ok")
	_check(ContractIds.is_connection_id("c0123456789abcdef"), "connection_id ok")
	_check(ContractIds.is_authority_epoch("e" + "0123456789abcdef0123456789abcdef"), "epoch ok")
	_check(ContractIds.is_event_id("ev0123456789abcdef0123456789abcdef"), "event_id ok")
	_check(ContractIds.is_crop_instance_id("ci0123456789abcdef0123456789abcdef"), "crop_instance_id ok")
	_check(ContractIds.is_definition_id("crop.radish"), "definition_id ok")
	_check(not ContractIds.is_definition_id("Crop.Radish"), "definition_id case rejected")
	_check(not ContractIds.is_definition_id("1crop"), "definition_id leading digit rejected")


# ---------- 快照并列名次 ----------

func _test_snapshot_ranks() -> void:
	var world := {
		"public_world_id": "pw" + "0123456789abcdef0123456789abcdef",
		"world_display_name": "测试农场",
		"generated_at_utc": "2026-09-08T12:00:00Z",
		"game_day": 3,
		"ruleset_version": "v1.0",
	}
	var rows := [
		{"public_player_id": "pm" + "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "alias": "甲",
			"total_gross_sales": 240, "today_gross_sales": 96,
			"contribution_breakdown": {"planting": 4, "watering": 2, "harvesting": 3, "donation": 0}},
		{"public_player_id": "pm" + "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", "alias": "乙",
			"total_gross_sales": 240, "today_gross_sales": 144,
			"contribution_breakdown": {"planting": 6, "watering": 2, "harvesting": 4, "donation": 2}},
		{"public_player_id": "pm" + "cccccccccccccccccccccccccccccccc", "alias": "丙",
			"total_gross_sales": 48, "today_gross_sales": 0,
			"contribution_breakdown": {"planting": 1, "watering": 0, "harvesting": 0, "donation": 1}},
	]
	var snap := ContractPublicSnapshot.build(world, rows)
	_check(ContractPublicSnapshot.validate(snap) == "", "built snapshot valid")
	var entries: Array = snap["entries"]
	var a: Dictionary = entries[0]
	var b: Dictionary = entries[1]
	var c: Dictionary = entries[2]
	_check(a["ranks"]["total_gross_sales"] == 1 and b["ranks"]["total_gross_sales"] == 1,
		"tie both rank 1")
	_check(c["ranks"]["total_gross_sales"] == 3, "competition rank skips to 3")
	_check(a["contribution_total"] == 9, "contribution total summed")
	_check(b["ranks"]["today_gross_sales"] == 1 and a["ranks"]["today_gross_sales"] == 2,
		"today ranking distinct")


# ---------- 玩家视图过滤 ----------

func _test_player_view() -> void:
	var world := {
		"business_revision": 72,
		"game_day": 4,
		"day_elapsed_ms": 120000,
		"treasury": 457,
		"members": [
			{"player_id": "m" + "1".repeat(32), "display_name": "甲", "avatar": "avatar.1", "join_order": 1, "online": true, "status": "active", "credential_digest": "secret-digest"},
			{"player_id": "m" + "2".repeat(32), "display_name": "乙", "avatar": "avatar.2", "join_order": 2, "online": false, "status": "active", "credential_digest": "other-digest"},
		],
		"inventories": {
			"backpack:m" + "1".repeat(32): {"slots": [{"item": "seed.radish", "qty": 5}]},
			"backpack:m" + "2".repeat(32): {"slots": [{"item": "seed.potato", "qty": 2}]},
			"shared_storage": {"slots": []},
		},
		"crops": [],
		"projects": [],
		"leaderboard": {"total_sales": {}, "today_sales": {}, "contribution": {}},
	}
	var view := ContractView.build_player_view(world, "m" + "1".repeat(32))
	_check(ContractView.validate_player_view(view) == "", "own view valid")
	_check(view["inventories"].has("backpack:m" + "1".repeat(32)), "own backpack present")
	_check(not view["inventories"].has("backpack:m" + "2".repeat(32)), "foreign backpack absent")
	_check(not JSON.stringify(view).contains("secret-digest"), "no credential leak")
	var other := ContractView.build_player_view(world, "m" + "2".repeat(32))
	_check(ContractView.validate_player_view(other) == "", "other member view valid")
	_check(not other["inventories"].has("backpack:m" + "1".repeat(32)), "cannot see first member backpack")


# ---------- 内容定义整包 ----------

func _test_content_bundle() -> void:
	var items: Dictionary = _load("res://content/schema/items.json")
	var crops: Dictionary = _load("res://content/schema/crops.json")
	var projects: Dictionary = _load("res://content/schema/projects.json")
	_check(ContentValidator.validate_content_bundle(items, crops, projects) == "",
		"content bundle valid")

	# 作物引用未知物品 → 拒绝
	var bad_crops: Dictionary = crops.duplicate(true)
	(bad_crops["crops"][0] as Dictionary)["produce_item_id"] = "produce.unknown"
	_check(ContentValidator.validate_content_bundle(items, bad_crops, projects) != "",
		"unknown item reference rejected")

	# 项目需求引用种子（非产物）→ 拒绝
	var bad_projects: Dictionary = projects.duplicate(true)
	(bad_projects["projects"][0]["requires"][0] as Dictionary)["item_id"] = "seed.radish"
	_check(ContentValidator.validate_content_bundle(items, crops, bad_projects) != "",
		"project requiring seed rejected")

	# 草莓阶段缺失最终成熟日 → 拒绝
	var bad_crops2: Dictionary = crops.duplicate(true)
	var strawberry: Dictionary = bad_crops2["crops"][4]
	(strawberry["stages"][-1] as Dictionary)["min_growth_days"] = 3
	_check(ContentValidator.validate_content_bundle(items, bad_crops2, projects) != "",
		"strawberry stage mismatch rejected")
