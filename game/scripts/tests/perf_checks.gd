extends SceneTree
## PERF-01：可复现的性能采样。启动耗时、分区帧时间分位数、draw calls 与内存。
## 窗口模式运行才有真实渲染负载：--path game --script res://scripts/tests/perf_checks.gd
const Definition := preload("res://scripts/data/first_map_definition.gd")
var report: Array[String] = []
var game: Node3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1600, 1000)
	var boot_start := Time.get_ticks_msec()
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	for i in range(5):
		await process_frame
	var boot_ms := Time.get_ticks_msec() - boot_start
	_emit("BOOT ms=%d (instantiate→3 frames)" % boot_ms)
	_emit("HARDWARE gpu=%s" % RenderingServer.get_video_adapter_name())
	var regions := {
		"farm": Vector2(-663, 242),
		"town": Vector2(80, -160),
		"forest": Definition.point([626, 137]),
		"orchard": Definition.point([1000, 300]),
		"harbor": Vector2(-150, 760),
	}
	for key: String in regions:
		var at: Vector2 = regions[key]
		game.player.teleport(Vector3(at.x, 0, at.y))
		if game.scenery != null:
			game.scenery._refresh(true)
		for i in range(30):
			await process_frame
		var sample := await _sample(240)
		_emit("REGION %s p50=%.2fms p90=%.2fms p99=%.2fms max=%.2fms draws=%d mem=%.0fMB" % [
			key, sample[0], sample[1], sample[2], sample[3], sample[4], sample[5]])
	# 高分辨率（等同 2560×1600 视口）
	root.size = Vector2i(2560, 1600)
	game.player.teleport(Vector3(-663, 0, 242))
	if game.scenery != null:
		game.scenery._refresh(true)
	for i in range(30):
		await process_frame
	var hires := await _sample(240)
	_emit("REGION hires-2560x1600-farm p50=%.2fms p90=%.2fms p99=%.2fms max=%.2fms draws=%d mem=%.0fMB" % [
		hires[0], hires[1], hires[2], hires[3], hires[4], hires[5]])
	for line in report:
		print("PERF01 " + line)
	quit(0)


func _sample(frames: int) -> Array:
	var times := PackedFloat32Array()
	var draws := 0
	for i in range(frames):
		var start := Time.get_ticks_usec()
		await process_frame
		times.append((Time.get_ticks_usec() - start) * 0.001)
		draws = maxi(draws, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
	times.sort()
	var pick := func(q: float) -> float: return times[clampi(int(q * (times.size() - 1)), 0, times.size() - 1)]
	var memory := float(Performance.get_monitor(Performance.MEMORY_STATIC)) / 1048576.0
	return [pick.call(0.5), pick.call(0.9), pick.call(0.99), times[times.size() - 1], draws, memory]


func _emit(line: String) -> void:
	report.append(line)
