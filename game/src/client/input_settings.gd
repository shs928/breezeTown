class_name InputSettings
## 输入与设置（UI 唯一维护，M5 UI-06；PRD 4.4 / CASE-38）。
## 键位重绑定、冲突检测、恢复默认；设置持久化到用户目录（不写世界存档）。

const ContractLimits := preload("res://src/contracts/contract_limits.gd")

const DEFAULT_BINDINGS := {
	"move_up": "W",
	"move_down": "S",
	"move_left": "A",
	"move_right": "D",
	"interact": "E",
	"inventory": "TAB",
	"leaderboard": "L",
	"menu": "ESCAPE",
	"hotbar_1": "1", "hotbar_2": "2", "hotbar_3": "3",
	"hotbar_4": "4", "hotbar_5": "5", "hotbar_6": "6",
}
const REBINDABLE: PackedStringArray = [
	"move_up", "move_down", "move_left", "move_right",
	"interact", "inventory", "leaderboard", "menu",
	"hotbar_1", "hotbar_2", "hotbar_3", "hotbar_4", "hotbar_5", "hotbar_6",
]

var bindings: Dictionary = {}
var master_volume := 0.8
var sfx_volume := 0.8
var ui_scale := 1.0
var fullscreen := false

var _path := ""


func load_or_default(user_data_dir: String) -> void:
	_path = user_data_dir + "/input_settings.json"
	bindings = DEFAULT_BINDINGS.duplicate(true)
	if not FileAccess.file_exists(_path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(_path))
	if parsed is not Dictionary:
		return
	var data: Dictionary = parsed
	if data.get("bindings", null) is Dictionary:
		for action: String in (data["bindings"] as Dictionary):
			if action in REBINDABLE:
				bindings[action] = str(data["bindings"][action])
	master_volume = clampf(float(data.get("master_volume", 0.8)), 0.0, 1.0)
	sfx_volume = clampf(float(data.get("sfx_volume", 0.8)), 0.0, 1.0)
	ui_scale = clampf(float(data.get("ui_scale", 1.0)), 1.0, 1.5)
	fullscreen = bool(data.get("fullscreen", false))


func save() -> bool:
	if _path.is_empty():
		return false
	DirAccess.make_dir_recursive_absolute(_path.get_base_dir())
	var f := FileAccess.open(_path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify({
		"bindings": bindings, "master_volume": master_volume,
		"sfx_volume": sfx_volume, "ui_scale": ui_scale, "fullscreen": fullscreen,
	}))
	f.flush()
	f.close()
	return true


## 重绑定一个动作。返回 {ok, error, conflict_with}。
## 冲突时不修改任何绑定（整笔失败）。
func rebind(action: String, key: String) -> Dictionary:
	if not action in REBINDABLE:
		return {"ok": false, "error": "not_rebindable", "conflict_with": ""}
	var normalized := key.to_upper()
	if normalized.is_empty():
		return {"ok": false, "error": "empty_key", "conflict_with": ""}
	for other: String in bindings:
		if other != action and str(bindings[other]).to_upper() == normalized:
			return {"ok": false, "error": "conflict", "conflict_with": other}
	bindings[action] = normalized
	save()
	return {"ok": true, "error": "", "conflict_with": ""}


func restore_defaults() -> void:
	bindings = DEFAULT_BINDINGS.duplicate(true)
	save()


func binding_of(action: String) -> String:
	return str(bindings.get(action, ""))


## 冲突检查：返回全部重复键位。
func conflicts() -> Array:
	var seen := {}
	var result: Array = []
	for action: String in bindings:
		var key := str(bindings[action]).to_upper()
		if seen.has(key):
			result.append({"key": key, "actions": [seen[key], action]})
		else:
			seen[key] = action
	return result
