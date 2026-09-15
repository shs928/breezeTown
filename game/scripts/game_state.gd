extends RefCounted
## 一次经营的全部数据：作物配置、金币、背包、游戏日时钟。
## 时钟以小时计：每天 06:00 开始，26:00（次日 02:00）日切并结算生长。

const CROPS := {
	"radish": {"label": "小萝卜", "seed_price": 3, "sell_price": 8, "grow_days": 2},
	"strawberry": {"label": "草莓", "seed_price": 6, "sell_price": 15, "grow_days": 3},
	"wheat": {"label": "小麦", "seed_price": 4, "sell_price": 11, "grow_days": 3},
	"pumpkin": {"label": "南瓜", "seed_price": 9, "sell_price": 26, "grow_days": 4},
}
const CROP_ORDER := ["radish", "strawberry", "wheat", "pumpkin"]
const START_COINS := 20
const HOURS_PER_DAY := 20.0  # 06:00 → 次日 02:00

var coins: int = START_COINS
var seeds := {"radish": 6, "strawberry": 0, "wheat": 0, "pumpkin": 0}
var harvest := {"radish": 0, "strawberry": 0, "wheat": 0, "pumpkin": 0}
var day := 1
var clock := 8.0


static func crop_label(kind: String) -> String:
	return CROPS[kind]["label"]


static func crop_field(kind: String, field: String) -> int:
	return CROPS[kind][field]


func add_coins(amount: int) -> void:
	coins += amount


func buy_seed(kind: String, count: int) -> bool:
	var cost: int = CROPS[kind]["seed_price"] * count
	if coins < cost:
		return false
	coins -= cost
	seeds[kind] += count
	return true


func sell_all_harvest() -> int:
	var earned := 0
	for kind in harvest:
		earned += harvest[kind] * CROPS[kind]["sell_price"]
		harvest[kind] = 0
	coins += earned
	return earned


func advance_hour(delta_hours: float) -> bool:
	## 返回 true 表示发生了日切（需要结算生长）。
	clock += delta_hours
	if clock >= 6.0 + HOURS_PER_DAY:
		clock -= HOURS_PER_DAY
		day += 1
		return true
	return false


func sleep_to_next_day() -> void:
	clock = 6.0
	day += 1


func clock_text() -> String:
	var hour := int(clock) % 24
	var minute := int(fmod(clock, 1.0) * 60.0)
	return "%02d:%02d" % [hour, minute]
