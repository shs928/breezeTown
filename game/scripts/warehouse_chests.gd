extends Node3D
## STORE-01：可放置宝箱（农场共享仓库的存取点）。所有箱子连通同一仓库，
## 因此只持久化位置；内容在 GameState.warehouse。占地经 map.occupy_resource 阻耕。

const M := preload("res://scripts/art/art_mesh.gd")

var map: RefCounted  # MapData：登记占地防耕作
var positions: Array[Vector3] = []
var _nodes: Array[Node3D] = []
var _focus_ring: MeshInstance3D


func place(at: Vector3) -> void:
	var p := Vector3(snappedf(at.x, 0.05), 0.0, snappedf(at.z, 0.05))
	positions.append(p)
	_nodes.append(_build_chest(p))
	if map != null:
		map.occupy_resource(_id_of(p), Vector2(p.x, p.z), 0.7)


func remove_nearest(at: Vector3) -> bool:
	## 收起最近的宝箱（内容留在共享仓库，零损失）。
	var best := -1
	var best_distance := 2.6
	for index in range(positions.size()):
		var distance := Vector2(positions[index].x, positions[index].z).distance_to(Vector2(at.x, at.z))
		if distance < best_distance:
			best_distance = distance
			best = index
	if best < 0:
		return false
	if map != null:
		map.release_resource(_id_of(positions[best]))
	_nodes[best].queue_free()
	_nodes.remove_at(best)
	positions.remove_at(best)
	if _focus_ring != null:
		_focus_ring.visible = false
	return true


func nearest_distance(at: Vector3) -> float:
	var best := INF
	for position in positions:
		best = minf(best, Vector2(position.x, position.z).distance_to(Vector2(at.x, at.z)))
	return best


func near(at: Vector2, radius: float = 1.2) -> bool:
	return nearest_distance(Vector3(at.x, 0, at.y)) <= radius


func target_at(world_at: Vector3) -> Dictionary:
	if _focus_ring == null:
		_focus_ring = M.torus(self, Vector3.ZERO, 0.78, 0.03, "#ebd99a", "ChestFocus")
		_focus_ring.hide()
	var best := -1
	var best_distance := 2.2
	for index in range(positions.size()):
		var distance := Vector3(positions[index].x, 0.0, positions[index].z).distance_to(world_at)
		if distance < best_distance:
			best_distance = distance
			best = index
	if best < 0:
		return {}
	_focus_ring.position = positions[best] + Vector3(0, 0.06, 0)
	_focus_ring.show()
	return {"kind": "warehouse_chest", "index": best, "position": positions[best]}


func clear_focus() -> void:
	if _focus_ring != null:
		_focus_ring.visible = false


func to_dict() -> Dictionary:
	var placed := []
	for position in positions:
		placed.append([position.x, position.z])
	return {"placed": placed}


func from_dict(data: Dictionary) -> void:
	for node in _nodes:
		node.queue_free()
	_nodes.clear()
	positions.clear()
	for entry: Array in data.get("placed", []):
		if entry.size() == 2 and entry[0] is float and entry[1] is float and is_finite(float(entry[0])) and is_finite(float(entry[1])):
			place(Vector3(float(entry[0]), 0.0, float(entry[1])))


func _id_of(at: Vector3) -> int:
	return hash("chest:%.2f:%.2f" % [at.x, at.z])


func _build_chest(at: Vector3) -> Node3D:
	var node := Node3D.new()
	node.name = "Chest_%d" % _nodes.size()
	node.position = at
	add_child(node)
	M.box(node, Vector3(0, 0.26, 0), Vector3(0.92, 0.5, 0.66), "#9a774d", "ChestBody", 0.04)
	M.box(node, Vector3(0, 0.58, -0.06), Vector3(0.98, 0.22, 0.72), "#7c5c3b", "ChestLid", 0.05)
	M.box(node, Vector3(0, 0.44, 0.3), Vector3(0.16, 0.2, 0.08), "#d8b25a", "ChestLatch", 0.02)
	M.box(node, Vector3(0, 0.02, 0), Vector3(1.05, 0.04, 0.8), "#8a6240", "ChestPad", 0)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, 0.8, 0.75)
	shape.shape = box
	shape.position = Vector3(0, 0.4, 0)
	body.add_child(shape)
	node.add_child(body)
	return node
