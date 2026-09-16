extends RefCounted
## 伤害数字、碎屑与剑光均在命中事件发生后生成。

const M = preload("res://scripts/art/art_mesh.gd")
const FONT = preload("res://resources/ui_font.tres")


static func number(parent: Node3D, at: Vector3, value: String, color: Color = Color("#ffdf83")) -> Label3D:
	var label := Label3D.new()
	label.name = "DamageNumber"
	label.font = FONT
	label.text = value
	label.font_size = 56
	label.pixel_size = 0.011
	label.outline_size = 12
	label.outline_modulate = Color("#252332")
	label.modulate = color
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.render_priority = 20
	at += Vector3(0.42, 0.6, 0)
	label.position = at
	parent.add_child(label)
	var tween := label.create_tween().set_parallel(true)
	tween.tween_property(label, "position", at + Vector3(0.16, 1.5, 0), 0.95).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.38).set_delay(0.57)
	tween.chain().tween_callback(label.queue_free)
	return label


static func burst(parent: Node3D, at: Vector3, color: String, count: int = 7) -> void:
	var root := Node3D.new()
	root.name = "HitChips"
	root.position = at
	parent.add_child(root)
	for i in range(count):
		var chip := M.box(root, Vector3.ZERO, Vector3.ONE * (0.075 + i % 3 * 0.03), color, "Chip", 0.012)
		var direction := Vector3(cos(i * 2.4), 0.7 + i % 3 * 0.25, sin(i * 2.4))
		var tween := root.create_tween().set_parallel(true)
		tween.tween_property(chip, "position", direction * 0.68, 0.24).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(chip, "rotation", Vector3(i, i * 2, i * 0.3), 0.4)
		tween.tween_property(chip, "scale", Vector3.ONE * 0.01, 0.22).set_delay(0.20)
	root.create_tween().tween_callback(root.queue_free).set_delay(0.5)


static func slash(parent: Node3D, at: Vector3, facing: Vector3) -> void:
	var root := Node3D.new()
	root.name = "SwordArc"
	root.position = at + Vector3(0, 0.8, 0)
	root.rotation.y = atan2(facing.x, facing.z)
	parent.add_child(root)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(16):
		var a := lerpf(-1.13, 1.13, i / 16.0)
		var b := lerpf(-1.13, 1.13, (i + 1) / 16.0)
		M.polygon(surface, [Vector3(sin(a), 0, cos(a)) * 1.15, Vector3(sin(a), 0, cos(a)) * 2.1, Vector3(sin(b), 0, cos(b)) * 2.1, Vector3(sin(b), 0, cos(b)) * 1.15], Vector3.UP)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1, 0.91, 0.67, 0.56)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	M.mesh_node(root, surface.commit(), Vector3.ZERO, material, "Arc")
	var tween := root.create_tween()
	tween.tween_property(material, "albedo_color:a", 0.0, 0.22)
	tween.tween_callback(root.queue_free)
