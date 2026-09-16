extends RefCounted
## AnimalData 目录：动物定义的唯一事实来源（V2 PRD 第 10 节）。
## 字段：label 显示名；measure 量词；price 购入价；product 产出物品 id。

const ANIMALS := {
	"chicken": {"label": "母鸡", "measure": "只", "price": 40, "product": "egg"},
	"sheep": {"label": "绵羊", "measure": "只", "price": 90, "product": "wool"},
	"cow": {"label": "奶牛", "measure": "头", "price": 150, "product": "milk"},
}
const ORDER := ["chicken", "sheep", "cow"]

## 兼容导出：旧代码经由 RanchModels / GameState 访问的两张表。
const ANIMAL_LABELS := {"cow": "奶牛", "sheep": "绵羊", "chicken": "母鸡"}
const ANIMAL_PRODUCTS := {"cow": "milk", "sheep": "wool", "chicken": "egg"}


static func label(kind: String) -> String:
	return ANIMALS[kind]["label"]


static func product(kind: String) -> String:
	return ANIMALS[kind]["product"]


static func price(kind: String) -> int:
	return int(ANIMALS[kind]["price"])
