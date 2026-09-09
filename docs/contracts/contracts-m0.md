# 微风小镇：契约候选（M0 / FND-02）

版本：候选 0（LEAD-01 复核后发布为契约 v1）；日期：2026-09-08  
状态：**候选**。本文件与 `game/src/contracts/`、`game/content/schema/` 一一对应；测试见 `game/tests/unit/contracts/test_runner.gd`（63 项检查全部通过，命令见 §8）。

## 1. 端口职责（契约 3.1 的 M0 候选签名）

| 端口 | 核心方法（候选） | 返回 | 禁止 |
|---|---|---|---|
| CommandGateway | `submit(command: Dictionary) -> Dictionary` | 回执 `{client_sequence, accepted, error_code, …}` | UI 绕过入口改领域 |
| WorldRuntime | `tick(delta_ms)`, `enqueue(cmd)`, `snapshot(revision)` | — | 读键盘/开窗口/依赖渲染 |
| TransactionCoordinator | `commit(batch) -> bool` | 全有或全无 | 统计走异步信号即算成功 |
| TransportPort | `send(channel, bytes)`, `poll()` | — | 决定价格/归属/贡献 |
| IdentityPort | `create_credential()`, `bind(connection, member)`, `verify(token)` | 绑定结果 | 用显示名/自报 ID 授权 |
| WorldRepository | `save(envelope)`, `load(world_id) -> envelope` | envelope | 生长/币值计算、联网 |
| ClockPort | `now_ms()`, `sim_elapsed_ms()` | int | 用客户端日期结算游戏日 |
| PublicExporter | `export(snapshot: Dictionary) -> Error` | 只接受白名单 DTO | 接收完整 WorldState |

## 2. 身份与随机 ID 格式（候选）

| 标识 | 格式 | 生命周期 |
|---|---|---|
| player_id | `m` + 32 hex | 单世界永久成员 ID |
| public_player_id | `pm` + 32 hex | 单世界公开榜专用，跨导出稳定 |
| world_id | `w` + 32 hex | 世界目录名（不同于世界名） |
| public_world_id | `pw` + 32 hex | 公开快照标识 |
| connection_id | `c` + 8..32 hex | 单次连接临时 |
| authority_epoch | `e` + 32 hex | 每次权威进程启动重新生成 |
| event_id | `ev` + 32 hex | 事件事实 ID，不复用 |
| crop_instance_id | `ci` + 32 hex | 作物实例，不复用 |

三者身份区分是硬规则：`player_id` ≠ `connection_id` ≠ `public_player_id`；昵称/节点名/IP 不是身份。定义 ID 白名单见 `items.json`/`crops.json`/`projects.json`；格式 `^[a-z][a-z0-9_.]{0,63}$`。

## 3. 数值与字段边界（实现于 ContractLimits）

- 业务整数上限 `9_000_000_000_000`；一次可交易数量 `1..99`；解析后重新校验，整值 float 归一化、小数/NaN 拒绝。
- 名称（世界名/昵称/公开别名）：去控制字符与首尾空白后非空、≤32 字符、UTF-8 ≤128 字节。
- 席位：历史成员 ≤16、在线 ≤4、待审批 ≤8（60 秒过期）、耕作格 ≤256。
- 容器：背包 24 格（快捷栏 6）、共享仓库 24→48 格；槽位载荷硬上限 0..47。
- 消息/文件：业务消息 ≤16KiB、玩家视图 ≤2MiB、私有存档 ≤16MiB。
- 节奏：游戏日 600,000ms；自动保存 30s；35s 无成功保存触发保存故障；快照保留 5 代；回执缓存 256/人；日摘要 30 天；事件日志 ≤10,000 条。
- 网络：心跳 2s/超时 8s；建连+信任+认证 15s；审批 60s；快照 10s；重连累计 30s；业务 10/s（突发 20）、移动 30/s（突发 60）。
- 初始世界：300 金币、共享仓库 20 粒萝卜种子、4 株成熟萝卜、耕地区 12×12。
- 贡献：种 +2 / 浇 +1 / 收 +3 / 捐 +2每件；整地、出售、采购、领救济、转移 0 分。

## 4. 命令信封（实现于 ContractEnvelopes.validate_command）

字段恰好为 `protocol_version, world_id, authority_epoch, client_sequence, command_type, payload`（+可选 `expected_versions`）。出现 `player_id/actor_player_id/price/unit_price/amount/points/contribution` 任一字段立即拒绝；载荷键集合精确匹配各命令 spec，未知键拒绝（客户端提交 `unit_price` 因此被挡）；`economy.claim_relief`、`owner.save/export/close` 载荷为空对象。命令白名单 15 个，见 `COMMANDS`。

## 5. 事件信封（validate_event）

字段恰好为 `event_id, event_sequence, world_id, business_revision, actor_player_id, game_day, event_type, ruleset_version, payload`。事件白名单 17 个（`PlotTilled…DayAdvanced/MemberApproved/MemberRevoked/MemberRebound`）。事件由服务器生成并携带当时裁定的价格/数量/分数；重放不按当前价重算。

## 6. 存档 envelope（validate_save_envelope / make_save_envelope）

`{format_version: 1, world_id, generation ≥1, payload_json, payload_sha256}`；校验顺序：字段集合 → format（未来版本拒绝）→ ID → generation → 大小 ≤16MiB → **SHA-256 对 payload_json 的 UTF-8 字节**（`String.sha256_text()`）→ payload 可解析。generation 单调递增，不复用 business_revision。

## 7. PublicSnapshot（ContractPublicSnapshot）

白名单：顶层 9 字段、行 7 字段、贡献分类 4 键、名次 3 键；任何白名单外字段（含 `source_ip`）拒绝；数值非负有界；`ranking_scope=consenting_members_only` 固定。`build()` 从显式行构造并重排名：数值降序、并列竞赛名次（1、1、3）、并列内按稳定次序。空行合法（“暂无同意公开的成员”）。别名渲染时转义（HTML 侧职责，M4 落地）。

## 8. 复现

```sh
GODOT=tools/engine/Godot-4.7.2-stable/Godot.app/Contents/MacOS/Godot
"$GODOT" --headless --path game --script res://tests/unit/contracts/test_runner.gd
# 实测：CONTRACTS_OK checks=63，exit=0（2026-09-08，macOS 26.4 arm64，Godot 4.7.2-stable）
```

合法样例 5 项、非法样例 17 项位于 `game/content/schema/examples/{legal,illegal}/`；示例地图 `map_town_minimal.json`（64×64，四出生点、五设施、12×12 耕地区⊆16×16 扩展区，附带 4 个非法变体）。内容整包（items/crops/projects）与地图由 `ContentValidator` 校验。

## 9. 已知边界与待办

- `protocol_version=0`、`save format_version=1`、`ruleset_version=v1.0-m0-candidate` 为候选；LEAD-01 冻结时 protocol 升 1，命名去 `-candidate`。
- 载荷 spec 是结构性边界；距离/库存/资金等玩法前置在 M1+ 处理器中执行（契约 §5.3 提交顺序）。
- 视图过滤 `ContractView.build_player_view` 是契约参考实现；SIM 的正式视图（M1）必须复用同一逻辑并通过同一校验。
- 成员管理命令（`owner.member_action` 的 `action`）在 M2 收窄为枚举 approve/kick/revoke/rebind。
- Windows 平台文件行为差异由 DATA-00/QA-02 记录，不属于本契约候选的验证范围。
