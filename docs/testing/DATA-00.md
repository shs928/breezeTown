> **2D 历史记录，不作为当前开发依据。** 当前 3D 工作见 [V2 PRD](../product/01-product-prd-v2.md) 和 [当前任务板](../execution/task-board.md)；本文旧状态、路径和命令仅供追溯。

# DATA-00 测试记录：存档发布与写锁实验

日期：2026-09-08；执行者：DATA（主执行者兼任）  
环境：macOS 26.4 arm64；Godot 4.7.2-stable；工具路径 `tools/engine/Godot-4.7.2-stable/Godot.app/Contents/MacOS/Godot`

## 复现命令

```sh
GODOT=tools/engine/Godot-4.7.2-stable/Godot.app/Contents/MacOS/Godot
"$GODOT" --headless --path work/save-spike --script res://test_runner.gd
```

## 实测结果（重复执行两轮，均通过）

| 轮次 | 结果 | 检查数 |
|---|---|---|
| 1 | `SAVE_SPIKE_OK` | 45/45，exit=0 |
| 2 | `SAVE_SPIKE_OK` | 45/45，exit=0 |

## 覆盖矩阵

| 场景 | 验证内容 | 结果 |
|---|---|---|
| 真实双进程锁竞争 | 父进程持锁 → 第二个**真实引擎进程**（claim_probe）被 `locked_alive` 拒绝；释放后子进程成功取得 | ✓ |
| 残留锁恢复 | lock.json 指向必死 PID → 安全接管 `claimed_stale_recovered` | ✓ |
| 活跃外部进程锁 | 自建存活进程持锁 → 拒绝（注：macOS 上不能用 pid 1，`kill -0` 对 root 进程 EPERM） | ✓ |
| 代际发布与轮转 | 发布 7 代 → 最新=7；1、2 被清理；3..7 保留；checksum 往返一致 | ✓ |
| write/verify/publish 故障注入 | 失败代从未出现（无 `2.json`）；上一有效代可加载；verify/publish 留 `.tmp-*` 诊断 | ✓ |
| cleanup 故障注入 | 新代完整、轮转挂起；加载正确返回新代 | ✓ |
| 损坏最新代 | 截断 → 回退上一代；原因记录 `unparseable`；损坏原件保留 | ✓ |
| 未来格式 | format_version=99 → 跳过；原因记录 `future_or_unknown_format`；上一代加载 | ✓ |

## 未验证项

- **Windows 实机**：锁/活性检查/rename 行为均未实测（无设备）；候选方案与风险见 `docs/adr/DATA-00.md` §2，列入 QA-02 补验。
- 断电级故障（非进程崩溃）：未模拟；不宣称断电零丢失。
- 35 秒保存故障保护、控制事务屏障、manifest 指针：DATA-01/02 范围。
- 局域网/异地文件系统（NFS/SMB）：不在 V1 承诺内，世界目录应在本地盘。

## 运行数据

每轮实验数据写入 `work/save-spike/run/<unix_ts>/`（已 gitignore，不入库）。
