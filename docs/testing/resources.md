> **2D 历史记录，不作为当前开发依据。** 当前 3D 工作见 [V2 PRD](../product/01-product-prd-v2.md) 和 [当前任务板](../execution/task-board.md)；本文旧状态、路径和命令仅供追溯。

# 测试资源登记与缺口（QA）

日期：2026-09-09；维护：QA；状态：M0 登记，M5/QA-02 前补齐。

## 1. 当前开发机基准

| 项 | 值 | 来源 |
|---|---|---|
| 平台 | macOS 26.4（Build 25E246） | FND-01 实测 |
| 机型 | MacBook Air（Apple M5） | QA-01 实测 |
| CPU | Apple M5，10 核（4 性能 + 6 能效） | QA-01 实测 |
| 内存 | 16 GB | QA-01 实测 |
| 架构 | arm64（Apple Silicon） | FND-01 实测 |
| 磁盘可用 | ~340 GiB | FND-01 |
| 引擎 | Godot 4.7.2-stable（`4.7.2.stable.official.ed1daf0bf…`） | engine-lock.json |
| GPU / 显示分辨率 | 未单独登记 | PERF-01 前用 `system_profiler SPDisplaysDataType` 补 |

注：16 GB 统一内存、集显是 M5 机型；NFR-04 的 1 GiB RSS 目标以此为基准机登记，M5 性能报告必须标注机型与配置。

## 2. 资源缺口

| 资源 | 用途 | 状态 | 负责人 | 最迟门禁 | 缺口影响 |
|---|---|---|---|---|---|
| Windows x64 实机 | 双平台构建/运行验收 | **缺** | QA/LEAD | QA-02 | CASE-43/44、NFR-08 未验证；不得宣称双平台通过 |
| macOS Apple Silicon 实机 | 已有 | 具备 | — | — | — |
| 真实异地可达公网 IPv4 | 跨家庭网络联机 | **缺** | NET/QA | INT-02 | CASE-49 真实拓扑未验证 |
| 局域网双机 | LAN 联机 | **缺** | NET/QA | INT-02 | CASE-49 LAN 未验证 |
| 至少 2 名并发联机测试者 | 四人回归 | **缺** | QA/LEAD | INT-02/03 | 四人场景未验证 |
| 5 名未参与开发的新手 | CASE-37 可用性 | **缺** | QA/LEAD | QA-03 | 体验验收未验证 |
| 素材来源与预算 | ART-01 | **未定** | 用户/UI | ART-01 | 不得使用未授权素材 |
| 远程仓库/分发位置 | 托管与发布 | 未提供 | LEAD | REL-03 | 不阻止 M0；本地检查入口已就绪 |

## 3. 资源缺失的处理原则

- 缺失不阻止其他任务推进；但**对应验收必须保持“未验证”**，不得用本机结果冒充。
- 本机多进程 ≠ 真实双机；macOS 导出 ≠ Windows 导出。
- 资源到位后由原 owner 补验并在追溯矩阵更新状态；未关闭的缺口在 M0 出口清单中明确列出。

## 4. 测试数据约定（与 04 文档一致）

固定 fixture 命名：`world_empty_v1`、`world_crop_boundary_v1`、`world_stats_v1`、`world_save_generations_v1`、`migration_world_v1`。M0 尚未生成这些 fixture（属 M1+ 交付）；现有样例是 `game/content/schema/examples/` 下的契约样例与 `work/*-spike/run/` 的合成实验数据。
