extends Object
## DATA-00 存档实验库：目录锁与代际快照发布的最小可验证实现。
## 这是独立实验代码（spike），不进入正式工程；正式 WorldRepository 是 DATA-01 的工作。
##
## 锁方案（候选）：对 runtime.lock.d 目录执行 mkdir —— mkdir 是原子系统调用，
## 目录存在则创建失败，天然互斥；目录内 lock.json 记录 pid 等信息。
## 残留锁的恢复必须先做活性检查（kill -0），不允许“见到锁文件就删”。
##
## 发布方案（候选）：写临时文件 → flush/close → 重新读取并校验 checksum/可解析性
## → rename 为唯一 generation 文件（发布前目标不存在，POSIX rename 原子）
## → 轮转只删超出保留数的旧代；校验失败不删除任何文件（保留证据）。
##
## 故障注入：通过 fail_stage 参数在 write/verify/publish/cleanup 四个阶段中止，
## 用于验证“上一有效代仍可加载”。

const KEEP_GENERATIONS := 5
const FORMAT_VERSION := 1
const LOCK_DIR := "runtime.lock.d"


# ================= 进程锁 =================

## 尝试取得世界写锁。返回 {ok: bool, reason: String, pid: int}。
static func claim_lock(world_dir: String) -> Dictionary:
	var da := DirAccess.open(world_dir)
	if da == null:
		return {"ok": false, "reason": "world_dir_missing", "pid": 0}
	if da.make_dir(LOCK_DIR) == OK:
		var info := {"pid": OS.get_process_id(), "started_at": Time.get_unix_time_from_system()}
		var f := FileAccess.open(world_dir + "/" + LOCK_DIR + "/lock.json", FileAccess.WRITE)
		if f == null:
			return {"ok": false, "reason": "lock_info_write_failed", "pid": 0}
		f.store_string(JSON.stringify(info))
		f.close()
		return {"ok": true, "reason": "claimed", "pid": OS.get_process_id()}
	# mkdir 失败：锁目录已存在。区分活跃锁与残留锁。
	var existing := _read_lock_info(world_dir)
	if existing.is_empty():
		return {"ok": false, "reason": "locked_unreadable", "pid": 0}
	if _pid_alive(int(existing["pid"])):
		return {"ok": false, "reason": "locked_alive", "pid": int(existing["pid"])}
	# 残留锁：持锁进程已死，安全接管。先拆掉旧目录再竞争（若并发竞争失败则下次再检测）。
	if not _remove_lock_dir(world_dir):
		return {"ok": false, "reason": "stale_lock_removal_failed", "pid": int(existing["pid"])}
	if da.make_dir(LOCK_DIR) == OK:
		var info2 := {"pid": OS.get_process_id(), "started_at": Time.get_unix_time_from_system(), "recovered_stale": true, "stale_pid": int(existing["pid"])}
		var f2 := FileAccess.open(world_dir + "/" + LOCK_DIR + "/lock.json", FileAccess.WRITE)
		if f2 == null:
			return {"ok": false, "reason": "lock_info_write_failed", "pid": 0}
		f2.store_string(JSON.stringify(info2))
		f2.close()
		return {"ok": true, "reason": "claimed_stale_recovered", "pid": OS.get_process_id()}
	return {"ok": false, "reason": "locked_by_racer", "pid": 0}


static func release_lock(world_dir: String) -> bool:
	return _remove_lock_dir(world_dir)


static func _remove_lock_dir(world_dir: String) -> bool:
	var da := DirAccess.open(world_dir + "/" + LOCK_DIR)
	if da == null:
		return true  # 锁目录不存在视为已释放
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


static func _read_lock_info(world_dir: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(world_dir + "/" + LOCK_DIR + "/lock.json")
	if text.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if parsed is not Dictionary or not (parsed as Dictionary).has("pid"):
		return {}
	return parsed


## 跨平台进程存活检测（Godot 4）：Unix 内部即 kill(pid,0)；Windows 用 OpenProcess。
## 原 kill -0 直调在 Windows 无此命令；Windows 路线已在 win64 实机验证，见 docs/adr/DATA-00.md。
static func _pid_alive(pid: int) -> bool:
	if pid <= 0:
		return false
	return OS.is_process_running(pid)


# ================= 代际发布 =================

## 发布一个 generation。返回 {ok, stage, generation}。
static func publish(world_dir: String, world_id: String, generation: int, payload: Dictionary, fail_stage := "") -> Dictionary:
	var payload_json := JSON.stringify(payload)
	var envelope := {
		"format_version": FORMAT_VERSION,
		"world_id": world_id,
		"generation": generation,
		"payload_json": payload_json,
		"payload_sha256": payload_json.sha256_text(),
	}
	var snapshots_dir := world_dir + "/snapshots"
	DirAccess.make_dir_recursive_absolute(snapshots_dir)
	var tmp_name := ".tmp-%d.json" % generation
	var final_name := "%d.json" % generation

	if fail_stage == "write":
		return {"ok": false, "stage": "write", "generation": generation}
	var f := FileAccess.open(snapshots_dir + "/" + tmp_name, FileAccess.WRITE)
	if f == null:
		return {"ok": false, "stage": "write", "generation": generation}
	f.store_string(JSON.stringify(envelope))
	f.flush()
	f.close()

	if fail_stage == "verify":
		return {"ok": false, "stage": "verify", "generation": generation}
	# 验证：重新读取实际写入字节，校验 checksum 与可解析性。
	var readback := FileAccess.get_file_as_string(snapshots_dir + "/" + tmp_name)
	var parsed: Variant = JSON.parse_string(readback)
	if parsed is not Dictionary:
		return {"ok": false, "stage": "verify", "generation": generation}
	var back: Dictionary = parsed
	if back.get("payload_sha256", "") != envelope["payload_sha256"]:
		return {"ok": false, "stage": "verify", "generation": generation}

	if fail_stage == "publish":
		return {"ok": false, "stage": "publish", "generation": generation}
	var da := DirAccess.open(snapshots_dir)
	if da == null or da.file_exists(final_name):
		return {"ok": false, "stage": "publish", "generation": generation}
	if da.rename(tmp_name, final_name) != OK:
		return {"ok": false, "stage": "publish", "generation": generation}

	if fail_stage == "cleanup":
		return {"ok": true, "stage": "cleanup_injected", "generation": generation}
	_rotate(snapshots_dir)
	return {"ok": true, "stage": "published", "generation": generation}


## 只保留最近 KEEP_GENERATIONS 个有效代；.tmp-* 不参与轮转判断。
static func _rotate(snapshots_dir: String) -> void:
	var gens := _list_generations(snapshots_dir)
	if gens.size() <= KEEP_GENERATIONS:
		return
	var da := DirAccess.open(snapshots_dir)
	if da == null:
		return
	for i in range(0, gens.size() - KEEP_GENERATIONS):
		da.remove("%d.json" % gens[i])


static func _list_generations(snapshots_dir: String) -> Array[int]:
	var result: Array[int] = []
	var da := DirAccess.open(snapshots_dir)
	if da == null:
		return result
	da.list_dir_begin()
	var name := da.get_next()
	while not name.is_empty():
		if not da.current_is_dir() and name.ends_with(".json") and not name.begins_with(".tmp-"):
			var gen := int(name.get_basename())
			if str(gen) == name.get_basename():
				result.append(gen)
		name = da.get_next()
	da.list_dir_end()
	result.sort()
	return result


## 加载最新有效代：从高到低扫描，损坏/未来格式跳过并记录，**不删除任何文件**。
## 返回 {ok, generation, envelope, rejected: [{generation, reason}]}。
static func load_latest(world_dir: String) -> Dictionary:
	var snapshots_dir := world_dir + "/snapshots"
	var rejected: Array = []
	var gens := _list_generations(snapshots_dir)
	gens.reverse()  # 从最高代开始
	for gen in gens:
		var text := FileAccess.get_file_as_string(snapshots_dir + "/%d.json" % gen)
		var parsed: Variant = JSON.parse_string(text)
		var reason := ""
		if parsed is not Dictionary:
			reason = "unparseable"
		else:
			reason = _validate_envelope(parsed)
		if reason.is_empty():
			return {"ok": true, "generation": gen, "envelope": parsed, "rejected": rejected}
		rejected.append({"generation": gen, "reason": reason})
	return {"ok": false, "generation": 0, "envelope": {}, "rejected": rejected}


## 最小 envelope 校验（spike 自带；正式契约见 game/src/contracts/contract_envelopes.gd）。
static func _validate_envelope(env: Dictionary) -> String:
	var required := ["format_version", "world_id", "generation", "payload_json", "payload_sha256"]
	for key in required:
		if not env.has(key):
			return "missing:" + key
	if env["format_version"] != FORMAT_VERSION:
		return "future_or_unknown_format"
	var payload_json: String = env["payload_json"]
	if payload_json.sha256_text() != env["payload_sha256"]:
		return "checksum_mismatch"
	if JSON.parse_string(payload_json) == null:
		return "payload_not_json"
	return ""
