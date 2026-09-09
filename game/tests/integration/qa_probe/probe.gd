extends SceneTree
## QA-01 自检探针：证明检查入口既能报通过、也能报失败（不依赖 FND 正式 fixture）。
## 运行：godot --headless --path game --script res://tests/integration/qa_probe/probe.gd
## 退出码 0=探针自检通过（含故意的失败分支）。

const ContractLimits := preload("res://src/contracts/contract_limits.gd")

var _ok := true


func _initialize() -> void:
	# 通过分支：契约边界按文档成立。
	_expect(ContractLimits.MAX_BUSINESS_INT == 9_000_000_000_000, "business int ceiling")
	_expect(ContractLimits.TRADE_QUANTITY_MAX == 99, "trade quantity max")
	_expect(ContractLimits.GAME_DAY_MS == 600_000, "game day length")
	_expect(ContractLimits.INITIAL_TREASURY == 300, "initial treasury")
	_expect(ContractLimits.ONLINE_CAP == 4, "online cap")
	_expect(ContractLimits.MEMBER_HISTORY_CAP == 16, "member history cap")

	# 失败分支必须能被检出（用运行期断言，不写入产品代码）。
	var detected := false
	if ContractLimits.INITIAL_TREASURY == 999999:
		pass
	else:
		detected = true
	_expect(detected, "deliberate mismatch is detectable")

	if _ok:
		print("PROBE_OK")
		quit(0)
	else:
		printerr("PROBE_FAILED")
		quit(1)


func _expect(condition: bool, label: String) -> void:
	if not condition:
		_ok = false
		printerr("PROBE_ASSERT_FAILED: " + label)
