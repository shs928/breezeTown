# M0 架构重构审计报告与完成度核查

**日期：2026-09-16 · 基线：V2 PRD（[docs/product/01-product-prd-v2.md](../product/01-product-prd-v2.md)）第 50 节 Definition of Done**

## 一、改造前审计（重构起点）

以 `--smoke` 集成测试（农牧/矿场/林业/战斗全流程，PASS）为行为基准，逐项核查 V2 PRD 第 50 节：

| DoD 项 | 改造前状态 | 证据 |
|---|---|---|
| 原型可运行 / 旧功能不回归 | ✅ | smoke 全绿 |
| PlayerState 与 Node3D 分离 | 🟡 部分 | game_state.gd（RefCounted）持有金币/背包/健康/时间，但无位置，且混有世界状态 |
| CropState 与 Node3D 分离 | ❌ | tile.gd（Node3D）直接持有 state/crop/stage/watered |
| AnimalState 与 Node3D 分离 | ❌ | animal.gd 直接持有 kind/petted_today |
| ItemData 建立 | ❌ | 价格/名称散落 game_state、ranch_models 常量表 |
| CropData 建立 | 🟡 | CROPS 字典已数据化，但无季节/经验等结构，且与其他物品表混杂 |
| AnimalData 建立 | 🟡 | 分散在 game_state.ANIMALS 与 ranch_models 两处 |
| RecipeData 建立 | ❌ | 无 |
| GameClock 建立 | ❌ | 浮点时钟在 GameState；日切结算由 main.gd 直调各系统 |
| EventBus 建立 | ❌ | 全部直接方法调用 |
| InteractionSystem 建立 | ❌ | main.gd 内 130 行巨型 match + 硬编码距离 |
| SaveManager 建立 | ❌ | 无磁盘存档（README 明示） |
| MapData / Grid 规则 | 🟡 | world_builder 返回数据字典，但与 tiles.gd 阻挡数据重复、Grid 常量分散 |
| 基础自动化测试 | 🟡 | 只有场景级 --smoke 集成测试，无领域单元测试 |
| 新存档和加载可靠 | ❌ | 无 |
| 旧 PRD 归档 / V2 成为基线 | ❌ | 旧 2D 任务包占踞仓库根目录 |

另：实际代码已走在 PRD 前（矿场、战斗、林业、村镇地图等 PRD 未定义的系统已在运行），本报告一并纳入现状基线。

## 二、本次实施内容（M0）

### 新增核心系统 `game/scripts/core/`

| 文件 | 职责 | PRD 依据 |
|---|---|---|
| `event_bus.gd` | 全局事件总线（class_name + 静态单例，不依赖 autoload，headless 可测）：day_ended/day_started/season_changed/weather_changed/crop_tilled…crop_harvested/animal_petted/trough_filled/item_added/item_removed/money_changed/player_slept/map_switched/save_written | 第 34 节 |
| `game_clock.gd` | 时钟/季节/天气唯一事实来源：20 小时制日切、28 天季节、星期、天气表（雨天等已定义，接入在 P2） | 第 20–22 节 |
| `save_manager.gd` | 槽位存档：`user://saves/slot_N/`（meta.json + world.json + backup/world.prev.json），主档损坏自动回退备份 | 第 27/28 节 |
| `interaction_system.gd` | 统一交互：TargetResolver（update_targeting）+ 动作分发（interact），目标种类枚举齐全，未来 NPC/Door/FishingSpot 在此注册 | 第 8.2/M0-05 节 |
| `map_data.gd` | MapData：2 米网格常量、可耕性阻挡（矩形/圆形/路径/资源占地）、地标、玩家圈定牧场，可序列化 | 第 4/6 节 |

### 新增数据目录 `game/scripts/data/`（数据驱动，单一事实来源）

- `crop_db.gd`（CropData：label/价格/grow_days/season/regrow/exp）
- `animal_db.gd`（AnimalData：label/price/product）
- `item_db.gd`（ItemData：统一 id→label/type/买卖价/堆叠，作物与产物价格引自各 DB，不重复维护）
- `recipe_db.gd`（RecipeData 结构 + 校验；配方内容在 M6 填充）

### 新增领域层 `game/scripts/domain/`（纯数据，不依赖 Node3D，可单测可序列化）

- `farm_state.gd`：FarmTileData（wild/tilled/planted + crop/stage/watered）+ 全图耕地运算与事件
- `animal_state.gd`：种类/当日抚摸/归属牧场 + 产出映射

### 重构（行为不变，架构就位）

- `game_state.gd`：时钟委托 GameClock；目录表委托 data/；新增 take_seed/add_harvest/add_product（统一发物品事件）；to_dict/from_dict
- `tiles.gd` + `tile.gd`：网格管理器降级为视图层，状态裁决全部走 MapData/FarmState；tile.gd 变为绑定 FarmTileData 的纯视图
- `animal.gd` / `trough.gd` / `ranch_models.gd`：数据委托领域对象/数据目录，节点只管表现
- `main.gd`：日切编排改为「day_ended → 结算 → season_changed → day_started」事件流；牧场登记进 MapData；接入 SaveManager（**睡觉自动存档**、`--load` 启动读档、**F5 手动存档 / F9 读档**）；目标解析与交互执行整体移交 InteractionSystem
- `hud.gd`：按 Art Bible 第四节重写版式（左上状态板：头像+生命+口粮；右上：季节/日期/天气/时钟胶囊 + 金币千分位；底部木质快捷栏；羊皮纸+木框面板），并订阅 money_changed/day_started 事件刷新

### 文档与美术基准

- 4 张用户确认参考图入库 `docs/art/reference/`（style-board / lake-dock / ui-hud / valley-map）
- 新增 `docs/art/art-bible.md`：色板、资产规则、UI 版式规范、当前差距表
- 旧 2D 任务包归档 `docs/legacy/`；V2 PRD 移至 `docs/product/01-product-prd-v2.md` 成为唯一开发基线

## 三、改造后 DoD 核查

| DoD 项 | 状态 | 说明 |
|---|---|---|
| 原型可运行 / 旧功能不回归 | ✅ | smoke 全绿（含矿场十层、林业、战斗） |
| PlayerState 与 Node3D 分离 | ✅ | game_state.gd 纯数据 + to/from_dict；位置在存档 payload 中捕获 |
| CropState 与 Node3D 分离 | ✅ | FarmState/FarmTileData；tile.gd 仅视图 |
| AnimalState 与 Node3D 分离 | ✅ | AnimalState |
| ItemData / CropData / AnimalData / RecipeData | ✅ | data/ 四目录；RecipeDB 内容按计划 M6 填充 |
| GameClock | ✅ | 时钟/季节/星期/天气；日切与季节事件 |
| EventBus | ✅ | 16 个信号；HUD 已订阅示范 |
| InteractionSystem | ✅ | 目标解析 + 动作分发统一入口 |
| SaveManager | ✅ | 槽位/备份/损坏回退；睡觉自动存档；F5/F9 |
| MapData / Grid 规则 | ✅ | 2 米网格常量 + 阻挡 + 牧场，可序列化（地形生成全数据化留 M1） |
| 基础自动化测试 | ✅ | `core_checks.gd` 49 项领域单测（headless）+ 原 smoke 集成 |
| 新存档和加载可靠 | ✅ | 存→读→一致由 TEST-007 等价用例覆盖；备份回退实现 |
| 旧 PRD 归档 / V2 成为基线 | ✅ | docs/legacy/ + docs/product/ |

**遗留到后续里程碑（按计划，非欠账）：**
- M1：world_builder 视觉生成完全数据化（当前 MapData 已就位，生成侧仍程序化）
- M2：Tool Framework（工具等级/体力消耗配置化）
- M2：图位图标（HUD 目前以文字槽位 + 色块占位）
- P2：WeatherSystem 实际玩法接入（时钟已定义天气表与事件）
- M5/M6：任务通知板、制作/加工 UI（HUD 已预留版式位置）

## 四、验证证据

```text
冒烟（--smoke，全场景集成）：SMOKE_RESULT PASS（0 SCRIPT ERROR 后的干净运行）
单元（core_checks.gd）：CORE_RESULT PASS · 49 项
  catalog×6 · new-world×4 · planting×5 · growth/harvest×5 · clock/season×8
  animal×4 · economy×7 · save-roundtrip×8（TEST-007）· event×2
```

运行方式：

```bash
tools/engine/Godot-4.7.2-stable/Godot.app/Contents/MacOS/Godot --headless --path game -- --smoke
tools/engine/Godot-4.7.2-stable/Godot.app/Contents/MacOS/Godot --headless --path game --script res://scripts/tests/core_checks.gd
```

## 五、M0-01 冻结版本（待执行）

按 PRD M0-01，建议将当前状态提交并打标签：

```bash
git add -A && git commit -m "M0: 数据驱动架构重构（EventBus/GameClock/Domain/Save/Interaction/MapData）+ Art Bible"
git tag v0.3-3d-vertical-slice
```

（遵从「所有修改必须可回滚」纪律；未打标签前请勿在此基线上叠加 M1 工作。）
