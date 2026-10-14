# 竞品深挖：一手公开材料 + 开源码 + 量自己

更新于 2026-10-14。这份补的是 [竞品调研](competitors.md)、[Wins](competitive-analysis.md)、[niri](niri.md)、[每个领域的分数](scorecard.md) 之外的**机制层**：
以前只从各家产品页读「它有什么」，这一份读它**怎么做到**。目标是取长补短，不是记功能清单。

来源分三类，逐条标出：

- **一手公开材料**：各家官网、更新日志、商店页、自家 release notes。照 [competitors.md](competitors.md) 的规矩——取不到就写取不到，不靠二手描述补。
- **开源码**：仓库可读，按许可证分级（见下）。
- **量自己**：对我们本机的构建做静态测量。竞品逆向**未开始**，原因见第六节。

## 一、方法与界线

前提照记（Aaron 2026-10-14 口述）：非商业项目、自行实现、已征询律师意见。结论以律师为准；下面是**做法**上的界线，逐目标核。

1. **不绕过保护措施。** 不碰 DRM、授权／序列号检查、anti-tamper、加密载荷。若某个目标的保护让分析非绕过不可，**停下来回报**，不硬上。已经撞到一条：Wins 3.6 更新日志自述「加强授权验证与应用完整性检查，提高防破解和防篡改能力」——这一类就是禁区，不做。
2. **不搬代码、不搬资产。** 产出是**行为与机制描述**（它怎么判定、状态机长什么样、边界在哪），实现我们自己写。下面每条都标「观察」（源码／发布日志直接读到）或「推论」（从观察推出来的）。
3. **许可证分级。** 开源码能不能拿代码，看许可证：MIT 可借代码并带版权声明；GPL／CC BY-NC 只借思路，附来源 repo、分支与 commit。本项目是 MIT，所以 GPL 那几家（Atoll、niri）**只能用它们的思路，不能拷代码**。
4. **全程留证据。** 每个结论带来源与读取日期；开源码带 commit SHA。这一项不是负担，是这个项目本来的规矩（[Computer Use 验收](computer-use-qa.md) 也是这么要求的）。
5. **取得与分工。** 把竞品 App 弄到本机是**授权行为**——安装即接受它的条款，付费版要买（试用的时长／退款条款各家不同，见第三节）。这一步由 Aaron 做，不由执行模型代替：**Aaron 取件，分析在件上做。** 2026-10-14：Aaron 先后供了 Wins 3.5.1 与 Alcove 1.7.7 的 DMG（都未安装），已在两份上做了静态面分析，见第三节；其余各家尚未供件，逆向**未开始**。

## 二、结论：取长补短 + 我们已经在做的

每一行 = 一条可以拿过来的做法，对到 [scorecard](scorecard.md) 的领域和我们的欠账，最后是可验收的形状。

| 借什么 | 来自 | 对到哪个领域 | 我们的欠账 | 可验收的形状 |
| --- | --- | --- | --- | --- |
| 下载「完成 vs 取消」的判定：目标档**被写过**、非空、且时间戳**比开始时晚** | Atoll `DownloadManager.completed` | 进度卡（新表面） | [progress-in-notch.md](progress-in-notch.md):128 的规则少两条：Firefox 的空占位档、覆盖已存在的档 | 用 Firefox（占位档）／Safari（bundle）／Chromium 各下一次，中途取消一次；取消不说"完成" |
| Safari 的 `.download` 是 **bundle**，字节落在子档里，要递归加总 | Atoll `allocatedBytes` | 同上 | 现有笔记写「只文件」，漏了 Safari | Safari 下载时进度条在动，不是"卡住" |
| 用 **allocated size** 而不是 logical size 算进度 | Atoll 注释（`bytesInProgress`） | 同上 | 未记载 | 对预分配整档的浏览器，进度不显示成"瞬间完成" |
| 扫描簿记与目录 watcher 分开，测试可注入扫描 | Atoll `init(monitoringDisabledForTesting:)` | 测试 | — | 扫描簿记有单测，不靠真去动 `~/Downloads` |
| 手指位移 → 一屏：**1200 逻辑点** | niri `VIEW_GESTURE_WORKING_AREA_MOVEMENT` | 标题栏手势／卷轴 | 手感值未定 | 手感参数成为可调常量，有探针 |
| 甩动投影：**150ms** 速度视窗、阻尼 **0.997** | niri `SwipeTracker` | 甩一下（94） | 未记载投影模型 | 甩出去的落点与速度投影一致 |
| 列宽存**比例**不存像素，换屏后仍并排 | niri `ColumnWidth` + 注释 | 卷轴／分屏 | — | ⅓+½ 在换屏、改分辨率后仍并排 |
| 平台吃掉手势时，**从 scroll delta 反推方向** | niri `ScrollSwipeGesture` | 标题栏手势 | 我们是"三指被系统占、改用标题栏两指" | 方向判定不依赖手指数 |
| 不可见工作区塞到可见区**角落外一像素**，并记住原位 | AeroSpace `MacWindow.hideInCorner` | 卷轴「停在屏幕外的列」 | [niri.md](niri.md):90 已把它列为限制 | 露一条边的列能还原回原位 |
| 切换时**先 unhide 可见的、再 hide 不可见的** | AeroSpace `refresh.swift` | 卷轴 | — | 切换时不出闪烁 |
| 最小尺寸：先试 → settling pass → 才判定被 AX 夹住 → 提示 | Rectangle `WindowManager` / `WindowAnimationPlacement` / `MessageView` | R46「做不了就说一声」 | 现有只写"浮窗说一句" | 固定尺寸窗口（计算器、系统设置）排布时出提示，不假装做了 |
| DockDoor 的 12 条 release 修复当验收用例 | DockDoor releases | 窗口浏览视觉验收 | [competitive-analysis.md](competitive-analysis.md):33 已经要了，但没上机 | 每条 bug 场景各一条探针（见第四节） |
| Wins 3.5/3.5.1 的拖动误触发与 macOS 27 拖动卡顿 | Wins 更新日志 | 刘海落点小岛（R23–R25、R33） | 已写进登记 | 照场景验收 |
| AirPods 每个型号／配色一份**预渲染影片**，连上时播 | Alcove Resources（10 组 `airpods-max-*.mp4` 等） | 设备电量／刘海 | 未记载 | 连上 AirPods 时刘海出现对应型号的动画 |
| 正在播放：**公开** Apple Events 定向控制具体播放器（`com.spotify.client`／`com.apple.Music`…） | Alcove entitlements | 刘海（88）／正在播放 | 设计稿倾向私有 `mediaremote-adapter` | 播放器能读到曲目；且不依赖私有框架（稳定性换覆盖面） |
| **无标题窗口**、App 专用浮动面板（Premiere）、**系统设置**、Finder 替身、**显示器变化** | WindowMizer 6 的修复史（6.2.3–6.2.8） | 收起本体（92） | 我们的验收没覆盖这几类边界 | 每条各一条探针；收起不崩、菜单不错乱、恢复原位 |
| 分屏时**按刘海精确避开**，活动工作区固定在刘海左侧 | OmniWM（GPL-2.0，开源） | 刘海（88）／分屏 | 未记载 | 分屏避开刘海；活动列固定在左 |
| **「No focus stealing」**：后台 App 弹窗不抢焦点、不滚 strip | ChainYourMac 官网 | 卷轴／看一眼 | 未记载 | 后台弹窗时焦点与 strip 位置都不动 |
| 装／跑着别的窗口管理器（Rectangle／Magnet）时**检测并警告** | ChainYourMac「Mac Setup」 | 键盘（90）／quiet-defaults | 我们现在只对 Swish 说一次 | 检测到别的 WM 在跑时能报出名字 |
| **self-healing engine**：引擎进程挂了自动拉起，并留日志 | ChainYourMac 官网 | 稳定性（无对应格） | 未记载 | 引擎被杀掉后能自愈，且日志能说明发生了什么 |
| 一条 strip **每显示器、每 Space 各一份**，且能按屏单独关掉 | ChainYourMac「Configuration → Displays」 | 多显示器（90）／跨桌面（92） | 已有「每张桌面都有」，但没「按屏单独关」 | 某一块屏可以退出接管，窗口留在原处 |
| **权限面收到最窄**：不要屏幕录制，连 entitlements 都不声明 | ChainYourMac（零 entitlements） | 权限／隐私（跨全局） | 我们要屏幕录制（实时预览）＋若干 entitlement | 列一份权限申请清单，对外可直接对照 |
| **闭源竞品与 MIT 开源同源**：ChainYourMac 的 bundle id 是 `com.ahmedgagan.paneru` | ChainYourMac 2.2.5 二进制 | 许可干净（全项目原则） | [niri.md](niri.md):18 把 Paneru 与 ChainYourMac 当作不同性质的两家 | 要借它的做法前，先分清哪一层来自 MIT 的 Paneru、哪一层是他自己的 |
| 事件处理**两种形态同存**：全域 tap 与**按单一程序** tap（`CGEventTapCreateForPid`），默认走全域 | WindowMizer 6.2.8 二进制 ＋ 它 6.2.5 的更新日誌 | 收起本体（92）／键盘（90） | 我们只有全域（Carbon 热键）＋合成事件，**没有按程序的事件通道** | 给 App 专用怪癖（Premiere 那类）一条独立通道，且默认不用它 |
| **跟着背景亮度走**的对比描边（保证轮廓在任何壁纸上可辨） | Alcove `NotchContrastOutline*`／`NotchLumaView` | 刘海（88） | 未记载 | 换任何壁纸（纯白/纯黑/花），刘海轮廓都看得清 |
| **渐进**模糊，不是均匀模糊 | Alcove `NotchProgressiveBlurView` | 刘海（88） | 未记载 | 边缘模糊有梯度，不是一刀切 |
| **私有 API 隔离进 XPC helper**，主 App 不直接调 | Alcove：主 App 0 个 `MR*` 符号，helper 18 个 | 稳定性／架构 | 我们不用私有；缺的是「万一要用怎么用得不脏」 | 要用私有 API 时，关进 helper，主进程与它解耦 |
| 波形来自**抓音频**（aggregate device ＋ HAL），不是读播放器 metadata | Alcove `AudioFrequencyBand` 等 ＋ 它的权限说明 | 刘海（88）／波形 | [scorecard](scorecard.md):29 说「有意不抄私有绘制」，但**输入从哪来没定** | 有声音就动、不依赖具体播放器；公开 API 实现 |

把上面每一条对回**我们自己的代码**，大半已经在做——而且走的是**公开**路线：

| 竞品怎么做的 | 我们已经在做的 | 依据 |
| --- | --- | --- |
| Wins 用私有 `_CGSHWCaptureWindowList` 抓窗口画面 | **公开 ScreenCaptureKit**（37 个文件用到；我们二进制里有 9 个 `SCS*` 符号） | `prototype/` 搜索 ＋ 我们自己的符号表 |
| Wins 用私有 `CoreDock` 锁 Dock 屏 | **Dock 锁定已经做了** | [competitors.md](competitors.md):34「有（Dock 锁定）」＋ `Preferences.swift`／`WindowShade.swift` |
| Alcove 用私有 `DisplayServices` 调亮度 | **同样用 DisplayServices** | [scorecard](scorecard.md):30 我们自己写的「亮度 DisplayServices」 |
| Alcove 用公开 Core Audio 调音量 | 同样 Core Audio | scorecard.md:30 |
| Alcove 有蓝牙／AirPods 电量 | **已经有**：`AirPodsBatterySource.swift`、`BluetoothBatteryParse.swift`、`WS2BluetoothPresenceSource.swift` | [device-battery.md](device-battery.md) ＋ 仓库内 |
| Wins 读系统符号快捷键表（`_CopySymbolicHotKeys`） | **我们已经在读**，还处理了「这个键被关掉」的情况 | `LaunchpadController.swift:331`（`com.apple.symbolichotkeys` → `AppleSymbolicHotKeys`）、`ElsewhereWindows.swift:188`（79／81：关掉返回 nil、没改过用系统默认 ⌃←／⌃→） |
| 两家都用私有 `_CGS*` 跨 Space 搬窗口 | 我们**一个 `_CGS*` 符号都没有**也做到了跨桌面 | 我们自己的符号表；[scorecard](scorecard.md):42 跨桌面 92 |
| 两家都用 AX 做窗口动作 | 同样 AX | 同上 |

**故意不做的**（已定案，不是欠账）：替换 ⌘Tab、冻结系统 HUD 进程、读通知中心私有库、假刘海——[design-grammar.md](design-grammar.md):91；不抄 Alcove 的私有绘制——[scorecard](scorecard.md):29。

**所以这一轮的增量很薄。** 二进制分析基本在**印证我们已有的架构**（同一件事，他们走私有、我们走公开），没有推翻任何既有判断。真正新的只有四条，且都在开源码与一枚行为细节里：Atoll 的下载完成判定（我们原本的笔记是错的）、Atoll 用 allocated size 而非 logical size、Rectangle 的 settling pass、AeroSpace 的角落停靠与「先显后隐」。niri 的手感值（1200 点／屏、150ms、0.997）算第五条，属于可调参数。

**一处自我更正**：上一版把「`_CopySymbolicHotKeys` 判冲突」列成「值得直接借」是**错的**——我们已经在做，见上表。已从对照表移除。

## 三、二进制分析：静态面与函数级对比

### Wins 3.6

从官网更新日志读全了 3.3 → 3.6（[wins.cool/zh/changelog](https://wins.cool/zh/changelog)，读取于 2026-10-14）。以前 [competitive-analysis.md](competitive-analysis.md) 只用 3.4/3.5 的二手转述，这次是逐版原文。**由更新日志推出的 bug 史**，就是我们该有的验收用例：

| 版本 | 日期 | 修过什么（原文摘要） |
| --- | --- | --- |
| 3.6 | 2026-09-15 | 全面支持 macOS 27；修复 Dock 图标快速切换或重新悬停时**窗口预览意外消失**；修复 Cmd-Tab Plus 首次触发**花屏**；减少空闲后台活动；**加强防破解与防篡改**（禁区）；修复激活失败缺少提示 |
| 3.5.1 | 2026-08-29 | 修复**拖动窗口调整大小时误触发悬浮分屏岛和边缘吸附**；优化 macOS 27 下拖动性能，**减少拖动期间重复的窗口状态读取与后台刷新**；调度中心 Pro 跨 Space 窗口匹配不准；App Exposé 关窗后状态衔接；Intel Mac 上打不开系统设置面板 |
| 3.5 | 2026-08-09 | 新增「Dock 锁定屏幕」；**悬浮分屏岛与边缘吸附自动忽略无法调整大小的窗口**；重构 Mission Control Pro；修复 Flick Dock 偶发误触发 |
| 3.4 | 2026-06-29 | **悬浮分屏岛**与刘海融合；Cmd-Tab Plus 数字角标 1/2/3、支持 >5 窗口；「最小化全部窗口」二次触发召回并**恢复层级**；修复 Dock 预览睡眠唤醒后**显示红绿灯按钮** |
| 3.3 | 2026-04-21 | 悬浮分屏岛支持**外置竖屏**；调整 Dock 预览显示区域 |

观察。两条直接可用：3.5 那条「忽略无法调整大小的窗口」正是 R46 的同一条原则（文档里已经引了，这次拿到版本号）；3.5.1 那条「减少拖动期间重复的窗口状态读取」是我们的落点小岛大概率也会踩的坑。

#### Wins 3.5.1：二进制静态面（Aaron 供件，2026-10-14）

来源：`Wins-latest-3.5.1.dmg`，59,927,876 字节，sha256 `e37c126c7e8a0604dcc3fac2154f6d4f49bcdf32b4c0e3d1a87de652aa37d047`。**只读挂载、未安装、未执行。**

**先回答闸门问题：不需要绕过保护。** 没有 `LC_ENCRYPTION_INFO` segment——二进制**未加密**，是一般的 fat Mach-O（x86_64 + arm64），符号 1690 个、未完全剥离。3.6 才自述加的防破解防篡改不在这份里。**要记下来给律师看的一点：这里刻意挑了 3.5.1 来避开 3.6 的保护层**——不是绕过，但这是一个有意的版本选择。授权层用的是内嵌 **`Paddle.framework`**；**那是禁区，本轮只记录它存在，没有碰它的逻辑。**

**provenance（签名有效，确认是官方构建）**：`Identifier=cools.wins.main`、`TeamIdentifier=NR9F93G9FY`、`Authority=Developer ID Application: Chengjun Yuan (NR9F93G9FY)`、`Timestamp=2026-08-29`、`flags=0x10000(runtime)`（有 hardened runtime）。

| 项 | 值 |
| --- | --- |
| bundle id / 版本 | `cools.wins.main`，3.5.1（build 53），`LSMinimumSystemVersion 12.0` |
| `LSUIElement` | **1** —— 印证你们文件写的「没有菜单栏图标，也不占 Dock」 |
| app / 二进制 | 75 MB / 6,241,888 字节 |
| 内嵌框架 | `Paddle.framework`（授权）、`Sparkle.framework`（更新） |
| LoginItems | `WinsHelper.app`（`cool.wins.WinsHelper`，同一 Team） |
| entitlements | 非沙盒；`automation.apple-events: true`；**`temporary-exception.apple-events: ["com.apple.systempreferences"]`**——这解释了它「把设置面板装进系统设置」是怎么做到的 |

**它在用什么系统设施**（直接读自链接符号）：

- **私有 CoreGraphics／窗口服务器（`SkyLight`，直接链接）**：`_CGSAddWindowsToSpaces`、`_CGSRemoveWindowsFromSpaces`、`_CGSCopyManagedDisplaySpaces`、`_CGSManagedDisplayGetCurrentSpace`、`_CGSCopySpacesForWindows`、`_CGSCopyWindowsWithOptionsAndTags`、`_CGSCopyWindowProperty`、`_CGSGetWindowBounds/Level/Owner`、**`_CGSHWCaptureWindowList`**。这一排解释了三件事：怎么按 Space 枚举窗口、**怎么把窗口搬进／搬出某个 Space**、以及怎么拿窗口画面。
- **私有 `CoreDock`**：`_CoreDockSetOrientationAndPinning`、`_CoreDockSetAutoHideEnabled` 等——这就是 3.5 那个「Dock 锁定屏幕」的实现方式。
- **全局热键走 Carbon Event Manager**（`_AddEventTypesToHandler`、`_GetEventDispatcherTarget`、`_GetEventKind/Parameter`），并用 **`_CopySymbolicHotKeys` 读系统的符号快捷键表**。
- IOKit（`_IORegistryEntryCreateCFProperty`、`_IOServiceGetMatchingService`）与 `_GetProcessForPID`／`_GetProcessInformation`。

**对我们意味着什么（推论，标清楚）**：Wins 把关键能力建在**私有 API** 上——跨 Space 搬窗口、Dock 定位、窗口抓图。我们这边（见第五节）**一个 `_CGS*` 符号都没有**，走的是 AX ＋ 公开 API。[design-grammar.md](design-grammar.md):91 对别家已经定过调子（"冻结系统 HUD 进程、假刘海、读通知中心私有库、替换 ⌘Tab"列为不取），这次是同一类判断，对象换成 Wins。**这一片里唯一我觉得值得直接跟的是 `_CopySymbolicHotKeys`**（公开 Carbon API），已进第二节对照表。

### Swish

[highlyopinionated.co/swish](https://highlyopinionated.co/swish/)，读取于 2026-10-14。**注意：当前是 Black Friday 促销页，价格有时效。** 页面自述：★4.9/5、Ready for macOS 27、30 个手势、标题栏滑动吸附、2×2／3×2／3×3 网格、←↑↓→ 与 WASD、捏合关窗、下滑最小化、张开放全屏、按物理位置把窗口移到另一块屏、支持 Spaces、Magic Trackpad ＋ Magic Mouse ＋ 快捷键、可拖分隔条一次改多窗。价格：标签 $16，促销 $8 或 €5（Space/Time Bundle）。

观察。与 [competitors.md](competitors.md) 的 Swish 一节一致，新增两点：**当前促销价**、**已声明 ready for macOS 27**。标题栏双指滑的冲突（我们与它抢同一块地方）这轮没有新信息。

### Alcove

**逐版说明取不到。** [competitors.md](competitors.md):98 引的 `github.com/henrikruscon/alcove-releases` 本轮回 404；`henrikruscon` 名下的仓库列表里也没有它（只有几个无关的 theme／plugin），所以那个发版仓库已经不存在了。

**但它的官网把版本数据放在前端 bundle 里**（[tryalcove.com](https://tryalcove.com) 的 `/assets/index-*.js`，读取于 2026-10-14）。观察到的原文数据：

- `1.7.7`，build `199`，发布 `2026-06-26`，`minimum_system_version: 15`；资产 `Alcove.zip` 15,072,588 字节、`Alcove.dmg` 15,882,232 字节。
- 同处还带 `1.7.9`，build `203`，发布 `2026-06-30`。
- 试用与正式走同一个资产，用 `channel=trial` 区分（`Dl(e){return e.includes('channel=trial')}`）。

**下载端点静态取不到。** 站是 SPA（任意路径都回同一份壳 HTML）；`Assets/…/Alcove.dmg` 这类直链一律 404，`cdn.tryalcove.com` 与 `api.tryalcove.com` 的常见路径也全 404。也就是说 DMG 的地址是在**点击时**由前端（可能带签名或走 API）解析出来的，命令行拿不到。

**试用条款（FAQ，第一方，读取于 2026-10-14）**：72 小时试用；一份授权最多 3 台同时使用；一次买断、含未来更新；无折扣；14 天内可全额退款。

沿用 [competitors.md](competitors.md) 与 [notch.md](notch.md) 已有的一手记录（$14.99、依赖私有 API）。

#### Alcove 1.7.7：二进制静态面（Aaron 供件，2026-10-14）

来源：`Alcove.dmg`，15,882,232 字节，sha256 `17c481ffa9af91fc76e2ba9995f96750538bf171e5eb2be602c07255f4d944e5`。**只读挂载、未安装、未执行。**

**三处交叉验证都对上**，所以这份的来源是确定的：DMG 字节数 15,882,232 = 官网 JS 里 `Alcove.dmg` 的 `size_bytes`；plist 的 `1.7.7`／build `199`／`LSMinimumSystemVersion 15.0` = JS 里 `minimum_system_version: 15`；签名时间戳 `Jun 26, 2026` = JS 里 1.7.7 的 `published_at 2026-06-26`。签名 `com.henrikruscon.Alcove`、Team `287NUTSP69`、Developer ID `Henrik Ruscon`、`flags=0x10000(runtime)`。

**闸门：不需要绕过保护。** 0 个 `LC_ENCRYPTION_INFO`，fat（x86_64 + arm64），13,627,728 字节。

| 项 | 值 |
| --- | --- |
| 版本 | 1.7.7（build 199），最低 macOS 15.0 |
| `LSUIElement` | 1 → 菜单栏 App，无 Dock 图标 |
| app | 23 MB |
| XPC 服务 | `AlcoveHelper.xpc`，标识 **`com.apple.controlcenter.AlcoveHelper`** |
| 内嵌框架 | 无 Frameworks 目录；**没有** Sparkle／Paddle |
| 包内库 | `Defaults_Defaults.bundle`（sindresorhus 的 Defaults，和 Atoll 同一个）、`Vortex_Vortex.bundle` |
| provisionprofile | 有（WeatherKit 需要） |

**核对 [competitors.md](competitors.md):101 那条「依赖私有 API」——证实了，而且能点名：**

- **私有 `DisplayServices`**（直接链接）：`_DisplayServicesGetBrightness`、`_SetBrightness`、**`_DisplayServicesSetBrightnessSmooth`**、`_RegisterForBrightnessChangeNotifications`、`_CanChangeBrightness`、`_GetBrightnessIncrement`。亮度是这么做的。（对照：你们自己 [设计系统](design-grammar.md) 里也写了「亮度 DisplayServices」，但**我们那份 9/22 构建的未定义符号里没有它**——可能晚于 9/22，也可能走 `dlsym` 动态取；这条我没核实，标出来。）
- **私有 `MediaRemote`**（直接链接）＋ `NSAppleEventsUsageDescription`（原话 "control and display your playing music"）＋ 对 `com.spotify.client`／`com.apple.Music`／`com.apple.Safari`／`com.google.Chrome`／`company.thebrowser.dia` 的 **Apple Events 特例授权**。→ 正在播放是**两条并用**：MediaRemote 拿信息，Apple Events 控制具体那几个播放器。你们设计稿里考虑过 `mediaremote-adapter`（BSD-3），这家是「私有框架 ＋ 公开 Apple Events」混用。
- **私有窗口服务器 `_CGS*`**：`_CGSAddWindowsToSpaces`／`_CGSRemoveWindowsFromSpaces`（跨 Space 搬窗口）、`_CGSGetActiveSpace`、`_CGSCopyManagedDisplaySpaces`、**`_CGSSpaceCreate`／`_CGSSpaceDestroy`／`_CGSSpaceGetType`／`_CGSSpaceSetAbsoluteLevel`／`_CGSHideSpaces`／`_CGSShowSpaces`**（自建／隐藏 Space）、**`_CGShieldingWindowLevel`**（盖住菜单栏那一层的高度——刘海 App 要在那上面画东西靠它）。
- **CoreAudio**（`_AudioObjectAddPropertyListener`、`_AudioHardwareCreateAggregateDevice`）→ 音量走**公开**的 Core Audio，和你们一样。
- **CoreBluetooth／IOBluetooth** → 蓝牙设备（AirPods）。
- **CoreLocation／MapKit／EventKit／WeatherKit** → 位置、日历、天气。

**两条「未核实」现在结案：**

1. `com.apple.security.personal-information.calendars` ＋ EventKit ＋ `_EKEventStoreChangedNotification` → **日历是真的**。（[competitors.md](competitors.md):109 写「日历、锁屏小组件、模拟刘海只见二手页，标未核实」——日历这条可以结案；锁屏小组件与假刘海仍未核实。）
2. `com.apple.developer.weatherkit` ＋ CoreLocation ＋ MapKit → **天气是真的**（WeatherKit 需要 provisionprofile，也解释了包里为什么带那个文件）。

**Resources 里有一条值得直接看：** 33 个资源里有一整套 **AirPods 影片**——`airpods-max-{blue,green,midnight,orange,purple,red,silver,sky-blue,space-gray,starlight}.mp4`、`airpods-pro.mp4`、`airpods-pro-2.mp4`、`airpods-pro-3.mp4`、`airpods-3.mp4`、`airpods-4.mp4`，另有 `alt-jingle.m4a`。推论：**「AirPods 连上时刘海里的那个动画」是每个型号／配色一份预渲染影片**，不是程序画的。这条和你们的 [device-battery.md](device-battery.md)／AirPods 电池那条线直接相关，已进第二节对照表。

**禁区**：没有第三方授权框架（无 Sparkle／Paddle），授权逻辑疑似自己实现（CryptoKit／Network／OpenDirectory 都在符号表里）——**这一块我没有碰**，只记录它存在。它那个 XPC 标识 `com.apple.controlcenter.AlcoveHelper` 借的是 Apple 自己的命名空间，这里只记事实，不推测用途。

#### 函数级对比：我们 vs Wins 3.5.1 vs Alcove 1.7.7（2026-10-14）

**方法**：Hopper 的脚本能力走 Apple Events，需要一次 TCC 授权，不绕（也不该绕）。改用它之外的东西——**Apple 自带 `llvm-objdump`**（Xcode 里就有，不需要下载也不需要授权），做**呼叫轮廓**：把整个二进制的 `bl … ; symbol stub for: _X` 抽出来，按类别计数，并记下每个被调符号由哪些函数发起。

```
xcrun llvm-objdump -d --macho --no-show-raw-insn <binary> \
 | (统计: 函数标签 ^_name: → 呼叫点 bl … symbol stub for: _SYM)
```

**限制先说清**：这是**静态呼叫点**，不是运行期次数；Wins 与 Alcove 的发行构建**符号被剥离**（具名函数取不到，只有 1 个），所以它们那一侧只有类别计数、没有「哪个函数在叫」——对比因此是不对称的，能答的是「用什么设施、用了多少」，答不了「在哪一秒热的」。

| 类别（呼叫点数） | 我们 | Wins 3.5.1 | Alcove 1.7.7 |
| --- | --- | --- | --- |
| AX（辅助功能） | **508** | 301 | 13 |
| CGWindowServer 私有（`_CGS*`） | **1**（`CGSessionCopyCurrentDictionary`，无害） | 20 | 33 |
| `CoreDock` 私有 | **0** | 11 | 0 |
| `DisplayServices` 私有 | **0** | 0 | 24 |
| 观察者（AXObserver 等） | **20** | 10 | 0 |
| 定时器／轮询 | 4 | 8 | 2 |
| 事件（CGEvent…） | 118 | 72（其中 `CGEventTapEnable` ×15） | 11 |
| 具名函数 / 呼叫总数 | 6266 / 46433 | （剥离）/ 51012 | （剥离）/ 87545 |

**四条能站住的结论：**

1. **没有一家在轮询，我们和 Wins 都是观察者驱动。** 我们 20 个观察者呼叫点（`AXObserverCreate` ×3、`AddNotification` ×7、`GetRunLoopSource` ×8），Wins 10（`AXObserverCreate` ×3、`AddNotification` ×3）。Alcove 是 0（它本来就不驱动窗口）。
2. **我们基本不用私有窗口服务器，两家竞品都用。** 我们只有一个无害的 `CGSessionCopyCurrentDictionary`；Wins 20 个（按 Space 枚举窗口）、Alcove 33 个（含 `CGShieldingWindowLevel`、`CGSSpaceGetType`）。**这条把第二节「同一件事，他们走私有、我们走公开」从推断升级成证据。**
3. **事件监听面的差别**：Wins 有 `CGEventTapEnable` ×15——它大量依赖事件监听；我们是 0，我们多做的是**合成**事件（`CGEventPost` ×38）。这条和 Wins 自己更新日志里「macOS 27 拖动卡顿、减少拖动期间重复的窗口状态读取」是同一条热路径上的东西。
4. **`AXIsProcessTrusted` 我们用了 49 处——查过呼叫者，不是问题。** 发起的是 `AppDelegate.toggle`／`focusCurrentWindow`／`rebuildMenu`／`WindowBrowserController.openKeyboardPanel` 这些**动作级**路径，外加一批 `DockHover*Probe`（探针）。没有一处在逐帧路径上。**先怀疑、再查、然后收回**，这条记下来是为了下次别再当作味道。

**一处对不上的地方（需要当前构建才能下定论）**：[scorecard](scorecard.md):30 写「音量 Core Audio，**亮度 DisplayServices**」，但这台机器上 9/22 那份构建里 **`DisplayServices` 呼叫点是 0，也没有任何 `IODisplay*`**，只有 `CGDisplayBounds`／`CGDisplayIsBuiltin` 这类**公开**显示信息。所以那份构建里没有亮度控制这条实现——可能是 9/22 之后才落的，**要用当前签名构建重核**，现在标未核实。

**我们的实时预览路径（读自符号表）**：`SCDisplay` ＋ `SCStreamFrameInfoDisplayTime` ＋ `AVSampleBufferDisplayLayer` = **公开 ScreenCaptureKit → AVSampleBufferDisplayLayer**，对应 Wins 那边的私有 `_CGSHWCaptureWindowList`。

**所以「我们是不是更好」这个问题，在这几条轴上有答案**：观察者驱动（同 Wins，优于轮询）、公开 API 路线（优于两家的私有）、事件监听面更克制（Wins 的事件监听多 15 处）。要挑毛病的话，这一轮没挑到——`AXIsProcessTrusted` 那条查完就撤了。

#### 那私有 API 是不是更快？（2026-10-14，实测）

上面说的是**架构卫生**，不是**性能**——两回事，得分开问。分成三件事来看，私有只在其中一件上可能真的赢。

**实测（这台机器，128 个窗口）**

| 公开路径 | 每次耗时 |
| --- | --- |
| `CGWindowListCopyWindowInfo(optionAll)` | **2.156 ms** |
| `SCShareableContent`（ScreenCaptureKit 的枚举） | **32.1 ms** |

（截图路径**没有实测**：那要把当前屏幕内容收进来，不取。）

**推论，逐件说**

1. **枚举窗口：私有没有明显优势，而且我们已经在快路上。** 我们的枚举走 `CGWindowListCopyWindowInfo`——它本身就是一次视窗伺服器查询，和私有的 `CGSCopyWindowsWithOptionsAndTags` 是同一类调用，**2.2 ms**。顺带一条不用碰私有 API 就能拿的收益：**谁要是拿 `SCShareableContent` 做枚举，光换回 `CGWindowListCopyWindowInfo` 就是 15 倍**（32.1 → 2.2 ms）。
2. **一次性截图：这里私有大概率真的更快——但标推论。** `CGSHWCaptureWindowList` 是一次调用直接返回 IOSurface；公开的 `SCScreenshotManager` 得先过采集服务那一跳，而**光是那一跳（`SCShareableContent`）就 32 ms**。我没写链接私有框架的代码去实测，所以这条是推论。它的收益落在你们的「看一眼」上——那一步是「先截一张图，再上实时流接替」，悬停时就是这一下。
3. **连续预览：私有在这件事上没有好的对等物。** 私有窗口抓取是**拉取式**的，要连续就得轮询——60 Hz 轮询 `CGSHWCaptureWindowList` 会比一路 `SCStream` 更差。所以实时这一段，公开不只是「干净」，是**对的工具**。
4. **竞品用 CGS 的真正原因是「能力」，不是「速度」**：窗口属于哪个 Space、跨 Space 搬窗、Dock 钉屏、shielding 层高——这些没有公开对等物。Wins 那 20 个呼叫点几乎都在这一类上。

**代价**：私有未文档化，系统更新会静默失效（我们这个项目对这类已经定过调子，见 [design-grammar.md](design-grammar.md):91）。

**所以对你那个问题的答案**：**列举上是「不」，截图上是「很可能」，连续预览上是「用不上」**。真要吃这条收益，最划算的一步不是去碰私有 CGS，而是先把枚举从 SCK 换到 `CGWindowListCopyWindowInfo`（如果哪里还在用 SCK 做枚举）——那是纯公开 API，15 倍。

#### 其余六家的二进制静态面（2026-10-14，Aaron 供件，一次跑完）

方法同前四步。**六份都不需要绕过保护**（`LC_ENCRYPTION_INFO` 段数全为 0），签名与公证全部有效。

| 应用 | 版本 | 公证主体 | 二进制／包 | entitlements 要点 | 私有/关键面 |
| --- | --- | --- | --- | --- | --- |
| Swish | 1.13.3 | Christian Renninger | 3.2 MB / 11 MB | apple-events；**disable-library-validation** | **`CGEventTapCreate`／`CGEventTapEnable`** ＋ 大量 AX |
| ChainYourMac | 2.2.5 | Shabana Gagan | 5.1 MB / 18 MB | **一个都没有** | 无私有符号 |
| LaunchOS | 2.4.0 | Remix Design Studio | 8.8 MB / 16 MB | apple-events | **`CGSHWCaptureWindowList`、`CGSSetMenuBarInsetAndAlpha`、`CGSCopyManagedDisplaySpaces`、`CoreDockGetAutoHideEnabled`** ＋ `CGEventTap` ＋ AX |
| Notchy | 1.0.208 | Vishva Variya | **227 MB / 354 MB** | **camera、bluetooth、addressbook、calendars、location、reminders**、application-groups、apple-events | AX（重） |
| Droppy | 16.0.1 | Jordy Spruit | 51.6 MB / 90 MB | **sandbox=true**；camera、audio-input、addressbook、calendars、reminders、network、downloads；**disable-library-validation** | AX |
| DockMate | 0.8.7（2021-03） | wolfgang baird | 2.3 MB / 13 MB | **sandbox=true**；calendars；apple-events | AX |

**五条值得记的：**

1. **ChainYourMac 的 bundle identifier 是 `com.ahmedgagan.paneru`** ——它建在／衍生自 **Paneru**，也就是我们 [niri.md](niri.md):18 当作 **MIT 开源**的那一个。所以「ChainYourMac＝闭源竞品」与「Paneru＝开源可读」其实是**同一条血脉**：[niri.md](niri.md) 的分法要修正，这对我们「许可干净」那套（MIT 署名义务）有直接影响。另外它的 entitlements **一个都没有**——辅助功能靠用户在系统设置里授，不需要 entitlement 声明。
2. **私有窗口服务器面不是普遍现象**：六家里只有 **LaunchOS** 用（`_CGSHWCaptureWindowList` 抓窗口给它的「窗口浏览」、`_CGSSetMenuBarInsetAndAlpha` 控制菜单栏、`CoreDock*` 读 Dock 状态）。Swish／ChainYourMac／Notchy／Droppy／DockMate 都是 AX 为主。**加上前面的 Wins 与 Alcove，用私有的其实是少数派，且集中在「预览／截图」和「刘海／菜单栏覆盖」两件事上。**
3. **Swish 的手势机制确认**：`CGEventTapCreate` ＋ `CGEventTapEnable` ＋ 大量 AX——标题栏滑动是**从事件拦截层拿的**，不是靠 AX 观察。这解释了它和我们抢同一块手势区时为什么能先手。
4. **两个刘海应用索取了大量个人信息**：Notchy 要 camera／bluetooth／addressbook／calendars／location／reminders，Droppy 要 camera／audio／addressbook／calendars／reminders。我们在这方面是**优势项**（[隐私登记](computer-use-qa.md) 那套），对外说的时候可以直接对照。
5. 顺带：**Notchy 的包 354 MB**（二进制 227 MB）对一个刘海工具来说异常大。

#### 两份被退回／卡住的

- **MediaMate `[MacSKY].dmg`：盗版件，退回。** `Authority=TEAM EDiSO`（破解组织签名）、`TeamIdentifier=not set`、CodeDirectory 20400、**Gatekeeper `rejected`**；对照正版件是 `accepted / source=Notarized Developer ID`。它是被第三方**重新签名过的改动件**，分析它得到的是「破解版长什么样」而不是 MediaMate；而且它不在我们的目标清单里。要做就从官方站取正版／试用，并说明它对应哪个 scorecard 格子。
- **WindowMizer 6.2.8：被它自己的 EULA 挡住。** 挂载时弹出授权条款，明文写「you will not rent, lease, sublicense, **or attempt to reverse engineer this product**」，`hdiutil` 因此 canceled。**我不代 Aaron 按 Agree**——接受条款是被授权人的法律行为。要分析就在 Finder 里挂起来，我再跑同一套四步。

#### WindowMizer 6.2.8：二进制静态面（Aaron 挂载后分析，2026-10-14）

**先记一条程序上的事**：这个 DMG 挂载时弹 EULA，明文写「you will not rent, lease, sublicense, **or attempt to reverse engineer this product**」，`hdiutil` 因此拒绝挂载。**由 Aaron 自己在 Finder 里点 Agree 挂起**，分析在挂好的副本上做——接受条款是被授权人的行为，不由执行模型代按。

| 项 | 值 |
| --- | --- |
| id / 版本 | `com.windowmizer.WindowMizer` / 6.2.8（与官网 6.2.8、2026-09-15 对上） |
| 公证 | `Developer ID Application: RGB World, Inc. (783W9MA932)`，**accepted / Notarized** |
| 闸门 | **0 个 `LC_ENCRYPTION_INFO`** → 不需要绕过保护 |
| 二进制／包 | 10.3 MB / 21 MB，fat（x86_64 + arm64） |
| entitlements | **一个都没有** |
| `LSUIElement` | **0**（有 Dock 图标——这批里少见） |
| 内嵌 | `Sparkle.framework`（更新） |
| 最小系统 | macOS 15.0 |

**一手材料与二进制互相印证的一条**：它 6.2.5 的更新日誌写「Remove Event Handler as a default setting. The default is now always **Global Event Monitor**」——二进位上正好两种都在：**`CGEventTapCreate`（全域）与 `CGEventTapCreateForPid`（按单一程序）**，而且事件类呼叫里 `CGEventTapIsEnabled` 出现 **26 次**（就是在两种形态之间切换状态）。它那一长串 Adobe Premiere／QuarkXPress 专用修复，靠的就是「按程序的 tap」这条独立通道。

**模型对比**（「收起本体」这一格）：WindowMizer 是 **AX ＋ 事件 tap（全域＋按程序）＋ AX 观察者**；我们是 **AX（508 处）＋ 观察者（20 处）＋ 合成事件（`CGEventPost` 38 处）**。它是「拦别人的输入」，我们是「发自己的输入」。

呼叫轮廓：**112,124 次 `bl`**（这批里最密；对照：我们 46,433、Wins 51,012、Alcove 87,545、Swish 18,926、LaunchOS 64,864），具名函数 57（发行构建已剥离）。

#### Alcove 1.7.7：重点深挖（同一份件，2026-10-14 二手更细一遍）

**一、它自己的权限说明反过来解释了机制**（`Info.plist`，一手）：

| 权限 | 它写给自己用户看的用途 | 由此推出的机制 |
| --- | --- | --- |
| `NSAppleEvents` | control and display your playing music | 用 Apple Events 控播放器 |
| **`NSAudioCapture`** | **display the live waveform** | **波形是抓音频画出来的**，不是读播放器 metadata |
| `NSBluetoothAlways` | visualize your connected audio devices | AirPods 视觉 |
| `NSCalendarsFullAccess` | show your upcoming events | 日历 |
| **`NSLocalNetwork`** | **validate your license** | **授权校验走本地网络**（禁区，只记录） |
| `NSLocation` | determine your location | 天气 |

**二、架构：私有面被关在一个 XPC helper 里。** 主 App **链接**了私有的 `MediaRemote.framework`，但**一个 `MRMediaRemote*` 符号都没有（0 个）**；那些调用全在 `Contents/XPCServices/AlcoveHelper.xpc` 里（18 个 `MRMediaRemote*`：`GetNowPlayingInfo`、`SendCommand`、`SetElapsedTime`、`SetShuffleMode`、`RegisterForNowPlayingNotifications`…），helper 自己把自己命名为 `MediaRemoteHelper` / `PrivateMediaRemote`。分层是：**主 App 走公开 API ＋ Apple Events，私有 MediaRemote 关在 helper 里**。

→ 这是一个**可以直接学的模式**：私有 API 隔离进 XPC，主进程不受它的崩溃/阻塞牵连。我们目前为止是「完全不用私有」，这条给的是「万一要用，怎么用得不脏」。

**三、波形到底怎么来的。** 主 App 有 `AudioManager`／`AudioFrequencyBand`／`AudioStream`／`AudioDevice`／`AudioObjectPool`／`AudioPermissionStatus`／`audioRenderingModeKey`／`audioTierKey`，并链接 **`AudioHardwareCreateAggregateDevice`** ＋ HAL 属性监听；注意**没有** `AudioHardwareCreateProcessTap`（macOS 14.2+ 的正规 tap 通道）。推论（**未实测运行**）：它建 aggregate device、靠 HAL 轮询抓输出音频，再自己算频段画波形。这正好补上 [scorecard](scorecard.md):29 那条「Alcove 级媒体波形——有意不抄私有绘制」的**机制空白**：画法不该抄，但**输入从哪来**是工程问题，它的答案不是私有绘制，是抓音频。

**四、刘海那一格的型别名（这批里最有参考价值）**：

- `NotchController`／`NotchCoordinator`／`NotchPanel`／`NotchView`／`NotchExpandedView`／`NotchShape`／`NotchBackdropPanel`
- **`NotchContrastOutlineShape`／`NotchContrastOutlineView`／`NotchContrastOutlineLuminanceState`** ＋ **`NotchLumaView`**：一条**跟着背景亮度走**的对比描边——为保证轮廓在任何壁纸上都看得见
- **`NotchProgressiveBlurView`**：**渐进**模糊（不是均匀模糊）
- **`NotchQuickPeekView`**：快速瞥一眼
- **`NotchSwipeDirection`／`NotchSwipeMonitor`／`NotchSwipeScrollHandler`／`NotchSwipes`**：刘海自己的滑动子系统
- 另有 `SpaceManager`、`BatteryManager`／`BatteryHelper`／`BatterySettingsView`、`ArtworkCutoutBackdrop`／`ArtworkFlipEffect`／`ArtworkTransition`（封面翻转）、`CachedWeather`、**`DummyNotch`**（无刘海机型用）

**五、两条一手事实**

- **资源盘点：28 个影音档、0 张图片**——视觉素材基本是**预渲染视频**（对应前面「AirPods 每个型号／配色一份 mp4」的发现）。
- **只做 `en` 本地化**——Alcove 是**纯英文**，不覆盖中文市场。

**六、授权子系统**（`License`／`LicenseAPI`／`LicenseClaims`／`LicenseController`／`LicenseManager`／`LicenseStateError`／`LicenseTokenError`／`StoredLicenseState`，且校验走本地网络）——**禁区，只记录存在，不碰。**

### DockDoor（开源，但 release 日志是现成的验收清单）

仓库 [ejbills/DockDoor](https://github.com/ejbills/DockDoor)（默认分支 `main@7be384b46da6`）的 release 记录，读取于 2026-10-14。**这些 bug 场景正是 [competitive-analysis.md](competitive-analysis.md):33 想补进窗口浏览视觉验收的东西**：

| 版本 | 日期 | 修过什么 | 对应的验收场景 |
| --- | --- | --- | --- |
| 1.40.5 | 2026-10-04 | 重启键鼠／Dock 锁定监控后**崩溃** | 开关监控后仍能开预览 |
| 1.40.4 | 2026-10-02 | macOS 临时**阻止它发输入**后，点 Dock 或预览没反应 | 系统拦截输入后能恢复 |
| 1.40.2 | 2026-09-30 | 退出／崩溃的 App 的窗口**残留在切换器里** | 关掉的 App 不留在列表 |
| 1.40.1.0.3 | 2026-09-05 | 切 Space 时缩略图**撕裂** | 切桌面时预览完整 |
| 1.40.1 | 2026-09-03 | macOS 26.3+ 在 dock 窗口内**点击无反应** | 系统大版本下的点击 |
| 1.40.0 | 2026-09-03 | 点 Dock 图标后 Dock **卡在自动隐藏外**；预览**滚动失效** | Dock 自动隐藏状态、滚动 |

观察。另注：该仓库 GitHub 判为 `NOASSERTION`（没有声明标准许可证），所以它**只借思路**，不碰代码，和 Mos／Mac Mouse Fix 同一条规矩。

### 其余闭源竞品：第一方材料（2026-10-14 补）

#### WindowMizer 6 —— 66 个版本的完整更新史，223 条修复/变更

一手：`windowmizer.com/wm-releasenotes`（读取于 2026-10-14）。最新 **6.2.8（2026-09-15）**，要求 macOS 15.3+，$25 新购 / $20、$15 升级（大版本授权）。**它的更新史就是我们「收起本体」那一格的验收用例库**——挑直接相关的：

- 6.2.8　**显示器变化后**重启／关机／退出时崩溃
- 6.2.7　**读不到窗口标题时**更新 Window／Dock 菜单崩溃；无标题窗口时窗口列表排序失败
- 6.2.6　双击 **Finder 文件夹替身**误触发窗口动作；隐藏／显示桌面图标偶发失败
- 6.2.5　**把默认的「Event Handler」换成「Global Event Monitor」**（一次机制决策，和我们选事件监听还是热键是同一类取舍）
- 6.2.4　**一大批 Adobe Premiere 专用修复**：浮动面板收起时闪烁、恢复时放大到全屏、脱离的面板高度跳错、占位条与真窗口的取舍；外加 QuarkXPress 预设
- 6.2.3　**把系统设置收成标题条后关闭它，会让系统设置留在「在跑但没有窗口」的状态**；Premiere 改成「缩的是**真窗口**，不用占位条」

我们收起的是真窗口（[competitors.md](competitors.md):17 记我们这一格领先），但上面的边界——**无标题窗口、App 专用浮动面板、系统设置这类特殊 App、Finder 替身、显示器变化**——每一条都是我们大概率会撞的同一类，各值得一条探针。

#### Swish

更新日誌是 **Notion 页面**（内容由前端拉取），静态抓不到——**取不到**。市场页已记（$16，促销 $8／€5，30 手势，4.9/5，Ready for macOS 27）。

#### DockMate

一手确认：**最新版 0.8.7，2021-03-12**，$14.99 起，免费一周试用，macOS 10.14+。**停工五年多**，不再是对手——[competitors.md](competitors.md):20 的判断得到一手佐证。

#### LaunchOS（启动台这一格的 85）

一手：[launchosapp.com](https://www.launchosapp.com)（读取于 2026-10-14）。**要求 macOS 26+**；免费 Basic 档 ＋ **7 天 Pro 试用**；$11.99 ／ $18.99 ／ $35.99（Paddle 收款）。定位是「把 macOS 26 拿掉的 Launchpad 复原」——**像素级复刻系统旧交互**，不是新交互。

#### ChainYourMac（$19.99 买断，macOS 13+ Apple 芯片）

一手：[chainyourmac.com](https://chainyourmac.com) 与其**自营对比页**（读取于 2026-10-14）。**更正一处**：[niri.md](niri.md):20 记的 `$9.99` 不对，官网现价 **$19.99**（买断、终身授权）。

它的定位一句话就是冲我们来的：**「PaperWM for Mac and niri for macOS, built as a native app」**——直接拿 PaperWM／niri 的受众当目标，卖点是「一样的卷动模型，但用 Mac 的做法：设置窗口而不是配置文件、跟手指的触控板滑动、不改 SIP」。

**与我们直接可对照的几条：**

- **权限面比我们窄**：官网明写「**Only needs the Accessibility permission**」「No account, no telemetry in the app」，公证 ＋ Developer ID。它不抓画面（没有预览），所以不需要屏幕录制；我们是 AX ＋ ScreenCaptureKit。
- **焦点一变就滚，「弹簧动画从按下的那一刻起」**；每个显示器、每个 Space 各有一条自己的 strip，并且能在「Configuration → Displays」**单独关掉某一块屏**（适合演示屏／竖屏）。
- **「No focus stealing」**：后台 App 弹窗不抢焦点、不滚你的 strip。
- **「Mac Setup 会检测 Rectangle／Magnet 这类窗口管理器在跑并警告」**。
- **「Plain ⌥ is left to macOS」**：默认用 ⌃⌥，理由是 ⌥ 归系统用于跳词和打 ç® 这类字符——和我们 quiet-defaults「⌃⌘ 新装不占」是同一种自觉。
- **self-healing engine**：引擎进程挂了会自己拉起，并留一份引擎日志。
- **自动化面**：`chainyourmac://` URL scheme ＋ Raycast script commands ＋ 命令行工具。我们 [niri.md](niri.md):91 把「脚本和 IPC」列为**不追**——但 ChainYourMac 和 OmniWM 都发了这一块。
- 交付节奏（自家 appcast）：**2.2.3／2.2.4／2.2.5 全在 2026-10-12～13 两天内**。

**它自家的竞品地图（一手，但作者自认有倾向——页面自己写了 disclosure）**：那份对比页把同类列成 `ChainYourMac（$19.99）｜OmniWM（macOS 26+，免费开源）｜PaperWM.spoon（Hammerspoon＋Lua）｜**Nehir**（自称 OmniWM 的窄化版，只做卷动）｜**komorebi for Mac**（个人免费）｜**ScrollDesktop.spoon**（实验）`，并按 macOS 版本给结论：**13–15 选它或 PaperWM.spoon；26 Tahoe 选它或 OmniWM**。

→ **`Nehir`／`komorebi for Mac`／`ScrollDesktop.spoon` 这三个名字我们文件里没有**，该补进竞品册；这份地图本身也是「谁把谁当对手」的一手证据。

#### DynamicLake

官网 [dynamiclake.com](https://www.dynamiclake.com) 只拿到片段（一手：用 **FFmpeg（LGPLv3）**做音视频转码）。价格与版本来自二手（~$16.90 买断、v2.0 2026-03、macOS 14+），**标未核实**。

**另记一条安全事实**（对「你取件」那一步直接有意义）：多个来源报 **DynamicLake 这个名字被恶意广告冒用**，假下载页散播窃密程序。只从官方站取件。

#### NotchNook / Droppy / Notchy / MacNotch

NotchNook 官网 `notchnook.app` 回 **402**（付费墙／疑已停摆，与「已从 Setapp 下架、授权服务器离线」的报道一致，**二手，未核实**）。Droppy／Notchy／MacNotch 本轮**没找到可靠的第一方页面**，标未开始。

## 四、开源码：机制层（这一块以前是最薄的）

读的是仓库源码。**GPL 的（Atoll、niri）只取思路、不取代码**；MIT 的（AeroSpace、Paneru）可借代码但要带版权声明。

### Atoll（GPL-3.0）— 下载进度

`dev@fdc1c14471ec`，`DynamicIsland/managers/DownloadManager.swift`（614 行）。这一家我们已经在 [progress-in-notch.md](progress-in-notch.md):128 引过它的思路，但**没读过码**。读完发现三个我们笔记里没有的关键点：

**观察 1：临时档的四种后缀，以及 Safari 是 bundle。**
`PartialDownload.extensions = ["crdownload", "download", "opdownload", "part"]`。Chromium → `.crdownload`，Firefox → `.part`，Opera → `.opdownload`，**Safari 的 `.download` 是 bundle（目录）不是文件**，字节落在子档里，目录项本身不长大——只量顶层会把每个 Safari 下载都报成"永久卡住"。它的解法是递归加总子档（`allocatedBytes`）。我们笔记写的"只文件"漏了 Safari 这一路。

**观察 2：完成判定比我们写的严。** `completed(among:stamps:stampsWhenStarted:)`：
- 完成 = **目标档被写过**，不是"目标档存在"。Firefox 会先把目标档建**空占位**、字节写进旁边的 `.part`，所以"存在"什么也证明不了——**持有数据才是**，只有非空档才记时间戳。
- 覆盖已存在的档时，目标档在第一个字节到达前就有数据——所以时间戳必须**变了**，否则"取消"会被读成"完成"。
- 比较是 `now > before`（**更晚**，不只是"不同"）：比开始时还旧的目标档不是这次写的，是别的东西还原／拷贝过去的。

我们笔记现在的规则是「文件改名成正式名、目标档修改时间变了算完成，没变算取消」——漏了 Firefox 空占位、漏了"更晚 ≠ 不同"、漏了覆盖既有档。

**观察 3：其它两条工程细节。**
- 进度用 **allocated size**（`.fileAllocatedSizeKey`）而不是 logical size：预分配整档的浏览器会从第一刻就报最终大小，logical size 会读成"瞬间完成然后不动"。磁盘块随字节到达而增长。
- 速率计算的坑：一个下载结束会把它的字节从总量里带走，所以「总量下降」不能判定；它测的是**有没有文件离开集合**（`earlier.files.isSubset(of: files)`），因为"一个 2MB 完成 + 另一个涨 5MB"净增 +3MB，会悄悄低估速率。
- 扫描簿记（`vanishedSinceActive`、`ignoredFiles`、`destinationStampsWhenStarted`）与目录 watcher 分开，留了一个 `init(monitoringDisabledForTesting:)` 只给测试用，让扫描可以**直接喂进去**——注释原话是"扫描簿记是最值得测、也最难到达的部分"。这条对我们的探针文化直接可用。
- 并发坑（它踩过）：目录 source 的回调在它自己的队列上，回主 actor 的那一跳如果写成非结构化 `Task`，从那个队列建出来的 Task **从不运行**——列表读了然后被静默丢掉，于是启动后才出现的下载永远不会被发现。

### niri（GPL-3.0）— 卷动平铺与手势

`main@4263c9a17f80`。我们 [niri.md](niri.md) 是从它的文档写的，这次读 `src/layout/scrolling.rs`（5749 行）、`src/input/swipe_tracker.rs`、`src/input/scroll_swipe_gesture.rs`。**只借思路。**

- **手感值**：`VIEW_GESTURE_WORKING_AREA_MOVEMENT = 1200.`——注释写"滚动一整个工作区宽度所需的手指位移"。可作为一个可验收的手感目标值。
- **甩动投影**（`SwipeTracker`）：速度取 **150ms** 历史视窗（`HISTORY_LIMIT`）内的 `总位移 / 总时长`，触控板阻尼 `DECELERATION_TOUCHPAD = 0.997`，并有 `projected_end_pos()`（投影终点）决定吸附到哪一列。我们的「甩一下」这一格是 94 分，但没有记过投影模型——这是可对标的形状。
- **平台限制的绕法**：注释直说 libinput 只给 **3 指及以上**的触控板滑动手势，所以他们**从 scroll delta 反推**方向（`self.vertical = dy != 0.`）。这跟我们是同一类问题——我们这边三指归了系统、改用标题栏两指——但解法不同：他们是把"平台不给手势"降级成"从滚动事件判定方向"。
- **列宽存比例**：`ColumnWidth` 有 proportional 与 fixed 两种，注释解释为什么宽度要存比例：两列各 50% 并排时，换到不同尺寸的输出**要保持并排**；高度则相反，立刻转成固定值。
- **视图偏移的状态模型**：`ViewOffset::Static | Animating | Gesture`——"静止／动画中／正被手势控制"三态，干净。我们的卷轴跟手可以照这个分态。

### AeroSpace（MIT）— 停在屏幕外的窗口

`main@74a1bf17e82d`。我们 [niri.md](niri.md):90 记过"AeroSpace 藏窗口也只停在下面两个角上"，这次读到了**怎么做**（`Sources/AppBundle/tree/MacWindow.swift`）：

- `hideInCorner(_ corner: OptimalHideCorner)`：把窗口放到**可见区的角落**——一个角是 `visibleRect.bottomLeftCorner + onePixelOffset + CGPoint(x: -s.width, y: 0)`（即整扇推到左边外、底对齐），另一个是 `bottomRightCorner - onePixelOffset`；配 `unhideFromCorner()`。
- 它专门留了 `prevUnhiddenEmulationPosition`，注释是"别在连续 `hideInCorner` 时意外覆盖掉上次的真实位置"——**记住原位**，这正是我们"露一条边的列要能还原"需要的东西。
- `Sources/AppBundle/layout/refresh.swift` 注释："为了减少闪烁，先把可见工作区 unhide，再 hide 不可见的"——顺序也是设计的一部分。

推论：这套"推到屏幕角外一像素 + 记住原位 + 先显后隐"可以直接映射到我们的卷轴"停在屏幕外的列"，用来替代我们目前在 [niri.md](niri.md):90 记的那条限制。**但上沿不行**（macOS 不让有标题栏的窗口上沿离开屏幕），这条限制两家都撞过。

### Rectangle — 「最小尺寸」怎么提示

`main@1d46069c27b3`。我们在 [competitive-analysis.md](competitive-analysis.md):29 引了它「App 不肯缩到要的大小时，浮窗说'达到最小尺寸'」——这次读到机制，比一句话细：

- 提示是一个 **popover + 文本字段**（`Rectangle/Popover/MessageView.swift`：`popover.show(relativeTo:of:preferredEdge:)`，`show(message:sender:)`），不是系统通知。
- 关键在**什么时候才敢说**这条提示：源码里有两个注释点——`WindowManager.swift` 的"AX 能施加一个 settling pass 之前没报出来的最小尺寸"，以及 `WindowAnimationPlacement.swift` 的"保持可重试，而不是变成推定出来的最小尺寸"。也就是说，它**先尝试、等一次 settling、确认是 AX 夹住了才提示**，不会因为动画还没落定就误报。

推论：这正是 R46「做不了就说一声，不假装做了」需要的形状——我们现在的记录只写了"浮窗说一句"，没有"settling 之后再判定"这一步。

### Paneru（MIT）— 只读了一半，标部分

`main@8a213313538a`。只读了 `src/platform/display.rs`（133 行，是显示器变化的 `extern "C-unwind"` 回调）。它对我们 [niri.md](niri.md):18 记的那条「要求打开'显示器具有单独空间'」我**这轮没有核实**，标部分完成。

### OmniWM（GPL-2.0）— 更正：它是开源，不是竞品里的闭源那批

[niri.md](niri.md):20 把 OmniWM 列进「macOS 上照 niri 做的几家」时**没标授权**，这一轮一手确认：**`GPL-2.0-only`，free forever，v0.7.6，macOS 26+ ／ Apple Silicon**，官网 [omniwm.app](https://omniwm.app)（读取于 2026-10-14）。所以它按许可证分级属于「只借思路」那一档，不是闭源。

两条对我们有用的，直接读自它自己的页面：

- **「Split around the notch, pixel-perfect — the active workspace always docks on its left」**：分屏时**按刘海精确避开**，而且活动工作区固定停在刘海左侧。这是我在竞品里见过的**唯一**一处把「刘海」和「平铺布局」正面缝合的做法——正好落在我们 88 分那一格上（[scorecard](scorecard.md):29）。已进第二节对照表。
- 它提供 `omniwmctl` 的 **NDJSON over local socket** 脚本接口（`omniwmctl query windows --workspace 1`），可以订阅实时事件——和我们 [niri.md](niri.md):91 列为「不追」的「脚本和 IPC」是同一件事，它做了。

其余（捲动列、每屏工作区条、跨工作区浮动的终端、工作区滑动 opt-in）与 [niri.md](niri.md) 已记的 niri 那套同源，不再重复。

## 五、量自己（C 线）

REA 在这台机器上**还没有真正跑通**，先把能拿到的事实记清楚。

**测量的对象不是当前源码。** 量的是 `prototype/WindowShade.app`，二进制时间戳 **2026-09-22**，早于 1.0.16 那一批工作。所以下面的数字只说明"这个构建长什么样"，**不能当作当前版本的对外数字**（[scorecard](scorecard.md):43 的 R30「必须用当前版本重新测」仍然开着）。

| 项 | 值 |
| --- | --- |
| bundle 大小 | 6.6 MB |
| 二进制 | 3,726,192 字节 |
| 二进制 sha256 | `e2e666cedf9c7164a6beefabb03c4c6ef72897c928b69d0983000bb8a49da6ad` |
| bundle 内容 sha256 | `af990790fb129d2cdbe438f362d5600be276912d2df315d694fe4b1da965dbdc` |
| identifier | `com.windowshade.prototype` |
| TeamIdentifier | `FVGLY6W6S4` |
| 签名 flags | `0x0(none)` —— **没有 hardened runtime** |
| `__TEXT` / `__text` | 2,293,760 / 1,962,000 |
| 链接的框架 | ScreenCaptureKit、VideoToolbox、MetalKit、Metal、IOKit、Carbon、ApplicationServices、ServiceManagement、AVFoundation… |
| 未定义符号里的私有／低层面 | `_AXUIElement*`（10 个）、`_IOHIDDeviceGetReport`、`_IOHIDManager*`（8 个） |

观察。**这是静态测量，不是运行测量**——物理占用、常驻 CPU（R30 要的数）需要启动一次再量，本轮没做。

**REA 的卡点（两条都可修，2026-10-14 复核）**：`rea analyze prototype/WindowShade.app` 两次失败，原因都在 provider，不在策略：

1. 不设环境变量时，REA 找的是 `/Applications/Hopper Disassembler.app/...`，而本机装的是 **`Hopper Disassembler v4.app`**（多一个 ` v4`），于是判 `executable_missing`。设 `HOPPER_LAUNCHER_PATH` 指向正确路径即可越过这一步。
2. 越过之后 Hopper 起来了，但桥接失败，exit code 2：`Cannot launch Hopper! Not authorized to send Apple events to Hopper Disassembler v4.`——**缺 macOS 的自动化／Apple Events 权限**。这条最便宜：在 系统设置 → 隐私与安全性 → 自动化 里，给发起调用的进程勾上对 Hopper 的控制权，一次授权即可，不用装任何东西。
3. Ghidra 这条要多装一层：**本机没有任何 JDK**（`/usr/libexec/java_home` 找不到，brew 里也没有 java），而 Ghidra 需要 JDK 21+。REA 要的是 12.1.x，当前最新是 **12.1.4**（`ghidra_12.1.4_PUBLIC_20260921.zip`，2026-09-21，GitHub `NationalSecurityAgency/ghidra`）。装上 JDK + 解压 Ghidra、设 `GHIDRA_INSTALL_DIR` 即可。这条路不需要 GUI 授权，适合无人值守。
4. IDA 那条需要上游 MCP 注册（`REA_IDA_MCP_CONFIG`），本机没有 IDA。

两条（Hopper 权限、或 JDK+Ghidra，约 1 GB）任一条开通，原生分析就能跑。失败时在 `/tmp` 留的 `rea-*` 临时目录已清掉。

**运行期数字仍未量。** 本机没有在跑 WindowShade；它是窗口管理器，主动启动会动到 Aaron 正在用的桌面（当时还有编译在跑），所以没有擅自启动。物理占用与常驻 CPU 要在机器空闲时量一次（照 [scorecard](scorecard.md) 的「60 秒静置实测」口径）。

## 六、未核实 / 未开始

**未核实（二手或本轮取不到）**

- Alcove 的**逐版更新日志**：`alcove-releases` 仓库 404，**取不到**（但版本数据从官网前端 bundle 拿到了，见第三节）。
- NotchNook 已停摆：官网 402 ＋ 报道，**二手，未核实**。
- **我们自己的「亮度 DisplayServices」**：[scorecard](scorecard.md):30 这么写，但 9/22 那份构建里 `DisplayServices` 呼叫点是 0、也没有 `IODisplay*`。要用**当前签名构建**重核，见第三节末。
- Paneru 要求「显示器具有单独空间」：本轮没核。
- Rectangle 的许可证：本轮没核。
- DockDoor 的许可证：GitHub 判 `NOASSERTION`（未声明标准许可证），因此按"只借思路"处理。
- Swish 的价格：促销页，**有时效**，已记读取日期。
- **WindowMizer／DockMate／ChainYourMac／LaunchOS 已经补上一手**（见第三节）。
- **Swish 的逐版更新日誌**：Notion 页面，静态**取不到**。
- **DynamicLake**：价格与版本只有二手（~$16.90、v2.0 2026-03），**未核实**；官网只拿到片段（用 FFmpeg LGPLv3）。
- **Droppy／Notchy／MacNotch**：没找到可靠第一方页面，**未开始**。

**待取件清单（Aaron 取件，分析在件上做）**

| 优先 | 目标 | 对应格子 | 闭源事实 | 怎么拿 |
| --- | --- | --- | --- | --- |
| P0 | Swish | 标题栏手势（85） | $16（促销 $8／€5），★4.9，30 手势 | 官网 free trial |
| P0 | WindowMizer 6 | 收起本体（我 92／它 75） | $25 新购、$20／$15 升级；macOS 15.3+、Apple 芯片 | 官网 14 天试用 |
| P1 | ChainYourMac | 卷动平铺 | $9.99 | **直链** `chainyourmac.com/downloads/ChainYourMac-2.2.5.dmg` |
| P1 | LaunchOS | 启动台（85） | 免费 Basic ＋ Pro $11.99／$18.99／$35.99（Paddle）；要求 macOS 26+ | 官网 7 天 Pro 试用 |
| P2 | DynamicLake | 刘海 | Pro ~$16.90（二手，未核实）；macOS 14+ | **只从 dynamiclake.com**——该名字曾被恶意广告冒用，假下载页散布窃密程序 |
| P2 | NotchNook | 刘海（旧基准） | 疑停摆 | 官网 402，大概取不到 |
| P2 | Notchy／MacNotch／Droppy | 刘海（拖到刘海贴半屏） | 官方页未找到 | 找到再说 |
| 可省 | DockMate | Dock 预览 | $14.99、一周试用 | 最新版停在 2021-03-12，已非对手 |

开源的**不需要取件**，直接读源码/仓库即可：OmniWM（GPL-2.0）、Atoll（GPL）、niri（GPL）、AeroSpace（MIT）、Paneru（MIT）、Rectangle、DockDoor、Peninsula（GPL）。

**每份一律跑这四步**：验签名（provenance，并与官网版本／大小交叉核对）→ **回答条件 1「需不需要绕过保护」** → 静态面（entitlements／框架／私有符号面／包结构／包内资源）→ **呼叫轮廓**（`llvm-objdump`，与我们的构建同一口径，可直接比较）。函数体内的伪代码仍需 decompiler；呼叫轮廓这一层不需要。

**未开始**

- **竞品逆向分析：Wins 3.5.1 与 Alcove 1.7.7 做完了静态面与呼叫轮廓**（第三节），因为 Aaron 供了件。其余各家的**第一方材料已补**（WindowMizer／DockMate／ChainYourMac／LaunchOS／OmniWM，见第三节），但它们的**二进制分析未开始**：
  1. **App 不在本机**。这一轮试过从命令行取件，结论是**取不到**：这类站的下载地址是前端在点击时解析的（SPA ＋ 可能需要走 API／签名），静态 HTML 和常见路径都拿不到；只有开源的那几家（DockDoor 等）能从 GitHub 取。取件仍是 Aaron 的——而且它本来就是授权行为，见第一节条件 5。
  2. **decompiler provider 没通**（Hopper 差一次自动化授权；Ghidra 差 JDK）。见第五节。**这也是 Wins 只做到「静态面」的原因**：符号、框架、entitlements 这类读得出来，伪代码和函数逻辑要 provider 通了才能做。
- **开始每个目标前都要先回答条件 1「需不需要绕过保护」。** 已经撞到一条现成的：**Wins 3.6 自述加了防破解与防篡改**——那类就是不做，不试探、不绕过；本轮拿 3.5.1 是因为它不含那层保护（这一点已记在第三节，供律师看）。
- **我们自己的运行测量**（物理占用、常驻 CPU）：未做。需要机器空闲时启动一次再量（不想动到正在用的桌面）。
- **两家的函数级只做到「呼叫轮廓」。** 符号、框架、entitlements、包内资源这一层读得出来；**呼叫轮廓**（谁调了什么设施、多少处）已经用 `llvm-objdump` 做完了，见第三节末。还差的只有**伪代码**（函数体内的逻辑），那要一个 decompiler：Hopper 差一次自动化授权（它的脚本能力走 Apple Events，绕不了也不该绕），Ghidra 差 543 MB 下载（本机对外带宽被压到 33–116 KB/s，已在装的 JDK 到位后放弃）。

## 七、参考

一手公开材料（读取于 2026-10-14）

- Wins：[更新日志](https://wins.cool/zh/changelog)
- Swish：[产品页](https://highlyopinionated.co/swish/)（当日为促销页）
- Alcove：[官网](https://tryalcove.com)（更新日志仓库 404）
- DockDoor：[仓库](https://github.com/ejbills/DockDoor)／[releases](https://github.com/ejbills/DockDoor/releases)

开源码（读取于 2026-10-14，分支与 commit 如正文）

- Atoll（GPL-3.0）：[Ebullioscopic/Atoll](https://github.com/Ebullioscopic/Atoll) `dev@fdc1c14471ec`
- niri（GPL-3.0）：[niri-wm/niri](https://github.com/niri-wm/niri) `main@4263c9a17f80`
- AeroSpace（MIT）：[nikitabobko/AeroSpace](https://github.com/nikitabobko/AeroSpace) `main@74a1bf17e82d`
- Rectangle：[rxhanson/Rectangle](https://github.com/rxhanson/Rectangle) `main@1d46069c27b3`
- Paneru（MIT）：[karinushka/paneru](https://github.com/karinushka/paneru) `main@8a213313538a`

本机

- 测量对象：`prototype/WindowShade.app`（二进制 2026-09-22），sha256 见第五节。
