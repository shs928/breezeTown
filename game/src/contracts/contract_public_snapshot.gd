class_name ContractPublicSnapshot
## 公开榜单快照白名单契约（契约 9.2 / PRD 第 10 章，M0 候选）。
##
## 规则：
## - 白名单构造，不“先复制存档再删字段”；出现任何白名单外字段即拒绝。
## - 三榜来自同一个一致 revision；行过滤后重排名次。
## - 禁止出现：IP、设备信息、路径、私有 ID、凭据、背包、聊天等任何白名单外内容。

const PUBLIC_SCHEMA_VERSION := 1
const SOURCE_KIND := "self_hosted_snapshot"
const RANKING_SCOPE := "consenting_members_only"

const ContractLimits := preload("res://src/contracts/contract_limits.gd")
const ContractIds := preload("res://src/contracts/contract_ids.gd")

const ALLOWED_TOP_FIELDS: PackedStringArray = [
	"public_schema_version", "public_world_id", "world_display_name",
	"generated_at_utc", "game_day", "ruleset_version",
	"source_kind", "ranking_scope", "entries",
]
const ALLOWED_ENTRY_FIELDS: PackedStringArray = [
	"public_player_id", "alias",
	"total_gross_sales", "today_gross_sales",
	"contribution_total", "contribution_breakdown", "ranks",
]
const CONTRIBUTION_KEYS: PackedStringArray = ["planting", "watering", "harvesting", "donation"]
const RANK_KEYS: PackedStringArray = ["total_gross_sales", "today_gross_sales", "contribution_total"]


## 返回空串表示合法；否则返回 CONTRACTS_SNAPSHOT_* 失败原因。
static func validate(snapshot: Dictionary) -> String:
	for k: Variant in snapshot:
		if not k in ALLOWED_TOP_FIELDS:
			return "CONTRACTS_SNAPSHOT_UNKNOWN_FIELD:" + str(k)
	for k: String in ALLOWED_TOP_FIELDS:
		if not snapshot.has(k):
			return "CONTRACTS_SNAPSHOT_MISSING_FIELD:" + k
	if snapshot["public_schema_version"] != PUBLIC_SCHEMA_VERSION:
		return "CONTRACTS_SNAPSHOT_SCHEMA_VERSION"
	if not ContractIds.is_public_world_id(snapshot["public_world_id"]):
		return "CONTRACTS_SNAPSHOT_WORLD_ID"
	if snapshot["world_display_name"] is not String or (snapshot["world_display_name"] as String).is_empty():
		return "CONTRACTS_SNAPSHOT_WORLD_NAME"
	if snapshot["generated_at_utc"] is not String or (snapshot["generated_at_utc"] as String).is_empty():
		return "CONTRACTS_SNAPSHOT_TIMESTAMP"
	if snapshot["game_day"] is not int or snapshot["game_day"] < 1:
		return "CONTRACTS_SNAPSHOT_GAME_DAY"
	if snapshot["ruleset_version"] is not String or (snapshot["ruleset_version"] as String).is_empty():
		return "CONTRACTS_SNAPSHOT_RULESET"
	if snapshot["source_kind"] != SOURCE_KIND:
		return "CONTRACTS_SNAPSHOT_SOURCE_KIND"
	if snapshot["ranking_scope"] != RANKING_SCOPE:
		return "CONTRACTS_SNAPSHOT_RANKING_SCOPE"
	if snapshot["entries"] is not Array:
		return "CONTRACTS_SNAPSHOT_ENTRIES_TYPE"
	for entry_v: Variant in snapshot["entries"]:
		if entry_v is not Dictionary:
			return "CONTRACTS_SNAPSHOT_ENTRY_TYPE"
		var err := _validate_entry(entry_v)
		if not err.is_empty():
			return err
	return ""


static func _validate_entry(entry: Dictionary) -> String:
	for k: Variant in entry:
		if not k in ALLOWED_ENTRY_FIELDS:
			return "CONTRACTS_SNAPSHOT_ENTRY_UNKNOWN_FIELD:" + str(k)
	for k: String in ALLOWED_ENTRY_FIELDS:
		if not entry.has(k):
			return "CONTRACTS_SNAPSHOT_ENTRY_MISSING_FIELD:" + k
	if not ContractIds.is_public_player_id(entry["public_player_id"]):
		return "CONTRACTS_SNAPSHOT_ENTRY_PUBLIC_ID"
	if entry["alias"] is not String or (entry["alias"] as String).is_empty():
		return "CONTRACTS_SNAPSHOT_ENTRY_ALIAS"
	for key in ["total_gross_sales", "today_gross_sales", "contribution_total"]:
		if entry[key] is not int or entry[key] < 0 or entry[key] > ContractLimits.MAX_BUSINESS_INT:
			return "CONTRACTS_SNAPSHOT_ENTRY_VALUE:" + key
	var breakdown: Variant = entry["contribution_breakdown"]
	if breakdown is not Dictionary or (breakdown as Dictionary).size() != CONTRIBUTION_KEYS.size():
		return "CONTRACTS_SNAPSHOT_ENTRY_BREAKDOWN_SET"
	for key: String in CONTRIBUTION_KEYS:
		if not breakdown.has(key) or breakdown[key] is not int or breakdown[key] < 0:
			return "CONTRACTS_SNAPSHOT_ENTRY_BREAKDOWN:" + key
	var ranks: Variant = entry["ranks"]
	if ranks is not Dictionary or (ranks as Dictionary).size() != RANK_KEYS.size():
		return "CONTRACTS_SNAPSHOT_ENTRY_RANKS_SET"
	for key: String in RANK_KEYS:
		if not ranks.has(key) or ranks[key] is not int or ranks[key] < 1:
			return "CONTRACTS_SNAPSHOT_ENTRY_RANKS:" + key
	return ""


## 由白名单构造快照（只接受显式传入的字段，杜绝整存档倾倒）。
## world: {public_world_id, world_display_name, generated_at_utc, game_day, ruleset_version}
## rows: [{public_player_id, alias, total_gross_sales, today_gross_sales,
##         contribution_breakdown:{...}}] —— 已按授权过滤的行。
static func build(world: Dictionary, rows: Array) -> Dictionary:
	var enriched: Array = []
	for row: Dictionary in rows:
		var total := 0
		for key: String in CONTRIBUTION_KEYS:
			total += int(row["contribution_breakdown"].get(key, 0))
		enriched.append({
			"public_player_id": row["public_player_id"],
			"alias": row["alias"],
			"total_gross_sales": int(row["total_gross_sales"]),
			"today_gross_sales": int(row["today_gross_sales"]),
			"contribution_total": total,
			"contribution_breakdown": row["contribution_breakdown"].duplicate(true),
			"ranks": {"total_gross_sales": 1, "today_gross_sales": 1, "contribution_total": 1},
		})
	# 过滤后重排名：数值降序、并列同号（竞赛名次 1、1、3），并列内按加入顺序稳定。
	for rank_key in ["total_gross_sales", "today_gross_sales", "contribution_total"]:
		_assign_competition_ranks(enriched, rank_key)
	return {
		"public_schema_version": PUBLIC_SCHEMA_VERSION,
		"public_world_id": world["public_world_id"],
		"world_display_name": world["world_display_name"],
		"generated_at_utc": world["generated_at_utc"],
		"game_day": world["game_day"],
		"ruleset_version": world["ruleset_version"],
		"source_kind": SOURCE_KIND,
		"ranking_scope": RANKING_SCOPE,
		"entries": enriched,
	}


static func _assign_competition_ranks(entries: Array, value_key: String) -> void:
	var sorted := entries.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a[value_key] != b[value_key]:
			return a[value_key] > b[value_key]
		return a["public_player_id"] < b["public_player_id"]  # 稳定次序（M0 用 ID；正式用 join_order）
	)
	var prev_value := -1
	var prev_rank := 0
	for i in sorted.size():
		var value: int = sorted[i][value_key]
		var rank := prev_rank if value == prev_value else i + 1
		sorted[i]["ranks"][value_key] = rank
		prev_value = value
		prev_rank = rank
