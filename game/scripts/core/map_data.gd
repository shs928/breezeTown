extends RefCounted
## 地图空间规则的唯一数据入口。耕种、资源刷新、导航与水体碰撞共用布局。
## 本类不持有 Node，也不根据视觉网格推导规则。

const GRID := 2.0

var map_id := "breeze_valley"
var revision := 1
var bounds_half := Vector2(96.0, 80.0)
var bounds_power := 6
var blocked_rects: Array[Rect2] = []
var blocked_circles: Array = []
var blocked_paths: Array = []
var resource_blocks := {}
var landmarks := {}
var sites: Array = []
var pastures: Array[Rect2] = []
var waters: Array = []
var bridges: Array = []
var docks: Array = []
var ramps: Array = []
var obstacles: Array = []
var navigation_revision := 0


func load_from_world(world: Dictionary) -> void:
	bounds_half = world["bounds"]["half"]
	bounds_power = world["bounds"]["pow"]
	landmarks = world.get("landmarks", {}).duplicate(true)
	sites = world.get("sites", []).duplicate(true)
	var definition: Dictionary = world.get("definition", {})
	map_id = definition.get("id", "breeze_valley")
	revision = definition.get("revision", 1)
	waters = definition.get("waters", []).duplicate(true)
	for water:Dictionary in waters:
		var polygon:PackedVector2Array=water["polygon"]
		var water_bounds:=Rect2(polygon[0],Vector2.ZERO)
		for point:Vector2 in polygon:water_bounds=water_bounds.expand(point)
		water["bounds"]=water_bounds
	bridges = definition.get("bridges", []).duplicate(true)
	docks = definition.get("docks", []).duplicate(true)
	ramps = definition.get("ramps", []).duplicate(true)
	obstacles = world.get("obstacles", []).duplicate(true)
	var blocked: Dictionary = world.get("blocked", {})
	blocked_rects.assign(blocked.get("rects", []))
	blocked_circles = blocked.get("circles", []).duplicate(true)
	blocked_paths = blocked.get("paths", []).duplicate(true)
	resource_blocks.clear()
	navigation_revision += 1


func occupy_resource(id: int, at: Vector2, radius: float) -> void:
	resource_blocks[id] = {"position": at, "radius": radius}
	navigation_revision += 1


func release_resource(id: int) -> void:
	if resource_blocks.erase(id):
		navigation_revision += 1


func key_of(world: Vector3) -> Vector2i:
	return Vector2i(roundi(world.x / GRID), roundi(world.z / GRID))


func center_of(key: Vector2i) -> Vector3:
	return Vector3(key.x * GRID, 0, key.y * GRID)


func contains(at: Vector2, radius: float = 0.0) -> bool:
	var half := bounds_half - Vector2.ONE * radius
	return pow(absf(at.x) / half.x, bounds_power) + pow(absf(at.y) / half.y, bounds_power) < 1.0


func is_water(at: Vector2, margin: float = 0.0) -> bool:
	for water: Dictionary in waters:
		if not (water["bounds"] as Rect2).grow(margin).has_point(at):continue
		var polygon: PackedVector2Array = water["polygon"]
		if Geometry2D.is_point_in_polygon(at, polygon):
			return true
		if margin > 0:
			for index in range(polygon.size()):
				if Geometry2D.get_closest_point_to_segment(at, polygon[index], polygon[(index + 1) % polygon.size()]).distance_to(at) <= margin:
					return true
	return false


func on_deck(at: Vector2, radius: float = 0.0) -> bool:
	for entry: Dictionary in bridges + docks:
		var rect: Rect2 = entry["rect"]
		if rect.size.x > radius * 2 and rect.size.y > radius * 2 and rect.grow(-radius).has_point(at):
			return true
	return false


func is_walkable(at: Vector2, radius: float = 0.35) -> bool:
	if not contains(at, radius + 0.1):
		return false
	if not on_deck(at, radius) and is_water(at, radius):
		return false
	for obstacle: Dictionary in obstacles:
		var pos: Vector3 = obstacle["position"]
		var center := Vector2(pos.x, pos.z)
		if obstacle["shape"] == "box":
			var size: Vector3 = obstacle["size"]
			var half := Vector2(size.x, size.z) * 0.5
			if at.distance_to(at.clamp(center - half, center + half)) <= radius:
				return false
		elif at.distance_to(center) < float(obstacle["radius"]) + radius:
			return false
	for entry: Dictionary in resource_blocks.values():
		if at.distance_to(entry["position"]) < float(entry["radius"]) + radius:
			return false
	return true


func segment_is_walkable(from: Vector2, to: Vector2, radius: float = 0.35) -> bool:
	var steps := maxi(1, ceili(from.distance_to(to) / 0.3))
	for index in range(steps + 1):
		if not is_walkable(from.lerp(to, float(index) / steps), radius):
			return false
	return true


func is_open(key: Vector2i) -> bool:
	var flat := Vector2(key) * GRID
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		if not contains(flat + corner * 1.15):
			return false
	if is_water(flat, GRID * 0.72):
		return false
	var footprint := Rect2(flat - Vector2.ONE * 0.96, Vector2.ONE * 1.92)
	for entry: Dictionary in bridges + docks:
		if (entry["rect"] as Rect2).intersects(footprint):
			return false
	for rect in blocked_rects:
		if rect.intersects(footprint):
			return false
	for entry: Dictionary in blocked_circles + resource_blocks.values():
		var closest := (entry["position"] as Vector2).clamp(footprint.position, footprint.end)
		if closest.distance_to(entry["position"]) < float(entry["radius"]):
			return false
	for path: Dictionary in blocked_paths:
		if Geometry2D.get_closest_point_to_segment(flat, path["from"], path["to"]).distance_to(flat) < float(path["width"]) * 0.5 + 1.36:
			return false
	return true


func water_collision_rects(area:Rect2=Rect2()) -> Array[Rect2]:
	## 1 米水域栅格按行合并，桥/码头完整留空；碰撞不会产生横跨河流的隐形墙。
	var result: Array[Rect2] = []
	if area.size==Vector2.ZERO:area=Rect2(-bounds_half,bounds_half*2)
	for z in range(floori(area.position.y),ceili(area.end.y)):
		var start := 0
		var running := false
		for x in range(floori(area.position.x),ceili(area.end.x)+1):
			var wet := false
			if x < ceili(area.end.x):
				var cell := Rect2(x, z, 1, 1)
				wet = is_water(cell.get_center())
				if wet:
					for deck: Dictionary in bridges + docks:
						if cell.intersects((deck["rect"] as Rect2).grow(0.01)):
							wet = false
							break
			if wet and not running:
				start = x
				running = true
			elif not wet and running:
				result.append(Rect2(start, z, x - start, 1))
				running = false
	return result


func add_pasture(rect: Rect2) -> void:
	pastures.append(rect)
	# 与 Pasture 的实体围栏一致，南侧 2.4 米大门保持畅通。
	var p := rect.position
	var e := rect.end
	var gate := rect.get_center().x
	for line in [[p, Vector2(p.x, e.y)], [p, Vector2(e.x, p.y)], [Vector2(e.x, p.y), e], [Vector2(p.x, e.y), Vector2(gate - 1.2, e.y)], [Vector2(gate + 1.2, e.y), e]]:
		var a: Vector2 = line[0]
		var b: Vector2 = line[1]
		obstacles.append({"shape": "box", "position": Vector3((a.x + b.x) * 0.5, 0.45, (a.y + b.y) * 0.5), "size": Vector3(absf(a.x - b.x) + 0.35, 0.9, absf(a.y - b.y) + 0.35)})
	navigation_revision += 1


func to_dict() -> Dictionary:
	var list := []
	for rect in pastures:
		list.append([rect.position.x, rect.position.y, rect.size.x, rect.size.y])
	return {"map_id": map_id, "revision": revision, "pastures": list}


func from_dict(data: Dictionary) -> void:
	pastures.clear()
	for entry: Array in data.get("pastures", []):
		pastures.append(Rect2(entry[0], entry[1], entry[2], entry[3]))
