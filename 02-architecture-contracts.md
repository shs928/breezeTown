# 微风小镇 V1：架构与协作契约

版本：0.3；日期：2026-09-08  
状态：可执行设计基线；M0 验证具体 API 并冻结接口。本文定义实现边界，不表示工程或接口已经存在。

## 1. 架构原则与技术决策

### 1.1 模块化单体，不提前微服务化

一个游戏工程、一套世界模型、一条权威业务提交路径。客户端、房主、无界面服务器通过启动组合选择功能，不各自复制玩法实现。

```text
客户端表现层 ── 本地或网络命令入口 ── 会话与身份校验
                                         │
                                  Application / 命令协调
                                         │
                         Domain / 世界、农务、物品、经济、建设
                                         │
                          同步提交状态、事件、统计投影
                              │                    │
                        存档适配器             状态视图 / 同步
                              │                    │
                        私有世界文件          界面 / 公开 DTO
```

依赖方向：表现层依赖应用入口和只读视图；应用层依赖领域和端口；基础设施实现端口；组合根创建并连接各模块。领域不得反向调用 UI、网络连接、文件系统或全局服务定位器。

Godot 的场景组织指南强调低耦合和单一职责，可作为节点拆分参考；具体目录和业务分层是本项目设计，不是引擎强制要求。[S3]

### 1.2 建议基线及 M0 决策项

| 项目 | 建议基线 | M0 输出 |
|---|---|---|
| 引擎/语言 | Godot 4.x 稳定版，GDScript，类型化业务数据 | 精确版本、导出模板、下载来源、许可证、版本锁定文件 |
| 网络 | ENetConnection 适配器，DTLS 加密，应用消息协议 | 双机握手、证书校验、消息通道、Windows/macOS 导出证据 |
| 后备决策 | 若上述路线在时间盒内不成立，评审 TLS/WebSocket | 只能冻结一条生产路线；重写通道/性能假设，不保留双路线半成品 |
| 持久化 | 本地 JSON 快照 + 完整性校验 + 代际备份 | 原子发布策略、文件锁和故障注入试验 |
| 测试 | 无界面领域测试 + 多进程集成测试 | 选择并锁定一个兼容测试方案；不并存多套框架 |
| 运行方式 | solo / listen_host / client / dedicated | 一套组合根；dedicated 不实例化 UI、音频或房主角色 |
| 内容 | 明确 schema 的数据文件 + 合法美术音频资源 | 加载校验和许可登记模板 |

不引入默认云后端、PostgreSQL、Redis、消息队列、容器编排、服务发现或运行时大模型。正式自建服包装可后续增加，业务核心不依赖这些设施。

Godot 的 ENetConnection 提供 DTLS 客户端/服务器配置，并要求在指定建连阶段完成配置；这些是 Godot 的扩展，需要实际验证，不能假定任意 ENet 实现均兼容。[S4] 本项目不直接以场景路径作为跨进程业务身份，也不把高层场景 RPC 暴露成任意方法调用。

### 1.3 三种身份不得混用

- `player_id`：服务器分配，单世界稳定成员 ID，用于背包、统计、角色和权限。
- `connection_id`：某次网络连接的临时标识，仅会话层使用。
- `public_player_id`：独立随机的单世界公开标识，仅用于获授权的公开 DTO。

同理区分 `world_id` 与 `public_world_id`；昵称、场景节点名、IP 均不是权威身份。

## 2. 拟定工程目录与所有权

以下是将来工程内的相对路径，不是本轮已创建的代码目录。M0 依任务卡逐项建立；现有六份需求基线保留在项目根目录，`docs/` 用于新增决策、任务状态和报告。

```text
game/
  project.godot
  export_presets.cfg
  src/
    bootstrap/
    contracts/
    domain/
      world/
      inventory/
      economy/
      farming/
      projects/
      statistics/
    application/
      core/
      world/
      inventory/
      economy/
      farming/
      projects/
      reporting/
      session/
      sync/
    infrastructure/
      network/
      identity/
      persistence/
      public_export/
    client/
  scenes/
    bootstrap/
    client/
  content/
    definitions/
    schema/
    maps/
  assets/
  tests/
    unit/contracts/
    unit/simulation/
    unit/economy/
    unit/farming/
    unit/data/
    network/
    client/
    integration/
    acceptance/
    performance/
    security/
    fixtures/
tools/
docs/
```

精确写入权限见任务文档。领域与应用层按功能组织，避免所有功能共用一个可随意修改的 `GameManager`、`DataManager` 或全局可变字典。

共享 schema 由 FND 唯一写入、LEAD 审阅；FARM 管作物/项目定义，ECON 管经济/物品定义。统计投影归 ECON，持久化与公开导出归 DATA。地图布局、美术和界面由 UI 管；地图的可通行/可耕字段格式由契约确定，不能由画面节点名称隐式决定。

## 3. 模块接口与运行模式

### 3.1 必要端口

名字是冻结前建议名。下面只列需要跨模块替换的边界，不为每个函数创建接口。

| 契约 | 核心职责 | 禁止事项 |
|---|---|---|
| CommandGateway | 接收绑定身份的命令，返回回执 | UI 绕过入口直接修改领域 |
| WorldRuntime | 推进模拟、排队命令、提供一致快照 | 读取键盘、操作窗口、依赖渲染场景 |
| TransactionCoordinator | 校验并原子提交状态/事件/统计 | 把统计更新丢给异步信号后宣称成功 |
| TransportPort | 连接、收发有界消息、断线；可靠/最新状态语义 | 决定价格、玩家归属或贡献分 |
| IdentityPort | 信任服务器、成员认证、连接与成员绑定 | 用显示名或客户端自报 ID 授权 |
| WorldRepository | 保存/加载快照、备份、校验、版本迁移 | 生长计算、币值计算、联网认证 |
| ClockPort | 受控模拟时间与独立现实时间读取 | 用客户端系统日期结算游戏日 |
| PublicExporter | 将已过滤的 PublicSnapshot 写入 HTML/JSON | 接收完整私有 WorldState |

内容定义作为只读 `GameRules` 注入世界服务；允许使用 Godot 的数学/容器基础类型，但核心规则不得要求活跃窗口、AudioServer、Input 或渲染节点。

### 3.2 运行组合

| 模式 | 领域权威 | 网络监听 | 本地角色/界面 | 在线人数计算 |
|---|---|---|---|---|
| solo | 本机 | 无 | 有 | 1 |
| listen_host | 本机 | 有 | 有 | 房主 + 远端 |
| client | 远端 | 无 | 有，只有视图/预测 | 由服务器提供 |
| dedicated | 本机 | 有 | 无 | 仅真实已加入的客户端 |

本地房主通过 `LocalCommandGateway` 调用相同路由/校验/事务。网络层编解码可跳过，权限、顺序、容量、距离、价格和计分不能跳过。

M1 的 NET-00 先实现本地 IdentityPort：生成并持久保存本地凭据，提供候选所有者和本地会话；与世界首次保存组合成功后才激活身份。ECON 只按传入的合法成员 ID 创建库存，不生成凭据或写身份绑定。M2 的 NET-02 在此基础上接入远端认证，保持原有成员身份。

SIM 在 `application/world` 从只读地图数据计算碰撞、生成按玩家权限过滤的视图；NET 在 `application/sync` 负责捕获、缓冲、编码与 revision 推进，复用同一视图过滤逻辑。FND-02 提供可通行/可耕格与设施区域的最小 schema 样例供 SIM 单测；UI-02 的正式地图通过同一内容加载器，在 INT-01 验证真实碰撞。

第一条农务闭环完成时就运行无界面 smoke：不需要完整 Linux 分发包，但必须证明世界能在没有玩家 A 的界面和角色时存在。Godot 支持 headless 和 dedicated-server 导出，这不自动保证应用层没有 UI 依赖。[S2]

## 4. 权威世界与数据模型

### 4.1 核心模型

| 模型 | 关键字段与边界 |
|---|---|
| WorldState | world_id、owner_player_id、schema_version、ruleset_version、content_hash、game_day、day_elapsed_ms、business_revision、next_event_seq、treasury、members、plots、projects、containers、stats、publication_enabled、consent_revision |
| WorldMember | player_id、join_order、role、status、display_name、credential_digest、public_player_id、publication_consent、public_alias、avatar、inventory_id、last_valid_position |
| CropInstance | crop_instance_id、crop_definition_id、tile_id、growth_days、planted_day、watered_day、revision；不记录场景节点路径 |
| Inventory | container_id、owner_type、owner_id、capacity、slots、revision；slot 是 item_definition_id + quantity |
| ProjectState | project_id、accepted_quantities、completion_day、revision |
| StatisticsState | 各成员累计销售额/贡献分类、当前日与最近 30 个完成日、世界累计销售/采购、last_applied_event_seq |
| RuntimeSession | authority_epoch、connection bindings、per-player command high-watermark、receipts、sim_tick；主要为运行期数据 |

`authority_epoch` 每次权威进程启动或恢复世界时生成新随机值。`business_revision` 和事件序号来自存档；恢复备份可能回退，所以不能把它们单独当成跨恢复永远递增的标识。

所有者由持久化的 owner_player_id/成员角色指定，是否渲染该角色不影响管理权限。创建世界时建立本地身份凭据，dedicated 由该成员在普通客户端登录管理；本机停服维护入口用于丢失凭据时重绑定，不能由网络消息调用。

### 4.2 数值和字段限制

- 业务整数必须有限、无小数；金额/积分/序号上限统一为 `9_000_000_000_000`，低于 JSON 安全整数上限。解析后重新校验，不依赖隐式类型转换。
- 一次可交易数量 `1..99`；负数、0、小数、NaN/Infinity、超过上限均拒绝。
- 世界名和昵称分别最长 32 个 Unicode 字符且 UTF-8 不超过 128 字节；去除控制字符；不得当文件名、格式模板或可执行标签使用。
- 世界名、昵称及显式公开别名经去控制字符、首尾去空白后不能为空；公开别名沿用昵称长度限制。名称允许重复，身份仍由 ID 区分。
- 固定定义 ID 只接受内容目录白名单，动态 ID 是受控随机值；文件路径不能来自任意客户端参数。
- 同一世界最多 16 个历史成员、4 个在线成员、256 个耕作格；版本变更前不提供任意无限扩容配置。
- 单条普通业务消息最大 16KiB；单次客户端世界视图快照最大 2MiB；单个私有存档文件最大 16MiB；上限不成立时以 ADR 变更而非直接关闭校验。

## 5. 统一命令、事件和事务

### 5.1 命令信封

```json
{
  "protocol_version": 1,
  "world_id": "world-example",
  "authority_epoch": "epoch-example",
  "client_sequence": 12,
  "command_type": "farming.plant",
  "expected_versions": {"inventory": 8, "tile": 2},
  "payload": {"tile_id": 515, "seed_slot": 3, "seed_definition_id": "seed.radish"}
}
```

示例中的 ID 是文档占位值，不是生产 ID 编码。生产随机标识格式由 FND-02 冻结。

信封不含可授权的 `player_id`、客户端价格、最终金额或贡献分；服务器从已认证会话绑定获得操作者。业务时间由服务器填入。`expected_versions` 只检查此次涉及的聚合，不能因为别人移动一步就拒绝所有操作。

### 5.2 首版命令集合

| 命令 | 输入意图 | 成功后的核心事实 |
|---|---|---|
| world.move_input | 输入方向、输入序号 | 校验后的移动状态；不进入经济日志 |
| farming.till | 地块 | PlotTilled |
| farming.plant | 地块、种子格 | CropPlanted，种子扣除 |
| farming.water | 作物/地块 | CropWatered |
| farming.harvest | 作物/地块 | CropHarvested，产物入包 |
| inventory.transfer | 本人背包/共享仓库的来源、目标、格与数量 | ItemsTransferred；本人背包内整理同样校验容量/格版本 |
| economy.buy_seed | 商品定义、数量 | SeedPurchased，扣款、入包 |
| economy.sell | 背包格、产物定义、数量 | ProduceSold，扣物、加款 |
| projects.donate | 项目、物品、数量 | ProjectDonated；必要时 ProjectCompleted |
| economy.claim_relief | 领取意图 | ReliefGranted，无收益/贡献 |
| profile.update | 本人昵称 | MemberProfileChanged；avatar 由初始配色分配，首版不接收外观修改 |
| privacy.set_publication | 同意状态/别名 | PublicationPreferenceChanged |
| owner.set_publication | 世界公开总开关 | WorldPublicationChanged，保存成功后才生效 |
| owner.member_action | 批准/踢出/撤销/重新绑定 | 受权限保护的成员变化 |
| owner.save/export/close | 保存、公开导出或关闭意图 | 应用工作流，不伪造玩法收益 |

移动与管理工作流使用各自冻结的有界 schema。已认证成员的管理操作沿用业务序号和幂等回执；认证前申请用单独请求 ID，并以凭据摘要合并待审批项。禁止使用未受控字典兜底。

### 5.3 业务提交顺序

1. 校验信封、协议/世界/epoch、身份、权限、速率、序号；解析出绑定身份。
2. 在单写入线程/队列上获取相关状态，校验距离、格版本、数量、价格定义和玩法前置条件。
3. 构造待提交变更、事件及统计变更；此时不向真实容器写入任何一半的结果。
4. 验证所有后置不变量；任一规则或统计投影失败则丢弃整个批次。
5. 一次性应用状态和统计、追加事件、更新业务 revision 和回执；形成内存中的提交点。
6. 返回成功/失败回执，发布只读视图差量；音效、动画、导出等副作用只能在提交后发生。
7. 保存调度器捕获某个完整已提交 revision；失败不倒扣内存中的已生效经济，但进入 SAVE_FAULT，暂停模拟/后续修改及公开导出，直到完整保存成功。

V1 使用内存原子业务批次与整体快照，不宣称数据库 ACID 或每笔交易立刻落盘。业务一致性和崩溃后的持久性是两个不同保证。

身份批准、凭据重绑/撤销、公开同意属于需要持久化确认的控制事务：在屏障内构造候选状态，保存并验证后再发布为活跃状态/返回最终回执；失败不激活候选身份或授权，保留最后有效绑定，并进入 SAVE_FAULT。只允许一个控制事务在途；保存成功后回执丢失可从已确认状态查询结果，不能重复创建成员。普通 UI、角色或统计信号都不能承担这些事务。

世界公开开关也使用控制事务。`consent_revision` 在世界开关、成员同意/撤回、公开别名或“使用昵称”选择变更时递增；已选择公开昵称的成员改名时，同步更新该版本并持久化确认。导出发布时同时检查世界总开关和 `consent_revision`，避免生成期间关闭公开后仍发布。普通背包内部转移只递增该容器一次 revision；不得将来源和目标相同视为两次独立扣加。

### 5.4 必须长期成立的不变量

- `treasury = 300 + total_sales - total_purchases`。
- 每个容器内数量 `1..99`，空格无定义 ID；容器不超过容量，作物实例不重复占格。
- 收获的作物消失与产物入包必须同时发生；失败不能先清地。
- 每个作物的同日浇水最多贡献一次；成熟后的水不增加积分。
- `sum(member_total_sales) = total_sales`；今日对应当前游戏日桶。
- 当前统计等于统计 checkpoint 加尚未压缩的事实事件投影。
- 项目接受数不超过需求，完工与效果只结算一次。
- 认证、权限和公开同意不能通过一个普通玩法事件被修改。

### 5.5 业务事件

```json
{
  "event_id": "event-example",
  "event_sequence": 108,
  "world_id": "world-example",
  "business_revision": 72,
  "actor_player_id": "member-example",
  "game_day": 4,
  "event_type": "ProduceSold",
  "ruleset_version": "v1.0",
  "payload": {"item_definition_id": "produce.radish", "quantity": 10, "unit_price": 24, "gross_amount": 240}
}
```

事件由服务器生成，并记录当时已裁定的数量、币值、贡献分类/分数或规则版本。重放已有事件不得拿当前商品价重新计算历史金额。事件是事实，不是可以由客户端任意广播的通知。

V1 不做全世界事件溯源。位置高频更新不进经济日志。事件 ID 独立随机，不能因恢复旧快照复用；序号用于单条存档时间线内部顺序。

## 6. 幂等、并发和跨日

### 6.1 重试语义

- 幂等键是 `(authority_epoch, player_id, client_sequence)`，同时记录消息内容摘要。
- 每个成员的可靠业务命令顺序处理。MVP 同一成员最多一个待确认的经济/农务命令，界面显示处理中；移动不受此限制。
- 期望序号是 `last_sequence + 1`；同序号同内容重发返回原回执，不再执行。
- 已处理序号携带不同内容时拒绝；未来跳号返回所需序号；失败的已受理业务命令也占用序号。
- 每成员缓存最近 256 个回执，保留本 epoch 的序号高水位；超过缓存的旧请求返回 `RECEIPT_EXPIRED`，不能因为缓存过期而再次执行。
- 同 epoch 重连：认证后查询同步状态/回执，再决定是否重发尚未确认的同一命令。客户端丢失本地序号时从服务器查询高水位，不能从 1 覆盖已有操作。
- 每次 ACTIVE 绑定增加 connection_generation；断线时关闭旧绑定，新连接激活后拒绝旧连接残留消息。幂等键仍按成员/epoch，不因换连接重新结算。
- 传输/认证/限流失败属于未受理，不消耗业务序号；返回 accepted=false。已受理命令的业务失败 accepted=true，消耗序号并缓存回执，避免客户端无法判断是否推进。
- epoch 改变：清空客户端未确认动作，不自动重放旧命令；完整同步并提示可能恢复到最近存档。
- 不承诺跨不同 epoch 的“用户同一意图 exactly-once”；通过禁止自动重放和强制重同步防止隐式重复。

### 6.2 并发冲突

同一世界命令串行提交；两次请求各自使用提交时的现状，不使用客户端预判。容器和格版本只是改善冲突提示，最终条件校验仍必不可少。

例：A、B 同时取仓库里最后 1 个萝卜，第一个成功；第二个收到 `STALE_STATE` 或 `INSUFFICIENT_ITEMS`。不能出现两个客户端都收到成功，再靠稍后同步“修正”。

### 6.3 日切边界

世界计时达到边界时设置日切屏障。已进入当前批次的命令先完成；之后的业务命令等待屏障结束，按新游戏日执行或明确失败。日切本身在同一条权威提交路径上执行一次。

同时推进生长、重置浇水、递增天数、初始化当日统计桶和更新 `DayAdvanced` 标记。保存捕获日切前或日切后的完整状态，不允许保存一半旧日一半新日。

## 7. 网络、认证和状态同步

### 7.1 传输边界

ENet 基线使用 UDP，通常需要正确端口转发才能跨家庭网络入站；局域网通不证明公网可达。Godot 官方文档也明确了 UDP 和端口转发要求。[S1]

- 暂定 UDP 端口 24642，允许用户在开服前修改；占用时明确报错，不悄悄换端口。
- V1 承诺 IPv4 可达地址或解析到 IPv4 的主机名；IPv6、UPnP 自动配置、NAT 打洞、官方中继不纳入承诺。
- 不默认修改路由器、防火墙或运行公网 HTTP 服务。
- 如果 M0 选择 TLS/WebSocket，正式契约必须相应改为 TCP、通道复用语义和新的网络验收，不能仍对用户展示 UDP 指引。

### 7.2 新成员和持久身份

目标是熟人私有世界的身份连续性，不是建立互联网账号平台。

1. 房主生成本世界的服务器证书/私钥和可分享的“连接卡”；连接卡含地址、端口、服务器公开证书/指纹及目标世界信息，不含成员凭据或私钥。
2. 朋友通过可信渠道获取连接卡并确认；客户端用受信证书建立加密连接，凭据不能通过关闭证书校验的生产路径发送。
3. 客户端为该世界生成并本地持久保存高熵随机凭据，再经加密连接请求加入；由房主显式批准新成员。待审批最多 8 项、每项 60 秒、同一凭据摘要一项；审批成功保存才占历史槽位，拒绝/超时不占用。
4. 服务器保存凭据摘要、随机 player_id 与成员状态，不记录明文凭据。成员批准结果需完成一次有效保存后才发出“已加入”的最终回执。
5. 历史成员通过加密连接证明持有该凭据；服务器解析出绑定 player_id，不接受客户端自选旧成员身份。
6. 丢失凭据时由所有者核对新请求并选中既有成员重新绑定；一次控制事务内替换摘要，保存后关闭旧连接，保留 ID/背包/统计。所有者丢失凭据需停服本机维护，不能通过自报角色恢复。

凭据使用加密随机源生成，至少 256 bit；摘要/比较使用成熟库能力，不设计自制密码算法。准确 API、证书有效期/更新路径、错误反馈和导出平台行为由 `NET-01` 实验与 ADR 冻结。

客户端私有配置中凭据不得进入工程、日志或公开导出。世界备份包含认证摘要及私有服务器配置时属于敏感文件，不能当榜单附件公开。

连接卡是用户主动给好友的连接资料，与面向公开榜单的 `PublicSnapshot` 完全不同；两者不能共用导出按钮或序列化器。

### 7.3 会话状态机

`DISCONNECTED → CONNECTING → TRUST_CHECK → AUTHENTICATING → WAIT_APPROVAL（新成员）→ SYNCING → ACTIVE → RECONNECTING / CLOSED`。

- ACTIVE 前不接受改变世界的命令，认证完成前不下发私有世界快照。建连/信任/认证阶段累计最多 15 秒；审批超时 60 秒，快照超时 10 秒。
- 心跳目标 2 秒；8 秒没有有效消息视为断线并释放在线槽位。
- 客户端自动重连退避 1、2、4、8 秒，累计最多 30 秒；随后由用户手动重试。
- 同成员旧连接尚未超时，重连可以等待，但不能建立两个 ACTIVE 身份或覆盖别人会话。
- 主机关服发送结束原因并关闭；突发崩溃走超时，不让客户端继续推进。
- 零真实玩家在线时世界暂停；未认证连接、机器人探针不算玩家。

### 7.4 消息通道

| 通道 | 内容 | 语义 |
|---|---|---|
| control | 版本、认证后控制、会话状态、心跳 | 可靠、有界；认证握手另限流 |
| business | 操作、回执、权威业务差量 | 可靠有序；同一视图 revision 有明确先后 |
| movement | 输入与位置快照 | 可丢弃旧包，以新序号为准；不承载金币或收获 |
| snapshot | 加入/重连的大快照分片 | 可靠，有总量/分片数/超时限制 |

Godot 文档介绍了可靠性、顺序和通道隔离；以上是本项目的逻辑通道分配，需适配所选低层 API，而不是照抄高层默认通道编号行为。[S1]

### 7.5 视图同步与移动

- 权威模拟目标 20Hz；移动输入最高 20Hz，位置下发目标 10–20Hz；客户端独立以显示刷新率渲染。初始角色速度 96 像素/秒；农务范围 48 像素，校验阻挡线段。只累加实际模拟步时间，休眠/暂停不按系统时钟补跑。
- 玩家可预测自己的移动并纠偏，远端角色插值；经济/背包/作物结果不做可结算的客户端预测。
- 移动方向归一化、限制频率和最大速度，服务器负责碰撞与操作距离；最终位置不能由客户端直接覆盖。
- 加入时捕获 revision R 的玩家视图快照，缓冲 R 之后差量；完整校验并应用 R 后再顺序应用缓冲，最后开放操作。
- 快照仅包含该客户端有权见到的数据；不发送其他成员完整背包或凭据摘要。
- 差量包含 base_revision / target_revision；发现缺口要求重同步，不猜测缺失操作。
- 与本客户端无可见变化的提交仍发送轻量 revision 推进标记，避免因私有数据过滤制造虚假缺口。
- 同步缓冲上限 2MiB/10 秒，超限中止并重新捕获快照；不无限积累内存。
- 位置用独立 sim_tick/input_sequence 去旧包，不让每帧移动触发经济 revision、存档或排行榜刷新。

### 7.6 错误码最小集合

`NOT_AUTHENTICATED`、`NOT_ALLOWED`、`WORLD_MISMATCH`、`VERSION_MISMATCH`、`STALE_EPOCH`、`STALE_STATE`、`INVALID_ARGUMENT`、`OUT_OF_RANGE`、`INVENTORY_FULL`、`INSUFFICIENT_ITEMS`、`INSUFFICIENT_FUNDS`、`TARGET_CHANGED`、`RATE_LIMITED`、`SEQUENCE_GAP`、`RECEIPT_EXPIRED`、`SYNC_REQUIRED`、`MEMBER_LIMIT`、`ONLINE_LIMIT`、`DUPLICATE_SESSION`、`SAVE_FAILED`、`SAVE_UNAVAILABLE`、`SERVER_CLOSING`。

UI 使用本地化文案映射，不把异常堆栈、用户路径或凭据显示成普通错误提示。

## 8. 存档、备份与搬迁

### 8.1 一个世界一个写入者

启动前取得世界级进程写锁；锁冲突拒绝启动。跨 Windows/macOS/Linux 的具体锁/崩溃残留恢复方案在 M0 验证；不能用“看到 lock 文件就自动删”代替活跃进程检查。

拟定私有布局：

```text
user_data/worlds/<world_id>/
  manifest.json
  snapshots/<generation>.json
  backups/<manual_backup_id>/
  private/server_certificate.pem
  private/server_private_key.pem
  runtime.lock
```

本地客户端身份配置独立于世界目录；玩家在同一台设备上改为连接专用服时仍使用原身份。导出世界不要求泄露客户端明文凭据。

### 8.2 发布一个有效快照

1. 从已完成业务提交点捕获不可变的世界数据副本，包含统计和事件 checkpoint。
2. 在后台序列化并校验；写入同一文件系统上的临时文件，完成可用的 flush/close。
3. 对实际写入字节验证 checksum 和可解析性；发布为新的唯一 generation 文件，不先删除上一份。
4. 最后更新可选 manifest 提示指针。指针不是唯一真相；启动可扫描经校验的完整快照。
5. 只有新快照验证通过后才清理超出最近 5 代的自动快照；手动备份不参与轮转。

校验和用于发现损坏，不是防房主作弊的签名。任何跨平台原子性/刷新保证都要用故障测试证明，不在 PRD 中假定调用 rename 即有无限可靠性。

建议 envelope 包含 format_version、world_id、generation、payload_json（按原字节保存的 JSON 文本）及该 UTF-8 文本的 SHA-256，避免读取后重新序列化造成 checksum 不一致。最终格式和样例在 FND-02 冻结。

同一世界只允许一个保存作业执行，周期请求合并到下一个一致快照；不得让旧异步作业晚完成后覆盖更新的 generation。generation 单独单调增长，不复用 business_revision（没有业务动作时游戏时间仍变化）。每个快照还携带捕获时的 sim_tick、epoch 和控制事务版本。

保存故障状态遵守 PRD 11.1：任何一次保存明确失败即暂停世界；尚无明确结果但运行中超过 35 秒没有成功保存也触发暂停，拒绝新的修改（SAVE_UNAVAILABLE、未受理），禁用公开导出。重试或“另存完整恢复包”成功后才解除；若用户放弃退出，报告未保存而不伪报成功。系统休眠时间不参与 35 秒故障检测。

控制事务的候选快照与普通保存共用这一队列和互斥屏障。恢复时选最新已验证、已发布的 generation；不能只按易受改时钟影响的时间戳选择。

### 8.3 日志有界化与统计恢复

- 完整私有快照是恢复真相；不需要重放所有历史玩家动作才能加载。
- 保留最近 10,000 条关键事实事件，含经济、贡献、仓库/控制诊断记录；较旧事件折叠到统计 checkpoint，不保留无限增长日志。非计分事件对统计为无操作但推进处理水位，避免混合事件序列被误判为遗漏。
- checkpoint 记录截止事件序号和当时累计/日统计；重算是 checkpoint + 后续事件，必须与当前物化统计一致。
- 当前日及最近 30 个已完成游戏日摘要保留；更旧的日明细删除不影响累计值和对账。
- 压缩在一致快照边界进行，不能先删除事件再保存 checkpoint。
- 这是有限窗口诊断，不宣称永久审计。改变规则后依然沿用事件中已裁定分数，不重新解释历史事实。

### 8.4 恢复与版本

- 加载前校验文件大小、envelope、checksum、schema、world_id、定义版本及结构不变量。
- manifest 无效或最新快照损坏时列出可恢复的有效代；要求用户确认回退并说明时间/游戏日，不静默抹去进展。
- 显式恢复旧代前保留原件，生成新 epoch，清空全部 credential_digest 绑定及公开同意；通过本机停服维护先恢复所有者，再核对并重绑成员，保留原 ID/财产/统计。防止旧快照复活已撤销凭据或已撤回授权。正常最新代启动与正常停服迁移不清空绑定。
- 存档升级在副本执行，成功后发布新代；未来版本和缺失迁移路径明确拒绝，不吞掉未知字段后继续。
- V1 新世界可以只有 schema 1，但迁移机制必须用测试用 schema 0→1 fixture 验证；不编造对不存在历史发行版的兼容承诺。

### 8.5 搬到专用服

V1 搬迁验证流程：所有者关闭世界 → 完成快照 → 导出私有迁移包 → 校验包 → 目标导入 → 无界面启动 → 原玩家使用原身份资料加入 → 验证物品/资金/榜单/游戏日/建设一致。

- 保持 world_id、成员 ID、公开标识和数据；生成新 authority_epoch。
- 迁移包包含版本信息、世界快照、必要私有服务器配置及文件校验清单，不含进程锁和临时文件。
- 如服务器证书改变，必须通过可信渠道重新发连接卡；不能静默接受替换证书。
- 原权威实例必须停服，不支持两个服务器同时写入/合并“同一个世界”；无法阻止用户手工复制，但产品不承诺分叉再合并。
- 导入拒绝路径穿越、绝对路径、符号链接和超限解压内容；解压总量上限暂定 100MiB。
- 完整社区服安装器、监控、Web 管理台、在线迁移、容器镜像不属于本版成品范围。

### 8.6 dedicated 技术证明的最低交付

V1 在开发用 macOS 上验证，下列是待实现的项目参数接口，不是 Godot 内置选项：

```text
godot --headless --path game -- --mode=dedicated --world-dir=<absolute-world-dir> --port=24642
```

只加载现有已验证世界，不自动建新世界；从目录读取私有服务器配置，默认绑定所有 IPv4 网卡，日志不输出凭据。原所有者通过普通客户端管理；正常退出信号及 owner.close 都先屏障停止操作、保存、通知客户端、释放锁并退出；保存失败按故障流程返回非零状态，不宣称成功。M0 冻结实际参数和 SIGTERM/退出处理方式。Linux 长期发行包、服务守护、容器和管理网站留在后续版本。

## 9. 榜单与公开导出契约

### 9.1 统计不是松散订阅者

累计收益和贡献投影参与同一次业务提交。UI 刷新通知可以丢失，统计结果不能因为信号未连接而漏记。

`StatisticsProjector` 根据已确认事件及当时规则裁定结果更新。去重依据事件序号/事件 ID，并检查 checkpoint 水位；读取榜单只查询只读物化视图，不每帧扫描完整日志。

### 9.2 PublicSnapshot

```json
{
  "public_schema_version": 1,
  "public_world_id": "public-world-example",
  "world_display_name": "朋友的农场",
  "generated_at_utc": "2026-09-07T08:00:00Z",
  "game_day": 4,
  "ruleset_version": "v1.0",
  "source_kind": "self_hosted_snapshot",
  "ranking_scope": "consenting_members_only",
  "entries": [
    {
      "public_player_id": "public-member-example",
      "alias": "园丁一号",
      "total_gross_sales": 240,
      "today_gross_sales": 96,
      "contribution_total": 35,
      "contribution_breakdown": {"planting": 10, "watering": 5, "harvesting": 12, "donation": 8},
      "ranks": {"total_gross_sales": 1, "today_gross_sales": 1, "contribution_total": 1}
    }
  ]
}
```

日期和数值为说明样例，不是实际玩家数据。实际输出必须通过白名单 schema，拒绝额外属性，并从同一个一致 revision 生成全部三榜。

- 世界总开关关闭时禁止生成或发布新公开包；按钮提示先授权，不自动打开。已生成在途作业也必须取消。
- 同意为本世界三榜与分类的一组授权；公开随机 ID 跨快照稳定且不跨世界复用。行过滤后重新计算名次；空列表显示“暂无同意公开的成员”。别名可重复，短公开标识辅助区分。
- 别名必须作为纯文本转义；不解释 HTML、模板或脚本，不使用原始昵称作为文件路径。
- JSON 和 HTML 成对使用同一已确认快照；发布前再检查世界总开关和 consent_revision，授权变化则取消/重新生成，不发布捕获之后已撤回的行。授权复核与导出目录最终发布在控制事务屏障内排序，关闭/撤回先提交则该作业不得发布；不能在异步写文件前只检查一次。两文件写入同一临时包目录、验证完整后一次发布新导出目录，任一失败不留下半对文件。显示生成时间与非实时提示；不提供远程删除他人副本的虚假承诺。
- 固定安全文件名，版本/时间后缀不包含用户输入；不默认覆盖未经确认的用户文件。

## 10. 版本、观测和安全

### 10.1 四个独立版本

- `game_version`：发行包语义版本，如 0.1.0-rc.1。
- `protocol_version`：消息/行为兼容性；V1 要求精确兼容。
- `save_schema_version`：持久结构与迁移路径。
- `ruleset_version` + `content_hash`：数值、地图/碰撞及物品定义；联机两端必须匹配，避免“客户端看见能种、服务器不能种”。

公共导出另有 `public_schema_version`。改变 UI 排版不应自动使存档不兼容；改变规则也不应由玩家临时编辑配置热加载。

### 10.2 日志与诊断

记录：版本、运行模式、请求关联号、错误码、处理耗时、保存状态、重连原因、快照大小和吞吐。可使用脱敏的单世界成员关联标识，不记录凭据、认证信封全文或公开发布成员 IP。

本地日志限额轮转，建议 5×5MiB。诊断导出先预览/脱敏；不开默认远程遥测。不用 `print(WorldState)` 或完整网络抓包充当面向普通用户的诊断日志。

### 10.3 防滥用底线

身份前后分别限流；普通业务目标每成员最多 10 次/秒、短时突发 20；移动最多 30 次/秒、突发 60；具体令牌桶参数由网络测试修正并留记录。

先检查长度/类型/枚举再分配大型对象；拒绝任意 Resource/Object 反序列化、动态方法名调用、来自客户端的文件路径和未经授权的 owner 命令。协议错误重复出现可断开，不崩溃整个房主进程。

## 11. 不提前实现的扩展点

- 新玩法：增加领域模块、命令、事实事件与可选统计处理，不要求改运输层和 UI 总控。
- 正式社区服：复用 dedicated 组合，增加部署/配置/管理包装，不复制 WorldState。
- 平台账号与中继：替换 IdentityPort / TransportPort，保留 player_id 与业务命令语义；映射方案另行评审。
- 数据库：未来替换 WorldRepository；没有容量/并发证据前不切数据库。
- Web 榜单：消费 PublicSnapshot 或后续只读服务；不直接接触完整存档。
- 不实现通用插件引擎、全功能 ECS、分布式世界分片或热加载脚本系统。

## 12. 技术依据与核实边界

以下均为 Godot 官方一手文档。相关网页于 2026-09-07 查阅；stable 路径会随官方版本更新，因此 M0 需登记实际引擎版本及对应版本文档，本文不声称某个具体次版本是“最新”。

- [S1] High-level multiplayer：UDP/端口转发、可靠性、通道、服务器权威。[High-level multiplayer](https://docs.godotengine.org/en/stable/tutorials/networking/high_level_multiplayer.html)
- [S2] Exporting for dedicated servers：headless、专用服导出及资源剥离。[Exporting for dedicated servers](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_dedicated_servers.html)
- [S3] Scene organization：低耦合、显式依赖与单一职责。[Scene organization](https://docs.godotengine.org/en/stable/tutorials/best_practices/scene_organization.html)
- [S4] ENetConnection：DTLS 配置方法、调用时机和 Godot 扩展约束。[ENetConnection](https://docs.godotengine.org/en/stable/classes/class_enetconnection.html)

本文其余数值、schema、角色和流程是本项目提出的设计约束，不是官方性能保证。文档存在 API 可能性不等于目标平台已验证；NET-01、FND-01 和 QA 门禁不能省略。
