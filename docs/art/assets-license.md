# 素材来源与许可清单

更新：2026-09-16。以下区分原创生成资产、用户提供参考资料及其派生资源。文件存在或用户提供参考用途，不自动等于已有第三方商业分发许可；未附带许可文本的来源如实登记，不标注为 CC0 或项目原创。

## 当前 3D 资产

| 素材 | 来源 / 权利记录 | 位置与重建方式 |
|---|---|---|
| 第一张地图的原图 | 用户提供，带 400 米标尺的 `first-map-scale.png`；未随当前文件附带作者信息或许可文本 | `docs/art/reference/first-map-scale.png`；1312 × 1199 像素 |
| 地图蓝图、检查叠加图、森林掩码 | 根据上述用户参考图人工描点或图像处理所得的派生资料；像素数据与描图结果不能笼统登记为与来源无关的原创图像 | `game/resources/maps/first_map_blueprint.json`、`forest_mask.png`、`docs/maps/first-map-trace.png`；`tools/art/build_map_trace.py` |
| 画风、湖畔、HUD、羊皮纸地图、早期山谷全景参考 | 用户提供；当前文件未附第三方许可文本。作为风格 / 地理参考保存，其中 HUD 图也参与实际资产裁切 | `docs/art/reference/{style-board,lake-dock,ui-hud,valley-map,world-map-landscape}.png` |
| HUD 木框、纸面、头像、金币与部分工具图标 | 由 `ui-hud.png` 裁切、清理或抠图，属于参考图派生资产；没有把来源图片声明为项目原创 | `game/resources/ui/`；`tools/art/build_reference_ui.py` |
| 补充工具图标 | 生成脚本中另行绘制的短剑、空手、镐子、树苗、围栏、口粮图标；与参考图裁切项目在脚本中分开 | 同上 |
| 农舍、商店、谷仓、鸡舍 GLB 与 Blender 副本 | 项目内建筑生成代码产生几何，导出 GLB，再转存 `.blend`；未引入外购建筑模型 | `game/resources/models/{cottage,seed_shop,barn,coop}.glb`、`art/3d/source/`；`export_architecture.gd`、`blender/prepare_architecture.py` |
| 成年树木 GLB 与 Blender 源文件 | 项目内 Blender Python 生成枝干、叶簇、材质与变体；未引入第三方树木模型 | `foliage_{pine,oak,apple}_{0,1}.glb` 与对应 `.blend`；`tools/art/blender/build_foliage.py` |
| 建筑木纹、灰泥、石材、屋瓦贴图 | 固定随机种子的项目原创程序纹理；颜色与法线由算法生成，不使用外部照片 | `game/resources/architecture/`；`tools/art/build_architecture_materials.py`，需要 Pillow / NumPy |
| 草地、泥土、石材地表纹理 | 固定随机种子的项目原创程序纹理 | `game/resources/materials/terrain/`；`tools/art/build_surface_textures.py` |
| 乡镇建筑、地形、岩石、道具、角色、矿场、装备与怪物程序模型 | 项目代码生成几何；玩法或风格参考不表示导入其他游戏资产 | `game/scripts/art/`、`game/scripts/mine_monster.gd` 等 |
| Breeze Town UI 中文字体 | Google Fonts 的 Noto Sans SC，SIL OFL 1.1；固定 400 字重并取子集，改名 Breeze Town UI，保留完整许可 | `game/resources/fonts/`；来源、校验值与重建命令见该目录 README |

当前可以追溯生成链路；用户参考图及派生 HUD / 地图资源的作者、原始出处和分发许可在现有文件中未登记，本清单不推定其许可。

地图比例和内容范围见 [第一张地图说明](../maps/first-map.md)，模型与纹理目标见 [Art Bible](art-bible.md)。生成工具需要的 Godot、Blender、Pillow 与 NumPy 是开发依赖；它们的工具许可不代替输入参考图的权利记录。

## 可复现性与当前限制

- GLB、`.blend` 与 PNG 的命令链路集中记录在 [资产流程](../maps/first-map.md#可复现资产流程)。建筑 Blender 文件当前由生成 GLB 转存，尚无 GDScript 与 Blender 双向同步；不能混淆生成来源和编辑副本。
- 纹理与植被脚本使用固定随机种子以便重建；未在此登记跨 Blender / Godot 版本的二进制完全一致性。
- 原始参考图、描图叠加图与资产预览各有用途，不能作为实际游戏画风已通过验收的证明。
- 音效、正式应用图标及其他尚未引入的资源仍需在加入时登记。下方 2D 记录只对应历史版本，其中“无外部字体”“全部素材原创”等表述不适用于当前 3D 素材清单。

## 2D 阶段归档（2026-09-09）

## 1. 原创程序化素材

| 项 | 内容 |
|---|---|
| 来源 | 本项目原创，由 `tools/art/generate_assets.py` 程序化生成 |
| 许可 | 项目自有版权；无第三方素材、无外部字体、无外部音效 |
| 生成方式 | 标准库 PNG 编码（无第三方依赖），色板取自 `docs/ui/art-direction.md` |
| 数量 | 39 个 PNG（地块 7、角色 4、作物阶段 17、工具/图标 8、建筑 3） |
| 位置 | `game/assets/generated/` |
| 可复现 | `python3 tools/art/generate_assets.py`（幂等，输出稳定） |

## 2. 素材清单

| 类别 | 文件 |
|---|---|
| 地块 | `tile_grass`、`tile_soil`、`tile_soil_tilled`、`tile_soil_wet`、`tile_path`、`tile_blocked`、`tile_facility`、`tile_spawn` |
| 角色 | `avatar_1..4`（四种配色 + 不同帽子剪影，色盲可辨） |
| 作物 | `crop_{radish,potato,wheat,carrot,strawberry}_{sown,seedling,growing,mature}`（按 PRD 6.1 阶段映射） |
| 工具 | `tool_hoe`、`tool_watering_can`、`tool_hand` |
| 图标 | `icon_seed`、`icon_coin`、`icon_storage`、`icon_project`、`icon_leaderboard` |
| 建筑 | `building_shop`、`building_storage`、`building_monument` |

## 3. 第三方依赖

| 项 | 版本 | 许可 | 用途 |
|---|---|---|---|
| Godot Engine | 4.7.2-stable | MIT | 引擎（见 `docs/build/engine-lock.json`） |
| 字体 | 未引入外部字体 | — | 使用 Godot 内置回退字体；如需像素字体，购买/授权后须更新本清单 |
| 音效 | **未引入** | — | V1 音效缺口：需用户授权预算后采购或自行录制（见第 4 节） |

## 4. 未完成项

- **音效**：尚未引入任何音频素材。`docs/ui/art-direction.md` 第 6 节要求原创或 CC0 音效；采购/录制需用户授权预算。当前游戏在无音频设备下正常工作（dedicated 不加载音频）。
- **像素字体**：当前用内置字体回退，未购买商业像素字体。若最终视觉要求点阵字体，需登记许可后再引入。
- **正式图标/启动图**：当前使用生成的建筑图作占位，最终应用图标需 ART-01 后续补。

## 5. 合规声明

- 未使用任何既有商业作品的素材、贴图、音乐或字体。
- 未使用占位方块截图冒充最终视觉（PRD 第 14 章红线）；本轮素材是原创像素图，但**仍非最终美术定稿**，M6 前可继续迭代。
- 所有素材均可用 `tools/art/generate_assets.py` 重新生成，来源可追溯。
