# 1.0.18 性能热点清单（静态勘察，未跑任何探针）

2026-10-17。范围：Apple silicon 上四个场景——收起／展开、窗口浏览打开、看一眼、刘海空闲。
方法：只读代码，按 `rg` 找计时器、显示链接、主线程上的 AX／CGWindowList 调用、图像转换和 Metal 管线创建，再顺着调用链读上下文。
**这份清单里的毫秒数全是估计**，来源分三种，每条都标了：【注】代码或文档里已有的实测说明；【推】我按调用类型与 [performance.md](performance.md) 的量级表推的；【无】没有任何数字，只是结构上可疑。
没有改任何产品代码。哪条值得动，等 `scripts/perf-report.sh` 跑出的 `--hitch` 数字和下面的"怎么确认"一起定，再改；Pareto 规则：只改有前后数字、行为不变的地方。

## 怎么读 `--hitch`

`--hitch` 量的是**主线程**在交互期间有没有按时让出每一帧（`App/HitchProbe.swift` 的显示链接回调在主线程 run loop 上）。所以它只会被"主线程上的同步阻塞"抓到；纯 GPU 或窗口服务器那一侧的掉帧要用 Instruments。下面的候选因此按"是不是主线程上同步做了一件大事"来排。

类对应的场景：`fold`／`unfold` = 收起／展开；`browser-open`／`browser-close` = 窗口浏览；`glance-show`／`glance-hide` = 看一眼。刘海空闲没有 `--hitch` 类，用能耗脚本量（见"确认手段"）。

## 排序总表

| # | 场景 | 候选 | 位置 | 估计 | 依据 | 风险 |
| --- | --- | --- | --- | --- | --- | --- |
| H1 | 收起 | 恢复记录落盘用 `F_FULLFSYNC`，在主线程同步做，一次收起至少两次写 | `Recovery/DurableShadeJournal.swift:52,68`；调用 `App/ShadeController.swift:381,430` | 每次写 3–20 ms，两次合计 6–40 ms | 【推】 | 高：这是崩溃一致性保证（先落盘再隐藏），只能量，不能随手挪 |
| H2 | 收起 | 背景快速合成在 `@MainActor` 里同步跑：全量 `CGWindowListCopyWindowInfo` ＋ `CGWindowListCreateImageFromArray`（整窗大小，Retina） | `Effects/WindowFoldEffects.swift:174`（函数）、`:197`（调用）；实现 `Capture/FastCapture.swift:52-73` | 20–60 ms，随窗口像素数涨 | 【注】`FastCapture.swift:4` 与 `WindowFoldEffects.swift:195` 自述"几十毫秒" | 中：搬到后台队列即可，`ShadeController.fastWindowCapture` 已有现成做法（`:851`，`pixelAnalysisQueue`） |
| H3 | 窗口浏览 | 每个 App 的发现结果回来都整面板重算：`finishMetadataJob` → `refreshPanel()`，没有合并 | `WindowBrowser/WindowBrowserController.swift:1276`（`refreshPanel()` 调用在其函数体内）、`:1387` | 开面板后第一秒内 N 次（N＝常规 App 数，常见 15–40）整面板布局＋`contentView.update`；单次 1–5 ms | 【推】；文档里 [window-browser-performance.md](window-browser-performance.md) 量过"暖刷新"单次，但没量过 N 次叠加 | 低：合并到每帧一次（或 16 ms 内一次）不改结果，只改时机 |
| H4 | 看一眼 | 出现时在主线程同步做 `FastCapture.composite`（取消隐藏路径要先截背景） | `App/Glance.swift:691` | 20–60 ms | 【注】同 H2 的自述；这里用的是卡片区域，比整窗小，估计偏下限 | 中：背景必须在取消隐藏**之前**取到，顺序不能乱，可以先后台取、取到再 show |
| H5 | 收起／展开 | 隐藏策略在主线程做多次 AX：`fallbackHide` 里 `appCurrentUserWindowCount`＋`appWindowCount`（各一次 `kAXWindowsAttribute`，事务备忘 `Window/AppWindows.swift:73-85` 内只有第一次真问），`axOffscreenHide` 最多 4 轮"写位置＋读位置" | `App/FoldTransaction.swift:759-761,640-657`；`Window/AppWindows.swift:73` | 目标空闲时 20–25 ms（首次枚举）＋每轮 0.2 ms；目标忙时每次 ≈19 ms，最坏被 2 s 超时托住（`WindowShade.swift:367`） | 【注】[performance.md](performance.md) 表里 `kAXWindowsAttribute` 18–25 ms、忙时单读 ≈19 ms | 中：已有 `AXStallBreaker`、`timedRead`；真收益在"忙目标"，空闲目标已被备忘压住 |
| H6 | 收起（冷） | 第一次收起时在主线程同步创建 Metal 设备、库和三条管线 | `Effects/FoldGPU.swift:79`（`objects()`）、`:125-136`；预热 `:96`、触发 `Effects/DuoController.swift:96`（启动后 4 秒，仅在效果开着时） | 冷启动首次 100–400 ms；预热后为 0 | 【注】`EffectSession.swift:71-74` 注释写"首次收起含 GPU 共享对象创建"；数字【无】 | 低：已有预热；风险点是"启动 4 秒内就收起"或"效果当时关着、后来才开" |
| H7 | 刘海空闲 | `syncTimer` 每 2 秒一次（容差 0.5 s），永久存在；内部 `leases.tick()`、`syncWatchers()`，有收起窗口时还 `refresh()` | `App/Notch.swift:318-326` | 每次 <0.2 ms，但是 0.5 次/秒的固定唤醒 | 【推】 | 低：可在 `owner.shaded` 为空且没有 lease 时停掉，事件来了再起；但要确认 `leases.tick()` 的到期结算不能停 |
| H8 | 刘海空闲（有音乐播放器） | 活动轮询在进度档每 2 秒一次，每次主线程先扫 `NSWorkspace.shared.runningApplications`（两处）再切 worker | `App/NotchActivitySources.swift:253-256,284`；档位 `App/NotchActivityPollPolicy.swift:20-26` | 每次主线程 0.2–1 ms；整体约 0.5 次/秒唤醒 | 【推】；`:283` 的注释自己写过"列系统音频进程每 2 秒约占一个核的 1.7%"，说明这里的成本有过先例 | 低：推送流健康时已不问脚本（`:266-270`），所以主要是 `runningApplications` 那两次；可改为缓存＋`NSWorkspace` 通知失效 |
| H9 | 刘海空闲 | 听不到媒体键时亮度每 0.2 秒读一次，永久 | `App/NotchLevelObserver.swift:132`、`:488-495` | 5 次/秒唤醒，每次一次 IOKit／DisplayServices 读，<0.1 ms | 【推】；只在 `gate.keysAvailable == false` 时走（`:130-134`） | 低；条件罕见，先确认真机上会不会走到（日志里有 `media-key monitor unavailable`） |
| H10 | 收起中的窗口存在时 | 巡检计时器 5 秒一次（容差 1.5 s）：每轮 `shadeJournalEntries()` 读盘解码＋`pruneShadeJournal` 再读一次，都在主线程 | `App/Reconcile.swift:11-16,40-60`；`Recovery/Journal.swift:12,56` | 每轮 2 次小文件读＋plist 解码，约 0.2–1 ms；0.2 次/秒唤醒 | 【推】 | 低：日志只在本进程里变，可以内存里留一份、写时更新；但"另一个进程改过日志"的假设要先确认没有 |
| H11 | 窗口浏览打开 | 面板打开时主线程一次性做 `refreshHelperMap`（遍历所有 `runningApplications`，对没缓存的进程 `resolvingSymlinksInPath`）和 `scheduleGlobalDiscovery`（再遍历一次），两次遍历 | `WindowBrowser/WindowBrowserController.swift:1169-1199,1201-1213` | 0.5–3 ms（首次，路径解析要碰文件系统）；之后有缓存 | 【推】 | 低 |
| H12 | 窗口浏览（实时画面） | 选中项实时预览起流时用 `ShareableContentLoader.current()`（未缓存的 `SCShareableContent.current`），不走 `ShareableContentCache` | `WindowBrowser/WindowBrowserController.swift:1709`；对照 `Capture/ShareableContentCache.swift` | 约 30 ms 起（全量枚举），慢机器数百毫秒；在后台 `Task` 里，**不卡主线程但拖延实时画面出现** | 【注】[perf-energy.md](perf-energy.md) 实测 `SCShareableContent` 32.1 ms；`ShareableContentCache.swift:5-9` 自述"数百毫秒到数秒" | 低：缓存已有，且命中不到目标时会强制刷新（正确性不依赖 TTL） |

## 分场景细节

### 收起／展开（`fold`／`unfold`）

主线程上的同步块按顺序是：读位置和大小（`ShadeController.swift:277-278`，`timedRead` 包着，空闲 App 约 0.1 ms）→ 解析外框／计划 → **恢复意图落盘（H1）** → 焦点交接 → 隐藏（H5）→ 隐藏验证 → **恢复记录再落盘（H1）**。
卷帘动画那一侧：`EffectSession` 的显示链接锁在 60 Hz（`Effects/EffectSession.swift:32`），帧由 GPU 完成回调归还空位，不绕主线程；图像准备（vImage 色彩空间转换＋纹理）在有界 worker（`Effects/FoldRenderer.swift:42-48`）。这一侧结构上没发现主线程重活，所以先不列候选。

`ShadeController` 里已经有逐段计时（`foldPhase`，`Window/AppWindows.swift:41-52`，阶段名如"恢复意图落盘""隐藏窗口""元素刷新""折叠计划"），累计报告 `foldPhaseReport()`；**它目前只在专注一次折叠一批窗口后打印**（`App/FocusSession.swift:476`），单次双击收起不会出报告。所以 H1、H5 不需要新增计时，但要让探针（`--fold-timing`）或日志在一次收起后读出 `foldPhaseTotals`——这是探针侧的小改动，不碰产品行为。

- **H1 的取舍**：先落盘再隐藏是故意的（`ShadeController.swift:376` 起的注释）。可行的方向只有两类：不改语义，只把"第二次写"（隐藏验证后的更新，`:430`）挪到后台串行队列；或者把每次落盘的 `F_FULLFSYNC` 换成只在第一次（意图）用。第二类会削弱崩溃一致性，**不建议在 1.0.18 动**。先量。
- **H2**：`background(for:)` 里的 `FastCapture.composite` 是**同步**的，前面的 `fastWindowCapture` 已经是后台的了，这一段是漏网的。展开路径（`FoldExit.swift`）我没逐行读，是否有对称的同步截图未核对。
- **H6**：预热的触发条件是 `settings.desktopEnabled || settings.windowsEnabled`（`DuoController.swift:96`）。如果收起效果在启动时是关的、之后才在设置里打开，第一次收起仍会走同步创建；`objects()` 没有任何 signpost。

### 窗口浏览打开（`browser-open`／`browser-close`）

`openKeyboardPanel`（`:931`）一次性在主线程做：新建 `Session`、新建 `WindowBrowserPanel`（`:985`，每次新建，Dock 路径有预热 `prewarmDockPanelIfNeeded` `:763` 而键盘路径没有）、`refreshManagedWindows`（`:1150`，内部 `refreshPanel()`）、`installPanelMonitors`（3 个全局事件监视器）、`refreshHelperMap`、`scheduleGlobalDiscovery`。
AX 发现本身在后台队列里跑（`startMetadataJob` `:1236`，`metadataQueue`），并且有 `AXStallBreaker` 和每应用一个在途任务的限制；**主线程的代价在结果回来之后的 `refreshPanel()`**（H3）。
面板打开期间还有 0.6 秒一次的存活扫描（`:1336`，只在面板开着时），以及一个全局 `mouseMoved` 监视器（`:2538-2547`，每次鼠标移动都进主线程；Dock 模式下函数体内有 `NSEvent.mouseLocation`＋几何判断，量级很小但事件频率高）。
`--hitch` 的 `browser-open` 量的是 `openKeyboardPanel()` 到"面板可见＋列表填进来最多 1.5 秒＋350 ms 尾巴"，所以 H3 的 N 次重算**正好落在测量窗口里**。

### 看一眼（`glance-show`／`glance-hide`）

- 出现：H4（同步背景截图）。`GlancePanel`、`GlanceContentView` 每次新建（`Glance.swift:679-690`），这类创建通常 1–3 ms，不单列。
- 期间：`ensureTimer`（`:908-935`）用 `DispatchSource` 在 **主队列**上 33 ms 一次（有会话时），每拍 `driveUnhide` 里：`windowIsOnScreenNow`＝`cgWindowInfo(id)` 单窗口 `CGWindowListCopyWindowInfo`（`Window/AXWindow.swift:387`），出现后约 0.8 秒内每拍一次，约 30 次/秒；`sample(at:)` 里每拍一次 `NSWindow.windowNumber(at:belowWindowWithWindowNumber:)`（`:1031`，`hitTestsByGeometry` 为假时）。单次都小（<0.3 ms），合计 <10 ms/s，**不是 hitch 来源，但算能耗**。
- 空闲（没有会话、没有等待指针离开的卷帘条）时 `needsTimer` 为假，定时器会取消（`:908-912`），**这一条我读过，空闲零计时器**。
- `windowCornerRadius` 每个窗口只量一次（有缓存 `cornerRadii`），裁 240×240 的图做像素扫描，<1 ms，不单列。

### 刘海空闲

固定唤醒源（刘海开着、没有任何收起窗口、没有播放器时）：

| 来源 | 位置 | 频率 |
| --- | --- | --- |
| `syncTimer`（H7） | `App/Notch.swift:318` | 0.5 次/秒 |
| 活动轮询空闲档 | `App/NotchActivityPollPolicy.swift:24`（30 s），`NotchActivitySources.swift:97` | 0.03 次/秒 |
| `environmentWatch` | `WindowShade.swift:1058`（5 s），内部 `EventTapHealth.sweep`＋`AXIsProcessTrusted()` | 0.2 次/秒 |
| 亮度回退轮询（H9，条件性） | `App/NotchLevelObserver.swift:488` | 5 次/秒 |
| LidAngle 看门狗（仅相关效果开时） | `Effects/LidAngleSource.swift:97-104`，推送健康 1 Hz／不健康 4 Hz | 1–4 次/秒 |

有收起窗口时加：`reconcileTimer`（H10，0.2 次/秒）、`Carry` 1.5 s（只在有"带到每张桌面"的窗口时，`Carry.swift:425`）。
有播放器时加：活动轮询进度档（H8，0.5 次/秒）。
事件监视器：`NotchLevelObserver` 的全局 `.systemDefined` 监视器和（可选）HID 级 tap（`:296-298`）只在媒体键事件到来时工作，空闲无成本；它的 tap 跑在哪条 run loop **没核对**。
我核对过的 session 级 tap 都在自己的线程上（`WindowShade.swift:1000-1004` 的标题栏单击 tap、`ScrollTap.swift:127-129`、`TrackpadGestures.swift:2221-2223`、`MiddleTitlebarTap.swift:60-79`、`WindowSwitcher.swift` 的按键 tap），回调不占主线程；其中 `WindowSwitcher` 的 tap 是 `headInsert`＋`defaultTap`，掩码是全部 `keyDown/keyUp/flagsChanged`，意味着只要窗口切换器开着，**全系统每次按键都先过这个回调**（回调体里先 `async` 到主线程，`WindowSwitcher.swift:98`），延迟成本是每键一次进程间往返，没数字，值得用 E6 的探针看一眼。

没有任何一项是显示链接或 120 Hz 计时器在空闲时常驻：`rg` 全仓 `CADisplayLink`／`1.0 / 120` 的使用点我逐个对过上下文，都挂在一次交互的生命周期里（`EffectSession`、`ScrollStripOverview`、`ScrollStripRun`、`Notch` 内容进场的 `contentLink`、`ScrollTap` 等），有 `invalidate`。**唯一要核实的是 `Notch.swift:5205-5208` 的 `contentLink`**（步进在 `:5133` 的 `contentWatchStep`）：它请求 60–120 Hz（preferred 120），应该在内容到达 40% 后停（`contentWatchStep`），我没读到停止分支的完整路径，列为"确认生命周期"。

## 怎么确认（每条对应的测量）

| # | 现成手段 | 具体做法 | 缺什么 |
| --- | --- | --- | --- |
| H1 | `--fold-timing`（打印 `TIMING`）＋ `foldPhaseReport()` 阶段"恢复意图落盘""隐藏验证" | `bash tests/run-glance-probe.sh --fold-timing`，读阶段累计；`HITCH fold` 的 worst 对照 | 日志里要有 `foldPhaseReport` 输出，若只在专注结束时打印，探针里需要读一次（**探针改动，不是产品改动**） |
| H2 | `HITCH fold`（`worst`）、`SystemLog.foldSignposter` 的 `fold` 区间 | 对比 `WINDOWSHADE_DISABLE_FAST_CAPTURE=1`（`FastCapture.swift:29`）前后 `worst`；Instruments 的 os_signpost 轨道 | 缺 `background` 的单独 signpost：建议加 `SystemLog.foldSignposter.beginInterval("fold-background")`（只增埋点） |
| H3 | `HITCH browser-open`（`n=20` 的 `worst`／`p95`）、`SystemLog.windowBrowserSignposter` 的 `session` 区间与 `stage` 事件（`WindowBrowserController.swift:217,231`）；`noteDiscoveryRequest`／`first-catalog-publish` 计数 | `log stream --signpost --predicate 'subsystem == "com.windowshade.prototype"'` 数 `refreshPanel` 次数；加一个 `refreshPanel` 计数器进诊断（[window-browser-performance.md](window-browser-performance.md) §17.1 有会话计数框架） | `refreshPanel` 次数还没有计数 |
| H4 | `HITCH glance-show` | 对比 `viaUnhide`（卷帘条背后窗口被隐藏）与非 `viaUnhide`（有快照）两种场景的 `worst` | `--hitch` 的看一眼用的是 fixture 窗口，是否走 `viaUnhide` 取决于收起方式；要在日志里确认 `glance: unhide under cover` 出现 |
| H5 | `foldPhaseTotals`："元素刷新""窗口属性读取""隐藏窗口"；`axWindowListEnumerations`（`AppWindows.swift:34`，数一次折叠真枚举几遍）；E5 `AXStallBreaker` 日志 | `--fold-timing` 后读这三个数；忙目标场景用 `--switch-cpu`／`--idle-first-op`（E6，`GlanceProbe.swift:159,164`） | 忙目标只能人为造（先让目标 App 做重活），现成探针没有 |
| H6 | `EffectSession.rendererInitMs`（`EffectSession.swift:74-81`，`WINDOWSHADE_DUO_DIAGNOSTICS=1` 时写日志 `rendererInit=`） | 冷启动后 4 秒内第一次收起，对比 4 秒后第一次收起的 `rendererInit` | 需要冷启动场景脚本 |
| H7 | `scripts/energy-profile.sh`（E1，60 秒静置 CPU%，3 次取中位）、`tests/run-idle-timer-tests.sh` | 空闲 CPU% 和 `sudo powermetrics --samplers tasks` 的 wakeups／s；对照"停 `syncTimer`"前后 | 一个计时器的收益在噪声里，需要 `powermetrics` 的唤醒计数而不是 CPU% |
| H8 | 同上＋播放器开着 | 开 Music 播放，跑 E1 | 同上 |
| H9 | 日志 `media-key monitor unavailable`（`NotchLevelObserver.swift:133`） | 先 grep 真机日志有没有；没有就不用管 | — |
| H10 | E1（有收起窗口时）、`wlog("reconcile: timer started")` | 收起一扇窗后跑 E1 | 同 H7 |
| H11 | `windowBrowserSignposter` 的 `stage` 事件 | 加一个 `stage`；或用 Instruments Time Profiler 看 `openKeyboardPanel` 自身耗时 | 缺 stage 埋点 |
| H12 | `HITCH browser-open` 不会抓到（在后台）；看"选中项到实时画面出现"的间隔 | 日志里 `LivePreviewLease` 起流时间戳（`WindowBrowserController.swift:1700-1730`） | 缺计时 |

## 建议的量测顺序（一次真机，不动产品代码）

1. `scripts/perf-report.sh --host`（主机空闲时）取六类 `HITCH` 基线，同时留 `.build/perf/*.json`。
2. 对 `fold` 读 `foldPhaseReport()`，一次看清 H1、H5 各占几毫秒；对 `browser-open` 数 `refreshPanel` 次数看 H3；对 `glance-show` 分 `viaUnhide`／快照两种看 H4。
3. 只有 `worst` 或 `p95` 超预算的类，才进下一步，而且**只改有前后数字的那一处**。已知的预期：`fold`／`browser-open`／`glance-show` 最可能是 H2、H3、H4；H1 即便量出来大，也不在 1.0.18 动。
4. 虚拟机里的 `--hitch` 只拦 ≥500 ms 单帧，对这些毫秒级候选基本没有分辨力；VM 数字只用来确认没有新的整秒阻塞，别拿它判 H1–H5。

## 没有覆盖的地方

- 展开路径（`App/FoldExit.swift`）只读了开头：`:55-58` 有 `timedRead` 包着的 AX 读，其余（解除隐藏、AX 写回、日志记录移除）没逐行核对，H1 的"展开时的第三次落盘"也是推测。
- `PinnedPreview`（`PinnedPreview.swift:1096` 的 0.2 s、`:1418` 的 30 Hz 计时器）、`Launchpad`、`PictureInPicture`、`SplitView`、`SlideOver`、设置窗口（`Preferences.swift:1271` 的 1 秒计时器）不在这四个场景里，没有评估。
- 内存与能耗的绝对值（E2）不在这份里。
- 没有任何一条被实测证实；本清单的作用是缩小测量范围，不是给结论。
