# ADR：加密连接路线与身份流程（NET-01）

日期：2026-09-09；状态：**候选路线，本机 macOS 多进程实验通过；LAN/异地双机未验证（INT-02 补）**  
关联：契约 §7；时间盒结论在 3 个工作日内完成，未触发 TLS/WebSocket 后备评审。

## 1. 决策

**生产路线维持基线：ENet/UDP + DTLS（Godot 低层 ENetConnection + TLSOptions）**。理由与关键证据：

1. **高层 API 不可用**：Godot 4.7.2 的 `ENetMultiplayerPeer` **没有暴露任何 DTLS/TLS 选项方法**（ClassDB 内省证实：仅有 create_server/create_client/create_mesh/add_mesh_peer/set_bind_ip/get_host/get_peer）。若走高层 API 只能明文，违反 PRD“长期凭据必须经加密传输”红线。
2. **低层 API 完整可用**：`ENetConnection.dtls_server_setup(TLSOptions.server(key, cert))` 与 `dtls_client_setup(hostname, TLSOptions.client(trusted_chain, cn_override))` 在 macOS 实测工作；受信证书握手、错误证书拒绝均按预期。
3. 因此 M2 的 TransportPort 适配器必须基于**低层 ENetConnection 自建消息层**（可靠有序控制/业务通道由 ENet packet flags 表达），并复用 NET-01 已验证的握手/身份时序。

**客户端证书校验规则**：`TLSOptions.client(server_cert, "")` + `dtls_client_setup("localhost"/主机名, options)`——信任锚是连接卡里分发的服务器证书本身（自签、单服务器场景），主机名校验开启。**`client_unsafe()` 禁止出现在生产路径**（仅允许出现在本实验的对照组中；本实验未使用）。

## 2. 身份与加入流程（候选，与契约 7.2 对齐的部分已实验）

1. 房主生成 2048-bit RSA 密钥 + 自签证书（`Crypto.generate_rsa/generate_self_signed_certificate`），PEM 存世界私有目录。
2. 客户端本地生成 256-bit 随机凭据（`Crypto.generate_random_bytes(32)`），DTLS 连接建立后发送 `join_req{token, display_name}`；**凭据经环境变量传入实验进程**，服务器只计算 SHA-256 摘要存储，日志仅出现摘要前缀 12 字符（实验含泄漏扫描断言）。
3. 服务器规则（已实验）：同摘要已有活跃连接 → `duplicate_session` 拒绝；手动模式进入待审批队列（容量 8、TTL 过期、同摘要只保留一项）；自动模式受 4 席位上限；满员 → `server_full`；优雅关服前广播 `server_closing`。
4. 消息为单包 JSON（ENet 保包边界），可靠模式 `FLAG_RELIABLE`；低层事件循环 `service() → [event, peer, …]` + `peer.get_packet()/put_packet()`。

### 连接卡格式候选（M2 冻结为正式 schema）

```json
{
  "card_schema_version": 1,
  "address": "192.0.2.10",
  "port": 24642,
  "tls_hostname": "localhost",
  "server_certificate_pem": "-----BEGIN CERTIFICATE-----\n...",
  "world_display_name": "朋友的农场",
  "protocol_version": 1,
  "created_at_utc": "2026-09-09T00:00:00Z"
}
```

- 含地址/端口/证书/世界显示名/协议版本；**不含**成员凭据、服务器私钥、任何私有 ID。
- 客户端把 `server_certificate_pem` 作为唯一信任锚；证书更换 = 重发连接卡，不静默接受。
- 连接卡与 PublicSnapshot 不共用序列化器/导出入口（契约 7.2）。

## 3. 平台 API 备忘（M2 实现陷阱）

- `service()` 返回 `Array [event, peer, data, channel]`；RECEIVE 的数据**不在数组里**，必须 `peer.get_packet()`（继承自 PacketPeer）。事件值：NONE=0/CONNECT=1/DISCONNECT=2/RECEIVE=3/ERROR=-1。
- `Crypto.generate_self_signed_certificate` 的日期格式是 `YYYYMMDDHHMMSS`，issuer 必须含 `CN=/O=/C=`，否则静默生成**空证书**。
- 断开时 mbedTLS 可能打印 `bio_recv` 噪声错误到 stderr，属已知引擎噪声，UI 不得把它当用户错误展示。

## 4. 未验证项

| 项 | 状态 | 补验安排 |
|---|---|---|
| LAN 双机、真实异地公网 IPv4 | 未验证（本机 127.0.0.1 多进程不能替代） | INT-02，需真实网络资源（§资源门禁） |
| 双重 NAT/CGNAT 边界 | 未验证且 V1 不承诺直连 | 用户文档明示；不做绕过 |
| Windows DTLS 行为 | 未验证 | QA-02 |
| 证书轮换/吊销 | V1 只做“换卡重发”，无吊销基础设施 | 文档明示信任边界 |
| 20Hz 权威模拟下的带宽 | 本实验未压测 | PERF-01 |

## 5. 实验证据

见 `docs/testing/NET-01.md`（6 场景 × 2 轮全部通过：受信握手、错误证书拒绝、重复身份、4 席位 + 拒绝第 5、8 待审批 + TTL 过期 + 第 9 拒绝、优雅关服通知）。实验代码 `work/net-spike/`（独立最小工程）。
