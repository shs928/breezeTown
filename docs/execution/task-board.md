# 微风小镇：执行任务板

更新日期：2026-09-09（Asia/Shanghai）  
产品文档：0.3；游戏目标：0.1.0；当前阶段：**M0–M5 已通过（+ 素材/引导/性能/候选包）→ M6 待启动（需外部资源）**；契约：**已冻结 v1**。

用户已授权执行。LEAD 为主执行者；本板记录真实状态，独立实验通过不等于正式游戏验收。一人兼多角色时，各角色写入范围仍分开，验收身份按任务记录。

统一检查入口：`tools/test/check.sh`（boot / contracts / save-spike / net-spike / probe）。

## M0 状态

| 任务 | Owner / 执行者 | 状态 | 前置 | 证据 / 下一步 |
|---|---|---|---|---|
| FND-01 | FND / 主执行者 | **ACCEPTED** | 无 | 引擎 4.7.2-stable 锁定；四模式 headless 启停 exit 0，非法模式 exit 2；macOS 导出包可启动。见 `docs/build/FND-01.md`、`engine-lock.json` |
| FND-02 | FND / 主执行者 | **ACCEPTED** | FND-01 | 契约 v1 + 5 合法/17 非法样例 + 地图 schema；`CONTRACTS_OK checks=63`。见 `docs/contracts/contracts-m0.md` |
| NET-01 | NET / 主执行者 | **ACCEPTED** | FND-01 | DTLS 6 场景真实多进程 ×2 轮 `NET_SPIKE_OK`；凭据零泄漏。见 `docs/adr/NET-01.md` |
| DATA-00 | DATA / 主执行者 | **ACCEPTED** | FND-01 | 双进程锁竞争 + 四阶段故障注入 + 损坏/未来格式回退，`SAVE_SPIKE_OK checks=45` ×2 轮。见 `docs/adr/DATA-00.md` |
| QA-01 | QA / 主执行者 | **ACCEPTED** | FND-01 | `check.sh` 5/5 全绿；probe 通过/失败双向实测；追溯矩阵 + 资源登记。见 `docs/testing/` |
| UI-01 | UI / 主执行者 | **ACCEPTED** | 无 | 14 页状态表 + 输入焦点契约 + 像素风方向稿；9 步走查闭环。见 `docs/ui/` |
| LEAD-01 | LEAD / 主执行者 | **ACCEPTED** | FND-02、NET-01、DATA-00、QA-01、UI-01 | 契约/引擎/网络/存档/UI 基线冻结；M0 本机门通过。见 `docs/adr/M0-baseline.md` |

## M1 状态（全部 ACCEPTED，详见 `docs/execution/M1.md`）

| 任务 | Owner | 状态 | 前置 | 证据 |
|---|---|---|---|---|
| SIM-01 | SIM | **ACCEPTED** | LEAD-01 | `SIM_OK` 50；世界核心/原子事务/日切/移动 |
| ECON-01 | ECON | **ACCEPTED** | SIM-01 | `ECON_OK` 53；背包/资金/买卖 |
| FARM-01 | FARM | **ACCEPTED** | ECON-01 | `FARM_OK` 59；五作物完整循环 |
| ECON-02 | ECON | **ACCEPTED** | FARM-01 | `STATS_OK` 26；三榜/并列/投影 |
| DATA-01 | DATA | **ACCEPTED** | SIM-01 | `DATA_OK` 42；仓库/锁/故障状态 |
| NET-00 | NET | **ACCEPTED** | ECON-01、DATA-01 | `NET00_OK` 32；身份/激活/继续 |
| UI-02 | UI | **ACCEPTED** | ECON-02、DATA-01、NET-00 | 窗口模式实机启动；动作方法经网关 |
| INT-01 | QA | **ACCEPTED** | UI-02 | `INT01_OK` 37；单机全流程 + headless 同核心 |

统一检查入口 `tools/test/check.sh`：**12/12 全绿**。

## M6（依赖未解锁，保持 TODO）

| 任务 | Owner | 状态 | 前置 |
|---|---|---|---|
| NET-02 | NET | **ACCEPTED** | INT-01 | `NET02_OK` 40 + `M2E2E_OK` 24 |
| SIM-02 | SIM | **ACCEPTED** | INT-01 | `SIM02_OK` 22 |
| NET-03 | NET | **ACCEPTED** | NET-02、SIM-02 | `NET03_OK` 21 |
| NET-04 | NET | **ACCEPTED** | NET-03 | `NET04_OK` 19 |
| UI-03 | UI | **ACCEPTED** | NET-04 | 由 INT-02 驱动真实动作方法 |
| INT-02 | QA | **ACCEPTED** | UI-03 | `INT02_OK` 26（本机多会话；异地待补） |
| ECON-04 | ECON | **ACCEPTED** | INT-02 | `M3_OK` 39（含救济与仓库并发） |
| FARM-02 | FARM | **ACCEPTED** | ECON-04 | 三建设/顺序解锁/效果一次 |
| ECON-03 | ECON | **ACCEPTED** | FARM-02 | 统计校准并入 M3 |
| SIM-03 | SIM | **ACCEPTED** | INT-02 | 多人日切/零在线暂停 |
| NET-05 | NET | **ACCEPTED** | ECON-03、SIM-03 | `NET05_OK` 16 |
| UI-04 | UI | **ACCEPTED** | NET-05 | 仓库/建设板/榜单明细 |
| INT-03 | QA | **ACCEPTED** | UI-04 | `INT03_OK` 30（fixture；真人待 M6） |
| DATA-02 | DATA | **ACCEPTED** | INT-03 | `DATA02_OK` 17 |
| DATA-03 | DATA | **ACCEPTED** | DATA-02 | `DATA03_OK` 22 |
| DATA-04 | DATA | **ACCEPTED** | DATA-03 | `DATA04_OK` 23 |
| DATA-05 | DATA | **ACCEPTED** | DATA-04 | `DATA05_OK` 27 |
| NET-06 | NET | **ACCEPTED** | DATA-05 | dedicated 加载迁移世界 |
| UI-05 | UI | **ACCEPTED** | DATA-04 | 授权/导出/保存故障界面 |
| SEC-01 | QA | **ACCEPTED** | NET-06、UI-05 | `SEC01_OK` 34 |
| ART-01 | UI | **ACCEPTED** | SEC-01 | 39 个原创素材 + 许可清单 |
| UI-06 | UI | **ACCEPTED** | ART-01 | 引导/重绑定/设置（`M5_OK` 55） |
| PERF-01 | QA | **ACCEPTED** | UI-06 | 256 株实测：tick 7µs/日切 3.6ms/保存 3ms/RSS 134MiB |
| QA-02 | QA | TODO | PERF-01 | **BLOCKED**：缺 Windows 实机与真实网络 |
| REL-01 | QA | **ACCEPTED** | QA-02 | `tools/release/build.sh` 通过（含检查门禁） |
| REL-02 | LEAD | **ACCEPTED** | REL-01 | `docs/user-manual.md` |
| QA-03 | QA | TODO | REL-02 |
| LEAD-02 | LEAD | TODO | QA-03 |
| REL-03 | QA | TODO | LEAD-02 |
| LEAD-03 | LEAD | TODO | REL-03 |

## 阻塞与未验证（不得写成通过）

| 项 | 影响 | 补验任务 |
|---|---|---|
| Windows x64 实机缺失 | CASE-43/44、NFR-08 双平台 | QA-02 |
| 真实 LAN / 异地公网 IPv4 缺失 | CASE-49、INT-02 | INT-02 |
| 联机测试者 / 新手缺失 | 四人回归、CASE-37 | INT-03 / QA-03 |
| 素材来源与预算未定 | ART-01 | 用户授权 |
| CI 未运行（非 Git 仓库、无远程托管） | — | 本地入口已就绪，不冒充通过 |

## 下一步

1. M6 的 QA-03（五名新手真人验收）**阻塞于外部资源**：需要 5 名未参与开发的新手，当前不可用。
2. QA-02（双平台黑盒）阻塞于 Windows 实机；NFR-02/03/04 完整报告阻塞于真实网络与 4 名测试者。
3. 在资源到位前，0.1.0 候选包已构建完成（`build/release-0.1.0/`），但**不得宣称已发布**。
