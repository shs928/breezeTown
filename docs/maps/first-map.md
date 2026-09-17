# 第一张地图：真实比例与实现记录

更新：2026-09-16。本文记录地图定义与实现边界。最新验证见 [接续记录](../execution/SUMMARY.md)，下一步见 [任务板](../execution/task-board.md)；整体画风仍待参考图验收。

## 基准、比例与坐标

当前地理基准为用户提供的 [first-map-scale.png](../art/reference/first-map-scale.png)，图像为 **1312 × 1199 像素**。用户确认以右下角整段 **400 米 / 202 像素**标尺换算真实距离；端点记录为 `(1068, 1166)` 与 `(1270, 1166)`。

| 项目 | 当前值 |
|---|---|
| 每像素距离 | `400 / 202 = 1.9801980198 m/px` |
| 东西宽度 | `1312 × 400 / 202 = 2598.019802 m` |
| 南北长度 | `1199 × 400 / 202 = 2374.257426 m` |
| 矩形范围面积 | 约 `6.1684 km²`，包含南部海域，不是陆地或耕地净面积 |
| 像素原点 | 图心 `(656, 599.5)` |
| 世界坐标 | `X = (px - 656) × 400 / 202`；`Z = (py - 599.5) × 400 / 202` |
| 方向 | 图上北为世界 `-Z`，东为 `+X`；`Y` 单独用于高度 |
| 地图 ID | `willow_creek_valley_v1`，当前定义版本 `1` |

这是对示意地图采用统一比例的游戏世界约定，不是地理测绘成果。没有根据透视插画反推真实海拔，也没有从图片获取精确地籍边界。

**归属按用户确认：西南为玩家农场，东北为 NPC 农庄。** 东北土地已禁止玩家开垦、种树和围建，仍可步行进入。 原图东北的 “Your Farm” 标签仅是图片内容，不覆盖这一归属。玩家出生点由西南农舍的实际门前位置计算。旧 [world-map-landscape.png](../art/reference/world-map-landscape.png)保留为早期构图参考；[valley-map.png](../art/reference/valley-map.png)用于羊皮纸导览图风格，不再决定默认地图的地理位置。

## 数据来源与默认入口

[蓝图 JSON](../../game/resources/maps/first_map_blueprint.json)保留图片像素坐标，是当前描图的来源数据。[first_map_definition.gd](../../game/scripts/data/first_map_definition.gd)集中执行米制换算，生成建筑、道路、水域、桥梁、码头、区域、地标和保留范围。

默认构建链为：

```text
game/scenes/main.tscn
  → world_builder.gd
  → first_map_builder.gd
  → first_map_definition.gd + first_map_blueprint.json
```

`--reference-farm` 让 `world_builder.gd` 使用旧的近景参考农场；默认不加该参数。两者共用玩法和部分资产，但具有不同布局与地图 ID。不能把旧图坐标直接当成新图有效坐标，也不能把旧图的运行记录当成新图通过验收。

目前 JSON 登记 9 个区域、22 处建筑、21 条道路、4 段河道、3 片湖塘、4 座桥、9 块区域农田和 4 个码头矩形。构建阶段另外增加每栋建筑的入口支路、港务小屋平台及连接步道；南部海域由海岸线与图片南边界闭合。

| 分区 | 代码中的范围与角色 |
|---|---|
| 西南玩家农场 | 玩家农舍、谷仓、鸡舍、初始菜园、牧场和邻近资源 |
| 东北 NPC 农庄 | 农庄、谷仓和鸡舍的地理登记与外观；NPC 经营逻辑尚未实现 |
| 中部镇区 | 商店、酒馆、医院、广场、图书馆、学校及其他服务建筑 |
| 西侧住宅区 | 五处住宅和连接道路 |
| 西北山地 | 矿场入口与岩岭；接入既有十层矿场 |
| 北部森林、东侧果园 | 区域登记、植被覆盖来源；果园内容尚未完整实现 |
| 东南湖区 | 月湾湖及外排溪流；尚无完整钓鱼玩法 |
| 南部港口 | 码头、港务小屋、灯塔、船只与海岸表现；尚无航行或港口经营 |

## 建筑按图定位，尺寸使用米制模型

图片建筑具有插画式放大和透视。JSON 的 `at` 决定建筑中心；示意图 `size` 字段不直接作为运行时占地。当前定义使用模型类别的基础尺寸、`factor` 与碰撞余量计算物理占地；表现层对高度增幅另有限制，避免大型地图符号被整体放成巨型建筑。

例如，当前逻辑占地约为：玩家农舍 **10.65 × 9.61 米**、玩家谷仓 **14.77 × 11.69 米**、玩家鸡舍 **4.67 × 3.99 米**、杂货店 **11.25 × 9.25 米**、社区中心 **27.25 × 18.25 米**、学校 **26.65 × 19.39 米**。这些数值来自定义中的碰撞占地公式，不是对屋檐、台阶等渲染包围盒的精测。

门前交互点依模型类别计算，支路连接最近的主路。实际门宽、台阶、碰撞与模型包围盒仍需逐栋核对；仅有中心坐标对齐不能证明建筑已经完成。

## 人工描图与误差

道路采用手工选择的折线，河道采用中心线加宽，湖泊与海岸采用多边形，桥梁/码头采用矩形。区域边界使用便于规则管理的矩形，不能理解为图片中每一段围栏的精确轮廓。

[描图检查图](first-map-trace.png)在原图上叠加黄线道路、青线水系、浅色海岸、红点建筑中心、粉色桥梁范围。它由 `tools/art/build_map_trace.py` 从蓝图生成，用于检查位置偏差，**不是游戏运行截图**。

当前未执行全图逐点误差测量，也未计算均方根误差。按已确认比例，1 像素约为 1.98 米，5 像素约为 9.90 米，10 像素约为 19.80 米；这些只是换算示例，不是已测得的精度。河道转弯、岸边植被遮挡、港口边界和建筑视觉中心都存在人工判断误差。

地形当前按 8 米间距建网格，并在已登记水域下压河床；大部分陆地仍为平面，西北另加岩岭。林地掩码由参考图的颜色阈值、模糊和区域排除生成，可能把阴影、文字和非树绿色区域误判成森林。蓝图折线、低分辨率掩码与运行时散布共同决定外观，尚不能声称逐像素复刻。

## 已接入的运行机制与限制

- 地图规则、建筑碰撞、道路禁耕、水域禁行和禁耕、桥/码头通行共同读取地图定义。跨桥高度由共享地表高度逻辑处理。
- 实际种植状态集中在玩家农舍附近的小菜园。区域农田当前有地表表现，尚未为整张地图所有田块建立成熟经营内容。
- 近处森林以 64 米区块、玩家周围 3 × 3 区块生成，共享 GLB 网格，通过 MultiMesh 渲染并登记树干碰撞。它是环境植被；不能视作所有树木都已实现砍伐、掉落与持久化。农舍邻近可交互树木使用既有资源系统。
- 大图水岸物理碰撞按玩家附近范围更新；地图规则仍可查询完整水域。寻路根据请求范围构建有界网格，远距离精度与全图路线仍需验收。
- 导览图使用运行时同一份建筑、道路与水域数据。较小的真实建筑在全图上可能只占数个屏幕像素，标注密度与地点检索仍可改善。
- 既有农牧、经济、背包、口粮、跨天与矿场流程继续接入；第一张地图的全链路完成度应以新图运行检查为准。

按当前玩家步行 3.6 m/s、快跑 6.4 m/s 计算，横穿 2.6 km 包围范围的直线理论耗时约为 12 分钟或 6.8 分钟；这不包含绕路、碰撞和游戏操作，也不是实测游玩时长。长距离交通、道路节奏、沿途内容和日长尚需共同平衡。

## 存档隔离

默认大图使用 `user://saves/willow_creek_valley_v1/slot_1/`；旧近景保留 `user://saves/slot_1/`。不同地图存档不混用，不兼容读取会被拒绝；完整地表资源和矿层持久化仍见 WORLD-01 待办。

## 可复现资产流程

在仓库根目录执行下述命令。Python 需要 Pillow，建筑贴图另需 NumPy；Blender 植被脚本以 4.5 为基线，示例假设 `blender` 可从 PATH 调用。下述命令登记生成链路，不表示本次文档任务已重新执行资产生成。

### 1. 生成贴图、HUD 与描图检查图

```bash
python3 tools/art/build_architecture_materials.py
python3 tools/art/build_surface_textures.py
python3 tools/art/build_reference_ui.py
python3 tools/art/build_map_trace.py
```

输出包括：

- `game/resources/architecture/`：木纹、灰泥、石材、屋瓦的颜色及浅法线贴图；当前为固定种子的原创程序纹理，没有采样外部照片。
- `game/resources/materials/terrain/`：草地、泥土与石材纹理。
- `game/resources/ui/`：用户参考图派生的木框、纸面、头像与部分工具图标，以及补充绘制的工具图标。演示文字已移除，游戏中的金币、日期、生命、库存与快捷键由实时数据绘制。
- `game/resources/maps/forest_mask.png`：从地图参考图提取的环境植被掩码；`docs/maps/first-map-trace.png`：人工描图叠加图。

### 2. 生成建筑 GLB 与 Blender 可编辑副本

```bash
# 先导入上述贴图
tools/engine/Godot-4.7.2-stable/Godot.app/Contents/MacOS/Godot --headless --path game --editor --quit
# 从当前建筑脚本生成合批的运行时 GLB
tools/engine/Godot-4.7.2-stable/Godot.app/Contents/MacOS/Godot --headless --path game --script ../tools/art/export_architecture.gd
# 将 GLB 导入 Blender，保存可编辑源文件
blender --background --threads 4 --python tools/art/blender/prepare_architecture.py
```

当前建筑生成源是 `building_models.gd`、`ranch_models.gd`；输出为 `game/resources/models/{cottage,seed_shop,barn,coop}.glb`。`prepare_architecture.py` 将这些 GLB 转存为 `art/3d/source/*.blend`，**它本身不重新建模，也不把 Blender 修改反向同步到 GDScript**。

若在 Blender 中修改 `.blend`，应明确选择相应对象并重新导出到对应 GLB，保留米制尺度、材质和轴向；再次运行 GDScript 导出或转存脚本会覆盖对应生成文件。当前没有双向同步工具。运行时 `authored_assets.gd` 负责实例化建筑 GLB，并恢复需要的顶点色材质标志。

### 3. 生成树木并完成 Godot 导入

```bash
blender --background --threads 4 --python tools/art/blender/build_foliage.py
tools/engine/Godot-4.7.2-stable/Godot.app/Contents/MacOS/Godot --headless --path game --editor --quit
```

植被脚本生成 pine / oak / apple 各两种变体，同时输出 `art/3d/source/foliage_*.blend` 和 `game/resources/models/foliage_*.glb`。脚本使用固定随机种子与材质，并显式处理 Godot / Blender 轴向转换。成年树优先加载 GLB，幼苗等阶段仍有程序网格实现。可编辑 `.blend`、生成 GLB、贴图和实际导入结果需要一并复查；拥有源文件不代表模型密度、LOD 或视觉质量已经验收。

## 验证入口与尚未完成的内容

`game/scripts/tests/first_map_checks.gd` 提供标尺、世界范围、农场归属、建筑物理尺度、桥港登记、默认启动、入口可用、商店交互和局部加载范围等检查入口：

```bash
tools/engine/Godot-4.7.2-stable/Godot.app/Contents/MacOS/Godot --headless --path game --script res://scripts/tests/first_map_checks.gd
```

以上检查应连同真实主场景截图、实际移动和交互体验一起记录。本文件不登记未经主线程提供的 PASS、FPS、全图可达或稳定性结论。截图命令见 [README](../../README.md)。

尚未完成或仍需验收：

1. 全图人工描图误差复核、建筑模型/碰撞/门前区域逐栋检查、桥头与岸线的全路线测试。
2. 原图一致的地形起伏、森林密度、远景 LOD、河岸浅滩、港口细节、材质笔触及整体画风。
3. 新图的长距离交通、任务密度、日长与经营节奏；区域农田、NPC 农庄与果园的完整玩法。
4. NPC、学校/医院/社区等服务、建筑室内、任务、钓鱼、航行及海港经营；地图上的位置与外观不等于服务已经实现。
5. 地表全域资源持久化、跨地图旧存档处理的完整验收、平台性能与长时间运行。
6. V2 尚未交付的完整季节天气玩法、音效、联机及其他里程碑。
