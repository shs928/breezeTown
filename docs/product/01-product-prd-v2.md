# 微风小镇 3D（BreezeTown）
## 第一张核心地图完整玩法开发 PRD + 技术改造方案

**文档版本：V2.1（2026-09-16 同步用户确认）**

**项目定位：等距 3D 卡通乡村农场模拟游戏**  
**技术基线：Godot 4.7.2 / 3D**  
**开发基线：现有 BreezeTown 3D Vertical Slice**  
**美术基准：用户提供的乡村农场等距 3D 卡通参考图**

## 最新确认与执行入口

以下用户后续决定覆盖原方案中的旧假设：

- 允许重建和破坏性改造，以用户提供的 UI/美术参考为目标；现有模型与旧布局不构成保留约束。
- 地图以 400 米 / 202 像素标尺换算，约 2598 × 2374 米。建筑是地标符号：位置照图，模型使用合理实际尺寸；耕地格为 2 米。
- 西南归玩家，东北归 NPC；出生、初始菜园和经营权限按此执行，原图 “Your Farm” 不覆盖归属决定。
- 失效 2D 需求包按用户要求删除，不另存 Legacy PRD。历史报告只作追溯。
- [当前任务板](../execution/task-board.md)保存下一步工作和验收条件，[接续记录](../execution/SUMMARY.md)记录实际实现及证据。本文的产品目标不等于已经实现。

地图细则见 [第一张地图](../maps/first-map.md)，画风见 [Art Bible](../art/art-bible.md)。优先级：用户最新确认 → 本 PRD → 专项说明。

---

# 0. 项目决策

## 0.1 项目现状

当前 BreezeTown 已经从早期 2D/联机农场小游戏方向转向 Godot 4.7.2 的 3D 农场原型。

现阶段原型已经具备一部分可玩的基础能力：

- 3D 场景
- 大型农场地图原型
- 玩家移动
- 相机缩放
- 农田
- 种植
- 浇水
- 生长
- 收获
- 商品出售
- 种子商店
- 牧场
- 红色谷仓
- 鸡舍
- 牛、羊、鸡等动物原型
- 睡眠
- 昼夜变化
- 跨天状态更新
- 程序化建筑/物件模型

以上是改造起点。用户后续已允许重建，不要求保留旧视觉实现与地图布局。

## 0.2 核心判断

项目当前最大的问题不是“3D 原型做错了”，而是：

> **旧产品文档仍然描述早期的小型农场项目，而代码已经逐渐变成一个更完整的 3D 农场模拟游戏。**

因此本次版本需要做一次正式的产品与架构切换：

> 保存可回退快照，按参考图重建视觉和地图；完善数据驱动、系统解耦的 3D 农场框架，再以完整地图验证核心玩法。

---

# 1. 产品定位

## 1.1 一句话定位

> 一款采用等距 3D 卡通乡村美术风格的农场生活模拟游戏。玩家在一张完整的核心地图中进行种植、养殖、采集、钓鱼、制作、加工、经营、探索和 NPC 社交，并通过时间、季节和世界状态形成长期成长循环。

## 1.2 核心体验关键词

- 温馨
- 乡村
- 自由探索
- 农场经营
- 收集与成长
- 轻量模拟
- 生活感
- 可持续成长
- 低压力
- 具有沉浸感的每日循环

---

# 2. 视觉目标

用户提供的参考图应被正式定义为项目第一版 **Art Bible / 美术圣经**。

参考图不是“随手参考”，而是建立统一视觉语言的基准。

## 2.1 风格关键词

**Isometric / Stylized 3D / Hand-painted / Cozy / Rural Fantasy / Soft Lighting**

## 2.2 具体视觉规则

| 项目 | 标准 |
|---|---|
| 视角 | 等距/近等距视角 |
| 投影 | Orthographic 优先，可使用弱透视 |
| 镜头 | 斜上方观察 |
| 建模 | 中低面数 |
| 材质 | 手绘感、弱 PBR |
| 光照 | 柔和环境光 + 日光 |
| 阴影 | 柔和但清晰 |
| 植物 | 大轮廓、蓬松、夸张 |
| 建筑 | 圆润、童话式乡村建筑 |
| 地面 | 草地、泥土、石块、花草形成手绘层次 |
| 水体 | 明亮蓝绿色、具有卡通波纹 |
| 角色 | 卡通比例、轮廓清晰 |
| 道具 | 轻微夸张比例，突出可读性 |
| 色彩 | 暖色乡村 + 清新自然色 |
| UI | 木质、纸张、布料、手工感 |

## 2.3 美术统一原则

所有以下资产必须遵循同一视觉体系：

- 建筑
- 道路
- 树木
- 花草
- 作物
- 动物
- 角色
- 道具
- 工坊
- 水体
- 地面
- UI
- VFX

禁止出现“单独看很好看，但放在一起像来自不同游戏”的资产。

---

# 3. 产品范围

第一张地图必须形成完整、可独立验证的核心游戏循环。

## 3.1 核心循环

```text
起床
 ↓
查看天气 / 日历 / 任务
 ↓
处理农场
 ↓
种植 / 浇水 / 采集
 ↓
照顾动物
 ↓
进入森林 / 湖泊 / 其他区域
 ↓
钓鱼 / 采集 / 探索
 ↓
回家加工材料
 ↓
制作 / 烹饪 / 生产
 ↓
和 NPC 互动
 ↓
出售商品 / 购买材料
 ↓
安排第二天
 ↓
睡觉
 ↓
结算 / 生长 / 动物产出 / 世界刷新
 ↓
第二天
```

## 3.2 第一阶段必须包含的系统

### P0 核心系统

- 地图
- Grid
- 玩家移动
- 交互系统
- 农业
- 动物
- 背包
- 物品
- 商店
- 经济
- 时间
- 睡眠
- 存档

### P1 完整玩法系统

- 钓鱼
- 采集
- 制作
- 加工
- NPC
- 任务
- 好感
- 季节
- 天气

### P2 打磨系统

- 建筑升级
- 更完整的事件
- 教学
- 音乐
- 音效
- VFX
- 性能优化
- UI 打磨

### P3 联机

- Host
- Client
- 状态同步
- 多人农场
- 权威世界
- Dedicated Server

---

# 4. 第一张地图定义

## 4.1 “等大”的正确含义

项目不应该以“图片像素一样大”作为地图尺寸标准，也不应该只用“看起来差不多大”。

正式定义：

> 第一张地图采用固定 Tile Grid，并建立统一的空间尺度。地图宽高、功能区域面积、建筑占地、道路宽度、农田面积、玩家移动速度、交互距离、碰撞范围及主要地标关系都采用 Grid/Tile 规则定义。

当前原型约为 92×72 米，可作为技术原型尺寸基线，但最终正式尺寸必须转换为明确的 Grid/Tile 规范。

## 4.2 地图设计原则

- 世界逻辑以 Tile/Grid 为基础
- 视觉模型尺寸不得决定游戏逻辑
- 道路、建筑、农田、交互点全部可由地图数据描述
- 地图边界明确
- 所有可行走区域具备统一碰撞规则
- 所有 NPC 和动物都可通过 Navigation 找到目标地点
- 不允许使用散落的硬编码坐标驱动核心玩法

---

# 5. 第一张地图分区

## A. 玩家农场区

包括：

- 住宅
- 农田
- 水源
- 仓库
- 加工区
- 动物区
- 装饰区
- 玩家可建设区

## B. 村镇核心区

包括：

- 种子商店
- 物品商店
- 出售点
- 公告板
- 公共设施
- NPC 聚集区

## C. 森林区

包括：

- 树木
- 石头
- 野生植物
- 可采集资源
- 隐藏点
- 特殊事件点

## D. 湖泊区

包括：

- 水体
- 钓鱼点
- 码头
- 船
- 鱼群
- 水边采集资源

## E. 牧场区

包括：

- 谷仓
- 鸡舍
- 饲料槽
- 围栏
- 草场
- 动物活动区域

---

# 6. 地图技术架构

不要继续采用“直接在场景里摆物件 + 脚本直接控制物件”的模式。

正式架构：

```text
MapData
 ↓
Grid
 ↓
Terrain
 ↓
StaticObjects
 ↓
Buildings
 ↓
Interactables
 ↓
SpawnPoints
 ↓
Navigation
```

地图应由数据描述。

建议数据结构：

```text
Map
 ├── dimensions
 ├── tiles
 ├── terrain
 ├── collisions
 ├── buildings
 ├── objects
 ├── interactables
 ├── npc_spawn
 ├── animal_spawn
 ├── fishing_zones
 └── resource_nodes
```

---

# 7. 玩家系统

## 7.1 移动

必须支持：

- WASD
- 八方向移动
- 角色朝向
- 移动动画
- 冲刺
- 碰撞
- 移动速度
- 状态控制

## 7.2 PlayerState

```text
PlayerState

id
position
direction
money
energy
health
inventory
tools
equipment
skills
friendship
quests
stats
```

## 7.3 玩家状态设计原则

玩家数据不应该依赖 3D Node 存储。

应该做到：

> 即使不加载 3D 场景，核心 PlayerState 仍然可以运行、保存和恢复。

---

# 8. 工具系统

当前原型已经具备部分基础工具能力，应统一升级成 Tool Framework。

## 8.1 工具类型

```text
Tool
 ├── Hoe
 ├── WateringCan
 ├── Axe
 ├── Pickaxe
 ├── Scythe
 └── FishingRod
```

## 8.2 统一接口

```text
can_use(target)
get_energy_cost()
get_animation()
execute(target)
get_effect()
```

## 8.3 工具升级

每种工具支持等级：

```text
Level 1
Level 2
Level 3
Level 4
```

属性可影响：

- 范围
- 效率
- 能量消耗
- 破坏等级
- 动画
- 特殊能力

---

# 9. 农业系统

农业是第一张地图的第一核心玩法。

## 9.1 土地状态

```text
UNTILLED
TILLED
WATERED
FERTILIZED
READY_TO_PLANT
CROP
DEAD
```

## 9.2 CropData

```text
CropData

id
name
seed_item
season
growth_days[]
water_required
harvest_count
sell_price
exp
model
icon
```

## 9.3 生长流程

```text
种子
 ↓
播种
 ↓
发芽
 ↓
幼苗
 ↓
成长
 ↓
成熟
 ↓
收获
 ↓
死亡 / 再生
```

## 9.4 影响因素

- 日期
- 季节
- 天气
- 浇水
- 土壤
- 肥料
- 作物种类
- 作物品质

---

# 10. 动物系统

当前 3D 原型已经具备基础动物，因此应在此基础上正式化，而不是重新设计。

## 10.1 Animal

```text
Animal

id
species
position
age
friendship
hunger
happiness
health
production
schedule
home
```

## 10.2 行为状态

```text
Wander
 ↓
Eat
 ↓
Interact
 ↓
Produce
 ↓
Rest
 ↓
ReturnHome
```

## 10.3 第一阶段动物

- 鸡
- 牛
- 羊

## 10.4 动物产出

```text
Cow -> Milk
Sheep -> Wool
Chicken -> Egg
```

后续可以增加：

- 鸭
- 山羊
- 猪
- 兔
- 马

---

# 11. 钓鱼系统

钓鱼是第一张地图必须加入的完整玩法系统。

## 11.1 核心流程

```text
来到水边
 ↓
装备钓竿
 ↓
抛竿
 ↓
等待
 ↓
鱼上钩
 ↓
鱼开始挣扎
 ↓
控制收线/张力
 ↓
成功
 ↓
获得鱼
```

## 11.2 FishData

```text
FishData

id
species
rarity
location
season
weather
time
behavior
difficulty
sell_price
```

## 11.3 钓鱼系统应支持

- 多种鱼
- 不同时间
- 不同天气
- 不同季节
- 不同钓鱼区域
- 不同鱼类行为
- 稀有鱼
- 鱼品质
- 钓鱼经验
- 钓鱼等级

---

# 12. 采集系统

建立统一的 ResourceNode。

## 12.1 资源类型

```text
Tree
Rock
Bush
Flower
Herb
WildCrop
Shell
FishingSpot
```

## 12.2 统一接口

```text
can_harvest()
harvest()
respawn()
```

## 12.3 资源刷新

支持：

- 每日刷新
- 多日刷新
- 季节刷新
- 条件刷新
- 特殊事件刷新

---

# 13. 制作系统

制作必须数据驱动，不能把配方直接写在 UI 里。

## 13.1 RecipeData

```text
RecipeData

id
inputs
outputs
time
required_station
unlock_level
```

例如：

```text
Wood x10
+
Stone x5
↓
Chest
```

---

# 14. 加工系统

参考图中已经有炉子、加工台、宝箱等功能设施，因此加工系统需要与建筑/机器系统统一设计。

## 14.1 Machine

```text
Machine
 ├── Input
 ├── Recipe
 ├── ProcessingTime
 ├── Output
 ├── State
 └── Animation
```

## 14.2 Machine State

```text
EMPTY
INPUT_READY
PROCESSING
FINISHED
COLLECTED
```

---

# 15. 背包与仓库

## 15.1 玩家背包

支持：

- 格子
- 堆叠
- 拖动
- 使用
- 丢弃
- 分类
- 快捷栏

## 15.2 仓库

支持：

- 箱子
- 农场共享仓库
- 自动整理
- 分类
- 堆叠
- 扩容

---

# 16. 物品系统

所有物品统一使用 ItemData。

```text
ItemData

id
name
type
icon
model
max_stack
price
tags
use_action
description
```

物品类型：

```text
Seed
Crop
Resource
Tool
Material
AnimalProduct
Fish
Food
QuestItem
Machine
Decor
```

---

# 17. 商店与经济系统

当前原型已经有种子商店和出售功能，应继续演进。

## 17.1 商店

支持：

- 种子购买
- 材料购买
- 工具购买
- 道具购买
- 出售
- 商品解锁
- 每日库存
- 商品刷新

## 17.2 经济系统

```text
Item
 ↓
BasePrice
 ↓
BuyPrice
SellPrice
 ↓
ShopInventory
```

---

# 18. NPC 系统

NPC 是把“农场 Demo”升级成完整生活模拟游戏的关键。

## 18.1 NPC 数据

```text
NPC

id
name
appearance
schedule
dialogue
friendship
gift_preference
quests
events
```

## 18.2 NPC 日程

推荐结构：

```text
Time
 ↓
Schedule
 ↓
Goal
 ↓
Navigation
 ↓
Action
```

而不是：

```text
if hour == 8:
    npc.position = Vector3(...)
```

## 18.3 NPC 行为

例如：

```text
07:00 起床
 ↓
08:00 工作
 ↓
12:00 午餐
 ↓
14:00 行走
 ↓
18:00 回家
 ↓
22:00 睡觉
```

实际内容可根据项目世界观重新设计。

---

# 19. NPC 好感

第一阶段采用简单、可靠的数值体系。

```text
FriendshipPoints
```

增加来源：

- 对话
- 礼物
- 任务
- 特殊事件

等级：

```text
Level 0
Level 1
Level 2
...
```

后续再扩展关系事件。

---

# 20. 时间系统

时间是全局核心服务。

## 20.1 GameClock

```text
GameClock

Year
Season
Day
Hour
Minute
TimeScale
```

## 20.2 事件

```text
DayStarted
HourChanged
DayEnded
SeasonChanged
```

## 20.3 系统订阅

```text
GameClock
 ↓
FarmSystem
AnimalSystem
MachineSystem
NPCSystem
WeatherSystem
QuestSystem
WorldSystem
```

---

# 21. 季节系统

支持：

- 春
- 夏
- 秋
- 冬

季节影响：

- 作物
- 鱼
- NPC
- 商店
- 环境
- 草
- 树
- 花
- 资源

---

# 22. 天气系统

天气类型：

```text
SUNNY
CLOUDY
RAIN
STORM
SNOW
```

天气影响：

- 作物浇水
- 动物行为
- NPC 行为
- 钓鱼
- 采集
- 环境效果
- BGM
- VFX

---

# 23. 体力系统

加入 Energy 系统。

例如：

```text
砍树 -10
挖矿 -8
锄地 -2
浇水 -1
钓鱼 -5
```

体力消耗必须由 Tool/Action Data 配置，而不是写死在玩家控制器里。

---

# 24. 任务系统

## 24.1 QuestData

```text
Quest

id
requirements
progress
reward
deadline
unlock
```

## 24.2 任务类型

- 收集
- 种植
- 收获
- 加工
- 钓鱼
- 对话
- 送礼
- 探索
- 公共建设

---

# 25. 建筑系统

建筑数据和建筑模型必须分离。

## 25.1 BuildingData

```text
BuildingData

id
size
footprint
collision
door
interior
interactables
upgrade
```

## 25.2 第一阶段建筑

- 住宅
- 谷仓
- 鸡舍
- 商店
- 工作台
- 炉子
- 水井
- 仓库
- 宝箱
- 风车
- 公告牌

---

# 26. 室内系统

室外与室内采用 Scene Transition。

```text
World
 ├── Outdoor
 ├── HouseInterior
 ├── ShopInterior
 ├── BarnInterior
 └── CoopInterior
```

统一入口：

```text
Door
 ↓
SceneTransition
 ↓
Interior
```

---

# 27. 存档系统

当前项目必须在新增大量系统前完成可靠存档。

## 27.1 必须保存

```text
World
Player
Inventory
Money
Crops
Animals
Machines
Buildings
NPC
Friendship
Quest
Time
Weather
Season
MapState
```

## 27.2 必须支持

- 新存档
- 加载存档
- 自动保存
- 手动保存
- Save Backup
- 崩溃恢复
- 版本迁移

---

# 28. 推荐存档结构

```text
save/
 ├── meta.json
 ├── world.json
 ├── players/
 ├── maps/
 └── backups/
```

核心原则：

> 存档内容代表游戏世界，而不是代表当前 Scene 树。

---

# 29. UI 系统

UI 与业务解耦。

## HUD

```text
HUD
 ├── Clock
 ├── Weather
 ├── Energy
 ├── Money
 ├── Hotbar
 └── Notification
```

## 独立界面

```text
Inventory
Shop
Dialogue
Quest
Map
Crafting
Animal
Building
Save
Settings
```

---

# 30. Camera 系统

建立统一的 CameraController。

```text
CameraController
 ├── Zoom
 ├── Rotation
 ├── Follow
 ├── Bounds
 ├── Smoothness
 └── Shake
```

原则：

> Camera 只负责视觉表现，不参与世界逻辑。

---

# 31. 美术资产架构

当前项目主要使用程序化模型生成，适合作为早期快速原型。

但正式版本应该逐步升级到：

```text
ArtSource
 ↓
Prefab
 ↓
GameObject
```

而不是长期使用：

```text
Gameplay Script
 ↓
GenerateMesh()
```

## 31.1 资产分类

```text
art/
├── characters/
├── buildings/
├── environment/
├── crops/
├── animals/
├── props/
└── materials/
```

## 31.2 美术与玩法分离

同一个：

```text
BuildingID = House_01
```

可以绑定不同视觉 Prefab：

```text
House_01
 ↓
House_01_Prefab
 ↓
CurrentArtStyle
```

逻辑与模型解耦后，未来可替换美术风格。

---

# 32. 推荐工程结构

建议逐步向以下结构迁移：

```text
game/
├── project.godot
│
├── scenes/
│   ├── main/
│   ├── world/
│   ├── player/
│   ├── npc/
│   ├── animals/
│   ├── buildings/
│   ├── machines/
│   └── ui/
│
├── scripts/
│   ├── core/
│   │   ├── game_manager.gd
│   │   ├── time_manager.gd
│   │   ├── save_manager.gd
│   │   └── event_bus.gd
│   │
│   ├── player/
│   ├── farming/
│   ├── animals/
│   ├── fishing/
│   ├── crafting/
│   ├── economy/
│   ├── npc/
│   ├── quests/
│   ├── world/
│   └── ui/
│
├── data/
│   ├── crops/
│   ├── items/
│   ├── animals/
│   ├── recipes/
│   ├── fish/
│   ├── npc/
│   ├── buildings/
│   └── quests/
│
├── maps/
│   └── farm_01/
│
├── art/
│   ├── characters/
│   ├── buildings/
│   ├── environment/
│   ├── crops/
│   ├── animals/
│   ├── props/
│   └── materials/
│
└── tests/
```

---

# 33. 核心架构原则

必须形成：

```text
UI
 ↓
Application
 ↓
Domain
 ↓
Data
```

避免：

```text
UI Button
 ↓
直接修改 Player
 ↓
直接修改金币
 ↓
直接修改作物
```

推荐通过 Command / Service / Event：

```text
Player clicks Harvest
 ↓
HarvestCommand
 ↓
FarmService
 ↓
Validate
 ↓
Apply
 ↓
Event
 ↓
Inventory / Stats / UI
```

---

# 34. EventBus

建议建立全局事件总线。

## 事件列表

```text
day_started
day_ended
crop_harvested
crop_planted
crop_watered
animal_fed
animal_product_ready
item_added
item_removed
money_changed
npc_interacted
quest_completed
machine_finished
weather_changed
season_changed
```

## 原则

- 系统之间尽量不直接引用
- UI 监听事件
- 数据系统发布事件
- 业务逻辑通过 Service 完成

---

# 35. 当前代码改造方案

## 总原则

**按用户最新授权可重建当前原型。保留可回退快照，以参考画风、真实比例与玩法验收决定实现取舍。**

采用：

```text
Current 3D Prototype
 ↓
Freeze
 ↓
Refactor
 ↓
Extract Systems
 ↓
Data-Driven
 ↓
Add New Systems
```

---

# 36. M0 架构重构

M0 不新增大量玩法，只负责让现有项目具备持续开发条件。

## M0-01：冻结当前版本

建立版本：

```text
v0.3-3d-vertical-slice
```

保证：

- 种植
- 浇水
- 收获
- 商店
- 动物
- 睡眠

仍可以完整运行。

## M0-02：提取 Domain State

抽离：

```text
CropState
AnimalState
ItemState
PlayerState
WorldState
```

要求：

> 不依赖 Node3D 就能运行核心数据逻辑。

## M0-03：建立核心系统

新增：

```text
MapData
Grid
InteractionSystem
GameClock
SaveManager
EventBus
```

## M0-04：转换作物数据

从：

```gdscript
if crop_type == "tomato":
    ...
elif crop_type == "corn":
    ...
```

逐步迁移至：

```text
CropData
```

## M0-05：统一交互

建立：

```text
InteractionSystem
 ↓
TargetResolver
 ↓
InteractionTarget
 ↓
Action
```

目标包括：

```text
Crop
Animal
Machine
NPC
Door
Chest
FishingSpot
Shop
Building
```

## M0-06：GameClock

统一处理：

```text
Day
Hour
Minute
Season
Weather
```

## M0-07：SaveManager

先保存：

```text
day
player
inventory
money
farm
animals
buildings
```

---

# 37. 为什么要先 M0

不要在当前项目上直接追加：

```text
钓鱼
NPC
天气
季节
任务
制作
建筑升级
联机
```

否则会变成：

> 功能越来越多，但每个系统互相耦合，改一个系统会影响其他系统。

因此 M0 是必须的。

---

# 38. 开发里程碑

## M0：架构重置

目标：

> 让现有 3D Demo 变成可以长期扩展的基础。

完成：

- Domain State
- EventBus
- GameClock
- ItemData
- CropData
- InteractionSystem
- SaveManager
- MapData

---

## M1：第一张地图正式版

完成：

- Grid
- 地形
- 农场
- 住宅
- 商店
- 森林
- 湖泊
- 牧场
- 道路
- 码头
- 地图边界
- Navigation

---

## M2：农业完整版

完成：

- 多作物
- 季节
- 生长
- 浇水
- 肥料
- 品质
- 收获
- 种子
- 经验
- 工具升级

---

## M3：畜牧完整版

完成：

- 鸡
- 牛
- 羊
- 饲料
- 好感
- 动物 AI
- 生产
- 建筑
- 建筑容量
- 建筑升级

---

## M4：探索 + 钓鱼 + 采集

完成：

- 钓鱼
- 鱼类
- 森林资源
- 采集
- 工具
- 资源刷新
- 水边玩法

---

## M5：NPC + 任务

完成：

- NPC
- 日程
- 移动
- 对话
- 好感
- 礼物
- 任务
- 特殊事件

---

## M6：制作 + 加工 + 经济

完成：

- 制作
- 炉子
- 加工台
- 宝箱
- 商店
- 出售
- 经济循环

---

## M7：最终打磨

完成：

- 音效
- BGM
- VFX
- UI
- 教学
- 新手流程
- 性能
- Save Recovery
- Bug 修复
- UX 优化

---

# 39. 第一张地图最终完成条件

第一张地图不能以“场景做完”作为完成标准。

必须完整跑通：

```text
New Game
 ↓
Spawn
 ↓
获得初始工具
 ↓
开垦农田
 ↓
播种
 ↓
浇水
 ↓
等待作物生长
 ↓
收获
 ↓
出售
 ↓
购买新种子
 ↓
照顾动物
 ↓
获得动物产品
 ↓
加工
 ↓
制作
 ↓
进入森林
 ↓
采集
 ↓
进入湖边
 ↓
钓鱼
 ↓
NPC 对话
 ↓
接受任务
 ↓
完成任务
 ↓
领取奖励
 ↓
睡觉
 ↓
第二天
 ↓
所有状态正确保存
 ↓
退出游戏
 ↓
重新进入
 ↓
进度完全恢复
```

---

# 40. 测试体系

## 40.1 单元测试

测试：

- Crop
- Item
- Inventory
- Animal
- Fish
- Recipe
- Economy
- Time
- Save

## 40.2 集成测试

例如：

```text
Plant
→ Save
→ Load
→ Grow
→ Harvest
```

## 40.3 游戏测试

至少完整跑：

```text
Day 1
→ Day 2
→ Day 3
```

并确认所有世界状态正确。

---

# 41. 自动化验收标准

## TEST-001：新建世界

```text
Player exists
Money exists
Inventory exists
Day = 1
```

## TEST-002：种植

```text
Tilled
→ Planted
→ Watered
```

## TEST-003：成长

```text
Day + 1
→ GrowthStage + 1
```

## TEST-004：收获

```text
Crop removed
Item added
XP added
```

## TEST-005：动物

```text
Fed
→ Happiness+
→ Production
```

## TEST-006：钓鱼

```text
Cast
→ Bite
→ Success
→ Fish added
```

## TEST-007：存档

```text
Play
→ Save
→ Quit
→ Load
→ State identical
```

---

# 42. 旧 PRD 的处理方式

按用户 2026-09-16 要求，删除失效的旧 2D 产品 PRD、架构契约、路线图、验收与执行准备文档，并清除 README 旧需求入口。历史内容可从 Git 查询，不在工作区保留第二套产品基线。

当前产品方案为本文；地图规则见 [first-map.md](../maps/first-map.md)，美术见 [Art Bible](../art/art-bible.md)，后续工作统一存于 [当前任务板](../execution/task-board.md)。历史 ADR 和测试报告保留，标明适用版本。

---

# 43. 为什么不要现在直接做联机

原项目早期大量目标围绕：

- 1–4 人合作
- Host
- Client
- 共享资金
- 权威服务器
- Dedicated Server
- 联机状态同步

这些设计并不是没有价值，但当前项目已经发生产品方向变化。

推荐：

```text
单机完整玩法
 ↓
稳定存档
 ↓
完整第一张地图
 ↓
完整系统
 ↓
性能优化
 ↓
联机
 ↓
Dedicated Server
```

不要同时开发：

```text
3D
+
大地图
+
NPC
+
动物
+
钓鱼
+
季节
+
天气
+
联机
+
Dedicated Server
```

否则复杂度会快速增长。

---

# 44. 产品版本路线

## V2.0 — 单机完整版

目标：

> 第一张地图完整可玩。

包含：

- 农业
- 牧场
- 钓鱼
- 采集
- 制作
- 加工
- NPC
- 时间
- 季节
- 天气
- 任务
- 好感
- 存档

## V2.5 — 联机

加入：

- Host
- Client
- 世界同步
- 多人农场
- 多人交互
- 权威世界

## V3.0 — Dedicated Server

加入：

- Dedicated Server
- 世界托管
- 管理
- 备份
- 世界迁移
- 长期在线世界

---

# 45. 最终技术路线图

```text
                ┌──────────────────────┐
                │ 当前 3D Vertical Slice │
                └──────────┬───────────┘
                           ↓
                ┌──────────────────────┐
                │      架构重构 M0       │
                └──────────┬───────────┘
                           ↓
        ┌──────────────────┼──────────────────┐
        ↓                  ↓                  ↓
     Map/Grid           Game Data           Save
        │                  │                  │
        └──────────────────┼──────────────────┘
                           ↓
                     Core Gameplay
                           ↓
       ┌────────┬──────────┼────────┬─────────┐
       ↓        ↓          ↓        ↓         ↓
      Farm    Animal     Fishing  Crafting   NPC
       │        │          │        │         │
       └────────┴──────────┼────────┴─────────┘
                           ↓
                 Time / Season / Weather
                           ↓
                    Economy / Quest
                           ↓
                 第一张地图完整版
                           ↓
                      QA / Polish
                           ↓
                         V2.0
                           ↓
                       联机 V2.5
                           ↓
                  Dedicated Server V3.0
```

---

# 46. 当前代码审计与改造优先级

| 优先级 | 改造项 |
|---|---|
| P0 | 数据驱动 |
| P0 | Domain/Application/Presentation 分层 |
| P0 | GameClock |
| P0 | SaveManager |
| P0 | InteractionSystem |
| P0 | EventBus |
| P0 | Map/Grid 数据化 |
| P1 | 农业完整化 |
| P1 | 动物完整化 |
| P1 | 钓鱼 |
| P1 | 采集 |
| P1 | 制作/加工 |
| P1 | NPC |
| P2 | 季节天气 |
| P2 | 任务 |
| P2 | 好感 |
| P2 | 建筑升级 |
| P3 | 联机 |
| P3 | Dedicated Server |

---

# 47. 第一阶段执行任务模板

每个开发任务都应该包含：

```text
Task ID
Task Name
Goal
Current Code
Files To Modify
Files To Create
Dependencies
Implementation Details
Acceptance Criteria
Test Cases
Expected Commit
Rollback Plan
```

示例：

## TASK-M0-001：建立 GameClock

### Goal

建立全局游戏时间系统，替换现有分散的日期/睡眠逻辑。

### Dependencies

- EventBus

### Files

```text
scripts/core/game_clock.gd
scripts/core/event_bus.gd
tests/test_game_clock.gd
```

### Acceptance Criteria

- Day 正常推进
- Hour 正常推进
- Minute 正常推进
- 日结算事件正确触发
- 新一天事件正确触发
- 其他系统可以订阅
- 不直接依赖 Player Node

### Test

```text
Day 1
→ Sleep
→ Day 2
```

---

# 48. 开发纪律

## 规则 1

新系统不得直接修改其他系统的内部变量。

## 规则 2

所有可配置内容尽量数据驱动。

## 规则 3

世界状态与 3D 表现分离。

## 规则 4

UI 不直接执行业务逻辑。

## 规则 5

不要为了一个功能把核心架构重新写一遍。

## 规则 6

任何新玩法必须提供：

- 数据结构
- 业务逻辑
- UI
- Save
- Event
- Test

## 规则 7

所有修改都必须能回滚。

---

# 49. 当前项目最重要的转型

现在项目不是：

> “继续开发一个已经有一些功能的 3D 农场 Demo”。

而应该正式变成：

> **“基于当前 3D Vertical Slice，建立一个可以长期扩张的完整 3D 农场模拟游戏框架，并用第一张地图完成所有核心玩法验证。”**

重建范围以用户最新确认和参考图验收为准。

应该：

> **保留可回退快照；按参考图重建，解除旧假设和玩法耦合；以用户确认后的 V2 PRD 和当前任务板继续开发。**

---

# 50. 第一阶段完成后的 Definition of Done

满足以下条件，M0 才算完成：

- [ ] 当前 3D 原型可正常运行
- [ ] 旧功能行为不回归
- [ ] PlayerState 与 Node3D 分离
- [ ] CropState 与 Node3D 分离
- [ ] AnimalState 与 Node3D 分离
- [ ] ItemData 建立
- [ ] CropData 建立
- [ ] AnimalData 建立
- [ ] RecipeData 建立
- [ ] GameClock 建立
- [ ] EventBus 建立
- [ ] InteractionSystem 建立
- [ ] SaveManager 建立
- [ ] MapData 建立
- [ ] Grid 规则建立
- [ ] 基础自动化测试建立
- [ ] 新存档和加载可靠
- [x] 失效旧 PRD 已删除，当前需求与任务入口已统一
- [ ] V2 PRD 成为正式开发基线

---

# 51. 最终结论

当前执行路线为：

> **保存快照 → 按参考图重建视觉和真实比例地图 → 完善架构 → 用 Grid/Data/Event/Save 建立底座 → 逐步补齐农业、动物、钓鱼、采集、制作、NPC、季节、天气、任务 → 打磨第一张完整地图 → 最后再做联机。**

实际顺序与完成情况持续记录在当前任务板。

项目开发优先顺序最终锁定为：

```text
M0 架构重构
 ↓
M1 第一张地图
 ↓
M2 农业
 ↓
M3 动物
 ↓
M4 钓鱼 + 采集
 ↓
M5 NPC + 任务
 ↓
M6 制作 + 加工 + 经济
 ↓
M7 打磨
 ↓
V2.0 单机完整版本
 ↓
V2.5 联机
 ↓
V3.0 Dedicated Server
```
