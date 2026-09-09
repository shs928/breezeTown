# M1 任务卡：单人可玩切片

依据：`docs/adr/M0-baseline.md`（冻结基线）、`03-roadmap-agent-tasks.md` §5.1。  
状态：**SIM-01 为唯一 READY**；其余按依赖依序解锁。每卡已填入实际契约版本与可运行命令。

## 共同基线（所有 M1 卡）

- 契约版本：**v1**（`protocol_version=1`、`save_schema_version=1`、`ruleset_version=v1.0`、`content_schema_version=1`、`public_schema_version=1`）。
- 引擎：Godot 4.7.2-stable（`tools/engine/fetch-godot.sh` 复现）。
- 契约代码：`game/src/contracts/`（`contract_limits.gd`、`contract_ids.gd`、`contract_envelopes.gd`、`contract_error.gd`、`contract_public_snapshot.gd`、`contract_view.gd`、`content_validator.gd`）。
- 内容样例：`game/content/schema/{items,crops,projects}.json`、`examples/map_town_minimal.json`。
- 检查入口：`tools/test/check.sh`（提交前必须全绿）。
- 红线：UI/网络不绕过网关改权威状态；一次业务提交全有或全无；昵称只用于显示。

---

## SIM-01（SIM）— READY

- 目标版本/契约版本/集成基线：0.1.0 / 契约 v1 / M0 基线。
- 已接受前置：LEAD-01（M0 基线）。
- 允许修改：`game/src/domain/world/`、`game/src/application/core/`、`game/src/application/world/`、`game/tests/unit/simulation/`。
- 禁止修改：`game/src/contracts/`（需改先提 ADR）、其他 owner 目录、`content/` 定义。
- 交付行为：
  1. `WorldState`（字段按契约 4.1：world_id、owner_player_id、schema_version、ruleset_version、content_hash、game_day、day_elapsed_ms、business_revision、next_event_seq、treasury、members、plots、projects、containers、stats、publication_enabled、consent_revision）。
  2. `LocalCommandGateway`：接收绑定身份的命令 → 校验 → 单写队列 → 原子提交 → 回执；复用 `ContractEnvelopes.validate_command`。
  3. 原子业务队列 + 事务协调：失败整批丢弃，不留半状态。
  4. `ClockPort` 实现：只累加实际模拟步；`GAME_DAY_MS=600000`；日切屏障（先完成当前批次 → 结算 → 递增日 → 清浇水 → 恢复）。
  5. 最小移动/碰撞：读 `map_town_minimal.json` 的 legend，96 px/s，玩家互不阻挡，静态碰撞生效。
  6. 保存调度端口（接口，不实现文件 IO；由 DATA-01 提供 `WorldRepository`）。
  7. `profile.update` 处理器：昵称清洗用 `ContractLimits.sanitize_display_name`，产生 `MemberProfileChanged`。
- 适用：FR-01/03/07、NFR-01/06；CASE-01/07/09/17 的基础规则（无界面）。
- 验收命令：
  ```sh
  "$GODOT" --headless --path game --script res://tests/unit/simulation/test_runner.gd
  tools/test/check.sh contracts   # 不得回归
  ```
  人工场景：以固定 seed 创建世界 → 移动撞边界 → 推进 600s → 日切一次，断言 game_day/treasury/revision 与事件序列。
- 跨平台/真实网络：不需要。
- 未具备资源：无。

## ECON-01（ECON）— TODO（依赖 SIM-01）

- 允许修改：`game/src/domain/inventory/`、`game/src/domain/economy/`、`game/src/application/inventory/`、`game/src/application/economy/`、`game/content/definitions/items`、`game/tests/unit/economy/`。
- 交付：24 格背包（6 快捷栏）、堆叠/整组移动/拆分、初始共享库存（20 萝卜种子）/资金（300）、购买种子、出售作物（只收产物）。
- 验收：CASE-12/14/15 的无界面对账；失败无半提交；`treasury = 300 + total_sales - total_purchases`。
- 命令：`"$GODOT" --headless --path game --script res://tests/unit/economy/test_runner.gd`

## FARM-01（FARM）— TODO（依赖 ECON-01）

- 允许修改：`game/src/domain/farming/`、`game/src/application/farming/`、`game/content/definitions/crops`、`game/tests/unit/farming/`。
- 交付：五作物定义接入 `crops.json`；整地/播种/浇水/生长/收获处理器；距离 ≤48px 且线段不穿阻挡。
- 验收：CASE-09/10/11 无界面；萝卜完整循环；未浇水不长、成熟不再计分、抢收只一胜。
- 命令：`"$GODOT" --headless --path game --script res://tests/unit/farming/test_runner.gd`

## ECON-02（ECON）— TODO（依赖 FARM-01）

- 交付：事件投影、累计/当日收益、贡献分类、并列排序（竞赛名次 1/1/3，稳定顺序）。
- 验收：CASE-15/21/23；`sum(member_total_sales)=total_sales`；checkpoint + 后续事件 = 实时物化。

## DATA-01（DATA）— TODO（依赖 SIM-01；可与 ECON/FARM 并行）

- 允许修改：`game/src/infrastructure/persistence/`、`game/src/application/` 内保存调度、`game/tests/unit/data/`。
- 交付：正式 `WorldRepository`（复用 `ContractEnvelopes.validate_save_envelope`）、加载/自动保存/手动/退出保存、保存故障状态接口（明确失败立即冻结；35s 无成功保存触发保护）。
- 依据：`docs/adr/DATA-00.md`（锁与发布方案）。
- 验收：CASE-02/27/28/46 基础场景。

## NET-00（NET）— TODO（依赖 ECON-01、DATA-01）

- 允许修改：`game/src/infrastructure/identity/`、`game/src/application/session/`、`game/tests/network/`。
- 交付：本地 `IdentityPort`、凭据创建/本地持久化、候选所有者、`LocalSession`；首次保存成功后才激活身份；继续世界复用身份。
- 验收：CASE-01/02/06 的单人部分；ECON 只按合法成员 ID 建库存，不生成凭据。

## UI-02（UI）— TODO（依赖 ECON-02、DATA-01、NET-00）

- 允许修改：`game/src/client/`、`game/scenes/client/`、`game/assets/`、`game/content/maps/`、`game/tests/client/`、`docs/ui/`。
- 交付：主菜单、正式最小地图/角色、工具与快捷栏、背包整理/商店/榜单/改昵称/错误/保存状态；只调网关；基本设置可用。
- 依据：`docs/ui/flows-screens.md`、`input-contract.md`、`art-direction.md`。
- 验收：只验单人启动与本地继续，不接通远端联机；地图通过 `ContentValidator.validate_map`。

## INT-01（QA）— TODO（依赖 UI-02）

- 允许修改：`game/tests/integration/`、`docs/testing/`。
- 交付：CASE-01/02/07/09/15/21/27 完整单机流程 + headless 同核心 smoke。
- 约束：由 FND 集成 bootstrap、各 owner 修复；QA 不越权改实现；不得用 mock 成功替代。
