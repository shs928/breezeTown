class_name ItemCatalog
## 物品与作物定义目录（ECON 唯一维护）。从 content/schema/*.json 加载，提供只读查询。
## 价格来自定义文件；客户端不能提交价格（契约 5.2）。

const ContractIds := preload("res://src/contracts/contract_ids.gd")

var items: Dictionary = {}    # item_definition_id -> {kind, stack_max, crop_id}
var crops: Dictionary = {}    # crop_definition_id -> 定义
var projects: Dictionary = {} # project_id -> 定义


static func load_from_disk() -> ItemCatalog:
	var catalog := new()
	catalog.items = _index(_read_json("res://content/schema/items.json")["items"], "id")
	catalog.crops = _index(_read_json("res://content/schema/crops.json")["crops"], "id")
	catalog.projects = _index(_read_json("res://content/schema/projects.json")["projects"], "id")
	return catalog


static func _read_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is not Dictionary:
		push_error("failed to parse content: " + path)
		return {}
	return parsed


static func _index(list: Array, key: String) -> Dictionary:
	var out := {}
	for entry: Dictionary in list:
		out[entry[key]] = entry
	return out


func has_item(item_definition_id: String) -> bool:
	return items.has(item_definition_id)


func is_seed(item_definition_id: String) -> bool:
	return items.get(item_definition_id, {}).get("kind", "") == "seed"


func is_produce(item_definition_id: String) -> bool:
	return items.get(item_definition_id, {}).get("kind", "") == "produce"


func seed_price(seed_definition_id: String) -> int:
	var crop_id: String = items.get(seed_definition_id, {}).get("crop_id", "")
	return int(crops.get(crop_id, {}).get("seed_price", 0))


func sell_price(produce_definition_id: String) -> int:
	var crop_id: String = items.get(produce_definition_id, {}).get("crop_id", "")
	return int(crops.get(crop_id, {}).get("sell_price", 0))


func crop_definition(crop_id: String) -> Dictionary:
	return crops.get(crop_id, {})


func crop_id_of(item_definition_id: String) -> String:
	return str(items.get(item_definition_id, {}).get("crop_id", ""))


## 内容 hash：所有定义文件的稳定摘要，用于联机两端校验（契约 10.1）。
static func content_hash() -> String:
	var blob := ""
	for path in ["res://content/schema/items.json", "res://content/schema/crops.json", "res://content/schema/projects.json"]:
		blob += FileAccess.get_file_as_string(path)
	return blob.sha256_text()
