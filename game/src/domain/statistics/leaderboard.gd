class_name Leaderboard
## 榜单投影（ECON 唯一维护，PRD 第 9 章 / 契约 9.1）。
## 读取只读物化视图（world.stats），不每帧扫描日志；排序为数值降序、并列竞赛名次（1、1、3），
## 并列内按加入顺序稳定。收益与贡献完全分开，收益不发放任何经济奖励。

const ContractLimits := preload("res://src/contracts/contract_limits.gd")
const WorldState := preload("res://src/domain/world/world_state.gd")

const METRICS: PackedStringArray = ["total_gross_sales", "today_gross_sales", "contribution_total"]


## 返回三张榜：{total_gross_sales: [rows], today_gross_sales: [rows], contribution_total: [rows]}。
## 每行：{player_id, display_name, join_order, online, status, value, rank, contribution_breakdown}
static func build(world: WorldState, online_players: Array = []) -> Dictionary:
	var rows: Array = []
	for member: Dictionary in world.members:
		var player_id: String = member["player_id"]
		var stats: Dictionary = world.stats["members"].get(player_id, {})
		var contribution: Dictionary = stats.get("contribution", {})
		var contribution_total := 0
		for key: String in contribution:
			contribution_total += int(contribution[key])
		rows.append({
			"player_id": player_id,
			"display_name": member["display_name"],
			"join_order": int(member["join_order"]),
			"status": member["status"],
			"online": player_id in online_players,
			"total_gross_sales": int(stats.get("total_gross_sales", 0)),
			"today_gross_sales": int(stats.get("today_gross_sales", 0)),
			"contribution_total": contribution_total,
			"contribution_breakdown": contribution.duplicate(true),
		})
	var result := {}
	for metric: String in METRICS:
		result[metric] = _rank(rows, metric)
	return result


## 竞赛名次排序：数值降序；并列同号；并列内按 join_order 稳定。
static func _rank(rows: Array, metric: String) -> Array:
	var sorted := rows.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a[metric] != b[metric]:
			return a[metric] > b[metric]
		return a["join_order"] < b["join_order"]
	)
	var out: Array = []
	var prev_value := -1
	var prev_rank := 0
	for i in sorted.size():
		var value: int = sorted[i][metric]
		var rank: int = prev_rank if value == prev_value else i + 1
		var row: Dictionary = sorted[i].duplicate(true)
		row["value"] = value
		row["rank"] = rank
		out.append(row)
		prev_value = value
		prev_rank = rank
	return out


## 个人贡献明细 + 规则版本（PRD 9.3）。
static func member_detail(world: WorldState, player_id: String) -> Dictionary:
	var member: Dictionary = world.find_member(player_id)
	if member.is_empty():
		return {}
	var stats: Dictionary = world.stats["members"].get(player_id, {})
	return {
		"player_id": player_id,
		"display_name": member["display_name"],
		"contribution_breakdown": stats.get("contribution", {}).duplicate(true),
		"ruleset_version": world.ruleset_version,
		"game_day": world.game_day,
	}


## 对账检查（契约 5.4 / CASE-23）：成员销售额求和 == 世界总额；贡献与收益分离。
static func reconcile(world: WorldState) -> Dictionary:
	var member_sum := 0
	var contribution_total := 0
	for player_id: String in world.stats["members"]:
		member_sum += int(world.stats["members"][player_id]["total_gross_sales"])
		var contribution: Dictionary = world.stats["members"][player_id].get("contribution", {})
		for key: String in contribution:
			contribution_total += int(contribution[key])
	return {
		"ok": member_sum == int(world.stats["world_total_sales"]),
		"member_sales_sum": member_sum,
		"world_total_sales": int(world.stats["world_total_sales"]),
		"contribution_total": contribution_total,
		"treasury": world.treasury,
	}
