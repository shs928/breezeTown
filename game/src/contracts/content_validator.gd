class_name ContentValidator
## 内容加载校验入口（FND-02）：物品/作物/项目定义与地图 schema 校验。
## 表现层与权威碰撞共用同一份经校验的内容，不允许节点名称隐式决定可通行/可耕。
## 返回空串表示合法；否则返回 CONTENT_* 失败原因（首个错误即停）。

const MAP_SCHEMA_VERSION := 1
const CONTENT_SCHEMA_VERSION := 1
const REQUIRED_FACILITY_TYPES: PackedStringArray = [
	"seed_shop", "sell_point", "shared_storage", "project_board", "leaderboard",
]

const ContractLimits := preload("res://src/contracts/contract_limits.gd")
const ContractIds := preload("res://src/contracts/contract_ids.gd")


## 校验整包内容：{"items": <dict>, "crops": <dict>, "projects": <dict>}
static func validate_content_bundle(items_doc: Dictionary, crops_doc: Dictionary, projects_doc: Dictionary) -> String:
	var item_ids := {}
	if items_doc.get("content_schema_version") != CONTENT_SCHEMA_VERSION:
		return "CONTENT_SCHEMA_VERSION:items"
	for item: Dictionary in items_doc.get("items", []):
		for key in ["id", "kind", "stack_max", "crop_id"]:
			if not item.has(key):
				return "CONTENT_ITEM_MISSING_FIELD:" + str(item.get("id", "?"))
		if not ContractIds.is_definition_id(item["id"]):
			return "CONTENT_ITEM_BAD_ID:" + str(item["id"])
		if item_ids.has(item["id"]):
			return "CONTENT_ITEM_DUPLICATE:" + str(item["id"])
		if not item["kind"] in ["seed", "produce"]:
			return "CONTENT_ITEM_KIND:" + str(item["id"])
		if item["stack_max"] is not int or item["stack_max"] != ContractLimits.TRADE_QUANTITY_MAX:
			return "CONTENT_ITEM_STACK:" + str(item["id"])
		item_ids[item["id"]] = item

	if crops_doc.get("content_schema_version") != CONTENT_SCHEMA_VERSION:
		return "CONTENT_SCHEMA_VERSION:crops"
	var crop_ids := {}
	for crop: Dictionary in crops_doc.get("crops", []):
		for key in ["id", "name", "seed_item_id", "produce_item_id", "seed_price", "sell_price", "growth_days", "stages"]:
			if not crop.has(key):
				return "CONTENT_CROP_MISSING_FIELD:" + str(crop.get("id", "?"))
		if not ContractIds.is_definition_id(crop["id"]):
			return "CONTENT_CROP_BAD_ID:" + str(crop["id"])
		if crop_ids.has(crop["id"]):
			return "CONTENT_CROP_DUPLICATE:" + str(crop["id"])
		for item_key in ["seed_item_id", "produce_item_id"]:
			if not item_ids.has(crop[item_key]):
				return "CONTENT_CROP_UNKNOWN_ITEM:" + str(crop["id"]) + ":" + str(crop[item_key])
		for price_key in ["seed_price", "sell_price"]:
			if crop[price_key] is not int or crop[price_key] <= 0 or crop[price_key] > ContractLimits.MAX_BUSINESS_INT:
				return "CONTENT_CROP_PRICE:" + str(crop["id"]) + ":" + price_key
		if crop["growth_days"] is not int or crop["growth_days"] < 1:
			return "CONTENT_CROP_GROWTH:" + str(crop["id"])
		var stages: Array = crop["stages"]
		var prev_min := -1
		for stage: Dictionary in stages:
			if not stage.has("min_growth_days") or not stage.has("stage"):
				return "CONTENT_CROP_STAGE_FIELD:" + str(crop["id"])
			if stage["min_growth_days"] is not int or stage["min_growth_days"] <= prev_min:
				return "CONTENT_CROP_STAGE_ORDER:" + str(crop["id"])
			prev_min = stage["min_growth_days"]
		if stages.is_empty() or stages[-1]["min_growth_days"] != crop["growth_days"]:
			return "CONTENT_CROP_STAGE_MATURE:" + str(crop["id"])
		if stages[0]["min_growth_days"] != 0:
			return "CONTENT_CROP_STAGE_SOWN:" + str(crop["id"])
		crop_ids[crop["id"]] = crop

	if projects_doc.get("content_schema_version") != CONTENT_SCHEMA_VERSION:
		return "CONTENT_SCHEMA_VERSION:projects"
	var project_ids := {}
	var prev_order := 0
	for project: Dictionary in projects_doc.get("projects", []):
		for key in ["id", "name", "order", "requires_after", "requires", "effect"]:
			if not project.has(key):
				return "CONTENT_PROJECT_MISSING_FIELD:" + str(project.get("id", "?"))
		if not ContractIds.is_definition_id(project["id"]):
			return "CONTENT_PROJECT_BAD_ID:" + str(project["id"])
		if project_ids.has(project["id"]):
			return "CONTENT_PROJECT_DUPLICATE:" + str(project["id"])
		if project["order"] is not int or project["order"] != prev_order + 1:
			return "CONTENT_PROJECT_ORDER:" + str(project["id"])
		prev_order = project["order"]
		var prev_id: String = "" if project["order"] == 1 else _project_with_order(projects_doc, project["order"] - 1)
		if project["requires_after"] != null and project["requires_after"] != prev_id:
			return "CONTENT_PROJECT_CHAIN:" + str(project["id"])
		var total_needed := 0
		for req: Dictionary in project["requires"]:
			if not req.has_all(["item_id", "quantity"]):
				return "CONTENT_PROJECT_REQUIRE_FIELD:" + str(project["id"])
			if not item_ids.has(req["item_id"]):
				return "CONTENT_PROJECT_UNKNOWN_ITEM:" + str(project["id"]) + ":" + str(req["item_id"])
			if item_ids[req["item_id"]]["kind"] != "produce":
				return "CONTENT_PROJECT_NEEDS_PRODUCE:" + str(project["id"])
			if req["quantity"] is not int or req["quantity"] < 1 or req["quantity"] > 999:
				return "CONTENT_PROJECT_REQUIRE_QTY:" + str(project["id"])
			total_needed += req["quantity"]
		if total_needed > 999:
			return "CONTENT_PROJECT_TOTAL:" + str(project["id"])
		var effect: Dictionary = project["effect"]
		match effect.get("type", ""):
			"expand_farm":
				if effect.get("to_plots") != ContractLimits.TILLABLE_EXPANDED:
					return "CONTENT_PROJECT_FARM_PLOTS:" + str(project["id"])
			"expand_storage":
				if effect.get("to_slots") != ContractLimits.SHARED_STORAGE_SLOTS_EXPANDED:
					return "CONTENT_PROJECT_STORAGE_SLOTS:" + str(project["id"])
			"monument":
				pass
			_:
				return "CONTENT_PROJECT_EFFECT:" + str(project["id"])
		project_ids[project["id"]] = project
	return ""


static func _project_with_order(projects_doc: Dictionary, order: int) -> String:
	for project: Dictionary in projects_doc.get("projects", []):
		if project["order"] == order:
			return project["id"]
	return ""


## 地图校验：尺寸/图例/行宽/出生点/设施/可耕区全部按契约边界。
static func validate_map(map: Dictionary) -> String:
	if map.get("map_schema_version") != MAP_SCHEMA_VERSION:
		return "CONTENT_MAP_SCHEMA_VERSION"
	if map.get("width") != ContractLimits.MAP_W or map.get("height") != ContractLimits.MAP_H:
		return "CONTENT_MAP_SIZE"
	if map.get("tile_size") != ContractLimits.TILE_SIZE_PX:
		return "CONTENT_MAP_TILE_SIZE"
	var legend: Dictionary = map.get("legend", {})
	for required in ["G", "F", "P", "S", "B"]:
		if not legend.has(required):
			return "CONTENT_MAP_LEGEND:" + required
	var tiles: Array = map.get("tiles", [])
	if tiles.size() != ContractLimits.MAP_H:
		return "CONTENT_MAP_ROWS"
	var farmable := {}
	for y in tiles.size():
		var row: String = tiles[y]
		if row.length() != ContractLimits.MAP_W:
			return "CONTENT_MAP_ROW_WIDTH:" + str(y)
		for x in row.length():
			var ch := row[x]
			if not legend.has(ch):
				return "CONTENT_MAP_UNKNOWN_TILE:%d,%d" % [x, y]
			if ch == "F":
				farmable["%d,%d" % [x, y]] = true

	var initial: Dictionary = map.get("initial_farmable_rect", {})
	var expanded: Dictionary = map.get("expanded_farmable_rect", {})
	if not _valid_rect(initial) or not _valid_rect(expanded):
		return "CONTENT_MAP_FARM_RECT"
	if initial["w"] * initial["h"] != ContractLimits.TILLABLE_INITIAL:
		return "CONTENT_MAP_FARM_INITIAL_COUNT"
	if expanded["w"] * expanded["h"] != ContractLimits.TILLABLE_EXPANDED:
		return "CONTENT_MAP_FARM_EXPANDED_COUNT"
	if not _rect_contains(expanded, initial):
		return "CONTENT_MAP_FARM_NESTING"
	for key: String in farmable:
		var parts := key.split(",")
		var fx := int(parts[0])
		var fy := int(parts[1])
		if not (fx >= int(initial["x"]) and fx < int(initial["x"]) + int(initial["w"])
				and fy >= int(initial["y"]) and fy < int(initial["y"]) + int(initial["h"])):
			return "CONTENT_MAP_FARMABLE_OUTSIDE_RECT:%s" % key

	var spawns: Array = map.get("spawn_points", [])
	if spawns.size() != ContractLimits.SPAWN_POINT_COUNT:
		return "CONTENT_MAP_SPAWN_COUNT"
	var seen_spawns := {}
	for spawn: Dictionary in spawns:
		if not spawn.has_all(["x", "y"]):
			return "CONTENT_MAP_SPAWN_FIELD"
		var sx := int(spawn["x"])
		var sy := int(spawn["y"])
		if sx < 0 or sx >= ContractLimits.MAP_W or sy < 0 or sy >= ContractLimits.MAP_H:
			return "CONTENT_MAP_SPAWN_BOUNDS"
		var key := "%d,%d" % [sx, sy]
		if seen_spawns.has(key):
			return "CONTENT_MAP_SPAWN_DUPLICATE"
		seen_spawns[key] = true
		if tiles[sy][sx] != "S":
			return "CONTENT_MAP_SPAWN_NOT_WALKABLE"

	var facilities: Array = map.get("facilities", [])
	var seen_types := {}
	var seen_ids := {}
	for facility: Dictionary in facilities:
		if not facility.has_all(["id", "type", "rect"]):
			return "CONTENT_MAP_FACILITY_FIELD"
		if seen_ids.has(facility["id"]):
			return "CONTENT_MAP_FACILITY_DUPLICATE:" + str(facility["id"])
		seen_ids[facility["id"]] = true
		if not facility["type"] in REQUIRED_FACILITY_TYPES:
			return "CONTENT_MAP_FACILITY_TYPE:" + str(facility["type"])
		if seen_types.has(facility["type"]):
			return "CONTENT_MAP_FACILITY_ONCE:" + str(facility["type"])
		seen_types[facility["type"]] = true
		var rect: Dictionary = facility["rect"]
		if not _valid_rect(rect):
			return "CONTENT_MAP_FACILITY_RECT:" + str(facility["id"])
		if int(rect["x"]) + int(rect["w"]) > ContractLimits.MAP_W or int(rect["y"]) + int(rect["h"]) > ContractLimits.MAP_H:
			return "CONTENT_MAP_FACILITY_BOUNDS:" + str(facility["id"])
		for dy in int(rect["h"]):
			for dx in int(rect["w"]):
				var tx: int = int(rect["x"]) + dx
				var ty: int = int(rect["y"]) + dy
				if tiles[ty][tx] != "P":
					return "CONTENT_MAP_FACILITY_ZONE_NOT_P:%s:%d,%d" % [facility["id"], tx, ty]
	for required_type: String in REQUIRED_FACILITY_TYPES:
		if not seen_types.has(required_type):
			return "CONTENT_MAP_FACILITY_MISSING:" + required_type
	return ""


static func _valid_rect(rect: Dictionary) -> bool:
	if not rect.has_all(["x", "y", "w", "h"]):
		return false
	for key in ["x", "y", "w", "h"]:
		if rect[key] is not int or rect[key] < 0:
			return false
	return rect["w"] > 0 and rect["h"] > 0


static func _rect_contains(outer: Dictionary, inner: Dictionary) -> bool:
	return (int(inner["x"]) >= int(outer["x"])
		and int(inner["y"]) >= int(outer["y"])
		and int(inner["x"]) + int(inner["w"]) <= int(outer["x"]) + int(outer["w"])
		and int(inner["y"]) + int(inner["h"]) <= int(outer["y"]) + int(outer["h"]))
