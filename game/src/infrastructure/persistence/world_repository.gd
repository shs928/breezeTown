class_name WorldRepository
## 正式世界持久化（DATA 唯一维护）。复用 DATA-00 已验证的方案与契约 v1 envelope：
## 原子目录锁 + 临时写/验证/rename 发布 + 5 代轮转；加载从高到低扫描，损坏/未来格式跳过且不删除文件。
##
## 布局：<world_dir>/
##   runtime.lock.d/lock.json
##   snapshots/<generation>.json     （envelope 格式，见 ContractEnvelopes）
##   backups/<backup_id>/<generation>.json
##
## 本类不做生长/币值计算，不联网（契约 3.1 的禁止事项）。

const ContractLimits := preload("res://src/contracts/contract_limits.gd")
const ContractEnvelopes := preload("res://src/contracts/contract_envelopes.gd")
const WorldState := preload("res://src/domain/world/world_state.gd")

const LOCK_DIR := "runtime.lock.d"

var world_dir := ""
var world_id := ""
var _locked := false


# ================= 进程锁 =================

func claim_lock() -> Dictionary:
	if world_dir.is_empty():
		return {"ok": false, "reason": "no_world_dir"}
	var da := DirAccess.open(world_dir)
	if da == null:
		return {"ok": false, "reason": "world_dir_missing"}
	if da.make_dir(LOCK_DIR) == OK:
		_write_lock_info({"pid": OS.get_process_id()})
		_locked = true
		return {"ok": true, "reason": "claimed"}
	var existing := _read_lock_info()
	if existing.is_empty():
		return {"ok": false, "reason": "locked_unreadable"}
	if _pid_alive(int(existing["pid"])):
		return {"ok": false, "reason": "locked_alive", "pid": int(existing["pid"])}
	# 残留锁（持锁进程已死）→ 安全接管
	if not _remove_lock_dir():
		return {"ok": false, "reason": "stale_lock_removal_failed"}
	if da.make_dir(LOCK_DIR) != OK:
		return {"ok": false, "reason": "locked_by_racer"}
	_write_lock_info({"pid": OS.get_process_id(), "recovered_stale": int(existing["pid"])})
	_locked = true
	return {"ok": true, "reason": "claimed_stale_recovered"}


func release_lock() -> void:
	if _locked:
		_remove_lock_dir()
		_locked = false


func _write_lock_info(info: Dictionary) -> void:
	var f := FileAccess.open(world_dir + "/" + LOCK_DIR + "/lock.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(info))
		f.close()


func _read_lock_info() -> Dictionary:
	var text := FileAccess.get_file_as_string(world_dir + "/" + LOCK_DIR + "/lock.json")
	if text.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(text)
	return parsed if parsed is Dictionary and (parsed as Dictionary).has("pid") else {}


func _pid_alive(pid: int) -> bool:
	if pid <= 0:
		return false
	var output: Array = []
	OS.execute("kill", PackedStringArray(["-0", str(pid)]), output, true)
	return not output.is_empty() and int(str(output[0])) == 0


func _remove_lock_dir() -> bool:
	var da := DirAccess.open(world_dir + "/" + LOCK_DIR)
	if da == null:
		return true
	da.list_dir_begin()
	var name := da.get_next()
	var files: Array[String] = []
	while not name.is_empty():
		if not da.current_is_dir():
			files.append(name)
		name = da.get_next()
	da.list_dir_end()
	for file in files:
		da.remove(file)
	var parent := DirAccess.open(world_dir)
	return parent != null and parent.remove(LOCK_DIR) == OK


# ================= 保存 =================

## 保存一个完整快照。返回 {ok, generation, error}。
## 失败不破坏上一有效代；调用方负责进入保存故障状态。
func save(world: WorldState) -> Dictionary:
	if world_dir.is_empty():
		return {"ok": false, "generation": 0, "error": "no_world_dir"}
	var snapshots_dir := world_dir + "/snapshots"
	DirAccess.make_dir_recursive_absolute(snapshots_dir)
	var generation := _next_generation(snapshots_dir)
	var payload_json := JSON.stringify(world.to_dict())
	var envelope := ContractEnvelopes.make_save_envelope(world.world_id, generation, payload_json)
	var envelope_err := ContractEnvelopes.validate_save_envelope(envelope)
	if not envelope_err.is_empty():
		return {"ok": false, "generation": 0, "error": envelope_err}
	var tmp_path := snapshots_dir + "/.tmp-%d.json" % generation
	var final_path := snapshots_dir + "/%d.json" % generation
	var f := FileAccess.open(tmp_path, FileAccess.WRITE)
	if f == null:
		return {"ok": false, "generation": 0, "error": "write_failed"}
	f.store_string(JSON.stringify(envelope))
	f.flush()
	f.close()
	# 验证实际写入字节
	var readback := FileAccess.get_file_as_string(tmp_path)
	var parsed: Variant = JSON.parse_string(readback)
	if parsed is not Dictionary or (parsed as Dictionary).get("payload_sha256", "") != envelope["payload_sha256"]:
		return {"ok": false, "generation": 0, "error": "verify_failed"}
	var da := DirAccess.open(snapshots_dir)
	if da == null or da.file_exists("%d.json" % generation):
		return {"ok": false, "generation": 0, "error": "publish_conflict"}
	if da.rename(".tmp-%d.json" % generation, "%d.json" % generation) != OK:
		return {"ok": false, "generation": 0, "error": "publish_failed"}
	_rotate(snapshots_dir)
	return {"ok": true, "generation": generation, "error": ""}


func _next_generation(snapshots_dir: String) -> int:
	var gens := _list_generations(snapshots_dir)
	return (int(gens[-1]) + 1) if not gens.is_empty() else 1


func _rotate(snapshots_dir: String) -> void:
	var gens := _list_generations(snapshots_dir)
	if gens.size() <= ContractLimits.SNAPSHOT_KEEP_GENERATIONS:
		return
	var da := DirAccess.open(snapshots_dir)
	if da == null:
		return
	for i in range(0, gens.size() - ContractLimits.SNAPSHOT_KEEP_GENERATIONS):
		da.remove("%d.json" % gens[i])


func _list_generations(snapshots_dir: String) -> Array[int]:
	var result: Array[int] = []
	var da := DirAccess.open(snapshots_dir)
	if da == null:
		return result
	da.list_dir_begin()
	var name := da.get_next()
	while not name.is_empty():
		if not da.current_is_dir() and name.ends_with(".json") and not name.begins_with(".tmp-"):
			var base := name.get_basename()
			if str(int(base)) == base:
				result.append(int(base))
		name = da.get_next()
	da.list_dir_end()
	result.sort()
	return result


# ================= 加载 =================

## 加载最新有效代。返回 {ok, world, generation, rejected}。
func load_latest() -> Dictionary:
	var snapshots_dir := world_dir + "/snapshots"
	var gens := _list_generations(snapshots_dir)
	gens.reverse()
	var rejected: Array = []
	for generation in gens:
		var text := FileAccess.get_file_as_string(snapshots_dir + "/%d.json" % generation)
		var parsed: Variant = normalize_numbers(JSON.parse_string(text))
		var reason := ""
		if parsed is not Dictionary:
			reason = "unparseable"
		else:
			reason = ContractEnvelopes.validate_save_envelope(parsed)
		if reason.is_empty():
			var world := _world_from_envelope(parsed)
			if world == null:
				rejected.append({"generation": generation, "reason": "structure_invalid"})
				continue
			return {"ok": true, "world": world, "generation": generation, "rejected": rejected}
		rejected.append({"generation": generation, "reason": reason})
	return {"ok": false, "world": null, "generation": 0, "rejected": rejected}


## JSON 把所有数字解析为 float；契约 4.2 要求解析后重新校验。
## 把整值 float 归一化为 int（非整值保留，交由校验器按小数拒绝）。
static func normalize_numbers(value: Variant) -> Variant:
	if value is Array:
		var out: Array = []
		for item: Variant in value:
			out.append(normalize_numbers(item))
		return out
	if value is Dictionary:
		var out := {}
		for key: Variant in value:
			out[key] = normalize_numbers(value[key])
		return out
	if value is float:
		var as_int := int(value)
		if is_equal_approx(value, float(as_int)):
			return as_int
	return value


func _world_from_envelope(envelope: Dictionary) -> WorldState:
	var payload: Variant = JSON.parse_string(envelope["payload_json"])
	if payload is not Dictionary:
		return null
	var data: Dictionary = payload
	var world: WorldState = WorldState.create(str(data["world_id"]), str(data["owner_player_id"]), "占位")
	# 用持久化数据覆盖（保持与 to_dict 字段一致）
	world.game_day = int(data["game_day"])
	world.day_elapsed_ms = int(data["day_elapsed_ms"])
	world.business_revision = int(data["business_revision"])
	world.next_event_seq = int(data["next_event_seq"])
	world.treasury = int(data["treasury"])
	world.members = data["members"]
	world.plots = data["plots"]
	world.crops = data["crops"]
	world.projects = data["projects"]
	world.containers = data["containers"]
	world.stats = data["stats"]
	world.publication_enabled = bool(data["publication_enabled"])
	world.consent_revision = int(data["consent_revision"])
	world.schema_version = int(data["schema_version"])
	world.ruleset_version = str(data["ruleset_version"])
	world.content_hash = str(data["content_hash"])
	world.sim_tick = int(data.get("sim_tick", 0))
	world.authority_epoch = "e" + Crypto.new().generate_random_bytes(16).hex_encode()  # 恢复后新 epoch
	return world


## 手动备份（不被自动轮转删除）。
func backup_now() -> Dictionary:
	var backup_id := "manual-%d" % Time.get_unix_time_from_system()
	var backup_dir := world_dir + "/backups/" + backup_id
	DirAccess.make_dir_recursive_absolute(backup_dir)
	var snapshots_dir := world_dir + "/snapshots"
	var gens := _list_generations(snapshots_dir)
	if gens.is_empty():
		return {"ok": false, "backup_id": backup_id, "error": "no_snapshot"}
	var latest := "%d.json" % gens[-1]
	var content := FileAccess.get_file_as_string(snapshots_dir + "/" + latest)
	var f := FileAccess.open(backup_dir + "/" + latest, FileAccess.WRITE)
	if f == null:
		return {"ok": false, "backup_id": backup_id, "error": "write_failed"}
	f.store_string(content)
	f.close()
	return {"ok": true, "backup_id": backup_id, "error": ""}


## 显式恢复旧代：保留原件、生成新 epoch、清空全部凭据绑定与公开同意。
## 契约 8.4：防止旧快照复活已撤销凭据或已撤回授权。
func restore_generation(generation: int) -> Dictionary:
	var snapshots_dir := world_dir + "/snapshots"
	var path := snapshots_dir + "/%d.json" % generation
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "generation_not_found"}
	# 先把原文件复制一份保全证据
	var preserve_dir := world_dir + "/restore_preserved"
	DirAccess.make_dir_recursive_absolute(preserve_dir)
	var original := FileAccess.get_file_as_string(path)
	var pf := FileAccess.open(preserve_dir + "/%d-before-restore.json" % generation, FileAccess.WRITE)
	if pf != null:
		pf.store_string(original)
		pf.close()
	var parsed: Variant = normalize_numbers(JSON.parse_string(original))
	if parsed is not Dictionary:
		return {"ok": false, "error": "unparseable"}
	var world := _world_from_envelope(parsed)
	if world == null:
		return {"ok": false, "error": "structure_invalid"}
	# 清空身份绑定与公开同意（必须经本机停服维护重新绑定）
	for member: Dictionary in world.members:
		member["credential_digest"] = ""
		member["publication_consent"] = false
		member["public_alias"] = ""
	world.publication_enabled = false
	world.consent_revision += 1
	# 发布为一个新代（不覆盖原代）
	var save_result := save(world)
	if not save_result["ok"]:
		return {"ok": false, "error": "restore_save_failed:" + str(save_result["error"])}
	return {"ok": true, "error": "", "world": world, "generation": int(save_result["generation"])}


## 本机停服维护恢复所有者（仅在无活跃锁时允许）。
## 契约 8.4 / PRD 4.2：远程接口不能声称自己是房主来恢复所有者。
func maintenance_restore_owner(new_owner_digest: String) -> Dictionary:
	if _locked:
		return {"ok": false, "error": "world_still_locked"}
	if new_owner_digest.length() != 64:
		return {"ok": false, "error": "bad_digest"}
	var loaded := load_latest()
	if not loaded["ok"]:
		return {"ok": false, "error": "load_failed"}
	var world: WorldState = loaded["world"]
	var owner: Dictionary = world.find_member(world.owner_player_id)
	if owner.is_empty():
		return {"ok": false, "error": "owner_missing"}
	owner["credential_digest"] = new_owner_digest
	owner["status"] = "active"
	var save_result := save(world)
	if not save_result["ok"]:
		return {"ok": false, "error": "save_failed"}
	return {"ok": true, "error": "", "owner_player_id": world.owner_player_id}


## schema 迁移：把旧格式 payload 升级到当前版本。返回 {ok, world, error}。
## V1 只有 schema 1；用测试用 schema 0 fixture 验证迁移机制（契约 8.4）。
func migrate_payload(payload: Dictionary) -> Dictionary:
	var version := int(payload.get("schema_version", 0))
	if version == ContractEnvelopes.SAVE_FORMAT_VERSION_CANDIDATE:
		return {"ok": true, "error": "", "migrated": false}
	if version > ContractEnvelopes.SAVE_FORMAT_VERSION_CANDIDATE:
		return {"ok": false, "error": "future_schema_rejected", "migrated": false}
	# schema 0 → 1：补齐 V1 新增字段（默认值），不丢弃已有字段
	var upgraded := payload.duplicate(true)
	upgraded["schema_version"] = 1
	if not upgraded.has("consent_revision"):
		upgraded["consent_revision"] = 0
	if not upgraded.has("publication_enabled"):
		upgraded["publication_enabled"] = false
	if not upgraded.has("sim_tick"):
		upgraded["sim_tick"] = 0
	if not upgraded.has("stats"):
		upgraded["stats"] = {"members": {}, "world_total_sales": 0, "world_total_purchases": 0, "last_applied_event_seq": 0}
	return {"ok": true, "error": "", "migrated": true, "payload": upgraded}


## 列出手动备份（供恢复 UI）。
func list_backups() -> Array:
	var result: Array = []
	var da := DirAccess.open(world_dir + "/backups")
	if da == null:
		return result
	da.list_dir_begin()
	var name := da.get_next()
	while not name.is_empty():
		if da.current_is_dir():
			result.append(name)
		name = da.get_next()
	da.list_dir_end()
	result.sort()
	return result
