# V2 接续记录（历史日志）


更新：2026-09-18。本文件只留各轮改动与验证的过程记录；**当前状态、下一批任务与运行命令以 [任务板](task-board.md) 为准**（续作入口）。最近批次：TRANSPORT-02 驿站马车（PLAY-01 方案 A 实施）；此前 SOAK-01 长时回归、POLISH-05 两轮（季节视觉）、POLISH-04 退出崩溃排查、BUILD-01 构建导出、SETTINGS-01、POLISH-02、POLISH-01 第一轮、STORE-02、STORE-01、INDOOR-02+PROCESS-01、INDOOR-01、PERF-03、QUEST-01、NPC-01、GATHER-01、FISH-01 两轮、ART-02、PERF-02、PLAY-01、FARM-01 两轮。画风终验待用户确认。

## 2026-09-18 · TRANSPORT-02 驿站马车（PLAY-01 方案 A，用户选定）

改动范围：新增 `data/carriage_db.gd`（站点/矩阵/票价唯一数据源）与 `carriage_station.gd`（六站表现+解锁+焦点+存档）；改动 `core/interaction_system.gd`（carriage_station 焦点+踩点解锁）、`hud.gd`（马车线路面板+carriage_travel_requested 信号）、`main.gd`（创建/解析锚点/乘车传送/`travel` 存档键）、`docs/product/02-transport-pacing-plan.md`（状态更新+已实施参数）、新增 `tests/carriage_checks.gd`（25 项）。

- **玩法**：六站（农场口/镇广场/矿口/港务码头/北岭农庄/月湾湖畔），农场↔镇区开局解锁（免费教学线路），其余走到站旁自动解锁；站旁 E 呼叫面板选已解锁目的地，乘车扣矩阵时长（2–4 游戏时）+10 币（教学线免费），淡出淡入抵达站旁并 toast（新站解锁提示）。矩阵按 PLAY-01 实测距离标定，对称性有领域断言。
- **排错记录**：①湖畔站偏移与老王日程锚点几乎重合、农庄站与玛尔妮相距 2.5 米——驿站 2.4 米焦点半径抢在 NPC 对话之前，quest_checks 传话链 7 项连锁失败暴露；两站偏移移出 NPC 日程半径（湖 +7.5/+4.0、农庄 +6/+6）后恢复。教训：**新场景焦点类型的落点必须对照所有既有焦点源的站位半径**。②测试轮询"乘车完成"不能用 `carriage_from_id==""`（close_carriage 在淡出前就清了），必须轮询玩家实际坐标。③本机 Git Bash 的 sed 多行插入（\ 续行）会粘连/丢行——多次踩坑后一律改用临时文件拼接。
- **验证证据**：`work/art01/transport02-station.png`（农场站实景）；carriage 25 项 PASS（六站定位/默认解锁/踩点解锁/面板/计费计时长/免费线路/穷旅客拒载/矩阵对称/存读档解锁恢复）；回归 indoor 199 / first_map 154 / npc 42 / quest 31 / smoke 全 PASS。
- **剩余范围**：C1（快跑时间消耗减半）未实施（可作后续节奏微调项）；马车仅停驻表现无行驶动画（氛围增强留 ART 批次）；用户实机手感验收。

## 2026-09-18 · SOAK-01 长时间运行回归（整年模拟浸泡测试）

改动范围：新增 `tests/soak_checks.gd`（无生产代码改动）。

- **设计**：确定性步进模拟经营——`SOAK_DAYS`（默认 112=整年四季）逐段推时间，按概率穿插存读档往返（断言金币/天数无损）、四室内进出、矿场进出、四区域传送（驱动森林分块流式加载与水域碰撞重建）、熔炉整周期、农田全年追踪；每 14 天采样静态内存/对象数/节点数。`SOAK_SEED` 固定可复现。
- **结果（112 天）**：SOAK PASS，34 次操作、零脚本错误；内存 367→394MB 平台期、节点 6384→8659 平台期（分块流式收敛，无泄漏增长）；存读档多次往返无损；退出码 0。**365 天加强版（≈3.26 游戏年）**：PASS 22 项、125 次操作、内存平台 405MB、零脚本错误。
- **排错记录**：①`--script` 桩环境里 main._process 不运行——所有逐帧系统（机器 tick、NPC 日程）须测试显式驱动（`_tick_machines/_update_npc_schedules` 与逐帧行为等价的批处理），此前各场景测试直接调内部方法所以从未暴露；②节点数监视器名是 `OBJECT_NODE_COUNT` 不是 NODE_COUNT；③测试内嵌函数一行化——sed 多行插入在本机 Git Bash 不可靠，改用 perl -0pi 或先写临时文件再 rinsert。
- **剩余范围**：灌木季色、音效、引擎 issue 上报、（长期）真实挂机数小时的人类验证。

## 2026-09-18 · POLISH-05 二轮：树冠/森林季色（樱花冬季穿帮修复 + 秋季金林）

改动范围：`art/season_visuals.gd`（叶季色表、共享季色材质、GLB 材质原地变异 + 字符串键原色表、_parts 通道）、`art/tree_models.gd`（Leaves 材质改专属 `#fffffe` 单例）、`main.gd`（_apply_season_visuals 扩展三通道）、`tests/indoor_checks.gd`（树冠季色 7 项）。

- **三条通道对应三类载体**：①森林/成树 GLB——材质名前缀（PineLeaf/Broadleaf）识别树冠，albedo 原地变异（共享导入资源一次生效全场景）；②代码树冠（樱花/幼树）——合并进 StaticGeometry 批次，树叶改挂 `#fffffe` 专属材质使其自成独立批次，季切只改共享材质 albedo；③世界内嵌 GLB 树——MeshInstance 遍历覆盖。树干（WarmBark）与果实（AppleVermilion）排除。
- **排错记录**：①首版给 MultiMesh 设 material_override——会整体替换 GLB 材质丢纹理，靠"森林无 FoliageMulti 命名"的测试失败暴露，改材质变异方案后撤销；②原色表用 Object 键在存读档后失效（材质实例释放）——改"材质名@路径"字符串键；③GLB 遍历只扫 MeshInstance3D 漏掉 MultiMesh——补 _parts 通道；④"Leaves 命名节点"只在代码构建树存在，世界树全是 GLB 或已合并——按载体分流是本批核心设计。
- **验证证据**：`work/art01/polish05b-{winter-trees,autumn-forest,winter-forest}.png`（秋橡金黄/松橄榄金、冬樱霜紫）、四季 `polish05-season-{1,29,57,85}.png`；season 18 + indoor 199 全 PASS；回归 14 套 + smoke 全 PASS；导出包重建后退出 0 + smoke PASS。
- **剩余范围**：灌木季色（材质色非顶点色，需单独方案）、雪天细节、音效、长时间回归、引擎 issue 上报。

## 2026-09-18 · POLISH-05 季节地表视觉第一轮（冬雪盖、秋草黄、环境色调层）

改动范围：`art/cozy_landscape.gd`（地面着色器 +snow_amount/+season_tint）、新增 `art/season_visuals.gd`（纯函数调色表）、`main.gd`（_apply_daylight 季节层叠加 + _apply_season_visuals + `--day=` 截图参数）、`tests/season_checks.gd`（18 项）、`tests/indoor_checks.gd`（季节联动 5 项）。

- **实现选型**：不加大覆盖面（会盖住道路交互感），改为**地面着色器 uniform**——snow_amount 噪声化混雪（0.82~1.0 随噪声起伏，避免"贴纸感"），season_tint 乘子调草色。世界场景走缓存/预置时同样生效（材质实例运行时取自 MetricTerrain 节点）。环境色调层叠在日光关键帧与雨天压暗之间（顺序：日光插值→季节乘子→雨天压暗）。
- **视觉结果**：冬季地面全雪盖、作物穿雪、道路如扫过、环境冷蓝；秋季草转干黄+暖金光线；夏季深绿；春季微鲜。树冠/灌木重着色（foliage_tint 已备接口）留下一批——本季樱花树在冬天仍是粉色，是当前最显眼的季节穿帮。
- **排错记录**：色相方向断言写反（冬 b 通道应更高）；sed 批量编辑 shader 后必须 grep 验证落点。`--day=` 截图参数同步联动 weather_for_day。
- **验证证据**：`work/art01/polish05-season-{1,29,57,85}.png` 同机位四季对比；season 18 / indoor 192 全 PASS；回归 13 套 + smoke 全 PASS；世界重建+导出后 PREBUILT 命中、退出 0。
- **剩余范围**：树冠/灌木季节重着色、雪天积水/脚印细节、音效、长时间回归、引擎 issue 上报。

## 2026-09-18 · POLISH-04 退出段错误排查与发布形态定型（debug 模板导出）

改动范围：`core/save_manager.gd`（_read_text 辅助 + 存档读取 2 处）、`first_map_builder.gd`（_read_text + 指纹/缓存读取 3 处）、`tools/build_windows.sh`（--export-release → --export-debug）。临时探针（exit_bisect/split_payload/leak_probe、main.gd 阶段门、clean-probe 工程）诊断后全部清理。

- **症状**：release 模板导出包（4.7.1/4.7.2 双版本）退出确定性堆损坏（0xC0000374，WER：ntdll）；debug 模板与 dev 引擎全程正常；headless（Dummy 渲染器）也崩 → 非渲染侧。
- **定位过程（大量二分）**：子树预释放（HUD/天气/灯光/玩家/OutdoorMap 全试）无效；静态资源缓存清空无效；脚本导出三模式、TAA/MSAA/SSAO/粒子、4.7.1 模板均排除；在纯净工程复刻 load+instantiate 游戏 world.scn 即崩（最小复现），进一步二分到 **`FileAccess.get_as_text()` 单 API 即可触发**（10 行探针 3/3 复现；`get_buffer+get_string_from_utf8`/`get_as_utf8_string`/`get_line` 全部干净）。修复全部生产调用点后 stage2a（世界加载）恢复干净退出，但完整启动仍有布局敏感的退出崩溃（同一处代码加两条 if 即翻转）→ 判定为引擎原生缺陷，代码侧无法根治。
- **上报素材**：clean-probe 最小复现工程（Node3D._ready + FileAccess.get_as_text → release 导出包退出段错误；4.7.1/4.7.2 复现，debug 模板正常）留存于 work/clean-probe/。
- **发布决策**：构建链改 `--export-debug`。依据：退出 5/5 exit 0、headless smoke PASS + exit 0、实机渲染 128.7 fps（与 release 同级；debug 模板不降低 GDScript 速度）。release 模板待引擎修复后切回。
- **验证证据**：最终包 quit 3/3 干净、debug smoke PASS、窗口渲染截图 `work/art01/build01-debug-perf.png`；开发回归 13 套 + smoke 全 PASS（core/first_map 154/indoor 160+187/settings 13/npc 159+42/quest 135+31/farm 54/forage 138/fishing 77/weather 40）。**教训**：sed/perl 批量插代码两次搞坏文件（吞行/重复行），阶段门类临时插桩必须用行号 sed 且插完立即 grep 验证；"修好又坏"的波动首先要怀疑二进制布局敏感性而非回退。
- **剩余范围**：引擎 issue 上报（附最小复现）、退出泄漏告警（资源缓存持有，进程正常退出）、季节地表变化、音效、长时间回归。

## 2026-09-18 · BUILD-01 构建导出（Windows 单文件 exe + 内置烘焙世界）

改动范围：新增 `export_presets.cfg`、`tools/build_windows.sh`、`scripts/bake_world.gd`、`scripts/tools/make_icon.gd`、`game/icon.png`；改动 `first_map_builder.gd`（长度指纹 + 导出包预置世界）、`.gitignore`（prebuilt/ 与 icon_raw.png）。

- **构建链**：`tools/build_windows.sh` 两步——①全量烘焙世界进 `game/prebuilt/`（约 11 秒，每次构建重烘不做跳过）；②`--export-release "Windows Desktop"` 出 `build/BreezeTown.exe`（171MB 单文件，内嵌 PCK，S3TC/BPTC）。产品名/图标/描述已进 exe 资源。
- **首启加速**：导出包运行时 `OS.has_feature("template")` 命中即加载 `res://prebuilt/` 只读世界（`WORLD_PREBUILT HIT`），清空用户缓存首启也无 27 秒重建、不写 `user://cache/`。
- **指纹方案的三次迭代（重要教训）**：①`FileAccess.get_md5` 对 PCK 内嵌文件行为与源树不同；②此引擎构建无字节级哈希 API（PackedByteArray 无 md5/sha256/hex_encode，无 HashContext，String 无 utf32_to_string——全部实测排除）；③导出 PCK 根本不含 .glb 源文件（只有导入产物），且 headless 导出时脚本的编译形态与源树长度不同——**任何跨环境内容指纹都会误拒**。最终：开发缓存用"路径+文件长度"指纹（.gd/.json 两环境逐字节一致），导出包预置世界不做运行时校验（完整性由构建链保证）。
- **其他排错**：导出路径必须绝对路径且父目录须先存在；`OS.has_feature("export")` 是错误特性名（正确为 `"template"`）；bake 脚本解析失败时 Godot 不退出（协程悬挂）导致后台任务空转 35 分钟——构建链所有 Godot 调用加 `timeout`。
- **验证证据**：导出包清空用户缓存后 headless smoke 全 PASS 且 `WORLD_PREBUILT HIT`、无缓存写入；窗口模式启动画面完整（`work/art01/build01-windowed.png`）；开发环境回归 first_map 154 / core / indoor 187 / settings 13 / smoke 全 PASS。
- **剩余范围**：退出时段错误（既有 ObjectDB/资源泄漏的终态表现，POLISH-01 备查项）、Steam 管道部署与 depot 打包、macOS/Linux 导出、版本号与自动更新策略。

## 2026-09-18 · SETTINGS-01 设置面板（显示/音量/键位重绑，ConfigFile 持久化）

改动范围：新增 `core/game_settings.gd` 与 `tests/settings_checks.gd`；改动 `core/input_actions.gd`（settings 动作 F10/Start）、`hud.gd`（设置面板+重绑捕获 `capture_rebind`）、`main.gd`（启动应用设置、重绑路由、`--open-settings` 截图参数）。

- **面板**：显示模式（窗口/全屏 OptionButton）、垂直同步 CheckButton、主音量 HSlider（AudioServer 主总线，为音效批次预留）、13 项键位重绑（点击按钮→"按新键…"→按键盘生效、Esc 取消；重绑只替换键盘事件保留手柄绑定）、恢复默认键位。木框羊皮纸风格与全 UI 统一。
- **持久化**：ConfigFile `user://settings.cfg`；video/audio/keys 三节。**关键设计**：测试环境（BREEZETOWN_SAVE_ROOT 非空）不落盘且启动不应用键位——否则开发者改键后所有 headless 按键注入检查（E 进店等）会静默失配；`save_settings(force)` 供领域测试强制写入。
- **排错记录**：`apply_keybind` 初版混入未完成的探索代码（`if ... or true: pass`）——写完即读一遍；`load-clamps-display` 断言初版没先把脏值写进文件（load 只读文件，改静态值再 load 不构成往返）。
- **验证证据**：`work/art01/settings01-panel-1600.png`；settings 领域 13 项、indoor 场景 187 项（含 F10 开关、重绑 K 生效/恢复默认后 Tab 可用）；回归 11 套 + smoke 全 PASS，0 脚本错误。
- **剩余范围**：设置面板的画质档位（阴影/抗锯齿）、键位重绑的手柄侧 UI、季节地表变化、音效资产。

## 2026-09-18 · POLISH-02 输入动作层与手柄支持（键盘行为零变化）

改动范围：新增 `core/input_actions.gd`；改动 `player.gd`（移动 get_vector/跑步动作化）、`main.gd`（`_unhandled_input` 全动作化+左键抽 `_on_world_click`+钓鱼输入动作化）、`hud.gd`（面板手柄焦点抓取）、`tests/indoor_checks.gd`（手柄注入 4 项）。

- **动作清单**：18 组动作在 `main._ready` 最先注册（幂等，重注册先 erase events）。移动=WASD/方向键/左摇杆（死区 0.3）、跑=Shift/L3、交互=E/A、工具=空格/X、口粮=Q/Back、换种=R/十字键下、背包=Tab/Y、地图=M/十字键上、快存 F5、快读 F9、工具循环 LB/RB、缩放=滚轮/十字键左右、槽位 1–0；关闭=内置 ui_cancel（Esc/B）。
- **兼容性关键**：每个键盘键同时绑 keycode 与 physical_keycode 两个事件——真实键盘与测试的 `parse_input_event`（双字段都设）都能命中；`Input.get_vector` 的 y 轴与旧 W/S 口径一致，移动语义逐字不变。
- **手柄 UI 导航**：四个面板（商店/仓库/对话/升降机）打开时抓取首个可用按钮焦点，**仅在连接了手柄时**——键盘用户的 Space 在模态内"无操作"的旧行为保持不变（否则焦点按钮会吞 Space）。
- **排错记录**：重写 `_unhandled_input` 时漏掉了左键点击分支（面向落点+使用工具），被编辑失败的"字符串不存在"暴露——重写大函数前必须完整读取现场；perl 带字节转义的多行替换把 task-board 头行损坏（`git checkout` 单文件恢复后改用编辑工具）——**带转义字节的批量文本替换禁用于文档**。
- **验证证据**：键盘行为回归 first_map 154 / smoke / npc 42 / quest 31 / farm 54 / indoor 176→180（含手柄注入：A 进出门农舍、焦点解析）全 PASS，0 脚本错误；本批无新截图（无视觉变化），手柄实机体验待用户验收。
- **剩余范围**：设置菜单与键位重绑 UI、手柄按键提示文案、季节地表变化、音效。

## 2026-09-18 · POLISH-01 第一轮（天气视觉与降雨浇地）

改动范围：`tiles.gd`（`water_all()`）、`core/game_clock.gd`（`is_rainy()` 静态规则）、`main.gd`（`_setup_weather_fx` 雨雪粒子、`_apply_daylight` 门控与雨天压暗、`_apply_rollover` 降雨浇地、`--weather=` 截图参数）。

- **雨雪粒子**：GPUParticles3D 挂架跟随玩家（y+9），排放盒 ±22 米；雨 900 条细长丝（18–22 m/s + 微风斜落），雪 420 片慢速 billboard 白片（生命周期 6 秒覆盖全程下落）。发射与可见性在 `_apply_daylight` 顶部统一门控：仅室外 + 对应天气；矿场/室内自动关闭。
- **雨天氛围**：天空色向灰蓝 lerp 45%、环境光 ×0.82、阳光 ×0.45、补光 0.14——与粒子同帧生效，无切换跳变（每帧插值本身就是连续的）。
- **降雨自动浇地**：`_apply_rollover` 日切结算时按 `GameClock.is_rainy(天气)`（rain/storm；雪不浇——冬季作物枯萎，规则无歧义）调用 `tiles.water_all()`，toast 浇灌株数；睡觉与自然日切一致生效，雨天早上一睁眼全农场已浇好。
- **排错记录**：无新坑；`_apply_daylight` 顶部门控设计让矿场分支 early-return 不会漏关粒子。
- **验证证据**：`work/art01/polish01-rain-1600.png`（雨天农田实机：雨丝+压暗+天气芯片"雨"）；weather 31→40、indoor 场景 168→176（晴不浇/雨浇/雪不浇三段日切+粒子存在性）；回归 core/npc 159+42/quest 135+31/farm 54/forage 138/fishing 77/first_map 154/smoke 全 PASS，0 脚本错误。
- **剩余范围**：季节地表变化（冬雪盖/秋色调）、雨声音效、设置/键位/手柄、构建产物、长时间回归。

## 2026-09-18 · STORE-02 仓库扩容/丢弃/分类 + 加工第二辈配方

改动范围：`data/item_db.gd`（bread/blanket 入 products、warehouse_expansion 特殊物品）、`data/recipe_db.gd`（kitchen/loom 站点与 3 新配方）、`game_state.gd`（`warehouse_capacity`/`warehouse_total`/`warehouse_discard`，容量存档归一下限 300）、`data/interior_db.gd`+`interior_room.gd`（酒馆厨房灶台、谷仓织布机）、`hud.gd`（容量显示/六族分组标题/丢弃两步确认）、`main.gd`（扩容产出、容量闸门、丢弃处理）。

- **容量与扩容**：仓库默认 300 件上限，超容整批存入被拒并提示；工作台新配方 木材×15+石料×10→仓库扩容（+300，可重复）。面板状态栏显示"仓库 x/y 件"。
- **丢弃与分类**：仓库面板按六族分组加标题；逐行"丢弃"两步确认（首点变"确认丢弃？"防误触）。
- **加工第二辈**：酒馆厨房灶台 小麦×3→面包（3 时，24 币）；谷仓织布机 羊毛×3→毛毯（6 时，48 币）。面包/毛毯入 products 族可售可送礼。
- **设计决定（暂定）**：多配方机器按目录序自动选首个原料齐全者（熔炉铜>铁、工作台宝箱>肥料>扩容），配方选择 UI 列入后续——由此场景测试断言"木料石料齐备时工作台优先做宝箱"，扩容用直接启动配方验证。
- **排错记录**：`state`（RefCounted）方法返回 Variant 不能 `:=` 推断（本批再次出现，`warehouse_discard` 处）；sed 在 elif 链中插行吞掉 `hud.hide()` 造成解析失败。新增 products 键时漏改 `game_state` 初始表导致 `products["bread"]` 越界——**ItemDB/初始表/存档归一三处必须同步**。
- **验证证据**：`work/indoor01/` 更新 `indoor-{inn,player_barn}-1600.png`（厨房灶台/织布机）；indoor 领域 145→160、indoor 场景 142→168；回归 core/npc 159+42/quest 135+31/farm 54/forage 138/fishing 77/weather 31/first_map 154/smoke 全 PASS，0 脚本错误。
- **剩余范围**：背包拖拽与格子化（PRD 15.1 完整形态，需背包模型改造，列后续）、配方选择 UI、POLISH-01。

## 2026-09-18 · STORE-01 工作台与仓库第一轮（宝箱制作/放置、共享仓库存取）

改动范围：新增 `warehouse_chests.gd`；改动 `data/item_db.gd`（chest/fertilizer 特殊物品入表）、`data/recipe_db.gd`（工作台两配方）、`game_state.gd`（`chests_ready`/`warehouse` + 整批存取与脏档清洗）、`data/interior_db.gd`+`interior_room.gd`（木工坊室内与工作台机器）、`core/interaction_system.gd`（warehouse_chest/chest_place 焦点）、`main.gd`（产出特判、放置/开关/收起、`chests` 世界存档键、HUD 信号）、`hud.gd`（共享仓库面板）。

- **工作台（木工坊室内）**：木材×10+石料×5→宝箱（2 游戏时）、木材×6→肥料×2（1 游戏时）。宝箱/肥料以特殊物品入 ItemDB 供配方校验，产出在 `_grant_machine_output` 特判路由（`chests_ready` 计数 / `state.fertilizer`），与六族背包产出分流。
- **宝箱放置**：收取后面向空地按 E 放置（is_open+非耕格门控），登记 `occupy_resource` 阻耕作；面板内"收起这个宝箱"返还放置计数，仓库内容不受影响。
- **共享仓库**：所有宝箱连通同一 `GameState.warehouse`（六族物品整批存取，事件口径与背包一致——取出委托物品会正常触发"委托可交付"toast）。HUD 新面板：逐行"背包 n / 仓库 m"与 存入/取出 按钮，`chest_open` 进 `modal_open`/`dismiss_panels`。
- **存档**：economy 侧 `warehouse`+`chests_ready`（未知物品/脏值/负数清洗，上限 1e6）；世界侧 `chests` 键只存位置数组（共享仓库设计使内容无需随箱存），重建时重新登记占地。**坑**：`state` 在 main 中是 RefCounted，`var moved := state.warehouse_deposit(...)` 无法类型推断——显式 `: int`。
- **验证证据**：`work/indoor01/` 新增 `indoor-carpenter-1600.png`、`store-chest-farm-1600.png`（放置宝箱+仓库提示，截图参数 `--place-chest`）；indoor 领域 118→145、indoor 场景 121→142；回归 11 套 + smoke 全 PASS，0 脚本错误。排错记录：sed 向 `--clean` 分支插入 elif 时吞掉 `hud.hide()` 导致 main.gd 解析失败（"Expected indented block after elif"）——批量插入后必须重跑编译路径验证。
- **剩余范围**：仓库扩容/分类与背包拖拽、加工第二辈配方（羊毛制品、酒馆菜谱）、LEGEND-01 图鉴、POLISH-01。

## 2026-09-18 · INDOOR-02 室内第二轮 + PROCESS-01 加工第一轮（机器/值守/增值链）

改动范围：新增 `domain/machine_state.gd`；填充 `data/recipe_db.gd`（首批 4 配方接线）；改动 `data/item_db.gd`（铜锭/铁锭/奶酪/蛋黄酱）、`data/interior_db.gd`（smith/player_barn/player_coop 三房 + 机器 + npc_spot）、`interior_room.gd`（机器视图/产出指示/npc 站位/hint_provider）、`game_state.gd`（库存新键 + add_mineral）、`npc.gd`（值守站位/`snap_to_schedule`）、`data/npc_db.gd`（皮埃尔锚点 `shop_door`→等价 `site:shop`）、`core/interaction_system.gd`（interior_machine 焦点 + 室内 NPC 焦点）、`main.gd`（机器初始化/tick/交互/`interiors` 存档键/值守挂载）、`tests/indoor_{domain_,}checks.gd` 与 `tests/npc_{domain_,}checks.gd`（断言随锚点迁移更新）。

- **加工链（PRD 第 13/14 节首批落地）**：熔炉 铜矿×4→铜锭(2 游戏时)/铁矿×4→铁锭(3)，奶酪压榨机 牛奶→奶酪(8)，蛋黄酱机 鸡蛋→蛋黄酱(4)。E 空转提示原料、投入即开始（原料走六族 `count_item/remove_items`）、加工提示剩余、完成 toast+产出指示物、收取回空。加工随世界时间推进（跨天/睡觉大步生效），`interiors` 存档键按"房间:机器"恢复剩余时长，未知配方/键清洗。
- **三个新室内**：铁匠铺（熔炉/铁砧/煤堆/武器架）、谷仓（压榨机/干草/食槽）、鸡舍（蛋黄酱机/巢箱）。**坑**：房间 id 必须对齐建筑 id（`player_barn`/`player_coop` 而非 `barn`/`coop`），否则门点映射失联——被领域检查"building-exists-*"当场抓住。
- **NPC 店内值守**：锚点为 `site:<房间id>` 的村民进屋时站 `npc_spot` 面向门口，室内对话焦点优先于服务点；出门 `snap_to_schedule` 回日程位。**关键排错**：NPC 挂在 `_outdoors` 下，进屋被整体隐藏（测试断言位置全过、截图却没人）——值守时临时改挂 `_interior_root`，出门挂回；另发现柜台后的站位在东南俯视相机下被柜台完全遮挡，站位沿柜台后沿前移并微偏后可见。
- **皮埃尔锚点迁移**：`shop_door` 与 `site:shop` 解析到同一坐标（landmark 即该建筑 door），室外行为零变化，但由此可被"锚点=建筑"的值守规则命中；npc_domain/npc_checks 中 6 处锚点键断言同步更新。
- **经济意义**：矿场与畜牧产出获得增值加工（锭 25/45、奶酪 32、蛋黄酱 12，均为出售/送礼物品）；工具升级仍用原矿（暂定，待确认是否改用锭）。
- **验证证据**：`work/indoor01/` 新增 `indoor-{smith,player_barn,player_coop}-1600.png` 与值守版 `indoor-shop-1600.png`（皮埃尔可见）；indoor 领域 68→118、indoor 场景 61→121（机器三流程、铁配方切换、值守与恢复、加工中存读档）；回归 npc_domain 159 / npc 42 / quest_domain 135 / quest 31 / first_map 154 / farm 54 / forage 138 / fishing-economy 77 / weather 31 / core / smoke 全 PASS，0 脚本错误。
- **剩余范围**：工作台/仓库（箱子与共享仓库）、加工第二辈配方（羊毛/菜谱）、皮埃尔锚点迁移后 `shop_door` landmark 仅剩出生点用途（保留）、最终门牌与布局待用户确认。

## 2026-09-18 · INDOOR-01 室内第一轮（Door → SceneTransition → Interior，四房带真实服务）

改动范围：新增 `data/interior_db.gd`、`interior_room.gd`、`tests/indoor_{domain_,}checks.gd`；改动 `game_state.gd`（buy_meal/buy_treatment，复用 `_purchase` 统一金币事件）、`core/interaction_system.gd`（室外门点统一 `building_door`，新增室内出口/服务焦点）、`main.gd`（_enter_building/_exit_building/_switch_indoor/_interior_service、`indoor` 存档键、smoke 商店流程改写、`--indoor=` 截图参数）、`player.gd`（set_bounds 增可选 center，默认原点不改既有行为）、`tests/first_map_checks.gd`（门点断言改写）、`tests/npc_checks.gd`（堵门守卫断言映射为进门+柜台，加 `_until` 轮询助手）。

- **四房服务**：农舍床铺=睡觉+自动存档（复用 `_sleep`）；杂货店柜台=商店 UI；酒馆吧台=套餐 30 币（体力回满+生命+60）；医院病床=治疗 50 币（生命回满；满血/缺币拒绝并 toast）。领域检查覆盖价格、恢复钳制、拒绝路径。
- **切换与边界**：房间建在远端展示坐标（z=9000）避免与地表物理重叠；玩家边界超椭圆改为支持中心点（房间中心）；室内时地图标记钉在建筑门口、时间照常流动、水面判定与水域碰撞重建门控关闭、`surface_map` 置空。房间无状态不进存档，仅存 `indoor` 键（房间 id），读档原位恢复；矿场/室内互斥。
- **视觉**：地板木板缝+门垫、北/西整高墙+南/东矮墙（东南俯视相机不遮挡角色）、墙裙腰线、房间暖光。**排错**：首版南墙整高把出生点角色完全挡住（视线在墙处 2.89m < 墙高 3.1m）——改矮墙后复检可见；墙裙尺寸未按墙朝向取轴导致"漂浮梁"穿墙——改为按朝向取长短轴。出生点最初卡在门框里，内移 0.6m。
- **排错（测试方法）**：headless 帧率不设上限，淡入淡出按真实时钟走——固定 55 帧等待时序不稳（`change` 回调已跑、`finished` 未跑，`_transitioning` 仍真导致焦点全空的级联失败）；统一改为 `_until` 条件轮询。边界钳制断言同理（process 帧远快于物理帧）。
- **语义变化**：室外 shop/cottage 门点 E 从"直接开店/睡觉"改为"进室内"；npc 堵门守卫（NPC-01）断言映射为"门点优先于对话、柜台办服务"——皮埃尔的门侧站位 (3,1.2)（3.26 米）在 2.4 米门点半径之外，交谈不受影响。布局与门牌为暂定值，待用户确认（任务板"后续需要确认"）。
- **验证证据**：`work/indoor01/` 截图 `indoor-{shop,cottage,inn,clinic}-1600.png`、`indoor-{shop,cottage}-1280.png` 双尺寸复核；indoor 领域 68 / 场景 61 / first_map 154 / npc 42 / quest 31 / core / farm 54 / forage 138 / fishing-economy 77 / 默认 smoke 全 PASS，0 脚本错误。
- **剩余范围**：室内第二轮（谷仓/鸡舍/铁匠铺/图书馆等 + NPC 室内锚点与店内服务深度）、制作加工（RecipeData/Machine）与仓库。

## 2026-09-18 · PERF-03 走路尖峰修复（导航网格全量重建 + is_walkable 全表遍历）

改动范围：`core/map_data.gd`（障碍/资源 16 米空间哈希索引、导航事件表 `navigation_events`、`navigation_full_dirty`）、`core/world_navigation.gd`（失效改事件增量刷新、锚点量化 64→160 米、局部网格 2 米格）。

- **现象与定位**：走路时每隔几十米主线程冻结 1.8–4.5 秒（实测复现：1.6km 往返 19260 帧，24 次 >150ms 尖峰，最大 4533ms，回程同位置复现）。逐层排除渲染（暂停帧纯渲染 max 18ms）、水域碰撞、森林区块、HUD 后，定位到 `OutdoorMap` 下的动物寻路：`_ensure_grid` 在 `navigation_revision` 变化或 64 米锚点平移时同步重建 ~160×160 格，每格 `is_walkable` 线性遍历全部障碍+资源占地（区块流转逐树 bump 版本号；越往东已加载资源越多、越慢——完美解释症状）。
- **修复**：①空间哈希索引让 is_walkable 只查邻域格；②导航失效按事件增量刷新（只有事件附近的格子重算），锚点量化与 2 米格把偶发整表重建压到半帧内（路径仍有逐段真实地图校验兜底）。
- **结果**：同一路线 0 次 >150ms 尖峰、最大 72ms。排错记录：`Dictionary.get(key)` 缺键返回 Nil 不能赋给 typed Array；GDScript 三元分支内声明的变量不出作用域。临时诊断脚本（walk/scan 系列）验证后即删，修复断言并入既有 headless 检查。

## 2026-09-18 · QUEST-01 NPC 委托任务（链式前置、收集/传话两类）

改动范围：新增 `data/quest_db.gd`、`tests/quest_domain_checks.gd`、`tests/quest_checks.gd`；改动 `game_state.gd`（quest 状态机、`count_item()/remove_items()` 六族统一扣件、`quests` 存档键）、`hud.gd`（委托按钮/追踪药丸/背包任务区）、`main.gd`（对话集成、接受/交付/传话流程、可交付 toast）。

- **数据与链**：八项委托，每人一条两段链（皮埃尔萝卜→沙丁鱼、玛尔妮鸡蛋→木材、巴特铜矿→煤炭、老王捎话→鲤鱼）。收集类凑 N 件五族物品回交付人处换取金币+好感；传话类与目标 NPC 交谈自动完成。`requires` 指向同 giver 的前置委托，领域测试校验链内无环、每村至少一链。
- **对话集成**：开对话时主控计算 `offer`（可接的第一个委托）与 `turnin`（该村民名下进行中的收集委托，含进度与 ready），HUD 据此显示"接受委托：X"/"交付：X（x/y）"按钮；交付扣实物（品质计数随总数对齐）并发奖励（好感夹 1000），答谢台词进对话框；传话在目标对话里自动完成、对方说答谢词。跨 giver 交付/接受一律拒绝（场景断言）。
- **可见性**：右上角追踪药丸（金额栏下方）常显进行中委托与进度；背包顶部"任务"区列进行中/已完成；凑满货物时 item_added 事件触发一次性"委托可交付"toast（`_quest_toast_done` 运行时集合防重复，接受/交付时清除）。
- **存档**：`quests: {accepted, completed}` 日戳表进 economy；旧档为空、未知 id 忽略、脏值夹 1000000、不改输入字典。
- **顺手修复（既有 flake）**：本轮 legacy smoke 首跑 `sell,sell-ranch` 失败、复跑通过——根因是 FARM-01 收获品质随机（施肥银 35%/金 10%），而 smoke 自那时起按固定 28/42 币断言，约半数进程必失败，此前各轮均属侥幸。改为按 `harvest_quality` 实际品质计算期望值（`radish_bonus`），双 smoke 复跑 PASS。教训：**断言涉及随机 roll 时期望值必须从被测状态推导，不能写死**。
- **排错记录**：GDScript `as` 优先级低于 `==`（`a == [x] as T` 解析成 `(a == [x]) as T`，须加括号）；场景测试 `_save_restore` 再次漏 `await`（协程悬挂 freed 报错，与 NPC-01 同型）；领域测试直接置 `quests_completed` 绕过链式前置时忘了接受步骤导致 `complete_quest` 空返回。
- **验证证据**：`work/quest01/`——`quest-domain.log` 135 项；`quest-scene.log` 31 项（对话委托入口、接受/进度/交付、传话自动完成、跨 giver 防护、存读档）；`visual-1600.log`/`visual-1280.log` 各 34 项。回归：npc 159/40、farm 54、钓鱼 275/77/104、天气 31、采集 138、core、first_map 152、新旧 smoke（flake 修复后复跑）全 PASS，0 脚本错误。截图 `quest-{1600,1280}.png`（委托按钮+追踪药丸）与 `quest-{1600,1280}-inventory.png`（背包任务区）双尺寸复核通过。
- **剩余范围**：每日重复委托、任务物品奖励、特殊事件、生日节日（LIFE-01 后续）；室内场景为下一批。

## 2026-09-18 · NPC-01 第一轮（日程/对话/送礼好感）

改动范围：新增 `data/npc_db.gd`、`npc.gd`、`tests/npc_domain_checks.gd`、`tests/npc_checks.gd`；改动 `game_state.gd`（好感/每日门控/送礼扣件/`npc` 存档键）、`core/interaction_system.gd`（npc 目标）、`hud.gd`（对话面板与 `dialogue_open` 模态）、`main.gd`（生成/锚点解析/时间推进/对话与送礼流程）。

- **四位村民**：皮埃尔（杂货店主：商店⇄镇广场）、玛尔妮（北岭牧场主：谷仓⇄农舍）、巴特（铁匠：铁匠铺⇄酒馆）、老王（渔夫：湖畔⇄酒馆⇄广场住宅）。日程是左闭右开时段→锚点表，覆盖 6:00–30:00（小时数 `fposmod(h-6+24,24)+6` 折算跨午夜）；锚点=landmarks 键或 `site:建筑id`（main 启动时解析到建筑 door，缺失回落镇广场）。
- **门侧偏移（关键排错）**：首版把皮埃尔白天锚点设在 shop_door 本点且村民焦点先于门点检测，皮埃尔堵死商店——first_map 152 项与新旧 smoke 首跑齐刷刷在 `shop-open` 失败。修法：日程条目加 `offset`（13 处门侧站位，皮埃尔 (3,1.2)），村民焦点回到门点之后、采集物之后；场景测试加"皮埃尔在门边时商店仍可打开"断言防回归。教训：**站在门口的 NPC 必须让出门点半径**。
- **交谈与送礼**：E（2.2 米）开对话面板；初见问候、之后按好感三档（<300/<700/≥700）从台词池抽句，`_npc_rng` 随机。送礼每天限一份，喜好四档（钟爱+60/喜欢+30/普通+15/讨厌−30）；`remove_gift_item()` 统一从六族背包扣一件，品质计数随总数对齐（普通=总数−银−金，先普通后银金——首版实现扣件顺序颠倒被领域测试抓出后重写为 tracked 对齐式）。好感 0–1000，十心显示。
- **存档**：`npc` 键（friendship/talk/gift 三表），旧档清零、未知 id 忽略、脏值夹取（talk/gift 是天数，上限 1000000 而非好感上限——首版统一夹 1000 被测试修正）；talk/gift 记录上次对话/送礼日，读档后"每日一次"门控继续生效。
- **排错记录**：`npcs` 数组挂在 main 上，场景测试 `_save_restore` 是协程却漏 `await`，游戏对象先释放导致 `previously freed` 级联报错；`find_child("HeadPivot")` 默认只找 owner 归属节点，代码生成的节点须 `find_child(name, true, false)`；`var fresh := GameState_new()` 返回 Variant 不能推断（改无类型）。
- **验证证据**：`work/npc01/`——`npc-domain.log` 159 项；`npc-scene.log` 40 项（锚点解析、日程切换含边界、对话门控、送礼扣件与重复送礼、存读档、堵门保护）；`visual-1600.log`/`visual-1280.log` 各 42 项。回归：first_map 152（复跑）、farm 54、钓鱼 275/77/104、天气 31、采集 138、core、新旧 smoke（复跑）全 PASS，0 脚本错误。截图 `npc-{1600,1280}.png`（皮埃尔对话：门侧站位/十心/台词）与 `npc-{1600,1280}-gift.png`（送礼面板）双尺寸复核通过。
- **剩余范围**：NPC 任务与特殊事件、生日/节日、礼物信件、室内与店铺服务深度（LIFE-01 后续）；交通方案（PLAY-01）仍待用户选择。

## 2026-09-18 · GATHER-01 野外采集（栖息地/季节刷新、徒手采集、经济与存档）

改动范围：新增 `data/forage_db.gd`、`forage_resource.gd`、`forage_resources.gd`、`tests/forage_domain_checks.gd`、`tests/forage_checks.gd`；改动 `data/item_db.gd`（forage 物品注册）、`game_state.gd`（库存/折价/出售/存档清洗）、`core/interaction_system.gd`（forage 目标与采集动作）、`main.gd`（管理器接线、日切补种与换季 toast、存读档）、`hud.gd`（背包“采集”区与商店折价文案）。

- **数据与栖息地**：14 种植物与海贝，六类栖息地映射到大图实际区域（森林/果园/镇区=同名区域矩形；湖畔=lake 区外环 16 米且距水 ≤9 米；海岸=harbor 区距水 ≤11 米；山地=mine 区外扩 24 米∪瀑布 70 米半径）。落点拒绝：水面、码头、耕地、牧场、NPC 农庄外扩 2 米、道路中心带、与既有采集物间距 <2.6 米；全场上限 90 株。
- **刷新**：开局 7–10 株；此后每天 4–7 株，按 `day*7919+137` 确定性播种（同日重放结果一致，场景测试验证）；换季（自然日切或睡觉）先移除不合季物种并 toast 株数，天气只影响当日生成池。稀有度 common/uncommon/rare 目前仅用于提示标注，不影响价格。
- **交互与经济**：任意工具下 E 徒手采集（2.3 米半径，金环聚焦+名称/价格/稀有度提示），+5 通用经验并复用升级提示；目标优先级低于工具目标与钓点、高于捡拾/动物/地块。`state.forage` 库存进入 `sale_total()`/`sell_all_harvest()`，与收获/产品/鱼获同一商店入口折价卖出；背包“物品”页新增“采集”区。
- **存档**：世界侧新增 `forage` 键（节点+季节；读档丢弃不合季物种、0.5×株距内重复落点去重）；经济侧 `forage` 计数旧档缺键清零，未知物种忽略、非有限/负数归零、1.5 之类浮点截断，输入字典不被修改。MapRestore 整表透传，无需改动。
- **视觉返工**：首版造型在 27 米正交相机下几乎不可辨（冬根被角色遮挡），整体提高 1.9× 造型基准并把聚焦环从 0.62 米放大到 0.95 米后复检通过。
- **排错记录**：`const Resource` 与原生类重名导致编译失败（改名 `Plant`）；成员初始化调用 `_zero_forage()` 需声明为 static；字典 `.get()` 推断 Variant 触发“警告即错误”（显式 `: String`）；测试里 GDScript lambda 按值捕获局部变量导致事件计数恒 0（计数器提升为成员变量）；`Dictionary` 无 `all()`、`Array.any()` 必须带谓词。
- **验证证据**：`work/gather01/`——`forage-domain.log` 138 项；`forage-scene.log` 71 项（真实地图落点规则、逐物种栖息地锚定、确定性日切、E 采集加项/除名/经验/防重复、存档恢复同位置同物种、换季清理后仅剩当季物种）；`visual-1600.log` 79 项与 `visual-1280.log` 85 项（场景检查项数随每次随机生成株数浮动，含 `forage-{1600,1280}.png` 与 `-inventory.png` 截图捕获）。回归：钓鱼 275/77/104、天气 31、农场 54、地图 152、core、新旧 smoke 全 PASS，0 脚本错误；模型缩放返工后复跑默认 smoke PASS。场景退出仍报既有 ObjectDB/渲染资源泄漏，留 POLISH-01。
- **剩余范围**：采集专属等级与图鉴、天气对已落地采集物的影响、制作/加工配方消费采集物，均留后续批次；交通方案（PLAY-01）仍待用户选择。

## 2026-09-18 · FISH-01 第二轮（条件鱼池、品质、独立成长与天气日切）

改动范围：`data/fish_db.gd`（条件、稀有度、行为）、`domain/fishing_session.gd`（行为与等级收益、控制评分）、`game_state.gd`（独立经验/品质/价格/存档）、`core/game_clock.gd`（天气循环）、`main.gd`（抛竿上下文、捕获奖励、逐日结算）、`hud.gd`（物品/鱼类页与技能信息），以及钓鱼规则、经济、场景和天气专项测试。前序未提交工作继续保留。

- **条件与行为**：按湖河、季节、天气、左闭右开时段筛选鱼池，包含鲶鱼 18:00–02:00 跨午夜条件；六种鱼有普通/少见/稀有元数据，`steady/dart/surge` 三种行为影响角力节奏。无符合条件的鱼时抛竿不扣体力；海域仍未开放。
- **独立成长**：捕获成功获得 `12×鱼难度` 钓鱼经验，升级门槛 `100×当前等级`，余量保留，10 级封顶后经验归零。只修改钓鱼会话收益：10 级咬钩窗口 +0.45 秒、进度增长 +18%、张力增长 -15%，一直按住仍会断线；通用等级和工具体力规则不变。
- **品质与计价**：本次角力张力处于 `[0.2,0.8]` 的时间比例构成控制分数，再加 `0.04×(钓鱼等级-1)`；银阈值 0.82、金阈值 1.14，因此优秀控制从 5 级开始可能取得金品质。普通/银/金售价倍率 1/1.5/2，银品质鱼逐条向下取整（银锦鲤 67 币/条）；农作物原有整批银品质取整规则保留。`sale_total()` 同时服务商店预估与真正卖出，物品/金币事件仍只结算一次。
- **存档**：新增 `fish_quality`（银/金子集）、`fishing_level`、`fishing_xp`；旧档缺少新字段时恢复零品质、1 级、0 经验，重复原位加载同样适用。加载仅清理新的鱼类字段：忽略未知种类，非数值/非有限数据归默认，数量有界，金/银总量不超过鱼获总数；嵌套表深拷贝，输入字典不被修改。JSON、直接内存字典与隔离磁盘存档均验证。
- **天气与跨天**：天气按七日晴/多云/雨/晴/晴/暴风雨/多云循环，冬季雨/暴风雨转雪；自然跨天和睡觉更新，合法已存天气在读档时保留。`_advance_world_time()` 将大时间步拆到各日边界，对每一天调用全世界结算，避免多日时间推进只结算一次。天气现用于鱼池，雨雪视觉及通用农场降雨效果留 POLISH-01。
- **HUD**：背包改为“物品/鱼类”两个可滚动页；鱼类页展示钓鱼等级/经验、普通/银/金持有数量、条件、当前可钓状态与单价。商店保留固定出售/关闭操作。第一版标签页灰底与文字对比不足，已改透明/纸色样式，并限制背包位置与高度避开信息栏和快捷栏。
- **验证证据**：`work/fish02/fishing-domain.log` 275 项、`economy.log` 77 项、`weather.log` 31 项、`fishing.log` 104 项、`farm.log` 54 项、`core.log` 及新旧地图 smoke 均 PASS；`hud-layout.log` 22 项验证双尺寸面板边界、滚动、文字宽度和标签样式。`visual-1600.log` 与 `visual-1280.log` 各 109 项 PASS。实机角力/鱼类页/商店截图已保存为 `work/fish02/fishing-{1600,1280}.png`、`fishing-{1600,1280}-inventory.png`、`fishing-{1600,1280}-shop.png`，最终 1600×1000 与 1280×800 视觉复核完成。`fishing-initial.log` 98 项保留为增加多日结算检查前的历史记录。
- **剩余范围**：下一步 LIFE-01 先做采集，再接 NPC 日程/对话/好感/任务、室内、制作加工和仓库；海钓、天气视觉和通用农场天气影响尚未实现，不宣称整个 M4 完成。既有退出资源泄漏仍列 POLISH-01。

## 2026-09-18 · FISH-01 第一轮（接续中断草稿，补齐淡水核心流程）

用户指定的 `sess\_9994c8b4-2738-4ef2-b952-9848f4b59642.zcode-session` 未在所给路径及 Workspace 搜索中找到。本轮依据任务板、历史接续记录与未提交代码恢复；保留此前所有未提交工作，继续已开始但尚未验收的钓鱼模块。

- 修复 `main.gd` 中 Variant 推断与 `m`/`M` 拼写导致的解析错误；原始失败记录在 `work/fish01/baseline-import.log`，修复后导入见 `import.log`。
- 新建纯数据 `domain/fishing_session.gd`，状态依次为等待、咬钩、角力、捕获/逃脱；按住收线提高张力与进度，松手回落，过紧、过松和超时可失败。规则按小时间步推进；三档难度的受控收线测试约 5.50/7.58/9.78 秒完成。
- 复用草稿的六种鱼、鱼竿模型/图标、物品目录、背包与卖出；有效抛竿消耗 5 体力，成功通过 `GameState.add_fish()` 发物品事件并增加通用经验。旧档缺少鱼获键时清零，内存往返使用鱼获副本避免自我清空。
- 采样到的真实淡水点同时决定鱼池和鱼漂位置；桥面不可落漂，海水不再充当河流。移动/转身、工具/面板切换、Esc、跨天、成功读档、地图过渡均清理临时钓鱼状态；被拒绝的读档保持现场。
- HUD 加张力/收线进度，鱼竿快捷键显示为 `0`。顺带修复阻断出售流程的旧商店溢出：原高 1225 像素使卖出按钮落到窗口下方，现货架滚动，出售和关闭固定显示。独立布局探针覆盖 1600×1000 与 1280×800。
- 验证：钓鱼规则 57、钓鱼场景 75、HUD 布局 60、地图 152、农场 54、领域数据、新旧地图 smoke 全 PASS。场景测试覆盖普通 E/空格/鼠标输入、物品/金币事件仅触发一次、出售与重复出售、磁盘存读和取消。日志在 `work/fish01/`；本轮未重跑 WORLD-01 两进程重启测试。
- 实机：1600×1000、1280×800 两轮各 79 项 PASS，截图 `work/fish01/fishing-{1600,1280}.png` 与 `fishing-{1600,1280}-shop.png`。初版居中张力面板遮住鱼漂，检查后移到右侧并加入投影点无遮挡断言；已复核两种尺寸。
- 当轮限制（历史，条件/品质/成长已在第二轮补齐）：时段/季节/天气条件、鱼品质、专属钓鱼经验/等级与海钓当时尚未完成，不能称整个 M4 完成。部分场景结束仍产生既有 ObjectDB/RID/资源泄漏输出，历史 `farm01-smoke2.log` 已有同类错误；本轮脚本无错误、玩法断言通过，资源生命周期问题留 POLISH-01 单独处理。

## 2026-09-18 · FARM-01 第二轮（肥料/品质/经验/伤害倍率/建筑扩容）

改动文件：`game_state.gd`（xp/等级/肥料/品质表/建筑等级/工具伤害倍率/扩容购买）、`domain/farm_state.gd`（fertilized 标记与双倍生长）、`core/interaction_system.gd`（播种自动施肥、收获品质+经验、拾取经验、升级提示）、`main.gd`（容量闸门、building 购买路由、_on_tool_hit 传倍率）、`hud.gd`（Lv 标题、品质行、肥料行、建筑扩容分区）、`surface_resources.gd`/`mine_floor.gd`/`first_map_scenery.gd`（swing 增 power 参数）、`tests/farm_checks.gd` 扩至 54 项。

- **肥料**：播种时若库存>0 自动消耗 1 施用（零新交互）；施肥夜 stage +2（连作惩罚仍优先生效），收获品质 roll 加成，收获/枯萎清除标记。存档随 farm tiles 往返。
- **品质**：普通/银/金，基础 3%/17%，施肥 10%/35%；银 ×1.5、金 ×2 折价；harvest_quality 双字典进存档，卖出即清零；背包品质行与收获 toast（"（银）/（金！）"）。
- **经验/等级**：收获得 crop exp、拾取产品 +5；每级需 100×当前级经验，每级体力上限 +10（energy_max），睡觉回满对齐新上限；状态栏标题显示 Lv。
- **伤害倍率**：镐/斧 tool_power 1.0/1.5/2.0 以 power 参数穿入 surface_resources/mine_floor/first_map_scenery 的 swing（roundi 保护，剑与怪物数值未动）。
- **建筑容量**：谷仓（牛羊）每级 4、鸡舍（鸡）每级 6，购买动物超容拒绝并提示先扩容；扩容金币+木材+石料（上限 3 级），商店动态显示容量与造价。
- **排错记录**：add_harvest 新旧重名导致 game_state 解析失败（删旧版）；interaction_system 里 `_notify_level` 误用未声明的 `hud`（改 game.hud）；字典字面量索引需显式 String 类型。
- 测试 54 项全 PASS；回归：默认 smoke、旧图 smoke、地图专项 152、持久化 write 10 + verify 9 全 PASS，0 脚本错误。截图 `work/art01/farm01-hud2.png`（Lv 标题）。日志 `work/art01/farm01-*2.log`。

## 2026-09-18 · FARM-01 第一轮（季节/轮作/体力/工具升级/动物经营）

改动文件：`data/crop_db.gd`、`core/game_clock.gd`（season_key）、`domain/farm_state.gd`、`domain/animal_state.gd`、`game_state.gd`、`core/interaction_system.gd`、`main.gd`、`hud.gd`、`art/equipment_models.gd`（TOOL_LABELS）、新增 `tests/farm_checks.gd`（40 项）。

- **季节与轮作**：farm.plant 增加可选 season 裁决（UI 层 can_plant_now 先行提示）；FarmTileData 记 last_crop，连作 rotation_pending 首夜不生长；wither_out_of_season(season_key) 在 _pass_day 换季分支调用，枯萎回裸土并 toast 株数。**坑**：GameClock.season() 返回中文显示名，与 crop_db 的英文键比对永远失败——曾让 smoke 的 plant/water/grow/harvest/sell 连锁失败；新增 season_key() 作为数据口径，显示名仅供 UI。
- **体力**：GameState.energy（上限 100），tool_energy_cost 基础值×等级系数；E 农事与镐/斧/剑挥动统一走 spend_tool_energy 闸门，不足即 toast 拒绝；睡觉回满，口粮 +35 生命&体力。状态栏加 ⚡ 金色条（对照参考 ui-hud 的心+闪电双条）。
- **工具升级**：锄/壶/镐/斧 1→3 级，造价金币+铜/铁（把矿场产出接进农场成长）；效果=体力消耗 ×1.0/0.6/0.3，水壶 2 级一次浇 3×3。商店改名"皮埃尔杂货店"并新增物资（饲料/口粮）、升级、动物三个分区，购买统一路由 _on_buy 的 kind 命名空间（animal:/upgrade:/feed/ration）。
- **动物经营**：饲料 8 币/份，对食槽按 E 消耗 1 份填一夜（新档预填，兼容既有 smoke 的 trough-fill/produce 断言）；好感 0–500：抚摸+30、吃饱+20、挨饿−10，≥400 次日双倍产出（确定性阈值，随机数只决定掉落位置）；商店购鸡/羊/牛入初始牧场，走同一存档/导航管线（_spawn_animal）。AnimalState 存档含 friendship。
- 测试 `farm_checks.gd` 40 项：宜种/拒种、换季枯萎、轮作延迟与恢复、体力扣除/闸门/口粮、升级双扣费与系数、购买动物、填槽消耗、产出与好感、双倍阈值、存读档经济闭环、NPC 土地保护。**排错记录**：setup 参数顺序（Rect2）、轮作断言漏算惩罚夜、升级造价断言、season 中文/英文键。
- 回归：默认 smoke、旧图 smoke、地图专项 152、农场 40 项全 PASS，0 脚本错误。截图 `work/art01/farm01-hud.png`（心+⚡双条状态栏）。日志 `work/art01/farm01-*.log`。

## 2026-09-18 · PLAY-01 第一阶段（行程实测与交通/节奏方案，未实施）

改动文件：无游戏代码；新增 [交通与节奏方案](../product/02-transport-pacing-plan.md)、实测脚本 `work/play01/travel_measure.gd`、日志 `work/art01/play01-measure.log`。

- 方法：沿 first_map_checks 已验收的四条主干路线途经点，按精确速度（步行 3.6 / 快跑 6.4 m/s）逐物理帧推进玩家位置，读 `state.time` 天数差+时刻差折算消耗。首版口径用 fposmod 在跨天时每 20 游戏时丢一天——修正为按天数差累计后复测。
- 关键数字：1 现实秒=8 游戏分钟，白天 13.8 游戏时（103.5 现实秒）。农场→镇 839m：步行 233s=1.55 游戏日、快跑 131s=0.87 日；农场→矿口 2065m：3.82/2.15 日；步行全天射程 373m。**"进城买卖"一天内无法往返，矿场实际不可达**——节奏断层量化坐实。
- 方案（待确认）：A 马车站六站（推荐主案）/ B 传送石碑（轻量）/ C 调时间节奏（C1 跑步消耗减半、C2 拉长一天、C3 提速）；推荐 D=A+C1。实施范围、验收标准已写入方案文档。

## 2026-09-18 · PERF-02 世界缓存 + 传送尖峰摊平

改动文件：`first_map_builder.gd`（缓存层）、`first_map_scenery.gd`（分块队列）、`animal.gd`（启动寻路错峰）、`tests/perf_checks.gd`（`_refresh(true)`）、`tests/first_map_checks.gd`（+6 项缓存/指纹测试）、`main.gd`（仅缓存探针后已还原，净改动 0）。

- **世界缓存**：`build()` 拆为 `_build_world()`（贵）+ 缓存层。指纹 = `res://scripts` 全部 .gd/.gdshader + 蓝图 JSON + `resources/models` GLB 的 md5 聚合 sha256；命中时载入 `world.scn`（PackedScene，186MB，载入 1.35s + 实例化 0.12s，209 顶层节点/3943 节点）并 `str_to_var` 还原数据字典。坑：`PackedScene.pack()` 只收录 owner 归根的节点，打包前须 `_set_owners()` 遍历（farmer_model.gd 有先例）。目录 `user://cache/willow_creek_valley_v1/`，`BREEZETOWN_CACHE_ROOT` 供测试隔离。
- **启动测量**（perf_checks BOOT=实例化→3帧，1600×1000）：重建 MISS 35.0s → 缓存 HIT **6.8s**。分解：缓存载入 1.5s、_ready 其余 0.8s（动物 0.17、地表资源 0.4、菜园种植 0.13、tiles/nav 0.07）、首帧 GPU 上传+管线预热 4.5s（引擎/驱动层，管线缓存已开启并落盘）。**<5s 目标在本机未达**，卡在 GPU 预热下限；世界构建开销（原 ~23s）已基本消掉。
- **动物启动寻路**：`set_navigation` 不再立即 `_pick_target()`（7 只×最多 8 次全图 A* = 7.2s），先直奔场内随机点（矩形内直线必在场内，安全），0.6–2.6s 错峰后恢复寻路挑选。
- **分块森林队列**：`_refresh(force_all=false)` 无头测试与显式调用保持同步整建；交互模式只同步建玩家所在块，其余按到玩家距离排队、每帧最多建 1 块。跨区传送尖峰从一次性 4.5s 变为每帧 ~0.5s 单块成本；perf/测试工具用 `_refresh(true)`。
- 验证：默认 smoke、旧图 smoke、地图专项 152（含缓存写盘/指纹一致/篡改失效/重建恢复/二次命中 6 项）、持久化 write 10 + verify 9、地图规则 21 全 PASS，0 脚本错误；缓存命中场景实机截图 `work/art01/perf02-farm-hit.png` 与全新构建渲染一致（draws 1455 vs 1427）。性能日志 `work/art01/perf02-perf-{miss,hit}.log`。

## 2026-09-18 · ART-02 画风差距收尾（牲畜可读性 + Q 版角色 + 图标 + 开花树）

改动文件：`ranch_models.gd`、`art/farmer_model.gd`、`art/tree_models.gd`、`first_map_builder.gd`、`tools/art/build_reference_ui.py` 及 `game/resources/ui/` 六枚重绘图标。另：本机（Windows）首次装好引擎 `tools/engine/Godot-4.7.2-stable/Godot_v4.7.2_win64*.exe` 与仓库内 Pillow Python `tools/python/`；二者均为下载缓存不入库（已进 .gitignore），后者由 embeddable Python + pip + pillow 装成。

- **牲畜可读性（①）**：初始化牧场其实已有 2 牛 2 羊 3 鸡在围栏内游荡，真实差距是奶牛白身+背脊小黑斑在俯视相机下与羊难以区分。改为 6 块暖棕大花斑（`#8a5a3f` 系）包裹体侧并盖过背脊，头部加棕斑、耳与角微放大；实机对照牛羊一眼可辨。
- **角色 Q 版（②）**：`HeadPivot` 整体 1.2×（含发与草帽）、双腿枢轴 Y 0.9×，`BODY_HEIGHT` 0.655→0.59 保持脚底贴地。头身比（含帽）约 1:2.5，动画关节路径不受缩放影响。
- **图标插画质感（③）**：`build_reference_ui.py` 手绘六枚（拳/镐/剑/树苗/围栏/口粮）改为 272×256 绘制后 LANCZOS 缩到 68×64，统一暖色描边 `#4d4337`、双阶明暗+高光；参考图裁切的四枚（壶/锄/斧/种）保持不动。
- **开花果树（④）**：`tree_models.gd` 新增 blossom 变体——`_oak` 叶簇色调整体切换粉色系（樱花式），冠层外围再缀 20 团深粉花团；`first_map_builder.gd` 农舍庭院 grove 前部加两株（`(-12.5,7)`、`(7,31)`，走既有道路/森林遮盖守卫）。花树是纯装饰 prop，不进砍伐/持久化系统。
- 验证（Windows + RTX 2060S，日志 `work/art01/art02-*.log`）：默认 smoke、旧图 `--reference-farm` smoke、地图专项 146 项、领域 49 项全部 PASS，0 脚本错误。固定 `--hour=11` 截图：`art02-farm.png`（出生点全景：Q 版角色+新图标+花树）、`art02-pasture2.png`（牧场牛羊鸡）、`art02-blossom2.png`（花树近景）、`art02-icons.png`（图标表）。
- 遗留：画风终验待用户实机确认；室内场景属 LIFE-01。

## 2026-09-17 · 画风对照第二轮（视觉对照 + 回归修复）

对照样例库（style-board / ui-hud / lake-dock）与实机逐项比对后改动：`tile.gd`、`cozy_landscape.gd`、`water_models.gd`、`hud.gd`。

- **修复两处 PERF-01 引入的视觉回归**（此前截图误判为正常）：①苗床木框旋转方向写反，田里出现横穿木条；②作物烘焙网格带 12 米容器偏移，被实例随机朝向绕原点甩出十几米，草坪散落大量南瓜/草莓。修法：木框按边缘方向旋转；烘焙后把顶点平移回原点再缓存。
- 草地着色器向参考图靠拢：色板加深加饱和，新增斜向修剪条纹与更明显的双色斑点。
- 水体更深更蓝（深度权重 0.5→0.62），湖面波纹笔触改细并贴近水色。
- 干土调暖（#7e5a3b / 垄 #654331·#735035）。
- HUD 对照 ui-hud：日期栏改为四段羊皮纸药丸（季节/日期/天气/时钟 + 粉红黄蓝图标点）；选中工具槽金光增强（4px 金框 + 9px 外发光）。
- 验证：默认 smoke、地图专项 146、领域全部 PASS，0 脚本错误。截图 `style3-farm.png`、`fix3-homestead.png`。
- 与参考图剩余差距（下轮候选）：牧区牲畜可见度、角色头身比、工具图标插画质感、室内场景。

## 2026-09-17 · PERF-01 第一轮（启动与绘制优化）

改动文件：`art_mesh.gd`（图元网格参数缓存）、`water_models.gd`（岸石并入共享网格 + 修一处潜在死循环步进）、`tile.gd`（视觉层重写：土壤/木框/作物网格按种类静态缓存，作物 MultiMesh 实例化，湿土换缓存网格）、新增常驻工具 `tests/perf_checks.gd`（启动耗时、分区帧时间分位、draw calls、内存、高分辨率）。

- 基线（M5 / 1600×1000 / 窗口）：启动 56.4s；农场 p50 16.8ms、draws 4607；传送后偶发 >1s 卡顿。
- 热点：①海岸线水岸石逐颗实例化（1542 个 320 顶点网格）；②每块耕格的作物逐格烘焙 ≈0.45s/格 ×64 初始格 ≈29s；③静态合并按实例 append 固定开销 ~0.9ms × 1.6 万实例 ≈14s。
- 优化后：**启动 56.4s→23.0s**（剩 ~20s 为冷启动世界构建，可用世界视觉缓存解决，留待第二轮）；**农场 draws 4607→2529**；农场/镇区/森林/果园/港口 p50、p90 全部在 16.7ms 帧预算内（60fps）；2560×1600 农场 p50 21.3ms（≈47fps）；内存 ~180MB。传送后的区块重建尖峰（单次 ~0.5–1.7s）仍在，属跨区传送场景，正常游玩按 64m 分块渐进加载。
- 验证：默认 smoke、地图专项 146、持久化两阶段 10+9 全 PASS，0 脚本错误；菜园实机截图视觉无损（见画风第二轮 `style3-farm.png`；当时截图 `perf01-garden.png` 已在清理中删除）。性能日志 `work/art01/perf01-run3.log`，命令见 `perf_checks.gd` 头注。

## 2026-09-17 · WORLD-01 第一轮（分块森林可交互与全量持久化）

改动文件：`first_map_scenery.gd`（重写：稳定 ID 注册表、swing/target_at、持久化、耕地避让）、`surface_resources.gd` 与 `mine_floor.gd`（to_dict/apply_state）、`main.gd`（scenery 成员、斧击路由、战利品通道、存档三新键、矿层恢复）、`core/interaction_system.gd`（chunk_tree 目标）、新增 `tests/world_persist_checks.gd`。

- 分块森林每棵树有稳定 ID（`forest:区块:格` / `orchard:行:列` 字符串，JSON 往返安全）；注册表驱动斧击：36 血、每击 18（两下砍倒，与地表树一致），破坏后重建该 64 米区块、释放占用、经 `tree_broken` 信号走与地表树相同的掉落通道（木材 4–7 + 30% 树苗）。
- 持久化采用**差异存储**：只保存玩家造成的移除列表，森林生成默认值保持确定性——存档体积不随森林大小增长。半砍的树血量不持久（重启回满，已记录为设计）。
- 存档新增三键：`surface`（全部地表资源+掉落物状态）、`forest`（移除列表）、`mine`（各层已破坏岩格/掉落/宝箱/营地/梯子旗标+当前层数）。读档在矿场时直接回到对应层与原位置；重复读档幂等。
- 环境树不覆盖已保存耕地：区块树放置避让 3×3 耕格（`farm_tiles`）；地表资源按存档重建后再执行田块/圈地冲突清理。
- 新增两阶段重启测试 `world_persist_checks.gd`（write/verify 两个独立进程，共用 BREEZETOWN_SAVE_ROOT）：砍树→掉木材、种树苗、耕种、矿场破岩→存档→**新进程**读档→树未复活/未重注册、树苗/耕地保留、矿层与岩格一致、双读档幂等，10+9 项全过。
- 回归：默认 smoke、旧图 `--reference-farm` smoke、地图专项 146、领域、地图规则全部 PASS，0 脚本错误。
- 遗留：矿场怪物重启后重新出现（守护者设计，宝箱旗标防重复领取）；半砍森林树血量不持久。


## 2026-09-17 · MAP-01 第一轮（逐区地形与装饰）

改动文件：`first_map_terrain.gd`（北岭主脉、瀑布峰体）、`water_models.gd`（`_cascade` 参数化瀑布并接入大图）、`first_map_definition.gd`（湖畔码头 dock）、`first_map_scenery.gd`（苹果树部件 + 果园行栽网格）、`first_map_builder.gd`（镇区/港口/NPC 农庄装饰、湖畔小船）、`first_map_checks.gd`（码头数 7、四条主干路线寻路检查）。

- 西北：7 座 62–114 米雪峰补足天际线；瀑布地标处 6 峰收口 + 两座侧峰，`_cascade` 从 24 米高五级跌入 north_creek，含泡沫条纹与阶侧岩。
- 果园：区块系统新增 apple 部件；果园区域 13 米世界对齐网格行栽（约 1300 株全园），避让水/路/建筑，登记占用与碰撞；随机林区跳过果园防重叠。
- 湖畔：lake_view 地标向东 17 米码头（walkway 渲染、水域碰撞扣除、可行走/不可耕作自动生效），尽头系小划艇。
- 港口：长栈桥系缆桩与货堆；深水栈桥尽头木吊车（桅杆/斜臂/拉索/吊钩），岸侧船桨浮标；吊车接入夜灯。
- 镇区：广场四边长椅朝喷泉、四角街灯、西侧两座条纹市集棚、东北告示板。
- NPC 农庄：谷仓南侧 38×24 米畜栏（避让道路自动留口）、双层干草捆、木桶、水壶、街灯；农舍周边 2600 簇草花，避让三栋建筑、全部耕地、道路与畜栏。
- 路线验证改为沿路途经点逐跳寻路（每跳 ≤250 米保分辨率，跨河只经桥）：农场→镇区→矿口、镇区→NPC 农庄、镇区→港口全部连通；镇广场中心为喷泉碰撞体，途经点改用边缘。
- 验证：地图专项 146 项（含新路线 4 项）、smoke 310 项、领域、地图规则全部 PASS，0 脚本/着色器错误。截图 `work/art01/map01-{waterfall,orchard,harbor,town-square,npc-farm,lake-pier}.png`。
- 遗留：homes 住宅区庭院未装饰；瀑布山地仍可穿行（沿既有矿山行为）；画面验收待用户。


## 2026-09-17 · ART-01 第一轮（农场近景）

改动文件：`first_map_builder.gd`（庭院装饰、大田着色、道具放置）、`cozy_landscape.gd`（花色调板、灌木团簇）、`tile.gd`（苗床木框、作物随机变化）、`landscape_models.gd`（新增干草捆/柴堆/邮箱）。

- 农舍周边 200×124 米庭院：约 5600 簇草花（密度随离舍距离衰减）、6 处花境、井边花环、12 处灌木群（不规则团簇 + 随机浆果）、14 株背景树（避让森林遮罩与道路）。
- 生活道具经 `_place_prop()` 统一放置：自动避让道路/建筑/菜园并登记障碍——柴堆、木桶、板条箱、邮箱、两根灯柱（接入夜灯）、双层干草捆、水壶、踏石。
- 苗床木框按"邻居未耕才显示"规则画边板，玩家后续开荒同样生效；相邻格耕开后边板自动隐藏。
- 大田改用犁沟条纹着色器（世界空间垄向 + 土块噪声 + 边缘磨损），9 块农田零额外面数；期间修复一处 GLSL 括号笔误导致的 headless 着色器编译失败。
- 验证（`work/art01/`）：地图专项 132 项、默认 smoke 310 项、领域、地图规则全部 PASS，0 脚本错误；实机采样 60 FPS。截图：`final-garden.png`、`final-homestead.png`（固定 `--hour=11`）。
- 画风验收仍需用户对照 [style-board](../art/reference/style-board.png) 评估；本轮未动建筑 GLB、角色与 UI，比例统一属后续轮次。


## 当前实际状态

默认地图 `willow_creek_valley_v1`，约 2598 × 2374 米。西南玩家、东北 NPC；建筑按图定位、使用实际尺寸。已接入地图、近景美术、HUD、农牧/商店/林业/十层矿场和基础存档。**整体画风仍未达到参考图，完整 V2 尚未完成。**

- 蓝图：`game/resources/maps/first_map_blueprint.json`；换算：`game/scripts/data/first_map_definition.gd`。
- 构建：`world_builder.gd` → `first_map_builder.gd`；地形：`art/first_map_terrain.gd`；森林：`first_map_scenery.gd`。
- 原图：`docs/art/reference/`；[地图说明](../maps/first-map.md)记录坐标、误差、资产生成流程。
- 模型：`game/resources/models/*.glb`；源文件：`art/3d/source/*.blend`；生成器：`tools/art/`。
- 农舍附近田地/资源可交互。大片田地多为地表表现；分块森林已可砍伐并差异持久化（WORLD-01）；多数服务建筑只有外观。
- 森林以 64 米区块加载附近 3 × 3 块，水岸碰撞/寻路计算有界；全图性能、远景、长时间体验仍待验证。

近期修复：GLB 顶点色、过高农舍/镜头截断、围栏挡路、北桥轴向与侧入口、桥栏碰撞、狭窄码头半径判断、NPC 农田保护、跨地图存档混用及高分辨率 HUD 缩放。

## 存档边界

- 大图：`user://saves/willow_creek_valley_v1/slot_1/`。
- 旧近景：`user://saves/slot_1/`，用 `--reference-farm` 启动。
- `SaveManager.select_world()` 选择目录；`MapRestore.plan()` 拒绝不兼容地图/大图无法识别来源的旧档，保持当前状态。这是隔离和拒绝，不是坐标迁移。
- 测试通过 `BREEZETOWN_SAVE_ROOT` 使用独立目录。
- `WORLD-01` 后存档已覆盖地表资源、掉落物、分块森林移除差异与矿层状态（岩格/宝箱/营地/梯子）；怪物重启后重新出现，半砍森林树血量不持久。

## 已核对的验证证据

2026-09-16 以下日志均有 PASS，无 `ERROR` / `SCRIPT ERROR`：

| 验证 | 结果 | 日志 |
|---|---|---|
| 比例、归属、建筑/桥梁、水岸、围栏、NPC 土地、存档隔离与矿场往返读档 | 132 项 | [first-map.log](../../work/first-map/validation/first-map.log) |
| 领域数据、经济、时钟、存档 | 49 项 | [core.log](../../work/first-map/validation/core.log) |
| 地图规则、寻路、迁移 | 21 项 | [map-domain.log](../../work/first-map/validation/map-domain.log) |
| 默认地图完整 smoke | 310 项 | [default-smoke.log](../../work/first-map/validation/default-smoke.log) |
| 旧近景 smoke | 265 项 | [legacy-smoke.log](../../work/first-map/validation/legacy-smoke.log) |
| 普通林业输入 | 12 项 | [forestry-input.log](../../work/first-map/validation/forestry-input.log) |
| 普通矿场输入 | 11 项 | [mine-input.log](../../work/first-map/validation/mine-input.log) |
| 资源导入 | 无脚本错误 | [import.log](../../work/first-map/validation/import.log) |

完整 smoke 与普通输入先通过；最后新增的 NPC 土地、存档隔离修复由随后重跑的地图专项、领域和地图规则检查覆盖。最后修复后未重复全部套件。

实机截图：[玩家农场](../../work/visual-slice/scaled-farm-final.png)、[全域导览](../../work/visual-slice/scaled-map-final.png)。[描图叠加图](../maps/first-map-trace.png)只用于原图对位。截图 FPS 属于短时采样，不构成性能验收。

## 运行命令

在仓库根目录执行：

```sh
# 默认真实比例地图
tools/engine/Godot-4.7.2-stable/Godot.app/Contents/MacOS/Godot --path game

# 专项验证，隔离存档
BREEZETOWN_SAVE_ROOT="$PWD/work/game-data/check" tools/engine/Godot-4.7.2-stable/Godot.app/Contents/MacOS/Godot --headless --path game --script res://scripts/tests/first_map_checks.gd

# 地图规则
tools/engine/Godot-4.7.2-stable/Godot.app/Contents/MacOS/Godot --headless --path game --script res://scripts/tests/map_domain_checks.gd

# 固定窗口与时间截图
tools/engine/Godot-4.7.2-stable/Godot.app/Contents/MacOS/Godot --path game --windowed --resolution 1600x1000 -- --hour=11 --shot="$PWD/work/art01/next.png"
```

资源导入使用 `--headless --editor --path game --quit`。Godot 可能在脚本报错后仍退出 0，必须检查日志。

## 本轮文档清理

按用户要求删除旧 2D 产品 PRD、架构契约、路线图、验收和执行准备共 5 份失效需求文档，移除 README 的旧需求入口。保留 V2 全文与参考图，更新与后续确认冲突的条款。历史 ADR、2D 执行/测试报告保留并标注其适用版本；旧任务状态不再驱动开发。
