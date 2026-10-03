# 进度（第十份并入 + 复核交接，2026-10-03）

## 契约摘要

三方合并并入第十份：`build.sh` 四条 swiftc 显式 Swift 6 / 完整并发检查 / 警告视为错误、
`--check` 不读本机签名配置；`Journal.journalID` 精确非零 UInt32；跑第十份自检、现有九套回归与一次
真实 Mac 构建（W00）；写一份给后续模型的复核交接。见 `.statem/task.txt`。

## 交付物身份

- 提交：`4f276ea`（第十份合并）、`e3e5b3b`（复核交接 + 台账）；上一轮 `af0437c`、`38bb231`（第九份）。未推送。
- 合并：5 替换 + 1 新增；`START-HERE`、`1.0.16 对照表` 走 `git merge-file` 三方合并（无冲突）。
- 归档：`docs/handoff/chatgpt-review-2/part10/`；仓库 runner：`tests/part10/`。
- 复核交接：`docs/handoff/round2-part10/REVIEW-HANDOFF.md`；证据在 `docs/handoff/round2-part10/evidence/`。
- Mac 适配（主模型补）：bash 3.2 空数组展开（`prototype/build.sh`）、`run-final.py` 报告路径 `/var` 规范化
  与 legacy 接线、`tests/part10/tools/stage.py` 的 `/var`+`resolve()`、`test-handoff-tools.py` 读 `drift.json`。

## 跑过的检查与结果

| 检查 | 结果 |
| --- | --- |
| `test-journal-id.py`（25 个边界） | 25/25；旧实现在 NaN/2^32 触发陷阱，true/1.5 被当窗口 1 |
| `test-build-entry.py` | 12/12（替身工具链，非 Mac 编译） |
| `test-handoff-tools.py` | 16/16（含漂移清单门禁） |
| `test-stage.py` | 18/18 |
| `run-final.py` 九套 | window-core / frame / foundation / native / duo / input / flow / legacy-foundation / legacy-process 全 PASSED |
| `run-final.py --suite mac-build`（真 SDK + Sparkle 2.10.0） | **FAILED，exit 1**：`build.sh --check` 报 98 处严格并发诊断 |

## 残余风险 / 关键结论

- **`main` 当前在显式 Swift 6 严格并发下编不过（98 处）**，W00 未完成。这是第十份打开构建参数后的
  真实结果，不是合并事故；没有为拿绿色撤销参数。三类：约 20 处是既有 warning 被升格
  （NoUsage / ImplicitStrongCapture / Deprecated / UnnecessaryEffectMarker），约 70 处是 Swift 6 语言模式
  新暴露的隔离问题（AddPreconcurrencyImport 22、MutableGlobalVariable 16、ConformanceIsolation 9、
  NonSendableExitingActor 2、SendableClosureCaptures 2、另有 29 处未带类别码）。
- `code-map` 漂移 21 条 + 1 条路径搬迁 + 1 条应当缺席，全部登记在 `tests/part10/DRIFT.md` / `drift.json`，
  并做成门禁（清单外新漂移会失败）。
- 第九份工单矩阵的受控真机观察（M01…M18）仍未做，等用户指定可动窗口。
- 未做：W01 起的真实验收、能耗、影片、签名发布；没有推送、打标签、改更新源或替换日用 App。

## 下一步

1. 等用户决定 W00 走哪条路（修到绿 / 退回参数 / 保留但标注不可构建）。
2. 交给后续更高智能的模型按 `REVIEW-HANDOFF.md` 的复核议程逐条复核。
