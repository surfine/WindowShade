# 实施审计落实状态 · 2026-10-05

来源：[REVIEW-AND-EXECUTION.md](REVIEW-AND-EXECUTION.md) / `execution-plan.json`。  
分支：`cursor/silent-effect-receipts`。审查快照：`713d388`。

| 工单 | 状态 | 本轮落地 |
| --- | --- | --- |
| R00 证据基线 | 已记 | FINAL-HANDOFF 当前指针；本目录落档；禁止旧 pinned-blob |
| R01 恢复日志数值 | 代码已加 | `JournalNumeric.swift`；Rescue 坏条目隔离；`tests/run-journal-numeric-tests.sh` PASS |
| R02 遮罩热插拔/Esc | 代码已加 | display ID/frame/epoch 对账；复用面板；临时 global Esc；屏参重建；静音页「撤掉遮挡」；`onClearRequested` 接线；隔离断言见 `run-silent-integration-tests.sh --case r02` |
| R03 异步终态 | 代码已加 | 统一 `watchAsyncEnd`：glance / pin / slideOver·leave / pip·leave / collapse（FoldCompletion）/ expand（离 shaded + 在屏）；超时更新 lastResult；台账换代作废隔离断言见 `--case r03` |
| R04 相机正向链 | 第一步 | `FacePipelineCounters`；milestone 打印 `head-pipeline`；接线断言见 `--case r04`；真机 10 秒单脸闭环仍待 Aaron 授权跑 |

未做：签名、发布、替换 `/Applications`；R05+ 测量与模型后端比较；CarPlay / 系统解锁终局。

验收提醒：授权成功≠采集成功；隔离数值测试≠整应用救援回归；异步 watcher 通过≠真机效果矩阵全部 pass。
