extends RefCounted
## V2 微风山谷的唯一地图定义。只包含值类型，不读取模型、不创建场景节点。
## 平面坐标为 (世界 X, 世界 Z)，道路、入口、河岸和导览图共用同一份数据。


static func create() -> Dictionary:
	var river := PackedVector2Array([
		Vector2(16, -84), Vector2(16, -67), Vector2(10, -58), Vector2(-6, -48),
		Vector2(-12, -32), Vector2(-7, -20), Vector2(3, -8), Vector2(3, 12),
		Vector2(-1, 29), Vector2(-6, 42), Vector2(-5, 59), Vector2(-11, 84),
	])
	var farm_brook := PackedVector2Array([Vector2(-14,-8),Vector2(-12,-4),Vector2(-10,1),Vector2(-9,10),Vector2(-10,21),Vector2(-7,30),Vector2(-6,42)])
	var tributary := PackedVector2Array([Vector2(-6, 42), Vector2(6, 43), Vector2(16, 45), Vector2(26, 45)])
	var lake_center := Vector2(43, 49)
	var lake_radius := Vector2(25, 22)
	var buildings := [
		_building("cottage", "cottage", "农舍", Vector2(-30, -4), Vector2(8.0, 7.0), Vector2(-28.76, 2.8)),
		_building("shop", "shop", "种子商店", Vector2(22, -18), Vector2(5.0, 4.0), Vector2(20.55, -14.8)),
		_building("barn", "barn", "谷仓", Vector2(20, 0), Vector2(7.2, 5.8), Vector2(20.8, 3.6)),
		_building("coop", "coop", "鸡舍", Vector2(32, 0.6), Vector2(3.1, 2.6), Vector2(32.6, 3.1)),
		_building("hall", "hall", "镇公所", Vector2(34, -56), Vector2(9.3, 6.2), Vector2(34, -51.8)),
		_building("clinic", "clinic", "诊所", Vector2(18, -49), Vector2(6.3, 5.0), Vector2(18, -45.4)),
		_building("library", "library", "图书馆", Vector2(52, -55), Vector2(7.5, 5.6), Vector2(52, -51.1)),
		_building("inn", "inn", "旅店", Vector2(67, -41), Vector2(8.1, 6.0), Vector2(67, -36.9)),
		_building("bakery", "bakery", "面包房", Vector2(18, -32), Vector2(6.1, 4.8), Vector2(16.724, -28.5)),
		_building("smith", "smith", "铁匠铺", Vector2(50, -29), Vector2(6.7, 5.0), Vector2(48.592, -25.4)),
		_building("carpenter", "carpenter", "木工坊", Vector2(-54, -31), Vector2(7.1, 5.4), Vector2(-55.496, -27.2)),
		_building("home_oak", "home_a", "橡树小屋", Vector2(67, -59), Vector2(5.1, 4.4), Vector2(67, -55.7)),
		_building("home_mint", "home_b", "薄荷小屋", Vector2(78, -25), Vector2(5.5, 4.6), Vector2(78, -21.6)),
		_building("home_flower", "home_c", "花篱小屋", Vector2(64, -12), Vector2(4.9, 4.2), Vector2(64, -8.8)),
		_building("home_lake", "home_a", "湖畔人家", Vector2(42, -11), Vector2(5.1, 4.4), Vector2(42, -7.7)),
		_building("forest_cabin", "home_b", "林间小屋", Vector2(-60, -55), Vector2(5.5, 4.6), Vector2(-60, -51.6)),
		_building("windmill", "windmill", "风车", Vector2(-57, 18), Vector2(4.5, 4.4), Vector2(-57, 21.3)),
	]
	var roads := [
		_road("town_approach", [Vector2(-66, -40), Vector2(-24, -40), Vector2(-9, -40), Vector2(9, -40), Vector2(35, -40), Vector2(57, -40)], 3.6, true),
		_road("town_axis", [Vector2(34, -51.8), Vector2(34, -40), Vector2(34, -24), Vector2(35, -18)], 3.2, true),
		_road("clinic_entry", [Vector2(18, -45.4), Vector2(18, -40)], 2.0, true),
		_road("library_entry", [Vector2(52, -51.1), Vector2(52, -46), Vector2(45, -46)], 2.1, true),
		_road("inn_entry", [Vector2(57, -40), Vector2(57, -35), Vector2(67, -35), Vector2(67, -36.9)], 2.2, true),
		_road("bakery_entry", [Vector2(18, -40), Vector2(11, -40), Vector2(11, -25), Vector2(16.724, -25), Vector2(16.724, -28.5)], 2.1),
		_road("smith_entry", [Vector2(34, -24), Vector2(48.592, -24), Vector2(48.592, -25.4)], 2.1),
		_road("town_market", [Vector2(11, -25), Vector2(8, -22), Vector2(10, -13), Vector2(20.55, -13), Vector2(20.55, -14.8)], 2.4),
		_road("farm_market", [Vector2(-28.76, 2.8), Vector2(-23, 0.8), Vector2(-16, -13), Vector2(-1.1667,-13), Vector2(10,-13)], 2.6),
		_road("west_riverbank", [Vector2(-18, -13), Vector2(-16, -4), Vector2(-15, 10), Vector2(-16, 20), Vector2(-12, 29)], 2.2),
		_road("farm_east_gate", [Vector2(-17, 10), Vector2(-9, 10), Vector2(-4, 10)], 2.0),
		_road("farm_loop", [Vector2(-28.76, 2.8), Vector2(-28.76, 3.3), Vector2(-46, 1.1), Vector2(-49, 9), Vector2(-49, 26), Vector2(-46, 33), Vector2(-26, 33), Vector2(-26, 27)], 2.2),
		_road("windmill_entry", [Vector2(-49, 24), Vector2(-57, 24), Vector2(-57, 21.3)], 2.0),
		_road("carpenter_entry", [Vector2(-66, -40), Vector2(-66, -24), Vector2(-55.496, -24), Vector2(-55.496, -27.2)], 2.0),
		_road("farm_carpenter", [Vector2(-46, -6), Vector2(-50, -18), Vector2(-55.496, -24)], 2.0),
		_road("forest_cabin_entry", [Vector2(-60, -51.6), Vector2(-60, -40)], 2.0),
		_road("ranch_bridge", [Vector2(-26, 33), Vector2(-10, 33), Vector2(-10, 29), Vector2(-1, 29), Vector2(8, 29), Vector2(23.5, 27), Vector2(23.5, 23)], 2.5),
		_road("ranch_entry", [Vector2(10, -13), Vector2(9, 3), Vector2(20.8, 3.6)], 2.1),
		_road("ranch_west_edge", [Vector2(9, 3), Vector2(8, 16), Vector2(8, 29)], 2.1),
		_road("ranch_town", [Vector2(23.5, 27), Vector2(39, 25), Vector2(45, 20), Vector2(45, 3), Vector2(35, -4), Vector2(35, -18), Vector2(34, -24)], 2.3),
		_road("homes_north", [Vector2(52, -46), Vector2(58, -49), Vector2(67, -50), Vector2(67, -55.7)], 2.0),
		_road("homes_east", [Vector2(67, -35), Vector2(73, -33), Vector2(73, -18), Vector2(78, -18), Vector2(78, -21.6)], 2.0),
		_road("homes_south", [Vector2(45, 3), Vector2(56, 0), Vector2(64, -5), Vector2(73, -18)], 2.0),
		_road("home_flower_entry", [Vector2(64, -5), Vector2(64, -8.8)], 1.8),
		_road("home_lake_entry", [Vector2(35, -4), Vector2(42, -4), Vector2(42, -7.7)], 1.8),
		_road("lake_east_trail", [Vector2(56, 0), Vector2(73, 12), Vector2(77, 35), Vector2(75, 55), Vector2(68, 68)], 1.8),
		_road("south_meadow", [Vector2(-46, 33), Vector2(-38, 49), Vector2(-20, 55), Vector2(-18, 63), Vector2(-5.96, 63), Vector2(3, 63), Vector2(7, 53)], 2.0),
		_road("woodland_loop", [Vector2(-66, -40), Vector2(-74, -22), Vector2(-72, 9), Vector2(-67, 33), Vector2(-52, 51), Vector2(-38, 49)], 1.8),
		_road("north_woodland", [Vector2(-60, -51.6), Vector2(-60, -48), Vector2(-66, -48), Vector2(-71, -59), Vector2(-52, -64), Vector2(-29, -63)], 1.7),
		_road("mine_entry", [Vector2(-29, -63), Vector2(-29, -70.6)], 2.4),
		_road("mine_town", [Vector2(-24, -40), Vector2(-24, -57), Vector2(-29, -63)], 2.0),
	]
	return {
		"id": "breeze_valley", "revision": 4,
		"bounds": {"half": Vector2(96, 80), "pow": 6},
		"farm": Rect2(-44, 2, 29, 27), "ranch": Rect2(9, -4, 29, 29),
		"pasture": Rect2(12, 6, 23, 17), "square": Rect2(25, -49, 20, 18),
		"lake_center": lake_center, "lake_radius": lake_radius,
		"landmarks": {
			"shop_door": Vector3(20.55, 0, -14.8), "cottage_door": Vector3(-28.76, 0, 2.8),
			"spawn": Vector3(-27, 0, 11), "trough": Vector3(23.5, 0, 22),
			"town_square": Vector3(35, 0, -40), "mine_door": Vector3(-29, 0, -70.6),
			"waterfall": Vector3(16, 0, -77), "lake_view": Vector3(7, 0, 53),
		},
		"buildings": buildings, "roads": roads,
		"waters": [
			{"id": "willow_brook", "kind": "river", "polygon": _ribbon(farm_brook,1.7), "points": farm_brook, "width": 3.4},
			{"id": "breeze_river", "kind": "river", "polygon": _ribbon(river, 3.0), "points": river, "width": 6.0},
			{"id": "lake_channel", "kind": "river", "polygon": _ribbon(tributary, 2.2), "points": tributary, "width": 4.4},
			{"id": "moon_lake", "kind": "lake", "polygon": _ellipse(lake_center, lake_radius), "center": lake_center, "radius": lake_radius},
		],
		"bridges": [
			{"id": "farm_stone_bridge", "rect": Rect2(-14,7.5,10,4.4), "axis":"x", "stone":true, "rise":0.52},
			{"id": "town_bridge", "rect": Rect2(-16, -42.5, 14, 5), "axis": "x"},
			{"id": "market_bridge", "rect": Rect2(-8.1667, -15.5, 14, 5), "axis": "x"},
			{"id": "ranch_bridge", "rect": Rect2(-8, 26.5, 14, 5), "axis": "x"},
			{"id": "meadow_bridge", "rect": Rect2(-12.96, 60.5, 14, 5), "axis": "x"},
		],
		"docks": [],
		"ramps": [{"rect":Rect2(-29.9,.3,3.4,2.5),"rise":.62,"axis":"-z"}],
		"forests": [
			{"id": "west_pines", "rect": Rect2(-89, -61, 24, 103), "color": "#65865e"},
			{"id": "north_pines", "rect": Rect2(-72, -74, 62, 13), "color": "#597c5b"},
			{"id": "east_pines", "rect": Rect2(78, -12, 14, 63), "color": "#638859"},
		],
		"regions": [
			_region("farm", "向阳农场", Vector2(-26, 16), Rect2(-49, -22, 44, 55), "#a6b76f"),
			_region("ranch", "微风牧场", Vector2(24, 14), Rect2(9, -4, 29, 29), "#bac987"),
			_region("town", "微风镇", Vector2(36, -39), Rect2(10, -63, 49, 39), "#d4bd93"),
			_region("homes", "花篱住宅街", Vector2(65, -23), Rect2(38, -65, 47, 63), "#a5ba83"),
			_region("forest", "松语森林", Vector2(-66, -12), Rect2(-88, -65, 28, 97), "#668b67"),
			_region("orchard", "西风果园", Vector2(-53, 44), Rect2(-65, 34, 25, 21), "#a4b26e"),
			_region("meadow", "溪畔草甸", Vector2(-23, 56), Rect2(-39, 36, 33, 33), "#a7bb82"),
			_region("lake", "月湾湖", lake_center, Rect2(lake_center - lake_radius, lake_radius * 2), "#66b1be"),
			_region("mine", "星辉矿场", Vector2(-29, -73), Rect2(-38, -79, 18, 15), "#989e98"),
		],
		"reserved": [Rect2(-44, 2, 29, 27), Rect2(9, -4, 29, 29), Rect2(25, -49, 20, 18), Rect2(-65, 34, 25, 21), Rect2(-38, -79, 18, 15)],
		"resource_zones": [
			{"id": "orchard", "category": "tree", "species": "apple", "rect": Rect2(-65, 34, 25, 21)},
			{"id": "woodland", "category": "tree", "species": "pine", "rect": Rect2(-88, -65, 24, 97)},
			{"id": "starter_grove", "category": "tree", "species": "oak", "rect": Rect2(-33, 35, 20, 15)},
		],
	}


static func _building(id: String, kind: String, label: String, at: Vector2, size: Vector2, door: Vector2) -> Dictionary:
	return {"id": id, "kind": kind, "label": label, "position": at, "size": size, "door": door}


static func _road(id: String, points: Array, width: float, paved: bool = false) -> Dictionary:
	var rounded:Array=[]
	rounded.append(points[0])
	for i in range(1,points.size()-1):
		var corner:Vector2=points[i]
		var previous:Vector2=points[i-1]
		var next:Vector2=points[i+1]
		var radius:=minf(width*.42,minf(corner.distance_to(previous),corner.distance_to(next))*.22)
		var a:=corner.move_toward(previous,radius)
		var b:=corner.move_toward(next,radius)
		for j in range(5):
			var t:=j/4.0
			rounded.append(a.lerp(corner,t).lerp(corner.lerp(b,t),t))
	rounded.append(points[-1])
	return {"id": id, "points": rounded, "width": width, "paved": paved}


static func _region(id: String, label: String, at: Vector2, rect: Rect2, color: String) -> Dictionary:
	return {"id": id, "label": label, "position": at, "rect": rect, "color": color}


static func _ribbon(points: PackedVector2Array, half_width: float) -> PackedVector2Array:
	var polygons := Geometry2D.offset_polyline(points, half_width, Geometry2D.JOIN_ROUND, Geometry2D.END_SQUARE)
	return polygons[0] if not polygons.is_empty() else PackedVector2Array()


static func _ellipse(center: Vector2, radius: Vector2) -> PackedVector2Array:
	var polygon := PackedVector2Array()
	for i in range(80):
		var angle := i * TAU / 80.0
		var wave := 1.0 + sin(angle * 5.0) * 0.025 + cos(angle * 9.0) * 0.012
		polygon.append(center + Vector2(cos(angle), sin(angle)) * radius * wave)
	return polygon
