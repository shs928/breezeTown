# 微风小镇 V2 · 任务板（续作唯一入口）

更新：2026-09-18（POLISH-02 输入层改造：InputMap 动作层 + 手柄支持，键盘行为不变）。上一提交 `5235526`；此前 `bf6b664` 已入库 ART-02 → STORE-02 与 POLISH-01 第一轮全部工作。

**下次接续方法**：读本文 → `git status` / `git log -3` 确认现场 → 从「下一批任务」按顺序取第一项执行。历史过程见 [接续记录](SUMMARY.md)，产品范围见 [V2 PRD](../product/01-product-prd-v2.md)，地图/画风规范见 [地图说明](../maps/first-map.md) 与 [Art Bible](../art/art-bible.md)。

## 已确认，不重复询问

1. Godot 4.7.2 / 3D；以用户 UI 与美术参考图（`docs/art/reference/`）为目标，允许破坏性改造，旧模型与布局不构成保留约束。
2. 地理基准 [first-map-scale.png](../art/reference/first-map-scale.png)，400 米 / 202 像素 ≈ **2598 × 2374 米**；X 东 Z 南，耕地格 2 米；建筑按图定位、用实际尺寸，不按图标轮廓定占地。
3. **西南玩家农场，东北 NPC 农庄**；出生、初始菜园、初始牧场在西南；东北土地不可开垦/围建。
4. V2 单机完整地图先行；联机 V2.5、独立服务器 V3.0。旧 2D 文档与其通过状态不适用本版本。
5. 可并行子智能体；资料能推定的事不问用户；影响布局/玩法范围的决定先给方案再实施。

## 当前基线（玩法回归通过，退出资源警告见下方）

- **ART-01 玩家农场近景**：庭院草花/花境/灌木/道具（柴堆、干草捆、邮箱、灯柱…）、苗床低木框（相邻格耕开自动隐藏）、作物随机错位高矮、大田犁沟条纹着色器。证据 `work/art01/final-garden.png`、`final-homestead.png`。
- **MAP-01 逐区地形**：西北雪山主脉 + 溪源五级瀑布；果园 13 米行栽苹果树（分块加载）；湖畔码头+划艇（第 7 个 dock）；港口吊车/系缆桩/货堆；镇广场家具与市集棚；NPC 农庄畜栏与庭院。证据 `work/art01/map01-*.png` 六张。
- **WORLD-01 森林与持久化**：分块森林稳定 ID 可砍伐（破坏后重建区块、统一掉落通道）；存档新增 `surface`/`forest`/`mine` 三键；读档回矿层；环境树避让已存耕地。两阶段重启测试 `tests/world_persist_checks.gd`（write/verify 两个独立进程）。
- **PERF-01 第一轮**：启动 56.4→23.0s；农场 draws 4607→2529；五区域 60fps（M5/1600×1000，p50/p90 在 16.7ms 预算内）；常驻采样工具 `tests/perf_checks.gd`。
- **画风第二轮**：草地饱和色板+修剪条纹、水更深蓝、波纹细化、干土调暖、HUD 日期栏四段药丸、选中槽金光；并修复 PERF 引入的两处回归（木框方向、作物烘焙偏移散落）。证据 `work/art01/style3-farm.png`、`fix3-garden.png`、`fix3-homestead.png`、`style2-dock2.png`。
- **ART-02 画风差距收尾（2026-09-18）**：①奶牛改暖棕大花斑（体侧+背脊，俯视相机下一眼可辨牛/羊）；②角色头身比 Q 版（头含帽 1.2×、腿 0.9×，`farmer_model.gd` `BODY_HEIGHT` 0.59）；③工具图标重绘为 4x 超采样手绘风（`build_reference_ui.py`，拳/镐/剑/树苗/围栏/口粮，参考裁切四枚不动）；④农舍门前与牧场门侧各一株开花果树（樱花式粉冠，`tree_models.gd` blossom 变体）。证据 `work/art01/art02-{farm,pasture2,blossom2,icons}.png`。
- **PERF-02 世界缓存 + 传送尖峰摊平（2026-09-18，Windows/RTX 2060S）**：`first_map_builder.gd` 按指纹缓存 root 场景（PackedScene 186MB，`user://cache/`，`BREEZETOWN_CACHE_ROOT` 可覆盖）与数据字典（var_to_str 往返）；指纹=脚本/蓝图/GLB 的 md5 聚合，任何构建输入变化即失效。启动（实例化→3帧）35.0s→**6.8s**（缓存载入 1.5s + 游戏代码 0.8s + 首帧 GPU 预热 4.5s，引擎层下限）；<5s 目标在本机受首帧 GPU 预热限制未达。动物启动寻路改为错峰延迟（省 7.2s）；森林分块队列化每帧最多 1 块（跨区传送尖峰 4.5s→单块 ~0.5s；`_refresh(true)` 供测试/工具同步整建）。区域 p50/p90 均在 16.7ms 预算内（draws 1810 vs 基线 1814，缓存场景渲染一致）。证据 `work/art01/perf02-*`。
- **PLAY-01 第一阶段（2026-09-18）：行程实测 + 方案已成文**。引擎内实测六条路线：农场→镇 839m（步行 1.55 游戏日/快跑 0.87 日）、农场→矿口 2065m（3.82/2.15 日）；白天预算 13.8 游戏时（103.5 现实秒），步行全天射程仅 373m——"进城买卖"目前一天内无法完成，矿场实际不可达。**交通（马车站）+ 时间节奏（跑步消耗减半）组合方案已写入 [交通与节奏方案](../product/02-transport-pacing-plan.md)，待用户选择后实施**。
- **FARM-01 第一轮（2026-09-18）：农牧经营闭环**。①季节：播种按 crop_db 宜种季节裁决（UI 提示），换季时不合季作物枯萎回裸土；②轮作：收获记录 last_crop，连作首夜不生长（+1 天），换茬恢复；③体力（新系统）：锄2/种0.5/浇1/镐2/斧2/剑1 点，归零拒绝动作，睡觉回满、口粮+35（心+⚡双条状态栏）；④工具升级：锄/壶/镐/斧 1→3 级（金币+铜/铁，商店办理），体力消耗 ×1.0/0.6/0.3，水壶 2 级一次浇 3×3；⑤动物经营：饲料经济（商店 8 币/份，E 填槽，新档预填）、好感 0–500（抚摸+30/吃饱+20/挨饿−10），≥400 次日产出翻倍，商店可购鸡40/羊90/牛150 入住初始牧场；大片田地经营规则＝体力即开荒上限（满体力 50 格/日）。新增 `tests/farm_checks.gd` 40 项全 PASS。证据 `work/art01/farm01-*`。
- **FARM-01 第二轮（2026-09-18）：M2/M3 收尾**。①肥料（商店 8 币）：播种时自动消耗，施肥作物每个浇水夜多长一阶，收获品质更好；②品质：收获按施肥与否 roll 普通/银/金（3/17% → 10/35%），银 ×1.5 金 ×2 折价，背包与收获 toast 显示；③经验/等级：收获得作物 exp、拾取产品 +5，每 100×等级升一级，每级体力上限 +10（状态栏显示 Lv）；④工具伤害加成：镐/斧等级倍率 1.0/1.5/2.0 穿入地表资源/森林/矿岩三处受击；⑤建筑容量与升级：谷仓住牛羊每级 4、鸡舍住鸡每级 6，购满容量拒绝并提示，商店扩容（金币+木材+石料，上限 3 级）。farm_checks 扩至 54 项全 PASS。
- **FISH-01 第一轮（2026-09-18，历史基线）**：恢复中断的钓鱼草稿并修复解析错误；六种淡水鱼，湖泊/河流独立鱼池，海域不再误判成河流。`0` 装备鱼竿，E/空格/左键抛竿和提竿，咬钩后按住收线、松开放线；张力过高、持续松线或超时会失败。每次有效抛竿消耗 5 体力，成功仅入包/发事件/加通用经验一次，鱼获可出售与存档。移动、转身、换工具、Esc、面板、跨天、读档、切图取消；拒绝的读档保留现场。鱼漂与水域判定共用采样点，桥面不可落漂。专属张力/进度 HUD，快捷栏鱼竿显示 `0`。商店改为可滚动货架，出售/关闭固定可见。第一轮未含的条件、品质和独立成长已由第二轮补齐；海钓仍未实现，不标记完整 M4 完成。
- **FISH-01 第二轮（2026-09-18）**：鱼池按水域/季节/天气/时段筛选，含跨午夜，鱼类带稀有度与 `steady/dart/surge` 行为；独立钓鱼等级 1–10，成功获得 `12×难度` 经验，升级需 `100×当前等级`，10 级封顶。等级收益限定在钓鱼会话：10 级咬钩窗口 +0.45 秒、收线进度 +18%、张力增长 -15%，一直按住仍会失败。品质分数为张力保持在 `[0.2,0.8]` 的时间比例 + `0.04×(等级-1)`，银阈值 0.82、金阈值 1.14，优秀控制从 5 级可获金品质；售价普通 1×、银 1.5×（逐条向下取整）、金 2×。`sale_total()` 统一商店估价与卖出。新增 `fish_quality/fishing_level/fishing_xp` 存档字段，旧档默认零品质/1 级/0 经验，异常数量和品质归一化且不修改输入字典。背包改为“物品/鱼类”两个可滚动页，显示鱼类条件、当前可钓状态、品质、价格与技能。
- **天气与日切（FISH-01 第二轮）**：七日天气为晴/多云/雨/晴/晴/暴风雨/多云，冬季雨与暴风雨转为雪；自然日切和睡觉更新，读档保留有效的已存天气。`_advance_world_time()` 按每天拆分时间推进，确保大时间步内每一天的全世界结算均执行。天气已用于鱼池；天气视觉及通用农场降雨效果未实现。
- **GATHER-01 野外采集（2026-09-18，LIFE-01）**：新增 `data/forage_db.gd`（14 种植物与海贝的唯一数据源：栖息地/季节/天气/权重/稀有度/造型）与 `forage_resource.gd`+`forage_resources.gd`（无碰撞视觉节点 + 刷新管理器，对应 PRD ResourceNode 的 can_harvest/harvest/respawn）。①栖息地六类：森林=forest 区、果园=orchard 区、镇区=town 区、湖畔=lake 区外环 16 米且邻水 9 米、海岸=harbor 区邻水 11 米、山地=mine 区外扩 24 米∪瀑布 70 米半径；NPC 农庄、耕地、牧场、道路、水面、码头均拒绝落点，株间距 ≥2.6 米，全场上限 90 株。②刷新：开局 7–10 株，之后每天 4–7 株（按日确定性播种 `day*7919+137`），换季先清理不合季物种并 toast 株数；天气仅影响当日生成池，不影响已落地植株。③交互：任何工具下 E 徒手采集（半径 2.3 米，金环聚焦 + “E 采集 X · N 币[·稀有度]”提示），+5 通用经验；工具目标/钓点优先于采集物。④经济：`state.forage` 库存、`sale_total()`/`sell_all_harvest()` 统一折价与卖出、背包新增“采集”区。⑤存档：世界侧 `forage` 键（节点+季节，读档丢弃不合季物种、重复落点去重）+ 经济侧 `forage` 键（旧档清零、未知物种与脏数值归一、不改输入字典）。采集物 1.9× 造型基准保证俯视相机可辨。专属采集等级/图鉴页与制作配方联动未实现。
- FISH-01 回归（历史）：钓鱼规则 275、钓鱼经济 77、天气 31、真实场景/输入/存档/出售与多日结算 104、农场 54、HUD 布局 22、原领域数据及新旧地图 smoke 均 PASS；1600×1000 与 1280×800 渲染各 109 项 PASS，证据 `work/fish02/`（第一轮 `work/fish01/` 保留，不代替第二轮结果）。
- GATHER-01 回归：采集领域 138、采集场景（真实地图落点规则/确定性日切/E 采集/存读档/换季清理）71–91、钓鱼规则 275、钓鱼经济 77、天气 31、钓鱼场景 104、农场 54、地图 152、新旧地图 smoke 全 PASS，0 脚本错误；1600×1000 与 1280×800 渲染各 PASS，采集物聚焦截图与背包“采集”区已复核，见 `work/gather01/`。场景检查退出仍报既有 `ObjectDB`/渲染资源泄漏，留 POLISH-01。
- **NPC-01 第一轮（2026-09-18，LIFE-01：日程/对话/送礼好感）**：新增 `data/npc_db.gd`（人设唯一来源）、`npc.gd`（Q 版造型+日程+踱步）与 `tests/npc_{domain_,}checks.gd`。①四位村民：皮埃尔（杂货店主，商店⇄镇广场）、玛尔妮（北岭牧场主，谷仓⇄农舍）、巴特（铁匠，铁匠铺⇄酒馆）、老王（渔夫，湖畔⇄酒馆⇄广场住宅）；日程为左闭右开时段→锚点（覆盖 6:00–30:00，跨午夜折算），锚点=landmarks 键或 `site:建筑id`（解析到建筑 door），带门侧 offset 站位（共 13 处，皮埃尔 (3,1.2)），踱步半径 1–3 米，70 米外休眠省开销；无碰撞体、不进寻路。②交谈：E（2.2 米）开对话面板（姓名/身份/十心/台词/送礼/离开），初见问候、之后按好感三档（<300/<700/≥700）闲聊，每日首聊 +8。③送礼：面板内送礼列表=六族持有物品（收获/产品/鱼获/采集/矿石/林业），每天限一份；喜好四档 钟爱+60/喜欢+30/普通+15/讨厌−30，扣一件实物（品质计数先普通后银金），反应台词进对话框，好感 toast。好感 0–1000（十心），`npc` 存档键（friendship/talk/gift 三表，旧档清零、未知 id 忽略、脏值夹取、不改输入）。④优先级：村民焦点低于门点（shop/cottage/mine）与工具/采集目标，锚点偏移保证不堵商店门（场景含"NPC 在门边时商店仍可打开"断言）。任务/特殊事件/礼物信件未实现。
- NPC-01 回归：领域 159、场景 40（锚点解析、日程切换、对话门控、送礼扣件、存读档、堵门保护）全 PASS；first_map 152、farm 54、钓鱼 275/77/104、天气 31、采集 138、core、新旧 smoke（堵门修复后复跑）全 PASS，0 脚本错误；1600×1000 与 1280×800 渲染各 42 项 PASS，对话框与送礼面板截图已复核（`work/npc01/npc-{1600,1280}.png`、`-gift.png`）。场景退出仍报既有 ObjectDB/渲染资源泄漏，留 POLISH-01。
- **QUEST-01 NPC 委托任务（2026-09-18，LIFE-01）**：新增 `data/quest_db.gd`（八项委托唯一来源）与 `tests/quest_{domain_,}checks.gd`。①两类委托：收集交付（凑 N 件指定物品回交付人处交，覆盖作物/鱼获/采集/矿石/林业五族：皮埃尔萝卜→沙丁鱼、玛尔妮鸡蛋→木材、巴特铜矿→煤炭、老王鲤鱼）与传话（老王捎话玛尔妮，与目标交谈自动完成）；每人一条两段链，`requires` 前置完成后解锁，链内同 giver、无环（领域测试校验）。②对话面板集成：与村民交谈时出现"接受委托：X"按钮（可接委托）、"交付：X（x/y）"按钮（进行中收集委托，未凑齐禁用）；交付扣实物（品质计数对齐，复用 remove_items）、发金币+好感（夹 1000 上限）、答谢台词；传话在目标对话中自动完成并 toast 奖励。③可见性：右上角追踪药丸常显进行中委托与进度（金额栏下方 y=170），背包顶部"任务"区列进行中/已完成，凑满时 item_added 触发一次性"委托可交付"toast（`_quest_toast_done` 防重复）。④存档：economy 侧 `quests` 键（accepted/completed 日戳），旧档为空、未知 id 忽略、脏值夹 1000000、不改输入；`count_item()/remove_items()` 六族统一计数扣件（送礼 remove_gift_item 改为其单件包装）。⑤顺手修复：smoke 的 sell/sell-ranch 断言自 FARM-01 起按固定 28/42 币断言，但施肥收获品质随机（银 35%/金 10%），约半数进程会失败——改为按 `harvest_quality` 实际品质计算期望值，消除既有 flake。每日重复委托/任务物品奖励/特殊事件未实现。
- QUEST-01 回归：领域 135、场景 31（对话委托入口、接受/进度/交付/传话、跨 giver 防护、存读档）全 PASS；npc 159/40、farm 54、钓鱼 275/77/104、天气 31、采集 138、core、first_map 152、新旧 smoke（flake 修复后复跑）全 PASS，0 脚本错误；1600×1000 与 1280×800 渲染各 34 项 PASS，追踪药丸/委托按钮/背包任务区截图已复核（`work/quest01/quest-{1600,1280}.png`、`-inventory.png`）。
- **PERF-03 走路尖峰修复（2026-09-18，Windows/RTX 2060S）**：定位并修复"走路时每隔几十米冻结 1.8–4.5 秒"的主线程卡顿。根因链：玩家移动→森林区块加载/卸载→逐树 `occupy/release_resource` bump `navigation_revision`→任意动物空闲到期 `find_path`→`_ensure_grid` 全量重建 ~160×160 格（每格线性遍历全部障碍+资源占地，越东资源越多越慢）。修复：①`map_data.gd` 障碍/资源 16 米空间哈希索引（is_walkable 从 O(全表) 降为 O(邻域)，全部调用方受益）；②`world_navigation.gd` 网格失效改事件增量刷新（occupy/release/add_pasture 记 (x,z,radius) 事件，只重算受影响格子）+ 锚点量化 64→160 米 + 局部网格 2 米格。走路模拟（1.6km 往返 19260 帧）：24 次 >150ms 尖峰/最大 4533ms → **0 尖峰/最大 72ms**。回归 first_map/core/world_persist 全 PASS。
- **INDOOR-01 室内第一轮（2026-09-18，LIFE-01：Door → SceneTransition → Interior）**：新增 `data/interior_db.gd`（房间唯一数据源：尺寸/出生点/出口/服务点/文案）与 `interior_room.gd`（地板/墙体/家具/碰撞/服务聚焦环构建）。①四房带真实服务：**玩家农舍**（床=睡觉+自动存档，复用 `_sleep`）、**皮埃尔杂货店**（柜台开商店 UI）、**酒馆**（吧台套餐 30 币=体力回满+生命+60，`GameState.buy_meal`）、**医院**（病床治疗 50 币=生命回满，满血/缺币拒绝，`GameState.buy_treatment`）；均走 `_purchase` 统一金币事件。②场景切换：室外门点统一 `building_door` 焦点（2.4 米，仅限室内表内建筑）→ `main._enter_building/_exit_building` 走 `hud.fade_transition`；房间建在远端展示坐标（z=9000），玩家边界改中心化超椭圆（`player.set_bounds` 增 center 参数，默认原点不改变既有行为）；室内时地图标记钉在建筑门口、时间照常流动、水面判定/水域碰撞重建门控关闭。③存档：`indoor` 键（房间 id），读档原位回到同一房间；矿场/室内互斥处理。④语义变化：室外 shop/cottage 门点 E 从"直接开店/睡觉"改为"进室内"，服务在柜台/床铺办理；smoke 与 first_map 断言同步改写（npc 堵门守卫断言映射为"门点优先于对话、柜台办服务"）。**布局与门牌为暂定值**（见"后续需要确认"）。
- **INDOOR-02 室内第二轮 + PROCESS-01 加工第一轮（2026-09-18，LIFE-01）**：新增 `domain/machine_state.gd`（EMPTY→PROCESSING→FINISHED→收取，`can_start` 按目录序取首个原料齐全配方，to_dict/from_dict 脏配方清洗）；`data/recipe_db.gd` 填充首批配方并接进玩法（熔炉：铜矿×4→铜锭 2 游戏时、铁矿×4→铁锭 3 游戏时；奶酪压榨机：牛奶×1→奶酪 8 游戏时；蛋黄酱机：鸡蛋×1→蛋黄酱 4 游戏时），`requirements_text()` 生成原料提示；ItemDB 新增 铜锭 25/铁锭 45（minerals）与 奶酪 32/蛋黄酱 12（products），`GameState.add_mineral` 统一产出事件。①三个新室内：**铁匠铺**（熔炉+铁砧+煤堆+武器架，巴特值守）、**农场谷仓**（奶酪压榨机+干草/食槽）、**农场鸡舍**（蛋黄酱机+巢箱，房间 id 对齐建筑 id `player_barn`/`player_coop`）。②机器交互：E 空转提示原料、投入自动开始、加工中提示剩余游戏时、完成提示与产出指示物（`refresh_machines`）、收取回 EMPTY；加工随世界时间推进（跨天/睡觉大步同样生效），完成时 toast。③**NPC 店内值守**：日程锚点为 `site:<房间id>` 的村民进屋时站在 `npc_spot` 面向门口（皮埃尔守杂货店柜台、巴特守铁匠铺、老王晚间守酒馆），皮埃尔锚点从 `shop_door` 迁移为等价的 `site:shop`；值守期间 NPC 临时改挂 `_interior_root`（否则被隐藏的 `_outdoors` 连带隐藏——排错要点），出门挂回并 `snap_to_schedule` 回日程位置；室内 NPC 对话焦点优先于服务点。④存档：`interiors` 键（"房间:机器"→状态），旧档缺省为空转、未知配方清洗；未知键忽略。⑤经济意义：矿石/牛奶/鸡蛋获得增值加工链（锭、奶酪、蛋黄酱均可出售或送礼），工具升级仍用原矿（暂定）。
- **STORE-01 工作台与仓库第一轮（2026-09-18，LIFE-01）**：①**木工坊室内**（style carpenter：工作台机器+木料堆+锯木架），工作台两配方（PRD 13 示例落地）：木材×10+石料×5→**宝箱**（2 游戏时）、木材×6→**肥料×2**（1 游戏时，接进 state.fertilizer）；宝箱/肥料以特殊物品入 ItemDB 供配方校验，产出走 `_grant_machine_output` 特判（chests_ready / fertilizer 计数）。②**宝箱放置**：E 收取后 `chests_ready` 计数，面向空地按 E 放置（`tiles.is_open`+非耕格门控），放置登记 `occupy_resource` 阻耕作；可"收起宝箱"返还计数重新放置（仓库内容不受影响）。③**农场共享仓库**：所有宝箱连通同一仓库（`GameState.warehouse`，六族物品整批存取 `warehouse_deposit/withdraw`，事件口径与背包一致），新 HUD 面板（`chest_open` 入 `modal_open`、逐行 存入/取出 按钮、收起/离开），宝箱按 E 即开。④存档：economy 侧 `warehouse`（未知物品/脏值清洗）+`chests_ready`；世界侧 `chests` 键（仅位置数组，重建时重新登记占地）。⑤截图参数新增 `--place-chest`。
- **STORE-02 仓库扩容/丢弃/分类 + 加工第二辈配方（2026-09-18，LIFE-01）**：①**仓库容量**：默认 300 件（`warehouse_capacity`，存档归一下限 300），超容存入拒绝并提示；工作台新配方 木材×15+石料×10→**仓库扩容**（4 游戏时，+300，可重复）。②**丢弃**：仓库面板逐行"丢弃"按钮两步确认（首点变"确认丢弃？"），`warehouse_discard` 清空该物品存量。③**分类**：仓库面板按 收获/产品/鱼类/采集/矿石/林业 六族分组显示并显示"仓库 x/y 件"容量条。④**加工第二辈**：酒馆**厨房灶台**（小麦×3→面包 24 币，3 游戏时）、谷仓**织布机**（羊毛×3→毛毯 48 币，6 游戏时）；面包/毛毯入 products 族（可售可送礼）。⑤多配方机器选择暂定"按目录序取首个原料齐全者"（熔炉铜优先铁、工作台宝箱优先扩容），配方选择 UI 列入后续。
- **POLISH-01 第一轮：天气视觉与降雨浇地（2026-09-18）**：①**雨雪粒子**：`main._setup_weather_fx()` 建相机跟随挂架（y+9，排放盒 ±22 米），雨=900 条细长雨丝（快速下落+微风斜落），雪=420 片慢速飘落白色粒子（billboard）；`_apply_daylight` 按天气/室内/矿内门控发射与可见性。②**雨天氛围**：天空向灰蓝压暗 45%、环境光 ×0.82、阳光 ×0.45、补光 0.14。③**降雨自动浇地**：日切结算（`_apply_rollover`）时 `GameClock.is_rainy()`（rain/storm；雪不浇）→ `tiles.water_all()` 浇灌全部已种植耕地并 toast 株数——睡觉与自然日切一致生效。④截图参数 `--weather=rain|snow|...`。⑤新增 `tiles.water_all()`。证据：`work/art01/polish01-rain-1600.png`（雨天农田）；weather 31→40（is_rainy 规则/循环浇灌日/冬季雪不浇）、indoor 场景 168→176（晴不浇/雨浇/雪不浇三段日切）；回归 core/npc 159+42/quest 135+31/farm 54/forage 138/fishing 77/first_map 154/smoke 全 PASS，0 脚本错误。剩余：季节地表变化、雨声音效、雪地积盖、设置/手柄。
- **POLISH-02 第二轮：输入动作层与手柄支持（2026-09-18）**：新增 `core/input_actions.gd`（`main._ready` 最先注册，幂等；每个键盘键同时绑 keycode+physical_keycode，兼容测试注入）。①18 组动作：移动（WASD/方向键/左摇杆，死区 0.3）、跑（Shift/L3）、交互（E/A）、使用工具（空格/X）、吃口粮（Q/Back）、换种子（R/十字键下）、背包（Tab/Y）、地图（M/十字键上）、快存 F5、快读 F9、工具循环（LB/RB）、缩放（滚轮/十字键左右）、工具槽 1–0；ui_cancel 用内置（Esc/B）。②`player.gd` 移动改 `Input.get_vector`（相机相对方向不变），`main.gd` `_unhandled_input` 全部动作化（模态白名单=地图/关闭/背包），左键点击抽为 `_on_world_click`，钓鱼收线输入动作化。③手柄 UI 导航：商店/仓库/对话/升降机面板打开时**仅在连接手柄时**抓取首个可用按钮焦点（键盘 Space 行为不变）。④键盘行为零变化：所有按键驱动测试（first_map 154/smoke/npc/quest/indoor 176→180）全 PASS；新增手柄注入检查（A 进出门农舍 4 项）。剩余：设置菜单与键位重绑 UI、手柄提示文案。
- **SETTINGS-01 设置面板（2026-09-18，POLISH-01 第三轮）**：新增 `core/game_settings.gd`（ConfigFile 持久化 user://settings.cfg；测试环境 BREEZETOWN_SAVE_ROOT 非空时不落盘、启动不应用键位——防止改键破坏 headless 按键注入）与 `tests/settings_checks.gd`（13 项：存储往返/重绑联动/恢复默认/脏值夹取）。HUD 设置面板：显示模式（窗口/全屏）、垂直同步、主音量滑条（AudioServer 主总线）、13 项键位重绑（点击→按新键→Esc 取消，重绑保留手柄绑定）、恢复默认键位；`settings_open` 入 `modal_open`/`dismiss_panels`。入口：F10 / 手柄 Start / `--open-settings` 截图参数。证据 `work/art01/settings01-panel-1600.png`；settings 13 / indoor 187 / 回归 10 套 + smoke 全 PASS，0 脚本错误。
- **BUILD-01 构建导出（2026-09-18）**：①`export_presets.cfg`（Windows Desktop，内嵌 PCK 单文件 exe，S3TC/BPTC 纹理，icon.png+产品元数据）；②`tools/build_windows.sh` 构建链：全量烘焙世界（`scripts/bake_world.gd`，~11 秒，产物 `game/prebuilt/` 不入库）→ 导出 `build/BreezeTown.exe`（~171MB）；③`first_map_builder` 导出包预置世界：`OS.has_feature("template")` 时加载 `res://prebuilt/`（只读、不写用户缓存），**首启 27 秒世界重建消除**；④游戏图标：截取农场景 256px（`scripts/tools/make_icon.gd`）。**排错记录（引擎 API 逐个验证）**：此 4.7.2 构建的 PackedByteArray 无 md5_text/sha256_buffer/hex_encode、String 无 utf32_to_string、无 HashContext——字节级哈希全不可用；FileAccess.get_md5 与导出 PCK 内文件不兼容；导出 PCK 不含 .glb 源（只含导入产物）→ GLB 不能进运行时指纹；最终指纹=路径+文件长度（.gd/.json 两环境逐字节一致），而**导出包预置世界不做运行时指纹校验**（构建链保证每次导出前重烘，校验在两环境 .gd 字节形态有差异时必误拒——headless 导出脚本编译后与源树长度不同）。导出路径必须是绝对路径（相对路径相对 game/ 解析且不自动建目录）；`OS.has_feature("export")` 特性名错误，应为 `"template"`。**验证**：导出包清空用户缓存后 `WORLD_PREBUILT HIT 209 top nodes`+`SMOKE_RESULT PASS`+无用户缓存写入；窗口模式启动渲染完整（`work/art01/build01-windowed.png`）；开发环境回归 first_map 154/core/indoor 187/settings 13/smoke 全 PASS。剩余：退出段段错误（既有资源生命周期问题 POLISH-01 备查项）、Steam 管道部署、其他平台。
- **POLISH-04 退出段错误排查与发布形态定型（2026-09-18）**：症状=release 模板导出包退出确定性堆损坏（0xC0000374，WER 故障模块 ntdll）；debug 模板/dev 引擎正常；headless（Dummy 渲染器）也崩→非渲染问题。**逐层排除**：子树预释放（HUD/天气/灯光/玩家/地表全试）、静态资源缓存清空、脚本导出模式三档、TAA/MSAA/SSAO/粒子、4.7.1 模板（同样崩）、world.scn 最小复现探针（纯净工程仅 load+instantiate 游戏 world.scn 即崩）。**期间实锤并修复一个真实缺陷**：`FileAccess.get_as_text()` 在 release 模板下触发退出堆损坏（10 行探针 3/3 复现；get_buffer+get_string_from_utf8 / get_as_utf8_string / get_line 均无此问题）——save_manager（存档读）与 first_map_builder（指纹/缓存读）共 5 处替换。**但主触发仍存在**：同为 build() 内、对二进制布局敏感（同一处代码加两个环境变量判断即翻转），属引擎原生缺陷（4.7.1/4.7.2 双版本复现，已具备上报素材）。**发布决策**：构建链改用 **debug 模板导出**（`--export-debug`）——退出 5/5 干净（exit 0）、headless smoke PASS、实机 128.7 fps 与 release 同级（debug 模板 GDScript 速度相同）；release 模板留待引擎升级后再切。退出时仍有 ObjectDB/RID 泄漏告警（资源缓存持有，进程正常退出，POLISH-01 备查）。探针代码已清理（exit_bisect/split_payload/leak_probe、main.gd 阶段门）。
- **POLISH-05 季节地表视觉第一轮（2026-09-18）**：①**地面雪**：`cozy_landscape.gd` 地面着色器新增 `snow_amount` uniform（噪声化雪色混合，田野/道路覆雪、作物穿雪而出）；②**地面草色**：`season_tint` uniform（秋干黄 1.06/0.96/0.70、夏深绿、春鲜嫩）；③**环境色调层**：`_apply_daylight` 在日光插值与雨天压暗之间叠加季节乘子（冬冷蓝 bg/amb/sun、秋暖金、春微鲜、夏中性，`art/season_visuals.gd` 纯函数调色表）；季节变化时 `_apply_season_visuals` 重设 uniform（材质从世界 MetricTerrain 节点取，缓存/预置场景同样适用）。④截图参数新增 `--day=N`（切天数=切季节，天气按日历联动）。⑤树冠/灌木季节重着色（foliage_tint 已备）留下一批。证据：`work/art01/polish05-season-{1,29,57,85}.png`（春/夏/秋/冬同机位对比，冬季雪盖+秋季干黄+作物穿雪）；season 18 / indoor 192；回归 13 套 + smoke 全 PASS；导出包重建后 PREBUILT 命中、退出 0。

## 下一批任务（按顺序执行）

| 顺序 / ID | 状态 | 具体工作 | 验收标准 |
|---|---|---|---|
| 1 · PLAY-01 | **方案待用户确认** | 第一阶段完成（实测+方案，见上方基线与 [方案文档](../product/02-transport-pacing-plan.md)）。第二阶段：按用户选定方案实施交通/节奏调整。 | 站间耗时实测并写入方案档；六站全部可达；存读档含解锁状态；smoke/地图专项回归通过；用户实机验收手感。 |
| 2 · LIFE-01 | **进行中** | FISH-01 两轮、GATHER-01、NPC-01、QUEST-01、INDOOR-01/02、STORE-01/02（工作台+仓库+扩容+加工两辈）已完成。下一步候选：POLISH-01（天气视觉/降雨浇地/音效/设置与手柄）、配方选择 UI、背包格子化、LEGEND-01 图鉴。海钓另列后续范围，不把淡水钓鱼两轮等同完整 M4。 | 每项具备数据、交互、失败处理、存档与玩法验证；建筑外观 ≠ 服务完成。 |
| 3 · POLISH-01 | **进行中** | 第一轮（天气）与第二轮（输入层）完成：雨雪粒子、降雨自动浇地、InputMap 动作层与手柄支持（键盘行为不变）。第一轮（天气）、第二轮（输入层+手柄）、第三轮（设置面板：显示模式/垂直同步/主音量/键位重绑，ConfigFile 持久化）完成。第一二三轮（天气/输入+手柄/设置面板）完成；BUILD-01 构建导出完成；POLISH-04 退出堆损坏排查完成——发布形态改 debug 模板导出（退出干净+性能同级），get_as_text 缺陷已修。季节地表第一轮完成（冬雪+秋黄+环境层）。剩余：树冠重着色、音效、长时间回归、上报引擎 issue。 | 场景/存档回归、目标设备性能与真人体验证据齐全后判定首图完成度。 |

已完成批次：ART-02、PERF-02、PERF-03、PLAY-01 第一阶段、FARM-01 两轮、FISH-01 两轮、GATHER-01、NPC-01、QUEST-01、INDOOR-01（2026-09-18）见上方基线；画风终验与交通方案仍待用户确认。PLAY-01 尚无选择时，可继续 LIFE-01 已确定范围。

## 长期 / 备忘

- **NET-01（V2.5 BACKLOG）**：联机与专用服务器；依赖单机世界状态、存档、首图玩法稳定；届时另行设计网络契约与真实多机验收。
- MAP-01 遗留：homes 住宅区（西区 5 栋）庭院未装饰；瀑布山地可穿行（沿既有矿山行为，如需阻挡须专门设计）。
- 已记录的设计决定：矿场怪物重启后重现（宝箱旗标防重复领取）；半砍森林树血量不持久；森林存档为差异存储（只存移除列表）。
- 视觉风险备忘：`tile.gd::_bake_model` 依赖"烘焙后顶点平移回原点"——若复用该函数给带随机朝向的 MultiMesh，切勿去掉 `-BAKE_CENTER` 的顶点回移（曾造成作物散落十几米的回归）。
- POLISH-01 补查：场景退出的 ObjectDB/RID/渲染资源泄漏；这是本轮复测发现的既有问题，玩法断言通过不代表资源生命周期验收通过。

## 运行与验证命令

```sh
# 实机（默认大图，出生点即玩家农场）
tools/engine/Godot-4.7.2-stable/Godot.app/Contents/MacOS/Godot --path game

# 专项验证（存档一律用独立目录）
BREEZETOWN_SAVE_ROOT="$PWD/work/game-data/check" tools/engine/Godot-4.7.2-stable/Godot.app/Contents/MacOS/Godot --headless --path game --script res://scripts/tests/first_map_checks.gd
BREEZETOWN_SAVE_ROOT="$PWD/work/game-data/check" tools/engine/Godot-4.7.2-stable/Godot.app/Contents/MacOS/Godot --headless --path game --script res://scripts/tests/core_checks.gd
tools/engine/Godot-4.7.2-stable/Godot.app/Contents/MacOS/Godot --headless --path game --script res://scripts/tests/map_domain_checks.gd

# 完整冒烟（310 项）与持久化两阶段（write 后必须 verify，两个独立进程）
BREEZETOWN_SAVE_ROOT="$PWD/work/game-data/check" tools/engine/Godot-4.7.2-stable/Godot.app/Contents/MacOS/Godot --headless --path game -- --smoke
BREEZETOWN_SAVE_ROOT="$PWD/work/game-data/wp" tools/engine/Godot-4.7.2-stable/Godot.app/Contents/MacOS/Godot --headless --path game --script res://scripts/tests/world_persist_checks.gd -- --phase=write
BREEZETOWN_SAVE_ROOT="$PWD/work/game-data/wp" tools/engine/Godot-4.7.2-stable/Godot.app/Contents/MacOS/Godot --headless --path game --script res://scripts/tests/world_persist_checks.gd -- --phase=verify

# 性能采样（窗口模式才有真实渲染负载）
tools/engine/Godot-4.7.2-stable/Godot.app/Contents/MacOS/Godot --path game --windowed --resolution 1600x1000 --script res://scripts/tests/perf_checks.gd

# 固定视角截图
tools/engine/Godot-4.7.2-stable/Godot.app/Contents/MacOS/Godot --path game --windowed --resolution 1600x1000 -- --at=-672,252 --zoom=1.35 --hour=11 --shot="$PWD/work/art01/next.png"
```

注意：Godot 脚本报错后可能仍退出码 0，**必须 grep 日志**确认 `SCRIPT ERROR` 为 0 且 `*_RESULT PASS`。资源导入用 `--headless --editor --path game --quit`。PERF-02 起 `world_builder.build()` 按脚本/资产指纹缓存到 `user://cache/`（`BREEZETOWN_CACHE_ROOT` 可覆盖；改任何构建输入自动失效重建）。引擎：macOS 用 `tools/engine/Godot-4.7.2-stable/Godot.app/Contents/MacOS/Godot`，Windows 用同目录 `Godot_v4.7.2-stable_win64_console.exe`（首次需导入资源）。带 Pillow 的 Python：macOS `/Users/shenhongshi/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3`，Windows 仓库内 `tools/python/python.exe`（embeddable + pip + pillow，已装好；UI 图标重生成 `tools/python/python.exe tools/art/build_reference_ui.py`）。

钓鱼检查（Windows PowerShell，在仓库根目录）：

```powershell
& 'tools/engine/Godot-4.7.2-stable/Godot_v4.7.2-stable_win64_console.exe' --headless --path game --script res://scripts/tests/fishing_domain_checks.gd
# 品质/估价/出售/等级/新旧存档；自动使用隔离存档。
& 'tools/engine/Godot-4.7.2-stable/Godot_v4.7.2-stable_win64_console.exe' --headless --path game --script res://scripts/tests/fishing_economy_checks.gd
# 七日天气、冬季转换、自然跨天/睡觉与存档天气。
& 'tools/engine/Godot-4.7.2-stable/Godot_v4.7.2-stable_win64_console.exe' --headless --path game --script res://scripts/tests/weather_checks.gd
# 场景检查自动选择隔离存档目录，不覆盖玩家存档。
& 'tools/engine/Godot-4.7.2-stable/Godot_v4.7.2-stable_win64_console.exe' --headless --path game --script res://scripts/tests/fishing_checks.gd
# 实机画面：不用 --headless；可将 capture-size 改为 1280x800。
& 'tools/engine/Godot-4.7.2-stable/Godot_v4.7.2-stable_win64_console.exe' --path game --windowed --script res://scripts/tests/fishing_checks.gd -- --capture=D:/Workspace/BREEZETown2/work/fish02/fishing-1600.png --capture-size=1600x1000
```

采集检查（Windows PowerShell，在仓库根目录）：

```powershell
# 物种条件、抽选确定性、经济与存读档清洗。
& 'tools/engine/Godot-4.7.2-stable/Godot_v4.7.2-stable_win64_console.exe' --headless --path game --script res://scripts/tests/forage_domain_checks.gd
# 真实地图落点规则、确定性日切、E 采集、存档恢复与换季清理；自动隔离存档。
& 'tools/engine/Godot-4.7.2-stable/Godot_v4.7.2-stable_win64_console.exe' --headless --path game --script res://scripts/tests/forage_checks.gd
# 实机画面：不用 --headless；capture-size 可改 1280x800。
& 'tools/engine/Godot-4.7.2-stable/Godot_v4.7.2-stable_win64_console.exe' --path game --windowed --script res://scripts/tests/forage_checks.gd -- --capture=D:/Workspace/BREEZETown2/work/gather01/forage-1600.png --capture-size=1600x1000
```

NPC 检查（Windows PowerShell，在仓库根目录）：

```powershell
# 人设数据、日程数学、好感/送礼规则与存读档清洗。
& 'tools/engine/Godot-4.7.2-stable/Godot_v4.7.2-stable_win64_console.exe' --headless --path game --script res://scripts/tests/npc_domain_checks.gd
# 真实地图锚点解析、日程切换、对话/送礼流程、存档与堵门保护；自动隔离存档。
& 'tools/engine/Godot-4.7.2-stable/Godot_v4.7.2-stable_win64_console.exe' --headless --path game --script res://scripts/tests/npc_checks.gd
# 实机画面：不用 --headless；capture-size 可改 1280x800。
& 'tools/engine/Godot-4.7.2-stable/Godot_v4.7.2-stable_win64_console.exe' --path game --windowed --script res://scripts/tests/npc_checks.gd -- --capture=D:/Workspace/BREEZETown2/work/npc01/npc-1600.png --capture-size=1600x1000
```

委托任务检查（Windows PowerShell，在仓库根目录）：

```powershell
# 数据链完整性、前置解锁、接受/进度/交付/传话规则与存读档清洗。
& 'tools/engine/Godot-4.7.2-stable/Godot_v4.7.2-stable_win64_console.exe' --headless --path game --script res://scripts/tests/quest_domain_checks.gd
# 真实地图对话委托全流程、跨 giver 防护与存档恢复；自动隔离存档。
& 'tools/engine/Godot-4.7.2-stable/Godot_v4.7.2-stable_win64_console.exe' --headless --path game --script res://scripts/tests/quest_checks.gd
# 实机画面：不用 --headless；capture-size 可改 1280x800。
& 'tools/engine/Godot-4.7.2-stable/Godot_v4.7.2-stable_win64_console.exe' --path game --windowed --script res://scripts/tests/quest_checks.gd -- --capture=D:/Workspace/BREEZETown2/work/quest01/quest-1600.png --capture-size=1600x1000
```

室内检查（Windows PowerShell，在仓库根目录）：

```powershell
# 房间数据完整性、建筑耦合、酒馆/诊所服务规则与经济口径。
& 'tools/engine/Godot-4.7.2-stable/Godot_v4.7.2-stable_win64_console.exe' --headless --path game --script res://scripts/tests/indoor_domain_checks.gd
# 四门进出、室内服务、边界钳制、室内时间流动与存读档原位恢复；自动隔离存档。
& 'tools/engine/Godot-4.7.2-stable/Godot_v4.7.2-stable_win64_console.exe' --headless --path game --script res://scripts/tests/indoor_checks.gd
# 实机室内画面（任选房间 id：cottage/shop/inn/clinic）。
& 'tools/engine/Godot-4.7.2-stable/Godot_v4.7.2-stable_win64_console.exe' --path game --windowed --resolution 1600x1000 -- --indoor=shop --shot=D:/Workspace/BREEZETown2/work/indoor01/next.png
```

## 关键文件地图

| 关注点 | 文件 |
|---|---|
| 地图蓝图（唯一坐标源） | `game/resources/maps/first_map_blueprint.json` → 换算 `game/scripts/data/first_map_definition.gd` |
| 世界构建 | `game/scripts/world_builder.gd` → `first_map_builder.gd`；地形 `art/first_map_terrain.gd`；水系 `art/water_models.gd`（瀑布 `_cascade`） |
| 森林/果园分块 | `game/scripts/first_map_scenery.gd`（稳定 ID、可砍伐、差异持久化、耕地避让） |
| 耕地视图 | `game/scripts/tile.gd`（网格静态缓存 + MultiMesh；`_bake_model` 见风险备忘）；领域 `domain/farm_state.gd` |
| 地表资源/掉落 | `game/scripts/surface_resources.gd`、`surface_resource.gd`、`surface_drop.gd` |
| 存档 | `core/save_manager.gd`、`core/map_restore.gd`；载荷在 `main.gd::_save_payload()`（surface/forest/mine 三键在此）；读档 `_apply_load()` |
| 矿场 | `mine_layout.gd`（确定性布局）、`mine_floor.gd`（含 to_dict/apply_state）、`mine_rock/monster/drop.gd` |
| 交互 | `core/interaction_system.gd`（目标解析与执行统一入口，新交互类型在此注册） |
| 钓鱼 | `data/fish_db.gd`（条件鱼池/稀有度/行为）；`domain/fishing_session.gd`（等待/咬钩/张力/控制评分）；`game_state.gd`（品质/成长/估价/存档）；`main.gd::_fishing_target/_tick_fishing`（场景与结算）；`tests/fishing_{domain_,economy_,}checks.gd` |
| 采集 | `data/forage_db.gd`（物种/栖息地/季节/抽选）；`forage_resource.gd`（造型节点）；`forage_resources.gd`（日切刷新/落点裁决/存档）；`game_state.gd`（库存/折价/存档）；`core/interaction_system.gd`（forage 目标与采集）；`tests/forage_{domain_,}checks.gd` |
| NPC | `data/npc_db.gd`（人设/日程/喜好/台词）；`npc.gd`（造型/踱步/锚点切换）；`game_state.gd`（好感/每日门控/送礼扣件/npc 存档键）；`core/interaction_system.gd`（npc 目标）；`main.gd::_spawn_npcs/_open_dialogue/_on_dialogue_gift`（锚点解析与对话/送礼流程）；`hud.gd::_build_dialogue`（对话面板）；`tests/npc_{domain_,}checks.gd` |
| 委托任务 | `data/quest_db.gd`（八项委托/链式前置）；`game_state.gd`（quest_* 状态机/count_item/remove_items/quests 存档键）；`hud.gd`（委托按钮/追踪药丸/背包任务区）；`main.gd`（_dialogue_quest_offer/_on_quest_accept/_on_quest_turnin/可交付 toast）；`tests/quest_{domain_,}checks.gd` |
| 室内 | `data/interior_db.gd`（房间/服务/机器/npc_spot 唯一数据源）；`interior_room.gd`（房间构建/服务与机器聚焦）；`domain/machine_state.gd` + `data/recipe_db.gd`（加工配方与状态机）；`game_state.gd`（buy_meal/buy_treatment/add_mineral）；`core/interaction_system.gd`（building_door/interior_exit/interior_service/interior_machine 焦点）；`main.gd`（_enter_building/_exit_building/_switch_indoor/_interior_service/_interior_machine/_tick_machines/_station_staff/place_chest/open_warehouse、indoor+interiors+chests 存档键）；`warehouse_chests.gd`（宝箱放置与共享仓库存取点）；`tests/indoor_{domain_,}checks.gd` |
| 时钟/天气 | `core/game_clock.gd`（七日天气、季节、时间数学）；`main.gd::_advance_world_time`（逐日结算）；`tests/weather_checks.gd` |
| 导航/规则 | `core/map_data.gd`（水域/障碍/占用）、`core/world_navigation.gd`（局部有界寻路） |
| HUD/UI | `game/scripts/hud.gd`（木框+羊皮纸；日期栏四段药丸在 `_build_info_chips`） |
| 测试 | `game/scripts/tests/`：`first_map_checks` / `core_checks` / `map_domain_checks` / `world_persist_checks` / `perf_checks` |
| 资产 | 模型 `game/resources/models/*.glb`；Blender 源 `art/3d/source/`；生成器 `tools/art/` |

## 证据索引（work/ 已清理，仅以下文件有效）

- 截图：`work/art01/`——`final-garden/final-homestead`（ART-01）、`map01-*` 六张（MAP-01）、`style3-farm + fix3-* + style2-dock2`（画风）、`art02-farm/pasture2/blossom2/icons`（ART-02）、`perf02-farm-hit`（缓存命中渲染）、`farm01-hud + hud-status-zoom`（心+⚡状态栏）；`work/visual-slice/scaled-{farm,map}-final.png`（大图全景）。
- 日志：`work/art01/*.log`——最新 `farm01-*`（FARM-01 回归）、`art02-*`、`perf02-*`、`play01-measure`（行程实测），此前 `style-*` / `map01-*` / `world01-*` / `perf01-*`；更早基线 `work/first-map/validation/`（2026-09-16）。
- 钓鱼第二轮：`work/fish02/`，`fishing-domain.log`（275）/ `economy.log`（77）/ `weather.log`（31）/ `fishing.log`（104）/ `farm.log`（54）/ `hud-layout.log`（22）/ `core.log` / 新旧 smoke 均 PASS，`visual-1600.log` 与 `visual-1280.log` 各 109 项 PASS；`fishing-initial.log`（98）保留为新增多日回归前的历史记录。截图 `fishing-{1600,1280}.png`、`fishing-{1600,1280}-inventory.png`、`fishing-{1600,1280}-shop.png` 已归档，最终双尺寸视觉复核完成。
- 采集（GATHER-01）：`work/gather01/`，`forage-domain.log`（138）/ `forage-scene.log`（71，headless）/ `visual-1600.log`（79）与 `visual-1280.log`（85，含采集物聚焦与背包截图捕获；场景检查项数随每次随机生成株数浮动）/ `core.log` / `farm.log` / `fishing-domain.log` / `economy.log` / `weather.log` / `fishing.log` / `first-map.log` / 新旧 smoke（含缩放返工后复跑 `default-smoke2.log`）均 PASS。截图 `forage-{1600,1280}.png`（冬根聚焦 + 提示）与 `forage-{1600,1280}-inventory.png`（背包“采集”区）已复核。
- NPC 第一轮（NPC-01）：`work/npc01/`，`npc-domain.log`（159）/ `npc-scene.log`（40，headless）/ `visual-1600.log` 与 `visual-1280.log`（各 42，含对话框与送礼面板截图捕获）/ `core.log` / `farm.log` / `fishing-domain.log` / `economy.log` / `weather.log` / `fishing.log` / `forage-domain.log` / `first-map2.log` / 新旧 smoke（堵门修复后复跑 `default-smoke2.log`、`legacy-smoke2.log`；首跑 `first-map.log` 与 `*-smoke.log` 为堵门缺陷的失败记录）均 PASS。截图 `npc-{1600,1280}.png`（皮埃尔对话面板）与 `npc-{1600,1280}-gift.png`（送礼面板）已复核。
- 委托任务（QUEST-01）：`work/quest01/`，`quest-domain.log`（135）/ `quest-scene.log`（31，headless）/ `visual-1600.log` 与 `visual-1280.log`（各 34，含追踪药丸、委托按钮与背包任务区截图捕获）/ `npc-domain.log` / `npc-scene.log` / `core.log` / `farm.log` / `fishing-domain.log` / `economy.log` / `weather.log` / `fishing.log` / `forage-domain.log` / `first-map.log` / 新旧 smoke（flake 修复后复跑 `default-smoke2.log`、`legacy-smoke3.log`；首跑 `legacy-smoke.log` 为品质 flake 的失败记录，`legacy-smoke2.log` 为修复前偶发通过）均 PASS。截图 `quest-{1600,1280}.png` 与 `quest-{1600,1280}-inventory.png` 已复核。
- 室内第一轮（INDOOR-01）：`work/indoor01/`，截图 `indoor-{shop,cottage,inn,clinic}-1600.png` 与 `indoor-{shop,cottage}-1280.png`（双尺寸复核：角色可见、家具/服务可读、南东矮墙不挡相机）。验证证据：indoor 领域 68 / indoor 场景 61（四门进出、服务与失败路径、边界钳制、室内时间流动、存读档原位恢复）/ first_map 154（含门点语义改写断言）/ npc 42（堵门守卫映射为进门+柜台）/ quest 31 / core / farm 54 / forage 138 / fishing-economy 77 / 默认 smoke（含商店进门流程改写）全 PASS，0 脚本错误。
- 室内第二轮+加工（INDOOR-02/PROCESS-01）：`work/indoor01/` 新增 `indoor-{smith,player_barn,player_coop}-1600.png` 与皮埃尔值守版 `indoor-shop-1600.png`。indoor 领域扩至 118（配方自检/机器生命周期/存档往返/脏档清洗）、indoor 场景扩至 121（三机器投料/加工/收取、铁配方切换、皮埃尔值守与出门恢复、加工中存读档）；回归 npc_domain 159 / npc 42 / quest_domain 135 / quest 31 / first_map 154 / farm 54 / forage 138 / fishing-economy 77 / weather 31 / core / 默认 smoke 全 PASS，0 脚本错误。
- 工作台与仓库（STORE-01）：`work/indoor01/` 新增 `indoor-carpenter-1600.png`（工作台/木料堆/锯木架）与 `store-chest-farm-1600.png`（农场放置宝箱+共享仓库提示）。indoor 领域扩至 145（工作台配方、仓库整批存取/六族口径/存读档清洗/脏档防御）、indoor 场景扩至 142（宝箱制作→放置→面板存取→收起→位置与仓库存读档）；回归 npc_domain 159 / npc 42 / quest_domain 135 / quest 31 / farm 54 / forage 138 / fishing-economy 77 / weather 31 / first_map 154 / core / 默认 smoke 全 PASS，0 脚本错误。
- 仓库扩容/丢弃/分类+加工二辈（STORE-02）：`work/indoor01/` 更新 `indoor-{inn,player_barn}-1600.png`（厨房灶台/织布机）。indoor 领域 145→160（容量口径/丢弃/归一下限/新配方）、indoor 场景 142→168（面包/毛毯/扩容发放/容量闸门/丢弃信号/多配方选择序）；回归 10 套 + smoke 全 PASS，0 脚本错误。
- 钓鱼第一轮历史：`work/fish01/`，`fishing-domain.log` / `fishing.log` / `hud_layout_probe.log` / `first-map.log` / `farm.log` / `core.log` / 新旧 smoke；`fishing-{1600,1280}.png` 为角力画面，`fishing-{1600,1280}-shop.png` 为商店画面，对应 `visual-{1600,1280}.log`。`baseline-import.log` 是修复前失败记录，不是当前验收结果。
- 对图：`docs/maps/first-map-trace.png`（描图叠加，仅对位用，不是实现画面）。

## 后续需要确认的事项（实施前先给方案）

公共土地永久经营范围、长途交通形式、NPC 农庄经营关系、最终门牌命名与室内布局。当前若干名称与服务建筑类别为实现暂定值，不作为用户最终命名。
