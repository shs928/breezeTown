class_name SyncBuffer
## 快照与差量缓冲（NET 唯一维护，M2 NET-03；契约 7.5）。
## 职责：
## - 加入/重连时在 revision R 捕获某成员的可见视图快照；
## - 缓冲 R 之后的差量，客户端按序应用；
## - 差量携带 base_revision/target_revision，发现缺口要求重同步（不猜测缺失操作）；
## - 无可见变化的提交仍发轻量 revision 推进标记，避免私有过滤造成虚假缺口；
## - 缓冲上限 2MiB / 10 秒，超限中止并重新捕获。
##
## 过滤逻辑复用 WorldView（契约 3.2 要求，不另写一套）。

const ContractLimits := preload("res://src/contracts/contract_limits.gd")
const WorldView := preload("res://src/application/world/world_view.gd")

const BUFFER_MAX_BYTES := 2 * 1024 * 1024
const BUFFER_MAX_AGE_MS := 10_000

var base_revision := 0
var base_snapshot: Dictionary = {}
var deltas: Array = []          # [{base_revision, target_revision, view, at_ms}]
var buffer_bytes := 0
var started_at_ms := 0
var aborted := false
var abort_reason := ""
## 上一次推送给该客户端可见的视图快照，用于判断本次提交是否对其可见。
var last_pushed_view: Dictionary = {}


## 捕获某成员的基线快照（加入/重连时调用）。
func capture(world, member_id: String, online_players: Array = []) -> Dictionary:
	var result := WorldView.build(world, member_id, online_players)
	if not result["ok"]:
		return {"ok": false, "error": result["error"]}
	base_revision = int(result["snapshot"]["base_revision"])
	base_snapshot = result["snapshot"]
	deltas = []
	buffer_bytes = 0
	started_at_ms = Time.get_ticks_msec()
	aborted = false
	abort_reason = ""
	last_pushed_view = base_snapshot.duplicate(true)
	return {"ok": true, "snapshot": base_snapshot}


## 记录一次提交后的差量。返回 {ok, delta, skipped} 或 {ok:false, reason}。
## 若该成员看不到任何变化，仍返回轻量推进标记（view 为 null）。
func push(world, member_id: String, online_players: Array = []) -> Dictionary:
	if aborted:
		return {"ok": false, "reason": abort_reason}
	var result := WorldView.build(world, member_id, online_players)
	if not result["ok"]:
		return {"ok": false, "reason": result["error"]}
	var target := int(result["snapshot"]["base_revision"])
	# 与已推送的最高 revision 比较；不能假设每次提交只 +1（日切等可能跳号）。
	var highest := base_revision if deltas.is_empty() else int(deltas[-1]["target_revision"])
	if target <= highest:
		return {"ok": true, "delta": {}, "skipped": true}
	var previous_target := highest
	var visible := _visible_change(result["snapshot"])
	var delta := {
		"base_revision": previous_target,
		"target_revision": target,
		"view": result["snapshot"] if visible else null,
		"at_ms": Time.get_ticks_msec(),
	}
	if visible:
		last_pushed_view = (result["snapshot"] as Dictionary).duplicate(true)
	deltas.append(delta)
	buffer_bytes += JSON.stringify(delta).to_utf8_buffer().size()
	# 上限保护：超限中止并要求重新捕获（契约 7.5）
	if buffer_bytes > BUFFER_MAX_BYTES:
		aborted = true
		abort_reason = "buffer_bytes_exceeded"
		return {"ok": false, "reason": abort_reason}
	if Time.get_ticks_msec() - started_at_ms > BUFFER_MAX_AGE_MS:
		aborted = true
		abort_reason = "buffer_age_exceeded"
		return {"ok": false, "reason": abort_reason}
	return {"ok": true, "delta": delta, "skipped": false}


## 客户端侧：应用一个差量。返回 {ok, reason, needs_resync}。
## 缺口（base_revision 与本地已应用版本不连续）→ 要求重同步。
func apply_delta(local_revision: int, delta: Dictionary) -> Dictionary:
	if int(delta.get("base_revision", -1)) != local_revision:
		return {"ok": false, "reason": "revision_gap", "needs_resync": true}
	return {"ok": true, "reason": "", "needs_resync": false, "target_revision": int(delta["target_revision"])}


## 客户端侧：按序应用缓冲的全部差量。返回 {ok, applied, needs_resync, reason}。
func apply_all(local_revision: int) -> Dictionary:
	var current := local_revision
	var applied := 0
	for delta: Dictionary in deltas:
		var result := apply_delta(current, delta)
		if not result["ok"]:
			return {"ok": false, "applied": applied, "needs_resync": true, "reason": result["reason"]}
		current = int(result["target_revision"])
		applied += 1
	return {"ok": true, "applied": applied, "needs_resync": false, "reason": "", "revision": current}


func buffer_size() -> int:
	return buffer_bytes


func delta_count() -> int:
	return deltas.size()


func _visible_change(snapshot: Dictionary) -> bool:
	# 与上一次推送给该客户端的视图比较；无变化则发轻量推进标记（避免虚假缺口）。
	for key in ["treasury", "game_day", "crops", "projects", "leaderboard", "inventories", "members"]:
		if JSON.stringify(snapshot.get(key, null)) != JSON.stringify(last_pushed_view.get(key, null)):
			return true
	return false
