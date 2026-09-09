class_name SaveScheduler
## 保存调度（DATA 唯一维护，契约 8.2 / PRD 11.1）。
## 规则：
## - 目标间隔 30s；日切/批准/正常退出触发额外保存；手动随时可用。
## - 同一世界只允许一个保存作业；周期请求合并到下一个一致快照。
## - 任何明确保存失败立即进入 SAVE_FAULT（暂停模拟与修改、禁用导出），不等 35s。
## - 无明确结果但 35s 没有成功保存也触发保护；系统休眠时间不参与 35s 检测。

const ContractLimits := preload("res://src/contracts/contract_limits.gd")
const ContractEnvelopes := preload("res://src/contracts/contract_envelopes.gd")
const WorldRepository := preload("res://src/infrastructure/persistence/world_repository.gd")
const WorldState := preload("res://src/domain/world/world_state.gd")
const WorldRuntime := preload("res://src/application/world/world_runtime.gd")

enum State { IDLE, SAVING, SAVE_FAULT }

var state: int = State.IDLE
var last_success_ms := 0
var last_success_wall := 0.0
var last_error := ""
var generations_saved := 0

var _repository: WorldRepository
var _runtime: WorldRuntime
var _accumulated_ms := 0
var _interval_ms := ContractLimits.AUTOSAVE_INTERVAL_S * 1000


func setup(repository: WorldRepository, runtime: WorldRuntime) -> void:
	_repository = repository
	_runtime = runtime
	last_success_ms = Time.get_ticks_msec()
	last_success_wall = Time.get_unix_time_from_system()
	_runtime.save_requested.connect(_on_save_requested)


## 每帧调用；返回是否触发了自动保存。
func tick(delta_ms: int) -> bool:
	if state == State.SAVE_FAULT:
		return false
	_accumulated_ms += delta_ms
	if _accumulated_ms < _interval_ms:
		return false
	_accumulated_ms = 0
	save_now("autosave")
	return true


## 执行一次保存。明确失败立即进入故障状态。
func save_now(_reason: String) -> bool:
	if state == State.SAVING:
		return false  # 合并到下一个一致快照
	state = State.SAVING
	var result := _repository.save(_runtime.world)
	if result["ok"]:
		state = State.IDLE
		last_success_ms = Time.get_ticks_msec()
		last_success_wall = Time.get_unix_time_from_system()
		last_error = ""
		generations_saved += 1
		return true
	state = State.SAVE_FAULT
	last_error = str(result["error"])
	_runtime.set_save_fault(true)
	return false


## 35 秒保护：无明确结果但超时未成功保存 → 冻结。休眠时间不参与（由调用方只传实际模拟时间）。
func check_stall(real_elapsed_ms_since_last_poll: int) -> bool:
	if state == State.SAVE_FAULT:
		return true
	if state == State.SAVING:
		return false
	if Time.get_ticks_msec() - last_success_ms > ContractLimits.SAVE_STALL_FAULT_S * 1000:
		state = State.SAVE_FAULT
		last_error = "save_stall_timeout"
		_runtime.set_save_fault(true)
		return true
	return false


## 重试保存（故障恢复）。
func retry() -> bool:
	if state != State.SAVE_FAULT:
		return true
	var ok := save_now("retry")
	if ok:
		_runtime.set_save_fault(false)
		last_success_ms = Time.get_ticks_msec()
	return ok


## 另存完整恢复包到其他目录（故障时保留进展）。
func save_recovery_copy(target_dir: String) -> Dictionary:
	DirAccess.make_dir_recursive_absolute(target_dir)
	var payload_json := JSON.stringify(_runtime.world.to_dict())
	var envelope := ContractEnvelopes.make_save_envelope(_runtime.world.world_id, generations_saved + 1, payload_json)
	var path := target_dir + "/recovery-%d.json" % Time.get_unix_time_from_system()
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return {"ok": false, "path": "", "error": "write_failed"}
	f.store_string(JSON.stringify(envelope))
	f.flush()
	f.close()
	return {"ok": true, "path": path, "error": ""}


func is_fault() -> bool:
	return state == State.SAVE_FAULT


func seconds_since_last_save() -> int:
	return (Time.get_ticks_msec() - last_success_ms) / 1000


func _on_save_requested(_reason: String) -> void:
	if state == State.SAVE_FAULT:
		return
	save_now(_reason)
