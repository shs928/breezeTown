extends SceneTree
## NET-01 实验编排器：真实多进程运行全部场景并核对退出码与凭据泄漏。
## 运行：godot --headless --path work/net-spike --script res://spike_orchestrator.gd
## 场景：受信握手 / 错误证书拒绝 / 重复身份 / 四席位上限 / 待审批队列与TTL / 优雅关服。
## 退出码 0=全部通过。运行数据在 res://run/<ts>/（不入库）。

const NetSpike := preload("res://net_spike.gd")

var _dir := ""
var _failures: PackedStringArray = []
var _scenario := 0


func _initialize() -> void:
	_dir = ProjectSettings.globalize_path("res://run/%d" % Time.get_unix_time_from_system())
	DirAccess.make_dir_recursive_absolute(_dir)

	# 证书对（main=服务器真实身份，decoy=错误证书）
	var certs_dir := _dir + "/certs"
	var gen_out: Array = []
	var engine := OS.get_executable_path()
	var project := ProjectSettings.globalize_path("res://")
	OS.execute(engine, PackedStringArray([
		"--headless", "--path", project, "--script", "res://gen_certs.gd",
		"--", "--out-dir=" + certs_dir,
	]), gen_out, true)
	if not "\n".join(gen_out).contains("CERTS_OK"):
		printerr("cert generation failed: ", "\n".join(gen_out))
		quit(1)
		return
	var main_cert := certs_dir + "/main/server.pem"
	var main_key := certs_dir + "/main/server.key"
	var decoy_cert := certs_dir + "/decoy/server.pem"

	_scenario_1_trusted_handshake(main_cert, main_key)
	_scenario_2_wrong_cert(main_cert, main_key, decoy_cert)
	_scenario_3_duplicate_identity(main_cert, main_key)
	_scenario_4_seat_capacity(main_cert, main_key)
	_scenario_5_approval_queue(main_cert, main_key)
	_scenario_6_graceful_closing(main_cert, main_key)

	if _failures.is_empty():
		print("NET_SPIKE_OK scenarios=6 run_dir=%s" % _dir)
		quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: " + failure)
		printerr("NET_SPIKE_FAILED failures=%d" % _failures.size())
		quit(1)


# ---------- 进程辅助 ----------

func _next_port() -> int:
	_scenario += 1
	return 24500 + _scenario * 7


func _spawn(name: String, args: PackedStringArray) -> int:
	var log_path := _dir + "/" + name + ".log"
	var code_path := _dir + "/" + name + ".code"
	var parts := PackedStringArray()
	parts.append_array([OS.get_executable_path(), "--headless", "--path",
		ProjectSettings.globalize_path("res://")])
	parts.append_array(args)
	var shell := ""
	for part in parts:
		shell += "'%s' " % part
	shell += "> '%s' 2>&1; echo $? > '%s'" % [log_path, code_path]
	return OS.create_process("sh", ["-c", shell])


func _wait_exit(pid: int, code_path: String, budget_s: float) -> int:
	var deadline := Time.get_ticks_msec() + int(budget_s * 1000)
	while Time.get_ticks_msec() < deadline:
		if FileAccess.file_exists(code_path):
			return int(FileAccess.get_file_as_string(code_path).strip_edges())
		OS.delay_msec(100)
	return -999  # 超预算


## 启动客户端进程但**不等待**（并发场景必须先全部启动再统一等待）。
func _start_client(port: int, trust_cert: String, token: String, hold_s := 0.0, wait_s := 8.0) -> Dictionary:
	var name := "cli_p%d_t%d" % [port, Time.get_ticks_msec()]
	OS.set_environment("NET_SPIKE_TOKEN", token)
	var pid := _spawn(name, PackedStringArray([
		"--script", "res://spike_client.gd", "--",
		"--port=%d" % port, "--trust-cert=%s" % trust_cert,
		"--hold-s=%.1f" % hold_s, "--wait-s=%.1f" % wait_s,
	]))
	OS.set_environment("NET_SPIKE_TOKEN", "")
	return {"pid": pid, "name": name, "code": -1000}


func _wait_client(client: Dictionary, hold_s := 0.0, wait_s := 8.0) -> Dictionary:
	var code := _wait_exit(client["pid"], _dir + "/" + client["name"] + ".code", wait_s + hold_s + 30.0)
	client["code"] = code
	return client


func _spawn_client(port: int, trust_cert: String, token: String, hold_s := 0.0, wait_s := 8.0) -> Dictionary:
	var client := _start_client(port, trust_cert, token, hold_s, wait_s)
	return _wait_client(client, hold_s, wait_s)


func _kill(pid: int) -> void:
	if pid > 0 and OS.is_process_running(pid):
		OS.kill(pid)


func _spawn_server(port: int, main_cert: String, main_key: String, approval := "auto", ttl_s := 2.0, max_run_s := 12.0) -> Dictionary:
	var name := "srv_p%d" % port
	var pid := _spawn(name, PackedStringArray([
		"--script", "res://spike_server.gd", "--",
		"--port=%d" % port, "--cert-file=%s" % main_cert, "--key-file=%s" % main_key,
		"--approval=%s" % approval, "--ttl-s=%.1f" % ttl_s, "--max-run-s=%.1f" % max_run_s,
	]))
	# 等待 listening 标记
	var log_path := _dir + "/" + name + ".log"
	var deadline := Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < deadline:
		if FileAccess.file_exists(log_path):
			var text := FileAccess.get_file_as_string(log_path)
			if text.contains("listening"):
				break
			if text.contains("missing") or text.contains("failed"):
				break
		OS.delay_msec(100)
	return {"pid": pid, "name": name}


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures.append(label)


func _scan_logs_for_leak(token: String, label: String) -> void:
	# 凭据原文不得出现在任何日志/退出码文件中。
	for file in _list_log_files():
		var text := FileAccess.get_file_as_string(file)
		if text.contains(token):
			_failures.append("credential leak in %s (%s)" % [file, label])


func _list_log_files() -> Array[String]:
	var files: Array[String] = []
	var da := DirAccess.open(_dir)
	da.list_dir_begin()
	var name := da.get_next()
	while not name.is_empty():
		if not da.current_is_dir() and (name.ends_with(".log") or name.ends_with(".code")):
			files.append(_dir + "/" + name)
		name = da.get_next()
	da.list_dir_end()
	return files


# ---------- 场景 ----------

func _scenario_1_trusted_handshake(main_cert: String, main_key: String) -> void:
	var port := _next_port()
	var srv := _spawn_server(port, main_cert, main_key)
	var token := NetSpike.new_token()
	var cli := _spawn_client(port, main_cert, token)
	_check(cli["code"] == 0, "S1 trusted handshake welcome (code=%s)" % cli["code"])
	_scan_logs_for_leak(token, "S1")
	_kill(srv["pid"])


func _scenario_2_wrong_cert(main_cert: String, main_key: String, decoy_cert: String) -> void:
	var port := _next_port()
	var srv := _spawn_server(port, main_cert, main_key)
	var token := NetSpike.new_token()
	var cli := _spawn_client(port, decoy_cert, token)
	_check(cli["code"] == 2, "S2 wrong cert rejected (code=%s)" % cli["code"])
	_scan_logs_for_leak(token, "S2")
	_kill(srv["pid"])


func _scenario_3_duplicate_identity(main_cert: String, main_key: String) -> void:
	var port := _next_port()
	var srv := _spawn_server(port, main_cert, main_key)
	var token := NetSpike.new_token()
	var holder := _spawn_client(port, main_cert, token, 6.0)  # 保持连接 6 秒
	OS.delay_msec(1500)
	var second := _spawn_client(port, main_cert, token)
	_check(holder["code"] == 0, "S3 first connection welcomed (code=%s)" % holder["code"])
	_check(second["code"] == 3, "S3 duplicate identity rejected (code=%s)" % second["code"])
	_scan_logs_for_leak(token, "S3")
	_kill(srv["pid"])


func _scenario_4_seat_capacity(main_cert: String, main_key: String) -> void:
	var port := _next_port()
	var srv := _spawn_server(port, main_cert, main_key)
	var tokens: Array[String] = []
	var holders: Array[Dictionary] = []
	for i in 4:
		var token := NetSpike.new_token()
		tokens.append(token)
		holders.append(_start_client(port, main_cert, token, 5.0))
	OS.delay_msec(1500)
	var fifth := _spawn_client(port, main_cert, NetSpike.new_token())
	for handle: Dictionary in holders:
		_wait_client(handle, 5.0)
	for i in 4:
		_check(holders[i]["code"] == 0, "S4 seat %d welcomed (code=%s)" % [i, holders[i]["code"]])
	_check(fifth["code"] == 3, "S4 fifth client rejected server_full (code=%s)" % fifth["code"])
	for token in tokens:
		_scan_logs_for_leak(token, "S4")
	_kill(srv["pid"])


func _scenario_5_approval_queue(main_cert: String, main_key: String) -> void:
	var port := _next_port()
	# TTL 必须覆盖第 9 个客户端的完整启动+连接耗时（Windows 进程启动显著慢于 macOS，
	# 2s 时队列会先整体过期，第 9 个连接会被误判为可入队）；8 个等待者改在 6s 处超时，仍在 8s 预算内。
	var srv := _spawn_server(port, main_cert, main_key, "manual", 6.0, 20.0)
	var tokens: Array[String] = []
	var pending_clients: Array[Dictionary] = []
	for i in 8:
		var token := NetSpike.new_token()
		tokens.append(token)
		pending_clients.append(_start_client(port, main_cert, token, 0.0, 8.0))
	OS.delay_msec(1500)
	var ninth := _spawn_client(port, main_cert, NetSpike.new_token())
	for handle: Dictionary in pending_clients:
		_wait_client(handle, 0.0, 8.0)
	for i in 8:
		_check(pending_clients[i]["code"] == 4, "S5 pending %d approval timeout (code=%s)" % [i, pending_clients[i]["code"]])
	_check(ninth["code"] == 3, "S5 ninth pending_full rejected (code=%s)" % ninth["code"])
	for token in tokens:
		_scan_logs_for_leak(token, "S5")
	_kill(srv["pid"])


func _scenario_6_graceful_closing(main_cert: String, main_key: String) -> void:
	var port := _next_port()
	var srv := _spawn_server(port, main_cert, main_key, "auto", 2.0, 4.0)
	var token := NetSpike.new_token()
	var cli := _spawn_client(port, main_cert, token, 8.0, 8.0)
	_check(cli["code"] == 5, "S6 client notified of server closing (code=%s)" % cli["code"])
	_scan_logs_for_leak(token, "S6")
	_kill(srv["pid"])
