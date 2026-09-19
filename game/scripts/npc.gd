extends Node3D
## 村民节点（NPC-01）：Q 版造型 + 日程锚点切换 + 近距踱步。
## 无碰撞体；位置由时间确定性驱动，不进存档（好感等关系数据在 GameState）。

const M := preload("res://scripts/art/art_mesh.gd")
const NpcDB := preload("res://scripts/data/npc_db.gd")

const WANDER_INTERVAL := Vector2(3.0, 7.0)
const WALK_SPEED := 0.9
const ACTIVE_RANGE := 70.0

var id := ""
var player: CharacterBody3D
var anchors: Dictionary = {}  # 锚点键 → Vector3（由 main 解析注入）
var rng := RandomNumberGenerator.new()
var _anchor_key := ""
var _home := Vector3.ZERO
var _wander_radius := 2.0
var _target := Vector3.ZERO
var _idle := 0.0
var _station := Vector3.INF  # INDOOR-02：非 INF 时为室内值守站位，停用踱步


func setup(npc_id: String, resolved_anchors: Dictionary, seed_value: int) -> void:
	id = npc_id
	anchors = resolved_anchors
	rng.seed = seed_value
	_build(NpcDB.entry(npc_id)["palette"])
	rng.randomize()


func label() -> String:
	return NpcDB.label(id)


func role() -> String:
	return NpcDB.role(id)


## 时刻推进：跨入新日程条目时整点切换到该锚点；同条目内保持踱步。
## 锚点可带 offset（门侧站位），避免村民堵住商店/农舍等门点交互。
func update_hours(hours: float) -> void:
	var slot: Dictionary = NpcDB.schedule_at(id, hours)
	if slot["anchor"] != _anchor_key:
		_apply_slot(slot)


func snap_to_schedule(hours: float) -> void:
	## INDOOR-02：离开室内时强制回到当前日程锚点（站内值守不改变日程槽）。
	_apply_slot(NpcDB.schedule_at(id, hours))


func _apply_slot(slot: Dictionary) -> void:
	_anchor_key = slot["anchor"]
	var offset: Array = slot.get("offset", [0.0, 0.0])
	_home = _anchor_position(slot["anchor"]) + Vector3(float(offset[0]), 0, float(offset[1]))
	_wander_radius = float(slot.get("wander", 2.0))
	global_position = _home + _offset()
	_pick_target()


func home_position() -> Vector3:
	return _home


func is_stationed() -> bool:
	## INDOOR-02：是否处于室内值守状态（对话焦点在室内优先于服务点）。
	return _station.x != INF


func set_indoor_station(at: Vector3) -> void:
	_station = at
	global_position = at
	rotation.y = 0.0


func clear_indoor_station(hours: float) -> void:
	_station = Vector3.INF
	snap_to_schedule(hours)


func _physics_process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	if _station.x != INF:
		# INDOOR-02：室内值守——站在服务位面朝门口（+z），不踱步。
		global_position = _station
		rotation.y = 0.0
		return
	if global_position.distance_to(player.global_position) > ACTIVE_RANGE:
		return
	if _idle > 0.0:
		_idle -= delta
		return
	var to_target := _target - global_position
	to_target.y = 0.0
	if to_target.length() < 0.12:
		_idle = rng.randf_range(WANDER_INTERVAL.x, WANDER_INTERVAL.y)
		_pick_target()
		return
	var step := to_target.normalized() * WALK_SPEED * delta
	global_position += step
	rotation.y = atan2(to_target.x, to_target.z)


func _pick_target() -> void:
	_target = _home + _offset()
	_target.x = clampf(_target.x, _home.x - _wander_radius, _home.x + _wander_radius)
	_target.z = clampf(_target.z, _home.z - _wander_radius, _home.z + _wander_radius)


func _offset() -> Vector3:
	return Vector3(rng.randf_range(-_wander_radius, _wander_radius) * 0.6, 0, rng.randf_range(-_wander_radius, _wander_radius) * 0.6)


func _anchor_position(key: String) -> Vector3:
	return anchors.get(key, anchors.get("town_square", Vector3.ZERO))


## ---- Q 版村民造型：与玩家农民同比例（腿 0.59 身高 + 1.2× 头部），按色板换装 ----

func _build(palette: Dictionary) -> void:
	var coat: String = palette.get("coat", "#6b7c8a")
	var pants: String = palette.get("pants", "#5a4632")
	var hat: String = palette.get("hat", "")
	var hair: String = palette.get("hair", "#4a2f1b")
	var body := Node3D.new()
	body.name = "Body"
	add_child(body)
	body.position = Vector3(0, 0.59, 0)
	M.cylinder(body, Vector3(-0.075, -0.28, 0), 0.055, 0.05, 0.3, pants, "LegL", 8)
	M.cylinder(body, Vector3(0.075, -0.28, 0), 0.055, 0.05, 0.3, pants, "LegR", 8)
	M.ellipsoid(body, Vector3(0, -0.06, 0), Vector3(0.155, 0.19, 0.125), coat, "Torso", 14, 10)
	M.cylinder(body, Vector3(-0.175, -0.05, 0.02), 0.038, 0.032, 0.24, coat, "ArmL", 8)
	M.cylinder(body, Vector3(0.175, -0.05, 0.02), 0.038, 0.032, 0.24, coat, "ArmR", 8)
	var head_pivot := Node3D.new()
	head_pivot.name = "HeadPivot"
	body.add_child(head_pivot)
	head_pivot.position = Vector3(0, 0.14, 0)
	var head := M.ellipsoid(head_pivot, Vector3(0, 0.1, 0), Vector3(0.135, 0.13, 0.125), "#e8b98a", "Head", 16, 12)
	head.scale = head.scale * 1.2
	M.ellipsoid(head_pivot, Vector3(0, 0.115, 0.115), Vector3(0.017, 0.014, 0.012), "#3a2a1a", "EyeL", 8, 6)
	M.ellipsoid(head_pivot, Vector3(0.045, 0.115, 0.11), Vector3(0.017, 0.014, 0.012), "#3a2a1a", "EyeR", 8, 6)
	M.blob(head_pivot, Vector3(0, 0.14, -0.015), Vector3(0.135, 0.115, 0.13), hair, 0.42, "Hair")
	if hat.is_empty():
		return
	M.cylinder(head_pivot, Vector3(0, 0.235, 0.005), 0.115, 0.115, 0.016, hat, "HatBrim", 12)
	M.cylinder(head_pivot, Vector3(0, 0.27, 0.005), 0.075, 0.082, 0.075, hat, "HatCrown", 12)
