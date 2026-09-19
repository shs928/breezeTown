extends RefCounted
## POLISH-05：季节地表视觉调色。纯数据口径，_apply_daylight 每帧引用，
## 场景副作用（地面雪 uniform、树叶季色覆盖等）由 main 按季节变化时应用。

## 当前树叶季色（apply_foliage_tint 更新；森林分块构建时即时读取）。
static var current_foliage_tint := Color.WHITE
static var _foliage_material: StandardMaterial3D

## 树叶季色乘子：作用于树冠顶点色。秋季转金黄、冬季霜灰蓝（压住粉樱）、
## 夏中性、春微鲜。乘子过强会连树干顶点色一起失真，取值保守。
static func foliage_tint_for(season_key: String) -> Color:
	match season_key:
		"winter":
			return Color(0.58, 0.68, 0.82)
		"autumn":
			return Color(1.38, 0.78, 0.38)
		"summer":
			return Color(0.97, 1.02, 0.92)
		_:
			return Color(1.03, 1.07, 0.94)


## 共享的树叶季色材质：白色底 + 顶点色 + 季色乘子（所有被覆盖节点共用一份）。
static func foliage_material() -> StandardMaterial3D:
	if _foliage_material == null:
		_foliage_material = StandardMaterial3D.new()
		_foliage_material.vertex_color_use_as_albedo = true
		_foliage_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_foliage_material.albedo_color = current_foliage_tint
	return _foliage_material


static func apply_foliage_tint(season_key: String) -> void:
	current_foliage_tint = foliage_tint_for(season_key)
	# 世界构建时代码树冠合并进专用 "#fffffe" 批次（与通用白分离）——
	# 改这一个共享材质的 albedo 即可整体调色树冠（顶点色 × 乘子）。
	var ArtMesh := load("res://scripts/art/art_mesh.gd")
	(ArtMesh.paint("#fffffe") as StandardMaterial3D).albedo_color = current_foliage_tint


static func foliage_singleton() -> StandardMaterial3D:
	var ArtMesh := load("res://scripts/art/art_mesh.gd")
	return ArtMesh.paint("#fffffe") as StandardMaterial3D


## GLB 树冠材质季色（森林与成树）：按导入材质名前缀识别树冠（PineLeaf/Broadleaf），
## 原色 × 季色乘子；树干（WarmBark）与果实（AppleVermilion）不参与。
## 材质为全局共享导入资源，原地变异一次全场景生效；原色记录一次用于恢复。
static var _foliage_originals := {}
const FOLIAGE_MATERIAL_PREFIXES := ["PineLeaf", "Broadleaf"]


static func apply_glb_foliage(root: Node, season_key: String) -> int:
	var tint := foliage_tint_for(season_key)
	var touched := 0
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (node as MeshInstance3D).mesh
		if mesh == null:
			continue
		for s in range(mesh.get_surface_count()):
			var mat := mesh.surface_get_material(s)
			if mat is StandardMaterial3D and _is_foliage_material(mat as StandardMaterial3D):
				touch_material(mat as StandardMaterial3D, tint)
				touched += 1
	return touched


static func _is_foliage_material(mat: StandardMaterial3D) -> bool:
	for prefix: String in FOLIAGE_MATERIAL_PREFIXES:
		if mat.resource_name.begins_with(prefix):
			return true
	return false


## 原色表用"材质名@路径"字符串做键：Object 键会因材质实例释放而失效。
static func _material_key(mat: StandardMaterial3D) -> String:
	return mat.resource_name + "@" + mat.resource_path


static func touch_material(mat: StandardMaterial3D, tint: Color) -> void:
	var key := _material_key(mat)
	if not _foliage_originals.has(key):
		_foliage_originals[key] = mat.albedo_color
	mat.albedo_color = (_foliage_originals[key] as Color) * tint


static func original_color_of(mat: StandardMaterial3D) -> Color:
	return _foliage_originals.get(_material_key(mat), mat.albedo_color)


## 森林分块专用：MultiMesh 的材质不在节点树上，直接扫 _parts 的网格表面。
## _parts 实例全分块共享，记录一次后新建分块自动生效。
static func apply_parts_foliage(parts: Dictionary, season_key: String) -> void:
	var tint := foliage_tint_for(season_key)
	for species: String in parts:
		for part: Dictionary in parts[species]:
			var mesh: Mesh = part["mesh"]
			if mesh == null:
				continue
			for s in range(mesh.get_surface_count()):
				var mat := mesh.surface_get_material(s)
				if mat is StandardMaterial3D and _is_foliage_material(mat as StandardMaterial3D):
					touch_material(mat as StandardMaterial3D, tint)


## 地面雪量：冬季全覆盖，其他季节 0（春秋不做残雪，规则无歧义）。
static func snow_amount_for(season_key: String) -> float:
	return 1.0 if season_key == "winter" else 0.0


## 地面草地色调乘子：秋转干黄、夏深绿、春鲜嫩、冬由雪量接管（色调不参与）。
static func ground_tint_for(season_key: String) -> Color:
	match season_key:
		"autumn":
			return Color(1.06, 0.96, 0.70)
		"summer":
			return Color(0.94, 1.02, 0.90)
		"spring":
			return Color(1.0, 1.04, 0.96)
		_:
			return Color.WHITE


## 环境色调乘子：背景/环境光向季节色偏移的比例，与日光关键帧插值结果相乘叠加。
## winter 冷冽偏蓝、autumn 暖金、spring 微鲜、summer 中性。
static func env_tint_for(season_key: String) -> Dictionary:
	match season_key:
		"winter":
			return {"bg": Color("#9fb4d8"), "bg_strength": 0.32, "amb": Color("#b9c9e2"), "amb_strength": 0.30, "sun": Color("#e8f0ff"), "sun_strength": 0.22, "energy": 0.92}
		"autumn":
			return {"bg": Color("#d8b878"), "bg_strength": 0.24, "amb": Color("#e2c9a0"), "amb_strength": 0.22, "sun": Color("#ffd9a0"), "sun_strength": 0.18, "energy": 0.97}
		"spring":
			return {"bg": Color("#cfe0b8"), "bg_strength": 0.10, "amb": Color("#d8e8c8"), "amb_strength": 0.10, "sun": Color("#fff3dc"), "sun_strength": 0.08, "energy": 1.0}
		_:
			return {"bg": Color("#e8f0e0"), "bg_strength": 0.06, "amb": Color("#eef4e4"), "amb_strength": 0.06, "sun": Color("#fff8ea"), "sun_strength": 0.05, "energy": 1.0}
