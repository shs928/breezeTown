extends SceneTree
## NET-05 测试（headless，本机多会话）：远端客户端的完整玩法命令经权威路径执行。
## 覆盖 CASE-11/13/16/17 的联机子场景：远端农务、共享仓库、重发、跨日。
## 运行：godot --headless --path game --script res://tests/integration/net05_test_runner.gd

const ContractLimits := preload("res://src/contracts/contract_limits.gd")
const ContractError := preload("res://src/contracts/contract_error.gd")
const ClientRoot := preload("res://src/client/client_root.gd")
const ClientSession := preload("res://src/application/session/client_session.gd")
const ConnectionCard := preload("res://src/infrastructure/network/connection_card.gd")
const ItemCatalog := preload("res://src/domain/economy/item_catalog.gd")
const WorldState := preload("res://src/domain/world/world_state.gd")

var _checks := 0
var _failures: PackedStringArray = []
var _root := ""
var _port := 24770


func _initialize() -> void:
	_root = ProjectSettings.globalize_path("res://../work/game-data/net05/%d" % Time.get_unix_time_from_system())
	DirAccess.make_dir_recursive_absolute(_root)
	_test_remote_farming_and_economy()
	_test_remote_storage_and_duplicate()
	_test_remote_day_boundary()

	if _failures.is_empty():
		print("NET05_OK checks=%d run_dir=%s" % [_checks, _root])
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: " + f)
		printerr("NET05_FAILED checks=%d failures=%d" % [_checks, _failures.size()])
		quit(1)


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(label)


func _make_client(name: String, mode: String) -> ClientRoot:
	var client := ClientRoot.new()
	client.mode = mode
	client.host_port = _port
	client.world_dir_override = _root + "/" + name + "/worlds"
	client.catalog = ItemCatalog.load_from_disk()
	client._user_data_dir = _root + "/" + name + "/user_data"
	client._worlds_dir = client.world_dir_override
	DirAccess.make_dir_recursive_absolute(client._user_data_dir)
	DirAccess.make_dir_recursive_absolute(client._worlds_dir)
	return client


func _pump(host: ClientRoot, remote: ClientRoot, condition: Callable, budget_ms := 6000) -> bool:
	var deadline := Time.get_ticks_msec() + budget_ms
	while Time.get_ticks_msec() < deadline:
		if host != null:
			host.action_poll_hosting()
		if remote != null:
			remote.action_poll_remote()
		if bool(condition.call()):
			return true
	return false


## 建立房主 + 一个已批准远端，返回 [host, remote]。
func _establish(port: int) -> Array:
	var host := _make_client("host%d" % port, "listen_host")
	host.host_port = port
	host.action_create_world("房主", "M3 联机世界")
	var card: Dictionary = host.session.connection_card
	var remote := _make_client("remote%d" % port, "client")
	var token := Crypto.new().generate_random_bytes(32).hex_encode()
	remote.action_join_world(ConnectionCard.to_text(card), token, "朋友")
	_pump(host, remote, func() -> bool: return host.pending_approvals().size() == 1)
	host.action_approve_join(host.pending_approvals()[0])
	_pump(host, remote, func() -> bool: return remote.remote_state() == ClientSession.State.ACTIVE)
	return [host, remote]


func _remote_cmd(remote: ClientRoot, host: ClientRoot, command_type: String, payload: Dictionary, expect := -1) -> Dictionary:
	var before: int = remote.remote_session.receipts.size()
	remote.action_remote_command(command_type, payload)
	_pump(host, remote, func() -> bool: return remote.remote_session.receipts.size() > before, 5000)
	var keys := remote.remote_session.receipts.keys()
	keys.sort()
	var receipt: Dictionary = remote.remote_session.receipts[keys[-1]]
	if expect >= 0:
		_check(int(receipt["client_sequence"]) == expect, "receipt sequence %d (got %d)" % [expect, int(receipt["client_sequence"])])
	return receipt


func _remote_player_id(remote: ClientRoot) -> String:
	return remote.remote_session.player_id


# ---------- 1. 远端农务 + 经济 ----------

func _test_remote_farming_and_economy() -> void:
	var parts := _establish(_port)
	var host: ClientRoot = parts[0]
	var remote: ClientRoot = parts[1]
	var pid := _remote_player_id(remote)
	# 把远端角色放到耕地旁（服务器权威位置）
	host.session.world.find_member(pid)["last_valid_position"] = {"x": 976.0, "y": 976.0}
	# 远端购买种子
	var buy := _remote_cmd(remote, host, "economy.buy_seed", {"seed_definition_id": "seed.radish", "quantity": 3})
	_check(buy["accepted"] and str(buy["error_code"]).is_empty(), "remote buy seed (%s)" % str(buy.get("error_code", "")))
	_check(host.session.world.treasury == 300 - 45, "host treasury reflects remote purchase")
	# 远端整地 + 播种
	var till := _remote_cmd(remote, host, "farming.till", {"tile_id": 1950})
	_check(till["accepted"] and str(till["error_code"]).is_empty(), "remote till (%s)" % str(till.get("error_code", "")))
	var plant := _remote_cmd(remote, host, "farming.plant", {"tile_id": 1950, "seed_slot": 0, "seed_definition_id": "seed.radish"})
	_check(plant["accepted"] and str(plant["error_code"]).is_empty(), "remote plant (%s)" % str(plant.get("error_code", "")))
	# 远端浇水
	var water := _remote_cmd(remote, host, "farming.water", {"tile_id": 1950})
	_check(water["accepted"] and str(water["error_code"]).is_empty(), "remote water (%s)" % str(water.get("error_code", "")))
	# 房主推进日切（服务器权威）
	host.session.runtime.tick(ContractLimits.GAME_DAY_MS)
	var crop_id: String = host.session.world.plots["1950"]["crop_instance_id"]
	_check(int(host.session.world.crops[crop_id]["growth_days"]) == 1, "crop grew via host tick")
	# 远端收获
	var harvest := _remote_cmd(remote, host, "farming.harvest", {"tile_id": 1950})
	_check(harvest["accepted"] and str(harvest["error_code"]).is_empty(), "remote harvest (%s)" % str(harvest.get("error_code", "")))
	_check(int(host.session.world.stats["members"][pid]["contribution"]["harvesting"]) == 3, "remote contribution recorded")
	host.action_quit()
	remote.remote_session.close()


# ---------- 2. 远端共享仓库 + 重发（CASE-13/16） ----------

func _test_remote_storage_and_duplicate() -> void:
	var parts := _establish(_port + 1)
	var host: ClientRoot = parts[0]
	var remote: ClientRoot = parts[1]
	var pid := _remote_player_id(remote)
	# 远端把买到的种子放入共享仓库
	_remote_cmd(remote, host, "economy.buy_seed", {"seed_definition_id": "seed.wheat", "quantity": 4})
	var backpack: Dictionary = host.session.world.containers["backpack:" + pid]
	var slot := -1
	for i in backpack["slots"].size():
		if backpack["slots"][i] != null and backpack["slots"][i]["item_definition_id"] == "seed.wheat":
			slot = i
			break
	var move := _remote_cmd(remote, host, "inventory.transfer", {
		"from_container": "backpack:" + pid, "to_container": "shared_storage",
		"from_slot": slot, "to_slot": 2, "quantity": 4})
	_check(move["accepted"] and str(move["error_code"]).is_empty(), "remote storage transfer (%s)" % str(move.get("error_code", "")))
	_check(host.session.world.containers["shared_storage"]["slots"][2]["quantity"] == 4, "storage reflects remote transfer")
	# 重发同一命令（同序号同内容）→ 返回原回执，不重复执行
	var seq := remote.remote_session.current_sequence()
	var storage_before: int = host.session.world.containers["shared_storage"]["slots"][2]["quantity"]
	var resend := remote.remote_session.send_command("inventory.transfer", {
		"from_container": "backpack:" + pid, "to_container": "shared_storage",
		"from_slot": slot, "to_slot": 2, "quantity": 4})
	# 手动重发同序号：直接构造（ClientSession 会自动递增，这里验证服务器幂等）
	var manual := host.session.runtime.submit({
		"protocol_version": 1, "world_id": host.session.world.world_id,
		"authority_epoch": host.session.world.authority_epoch,
		"client_sequence": seq, "command_type": "inventory.transfer",
		"payload": {"from_container": "backpack:" + pid, "to_container": "shared_storage",
			"from_slot": slot, "to_slot": 2, "quantity": 4},
		"_actor_player_id": pid,
	})
	_check(manual.get("replayed", false), "same sequence+content replays cached receipt")
	_check(int(host.session.world.containers["shared_storage"]["slots"][2]["quantity"]) == storage_before, "no duplicate transfer")
	host.action_quit()
	remote.remote_session.close()


# ---------- 3. 远端跨日边界（CASE-17 联机子场景） ----------

func _test_remote_day_boundary() -> void:
	var parts := _establish(_port + 2)
	var host: ClientRoot = parts[0]
	var remote: ClientRoot = parts[1]
	var pid := _remote_player_id(remote)
	host.session.world.find_member(pid)["last_valid_position"] = {"x": 976.0, "y": 976.0}
	# 远端买种、整地、播种（不浇水）
	_remote_cmd(remote, host, "economy.buy_seed", {"seed_definition_id": "seed.radish", "quantity": 1})
	_remote_cmd(remote, host, "farming.till", {"tile_id": 1951})
	_remote_cmd(remote, host, "farming.plant", {"tile_id": 1951, "seed_slot": 0, "seed_definition_id": "seed.radish"})
	var crop_id: String = host.session.world.plots["1951"]["crop_instance_id"]
	# 未浇水 → 日切不生长
	host.action_tick(ContractLimits.GAME_DAY_MS)
	_pump(host, remote, func() -> bool: return remote.remote_session.applied_revision() >= host.session.world.business_revision, 2000)
	_check(int(host.session.world.crops[crop_id]["growth_days"]) == 0, "no growth without watering (remote crop)")
	_check(host.session.world.game_day == 2, "day advanced")
	# 远端日切后浇水 → 再次日切生长
	_remote_cmd(remote, host, "farming.water", {"tile_id": 1951})
	host.action_tick(ContractLimits.GAME_DAY_MS)
	_pump(host, remote, func() -> bool: return remote.remote_session.applied_revision() >= host.session.world.business_revision, 2000)
	_check(int(host.session.world.crops[crop_id]["growth_days"]) == 1, "growth after watering in new day")
	# 客户端最终同步到最新 revision
	var synced := _pump(host, remote, func() -> bool:
		return remote.remote_session.applied_revision() >= host.session.world.business_revision, 5000)
	_check(synced, "remote client converged after day boundaries (client=%d host=%d)" % [remote.remote_session.applied_revision(), host.session.world.business_revision])
	host.action_quit()
	remote.remote_session.close()
