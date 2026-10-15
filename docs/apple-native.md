# Apple 原生優先：站在 Apple 的立場上做

2026-10-15。这一份把「**充分利用 Apple 最新 API，积极站在 Apple 原生立场**」变成可执行的判断依据。配套：[性能与能效](perf-energy.md)（Apple 芯片那节）、[重塑执行规格](product-reshape-spec.md)（**N 系列**任务）。

## 一、先说结论：我们已经相当「原生」

查下来，**我们不是「该用没用」，而是已经踩在 Apple 的路线上**。以下每一条都有代码证据：

| 我们已经在做的 | 证据 | 为什么这算「原生」 |
| --- | --- | --- |
| **帧同步用 `CADisplayLink`，不用过时的 `CVDisplayLink`** | `App/ScrollStripRun.swift:61`／`:106`，还写了弱引用代理防环（`:74` 的注释） | `CVDisplayLink` 自 macOS 14 起被 `CADisplayLink` 取代 |
| **Liquid Glass 按 SDK 存在性与系统版本双重 gate** | `build.sh:106` 检查 `NSGlassEffectView.h`；`#if WINDOWSHADE_SDK_HAS_GLASS`（`SlideOverGlass.swift`、`Launchpad.swift`）；`if #available(macOS 26.0, *)` | 新材质可用的第一天就能用上，旧系统自动退回 |
| **自己的窗口一律 `tabbingMode = .disallowed`** | 8 处以上（`Carry.swift:26`、`Thumbnail.swift:34`、`WindowBrowserPanel.swift:51`、`GlancePanel.swift:29`…） | 这是 AppKit 给的**原生**「别把我并进窗口标签」开关 |
| **macOS 15 的 `fullScreenDisallowsTiling`** | `App/Thumbnail.swift:35` | 系统自带平铺管不到我们 |
| **纯 AppKit，不混状态模型** | `ObservableObject` 0 档、`@Observable` 0 档 | macOS 的窗口管理本来就是 AppKit 的地盘，不必为了用 SwiftUI 而用 |
| **Swift 6 ＋ 完全并发检查 ＋ 警告即错误** | `-swift-version 6 -strict-concurrency=complete -warnings-as-errors` | 跟得上 Apple 的并发方向 |
| **部署目标 14.0，新 API 一律 `#available` gate** | `build.sh:151/158`；`ScreenCaptureBridge.swift:321/501/512` 等 | 老系统不崩、新系统吃到新能力 |
| **硬件能力** | Vision（ANE）、Metal（`FoldRenderer`）、VideoToolbox、ScreenCaptureKit | 见[性能与能效](perf-energy.md)§二 |
| **功耗策略** | `App/PowerPolicy.swift`（`thermalState` ＋ 低电量）、`App/AppNapActivity.swift`（`beginActivity`） | Apple 给的两套功耗 API 都在用 |

**所以这一份的重点不是「改用原生」，是补五处缺口。**

## 二、五处缺口（都有代码证据）

### N1 · 自动化／扩展面：Apple 的原生答案是 **App Intents**，不是自造 CLI

**这一条改写了我们之前的判断。** [niri.md](niri.md):91 把「脚本和 IPC」列为**不追**；[功能碾压](dominance.md) 把它记成一行空白，理由是**三家竞品都发了自造的表面**——OmniWM 是 `omniwmctl` 的 NDJSON socket，ChainYourMac 是 URL scheme ＋ Raycast ＋ CLI，DynamicLake 是插件市场。于是问题看起来是「要么自造一套，要么放弃」。

**站在 Apple 的立场上，这个问题不存在**：**App Intents** 就是 Apple 给的原生表面。定义了 Intent 之后，用户**免费**得到：

- **快捷指令（Shortcuts）**里的动作，可编排、可自动化；
- **Spotlight** 里的动作条目；
- **Siri**；
- 专注模式／自动化触发；
- 而且**不需要**自造 CLI、不需要注册 URL scheme、不需要设计插件格式——**全部由系统代管**。

**现状**：全仓 **0 处** App Intents（连 `NSUserActivity` 都没有）。

**改法**：把**已经在菜单栏/快捷键里存在的动作**（收起当前窗口、全部收进刘海、打开窗口浏览、切到某扇窗、恢复全部……）各定义成一个 Intent。**先做最常用的 5–8 个**，不要一次铺满。
**验收**：在「快捷指令」里能搜到我们的动作、能跑通、能串成一条自动化；Spotlight 里能搜到。
**风险**：Intent 是**用户可见的公开契约**，名字要与[固定词汇表](copy-guide.md)一致，且**改名的代价比内部 API 高**——所以先定名再实现。

### N2 · 统一记录：我们现在自绘文件日志，Apple 的原生是 `os.Logger`

**现状**：`Support/Diagnostics.swift:7` 的 `WindowShadeLogger` 是自绘的：每条日志走一次 `DispatchQueue.async` ＋ `Data` 拼接 ＋ `SecureLogFile.append`。`import os` 只在 3 个文件里出现，而且**没有一处在用 `os_log`／`OSLog`／`os_signpost`**。

**Apple 的原生做法是统一记录（Unified Logging）**，它有三个我们缺的性质：

1. **在 Console.app 与 `log stream` 里可见**——用户报障时能直接抓，我们的文件日志只有我们自己的工具能读。
2. **延迟格式化**：字符串在被真正读取之前不拼装，**对功率友善**（我们现在每条都拼一次 `Data`）。
3. **有隐私分级**：`privacy: .public/.private/.sensitive` 能在记录层就决定哪些字段不出设备——**这与我们的隐私登记天然对齐**（[privacy-page.md](privacy-page.md)）。

**改法**：**不是把文件日志全换掉**（我们的文件日志有自己的用途：`SecureLogFile` 与探针依赖它）。新增/改造的是：
- **面向系统的诊断**（启动、权限、通道体检、自愈）走 `os.Logger`，带 `subsystem`（用 bundle id）与 `category`；
- **每条带用户数据的日志**显式标 `privacy:`，与隐私登记逐条对齐；
- 文件日志保留，作为「本地可拖出来的一份」。

**验收**：`log stream --predicate 'subsystem == "com.windowshade.prototype"'` 能看到关键路径；隐私字段在系统日志里默认是 `<private>`。

### N3 · 性能观测：用 **`OSSignposter`**，让性能工作能在 Instruments 里看到

**现状**：性能量测靠自绘计时（`AXLatencyBench` 自己算 ms、`wlog` 打时间戳）。

**Apple 的原生做法是 signpost**：把阶段用 `OSSignposter` 标出区间与事件，**Instruments 里直接显示成时间线**。E／H 系列（静置、折叠延迟、AX 可取消、GPU 路径）**全都该走这条**，而不是每个探针各写一套计时。

**改法**：先给**折叠**与**窗口浏览**两条关键路径加 signpost（begin/end 区间 ＋ 关键事件），Instruments 能录下来。
**验收**：Instruments 的 os_signpost 轨道里能看到这两条路径的阶段划分；一次折叠的耗时分解可读。

### N4 · 低功耗周期调度：**`NSBackgroundActivityScheduler`**

**现状**：全仓 **0 处**；周期工作一律 `Timer`（77 处，见[性能与能效](perf-energy.md)§四）。

**Apple 的原生做法**：`NSBackgroundActivityScheduler` 让**系统**按电源、热压力、闲置窗口决定什么时候跑——**这正是「站在 Apple 立场」的字面意思**：把「什么时候做」交给系统，而不是自己定死。

**适用与不适用**（要分清，别滥用）：
- **适用**：非延迟敏感的周期工作——**更新检查**（`App/Updater.swift:137` 的 10s）、维护性清扫、统计汇总。
- **不适用**：**延迟敏感的**——R1 那个 5 秒事件通道体检**必须**保持 `Timer`（通道死了要尽快发现，不能等系统挑时机）。

**验收**：更新检查改走 NBAS 后，功能行为不变，且低电量模式下由系统自然推迟。

### N5 · **`PrivacyInfo.xcprivacy`**：Apple 的硬要求，我们现在没有

**现状**：全仓**没有** `PrivacyInfo.xcprivacy`。而我们确实在用 Apple 列的 **required-reason API**：

| 类别 | 我们在用 | 证据 |
| --- | --- | --- |
| **系统启动时间** | `ProcessInfo.systemUptime` | **41 个文件** |
| **用户默认值** | `UserDefaults` | `Preferences.swift` 等 |

**为什么这条要排在前面**：它**不是体验问题，是公証与上架的门槛**。[production-maturity](production-maturity.md) 的 B 组（Developer ID ＋ 公証）已经在路上，**没有这张清单会在公証那一步被挡回来**。

**改法**：按 Apple 的格式写 `PrivacyInfo.xcprivacy`，**逐类申明理由**（`NSPrivacyAccessedAPICategorySystemBootTime` → `35F9.1`；`NSPrivacyAccessedAPICategoryUserDefaults` → `CA92.1`），并把 `NSPrivacyTracking`／`NSPrivacyCollectedDataTypes` 按实际（不追踪、不收集）。
**验收**：清单进包；`plutil -p` 能读出；Xcode/公证工具的 required-reason 检查不报。
**注意**：先**逐条核**我们实际用的是哪些 required-reason 类别，**不要把用不到的类别一起抄进去**——申明不实比不申明更糟。

## 三、继续采用新 API 的两条纪律

1. **一律 `#available` gate ＋ 旧系统退回**（我们已经这么做，保持）。规矩：新 API 只用在**它解决的那个问题**上，不用来「顺便现代化」。
2. **不用新 API 换掉能用的旧 API**。`CVDisplayLink` 那种**已被 Apple 标记过时**的才换；没被标记的要换，先给理由与数字。

## 四、这一份与其它文档的关系

- 与 [性能与能效](perf-energy.md)§二（Apple 芯片）分工清楚：**那一节管「算得快不快、省不省电」，这一节管「是不是走 Apple 的路」**。
- N1（App Intents）**改写**[功能碾压](dominance.md) 里「扩展面」那一行的结论；N5 是 [production-maturity](production-maturity.md) B 组的前置条件。
- 任务已并入[重塑执行规格](product-reshape-spec.md)的 **N 系列**。
