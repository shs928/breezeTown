extends SceneTree
## NET-04 测试（headless）：限流令牌桶、脱敏日志、过期回执、重连退避。
## 运行：godot --headless --path game --script res://tests/integration/net04_test_runner.gd

const ContractLimits := preload("res://src/contracts/contract_limits.gd")
const ContractError := preload("res://src/contracts/contract_error.gd")
const RateLimiter := preload("res://src/infrastructure/network/rate_limiter.gd")
const SafeLog := preload("res://src/infrastructure/network/safe_log.gd")
const ClientSession := preload("res://src/application/session/client_session.gd")
const NetTransport := preload("res://src/infrastructure/network/net_transport.gd")
const WorldState := preload("res://src/domain/world/world_state.gd")
const WorldRuntime := preload("res://src/application/world/world_runtime.gd")

var _checks := 0
var _failures: PackedStringArray = []


func _initialize() -> void:
	_test_token_bucket()
	_test_safe_log_redaction()
	_test_receipt_cache_bounds()
	_test_reconnect_backoff()

	if _failures.is_empty():
		print("NET04_OK checks=%d" % _checks)
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: " + f)
		printerr("NET04_FAILED checks=%d failures=%d" % [_checks, _failures.size()])
		quit(1)


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(label)


# ---------- 1. 令牌桶 ----------

func _test_token_bucket() -> void:
	var limiter := RateLimiter.new()
	var t := 1_000_000
	# 突发 20：前 20 次允许，第 21 次拒绝
	var allowed := 0
	for i in 25:
		if limiter.allow("k", 10, 20, t):
			allowed += 1
	_check(allowed == 20, "burst allows exactly 20 (got %d)" % allowed)
	# 1 秒后恢复 10 个令牌
	var allowed2 := 0
	for i in 15:
		if limiter.allow("k", 10, 20, t + 1000):
			allowed2 += 1
	_check(allowed2 == 10, "refill 10 tokens per second (got %d)" % allowed2)
	# 不同 key 独立
	_check(limiter.allow("other", 10, 20, t), "different key has own bucket")
	# reset
	limiter.reset("k")
	_check(limiter.allow("k", 10, 20, t + 1000), "reset restores bucket")


# ---------- 2. 脱敏日志 ----------

func _test_safe_log_redaction() -> void:
	var log := SafeLog.new()
	var token := "a".repeat(64)
	log.log("info", "join", {"token": token, "display_name": "朋友", "digest_prefix": token.sha256_text().substr(0, 12)})
	log.log("info", "cert", {"pem": "-----BEGIN PRIVATE KEY-----\nsecret\n-----END PRIVATE KEY-----"})
	log.log("info", "nested", {"inner": {"credential": "secret-value"}})
	# 键名不敏感但值是 64 位 hex（凭据形态）：应替换为前缀提示
	log.log("info", "opaque", {"value": token})
	var text := log.to_text()
	_check(not text.contains(token), "raw credential not in log")
	_check(not text.contains("PRIVATE KEY"), "private key not in log")
	_check(not text.contains("secret-value"), "nested credential redacted")
	_check(text.contains("朋友"), "non-sensitive field preserved")
	_check(text.contains("digest-prefix-only"), "credential-shaped value replaced with prefix note")
	# 静态检测器
	_check(SafeLog.contains_sensitive("my token is abc"), "sensitive detector finds 'token'")
	_check(not SafeLog.contains_sensitive("普通文本"), "detector allows clean text")


# ---------- 3. 过期回执边界 ----------

func _test_receipt_cache_bounds() -> void:
	var world := WorldState.create("w" + "0".repeat(32), "m" + "1".repeat(32), "房主")
	var runtime := WorldRuntime.new()
	runtime.setup(world, {})
	var owner := world.owner_player_id
	# 发 300 条命令，缓存上限 256
	for i in 300:
		runtime.submit({
			"protocol_version": 1, "world_id": world.world_id, "authority_epoch": world.authority_epoch,
			"client_sequence": i + 1, "command_type": "profile.update",
			"payload": {"display_name": "名%d" % i}, "_actor_player_id": owner,
		})
	# 最旧的序号已被挤出缓存，但高水位仍是 300 → 返回 RECEIPT_EXPIRED 而非重复执行
	var expired := runtime.submit({
		"protocol_version": 1, "world_id": world.world_id, "authority_epoch": world.authority_epoch,
		"client_sequence": 1, "command_type": "profile.update",
		"payload": {"display_name": "旧请求"}, "_actor_player_id": owner,
	})
	_check(expired["error_code"] == ContractError.RECEIPT_EXPIRED, "expired receipt not re-executed (got %s)" % expired["error_code"])
	_check(runtime.next_expected_sequence(owner) == 301, "high watermark preserved")
	_check(world.find_member(owner)["display_name"] != "旧请求", "expired request did not change state")


# ---------- 4. 重连退避 ----------

func _test_reconnect_backoff() -> void:
	var client := ClientSession.new()
	client.setup(NetTransport.new())
	# 未连接状态下的退避序列定义
	_check(ClientSession.RECONNECT_BACKOFF_MS.size() == 4, "four backoff steps")
	_check(ClientSession.RECONNECT_BACKOFF_MS[0] == 1000 and ClientSession.RECONNECT_BACKOFF_MS[1] == 2000, "backoff 1s,2s")
	_check(ClientSession.RECONNECT_BACKOFF_MS[2] == 4000 and ClientSession.RECONNECT_BACKOFF_MS[3] == 8000, "backoff 4s,8s")
	# 累计 15 秒 ≤ 30 秒预算
	var total := 0
	for ms in ClientSession.RECONNECT_BACKOFF_MS:
		total += ms
	_check(total <= ContractLimits.RECONNECT_TOTAL_BUDGET_S * 1000, "backoff total within 30s budget (got %dms)" % total)
	# 未连接时发送命令被拒绝
	var receipt := client.send_command("profile.update", {"display_name": "甲"})
	_check(receipt["error_code"] == ContractError.NOT_AUTHENTICATED, "command rejected when not active")
	client.close()
