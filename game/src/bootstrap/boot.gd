extends Node
## 微风小镇组合根（FND-01 启动骨架 + M1 UI-02 客户端接入）。
## 职责：解析 --mode= 启动组合，校验合法性；headless 下只输出摘要并退出（保持 FND-01 行为），
## 窗口模式下根据 mode 加载客户端界面。世界业务逻辑由各领域模块提供，此处只做组合。
##
## 四种模式：solo（本地单人）、listen_host（本地+监听）、client（远端视图）、dedicated（无界面）。

const GAME_VERSION := "0.1.0"
const PROTOCOL_VERSION := 1  # LEAD-01 冻结为契约 v1
const VALID_MODES: PackedStringArray = ["solo", "listen_host", "client", "dedicated"]
const ClientRoot := preload("res://src/client/client_root.gd")

var _mode := ""
var _world_dir := ""
var _port := 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for arg: String in args:
		if arg.begins_with("--mode="):
			_mode = arg.get_slice("=", 1)
		elif arg.begins_with("--world-dir="):
			_world_dir = arg.get_slice("=", 1)
		elif arg.begins_with("--port="):
			_port = int(arg.get_slice("=", 1))

	if _mode.is_empty():
		_fail("missing required argument --mode=<solo|listen_host|client|dedicated>")
		return
	if not _mode in VALID_MODES:
		_fail("unknown mode '%s'; valid modes: %s" % [_mode, ", ".join(VALID_MODES)])
		return
	if _port != 0 and (_port < 1024 or _port > 65535):
		_fail("invalid port %d; expected 1024..65535" % _port)
		return

	_emit_summary()

	var headless := DisplayServer.get_name() == "headless"
	if headless or _mode == "dedicated":
		# dedicated 不创建 UI/音频/本地角色；headless 保持 M0 的“启动即退出”语义。
		get_tree().quit(0)
		return
	# 窗口模式：装载客户端（solo/listen_host/client 都需要界面；联机通道是 M2 工作）
	var client := ClientRoot.new()
	client.name = "ClientRoot"
	client.mode = _mode
	client.world_dir_override = _world_dir
	add_child(client)


func _fail(message: String) -> void:
	push_error("bootstrap: " + message)
	printerr("bootstrap: " + message)
	get_tree().quit(2)


func _emit_summary() -> void:
	var engine_info := Engine.get_version_info()
	var engine_version := "%d.%d.%d.%s.%s.%s" % [
		engine_info.major, engine_info.minor, engine_info.patch,
		engine_info.status, str(engine_info.build), str(engine_info.get("hash", "")),
	]
	var summary := {
		"event": "boot_summary",
		"game_version": GAME_VERSION,
		"protocol_version": PROTOCOL_VERSION,
		"mode": _mode,
		"engine_version": engine_version,
		"display_server": DisplayServer.get_name(),
		"headless": DisplayServer.get_name() == "headless",
		"world_dir": _world_dir,
		"port": _port,
		"network_listening": _mode == "listen_host" or _mode == "dedicated",
		"local_character_created": false,
		"ui_nodes_created": _count_ui_nodes(),
		"audio_players_created": _count_audio_nodes(),
		"note": "M1: windowed modes load the client; headless/dedicated stay UI-free and exit after summary.",
	}
	print(JSON.stringify(summary))


func _count_ui_nodes() -> int:
	var count := 0
	for child in get_tree().root.get_children():
		count += _count_ui_in(child)
	return count


func _count_ui_in(node: Node) -> int:
	var count := 0
	if node is Control or (node is Window and node != get_tree().root):
		count += 1
	for child in node.get_children():
		count += _count_ui_in(child)
	return count


func _count_audio_nodes() -> int:
	var count := 0
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is AudioStreamPlayer or node is AudioStreamPlayer2D or node is AudioStreamPlayer3D:
			count += 1
		for child in node.get_children():
			stack.append(child)
	return count
