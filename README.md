# 微风小镇：3D 可玩原型

当前工程使用 Godot 4.7.2。默认世界已切换为按用户确认比例尺描绘的第一张地图：**约 2598 × 2374 米，西南为玩家农场，东北为 NPC 农庄**。地图依据 [first-map-scale.png](docs/art/reference/first-map-scale.png)，其中 400 米标尺长 202 像素，按 `1 px = 400 / 202 m` 换算整张 1312 × 1199 像素图片。约 6.17 平方公里是包含海域的矩形包围范围，不是可耕地面积。

建筑中心、道路、河湖、桥梁与海岸通过同一份 [地图蓝图](game/resources/maps/first_map_blueprint.json)定位。图中的建筑是示意符号，**只按图定位，模型使用合理的实际尺寸**，不把屋顶图标的像素宽度直接当成建筑宽度。图上东北的 “Your Farm” 标签不作为归属规则；玩家农场按用户确认放在西南。比例、描图方法、资产流程和限制详见 [第一张地图说明](docs/maps/first-map.md)。

默认入口仍为 `game/scenes/main.tscn`，`world_builder.gd` 默认转交 `first_map_builder.gd`。旧的约 192 × 160 米近景参考农场保留为 **`--reference-farm`**，用于画风对照与旧场景回归，不是默认地图。失效的 2D 需求包已移除，历史版本可从 Git 查询。

## 继续开发入口

- [当前任务板](docs/execution/task-board.md)：已确认决定、完成项、下一步优先级、验收标准和并行分工。
- [接续记录](docs/execution/SUMMARY.md)：最近改动、验证日志、运行截图与尚未解决的问题。

需求以用户最新确认 → V2 PRD → 地图/美术专项说明为准。下一项先推进玩家农场的参考画风与实机对照，其他待办见任务板。

## 当前实现与边界

- 第一张地图的数据登记包含 9 个区域、22 处建筑、21 条主路、4 段河流、3 片湖塘、4 座桥、9 块区域农田及港口码头。建筑入口支路和港务小屋平台由代码补充。
- 玩家农舍附近保留实际可操作的小块菜园、牧场及树木资源；既有开垦、播种、浇水、收获、买卖、跨天、养殖与存档代码接入新世界。图上的大片农田目前主要是地表表现，不等于每块都已建立完整种植状态。
- 星辉矿场保留十层探索、采矿、战斗、升降机和掉落物系统；入口按新蓝图位于西北。医院、学校、社区中心等多数建筑目前为外观地标，尚无完整室内或 NPC 服务。
- 农舍、商店、谷仓、鸡舍与成年树使用可编辑 Blender 源文件 / GLB 资产；部分乡镇建筑、地形和道具仍由代码生成。木纹、墙面、石材、屋瓦与地表纹理可由脚本重建，HUD 使用参考图派生的木框与纸面、实时文字和工具图标。
- 大图的近处森林按 64 米区块加载，水岸碰撞与寻路限定计算范围。这是控制大地图开销的实现措施，尚不能据此宣称性能、全图连通性或长时间运行已验收。

**仍需完成**：参考图整体视觉匹配、远景森林与地形细节、建筑比例和门前空间逐栋核查、大尺度地图的移动节奏、全图路线验收、NPC 日程与任务、完整季节天气玩法、音效和联机。当前画风仍在迭代，贴图与 GLB 接入不代表已达到参考图质量。

## 运行与操作

使用 Godot 编辑器打开 `game/project.godot`，先完成资源导入再运行。macOS 仓库内引擎示例：

```bash
# 默认：真实比例第一张地图
tools/engine/Godot-4.7.2-stable/Godot.app/Contents/MacOS/Godot --path game
# 旧近景参考农场
tools/engine/Godot-4.7.2-stable/Godot.app/Contents/MacOS/Godot --path game -- --reference-farm
```

Windows 可使用同目录内 `Godot_v4.7.2-stable_win64.exe`，无界面检查使用对应 `_console.exe`。操作：**WASD 移动、Shift 快跑、滚轮缩放、M 地图、1–9 工具、R 换种子、E 交互、Tab 背包、Q 食用口粮、F5 存档、F9 读档、Esc 关闭面板**。工具顺序为空手、锄头、水壶、种子、围栏、镐子、短剑、斧头、树苗。矿场可用 E、空格或鼠标左键采矿/攻击。

睡觉自动存档，F5 手动保存，`--load` 请求启动读档。默认大图存于 `user://saves/willow_creek_valley_v1/slot_1/`；旧参考农场保留 `user://saves/slot_1/`。不同地图的存档相互隔离，读取不兼容地图会被拒绝并保持当前状态。自动检查通过 `BREEZETOWN_SAVE_ROOT` 使用独立测试目录。

以下是可重复执行的检查入口，**列出命令不代表本次执行或通过**；新图运行证据由对应检查日志和实机截图记录：

```bash
# 第一张地图：标尺、归属、建筑尺度、入口、基础交互及加载范围
tools/engine/Godot-4.7.2-stable/Godot.app/Contents/MacOS/Godot --headless --path game --script res://scripts/tests/first_map_checks.gd
# 领域层：数据、农场、时钟、经济与存档
tools/engine/Godot-4.7.2-stable/Godot.app/Contents/MacOS/Godot --headless --path game --script res://scripts/tests/core_checks.gd
# 默认地图实机截图；路径使用绝对路径
tools/engine/Godot-4.7.2-stable/Godot.app/Contents/MacOS/Godot --path game -- --shot=/tmp/breezetown-first-map.png
# 默认地图总览
tools/engine/Godot-4.7.2-stable/Godot.app/Contents/MacOS/Godot --path game -- --view=overview --shot=/tmp/breezetown-first-map-overview.png
```

截图还支持 `--view=map`、`--at=x,z`、`--zoom=0.8/1.0/1.35/1.8/2.3`、`--hour=22`；`--mine=1` 至 `--mine=10` 可直接进入矿层。旧版 [山谷验收](docs/testing/3d-valley-map.md)、[矿场验收](docs/testing/3d-mine.md)描述的是当时版本，不自动构成本次大图的验收证据。

## 架构与美术资料

[V2 PRD](docs/product/01-product-prd-v2.md)是产品方案，[M0 审计](docs/execution/m0-audit.md)记录此前的基础重构。数据目录在 `game/scripts/data/`；农田、动物、玩家经营状态与 3D 节点分离；`core/` 提供时钟、事件、存档、地图规则、交互和寻路服务。

- [第一张地图](docs/maps/first-map.md)：比例换算、人工描图、默认入口、资产重建、限制与验收入口。
- [Art Bible](docs/art/art-bible.md)：目标画风、当前实现与差距。
- [素材来源与许可](docs/art/assets-license.md)：原创生成资产、用户提供参考图、派生 HUD 与地图资源、字体。
- `art/3d/source/`：当前 Blender 可编辑资产；`art/2_5d/`：保留的旧美术工坊。
