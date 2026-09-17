# V2 接续记录（历史日志）

更新：2026-09-17。本文件只留各轮改动与验证的过程记录；**当前状态、下一批任务与运行命令以 [任务板](task-board.md) 为准**（续作入口）。最近一轮：画风对照迭代完成，对照截图 `work/art01/style3-farm.png`，画风终验待用户实机确认。

## 2026-09-17 · 画风对照第二轮（视觉对照 + 回归修复）

对照样例库（style-board / ui-hud / lake-dock）与实机逐项比对后改动：`tile.gd`、`cozy_landscape.gd`、`water_models.gd`、`hud.gd`。

- **修复两处 PERF-01 引入的视觉回归**（此前截图误判为正常）：①苗床木框旋转方向写反，田里出现横穿木条；②作物烘焙网格带 12 米容器偏移，被实例随机朝向绕原点甩出十几米，草坪散落大量南瓜/草莓。修法：木框按边缘方向旋转；烘焙后把顶点平移回原点再缓存。
- 草地着色器向参考图靠拢：色板加深加饱和，新增斜向修剪条纹与更明显的双色斑点。
- 水体更深更蓝（深度权重 0.5→0.62），湖面波纹笔触改细并贴近水色。
- 干土调暖（#7e5a3b / 垄 #654331·#735035）。
- HUD 对照 ui-hud：日期栏改为四段羊皮纸药丸（季节/日期/天气/时钟 + 粉红黄蓝图标点）；选中工具槽金光增强（4px 金框 + 9px 外发光）。
- 验证：默认 smoke、地图专项 146、领域全部 PASS，0 脚本错误。截图 `style3-farm.png`、`fix3-homestead.png`。
- 与参考图剩余差距（下轮候选）：牧区牲畜可见度、角色头身比、工具图标插画质感、室内场景。

## 2026-09-17 · PERF-01 第一轮（启动与绘制优化）

改动文件：`art_mesh.gd`（图元网格参数缓存）、`water_models.gd`（岸石并入共享网格 + 修一处潜在死循环步进）、`tile.gd`（视觉层重写：土壤/木框/作物网格按种类静态缓存，作物 MultiMesh 实例化，湿土换缓存网格）、新增常驻工具 `tests/perf_checks.gd`（启动耗时、分区帧时间分位、draw calls、内存、高分辨率）。

- 基线（M5 / 1600×1000 / 窗口）：启动 56.4s；农场 p50 16.8ms、draws 4607；传送后偶发 >1s 卡顿。
- 热点：①海岸线水岸石逐颗实例化（1542 个 320 顶点网格）；②每块耕格的作物逐格烘焙 ≈0.45s/格 ×64 初始格 ≈29s；③静态合并按实例 append 固定开销 ~0.9ms × 1.6 万实例 ≈14s。
- 优化后：**启动 56.4s→23.0s**（剩 ~20s 为冷启动世界构建，可用世界视觉缓存解决，留待第二轮）；**农场 draws 4607→2529**；农场/镇区/森林/果园/港口 p50、p90 全部在 16.7ms 帧预算内（60fps）；2560×1600 农场 p50 21.3ms（≈47fps）；内存 ~180MB。传送后的区块重建尖峰（单次 ~0.5–1.7s）仍在，属跨区传送场景，正常游玩按 64m 分块渐进加载。
- 验证：默认 smoke、地图专项 146、持久化两阶段 10+9 全 PASS，0 脚本错误；菜园实机截图视觉无损（见画风第二轮 `style3-farm.png`；当时截图 `perf01-garden.png` 已在清理中删除）。性能日志 `work/art01/perf01-run3.log`，命令见 `perf_checks.gd` 头注。

## 2026-09-17 · WORLD-01 第一轮（分块森林可交互与全量持久化）

改动文件：`first_map_scenery.gd`（重写：稳定 ID 注册表、swing/target_at、持久化、耕地避让）、`surface_resources.gd` 与 `mine_floor.gd`（to_dict/apply_state）、`main.gd`（scenery 成员、斧击路由、战利品通道、存档三新键、矿层恢复）、`core/interaction_system.gd`（chunk_tree 目标）、新增 `tests/world_persist_checks.gd`。

- 分块森林每棵树有稳定 ID（`forest:区块:格` / `orchard:行:列` 字符串，JSON 往返安全）；注册表驱动斧击：36 血、每击 18（两下砍倒，与地表树一致），破坏后重建该 64 米区块、释放占用、经 `tree_broken` 信号走与地表树相同的掉落通道（木材 4–7 + 30% 树苗）。
- 持久化采用**差异存储**：只保存玩家造成的移除列表，森林生成默认值保持确定性——存档体积不随森林大小增长。半砍的树血量不持久（重启回满，已记录为设计）。
- 存档新增三键：`surface`（全部地表资源+掉落物状态）、`forest`（移除列表）、`mine`（各层已破坏岩格/掉落/宝箱/营地/梯子旗标+当前层数）。读档在矿场时直接回到对应层与原位置；重复读档幂等。
- 环境树不覆盖已保存耕地：区块树放置避让 3×3 耕格（`farm_tiles`）；地表资源按存档重建后再执行田块/圈地冲突清理。
- 新增两阶段重启测试 `world_persist_checks.gd`（write/verify 两个独立进程，共用 BREEZETOWN_SAVE_ROOT）：砍树→掉木材、种树苗、耕种、矿场破岩→存档→**新进程**读档→树未复活/未重注册、树苗/耕地保留、矿层与岩格一致、双读档幂等，10+9 项全过。
- 回归：默认 smoke、旧图 `--reference-farm` smoke、地图专项 146、领域、地图规则全部 PASS，0 脚本错误。
- 遗留：矿场怪物重启后重新出现（守护者设计，宝箱旗标防重复领取）；半砍森林树血量不持久。


## 2026-09-17 · MAP-01 第一轮（逐区地形与装饰）

改动文件：`first_map_terrain.gd`（北岭主脉、瀑布峰体）、`water_models.gd`（`_cascade` 参数化瀑布并接入大图）、`first_map_definition.gd`（湖畔码头 dock）、`first_map_scenery.gd`（苹果树部件 + 果园行栽网格）、`first_map_builder.gd`（镇区/港口/NPC 农庄装饰、湖畔小船）、`first_map_checks.gd`（码头数 7、四条主干路线寻路检查）。

- 西北：7 座 62–114 米雪峰补足天际线；瀑布地标处 6 峰收口 + 两座侧峰，`_cascade` 从 24 米高五级跌入 north_creek，含泡沫条纹与阶侧岩。
- 果园：区块系统新增 apple 部件；果园区域 13 米世界对齐网格行栽（约 1300 株全园），避让水/路/建筑，登记占用与碰撞；随机林区跳过果园防重叠。
- 湖畔：lake_view 地标向东 17 米码头（walkway 渲染、水域碰撞扣除、可行走/不可耕作自动生效），尽头系小划艇。
- 港口：长栈桥系缆桩与货堆；深水栈桥尽头木吊车（桅杆/斜臂/拉索/吊钩），岸侧船桨浮标；吊车接入夜灯。
- 镇区：广场四边长椅朝喷泉、四角街灯、西侧两座条纹市集棚、东北告示板。
- NPC 农庄：谷仓南侧 38×24 米畜栏（避让道路自动留口）、双层干草捆、木桶、水壶、街灯；农舍周边 2600 簇草花，避让三栋建筑、全部耕地、道路与畜栏。
- 路线验证改为沿路途经点逐跳寻路（每跳 ≤250 米保分辨率，跨河只经桥）：农场→镇区→矿口、镇区→NPC 农庄、镇区→港口全部连通；镇广场中心为喷泉碰撞体，途经点改用边缘。
- 验证：地图专项 146 项（含新路线 4 项）、smoke 310 项、领域、地图规则全部 PASS，0 脚本/着色器错误。截图 `work/art01/map01-{waterfall,orchard,harbor,town-square,npc-farm,lake-pier}.png`。
- 遗留：homes 住宅区庭院未装饰；瀑布山地仍可穿行（沿既有矿山行为）；画面验收待用户。


## 2026-09-17 · ART-01 第一轮（农场近景）

改动文件：`first_map_builder.gd`（庭院装饰、大田着色、道具放置）、`cozy_landscape.gd`（花色调板、灌木团簇）、`tile.gd`（苗床木框、作物随机变化）、`landscape_models.gd`（新增干草捆/柴堆/邮箱）。

- 农舍周边 200×124 米庭院：约 5600 簇草花（密度随离舍距离衰减）、6 处花境、井边花环、12 处灌木群（不规则团簇 + 随机浆果）、14 株背景树（避让森林遮罩与道路）。
- 生活道具经 `_place_prop()` 统一放置：自动避让道路/建筑/菜园并登记障碍——柴堆、木桶、板条箱、邮箱、两根灯柱（接入夜灯）、双层干草捆、水壶、踏石。
- 苗床木框按"邻居未耕才显示"规则画边板，玩家后续开荒同样生效；相邻格耕开后边板自动隐藏。
- 大田改用犁沟条纹着色器（世界空间垄向 + 土块噪声 + 边缘磨损），9 块农田零额外面数；期间修复一处 GLSL 括号笔误导致的 headless 着色器编译失败。
- 验证（`work/art01/`）：地图专项 132 项、默认 smoke 310 项、领域、地图规则全部 PASS，0 脚本错误；实机采样 60 FPS。截图：`final-garden.png`、`final-homestead.png`（固定 `--hour=11`）。
- 画风验收仍需用户对照 [style-board](../art/reference/style-board.png) 评估；本轮未动建筑 GLB、角色与 UI，比例统一属后续轮次。


## 当前实际状态

默认地图 `willow_creek_valley_v1`，约 2598 × 2374 米。西南玩家、东北 NPC；建筑按图定位、使用实际尺寸。已接入地图、近景美术、HUD、农牧/商店/林业/十层矿场和基础存档。**整体画风仍未达到参考图，完整 V2 尚未完成。**

- 蓝图：`game/resources/maps/first_map_blueprint.json`；换算：`game/scripts/data/first_map_definition.gd`。
- 构建：`world_builder.gd` → `first_map_builder.gd`；地形：`art/first_map_terrain.gd`；森林：`first_map_scenery.gd`。
- 原图：`docs/art/reference/`；[地图说明](../maps/first-map.md)记录坐标、误差、资产生成流程。
- 模型：`game/resources/models/*.glb`；源文件：`art/3d/source/*.blend`；生成器：`tools/art/`。
- 农舍附近田地/资源可交互。大片田地多为地表表现；分块森林目前属于环境植被，尚未全部支持砍伐和持久化；多数服务建筑只有外观。
- 森林以 64 米区块加载附近 3 × 3 块，水岸碰撞/寻路计算有界；全图性能、远景、长时间体验仍待验证。

近期修复：GLB 顶点色、过高农舍/镜头截断、围栏挡路、北桥轴向与侧入口、桥栏碰撞、狭窄码头半径判断、NPC 农田保护、跨地图存档混用及高分辨率 HUD 缩放。

## 存档边界

- 大图：`user://saves/willow_creek_valley_v1/slot_1/`。
- 旧近景：`user://saves/slot_1/`，用 `--reference-farm` 启动。
- `SaveManager.select_world()` 选择目录；`MapRestore.plan()` 拒绝不兼容地图/大图无法识别来源的旧档，保持当前状态。这是隔离和拒绝，不是坐标迁移。
- 测试通过 `BREEZETOWN_SAVE_ROOT` 使用独立目录。
- `WORLD-01` 后存档已覆盖地表资源、掉落物、分块森林移除差异与矿层状态（岩格/宝箱/营地/梯子）；怪物重启后重新出现，半砍森林树血量不持久。

## 已核对的验证证据

2026-09-16 以下日志均有 PASS，无 `ERROR` / `SCRIPT ERROR`：

| 验证 | 结果 | 日志 |
|---|---|---|
| 比例、归属、建筑/桥梁、水岸、围栏、NPC 土地、存档隔离与矿场往返读档 | 132 项 | [first-map.log](../../work/first-map/validation/first-map.log) |
| 领域数据、经济、时钟、存档 | 49 项 | [core.log](../../work/first-map/validation/core.log) |
| 地图规则、寻路、迁移 | 21 项 | [map-domain.log](../../work/first-map/validation/map-domain.log) |
| 默认地图完整 smoke | 310 项 | [default-smoke.log](../../work/first-map/validation/default-smoke.log) |
| 旧近景 smoke | 265 项 | [legacy-smoke.log](../../work/first-map/validation/legacy-smoke.log) |
| 普通林业输入 | 12 项 | [forestry-input.log](../../work/first-map/validation/forestry-input.log) |
| 普通矿场输入 | 11 项 | [mine-input.log](../../work/first-map/validation/mine-input.log) |
| 资源导入 | 无脚本错误 | [import.log](../../work/first-map/validation/import.log) |

完整 smoke 与普通输入先通过；最后新增的 NPC 土地、存档隔离修复由随后重跑的地图专项、领域和地图规则检查覆盖。最后修复后未重复全部套件。

实机截图：[玩家农场](../../work/visual-slice/scaled-farm-final.png)、[全域导览](../../work/visual-slice/scaled-map-final.png)。[描图叠加图](../maps/first-map-trace.png)只用于原图对位。截图 FPS 属于短时采样，不构成性能验收。

## 运行命令

在仓库根目录执行：

```sh
# 默认真实比例地图
tools/engine/Godot-4.7.2-stable/Godot.app/Contents/MacOS/Godot --path game

# 专项验证，隔离存档
BREEZETOWN_SAVE_ROOT="$PWD/work/game-data/check" tools/engine/Godot-4.7.2-stable/Godot.app/Contents/MacOS/Godot --headless --path game --script res://scripts/tests/first_map_checks.gd

# 地图规则
tools/engine/Godot-4.7.2-stable/Godot.app/Contents/MacOS/Godot --headless --path game --script res://scripts/tests/map_domain_checks.gd

# 固定窗口与时间截图
tools/engine/Godot-4.7.2-stable/Godot.app/Contents/MacOS/Godot --path game --windowed --resolution 1600x1000 -- --hour=11 --shot="$PWD/work/art01/next.png"
```

资源导入使用 `--headless --editor --path game --quit`。Godot 可能在脚本报错后仍退出 0，必须检查日志。

## 本轮文档清理

按用户要求删除旧 2D 产品 PRD、架构契约、路线图、验收和执行准备共 5 份失效需求文档，移除 README 的旧需求入口。保留 V2 全文与参考图，更新与后续确认冲突的条款。历史 ADR、2D 执行/测试报告保留并标注其适用版本；旧任务状态不再驱动开发。
