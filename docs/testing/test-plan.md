> **2D 历史记录，不作为当前开发依据。** 当前 3D 工作见 [V2 PRD](../product/01-product-prd-v2.md) 和 [当前任务板](../execution/task-board.md)；本文旧状态、路径和命令仅供追溯。

# 测试计划（M0 锁定版）

日期：2026-09-09；维护：QA。本计划锁定测试方案、分层、网络矩阵与缺陷门；随 M1–M6 逐阶段补充实现任务。

## 1. 测试框架决策

**不引入第三方测试框架**。采用 Godot 原生 headless + 自建断言探针：

- 理由：M0 不并存多套框架；GDScript 领域测试可完全无界面运行（NFR-06 已实测）；避免额外依赖与许可登记负担。
- 统一入口 `tools/test/check.sh`；每个测试脚本以 `CONTRACTS_OK` / `SAVE_SPIKE_OK` / `NET_SPIKE_OK` / `PROBE_OK` 标记成功，非零退出表示失败。
- 未来若需参数化/性能采集，优先在现有脚本内扩展，不引入框架（需变更时走 ADR）。

## 2. 测试分层与责任

| 层 | 责任 | 目录 | 何时 |
|---|---|---|---|
| 单元/性质 | 实现者写本模块 | `game/tests/unit/**` | 随功能 |
| 契约 | FND | `game/tests/unit/contracts/` | M0 起 |
| 集成/多进程 | QA | `game/tests/integration/` | M1 起 |
| 网络实验 | NET | `work/net-spike/` | M0 |
| 存储实验 | DATA | `work/save-spike/` | M0 |
| 性能 | QA | `game/tests/performance/` | M5 |
| 安全 | QA | `game/tests/security/` | M4 |
| 手测/可用性 | QA | 录像/日志 | M6 |

单元测试由实现者维护，QA 不抢同一文件；跨模块验收由 QA 写。

## 3. 网络矩阵

| 档 | RTT | 丢包 | 抖动 | 时长 | 判据 |
|---|---|---|---|---|---|
| 基线 | 0 | 0 | 0 | 30 min | 可玩、无经济错误 |
| 档 1 | 100ms | 1% | 20ms | 30 min | 可玩、无经济错误 |
| 档 2 | 150ms | 3% | 30ms | 30 min | 可降流畅度，不可复制物品/绕过权限 |

注入方式：`dnctl` + `pf`（dummynet）；RTT 双向各半；记录实际 ping、工具参数、随机种子。

## 4. 性能场景（M5）

1. solo 256 株 30 min。
2. 房主 + 3 客户端混合操作 256 株 30 min。
3. 档 1 网络 30 min。
4. 档 2 网络 30 min。
5. 保存压力（自动/日切/手动交错 + 一次失败注入）。
6. dedicated 2 小时（每 30s 一项业务）。

每项报告平均/P95/P99 帧耗时、峰值/平均带宽、RSS、保存耗时、错误率、重同步次数、断线次数。

## 5. 缺陷分级门（04 文档）

- Blocker：崩溃/卡死、重复结算、物品复制、负资金、身份串号、存档不可恢复、公开泄露、越权 owner 命令、双权威写入。
- Critical：四人循环不可完成、频繁不一致、日切破坏、平台无法启动、核心焦点误操作、撤回仍导出、严重性能退化。
- Major / Minor：见 04 文档；Major 需已知问题说明。

## 6. 证据要求

每次结果记录：游戏版本、规则/内容 hash、平台、运行模式、配置、绝对日期、日志位置。可复现 = 从空数据目录按步骤两次同结论。失败保留最小存档、输入序列、日志、截图/录像（脱敏）。

## 7. M0 已锁定项

- 引擎：Godot 4.7.2-stable（`docs/build/engine-lock.json`）。
- 检查入口：`tools/test/check.sh`（5 项全绿）。
- 网络方案：ENet/UDP + DTLS 低层 API（`docs/adr/NET-01.md`）。
- 存储方案：目录锁 + 代际发布（`docs/adr/DATA-00.md`）。
- 契约候选：`docs/contracts/contracts-m0.md`（63 项检查）。
