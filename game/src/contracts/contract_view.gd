class_name ContractView
## 按成员权限过滤的玩家视图 DTO（契约 7.5，M0 候选）。
##
## 世界是公共农场：作物/项目/资金/榜单对全体成员可见；
## 每个成员只能看到自己的背包内容，绝不下发其他成员的背包或任何凭据摘要。
## 该函数是 NET 同步（application/sync）复用的同一份过滤逻辑的契约参考实现。

## 输入 world 关键结构（M0 测试用最小字典；正式 WorldState 在 M1 落地）：
## {
##   game_day, day_elapsed_ms, business_revision, treasury,
##   members: [{player_id, display_name, avatar, join_order, online, status}],
##   inventories: {"backpack:<player_id>": {...}, "shared_storage": {...}},
##   crops: [{crop_instance_id, tile_id, crop_definition_id, growth_days, watered_day, stage}],
##   projects: [{project_id, accepted_quantities, completed}],
##   leaderboard: {total_sales: {player_id: int}, today_sales: {...}, contribution: {...}}
## }
## 返回过滤后的视图字典；见 docs/contracts/contracts-m0.md 的字段表。
static func build_player_view(world: Dictionary, member_id: String) -> Dictionary:
	var members_view: Array = []
	for member: Dictionary in world["members"]:
		members_view.append({
			"player_id": member["player_id"],
			"display_name": member["display_name"],
			"avatar": member["avatar"],
			"online": member["online"],
			"status": member["status"],
			"is_self": member["player_id"] == member_id,
		})

	var inventories_view := {}
	var shared: Variant = world["inventories"].get("shared_storage", null)
	if shared != null:
		inventories_view["shared_storage"] = shared
	var own_key := "backpack:" + member_id
	if world["inventories"].has(own_key):
		inventories_view[own_key] = world["inventories"][own_key]

	return {
		"base_revision": world["business_revision"],
		"game_day": world["game_day"],
		"day_elapsed_ms": world["day_elapsed_ms"],
		"treasury": world["treasury"],
		"members": members_view,
		"inventories": inventories_view,
		"crops": world["crops"],
		"projects": world["projects"],
		"leaderboard": world["leaderboard"],
		"self_player_id": member_id,
	}


## 视图不变量校验：任何成员视图都不得包含他人背包，不得包含凭据/摘要类字段。
## 返回空串表示合法，否则返回 CONTRACTS_VIEW_* 失败原因。
static func validate_player_view(view: Dictionary) -> String:
	if not view.has_all(["base_revision", "game_day", "treasury", "members", "inventories", "crops", "projects", "leaderboard", "self_player_id"]):
		return "CONTRACTS_VIEW_MISSING_FIELD"
	var self_id: String = view["self_player_id"]
	for key: String in view["inventories"]:
		if key.begins_with("backpack:") and key != "backpack:" + self_id:
			return "CONTRACTS_VIEW_FOREIGN_BACKPACK:" + key
	for key: String in ["credential_digest", "connection_id", "ip", "server_certificate"]:
		if JSON.stringify(view).contains(key):
			return "CONTRACTS_VIEW_SENSITIVE_FIELD:" + key
	for member: Dictionary in view["members"]:
		if member.has("credential_digest"):
			return "CONTRACTS_VIEW_MEMBER_CREDENTIAL"
	return ""
