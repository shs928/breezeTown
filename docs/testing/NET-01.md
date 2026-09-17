> **2D 历史记录，不作为当前开发依据。** 当前 3D 工作见 [V2 PRD](../product/01-product-prd-v2.md) 和 [当前任务板](../execution/task-board.md)；本文旧状态、路径和命令仅供追溯。

# NET-01 测试记录：DTLS 加密连接与身份实验

日期：2026-09-09；执行者：NET（主执行者兼任）  
环境：macOS 26.4 arm64；Godot 4.7.2-stable；全程真实多进程（每场景独立服务器进程 + 客户端进程组）

## 复现命令

```sh
GODOT=tools/engine/Godot-4.7.2-stable/Godot.app/Contents/MacOS/Godot
"$GODOT" --headless --path work/net-spike --script res://spike_orchestrator.gd
# 退出码 0=全部场景通过；运行数据与日志在 work/net-spike/run/<ts>/
```

## 实测结果（两轮，均通过）

| 轮次 | 结果 |
|---|---|
| 1 | `NET_SPIKE_OK scenarios=6`，exit=0 |
| 2 | `NET_SPIKE_OK scenarios=6`，exit=0 |

## 场景覆盖矩阵

| 场景 | 进程拓扑 | 预期 | 结果 |
|---|---|---|---|
| S1 受信 DTLS 握手 + welcome | 1 服务器 + 1 客户端 | 客户端 exit 0 | ✓ |
| S2 错误证书拒绝 | 服务器用 main 证书，客户端信任 decoy | 客户端 exit 2（连接受信失败），服务器不崩溃 | ✓ |
| S3 重复身份 | 同一凭据两个客户端（前者 hold 6s） | 第一名 welcome；第二名 `duplicate_session` exit 3 | ✓ |
| S4 四席位上限 | 4 个保持连接的客户端并发 + 第 5 名 | 4×welcome；第 5 名 `server_full` exit 3 | ✓ |
| S5 待审批队列与 TTL | 手动审批 TTL=2s：8 个并发等待 + 第 9 名 | 8×`approval_timeout` exit 4；第 9 名 `pending_full` exit 3 | ✓ |
| S6 优雅关服 | 服务器 max-run 4s，客户端 hold 8s | 客户端收到 `server_closing` exit 5 | ✓ |
| 凭据泄漏扫描 | 全部场景日志与退出码文件 | 凭据原文零出现；仅 SHA-256 摘要前缀 | ✓ |

## 实验中确认的引擎行为（已写入 ADR §3）

- `ENetMultiplayerPeer`（高层）在 4.7.2 **无 DTLS 选项**；生产必须用低层 `ENetConnection` + `TLSOptions`。
- `service()` 返回 `[event, peer, data, channel]`，RECEIVE 的包必须经 `peer.get_packet()` 读取。
- 自签证书日期格式 `YYYYMMDDHHMMSS`；issuer 缺 `CN=/O=/C=` 时静默生成空证书（已加生成后非空断言）。

## 未验证项

- LAN / 真实异地公网 IPv4 / 双重 NAT / CGNAT：无真实网络资源；INT-02 补验，配置方案已写入 ADR §4。
- Windows DTLS 导出行为：QA-02 补验。
- 长连接稳定性、带宽、限流参数校准：PERF-01 / M2 NET-04。
- 实验用 TTL（2s）与超时（8s）是缩短值，生产用契约值（60s/15s/10s），语义相同。

## 泄漏与安全说明

- 凭据 256-bit 由 `Crypto.generate_random_bytes` 生成；实验经环境变量传入子进程（非命令行参数），结束即清空。
- 日志只允许 SHA-256 摘要前缀 12 字符；orchestrator 对全部 `.log`/`.code` 文件做原文泄漏断言。
- 私钥 PEM 只存在于 `run/<ts>/certs/main/`（已 gitignore）；decoy 证书仅用于负向用例。
