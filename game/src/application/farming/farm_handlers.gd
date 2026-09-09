class_name FarmHandlers
## FARM 命令处理器（FARM 唯一维护）：整地、播种、浇水、收获，以及日切时的生长结算。
## 处理器只构造提交计划；距离、格状态、库存、阶段一律在服务端校验。
##
## 规则来源：PRD 6.1/6.2、契约 5.2/6.3。

const ContractLimits := preload("res://src/contracts/contract_limits.gd")
const ContractError := preload("res://src/contracts/contract_error.gd")
const InventoryOps := preload("res://src/domain/inventory/inventory_ops.gd")
const ItemCatalog := preload("res://src/domain/economy/item_catalog.gd")
const WorldState := preload("res://src/domain/world/world_state.gd")
const WorldRuntime := preload("res://src/application/world/world_runtime.gd")
const TransactionCoordinator := preload("res://src/application/core/transaction_coordinator.gd")

const PLOT_UNTILLED := "untilled"
const PLOT_EMPTY := "empty"
const PLOT_PLANTED := "planted"

var catalog: ItemCatalog
var _runtime: WorldRuntime
var _rng := RandomNumberGenerator.new()


func setup(runtime: WorldRuntime, item_catalog: ItemCatalog, seed_value := 0) -> void:
	_runtime = runtime
	catalog = item_catalog
	if seed_value == 0:
		_rng.randomize()
	else:
		_rng.seed = seed_value
	_runtime.register_handler("farming.till", _handle_till)
	_runtime.register_handler("farming.plant", _handle_plant)
	_runtime.register_handler("farming.water", _handle_water)
	_runtime.register_handler("farming.harvest", _handle_harvest)


# ---------- 整地 ----------

func _handle_till(payload: Dictionary, player_id: String, batch: TransactionCoordinator.Batch) -> String:
	var tile_id := int(payload["tile_id"])
	var err := _validate_farm_target(tile_id, player_id)
	if not err.is_empty():
		return err
	if not _is_farmable(tile_id):
		return ContractError.NOT_ALLOWED
	var plot: Dictionary = _runtime.world.plots.get(str(tile_id), {})
	var state: String = plot.get("state", PLOT_UNTILLED)
	if state == PLOT_PLANTED:
		return ContractError.TARGET_CHANGED
	if state == PLOT_EMPTY:
		return ContractError.STALE_STATE  # 已是耕地
	batch.add_op({"op": "set_plot", "tile_id": tile_id, "plot": {"state": PLOT_EMPTY, "crop_instance_id": ""}})
	batch.add_event("PlotTilled", {"tile_id": tile_id}, player_id)
	return ""


# ---------- 播种 ----------

func _handle_plant(payload: Dictionary, player_id: String, batch: TransactionCoordinator.Batch) -> String:
	var tile_id := int(payload["tile_id"])
	var seed_slot := int(payload["seed_slot"])
	var seed_id: String = payload["seed_definition_id"]
	var err := _validate_farm_target(tile_id, player_id)
	if not err.is_empty():
		return err
	if not catalog.is_seed(seed_id):
		return ContractError.INVALID_ARGUMENT
	var plot: Dictionary = _runtime.world.plots.get(str(tile_id), {})
	if plot.get("state", PLOT_UNTILLED) != PLOT_EMPTY:
		return ContractError.TARGET_CHANGED
	if not str(plot.get("crop_instance_id", "")).is_empty():
		return ContractError.TARGET_CHANGED
	var member: Dictionary = _runtime.world.find_member(player_id)
	var backpack_id: String = member["inventory_id"]
	if not _runtime.world.containers.has(backpack_id):
		return ContractError.INVENTORY_FULL
	var backpack: Dictionary = _runtime.world.containers[backpack_id]
	if seed_slot < 0 or seed_slot >= backpack["slots"].size() or backpack["slots"][seed_slot] == null:
		return ContractError.INVALID_ARGUMENT
	var slot_item: Dictionary = backpack["slots"][seed_slot]
	if slot_item["item_definition_id"] != seed_id:
		return ContractError.TARGET_CHANGED
	if int(slot_item["quantity"]) < 1:
		return ContractError.INSUFFICIENT_ITEMS
	var left := int(slot_item["quantity"]) - 1
	var crop_instance_id := "ci" + Crypto.new().generate_random_bytes(16).hex_encode()
	batch.add_op({"op": "container_set", "container_id": backpack_id, "slot": seed_slot,
		"item": null if left == 0 else {"item_definition_id": seed_id, "quantity": left}})
	batch.add_op({"op": "set_plot", "tile_id": tile_id, "plot": {"state": PLOT_PLANTED, "crop_instance_id": crop_instance_id}})
	batch.add_op({"op": "set_crop", "crop_instance_id": crop_instance_id, "crop": {
		"crop_instance_id": crop_instance_id,
		"crop_definition_id": catalog.crop_id_of(seed_id),
		"tile_id": tile_id,
		"growth_days": 0,
		"planted_day": _runtime.world.game_day,
		"watered_day": 0,
	}})
	batch.add_contribution(player_id, "planting", ContractLimits.POINTS_PLANT)
	batch.add_event("CropPlanted", {"tile_id": tile_id, "crop_instance_id": crop_instance_id, "crop_definition_id": catalog.crop_id_of(seed_id)}, player_id)
	return ""


# ---------- 浇水 ----------

func _handle_water(payload: Dictionary, player_id: String, batch: TransactionCoordinator.Batch) -> String:
	var tile_id := int(payload["tile_id"])
	var err := _validate_farm_target(tile_id, player_id)
	if not err.is_empty():
		return err
	var plot: Dictionary = _runtime.world.plots.get(str(tile_id), {})
	if plot.get("state", "") != PLOT_PLANTED:
		return ContractError.TARGET_CHANGED
	var crop_id: String = str(plot.get("crop_instance_id", ""))
	var crop: Dictionary = _runtime.world.crops.get(crop_id, {})
	if crop.is_empty():
		return ContractError.TARGET_CHANGED
	var definition := catalog.crop_definition(crop["crop_definition_id"])
	if int(crop["growth_days"]) >= int(definition["growth_days"]):
		return ContractError.TARGET_CHANGED  # 成熟后浇水无意义（PRD 6.2）
	if int(crop["watered_day"]) == _runtime.world.game_day:
		return ContractError.STALE_STATE  # 同一作物同一游戏日最多计分一次
	var updated: Dictionary = crop.duplicate(true)
	updated["watered_day"] = _runtime.world.game_day
	batch.add_op({"op": "set_crop", "crop_instance_id": crop_id, "crop": updated})
	batch.add_contribution(player_id, "watering", ContractLimits.POINTS_WATER)
	batch.add_event("CropWatered", {"tile_id": tile_id, "crop_instance_id": crop_id, "game_day": _runtime.world.game_day}, player_id)
	return ""


# ---------- 收获 ----------

func _handle_harvest(payload: Dictionary, player_id: String, batch: TransactionCoordinator.Batch) -> String:
	var tile_id := int(payload["tile_id"])
	var err := _validate_farm_target(tile_id, player_id)
	if not err.is_empty():
		return err
	var plot: Dictionary = _runtime.world.plots.get(str(tile_id), {})
	if plot.get("state", "") != PLOT_PLANTED:
		return ContractError.TARGET_CHANGED
	var crop_id: String = str(plot.get("crop_instance_id", ""))
	var crop: Dictionary = _runtime.world.crops.get(crop_id, {})
	if crop.is_empty():
		return ContractError.TARGET_CHANGED
	var definition := catalog.crop_definition(crop["crop_definition_id"])
	if int(crop["growth_days"]) < int(definition["growth_days"]):
		return ContractError.TARGET_CHANGED  # 未成熟不可收
	var member: Dictionary = _runtime.world.find_member(player_id)
	var backpack_id: String = member["inventory_id"]
	if not _runtime.world.containers.has(backpack_id):
		return ContractError.INVENTORY_FULL
	var produce_id: String = definition["produce_item_id"]
	var plan := InventoryOps.plan_insert(_runtime.world.containers[backpack_id], produce_id, 1)
	if not plan["ok"]:
		return ContractError.INVENTORY_FULL  # 收获前检查容量，失败不清地
	for change: Dictionary in plan["changes"]:
		batch.add_op({"op": "container_set", "container_id": backpack_id, "slot": change["slot"], "item": change["item"]})
	batch.add_op({"op": "remove_crop", "crop_instance_id": crop_id})
	# 土地保持耕作状态（PRD 6.2）
	batch.add_op({"op": "set_plot", "tile_id": tile_id, "plot": {"state": PLOT_EMPTY, "crop_instance_id": ""}})
	batch.add_contribution(player_id, "harvesting", ContractLimits.POINTS_HARVEST)
	batch.add_event("CropHarvested", {"tile_id": tile_id, "crop_instance_id": crop_id, "produce_definition_id": produce_id, "quantity": 1}, player_id)
	return ""


# ---------- 日切生长结算（由 WorldRuntime 在日切屏障内调用） ----------

## 对全部未成熟作物结算生长：当 watered_day == 刚结束的游戏日时 +1 生长日。
## 必须在日切时、清浇水状态之前调用。
func settle_growth(ended_day: int, batch: TransactionCoordinator.Batch) -> void:
	for crop_id: String in _runtime.world.crops:
		var crop: Dictionary = _runtime.world.crops[crop_id]
		var definition := catalog.crop_definition(crop["crop_definition_id"])
		if int(crop["growth_days"]) >= int(definition["growth_days"]):
			continue
		if int(crop["watered_day"]) != ended_day:
			continue  # 未浇水停长，不死亡
		var updated: Dictionary = crop.duplicate(true)
		updated["growth_days"] = int(crop["growth_days"]) + 1
		batch.add_op({"op": "set_crop", "crop_instance_id": crop_id, "crop": updated})


## 当前视觉阶段（PRD 6.1 阶段映射）。
func stage_of(crop: Dictionary) -> String:
	var definition := catalog.crop_definition(crop["crop_definition_id"])
	var stages: Array = definition.get("stages", [])
	var stage := "sown"
	for entry: Dictionary in stages:
		if int(crop["growth_days"]) >= int(entry["min_growth_days"]):
			stage = entry["stage"]
	return stage


# ---------- 校验辅助 ----------

## 距离 ≤1.5 格（48px）且交互线段不穿阻挡格。
func _validate_farm_target(tile_id: int, player_id: String) -> String:
	if tile_id < 0 or tile_id >= ContractLimits.MAP_W * ContractLimits.MAP_H:
		return ContractError.OUT_OF_RANGE
	var member: Dictionary = _runtime.world.find_member(player_id)
	if member.is_empty():
		return ContractError.NOT_AUTHENTICATED
	var pos: Dictionary = member["last_valid_position"]
	var tile_x := tile_id % ContractLimits.MAP_W
	var tile_y := tile_id / ContractLimits.MAP_W
	var center_x := (tile_x + 0.5) * ContractLimits.TILE_SIZE_PX
	var center_y := (tile_y + 0.5) * ContractLimits.TILE_SIZE_PX
	var dx := center_x - float(pos["x"])
	var dy := center_y - float(pos["y"])
	var distance := sqrt(dx * dx + dy * dy)
	if distance > float(ContractLimits.INTERACT_RADIUS_PX):
		return ContractError.OUT_OF_RANGE
	if _segment_blocked(float(pos["x"]), float(pos["y"]), center_x, center_y):
		return ContractError.NOT_ALLOWED
	return ""


## 交互线段是否穿过阻挡格（按 8px 步长采样）。
func _segment_blocked(x0: float, y0: float, x1: float, y1: float) -> bool:
	var tiles: Array = _runtime.map_data.get("tiles", [])
	if tiles.is_empty():
		return false
	var distance := sqrt(pow(x1 - x0, 2) + pow(y1 - y0, 2))
	var steps := int(max(1.0, distance / 8.0))
	for i in steps + 1:
		var t := float(i) / float(steps)
		var x := x0 + (x1 - x0) * t
		var y := y0 + (y1 - y0) * t
		var tx := int(floor(x / float(ContractLimits.TILE_SIZE_PX)))
		var ty := int(floor(y / float(ContractLimits.TILE_SIZE_PX)))
		if ty < 0 or ty >= tiles.size():
			return true
		var row: String = tiles[ty]
		if tx < 0 or tx >= row.length():
			return true
		if row[tx] == "B":
			return true
	return false


func _is_farmable(tile_id: int) -> bool:
	var tiles: Array = _runtime.map_data.get("tiles", [])
	if tiles.is_empty():
		return true
	var tx := tile_id % ContractLimits.MAP_W
	var ty := tile_id / ContractLimits.MAP_W
	if ty < 0 or ty >= tiles.size():
		return false
	var row: String = tiles[ty]
	if tx < 0 or tx >= row.length():
		return false
	return row[tx] == "F"
