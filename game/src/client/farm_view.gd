extends Control
## 农场视图（UI 唯一维护，M1 UI-02）。只读渲染权威状态，点击转换为客户端动作。
## 不直接修改世界状态；所有交互经 client 的动作方法进入命令网关。

const ContractLimits := preload("res://src/contracts/contract_limits.gd")
const WorldState := preload("res://src/domain/world/world_state.gd")

var client: Node = null

var _tiles: Array = []
var _world: WorldState = null
var _player_id := ""
var _camera := Vector2.ZERO
var _textures: Dictionary = {}   # 名称 -> Texture2D（ART-01 原创素材）


func setup(world: WorldState, player_id: String) -> void:
	_world = world
	_player_id = player_id
	_tiles = _load_tiles()
	_load_textures()
	_center_on_player()
	queue_redraw()


## 加载 ART-01 生成的原创像素素材；缺失时回退到纯色绘制。
func _load_textures() -> void:
	for name: String in ["tile_grass", "tile_soil", "tile_soil_tilled", "tile_soil_wet",
			"tile_path", "tile_blocked", "tile_facility", "tile_spawn",
			"avatar_1", "avatar_2", "avatar_3", "avatar_4",
			"crop_radish_sown", "crop_radish_mature", "crop_potato_sown", "crop_potato_seedling",
			"crop_potato_mature", "crop_wheat_sown", "crop_wheat_seedling", "crop_wheat_mature",
			"crop_carrot_sown", "crop_carrot_seedling", "crop_carrot_growing", "crop_carrot_mature",
			"crop_strawberry_sown", "crop_strawberry_seedling", "crop_strawberry_growing",
			"crop_strawberry_mature"]:
		var path := "res://assets/generated/%s.png" % name
		if ResourceLoader.exists(path):
			_textures[name] = load(path)


func _load_tiles() -> Array:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://content/schema/examples/map_town_minimal.json"))
	if parsed is Dictionary:
		return (parsed as Dictionary).get("tiles", [])
	return []


func _center_on_player() -> void:
	if _world == null:
		return
	var member: Dictionary = _world.find_member(_player_id)
	if member.is_empty():
		return
	var pos: Dictionary = member["last_valid_position"]
	_camera = Vector2(float(pos["x"]), float(pos["y"])) - size * 0.5


func _draw() -> void:
	if _world == null or _tiles.is_empty():
		return
	var tile_size := ContractLimits.TILE_SIZE_PX
	# 只画可见范围，避免 64x64 全量绘制
	var start_x: int = max(0, int(_camera.x / tile_size))
	var start_y: int = max(0, int(_camera.y / tile_size))
	var end_x: int = min(ContractLimits.MAP_W - 1, int((_camera.x + size.x) / tile_size) + 1)
	var end_y: int = min(ContractLimits.MAP_H - 1, int((_camera.y + size.y) / tile_size) + 1)
	for y in range(start_y, end_y + 1):
		var row: String = _tiles[y]
		for x in range(start_x, end_x + 1):
			var rect := Rect2(Vector2(x * tile_size, y * tile_size) - _camera, Vector2(tile_size, tile_size))
			var plot: Dictionary = _world.plots.get(str(y * ContractLimits.MAP_W + x), {})
			var texture := _tile_texture(row[x], str(plot.get("state", "")))
			if texture != null:
				draw_texture_rect(texture, rect, false)
			else:
				draw_rect(rect, _tile_color(row[x], plot.get("state", "")))
	# 作物
	for crop_id: String in _world.crops:
		var crop: Dictionary = _world.crops[crop_id]
		var tile_id := int(crop["tile_id"])
		var cx := (tile_id % ContractLimits.MAP_W) * tile_size + tile_size / 2
		var cy := (tile_id / ContractLimits.MAP_W) * tile_size + tile_size / 2
		var center := Vector2(cx, cy) - _camera
		var stage: String = _stage_of(crop)
		var key := "%s_%s" % [str(crop["crop_definition_id"]).replace("crop.", "crop_"), stage]
		var crop_texture: Texture2D = _textures.get(key, null)
		if crop_texture != null:
			var crop_rect := Rect2(center - Vector2(16, 16), Vector2(32, 32))
			draw_texture_rect(crop_texture, crop_rect, false)
		else:
			var radius: float = 6.0 if stage == "mature" else 4.0
			draw_circle(center, radius, Color(0.85, 0.2, 0.2) if stage == "mature" else Color(0.35, 0.6, 0.25))
		if stage == "mature":
			draw_arc(center, 19.0, 0.0, TAU, 24, Color(0.95, 0.82, 0.42), 2.0)
	# 玩家（自己的角色高亮）
	for member: Dictionary in _world.members:
		if member["status"] != "active":
			continue
		var pos: Dictionary = member["last_valid_position"]
		var player_center := Vector2(float(pos["x"]), float(pos["y"])) - _camera
		var avatar_key := str(member.get("avatar", "avatar.1")).replace("avatar.", "avatar_")
		var avatar_texture: Texture2D = _textures.get(avatar_key, null)
		if avatar_texture != null:
			draw_texture_rect(avatar_texture, Rect2(player_center - Vector2(16, 16), Vector2(32, 32)), false)
		else:
			var color := Color(0.9, 0.36, 0.36) if member["player_id"] == _player_id else Color(0.3, 0.5, 0.82)
			draw_circle(player_center, 12.0, color)
		# 本人高亮环（不只靠颜色区分）
		if member["player_id"] == _player_id:
			draw_arc(player_center, 17.0, 0.0, TAU, 24, Color(0.95, 0.82, 0.42), 2.0)


## 地块纹理：耕地状态优先于地形。
func _tile_texture(ch: String, plot_state: String) -> Texture2D:
	if plot_state == "planted" or plot_state == "empty":
		return _textures.get("tile_soil_tilled", null)
	match ch:
		"B": return _textures.get("tile_blocked", null)
		"F": return _textures.get("tile_soil", null)
		"P": return _textures.get("tile_facility", null)
		"S": return _textures.get("tile_spawn", null)
		_: return _textures.get("tile_grass", null)


func _tile_color(ch: String, plot_state: String) -> Color:
	if plot_state == "empty":
		return Color(0.43, 0.32, 0.22)
	if plot_state == "planted":
		return Color(0.35, 0.26, 0.19)
	match ch:
		"B": return Color(0.37, 0.45, 0.3)
		"F": return Color(0.55, 0.42, 0.29)
		"P": return Color(0.79, 0.72, 0.6)
		"S": return Color(0.6, 0.72, 0.5)
		_: return Color(0.48, 0.71, 0.38)


func _stage_of(crop: Dictionary) -> String:
	if client != null and client.farm != null:
		return client.farm.stage_of(crop)
	return "sown"


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if client == null or not client.session.is_active():
			return
		var world_pos: Vector2 = event.position + _camera
		var tile_x := int(world_pos.x / ContractLimits.TILE_SIZE_PX)
		var tile_y := int(world_pos.y / ContractLimits.TILE_SIZE_PX)
		if tile_x < 0 or tile_x >= ContractLimits.MAP_W or tile_y < 0 or tile_y >= ContractLimits.MAP_H:
			return
		client.action_click_tile(tile_y * ContractLimits.MAP_W + tile_x)
		_center_on_player()
		queue_redraw()
