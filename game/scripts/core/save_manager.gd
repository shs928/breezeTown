extends RefCounted
## 存档管理（V2 PRD 第 27/28 节）：把世界状态写入磁盘，而不是保存场景树。
## 目录布局 user://saves/slot_<n>/：meta.json（概要）+ world.json（完整世界）
## + backup/world.prev.json（上一次世界快照，用于回退与崩溃恢复）。
## JSON 键统一为字符串；领域对象各自负责 to_dict/from_dict。

const VERSION := 1
const SAVE_ROOT := "user://saves"
static var _world_id := "breeze_valley"


static func select_world(map_id: String) -> void:
	_world_id = map_id.validate_filename()


static func slot_dir(slot: int) -> String:
	var root := OS.get_environment("BREEZETOWN_SAVE_ROOT")
	if root.is_empty(): root = SAVE_ROOT
	# Retain legacy slots in place; each new geography gets its own saves.
	if _world_id != "breeze_valley": root = root.path_join(_world_id)
	return "%s/slot_%d" % [root, slot]


static func save_game(slot: int, payload: Dictionary) -> Dictionary:
	## 写入存档；返回 {"ok": bool, "path": String, "error": String}。
	var dir := slot_dir(slot)
	var backup := dir + "/backup"
	DirAccess.make_dir_recursive_absolute(backup)
	var world_path := dir + "/world.json"
	if FileAccess.file_exists(world_path):
		DirAccess.rename_absolute(world_path, backup + "/world.prev.json")
	var world_file := FileAccess.open(world_path, FileAccess.WRITE)
	if world_file == null:
		return {"ok": false, "path": world_path, "error": "无法写入 %s" % world_path}
	world_file.store_string(JSON.stringify(payload, "  "))
	world_file.close()
	var meta := {
		"version": VERSION,
		"day": payload.get("clock", {}).get("day", 1),
		"season": payload.get("clock", {}).get("season", ""),
		"saved_at": Time.get_datetime_string_from_system(),
		"coins": payload.get("economy", {}).get("coins", 0),
	}
	var meta_file := FileAccess.open(dir + "/meta.json", FileAccess.WRITE)
	if meta_file != null:
		meta_file.store_string(JSON.stringify(meta, "  "))
		meta_file.close()
	EventBus.instance().save_written.emit(world_path)
	return {"ok": true, "path": world_path, "error": ""}


static func load_game(slot: int) -> Dictionary:
	## 读取存档；损坏或缺失返回空字典并带 "error"。
	var world_path := slot_dir(slot) + "/world.json"
	if not FileAccess.file_exists(world_path):
		return {"ok": false, "error": "存档不存在：%s" % world_path}
	var file := FileAccess.open(world_path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "无法读取 %s" % world_path}
	# POLISH-04：get_as_text 在 release 导出模板（4.7.1/4.7.2 Windows）会触发退出
	# 时堆损坏段错误，统一改用 get_buffer + get_string_from_utf8。
	var parsed: Variant = JSON.parse_string(_read_text(file))
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		# 主档损坏时尝试上一次备份。
		var backup_path := slot_dir(slot) + "/backup/world.prev.json"
		if FileAccess.file_exists(backup_path):
			var backup_file := FileAccess.open(backup_path, FileAccess.READ)
			parsed = JSON.parse_string(_read_text(backup_file))
			backup_file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"ok": false, "error": "存档已损坏"}
	parsed["ok"] = true
	return parsed


static func has_save(slot: int) -> bool:
	return FileAccess.file_exists(slot_dir(slot) + "/world.json")


static func _read_text(file: FileAccess) -> String:
	## POLISH-04：get_as_text() 在 release 导出模板（Godot 4.7.1/4.7.2 Windows）
	## 会在进程退出时触发堆损坏段错误；get_buffer + get_string_from_utf8 无此问题。
	return file.get_buffer(file.get_length()).get_string_from_utf8()
