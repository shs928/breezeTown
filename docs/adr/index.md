> **2D 历史记录，不作为当前开发依据。** 当前 3D 工作见 [V2 PRD](../product/01-product-prd-v2.md) 和 [当前任务板](../execution/task-board.md)；本文旧状态、路径和命令仅供追溯。

# ADR 索引

| ADR | 主题 | 状态 | 结论 |
|---|---|---|---|
| [M0-baseline.md](M0-baseline.md) | M0 技术门与执行基线冻结 | 已裁决 | M0 本机技术门通过；外部资源缺口挂起 |
| [NET-01.md](NET-01.md) | 加密连接路线与身份流程 | 候选路线（本机已验） | ENet/UDP + DTLS 低层 API；高层无 DTLS 选项 |
| [DATA-00.md](DATA-00.md) | 世界写锁与代际快照发布 | 候选方案（macOS 已验） | 原子目录锁 + rename 发布；Windows 未验 |

新增 ADR 规则：原因、影响 FR/NFR/任务/CASE、预计成本、替换/延后的工作、迁移与测试方案。既有范围内可逆的技术选择由 LEAD 判断；产品范围变化提交用户。
