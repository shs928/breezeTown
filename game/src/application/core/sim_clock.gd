class_name SimClock
## 受控模拟时钟（契约 3.1 ClockPort / 7.5）。只累加实际模拟步；
## 休眠/暂停不按系统时钟补跑。日切由 WorldRuntime 在到达边界时触发。
##
## 时间显示换算：06:00 + 本日已执行模拟毫秒 / GAME_DAY_MS × 1080 分钟（PRD 5.2）。

const ContractLimits := preload("res://src/contracts/contract_limits.gd")

const DAY_START_MINUTES := 6 * 60      # 06:00
const DAY_SPAN_MINUTES := 18 * 60      # 06:00 → 24:00

var day_elapsed_ms := 0


## 推进模拟。返回本次推进中触发的日切次数（0 或 1，一帧内不跳多日）。
func advance(delta_ms: int) -> int:
	if delta_ms <= 0:
		return 0
	day_elapsed_ms += delta_ms
	if day_elapsed_ms >= ContractLimits.GAME_DAY_MS:
		# 不补跑：超出的部分归入新的一天起点，避免休眠唤醒跳过多个游戏日。
		day_elapsed_ms -= ContractLimits.GAME_DAY_MS
		if day_elapsed_ms < 0:
			day_elapsed_ms = 0
		return 1
	return 0


## 当前游戏内时刻（分钟，从 00:00 起算）。
func clock_minutes() -> int:
	return DAY_START_MINUTES + int(float(day_elapsed_ms) / float(ContractLimits.GAME_DAY_MS) * DAY_SPAN_MINUTES)


func clock_text() -> String:
	var minutes := clock_minutes()
	return "%02d:%02d" % [(minutes / 60) % 24, minutes % 60]
