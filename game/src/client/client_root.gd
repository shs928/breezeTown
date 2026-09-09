class_name ClientRoot
extends Node
## 客户端组合根（UI 唯一维护，M1 UI-02）。
## 职责：主菜单 → 创建/继续世界 → 农场 HUD；所有玩法动作只经 LocalSession/WorldRuntime 网关，
## 不直接修改权威状态（NFR-06）。界面用代码构建，便于 headless 集成测试驱动同一套动作方法。
##
## M1 范围：单人启动与本地继续；远端联机（listen_host 的客户端连接、client 模式）属 M2 NET-02/UI-03。

const ContractLimits := preload("res://src/contracts/contract_limits.gd")
const ContractError := preload("res://src/contracts/contract_error.gd")
const LocalSession := preload("res://src/application/session/local_session.gd")
const WorldState := preload("res://src/domain/world/world_state.gd")
const ItemCatalog := preload("res://src/domain/economy/item_catalog.gd")
const EconomyHandlers := preload("res://src/application/economy/economy_handlers.gd")
const FarmHandlers := preload("res://src/application/farming/farm_handlers.gd")
const Leaderboard := preload("res://src/domain/statistics/leaderboard.gd")
const SaveScheduler := preload("res://src/infrastructure/persistence/save_scheduler.gd")
const FarmView := preload("res://src/client/farm_view.gd")
const ClientSession := preload("res://src/application/session/client_session.gd")
const NetTransport := preload("res://src/infrastructure/network/net_transport.gd")
const ConnectionCard := preload("res://src/infrastructure/network/connection_card.gd")
const PublicExporter := preload("res://src/infrastructure/public_export/public_exporter.gd")
const MigrationPack := preload("res://src/infrastructure/persistence/migration_pack.gd")
const InputSettings := preload("res://src/client/input_settings.gd")

var mode := "solo"
var world_dir_override := ""
var host_port := 24642   # 可由启动参数/测试覆盖

var session := LocalSession.new()
var catalog: ItemCatalog
var economy: EconomyHandlers
var farm: FarmHandlers
var scheduler: SaveScheduler
var save_scheduler_active := false

var _user_data_dir := ""
var _worlds_dir := ""
var _selected_tool := "hand"      # hand / hoe / watering_can
var _selected_hotbar := 0
var _action_sequence := 0
var _last_message := ""

# 界面节点（headless 下不创建）
var remote_session: ClientSession = null   # client 模式下的远端会话
var settings := InputSettings.new()
var tutorial_step := 0                     # 新手引导进度（0=未开始）
var _ui_root: Control = null
var _menu: Control = null
var _hud: Control = null
var _view: FarmView = null
var _status_label: Label = null
var _message_label: Label = null
var _treasury_label: Label = null
var _day_label: Label = null
var _save_label: Label = null
var _panel: Control = null


func _ready() -> void:
	catalog = ItemCatalog.load_from_disk()
	_user_data_dir = OS.get_user_data_dir()
	_worlds_dir = _user_data_dir + "/worlds"
	if not world_dir_override.is_empty():
		_worlds_dir = world_dir_override
	DirAccess.make_dir_recursive_absolute(_worlds_dir)
	settings.load_or_default(_user_data_dir)
	if DisplayServer.get_name() != "headless":
		_build_ui()


# ================= 可编程动作（按钮与测试共用） =================

## 创建世界。返回 {ok, error}。
func action_create_world(owner_name: String, world_name: String) -> Dictionary:
	var result := session.create_world(_user_data_dir, _worlds_dir, owner_name, world_name)
	if not result["ok"]:
		_set_message("创建失败：" + str(result["error"]))
		return result
	_after_world_active()
	_set_message("世界已创建并保存")
	return result


## 继续世界。返回 {ok, error}。
func action_continue_world(world_id: String) -> Dictionary:
	var result := session.continue_world(_user_data_dir, _worlds_dir, world_id)
	if not result["ok"]:
		_set_message("继续失败：" + str(result["error"]))
		return result
	_after_world_active()
	_set_message("已继续第 %d 日" % int(result.get("game_day", 1)))
	return result


## 列出本地世界（主菜单“继续世界”用）。
func list_local_worlds() -> Array:
	var result: Array = []
	var da := DirAccess.open(_worlds_dir)
	if da == null:
		return result
	da.list_dir_begin()
	var name := da.get_next()
	while not name.is_empty():
		if da.current_is_dir() and name.begins_with("w"):
			var repo_world_id := name
			var has_identity := not str(_user_data_dir).is_empty() and _identity_exists(repo_world_id)
			result.append({"world_id": repo_world_id, "has_identity": has_identity})
		name = da.get_next()
	da.list_dir_end()
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["world_id"] < b["world_id"])
	return result


func _identity_exists(world_id: String) -> bool:
	return FileAccess.file_exists(_user_data_dir + "/identity/" + world_id + ".json")


## 选择工具（hand/hoe/watering_can）。
func action_select_tool(tool: String) -> void:
	if not tool in ["hand", "hoe", "watering_can"]:
		return
	_selected_tool = tool
	_set_message("工具：%s" % _tool_label(tool))


## 选择快捷栏格。
func action_select_hotbar(index: int) -> void:
	if index < 0 or index >= ContractLimits.HOTBAR_SLOTS:
		return
	_selected_hotbar = index


## 对一格执行当前动作。返回回执。
func action_click_tile(tile_id: int) -> Dictionary:
	if not session.is_active():
		return {"accepted": false, "error_code": ContractError.NOT_AUTHENTICATED}
	var receipt: Dictionary
	match _selected_tool:
		"hoe":
			receipt = _submit("farming.till", {"tile_id": tile_id})
		"watering_can":
			receipt = _submit("farming.water", {"tile_id": tile_id})
		_:
			# 空手：成熟作物收获；若选中了种子则播种
			var plot: Dictionary = session.world.plots.get(str(tile_id), {})
			var crop_id: String = str(plot.get("crop_instance_id", ""))
			if not crop_id.is_empty() and _is_mature(crop_id):
				receipt = _submit("farming.harvest", {"tile_id": tile_id})
			else:
				receipt = _submit_plant(tile_id)
	_set_message(_receipt_message(receipt))
	_refresh_ui()
	return receipt


func action_sell_slot(slot: int, quantity: int) -> Dictionary:
	var slots: Array = session.world.containers["backpack:" + session.player_id]["slots"]
	if slot < 0 or slot >= slots.size() or slots[slot] == null:
		return {"accepted": false, "error_code": ContractError.INVALID_ARGUMENT}
	var receipt := _submit("economy.sell", {"slot": slot, "item_definition_id": slots[slot]["item_definition_id"], "quantity": quantity})
	_set_message(_receipt_message(receipt))
	_refresh_ui()
	return receipt


func action_buy_seed(seed_id: String, quantity: int) -> Dictionary:
	var receipt := _submit("economy.buy_seed", {"seed_definition_id": seed_id, "quantity": quantity})
	_set_message(_receipt_message(receipt))
	_refresh_ui()
	return receipt


func action_transfer(from_ref: String, from_slot: int, to_ref: String, to_slot: int, quantity: int) -> Dictionary:
	var receipt := _submit("inventory.transfer", {
		"from_container": from_ref, "to_container": to_ref,
		"from_slot": from_slot, "to_slot": to_slot, "quantity": quantity,
	})
	_set_message(_receipt_message(receipt))
	_refresh_ui()
	return receipt


func action_rename(new_name: String) -> Dictionary:
	var receipt := _submit("profile.update", {"display_name": new_name})
	_set_message(_receipt_message(receipt))
	_refresh_ui()
	return receipt


## 推进模拟时间（测试与主循环共用）。
func action_tick(delta_ms: int) -> void:
	if not session.is_active():
		return
	var advanced := session.runtime.tick(delta_ms)
	if save_scheduler_active:
		scheduler.tick(delta_ms)
	# 日切会改变所有玩家可见状态，必须向远端推送差量（否则客户端 revision 落后）。
	if advanced and session.server_session != null:
		session.server_session.broadcast_delta()
	_refresh_ui()


## 用连接卡加入他人世界（client 模式）。返回 {ok, error}。
func action_join_world(card_text: String, token: String, display_name: String) -> Dictionary:
	var parsed := ConnectionCard.parse(card_text)
	if not parsed["ok"]:
		_set_message("连接卡无效：" + str(parsed["error"]))
		return {"ok": false, "error": parsed["error"]}
	var card: Dictionary = parsed["card"]
	var trust_path := ConnectionCard.write_trusted_certificate(card, _user_data_dir + "/trust")
	if trust_path.is_empty():
		_set_message("无法保存服务器证书")
		return {"ok": false, "error": "trust_cert_write_failed"}
	remote_session = ClientSession.new()
	remote_session.setup(NetTransport.new())
	var result := remote_session.connect_to(
		str(card["address"]), int(card["port"]), str(card["tls_hostname"]),
		trust_path, token, display_name
	)
	if not result["ok"]:
		_set_message("连接失败：" + str(result["error"]))
		return result
	_set_message("正在连接 %s…" % str(card["world_display_name"]))
	return {"ok": true, "error": ""}


## 轮询远端会话（主循环调用）。返回是否发生状态变化。
func action_poll_remote() -> bool:
	if remote_session == null:
		return false
	var before := remote_session.state
	remote_session.poll(0)
	if remote_session.state != before:
		match remote_session.state:
			ClientSession.State.WAIT_APPROVAL:
				_set_message("等待房主批准…")
			ClientSession.State.ACTIVE:
				_set_message("已加入世界")
				_after_remote_active()
			ClientSession.State.DISCONNECTED:
				_set_message("连接断开：" + str(remote_session.last_error))
			ClientSession.State.RECONNECTING:
				_set_message("断线，正在重连…")
		return true
	return false


func remote_state() -> int:
	return remote_session.state if remote_session != null else ClientSession.State.DISCONNECTED


## 远端会话激活后的界面状态（使用服务器下发的快照，不直接改本地权威）。
func _after_remote_active() -> void:
	if remote_session == null:
		return
	_action_sequence = remote_session.current_sequence()
	if _hud != null:
		_menu.visible = false
		_hud.visible = true
	_refresh_ui()


## 远端模式下发送命令（经 ClientSession，回执异步到达）。
func action_remote_command(command_type: String, payload: Dictionary) -> Dictionary:
	if remote_session == null or not remote_session.is_active():
		return {"accepted": false, "error_code": ContractError.NOT_AUTHENTICATED}
	var result := remote_session.send_command(command_type, payload)
	_set_message("已提交，等待服务器回执")
	return result


## 开启联机监听（listen_host 模式）。返回 {ok, error, card}。
func action_start_hosting(port := 24642) -> Dictionary:
	if not session.is_active():
		return {"ok": false, "error": "no_active_session", "card": {}}
	var result := session.start_hosting("0.0.0.0", port, "localhost")
	if result["ok"]:
		_set_message("已开服，端口 %d；把连接卡发给朋友" % port)
	else:
		_set_message("开服失败：" + str(result["error"]))
	_refresh_ui()
	return result


## 轮询托管服务器（主循环调用）。
func action_poll_hosting() -> int:
	if session == null:
		return 0
	return session.poll_hosting(0)


func action_approve_join(digest: String) -> Dictionary:
	var result := session.approve_join(digest)
	_set_message("已批准新成员" if result["ok"] else "批准失败：" + str(result["error"]))
	_refresh_ui()
	return result


func action_reject_join(digest: String) -> Dictionary:
	return session.reject_join(digest)


func action_revoke_member(player_id_to_revoke: String) -> Dictionary:
	return session.revoke_member(player_id_to_revoke)


func pending_approvals() -> Array:
	return session.pending_approvals() if session != null else []


## 共享仓库：本人背包与仓库之间转移。
func action_storage_transfer(from_ref: String, from_slot: int, to_ref: String, to_slot: int, quantity: int) -> Dictionary:
	return action_transfer(from_ref, from_slot, to_ref, to_slot, quantity)


## 捐赠到公共建设。
func action_donate(project_id: String, item_id: String, quantity: int) -> Dictionary:
	var receipt := _submit("projects.donate", {"project_id": project_id, "item_definition_id": item_id, "quantity": quantity})
	_set_message(_receipt_message(receipt))
	_refresh_ui()
	return receipt


## 领取救济种子。
func action_claim_relief() -> Dictionary:
	var receipt := _submit("economy.claim_relief", {})
	_set_message(_receipt_message(receipt))
	_refresh_ui()
	return receipt


## 建设进度（供 UI 与测试）。
func project_progress() -> Array:
	if session == null or session.projects == null:
		return []
	return session.projects.all_progress()


## 救济可领取状态。
func relief_available() -> Dictionary:
	if session == null or session.relief == null:
		return {"ok": false, "reason": "not_ready"}
	return session.relief.can_claim()


## 共享仓库视图（格与数量）。
func storage_view() -> Dictionary:
	if not session.is_active():
		return {}
	var storage: Dictionary = session.world.containers.get("shared_storage", {})
	return {"capacity": int(storage.get("capacity", 0)), "slots": storage.get("slots", [])}


## 本人背包视图。
func backpack_view() -> Dictionary:
	if not session.is_active():
		return {}
	var backpack: Dictionary = session.world.containers.get("backpack:" + session.player_id, {})
	return {"capacity": int(backpack.get("capacity", 0)), "slots": backpack.get("slots", [])}


## 公开授权：本人同意/撤回 + 别名（成员级）。
func action_set_publication(consent: bool, alias := "") -> Dictionary:
	if not session.is_active():
		return {"ok": false, "error": "no_active_session"}
	var member: Dictionary = session.world.find_member(session.player_id)
	member["publication_consent"] = consent
	member["public_alias"] = ContractLimits.sanitize_display_name(alias) if not alias.is_empty() else ""
	session.world.consent_revision += 1
	_set_message("已同意公开" if consent else "已撤回公开授权")
	_refresh_ui()
	return {"ok": true, "error": ""}


## 世界公开总开关（仅所有者）。
func action_set_world_publication(enabled: bool) -> Dictionary:
	if not session.is_active():
		return {"ok": false, "error": "no_active_session"}
	if session.player_id != session.world.owner_player_id:
		return {"ok": false, "error": ContractError.NOT_ALLOWED}
	session.world.publication_enabled = enabled
	session.world.consent_revision += 1
	_set_message("世界公开已开启" if enabled else "世界公开已关闭")
	return {"ok": true, "error": ""}


## 预览即将公开的榜单（不含连接卡/私有 ID/IP）。
func action_preview_public() -> Dictionary:
	if not session.is_active():
		return {"ok": false, "snapshot": {}, "error": "no_active_session"}
	return PublicExporter.build_snapshot(session.world, Time.get_datetime_string_from_system(true) + "Z")


## 导出公开榜单（HTML + JSON 成对）。
func action_export_public() -> Dictionary:
	if not session.is_active():
		return {"ok": false, "error": "no_active_session"}
	var export_root := session.repository.world_dir + "/" + PublicExporter.EXPORT_SUBDIR
	var result := PublicExporter.export(session.world, export_root, session.world.consent_revision)
	_set_message("已导出公开榜单" if result["ok"] else "导出失败：" + str(result["error"]))
	return result


## 导出私有迁移包（停服后由所有者执行）。
func action_export_migration_pack(out_dir: String) -> Dictionary:
	if not session.is_active():
		return {"ok": false, "error": "no_active_session"}
	if session.player_id != session.world.owner_player_id:
		return {"ok": false, "error": ContractError.NOT_ALLOWED}
	var result := MigrationPack.export_pack(session.repository, session.world, out_dir)
	_set_message("已导出迁移包" if result["ok"] else "迁移包导出失败：" + str(result["error"]))
	return result


## 保存故障：重试。
func action_retry_save() -> bool:
	if scheduler == null:
		return false
	var ok := scheduler.retry()
	_set_message("保存成功，世界已恢复" if ok else "保存仍失败")
	_refresh_ui()
	return ok


## 保存故障：另存恢复包。
func action_save_recovery_copy(target_dir: String) -> Dictionary:
	if scheduler == null:
		return {"ok": false, "error": "no_scheduler"}
	return scheduler.save_recovery_copy(target_dir)


## 公开授权状态（供 UI/测试）。
func publication_state() -> Dictionary:
	if not session.is_active():
		return {}
	var member: Dictionary = session.world.find_member(session.player_id)
	return {
		"world_enabled": session.world.publication_enabled,
		"consent": bool(member.get("publication_consent", false)),
		"alias": str(member.get("public_alias", "")),
		"consent_revision": session.world.consent_revision,
		"is_owner": session.player_id == session.world.owner_player_id,
	}


## 新手引导：按步骤推进。返回当前引导提示。
func action_advance_tutorial() -> Dictionary:
	var steps := tutorial_steps()
	if tutorial_step >= steps.size():
		return {"done": true, "text": "引导已完成"}
	var step: Dictionary = steps[tutorial_step]
	tutorial_step += 1
	_set_message(str(step["text"]))
	return {"done": false, "step": tutorial_step, "text": str(step["text"]), "action": str(step["action"])}


## 引导步骤定义（PRD 2.2：入场 10 分钟内完成首次收获/出售）。
func tutorial_steps() -> Array:
	return [
		{"action": "move", "text": "用 WASD 移动，走到农田附近"},
		{"action": "till", "text": "选锄头，点击空地整地"},
		{"action": "plant", "text": "在商店买种子，点击耕地播种"},
		{"action": "water", "text": "选水壶，给作物浇水（每天一次）"},
		{"action": "wait", "text": "等待日切，浇过水的作物会生长"},
		{"action": "harvest", "text": "空手点击成熟作物收获"},
		{"action": "sell", "text": "到出售点卖出产物，获得资金"},
		{"action": "board", "text": "按 L 查看三榜，了解收益与贡献的区别"},
	]


func tutorial_done() -> bool:
	return tutorial_step >= tutorial_steps().size()


## 设置：重绑定键位（含冲突检测）。
func action_rebind(action: String, key: String) -> Dictionary:
	return settings.rebind(action, key)


func action_restore_default_bindings() -> void:
	settings.restore_defaults()


## 设置：音量/缩放/全屏。
func action_apply_settings(master: float, sfx: float, scale: float, fullscreen_on: bool) -> void:
	settings.master_volume = clampf(master, 0.0, 1.0)
	settings.sfx_volume = clampf(sfx, 0.0, 1.0)
	settings.ui_scale = clampf(scale, 1.0, 1.5)
	settings.fullscreen = fullscreen_on
	settings.save()
	if DisplayServer.get_name() != "headless":
		AudioServer.set_bus_volume_db(0, linear_to_db(maxf(0.0001, settings.master_volume)))
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen_on else DisplayServer.WINDOW_MODE_WINDOWED)


func settings_state() -> Dictionary:
	return {
		"bindings": settings.bindings.duplicate(true),
		"master_volume": settings.master_volume,
		"sfx_volume": settings.sfx_volume,
		"ui_scale": settings.ui_scale,
		"fullscreen": settings.fullscreen,
		"conflicts": settings.conflicts(),
	}


## 保存并退出。返回 {ok, error}。
func action_quit() -> Dictionary:
	if not session.is_active():
		return {"ok": false, "error": "no_active_session"}
	var result := session.close("quit")
	_set_message("已保存并退出" if result["ok"] else "退出时保存失败：" + str(result["error"]))
	_refresh_ui()
	return result


## 榜单数据（三榜）。
func leaderboard() -> Dictionary:
	if not session.is_active():
		return {}
	return Leaderboard.build(session.world)


func hud_state() -> Dictionary:
	if remote_session != null and remote_session.is_active():
		var snap: Dictionary = remote_session.snapshot
		return {
			"active": true,
			"remote": true,
			"game_day": int(snap.get("game_day", 1)),
			"clock": "",
			"treasury": int(snap.get("treasury", 0)),
			"player_id": remote_session.player_id,
			"display_name": _remote_display_name(),
			"save_fault": false,
			"message": _last_message,
		}
	if not session.is_active():
		return {"active": false}
	var w: WorldState = session.world
	return {
		"active": true,
		"game_day": w.game_day,
		"clock": session.runtime.clock.clock_text(),
		"treasury": w.treasury,
		"tool": _selected_tool,
		"hotbar": _selected_hotbar,
		"player_id": session.player_id,
		"display_name": w.find_member(session.player_id)["display_name"],
		"save_fault": session.runtime.is_save_fault(),
		"message": _last_message,
	}


# ================= 内部 =================

func _remote_display_name() -> String:
	if remote_session == null:
		return ""
	for row: Dictionary in remote_session.snapshot.get("members", []):
		if row.get("player_id", "") == remote_session.player_id:
			return str(row.get("display_name", ""))
	return ""


func _after_world_active() -> void:
	# 处理器由 LocalSession 统一装配（本地与远端共用）；这里只取引用。
	economy = session.economy
	farm = session.farm
	scheduler = SaveScheduler.new()
	scheduler.setup(session.repository, session.runtime)
	save_scheduler_active = true
	_action_sequence = 0
	_selected_tool = "hand"
	_selected_hotbar = 0
	if _view != null:
		_view.setup(session.world, session.player_id)
	if _hud != null:
		_menu.visible = false
		_hud.visible = true
	if mode == "listen_host":
		action_start_hosting(host_port)
	_refresh_ui()


func _submit(command_type: String, payload: Dictionary) -> Dictionary:
	_action_sequence += 1
	var receipt := session.runtime.submit({
		"protocol_version": 1,
		"world_id": session.world.world_id,
		"authority_epoch": session.world.authority_epoch,
		"client_sequence": _action_sequence,
		"command_type": command_type,
		"payload": payload,
		"_actor_player_id": session.player_id,
	})
	# 房主本地操作同样要推送给远端客户端（同一权威状态，不能只有远端命令才广播）。
	if receipt.get("accepted", false) and str(receipt.get("error_code", "")).is_empty() and session.server_session != null:
		session.server_session.broadcast_delta()
	return receipt


func _submit_plant(tile_id: int) -> Dictionary:
	var slots: Array = session.world.containers["backpack:" + session.player_id]["slots"]
	# 从当前快捷栏格开始找第一个种子
	for offset in slots.size():
		var index := (offset) % slots.size()
		var slot: Variant = slots[index]
		if slot != null and catalog.is_seed(slot["item_definition_id"]):
			_selected_hotbar = index % ContractLimits.HOTBAR_SLOTS
			return _submit("farming.plant", {"tile_id": tile_id, "seed_slot": index, "seed_definition_id": slot["item_definition_id"]})
	return {"accepted": false, "error_code": ContractError.INSUFFICIENT_ITEMS}


func _is_mature(crop_instance_id: String) -> bool:
	var crop: Dictionary = session.world.crops.get(crop_instance_id, {})
	if crop.is_empty():
		return false
	return farm.stage_of(crop) == "mature"


func _tool_label(tool: String) -> String:
	match tool:
		"hoe": return "锄头"
		"watering_can": return "水壶"
		_: return "空手"


func _receipt_message(receipt: Dictionary) -> String:
	if receipt.get("accepted", false) and str(receipt.get("error_code", "")).is_empty():
		return "操作成功"
	var code := str(receipt.get("error_code", ""))
	match code:
		ContractError.INVENTORY_FULL: return "背包已满"
		ContractError.INSUFFICIENT_FUNDS: return "资金不足"
		ContractError.INSUFFICIENT_ITEMS: return "物品不足"
		ContractError.TARGET_CHANGED: return "目标已变化"
		ContractError.STALE_STATE: return "状态已更新，请重试"
		ContractError.OUT_OF_RANGE: return "距离太远"
		ContractError.SAVE_UNAVAILABLE: return "保存故障，世界已暂停"
		ContractError.NOT_ALLOWED: return "此处无法进行该操作"
		ContractError.INVALID_ARGUMENT: return "参数无效"
		_: return "操作失败（%s）" % code


func _set_message(text: String) -> void:
	_last_message = text
	if _message_label != null:
		_message_label.text = text


func _refresh_ui() -> void:
	if _hud == null or not session.is_active():
		return
	var state := hud_state()
	_treasury_label.text = "资金 %d" % int(state["treasury"])
	_day_label.text = "第 %d 日 %s" % [int(state["game_day"]), str(state["clock"])]
	if bool(state["save_fault"]):
		_save_label.text = "⚠ 保存故障：已暂停"
	else:
		_save_label.text = "已保存 %d 秒前" % scheduler.seconds_since_last_save()
	if _view != null:
		_view.queue_redraw()


# ================= 界面构建（仅窗口模式） =================

func _build_ui() -> void:
	_ui_root = Control.new()
	_ui_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_ui_root)

	_menu = _build_menu()
	_ui_root.add_child(_menu)

	_hud = _build_hud()
	_hud.visible = false
	_ui_root.add_child(_hud)


func _build_menu() -> Control:
	var panel := _make_panel()
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.custom_minimum_size = Vector2(420, 0)
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)

	var title := Label.new()
	title.text = "微风小镇"
	title.add_theme_font_size_override("font_size", 32)
	box.add_child(title)

	var name_input := LineEdit.new()
	name_input.placeholder_text = "昵称"
	name_input.text = "房主"
	box.add_child(name_input)

	var world_input := LineEdit.new()
	world_input.placeholder_text = "世界名"
	world_input.text = "我的小镇"
	box.add_child(world_input)

	var create_btn := Button.new()
	create_btn.text = "创建世界（单人）"
	create_btn.pressed.connect(func() -> void:
		action_create_world(name_input.text, world_input.text)
	)
	box.add_child(create_btn)

	var continue_box := VBoxContainer.new()
	box.add_child(continue_box)
	var continue_title := Label.new()
	continue_title.text = "继续世界："
	continue_box.add_child(continue_title)
	for entry: Dictionary in list_local_worlds():
		if not entry["has_identity"]:
			continue
		var btn := Button.new()
		btn.text = str(entry["world_id"]).substr(0, 10) + "…"
		btn.pressed.connect(func() -> void: action_continue_world(entry["world_id"]))
		continue_box.add_child(btn)

	var card_input := LineEdit.new()
	card_input.placeholder_text = "粘贴连接卡（JSON）"
	box.add_child(card_input)
	var join_btn := Button.new()
	join_btn.text = "加入世界"
	join_btn.pressed.connect(func() -> void:
		var token := Crypto.new().generate_random_bytes(32).hex_encode()
		action_join_world(card_input.text, token, name_input.text)
	)
	box.add_child(join_btn)

	var quit_btn := Button.new()
	quit_btn.text = "退出"
	quit_btn.pressed.connect(func() -> void: get_tree().quit(0))
	box.add_child(quit_btn)
	return panel


func _build_hud() -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)

	_view = FarmView.new()
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.client = self
	root.add_child(_view)

	var top := HBoxContainer.new()
	top.position = Vector2(12, 8)
	root.add_child(top)
	_treasury_label = Label.new()
	top.add_child(_treasury_label)
	_day_label = Label.new()
	top.add_child(_day_label)
	_save_label = Label.new()
	top.add_child(_save_label)

	var tools := HBoxContainer.new()
	tools.position = Vector2(12, 560)
	root.add_child(tools)
	for tool: Array in [["hand", "空手"], ["hoe", "锄头"], ["watering_can", "水壶"]]:
		var btn := Button.new()
		btn.text = tool[1]
		btn.pressed.connect(func() -> void: action_select_tool(tool[0]))
		tools.add_child(btn)

	var hotbar := HBoxContainer.new()
	hotbar.position = Vector2(240, 560)
	root.add_child(hotbar)
	for i in ContractLimits.HOTBAR_SLOTS:
		var btn := Button.new()
		btn.text = str(i + 1)
		btn.custom_minimum_size = Vector2(48, 48)
		btn.pressed.connect(func() -> void: action_select_hotbar(i))
		hotbar.add_child(btn)

	var actions := HBoxContainer.new()
	actions.position = Vector2(600, 560)
	root.add_child(actions)
	var shop_btn := Button.new()
	shop_btn.text = "种子商店"
	shop_btn.pressed.connect(_show_shop)
	actions.add_child(shop_btn)
	var board_btn := Button.new()
	board_btn.text = "榜单"
	board_btn.pressed.connect(_show_leaderboard)
	actions.add_child(board_btn)
	var storage_btn := Button.new()
	storage_btn.text = "仓库"
	storage_btn.pressed.connect(_show_storage)
	actions.add_child(storage_btn)
	var project_btn := Button.new()
	project_btn.text = "建设板"
	project_btn.pressed.connect(_show_projects)
	actions.add_child(project_btn)

	_message_label = Label.new()
	_message_label.position = Vector2(240, 520)
	root.add_child(_message_label)

	_status_label = Label.new()
	_status_label.position = Vector2(240, 640)
	root.add_child(_status_label)
	return root


func _make_panel() -> Control:
	var panel := ColorRect.new()
	panel.color = Color(0.96, 0.94, 0.89, 0.97)
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	return panel


func _show_shop() -> void:
	if _panel != null:
		_panel.queue_free()
	_panel = _make_panel()
	var box := VBoxContainer.new()
	box.position = Vector2(400, 120)
	_panel.add_child(box)
	var title := Label.new()
	title.text = "种子商店（资金 %d）" % session.world.treasury
	box.add_child(title)
	for crop: Dictionary in catalog.crops.values():
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = "%s 种子 %d 金币" % [crop["name"], int(crop["seed_price"])]
		row.add_child(label)
		var buy1 := Button.new()
		buy1.text = "买 1"
		buy1.pressed.connect(func() -> void: action_buy_seed(crop["seed_item_id"], 1))
		row.add_child(buy1)
		var buy10 := Button.new()
		buy10.text = "买 10"
		buy10.pressed.connect(func() -> void: action_buy_seed(crop["seed_item_id"], 10))
		row.add_child(buy10)
		box.add_child(row)
	var close := Button.new()
	close.text = "关闭"
	close.pressed.connect(func() -> void: _panel.queue_free(); _panel = null)
	box.add_child(close)
	_ui_root.add_child(_panel)


func _show_storage() -> void:
	if _panel != null:
		_panel.queue_free()
	_panel = _make_panel()
	var box := VBoxContainer.new()
	box.position = Vector2(360, 100)
	_panel.add_child(box)
	var storage := storage_view()
	var backpack := backpack_view()
	var title := Label.new()
	title.text = "共享仓库（%d 格）｜我的背包（%d 格）" % [int(storage["capacity"]), int(backpack["capacity"])]
	box.add_child(title)
	for i in int(storage["capacity"]):
		var slot: Variant = storage["slots"][i] if i < storage["slots"].size() else null
		var line := Label.new()
		line.text = "仓 %d: %s" % [i, "空" if slot == null else "%s x%d" % [slot["item_definition_id"], int(slot["quantity"])]]
		box.add_child(line)
	# 快速转移：背包第一格 → 仓库第一空位
	var move_btn := Button.new()
	move_btn.text = "存入 1 个（背包首格 → 仓库）"
	move_btn.pressed.connect(func() -> void:
		for i in backpack["slots"].size():
			if backpack["slots"][i] != null:
				var free_slot := -1
				for j in int(storage["capacity"]):
					if storage["slots"][j] == null:
						free_slot = j
						break
				if free_slot >= 0:
					action_storage_transfer("backpack:" + session.player_id, i, "shared_storage", free_slot, 1)
				return
	)
	box.add_child(move_btn)
	var close := Button.new()
	close.text = "关闭"
	close.pressed.connect(func() -> void: _panel.queue_free(); _panel = null)
	box.add_child(close)
	_ui_root.add_child(_panel)


func _show_projects() -> void:
	if _panel != null:
		_panel.queue_free()
	_panel = _make_panel()
	var box := VBoxContainer.new()
	box.position = Vector2(360, 80)
	_panel.add_child(box)
	var title := Label.new()
	title.text = "公共建设（按顺序解锁）"
	box.add_child(title)
	for progress: Dictionary in project_progress():
		var line := Label.new()
		var status := "已完成" if progress["completed"] else ("可捐赠" if progress["unlocked"] else "未解锁")
		line.text = "%s [%s]" % [progress["name"], status]
		box.add_child(line)
		for req: Dictionary in progress["requirements"]:
			var req_line := Label.new()
			req_line.text = "    %s: %d/%d（还需 %d）" % [req["item_id"], int(req["accepted"]), int(req["required"]), int(req["remaining"])]
			box.add_child(req_line)
	# 救济
	var relief := relief_available()
	var relief_label := Label.new()
	relief_label.text = "救济种子：%s" % ("可领取" if relief["ok"] else "不可领取（%s）" % str(relief["reason"]))
	box.add_child(relief_label)
	if relief["ok"]:
		var relief_btn := Button.new()
		relief_btn.text = "领取 5 粒萝卜种子"
		relief_btn.pressed.connect(func() -> void: action_claim_relief())
		box.add_child(relief_btn)
	var close := Button.new()
	close.text = "关闭"
	close.pressed.connect(func() -> void: _panel.queue_free(); _panel = null)
	box.add_child(close)
	_ui_root.add_child(_panel)


func _show_leaderboard() -> void:
	if _panel != null:
		_panel.queue_free()
	_panel = _make_panel()
	var box := VBoxContainer.new()
	box.position = Vector2(360, 80)
	_panel.add_child(box)
	var title := Label.new()
	title.text = "累计收益榜（出售收入，非净利润）｜游戏第 %d 日" % session.world.game_day
	box.add_child(title)
	var boards := leaderboard()
	for row: Dictionary in boards["total_gross_sales"]:
		var line := Label.new()
		line.text = "%d. %s  %d%s" % [int(row["rank"]), row["display_name"], int(row["value"]), "（离线）" if not row["online"] else ""]
		box.add_child(line)
	var contribution_title := Label.new()
	contribution_title.text = "累计贡献榜（按有效操作计分，不代表劳动价值）"
	box.add_child(contribution_title)
	for row: Dictionary in boards["contribution_total"]:
		var line := Label.new()
		line.text = "%d. %s  %d" % [int(row["rank"]), row["display_name"], int(row["value"])]
		box.add_child(line)
	var close := Button.new()
	close.text = "关闭"
	close.pressed.connect(func() -> void: _panel.queue_free(); _panel = null)
	box.add_child(close)
	_ui_root.add_child(_panel)
