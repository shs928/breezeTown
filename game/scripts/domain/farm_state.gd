extends RefCounted
## 农业领域状态（CropState）：全图耕地数据，不依赖任何 Node3D，
## 可独立运算、单元测试与序列化。3D 节点（tile.gd）只是本状态的视图。

const CropDB := preload("res://scripts/data/crop_db.gd")


class FarmTileData extends RefCounted:
	var state := "wild"  # wild | tilled | planted
	var crop := ""
	var stage := 0
	var watered := false
	var last_crop := ""  # 轮作：上一茬作物；连作时首夜不生长
	var rotation_pending := false
	var fertilized := false  # FARM-01 二轮：施肥后每个浇水的夜晚多长一阶

	func is_mature() -> bool:
		return state == "planted" and stage >= CropDB.grow_days(crop)

	func to_dict() -> Dictionary:
		return {"state": state, "crop": crop, "stage": stage, "watered": watered, "last_crop": last_crop, "fertilized": fertilized}

	func from_dict(data: Dictionary) -> void:
		state = data.get("state", "wild")
		crop = data.get("crop", "")
		stage = int(data.get("stage", 0))
		watered = bool(data.get("watered", false))
		last_crop = data.get("last_crop", "")
		fertilized = bool(data.get("fertilized", false))


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


func plant(key: Vector2i, kind: String, season: String = "", fertilized: bool = false) -> bool:
	## season 传入时做宜种季节裁决（FARM-01）；fertilized 标记施肥加成。
	if season != "" and not CropDB.allows_season(kind, season):
		return false
	var data: FarmTileData = tiles.get(key)
	if data == null or not plant_data(data, key, kind, fertilized):
		return false
	return true


func plant_data(data: FarmTileData, key: Vector2i, kind: String, fertilized: bool = false) -> bool:
	if data.state != "tilled":
		return false
	data.state = "planted"
	data.crop = kind
	data.stage = 0
	data.watered = false
	data.fertilized = fertilized
	# 轮作（FARM-01）：连作同一作物首夜不生长，换茬恢复。
	data.rotation_pending = data.last_crop == kind
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
	data.last_crop = kind
	data.crop = ""
	data.stage = 0
	data.watered = false
	data.rotation_pending = false
	data.fertilized = false
	EventBus.instance().crop_harvested.emit(key, kind)
	return kind


func rollover() -> void:
	for key: Vector2i in tiles:
		rollover_data(tiles[key], key)


func rollover_data(data: FarmTileData, key: Vector2i) -> void:
	## 日切：浇过水的作物长一阶；施肥（二轮）再多一阶；连作首夜不生长；水量清空。
	if data.state == "planted" and data.watered and not data.is_mature():
		if data.rotation_pending:
			data.rotation_pending = false
		else:
			data.stage += 1
			if data.fertilized and not data.is_mature():
				data.stage += 1
	data.watered = false


func wither_out_of_season(season: String) -> int:
	## 换季（FARM-01）：不合新季节的作物枯萎回裸土，返回枯萎株数。
	var withered := 0
	for key: Vector2i in tiles:
		var data: FarmTileData = tiles[key]
		if data.state != "planted" or CropDB.allows_season(data.crop, season):
			continue
		data.state = "tilled"
		data.crop = ""
		data.stage = 0
		data.watered = false
		data.rotation_pending = false
		data.fertilized = false
		withered += 1
	return withered


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
