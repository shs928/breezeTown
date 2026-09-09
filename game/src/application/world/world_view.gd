class_name WorldView
## 按成员权限过滤的世界视图（SIM 唯一维护，M2 SIM-02）。
## 契约参考实现在 ContractView；本类把 WorldState 组装成其输入并补充同步元数据。
## NET 同步（application/sync）必须复用本类，不得另写过滤逻辑（契约 3.2）。

const ContractLimits := preload("res://src/contracts/contract_limits.gd")
const ContractView := preload("res://src/contracts/contract_view.gd")
const ContractError := preload("res://src/contracts/contract_error.gd")
const Leaderboard := preload("res://src/domain/statistics/leaderboard.gd")
const WorldState := preload("res://src/domain/world/world_state.gd")

const SNAPSHOT_PROTOCOL_VERSION := 1


## 构建某成员的可见视图快照。返回 {ok, snapshot} 或 {ok:false, error}。
static func build(world: WorldState, member_id: String, online_players: Array = []) -> Dictionary:
	var member: Dictionary = world.find_member(member_id)
	if member.is_empty():
		return {"ok": false, "error": ContractError.NOT_AUTHENTICATED}
	# 在线状态是运行期数据，不在持久化成员记录里；组装视图时按服务器会话补入。
	var members_view: Array = []
	for raw: Dictionary in world.members:
		var row: Dictionary = raw.duplicate(true)
		row["online"] = raw["player_id"] in online_players
		members_view.append(row)
	var world_dict := {
		"business_revision": world.business_revision,
		"game_day": world.game_day,
		"day_elapsed_ms": world.day_elapsed_ms,
		"treasury": world.treasury,
		"members": members_view,
		"inventories": world.containers,
		"crops": world.crops.values(),
		"projects": world.projects,
		"leaderboard": Leaderboard.build(world, online_players),
	}
	var view: Dictionary = ContractView.build_player_view(world_dict, member_id)
	var invalid := ContractView.validate_player_view(view)
	if not invalid.is_empty():
		return {"ok": false, "error": invalid}
	view["protocol_version"] = SNAPSHOT_PROTOCOL_VERSION
	view["authority_epoch"] = world.authority_epoch
	view["world_id"] = world.world_id
	view["ruleset_version"] = world.ruleset_version
	view["content_hash"] = world.content_hash
	view["sim_tick"] = world.sim_tick
	# 成员行的 online 状态由服务器提供（ Leaderboard 已含；members 行同步标注）
	for row: Dictionary in view["members"]:
		row["online"] = row["player_id"] in online_players
	var size := JSON.stringify(view).to_utf8_buffer().size()
	if size > ContractLimits.PLAYER_VIEW_SNAPSHOT_MAX_BYTES:
		return {"ok": false, "error": "snapshot_too_large:%d" % size}
	return {"ok": true, "snapshot": view}
