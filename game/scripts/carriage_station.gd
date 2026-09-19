extends Node3D
## TRANSPORT-02：驿站马车管理与场景表现。一个实例管理全部六站：
## 站牌+干草长椅+停驻马车的低多边形表现、解锁状态、焦点解析与存档。
## 位置经锚点解析（landmarks 键或 site:建筑id 的门点）+ 数据表偏移。

const DB := preload("res://scripts/data/carriage_db.gd")
const M := preload("res://scripts/art/art_mesh.gd")

var unlocked := {}  # id -> true（存档键 travel.unlocked）
var _positions := {}  # id -> Vector3
var _focus_ring: MeshInstance3D


func setup(resolve_anchor: Callable) -> void:
	for id: String in DB.ORDER:
		var spec: Dictionary = DB.entry(id)
		# 解析器由 main 注入：landmarks 键或 "site:建筑id" 均返回世界坐标。
		var base: Vector3 = resolve_anchor.call(String(spec["anchor"]))
		var offset: Vector3 = spec["offset"]
		_positions[id] = base + offset
	# 农场↔镇区教学线路：两端开站即解锁。
	unlocked["farm"] = true
	unlocked["town"] = true
	_build_visuals()


func _build_visuals() -> void:
	for id: String in DB.ORDER:
		var at: Vector3 = _positions[id]
		var station := Node3D.new()
		station.name = "CarriageStation_" + id
		station.position = at
		add_child(station)
		# 站牌：立柱 + 双色站板。
		M.beam(station, Vector3(0, 0, 0), Vector3(0, 2.3, 0), 0.09, "#7c5c3b", "Post")
		M.box(station, Vector3(0, 2.45, 0), Vector3(1.35, 0.5, 0.08), "#d9b45a", "SignBoard", 0.03)
		M.box(station, Vector3(0, 2.45, 0.045), Vector3(1.1, 0.2, 0.02), "#a55e47", "SignStripe", 0)
		# 干草长椅（候车座）。
		M.box(station, Vector3(-1.6, 0.28, 0.55), Vector3(1.7, 0.12, 0.5), "#c9a05f", "BenchSeat", 0.02)
		for leg_x in [-2.2, -1.0]:
			M.box(station, Vector3(leg_x, 0.12, 0.55), Vector3(0.12, 0.24, 0.44), "#8a6240", "BenchLeg", 0)
		# 停驻马车：车斗 + 双轮 + 辕杆 + 干草。
		var cart := Node3D.new()
		cart.name = "Cart"
		cart.position = Vector3(1.7, 0, 0.9)
		cart.rotation.y = 0.5
		station.add_child(cart)
		M.box(cart, Vector3(0, 0.55, 0), Vector3(1.5, 0.6, 1.0), "#9a774d", "CartBody", 0.05)
		M.box(cart, Vector3(0, 0.92, 0), Vector3(1.3, 0.18, 0.85), "#c9a05f", "CartRim", 0.03)
		for wheel_x in [-0.85, 0.85]:
			var wheel := M.cylinder(cart, Vector3(wheel_x, 0.42, 0.52), 0.42, 0.42, 0.09, "#6c4a2e", "CartWheel", 12)
			wheel.rotation.x = PI / 2
		M.beam(cart, Vector3(0.7, 0.5, 0), Vector3(2.3, 0.55, 0), 0.07, "#7c5c3b", "CartShaft")
		M.box(cart, Vector3(-0.2, 0.78, 0), Vector3(0.8, 0.34, 0.7), "#d9b45a", "CartHay", 0.04)
	if _focus_ring == null:
		_focus_ring = M.torus(self, Vector3.ZERO, 0.95, 0.035, "#edcf82", "CarriageFocus")
		_focus_ring.visible = false


func position_of(id: String) -> Vector3:
	return _positions.get(id, Vector3.ZERO)


func is_unlocked(id: String) -> bool:
	return unlocked.get(id, false)


## 走到站旁即解锁；返回 true 表示这是新解锁（调用方负责 toast）。
func unlock(id: String) -> bool:
	if unlocked.has(id):
		return false
	unlocked[id] = true
	return true


## 焦点解析：返回最近且已解锁（或即将解锁）的站点。
func target_at(world_at: Vector3, reach: float = 2.4) -> Dictionary:
	_focus_ring.visible = false
	var best: String = ""
	var best_distance := reach
	for id: String in DB.ORDER:
		var distance := Vector2(_positions[id].x, _positions[id].z).distance_to(Vector2(world_at.x, world_at.z))
		if distance < best_distance:
			best_distance = distance
			best = id
	if best == "":
		return {}
	_focus_ring.position = _positions[best] + Vector3(0, 0.06, 0)
	_focus_ring.visible = true
	var hint := "按 E 呼叫马车 · 前往已解锁站点" if is_unlocked(best) else "首次抵达 · 解锁驿站：%s" % DB.label(best)
	return {"kind": "carriage_station", "id": best, "hint": hint}


func clear_focus() -> void:
	if _focus_ring != null:
		_focus_ring.visible = false


func to_dict() -> Dictionary:
	var list := []
	for id: String in DB.ORDER:
		if unlocked.has(id):
			list.append(id)
	return {"unlocked": list}


func from_dict(data: Dictionary) -> void:
	unlocked = {"farm": true, "town": true}
	for id in data.get("unlocked", []):
		if DB.has(String(id)):
			unlocked[String(id)] = true
