class_name EventLog
## 事实事件日志与统计 checkpoint（DATA 唯一维护，M4 DATA-02；契约 8.3）。
## 规则：
## - 保留最近 10,000 条关键事实事件；较旧事件折叠到 checkpoint，不无限增长。
## - 非计分事件对统计为无操作但推进处理水位（避免混合序列被误判为遗漏）。
## - checkpoint 记录截止事件序号与当时累计/日统计；重算 = checkpoint + 后续事件。
## - 压缩在一致快照边界进行，不能先删事件再保存 checkpoint。

const ContractLimits := preload("res://src/contracts/contract_limits.gd")

var events: Array = []            # 最近事件（有界）
var checkpoint: Dictionary = {}   # {event_sequence, members:{...}, world_total_sales, world_total_purchases}


## 追加事件并按上限折叠。
func append(event: Dictionary) -> void:
	events.append(event)
	while events.size() > ContractLimits.EVENT_LOG_RETENTION:
		var folded: Dictionary = events.pop_front()
		_fold_into_checkpoint(folded)


## 把一条即将被淘汰的事件折叠进 checkpoint。
func _fold_into_checkpoint(event: Dictionary) -> void:
	if checkpoint.is_empty():
		checkpoint = {
			"event_sequence": 0,
			"members": {},
			"world_total_sales": 0,
			"world_total_purchases": 0,
		}
	var actor: String = event["actor_player_id"]
	if not checkpoint["members"].has(actor):
		checkpoint["members"][actor] = _empty_stats()
	var payload: Dictionary = event["payload"]
	match str(event["event_type"]):
		"ProduceSold":
			var gross := int(payload["gross_amount"])
			checkpoint["members"][actor]["total_gross_sales"] += gross
			checkpoint["world_total_sales"] = int(checkpoint["world_total_sales"]) + gross
		"SeedPurchased":
			checkpoint["world_total_purchases"] = int(checkpoint["world_total_purchases"]) + int(payload["total_amount"])
		"CropPlanted":
			checkpoint["members"][actor]["contribution"]["planting"] += ContractLimits.POINTS_PLANT
		"CropWatered":
			checkpoint["members"][actor]["contribution"]["watering"] += ContractLimits.POINTS_WATER
		"CropHarvested":
			checkpoint["members"][actor]["contribution"]["harvesting"] += ContractLimits.POINTS_HARVEST
		"ProjectDonated":
			checkpoint["members"][actor]["contribution"]["donation"] += ContractLimits.POINTS_DONATE_PER_ITEM * int(payload.get("quantity", 0))
		_:
			pass  # 非计分事件：只推进水位
	checkpoint["event_sequence"] = int(event["event_sequence"])


## 重算统计 = checkpoint + 当前事件列表。
func recompute() -> Dictionary:
	var result := {
		"members": {},
		"world_total_sales": 0,
		"world_total_purchases": 0,
		"last_event_seq": 0,
	}
	if not checkpoint.is_empty():
		result["members"] = (checkpoint["members"] as Dictionary).duplicate(true)
		result["world_total_sales"] = int(checkpoint["world_total_sales"])
		result["world_total_purchases"] = int(checkpoint["world_total_purchases"])
		result["last_event_seq"] = int(checkpoint["event_sequence"])
	for event: Dictionary in events:
		var actor: String = event["actor_player_id"]
		if not result["members"].has(actor):
			result["members"][actor] = _empty_stats()
		var payload: Dictionary = event["payload"]
		match str(event["event_type"]):
			"ProduceSold":
				var gross := int(payload["gross_amount"])
				result["members"][actor]["total_gross_sales"] += gross
				result["world_total_sales"] = int(result["world_total_sales"]) + gross
			"SeedPurchased":
				result["world_total_purchases"] = int(result["world_total_purchases"]) + int(payload["total_amount"])
			"CropPlanted":
				result["members"][actor]["contribution"]["planting"] += ContractLimits.POINTS_PLANT
			"CropWatered":
				result["members"][actor]["contribution"]["watering"] += ContractLimits.POINTS_WATER
			"CropHarvested":
				result["members"][actor]["contribution"]["harvesting"] += ContractLimits.POINTS_HARVEST
			"ProjectDonated":
				result["members"][actor]["contribution"]["donation"] += ContractLimits.POINTS_DONATE_PER_ITEM * int(payload.get("quantity", 0))
			_:
				pass
		result["last_event_seq"] = int(event["event_sequence"])
	return result


func size() -> int:
	return events.size()


func to_dict() -> Dictionary:
	return {"events": events, "checkpoint": checkpoint}


static func from_dict(data: Dictionary) -> EventLog:
	var log := new()
	log.events = data.get("events", [])
	log.checkpoint = data.get("checkpoint", {})
	return log


static func _empty_stats() -> Dictionary:
	return {
		"total_gross_sales": 0, "today_gross_sales": 0,
		"contribution": {"planting": 0, "watering": 0, "harvesting": 0, "donation": 0},
	}
