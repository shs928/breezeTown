extends Node3D
## 玩家圈定的牧场：沿矩形边界生成木围栏（南侧留大门），门口放食槽，
## 围栏自带碰撞；动物列表与产出拾取点由本节点管理。

const M = preload("res://scripts/art/art_mesh.gd")
const L = preload("res://scripts/art/landscape_models.gd")
const Trough := preload("res://scripts/trough.gd")

const FENCE_HEIGHT := 0.9
const GATE_WIDTH := 2.4

static var _fence_template: Node3D = null

var interior := Rect2()
var trough: Node3D
var animals: Array = []


func _exit_tree() -> void:
	if _fence_template != null:
		_fence_template.free()
		_fence_template = null


func setup(rect: Rect2) -> void:
	interior = rect
	var p := rect.position
	var e := rect.end
	_fence_run(Vector2(p.x, p.y), Vector2(p.x, e.y))
	_fence_run(Vector2(e.x, p.y), Vector2(e.x, e.y))
	_fence_run(Vector2(p.x, p.y), Vector2(e.x, p.y))
	var gate_center := (p.x + e.x) * 0.5
	_fence_run(Vector2(p.x, e.y), Vector2(gate_center - GATE_WIDTH * 0.5, e.y))
	_fence_run(Vector2(gate_center + GATE_WIDTH * 0.5, e.y), Vector2(e.x, e.y))
	for side in [-1.0, 1.0]:
		var post := M.box(self, Vector3(gate_center + side * GATE_WIDTH * 0.5, 0.6, e.y), Vector3(0.2, 1.25, 0.2), "#a5824f", "GatePost", 0.03)
		post.rotation.y = PI * 0.5
	trough = Trough.new()
	trough.name = "Trough"
	trough.position = Vector3(gate_center, 0, e.y - 1.0)
	add_child(trough)
	trough.setup()


func _fence_tpl() -> Node3D:
	if _fence_template == null:
		_fence_template = L.fence()
	return _fence_template.duplicate()


func _fence_run(from: Vector2, to: Vector2) -> void:
	var length := from.distance_to(to)
	if length < 0.4:
		return
	var count := maxi(1, roundi(length / 2.4))
	var along_x := absf(to.x - from.x) > absf(to.y - from.y)
	for i in range(count):
		var t := (i + 0.5) / float(count)
		var at := from.lerp(to, t)
		var fence := _fence_tpl()
		fence.scale.x = length / count / 2.4
		fence.position = Vector3(at.x, 0.01, at.y)
		fence.rotation.y = 0.0 if along_x else PI * 0.5
		add_child(fence)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(absf(to.x - from.x), FENCE_HEIGHT, absf(to.y - from.y)) + Vector3(0.35, 0, 0.35)
	shape.shape = box
	body.position = Vector3((from.x + to.x) * 0.5, FENCE_HEIGHT * 0.5, (from.y + to.y) * 0.5)
	body.add_child(shape)
	add_child(body)


func random_point() -> Vector3:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return Vector3(
		rng.randf_range(interior.position.x + 0.8, interior.end.x - 0.8),
		0,
		rng.randf_range(interior.position.y + 0.8, interior.end.y - 0.8)
	)


func add_animal(animal: Node3D) -> void:
	animals.append(animal)
	animal.position = random_point()
