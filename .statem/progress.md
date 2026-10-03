# 进度（第九份并入，2026-10-03）

## 契约摘要

把 ChatGPT 第二回合第九份并进 `main`：收起三态（hidden / visible / unknown）、完成通知绑定
transaction 与捕获的 waiter tokens、巡检不可变快照 + 批次/事务代次、AX observer 单调 routeID、
`EffectFrameAwaiter` 继承调用者隔离、原生 resize 去嵌套 RunLoop；按仓库既有写法修掉 macOS 上
实测出的 Swift 6 隔离错误；跑完全部自动化检查；再做一轮受控真机观察（只动明确允许的窗口，动手前确认）。
见 `.statem/task.txt`。约束：不签名/发布/推送/改更新源；`WS2FocusWindowPort.admitted=false`；
unknown 语义优先；中文提交信息。

## 交付物身份

- 三方合并（base=`base-sources/`、ours=HEAD、theirs=`overlay/`）15 文件：3 新增
  （`prototype/Core/WS2FoldCallbackStamp.swift`、`prototype/App/WS2FoldCallbackGuard.swift`、
  `docs/handoff/round2-part9/{INTEGRATION.md,privacy-signals.json}`）＋12 修改。
  唯一冲突 `prototype/App/FoldCompletion.swift`：保留 `awaitFold(id:)`，接上事务绑定语义。
- 归档：`docs/handoff/chatgpt-review-2/part9/`（整包）。
- 仓库 runner：`tests/part9/{tests,tools,sources,validation}/` + `base-files.json` + `manifest.json`。
- 隔离修复：23 处 / 8 文件，全部用 `MainActor.assumeIsolated`（EventTap 1、FoldExit 3、
  FoldTransaction 2、Reconcile 2、ShadeController 8、WS2FoldCallbackGuard 5、WindowFoldEffects 1、
  WindowBrowserAppDelegate 1）。
- 证据：`docs/handoff/chatgpt-review-2/part9/MAC-EVIDENCE.md`。

## 跑过的检查与结果（全部在本机）

| 检查 | 结果 |
| --- | --- |
| `tests/part9/tests/run.py --repo . --suite regression` | 42 场景 / 93 断言 / 0 失败 |
| `tests/part9/tests/run.py --repo . --suite frame` | 15 场景 / 15 断言 / 0 失败 |
| `tests/part9/tests/check-build.py --repo .` | Foundation 40 份类型检查 + 43 份语法，退出 0 |
| `tests/part9/tests/check-wiring.py --repo .` | 24 项全 PASS |
| `tests/part9/tests/test-tools.py` | 18 项 OK |
| `tests/part9/tests/run-previous.py`（duo、part8 input/fold/flow、part7 core/native/flow、legacy 两批） | 九套全过（33/49、21/49、6/27、27/51、3/14、18/145、legacy exit 0） |
| 仓库自身 runner | contracts 9/24、part2 22/86、part3 55/147、part4 72/188、part5 40/97 + 8/26、part6 42/95 + 9/27 + wire 4、PROC04 0.086s、T1 12/32、Mac 配对加密、conductor 手势全过 |
| readiness / 归档 | BLOCKED（exit 2，如实）；94 文件哈希全对 |
| `cd prototype && ./build.sh --check` | 退出 0 |
| `bash tests/run-appkit-tests.sh all` | 八套全过（含 LEASE-H01…08；需 WindowServer 会话） |
| 隐私门禁 | 登记表 466 点无未登记新增、页面数据同源 |

## 只有 Mac 才会暴露的问题（已处理）

1. 第九份把 `FoldCompletion` 改成 `@MainActor` 后，23 处非隔离调用点编不过（Linux 纯逻辑没暴露）；
   逐点核对都在主线程，按仓库既有写法包 `MainActor.assumeIsolated`，不改语义、不降版本、不关并发检查。
2. `tests/part9/tests/check-build.py` 仍按 `prototype/App/InteractionCoordinator.swift` 找共享仲裁，
   本仓库在 `Core/`，改成两边都能找到。
3. `tests/part9/tools/stage.py` 拒绝 macOS 的 `/var`，且 `resolve()` 与 `absolute()` 混用；照第七、八份的
   做法规范化 `/var`、`/tmp`、`/etc` 并全用 `resolve()`。
4. `run-previous.py` 的 legacy 两批要 `history/part1..part6`（本仓库平铺在 `tests/`，原件在归档）；改成用
   本仓库已适配的 `tests/part7/tests/regressions.py`，`--history` 指向 `docs/handoff/chatgpt-review-2`。
5. `tests/WindowFoldEffectsTests.swift` 用的是第九份已删除的「只按窗口 ID 报成功」API；测试宿主改成
   「先绑事务再按事务结算」，投递改主队列 flush 对账，成功用例装真实 `folded` 状态并固定未锁屏。
   `run-appkit-tests.sh` 的 `all` 分发器对 async 的 `main()` 加 `await`。
6. 隐私登记：`WS2FoldCallbackGuard` 新读一处 AX 布尔属性归 `window-ax`，旧的适配器登记点随实现移动；465 → 466。

## 残余风险

- **受控真机观察还没做**：工单 02/03 里可安全复现的 M01/M03/M06/M07/M08/M11/M14/M16/M17/M18
  需要动 Aaron 的真实窗口，必须他先指定「允许动」的窗口、动手前再确认一次。这是本轮唯一未完成项。
- AppKit 回归与读 `NSScreen` 的用例必须在有 WindowServer 会话的上下文跑（沙箱里 `NSScreen.screens` 为 0）。
- `part3` 的三条 unix socket 用例沙箱里 `bind` 回 `EPERM`，沙箱外通过——沙箱限制，不是回归。
- 完整 T3、真实 AX 收起/恢复与人工恢复、慢 AX 与强制取消、真实 SCK capture graph、Touch ID 允许端到端、
  配对接收、系统身份后端、能耗、影片与发布仍未做（以第九份 REMAINING 为准）。

## 下一步

1. 本轮已提交到 `main`（不推送、不打标签）。
2. 等 Aaron 指定可动窗口后，按 MAC-EVIDENCE 的矩阵逐例做受控真机观察并补证。
3. 未完成项按第九份 REMAINING 与工单 02/03/04 继续推进。
