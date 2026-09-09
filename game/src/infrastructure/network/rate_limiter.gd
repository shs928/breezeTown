class_name RateLimiter
## 令牌桶限流（NET 唯一维护，M2 NET-04；契约 10.3）。
## 身份前后分别限流；普通业务每成员 10 次/秒、突发 20；移动 30 次/秒、突发 60。
## 超限返回 false，由调用方映射为 RATE_LIMITED（未受理，不消耗业务序号）。

var _buckets: Dictionary = {}   # key -> {tokens, last_refill_ms}


## 尝试消费一个令牌。rate_per_s 与 burst 由调用方给出。
func allow(key: String, rate_per_s: int, burst: int, now_ms := -1) -> bool:
	var now := now_ms if now_ms >= 0 else Time.get_ticks_msec()
	var bucket: Dictionary = _buckets.get(key, {"tokens": float(burst), "last_refill_ms": now})
	var elapsed := now - int(bucket["last_refill_ms"])
	if elapsed > 0:
		var refill := float(elapsed) / 1000.0 * float(rate_per_s)
		bucket["tokens"] = min(float(burst), float(bucket["tokens"]) + refill)
		bucket["last_refill_ms"] = now
	if float(bucket["tokens"]) < 1.0:
		_buckets[key] = bucket
		return false
	bucket["tokens"] = float(bucket["tokens"]) - 1.0
	_buckets[key] = bucket
	return true


func reset(key: String) -> void:
	_buckets.erase(key)
