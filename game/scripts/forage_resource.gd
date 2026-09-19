extends Node3D
## 采集物节点（GATHER-01）：纯视觉、无碰撞，徒手 E 采集。
## 造型按 forage_db 的 form 字段生成：flower/bush/mushroom/root/shell/crystal。

const M := preload("res://scripts/art/art_mesh.gd")
const ForageDB := preload("res://scripts/data/forage_db.gd")

var kind := ""
var yaw := 0.0


func setup(entry: Dictionary) -> void:
	kind = entry.get("kind", "dandelion")
	yaw = entry.get("yaw", 0.0)
	rotation.y = yaw
	# 采集物是俯视相机下的拾取目标，按 1.9× 造型基准生成保证肉眼可辨。
	scale = Vector3.ONE * clampf(entry.get("scale", 1.0), 0.85, 1.2) * 1.9
	_build()


func label() -> String:
	return ForageDB.label(kind)


func _build() -> void:
	match ForageDB.form(kind):
		"flower":
			_flower()
		"bush":
			_bush()
		"mushroom":
			_mushroom()
		"root":
			_root()
		"shell":
			_shell()
		"crystal":
			_crystal()
		_:
			_flower()


func _flower() -> void:
	var palette: String = {"daffodil": "#f5c542", "dandelion": "#ffd94f", "sweet_pea": "#e88bb0"}.get(kind, "#f0d060")
	var heart: String = {"daffodil": "#d98a1f", "dandelion": "#e8a52a", "sweet_pea": "#a4517e"}.get(kind, "#d98a1f")
	M.cylinder(self, Vector3(0, 0.14, 0), 0.014, 0.01, 0.3, "#5c8a3f", "Stem", 7)
	M.leaf(self, Vector3(0.02, 0.04, 0), Vector3(0.14, 0.1, 0.04), 0.09, "#6d9c4a", "LeafA")
	M.leaf(self, Vector3(-0.02, 0.03, 0), Vector3(-0.13, 0.08, -0.05), 0.08, "#639244", "LeafB")
	M.ellipsoid(self, Vector3(0, 0.32, 0), Vector3(0.09, 0.075, 0.09), palette, "Blossom", 12, 8)
	M.ellipsoid(self, Vector3(0, 0.335, 0), Vector3(0.042, 0.04, 0.042), heart, "Heart", 8, 6)


func _bush() -> void:
	var berry := "#8e2d4f" if kind == "blackberry" else "#d2413f"
	M.blob(self, Vector3(0, 0.22, 0), Vector3(0.3, 0.24, 0.3), "#4f7d3a", 0.71, "Bush")
	M.blob(self, Vector3(0.14, 0.16, 0.1), Vector3(0.17, 0.13, 0.17), "#5c8a3f", 1.9, "BushSide")
	for offset in [Vector3(-0.12, 0.3, 0.08), Vector3(0.1, 0.36, -0.06), Vector3(0.2, 0.24, 0.14), Vector3(-0.05, 0.18, -0.16), Vector3(0.04, 0.42, 0.1)]:
		M.ellipsoid(self, offset, Vector3(0.035, 0.035, 0.035), berry, "Berry", 8, 6)


func _mushroom() -> void:
	M.cylinder(self, Vector3(0, 0.11, 0), 0.05, 0.038, 0.22, "#e8dcc4", "Stem", 10)
	M.ellipsoid(self, Vector3(0, 0.23, 0), Vector3(0.2, 0.11, 0.2), "#b0552f", "Cap", 14, 8)
	M.ellipsoid(self, Vector3(0.07, 0.27, 0.05), Vector3(0.028, 0.016, 0.028), "#f2e6cd", "SpotA", 6, 4)
	M.ellipsoid(self, Vector3(-0.08, 0.265, -0.04), Vector3(0.024, 0.014, 0.024), "#f2e6cd", "SpotB", 6, 4)
	M.ellipsoid(self, Vector3(0.16, 0.1, 0.12), Vector3(0.11, 0.07, 0.11), "#c97747", "CapSmall", 10, 6)


func _root() -> void:
	var crown := "#7fae55" if kind != "winter_root" else "#8fae8b"
	M.ellipsoid(self, Vector3(0, 0.05, 0), Vector3(0.08, 0.09, 0.08), "#cfa36b", "Root", 10, 6)
	for index in range(4):
		var angle := TAU * float(index) / 4.0 + 0.4
		var direction := Vector3(cos(angle), 0, sin(angle))
		M.leaf(self, direction * 0.03, direction * 0.22 + Vector3(0, 0.2, 0), 0.1, crown, "Leaf%d" % index)


func _shell() -> void:
	var tone := "#e8c9a8" if kind == "shell" else "#c9a089"
	M.ellipsoid(self, Vector3(0, 0.045, 0), Vector3(0.13, 0.06, 0.16), tone, "Shell", 12, 8)
	M.beam(self, Vector3(0, 0.0, -0.15), Vector3(0, 0.09, 0.13), 0.03, "#b98d6f", "Ridge")
	M.ellipsoid(self, Vector3(0, 0.02, 0.1), Vector3(0.05, 0.03, 0.05), "#8d6a52", "Hinge", 8, 5)


func _crystal() -> void:
	M.ellipsoid(self, Vector3(0, 0.08, 0), Vector3(0.07, 0.15, 0.07), "#9fd4e8", "Shard", 8, 6)
	M.ellipsoid(self, Vector3(0.09, 0.05, 0.05), Vector3(0.045, 0.1, 0.045), "#b7e2f0", "ShardSide", 8, 6)
	M.ellipsoid(self, Vector3(-0.07, 0.04, -0.05), Vector3(0.04, 0.08, 0.04), "#8ec6dd", "ShardSide2", 8, 6)
