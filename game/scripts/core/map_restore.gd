extends RefCounted
## 地图版本变化时先计算恢复方案；没有足够空地则保持当前世界与磁盘存档不变。
const MapData := preload("res://scripts/core/map_data.gd")


static func plan(saved: Dictionary, world: Dictionary) -> Dictionary:
	var map := MapData.new()
	map.load_from_world(world)
	var source_id: String = saved.get("map", {}).get("id", saved.get("pastures", {}).get("map_id", ""))
	if (not source_id.is_empty() and source_id != map.map_id) or (source_id.is_empty() and map.map_id == "willow_creek_valley_v1"):
		return {"ok": false, "error": "此存档属于另一张地图；请从对应地图读取，当前进度未改变"}
	var result := saved.duplicate(true)
	var moved := 0
	var enclosures := []
	var occupied := {}
	var initial: Rect2 = world["pasture"]
	var source: Array = saved.get("pastures", {}).get("pastures", []).duplicate(true)
	if source.is_empty():
		source.append([initial.position.x, initial.position.y, initial.size.x, initial.size.y])
	for index in range(source.size()):
		var entry: Array = source[index]
		var rect := initial if index == 0 else Rect2(entry[0], entry[1], entry[2], entry[3])
		if index > 0 and not _area_open(map, rect):
			var replacement := _find_area(map, rect)
			if replacement.size == Vector2.ZERO:
				return {"ok": false, "error": "新地图没有足够空地恢复牧场；原存档已保留"}
			rect = replacement
			moved += 1
		enclosures.append([rect.position.x, rect.position.y, rect.size.x, rect.size.y])
		map.blocked_rects.append(rect.grow(0.25))
	var restored_tiles := []
	var pending := []
	for original: Dictionary in saved.get("farm", {}).get("tiles", []):
		var entry := original.duplicate(true)
		var key := Vector2i(entry["key"][0], entry["key"][1])
		if map.is_open(key) and not occupied.has(key):
			occupied[key] = true
			restored_tiles.append(entry)
		else:
			pending.append(entry)
	var farm: Rect2 = world.get("definition", {}).get("farm", Rect2(-44, 2, 35, 27))
	var preferred := Vector2i(roundi(farm.get_center().x / MapData.GRID), roundi(farm.get_center().y / MapData.GRID))
	for entry: Dictionary in pending:
		var found := false
		for radius in range(101):
			if found:
				break
			for x in range(-radius, radius + 1):
				for y in range(-radius, radius + 1):
					if maxi(absi(x), absi(y)) != radius:
						continue
					var key := preferred + Vector2i(x, y)
					if not occupied.has(key) and map.is_open(key):
						occupied[key] = true
						entry["key"] = [key.x, key.y]
						restored_tiles.append(entry)
						moved += 1
						found = true
						break
				if found:
					break
		if not found:
			return {"ok": false, "error": "新地图没有足够空地恢复全部耕地；原存档已保留"}
	result["farm"] = {"tiles": restored_tiles}
	result["pastures"] = {"map_id": map.map_id, "revision": map.revision, "pastures": enclosures}
	result["map"] = {"id": map.map_id, "revision": map.revision}
	result["relocated"] = moved
	result["ok"] = true
	return result


static func _area_open(map: RefCounted, rect: Rect2) -> bool:
	for x in range(floori(rect.position.x / 2), ceili(rect.end.x / 2) + 1):
		for y in range(floori(rect.position.y / 2), ceili(rect.end.y / 2) + 1):
			if not map.is_open(Vector2i(x, y)):
				return false
	return true


static func _find_area(map: RefCounted, original: Rect2) -> Rect2:
	var best := Rect2()
	var distance := INF
	for x in range(-floori(map.bounds_half.x) + 4, floori(map.bounds_half.x) - ceili(original.size.x), 2):
		for y in range(-floori(map.bounds_half.y) + 4, floori(map.bounds_half.y) - ceili(original.size.y), 2):
			var candidate := Rect2(Vector2(x, y), original.size)
			var delta := candidate.position.distance_squared_to(original.position)
			if delta < distance and _area_open(map, candidate):
				best = candidate
				distance = delta
	return best
