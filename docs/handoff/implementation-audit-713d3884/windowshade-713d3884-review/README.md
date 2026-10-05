# WindowShade · 实施复核与下一轮执行单

审查日期：2026-10-05。

审查基线：`cursor/silent-effect-receipts` / `713d3884e31d4d6e698a7dc81df99219db1518b3`。
同期 `main`：`b271fcfb843e5caeb89c4e4960c9c8524f232ed6`。

本包包含审查和拟议工单，没有修改仓库，没有 Mac 整应用构建，没有新签名或发布，没有运行摄像头、蓝牙、Touch ID、锁屏、屏幕接管测试。

## 内容

- `REVIEW-AND-EXECUTION.md`：实施判断、具体代码缺口、Apple silicon 优化路线、全部原目标的验收方法。
- `execution-plan.json`：依赖顺序、文件、动作、验收与禁止事项。
- `sources.json`：本次实际阅读的关键仓库文件与 Apple 一手资料。
- `checks/NumericBoundaryProbe.swift`、`checks/run.py`：独立数值边界实验，不读取真实恢复日志，不是生产补丁。
- `evidence/`：本次 Linux Swift 数值实验的真实输出。

## 证据分界

仓库中的 M5 真机日志是开发者上传的历史测试证据。本轮阅读并核对了它们，没有把它们当成本轮亲自执行。

本轮实际执行的只有独立数值转换实验：Swift 6.2.1 / x86_64 Linux；17 条防御性解析断言通过。提取的 `Double → UInt32` 直接转换对 -1、NaN、Infinity、2^32 分别触发运行时陷阱；正常值 1 成功。这不等于已经复现完整 AppKit 救援过程。

`checks/run.py` 可在安装了 Swift 与 Python 的 Unix 系统执行。它会启动四个故意触发转换陷阱的隔离子进程，关闭 core dump；不启动 WindowShade。不要将 `unsafe-u32` 分支合入生产程序。

旧整改包的 pinned-blob 补丁不要套在这个新分支上。先在当前分支对应的干净副本上复核差异。
