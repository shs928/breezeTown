# 微风小镇 · 2.5D 美术样稿

2026-09-14：第一版 **立体角色＋立体场景、温暖手绘感** 美术样稿。六张图片均由本目录中的真实三维模型渲染；模型、材质和建模脚本一并交付。当前采用暖色块、顶点色、曲面瓦片、倒角和柔和光照建立风格。

这是当前唯一的 Godot 2.5D 风格工坊。场景是用于确认角色、建筑、作物和环境比例的农场微缩景观，布局经过压缩，不是完整游戏地图；当前交付重点是立体模型、材质、动画样稿和可旋转预览。

## 看图片

六张主图均为 **1920×1200 PNG**。

| 图片 | 内容 |
|---|---|
| [01 · 春日农场](renders/01-farm-day.png) | 农舍、商店、四种菜畦、树木、池塘、木桥和角色 |
| [02 · 农舍近景](renders/02-cottage.png) | 陶瓦、百叶窗、花箱、石基、门廊和农夫 |
| [03 · 农夫转面](renders/03-farmer-turnaround.png) | 同一角色的正面、侧面、背面与斜侧面 |
| [04 · 灯火夜景](renders/04-farm-dusk.png) | 同一三维场景的夜间灯光方案 |
| [05 · 种子商店](renders/05-seed-market.png) | 青绿瓦顶、条纹遮阳棚、种子柜台与陈设 |
| [06 · 两位农夫](renders/06-farmer-pair.png) | 蓝衣短发、绿衣短辫两种造型 |

## 用模型

`models/` 内有 **18 个 GLB**，采用 glTF 2.0，单位为米，Y 向上、正面朝 +Z。可以导入 Godot 或支持 glTF 的建模软件；本次重新导入验证使用 Godot 4.7.2。

| 类别 | 文件 |
|---|---|
| 角色 | [farmer_indigo.glb](models/farmer_indigo.glb)、[farmer_moss.glb](models/farmer_moss.glb) |
| 建筑 | [willow_cottage.glb](models/willow_cottage.glb)、[seed_market.glb](models/seed_market.glb) |
| 树木 | [meadow_oak.glb](models/meadow_oak.glb)、[apple_tree.glb](models/apple_tree.glb) |
| 菜畦 | [plot_radish.glb](models/plot_radish.glb)、[plot_strawberry.glb](models/plot_strawberry.glb)、[plot_wheat.glb](models/plot_wheat.glb)、[plot_pumpkin.glb](models/plot_pumpkin.glb) |
| 环境与农具 | [garden_fence.glb](models/garden_fence.glb)、[garden_well.glb](models/garden_well.glb)、[footbridge.glb](models/footbridge.glb)、[watering_can.glb](models/watering_can.glb)、[harvest_crate.glb](models/harvest_crate.glb)、[wooden_barrel.glb](models/wooden_barrel.glb)、[duck_pond.glb](models/duck_pond.glb) |
| 整个场景 | [breeze_town_farm.glb](models/breeze_town_farm.glb) |

角色身高约 1.724 米，脚底为原点，含 `idle`、`walk` 两个循环动画。当前动画驱动分件关节，**还不是正式蒙皮骨骼角色**。在 Godot 导入角色后，可用其中的 `AnimationPlayer` 播放动作。

GLB 保留几何、颜色材质与角色动画；日夜光照、展示相机和预览界面由 Godot 项目提供。因此在其他软件的默认灯光下，明暗会有所不同。

## 打开可旋转预览

在 Godot 4.7.2 中导入本目录的 [project.godot](project.godot)，运行主场景即可。仓库内也可直接使用已经配置好的引擎：

```powershell
pwsh -NoProfile -File tools/art/preview-2_5d.ps1
```

- `1`～`6`：切换六个场景；`Tab`：下一个场景。
- 鼠标左键拖动：旋转视角；滚轮：缩放。
- `空格`：切换角色行走、待机；`R`：自动环绕。
- `F`：保存当前画面到 `renders/my-*.png`。

预览与出图使用 Forward+ / Vulkan。本机已使用 RTX 2060 SUPER 完成实际渲染。

## 修改与重建

所有几何均由原创 GDScript 参数化建模，无外部模型、付费插件或第三方贴图依赖。源工程使用 Godot；可修改源脚本，或导入 GLB 后编辑网格。

| 源文件 | 修改内容 |
|---|---|
| [farmer_model.gd](scripts/farmer_model.gd) | 角色、发型、草帽、服装、关节与动作 |
| [building_models.gd](scripts/building_models.gd) | 农舍、商店、瓦片、门窗、石基 |
| [market_props.gd](buildings/market_props.gd) | 花箱、种子摊与柜台陈设 |
| [landscape_models.gd](scripts/landscape_models.gd) | 树木、菜畦、水塘、木桥、围栏与农具 |
| [scene_builder.gd](scripts/scene_builder.gd) | 场景布局、展示构图与六个视角 |
| [showcase.gd](scripts/showcase.gd) | 灯光、预览交互与独立高分辨率出图 |
| [model_pack.gd](scripts/model_pack.gd) | 静态网格合并、GLB 导出与重新导入检查 |
| [gltf_color_compat.gd](scripts/gltf_color_compat.gd) | 保持 GLB 动态加载时的顶点色 |

在仓库根目录执行：

```powershell
# 重建全部六张主图和十八个模型
pwsh -NoProfile -File tools/art/build-2_5d.ps1

# 只重出角色转面图；View 使用 0～5
pwsh -NoProfile -File tools/art/build-2_5d.ps1 -View 2 -RenderOnly

# 只导出模型
pwsh -NoProfile -File tools/art/build-2_5d.ps1 -ExportOnly
```

构建脚本保留独立日志，并检查进程结果、图片尺寸和模型导入结果。主图使用独立 1920×1200 渲染视口，不受桌面窗口大小影响。项目关闭运行时管线缓存写入，便于在受限工作目录中重建。

## 验证与接入顺序

本轮六张主图实际出图成功；[manifest.json](models/manifest.json) 记录 **18/18 模型导出、重新导入成功**，三角形数量一致，顶点与变换有限，彩色表面的顶点色已启用。两位农夫的动画随 GLB 保留。额外回归验证见 [validation](validation/)；几何细节检查见 [角色说明](character/README.md) 与 [建筑尺寸](buildings/model-dimensions.json)。

导出时对部分索引分组进行兼容性处理，保留 Godot 4.7.2 动态加载时的顶点色；几何数据与三角形数量不变，但会增加部分绘制提交。正式接入时应继续合批与减面。

当前为展示模型：蓝衣角色 78,920 三角形、绿衣角色 88,440，整场景 508,684。建筑单体保留细分部件，整场景对静态物体进行了合并。尚未做游戏级 LOD、正式蒙皮、地图碰撞、角色遮挡淡出，以及七种作物的完整生长阶段。

下一步先收敛角色比例与材质表现，再制作适合游戏镜头的低面数版本和农活动作，接入一个能移动、播种、浇水、收获的三维小场景，最后扩展到完整地图。原有存档和联机规则继续复用。

## 2026-09-15 交付记录

本轮已重新构建并复核当前资产：18/18 GLB 导出成功，6/6 PNG 为 1920×1200；`validation/verification.json` 记录 2646 项检查、0 个失败。导出的农场 GLB 已回导并重新渲染，结果见 [回导画面对比](validation/visual-comparison.json) 和 [imported-farm.png](validation/imported-farm.png)。

可直接分发的压缩包为 [breeze-town-2_5d-art-pack.zip](../breeze-town-2_5d-art-pack.zip)，不包含 Godot 引擎、缓存和诊断日志。压缩包只代表展示模型和风格基线，尚不代表 `game/` 已切换到 3D；当前整场景约 50.9 万三角形，角色约 7.9 万～8.8 万三角形，正式接入前必须制作游戏级低面数、LOD、碰撞代理和遮挡处理。
