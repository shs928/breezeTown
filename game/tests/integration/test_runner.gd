extends SceneTree
## INT-01 集成验收（headless）：CASE-01/02/07/09/15/21/27 的完整单机流程。
## 驱动的是 UI-02 的真实动作方法（不是 mock），验证 UI → 网关 → 领域 → 持久化整条链路。
## 运行：godot --headless --path game --script res://tests/integration/test_runner.gd

const ContractLimits := preload("res://src/contracts/contract_limits.gd")
const ContractError := preload("res://src/contracts/contract_error.gd")
const ClientRoot := preload("res://src/client/client_root.gd")
const LocalSession := preload("res://src/application/session/local_session.gd")
const WorldState := preload("res://src/domain/world/world_state.gd")
const TransactionCoordinator := preload("res://src/application/core/transaction_coordinator.gd")
const ItemCatalog := preload("res://src/domain/economy/item_catalog.gd")

var _checks := 0
var _failures: PackedStringArray = []
var _root := ""


func _initialize() -> void:
	_root = ProjectSettings.globalize_path("res://../work/game-data/int01/%d" % Time.get_unix_time_from_system())
	DirAccess.make_dir_recursive_absolute(_root)

	_test_full_single_player_flow()
	_test_save_and_continue_flow()
	_test_leaderboard_and_sell()
	_test_headless_same_core()

	if _failures.is_empty():
		print("INT01_OK checks=%d run_dir=%s" % [_checks, _root])
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: " + f)
		printerr("INT01_FAILED checks=%d failures=%d" % [_checks, _failures.size()])
		quit(1)


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(label)


## 创建一个指向隔离目录的客户端（不创建 UI，headless 可用）。
func _make_client(name: String) -> ClientRoot:
	var client := ClientRoot.new()
	client.mode = "solo"
	client.world_dir_override = _root + "/" + name + "/worlds"
	# _ready 不会被自动调用（未入树）；手动完成其初始化
	client.catalog = ItemCatalog.load_from_disk()
	client._user_data_dir = _root + "/" + name + "/user_data"
	client._worlds_dir = client.world_dir_override
	DirAccess.make_dir_recursive_absolute(client._user_data_dir)
	DirAccess.make_dir_recursive_absolute(client._worlds_dir)
	return client


func _move_to_farm(client: ClientRoot) -> void:
	# 把角色放到耕地旁，便于交互
	var member: Dictionary = client.session.world.find_member(client.session.player_id)
	member["last_valid_position"] = {"x": 976.0, "y": 976.0}


# ---------- 1. 完整单机流程：创建→整地→播种→浇水→日切→收获→出售 ----------

func _test_full_single_player_flow() -> void:
	var client := _make_client("flow")
	var created := client.action_create_world("房主", "完整流程世界")
	_check(created["ok"], "CASE-01 create world")
	_check(client.session.is_active(), "session active")
	_move_to_farm(client)
	var tile := 1950
	# 整地
	client.action_select_tool("hoe")
	var till := client.action_click_tile(tile)
	_check(till["accepted"] and till["error_code"] == "", "CASE-09 till")
	# 买种子
	var buy := client.action_buy_seed("seed.radish", 3)
	_check(buy["accepted"] and buy["error_code"] == "", "CASE-15 buy seed")
	_check(client.session.world.treasury == 300 - 45, "treasury debited")
	# 播种（空手 + 有种子）
	client.action_select_tool("hand")
	var plant := client.action_click_tile(tile)
	_check(plant["accepted"] and plant["error_code"] == "", "CASE-09 plant")
	var crop_id: String = client.session.world.plots[str(tile)]["crop_instance_id"]
	_check(not crop_id.is_empty(), "crop created")
	# 浇水
	client.action_select_tool("watering_can")
	var water := client.action_click_tile(tile)
	_check(water["accepted"] and water["error_code"] == "", "CASE-09 water")
	# 日切 → 生长
	client.action_tick(ContractLimits.GAME_DAY_MS)
	_check(client.session.world.game_day == 2, "day advanced")
	_check(int(client.session.world.crops[crop_id]["growth_days"]) == 1, "crop grew one day")
	# 收获（空手点击成熟作物）
	client.action_select_tool("hand")
	var harvest := client.action_click_tile(tile)
	_check(harvest["accepted"] and harvest["error_code"] == "", "CASE-09 harvest")
	# 找到产物并出售
	var backpack: Dictionary = client.session.world.containers["backpack:" + client.session.player_id]
	var produce_slot := -1
	for i in backpack["slots"].size():
		if backpack["slots"][i] != null and backpack["slots"][i]["item_definition_id"] == "produce.radish":
			produce_slot = i
			break
	_check(produce_slot >= 0, "produce in backpack")
	var sell := client.action_sell_slot(produce_slot, 1)
	_check(sell["accepted"] and sell["error_code"] == "", "CASE-15 sell")
	_check(client.session.world.treasury == 300 - 45 + 24, "treasury after sale")
	var stats: Dictionary = client.session.world.stats["members"][client.session.player_id]
	_check(int(stats["total_gross_sales"]) == 24, "member gross sales 24")
	_check(int(stats["contribution"]["planting"]) == 2, "planting contribution +2")
	_check(int(stats["contribution"]["watering"]) == 1, "watering contribution +1")
	_check(int(stats["contribution"]["harvesting"]) == 3, "harvesting contribution +3")
	_check(TransactionCoordinator.check_invariants(client.session.world) == "", "invariants hold")
	client.action_quit()


# ---------- 2. 保存与继续（CASE-02/27） ----------

func _test_save_and_continue_flow() -> void:
	var client := _make_client("continue")
	var created := client.action_create_world("房主", "续玩世界")
	var world_id: String = created["world_id"]
	_move_to_farm(client)
	client.action_buy_seed("seed.wheat", 5)
	client.action_tick(ContractLimits.GAME_DAY_MS * 3)
	var day_before: int = client.session.world.game_day
	var treasury_before: int = client.session.world.treasury
	var quit_result := client.action_quit()
	_check(quit_result["ok"], "CASE-27 save on quit")
	# 继续世界
	var resumed := _make_client("continue")
	var result := resumed.action_continue_world(world_id)
	_check(result["ok"], "CASE-02 continue world")
	_check(resumed.session.world.game_day == day_before, "game day preserved")
	_check(resumed.session.world.treasury == treasury_before, "treasury preserved")
	_check(not resumed.session.world.authority_epoch.is_empty(), "epoch regenerated")
	_check(resumed.session.world.members.size() == 1, "member preserved")
	resumed.action_quit()


# ---------- 3. 榜单（CASE-21） ----------

func _test_leaderboard_and_sell() -> void:
	var client := _make_client("board")
	client.action_create_world("房主", "榜单世界")
	# 加一个成员（模拟联机伙伴的历史行）
	var second: Dictionary = client.session.world.add_member("队友")
	client.session.world.containers[second["inventory_id"]] = {"capacity": 24, "slots": WorldState.empty_slots(24), "revision": 0}
	_move_to_farm(client)
	# 房主买种并卖产物
	client.action_buy_seed("seed.radish", 1)
	var backpack: Dictionary = client.session.world.containers["backpack:" + client.session.player_id]
	backpack["slots"][20] = {"item_definition_id": "produce.radish", "quantity": 5}
	client.action_sell_slot(20, 5)
	var boards := client.leaderboard()
	_check(boards.has("total_gross_sales") and boards.has("today_gross_sales") and boards.has("contribution_total"), "three boards present")
	var rows: Array = boards["total_gross_sales"]
	_check(rows.size() == 2, "both members listed")
	_check(rows[0]["value"] == 120, "seller leads with 120")
	_check(rows[0]["rank"] == 1 and rows[1]["rank"] == 2, "ranks assigned")
	var hud := client.hud_state()
	_check(hud["treasury"] == 300 - 15 + 120, "hud treasury correct")
	_check(hud["game_day"] == 1, "hud game day")
	_check(not str(hud["clock"]).is_empty(), "hud clock shown")
	client.action_quit()


# ---------- 4. headless 同核心（CASE-36 的启动子场景） ----------

func _test_headless_same_core() -> void:
	# 领域核心不依赖任何 UI 节点即可运行完整业务（上面三个用例已证明）。
	# 这里再验证：在没有 DisplayServer 的情况下创建客户端对象并完成一次命令。
	_check(DisplayServer.get_name() == "headless", "running headless")
	var client := _make_client("headless")
	var created := client.action_create_world("无界面房主", "headless 世界")
	_check(created["ok"], "headless world creation")
	var receipt := client.action_rename("新名字")
	_check(receipt["accepted"] and receipt["error_code"] == "", "headless command accepted")
	_check(client.session.world.find_member(client.session.player_id)["display_name"] == "新名字", "headless state changed")
	_check(client.hud_state()["active"], "headless hud state available without UI nodes")
	client.action_quit()
