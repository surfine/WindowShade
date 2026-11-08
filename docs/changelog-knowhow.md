# 竞品更新日志里的 real-world know-how

2026-10-14。依据：**11 个开源竞品／同场的 626 个 release、15,642 行一手更新日志**（本轮从 GitHub Releases API 全量取回），加上**闭源竞品的一手日志**（WindowMizer 66 版／972 行、Wins 3.1→3.6 全文、DockMate 0.8.5→0.8.7、LaunchOS 37 个版本、ChainYourMac 的 Sparkle appcast、以及已入库的 [DynamicLake 79 版／1,946 行](dynamiclake-changelog.md)）。全部读取于 2026-10-14。

这一份回答一个问题：**这些「已经付过款的失败」里，哪些是我们在真机上也会撞的？**

## 一、为什么更新日志比官网和二进制都值钱

官网说的是想让你相信的，二进制说的是它长什么样，**更新日志说的是它真的坏过什么**。每一条都是某个真实用户在真实机器上撞到、作者不得不修的东西——**这是唯一一种由「已经发生的失败」构成的证据**。

三行结论：

1. **失败是成类的，不是成家的。** 睡眠唤醒后失灵、幽灵窗口、离屏窗口被系统搬走、手势吞掉 App 滚动——同一件事在**四到六家**独立出现。所以这一份按**失效类别**组织，不按厂商组织。
2. **我们暴露最多的是「没有人的那一段」**：台前调度、设置备份与迁移、多点触控的设备归属、事件通道的周期巡检。这四类我们基本是空的。
3. **我们已经在做的，比预期多。** 十几条里我们已经有对等实现，而且有几处走得更前（`kAXUIElementDestroyedNotification` 只当提示、触点帧只在手指数变化时回主线程、离屏一律用点）。详见第三节。

### 读了什么

| 项目 | 许可 | release | 日志体量 | 与我们哪一格对应 |
| --- | --- | --- | --- | --- |
| DockDoor | GPL-3.0 | 171 | 120 KB | **窗口浏览（88）**、Dock 悬停、预览 |
| OmniWM | GPL-2.0 | 94 | 224 KB | 卷轴／平铺、多显示器、全屏还原 |
| Rectangle | NOASSERTION | 107 | 66 KB | 分屏（90）、台前调度 |
| AeroSpace | MIT | 63 | 38 KB | 卷轴、AX 阻塞、辅助功能权限 |
| Ice | NOASSERTION | 57 | 30 KB | 菜单栏（刘海相邻面） |
| Atoll | GPL-3.0 | 29 | 136 KB | **刘海（88）**、锁屏 |
| niri | GPL-3.0 | 23 | 247 KB | 卷轴、手势、输出（显示器） |
| boring.notch | — | 23 | 53 KB | **刘海（88）** |
| Loop | — | 20 | 32 KB | 分屏、动画、崩溃 |
| alt-tab-macos | — | 20 | 36 KB | **窗口浏览（88）**、切换器 |
| paneru | MIT | 19 | 24 KB | 卷轴 |
| PaperWM.spoon | MIT | 0 | — | 无 release；读源码，见[竞品深挖](competitive-deep-dive.md) |

闭源那几家（一手，非 GitHub）：

| 项目 | 一手来源 | 体量 | 与我们哪一格对应 |
| --- | --- | --- | --- |
| WindowMizer 6 | `windowmizer.com` 更新史页 | 66 版／972 行 | **收起本体（92）** |
| Wins | `wins.cool` 更新日志 | 3.1→3.6 全文 | 刘海（88）、Dock 预览、调度中心 |
| DockMate | `macenhance.com` Recent Changes | 0.8.5→0.8.7 | **窗口浏览（88）**、Dock 悬停 |
| LaunchOS | `launchosapp.com/release.en` | 37 个版本 | **启动台（85）** |
| ChainYourMac | Sparkle appcast（第一方） | 最近 3 版 | 卷轴 |
| DynamicLake | 已入库全文 | 79 版／1,946 行 | 刘海（88） |

（Ice／Loop／alt-tab-macos／boring.notch 是**同场的相邻项目**，不是我们列的竞品；它们的日志解决的是同一批 macOS 问题，所以算作证据。）

## 二、失效家族逐条

**十三个族**：A–H 来自开源项目（日志最完整），K–O 来自闭源竞品（修过一批开源项目碰不到的东西）。

`我们` 一栏：**已在做**（给了代码位置）、**部分**、**未做**（这是欠账）、**待核**（没查到底）。

### A 权限与事件通道

| 现象 | 谁撞过 | 我们 | 可验收的形状 |
| --- | --- | --- | --- |
| **换了签名证书，辅助功能授权作废，用户要重新授权一次** | AeroSpace **两次**：v0.17.0「Update codesign certificate due to expiration. **AeroSpace will re-request accessibility permission.**」、v0.20.3 同一条 | 我们用 Apple Development 凭证；**换成 Developer ID 时必然撞一次**（[production-maturity](production-maturity.md) B 组的动作） | 换证书那一版，欢迎窗口/设置里有一句说明「要重新授权一次」，不静默失灵 |
| 权限**授予了但不生效**，必须重启 App 才生效 | DockDoor：「Accessibility permission prompt no longer asks to restart **too early**」「DockDoor asks you to restart **once it detects the permission has been granted**」；alt-tab-macos v11.9.0（2026-10-06）「permission changes **could be missed until restart**」 | **部分**：多处按需读 `AXIsProcessTrusted()`（`WindowShade.swift:966`、`GlobalInputFilter.swift:484`、`MenuBarController.swift:110`、`NotchLevelObserver.swift:266`），**没有一处订阅权限变化**，也没有「检测到已授予 → 提示重启一次」的收口 | 授予后不重启能生效；做不到时提示一次，而不是反复提示或静默不动 |
| 用户**拒绝**屏幕录制后，反复被问 | DockDoor：「Skipping screen recording no longer **repeatedly** asks for permission」；alt-tab-macos v11.2.0「only show screen recording callout **when it's needed**」 | **已在做**：`Capture/ShareableContentCache.swift` 短 TTL 缓存；我们只在真的要出预览时开流 | 拒绝后不再弹；预览功能不可用时说清「为什么」 |
| 屏幕录制权限检查**阻塞主线程 ~9.3 ms** | OmniWM：「A native check measured about **9.3 ms on the main thread**… Permission refreshes when leaving System Settings」 | **已在做**：我们不直接调 `CGPreflightScreenCaptureAccess`；`SCShareableContent` 走 async ＋ 短 TTL 缓存 | 主线程上不出现权限检查；切换 App／滚动时无可测卡顿 |
| **Secure Input** 会静默吃掉所有快捷键，用户不知道为什么 | OmniWM：「**See when Secure Input blocks shortcuts.** … the menu bar icon and each Workspace Button show a **red lock**, and the status menu starts with a Secure Input row that **explains which shortcuts macOS withholds**」 | **部分**：`App/HabitContext.swift:844` 把 `IsSecureEventInputEnabled()` 当排除项用，**没有对用户可见的说明** | 处于 Secure Input 时，某个可见处（菜单栏／设置）能说明「快捷键为什么没反应」 |
| macOS 27 把辅助功能权限**改了名字与分类** | boring.notch v2.8-rc.0：「Accessibility permission references now use the current macOS terminology (**Device Control and Data Access**) and localization, with a fallback」 | **未做**：我们的文案与引导按当前系统写 | 文案与系统设置的措辞一致；旧系统有回退 |

### B AX 的阻塞、陈旧与身份

| 现象 | 谁撞过 | 我们 | 可验收的形状 |
| --- | --- | --- | --- |
| **AX 是阻塞 API**：一个 App 不响应，拖住整个系统 | AeroSpace v0.18.0（原文）：「macOS accessibility API **is a blocking API**. If at least one application was unresponsive, **it'd block the entire system**.」→ 改为 **thread-per-application** ＋ AX 请求可取消 ＋ 合并幂等请求 | **部分**：我们有按 App 的后台队列（[niri.md](niri.md):46「挪窗口放在每个 App 各自的后台队列上，慢 App 跟不上时跳过中间几帧」）＋逐调用 `AXUIElementSetMessagingTimeout` ＋ `Window/AXWindow.swift:310/324` 的按调用熔断。**但没有「可取消」** | 一个 App 卡住时，别的窗口照常跟手；被卡的请求可取消，不排到最后 |
| 不可响应的 App **拖慢整个界面**（切换器变慢、悬停不动） | alt-tab-macos v11.6.0「an unresponsive app may slow down the switcher」；DockDoor「DockDoor **backs off** from an unresponsive app instead of stalling on it」「Unresponsive apps no longer stall Dock hover, previews, or the switcher」；OmniWM「Avoid repeated waits on apps already reported as unresponsive」 | **已在做**：`PinnedPreview.swift:633`「避免全局点击和菜单重建对同一忙 app 反复烧满 AX timeout」＋有限次退避 | 拿一个卡住的 App（`kill -STOP`）当对象，悬停与切换器照常 |
| App **重建 AX 端点 / 换窗口身份 / 迟到回调**，陈旧事件把当前窗口顶掉 | OmniWM：「Hardened window discovery and **identity rebinding** when apps recreate Accessibility endpoints, change window identities, or deliver late callbacks, preventing stale events from replacing or removing the current window」 | **待核**：我们按 `CGWindowID` 认窗，但 App 重建 AX 端点后我们的 AX 元素是否还指向同一扇，没系统验过 | 用会重建窗口的 App（Electron 类）反复开关，窗口身份不串 |
| 后台 App 的**陈旧焦点回调偷走焦点** | OmniWM：「Background apps' stale AX focused-window callbacks **can no longer steal focus** from the actual frontmost app」 | **部分**：多处注释写着不抢焦点（`WS2SilentProductPort.swift:440`、`FoldTransaction.swift:822`），但**没有一条是按「陈旧回调」处理的** | 后台 App 弹窗/被唤醒时，前台 App 不变 |
| 唤醒时的自动激活造成「惊喜聚焦」 | DockDoor：「**Removed wake activation** to prevent surprise focus」「Control app activation on wake from sleep」 | **部分**：`PinnedPreview.swift:263` 等处在 `screensDidWakeNotification` 上恢复环境；有没有主动激活要核 | 唤醒后前台 App 与睡前一致 |

### C 窗口身份与幽灵窗口

| 现象 | 谁撞过 | 我们 | 可验收的形状 |
| --- | --- | --- | --- |
| **不能信 `kAXUIElementDestroyedNotification`** 来判断窗口关了，会留幽灵窗口 | AeroSpace v0.16.0（原文）：「Don't rely on macOS unreliable `kAXUIElementDestroyedNotification` callback to tell if window is closed which might lead to **ghost windows**」 | **已在做，而且做到了同一层**：`App/FoldTransaction.swift:919` 起，把销毁通知**当提示不当许可**——要求 `CGWindowListCopyWindowInfo(.optionIncludingWindow, id)` 查回**空**才动手，并且校验回调序号（注释原文：「A delayed destruction notification is a hint, not permission to act on a reused ID.」） | 关窗后不残留条目；窗口 ID 被复用时不误伤新窗 |
| App **不是销毁窗口，而是 orderOut 掉**（Calendar 等） | OmniWM：「Windows that apps such as Calendar close by **ordering out instead of destroying** are now retired from the layout. OmniWM validates targeted rescans against the app's Accessibility window list」 | **待核** | 日历/提醒事项关一扇窗后，列表里不留 |
| **没有标题的浮层/工具条被当成真窗口** | DockDoor：「**Untitled** toolbar/overlay windows no longer get mistaken for real app windows」「Untitled system overlay windows no longer show up as fake app windows in previews」 | **部分**：我们有逐 App 的 `fixedNonstandardChromeHeight(pid:)` 与窗口分类，但没有以「无标题浮层」为名的分类规则；OmniWM 的 18 个夹具也点了这一类 | 无标题浮层不在窗口浏览里出现（见 OmniWM 夹具） |
| App **静默退出**（没有终止通知）留下陈旧条目 | DockDoor：「Apps that quit **without a clean termination notice** no longer leave stale entries behind」「Apps that quit silently no longer leave stale entries」 | **部分**：`DockHoverObserver` 有 Dock 实例核对；全局 App 退出的兜底要核 | `kill -9` 一个 App 后，条目消失 |
| 同一 App 的**多实例**（终端带特殊参数启动）关窗后残留 | DockDoor：「Closed windows from **separate instances of the same app** no longer linger as stale entries」 | **待核** | 两个 iTerm／两个 Terminal 实例并存时关一个，另一个不受影响 |
| Office／Chrome Web App 切视图时会**先关再开**窗口，被误判成「没窗口了」→ 退出 App | DockDoor：「Microsoft Office apps and Chrome web apps briefly close and reopen windows when switching views; DockDoor now **double-checks the app truly has no windows before quitting it**」 | **待核**（这条很危险：误判会导致我们替用户退出 App） | Word／Excel 切视图时不触发「最后窗口关了就先退出」 |
| **原生标签页**在 AX 里每页是一扇独立窗口，没有属性能查从属 | **四家独立撞到**：DockDoor 做了合并（`NativeTabGrouping`，见[竞品深挖](competitive-deep-dive.md)）＋「**Detached native tabs now each show as a separate entry** instead of collapsing into one」；Paneru v0.5.1／v0.5.2 连着两版「Improved **detection of native tabs**」；Rectangle「Add **title bar tab group** support」 | **未做**：一扇开 5 个标签的终端／访达会出 5 条 | 5 标签的终端只出一条；**被拖出来的标签**各自成条（这两条要一起验） |
| 陈旧预览／条目在切换后还留着 | DockDoor 多条（v1.13.1「eliminates stale previews」、race condition、orphan detection）；alt-tab-macos v11.6.0「a closed window may linger in the switcher」、v11.7.1「missing or leftover windows when apps open, hide or quit」 | **部分**：`WindowBrowser` 有实时刷新；以「关掉/新开立刻反映」为验收 | 关窗／新开窗后列表立刻准 |

### D 睡眠、唤醒、显示器与空间

| 现象 | 谁撞过 | 我们 | 可验收的形状 |
| --- | --- | --- | --- |
| **睡眠/唤醒后失灵**：快捷键不响应、预览不出来 | DockDoor：「**recovers automatically after sleep, screen wake, or a display/resolution change**, instead of keybinds or previews going unresponsive」「no longer freezes after waking from sleep **when an app is hung**」（多条）；alt-tab-macos v11.3.1「be more resilient to **sleep-wake macos bugs**」；OmniWM「Trackpad gestures now recover automatically after **sleep or wake**」 | **部分**：观察者不少（`PinnedPreview.swift:263`、`NotchActivityController.swift:251`、`SplitView.swift:117`、`NotchWatch.swift:139`、`WS2AppRuntime.swift:102`、`CarPlaySurface.swift:276`），**但没有一个统一的「唤醒后重建 tap 与观察者」收口** | 睡一次、醒一次，全部功能照常；日志能读出「因为唤醒，重建了什么」 |
| **显示器重配置**（接／拔／改分辨率）后崩溃或失灵 | alt-tab-macos v11.6.0「rare crash when **displays are reconfigured**」；DockDoor「recovers…after a **display/resolution change**」；AeroSpace v0.13.3／v0.11.2「native crash … when you interact with macOS fullscreen/minimized windows, hidden apps」 | **部分**：`NotchLevelObserver.swift:509`、`NotchController.displayID` 有处理；崩溃面没系统跑过 | 接一块屏 → 拔掉 → 改分辨率，三件事各一条探针 |
| 显示器**身份不稳定**：`CGDirectDisplayID` 每次重启会变 | OmniWM：「**Stable display UUIDs** keep new monitor settings, routing, workspace assignments, and restore fingerprints attached through reconnects and runtime display-ID changes」；DockDoor 同一条（`CGDisplayCreateUUIDFromDisplayID`） | **部分**：`App/NotchSpaceGate.swift:174` 已用 UUID；**其余「按屏落盘」的键要过一遍** | 重启、重接后，某块屏的设置还在那块屏上 |
| **全屏还原**（含 Electron／TextEdit 重建窗口时的幽灵列） | OmniWM 一整个子系统：0.4.7.3「Preserves managed window frames across native fullscreen restore… **suppresses layout animations during the restore pass**」、0.5.x「**Electron, TextEdit** and similar apps no longer leave **phantom columns** behind」、0.6.x「restoring one fullscreen window no longer breaks another」 | **部分**：我们有收起/还原与租约（[blueprint](blueprint.md)），但「全屏进出」这一组边界没有专名 | 进全屏 → 退全屏 → 换一扇再进，窗口不串、不留幽灵 |
| **Mission Control** 打开时窗口列表错 | alt-tab-macos v11.7.0「**wrong windows listed or focused during Mission Control on macOS 27**」 | **待核** | Mission Control 打开时窗口浏览照常 |
| **台前调度（Stage Manager）**：缩略图空/透明、贴边不留位、多屏多空间各有一份 bug | **这是一个独立家族**：DockDoor 七条（「Fixed blank/transparent preview thumbnails under Stage Manager」「Snapped windows leave room for Stage Manager」等）；Rectangle 七条（「Stage Manager: fix **multi-space**」「fix **multi-screen**」「footprint window workaround」）；Loop 五条；且 Rectangle 有一条**把一个功能撤到 Terminal flag 后面**：「Behavior for snapping windows dragged directly from Stage Manager recent apps has been pulled behind a Terminal flag, **since it was causing app instability**」 | **未做**：我们只有一条注释借了 Wins 的经验（`WindowBrowser/WindowBrowserController.swift:1704`「台前调度里窗口外框被缩放、捕获尺寸和真实比例对不上时，只留边，不变形」），**没有任何台前调度专门的适配或验收** | 开台前调度，重跑：收起、窗口浏览、分屏、贴边、多屏各一条 |
| 空格切换时的焦点交接 / 视图位置 | OmniWM：「Restore keyboard focus when switching to an already-visible workspace after **Mouse Warp** moves the pointer between displays」；0.5.10「quitting an app with `Cmd+Q` could leave the **view scrolled to where the closed window used to be**」；niri「closing a window … restore the view position」 | **部分**：[niri.md](niri.md) 跨桌面 92；「关闭/最小化后让出位置」已写在卷轴里 | 关掉当前列的窗口后，卷轴停在合理位置而不是空位 |

### E 离屏与几何取整

| 现象 | 谁撞过 | 我们 | 可验收的形状 |
| --- | --- | --- | --- |
| **「露一点」被写成 1 个物理像素，在 Retina 上取整后消失**，系统把窗口搬回屏幕 | OmniWM #557（原文）：「Hidden windows are parked just off-screen with a deliberate one-point reveal so macOS does not treat them as fully off-screen. That reveal was computed as **one *physical* pixel — half a point on a Retina display** — and position writes round to whole points, so it was lost and macOS pushed the fully off-screen window back onto the display. The reveal is now **one point at every display scale**」 | **已在做，而且是从原理上做的**：`Core/DisplayShape.swift:9` 写明「硬件数值按面板像素（px）存，用的时候除以 `pxPerPt` = 原生面板像素宽 ÷ frame 宽。**不用 `backingScaleFactor`**」；卷轴那一条走 `ArrangeGap.points`／`sliver.band`（点） | 在 1×／2×／外接屏上，停在屏幕外的列都不被系统搬走 |
| macOS 会**「抓住」正在移动的窗口**并把它挪到别的显示器 | paneru：「**Nudge off-screen windows slightly down.** This should help against MacOS "catching" moving windows and moving them to another display」；PaperWM.spoon README 同一件事（[竞品深挖](competitive-deep-dive.md) 有第三份证词） | **已在做**：我们走「露一条边」并写了成因（[niri.md](niri.md):90） | 拖动／滑动途中，窗口没有被换屏 |
| 窗口**完全滑出屏幕**该不该允许 | Loop「**Prevented windows from moving off-screen**」；AeroSpace v0.19.0「Floating windows could appear off-screen」；niri 浮动窗口「remembers positions relative to the monitor size，and will always **push windows slightly away from the monitor edges**」 | **已在做**：我们不把窗口放出去，只在屏幕边留一条 | — |
| 焦点跟随鼠标时，滑过一扇半出屏的窗口会**把它滚进视野**（双屏下尤其烦） | niri：「you will frequently have windows partially off-screen. With `focus-follows-mouse`, moving the cursor over such a window would focus it and **scroll it into view**. This is especially problematic if you have **two monitors side-by-side**, and just want to move the mouse to the other monitor」 | **待核**：我们有没有 focus-follows-mouse | 双屏横排时，鼠标从一块屏划到另一块屏，不动卷轴 |
| **RTL 语言**下位置算反 | Rectangle：「Fix bug with swapped stage manager **position for RTL languages**」 | **未做**（我们不做繁体是既定选择，但阿拉伯语/希伯来语一旦进语言表就会撞） | 若加 RTL 语言，贴边与台前调度位置不反 |

### F 手势与输入

| 现象 | 谁撞过 | 我们 | 可验收的形状 |
| --- | --- | --- | --- |
| 我们的手势在**每一次双指滚动时都起手**，于是 App 收不到后面的滚动 | OmniWM 0.7.6（原文）：「Column scrolling **armed a gesture at the start of every two-finger scroll**, so apps such as **browsers ignored the rest of the scroll**. Column scrolling now uses three or four fingers, like Overview, and a **stale momentum-suppression state no longer swallows a new scroll after a gesture**」 | **已在做**：`App/GlobalInputFilter.swift` 的 `GlobalInputPredicate.titleScroll`／`dockSwipe` 要求 `momentumPhase == 0`、相位认得出、且 **相位是 `.began` 或已经有进行中的一下**；`Notch.swift:5518` 还要求 `hasPreciseScrollingDeltas` | 在浏览器里双指滚动，浏览器照常滚；标题栏上的手势不吞掉正文滚动 |
| **手指离开后的惯性尾巴**被算成新手势 | DockDoor：「`scrollWheelEventMomentumPhase != 0` 直接丢」 | **已在做**：多处 `momentumPhase` 门（`GlobalInputFilter.swift:186/194`、`LaunchpadFolders.swift:706`、`SlideOver.swift:1013`、`HabitKeys.swift:281`、`Notch.swift:5518`、`ScrollTap.swift:170`） | 甩一下之后不再触发第二个动作 |
| **内置触控板与外接触控板互相覆盖／结束对方的手势** | OmniWM：「Raw multitouch ownership is **isolated per physical device**, preventing a built-in trackpad and an external trackpad from overwriting or ending each other's gestures」 | **未做**：我们的触点路径不带设备身份（`App/TrackpadGestures.swift:2214` 只数 `.touching` 的个数） | 接一块外接触控板，两边的滑动手势互不打断 |
| **丢了最后一帧「抬起」**，之后的手势被永久挡住 | OmniWM：「**Missing final lift frames** recover after a stale gap so later gestures are **not permanently blocked**」 | **部分**：我们是「手指数变了才回主线程」，丢帧时靠下一次计数变化自愈；**没有专门的过期恢复** | 故意中断一次手势（合盖再开／快速抬手），下一次手势照常 |
| 触控板的**每一帧移动都送到主线程** | OmniWM 0.7.5（原文）：「**Handle one-finger trackpad movement off the main thread.** Touch frames that cannot start any enabled gesture are dropped on the touch thread… main-thread touch deliveries fell from **94.2% to 0.53%** of frames」 | **已在做，而且写法一致**：`App/TrackpadGestures.swift:2218` 注释原文「在监听线程上：**只在手指数变化时回主线程，手指在触控板上移动的每一帧都不打扰主线程**」，且 tap 跑在专属 `.userInteractive` 线程上 | 单指移动光标时，主线程没有可测的触点投递 |
| **手势开着的时候 Dock 与菜单栏变卡** | alt-tab-macos v11.4.4：「dock and menu bar **lag** while gestures are enabled」 | **待核** | 手势期间划到 Dock／菜单栏，不卡 |
| 面板里装的手势 tap 把**我们自己的窗口**卡住 | OmniWM：「Fix OmniWM's **own windows unresponsive** due to mouse event tap」 | **部分**：我们的 tap 是 `.listenOnly`；`PinnedPreview` 有多处「自己的窗口」判断 | 悬停我们自己的面板时照常 |
| 热角在手势期间误触发 | niri：「Fixed the **hot corner triggering during the view scrolling gesture**」 | **未做**（我们不做热角）；若做概览热角要记这一条 | — |

### G 性能、资源与崩溃陷阱

| 现象 | 谁撞过 | 我们 | 可验收的形状 |
| --- | --- | --- | --- |
| **空闲 CPU**：常驻轮询不停 | Atoll：「Reduced **idle CPU** from always-on **notch hover polling** and **OSDUIHelper process checks** by **backing off when the app is idle**」；alt-tab-macos v11.7.0「**less battery** used while AltTab is idle」、v11.7.0「the switcher may be **slow to appear after a long idle**」；OmniWM「trims idle input work」「**Skip the own-window hit test when it cannot matter**」 | **部分**：我们不轮询也不碰 OSDUIHelper（`App/NotchLevelControl.swift:9` 明确「不向 OSDUIHelper 或任何系统进程发信号」）；**空闲退避是否成体系要核**（R30 的 60 秒静置实测仍开着） | 静置 60 秒，CPU 曲线可解释；且长时间空闲后第一次操作不迟钝 |
| **锁屏／屏保时资源占用暴涨** | Ice 0.2.2：「excessive **memory usage when the screen is locked or the screen saver is active**」 | **部分**：多处监听锁屏并暂停（`PinnedPreview.swift:267`、`NotchLevelObserver.swift:389`、`CarPlaySurface.swift:283`、`NotchAuthentication.swift:47`、`SplitView.swift:118`） | 锁屏 5 分钟后量一次占用 |
| 切换 App 时**菜单栏覆盖层** CPU 飙 | Ice 0.10.0：「excessive **CPU usage by menu bar overlay panel when switching apps**」 | **部分**：我们有菜单栏相关面要核 | 连续快速切 20 个 App，CPU 曲线平 |
| **启动崩溃**：初始化里做同步外部调用，run loop 被转起来，SwiftUI 的 view body 重入同一个初始化 → `trying to lock recursively` | Atoll 2.3.3-beta.3（原文很具体）：「`BluetoothAudioManager`'s initialiser scanned connected devices **synchronously**, and that scan blocks on **`Process.waitUntilExit()`, which spins the run loop** — letting SwiftUI evaluate a view body that reads `BluetoothAudioManager.shared` and **re-enter the initialiser** that was still running. The scan now starts on the **next main-queue turn**」 | **待核**：搜我们有没有在初始化路径里做同步外部进程调用（蓝牙、声音、更新） | 冷启动 20 次不崩；初始化里没有 `waitUntilExit` |
| 窗口动作 **栈溢出**、空循环崩溃、更新器跨线程崩溃 | Loop：「Fix **stack overflow** crash on window-move actions」「Fix crash when a cycle action has an empty cycle」「Fix **updater crash** when updating download progress off the main thread」 | **待核**：我们的更新器（Sparkle ＋ `UpdaterSystem.swift`）与窗口动作的递归面 | 更新下载中反复切页面不崩 |
| **长时间运行后整数溢出** | niri：「Fixed a panic **after ~50 days of uptime due to an integer overflow**」 | **待核**：搜我们的运行时长／计数器累加 | 用假时钟把 uptime 推到 60 天，不崩 |
| 显示器/手势/退出时的**罕见崩溃** | alt-tab-macos 一长串：v11.6.0「rare crash when **displays are reconfigured**」「rare crash when cycling the switcher **as a window closes**」、v11.5.0「rare crash when a gesture session ends **while fingers are still down**」「crash on trackpad gesture via **Universal Control**」、v11.7.0「rare crash when AltTab **quits on logout or shutdown**」 | **待核**：这几条正好是「手势还没结束就换屏/退出」这一族 | 手势进行中拔屏、手势进行中退出 App，各一条探针 |
| `CGPoint.findIn` 之类**越界查找**原生崩溃 | AeroSpace：#164 `CGPoint.findIn` crash，#1492／#1921 等 | **待核** | 我们的几何查找要有边界行为 |

### H 设置迁移、本地化与系统版本

| 现象 | 谁撞过 | 我们 | 可验收的形状 |
| --- | --- | --- | --- |
| **新增一个必填字段就把用户配置整个清掉** | OmniWM 0.6.2→0.6.3（原文）：「Your `settings.toml` is **replaced with defaults on first launch** unless you edit it first. 0.6.3 requires two new fields that a normal 0.6.2 file does not contain. Without them, OmniWM preserves the old file as `settings.toml.corrupt`, replaces the live file with full defaults」「**your configuration stops applying** until you restore it」 | **部分**：我们只有一条带版本号的迁移（`WindowShade.swift:529` `migrateDistractingDefaultSounds`，键 `shadeSoundMigrationVersionDefaultsKey`）。**新增一个必填项就回默认值，是我们会犯的同一类** | 拿旧版设置文件启动新版，设置照旧；缺字段只补那一个 |
| **降级会把设置读坏** | OmniWM 连续三代都在写这件事：0.6.4「Migration is **forward-only**」、0.7.3「`settings.toml` upgrades to **schema 4**… The original is kept as `settings.toml.pre-v4`… **Restore the backup before downgrading**」 | **未做**：没有 schema 号、没有 `.pre-vN` 备份 | 每次改设置格式前，原文件留一份带版本号的备份 |
| **用户没有办法备份/恢复设置** | DockDoor：「Back up and restore settings **as a JSON file**」「Settings > General > Backup & Restore > Export/Import…」，并且**设置搜索里能找到**「backup/export/import/restore/sync/dotfiles/iCloud」 | **未做**：grep 不到设置的导出/导入 | 设置里能导出成一份 JSON、能导回来；设置搜索能搜到 |
| **设置触发的重启后，设置窗口不回来** | DockDoor：「Settings **reopen after settings-triggered restart**」（两次提到） | **待核** | 需要重启才能生效的开关，重启后设置窗口回到原页 |
| **改进程的 locale 会污染整个 App** | OmniWM：「Settings… no longer **crash on macOS 27 betas for users in comma-decimal regions**… The built-in terminal's startup had switched the **process's numeric locale**, which broke symbol rendering in those regions」 | **已在做**：grep 不到 `setlocale`／`LC_NUMERIC`，我们不改进程 locale | 德语/法语区（逗号小数）下不崩、数字显示正确 |
| **单位先换算再上色**（摄氏/华氏混用导致读数永远是最热的颜色） | Atoll：「The colour scale it draws from was also being **read in Celsius whatever the display unit**, so every Fahrenheit reading above freezing came out the hottest colour — **readings are converted before they are coloured**」 | **待核**：我们的电量／亮度／计时显示有没有单位换算 | 切成华氏/12 小时制，颜色与刻度仍然对 |
| **本地化要覆盖的不只是文案**：格式化、无障碍标签、OSD | boring.notch v2.8-rc.0：「Improved **locale-aware formatting across settings, battery, OSD, progress indicators, and accessibility labels**」 | **部分**：正在做英语适配（[BATCH27](handoff/BATCH27-ENGLISH-HANDOFF-2026-10-12.md)）；**格式与读屏标签是否在范围内要确认** | 英文下数字、时间、日期、读屏标签都是英文习惯 |
| 系统大版本会**大改菜单栏**，要靠 workaround 重建能力 | Ice 0.11.13：「Apple made **significant changes to the menu bar** that require new solutions. This release contains some preliminary fixes and workarounds to **restore a basic subset of features**. Not everything works the way it should.」 | **待核**：我们菜单栏面的 macOS 27 行为 | macOS 27 上菜单栏面逐条过 |

### 闭源竞品的一手日志（开源码看不到的那半边）

上面八族几乎全来自开源项目，因为开源项目的日志最完整。但**闭源那几家修过一批开源项目碰不到的东西**——尤其是「收起本体」这一格（WindowMizer 66 版／972 行）、Dock 悬停预览这一格（Wins 3.1→3.6、DockMate）、启动台这一格（LaunchOS 37 个版本）。下面五族（K–O）来自它们。

#### K 睡眠、唤醒与显示器（闭源也在同一条线上）

| 现象 | 谁撞过 | 我们 | 可验收的形状 |
| --- | --- | --- | --- |
| **唤醒后手势失效** | LaunchOS v1.5.1「Fixed an issue where **trackpad gesture could stop working after startup or waking from sleep**」；**v1.5.7 又修一次**「Fixed the issue of **trackpad occasionally failing after computer sleep**」 | 见 D 族：我们有唤醒观察者，但没有统一收口 | 睡/醒一次，手势照常；**跑两遍**（它修了两次） |
| 唤醒后预览里出现**红绿灯按钮** | Wins **两次**：3.1.1「Mac 从睡眠状态唤醒后，Dock 窗口预览偶发显示 🚥 按钮」、3.4「修复 Dock 窗口预览在睡眠唤醒后偶发显示红绿灯按钮的问题」 | **已有对策**：`Capture/CaptureIndicatorRemoval.swift` 专门检测并抹掉左上角 170×64 那一块里的红绿灯组 | 睡醒后立刻悬停 Dock，缩略图里没有红绿灯 |
| 唤醒/改显示器时崩溃 | WindowMizer 6.2.8「Crash when restarting, shutting down, or quitting **after a display change**」、「**Prevent crash on wake/display configuration changes**」、「Intermittent crash when attaching/removing additional monitors/displays」 | 见 D 族 | 睡前拔屏／醒后接屏，各一条 |
| 接／拔显示器后**界面显示不对** | LaunchOS v2.3.0「the interface could **display incorrectly after connecting or disconnecting a display**」；v0.9.4「display issues on **multiple monitors**」 | 待核 | 接屏/拔屏后，刘海与面板位置重算 |
| 覆盖层显示了**另一块屏的快照**；三块以上；两块同型号 | WindowMizer 6.2.x：「Fixed overlay windows from showing the **wrong monitor's snapshot** on multi-display setups」「Works with **three or more** monitors」「Works when monitors **share the same size and resolution**」「Overlay window's **rebuild automatically if display count changes**」 | 待核：我们的 `NotchLevelObserver`／预览有按 `CGDirectDisplayID` 取屏；**「两块同型号」是会撞的**（同 displayName、同分辨率） | 接两块同型号屏，各自显示各自的快照；拔掉一块，另一块不错位 |

#### L Dock 悬停预览的真实边界（DockMate 与 Wins）

| 现象 | 谁撞过 | 我们 | 可验收的形状 |
| --- | --- | --- | --- |
| **面板隐藏了还在挡鼠标** | DockMate「Fixed Preview window **blocking mouse events while hidden**」 | 待核 | 面板收起后，那一块区域能正常点到下面 |
| Dock **开着自动隐藏**或**开着放大** | DockMate「Improved Support for Dock with **autohide** enabled」「…with **magnification** enabled」 | 已有：我们处理了 Dock 四个方向与自动隐藏（[competitive-analysis.md](competitive-analysis.md):33） | 开/关自动隐藏、开/关放大，各一条 |
| Dock 在**左边或右边**时预览位置不对 | Wins 3.1.1「当 Dock 位于左侧或右侧时，Dock 窗口预览触发位置不正确」 | 已有（四个方向） | 四方向各一条 |
| 指针在 Dock 的**边缘像素**上不出预览 | DockMate「Preview window **not drawing if mouse was on very edge pixels of the Dock**」 | 待核 | 指针贴 Dock 最外一像素，仍能触发 |
| **快速移动鼠标**／**快速切换图标或重新悬停同一图标**时预览闪掉或给错图标 | DockMate「Preview window showing for a **nearby tile when rapidly moving mouse**」；Wins 3.6「修复**快速切换 Dock 图标或重新悬停同一图标**时，窗口预览意外消失的问题」 | 待核（[competitive-analysis.md](competitive-analysis.md):33 已按 Wins 的场景列了验收，尚未上机） | 来回快速扫过 5 个图标，每次都出对的 |
| Dock **还在隐藏动画里**就抢着聚焦窗口 | DockMate「Window **focusing too quickly on slower machines when Dock is still hiding**」 | 待核 | 自动隐藏的 Dock，点图标后不抢焦点 |
| 大预览的三类坏法：**分辨率低／被拉伸／不同步** | DockMate「Large preview showing in **low resolution**」「getting **stretched**」「being **out of sync**」 | 部分：`WindowBrowserController.swift:1704` 有「只留边不变形」的比例处理 | 大预览：清晰、不拉伸、和实时画面同步 |
| **定时器没释放**导致 CPU 高 | DockMate「**Elevated CPU usage related to unreleased timers** for scrolling text in music view」 | 待核：我们常驻面里的计时器在收起时是否释放 | 收起所有常驻面后，CPU 回到静息 |
| 窗口列表里出现**「假窗口」** | Wins 3.2「优化 Dock 窗口预览逻辑，减少出现"假窗口"预览的情况」 | 见 C 族（无标题浮层） | 同 C 族 |
| 某些第三方 App **预览不出来** | Wins 3.1.1「修复 **ToDesk、QQ 音乐**等第三方应用无法正常预览窗口的问题」 | 待核：这类 App 的 AX 面常常不标准 | 装几个国产 App 各验一条 |

#### M 收起本体这一格：外观切换与 Finder（WindowMizer 独有）

| 现象 | 谁撞过 | 我们 | 可验收的形状 |
| --- | --- | --- | --- |
| **系统明暗切换后**占位条不重建 | WindowMizer「Recreate placeholder images after **System Appearance change** (light/dark mode). **Note: Placeholder strips must be restored and re-collapsed for Appearance changes to take effect.**」；Wins 3.3「修复 Wins Panel 在切换到系统暗黑模式后无法自动适配主题的问题」 | 待核：卷帘条有没有订阅外观变化并重画 | 收起几扇窗 → 切明/暗 → 卷帘条立刻跟上，不用重新收起 |
| 重启后第一扇收起的窗口**用错了外观** | WindowMizer「**After restart, the first reduced window no longer appears in Dark Mode when the Mac is set to Light**」 | 待核 | 明色模式下重启，第一扇收起的窗口不是暗色 |
| **「降低透明度」开着／关着**是两套行为 | WindowMizer「When **Reduce Transparency** is on, overlay uses the previous full-screen behavior to avoid menu bar flicker」「Prevents duplicate/overlaying menu bars during reduce when Reduce Transparency is off」 | 待核：这是一个真实的无障碍设置，会改变我们的叠层画法 | 开关「降低透明度」各跑一遍：菜单栏不闪、不叠两条 |
| 收起／还原时**菜单栏闪错 App 名或留空** | WindowMizer 三条：「Menu bar now shows the app name sooner」「Reducing a window no longer **flashes the wrong app name or "Application"**」「Fixed issue where the **menu bar stayed blank** after reducing windows」 | 待核 | 连续收起 5 个不同 App 的窗口，菜单栏一直是当前 App 的名字 |
| 改窗口大小把 **Finder 列表视图的列宽**弄乱 | WindowMizer **两次**：「Finder window **column sizes** to change after window-shading a window」「when minimizing and restoring a Finder window, the Name, Size or Date column would be **a different** after collapsing and restoring」 | 待核：我们收起会写 frame；Finder 列表视图对 frame 变化敏感 | 列表视图的访达窗口，收起再还原后四列宽度不变 |
| **访达替身**（folder alias）双击被当成窗口动作 | WindowMizer「Double-clicking a **Finder folder alias** no longer performs a window action」 | 待核 | 双击桌面上的文件夹替身，不触发起伏 |

#### N 退出策略与权限（闭源才有的两类）

| 现象 | 谁撞过 | 我们 | 可验收的形状 |
| --- | --- | --- | --- |
| **IM 类 App 关掉最后一个窗口不该退出**，而**单窗口 App（App Store、计算器）关掉占位条就该退出** | Wins 3.2「**IM 应用在关闭最后一个窗口后将不会自动退出，而是保持后台运行**」；WindowMizer「**Single-window apps now quit** when closing the placeholder – if that's what they normally do (Ex: App Store, Calculator)」 | 待核：这是**一对相反的需求**，只能按 App 分类处理 | 微信/QQ 关最后一扇窗不进后台退出；计算器关掉占位条正常退出 |
| **辅助功能权限在运行中被撤掉**，必须告诉用户 | WindowMizer「Improved Accessibility setup and handling when **permission is lost**」「**Display an alert when Accessibility is turned off while WindowMizer is running**」 | **未做**：我们只在若干处静默读 `AXIsProcessTrusted()`，没有「权限被撤 → 告诉用户」的路径 | 运行中把辅助功能关掉，App 立刻说明「因为你关了权限，我不能工作了」 |
| **权限弹窗还开着的时候启动崩溃** | WindowMizer「Fixed a crash that could occur **during first launch while macOS is asking for Accessibility or Screen Recording permission**」 | 待核 | 全新机器第一次启动，权限弹窗逐个点，不崩 |
| 「最后一次还原」的**动画方向错**：被 `⌘H` 隐藏或最小化的窗口，回来时从屏幕**底角斜着飘进来** | ChainYourMac 2.2.3（appcast 原文）：「Windows of an app you hid (⌘H) or a window you minimized no longer **glide diagonally out of the bottom corner of the screen** when they come back. **They slide in from the screen edge like every other window.**」 | 待核：我们的还原动画有没有按来源分类 | 隐藏过的窗口回来时，方向和别的窗口一致 |
| **授权检测不稳定 / 重复激活** | Wins 3.3「提高授权检测的稳定性，减少**授权丢失需要重复激活**的问题」、3.5.1、3.6（这三条属**授权与防篡改**那类，[竞品深挖](competitive-deep-dive.md)第一节把它列为不分析、不绕过的禁区，**此处只记录存在**） | — | — |
| macOS 27 把系统设置的**辅助功能面板改名**为 Device Control and Data Access | WindowMizer「Conform to macOS 27 (**Golden Gate**) renaming of System Settings: **Accessibility panel -> Device Control and Data Access**」；boring.notch 同一条（A 族） | 同 A 族 | 文案与系统设置的分区名一致 |

#### O 启动台这一格（LaunchOS 的 37 个版本）

| 现象 | 谁撞过 | 我们 | 可验收的形状 |
| --- | --- | --- | --- |
| 图标在**不同分辨率**下显示异常／被放大 | LaunchOS v2.1.0「app icons would display **abnormally at different resolutions**」、v2.1.3「app icons could appear **enlarged**」 | 待核 | 换分辨率、换缩放档，图标不变形 |
| **有些 App 不出现** | LaunchOS v2.2.1「some apps **might not appear**」 | 待核 | 全覆盖测试：装一批冷门 App 看是否都在 |
| **Safari Web App** 卸载时出问题 | LaunchOS v2.4.0「Fixed an issue that could occur when **uninstalling Safari Web Apps**」 | 待核（同 C 族的 Office／Chrome Web App 一类） | 装一个 Safari Web App 再删掉，不崩不残留 |
| 启动台自己**出现在 Cmd+Tab 里** | LaunchOS v1.3.0「Fixed LaunchOS appearing in the **Cmd+Tab app switcher**」 | 已有：我们是 `LSUIElement`（见[竞品深挖](competitive-deep-dive.md)第三节的静态面） | 启动台不占 Cmd+Tab |
| **文件夹开着时全局搜索不可用** | LaunchOS v2.0.0「global search was unavailable **while a folder was open**」 | 待核 | 打开一个文件夹后再搜索，能搜 |
| macOS 27 上**壁纸显示**问题 | LaunchOS v2.1.1「wallpaper display issues on **macOS 27.0**」 | 待核 | macOS 27 上换壁纸，启动台/刘海背景跟上 |
| **某些机型**上 F4 键不工作 | LaunchOS v1.5.5「the **F4 key** was not working on some models」 | 待核（启动台触发键） | 老机型／外接键盘上触发键可用 |
| 不同语言下**文字被裁切** | LaunchOS v2.3.1「text could be **clipped in some languages**」；Wins 3.1.1「设置面板在**西班牙语、德语、中文、日语**等语言环境下无法完整显示的布局问题」 | **未做但即将撞**：英语适配正在做（[BATCH27](handoff/BATCH27-ENGLISH-HANDOFF-2026-10-12.md)）。**德语最长，最容易撑破** | 每种语言跑一遍设置窗口与常驻面，看有没有裁切/换行溢出 |
| **Intel Mac** 上的差异 | Wins 3.5.1「修复 **Intel Mac 在 macOS 14.8.9** 下无法打开系统设置面板」；alt-tab-macos v11.4.2「app may crash at launch on **intel macs**」 | 待核：我们的构建是 arm64＋Intel 双支持还是只 arm64，要核（[production-maturity](production-maturity.md) 的发行面） | 若有 Intel 构建，至少一台真机跑一遍 |

## 三、我们已经在做的（核实过，不必重做）

上面标「已在做」的，逐条对应到代码：

| 竞品修的问题 | 我们的对等实现 | 位置 |
| --- | --- | --- |
| 不能信 `kAXUIElementDestroyedNotification`（AeroSpace／OmniWM） | 把销毁通知**当提示不当许可**：要求 `CGWindowListCopyWindowInfo(.optionIncludingWindow, id)` 查回空，且校验回调序号 | `App/FoldTransaction.swift:919` |
| Dock 重启后悬停静默失效（DockDoor 的健康检查） | Dock 实例 **1 秒节流核对**，发现换了 pid 就重建 | `WindowBrowser/DockHoverObserver.swift:316` |
| tap 被系统禁用（DockDoor／全行业） | 五处 `tapDisabledByTimeout`／`tapDisabledByUserInput` 重开 ＋ 输入洪泛退避 | `GlobalInputFilter.swift:360`、`ScrollTap.swift:158`、`WindowSwitcher.swift:74`、`TrackpadGestures.swift:2242`、`NotchLevelObserver.swift:294`、`WindowShade.swift:962` |
| 手势吞掉 App 滚动（OmniWM 0.7.6） | 起手或已有进行中才算，且要求 `momentumPhase == 0`、`hasPreciseScrollingDeltas` | `App/GlobalInputFilter.swift` `GlobalInputPredicate`、`Notch.swift:5518` |
| 触点帧压主线程（OmniWM 0.7.5） | **只在手指数变化时回主线程**，tap 跑在专属 `.userInteractive` 线程 | `App/TrackpadGestures.swift:2218` |
| 离屏「露一点」被取整吃掉（OmniWM #557） | 按面板像素存硬件数值、用时除以 `pxPerPt`；卷轴那条走点 | `Core/DisplayShape.swift:9`、`ArrangeGap.points` |
| AX 拖死系统（AeroSpace 0.18.0） | 按 App 的后台队列 ＋ 逐调用 `AXUIElementSetMessagingTimeout` ＋ 按调用熔断 | `niri.md:46`、`Window/AXWindow.swift:310/324` |
| 不可响应的 App 拖慢界面（DockDoor／alt-tab） | 对同一忙 App 的退避，不反复烧满 AX timeout | `PinnedPreview.swift:633` |
| 常驻面在锁屏后烧资源（Ice 0.2.2） | 锁屏/屏保/唤醒观察者，各自暂停 | `PinnedPreview.swift:263`、`NotchLevelObserver.swift:389`、`SplitView.swift:117`、`CarPlaySurface.swift:276`、`NotchAuthentication.swift:47` |
| 改动进程 locale 会污染（OmniWM） | 不改进程 locale | 全仓无 `setlocale` |

**这一节的意义**：我们的架构判断是对的，而且有几处比竞品做得早（销毁通知只当提示、触点帧只在计数变化时过主线程、离屏一律用点）。**欠账集中在「没有人的那一段」**，不是集中在机制上。

## 四、动作清单（按先后）

**第一梯队：不修会持续出血的**

1. **唤醒后的统一收口**（D／K 族）：睡眠唤醒是这一整份里出现最多的一件事，而且**闭源也在同一条线上**（DockDoor 多条、alt-tab、OmniWM、niri 的盖子、WindowMizer 的崩溃、**LaunchOS 连修两版的手势失效**、Wins 两次的红绿灯）。我们现在观察者散在六处，缺一个「唤醒 → 重建 tap 与观察者 → 记一行日志」的位置。**这是第 1 优先。**
2. **原生标签页合并**（C 族）：四家独立撞到，判据现成（同 pid ＋ 取整相同的 frame），**且要连「被拖出来的标签各自成条」一起验**。闭源的 Wins 也在修 Finder 多标签。这条直接抬窗口浏览那一格。
3. **辅助功能权限被撤掉要告诉用户**（N 族）：WindowMizer 明写「Display an alert when Accessibility is turned off while WindowMizer is running」。现在我们只在若干处静默读 `AXIsProcessTrusted()`——**权限一撤，App 就静默失灵，用户不知道为什么**。
4. **设置备份/导出/导入 ＋ 迁移策略**（H 族）：现在是「新增必填字段就回默认值」的状态。OmniWM 用三代版本换来的教训是**先留 `.pre-vN` 备份、迁一次只补缺的字段**；DockDoor 把它做成设置里的一项并能搜到。**这是数据安全，优先于功能。**
5. **事件通道的周期巡检**（A 族）：补 `CGEvent.tapIsEnabled` 巡检 ＋ 事件投递金丝雀（写法见[竞品深挖](competitive-deep-dive.md)第四节）。我们现在只有 Dock 悬停那一处有 1 秒的实例核对。

**第二梯队：抬具体格子的**

6. **台前调度**（D 族）：DockDoor 七条 ＋ Rectangle 七条 ＋ Loop 五条，四家都在这上面反复栽。先要**一组探针**而不是功能。
7. **Dock 悬停的真实边界**（L 族，七条）：自动隐藏、放大、四方向、边缘像素、快速扫过、面板隐藏还挡鼠标、定时器未释放。我们已经有四方向与自动隐藏，**其余五条是待核**。
8. **外观切换（明暗、「降低透明度」）**（M 族）：WindowMizer 明确说「占位条必须**重新收起一次**才生效」——那是它没做好的地方，我们要做对。Wins 也栽在暗色适配上。
9. **Finder 两个坑**（M 族）：列表视图**列宽**被改（WindowMizer 修了两次）、**文件夹替身**双击被当窗口动作。
10. **菜单栏在收起/还原时闪错名或留空**（M 族，WindowMizer 三条）。
11. **退出策略按 App 分类**（N 族）：**IM 类关最后一扇窗不退出** vs **单窗口 App（App Store／计算器）关占位条就退出**——这是一对相反的需求。
12. **多语言下的布局裁切**（O 族）：Wins 栽在德/西/中/日，LaunchOS 栽在「text clipped in some languages」，boring.notch 专门做了一遍 locale 感知格式化。**英语适配正在做，德语最长最容易撑破，验的时候要按最长的那一门来。**
13. **`orderOut` 关窗、无标题浮层、静默退出、多实例**（C 族四条待核）：验的方式都是「造一个这样的 App，看列表对不对」。

**第三梯队：不会立刻出血但要记的**

14. **多点触控的设备归属**（F 族）：内置 ＋ 外接触控板的互相打断。
15. **Secure Input 的可见说明**（A 族）：OmniWM 做成了菜单栏的一行红锁。
16. **证书轮换与辅助功能重新授权**（A 族）：换 Developer ID 之前写进欢迎流程。
17. **崩溃面排查**（G 族）：`waitUntilExit` 重入、递归栈溢出、整数溢出、手势进行中换屏/退出、**权限弹窗还开着时启动**。
18. **启动台与 Intel 机型**（O 族）：图标在不同分辨率下的形态、冷门 App 是否都出现、有没有 Intel 构建要跟。


## 五、口径与来源

- **口径**：本轮把「更新日志」当作一手材料，和二进制、源码同级。取的是**作者自己写的、面向用户的**修复记录，不采信二手转述。每一条都带项目与版本号，可回查。
- **原始日志**（**不进仓库**）：`/tmp/ws-research/releases/*.md`（逐项目合并的 release notes）＋ `/tmp/ws-research/releases/digest/*.txt`（按失效主题切出的去重摘要）。
- **取法**：`gh api repos/<owner>/<repo>/releases?per_page=100 --paginate`，读取于 2026-10-14。闭源那几家的一手页面此前已落盘：`/tmp/ws-research/sites/*.html`。
- **已并入仓库的日志**：[DynamicLake 79 版／1,946 行](dynamiclake-changelog.md)（唯一全文入库的一份）、WindowMizer 66 版／223 条的摘要见[竞品深挖](competitive-deep-dive.md)第三节。
- **不做的**：日志里出现的**防破解/防篡改/授权校验**那类条目（Wins 3.6 有），不分析、不试探、不绕过——[竞品深挖](competitive-deep-dive.md)第一节的界线。
