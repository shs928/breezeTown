extends SceneTree
## DATA-00 存档实验主探针（headless）。
## 运行：godot --headless --path work/save-spike --script res://test_runner.gd
## 覆盖：真实双进程锁竞争、残留锁恢复、活跃锁拒绝、代际发布与轮转、
##       write/verify/publish/cleanup 四阶段故障注入、损坏最新代回退、未来格式跳过。
## 退出码 0=全部通过；1=失败。实验数据写入 res://run/（不入库）。

const SaveSpike := preload("res://save_spike.gd")

var _checks := 0
var _failures: PackedStringArray = []
var _run_root := ""


func _initialize() -> void:
	_run_root = ProjectSettings.globalize_path("res://run/%d" % Time.get_unix_time_from_system())
	DirAccess.make_dir_recursive_absolute(_run_root)

	_test_two_process_lock_race()
	_test_stale_lock_recovery()
	_test_alive_foreign_lock()
	_test_publish_and_rotation()
	_test_fault_injection()
	_test_corrupt_latest_generation()
	_test_future_format()

	if _failures.is_empty():
		print("SAVE_SPIKE_OK checks=%d run_dir=%s" % [_checks, _run_root])
		quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: " + failure)
		printerr("SAVE_SPIKE_FAILED checks=%d failures=%d" % [_checks, _failures.size()])
		quit(1)


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(label)


func _new_world(name: String) -> String:
	var path := _run_root + "/" + name
	DirAccess.make_dir_recursive_absolute(path)
	return path


# ---------- 1. 真实双进程锁竞争 ----------

func _test_two_process_lock_race() -> void:
	var world := _new_world("lock_race")
	DirAccess.make_dir_recursive_absolute(world + "/snapshots")
	var claim := SaveSpike.claim_lock(world)
	_check(claim["ok"], "parent claims lock first")

	# 用当前引擎二进制启动第二个真实进程竞争同一世界。
	var engine := OS.get_executable_path()
	var project := ProjectSettings.globalize_path("res://")
	var output: Array = []
	OS.execute(engine, PackedStringArray([
		"--headless", "--path", project, "--script", "res://claim_probe.gd",
		"--", "--world-dir=" + world,
	]), output, true)
	var child_out := "\n".join(output)
	_check(child_out.contains("locked_alive"),
		"second process rejected by live lock (out=%s)" % child_out.replace("\n", " | "))

	_check(SaveSpike.release_lock(world), "parent releases lock")

	# 释放后子进程应能取得锁（再次运行探针）。
	OS.execute(engine, PackedStringArray([
		"--headless", "--path", project, "--script", "res://claim_probe.gd",
		"--", "--world-dir=" + world,
	]), output, true)
	_check("\n".join(output).contains('"reason":"claimed"'),
		"child claims after release")


# ---------- 2. 残留锁恢复（持锁进程已死） ----------

func _test_stale_lock_recovery() -> void:
	var world := _new_world("stale_lock")
	DirAccess.make_dir_recursive_absolute(world + "/" + SaveSpike.LOCK_DIR)
	var f := FileAccess.open(world + "/" + SaveSpike.LOCK_DIR + "/lock.json", FileAccess.WRITE)
	# macOS pid 上限 99999：999999999 必然不存在的进程。
	f.store_string(JSON.stringify({"pid": 999999999, "started_at": 0.0}))
	f.close()
	var claim := SaveSpike.claim_lock(world)
	_check(claim["ok"] and claim["reason"] == "claimed_stale_recovered",
		"stale lock safely recovered (%s)" % str(claim["reason"]))
	SaveSpike.release_lock(world)


# ---------- 3. 活跃外部进程锁拒绝 ----------

func _test_alive_foreign_lock() -> void:
	var world := _new_world("alive_lock")
	DirAccess.make_dir_recursive_absolute(world + "/" + SaveSpike.LOCK_DIR)
	# 用自己创建的存活进程模拟“别人正开着世界”（macOS 上 kill -0 对 root 进程返回 EPERM，
	# 不能用 pid 1；锁持有者与检测者同用户，语义等价于房主进程）。
	var foreign_pid := OS.create_process("sleep", ["30"])
	_check(foreign_pid > 0, "helper process spawned for alive-lock test")
	var f := FileAccess.open(world + "/" + SaveSpike.LOCK_DIR + "/lock.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"pid": foreign_pid, "started_at": 0.0}))
	f.close()
	var claim := SaveSpike.claim_lock(world)
	_check(not claim["ok"] and claim["reason"] == "locked_alive",
		"lock held by live foreign process rejected")
	# 清理辅助进程。
	var kill_out: Array = []
	OS.execute("kill", PackedStringArray([str(foreign_pid)]), kill_out, true)


# ---------- 4. 发布与轮转 ----------

func _test_publish_and_rotation() -> void:
	var world := _new_world("publish")
	var world_id := "w" + "0123456789abcdef0123456789abcdef"
	for gen in range(1, 8):
		var result := SaveSpike.publish(world, world_id, gen, {"day": gen, "treasury": 300 + gen})
		_check(result["ok"], "publish gen %d" % gen)
	var load := SaveSpike.load_latest(world)
	_check(load["ok"] and load["generation"] == 7, "latest generation is 7")
	_check(load["envelope"]["payload_json"].contains("\"day\":7"), "payload content roundtrip")
	var da := DirAccess.open(world + "/snapshots")
	_check(not da.file_exists("1.json") and not da.file_exists("2.json"), "rotation removed gens 1,2")
	for gen in [3, 4, 5, 6, 7]:
		_check(da.file_exists("%d.json" % gen), "generation %d retained" % gen)
	_check(load["envelope"]["payload_sha256"] == (load["envelope"]["payload_json"] as String).sha256_text(),
		"checksum valid on load")


# ---------- 5. 故障注入 ----------

func _test_fault_injection() -> void:
	for stage in ["write", "verify", "publish", "cleanup"]:
		var world := _new_world("fault_" + stage)
		var world_id := "w" + "0123456789abcdef0123456789abcdef"
		var good := SaveSpike.publish(world, world_id, 1, {"day": 1})
		_check(good["ok"], "baseline gen 1 before fault %s" % stage)
		var injected := SaveSpike.publish(world, world_id, 2, {"day": 2}, stage)
		if stage == "cleanup":
			_check(injected["ok"], "cleanup injection leaves state consistent")
		else:
			_check(not injected["ok"] and injected["stage"] == stage,
				"fault injected at %s" % stage)
		var load := SaveSpike.load_latest(world)
		if stage == "cleanup":
			# cleanup 失败只意味着轮转未执行；已发布的 gen 2 是完整的，应正常加载。
			_check(load["ok"] and load["generation"] == 2,
				"cleanup failure: published gen 2 still loads (got gen %d)" % load["generation"])
		else:
			_check(load["ok"] and load["generation"] == 1,
				"previous valid generation loads after %s failure (got gen %d)" % [stage, load["generation"]])
		if stage != "cleanup":
			var da := DirAccess.open(world + "/snapshots")
			_check(not da.file_exists("2.json"),
				"failed publish never published partial gen 2 (%s)" % stage)
			# verify/publish 阶段失败会留下 .tmp-* 供诊断；DirAccess 列目录可能隐藏点文件，
			# 用 file_exists 精确检查。
			if stage != "write":
				_check(da.file_exists(".tmp-2.json"), "temp file kept for diagnosis (%s)" % stage)


# ---------- 6. 损坏最新代回退 ----------

func _test_corrupt_latest_generation() -> void:
	var world := _new_world("corrupt")
	var world_id := "w" + "0123456789abcdef0123456789abcdef"
	SaveSpike.publish(world, world_id, 1, {"day": 1})
	SaveSpike.publish(world, world_id, 2, {"day": 2})
	# 截断最新代：写入垃圾字节。
	var f := FileAccess.open(world + "/snapshots/2.json", FileAccess.WRITE)
	f.store_string("{\"format_version\":1,tru")
	f.close()
	var load := SaveSpike.load_latest(world)
	_check(load["ok"] and load["generation"] == 1, "corrupt latest falls back to gen 1")
	_check(_rejected_contains(load["rejected"], 2, "unparseable"), "corruption reason recorded")
	# 原件保留，不被加载器删除。
	var da := DirAccess.open(world + "/snapshots")
	_check(da.file_exists("2.json"), "corrupt file preserved for inspection")


# ---------- 7. 未来格式跳过 ----------

func _test_future_format() -> void:
	var world := _new_world("future")
	var world_id := "w" + "0123456789abcdef0123456789abcdef"
	SaveSpike.publish(world, world_id, 1, {"day": 1})
	var f := FileAccess.open(world + "/snapshots/2.json", FileAccess.WRITE)
	var payload := JSON.stringify({"day": 2})
	f.store_string(JSON.stringify({
		"format_version": 99, "world_id": world_id, "generation": 2,
		"payload_json": payload, "payload_sha256": payload.sha256_text(),
	}))
	f.close()
	var load := SaveSpike.load_latest(world)
	_check(load["ok"] and load["generation"] == 1, "future format skipped, gen 1 loads")
	_check(_rejected_contains(load["rejected"], 2, "future_or_unknown_format"),
		"future format reason recorded")


func _list_files(dir_path: String) -> Array[String]:
	var files: Array[String] = []
	var da := DirAccess.open(dir_path)
	if da == null:
		return files
	da.list_dir_begin()
	var name := da.get_next()
	while not name.is_empty():
		if not da.current_is_dir():
			files.append(name)
		name = da.get_next()
	da.list_dir_end()
	return files


func _rejected_contains(rejected: Array, generation: int, reason: String) -> bool:
	for entry: Dictionary in rejected:
		if entry["generation"] == generation and entry["reason"] == reason:
			return true
	return false
