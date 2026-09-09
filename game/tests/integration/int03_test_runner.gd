extends SceneTree
## INT-03 集成测试（headless）：四人并发回归 + 三建设完整推进（CASE-09..23/42）。
## 说明：CASE-42 的正式验收必须由真人在新世界以正常速率完成（QA-03/M6）；
## 本测试用 UI-04 的动作方法与合成 fixture 验证规则可达性与并发正确性，**不冒充真人体验验收**。
## 运行：godot --headless --path game --script res://tests/integration/int03_test_runner.gd

const ContractLimits := preload("res://src/contracts/contract_limits.gd")
const ContractError := preload("res://src/contracts/contract_error.gd")
const ClientRoot := preload("res://src/client/client_root.gd")
const ClientSession := preload("res://src/application/session/client_session.gd")
const ConnectionCard := preload("res://src/infrastructure/network/connection_card.gd")
const ItemCatalog := preload("res://src/domain/economy/item_catalog.gd")
const WorldState := preload("res://src/domain/world/world_state.gd")
const TransactionCoordinator := preload("res://src/application/core/transaction_coordinator.gd")
const Leaderboard := preload("res://src/domain/statistics/leaderboard.gd")

var _checks := 0
var _failures: PackedStringArray = []
var _root := ""
var _port := 24800


func _initialize() -> void:
	_root = ProjectSettings.globalize_path("res://../work/game-data/int03/%d" % Time.get_unix_time_from_system())
	DirAccess.make_dir_recursive_absolute(_root)
	_test_four_player_concurrent_regression()
	_test_full_progression_fixture()

	if _failures.is_empty():
		print("INT03_OK checks=%d run_dir=%s" % [_checks, _root])
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: " + f)
		printerr("INT03_FAILED checks=%d failures=%d" % [_checks, _failures.size()])
		quit(1)


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(label)


func _make_client(name: String, mode: String, port := 0) -> ClientRoot:
	var client := ClientRoot.new()
	client.mode = mode
	if port > 0:
		client.host_port = port
	client.world_dir_override = _root + "/" + name + "/worlds"
	client.catalog = ItemCatalog.load_from_disk()
	client._user_data_dir = _root + "/" + name + "/user_data"
	client._worlds_dir = client.world_dir_override
	DirAccess.make_dir_recursive_absolute(client._user_data_dir)
	DirAccess.make_dir_recursive_absolute(client._worlds_dir)
	return client


func _pump(host: ClientRoot, remotes: Array, condition: Callable, budget_ms := 8000) -> bool:
	var deadline := Time.get_ticks_msec() + budget_ms
	while Time.get_ticks_msec() < deadline:
		host.action_poll_hosting()
		for r: ClientRoot in remotes:
			r.action_poll_remote()
		if bool(condition.call()):
			return true
	return false


func _remote_cmd(remote: ClientRoot, host: ClientRoot, command_type: String, payload: Dictionary) -> Dictionary:
	var before: int = remote.remote_session.receipts.size()
	remote.action_remote_command(command_type, payload)
	_pump(host, [remote], func() -> bool: return remote.remote_session.receipts.size() > before, 5000)
	var keys := remote.remote_session.receipts.keys()
	keys.sort()
	return remote.remote_session.receipts[keys[-1]] if not keys.is_empty() else {}


# ---------- 1. 四人并发回归 ----------

func _test_four_player_concurrent_regression() -> void:
	var host := _make_client("host", "listen_host", _port)
	host.action_create_world("房主", "四人世界")
	var card: Dictionary = host.session.connection_card
	var remotes: Array = []
	# 3 名远端（房主占第 4 席）
	for i in 3:
		var remote := _make_client("remote%d" % i, "client")
		var token := Crypto.new().generate_random_bytes(32).hex_encode()
		remote.action_join_world(ConnectionCard.to_text(card), token, "玩家%d" % i)
		remotes.append(remote)
	_pump(host, remotes, func() -> bool: return host.pending_approvals().size() == 3)
	_check(host.pending_approvals().size() == 3, "three pending requests")
	for digest: String in host.pending_approvals():
		host.action_approve_join(digest)
	_pump(host, remotes, func() -> bool:
		for r: ClientRoot in remotes:
			if r.remote_state() != ClientSession.State.ACTIVE:
				return false
		return true
	)
	for i in 3:
		_check(remotes[i].remote_state() == ClientSession.State.ACTIVE, "remote %d active" % i)
	_check(host.session.server_session.online_players().size() == 3, "three remote players online")
	_check(host.session.world.members.size() == 4, "four members including host")
	# 第 5 人被拒（4 人上限含房主）
	var fifth := _make_client("fifth", "client")
	fifth.action_join_world(ConnectionCard.to_text(card), Crypto.new().generate_random_bytes(32).hex_encode(), "第五人")
	_pump(host, [fifth], func() -> bool: return fifth.remote_state() == ClientSession.State.DISCONNECTED)
	_check(fifth.remote_state() == ClientSession.State.DISCONNECTED, "fifth player rejected (4-seat cap)")
	# 四人并发操作：各自买种、整地、播种不同格
	var tiles := [1950, 1951, 1949]  # 角色周围 48px 内的三个可耕格（1952 距离 64px 超范围）
	var pid0: String = remotes[0].remote_session.player_id
	for i in 3:
		host.session.world.find_member(remotes[i].remote_session.player_id)["last_valid_position"] = {"x": 976.0, "y": 976.0}
		var buy_receipt := _remote_cmd(remotes[i], host, "economy.buy_seed", {"seed_definition_id": "seed.radish", "quantity": 2})
		_check(buy_receipt.get("accepted", false) and str(buy_receipt.get("error_code", "")).is_empty(),
			"remote %d buy seed (%s)" % [i, str(buy_receipt.get("error_code", ""))])
		var till_receipt := _remote_cmd(remotes[i], host, "farming.till", {"tile_id": tiles[i]})
		_check(till_receipt.get("accepted", false) and str(till_receipt.get("error_code", "")).is_empty(),
			"remote %d till (%s)" % [i, str(till_receipt.get("error_code", ""))])
		# 种子实际落格由服务器决定，从背包里找
		var rpid: String = remotes[i].remote_session.player_id
		var rbag: Dictionary = host.session.world.containers["backpack:" + rpid]
		var seed_slot := -1
		for k in rbag["slots"].size():
			if rbag["slots"][k] != null and rbag["slots"][k]["item_definition_id"] == "seed.radish":
				seed_slot = k
				break
		var plant_receipt := _remote_cmd(remotes[i], host, "farming.plant", {"tile_id": tiles[i], "seed_slot": seed_slot, "seed_definition_id": "seed.radish"})
		_check(plant_receipt.get("accepted", false) and str(plant_receipt.get("error_code", "")).is_empty(),
			"remote %d plant (%s)" % [i, str(plant_receipt.get("error_code", ""))])
	var planted := 0
	var states: Array = []
	for tile in tiles:
		var st: String = str(host.session.world.plots.get(str(tile), {}).get("state", "none"))
		states.append("%d=%s" % [tile, st])
		if st == "planted":
			planted += 1
	_check(planted == 3, "three concurrent plantings succeeded (got %d: %s)" % [planted, ", ".join(states)])
	# 并发抢收同一成熟作物：恰好一人成功
	host.session.world.find_member(pid0)["last_valid_position"] = {"x": 976.0, "y": 976.0}
	host.session.world.crops[host.session.world.plots["1950"]["crop_instance_id"]]["watered_day"] = host.session.world.game_day
	host.action_tick(ContractLimits.GAME_DAY_MS)
	var harvest_results: Array = []
	for r: ClientRoot in remotes:
		var receipt := _remote_cmd(r, host, "farming.harvest", {"tile_id": 1950})
		harvest_results.append(receipt)
	var successes := 0
	for receipt: Dictionary in harvest_results:
		if receipt.get("accepted", false) and str(receipt.get("error_code", "")).is_empty():
			successes += 1
	_check(successes == 1, "exactly one concurrent harvest succeeds (got %d)" % successes)
	# 不变量与对账
	_check(TransactionCoordinator.check_invariants(host.session.world) == "", "invariants hold after concurrency")
	var recon := Leaderboard.reconcile(host.session.world)
	_check(recon["ok"], "reconciliation ok after concurrency")
	# 全部客户端收敛
	var converged := _pump(host, remotes, func() -> bool:
		for r: ClientRoot in remotes:
			if r.remote_session.applied_revision() < host.session.world.business_revision:
				return false
		return true
	, 6000)
	_check(converged, "all clients converged")
	host.action_quit()
	for r: ClientRoot in remotes:
		r.remote_session.close()
	fifth.remote_session.close()


# ---------- 2. 完整推进（fixture，非真人验收） ----------

func _test_full_progression_fixture() -> void:
	var host := _make_client("prog", "solo")
	host.action_create_world("房主", "推进世界")
	var world: WorldState = host.session.world
	# 用合法账目备货（模拟正常经营积累），逐项完成三建设。
	# 来源：合成 fixture，不代表真人进度；规则路径与真实玩法一致。
	# 不直接改 treasury（会破坏不变量）；改为记录一笔等额采购。
	var spend := TransactionCoordinator.Batch.new()
	spend.add_op({"op": "treasury_delta", "delta": -world.treasury})
	spend.add_op({"op": "world_total_purchases", "delta": world.treasury})
	TransactionCoordinator.apply(world, spend, 1)
	_give(host, "produce.radish", 32)
	_give(host, "produce.wheat", 22)
	_give(host, "produce.potato", 32)
	_give(host, "produce.carrot", 22)
	_give(host, "produce.strawberry", 12)
	# 项目 1
	host.action_donate("project.field", "produce.radish", 20)
	host.action_donate("project.field", "produce.wheat", 10)
	_check(bool(host.session.projects.progress("project.field")["completed"]), "project.field completed")
	_check(int(world.stats.get("farm_capacity", 0)) == 256, "farm expanded")
	# 项目 2
	host.action_donate("project.storage", "produce.potato", 20)
	host.action_donate("project.storage", "produce.carrot", 10)
	_check(bool(host.session.projects.progress("project.storage")["completed"]), "project.storage completed")
	_check(int(world.containers["shared_storage"]["capacity"]) == 48, "storage expanded")
	# 项目 3
	for item: String in ["produce.radish", "produce.potato", "produce.wheat", "produce.carrot", "produce.strawberry"]:
		host.action_donate("project.monument", item, 12)
	_check(bool(host.session.projects.progress("project.monument")["completed"]), "project.monument completed")
	_check(int(world.stats.get("monument_completed_day", 0)) >= 1, "monument records day")
	# 完成后仍可继续经营
	_check(TransactionCoordinator.check_invariants(world) == "", "invariants hold after full progression")
	var progress := host.project_progress()
	_check(progress.size() == 3, "three projects reported")
	var all_complete := true
	for p: Dictionary in progress:
		if not p["completed"]:
			all_complete = false
	_check(all_complete, "all three projects complete")
	host.action_quit()


func _give(host: ClientRoot, item_id: String, quantity: int) -> void:
	var pid := host.session.player_id
	var backpack_id := "backpack:" + pid
	if not host.session.world.containers.has(backpack_id):
		host.session.world.containers[backpack_id] = {"capacity": 24, "slots": WorldState.empty_slots(24), "revision": 0}
	var plan := preload("res://src/domain/inventory/inventory_ops.gd").plan_insert(host.session.world.containers[backpack_id], item_id, quantity)
	for change: Dictionary in plan["changes"]:
		host.session.world.containers[backpack_id]["slots"][change["slot"]] = change["item"]
