# 交给 ChatGPT Pro 的提示词

把下面「---」之间的整段复制给 ChatGPT Pro（它需要能读 GitHub，仓库是公开的）。

---

你是 macOS 系统编程方面的资深工程师，请对下面这个整合方案做一次**独立、可证伪的深挖**，
重点是私有 WindowServer/SkyLight 行为、锁屏生命周期和失败模式。请直接给结论，不要复述我给你的背景。

## 背景

**产品 A：WindowShade**（我们要改的东西）

- 仓库（公开，MIT）：https://github.com/surfine/WindowShade
- macOS 14+，Swift + AppKit，**非沙盒**，走 GitHub Releases / 直接下载，**不上 App Store**。
- 它做的事：把窗口「收起来」成一条卷帘条、刘海面板、标题栏手势、卷轴（niri 式多列）、
  以及一个**合盖/倾斜效果**：合盖时把桌面画面折起来（用 ScreenCaptureKit 抓帧 + Metal 渲染 + 一个覆盖窗口），
  看起来像屏幕折下去。
- 请先读这几个文件（路径相对仓库根）：
  - `prototype/Private/SkyLightBridge.swift` —— 我们**已经**在用私有 SkyLight：
    `SLSMainConnectionID`、`SLSMoveWindowWithGroup`、`SLSCopySpacesForWindows`、
    `SLSMoveWindowsToManagedSpace`、`SLSManagedDisplayGetCurrentSpace`/`SetCurrentSpace`、
    `SLSGetWindowAlpha`/`SetWindowAlpha`。全部可选、dlopen 失败就降级。
  - `prototype/Effects/EffectSession.swift` —— 里面有 `EffectSecurityBoundary.isLocked`，
    注释写着「Lock-screen effects are deliberately unsupported」。
  - `prototype/Effects/DuoController.swift` —— 合盖/倾斜效果的控制器：观察
    `willSleep`、`screensDidSleep`、`sessionDidResignActive`、`didWake`、`screensDidWake`、
    `sessionDidBecomeActive`、`com.apple.screenIsLocked`/`Unlocked`，锁屏/休眠时 `suspend()`。
  - `prototype/Private/ScreenBezel.swift`、`prototype/App/Notch.swift`、`prototype/Overlay/` —— 我们自己的覆盖窗口。
  - `docs/glance-integration.md` —— 我们写的调研与分阶段方案（你要评的就是它）。
- 一条我们自己的实测：`CGSessionCopyCurrentDictionary` 是一次**同步的 WindowServer 往返**，
  曾经每秒轮询 12 次，后来改成只在状态变化时问。

**产品 B：Glance**（我们想借鉴的东西，MIT，Swift/SwiftUI，macOS 15+）

- 仓库（公开）：https://github.com/jonnyoo/glance ，另外可以直接读原始文件：
  - https://github.com/jonnyoo/glance/blob/main/glance/NotchOverlay/NotchSkyLight.swift
  - https://github.com/jonnyoo/glance/blob/main/glance/NotchOverlay/NotchWindow.swift
  - https://github.com/jonnyoo/glance/blob/main/glance/NotchOverlay/NotchWindowController.swift
  - https://github.com/jonnyoo/glance/blob/main/glance/LockMonitor.swift
- 它是「Mac 人脸解锁」：摄像头 + Vision/Core ML 识别人脸，解锁方式是把存在 Keychain 里的**登录密码**
  用 `CGEvent` 打进锁屏（`glance/KeystrokeInjector.swift`）。
- 我们**不做**人脸解锁那部分（不碰摄像头、不存密码）。我们要的是它顺带解决的两件事：
  1. **在真正的锁屏上显示自己的窗口**：`NotchSkyLight.swift` 用私有 SkyLight 的
     `SLSMainConnectionID` / `SLSSpaceCreate(conn, 1, 0)` / `SLSSpaceSetAbsoluteLevel(conn, space, 400)` /
     `SLSShowSpaces` / `SLSSpaceAddWindowsAndRemoveFromSpaces(conn, space, [windowNumber], 7)` /
     `SLSRemoveWindowsFromSpaces`，只在锁屏时 delegate、解锁立刻 undelegate，
     拿不到符号就降级成「锁屏上不可见」。文件头写明改编自 MIT 的
     https://github.com/Lakr233/SkyLightWindow 。
  2. **锁屏/休眠/唤醒状态的判断**：权威状态问
     `CGSessionCopyCurrentDictionary()["CGSSessionScreenIsLocked"]`，通知只当触发；
     另外记了两个坑：`screenIsLocked` 比系统真正挂起早约 150 毫秒，「睡着期间的锁屏通知不要照着做动作、
     等唤醒时重新判断」；以及**锁屏上 Secure Event Input 会压掉键盘事件**，不管有没有辅助功能授权。

## 我们要回答的问题

目标：把「锁屏上可见」和「锁屏/休眠状态」两件事接进 WindowShade，并且让**合盖折叠动画在锁屏上也能播完**
（现在是锁屏一到就被 `suspend()` 掐掉）。请逐条回答，并给出你**验证过**和**无法验证**的分界。

1. **可行性**：`SLSSpace*` 这几个符号在 macOS 14 / 15 / 26 / 27 上是否都还在？有没有**公开 API**
   能达到同样效果（例如把窗口层抬到锁屏之上、`NSWindow.Level` 的边界、
   `CGSSession*` / `SACLockScreen*` / `loginwindow` 相关接口、`kCGMaximumWindowLevel`）？
   如果没有，明说「只能走私有 API」。
2. **符号语义**：`SLSSpaceCreate(conn, 1, 0)` 的第二个参数为什么必须是 1？第三个参数是什么？
   `SLSSpaceSetAbsoluteLevel` 的 400 在别的 macOS 版本上是否还等于「锁屏时 Notification Center 的层」？
   `SLSSpaceAddWindowsAndRemoveFromSpaces` 最后一个参数 `7` 是什么含义？给别的值会怎样？
3. **生命周期**：窗口必须在**锁屏之前**就存在（甚至已经 `orderFrontRegardless`）吗？
   锁屏之后才创建窗口再 delegate 行不行？`SLSShowSpaces` 要不要每次锁屏都调？
   多显示器：一块屏一个空间，还是一个空间放所有屏的窗口号？外接屏热插拔呢？
   空间对象要不要在解锁时销毁（`SLSSpaceDestroy`？），还是复用？长期留着有没有泄漏或副作用
   （比如影响 Mission Control、Stage Manager、全屏空间、屏幕录制枚举）？
4. **像素从哪来**：我们折叠动画需要「桌面长什么样」。锁屏之后 `ScreenCaptureKit` / `CGWindowListCreateImage`
   抓到的是锁屏本身，不是锁屏后的桌面——请确认这一点，并给出方案：
   （a）锁屏前保留最后一帧并在锁屏上复用它；（b）别的办法。
   另外：进入锁屏时，正在跑的 capture session 会不会被杀、会不会留下录屏指示器？
   窗口在锁屏空间里显示时，它自己会不会被算进屏幕录制的内容？
5. **和我们的效果配合的正确顺序**：在「合盖 → 睡眠 → 唤醒到锁屏」这条链路上，
   delegate / 动画 / undelegate 应该各自发生在什么时刻？我们担心两件事：
   动画在 `willSleep` 之后才播会被挂起打断；以及唤醒时锁屏已经在了，此时再 delegate 会不会闪一下。
   请给出一个**时序列**（含容错：传感器没读数、锁屏通知丢、显示器睡眠）。
6. **风险与降级**：这些私有调用失败/半失败时分别是什么表现（返回错误码？静默无效？崩溃？），
   我们该怎么写「不崩、不闪、退回今天的行为」的降级路径？对公证（notarization）有没有影响？
   对 App Store 审核的影响是不是只到「不能用私有 API」这一条？
7. **我们代码里该改哪里**：以上方案落到上面列出的仓库文件上，请给出**文件级的改动清单**
   （新增哪些文件、改哪些函数、每个改动的一句话目的），以及一个**最小可验证的第一步**
   （能在一台真机上几分钟内看出「成 / 不成」的那种）。
8. **怎么安全地测**：我们需要探针自动锁屏再解锁。请给出安全的做法
   （例如有没有公开 API 能请求锁屏 / 解锁、怎样保证失败时不会把开发者锁在外面、
   是否应该在虚拟机或第二个用户会话里先试）。注意：**不能依赖用户密码**，也不能替用户输入密码。

## 输出要求

1. 一张**结论表**：把上面每个问题压成一两行结论，标「已验证 / 有把握 / 不确定」。
2. 一张**风险表**：风险 → 触发条件 → 表现 → 缓解 → 我们要不要接受。
3. 一份**分阶段实施计划**：阶段 → 改动文件 → 验收标准 → 回退方式；明确哪一步开始碰私有 API。
4. 一份**验证清单**：每个关键断言「怎么验证」（哪条命令、看哪个日志、看哪个界面现象）。
5. 最后一节**「我不确定的地方」**：把你无法从文档/头文件确认、只能靠实测的条目列清楚。

## 硬性约束

- **不要**建议装 root 助手 / LaunchDaemon / 关 SIP / 改系统文件；产品已经明确不做这些。
- **不要**建议存储或注入用户登录密码，也不要建议做摄像头人脸识别。
- 我们已经在用私有 SkyLight 符号，所以「用私有 API 本身」不是否决理由；但请说明**具体到这几个符号**的风险。
- 不要重写我们已有的 1.0.16 工作，只针对「锁屏可见 + 合盖动画跨锁屏」这一件事。
- Glance 与 SkyLightWindow 都是 MIT；如果你建议复制代码，请给出必须保留的版权声明。

---
