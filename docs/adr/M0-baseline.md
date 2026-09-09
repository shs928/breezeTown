# ADR：M0 技术门与执行基线冻结（LEAD-01）

日期：2026-09-09；状态：**已裁决**  
依赖证据：FND-01、FND-02、NET-01、DATA-00、QA-01、UI-01 全部交付并本机实测。

## 1. 判定

**M0 本机技术门通过。** 关键路线（无界面启动、加密连接、写锁与完整快照发布、契约无界面可测）均在开发机取得可复现证据；**外部资源缺口（Windows 实机、真实 LAN/异地网络、测试者）按第 5 节挂起，不构成本机技术门的阻塞，但对应验收保持未验证。**

依据：`tools/test/check.sh` 五项全绿（boot / contracts 63 / save-spike 45 / net-spike 6 场景 / probe 双向）。

## 2. 冻结清单

| 项 | 冻结值 | 位置 |
|---|---|---|
| 引擎/模板 | Godot **4.7.2-stable**（`4.7.2.stable.official.ed1daf0bf001b61586d9930840f2f1394092c079`） | `docs/build/engine-lock.json` |
| game_version | 0.1.0 | `game/project.godot` |
| protocol_version | **1**（由候选 0 升） | `contract_envelopes.gd` |
| save_schema_version | 1 | `contract_envelopes.gd` |
| ruleset_version | **v1.0**（去 `-candidate`） | `contract_envelopes.gd` |
| content_schema_version | 1 | `content/schema/*.json` |
| public_schema_version | 1 | `contract_public_snapshot.gd` |
| 契约目录/样例 | `game/src/contracts/`、`game/content/schema/examples/` | `docs/contracts/contracts-m0.md` |
| 生产网络路线 | ENet/UDP + DTLS 低层 `ENetConnection` + `TLSOptions`；端口候选 24642 | `docs/adr/NET-01.md` |
| 身份格式 | player_id `m`+32hex 等 8 类 | `contract_ids.gd` |
| 存档策略 | 原子目录锁 + 临时写/验证/rename 发布 + 5 代轮转 | `docs/adr/DATA-00.md` |
| 测试入口 | `tools/test/check.sh`（原生 headless，不引框架） | `docs/testing/test-plan.md` |
| UI 输入/内容规则 | `docs/ui/input-contract.md`、`flows-screens.md`、`art-direction.md` | — |

## 3. 实验差异裁决

- **NET-01 vs FND-02**：无 schema 冲突。NET-01 的连接卡是**独立 DTO**（含证书/地址），与 PublicSnapshot 严格分离；M2 为连接卡补正式 schema（`card_schema_version`）。
- **DATA-00 vs FND-02**：envelope 字段与校验顺序一致；DATA-00 为独立性自带最小校验，正式实现（DATA-01）必须复用 `ContractEnvelopes.validate_save_envelope`，**不允许第二套 schema**。
- **版本冻结影响**：候选样例中的 `protocol_version: 0` 与 `v1.0-m0-candidate` 已同步升为 `1` 与 `v1.0`；契约测试复跑仍 63 项全绿。

## 4. 资源缺口与挂起项（不得写成通过）

| 缺口 | 影响 | 补验任务 | 状态 |
|---|---|---|---|
| Windows x64 实机 | CASE-43/44、NFR-08 双平台 | QA-02 | **未验证** |
| 真实 LAN / 异地公网 IPv4 | CASE-49 真实拓扑、INT-02 | INT-02 | **未验证** |
| 2 名以上联机测试者 | 四人回归 | INT-03 | **未验证** |
| 5 名新手 | CASE-37 | QA-03 | **未验证** |
| 素材来源/预算 | ART-01 | 用户授权 | **未定** |
| 远程仓库/分发位置 | REL-03 | LEAD | 本地检查入口已就绪 |

## 5. M1 分派入口

见 `docs/execution/m1-tasks.md`：SIM-01 为唯一 READY，其余按依赖依序解锁。M1 不得等待 M2/M3 才补齐单人闭环。

## 6. 未运行 CI 的说明

当前目录不是 Git 仓库、无远程托管，故 CI 未运行。**不把“未运行 CI”写成通过**；本地检查入口与 CI 接入说明已就绪（`tools/test/check.sh` 可直接作为 CI 步骤）。
