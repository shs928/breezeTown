# 素材许可清单（ART-01）

日期：2026-09-09；维护：UI/LEAD。**本清单是 CASE-44 素材许可归档的证据。**

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
