extends RefCounted
## TRANSPORT-02：驿站马车唯一数据源（PLAY-01 方案 A）。
## 锚点为 landmarks 键或 "site:建筑id"（运行时经 main 解析为世界坐标）。
## 时长矩阵为设计标定值（依 02-transport-pacing-plan 实测距离折算）；
## 农场↔镇区为免费教学线路，其余 10 币/程。

const ORDER := ["farm", "town", "mine", "harbor", "npc", "lake"]

const STATIONS := {
	"farm": {"label": "向阳农场口", "anchor": "spawn", "offset": Vector3(2.5, 0, 1.5)},
	"town": {"label": "镇广场", "anchor": "town_square", "offset": Vector3(6.0, 0, 4.0)},
	"mine": {"label": "星辉矿口", "anchor": "mine_door", "offset": Vector3(1.5, 0, 3.2)},
	"harbor": {"label": "港务码头", "anchor": "site:harbor_house", "offset": Vector3(-3.0, 0, 4.5)},
	"npc": {"label": "北岭农庄", "anchor": "site:npc_farmhouse", "offset": Vector3(6.0, 0, 6.0)},
	"lake": {"label": "月湾湖畔", "anchor": "lake_view", "offset": Vector3(7.5, 0, 4.0)},
}

const RIDE_FEE := 10

## 站间乘车时长（游戏时）。矩阵对称；对角线 0。
const HOURS := {
	"farm": {"town": 2, "mine": 4, "harbor": 2, "npc": 4, "lake": 3},
	"town": {"farm": 2, "mine": 3, "harbor": 2, "npc": 2, "lake": 2},
	"mine": {"farm": 4, "town": 3, "harbor": 4, "npc": 3, "lake": 4},
	"harbor": {"farm": 2, "town": 2, "mine": 4, "npc": 3, "lake": 2},
	"npc": {"farm": 4, "town": 2, "mine": 3, "harbor": 3, "lake": 2},
	"lake": {"farm": 3, "town": 2, "mine": 4, "harbor": 2, "npc": 2},
}


static func has(id: String) -> bool:
	return STATIONS.has(id)


static func entry(id: String) -> Dictionary:
	return STATIONS.get(id, {})


static func label(id: String) -> String:
	return String(entry(id).get("label", id))


static func hours_between(from: String, to: String) -> int:
	if from == to or not HOURS.has(from):
		return 0
	return int(HOURS[from].get(to, 0))


static func fee_between(from: String, to: String) -> int:
	## 农场↔镇区教学线路免费，其余按固定票价。
	if (from == "farm" and to == "town") or (from == "town" and to == "farm"):
		return 0
	return RIDE_FEE
