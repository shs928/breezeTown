extends RefCounted
## 原创乡镇建筑；沿用农舍的石基、木构、瓦片和门窗比例。
## 建筑的正面统一朝 +Z，入口留在正面中央或左侧。

const M = preload("res://scripts/art/art_mesh.gd")
const B = preload("res://scripts/art/building_models.gd")
const L = preload("res://scripts/art/landscape_models.gd")

const STYLES := {
	"school": {"size":Vector2(8.0,5.8),"eave":3.8,"peak":5.8,"wall":"#e6dfc3","roof":"#58778c","label":"微风学校"},
	"hall": {"size": Vector2(9.0, 6.0), "eave": 4.0, "peak": 6.1, "wall": "#eee0b9", "roof": "#aa715b", "label": "微风镇公所"},
	"clinic": {"size": Vector2(6.0, 4.8), "eave": 3.2, "peak": 4.9, "wall": "#eee8cc", "roof": "#689687", "label": "柳荫诊所"},
	"smith": {"size": Vector2(6.4, 4.8), "eave": 3.1, "peak": 4.7, "wall": "#b8afa0", "roof": "#5c716d", "label": "山石铁匠铺"},
	"carpenter": {"size": Vector2(6.8, 5.2), "eave": 3.3, "peak": 5.1, "wall": "#caa47a", "roof": "#71895c", "label": "松木工坊"},
	"inn": {"size": Vector2(7.8, 5.8), "eave": 5.4, "peak": 7.0, "wall": "#ecd6ad", "roof": "#996951", "label": "晚风旅店"},
	"bakery": {"size": Vector2(5.8, 4.6), "eave": 3.2, "peak": 4.8, "wall": "#edd1af", "roof": "#b97c65", "label": "麦香面包房"},
	"library": {"size": Vector2(7.2, 5.4), "eave": 3.6, "peak": 5.5, "wall": "#ced2b0", "roof": "#557f80", "label": "小镇图书馆"},
	"home_a": {"size": Vector2(4.8, 4.2), "eave": 2.9, "peak": 4.6, "wall": "#eed9b4", "roof": "#9d7568", "label": "橡树小屋"},
	"home_b": {"size": Vector2(5.2, 4.4), "eave": 3.2, "peak": 4.8, "wall": "#d7dfbe", "roof": "#638689", "label": "薄荷小屋"},
	"home_c": {"size": Vector2(4.6, 4.0), "eave": 2.8, "peak": 4.4, "wall": "#e6c5aa", "roof": "#8a8295", "label": "花篱小屋"},
}


static func building(kind: String) -> Node3D:
	if kind == "windmill":
		return windmill()
	var spec: Dictionary = STYLES[kind]
	var size: Vector2 = spec["size"]
	var eave: float = spec["eave"]
	var peak: float = spec["peak"]
	var root := Node3D.new()
	root.name = "Town_" + kind
	root.set_meta("main_footprint_m", size)
	var palette := B._palette()
	palette["plaster"] = B._material(kind + "_plaster", Color(spec["wall"]))
	palette["plaster_light"] = B._material(kind + "_gable", Color(spec["wall"]).lightened(0.07))
	B._house_shell(root, size.x, size.y, eave, peak, palette)
	var roof := Color(spec["roof"])
	B._tiled_roof(root, size.x * 0.5 + 0.3, size.y * 0.5 + 0.3, eave + 0.04, peak + 0.05, [roof, roof.lightened(0.08), roof.darkened(0.07), roof.lightened(0.14)], palette)
	var front := size.y * 0.5 + 0.045
	var door_x := -size.x * 0.22 if kind in ["bakery", "smith", "carpenter"] else 0.0
	B._door(root, Vector3(door_x, 0.27, front), 1.0 if kind != "hall" else 1.4, 2.05, palette)
	M.box(root, Vector3(door_x, 0.09, front + 0.47), Vector3(1.85, 0.18, 1.05), "#b1a68c", "EntryStep", 0.07)
	if door_x == 0.0:
		for side in [-1.0, 1.0]:
			B._front_window(root, "FrontWindow", Vector3(side * size.x * 0.30, 1.62, front), 1.12, 1.24, palette, kind.begins_with("home") or kind == "clinic")
	else:
		B._front_window(root, "DisplayWindow", Vector3(size.x * 0.21, 1.65, front), 1.90, 1.30, palette, false)
	for side in [-1.0, 1.0]:
		var window := Node3D.new()
		window.position = Vector3(side * (size.x * 0.5 + 0.035), 1.65, -0.65)
		window.rotation.y = side * PI * 0.5
		root.add_child(window)
		B._front_window(window, "SideWindow", Vector3.ZERO, 1.05, 1.12, palette, false)
	B._round_attic_window(root, Vector3(0, eave + (peak - eave) * 0.38, front), 0.29, palette)
	B._lantern(root, Vector3(door_x + 0.83, 2.0, front + 0.08), palette)
	B._chimney(root, Vector3(size.x * 0.28, eave + 0.36, -size.y * 0.22), palette)
	if kind.begins_with("home"):
		B._portrait_porch(root, Vector3(0, 0, front), palette)
		B._flower_pot(root, Vector3(-size.x * 0.40, 0, front + 0.65), 1.0, palette)
		M.box(root, Vector3(size.x * 0.45, 0.54, front + 1.25), Vector3(0.10, 1.10, 0.10), "#8e7050", "MailboxPost")
		M.box(root, Vector3(size.x * 0.45, 1.13, front + 1.25), Vector3(0.5, 0.34, 0.34), spec["roof"], "Mailbox", 0.09)
	else:
		var sign_y := 3.42 if kind == "hall" else (2.65 if kind == "inn" else 2.78)
		signboard(root, spec["label"], Vector3(0, sign_y, front + 0.16), minf(size.x - 1.2, 3.7))
	match kind:
		"hall":
			_clock_tower(root, palette)
			for side in [-1.0, 1.0]:
				M.box(root, Vector3(side * 1.28, 1.35, front + 0.75), Vector3(0.20, 2.55, 0.20), "#e9dbb5", "PorticoColumn")
			M.box(root, Vector3(0, 2.64, front + 0.64), Vector3(3.1, 0.18, 1.4), "#aa715b", "PorticoRoof")
		"clinic":
			M.box(root, Vector3(-2.22, 2.62, front + 0.24), Vector3(0.23, 0.72, 0.10), "#548f77", "ClinicCross")
			M.box(root, Vector3(-2.22, 2.62, front + 0.25), Vector3(0.70, 0.23, 0.11), "#548f77", "ClinicCrossbar")
		"inn":
			for x in [-2.4, 0.0, 2.4]:
				B._front_window(root, "UpstairsWindow", Vector3(x, 4.1, front), 1.03, 1.27, palette, true)
			M.box(root, Vector3(0, 3.16, front + 0.57), Vector3(6.5, 0.18, 1.18), "#aa855c", "BalconyFloor")
			for i in range(13):
				M.box(root, Vector3(-3.1 + i * 0.52, 3.53, front + 1.05), Vector3(0.08, 0.74, 0.08), "#7e6047", "Balustrade")
			M.box(root, Vector3(0, 3.90, front + 1.05), Vector3(6.6, 0.10, 0.13), "#d0ab78", "BalconyRail")
		"bakery":
			B._striped_awning(root, Vector3(1.02, 0, front), 2.6, palette)
			M.box(root, Vector3(1.05, 0.7, front + 1.05), Vector3(2.3, 0.12, 0.65), "#a98054", "BreadCounter")
			for i in range(5):
				M.ellipsoid(root, Vector3(0.22 + i * 0.42, 0.88, front + 1.05), Vector3(0.17, 0.16, 0.25), "#d9ad65", "BreadLoaf", 12, 6)
		"smith", "carpenter":
			_work_yard(root, kind, size)
		"library":
			for i in range(3):
				var book := M.box(root, Vector3(-0.30 + i * 0.28, 4.38, front + 0.15), Vector3(0.22, 0.56, 0.12), ["#a97956", "#688b80", "#c6ac6d"][i], "BookEmblem")
				book.rotation.z = -0.14 if i == 2 else 0.0
	return root


static func _clock_tower(root: Node3D, palette: Dictionary) -> void:
	M.box(root, Vector3(0, 6.25, -0.3), Vector3(1.6, 2.4, 1.6), "#dfcba6", "ClockTower")
	var cap := M.cylinder(root, Vector3(0, 7.85, -0.3), 1.35, 0.06, 1.3, "#719084", "TowerRoof", 4)
	cap.rotation.y = PI * 0.25
	var clock := M.cylinder(root, Vector3(0, 6.76, 0.54), 0.55, 0.55, 0.1, "#f4e7c3", "ClockFace", 32)
	clock.rotation.x = PI * 0.5
	M.beam(root, Vector3(0, 6.76, 0.61), Vector3(-0.27, 6.98, 0.61), 0.055, "#576257", "HourHand")
	M.beam(root, Vector3(0, 6.76, 0.62), Vector3(0, 7.16, 0.62), 0.045, "#576257", "MinuteHand")
	for i in range(12):
		var angle := i * TAU / 12.0
		M.ellipsoid(root, Vector3(sin(angle) * 0.43, 6.76 + cos(angle) * 0.43, 0.61), Vector3(0.027, 0.027, 0.015), "#7d795e", "ClockHour", 6, 3)


static func _work_yard(root: Node3D, kind: String, size: Vector2) -> void:
	var x := size.x * 0.5 + 1.65
	var canopy := M.box(root, Vector3(x, 2.58, 0.7), Vector3(3.5, 0.14, 3.8), "#6e8271", "WorkshopCanopy")
	canopy.rotation.z = -0.12
	for z in [-0.9, 2.3]:
		M.box(root, Vector3(x + 1.45, 1.2, z), Vector3(0.17, 2.4, 0.17), "#92704c", "CanopyPost")
	M.box(root, Vector3(x, 0.65, 0.0), Vector3(2.2, 0.22, 0.88), "#9c7950", "WorkBench")
	for side in [-1.0, 1.0]:
		M.box(root, Vector3(x + side * 0.85, 0.31, 0), Vector3(0.19, 0.64, 0.7), "#70583f", "BenchLeg")
	if kind == "smith":
		M.box(root, Vector3(x, 0.95, 0), Vector3(1.0, 0.22, 0.48), "#545e5b", "AnvilTop")
		M.box(root, Vector3(x, 0.82, 0), Vector3(0.42, 0.30, 0.32), "#626e69", "AnvilWaist")
		M.box(root, Vector3(x, 0.26, -1.32), Vector3(2.6, 0.52, 0.72), "#968879", "ForgeHearth")
		for i in range(5):
			M.ellipsoid(root, Vector3(x - 0.75 + i * 0.36, 0.57, -1.3), Vector3(0.20, 0.12, 0.21), "#554b41", "Coal", 8, 4)
	else:
		for i in range(5):
			var log := M.cylinder(root, Vector3(x - 1.0 + (i % 3) * 0.62, 0.28 + (i / 3) * 0.52, 1.52), 0.28, 0.26, 2.2, "#b69363", "CutLumber", 12)
			log.rotation.x = PI * 0.5
		M.box(root, Vector3(x, 0.83, 0), Vector3(1.8, 0.08, 0.38), "#d1b184", "UnfinishedPlank")


static func windmill() -> Node3D:
	var root := Node3D.new()
	root.name = "MeadowWindmill"
	M.cylinder(root, Vector3(0, 3.0, 0), 2.0, 1.15, 6.0, "#ded2ae", "MillTower", 8)
	M.cylinder(root, Vector3(0, 6.4, 0), 1.6, 0.05, 1.7, "#8b7365", "MillCap", 8)
	var palette := B._palette()
	B._door(root, Vector3(0, 0.06, 1.92), 0.85, 1.85, palette)
	var sails := Node3D.new()
	sails.position = Vector3(0, 4.8, 1.58)
	sails.rotation.z = 0.42
	root.add_child(sails)
	for i in range(4):
		var blade := Node3D.new()
		blade.rotation.z = i * PI * 0.5
		sails.add_child(blade)
		M.box(blade, Vector3(0, 1.7, 0), Vector3(0.13, 3.8, 0.16), "#80674a", "SailSpar")
		M.box(blade, Vector3(0.34, 2.45, 0.03), Vector3(0.77, 1.9, 0.07), "#ede0b9", "LinenSail")
		for slat in range(5):
			M.box(blade, Vector3(0.34, 1.55 + slat * 0.44, 0.08), Vector3(0.87, 0.045, 0.045), "#b89b72", "SailBatten")
	M.ellipsoid(sails, Vector3(0, 0, 0.11), Vector3(0.24, 0.24, 0.16), "#6c6352", "SailHub", 12, 6)
	signboard(root, "山谷风车", Vector3(0, 2.45, 1.9), 2.0)
	return root


static func signboard(root: Node3D, title: String, at: Vector3, width: float = 3.0) -> void:
	M.box(root, at, Vector3(width, 0.52, 0.12), "#765f46", "WoodenSign", 0.045)
	M.box(root, at + Vector3(0, 0, 0.065), Vector3(width - 0.13, 0.39, 0.035), "#8d7350", "SignInset", 0.025)
	var label := Label3D.new()
	label.font = preload("res://resources/ui_font.tres")
	label.text = title
	label.font_size = 48
	label.pixel_size = minf(0.009, (width - 0.22) / maxf(1, title.length()) / 48.0)
	label.modulate = Color("#f5e6be")
	label.outline_size = 0
	label.position = at + Vector3(0, 0, 0.092)
	root.add_child(label)


static func bench() -> Node3D:
	var root := Node3D.new()
	root.name = "TownBench"
	for i in range(3):
		M.box(root, Vector3(0, 0.47, -0.20 + i * 0.19), Vector3(1.9, 0.09, 0.16), "#b89464", "SeatSlat")
	for x in [-0.73, 0.73]:
		M.box(root, Vector3(x, 0.23, 0), Vector3(0.12, 0.47, 0.55), "#647466", "BenchLeg")
		M.box(root, Vector3(x, 0.75, -0.28), Vector3(0.08, 0.80, 0.08), "#647466", "BackUpright")
	for y in [0.81, 1.04]:
		M.box(root, Vector3(0, y, -0.28), Vector3(1.9, 0.16, 0.08), "#c5a575", "BackSlat")
	return root


static func noticeboard() -> Node3D:
	var root := Node3D.new()
	root.name = "VillageNoticeboard"
	for x in [-0.9, 0.9]:
		M.box(root, Vector3(x, 1.12, 0), Vector3(0.16, 2.25, 0.16), "#9c7e55", "BoardPost")
	M.box(root, Vector3(0, 1.57, 0), Vector3(2.10, 1.12, 0.12), "#876947", "NoticeBoard")
	M.box(root, Vector3(0, 2.22, 0), Vector3(2.4, 0.16, 0.7), "#64857a", "BoardRoof")
	for i in range(3):
		var paper := M.box(root, Vector3(-0.58 + i * 0.57, 1.53, 0.08), Vector3(0.42, 0.66, 0.02), ["#e9dcae", "#dbb784", "#efe5c8"][i], "PinnedNotice", 0.01)
		paper.rotation.z = (i - 1) * 0.08
		for line in range(3):
			M.box(root, Vector3(-0.58 + i * 0.57, 1.62 - line * 0.13, 0.096), Vector3(0.26, 0.022, 0.01), "#a6a082", "NoticeWriting", 0)
	return root
