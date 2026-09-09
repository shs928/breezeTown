class_name WorldState
## 权威世界状态（契约 4.1）。所有业务变更只能经 TransactionCoordinator 原子提交。
## SIM 唯一写入；其他模块只读或通过应用层命令修改。

const ContractLimits := preload("res://src/contracts/contract_limits.gd")
const ContractIds := preload("res://src/contracts/contract_ids.gd")

var world_id := ""
var owner_player_id := ""
var schema_version := 1
var ruleset_version := "v1.0"
var content_hash := ""

var game_day := 1
var day_elapsed_ms := 0
var business_revision := 0
var next_event_seq := 1
var treasury := ContractLimits.INITIAL_TREASURY

var members: Array = []          # [{player_id, join_order, role, status, display_name, credential_digest, public_player_id, publication_consent, public_alias, avatar, inventory_id, last_valid_position}]
var plots: Dictionary = {}       # "x,y" -> {state, crop_instance_id}
var crops: Dictionary = {}       # crop_instance_id -> CropInstance dict
var projects: Array = []
var containers: Dictionary = {}  # container_id -> {capacity, slots, revision}
var stats: Dictionary = {}
var publication_enabled := false
var consent_revision := 0

# 运行期（不进存档的持久真相，但随快照携带 sim_tick/epoch 供同步）
var sim_tick := 0
var authority_epoch := ""


static func create(world_id: String, owner_player_id: String, owner_name: String) -> WorldState:
	var state := new()
	state.world_id = world_id
	state.owner_player_id = owner_player_id
	state.authority_epoch = "e" + _random_hex(32)
	state.members.append(state._new_member(owner_player_id, owner_name, 1, "owner"))
	# 初始共享资金与仓库（PRD 7.2 / 5.1）
	state.containers["shared_storage"] = {
		"capacity": ContractLimits.SHARED_STORAGE_SLOTS,
		"slots": empty_slots(ContractLimits.SHARED_STORAGE_SLOTS),
		"revision": 0,
	}
	state.containers["shared_storage"]["slots"][0] = {"item_definition_id": "seed.radish", "quantity": ContractLimits.INITIAL_RADISH_SEEDS}
	# 四株初始成熟萝卜（不计贡献）
	state.stats = {"members": {}, "world_total_sales": 0, "world_total_purchases": 0, "last_applied_event_seq": 0}
	state.stats["members"][owner_player_id] = state._empty_member_stats()
	return state


func _new_member(player_id: String, display_name: String, join_order: int, role: String) -> Dictionary:
	return {
		"player_id": player_id,
		"join_order": join_order,
		"role": role,
		"status": "active",
		"display_name": display_name,
		"credential_digest": "",
		"public_player_id": "pm" + _random_hex(32),
		"publication_consent": false,
		"public_alias": "",
		"avatar": "avatar.%d" % (((join_order - 1) % 4) + 1),
		"inventory_id": "backpack:" + player_id,
		"last_valid_position": {"x": 0.0, "y": 0.0},
	}


## 新增成员（M1 单人只用于测试夹具；联机批准在 M2）。
func add_member(display_name: String, role := "member") -> Dictionary:
	var player_id := "m" + _random_hex(32)
	var member := _new_member(player_id, display_name, members.size() + 1, role)
	members.append(member)
	containers[member["inventory_id"]] = {
		"capacity": ContractLimits.BACKPACK_SLOTS,
		"slots": empty_slots(ContractLimits.BACKPACK_SLOTS),
		"revision": 0,
	}
	stats["members"][player_id] = _empty_member_stats()
	return member


func find_member(player_id: String) -> Dictionary:
	for member: Dictionary in members:
		if member["player_id"] == player_id:
			return member
	return {}


func member_exists(player_id: String) -> bool:
	return not find_member(player_id).is_empty()


## 日切：递增日、清浇水、重置当日收益桶。返回是否发生日切。
func advance_day() -> bool:
	game_day += 1
	day_elapsed_ms = 0
	for crop_id: String in crops:
		crops[crop_id]["watered_day"] = 0
	for player_id: String in stats["members"]:
		stats["members"][player_id]["today_gross_sales"] = 0
	return true


## 只读视图（按成员权限过滤），复用契约过滤逻辑的语义。
func to_dict() -> Dictionary:
	return {
		"world_id": world_id,
		"owner_player_id": owner_player_id,
		"schema_version": schema_version,
		"ruleset_version": ruleset_version,
		"content_hash": content_hash,
		"game_day": game_day,
		"day_elapsed_ms": day_elapsed_ms,
		"business_revision": business_revision,
		"next_event_seq": next_event_seq,
		"treasury": treasury,
		"members": members,
		"plots": plots,
		"crops": crops,
		"projects": projects,
		"containers": containers,
		"stats": stats,
		"publication_enabled": publication_enabled,
		"consent_revision": consent_revision,
		"sim_tick": sim_tick,
		"authority_epoch": authority_epoch,
	}


func _empty_member_stats() -> Dictionary:
	return {
		"total_gross_sales": 0,
		"today_gross_sales": 0,
		"contribution": {"planting": 0, "watering": 0, "harvesting": 0, "donation": 0},
	}


static func empty_slots(count: int) -> Array:
	var slots: Array = []
	for i in count:
		slots.append(null)
	return slots


static func _random_hex(chars: int) -> String:
	return Crypto.new().generate_random_bytes(chars / 2).hex_encode()
