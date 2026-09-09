extends SceneTree
## NET-01：生成临时测试证书对。
## 用法：godot --headless --path work/net-spike --script res://gen_certs.gd -- --out-dir=<绝对路径> [--cn=localhost]
## 生成 <out>/server.pem / server.key（另一对 decoy.pem/decoy.key 用于“错误证书”用例）。

const NetSpike := preload("res://net_spike.gd")


func _initialize() -> void:
	var out_dir := ""
	var cn := "localhost"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out-dir="):
			out_dir = arg.get_slice("=", 1)
		elif arg.begins_with("--cn="):
			cn = arg.get_slice("=", 1)
	if out_dir.is_empty():
		printerr("gen_certs: missing --out-dir")
		quit(2)
		return
	var main := NetSpike.gen_certs(out_dir + "/main", cn)
	if not main["ok"]:
		printerr("gen_certs main failed: ", str(main["reason"]))
		quit(1)
		return
	var decoy := NetSpike.gen_certs(out_dir + "/decoy", cn)
	if not decoy["ok"]:
		printerr("gen_certs decoy failed: ", str(decoy["reason"]))
		quit(1)
		return
	print("CERTS_OK main=%s decoy=%s" % [main["cert_path"], decoy["cert_path"]])
	quit(0)
