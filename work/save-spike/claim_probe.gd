extends SceneTree
## DATA-00 锁竞争探针（子进程）。尝试取得指定世界的写锁：
## exit 0 = 意外取得成功（父进程测试视为失败）
## exit 3 = 被活跃锁拒绝（预期）
## exit 4 = 其他失败
## 用法：godot --headless --path work/save-spike --script res://claim_probe.gd -- --world-dir=<绝对路径>

const SaveSpike := preload("res://save_spike.gd")


func _initialize() -> void:
	var world_dir := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--world-dir="):
			world_dir = arg.get_slice("=", 1)
	if world_dir.is_empty() or DirAccess.open(world_dir) == null:
		printerr("claim_probe: missing or unreadable --world-dir")
		quit(4)
		return
	var result := SaveSpike.claim_lock(world_dir)
	print("claim_probe: ", JSON.stringify(result))
	if result["ok"]:
		quit(0)
	elif result["reason"] == "locked_alive":
		quit(3)
	else:
		quit(4)
