# 第九份在这台 Mac 上实际跑出来的结果（2026-10-03）

环境：macOS 27.0（Darwin 27.0.0、26A428）、Xcode SDK 27、Swift 6.4（swiftlang-6.4.0.34.1）、
arm64（Apple M5 MacBook Air，T8142）、两块屏（内置 1710×1107@2x + 一块外接，未锁屏）。
命令在仓库根跑，证据在 `.build/`、`tests/part9/validation/` 与下面引用的日志。

合并方式：`base-sources/`（第九份的基线）× 当前 `main`（ours）× `overlay/`（theirs）三方合并，
15 个文件（3 新增 + 12 修改）。唯一冲突在 `prototype/App/FoldCompletion.swift`：台账重写成
「事务绑定 + 整批取出 + 投递前复核」，我这边多了番茄钟要用的 `awaitFold(id:)`，最后保留 `awaitFold`
并接上新的结算语义。单岛仍用现有 `NotchLeaseHub`，没有引入第二套岛/窗口管理器。

本机哈希（改动/新增源码，取 sha256 前 16 位）：

| 文件 | sha256 |
| --- | --- |
| `prototype/Core/WS2FoldCallbackStamp.swift` | 50e53418e04733bb |
| `prototype/App/WS2FoldCallbackGuard.swift` | accc9b8e6118a219 |
| `prototype/App/FoldCompletion.swift` | 3a7f77be94e30fbd |
| `prototype/App/FoldTransaction.swift` | f12ad746b9b18c35 |
| `prototype/App/Reconcile.swift` | 3cccfe8f3a6fb7df |
| `prototype/App/ShadeController.swift` | e00567337576a630 |
| `prototype/App/WS2FoldEvidenceAdapter.swift` | 7d385fc9a74c0fd9 |
| `prototype/Core/FoldVerifier.swift` | 8391bca46e6af68e |
| `prototype/Effects/EffectFrameAwaiter.swift` | 9c7a967621855e6a |
| `prototype/Window/AXHelpers.swift` | b679b85d9e4e31f1 |
| `prototype/WindowBrowser/WindowBrowserAppDelegate.swift` | 62c3b432c25f5e40 |
| `prototype/WindowShade.swift` | 10fdfaa5bed80ec0 |
| `tests/duo-integration-check.py` | 0cfdb0a8cf0d5bb5 |

## 合入后跑通的

| 检查 | 命令 | 结果 |
| --- | --- | --- |
| 第九份 regression | `python3 tests/part9/tests/run.py --repo . --suite regression` | 42 场景 / 93 断言 / 0 失败 |
| 第九份 frame | `python3 tests/part9/tests/run.py --repo . --suite frame` | 15 场景 / 15 断言 / 0 失败 |
| 构建边界 | `python3 tests/part9/tests/check-build.py --repo .` | Foundation 40 份类型检查 + 43 份语法检查 |
| 接线检查 | `python3 tests/part9/tests/check-wiring.py --repo .` | 24 项全 PASS（三态、事务绑定、批次代次、routeID、首帧隔离、只读入口） |
| 文件工具 | `python3 tests/part9/tests/test-tools.py` | 18 项 OK（含 macOS 符号链接与路径规范化修正） |
| 旧回归（part9 runner） | `python3 tests/part9/tests/run-previous.py --repo . --history tests --suite …` | duo 三套全过；part8 input 33/49、fold 21/49、flow 6/27；part7 core 27/51、native 3/14、flow 18/145 |
| 旧回归（legacy，归档作 history） | 同上，`--history docs/handoff/chatgpt-review-2 --suite legacy-foundation\|legacy-process` | foundation 7 子套件全 exit 0；process part6 9/27、part5 8/26、PROC04 OBSERVED_PASS 0.17s |
| 仓库自身 runner | `tests/run-{contracts,part2..part6}-*.sh` | contracts 9/24、part2 22/86、part3 55/147、part4 72/188、part5 40/97 + 8/26、part6 42/95 + 9/27 + wire 4、PROC04 0.086s、T1 12/32、Mac 配对加密通过、conductor 手势全过 |
| readiness 门禁 | `tests/run-part6-readiness.sh` | exit 2（`BLOCKED`，与「设备与 Mac 证据未齐」一致，未强行转绿） |
| 归档完整性 | `tests/run-part6-archive-integrity.sh` | 94 文件校验通过 |
| 整 App | `cd prototype && ./build.sh --check` | 通过（含 Native C 模块与 Sparkle） |
| AppKit 回归 | `bash tests/run-appkit-tests.sh all` | 八套全过（含租约宿主 LEASE-H01…08） |
| 隐私门禁 | `tests/run-privacy-registry-check.sh` / `run-privacy-page-sync.sh` | 466 个词法点无未登记新增、页面数据同源 |

## 只有 Mac 才会暴露的问题（都已按证据处理）

### 一、Swift 6 严格并发的隔离错误（23 处，8 个文件）

第九份在 Linux 上只跑纯逻辑，`AppDelegate` 的 AppKit 扩展从没真编译过。它把
`FoldCompletion` 改成 `@MainActor extension`，于是所有在非隔离上下文里调用
`registerFoldWaiter` / `bindFoldWaiters` / `settleFoldWaiters` / `cancelFoldWaiters`，
以及读 `AuthorizationService.shared.lockState()`、`ledger.sessionEpoch` 的调用点全都编不过。
逐点核对后确认它们都在主线程（事件 tap 回调、AX observer、Timer、`DispatchQueue.main.async`、
`FoldVerifier.schedule` 就是 `DispatchQueue.main.asyncAfter`），照仓库既有写法
`MainActor.assumeIsolated { … }` 显式声明，不改语义、不降 Swift 版本、不关并发检查、
不加 `@unchecked Sendable`。

| 文件 | 处数 | 点 |
| --- | --- | --- |
| `App/ShadeController.swift` | 8 | `shade` 的 `sessionEpoch`/`admissionCurrent`/两处 `settleFoldWaiters`、安装与原生两条 `bindFoldWaiters`、未验证分支的 `settleFoldWaiters` |
| `App/WS2FoldCallbackGuard.swift` | 5 | `foldCallbackStamp` 的 `sessionEpoch`、`foldCallbackIsCurrent`/`observeFoldHide`/`retainUnconfirmedFold` 的 `lockState` 与 `settleFoldWaiters` |
| `App/FoldExit.swift` | 3 | `unshadeReturningElement`、`forceCleanup`、`removeProxyForAction` 的 `defer cancelFoldWaiters` |
| `App/FoldTransaction.swift` | 2 | `revealOverlayAfterVerification` 的 `lockState` 与 `settleFoldWaiters` |
| `App/Reconcile.swift` | 2 | `reconcileShadedWindows` 与 `applyReconcileAXSnapshots` 的 `lockState` |
| `App/EventTap.swift` | 1 | 标题栏双击动作里的 `registerFoldWaiter` |
| `Effects/WindowFoldEffects.swift` | 1 | 释放任务时按捕获 token 的 `settleFoldWaiter` |
| `WindowBrowser/WindowBrowserAppDelegate.swift` | 1 | `windowBrowserBeginFold` 的 `registerFoldWaiter`（该函数本就有 `dispatchPrecondition(.onQueue(.main))`） |

修完 `./build.sh --check` 通过（日志 `/private/tmp/p9-repo-build.log` 为修前 23 处，
`p9-repo-build2.log` 为修后「编译验证通过」）。

### 二、仓库入口/测试与第九份假设的差异

1. **`tests/part9/tests/check-build.py` 仍按 `prototype/App/InteractionCoordinator.swift` 找共享仲裁**，
   本仓库在 `Core/`。改成两边都能找到（沿用第七、八份 runner 的做法）。
2. **`tests/part9/tools/stage.py` 拒绝 macOS 的 `/var`**（Apple 自己的根级链接），且 `resolve()` 与
   `absolute()` 混用让「输出在输入内」失配。照本仓库既有做法先规范化 `/var`、`/tmp`、`/etc`，并全用 `resolve()`。
3. **`tests/part9/tests/run-previous.py` 的 legacy 两批**要 `history/part1..part6`，本仓库把历史测试
   平铺在 `tests/`（`part2/…/part6` 原件在归档里）。改成用本仓库已适配的 `tests/part7/tests/regressions.py`，
   `--history` 指向 `docs/handoff/chatgpt-review-2`。
4. **`tests/WindowFoldEffectsTests.swift` 用的是第九份已删除的「只按窗口 ID 报成功」API**
   （`settleFoldWaiters(id:success:)`）。第九份的意义正是取消这条路径，于是把测试宿主改成生产顺序：
   先把捕获的 token 绑到一个事务、再按事务结算；投递改成下一轮主队列，测试用一次主队列 flush 对账。
   需要「成功」的用例会装一份真实的 `folded` 状态并把锁态固定成未锁屏（`AuthorizationService.shared.lockState`
   是既有的测试接缝），交付的 `true` 仍然过一遍事务与锁态复核。
5. **`tests/run-appkit-tests.sh` 的 `all` 分发器**要 `await` 现在变成 async 的 `WindowFoldEffectsTests.main()`。

### 三、环境注记

- AppKit 回归与任何读 `NSScreen` 的用例必须在**有 WindowServer 会话的上下文**里跑：
  受限沙箱进程里 `NSScreen.screens` 为 0、`CGSessionCopyCurrentDictionary()` 为 nil，
  `NotchActivityViewTests` 会在 `NSScreen.main!` 崩。沙箱外一次跑通。
- `run-part3-core-tests.sh` 的三条 unix socket 用例在沙箱里 `bind` 回 `EPERM`（`system(1)`），
  沙箱外 `part3 core 55/147, 0 failures`。属沙箱限制，不是代码回归。

## 隐私登记

第九份新增的读取点只有 `WS2FoldCallbackGuard.swift` 里读一条 AX 布尔属性的
`AXUIElementCopyAttributeValue`（归 `window-ax`：只作三态观察与旧回调复核）。事务戳、routeID、
批次号都只在该次操作的内存里，不新存也不外发。旧的 `WS2FoldEvidenceAdapter` 读取点随实现搬到
`WS2FoldCallbackGuard`，登记表 465 → 466 点，页面数据同源。

## 受控真机观察（未做，等 Aaron 指定可动窗口）

工单 02/03 里可安全复现的那部分还没有跑：它必须在**明确允许的窗口**上动，动手前要再跟 Aaron 确认一次。
准备按这份矩阵逐步做，每例记：OS 构建/SDK/Swift/架构/屏幕配置/权限、源文件哈希（见上表）、命令、
操作时间、observed 三态与最终结果、journal 前后对比；unknown 的用例额外记窗口真实位置与恢复入口是否可用。
卡片截图不作为窗口已恢复的证据。

| 用例 | 想验证 |
| --- | --- |
| M01 | 收起→展开→立刻重收同窗，每次完成只归各自 transaction |
| M03 | AX 几何暂时读不到时显示「未确认」，恢复入口与 journal 仍在 |
| M06 | 收起过程中切 Space（或拔主显示器），旧 presentation 结果不被接受 |
| M07 | 等待/排队时锁屏再解锁，旧成功不复活、锁中不自动恢复 |
| M08 | 后台巡检未回时展开并重收同窗，旧 snapshot 不清理新状态 |
| M11 | 撤掉 observer 后旧通知排队到达，旧 routeID 不再路由 |
| M14 | 普通隐藏窗口在当前屏幕列表里缺席，不能仅凭缺席宣布成功 |
| M16 | 原生 resize 慢的应用走既有 proxy fallback，不恢复嵌套 RunLoop（记视觉差异） |
| M17 | 撤回 AX 权限后再恢复，旧结果不通过、新操作重读权限与上下文 |
| M18 | 人工尝试恢复一个「未确认」的窗口，观察真实结果，journal 不被假成功删除 |

本轮不做、按第九份 REMAINING 留档：M04/M05 私有隐藏策略重试细节、M09/M16 的强制取消与真实
ScreenCaptureKit capture graph、M10 活应用多次读尺寸、M12/M13/M15 的特例路径，以及完整 T3、
配对接收、原生允许审批、系统身份后端。

## 仍然没做（以第九份 REMAINING 为准）

整 App 的真实窗口收起/恢复与人工恢复、慢 AX 调用实测、下一轮的强制取消、真实 SCK capture graph、
完整 T3（强进程/窗口身份、用户 revision、run/effect 与原 journal 持久关联、真实幂等恢复）、
真实登录后的查询与原生页面、Touch ID 允许端到端、手柄/鼠标/多触点/遥控器与音频生产桥、
Swift SRP 依赖的异构互测与原生 Remote、可靠系统锁/身份后端、能耗与全菜单回归、影片、签名与发布。
自动窗口效果仍然关闭（`WS2FocusWindowPort.admitted=false`）。
