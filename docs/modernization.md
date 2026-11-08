# 现代化：离现代有多远，怎么走近

2026-10-15。这一份回答「尽可能现代化」。**工具链是 Swift 6.4**（`swift --version` → `Apple Swift version 6.4`），构建参数已经是 `-swift-version 6 -strict-concurrency=complete -warnings-as-errors`，部署目标 14.0。理由与出处：[Apple 原生优先](apple-native.md)、[性能与能效](perf-energy.md)。任务并入[重塑执行规格](product-reshape-spec.md)的 **M 系列**。

## 一、现状实测：我们是「混合体」

**不是「落后」，是一半已经现代化、一半在积累**。数字都是本轮实测（全仓 grep）：

| 已经现代的 | 实测 |
| --- | --- |
| Swift 6 语言模式 ＋ **完全并发检查** ＋ 警告即错误 | `build.sh:151/158` |
| **`CADisplayLink`**（不是过时的 `CVDisplayLink`） | `App/ScrollStripRun.swift:61/106` |
| **`Duration`／`ContinuousClock`** 已经用了 | **`Duration.` 95 处、`ContinuousClock` 11 处** |
| Liquid Glass 双重 gate、`tabbingMode = .disallowed` ×8 | 见 [Apple 原生优先](apple-native.md)§一 |
| 纯 AppKit，不混 SwiftUI 状态模型 | `ObservableObject` 0、`@Observable` 0 |

| 还在积累的 | 实测 | 类别 |
| --- | --- | --- |
| **`ProcessInfo.systemUptime`** | **108 处** | 旧时间基准 |
| **`CFAbsoluteTimeGetCurrent`** | **88 处** | 旧时间基准 |
| **`Task.sleep(nanoseconds:)`** | **325 处** | 旧睡眠写法 |
| `TimeInterval` | 742 处 | 旧时长类型（多数无害） |
| **`NSLock()`** | **66 处** | 旧同步原语 |
| **`os_unfair_lock`** | **31 处** | 旧同步原语 |
| **`@unchecked Sendable`** | **99 处** | **人工保证线程安全** |
| `DispatchSemaphore` | 14 处 | 旧同步原语 |
| `DateFormatter` | 8 处 | 旧格式化 |
| `NSRegularExpression` | 1 处 | 旧正则 |
| **`Mutex`／`Synchronization`／`Span`／`@concurrent`／`nonisolated(nonsending)`／typed throws** | **全部 0 处** | 未采用的现代特性 |

**`@unchecked Sendable` 不是均匀分布的**（`Support/SendableSystemHandles.swift` 8 处、`Effects/FoldGPU.swift` 5 处、`Effects/LidAngleSource.swift` 4 处，前十名占了约 35 处）——**说明它是集中在少数几个「与系统句柄打交道」的文件里，不是到处都欠债**。

**测试策略要说明白（2026-10-15 自纠）**：此前这一份写「`tests/` 是空的、只靠探针」，**是错的**。事实：`tests/` 有 **228 个 Swift 测试档 ＋ 215 支 `run-*.sh` runner**（共 465 个条目），用的是**自制的 `@main struct XxxTests` ＋ `expect()`** 模式（`import XCTest`／`import Testing` 各 0）；另有**应用自带的 `--*-probe` 真机探针**（`build.sh --check` 的自测与 [scorecard](scorecard.md) 的「真机」列指向它们）。**两条腿都在**——见 M7。

## 二、现代化清单

### M1 · 时间基准：`systemUptime`／`CFAbsoluteTimeGetCurrent` → `ContinuousClock`／`Duration`（**196 处，一石二鸟**）

**为什么这条排第一**：它不只是「写法更现代」，它**同时缩小一条合规义务**——`ProcessInfo.systemUptime` 属于 Apple 的 **required-reason API**（`NSPrivacyAccessedAPICategorySystemBootTime`）。**把它换成 `ContinuousClock`（单调时钟，语义等价）之后，这一类就不必在 `PrivacyInfo.xcprivacy` 里申明了**——N5 的范围直接变小。

**当前分布最密的几处**：`App/NotchActivityController.swift` 23 处、`App/HabitContext.swift` 12、`App/Notch.swift` 7、`App/NowPlayingStream.swift` 5、`App/NotchActivitySources.swift` 5。

**改法**：`let clock = ContinuousClock()`，用 `clock.now` 取 `Instant`，用 `Instant` 相减得 `Duration`（`a.duration(to: b)`）。**语义要点**：`systemUptime` 与 `ContinuousClock` 都是单调的，**不会因为用户改系统时间而跳**——这是等价的，别换成 `Date()`。
**验收**：改动文件的功能行为不变（探针回归）；全仓 `systemUptime` 归零后，N5 的清单里去掉 BootTime 一类。

### M2 · `Task.sleep(nanoseconds:)` → `Task.sleep(for:)`（325 处）

`try await Task.sleep(nanoseconds: 500_000_000)` → `try await Task.sleep(for: .milliseconds(500))`。

**为什么值得**：现在这个写法要人肉数零（`300_000_000` 是 0.3 秒还是 0.03 秒？**数错一个零就是十倍差**），而且它是 `Int` 参数、**负数直接崩**。`for:` 接受 `Duration`，`.milliseconds(300)` 一眼可读、类型安全。
**风险**：**几乎为零**（语义等价），但**量很大**——按文件分批，每批跑一次 `build.sh --check`。
**验收**：全仓 `nanoseconds:` 归零；行为不变。

### M3 · `NSLock`／`os_unfair_lock` → `Mutex`（97 处）——**小步走，不要大改**

现代做法是 `Synchronization.Mutex`：`let m = Mutex<State>(State())`，`m.withLock { … }` ——**拿不到「忘了 unlock」的 bug**（`NSLock` 的 `lock()`/`unlock()` 手动配对，提前 return 就漏）。`os_unfair_lock` 更糟：它是**按值传递**的，拷一下就坏。

**但这一条必须小步**，因为**它和 99 处 `@unchecked Sendable` 是耦合的**：那些文件是「手工保证线程安全」的，换锁只是换皮，真正的现代化是**把「手工保证」换成「类型保证」**（`Mutex`／actor／`@MainActor` 隔离）——那是一次**并发改造**，不是一次查找替换。

**策略**：
1. **新代码一律 `Mutex`**（或 `@MainActor` 隔离），不新增 `NSLock`／`os_unfair_lock`。写进[重塑执行规格](product-reshape-spec.md)§1 的纪律。
2. **旧代码按文件迁，从「状态最简单」的开始**（一个 `Mutex` 包一个值、没有嵌套加锁的）；**有嵌套加锁、有跨对象不变量的先不动**。
3. `DispatchSemaphore`（14 处）单列：多数是「等一个异步结果」，**这些该换成 `withCheckedContinuation`／`AsyncStream`**，而不是换成 `Mutex`。

**验收**：每个迁移的文件，`@unchecked Sendable` 能去掉就去掉（去不掉要写明为什么）；探针全跑一遍。

### M4 · 评估 `-default-isolation MainActor`（**先量，别直接上**）

Swift 6.2 起的 `-default-isolation MainActor`（SE-0466）让**默认一切都在主 actor 上**，后台工作显式标 `nonisolated`／`@concurrent`。对一个 **514 个文件的 AppKit 应用**，这能**一次消掉大量 `@MainActor` 标注噪声，并且默认就没有数据竞争**——是「现代化」里杠杆最大的一条。

**但它也可能是最大的坑**：开下去可能瞬间几百上千个编译错误。
**做法**：**先在一个分支上打开，把编译错误数出来**（`build.sh --check 2>&1 | grep -c "error:"`），**按「错误数 ÷ 改造收益」决定要不要走**。这件事的产出是**一个数字和一个判断**，不是一次重构。
**验收**：有一份「开之后错误数、错误集中在哪些文件、值不值得」的结论。

### M5 · `Span`／`RawSpan` 用在像素路径（与 H1 同源）

`Capture/PreviewRenderer.swift` 里的 `[UInt8]` ＋ 手算下标（`:104`、`:187`、`:193`）是「安全内存访问」的现代写法要解决的问题：`Span<UInt8>`／`RawSpan` 提供**边界安全的连续内存视图**，且不引入 `Unsafe*`。
**边界**：这一条**和 H1 一起做**——H1 是把循环换成 Metal／vImage；如果最终走 vImage，`Span` 就没必要了（vImage 有自己的缓冲类型）。**先定 H1 走哪条路，再决定要不要 M5**。

### M6 · `Regex` 与 `FormatStyle`（9 处，小活）

`NSRegularExpression` 1 处 → Swift 的 `Regex` 字面量 `/…/`；`DateFormatter` 8 处 → `date.formatted(...)`／`Date.FormatStyle`。
**注意**：`Support/Diagnostics.swift` 那个 `DateFormatter` 是**日志时间戳**，它显式设了 `Locale(identifier: "en_US_POSIX")`——**这一条不能省**，日期格式必须钉死 locale，否则在某些区域会变。换 `FormatStyle` 时要保留这个语义（`.locale(Locale(identifier: "en_US_POSIX"))`）。
**验收**：行为不变（尤其日志时间戳格式在非中文区域也不变）。

### M7 · 纯逻辑用 Swift Testing（**加法，不是替换**）

我们的验证有**两条腿**：`tests/` 里的 **228 个 Swift 测试档**（纯逻辑，跑得快）＋ **应用自带的 `--*-probe` 真机探针**（整机上的真实行为）。**这一份不推翻任何一条**——探针验的是「真机上的行为」，那是我们的长处。

**但纯逻辑要跟既有模式**（**2026-10-15 自纠**）：规格里的 R4（原生标签页合并的判据）明确要求「**不依赖 AX 与 AppKit 的纯函数，便于单测**」，而这类测试**在 `tests/` 里已有 228 个先例**——用的是 `@main struct + expect() + run-*.sh` 那套。**照它写，不引入 Swift Testing**：多一个框架就多一套 runner 与输出格式，而现有那套已经接进 `build.sh --check`（`:125`／`:184`／`:187`）。**「现代化」不等于把能用的东西换掉。**
**验收**：有第一个纯逻辑单测（建议就从 R4 的判据开始）。

## 三、诚实清单：什么**不**该做

- **不为了「现代化」换掉还能用的旧 API**。`TimeInterval`（742 处）大多数是无害的；全换 `Duration` 的收益不抵改动面。
- **不用 `@Observable` 硬套纯 AppKit**。我们没有 SwiftUI 状态模型，硬上只会多一层。
- **不在没有测试网的情况下大改并发**。99 处 `@unchecked Sendable` 是**地雷区**；M3／M4 都要「小步 ＋ 探针回归」，**不要 big-bang**。
- **不追 Swift 的每个新特性**。`InlineArray`、typed throws、`@concurrent` 这些，**遇到了合适的场景再用**，不为用而用。
- **不把现代化与功能改动混在一支提交里**。迁移类改动**行为必须不变**，否则出问题时分不清是哪个引起的。

## 四、与其它文档的关系

- [Apple 原生优先](apple-native.md)：那一份管「是不是走 Apple 的路」（App Intents／OSLog／PrivacyInfo）；**这一份管「写法和类型是不是现代」（时间／同步／内存／并发的类型系统）**。
- **M1 与 N5 直接联动**：M1 做完，N5 的申明范围变小。
- **M5 与 H1 联动**：H1 先定路（Metal 还是 vImage），再决定 M5。
- 任务已并入[重塑执行规格](product-reshape-spec.md)的 **M 系列**。
