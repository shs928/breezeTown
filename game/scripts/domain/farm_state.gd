extends RefCounted
## 农业领域状态（CropState）：全图耕地数据，不依赖任何 Node3D，
## 可独立运算、单元测试与序列化。3D 节点（tile.gd）只是本状态的视图。

const CropDB := preload("res://scripts/data/crop_db.gd")


class FarmTileData extends RefCounted:
	var state := "wild"  # wild | tilled | planted
	var crop := ""
	var stage := 0
	var watered := false

	func is_mature() -> bool:
		return state == "planted" and stage >= CropDB.grow_days(crop)

	func to_dict() -> Dictionary:
		return {"state": state, "crop": crop, "stage": stage, "watered": watered}

	func from_dict(data: Dictionary) -> void:
		state = data.get("state", "wild")
		crop = data.get("crop", "")
		stage = int(data.get("stage", 0))
		watered = bool(data.get("watered", false))


var tiles := {}  # Vector2i -> FarmTileData


func data_of(key: Vector2i) -> FarmTileData:
	return tiles.get(key)


func has_tile(key: Vector2i) -> bool:
	return tiles.has(key)


func till(key: Vector2i) -> FarmTileData:
	## 整地；已占用返回 null。
	if tiles.has(key):
		return null
	var data := FarmTileData.new()
	data.state = "tilled"
	tiles[key] = data
	EventBus.instance().crop_tilled.emit(key)
	return data


func plant(key: Vector2i, kind: String) -> bool:
	var data: FarmTileData = tiles.get(key)
	if data == null or not plant_data(data, key, kind):
		return false
	return true


func plant_data(data: FarmTileData, key: Vector2i, kind: String) -> bool:
	if data.state != "tilled":
		return false
	data.state = "planted"
	data.crop = kind
	data.stage = 0
	data.watered = false
	EventBus.instance().crop_planted.emit(key, kind)
	return true


func water(key: Vector2i) -> bool:
	var data: FarmTileData = tiles.get(key)
	if data == null:
		return false
	return water_data(data, key)


func water_data(data: FarmTileData, key: Vector2i) -> bool:
	if data.state != "planted" or data.watered or data.is_mature():
		return false
	data.watered = true
	EventBus.instance().crop_watered.emit(key)
	return true


func harvest(key: Vector2i) -> String:
	var data: FarmTileData = tiles.get(key)
	if data == null:
		return ""
	return harvest_data(data, key)


func harvest_data(data: FarmTileData, key: Vector2i) -> String:
	if not data.is_mature():
		return ""
	var kind := data.crop
	data.state = "tilled"
	data.crop = ""
	data.stage = 0
	data.watered = false
	EventBus.instance().crop_harvested.emit(key, kind)
	return kind


func rollover() -> void:
	for key: Vector2i in tiles:
		rollover_data(tiles[key], key)


func rollover_data(data: FarmTileData, key: Vector2i) -> void:
	## 日切：浇过水的作物长一阶；水量清空。
	if data.state == "planted" and data.watered and not data.is_mature():
		data.stage += 1
	data.watered = false


func to_dict() -> Dictionary:
	var list := []
	for key: Vector2i in tiles:
		var entry: Dictionary = tiles[key].to_dict()
		entry["key"] = [key.x, key.y]
		list.append(entry)
	return {"tiles": list}


func from_dict(data: Dictionary) -> void:
	tiles.clear()
	for entry: Dictionary in data.get("tiles", []):
		var key := Vector2i(entry["key"][0], entry["key"][1])
		var tile_data := FarmTileData.new()
		tile_data.from_dict(entry)
		tiles[key] = tile_data
