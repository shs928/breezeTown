# 微风小镇：3D 可玩原型

当前工程使用 Godot 4.7.2。默认世界已切换为按用户确认比例尺描绘的第一张地图：**约 2598 × 2374 米，西南为玩家农场，东北为 NPC 农庄**。地图依据 [first-map-scale.png](docs/art/reference/first-map-scale.png)，其中 400 米标尺长 202 像素，按 `1 px = 400 / 202 m` 换算整张 1312 × 1199 像素图片。约 6.17 平方公里是包含海域的矩形包围范围，不是可耕地面积。

建筑中心、道路、河湖、桥梁与海岸通过同一份 [地图蓝图](game/resources/maps/first_map_blueprint.json)定位。图中的建筑是示意符号，**只按图定位，模型使用合理的实际尺寸**，不把屋顶图标的像素宽度直接当成建筑宽度。图上东北的 “Your Farm” 标签不作为归属规则；玩家农场按用户确认放在西南。比例、描图方法、资产流程和限制详见 [第一张地图说明](docs/maps/first-map.md)。

默认入口仍为 `game/scenes/main.tscn`，`world_builder.gd` 默认转交 `first_map_builder.gd`。旧的约 192 × 160 米近景参考农场保留为 **`--reference-farm`**，用于画风对照与旧场景回归，不是默认地图。失效的 2D 需求包已移除，历史版本可从 Git 查询。

## 继续开发入口

- [当前任务板](docs/execution/task-board.md)：已确认决定、完成项、下一步优先级、验收标准和并行分工。
- [接续记录](docs/execution/SUMMARY.md)：最近改动、验证日志、运行截图与尚未解决的问题。

需求以用户最新确认 → V2 PRD → 地图/美术专项说明为准。当前已完成农牧经营两轮、淡水钓鱼两轮、野外采集、NPC 第一轮（日程/对话/送礼）与 NPC 委托任务，下一步推进室内与制作加工；画风终验与交通方案仍待确认，具体待办见任务板。

## 当前实现与边界

- 第一张地图的数据登记包含 9 个区域、22 处建筑、21 条主路、4 段河流、3 片湖塘、4 座桥、9 块区域农田及港口码头。建筑入口支路和港务小屋平台由代码补充。
- 玩家农舍附近保留实际可操作的小块菜园、牧场及树木资源；既有开垦、播种、浇水、收获、买卖、跨天、养殖与存档代码接入新世界。图上的大片农田目前主要是地表表现，不等于每块都已建立完整种植状态。
- 星辉矿场保留十层探索、采矿、战斗、升降机和掉落物系统；入口按新蓝图位于西北。医院、学校、社区中心等多数建筑目前为外观地标，尚无完整室内或 NPC 服务。
- 淡水钓鱼支持六种鱼，按湖河、季节、天气与时段筛选鱼池，含跨午夜条件、稀有度和三种角力行为。鱼获有普通/银/金品质，独立钓鱼等级为 1–10；背包“鱼类”页显示当前可钓状态、条件、品质数量与价格，商店估价和出售共用同一计价入口，品质及成长可存读档。海钓与完整 M4 仍未完成。
- 野外采集支持 14 种植物与海贝，按森林/果园/山地/湖畔/海岸/镇区六类栖息地与季节刷新，每天补充一小批、换季清理不合季物种；徒手 E 采集（+5 通用经验），入包后进背包“采集”区，可随收获一并估价出售，采集物位置与库存可存读档。采集物不进入图鉴页，稀有度仅在提示中标注；专属采集等级与制作配方联动未实现。
- NPC 第一轮：四位村民（皮埃尔/玛尔妮/巴特/老王）带 Q 版造型与色板换装，按日程（时段→锚点+门侧偏移+踱步）在商店、北岭农庄、铁匠铺、酒馆、湖畔之间移动；E 交谈有初见问候与按好感三档（<300/700/1000）闲聊，每日首聊 +8 好感；对话面板可送礼，每天限一份，喜好四档（钟爱+60/喜欢+30/普通+15/讨厌−30）扣一件背包实物并回反应台词；好感 0–1000（十心）与对话/送礼日戳可存读档。NPC 任务、特殊事件与礼物信件未实现。
- NPC 委托任务：八项数据驱动委托（每人一条两段链），分“收集交付”（凑齐 N 件指定物品回交付人领取金币+好感）与“传话”（与目标 NPC 交谈自动完成）两类，链式前置依次解锁；对话面板出现“接受委托/交付”按钮，右上角追踪药丸常显进行中委托与进度，凑满时 toast 提示可交付，交付扣实物、发奖励并展示答谢台词；任务状态（接受/完成日戳）可存读档。每日重复委托、特殊事件与任务物品奖励未实现。
- 天气按七日“晴、多云、雨、晴、晴、暴风雨、多云”循环，冬季雨和暴风雨转为雪；自然跨天与睡觉均更新，读档保留已存天气。天气已影响鱼池，雨雪视觉和降雨自动浇地等通用农场天气效果仍待实现。
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

Windows 可使用同目录内 `Godot_v4.7.2-stable_win64.exe`，无界面检查使用对应 `_console.exe`。操作：**WASD 移动、Shift 快跑、滚轮缩放、M 地图、1–9 工具、0 鱼竿、R 换种子、E 交互、Tab 背包、Q 食用口粮、F5 存档、F9 读档、Esc 关闭面板/取消钓鱼**。工具顺序为空手、锄头、水壶、种子、围栏、镐子、短剑、斧头、树苗。矿场可用 E、空格或鼠标左键采矿/攻击。钓鱼时面向湖泊或河流水面，E/空格/左键抛竿，咬钩后再按一次提竿；按住收线、松开降张力，收线进度满后获得鱼，持续过紧或过松会失败。

睡觉自动存档，F5 手动保存，`--load` 请求启动读档。默认大图存于 `user://saves/willow_creek_valley_v1/slot_1/`；旧参考农场保留 `user://saves/slot_1/`。不同地图的存档相互隔离，读取不兼容地图会被拒绝并保持当前状态。自动检查通过 `BREEZETOWN_SAVE_ROOT` 使用独立测试目录。

以下是可重复执行的检查入口，**列出命令不代表本次执行或通过**；新图运行证据由对应检查日志和实机截图记录：

```bash
# 第一张地图：标尺、归属、建筑尺度、入口、基础交互及加载范围
tools/engine/Godot-4.7.2-stable/Godot.app/Contents/MacOS/Godot --headless --path game --script res://scripts/tests/first_map_checks.gd
# 领域层：数据、农场、时钟、经济与存档
tools/engine/Godot-4.7.2-stable/Godot.app/Contents/MacOS/Godot --headless --path game --script res://scripts/tests/core_checks.gd
# 钓鱼品质、估价/出售、独立成长与存档兼容（自动隔离测试存档）
tools/engine/Godot-4.7.2-stable/Godot.app/Contents/MacOS/Godot --headless --path game --script res://scripts/tests/fishing_economy_checks.gd
# 野外采集：物种条件、生成刷新、采集流程与存档
tools/engine/Godot-4.7.2-stable/Godot.app/Contents/MacOS/Godot --headless --path game --script res://scripts/tests/forage_domain_checks.gd
tools/engine/Godot-4.7.2-stable/Godot.app/Contents/MacOS/Godot --headless --path game --script res://scripts/tests/forage_checks.gd
# NPC：人设/日程/好感/送礼与存档（自动隔离测试存档）
tools/engine/Godot-4.7.2-stable/Godot.app/Contents/MacOS/Godot --headless --path game --script res://scripts/tests/npc_domain_checks.gd
tools/engine/Godot-4.7.2-stable/Godot.app/Contents/MacOS/Godot --headless --path game --script res://scripts/tests/npc_checks.gd
# NPC 委托：数据链、接受/进度/交付/传话与存档
tools/engine/Godot-4.7.2-stable/Godot.app/Contents/MacOS/Godot --headless --path game --script res://scripts/tests/quest_domain_checks.gd
tools/engine/Godot-4.7.2-stable/Godot.app/Contents/MacOS/Godot --headless --path game --script res://scripts/tests/quest_checks.gd
# 天气循环、冬季转换、跨天/睡觉及存档天气
tools/engine/Godot-4.7.2-stable/Godot.app/Contents/MacOS/Godot --headless --path game --script res://scripts/tests/weather_checks.gd
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
