extends RefCounted
## INDOOR-01：室内房间唯一数据源（PRD 第 26 节 Door → SceneTransition → Interior）。
## 坐标为房间本地坐标（米，+x 东 / +z 南），原点在房间中心地面。
## 布局与服务为第一轮暂定值（任务板"后续需要确认"清单：最终门牌命名与室内布局待用户确认）。

const MEAL_PRICE := 30  # 酒馆套餐：付费回满体力并恢复生命
const MEAL_HEALTH := 60
const TREATMENT_PRICE := 50  # 诊所治疗：付费回满生命

## 服务种类：bed（农舍床铺=睡觉）/ counter_shop（商店柜台）/ counter_meal（酒馆餐食）/ clinic_bed（诊所治疗）
const ROOMS := {
	"cottage": {
		"label": "玩家农舍",
		"style": "home",
		"size": Vector2(10.5, 8.0),
		"spawn": Vector3(0, 0, 1.8),
		"exit": Vector3(0, 0, 3.3),
		"services": [
			{"kind": "bed", "label": "床铺", "at": Vector3(-3.4, 0, -1.9), "range": 1.9, "hint": "按 E 睡觉到明天 · 自动存档"},
		],
	},
	"shop": {
		"label": "皮埃尔杂货店",
		"style": "shop",
		"size": Vector2(12.0, 9.0),
		"spawn": Vector3(0, 0, 2.2),
		"exit": Vector3(0, 0, 3.8),
		"npc_spot": Vector3(0.9, 0, -2.25),
		"services": [
			{"kind": "counter_shop", "label": "柜台", "at": Vector3(0, 0, -1.6), "range": 2.3, "hint": "按 E 逛商店"},
		],
	},
	"inn": {
		"label": "酒馆",
		"style": "inn",
		"size": Vector2(14.0, 10.0),
		"spawn": Vector3(0, 0, 2.6),
		"exit": Vector3(0, 0, 4.2),
		"machines": [
			{"kind": "kitchen", "label": "厨房灶台", "at": Vector3(4.6, 0, -3.6), "range": 2.3},
		],
		"services": [
			{"kind": "counter_meal", "label": "吧台", "at": Vector3(-3.6, 0, -2.2), "range": 2.2, "hint": "按 E 用餐 · %d 币 · 体力回满 + 生命 +%d" % [MEAL_PRICE, MEAL_HEALTH]},
		],
	},
	"clinic": {
		"label": "医院",
		"style": "clinic",
		"size": Vector2(12.5, 9.5),
		"spawn": Vector3(0, 0, 2.4),
		"exit": Vector3(0, 0, 4.0),
		"services": [
			{"kind": "clinic_bed", "label": "病床", "at": Vector3(-3.4, 0, -2.0), "range": 2.0, "hint": "按 E 治疗 · %d 币 · 生命回满" % TREATMENT_PRICE},
		],
	},
	"smith": {
		"label": "铁匠铺",
		"style": "smith",
		"size": Vector2(12.0, 9.0),
		"spawn": Vector3(0, 0, 2.2),
		"exit": Vector3(0, 0, 3.8),
		"npc_spot": Vector3(-3.4, 0, -2.6),
		"machines": [
			{"kind": "furnace", "label": "熔炉", "at": Vector3(3.4, 0, -2.4), "range": 2.3},
		],
	},
	"player_barn": {
		"label": "农场谷仓",
		"style": "barn",
		"size": Vector2(13.0, 10.0),
		"spawn": Vector3(0, 0, 2.6),
		"exit": Vector3(0, 0, 4.2),
		"machines": [
			{"kind": "cheese_press", "label": "奶酪压榨机", "at": Vector3(-3.4, 0, -2.6), "range": 2.3},
			{"kind": "loom", "label": "织布机", "at": Vector3(3.6, 0, -1.2), "range": 2.3},
		],
	},
	"player_coop": {
		"label": "农场鸡舍",
		"style": "coop",
		"size": Vector2(9.0, 7.5),
		"spawn": Vector3(0, 0, 1.6),
		"exit": Vector3(0, 0, 3.0),
		"machines": [
			{"kind": "mayo_maker", "label": "蛋黄酱机", "at": Vector3(-2.4, 0, -1.8), "range": 2.0},
		],
	},
	"carpenter": {
		"label": "木工坊",
		"style": "carpenter",
		"size": Vector2(11.5, 9.0),
		"spawn": Vector3(0, 0, 2.2),
		"exit": Vector3(0, 0, 3.8),
		"machines": [
			{"kind": "workbench", "label": "工作台", "at": Vector3(3.2, 0, -2.4), "range": 2.3},
		],
	},
}

const ORDER := ["cottage", "shop", "inn", "clinic", "smith", "player_barn", "player_coop", "carpenter"]


static func has(id: String) -> bool:
	return ROOMS.has(id)


static func entry(id: String) -> Dictionary:
	return ROOMS.get(id, {})
