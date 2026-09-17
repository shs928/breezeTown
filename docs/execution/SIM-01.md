> **2D 历史记录，不作为当前开发依据。** 当前 3D 工作见 [V2 PRD](../product/01-product-prd-v2.md) 和 [当前任务板](../execution/task-board.md)；本文旧状态、路径和命令仅供追溯。

# SIM-01 交付记录：单人世界核心

- 执行者：SIM（主执行者兼任）；日期：2026-09-09
- 契约版本：v1；前置：LEAD-01（已接受）
- 结论：**通过**。`SIM_OK checks=50`，并纳入 `tools/test/check.sh`（全量 6/6 绿）。

## 1. 交付物

| 路径 | 内容 |
|---|---|
| `game/src/domain/world/world_state.gd` | 权威世界状态（契约 4.1 全字段）、创建/成员/日切/只读导出 |
| `game/src/application/core/sim_clock.gd` | 受控模拟时钟：只累加实际步、不补跑、时间文本换算 |
| `game/src/application/core/transaction_coordinator.gd` | 原子提交：计划校验 → 一次性应用状态/统计/事件 → 不变量检查 |
| `game/src/application/world/world_runtime.gd` | 单写命令网关、日切屏障、移动/碰撞、昵称、幂等回执、保存故障冻结 |
| `game/tests/unit/simulation/test_runner.gd` | 50 项无界面测试 |

## 2. 关键设计

- **提交计划模式**：处理器不直接改权威状态，返回 `{ops, events, stat_ops}`；协调器先整体校验再一次性应用，避免逐字段回滚遗漏，直接满足 NFR-01“全有或全无”。
- **不变量护栏**：每次提交后校验 `treasury = 300 + total_sales − total_purchases`、成员销售额求和 = 世界总额、容器容量与槽位数量边界；违反即报错而非静默继续。
- **幂等键**：`(epoch, player_id, client_sequence)` + payload 摘要；同序号同内容返回原回执并标 `replayed`，同序号不同内容拒绝；跳号返回 `SEQUENCE_GAP` + 期望序号；业务失败也消耗序号（契约 6.1）。
- **日切屏障**：`_day_barrier` 期间拒绝新业务命令；日切在同一条提交路径上完成递增日、清浇水、重置当日收益桶。
- **不补跑**：一次巨大 delta 只推进一个游戏日，休眠唤醒不跳多日（PRD 5.2）。
- **移动**：方向归一化、按 20Hz 单步推进、`input_sequence` 去旧包、静态碰撞（四角采样）+ 单轴滑动、玩家之间不阻挡。

## 3. 覆盖的验收

| CASE | 覆盖内容 | 结果 |
|---|---|---|
| CASE-01（基础） | 世界创建：初始资金 300、第 1 日、所有者角色、凭据不进世界状态、仓库 20 萝卜种子 | ✓ |
| CASE-07（基础） | 移动/碰撞/旧输入序号丢弃/玩家互不阻挡 | ✓ |
| CASE-09/17（时钟基础） | 600s 日切、时间换算（06:00 起）、休眠不补跑、日切重置 | ✓ |
| NFR-01（基础） | 原子提交：非法计划状态不变；不变量成立 | ✓ |
| 契约 6.1 | 幂等、跳号、业务失败消耗序号、保存故障冻结 | ✓ |

## 4. 未覆盖（后续任务）

- 生长结算接入日切（FARM-01）；库存/经济处理器（ECON-01）；统计投影（ECON-02）。
- 文件 IO 与保存调度实现（DATA-01）；正式身份（NET-00）。
- 远端同步/差量（M2 NET-03）。
- 玩家实体碰撞按设计**故意不存在**（PRD 5.1 避免堵门）。

## 5. 复现

```sh
tools/test/check.sh sim
# 或直接：godot --headless --path game --script res://tests/unit/simulation/test_runner.gd
```
