extends RefCounted
## CropData 目录：作物定义的唯一事实来源（V2 PRD 第 9.2 节）。
## 字段：label 显示名；seed_price/sell_price 经济；grow_days 生长天数；
## season 宜种季节；water_required 是否需要浇水；regrow 收获后是否再生；exp 收获经验。

const CROPS := {
	"radish": {"label": "小萝卜", "seed_price": 3, "sell_price": 8, "grow_days": 2, "season": "spring", "water_required": true, "regrow": false, "exp": 5},
	"strawberry": {"label": "草莓", "seed_price": 6, "sell_price": 15, "grow_days": 3, "season": "spring", "water_required": true, "regrow": false, "exp": 8},
	"wheat": {"label": "小麦", "seed_price": 4, "sell_price": 11, "grow_days": 3, "season": "summer", "water_required": true, "regrow": false, "exp": 7},
	"pumpkin": {"label": "南瓜", "seed_price": 9, "sell_price": 26, "grow_days": 4, "season": "autumn", "water_required": true, "regrow": false, "exp": 12},
}
const ORDER := ["radish", "strawberry", "wheat", "pumpkin"]


static func field(kind: String, key: String) -> Variant:
	return CROPS[kind][key]


static func label(kind: String) -> String:
	return CROPS[kind]["label"]


static func grow_days(kind: String) -> int:
	return int(CROPS[kind]["grow_days"])
