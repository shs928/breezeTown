class_name ContractLimits
## 微风小镇契约数值边界（M0 候选版本；LEAD-01 冻结后为契约 v1）。
## 来源：01-product-prd.md 0.3、02-architecture-contracts.md 0.3 第 4.2/6/7 章。
## 修改任何常量必须同步 docs/contracts/contracts-m0.md，并升规则版本。

# ---- 通用数值边界（契约 4.2）----
const MAX_BUSINESS_INT := 9_000_000_000_000
const TRADE_QUANTITY_MIN := 1
const TRADE_QUANTITY_MAX := 99
const NAME_MAX_CHARS := 32
const NAME_MAX_BYTES := 128

# ---- 容量与席位（契约 4.2 / PRD 4.2、7.1）----
const MEMBER_HISTORY_CAP := 16
const ONLINE_CAP := 4
const FARM_PLOT_CAP := 256
const PENDING_APPROVAL_CAP := 8
const PENDING_APPROVAL_TTL_MS := 60_000
const BACKPACK_SLOTS := 24
const HOTBAR_SLOTS := 6
const SHARED_STORAGE_SLOTS := 24
const SHARED_STORAGE_SLOTS_EXPANDED := 48
const CONTAINER_SLOT_MAX := 47  # 载荷级硬上限：最大容器（扩建仓库）末槽

# ---- 消息与文件尺寸（契约 4.2）----
const BUSINESS_MESSAGE_MAX_BYTES := 16 * 1024
const PLAYER_VIEW_SNAPSHOT_MAX_BYTES := 2 * 1024 * 1024
const SAVE_FILE_MAX_BYTES := 16 * 1024 * 1024

# ---- 世界初始与经济（PRD 7.2、5.1、8）----
const INITIAL_TREASURY := 300
const INITIAL_RADISH_SEEDS := 20
const INITIAL_MATURE_RADISHES := 4
const TILLABLE_INITIAL := 144   # 12x12
const TILLABLE_EXPANDED := 256  # 16x16
const MAP_W := 64
const MAP_H := 64
const TILE_SIZE_PX := 32
const INTERACT_RADIUS_PX := 48          # 1.5 格
const PLAYER_SPEED_PX_PER_S := 96.0
const SPAWN_POINT_COUNT := 4

# ---- 时间与节奏（PRD 5.2、11.1；契约 7.3）----
const GAME_DAY_MS := 600_000            # 10 分钟一个游戏日
const AUTOSAVE_INTERVAL_S := 30
const SAVE_STALL_FAULT_S := 35          # 无成功保存的故障保护阈值
const SNAPSHOT_KEEP_GENERATIONS := 5
const DAY_SUMMARY_RETENTION := 30
const EVENT_LOG_RETENTION := 10_000
const RECEIPT_CACHE_PER_MEMBER := 256

# ---- 会话与限流（契约 7.3、10.3）----
const HEARTBEAT_TARGET_S := 2
const HEARTBEAT_TIMEOUT_S := 8
const CONNECT_TRUST_AUTH_BUDGET_S := 15
const APPROVAL_TIMEOUT_S := 60
const SNAPSHOT_TIMEOUT_S := 10
const RECONNECT_TOTAL_BUDGET_S := 30
const RATE_BUSINESS_PER_S := 10
const RATE_BUSINESS_BURST := 20
const RATE_MOVE_PER_S := 30
const RATE_MOVE_BURST := 60

# ---- 贡献计分（PRD 9.2）----
const POINTS_PLANT := 2
const POINTS_WATER := 1
const POINTS_HARVEST := 3
const POINTS_DONATE_PER_ITEM := 2
const POINTS_NON_SCORING := 0


## 世界名/昵称/公开别名校验：去控制字符与首尾空白后非空，
## ≤32 个 Unicode 字符且 UTF-8 ≤128 字节。返回清洗后的名称，非法返回空串。
static func sanitize_display_name(raw: String) -> String:
	var cleaned := ""
	for ch in raw:
		if ch.unicode_at(0) >= 32:  # 去除 C0 控制字符（含 \n \t）
			cleaned += ch
	cleaned = cleaned.strip_edges()
	if cleaned.is_empty():
		return ""
	if cleaned.length() > NAME_MAX_CHARS:
		return ""
	if cleaned.to_utf8_buffer().size() > NAME_MAX_BYTES:
		return ""
	return cleaned


## 一次可交易数量校验：必须是有界正整数 1..99。
## GDScript 的 int 不会出现 NaN；JSON 解析出的 float 视为非法（拒绝小数）。
static func is_valid_trade_quantity(value: Variant) -> bool:
	if value is not int:
		return false
	return value >= TRADE_QUANTITY_MIN and value <= TRADE_QUANTITY_MAX


## 通用业务整数校验：有界、非负可选、不接受浮点。
static func is_valid_business_int(value: Variant, allow_zero := true) -> bool:
	if value is not int:
		return false
	if not allow_zero and value == 0:
		return false
	return value >= 0 and value <= MAX_BUSINESS_INT
