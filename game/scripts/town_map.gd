extends Control
## 随玩家移动的山谷导览图；地标和道路直接读取实际地图布局。

const Valley = preload("res://scripts/art/valley_terrain.gd")
const MineLayout = preload("res://scripts/mine_layout.gd")

var navigation: Dictionary = {}
var player_position := Vector2.ZERO
var expanded := false
var _font: Font
var _water_shapes: Array[PackedVector2Array] = []
var _label_areas: Array[Rect2] = []
var _forest_mask: Image
var _metric := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = preload("res://resources/ui_font.tres")


func configure(data: Dictionary) -> void:
	navigation = data
	_metric = data.get("map_id", "") == "willow_creek_valley_v1"
	_forest_mask = preload("res://resources/maps/forest_mask.png").get_image() if _metric else null
	_collect_water_shapes()
	queue_redraw()


func track(at: Vector3) -> void:
	var next := Vector2(at.x, at.z)
	if next.distance_squared_to(player_position) > 0.04:
		player_position = next
		queue_redraw()


func set_expanded(value: bool) -> void:
	expanded = value
	queue_redraw()


func _point(at: Vector2) -> Vector2:
	var half: Vector2 = navigation["half"]
	var margin := 40.0 if expanded else 18.0
	var scale_factor := minf((size.x - margin * 2) / (half.x * 2), (size.y - margin * 2 - 42) / (half.y * 2))
	return Vector2(size.x * 0.5, size.y * 0.5 + 13) + at * scale_factor


func _draw() -> void:
	if navigation.is_empty() or _font == null or size.x < 120 or size.y < 120:
		return
	if navigation.get("kind", "town") == "mine":
		_draw_mine()
		return
	_label_areas.clear()
	_draw_town_frame()
	_draw_land()
	_draw_regions()
	_draw_forests()
	_draw_roads()
	_draw_waters()
	_draw_crossings()
	_draw_sites()
	_draw_region_labels()
	_draw_compass()
	if _metric and expanded:
		_draw_scale()
	if expanded:
		draw_circle(Vector2(31, size.y - 24), 5.0, Color("#bc6646"))
		draw_string(_font, Vector2(43, size.y - 19), "你的位置    ·    西南：玩家农场    ·    东北：NPC 农庄" if _metric else "你的位置    ·    桥梁可过河    ·    Shift 快跑", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#6f6145"))
	var marker := _point(player_position)
	draw_circle(marker + Vector2(0, 1.5), 8.0 if expanded else 5.6, Color(0.18, 0.24, 0.17, 0.24))
	draw_circle(marker, 7.0 if expanded else 5.0, Color("#fff6d9"))
	draw_circle(marker, 4.6 if expanded else 3.2, Color("#bc6646"))


func _collect_water_shapes() -> void:
	_water_shapes.clear()
	# 合并相连的河湖轮廓，避免在汇流处画出不存在的岸线。
	for water: Dictionary in navigation.get("waters", []):
		var polygon: PackedVector2Array = water["polygon"]
		var index := 0
		while index < _water_shapes.size():
			var joined := Geometry2D.merge_polygons(polygon, _water_shapes[index])
			if joined.size() == 1:
				polygon = joined[0]
				_water_shapes.remove_at(index)
				index = 0
			else:
				index += 1
		_water_shapes.append(polygon)
	# 世界定义让河流越过边界接入瀑布和海洋，导览图在岛岸裁切。
	if not _water_shapes.is_empty() and navigation.has("half"):
		var boundary := PackedVector2Array()
		for i in range(96):
			var at := Valley.boundary_point(i * TAU / 96.0, navigation["half"], navigation["power"])
			boundary.append(Vector2(at.x, at.z))
		var clipped: Array[PackedVector2Array] = []
		for polygon: PackedVector2Array in _water_shapes:
			for part: PackedVector2Array in Geometry2D.intersect_polygons(polygon, boundary):
				clipped.append(part)
		_water_shapes = clipped


func _draw_town_frame() -> void:
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color("#966c41")
	frame.border_color = Color("#62492f")
	frame.set_border_width_all(2)
	frame.set_corner_radius_all(13)
	frame.shadow_color = Color(0.12, 0.19, 0.15, 0.24)
	frame.shadow_size = 6
	draw_style_box(frame, Rect2(Vector2.ZERO, size))
	var parchment := StyleBoxFlat.new()
	parchment.bg_color = Color("#ecdfb9")
	parchment.border_color = Color("#c6a974")
	parchment.set_border_width_all(2)
	parchment.set_corner_radius_all(8)
	draw_style_box(parchment, Rect2(Vector2.ONE * 7, size - Vector2.ONE * 14))
	for corner in [Vector2(5, 5), Vector2(size.x - 5, 5), Vector2(5, size.y - 5), size - Vector2.ONE * 5]:
		draw_circle(corner, 1.5, Color("#e0bf83"))
	var title := "微风山谷  ·  旅行地图" if expanded else "微风山谷"
	if _metric and expanded:
		title += "    2.60 × 2.37 km"
	draw_string(_font, Vector2(20, 29), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 21 if expanded else 16, Color("#584c31"))
	draw_string(_font, Vector2(size.x - (157 if expanded else 67), 28), "M / Esc 收起" if expanded else "M 展开", HORIZONTAL_ALIGNMENT_LEFT, -1, 14 if expanded else 12, Color("#847052"))
	if expanded:
		draw_line(Vector2(22, 42), Vector2(size.x - 22, 42), Color("#ccb487"), 1, true)


func _draw_land() -> void:
	var outline := PackedVector2Array()
	var south_shore := PackedVector2Array()
	for i in range(96):
		var at := Valley.boundary_point(i * TAU / 96.0, navigation["half"], navigation["power"])
		var point := _point(Vector2(at.x, at.z))
		outline.append(point)
		if i >= 4 and i <= 44:
			south_shore.append(point)
	# 南缘用海岸表达世界边界，北缘才是雪山。
	draw_polyline(south_shore, Color("#78b8c1"), 14 if expanded else 6, true)
	draw_colored_polygon(outline, Color("#a9ba76"))
	outline.append(outline[0])
	draw_polyline(outline, Color("#8d9c66"), 2.0 if expanded else 1.0, true)
	draw_polyline(south_shore, Color("#d2c797"), 4 if expanded else 1.8, true)
	var half: Vector2 = navigation["half"]
	for i in range(15 if expanded else 10):
		var angle := lerpf(PI * 1.20, PI * 1.80, i / (14.0 if expanded else 9.0))
		var at := Valley.boundary_point(angle, half - Vector2(4, 5), navigation["power"])
		if _metric:
			var px := Vector2(70 + (i % 5) * 58, 80 + (i / 5) * 48)
			var flat := (px - Vector2(656, 599.5)) * (400.0 / 202.0)
			at = Vector3(flat.x, 0, flat.y)
		var point := _point(Vector2(at.x, at.z))
		var radius := (10.0 if expanded else 3.8) * (1.0 + 0.18 * sin(i * 2.4))
		draw_colored_polygon(PackedVector2Array([point + Vector2(-radius, radius * 0.65), point + Vector2(0, -radius), point + Vector2(radius, radius * 0.65)]), Color("#858d7e"))
		draw_colored_polygon(PackedVector2Array([point + Vector2(0, -radius), point + Vector2(radius, radius * 0.65), point + Vector2(radius * 0.12, radius * 0.4)]), Color("#65786e"))
		draw_colored_polygon(PackedVector2Array([point + Vector2(-radius * 0.37, -radius * 0.39), point + Vector2(0, -radius), point + Vector2(radius * 0.36, -radius * 0.4), point + Vector2(radius * 0.05, -radius * 0.53)]), Color("#efeeda"))


func _screen_rect(rect: Rect2) -> Rect2:
	return Rect2(_point(rect.position), _point(rect.end) - _point(rect.position))


func _screen_polygon(polygon: PackedVector2Array) -> PackedVector2Array:
	var points := PackedVector2Array()
	for point: Vector2 in polygon:
		points.append(_point(point))
	return points


func _draw_regions() -> void:
	for region: Dictionary in navigation.get("regions", []):
		var rect: Rect2 = region["rect"]
		if region["id"] in ["lake", "mine"]:
			continue
		var tint := Color(region.get("color", "#a9ba76"))
		tint.a = 0.16
		var wash := StyleBoxFlat.new()
		wash.bg_color = tint
		wash.set_corner_radius_all(22 if expanded else 8)
		draw_style_box(wash, _screen_rect(rect))
	for region_name in ["farm", "ranch"]:
		if not navigation.has(region_name):
			continue
		var field := _screen_rect(navigation[region_name])
		draw_rect(field, Color("#bda875") if region_name == "farm" else Color("#b4c184"))
		draw_rect(field, Color("#9c9164"), false, 1.1)
		if region_name == "farm":
			var rows := 7 if expanded else 4
			for row in range(1, rows):
				var y := field.position.y + field.size.y * row / rows
				draw_line(Vector2(field.position.x + 2, y), Vector2(field.end.x - 2, y), Color("#94a56c"), 2.0 if expanded else 1.0, true)


func _draw_forests() -> void:
	if _metric and _forest_mask != null:
		var half: Vector2 = navigation["half"]
		var scale_factor := maxf(.001, _point(Vector2.RIGHT).x - _point(Vector2.ZERO).x)
		var spacing := (12.0 if expanded else 7.0) / scale_factor
		for row in range(ceili(half.y * 2 / spacing)):
			for column in range(ceili(half.x * 2 / spacing)):
				var at := -half + Vector2(column + .5, row + .5) * spacing
				at += Vector2(sin(row * 2.7 + column), cos(column * 1.8 + row)) * spacing * .22
				var uv := (at + half) / (half * 2)
				var pixel := Vector2i(uv * Vector2(_forest_mask.get_size()))
				if pixel.x < 0 or pixel.y < 0 or pixel.x >= _forest_mask.get_width() or pixel.y >= _forest_mask.get_height(): continue
				if _forest_mask.get_pixelv(pixel).r < .24 or _over_water(at): continue
				_draw_tree(_point(at), 6.5 if expanded else 3.3, (column + row) % 3 == 0)
		return
	for forest: Dictionary in navigation.get("forests", []):
		var rect: Rect2 = forest["rect"]
		var spacing := 6.0 if expanded else 12.0
		var rows := maxi(1, int(rect.size.y / spacing))
		var columns := maxi(1, int(rect.size.x / spacing))
		for row in range(rows):
			for column in range(columns):
				var at := rect.position + Vector2((column + 0.5) / columns, (row + 0.5) / rows) * rect.size
				at += Vector2(sin(row * 2.7 + column), cos(column * 1.8 + row)) * spacing * 0.16
				if _over_water(at):
					continue
				_draw_tree(_point(at), 8.0 if expanded else 2.5, (column + row) % 3 == 0)


func _over_water(at: Vector2) -> bool:
	for polygon: PackedVector2Array in _water_shapes:
		if Geometry2D.is_point_in_polygon(at, polygon):
			return true
	return false


func _draw_tree(point: Vector2, radius: float, broadleaf: bool) -> void:
	draw_line(point, point + Vector2(0, radius), Color("#857348"), 1.5 if expanded else 1.0)
	if broadleaf:
		draw_circle(point + Vector2(0, -radius * 0.2), radius * 0.78, Color("#6a925c"))
		draw_circle(point + Vector2(-radius * 0.2, -radius * 0.45), radius * 0.56, Color("#84a365"))
	else:
		draw_colored_polygon(PackedVector2Array([point + Vector2(-radius * 0.72, radius * 0.35), point + Vector2(0, -radius * 1.4), point + Vector2(radius * 0.72, radius * 0.35)]), Color("#527e5e"))
		draw_colored_polygon(PackedVector2Array([point + Vector2(-radius * 0.56, -radius * 0.2), point + Vector2(0, -radius * 1.4), point + Vector2(radius * 0.06, -radius * 0.1)]), Color("#75965f"))


func _draw_roads() -> void:
	var scale_factor := _point(Vector2.RIGHT).x - _point(Vector2.ZERO).x
	for road: Dictionary in navigation.get("roads", []):
		var points := PackedVector2Array()
		for at: Vector2 in road["points"]:
			points.append(_point(at))
		if points.size() < 2:
			continue
		var width := maxf(1.4, float(road.get("width", 2.0)) * scale_factor * 0.7)
		draw_polyline(points, Color("#ad9f70"), width + (1.4 if expanded else 0.7), true)
		draw_polyline(points, Color("#e9d8a5") if not road.get("paved", false) else Color("#d9d0ad"), width, true)


func _draw_waters() -> void:
	for polygon: PackedVector2Array in _water_shapes:
		var points := _screen_polygon(polygon)
		if points.size() < 3:
			continue
		draw_colored_polygon(points, Color("#6eacba"))
		points.append(points[0])
		draw_polyline(points, Color("#d2d2a1"), 3.0 if expanded else 1.4, true)
		draw_polyline(points, Color("#9ec8c3"), 1.3 if expanded else 0.7, true)
	if navigation.has("lake_center") and navigation.has("lake_radius"):
		var center: Vector2 = navigation["lake_center"]
		var radius: Vector2 = navigation["lake_radius"]
		for offset in [Vector2(-0.28, -0.27), Vector2(0.18, 0.1), Vector2(-0.15, 0.41)]:
			var at: Vector2 = center + offset * radius
			if _over_water(at):
				var point := _point(at)
				var length := 10.0 if expanded else 3.5
				draw_line(point - Vector2(length, 0), point + Vector2(length, 0), Color("#acd4d0"), 1.0, true)


func _draw_crossings() -> void:
	for kind in ["bridges", "docks"]:
		for crossing: Dictionary in navigation.get(kind, []):
			var rect := _screen_rect(crossing["rect"])
			draw_rect(rect.grow(0.6), Color("#715b3c"))
			draw_rect(rect, Color("#be9560"))
			var horizontal := rect.size.x > rect.size.y
			var count := 6 if expanded else 3
			for plank in range(1, count):
				var fraction := float(plank) / count
				var a := rect.position + Vector2(rect.size.x * fraction, 0) if horizontal else rect.position + Vector2(0, rect.size.y * fraction)
				var b := a + Vector2(0, rect.size.y) if horizontal else a + Vector2(rect.size.x, 0)
				draw_line(a, b, Color("#947749"), 0.8, true)


func _draw_sites() -> void:
	for site: Dictionary in navigation.get("sites", []):
		var half: Vector2 = site["size"] * 0.5
		var footprint := _screen_rect(Rect2(site["position"] - half, site["size"]))
		if _metric:
			var icon_size := footprint.size.max(Vector2(8, 7) if expanded else Vector2(3, 3))
			footprint = Rect2(_point(site["position"]) - icon_size * .5, icon_size)
		_label_areas.append(footprint.grow(2))
		var roof := Color("#bb7953")
		if site["id"] in ["clinic", "shop", "library", "cottage"]:
			roof = Color("#648d9a")
		draw_rect(Rect2(footprint.position + Vector2(0, 1.5), footprint.size), Color("#786745"))
		draw_rect(footprint, roof)
		draw_line(footprint.position + Vector2(0, footprint.size.y * 0.5), footprint.end - Vector2(0, footprint.size.y * 0.5), roof.lightened(0.26), 1.4 if expanded else 0.8)
	if navigation.has("mine"):
		var mine := _point(navigation["mine"])
		draw_circle(mine, 6.0 if expanded else 3.7, Color("#6c667a"))
		draw_arc(mine + Vector2(0, 1), 3.5 if expanded else 2.0, PI, TAU, 10, Color("#d8d0b1"), 1.6 if expanded else 1.0, true)
		if expanded:
			_draw_map_label("星辉矿场", mine, Color("#55475e"), 14, 15)
	if expanded:
		for site: Dictionary in navigation.get("sites", []):
			var half_size: Vector2 = site["size"] * 0.5
			var half_height := absf(_point(half_size).y - _point(Vector2.ZERO).y)
			_draw_map_label(site["label"], _point(site["position"]), Color("#554e36"), 13, half_height + 11, true)


func _draw_region_labels() -> void:
	for region: Dictionary in navigation.get("regions", []):
		if region["id"] == "mine":
			continue
		if not expanded and region["id"] not in ["farm", "ranch", "town", "village", "lake"]:
			continue
		var rect: Rect2 = region["rect"]
		var at: Vector2 = region.get("position", rect.get_center())
		_draw_map_label(region["label"], _point(at), Color("#47603e"), 16 if expanded else 10, 0)


func _draw_map_label(label: String, point: Vector2, color: Color, font_size: int, offset: float, connect_to_site: bool = false) -> void:
	var text_size := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var label_size := text_size + Vector2(8, 3)
	var chosen := Rect2(point + Vector2(-label_size.x * 0.5, offset), label_size)
	var found := false
	var shifts: Array[Vector2] = [Vector2(0, offset), Vector2(0, -offset - label_size.y)]
	for step in range(1, 5):
		var rise := (label_size.y + 4) * step
		shifts.append_array([Vector2(0, offset + rise), Vector2(0, -offset - label_size.y - rise)])
		for side in [-1, 1]:
			var slide: float = (label_size.x * 0.5 + 10) * side
			shifts.append_array([Vector2(slide, offset + rise * 0.5), Vector2(slide, -offset - label_size.y - rise * 0.5)])
	for shift: Vector2 in shifts:
		var candidate := Rect2(point + shift - Vector2(label_size.x * 0.5, 0), label_size)
		candidate.position.x = clampf(candidate.position.x, 16, size.x - candidate.size.x - 16)
		candidate.position.y = clampf(candidate.position.y, 45 if expanded else 36, size.y - candidate.size.y - (44 if expanded else 14))
		var overlaps := false
		for occupied: Rect2 in _label_areas:
			if occupied.intersects(candidate.grow(2)):
				overlaps = true
				break
		if not overlaps:
			chosen = candidate
			found = true
			break
	if not found and not expanded:
		return
	_label_areas.append(chosen)
	if connect_to_site and point.distance_to(chosen.get_center()) > offset + label_size.y:
		var nearest := Vector2(clampf(point.x, chosen.position.x, chosen.end.x), clampf(point.y, chosen.position.y, chosen.end.y))
		draw_line(point, nearest, Color("#8a8261"), 1.0, true)
	var plate := StyleBoxFlat.new()
	plate.bg_color = Color(0.95, 0.91, 0.75, 0.9)
	plate.set_corner_radius_all(3)
	draw_style_box(plate, chosen)
	draw_string(_font, chosen.position + Vector2(4, 1 + _font.get_ascent(font_size)), label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _draw_compass() -> void:
	var center := Vector2(43, 79) if expanded else Vector2(29, 54)
	var radius := 13.0 if expanded else 6.0
	draw_circle(center, radius + 2, Color(0.94, 0.89, 0.73, 0.88))
	draw_arc(center, radius * 0.7, 0, TAU, 32, Color("#9c8156"), 1.0, true)
	draw_colored_polygon(PackedVector2Array([center + Vector2(0, -radius), center + Vector2(-radius * 0.28, radius * 0.5), center, center + Vector2(radius * 0.28, radius * 0.5)]), Color("#876846"))
	draw_line(center - Vector2(radius, 0), center + Vector2(radius, 0), Color("#ae9468"), 1.0, true)
	draw_string(_font, center + Vector2(-5, -radius - 4), "北", HORIZONTAL_ALIGNMENT_LEFT, -1, 11 if expanded else 9, Color("#766143"))


func _draw_scale() -> void:
	var pixels_per_meter := _point(Vector2.RIGHT).x - _point(Vector2.ZERO).x
	var span := 400.0 * pixels_per_meter
	var origin := Vector2(size.x - span - 27, size.y - 25)
	draw_line(origin, origin + Vector2(span, 0), Color("#574d35"), 2, true)
	for i in range(3):
		var at := origin + Vector2(span * i / 2.0, 0)
		draw_line(at + Vector2(0, -4), at + Vector2(0, 3), Color("#574d35"), 1, true)
		draw_string(_font, at + Vector2(-3, -7), str(i * 200) + (" m" if i == 2 else ""), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#65563c"))


func _draw_mine() -> void:
	var card := StyleBoxFlat.new()
	card.bg_color = Color("#292f3d", 0.96)
	card.border_color = Color("#7e8293")
	card.set_border_width_all(2)
	card.set_corner_radius_all(14)
	draw_style_box(card, Rect2(Vector2.ZERO, size))
	draw_string(_font, Vector2(16, 28), "矿场 %02d / 10" % navigation["depth"], HORIZONTAL_ALIGNMENT_LEFT, -1, 20 if expanded else 15, Color("#e7d7b1"))
	draw_string(_font, Vector2(size.x - (145 if expanded else 62), 28), "M / Esc 收起" if expanded else "M 展开", HORIZONTAL_ALIGNMENT_LEFT, -1, 14 if expanded else 11, Color("#a2aebd"))
	for cell: Vector2i in navigation["cells"]:
		var world := MineLayout.center(cell)
		var a := _point(Vector2(world.x, world.z) - Vector2.ONE)
		var b := _point(Vector2(world.x, world.z) + Vector2.ONE)
		draw_rect(Rect2(a, b - a + Vector2.ONE * 0.3), Color("#777781"))
	for ore: Vector2 in navigation["ores"]:
		draw_circle(_point(ore), 3.4 if expanded else 1.5, Color("#b9a684"))
	for enemy: Vector2 in navigation["enemies"]:
		draw_circle(_point(enemy), 4.2 if expanded else 2.1, Color("#de8d88"))
	for entry in [{"at": navigation["up"], "label": "上行梯", "color": Color("#e9d4a0")}, {"at": navigation["down"], "label": "宝箱" if navigation["depth"] == 10 else ("下行梯" if navigation["descent_open"] else "裂隙岩石"), "color": Color("#ccb3ed")}]:
		var pos: Vector3 = entry["at"]
		var point := _point(Vector2(pos.x, pos.z))
		draw_rect(Rect2(point - Vector2.ONE * 4, Vector2.ONE * 8), entry["color"])
		if expanded:
			draw_string(_font, point + Vector2(9, 5), entry["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, entry["color"])
	if navigation["checkpoint"]:
		var lift: Vector3 = navigation["lift"]
		var point := _point(Vector2(lift.x, lift.z))
		draw_circle(point, 5.0 if expanded else 2.8, Color("#8ccccb"))
		if expanded:
			draw_string(_font, point + Vector2(9, 5), "升降机", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("#8ccccb"))
	var marker := _point(player_position)
	draw_circle(marker, 6.5 if expanded else 4.2, Color("#faf0d3"))
	draw_circle(marker, 3.7 if expanded else 2.4, Color("#e8b05f"))
	if expanded:
		draw_string(_font, Vector2(24, size.y - 21), "红点：怪物    浅棕：矿石    金色：你的位置    蓝绿：升降机", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("#c9c4b6"))
