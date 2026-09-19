extends RefCounted
## POLISH-05：季节地表视觉调色。纯数据口径，_apply_daylight 每帧引用，
## 场景副作用（地面雪 uniform 等）由 main 按季节变化时应用。

## 地面雪量：冬季全覆盖，其他季节 0（春秋不做残雪，规则无歧义）。
static func snow_amount_for(season_key: String) -> float:
	return 1.0 if season_key == "winter" else 0.0


## 地面草地色调乘子：秋转干黄、夏深绿、春鲜嫩、冬由雪量接管（色调不参与）。
static func ground_tint_for(season_key: String) -> Color:
	match season_key:
		"autumn":
			return Color(1.06, 0.96, 0.70)
		"summer":
			return Color(0.94, 1.02, 0.90)
		"spring":
			return Color(1.0, 1.04, 0.96)
		_:
			return Color.WHITE


## 环境色调乘子：背景/环境光向季节色偏移的比例，与日光关键帧插值结果相乘叠加。
## winter 冷冽偏蓝、autumn 暖金、spring 微鲜、summer 中性。
static func env_tint_for(season_key: String) -> Dictionary:
	match season_key:
		"winter":
			return {"bg": Color("#9fb4d8"), "bg_strength": 0.32, "amb": Color("#b9c9e2"), "amb_strength": 0.30, "sun": Color("#e8f0ff"), "sun_strength": 0.22, "energy": 0.92}
		"autumn":
			return {"bg": Color("#d8b878"), "bg_strength": 0.24, "amb": Color("#e2c9a0"), "amb_strength": 0.22, "sun": Color("#ffd9a0"), "sun_strength": 0.18, "energy": 0.97}
		"spring":
			return {"bg": Color("#cfe0b8"), "bg_strength": 0.10, "amb": Color("#d8e8c8"), "amb_strength": 0.10, "sun": Color("#fff3dc"), "sun_strength": 0.08, "energy": 1.0}
		_:
			return {"bg": Color("#e8f0e0"), "bg_strength": 0.06, "amb": Color("#eef4e4"), "amb_strength": 0.06, "sun": Color("#fff8ea"), "sun_strength": 0.05, "energy": 1.0}


## 树冠/灌木等植被的季节色调（供后续树冠重着色批次使用；本批次仅地面+环境）。
static func foliage_tint_for(season_key: String) -> Color:
	match season_key:
		"winter":
			return Color("#9fb8a8")
		"autumn":
			return Color("#d8a860")
		"summer":
			return Color("#5f9448")
		_:
			return Color.WHITE
