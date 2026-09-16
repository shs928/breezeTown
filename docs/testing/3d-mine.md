# 星辉矿场：十层地图验证

日期：2026-09-16。环境：macOS、Apple M5、Godot 4.7.2 stable、Metal Forward+。本次在现有 3D 山谷上增加地下矿场，保留此前的城镇扩图与农牧玩法。

## 可玩流程

从山谷北侧山脚的「星辉矿场」门口按 E 进入。山谷道路与 M 导览图均标出入口。入口位于 `(-29, -70.6)`，沿镇中心西侧通向北山的道路可达。

| 层数 | 场景与进度 |
|---|---|
| 1–3 | 旧矿道、铜脉回廊、矿车岔路；以铜矿为主，逐渐出现蝙蝠 |
| 4 | 滴水岩窟；铁矿、蓝绿色岩壁与浅水晶簇 |
| 5 | 矿工营地；无怪物，可休整，有升降机；向下梯子直接开放 |
| 6 | 幽蓝石窟；铁矿与洞穴怪物 |
| 7–9 | 水晶矿脉、回声深井、星辉回廊；紫色岩壁与水晶矿 |
| 10 | 地心晶室；晶岩守卫和两只蝙蝠，清理后开启宝箱 |

- 普通层北端的裂隙岩石需用镐子敲击两次，随后出现向下梯子。各层入口都有上行梯，1、5、10 层配有升降机；到达后才解锁对应目的地。
- 镐子每次对矿石造成 18 点采掘伤害。石料开采一次，铜矿、煤矿、水晶和裂隙岩石两次，铁矿三次。靠近矿物掉落后自动收集。
- 短剑对怪物造成 22 点伤害，镐子对怪物造成 6 点。挥击有方向、距离、冷却和墙体阻挡，每次挥动在接触时结算一次；短剑可以击中扇形范围中的多个怪物。飘字显示实际扣除的生命。
- 史莱姆和蝙蝠会绕过矿石追击，接近后显示预警，再尝试攻击；玩家可移动闪避。玩家有 100 生命，受伤后有 0.95 秒保护。Q 消耗一份口粮恢复最多 35 生命，满生命不会消耗。
- 第 5 层营地可休整一次，恢复全部生命并将口粮补足到至少 3 份。农舍睡觉也会恢复生命和口粮。倒下后返回矿口，恢复到 60 生命，已收集矿物保留。
- 第 10 层宝箱一次性给予水晶 12、铁矿 8、金币 150，并记录探索完成。
- 地表与矿层独立保存运行状态：离开地图后隐藏并停用其处理与碰撞；回访不会重刷矿石、怪物、营地或宝箱奖励。背包与农田、牧场在切换后保留。

当前是本地可玩原型。矿物用于收集展示，尚未接入锻造、矿物出售和磁盘存档；退出游戏后，本次运行的经营和矿场进度会重置。

## 操作

| 输入 | 行为 |
|---|---|
| WASD / 方向键，Shift | 移动，快跑 |
| 1–7 | 空手、锄头、水壶、种子、围栏、镐子、短剑 |
| E | 朝近处目标交互、采矿、攻击；使用梯子、升降机、营地、宝箱 |
| 空格 | 朝当前面向挥动镐子或短剑 |
| 鼠标左键 | 朝点击的地面方向挥动镐子或短剑 |
| Q | 食用口粮 |
| R | 切换种子种类，种子袋图案同步变化 |
| M / Tab / Esc | 当前地图、背包、关闭面板；这些面板打开时暂停矿场战斗 |
| 滚轮 | 调整跟随镜头距离；地表和地下分别记住缩放 |

六种非空手工具均有实际几何模型，挂在农夫右手关节下。锄地、挖矿和挥剑使用动作动画，装备随手臂一起运动。

## 自动化验证

完整玩法检查：

```bash
tools/engine/Godot-4.7.2-stable/Godot.app/Contents/MacOS/Godot --headless --path game -- --smoke
```

结果：**178 项通过，`SMOKE_RESULT PASS`**。日志：`work/game-3d-mine-smoke.log`。

正常输入与淡入淡出检查：

```bash
tools/engine/Godot-4.7.2-stable/Godot.app/Contents/MacOS/Godot --headless --path game --script res://scripts/tests/mine_input_checks.gd
```

结果：**11 项通过，`INPUT_RESULT PASS`**。日志：`work/game-3d-mine-input.log`。通过正常事件队列发送按键，不使用冒烟模式跳过过场；验证进出矿层、连续输入、WASD、6/7 装备、E 挖矿和上下梯、M/Esc 暂停与恢复。

合计 **189 项检查通过**。覆盖原有农牧与山谷回归，以及矿口通路、地表碰撞停用/恢复、七种装备状态、种子外观、挥动挂点、单次命中、伤害数字、墙体阻挡、怪物自身的追踪与攻击、受击保护、地图暂停、口粮、十层真实碰撞通路、逐层上下梯、升降机限制与按钮、营地与宝箱防重复奖励、回访状态、倒下返程与农舍恢复。

## 实机画面

15 个视图全部来自 Godot 运行中的场景；装备对照图仅裁切并排列各工具的游戏截图。批量复现只启动一次游戏：

```bash
tools/engine/Godot-4.7.2-stable/Godot.app/Contents/MacOS/Godot --path game --resolution 1600x1000 --script res://scripts/tests/capture_mine_gallery.gd
```

结果：`GALLERY_RESULT PASS 15 views`；日志 `work/game-3d-mine-gallery.log`。图像均为 1600×1000。单张图片也可用主场景的截图参数复现：

| 场景 | 参数 | 本地图片 |
|---|---|---|
| 北山矿口 | `--at=-29,-68.8 --zoom=1.35 --tool=pickaxe` | `work/game-3d-mine-entrance.png` |
| 第一层总览 | `--mine=1 --view=mine-overview` | `work/game-3d-mine-01-overview.png` |
| 第五层营地 | `--mine=5 --at=-5,3 --zoom=1.0` | `work/game-3d-mine-camp.png` |
| 第七层水晶区 | `--mine=7 --at=0,-4 --zoom=1.35` | `work/game-3d-mine-crystal.png` |
| 当前矿层地图 | `--mine=7 --view=map` | `work/game-3d-mine-map.png` |
| 山谷矿口地图标记 | `--view=map` | `work/game-3d-mine-valley-map.png` |
| 第十层守卫 | `--mine=10 --at=0,-3 --zoom=1.35 --tool=sword` | `work/game-3d-mine-guardian.png` |
| 挥剑与伤害数字 | `--mine=1 --view=combat` | `work/game-3d-mine-combat.png` |
| 七种装备状态 | `--mine=1 --view=equipment --tool=<工具 id>` | `work/game-3d-mine-tool-*.png` |
| 装备对照 | 上一行截图的裁切拼图 | `work/game-3d-mine-equipment-sheet.png` |

单张图片复现示例：

```bash
tools/engine/Godot-4.7.2-stable/Godot.app/Contents/MacOS/Godot --path game --resolution 1600x1000 -- --mine=1 --view=combat --shot=/absolute/path/combat.png
```

调试时 `--mine=1` 到 `--mine=10` 可直接进入指定矿层；正常游玩须从矿口逐层解锁。截图模式冻结怪物的 AI 决策，保留待机、挥动、命中、伤害数字和灯光渲染；战斗伤害通过实际挥击触发。

视觉复核修正了低矮岩壁在静态合并时的顶面缺口、矿脉被岩石表面遮住、战斗飘字与生命文字重叠、通知遮挡战斗区等问题。岩壁现在使用包含顶面和侧面的封闭网格，按节点位置参与静态分块；矿脉、装备和伤害数字可辨识。

截图与日志由现有 `.gitignore` 规则排除。Windows 本轮未实机验证。
