# 微风山谷扩图验证

日期：2026-09-16。环境：macOS、Apple M5、Godot 4.7.2 stable、Metal Forward+。本记录针对当前 3D 工程，不沿用历史 2D 测试结果。

## 本次交付

- 可活动边界从 92×72 米扩展到 192×160 米，名义面积约为原来的 4.64 倍。
- 新增 13 栋原创建筑：镇公所、诊所、图书馆、旅店、面包房、铁匠铺、木工坊、5 栋住宅、风车。连同原有 4 栋，共 17 处建筑地标。
- 镇中心广场、住宅街、果园、西侧山林、东侧山间湖和连通各区的道路；建筑入口、道路、碰撞与导览图共享布局数据。
- 周边为闭合的草坡、岩壁、错落岩峰与松林。玩家移动和耕地范围使用同一超椭圆边界。
- M 导览图、Shift 快跑、五档缩放；中文 HUD、地图和门牌使用内置 OFL 字体。
- 接通此前未完成迁移的网格耕地与牧场入口，修复主场景引用已删除的 `plot.gd` 而无法启动的问题。保留整地、播种、浇水、生长、收获、买卖、睡觉和动物产出流程。

新增城镇建筑本次提供外观、门牌和门前空间；室内、NPC 日程、诊疗、工具升级等服务没有接入。自建围栏目前生成空牧场，动物购买仍未实现。

## 自动化检查

运行：

```bash
tools/engine/Godot-4.7.2-stable/Godot.app/Contents/MacOS/Godot --headless --path game -- --smoke
```

结果：**70 项通过，`SMOKE_RESULT PASS`**。日志：`work/game-3d-valley-smoke.log`，无脚本错误或退出时资源泄漏警告。

另以普通游戏入口运行 120 帧（`--path game --quit-after 120`），输出 `GAME_READY` 并正常退出；日志 `work/game-3d-valley-boot.log` 无错误或警告。

覆盖：

- 初始资金与种子、整地、播种、重复无效播种不扣种子、浇水、逐日生长和成熟视觉、收获。
- 商店开关、作物出售、填食槽、抚摸动物、睡觉、产出、拾取和畜产品出售。
- 导览图开关及玩家移动锁定、解锁。
- 从实际出生点做碰撞网格搜索，每一步使用玩家胶囊体扫掠，验证 17 处建筑入口均可抵达，不能直接跳过薄围栏；同时检查建筑主体阻挡玩家。
- 农田和牧场大门、新扩展东西区域可达；广场、湖水和圆角边界不可开垦，外侧草地可开垦。
- 围栏不能覆盖道路；可在空地完成两角圈定，圈定后的牧场禁止耕种。
- 玩家在东、南、西、北方向越界时均被约束到山脚以内。

## 视觉复核

使用真正的游戏场景输出 1600×1000 截图并逐张检查，没有使用概念图替代游戏渲染。

| 场景 | 参数 | 本地截图 |
|---|---|---|
| 山谷全景 | `--view=overview` | `work/game-3d-valley-overview.png` |
| 镇中心 | `--at=0,-40 --zoom=2.3` | `work/game-3d-valley-town.png` |
| 导览图 | `--view=map` | `work/game-3d-valley-map.png` |
| 北侧山脚 | `--at=0,-74 --zoom=2.3` | `work/game-3d-valley-north.png` |
| 东侧山脚 | `--at=91,-6 --zoom=2.3` | `work/game-3d-valley-east.png` |
| 南侧山脚 | `--at=0,75 --zoom=2.3` | `work/game-3d-valley-south.png` |
| 南侧近景 | `--at=0,77 --zoom=0.8` | `work/game-3d-valley-south-close.png` |
| 西侧山脚 | `--at=-91,2 --zoom=2.3` | `work/game-3d-valley-west.png` |
| 住宅街 | `--at=47,-27 --zoom=2.3` | `work/game-3d-valley-homes.png` |
| 牧场 | `--at=24,16 --zoom=1.8` | `work/game-3d-valley-ranch.png` |
| 夜间广场 | `--at=0,-40 --zoom=2.3 --hour=22` | `work/game-3d-valley-night.png` |

复核结果：四侧无空白边界；山脚近景可见玩家；街区道路和门前通路清楚；地图中文、建筑门牌和 HUD 正常；夜间路灯覆盖广场入口。静态网格合并时为缺失的顶点色补白，避免原始球体与手工网格混合后出现黑色动物身体。

复现单张截图（将输出替换成自己的绝对路径）：

```bash
tools/engine/Godot-4.7.2-stable/Godot.app/Contents/MacOS/Godot --path game --resolution 1600x1000 -- --demo --view=overview --shot=/absolute/path/valley.png
```

镇中心、导览图、牧场、夜间广场、总览在本机预热 35 帧后取 60 帧短样本，约 60 FPS。这只是当前机器、当前视角的短采样，不代表其他硬件或长期负载表现。Windows 本轮未实机验证。

截图和引擎日志属于本地验证产物，由现有 `.gitignore` 规则排除。新增字体的来源、许可和可重建方式见 `game/resources/fonts/README.md`。
