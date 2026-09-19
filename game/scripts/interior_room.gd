extends Node3D
## INDOOR-01：室内房间视图（PRD 第 26 节 Interior）。布局来自 data/interior_db.gd，
## 本类负责把规格构建成房间：地板/墙体/家具/碰撞/服务点聚焦环与目标解析。
## 房间无天花板（俯视相机需要），室外天空色即室内环境光。第一轮无房间状态，不进存档。

const DB := preload("res://scripts/data/interior_db.gd")
const M := preload("res://scripts/art/art_mesh.gd")

const WALL_HEIGHT := 3.1
const LOW_WALL_HEIGHT := 0.9  # 南/东矮墙：东南俯视相机不被遮挡，角色始终可见
const WALL_COLOR := "#e8dcc4"
const WAINSWALL_COLOR := "#b98d5f"
const FLOOR_COLOR := "#a97e52"
const DOOR_WIDTH := 1.6

var id := ""
var label := ""
var spec: Dictionary = {}
var hint_provider := Callable()  # main 注入：func(room_id, machine_kind) -> String
var _focus_ring: MeshInstance3D
var _machine_props := {}  # kind -> {"output": MeshInstance3D}


func setup(room_id: String) -> void:
	id = room_id
	spec = DB.entry(room_id)
	label = spec["label"]


func _ready() -> void:
	var size: Vector2 = spec["size"]
	_build_floor(size)
	_build_walls(size)
	_build_furniture()
	_build_machines()
	_build_collision(size)
	_focus_ring = M.torus(self, Vector3.ZERO, 0.82, 0.03, "#edcf82", "InteriorFocus")
	_focus_ring.visible = false
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0, WALL_HEIGHT - 0.5, 0)
	lamp.light_color = Color("#ffd9a0")
	lamp.light_energy = 0.85
	lamp.omni_range = maxf(size.x, size.y) * 1.1
	lamp.omni_attenuation = 1.4
	lamp.shadow_enabled = false
	add_child(lamp)


func _build_floor(size: Vector2) -> void:
	M.box(self, Vector3(0, 0.05, 0), Vector3(size.x, 0.1, size.y), FLOOR_COLOR, "InteriorFloor", 0)
	# 木板缝：沿 x 的深色细条，让地板在俯视相机下有方向感。
	var planks := int(size.y / 1.1)
	for i in range(1, planks):
		M.box(self, Vector3(0, 0.102, -size.y * 0.5 + i * size.y / planks), Vector3(size.x, 0.004, 0.06), "#8a6240", "FloorSeam", 0)
	M.box(self, Vector3(0, 0.11, spec["exit"].z - 0.55), Vector3(1.9, 0.02, 1.1), "#c9a06a", "EntryMat", 0)


func _build_walls(size: Vector2) -> void:
	var half := size * 0.5
	# 北墙（z-）与西墙（x-）整高；南墙（z+，留门口）与东墙（x+）做矮墙——
	# 相机固定从东南俯视，矮墙保证角色和家具不被墙面挡住。
	_wall_run(Vector3(-half.x, 0, -half.y), Vector3(half.x, 0, -half.y), size, WALL_HEIGHT)
	_wall_run(Vector3(-half.x, 0, -half.y), Vector3(-half.x, 0, half.y), size, WALL_HEIGHT)
	_wall_run(Vector3(half.x, 0, -half.y + 2.2), Vector3(half.x, 0, half.y - 2.2), size, LOW_WALL_HEIGHT)
	_wall_run(Vector3(-half.x, 0, half.y), Vector3(-DOOR_WIDTH * 0.5 - 0.5, 0, half.y), size, LOW_WALL_HEIGHT)
	_wall_run(Vector3(DOOR_WIDTH * 0.5 + 0.5, 0, half.y), Vector3(half.x, 0, half.y), size, LOW_WALL_HEIGHT)
	# 门框柱。
	M.box(self, Vector3(-DOOR_WIDTH * 0.5 - 0.25, 1.4, half.y), Vector3(0.5, 2.8, 0.5), "#8a6240", "DoorPost")
	M.box(self, Vector3(DOOR_WIDTH * 0.5 + 0.25, 1.4, half.y), Vector3(0.5, 2.8, 0.5), "#8a6240", "DoorPost")
	M.box(self, Vector3(0, 2.95, half.y), Vector3(DOOR_WIDTH + 0.5, 0.5, 0.5), "#8a6240", "DoorLintel")


func _wall_run(from: Vector3, to: Vector3, size: Vector2, height: float = WALL_HEIGHT) -> void:
	var length := from.distance_to(to)
	if length < 0.05:
		return
	var center := (from + to) * 0.5
	var horizontal := absf(to.x - from.x) > absf(to.z - from.z)
	var wall_size := Vector3(length, height, 0.35) if horizontal else Vector3(0.35, height, length)
	M.box(self, center + Vector3(0, height * 0.5, 0), wall_size, WALL_COLOR, "InteriorWall", 0.05)
	# 墙裙：给墙面一条木色腰线；长短轴按墙的朝向取，避免腰线伸出墙头。
	var skirt := Vector3(length * 1.02, 0.22, 0.56) if horizontal else Vector3(0.56, 0.22, length * 1.02)
	M.box(self, center + Vector3(0, 0.44, 0), skirt, WAINSWALL_COLOR, "WallSkirt", 0)


func _build_furniture() -> void:
	match String(spec["style"]):
		"home":
			_bed(Vector3(-3.4, 0, -1.9))
			_table(Vector3(2.6, 0, -2.2), 1.6)
			_fireplace(Vector3(2.9, 0, -3.6))
			_rug(Vector3(0.4, 0, 0.4), 2.6, 1.8)
		"shop":
			_counter(Vector3(0, 0, -1.6), 4.6)
			_shelf_row(Vector3(-3.4, 0, -3.6), 3)
			_shelf_row(Vector3(3.4, 0, -3.6), 3)
			_crate_stack(Vector3(4.6, 0, 0.4))
		"inn":
			_counter(Vector3(-3.6, 0, -2.2), 3.6, "#7c5a8a")
			_table(Vector3(2.6, 0, -1.6), 1.7)
			_table(Vector3(3.4, 0, 1.6), 1.7)
			_table(Vector3(-2.4, 0, 1.8), 1.7)
			_rug(Vector3(0, 0, 0), 3.0, 2.0)
		"clinic":
			_bed(Vector3(-3.4, 0, -2.0), "#e9e4da", "#bcd8d2")
			_bed(Vector3(3.4, 0, -2.0), "#e9e4da", "#bcd8d2")
			_cabinet(Vector3(0, 0, -3.7))
			_rug(Vector3(0, 0, 0.8), 2.4, 1.6)
		"smith":
			_anvil(Vector3(-0.4, 0, -2.4))
			_coal_pile(Vector3(0.8, 0, -3.6))
			_barrel(Vector3(-5.0, 0, -3.4))
			_weapon_rack(Vector3(0.4, 0, -3.7))
		"barn":
			_hay_pile(Vector3(4.2, 0, -2.4))
			_hay_pile(Vector3(3.0, 0, -3.6))
			_trough_prop(Vector3(-0.4, 0, -3.9))
			_rug(Vector3(0.6, 0, 0.8), 2.4, 1.6, "#c9a06a")
		"coop":
			_nesting_boxes(Vector3(2.8, 0, -3.0))
			_feed_sack(Vector3(-4.4, 0, -3.2))
		"carpenter":
			_lumber_stack(Vector3(-3.6, 0, -2.4))
			_lumber_stack(Vector3(-2.6, 0, -3.4))
			_sawhorse(Vector3(-4.4, 0, -0.6))
			_rug(Vector3(0.4, 0, 0.6), 2.4, 1.6, "#a9825a")


## ---- PROCESS-01：加工机器视图（状态由 main 通过 refresh_machines 驱动） ----

func _build_machines() -> void:
	for machine: Dictionary in spec.get("machines", []):
		var kind: String = machine["kind"]
		var at: Vector3 = machine["at"]
		var output: MeshInstance3D
		match kind:
			"furnace":
				_furnace(at)
				output = M.box(self, at + Vector3(0, 2.5, 0), Vector3(0.5, 0.5, 0.5), "#d8b25a", "FurnaceOutput", 0.06)
			"cheese_press":
				_cheese_press(at)
				output = M.cylinder(self, at + Vector3(0, 1.35, 0), 0.42, 0.42, 0.3, "#f2e3b0", "CheeseWheel", 14)
			"mayo_maker":
				_mayo_maker(at)
				output = M.ellipsoid(self, at + Vector3(0.85, 1.15, 0), Vector3(0.22, 0.28, 0.22), "#f4e8b8", "MayoJar", 12, 8)
			"workbench":
				_workbench(at)
				output = M.box(self, at + Vector3(0.95, 1.35, 0.1), Vector3(0.62, 0.5, 0.5), "#a9825a", "ChestOutput", 0.05)
			"kitchen":
				_kitchen(at)
				output = M.box(self, at + Vector3(0, 1.62, 0.2), Vector3(0.66, 0.26, 0.42), "#e0b46a", "BreadLoaf", 0.05)
			"loom":
				_loom(at)
				output = M.box(self, at + Vector3(0, 1.05, 0.32), Vector3(0.9, 0.5, 0.14), "#7c5a8a", "BlanketRoll", 0.04)
		output.visible = false
		_machine_props[kind] = {"output": output}


func _furnace(at: Vector3) -> void:
	M.box(self, at + Vector3(0, 0.9, 0), Vector3(1.8, 1.8, 1.6), "#8f8b7d", "FurnaceBody", 0.06)
	M.box(self, at + Vector3(0, 0.55, 0.75), Vector3(1.0, 0.8, 0.2), "#4c4742", "FireboxMouth", 0)
	M.ellipsoid(self, at + Vector3(0, 0.5, 0.82), Vector3(0.34, 0.22, 0.1), "#e07b3f", "FurnaceEmber", 10, 6)
	M.beam(self, at + Vector3(0, 1.8, -0.3), at + Vector3(0, 3.0, -0.3), 0.34, "#7a756a", "Chimney")


func _cheese_press(at: Vector3) -> void:
	M.box(self, at + Vector3(0, 0.45, 0), Vector3(1.7, 0.9, 1.2), "#9a774d", "PressBase", 0.04)
	M.beam(self, at + Vector3(0, 0.9, 0), at + Vector3(0, 2.1, 0), 0.14, "#7c5c3b", "PressBeam")
	M.box(self, at + Vector3(0, 1.05, 0), Vector3(0.9, 0.22, 0.7), "#7c5c3b", "PressPlate", 0.02)
	M.cylinder(self, at + Vector3(0, 0.98, 0), 0.5, 0.5, 0.16, "#b8905a", "PressBasin", 14)


func _mayo_maker(at: Vector3) -> void:
	M.cylinder(self, at + Vector3(0, 0.6, 0), 0.62, 0.55, 1.2, "#8a6240", "MayoChurn", 14)
	M.cylinder(self, at + Vector3(0, 1.28, 0), 0.58, 0.44, 0.16, "#a9825a", "MayoLid", 14)
	M.box(self, at + Vector3(-0.9, 0.35, 0), Vector3(0.5, 0.7, 0.5), "#c9a06a", "Crate", 0.04)


func _workbench(at: Vector3) -> void:
	M.box(self, at + Vector3(0, 0.62, 0), Vector3(2.6, 0.14, 1.3), "#9a774d", "BenchTop", 0.03)
	for leg in [Vector3(-1.1, 0, -0.45), Vector3(1.1, 0, -0.45), Vector3(-1.1, 0, 0.45), Vector3(1.1, 0, 0.45)]:
		M.box(self, at + leg + Vector3(0, 0.28, 0), Vector3(0.16, 0.56, 0.16), "#7c5c3b", "BenchLeg", 0)
	M.box(self, at + Vector3(-0.7, 0.78, 0), Vector3(0.5, 0.24, 0.4), "#8f8b7d", "Vise", 0.03)
	M.beam(self, at + Vector3(0.7, 0.7, 0), at + Vector3(0.7, 1.1, 0), 0.05, "#aeb6bd", "File")


func _kitchen(at: Vector3) -> void:
	M.box(self, at + Vector3(0, 0.5, 0), Vector3(2.4, 1.0, 1.1), "#8f8b7d", "StoveBody", 0.04)
	M.box(self, at + Vector3(0, 1.05, 0), Vector3(2.5, 0.12, 1.2), "#6c675f", "StoveTop", 0.02)
	M.cylinder(self, at + Vector3(-0.55, 1.3, 0), 0.34, 0.28, 0.34, "#3c3835", "CookPot", 14)
	M.cylinder(self, at + Vector3(0.6, 1.18, 0.1), 0.2, 0.16, 0.18, "#c9564a", "Jar", 10)
	M.beam(self, at + Vector3(0, 1.1, -0.3), at + Vector3(0, 2.4, -0.3), 0.26, "#7a756a", "KitchenHood")


func _loom(at: Vector3) -> void:
	M.box(self, at + Vector3(0, 0.5, 0), Vector3(1.7, 1.0, 0.6), "#9a774d", "LoomBase", 0.04)
	M.box(self, at + Vector3(0, 1.9, -0.15), Vector3(1.7, 1.9, 0.14), "#7c5c3b", "LoomFrame", 0.03)
	for i in range(5):
		M.beam(self, at + Vector3(-0.6 + i * 0.3, 1.0, -0.05), at + Vector3(-0.6 + i * 0.3, 2.7, -0.05), 0.025, "#e8dcc4", "WarpThread")
	M.beam(self, at + Vector3(0, 2.75, -0.15), at + Vector3(0, 2.95, -0.15), 0.1, "#8a6240", "LoomBeam")


func _lumber_stack(at: Vector3) -> void:
	M.box(self, at + Vector3(0, 0.18, 0), Vector3(2.2, 0.24, 0.7), "#b98d5f", "Lumber", 0.02)
	M.box(self, at + Vector3(0.1, 0.44, 0.04), Vector3(1.9, 0.24, 0.62), "#a9825a", "Lumber", 0.02)
	M.box(self, at + Vector3(-0.05, 0.7, -0.03), Vector3(1.6, 0.24, 0.56), "#c9a06a", "Lumber", 0.02)


func _sawhorse(at: Vector3) -> void:
	M.beam(self, at + Vector3(-0.6, 0.62, 0), at + Vector3(0.6, 0.62, 0), 0.12, "#b98d5f", "SawhorseTop")
	M.beam(self, at + Vector3(-0.45, 0, -0.12), at + Vector3(-0.28, 0.6, 0), 0.09, "#8a6240", "SawhorseLeg")
	M.beam(self, at + Vector3(0.45, 0, -0.12), at + Vector3(0.28, 0.6, 0), 0.09, "#8a6240", "SawhorseLeg")


func _anvil(at: Vector3) -> void:
	M.cylinder(self, at + Vector3(0, 0.3, 0), 0.34, 0.4, 0.6, "#7c5c3b", "AnvilStump", 12)
	M.box(self, at + Vector3(0, 0.75, 0), Vector3(1.0, 0.3, 0.42), "#5c6256", "Anvil", 0.04)
	M.box(self, at + Vector3(0.4, 0.72, 0), Vector3(0.35, 0.24, 0.3), "#5c6256", "AnvilHorn", 0.03)


func _coal_pile(at: Vector3) -> void:
	M.ellipsoid(self, at + Vector3(0, 0.14, 0), Vector3(0.7, 0.2, 0.55), "#3c3835", "CoalPile", 12, 7)
	M.ellipsoid(self, at + Vector3(0.35, 0.16, 0.2), Vector3(0.22, 0.14, 0.2), "#4c4742", "CoalLump", 8, 5)


func _barrel(at: Vector3) -> void:
	M.cylinder(self, at + Vector3(0, 0.45, 0), 0.42, 0.38, 0.9, "#8a6240", "Barrel", 12)


func _weapon_rack(at: Vector3) -> void:
	M.box(self, at + Vector3(0, 0.9, 0), Vector3(1.9, 1.8, 0.22), "#7c5c3b", "RackBoard", 0.03)
	for i in range(3):
		M.beam(self, at + Vector3(-0.6 + i * 0.6, 0.4, 0.14), at + Vector3(-0.6 + i * 0.6, 1.6, 0.14), 0.05, ["#aeb6bd", "#d8b25a", "#8f9aa3"][i], "RackBlade")


func _hay_pile(at: Vector3) -> void:
	M.box(self, at + Vector3(0, 0.45, 0), Vector3(1.4, 0.9, 1.0), "#d9b45a", "HayBale", 0.06)
	M.box(self, at + Vector3(0.2, 1.15, 0.05), Vector3(0.9, 0.5, 0.7), "#c9a05f", "HayBale", 0.05)


func _trough_prop(at: Vector3) -> void:
	M.box(self, at + Vector3(0, 0.3, 0), Vector3(2.2, 0.6, 0.8), "#8a6240", "BarnTrough", 0.03)
	M.box(self, at + Vector3(0, 0.52, 0), Vector3(1.9, 0.18, 0.6), "#d9b45a", "HayFill", 0)


func _nesting_boxes(at: Vector3) -> void:
	for i in range(3):
		M.box(self, at + Vector3(-1.0 + i * 1.0, 0.4, 0), Vector3(0.8, 0.8, 0.7), "#a9825a", "NestBox", 0.04)
		M.ellipsoid(self, at + Vector3(-1.0 + i * 1.0, 0.86, 0.1), Vector3(0.16, 0.2, 0.16), "#f2ede2", "NestEgg", 10, 7)


func _feed_sack(at: Vector3) -> void:
	M.ellipsoid(self, at + Vector3(0, 0.42, 0), Vector3(0.42, 0.5, 0.38), "#d8cfa8", "FeedSack", 12, 8)
	M.cylinder(self, at + Vector3(0, 0.95, 0), 0.16, 0.2, 0.24, "#c4b98f", "SackNeck", 10)


func _bed(at: Vector3, frame: String = "#8a6240", blanket: String = "#c9564a") -> void:
	M.box(self, at + Vector3(0, 0.22, 0), Vector3(1.5, 0.3, 2.3), frame, "BedFrame")
	M.box(self, at + Vector3(0, 0.44, 0.12), Vector3(1.4, 0.18, 2.0), blanket, "Blanket")
	M.box(self, at + Vector3(0, 0.5, -0.78), Vector3(1.1, 0.16, 0.5), "#f2ede2", "Pillow")
	M.box(self, at + Vector3(0, 0.55, -1.1), Vector3(1.5, 0.5, 0.12), frame, "Headboard")


func _table(at: Vector3, radius: float) -> void:
	M.cylinder(self, at + Vector3(0, 0.62, 0), radius, radius, 0.09, "#9a774d", "TableTop", 18)
	M.cylinder(self, at + Vector3(0, 0.31, 0), 0.12, 0.16, 0.62, "#7c5c3b", "TableLeg", 10)
	M.ellipsoid(self, at + Vector3(radius * 0.4, 0.74, 0), Vector3(0.14, 0.1, 0.14), "#e8e4da", "Mug", 10, 6)


func _counter(at: Vector3, length: float, accent: String = "#9a774d") -> void:
	M.box(self, at + Vector3(0, 0.5, 0), Vector3(length, 1.0, 1.0), accent, "Counter", 0.04)
	M.box(self, at + Vector3(0, 1.06, 0.12), Vector3(length + 0.2, 0.09, 1.2), "#c9a06a", "CounterTop", 0.03)
	for i in range(3):
		var hex: String = ["#d98f3f", "#9db85c", "#c9564a"][i]
		M.ellipsoid(self, at + Vector3(-length * 0.3 + i * length * 0.3, 1.22, 0), Vector3(0.26, 0.14, 0.2), hex, "CounterGoods", 12, 7)


func _shelf_row(at: Vector3, shelves: int) -> void:
	M.box(self, at + Vector3(0, 1.5, 0), Vector3(2.6, 3.0, 0.5), "#8a6240", "Shelf", 0.04)
	for row in range(shelves):
		var y := 0.7 + row * 0.95
		M.box(self, at + Vector3(0, y, 0.12), Vector3(2.3, 0.07, 0.42), "#c9a06a", "ShelfBoard", 0)
		for i in range(4):
			var hex: String = ["#d98f3f", "#9db85c", "#c9564a", "#e8d9a0"][(row + i) % 4]
			M.box(self, at + Vector3(-0.9 + i * 0.6, y + 0.22, 0.1), Vector3(0.34, 0.34, 0.3), hex, "Jar", 0.04)


func _crate_stack(at: Vector3) -> void:
	M.box(self, at + Vector3(0, 0.45, 0), Vector3(0.9, 0.9, 0.9), "#a9825a", "Crate", 0.05)
	M.box(self, at + Vector3(0.12, 1.24, 0.05), Vector3(0.62, 0.62, 0.62), "#b98d5f", "Crate", 0.04)


func _fireplace(at: Vector3) -> void:
	M.box(self, at + Vector3(0, 0.75, 0), Vector3(2.0, 1.5, 0.7), "#8f8b7d", "Fireplace", 0.05)
	M.box(self, at + Vector3(0, 0.45, 0.3), Vector3(0.9, 0.6, 0.2), "#5c5650", "Firebox", 0)
	M.ellipsoid(self, at + Vector3(0, 0.32, 0.34), Vector3(0.3, 0.14, 0.12), "#e07b3f", "Ember", 10, 6)


func _rug(at: Vector3, width: float, depth: float, tint: String = "#bc6646") -> void:
	var inner := tint
	if tint != "#bc6646":
		inner = "#" + Color(tint).lightened(0.25).to_html(false)
	M.box(self, at + Vector3(0, 0.115, 0), Vector3(width, 0.02, depth), tint, "Rug", 0)
	M.box(self, at + Vector3(0, 0.117, 0), Vector3(width - 0.5, 0.012, depth - 0.5), inner, "RugInner", 0)


func _cabinet(at: Vector3) -> void:
	M.box(self, at + Vector3(0, 1.0, 0), Vector3(1.8, 2.0, 0.55), "#e9e4da", "Cabinet", 0.04)
	M.box(self, at + Vector3(0, 1.55, 0.3), Vector3(0.14, 0.5, 0.03), "#d0483e", "CrossV", 0)
	M.box(self, at + Vector3(0, 1.55, 0.3), Vector3(0.5, 0.14, 0.03), "#d0483e", "CrossH", 0)


func _build_collision(size: Vector2) -> void:
	var body := StaticBody3D.new()
	body.name = "InteriorWalls"
	var half := size * 0.5
	# 四面实体墙 + 南侧门口两侧墙段；与可视墙同位。
	var segments := [
		[Vector3(0, 0, -half.y), Vector3(size.x + 0.7, 1, 0.7)],
		[Vector3(-half.x, 0, 0), Vector3(0.7, 1, size.y + 0.7)],
		[Vector3(half.x, 0, 0), Vector3(0.7, 1, size.y - 4.4)],
		[Vector3(half.x, 0, half.y - 1.1), Vector3(0.7, 1, 2.2)],
		[Vector3(-half.x + (half.x - DOOR_WIDTH * 0.5 - 0.5) * 0.5, 0, half.y), Vector3(half.x - DOOR_WIDTH * 0.5 - 0.5, 1, 0.7)],
		[Vector3(half.x - (half.x - DOOR_WIDTH * 0.5 - 0.5) * 0.5, 0, half.y), Vector3(half.x - DOOR_WIDTH * 0.5 - 0.5, 1, 0.7)],
	]
	for segment: Array in segments:
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = segment[1]
		shape.shape = box
		shape.position = segment[0] + Vector3(0, 0.5, 0)
		body.add_child(shape)
	# 家具碰撞：柜台/床/货架占位，桌子和地毯不拦路。
	for service: Dictionary in spec.get("services", []):
		if service["kind"] in ["counter_shop", "counter_meal"]:
			_add_box_shape(body, service["at"] + Vector3(0, 0.5, 0), Vector3(4.0 if spec["style"] == "inn" else 4.8, 1.0, 1.1))
		elif service["kind"] in ["bed", "clinic_bed"]:
			_add_box_shape(body, service["at"] + Vector3(0, 0.4, 0), Vector3(1.6, 0.8, 2.4))
	# 机器占位：比可视体略宽，防止穿模。
	for machine: Dictionary in spec.get("machines", []):
		_add_box_shape(body, machine["at"] + Vector3(0, 0.6, 0), Vector3(2.0, 1.2, 1.8))
	add_child(body)


func _add_box_shape(body: StaticBody3D, at: Vector3, box_size: Vector3) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = box_size
	shape.shape = box
	shape.position = at
	body.add_child(shape)


func half_extents() -> Vector2:
	return spec["size"] * 0.5


func spawn_position() -> Vector3:
	return spec["spawn"]


func exit_position() -> Vector3:
	return spec["exit"]


func has_npc_spot() -> bool:
	return spec.has("npc_spot")


func npc_station_global() -> Vector3:
	return to_global(spec["npc_spot"])


func service_world_position(kind: String) -> Vector3:
	for service: Dictionary in spec.get("services", []):
		if service["kind"] == kind:
			return to_global(service["at"])
	return to_global(Vector3.ZERO)


func machine_world_position(kind: String) -> Vector3:
	for machine: Dictionary in spec.get("machines", []):
		if machine["kind"] == kind:
			return to_global(machine["at"])
	return to_global(Vector3.ZERO)


func refresh_machines(states: Dictionary) -> void:
	## states 按 kind 给出 MachineState；FINISHED 时显示产出指示物。
	for kind in _machine_props:
		var state: RefCounted = states.get(kind)
		var finished: bool = state != null and state.state() == "FINISHED"
		(_machine_props[kind]["output"] as MeshInstance3D).visible = finished


func target_at(world_at: Vector3) -> Dictionary:
	_focus_ring.visible = false
	var local := to_local(world_at)
	local.y = 0.0
	var best: Dictionary = {}
	var best_distance := 1.0e9
	for service: Dictionary in spec.get("services", []):
		var distance: float = local.distance_to(service["at"])
		if distance <= float(service["range"]) and distance < best_distance:
			best_distance = distance
			best = {"kind": "interior_service", "service": service["kind"], "label": service["label"], "hint": service["hint"], "at": service["at"]}
	for machine: Dictionary in spec.get("machines", []):
		var distance: float = local.distance_to(machine["at"])
		if distance <= float(machine["range"]) and distance < best_distance:
			best_distance = distance
			var hint: String = String(machine["label"])
			if hint_provider.is_valid():
				hint = String(hint_provider.call(id, machine["kind"]))
			best = {"kind": "interior_machine", "machine": machine["kind"], "label": machine["label"], "hint": hint, "at": machine["at"]}
	var exit_distance := local.distance_to(spec["exit"])
	if exit_distance <= 1.7 and best_distance > 1.2:
		best = {"kind": "interior_exit", "hint": "按 E 回到微风山谷"}
	if best.is_empty():
		return {}
	if best.has("at"):
		_focus_ring.position = best["at"] + Vector3(0, 0.06, 0)
		_focus_ring.visible = true
	return best
