# 微风小镇 V2 · 任务板（续作唯一入口）

更新：2026-09-17（画风第二轮 + 工作区清理后）。上一提交 `aa6f164`；工作区未提交改动 = ART/MAP/WORLD/PERF 四轮实现 + 文档清理。

**下次接续方法**：读本文 → `git status` / `git log -3` 确认现场 → 从「下一批任务」按顺序取第一项执行。历史过程见 [接续记录](SUMMARY.md)，产品范围见 [V2 PRD](../product/01-product-prd-v2.md)，地图/画风规范见 [地图说明](../maps/first-map.md) 与 [Art Bible](../art/art-bible.md)。

## 已确认，不重复询问

1. Godot 4.7.2 / 3D；以用户 UI 与美术参考图（`docs/art/reference/`）为目标，允许破坏性改造，旧模型与布局不构成保留约束。
2. 地理基准 [first-map-scale.png](../art/reference/first-map-scale.png)，400 米 / 202 像素 ≈ **2598 × 2374 米**；X 东 Z 南，耕地格 2 米；建筑按图定位、用实际尺寸，不按图标轮廓定占地。
3. **西南玩家农场，东北 NPC 农庄**；出生、初始菜园、初始牧场在西南；东北土地不可开垦/围建。
4. V2 单机完整地图先行；联机 V2.5、独立服务器 V3.0。旧 2D 文档与其通过状态不适用本版本。
5. 可并行子智能体；资料能推定的事不问用户；影响布局/玩法范围的决定先给方案再实施。

## 当前基线（全部通过回归，可直接在其上继续）

- **ART-01 玩家农场近景**：庭院草花/花境/灌木/道具（柴堆、干草捆、邮箱、灯柱…）、苗床低木框（相邻格耕开自动隐藏）、作物随机错位高矮、大田犁沟条纹着色器。证据 `work/art01/final-garden.png`、`final-homestead.png`。
- **MAP-01 逐区地形**：西北雪山主脉 + 溪源五级瀑布；果园 13 米行栽苹果树（分块加载）；湖畔码头+划艇（第 7 个 dock）；港口吊车/系缆桩/货堆；镇广场家具与市集棚；NPC 农庄畜栏与庭院。证据 `work/art01/map01-*.png` 六张。
- **WORLD-01 森林与持久化**：分块森林稳定 ID 可砍伐（破坏后重建区块、统一掉落通道）；存档新增 `surface`/`forest`/`mine` 三键；读档回矿层；环境树避让已存耕地。两阶段重启测试 `tests/world_persist_checks.gd`（write/verify 两个独立进程）。
- **PERF-01 第一轮**：启动 56.4→23.0s；农场 draws 4607→2529；五区域 60fps（M5/1600×1000，p50/p90 在 16.7ms 预算内）；常驻采样工具 `tests/perf_checks.gd`。
- **画风第二轮**：草地饱和色板+修剪条纹、水更深蓝、波纹细化、干土调暖、HUD 日期栏四段药丸、选中槽金光；并修复 PERF 引入的两处回归（木框方向、作物烘焙偏移散落）。证据 `work/art01/style3-farm.png`、`fix3-garden.png`、`fix3-homestead.png`、`style2-dock2.png`。
- 最新回归：`work/art01/style-{smoke,first,core}.log` 全 PASS（smoke 310 项、地图专项 146 项含 4 条主干路线、领域 49 项），0 脚本错误。

## 下一批任务（按顺序执行）

| 顺序 / ID | 状态 | 具体工作 | 验收标准 |
|---|---|---|---|
| 1 · ART-02 | **下一项** | 画风差距收尾（对照 style-board / ui-hud）：①初始牧场与畜栏放进牛/鸡（`main.gd` 初始动物 + `animal.gd`，参考图牲畜可见）；②角色头身比更 Q 版（`art/farmer_model.gd`）；③工具栏图标换手绘风贴图（可从 `docs/art/reference/ui-hud.png` 裁切图标与九宫格，Pillow Python 路径见文末）；④近景补 1–2 株开花果树点缀。 | 固定 `--hour=11` 实机截图与参考逐项对照；smoke / 地图专项回归通过；画风由用户实机验收。 |
| 2 · PERF-02 | TODO | 冷启动世界视觉+数据缓存：`world_builder.build()` 的场景与 data 字典按脚本指纹缓存到 `user://cache/`（改任何 builder/定义脚本自动失效），目标二次启动 <5s；跨区传送的区块重建尖峰（~1s）分帧摊平。 | 二次启动 <5s；五区域帧时间分位不劣于 `work/art01/perf01-run3.log`；指纹失效机制有测试。 |
| 3 · PLAY-01 | TODO | 实测公里级步行/快跑、一天时长、商店/矿口往返耗时；提出交通（马车站/传送点）与时间节奏方案，**经用户确认后**实施；补沿途交互与导览。 | 记录实测耗时与一天可完成的活动清单；交通方案先给用户确认再动工。 |
| 4 · FARM-01 | TODO | 按 V2 PRD M2/M3：季节种植与轮作、体力、工具升级、动物饲养/购买/产出；明确大片田地的经营规则。 | 数据驱动；跨天/换季/存读档/经济闭环测试；NPC 土地保护持续有效。 |
| 5 · LIFE-01 | TODO | 按 V2 M4–M6 逐个打通闭环：钓鱼、采集、NPC 日程/对话/好感/任务、室内、制作加工与仓库。 | 每项具备数据、交互、失败处理、存档与玩法验证；建筑外观 ≠ 服务完成。 |
| 6 · POLISH-01 | TODO | 天气/季节视觉与实际影响、音效、设置/输入、构建产物、长时间回归。 | 场景/存档回归、目标设备性能与真人体验证据齐全后判定首图完成度。 |

## 长期 / 备忘

- **NET-01（V2.5 BACKLOG）**：联机与专用服务器；依赖单机世界状态、存档、首图玩法稳定；届时另行设计网络契约与真实多机验收。
- MAP-01 遗留：homes 住宅区（西区 5 栋）庭院未装饰；瀑布山地可穿行（沿既有矿山行为，如需阻挡须专门设计）。
- 已记录的设计决定：矿场怪物重启后重现（宝箱旗标防重复领取）；半砍森林树血量不持久；森林存档为差异存储（只存移除列表）。
- 视觉风险备忘：`tile.gd::_bake_model` 依赖"烘焙后顶点平移回原点"——若复用该函数给带随机朝向的 MultiMesh，切勿去掉 `-BAKE_CENTER` 的顶点回移（曾造成作物散落十几米的回归）。

## 运行与验证命令

```sh
# 实机（默认大图，出生点即玩家农场）
tools/engine/Godot-4.7.2-stable/Godot.app/Contents/MacOS/Godot --path game

# 专项验证（存档一律用独立目录）
BREEZETOWN_SAVE_ROOT="$PWD/work/game-data/check" tools/engine/Godot-4.7.2-stable/Godot.app/Contents/MacOS/Godot --headless --path game --script res://scripts/tests/first_map_checks.gd
BREEZETOWN_SAVE_ROOT="$PWD/work/game-data/check" tools/engine/Godot-4.7.2-stable/Godot.app/Contents/MacOS/Godot --headless --path game --script res://scripts/tests/core_checks.gd
tools/engine/Godot-4.7.2-stable/Godot.app/Contents/MacOS/Godot --headless --path game --script res://scripts/tests/map_domain_checks.gd

# 完整冒烟（310 项）与持久化两阶段（write 后必须 verify，两个独立进程）
BREEZETOWN_SAVE_ROOT="$PWD/work/game-data/check" tools/engine/Godot-4.7.2-stable/Godot.app/Contents/MacOS/Godot --headless --path game -- --smoke
BREEZETOWN_SAVE_ROOT="$PWD/work/game-data/wp" tools/engine/Godot-4.7.2-stable/Godot.app/Contents/MacOS/Godot --headless --path game --script res://scripts/tests/world_persist_checks.gd -- --phase=write
BREEZETOWN_SAVE_ROOT="$PWD/work/game-data/wp" tools/engine/Godot-4.7.2-stable/Godot.app/Contents/MacOS/Godot --headless --path game --script res://scripts/tests/world_persist_checks.gd -- --phase=verify

# 性能采样（窗口模式才有真实渲染负载）
tools/engine/Godot-4.7.2-stable/Godot.app/Contents/MacOS/Godot --path game --windowed --resolution 1600x1000 --script res://scripts/tests/perf_checks.gd

# 固定视角截图
tools/engine/Godot-4.7.2-stable/Godot.app/Contents/MacOS/Godot --path game --windowed --resolution 1600x1000 -- --at=-672,252 --zoom=1.35 --hour=11 --shot="$PWD/work/art01/next.png"
```

注意：Godot 脚本报错后可能仍退出码 0，**必须 grep 日志**确认 `SCRIPT ERROR` 为 0 且 `*_RESULT PASS`。资源导入用 `--headless --editor --path game --quit`。带 Pillow 的 Python：`/Users/shenhongshi/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3`。

## 关键文件地图

| 关注点 | 文件 |
|---|---|
| 地图蓝图（唯一坐标源） | `game/resources/maps/first_map_blueprint.json` → 换算 `game/scripts/data/first_map_definition.gd` |
| 世界构建 | `game/scripts/world_builder.gd` → `first_map_builder.gd`；地形 `art/first_map_terrain.gd`；水系 `art/water_models.gd`（瀑布 `_cascade`） |
| 森林/果园分块 | `game/scripts/first_map_scenery.gd`（稳定 ID、可砍伐、差异持久化、耕地避让） |
| 耕地视图 | `game/scripts/tile.gd`（网格静态缓存 + MultiMesh；`_bake_model` 见风险备忘）；领域 `domain/farm_state.gd` |
| 地表资源/掉落 | `game/scripts/surface_resources.gd`、`surface_resource.gd`、`surface_drop.gd` |
| 存档 | `core/save_manager.gd`、`core/map_restore.gd`；载荷在 `main.gd::_save_payload()`（surface/forest/mine 三键在此）；读档 `_apply_load()` |
| 矿场 | `mine_layout.gd`（确定性布局）、`mine_floor.gd`（含 to_dict/apply_state）、`mine_rock/monster/drop.gd` |
| 交互 | `core/interaction_system.gd`（目标解析与执行统一入口，新交互类型在此注册） |
| 导航/规则 | `core/map_data.gd`（水域/障碍/占用）、`core/world_navigation.gd`（局部有界寻路） |
| HUD/UI | `game/scripts/hud.gd`（木框+羊皮纸；日期栏四段药丸在 `_build_info_chips`） |
| 测试 | `game/scripts/tests/`：`first_map_checks` / `core_checks` / `map_domain_checks` / `world_persist_checks` / `perf_checks` |
| 资产 | 模型 `game/resources/models/*.glb`；Blender 源 `art/3d/source/`；生成器 `tools/art/` |

## 证据索引（work/ 已清理，仅以下文件有效）

- 截图：`work/art01/`——`final-garden/final-homestead`（ART-01）、`map01-waterfall/orchard/harbor/town-square/npc-farm/lake-pier`（MAP-01）、`style3-farm + fix3-garden + fix3-homestead + style2-dock2`（画风）；`work/visual-slice/scaled-{farm,map}-final.png`（大图全景）。
- 日志：`work/art01/*.log`——最新 `style-*`，此前 `map01-*` / `world01-*` / `perf01-*`；更早基线 `work/first-map/validation/`（2026-09-16）。
- 对图：`docs/maps/first-map-trace.png`（描图叠加，仅对位用，不是实现画面）。

## 后续需要确认的事项（实施前先给方案）

公共土地永久经营范围、长途交通形式、NPC 农庄经营关系、最终门牌命名与室内布局。当前若干名称与服务建筑类别为实现暂定值，不作为用户最终命名。
