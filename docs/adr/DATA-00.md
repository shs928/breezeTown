> **2D 历史记录，不作为当前开发依据。** 当前 3D 工作见 [V2 PRD](../product/01-product-prd-v2.md) 和 [当前任务板](../execution/task-board.md)；本文旧状态、路径和命令仅供追溯。

# ADR：世界写锁与代际快照发布方案（DATA-00）

日期：2026-09-08；状态：**候选方案，本机 macOS 已实验验证；Windows 行为未验证**  
关联：契约 §8.1/§8.2；FND-02 envelope；正式实现在 DATA-01（WorldRepository），本 ADR 只固化 DATA-00 的实验结论与边界。

## 1. 决策

### 1.1 世界写锁：原子目录锁 + 持锁进程活性检查

- `user_data/worlds/<world_id>/runtime.lock.d/` 通过 `DirAccess.make_dir` 创建——`mkdir` 是原子系统调用，目录已存在即失败，天然互斥，跨 macOS/Windows/Linux 语义一致。
- 目录内 `lock.json` 记录 `{pid, started_at}`（恢复场景附 `recovered_stale`）。
- 第二实例启动时 mkdir 失败 → 读取 lock.json：
  - 持锁进程存活（`kill -0 pid` 退出码 0）→ **拒绝启动**（`locked_alive`），解释原因，不自动处理。
  - 持锁进程已死（崩溃残留）→ 拆除旧锁目录并重新竞争（`claimed_stale_recovered`）；并发竞争失败方按 `locked_by_racer` 退出。
  - lock.json 缺失/不可解析 → `locked_unreadable`，保守拒绝，不猜测。
- **禁止**“见到锁文件就自动删除”。

### 1.2 快照发布：临时写 → 验证 → rename → 轮转

1. 从内存一致状态序列化 envelope（format=1，含 payload_json 原文 + 其 UTF-8 SHA-256）。
2. 写 `snapshots/.tmp-<gen>.json`，`flush()` 后 close。
3. 重新读取**实际写入字节**，校验可解析性与 checksum；失败则中止（保留 tmp 供诊断），上一有效代不受影响。
4. 目标 `<gen>.json` 不存在时 `DirAccess.rename` 发布（POSIX rename 原子；generation 唯一，不覆盖）。
5. 轮转：只保留最近 5 个代；`.tmp-*` 不参与轮转判断。
6. 加载：从最高代向低扫描，逐个校验；损坏/未来格式**跳过并记录原因，不删除文件**（保留证据），返回第一个有效代及其 rejected 列表；无有效代则失败关闭。

### 1.3 故障语义（实验证实）

- write/verify/publish 任一阶段失败：目标代从未出现，加载得到上一有效代。
- cleanup 注入失败：新代已完整发布、只是旧代未清理——加载仍返回新代（这是正确的：轮转失败不损害一致性）。
- 四阶段注入（write/verify/publish/cleanup）+ 损坏最新代 + 未来格式共 45 项断言两轮全过。

## 2. 平台差异与未验证项

| 项 | macOS（已验证） | Windows（未验证，QA-02 前补） |
|---|---|---|
| mkdir 互斥 | ✓ | 预期等价（CreateDirectory 原子），需实测 |
| 残留锁活性检查 | `kill -0` | 无 kill；候选：`tasklist`/OpenProcess 查询，需 DATA-01 前定案 |
| rename 到不存在目标 | ✓ 原子 | 预期等价（MoveFileEx 非 MOVEFILE_REPLACE_EXISTING） |
| rename 覆盖已存在目标 | 未依赖 | Windows 上会失败——我们的 generation 唯一策略刻意规避了覆盖 rename |
| flush 语义 | flush+close 后掉电窗口存在 | 同左；不宣称断电零丢失（PRD 11.1 已声明） |

**与 FND-02 候选的兼容点**：envelope 字段集与校验顺序一致（format_version=1 / world_id / generation / payload_json / payload_sha256）；本实验为独立性自带最小校验，正式实现必须复用 `ContractEnvelopes.validate_save_envelope`，不允许第二套 schema。无冲突点。

## 3. 残余风险

- **PID 复用**：崩溃后同 PID 被新进程复用会把残留锁误判为活跃（保守方向的错误，安全侧）。缓解候选：lock.json 增加 boot_id（`sysctl kern.boottime`）比对；DATA-01 落地时决定。
- 崩溃残留 `.tmp-*` 会累积（DirAccess 不列出点文件，无法批量清扫）；影响仅占磁盘。正式实现可按已知 generation 前缀清理或换非点前缀，DATA-01 决定。
- 35 秒无成功保存的故障保护、控制事务屏障不在本实验范围（DATA-01/DATA-02）。

## 4. 实验入口

见 `docs/testing/DATA-00.md`。实验代码：`work/save-spike/`（自带独立最小工程，与主工程隔离）。
