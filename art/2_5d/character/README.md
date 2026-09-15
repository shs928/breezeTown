# 立体农夫角色

原生 Godot 4 网格资产；所有五官、帽子、编织纹、服装、缝线和工具均为真实几何体，无贴图依赖。

```gdscript
const FarmerModel = preload("res://scripts/farmer_model.gd")

var farmer: Node3D = FarmerModel.build(0)
add_child(farmer)
farmer.get_node("AnimationPlayer").play("idle")
```

- `build(0)`：栗色短发、靛蓝背带裤、苔绿色帽带。
- `build(1)`：铜色短辫、苔绿背带裤、陶土色帽带。
- 坐标：Y 向上，正面朝 +Z；脚底落在 Y=0，双脚围绕原点站立。
- 帽宽约 0.781 米，含帽高约 1.724 米，前后深度约 0.668 米。
- `AnimationPlayer` 包含 `idle`（3.2 秒）与 `walk`（0.92 秒）循环，默认不自动播放。
- 采用节点关节动画，未做蒙皮；网格与 StandardMaterial3D 可直接打包并交给主场景统一导出。

公开关节路径：

```text
Body/HeadPivot
Body/Arm_L
Body/Arm_R
Body/Arm_L/Elbow_L
Body/Arm_R/Elbow_R
Body/Leg_L
Body/Leg_R
Body/Leg_L/Knee_L
Body/Leg_R/Knee_R
```

角色使用高粗糙度材质，颜色层次由局部网格与轻微顶点色变化形成；最终画面由主场景的灯光、色调映射和环境光决定。当前版本适合人物展示、近景和美术定调：蓝衣 78,920 个三角形 / 115 个网格实例，绿衣 88,440 个三角形 / 125 个网格实例。大规模场景落地前应按关节和材质合批，并为远景减少草帽编织、缝线和圆面细分。

无界面检查命令（在仓库根目录执行）：

```powershell
& 'tools\engine\Godot-4.7.2-stable\Godot_v4.7.2-stable_win64_console.exe' --headless --path 'art/2_5d' --script 'res://character/check_farmer.gd' --log-file 'D:/Workspace/breezeTown/art/2_5d/character/check_farmer.log'
```

检查覆盖两种变体的网格、标准材质、顶点有限性、三角面朝向、脚底原点、尺寸、关节路径、动画实际采样与 PackedScene 打包；结构化结果见 `validation.json`。
