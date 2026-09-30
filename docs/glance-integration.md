# Glance 调研与整合方案

> **当前方案见 [锁屏翻盖与多因素解锁](lock-unlock-plan.md)（2026-09-30 晚）。**
> Aaron 已要求研究人脸、注视、主动活体、Apple Watch 与手机认证，原文“人脸解锁不做”作废。
> 本文保留历史研究和 Pro 修订记录；旧方案中锁屏回放真实桌面、自动无认证解锁、
> 私有符号存在即代表兼容的说法，不再作为实现依据。最新方案优先于本文历史段落。

2026-09-30。调研对象：[jonnyoo/glance](https://github.com/jonnyoo/glance)（MIT，1.5k★，Swift/SwiftUI，
macOS 15+，作者 Jonathan Zhou）。下面每一条结论都标了出处文件；Glance 的代码读的是本地克隆（`--depth 1`，main）。

## 结论

**当前整合目标包含锁屏动画、本人面容、注视和设备认证。** 下面两项是 Glance 已提供的技术入口；它们不能代替其余认证链的实现。

1. **锁屏上可见**：Glance 用私有 SkyLight 的「空间」API 把自己的面板抬到真正的锁屏之上
   （`glance/NotchOverlay/NotchSkyLight.swift`）。这是我们做不到、而它能做到的那一件事。
2. **锁屏 / 休眠 / 唤醒状态的可靠判断**：`glance/LockMonitor.swift` 的做法值得对齐——权威状态问
   `CGSSessionCopyCurrentDictionary`，通知只当触发，并且记下了两个坑（见下文）。

**凭据后端需要单独核定**：Glance 的人脸解锁会存登录密码（`SecureCredentialManager`、`KeychainManager`），
识别后用 `CGEvent` 把密码打进锁屏（`glance/KeystrokeInjector.swift`）。那是安全类功能，和我们
「窗口去哪儿了」的产品定位无关，而且一旦做错代价是用户的登录口令。

**对合盖动画：能改善，而且顺便修掉一个现有的粗糙点。**

| 现在 | 有了锁屏可见之后 |
| --- | --- |
| 锁屏一落地就 `suspend()`，叠合到一半的动画被掐掉（`DuoController` 收到 `screenIsLocked` → `suspend`） | 动画可以在锁屏上画完：桌面折起来、露出下面的锁屏，而不是被锁屏窗口盖住 |
| 触发只靠铰链角度 + 「一秒没读数就停」的看门狗（`tickDesktop`） | 用 `willSleep` / `screenIsLocked` 对准真正的「屏幕要走了」，不会早 150 毫秒、也不会在锁屏落地时重复播 |
| 唤醒到锁屏后什么都做不了 | 知道了锁屏的权威状态，可以决定「不播」（推荐）或者播一段很短的展开 |

**代价与前提**：要用私有 API；**但这不是新的风险类别**——我们已经在用 SkyLight
（`prototype/Private/SkyLightBridge.swift`：`SLSMainConnectionID`、`SLSMoveWindowWithGroup`、
`SLSCopySpacesForWindows`、`SLSManagedDisplayGetCurrentSpace/SetCurrentSpace`、`SLSGetWindowAlpha/SetWindowAlpha`），
Glance 用的那几个是同一份框架里另外几个符号。两边都**不开沙盒**，都不上 App Store。

## 一、Glance 的锁屏可见是怎么做的

`glance/NotchOverlay/NotchSkyLight.swift` 全部内容就是这件事，要点：

```swift
dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight", RTLD_NOW)
// 取这六个符号：SLSMainConnectionID、SLSSpaceCreate、SLSSpaceSetAbsoluteLevel、
//              SLSShowSpaces、SLSSpaceAddWindowsAndRemoveFromSpaces、SLSRemoveWindowsFromSpaces
space = SLSSpaceCreate(connection, 1, 0)                       // 第二个参数 1 是必须的
SLSSpaceSetAbsoluteLevel(connection, space, 400)               // 400 = Notification Center 在锁屏时的高度
SLSShowSpaces(connection, [space])
SLSSpaceAddWindowsAndRemoveFromSpaces(connection, space, [window.windowNumber], 7)  // 只在锁屏时
SLSRemoveWindowsFromSpaces(connection, [window.windowNumber], [space])               // 解锁立刻
```

作者自己写的注意点，值得照抄：

- **`1` 是有意义的**：换成别的值，Finder 会把桌面图标画进这个空间。
- **400 这个高度**是「Notification Center 在锁屏时的高度」，比普通的 `screenLock` 还高，所以能盖住锁屏。
- **只在真的锁着的时候 delegate，解锁立刻 undelegate**（`NotchWindowController.show()/hide()`）。
- **拿不到符号就降级**：`shared` 是 `nil`，调用方按「锁屏可见不可用」处理，不崩。
- 来源：文件头写明改编自 [Lakr233/SkyLightWindow](https://github.com/Lakr233/SkyLightWindow)（MIT）。
  Glance 与上游都是 MIT，我们也是 MIT，**复制代码要带版权声明**（见本文件末尾「归属」）。

窗口本身（`glance/NotchOverlay/NotchWindow.swift`）也有一套可对照的做法：无边框 `NSPanel` +
`.nonactivatingPanel`、`isOpaque = false`、`level = .mainMenu + 3`、
`collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]`、
装饰时 `ignoresMouseEvents = true`；**窗口建一次就不再改大小**，所有展开收起都是窗口内部在动
（`setFrame`/`setContentSize` 一概不碰，只 `setFrameOrigin`）。这一条和我们刘海面板的思路一致，可以直接对照。

## 二、它怎么判断锁屏、休眠和唤醒

`glance/LockMonitor.swift`：

| 用途 | 信号 | 备注（作者原话的意思） |
| --- | --- | --- |
| 权威状态 | `CGSessionCopyCurrentDictionary()["CGSSessionScreenIsLocked"]` | 通知可以被同用户的进程伪造，只能当触发；权威判断只认这个，拿不到就按「没锁」处理 |
| 锁 / 解锁 | `com.apple.screenIsLocked` / `com.apple.screenIsUnlocked` | 只当触发 |
| 唤醒 | `com.apple.screensaver.didstop`、`NSWorkspace.screensDidWakeNotification`、`NSWorkspace.didWakeNotification` | 显示器唤醒和系统唤醒都当触发，两者相差约 100 毫秒、先后不定 |
| 睡着 | `NSWorkspace.willSleepNotification` | `screenIsLocked` 大约比系统真正挂起早 150 毫秒到，所以睡着期间不要照着锁屏通知做动作，等唤醒时重新判断 |

还有一条对我们特别重要：**锁屏上 Secure Event Input 会压掉键盘事件**，不管有没有辅助功能授权
（作者在 `screensaver.didstop` 那里的注释）。也就是说——**锁屏上我们收不到手势和快捷键，只能画**。

### 我们现在的做法（对照）

我们其实已经有一半了，只是分散在几处：

- `prototype/Effects/EffectSession.swift` 的 `EffectSecurityBoundary.isLocked`：问
  `CGSessionCopyCurrentDictionary`，同时看 `CGSSessionScreenIsLocked` 和 `kCGSessionOnConsoleKey`。
  注释写着「**Lock-screen effects are deliberately unsupported**」。
- `prototype/Effects/DuoController.swift`：观察 `willSleep` / `screensDidSleep` / `sessionDidResignActive`
  → `suspend()`；`didWake` / `screensDidWake` / `sessionDidBecomeActive` → `resume()`；
  `screenIsLocked` / `screenIsUnlocked` → `suspend()` / `resume()`。
- `prototype/App/ScrollStripPeek.swift`、`prototype/WindowBrowser/WindowBrowserController.swift`：同样观察锁屏与休眠。
- `DuoController.swift` 里有一条我们自己的实测：**`CGSessionCopyCurrentDictionary` 是一次同步的
  WindowServer 往返，别轮询**（那里原本每秒问 12 次）。Glance 的做法（事件驱动 + 需要时问一次）和我们这条一致。

所以「阶段 1」不是新增一套，而是**收拢成一处**（一个 `Core` 里的纯规则 + 一个监视器），避免四份各自为政。

## 三、整合方案

### 阶段 0：先定这条决定（要 Aaron 拍板）

项目里原来写着「锁屏效果明确不做」。那条决定的技术前提是「要在锁屏上画东西，得有助手 / 关 SIP」——
**这个前提已被证伪**：Glance 是一个普通用户态的 App，没关 SIP、没装守护进程，只 dlopen 了 SkyLight。
按项目规矩，这里显式作废那条旧理由；是否改做，等 Aaron 定。

### 阶段 1：统一锁屏状态（不碰私有 API，先做）

- 新增 `prototype/Core/SessionLockState.swift`（纯值，可单测）：把「锁着 / 睡着 / 刚唤醒」三个状态和
  迁移规则写清楚（含「睡着期间的锁屏通知不算」）。
- 新增 `prototype/App/SessionMonitor.swift`：收拢现在散在四处的观察者，对外只暴露一个状态和
  「状态变了」的回调；权威判断只在**状态变化时**问一次 `CGSessionCopyCurrentDictionary`（不轮询）。
- 改造点：`DuoController`、`ScrollStripPeek`、`WindowBrowserController`、`EffectSecurityBoundary` 都改成读它。
- 验收：单测覆盖状态迁移；现有 `--duo-*`、`--strip`、窗口浏览探针全过；`CGSessionCopyCurrentDictionary`
  的调用次数在静置时接近 0（可在探针里数）。

### 阶段 2：锁屏可见这一层（私有 API，落在现有桥里）

- 在 `prototype/Private/SkyLightBridge.swift` 里补那六个符号，风格与现有封装一致：全部可选、拿不到就返回 nil。
  新增 `LockScreenSpace`（`delegate(_ window: NSWindow)` / `undelegate(_ window: NSWindow)` / `isAvailable`）。
- 铁律：**只在 `isScreenActuallyLocked()` 为真时 delegate，解锁或停止效果时立刻 undelegate**；
  没拿到符号时整条链路安静降级（和今天行为完全一样）。
- 验收：`--check` 通过；一个探针在真机锁屏上 delegate/undelegate 并核对窗口层级（这条探针会锁屏，
  要 Aaron 在场、先约定）。

### 阶段 3：合盖动画跨锁屏

三件事，按顺序：

1. **不要掐掉动画**：`DuoController` 收到锁屏/休眠时，如果叠合动画正在播，让它播完（现在是直接 `suspend()`）。
2. **对准时刻**：用 `willSleep` / `screenIsLocked` 作为「屏幕要走了」的真信号来启动或收尾，而不是只看铰链角度 + 1 秒看门狗。
3. **锁屏上画完**：桌面折起来的那一刻把面板 delegate 进锁屏空间，用的像素是**锁屏前最后一帧**
   （锁屏之后抓不到桌面——ScreenCaptureKit 那时抓到的是锁屏本身）。折完再把面板撤出、`undelegate`。

需要处理的边界：多显示器（每块屏一个空间还是一个空间放多个窗口号）、显示器睡眠、
`activeSpaceDidChange`（我们现在是 `stopDesktop()`）、以及**唤醒后不播**（推荐：唤醒到锁屏保持安静，
和「刘海只在卡住时开口」的克制一致）。

验收：真机探针「锁屏 → 叠合动画在锁屏上播完 → 解锁后桌面正常」；无私有 API 的机器上行为与今天一致；
锁屏期间的 CPU 不高于今天。

### 阶段 4：门禁与文档

- 探针要能安全地锁屏（先约定时间，跑完自动解锁；失败要能把人放回来）。
- `docs/scorecard.md` 的「盒盖动画」一格补上「锁屏上是否可见、手感如何」。
- 风险与降级写进 `docs/performance.md` 或本文件。

## 四、做不到的地方（先说清楚）

- **登出后的登录窗口、快速用户切换里的另一个会话**：我们的进程不在那个会话里，画不了。
  要做得有 root 助手 / LaunchDaemon——项目已经明确否决（`no lock-screen effect/helper/SIP` 里的
  「helper/SIP」那半条今天仍然成立，作废的只是「不画」那半条）。
- **锁屏上的交互**：Secure Event Input 压掉键盘，我们的手势和快捷键在锁屏上收不到，所以锁屏上只能是「看」。
- **人脸解锁**：见开头，不做。

## 五、风险

| 风险 | 说明 | 缓解 |
| --- | --- | --- |
| 私有 API 随系统变化 | `SLSSpace*` 是未公开符号，Apple 可以改 | 全部可选、拿不到就降级；探针在每版 macOS 上跑一次 |
| 上不了 App Store | 用私有 API + 已经是非沙盒 | 我们本来就走 GitHub Releases / 直接下载，不进 App Store |
| 隐私：留住最后一帧 | 锁屏上播的那一帧是锁屏前的桌面 | 只留一帧、只存内存、进锁屏后立刻用完即弃；设置里可关（关掉整个锁屏效果） |
| 锁屏上误触 | 抬到 level 400 的面板盖住锁屏 | 默认 `ignoresMouseEvents = true`，只在需要时接收点击（Glance 也是这么做的） |
| 多显示器 / Stage Manager / 全屏空间 | 空间模型比单屏复杂 | 阶段 2 先只做一块屏（主屏），跑通再铺开 |
| 授权与公证 | dlopen 私有框架不影响公证，但会让 App Store 排除 | 与今天一致，无新增 |

## 归属（License）

Glance 是 MIT（`github.com/jonnyoo/glance`），其中 `NotchSkyLight.swift` 文件头写明改编自
[Lakr233/SkyLightWindow](https://github.com/Lakr233/SkyLightWindow)（MIT）。我们也是 MIT。
**若照抄代码，按 MIT 要求保留版权与许可声明**：在复制的文件头写清来源与 MIT，并在
`docs/` 或 README 的致谢里列出两个项目。只借鉴做法、不抄代码时，也建议在注释里注明出处。

## 下一步

给 ChatGPT Pro 的深挖提示词见 [glance-pro-prompt.md](glance-pro-prompt.md)。

---

## 记录：ChatGPT Pro 的审查、我们的核对，以及改定的方案（2026-09-30）

提示词发出去后拿到了 Pro 的完整审查（本机存档在当次会话附件里）。**它的三条具体代码主张我逐条核对了，
全部成立**；它推翻了我原方案里的两处设计，我采纳。

### 一、它说对了的三件事（本项目源码核对）

1. **渲染 tick 里每帧都在问 WindowServer。** `DuoController.tickDesktop` 每帧调 `allowsAnimation`，
   而 `allowsAnimation` 里有 `EffectSecurityBoundary.isLocked` → `CGSessionCopyCurrentDictionary`，
   一次同步 IPC（代码另一处注释自己实测过：单次约 0.2 ms CPU，主线程还要等几毫秒）。桌面效果 60 fps
   就是每秒 60 次；传感器读数那条路（每秒 62 份）也走 `allowsAnimation`。
   → **已修**：新增 `Effects/EffectEnvironment.swift`，通知只触发重读，渲染每帧只读缓存，
   效果在跑时按最长 1 秒复查一次权威状态（通知丢了最多错一秒）。桌面会话结束时打一行
   `duo: desktop stopped lockQueries=…` 便于记录。
2. **`EffectFrameSource.stop()` 把结果丢了。** 现在是 `Task { try? await old.stopCapture() }`，
   停止完成与失败都不可观测（它建议：代次立即失效保留，另加可观测的停止结果）。
3. **`FoldRenderer.setImage()` 不推进 revision。** 换素材不会撤销已经提交的旧绘制，所以
   「先 setImage(安全素材) 再把这扇窗 delegate 到锁屏」**不能**证明旧桌面帧不会上锁屏。

### 二、它推翻了我原方案里的两处，已采纳

- **锁屏上不复用真实桌面像素。** 我原来写的是「留锁屏前最后一帧，锁屏上把它折起来」；
  Pro 指出那本身就是一次信息披露（对未认证的观看者展示原桌面），「只有几百毫秒／只在内存里／加了模糊」
  都不改变这一点。**改定**：锁屏那一层只用程序生成的纸面/边缘折叠等安全素材，
  并且**新建独立的 `LockOverlaySession`（自己的窗口 + 自己的 `FoldRenderer` 实例）**，
  从创建起就不接触真实桌面像素；不复用跑过真实桌面的那个实例。
- **不要收窄现有的私有空间编号。** 我们 `Private/SkyLightBridge.swift` 里 managed space 用的是 `UInt64`；
  Glance/SkyLightWindow 那份配方把空间号和返回值写成 `Int32`，历史 CGS 头文件却是 `size_t`。
  两边都不是经核定的契约，**新能力单独放一层，失败不连带禁用现有的挪窗口/透明度功能**。

### 三、我们补的证据：导出存在性（阶段 1A）

`scripts/sls-symbols.c`（Pro 附带的探针，已入库）只 `dlopen`／`dlsym`，不建空间、不挪窗口、不锁屏。

2026-09-30 在本机跑：**macOS 27.0（build 26A428）、arm64，十个符号全在**——
六个基础符号（`SLSMainConnectionID`、`SLSSpaceCreate`、`SLSSpaceSetAbsoluteLevel`、`SLSShowSpaces`、
`SLSSpaceAddWindowsAndRemoveFromSpaces`、`SLSRemoveWindowsFromSpaces`）加
`SLSHideSpaces`、`SLSSpaceDestroy`、`SLSCopySpacesForWindows`、`SLSSpaceGetType`，退出码 0。

**这只证明这台机器、这个系统构建、这个架构上符号在**；ABI、真锁屏可见、完整生命周期都还没验，
别的系统版本和架构也没有记录。按 Pro 的要求，未验证的组合一律默认关闭新能力。

### 四、阶段表（改用 Pro 的划分）

| 阶段 | 内容 | 验收 |
| --- | --- | --- |
| **0 状态与日志** | `EffectEnvironment` + Duo 接线：通知只重读、渲染 tick 无同步查询、unknown 不当解锁 | **已完成（2026-09-30）**：`--check` 通过、28 个 runner 全过；关闭新协调器时行为与之前一致 |
| **1A 只查符号** | 上面的 C 探针 | 本机已过；其余 OS build × 架构待补 |
| **1B 第一次改私有空间状态** | 独立小窗口探针 + `Private/LockScreenSpaceBridge.swift` | 真锁屏上出现小标记、鼠标与认证不受影响、到期/解锁后消失（**要人在场解锁**） |
| **2 安全离线呈现** | `Effects/LockOverlaySession.swift`：独立窗口 + 独立渲染器 + 安全素材 | 无 ScreenCaptureKit、无桌面素材也能跑折叠；任何失败先隐藏 |
| **3 接合盖状态转换** | Duo 的锁屏交接、`stop()` 可观测化 | 锁屏但未睡眠时接棒；睡眠立即撤场；唤醒不复播旧桌面 |
| **4 循环与显示配置** | 热插拔、显示器睡眠、全屏、Stage Manager、用户切换、退出 | 资源不持续增长，无残影 |
| **5 受限发布** | 兼容记录、默认开关、公证产物 | 只对验证过的组合声明支持 |

### 五、测试分工（照 Pro 的约束）

- 状态机与失败恢复：可以无人值守（重放通知、mock 失败）。
- **真锁屏：必须有人在旁边用系统认证解锁。** 探针不 key/main、整窗鼠标穿透、独立到期撤场，
  再有一个普通父进程看着它（不用 root、不用 LaunchDaemon）。**不能承诺无认证自动解锁**，
  也不拿 `CGSession -suspend` 之类的私有接口当稳定锁屏入口（系统给用户的是 ⌃⌘Q）。
- 首批实验：一个 240×48 的小窗口、只画计数、不碰 Metal 与 ScreenCaptureKit；先做
  「只提高 window level」与「私有空间委托」两组对照，再做「锁屏前建窗」与「锁屏后建窗」对照。

### 六、给 Pro 的提示词要补一条

上一版提示词只给了仓库根地址，没有写分支，Pro 按 `main` 读，于是
`docs/glance-integration.md`、`prototype/Private/ScreenBezel.swift`、`prototype/App/Notch.swift`
三个路径 404（这些文件都在分支上）。**下次一律给带 ref 的完整链接**：
`https://github.com/surfine/WindowShade/blob/codex/1.0.16-local-closure/<path>`。
