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
3. **许可证分级。** 开源码能不能拿代码，看许可证：MIT 可借代码并带版权声明；GPL／CC BY-NC 只借思路，附来源 repo、分支与 commit。本项目是 MIT，所以 **GPL 那几家（Atoll GPL-3.0、niri GPL-3.0、DockDoor GPL-3.0、OmniWM GPL-2.0、Nehir GPL-2.0）只能用它们的思路，不能拷代码。**
   **许可一律读原文，不采信 GitHub 标签**（本轮 DockDoor 就被误判成 `NOASSERTION`，实际是 GPL-3.0，见第四节）。
   **取用纪律**：从 GPL 源码里拿到的是「机制描述」（它怎么判定、状态机长什么样、边界在哪），落到我们仓库的是**我们自己写的实现**；写我们的代码时**不把那份源码摆在旁边逐行对照**。本文档记录的是机制，不是可粘贴的代码。
4. **全程留证据。** 每个结论带来源与读取日期；开源码带 commit SHA。这一项不是负担，是这个项目本来的规矩（[Computer Use 验收](computer-use-qa.md) 也是这么要求的）。
5. **取得与分工。** 把竞品 App 弄到本机是**授权行为**——安装即接受它的条款，付费版要买（试用的时长／退款条款各家不同，见第三节）。这一步由 Aaron 做，不由执行模型代替：**Aaron 取件，分析在件上做。** 2026-10-14：Aaron 先后供了 Wins 3.5.1 与 Alcove 1.7.7 的 DMG（都未安装），已在两份上做了静态面分析，见第三节；其余各家尚未供件，逆向**未开始**。
   **2026-10-15 例外一条（据实记录）**：WindowMizer 6.2.8 的 DMG 带一张**软件许可协议**（SLA），`hdiutil` **没有任何命令行接受选项**（Apple 刻意要求 GUI 同意），因此一直挂不上。Aaron 当天明确指示「**你替我按同意**」，于是由执行模型经 macOS 的 UI 自动化按下该对话框的 **Agree**（对话框按钮：Agree／Disagree／Save…／Print），随后才挂载与复制。**该协议含一条禁止逆向的条款**（原文：`you will not … attempt to reverse engineer this product`，全文抓取存于 `/tmp/ws-research/legal/windowmizer-EULA.txt`）。**同意这个动作是 Aaron 的决定、责任归 Aaron**；执行模型只做了机械操作，并在本条留痕。**注意这个动作的性质**：它是**给同意**（SLA 要求的是被许可人的允诺），**不是绕过保护措施**——后者（DRM／授权校验／加密载荷）仍一律不做，见第 1 条。

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
| 音频统一走 **`AudioHardwareCreateAggregateDevice`**（**两家独立实现都这么做**：Alcove ＋ MediaMate） | 两份二进制 | 刘海／波形／音量 | 未定 | 同一套输入，覆盖波形与音量胶囊 |
| 亮度：`DisplayServicesSetBrightnessSmooth` ＋ 私有 `CoreBrightness` | MediaMate（9 处 ＋ 链接两个私有框架） | 刘海（88）／亮度胶囊 | [scorecard](scorecard.md):30 写我们用 DisplayServices，但 9/22 构建里是 0 | 亮度胶囊可用；这是竞品走的同一条私有路 |
| 亮度走私有 `DisplayServices`——**三家独立实现都是这么做**（Alcove／MediaMate／DynamicLake 1.0） | 三份二进制的交叉印证 | 刘海（88）／亮度胶囊 | 同上 | 这是这一格的既成做法，不是某一家特例 |
| **把私有框架打包进自己的 App**（自带 `CoreBrightness`／`DisplayServices` 副本），不依赖系统那份 | DynamicLake 1.0 内嵌框架 | 刘海／亮度 | 未记载 | 行为不随系统 macOS 版本变（代价：自己背一份私有实现的漂移） |
| 每型号 AirPods 影片会**串台**（它修过「AirPods Pro 显示成 AirPods Max 影片」） | DynamicLake 1.9.7.5 更新日志 | 刘海／设备电量 | AirPods 电池那条线 | 连不同型号时图形/影片对得上 |
| 跨显示器时的刘海动画要更顺、菜单栏隐藏时 Pill 间距要对、外接屏 Liquid Glass | DynamicLake 1.9.7.5 更新日志 | 多显示器（90）／刘海（88） | 未记载 | 换屏、菜单栏自动隐藏、外接屏三种边界各一条探针 |
| 锁屏上可以**关掉刘海** | DynamicLake 1.9.7.5 更新日志 | 刘海（88） | 未记载 | 锁屏时不显示刘海 UI（可开关） |
| 常驻动画的 CPU 要专门优化（「significantly reduced CPU usage for live weather animations」） | DynamicLake 1.9.8 更新日志 | 性能（89） | 我们也有常驻动画／传感器的 CPU 账 | 常驻动画的 60 秒 CPU 曲线 |
| **每个功能统一前缀**（DynaMusic／DynaGlance／DynaDrop／DynaClip／DynaConnect…），紧凑形态有独立产品名（miniLake） | DynamicLake 官网 | 文案（[copy-guide.md](copy-guide.md) 的词汇表原则） | 我们的词汇是描述性的（卷帘条／窗口浏览／看一眼），没有家族前缀 | 每个功能一个固定名字，跨菜单／设置／官网一致 |
| **开源许可声明做成页脚可见项**（FFmpeg LGPLv3 ＋ 链接源码） | DynamicLake 官网页脚 | 许可干净（全项目原则） | 未记载 | 用到 LGPL／第三方代码时，署名与许可出现在用户可见处 |
| 扩展性当**头条**卖（`NEW: Plugins — Turn Your Ideas into Reality`） | DynamicLake 官网首页 | 扩展面 | [niri.md](niri.md):91 把「脚本和 IPC」列为不追 | 三家都发了（OmniWM／ChainYourMac／DynamicLake），建议重评 |
| **宿主拥有形状、内容方只填 slot**（面板／裁剪／刘海间隙／几何全归宿主，扩展不许自己画背景与分隔线） | DynamicLakeKit 契约（Extensions 文档） | 文法（[design-grammar.md](design-grammar.md)） | 我们的令牌层在做同一件事，但**没外化成契约** | 每个表面能说清「谁决定形状、谁只填内容」 |
| 紧凑区**不放描述性文字**，只放时长型内容（计时／倒计时）；文字一律进 Sneak Peek | DynamicLake Design Guidelines | 刘海／看一眼（95） | 我们的「顺利时不说话」偏原则，没有这一条可检验规则 | 紧凑区出现描述性文字即不合规 |
| **不放「旁边的人可能看到」的敏感信息** | DynamicLake Design Guidelines | 隐私／刘海 | 工程侧有隐私登记；**没有针对「常驻可见面」的内容级规矩** | 常驻可见面的一条内容审查 |
| **不放推广文字与无关动作** | DynamicLake Design Guidelines | 文案（[copy-guide.md](copy-guide.md)） | 有相近规则，未写成表面规则 | 常驻面出现推广文案即不合规 |
| **跟手的时间步长纪律**：积分步长上限 1/30s、速度求导下限 1/1000s（两种用途两个界） | Paneru `ecs/scroll.rs`（MIT） | 卷轴跟手（未发布） | 未记载 | 卡一帧不会把卷轴一步撞到边界；慢帧不会算出无穷速度 |
| 惯性 **`v *= exp(-k·dt)`**，且**故意不设上限**（衰减单调，长帧只会多消耗动量不会过冲） | Paneru `apply_inertia` | iPadOS 27 风格的甩一下（94） | 未记载 | 长帧／卡顿后不过冲 |
| 藏起来的工作区停在**显示器右下角内侧、留 10 px**——因为 macOS 会把完全移出屏幕的窗口改派给另一台显示器 | Paneru `PARKED_STRIP_SLIVER = 10`（与 AeroSpace 的 `bottomRightCorner − onePixelOffset` 同一招） | 卷轴「停在屏幕外的列」 | [niri.md](niri.md):90 记为限制 | 露一条边的列不会被系统搬走 |
| 栏内高度用 `binpack_heights` 打包，装不下回退均分 | Paneru `ecs/layout.rs` | 卷轴／分栏 | 未记载 | 一列叠多扇时高度分配合理 |
| **18 个案例的「窗口分类」夹具**（managed／float／unmanaged；含 PiP、Chrome 弹窗、**别的刘海 App 的浮层**、锁屏遮蔽、快速查看） | OmniWM `Tests/…/WindowClassification/`（GPL-2.0） | 窗口浏览／收起本体 | 我们的探针没覆盖这些分类边界 | 每个夹具一条，期望分类与它一致 |
| 「岛」做成**声明式 widget 命令流**（`add/remove/move/enable/set`）＋**拖放状态机**（file/url/text/image；dragged/began/ended，批量投递） | OmniWM `Core/Shell/ShellIsland*` | 刘海／看一眼 | 未记载 | 岛的内容可由外部命令驱动；拖放有完整状态机 |
| 周期巡检 **`CGEvent.tapIsEnabled(tap:)`**，为假就重建 tap（我们只在收到 `tapDisabledBy*` 时重开） | DockDoor `DockObserver.performHealthCheck`（GPL-3.0，只借思路） | 稳定性／自愈（无对应格） | 我们 grep 不到 `tapIsEnabled` | 人为停掉一个 tap（或让它超时死掉），5 秒内自愈且日志说明 |
| **事件投递金丝雀**：给自己投一个带魔数 subtype 的 `.applicationDefined` 事件，收到才算「还发得出事件」；连续两次没回来就重建全部 observer 与 tap；**空闲时不发** | DockDoor `postingCanary*`（`subtype 0x0D0D`） | 稳定性／自愈 | 未记载 | 模拟「系统不再送我们的合成事件」，能自愈 |
| **原生标签页合并**：同 pid ＋ 取整相同的 frame 判为一组；在屏的一律保留，屏外的每组留「最近访问」那一个 | DockDoor `NativeTabGrouping` | 窗口浏览（88） | 我们没有：5 标签的终端会出 5 条 | 开 5 个标签的终端／Finder，窗口浏览只出一条 |
| 标题栏高度**从关闭按钮推**（`maxY − closeButton.minY + 12`，夹 48–72），整个标题栏矩形**缓存 1 秒** | DockDoor `resolvedTitleBarHeight`／`cachedTitleBarInfo` | 标题栏手势／卷轴 | 我们按 App 记常数（28／24／34／38 ＋ 逐 App 表），没见过的 App 得加 | 未收录的 App 也能认准标题栏 |
| 滚轮手势加一道**最小步长**（`0.15`），挡掉「手搭上去轻滚一下」的误触发 | DockDoor `minimumTitleBarScrollDelta` | 标题栏手势 | 未记载（惯性相位与自然滚动我们已处理） | 轻滚不动；Wins 3.3／3.5.1 那类误触发不复现 |
| 「再按一次回去」**带过期时间**（记原 frame ＋ `expirationDate`） | DockDoor `pendingTitleBarRestoreState` | R07「暂时取消全部置顶」 | 现有是 toggle，没说过期 | 半小时后再按不会弹回半小时前的位置 |
| 缓存通知用**深度计数**抑制（嵌套不会提前放行）＋ 增删改入队、一个主队列 flush 合并 | DockDoor `SpaceWindowCacheManager` | 侧栏／面板重绘 | 未记载 | 一次操作只掀一次重绘 |
| 窗口顺序的键是 **`bundleId｜窗口标题`**，不是 windowID；上限 500 条 | DockDoor `WindowOrderPersistence` | R07「顺序不乱」 | 未记载 | 退出再开，顺序照旧；换过 windowID 也认得出 |
| 凡按显示器落盘的键都用 **`CGDisplayCreateUUIDFromDisplayID`** 的 UUID，并留迁移路径 | DockDoor `NSScreen.uniqueIdentifier`（理由：displayID 每次重启会变） | 多显示器（90） | 我们 `NotchSpaceGate.swift:174` 已用；**其余按键要过一遍** | 重启／重接显示器后，按屏的设置在原来的屏上 |
| 自己写窗口时**先停听、写后等一个动画时长再开听**（`animationDuration + 0.02`） | PaperWM.spoon `Windows.moveWindow`（MIT） | 卷轴／收起本体 | 未记载 | 自己搬窗口不引发第二次重排 |
| 跟手期间**只做最小动作**并把「应该在哪」与「实际在哪」分开存；END 时保证焦点落在**完全在屏**的窗口上 | PaperWM `slide_windows`／`getFirstVisibleWindow` | 卷轴跟手 | 我们已按 App 分队列丢帧；缺「停听」与「END 保焦点」 | 滑完焦点一定在看得见的窗口上 |
| 窗口分类用**声明式白名单**（`visible`／`fullscreen = false`／`hasTitlebar`／`allowRoles = AXStandardWindow`） | PaperWM `Config.window_filter` | 窗口浏览／收起本体 | 未记载 | 与 OmniWM 的 18 个夹具互为正面／反面 |
| 宽度档位取**黄金比的三个共轭**（0.236／0.382／0.618），每步倍率恒定 | PaperWM `Config.window_ratios` | 卷轴／分栏手感 | 我们是 ⅓ ½ ⅔ 整屏（不全等比） | 大一级／小一级的手感一致 |
| **raise 会抢焦点**——所以层序只在「组成变了」时重排，不由「重排发生了」驱动 | PaperWM `tileStackedColumn` 的 `stack_signature` | 置顶／层序 | 未记载 | 重排不抢焦点 |
| 快照缓存**带成本模型**（不是「都缓存」，是按代价决定留哪一个） | Alcove 私有属性 `cachedSnapshots` ＋ **`cachedSnapshotCost`／`cachedSnapshotCosts`**（Swift 反射字串，见第三节） | 看一眼／窗口浏览的缩略图 | 我们 `Capture/ShareableContentCache.swift` 是短 TTL 缓存，**没有成本维度** | 多显示器＋多窗口同时要缩略图时，缓存不会无界增长 |
| **检测并共存别的工具**：Alcove 与 MediaMate **两家都带 `betterDisplay*` 字段**（看 BetterDisplay 在不在），ChainYourMac 官网也写「检测别的窗口管理器」 | 三家（Swift 反射字串 ＋ 官网），见第三节 | quiet-defaults／键盘（90） | 我们现在只对 Swish 说一次 | 装／跑着 BetterDisplay、Rectangle、Magnet 时能报出名字，不打架 |
| **几何读取的四级回退链**：`windowServerRect` → `axWindowRect` → `axWindowRectFallback` → `windowListRectFallback` | Wins `drag.*` 命名空间（Ghidra 函数级，见第三节） | 卷轴／落点小岛／窗口浏览 | 未记载：我们的几何读不到时怎么兜底，没写成一条链 | AX 读不到时仍能拿到正确的窗口外框 |
| **唤醒后的恢复是三档**：立即 ＋ 0.20 秒 ＋ 0.80 秒，各一次 | Wins `resume.immediate`／`resume.delayed.0.20`／`resume.delayed.0.80`（Ghidra 函数级） | 稳定性／自愈（[changelog-knowhow](changelog-knowhow.md) 排第一的欠账） | 我们有六处唤醒观察者，**没有重试、没有统一收口** | 睡/醒后全部功能回来；日志能读出三档各自做了什么 |
| **岛的布局是一份可重载的 JSON**（含一次 `layoutSanitize`） | Wins `island.layoutJSON`／`layoutReload`／`layoutSanitize`——**这一格里第三家**走「形状是数据」（另两家：OmniWM 的 `ShellIsland` 命令流、DynamicLake 的扩展契约） | 文法（[design-grammar.md](design-grammar.md)）／落点小岛 | 我们的令牌层在做同一件事，但**没有外化成可重载的数据** | 岛的形状能由一份数据描述并热重载 |
| **有前置条件的功能要列出缺哪条 ＋ 一键跳到对应的系统设置** | Wins `dockLock.hud.requirement.{autoHideDisabled,dockAtBottom,separateSpacesEnabled}` ＋ `hud.openSystemSettings`（Ghidra 函数级） | 欢迎流程／设置（R35–R36） | 未记载 | 缺条件时说明是哪一条，并给一个直接打开的按钮 |
| **把「AX 读取次数」做成可观测的计数器**（并压到最低） | Wins `missionControl.axReadsMinimum`／`snapshotCacheHits`／`probeRuns`；OmniWM 也在日志里报 μs 级的快照构建开销 | 性能（89）／卷轴跟手 | 我们按 App 分队列丢帧，但**没有把它变成可量的数** | 有一条能读到的「每帧 AX 读取次数」，且可回归 |
| **一份 41 个 bundle id 的例外名单**（含 macOS 自带的 `apple.WindowManager`、以及微信／QQ／钉钉／WPS／ToDesk／B 站／飞书／ClashX 等中国市场常客） | Wins `com.*`（Ghidra 函数级），与它 3.1.1 的「修复 ToDesk、QQ 音乐预览」对得上 | 窗口浏览（88）／收起本体 | 我们有逐 App 的 `fixedNonstandardChromeHeight(pid:)`，**没拿这张名单逐条比过** | 名单逐个装／开一遍，行为都对 |
| **预览与隐藏用两个队列**（公共队列 ＋ 延迟隐藏队列） | Wins `wins.windowPreview.commonQueue`／`hideDelayQueue`；`dockWindow.mainQueueDelay` | 窗口浏览／Dock 悬停 | 我们按 App 分队列；**「延迟隐藏」单独一条队列**没有 | 快速扫过图标时不闪；隐藏有可控延迟 |
| 给常驻条设 **`NSWindow.collectionBehavior` 三开关**：`disallowsTiling`（macOS 15+ 别平铺我）、`canJoinAllSpaces`、`fullScreenNone` | WindowMizer 日志串（Ghidra 函数级，见第三节） | 卷帘条／收起本体（92） | 未记载：我们的条在 macOS 15+ 会不会被系统平铺管到，没验过 | 系统平铺/全屏不再碰我们的条 |
| **孤儿占位条要主动收掉**（被收起的窗口没了，条还在） | WindowMizer `Reduce produced orphan placeholder; closing`／`restore orphan placeholder …; closing strip only` | 收起本体（92） | 未记载 | 窗口被别处关掉后，条自己消失 |
| **还原走一条串行队列，并记队列深度** | WindowMizer `Queued serial placeholder restore wn=%ld queueDepth=%ld`／`Running serial placeholder restore remaining=%ld` | 收起本体（92）／批次还原 | 我们有折叠事务，**没有「队列深度」这个可观测的量** | 连续还原多扇不打架；队列深度可读 |
| **还原期间要压掉 App 自己发的 `unhideAllWindows`／`orderFront`** | WindowMizer `Suppressed unhideAllWindows orderFront for CollapsedWindow during restore guard` | 收起本体（92）／层序 | 未记载：**这是一类真实对抗**，App 会在我们还原时插一脚抢顺序 | 还原后层序不被 App 抢走 |
| 收起**高度是算出来的**：读 `axMinH` ＋ **`axToolbarH`（AX 工具条高度）** ＋ frame，再按 `heightMode`／`classic`／`variant` 分支 | WindowMizer `Finder reduceToTitlebar … axMinH=%f axToolbarH=%f` | 收起本体（92）／标题栏 | 我们逐 App 记常量；**没读 `axToolbarH`** | 有工具条的 App 收起高度也对 |
| AX raise **确认不了就按成功处理**（降级支路），并记下可见性 | WindowMizer `assume_success_after_ax_raise action=close_placeholder_anyway` | 收起本体／稳定性 | 我们 `RestoreVerification` 走「验证」；**缺「验证失败但照样往下走」的支路** | 验证不确定时不卡住流程 |
| **内嵌崩溃上报**（它用 PLCrashReporter，收 `hw.model`／`kern.osrelease` 等机器信息） | WindowMizer `plcrash.CrashReport.*` | 稳定性／自愈（[production-maturity](production-maturity.md) 至今空白的那条） | **我们没有** | 崩溃能上报并带机器信息；不必自研 |
| 手势按**类别分栈**做设置面（九类：Dock／通用／菜单栏／调度中心／九宫格／屏幕／吸附／标签页／三分） | Swish 的九组 `*GestureStack` ＋ 12 个手势原语（`GestureUp/Down/Left/Right`／`Inwards/Outwards`／`Hold`／`Tap`／`Mod2/3/G/S`） | 标题栏手势（85）／设置 | 我们是单文件 `TrackpadGestures.swift`（2200+ 行），设置面没有按类别分 | 手势设置按类别分组；原语与组合分开 |
| 启动台的 App 列表**读系统那份 SQLite**（`SELECT item_id, title, bundleid, storeid FROM apps`——正是 Launchpad 数据库的表结构），而不是自己扫 `/Applications` 拼 | LaunchOS（Ghidra 函数级，见第三节） | 启动台（85） | 未记载：**这是一条可查的路**，但要核实当前系统版本上的路径与字段，且**系统升级会改 schema，必须有回退** | 列表的顺序／分组／文件夹与原生一致 |
| **接管系统 HUD 必须留一个「还给你」的开关** | MediaMate 的 `Disable Hiding Native OSD` 设置项 | 刘海（88）／亮度胶囊 | 未记载 | 有开关能退回系统原生 OSD |
| 观察 **Game Overlay（游戏模式）控制条**的可见性 | MediaMate `com.apple.GameOverlayUI.dashboardControlsVisibilityChanged` | 刘海／HUD 冲突 | 未记载 | 游戏模式下不跟系统 HUD 打架 |
| **与别的系统工具互通而不是抢地盘**：MediaMate 内置 Lunar 支持 ＋ BetterDisplay 模块；Alcove／MediaMate 带 `betterDisplay*` 字段；ChainYourMac 检测别的 WM | **四家**（见第三节） | quiet-defaults／键盘（90） | 我们现在只对 Swish 说一次 | 装／跑着 Lunar、BetterDisplay、Rectangle 时能共存并报出名字 |
| 按 displayID 找屏**找不到就一秒后重试** | MediaMate `Display with ID %u not found, trying again in a second...` | 多显示器（90） | 未记载：我们缺这条重试数值 | 显示器刚接上时能找回它 |
| 一个成熟产品的 HUD 有**五种形态**（条状／亮度／音频／控制中心／经典包装），不是一种 | MediaMate `BarHUDKind`／`BrightnessHUD`／`AudioHUD`／`ControlCenterHUD`／`ClassicHUDViewWrapper` | 刘海／HUD | 未记载 | 五种形态各有对应设置与外观 |

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

**所以二进制那一半的增量很薄。** 二进制分析基本在**印证我们已有的架构**（同一件事，他们走私有、我们走公开），没有推翻任何既有判断。

**但开源码深读那一半不是薄的。** 到 2026-10-14 收工，从源码里拿到的**可操作增量是 16 条**（上表最后十六行）：四家开源各给了一块——Atoll 的下载完成判定（我们原本的笔记是错的）与 allocated size；AeroSpace 的角落停靠与「先显后隐」；Rectangle 的 settling pass；niri 的手感值（1200 点／屏、150ms、0.997）；Paneru 的时间步长纪律、惯性公式、停放 10 点、binpack；OmniWM 的 18 个分类夹具与「岛的命令流」；**DockDoor 一家的自愈清单就贡献了九条**（金丝雀、`tapIsEnabled` 巡检、标签页合并、标题栏推高、最小步长、带过期的还原、抑制深度计数、窗口顺序的键、显示器 UUID）；PaperWM 贡献了「停听—写—再开听」、「END 保焦点」、「声明式窗口过滤」、「黄金比档位」、「raise 抢焦点」。

**这 16 条里有 9 条集中在同一个命题上：长驻的窗口管理器需要一套周期性的自我体检。** 这是这一轮最值钱的一条，形状见 [production-maturity.md](production-maturity.md) A 组的「自愈」。

**一处自我更正**：上一版把「`_CopySymbolicHotKeys` 判冲突」列成「值得直接借」是**错的**——我们已经在做，见上表。已从对照表移除。

**这一份怎么往下用**：把上面的「可借项」变成动作、并让竞品情报持续进料，见 [向生产级成熟演进](production-maturity.md)（动作清单 ＋ 长效机制）；**包层面**（DMG 版面／语言覆盖／插件 bundle／体积构成）见 [竞品包装与发行面](competitive-packaging.md)；**站层面**（站点结构／定价模式／文案定位／FAQ／开发者面）见 [竞品官网与对表面](competitive-websites.md)；**失败层**（626 个 release 的更新日志按 13 个失效家族归好、逐条对到我们的代码，并排了先后）见 [更新日志里的 real-world know-how](changelog-knowhow.md)。

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
   **2026-10-14 深夜更正（读到确切机制）**：它不是「把 Paneru 的码编进自己 App」，而是**一个 Swift 外壳 ＋ 一个随包发行的 Paneru 引擎进程**。证据：`Contents/Resources/PaneruHelper` 是 **8.6 MB 的 Rust Mach-O（263 处 Rust 标记）**，**被用自己的 Developer ID 重新签名**（`com.ahmedgagan.paneru.helper`，TeamID `574N433KY2`，与主 App 同一个 Team）；App 里一个 Rust 符号都没有，全靠 `ChainYourMac.PaneruEngine.runEngine(arguments: [String])` 走 `Process` 拉起它，两者之间是 **unix socket**（`/tmp/paneru.socket`，`PaneruIPCError`）＋ 一个 **LaunchAgent**（`com.github.karinushka.paneru.plist`，这就是官网说的「self-healing engine」），并且随包带一份 `default_paneru.toml` 模板。**而且它在产品里做了 MIT 署名**——App 内字符串原文：「The window engine is built on **Paneru by Karinushka**, a sliding, tiling window manager for macOS, released under the **MIT License**.」＋「Paneru on GitHub」链接。→ **这是一份 MIT 合规做得又正确又可查的样例**：随包发行 MIT 二进位 → 用自己凭证重签 → 在产品内给署名与许可。我们若哪天要随包带第三方二进位，就照这个形状做。
   **随包那份 `default_paneru.toml` 是一份「成熟卷轴工具暴露哪些旋钮」的完整清单**（原文注释一并记下）：
   - 行为：`focus_follows_mouse`（悬停即聚焦、不点）、`mouse_follows_focus`（切到哪扇指针跟过去）、**`session_restore = true`**（重启后记住列序与列宽）
   - 布局：**`preset_column_widths = [0.25, 0.33, 0.5, 0.66, 0.75]`**（五档宽度；我们是 ⅓ ½ ⅔ 整屏）、`gap_inner = 8`／`gap_outer = 8`、**`dock_aware = true`**（让开 Dock）、**`center_focused_column = "never" | "on-overflow" | "always"`**（把「要不要把当前列居中」做成一个策略枚举）
   - 外观：`animation = "smooth" | "fast" | "instant"`（三档）、`focus_border`（宽／色／圆角）、`dim_inactive` ＋ 不透明度、**`minimap = true`**——注释原文「Strip minimap shown **briefly while navigating**」，**就是我们的卷轴指示条／概览**，它 2.2.4 的更新日志也写了这颗「带 App 图标的条」
   - 手势：条状滑动的手指数为 `0`（关）／`3`／`4`，注释写明了理由「**macOS 用掉了三指滑动**」
   - **文件头有一段值得抄的设计声明**：「The window manager **reloads this file automatically whenever it changes**. Keys **the app does not know about are left untouched** when it saves.」→ **配置热重载 ＋ 保存时保留未知键**（前向兼容）。我们不用写配置，但这条原则对「设置文件被旧版读」那一类问题是通用的。
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

#### MediaMate 3.8.4（Aaron 供件，已验签通过，2026-10-14）

不在原清单里；它是音量／亮度 HUD 那一类（对应 [scorecard](scorecard.md):29 的「音量与亮度都鼓成 210×36 胶囊」）。**验签通过**：`Developer ID Application: Wouter Hennen (2MMGJGVTB4)`、`TeamIdentifier=2MMGJGVTB4`、`flags=0x10000(runtime)`、Gatekeeper **accepted / Notarized**。（对照：先前那两份同名件是 `TEAM EDiSO` ／ `https://macked.app` 重签、`TeamIdentifier=not set`、`flags=0x0`、**rejected**。）

| 项 | 值 |
| --- | --- |
| id / 版本 | `com.tweety.MediaMate` / 3.8.4，最低 macOS 13.0，`LSUIElement 1` |
| 闸门 | **0 个 `LC_ENCRYPTION_INFO`** → 不需要绕过保护 |
| 二进制／包 | 14.1 MB / 20 MB，fat（x86_64 + arm64） |
| 链接的私有框架 | **`CoreBrightness`、`DisplayServices`、`MediaRemote`** ＋ 自带的 `SwiftUIHidden.framework` |
| XPC 服务 | `MediaMateHelper.xpc`，标识 **`com.apple.controlcenter.MediaMateHelper`** |
| entitlements | apple-events（＋临时例外）、**`aps-environment`（推送）**、**iCloud container**、team-identifier |
| 本地化 | **只有 `nl`（荷兰语）**（英语为基底） |
| 呼叫轮廓 | 69,335 次 `bl`；**AX 只有 3 处**（`AXIsProcessTrustedWithOptions`），它不是窗口管理器 |

**四条值得记的：**

1. **亮度的做法是私有的**：`_DisplayServicesSetBrightnessSmooth／GetBrightness／CanChangeBrightness`（9 处）＋ 链接私有的 **`CoreBrightness.framework`**，另有 `CGDisplayIsBuiltin`、`CGDisplayRegisterReconfigurationCallback`。→ 我们 [scorecard](scorecard.md):30 写「亮度 DisplayServices」但 9/22 那份构建里是 **0**；现在有一份**别人家的正版件**在做同一件事，可以拿它当「这条路长什么样」的参照（要不要走是我们自己的决定）。
2. **`AudioHardwareCreateAggregateDevice` 又出现了。** MediaMate 的音量走 CoreAudio HAL（`AudioObjectAddPropertyListener／Get/SetPropertyData`）＋ aggregate device——**和 Alcove 上一轮挖到的完全同一招**。这是**第二个独立样本**，反过来把我上一轮对 Alcove「波形靠 aggregate device 抓音频」的**推论**坐实了（当时标的是「未实测」）。
3. **`SwiftUIHidden.framework`**：它自带一个专为暴露 SwiftUI **隐藏介面**而生的第三方框架。
4. **XPC helper 借用了 Apple 的 `com.apple.controlcenter` 命名空间**——**Alcove 也是**（`com.apple.controlcenter.AlcoveHelper`）。两家独立的应用做同一件事。只记事实与「这是跨厂商的既有做法」，不推测用途。

另记：它的 entitlements 里有**推送（`aps-environment`）与 iCloud container**——对一个 HUD 应用不算寻常。**授权／付费那一段仍属禁区，没碰。**

#### DynamicLake 1.0：早期构建（Aaron 供件，2026-10-14）

**先说三份同名件的区别**，因为它们性质完全不同：

| 件 | 签名主体 | TeamID | Gatekeeper | 判断 |
| --- | --- | --- | --- | --- |
| `DynamicLakePro_1_8.dmg` | **`https://macked.app`** | not set | rejected | **盗版站重签 → 退回** |
| `DynamicLake 1.0.dmg`（本件） | **`Apple Development: Avior Rokach`** | `XT766AV9R9` | **rejected（`CSSMERR_TP_CERT_REVOKED`）** | **厂方自己的凭证、签名完整** → 可分析 |

本件**可分析的理由**：`codesign --verify --strict` **退出码 0**——签名结构完整、**二进位没有被事后改动**；签名主体是**厂商自己**（`aviorrok.DynamicLake`，TeamID `XT766AV9R9`），不是第三方。**吊销 ≠ 被篡改**，这是两件事。

**要记的保留条件（写清楚）**：① 这是 **Apple Development 凭证**，不是 Developer ID——**它从来不是正式发行版**；② 凭证**已被 Apple 吊销**，Gatekeeper 拒（所以它只能静态分析，不能当正常发行件用）；③ 版本是 **1.0**——**下面描述的是 1.0，不代表当前的 Pro 产品**；④ 取得渠道不明。

| 项 | 值 |
| --- | --- |
| 闸门 | **0 个 `LC_ENCRYPTION_INFO`** → 不需要绕过保护 |
| 二进制／包 | **434,736 bytes（0.43 MB）／ 3.2 MB**，fat；**呼叫总数只有 2,002**（1.0 是个极小的早期件） |
| entitlements | `app-sandbox: false`；`files.user-selected.read-only` |
| 私有符号面 | `_DisplayServicesSetBrightness`、`_DisplayServicesBrightnessChanged`、`_AudioObjectGet/SetPropertyData`、`_AudioObjectHasProperty` |
| LoginItem | `LaunchAtLoginHelper.app` |

**两条值得记的：**

1. **它把私有框架打包进自己的 App。** `Contents/Frameworks/` 里带着 **`CoreBrightness.framework`、`DisplayServices.framework` 的副本**（外加第三方的 `MediaKeyTap.framework`），不是链系统那份。这是「不随系统 macOS 版本变化」的做法，代价是把一份私有实现的漂移风险自己背下来。
2. **亮度这条路现在是三家交叉印证。** DisplayServices 系：**Alcove**（`SetBrightnessSmooth` 等 9 处）、**MediaMate**（9 处 ＋ CoreBrightness）、**DynamicLake 1.0**（`SetBrightness`／`BrightnessChanged`）。**三家独立实现都走私有 DisplayServices**——这就是这一格的既成做法，也说明我们 [scorecard](scorecard.md):30 写的「亮度 DisplayServices」方向对（而 9/22 那份构建里还没落）。

#### DynamicLake 更新日誌（一手，[dynamiclake.com/changelog](https://www.dynamiclake.com/changelog)，读取于 2026-10-14）

**全部 79 个版本、1,946 行的完整条目已逐版抄录成独立文档：[docs/dynamiclake-changelog.md](dynamiclake-changelog.md)**（含每版的 New Features／Improvements／Bug Fixes）。下面只放结论。

页面是 Framer 站的**服务器渲染**，内容直接可解析（最新两版在收合的 rich text 里，已解出）。**当前版本 1.9.8（October 2026）**——比 Aaron 拿到的 1.8 Pro 和我分析的 1.0 都新。

**一、节拍很密。** 从 **1.0.2（2024）到 1.9.8（2026-10）共 79 个版本**，多产月份一个月发六七个点版本（2026-03：1.8、1.8.1.1、1.8.2、1.8.3、1.8.3.5、1.8.3.6；2026-07：1.9.3、1.9.4、1.9.4.3）。

**二、1.9.8「A Whole Glance and Clip」全文**

- 新功能：**全新 DynaClip**、**全新 DynaGlance**、DynaGlance 左右两侧新行为、**DynaGlance 智能导航**、通知支持**图片与视频**、**支持 Apple 提醒**、更多天气细节（体感温度、降雨概率、风）、云的实时天气动画（雷暴、阴天）
- 改进：**「Significantly reduced CPU usage for live weather animations」**、重做雾的实时动画、DynaDrop UI、全应用动画
- 修复：音乐播放器**颜色滑块**、**Pill 的 live activity 动画**、DynaGlance 设置、DynaClip **多选文件**、timer 命令打不开计时器、**向上鼠标滑动关闭 live activity 的手势**、**BetterDisplay 集成**、**AirDrop**、WhatsApp 通知

**三、1.9.7.5「Polishing the polished」全文**

- 新功能：**完整支持 macOS 27**、悬停更多 Live Activity 预览 Sneak Peek、**DynaClip 标签间拖文件**、新的 DynaClip Sneak Peek、**可以关掉通知**、**可以在锁屏上关掉刘海**、**上滑最小化 Live Activity**、新插件选项、**下载 Safari／Chrome 等浏览器插件**
- 改进：音乐 Liquid Glass 设计、DynaClip 界面、**「Smoother notch animations when moving between displays」**、Semi-Liquid Glass 动画、重做 DynaKeys、Pill 模式下的通话与 DynaConnect 界面
- 修复：DynaSwitcher、**隐藏刘海**、SMS 回复、**DynaKeys 重启 Mac 后的问题**、**若干外接显示器问题**、**「AirPods Pro displaying the AirPods Max video」**、**菜单栏隐藏时 Pill 间距错**、外接屏上的 Liquid Glass、**韩语下的通话问题**、DMG 界面

**四、对我们的直接意义**（这几条都落在 scorecard 有分的那几格上）

- **AirPods 串台是他们真踩过的坑**：1.9.7.5 修「AirPods Pro 显示成 AirPods Max 影片」——正是我们前面从 Alcove 资源里推出的「每型号一份预渲染影片」那套做法的**失败模式**。我们做 AirPods 那条线时要直接照这个验。
- **实时天气动画的 CPU** 是他们专门优化的一项（1.9.8）——常驻动画的 CPU 曲线，对应我们 [scorecard](scorecard.md) 的性能那一格（89）。
- **跨显示器时的刘海动画**（1.9.7.5「smoother… when moving between displays」）、**菜单栏隐藏时 Pill 间距错**、**外接屏 Liquid Glass** 三处——全是「刘海＋多显示器」交界处的边界，我们那一格（多显示器 90／刘海 88）值得照抄这几条当探针。
- **锁屏上可以关掉刘海**（新选项）——一个我们没记过的控制项。
- **插件／Market 体系 ＋ 浏览器插件下载**（1.9.7）——又一次印证：自动化／扩展面已经不是「可追可不追」，OmniWM、ChainYourMac、DynamicLake 三家都发了。

#### DynamicLake 官网（一手，[dynamiclake.com](https://www.dynamiclake.com)，读取于 2026-10-14）—— 产品表达与命名

上一节是它的 bug 史（拿来当验收用例）；这一节是它**怎么讲自己**——这一块对我们更像「可以照着做」的东西。

**一、命名体系（最值得借的一条）。** 每个功能都有统一的 **`Dyna-` 前缀**：**DynaMusic、DynaGlance、DynaDrop、DynaClip、DynaConnect、DynaKeys、DynaSwitcher**；产品/形态另有独立名字：**DynamicLake**、**miniLake**、**Pill**。对照我们：词汇是描述性的（卷帘条／窗口浏览／看一眼／置顶），**没有家族前缀**。[copy-guide.md](copy-guide.md) 的规矩是「一个东西只有一个名字、跨菜单/设置/官网一致」——它把这套做成了**品牌级**：名字先成体系，再保证一致。

**二、定位语直接claim Apple 血统。** 主页标题 `DynamicLake - Dynamic Island Mac`，页脚写 **「Inspired by Apple Dynamic Island」「Liquid Glass Design - Inspired by Apple Liquid glass」**。这是明确的站位选择（代价是被拿去和 Apple 比、也更容易招来注意）。

**三、形态体系比我们多一档。** 满刘海岛 ／ **miniLake（「小而省屏幕空间」的紧凑形态）** ／ **Pill（无刘海机与外接屏）** ／ **Liquid Glass 与 Semi-Liquid Glass 两种材质** ／ 「**只在外接屏上启用**」的选项。→ **miniLake 对我们是新东西**：它把「紧凑形态」当成独立产品名与独立卖点，不只是布局选项；我们的「紧凑左右耳」目前是同一颗岛的一种状态。

**四、它自己的功能清单**：DynaMusic（音乐）、DynaGlance（日程＋天气）、**Calls（FaceTime／电话进 Mac 通知）**、Notifications（iMessage／WhatsApp／Telegram／Slack）、DynaDrop（拖放→分享链接／转档）、DynaClip（文件管理：跨文件夹移动、分享、AirDrop）、Timer、DynaConnect（蓝牙／AirPods 连接通知），外加「Small things, Big changes」（AirDrop、电量提醒、日历提醒、会议、音视频转档）。

**五、`NEW: Plugins` 上首页头条**（「Turn Your Ideas into Reality」）——扩展性被当**头条**卖，跟上一节 changelog 里 1.9.7 的 Market／Plugin 体系对得上。

**六、社会证明做得很实**：10 条**实名**推荐语（Bailey Bootthanoo、Dr M Kinsella、Perrichon Tom…），其中一条专门夸「**开发者修 bug 很快，我发了邮件，下一版就带着修复发出来了**」。→ 响应速度被用户当卖点，这一条值得我们对照自己的发布节奏。

**七、FAQ 的题目清单本身就是情报**（16 题；答案是前端载入、**取不到**）：「支持无刘海机型吗」「买之前能试吗」「能 PayPal 吗」「多设备怎么激活」「支持外接屏吗」「**支持 BetterDisplay 吗**」「支持 Liquid Glass 吗」「**AppleLake 或 dynamiclake.net 跟我是不是同一家**」「支持哪些语言」。最后那条说明——**冒名站的问题他们自己放在官方 FAQ 里澄清**（对应我们之前查到的「这名字被恶意广告冒用」）。

**八、网站自身**：Framer 站的自家站点、**Discord 社群**、X `@avirok1`、`/privacy-policy`、`/termsofuse`，页脚挂 **FFmpeg 的 LGPLv3 声明**并链到 `arthenica/ffmpeg-kit`——**开源许可合规做成用户可见的页脚项**。另外导航里有 **Liqoria**（同一开发者的第二个产品；changelog 里出现过「Liqoria Notch Player 激活时隐藏 DynamicLake」）。

#### DynamicLake 的扩展平台与设计指南（一手文件，[docs.dynamiclake.com](https://docs.dynamiclake.com/documentation/dynamiclakekit/)，读取于 2026-10-14）

**这份比反编译值钱**：它是官方写的**设计意图**，不是猜的。刘海／pill 在它这里已经不是「一个 App 的界面」，而是**别人可以挂上去的表面**。

**一、两套扩展机制（它自己划的）**

| 类型 | 用什么写 | 适合 |
| --- | --- | --- |
| **Extensions** | **SwiftUI ＋ ExtensionKit ＋ DynamicLakeKit**（有 SPM 包） | 完整自定义 UI、companion app、深系统集成 |
| **Plugins** | 打包成 **`.dynamiclakeplugin`** 的**可执行档**，用 **JSON 消息走本地 socket**（`create`／`update`／`dismiss`） | 脚本、AI agent、计时器、构建进度、本机服务 |

**二、它把「谁拥有什么」写成了契约**（最值得学的一条）：

> **「DynamicLake provides the panel, clipping, notch gap, and screen-aware geometry. Your extension or plugin provides the content inside the left and right slots.」**

- 紧凑区只有**左右两个 slot**，**中间留给刘海／pill 的形状**（`LiveActivitySlotLayout`）。
- Sneak Peek 也一样：**「DynamicLake owns the panel shape, background, separator, clipping, and hover behavior」**——扩展只填内容，**不许自己画背景／分隔线／外边距**。
- 状态由 companion app 用 `DynamicLakeActivityCenter` 推（`setActivityActive`／`updateActivityState`／`closeActivity`），扩展侧用 `DynamicLakeActivityStateReader` 读；状态是小的 `Codable`。
- 几何由宿主提供（`LiveActivityGeometry.currentOnActiveScreen(size:)`、`.small/.normal/.large`），**扩展不许自己重算**。
- 免费 **Playground**：不买 App 也能跑一个 extension／plugin。另有（**已暂停**）的验证注册表：registry 由 DynamicLake 签名、要求 Apple 代码签名有效、签名标识＝bundle id、Team ID 与 registry 一致（[github.com/rokach/DynamicLake-Trusted-Extensions](https://github.com/rokach/DynamicLake-Trusted-Extensions)）。

**三、它的 Design Guidelines，与我们的 [design-grammar.md](design-grammar.md) 对照**

它写的（原文摘要）：**紧凑、可一瞥、与当前任务明确相关**；**用最小的视觉重量呈现最有用的一条状态**；紧凑区放主状态、Sneak Peek 放少量补充；**「不要用描述性文字标签，紧凑区的文字应是时长型内容（计时／倒计时）」**；**「避免广告、推广文字与无关动作」**；**「避免旁边的人可能看到的敏感信息」**；细节交给 App 本体。

| | DynamicLake 的指南 | 我们的 [design-grammar.md](design-grammar.md) |
| --- | --- | --- |
| 强项 | **宿主／扩展的边界写成契约**（谁画形状、谁只填 slot）＋**具体失效模式**（配置与视图尺寸不一致 → Sneak Peek 关掉后 live activity 会跳） | **Apple 原则可追溯**（HIG 八条 + WWDC 期号逐条对上自己的 14 张稿）、**四层各管一事**、材质三层、弹簧令牌化、**准入**闸门 |
| 我们缺的 | 「紧凑区**不放描述性文字**、只放时长型内容」——比我们的「顺利时不说话」更可检验 | — |
| 我们缺的 | 「**不放旁边的人可能看到的敏感信息**」——我们工程侧有隐私登记，但**没看到一条针对「刘海是常驻可见面」的内容级规矩** | — |
| 我们缺的 | 「避免推广文字与无关动作」——[copy-guide.md](copy-guide.md) 有相近的，但没写成这一条表面规则 | — |

**四、结论**：它把「宿主拥有形状、内容方只填槽」这条**外化成了 API**；我们 [design-grammar.md](design-grammar.md) 的**令牌层**其实在做同一件事（数值只在令牌里、画面照稿），只是没外化。真正可以借的是它那三条**可检验的表面规矩**（不放描述性文字／不放敏感信息／不放推广）——它们针对的正是「一个常驻可见的面」，而我们目前没有这一层规矩。

#### 新增一层：Swift 反射字串（数据模型）——2026-10-14 深夜

闭源这批**全是纯 Swift 且 stripped**：`nm` 只有未定义符号（Alcove 2,883／Swish 1,169／Droppy 6,729／LaunchOS 2,426／MediaMate 4,275，**全是 import，没有一个是自己定义的**），`_OBJC_CLASS_$_` 一个也没有。所以类名、方法名不在符号表里。

可读的东西在 **`__TEXT,__swift5_reflstr`**——Swift 的反射字串段，里面存的是**存储属性的名字（明文）**。把该段抽出来、按「小写开头的标识符」过滤，就得到每个 App 的**数据模型**：它把什么东西当成字段、按什么维度切分功能。**这一层不需要反编译**，成本几乎为零，而且直接暴露它的功能骨架。

| App | reflstr 行数 | 从字段名直接读到的 |
| --- | --- | --- |
| Notchy | 23,952 | `accessibilityPollTimer`（**它在轮询 AX**）、`allWorkspaces`、`alternateScrollMode`、`activeFocusTimeSeconds`、`appBeforePanel`、`approvalIslandIDs`、`backspaceSendsControlH` |
| Droppy | 18,617 | **该段解码异常**（读出来是反序／错位的字元），本轮没读出可用字段名——已记，不猜 |
| Alcove | 4,905 | `compensatesForNotch`、`actualBrightnessByDisplayID`、`builtInDisplay`、**`betterDisplayBundleIdentifier`**、`cachedSnapshots` ＋ **`cachedSnapshotCost`／`cachedSnapshotCosts`**、`controlStripSnapshotImage`、`accumulatedScrollDeltaX/Y`、`activeFocusIdentifier` |
| MediaMate | 4,468 | `displayChange`、`isNotch`、`notchDisplay`、`lockscreen`、`expandOnHover`、**`betterDisplay`**、`accessibilityChecker` |
| LaunchOS | 2,645 | `dockRect`、`displayGroups`、`displayStructureSnapshot`、**`edgeHoverStartTime` ＋ `edgeHoverThreshold`**、`draggingDisplayLink`、`dropActionHoverDelay`、`desktopGesture`、`allowsVerticalScrolling` |
| Swish | 2,429 | 一整套「手势 × 动作 × 开关」的配置模型：`chainGestureCheckbox`、`dockGestureStack`、`dragUnsnapCheckbox`、`centerUnsnap`、`autoHide`、`appHide`／`appMinimize`／`appUnminimize`、`applicationDockItem`、`floatingWindow` |
| ChainYourMac | 511 | `PaneruEngine`、`PaneruCommand`、`PaneruDirection`、`PaneruWindowOperation`、`PaneruIPCError`、`autoStartEngine`、`engineVersion`、`windowOperation`（见第三节第 1 条与第一节的更正） |

**三条结论：**

1. **Notchy 在轮询 AX**（`accessibilityPollTimer`）。这是我们刻意不走的路（[blueprint](blueprint.md) 的口径是 AX ＋ 通知驱动，不轮询）。**现在有了一个具体的反面样本**可以写进「为什么不轮询」。
2. **「检测并共存工具」不是个例**：Alcove 与 MediaMate **两家都带 `betterDisplay*` 字段**（它们会看 BetterDisplay 在不在）。我们原先只记了 ChainYourMac 官网的「检测别的窗口管理器并警告」——现在是**三家在做同一件事**，[§二](competitive-deep-dive.md) 那条「检测并警告」的优先级应该上调。
3. **快照缓存带成本模型**（Alcove 的 `cachedSnapshotCost`）：它不是「都缓存」，而是**按代价决定留哪一个**。我们的 `Capture/ShareableContentCache.swift` 是短 TTL 缓存，**没有成本维度**——这条可以直接借，尤其在多显示器、多窗口同时要缩略图时。

**方法本身也值得记**：对纯 Swift 的竞品件，「反射字串」是**成本最低的一层情报**（一条命令，不用反编译、不用权限），拿到的是它的数据模型。以后每来一份新件，先跑这一层。

#### 私有 API 名單（逐家确切的符号，不是计数）——2026-10-14 深夜

之前只记了「Alcove 22 处、Droppy 48 处」这类**计数**。这一轮把**名单**抽全了（`nm -u` ＋ 家族归类），七家的策略差别一下就看出来：

| 项目 | 公开 AX | CGS/SkyLight | Space 操作 | DisplayServices | CoreDock | MediaRemote | 其他 | 合计 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Swish | 23 | 2 | · | · | · | · | 1 | **26** |
| Alcove | 2 | 13 | **8** | 7 | · | · | · | **22** |
| MediaMate | 1 | 2 | 1 | 3 | · | **9** | · | **15** |
| LaunchOS | 6 | 3 | · | · | 4 | · | · | **13** |
| Notchy | 23 | 14 | · | · | · | · | 19（含 IOHID） | **56** |
| Droppy | 20 | 6 | · | · | · | · | 22（含 IOHID） | **48** |
| ChainYourMac | 1 | · | · | · | · | · | · | **1** |

**「只有一家有」的符号**（独门能力）：

| 项目 | 别人没有的 |
| --- | --- |
| **Alcove** | `CGSGetActiveSpace`、**`CGSSpaceCreate`／`CGSSpaceDestroy`／`CGSSpaceGetType`／`CGSSpaceSetAbsoluteLevel`／`CGSHideSpaces`／`CGSShowSpaces`**、`DisplayServicesGetBrightnessIncrement`、`DisplayServicesRegisterForBrightnessChangeNotifications` |
| **MediaMate** | `CGSCopySpaces` ＋ **9 个 `MRMediaRemote*`**（`GetNowPlayingInfo`／`SendCommand`／`SetElapsedTime`／`SetRepeatMode`／`RequestNowPlayingPlaybackQueueForPlayerSync`…） |
| **Notchy** | **`IOHIDRequestAccess`／`IOHIDDeviceCreate`／`IOHIDDeviceRegisterInputReportWithTimeStampCallback`**、`CGSetDisplayTransferByFormula`、`CGSSetWindowAlpha`、`AXUIElementCopyMultipleAttributeValues` |
| **Droppy** | **`IOHIDEventGetFloatValue`／`IOHIDEventSetFloatValue`／`IOHIDSetModifierLockState`／`IOHIDGetModifierLockState`／`IOHIDManagerCopyDevices`**、`CGSServiceForDisplayNumber` |
| **LaunchOS** | `CGSHWCaptureWindowList`、**`CGSSetMenuBarInsetAndAlpha`**、`CoreDockGetAutoHideEnabled`／`CoreDockGetOrientationAndPinning`／`CoreDockGetRect`／`CoreDockSendNotification` |
| **Swish** | `AXObserverCreateWithInfoCallback`、`AXUIElementCopyAttributeNames`、`CGSSetConnectionProperty` |

**四条读得出来的：**

1. **Alcove 会自己建立与销毁 Space。** `CGSSpaceCreate`／`CGSSpaceDestroy`／`CGSHideSpaces`／`CGSShowSpaces`／`CGSSpaceSetAbsoluteLevel`——这不是「知道窗口在哪个 Space」，而是**造 Space、隐/显 Space**。这是这一格见到的最重的一项私有能力，也是我们**刻意不碰**的那一侧（[competitors.md](competitors.md):101 的界线）。记它，是为了知道「别人能做到什么」，不是因为我们打算做。
2. **同一个「媒体」问题，两种架构建制**：MediaMate 把 9 个 `MRMediaRemote*` **放在主进程里直呼**（连同 `DisplayServices`）；Alcove 把私有面**关进 XPC helper**（主 App 0 个 `MR*`）。同一件事的两种「脏度」，正好印证 [§二](competitive-deep-dive.md) 那条「万一要用私有 API，怎么用得不脏」。
3. **Notchy 与 Droppy 都下到 IOHID 层**（`IOHIDEventGetFloatValue`／`IOHIDSetModifierLockState`／`IOHIDRequestAccess`）：抓原始输入事件、读写修饰键锁状态。我们走的是 CGEventTap ＋ Carbon 热键，不下这一层。
4. **ChainYourMac 主 App 只有 1 个私有符号**（`AXIsProcessTrustedWithOptions`）——**因为它自己不干活**：全部窗口操作都在随包的 Paneru 引擎里（见第三节第 1 条的更正）。「外壳与引擎分离」在这里的直接好处就是**主进程的私有面接近零**。

#### 函数级：Wins 的内部信号命名空间（Ghidra 12.1.4，2026-10-15 凌晨）

**这是整轮调研里第一份真正的函数级材料**（Ghidra 通路打通的当晚做的）。方法：把件抽成 arm64 单架构切片 → `rea analyze --provider ghidra` → 用 `rea search --kind strings --mode regex` 把**点分命名空间**整片捞出来。Wins 的件里存着 **219 个点分键**，那不是文案，是**它自己的埋点／信号名**——等于把它的内部管线列了出来。

**1. 拖动 → 落点小岛 的完整管线（17 个 `drag.*`）：**

```
drag.windowServerRect   drag.axWindowRect   drag.axWindowRectFallback
drag.windowListRectFallback   drag.axWindowHitTest   drag.windowIdentifier
drag.axSizeSettable   drag.exclusionCheck   drag.snapAreaDetection
drag.islandUpdate   drag.edgeUpdate   drag.cursorNudge
drag.unsnapRestore   drag.shake   drag.stageManager
drag.flickDockPrepare   drag.flickDockRelease
```

- **几何读取是一条四级回退链**：`windowServerRect` → `axWindowRect` → `axWindowRectFallback` → `windowListRectFallback`。**这就是「AX 读不到时用什么兜底」的现成答案**，而且顺序说明了主次：**先 WindowServer，再 AX，再两层回退**。
- **`drag.axSizeSettable`** —— 这就是我们 [competitive-analysis.md](competitive-analysis.md):29 记的那条「让分屏岛与边缘吸附忽略不能调整大小的窗口」，现在有了它在竞品内部的**真实命名**。对照我们：`prototype/Window/AXWindow.swift:83` 的 `isAXSizeSettable` **只用在了卷帘条自身**，排布路径还没接——**这一条从「据说」变成「确认，且我们确实欠着」。**
- **`drag.stageManager`** —— **台前调度在拖动路径里是一个具名步骤**，和 [changelog-knowhow](changelog-knowhow.md) D 族那 19 条互相印证。
- **`drag.cursorNudge`** —— 拖动时会**轻推光标**（与 paneru「把离屏窗口往下推一点」是同一类手法，用途不同）。
- **`drag.flickDockPrepare` ／ `drag.flickDockRelease`** —— 甩到 Dock 的手势是**两段式**（预备 → 释放），不是一次性判定。

**2. 岛的布局是数据，不是代码（7 个 `island.*`）：**

```
island.layoutJSON   island.layoutReload   island.layoutSanitize
island.animationFrame   island.interactionUpdate   island.show   island.hide
```

`island.layoutJSON` ＋ `island.layoutReload` ＋ `island.layoutSanitize` 说明：**Wins 的落点小岛由一份 JSON 布局描述驱动，可以重载、并且会做一次「净化」**。这是这一格里**第三家**走「形状是数据」的路（另外两家：OmniWM 的 `ShellIsland` 命令流、DynamicLake 的扩展契约）。→ 我们 [design-grammar.md](design-grammar.md) 的令牌层在做同一件事，但**没有外化成一份可重载的数据**。

**3. 唤醒后的恢复是三档（3 个 `resume.*`）：**

```
resume.immediate   resume.delayed.0.20   resume.delayed.0.80
```

**直接回答了 [changelog-knowhow](changelog-knowhow.md) 里我们排第一的那条欠账**：Wins 的唤醒恢复不是「等一个通知就重建」，而是**立即一次 ＋ 0.20 秒后一次 ＋ 0.80 秒后一次**。三次重试、两个具名延迟。→ 我们的唤醒观察者散在六处且没有重试，**这条可以直接照抄数值**。

**4. Mission Control Pro 的埋点（12 个 `missionControl.*`）：**

```
probe   probeRuns   snapshot   snapshotCacheHits   axReadsMinimum
scan.dock   scan.windowManager   dragFastPath   handle   nodes.dock
nodes.windowManager   tapDisabled
```

读得出来两件事：**（a）它把「AX 读取次数」当成一个要压到最低的指标**（`axReadsMinimum`、`snapshotCacheHits`）——和我们 [niri.md](niri.md):46「慢 App 跟不上时跳过中间几帧」是同一个目标，但它**把它做成了可观测的计数器**；**（b）`tapDisabled` 是它自己记的一个信号**——**和我上一轮写进 [changelog-knowhow](changelog-knowhow.md) A 族的那条完全对上**：连 Wins 都把「tap 被系统禁用」当成一等公民在观测，而我们没有。

**5. Dock 锁定屏幕：三个前置条件 ＋ 一句「去哪开」**（`dockLock.*`、`dockDisplayLock.*`）：

```
dockLock.hud.requirement.autoHideDisabled
dockLock.hud.requirement.dockAtBottom
dockLock.hud.requirement.separateSpacesEnabled     ← 「显示器具有单独空间」
dockLock.hud.openSystemSettings   dockLock.hud.signOutNote
dockDisplayLock.targetUUID   targetUUIDs   enabled
dockDisplayLock.delayRecovery{Pending,Value,HadValue}
dockDisplayLock.orientationRecovery{Pending,Value}
dockDisplayLock.noRestartMigrationCompleted        ← 设置迁移标记
```

- **这条功能有前置条件，缺哪条就告诉用户哪条，并给一个直接跳到系统设置的按钮**。而且它明确要求 **「显示器具有单独空间」** ——**又是那一条**（Paneru／PaperWM／OmniWM 都在这个点上）。
- **`targetUUID` 用的是显示器 UUID，不是 displayID** ——与 DockDoor／OmniWM 同一条，**第四家**。
- **`noRestartMigrationCompleted`**：连「不用重启就迁移完」都留了标记——设置迁移是竞品的常规动作，不是我们的特例。
- **两个 recovery 状态机**（`delayRecovery`／`orientationRecovery`）＋ `delayRecoveryHadValue`：Dock 移动后「延迟值」和「朝向值」各自要恢复，且**要记得「之前是否有过值」**。这是一段很具体的恢复逻辑。

**6. 双队列（`wins.*`）：**

```
wins.windowPreview.commonQueue      wins.windowPreview.hideDelayQueue
wins.commandtabplus.appTitleCache   wins.commandtabplus.hoverDetection
wins.commandtabplus.runningAppIndex wins.multiWindow.minimize.concurrent
```

**预览用一个公共队列，隐藏用另一个「延迟隐藏」队列**——和我们按 App 分队列、[niri.md](niri.md):46 的「不拖慢手指」是同一种分治。另有 `dockWindow.mainQueueDelay`（他们**故意把主队列工作延后**）。

**7. 一张 41 个 bundle id 的「要特殊对待的 App」名单（`com.*`）：**

`apple.WindowManager`（**macOS 15 自带的窗口平铺**）、`apple.dock`、`apple.loginwindow`、`apple.screenIsUnlocked`、`apple.universalaccess`、`apple.systempreferences`、`apple.finder`、`apple.dt.Xcode`、`apple.AccessibilityInspector`、`apple.MobileSMS`、`apple.FaceTime`、`apple.Preview`、`apple.iBooksX`、`apple.iWork.Keynote`、`google.Chrome`、`microsoft.teams`／`teams2`、`openai.codex`、`electron.lark`、`alibaba.DingTalkMac`、`tencent.xinWeChat`、`tencent.qq`、`tencent.WeWorkMac`、`youqu.todesk.mac`、`kingsoft.wpsoffice`、`bilibili.bilibiliPC`、`west2online.ClashX`、`colliderli.iina`、`ssworks.drbetotte`、`sjc.calendar`、`ru.keepcoder.Telegram`、`IdeaPunch.ColorSlurp`、`goland.dvdfab.macos`、`net.battle.bootstrapper`、`blizzard.worldofwarcraft`、`valvesoftware.steam`、`hammerandchisel.discord`、`autodesk.AutoCAD`、adobe 三件、`jetbrains.`、`org.mozilla.firefox`、`videolan.vlc`。

→ **这是一张现成的「中国市场要特别照顾哪些 App」名单**，和 Wins 3.1.1 更新日志里「修复 ToDesk、QQ 音乐等第三方应用无法正常预览」对得上（`youqu.todesk.mac` 就在名单里）。**值得拿它逐条比我们的逐 App 表**（`fixedNonstandardChromeHeight(pid:)` 那一套），看我们漏了哪些。

**8. 其余的埋点**（各一条，都是「他们在观测什么」）：`ax.minimumOperations`、`preflight.identity`、`ui.updateAttempts`、`snapAreaDetection` 旁的 `snapping.filter/mouseDown/mouseUp`、`appexpose.windows`、`screen.detection/inspected`、`cursorNudge.eventsPosted`、`flickDock.offDockSkips`、`window.enumeration(s)`／`enumerationItems`、`window.screenshot(s)`。

**9. 一张完整的授权界面文案表（`update.*` 53 条 ＋ `activation.*` 21 条）：** 里面是 `entitlement.error.*` 的 **28 种错误**（`activationExpired`／`seatsFull`／`licenseNotFound`／`updateExpired`／`verificationHTTPStatus`…）与对应的 `entitlement.button.*`。按本项目第一节的界线，**这一块只记录存在，不分析、不试探**（[competitors.md](competitors.md):101）。它的用处只有一个：**「授权能出的岔子有多少种、每一种该怎么对用户说」**——是一份现成的文案清单。

**观察，不是伪代码。** 这一节拿到的是**字符串层的证据**（Ghidra 把定义到的字符串与它的引用都列了出来），说明的是**Wins 内部有哪些具名环节**；每个环节的**具体判定逻辑**还要逐函数 `rea decompile`。但即便如此，上面第 1／3／4／5 条已经能直接进我们的动作清单——**尤其是 `resume.delayed.0.20／0.80` 和 `drag.axSizeSettable`**。

#### 函数级：Alcove 的 20,250 条「字符串 → 函数」映射（同夜）

同一套方法换到 Alcove（`analyzeHeadless` ＋ 一个自写的 Java 后置脚本，把每个被定义成字符串的数据与其引用方函数导成 TSV）。**扫过 106,958 个已定义数据，留 14,962 个字符串，产出 20,250 条映射。** 拿到的：

**1. 它的 Space 操作是一个独立模块。** 九个 `CGS*Space*` 的存根地址**连成一片**（`0x100604ff8` → `0x100605020`），顺序是：

```
_CGSAddWindowsToSpaces  _CGSGetActiveSpace  _CGSHideSpaces
_CGSRemoveWindowsFromSpaces  _CGSShowSpaces  _CGSSpaceCreate
_CGSSpaceDestroy  _CGSSpaceGetType  _CGSSpaceSetAbsoluteLevel
```

→ **这九个连在一起，说明 Alcove 里有一个专门的「Space 管理」单元**，不是零散调用。而 `_CGSAddWindowsToSpaces` 另外在**三处**被引用（`0x10064e858`／`0x10065204c`／`0x1006533ec`）——**它在多个场景里都要把窗口塞进某个 Space**。我们自己不用这条路（[competitors.md](competitors.md):101），记它只为知道「对面的能力边界在哪」。

**2. Alcove 也有一张 App 例外名单，而且和 Wins 那张**几乎没有重叠**：**

```
com.apple.WindowManager   com.apple.WebKit.GPU   com.apple.screenIsUnlocked
com.google.Chrome         com.microsoft.teams2   com.spotify.client
com.tidal.desktop         com.tinyspeck.slackmacgap   net.whatsapp.WhatsApp
ru.keepcoder.Telegram     company.thebrowser.dia
com.riotgames.leagueoflegends / leagueclient / leagueclientux
com.nvidia.gfnpc.mall
```

Wins 那张是**中国市场**（微信／QQ／钉钉／WPS／ToDesk／B 站／飞书／ClashX），Alcove 这张是**西市场**（Slack／WhatsApp／Telegram／Spotify／TIDAL／Dia／**英雄联盟三个 bundle**／**GeForce Now**）。→ **两家独立实现、两张几乎不相交的例外名单**——这说明「**逐 App 例外表是结构上躲不掉的**」，不是某一家的癖好。**我们的 `fixedNonstandardChromeHeight(pid:)` 应该把两张名单并起来过一遍。**

**3. 它把自己的功能命名空间也写在里面：**

- **`focus.fitness` ／ `focus.personal` ／ `focus.sleep` ／ `focus.work`** —— **四种 macOS 专注模式被做成了数据**（四个键全指向同一个函数 `FUN_1000fb5d4`），也就是说**它按当时的专注模式切换行为**。这一条我们完全没记过。
- `calendar.empty.noEvents` ／ `calendar.empty.thisDayIsClear`——日历的两种空状态。
- `menu.media.copyLink` ／ `menu.media.showIn`——媒体项的右键菜单项。

#### 函数级：Swish 的手势分类骨架 与 WindowMizer 的占位条生命周期（同夜）

同一个方法又跑出两份（`Swish.tsv` 10,111 条；`WindowMizer.tsv` 23,011 条）。两份都值钱，而且是**不同类型的值钱**。

**一、Swish：把「30 个手势」的真实骨架挖出来了。**

```
GestureUp  GestureDown  GestureLeft  GestureRight
GestureInwards  GestureOutwards  GestureHold  GestureTap
GestureMod2  GestureMod3  GestureModG  GestureModS
```

这是它的**手势原语**：四个方向 ＋ 进出（inwards／outwards）＋ 按住 ＋ 点 ＋ 四个修饰键变体（Mod2／Mod3／ModG／ModS）。而我们此前只知道官网说的「30 个手势」——**现在知道那 30 个是这 12 个原语的组合**。

更实用的是它在设置里的**九组手势栈**（`NSStackView` 的实例变量名直接留在二进制里）：

```
dockGestureStack      generalGestureStack   menubarGestureStack
missionControlGestureStack   ninthsGestureStack   screensGestureStack
snappingGestureStack  tabsGestureStack      thirdsGestureStack
```

→ **九类：Dock／通用／菜单栏／调度中心／九宫格／屏幕／吸附／标签页／三分**。这是「一个成熟手势产品把功能切成哪几类」的现成答案。另外 `Swish/GestureView.swift`、`Swish.CenterGestureView` 这类 **`#file` 源码路径也留在二进制里**，等于免费看到它的文件结构。对照我们：`App/TrackpadGestures.swift` 2200+ 行一个文件——**它的「按类别分栈」值得借鉴到我们手势的设置面上**。

**二、WindowMizer：占位条（placeholder）的完整生命周期，全在它自己的日志串里。**

这一家的内嵌日志串极其啰嗦，而**正是这份啰嗦把「收起本体」这一格的问题空间完整摊开了**。逐条读到的（原文保留参数名）：

| 它记的东西 | 意味着什么 | 对我们 |
| --- | --- | --- |
| `placeholder green-button collectionBehavior fullScreenNone=%{bool}d disallowsTiling=%{bool}d canJoinAllSpaces=%{bool}d` | 给占位条设了**三个 `NSWindow.collectionBehavior` 开关**：`fullScreenNone`、**`disallowsTiling`**（macOS 15 起让系统别去平铺它）、`canJoinAllSpaces` | **可直接照抄**：我们的卷帘条若在 macOS 15+ 上被系统平铺管到，缺的就是 `disallowsTiling` |
| `usesDetachedFauxTrafficLights=%{bool}d` ＋ `styleMaskTitled=… isBorderless=… titleVisibility=… titlebarAppearsTransparent=…` | 无边框占位条上**自己画一套假的红绿灯**，并把窗口样式参数逐个记下来 | 我们 `Overlay/ShadeStrip.swift:351` 已经在处理 `.closeButton` 那一组，**值得比对它这套参数** |
| `Reduce produced orphan placeholder %s; closing`／`restore orphan placeholder …; closing strip only`／`Queued serial placeholder restore wn=%ld queueDepth=%ld`／`Running serial placeholder restore wn=%ld remaining=%ld` | **占位条会变成孤儿**（被收起的窗口消失了，占位条还在），而且**还原是一条串行队列、还记队列深度** | 我们有折叠事务（`FoldTransaction`），**但「孤儿占位条要主动收掉」和「串行还原队列带深度」这两条没有** |
| `Suppressed unhideAllWindows orderFront for CollapsedWindow during restore guard` | **还原期间要压掉 App 自己发的 `unhideAllWindows`／`orderFront`** | **这是一类真实的对抗**：App 在我们还原时会插一脚抢顺序。**我们侧栏/折叠的还原路径要查有没有这一条** |
| `compositor still shows placeholder after force teardown wn=%ld axWin=%ld` | 拆完之后**去问 compositor（WindowServer）它还显不显示**——不假设拆了就没了 | 与我们的 `Effects/RestoreVerification.swift` 同一种「验证效果真的发生」 |
| `assume_success_after_ax_raise action=close_placeholder_anyway quartzVisible=%{bool}d` | AX raise **确认不了时，就按成功处理**（并记下 qurtz 可见性） | 一个务实的**降级策略**：验证失败不等于操作失败，要有「照样往下走」的支路 |
| `placeholder inactive capture upscale to quartz pixels … quartzPt=%s`／`collapsed inactive snapshot missing after minimize tail` | 截图要**升采样到 Quartz 像素**；最小化之后快照会丢 | 又是「点 vs 像素」那一族，第 E 族的同类 |
| `Finder reduceToTitlebar … axMinH=%f axToolbarH=%f`／`Finder placeholder minHeight=%ldpt` | 收起的**高度是算出来的**：读 AX 最小高度、工具条高度、窗口 frame，再按 `heightMode`／`classic`／`variant` 分支 | 我们是逐 App 的 `fixedNonstandardChromeHeight`；**它多读了 `axToolbarH`（AX 工具条高度）这个量** |
| `collapsed strip not at reduced height after minimize wn=%ld frameH=%f` | 收起后**回头量一次高度对不对** | 可加进我们的收起探针 |
| `collapsedLayout.flush.display` | 显示器变化时**刷掉收起布局** | 对应 D 族的显示器变化 |

另外两条与「收起本体」无关、但属于生产成熟度：

- **它内嵌了 PLCrashReporter**（`plcrash.CrashReport.*`、`com.plausiblelabs.crashreporter.data`）——**它是一个带崩溃上报的 App**。[production-maturity](production-maturity.md) 里我们「崩溃自愈与日志」那条至今是空的，**这是一个可以照的形状**（不必自研，PLCrashReporter 是现成的）。
- 它收集 `hw.model`／`hw.logicalcpu_max`／`kern.osrelease`／`kern.osversion` 等机器信息——**为上报单准备的**。

**它的 App 例外名单很短**：`com.adobe.PremierePro`、`com.apple.Safari`、`com.apple.iCal`、`com.apple.automator`、`com.google.Chrome`、`com.vivaldi.Vivaldi`。**第三张独立名单，和 Wins、Alcove 那两张又不一样**——三张几乎不相交的名单摆在面前，「逐 App 例外表」这件事已经不需要再论证了。

#### 函数级：LaunchOS 读的是那个 SQLite 表 与 MediaMate 跟别人的互通（同夜）

**LaunchOS（`LaunchOS.tsv` 16,473 条）——启动台（85）这一格的关键一问有了答案：它从哪拿 App 列表。**

件里留着两条完整的 SQL：

```sql
SELECT name FROM sqlite_master WHERE type='table';
SELECT item_id, title, bundleid, storeid FROM apps
```

外加 `Failed to query sqlite_master`／`cantOpenDatabase`／`databaseNotFound` 三条失败分支，和一个 `com.launchosapp.metadata` 命名空间。

**`item_id, title, bundleid, storeid` 这一组列名，是 Apple 自己那个 Launchpad 数据库的表结构。** 也就是说：**LaunchOS 不是自己扫 `/Applications` 拼一份列表，而是去读系统那份 db**——这解释了它为什么能做到「顺序、分组、文件夹都跟原生一致」。→ **对我们启动台那一格，这是一条直接可查的路**（要核实的是那份 db 在当前系统版本上的确切路径与字段；它属于「读系统数据库」，不是私有 API，但**系统升级会改 schema**，所以必须有回退）。其余读到的：`folder.base.opacity`／`folder.title.opacity`（文件夹的渲染参数）、`hw.model`，以及一张 Apple App 名单（`com.apple.AppStore`／`Passwords`／`Preview`／`Stickies`／`findmy`／`ScreenContinuity`…）。

**MediaMate（`MediaMate.tsv` 26,932 条）——最值钱的不是它怎么调亮度，是它跟谁合作。**

```
Display config changed, restarting Lunar connection.
BetterDisplaySupport/BetterDisplay.swift     BetterDisplayCommand
BetterDisplayStatusView                      BetterDisplayStatusView
com.apple.GameOverlayUI.dashboardControlsVisibilityChanged
Disable Hiding Native OSD
Disabling keyboard brightness service
Display with ID %{public}u not found, trying again in a second...
```

四条：

1. **它内置了对 Lunar 的支持**（`restarting Lunar connection`）和对 **BetterDisplay** 的完整适配（`BetterDisplaySupport/` 一个模块）。→ 加上 Alcove 的 `betterDisplayBundleIdentifier`／`mediaMate` 的 `betterDisplay` 字段、ChainYourMac 官网的「检测别的窗口管理器并警告」，**现在有四家在做同一件事：主动与别的系统工具互通，而不是抢地盘。** 这是[竞品深挖](competitive-deep-dive.md)§二那条「检测并警告」的第四次印证，**优先级应上调**。
2. **它观察 macOS 的 Game Overlay（游戏模式）控制条可见性**（`com.apple.GameOverlayUI.dashboardControlsVisibilityChanged`）——一个我们绝不会想到的通知。游戏模式下系统会插自己的 HUD，**冲突就在这里**。
3. **`Disable Hiding Native OSD` 是一个设置项**：它默认要压掉系统原生 OSD，但**给了用户一个「别压」的开关**。→ 对我们是现成的做法：**接管系统 HUD 必须留一条「还给你」的路**。
4. **`Display with ID %{public}u not found, trying again in a second...`**——按 displayID 找屏，**找不到就一秒后重试**。与 D 族「显示器身份」那一族同源，但多给了一个具体数值（1 秒）。

它还留了一串源码路径（`Audio/AudioHUDView.swift`、`DisplayBrightness/BrightnessHUDView.swift`、`BetterDisplaySupport/BetterDisplay.swift`）和 HUD 的种类枚举（`BarHUDKind`／`BrightnessHUD`／`AudioHUD`／`ControlCenterHUD`／`ClassicHUDViewWrapper`）——**一个成熟产品的 HUD 有五种形态，不是一种**。

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

### 三份未挖 TSV 的收成＋私有面三镜重扫（2026-10-15）

七份 TSV 此前只挖了四份（Swish／WindowMizer／LaunchOS／MediaMate）；**Alcove（20,251 行）、ChainYourMac（32,143 行）、Wins（12,872 行）零引用**——本轮补挖，顺带用新镜头发起「私有面三镜」重扫（矩阵在第五节 5.3）。

**各家新事实：**

- **Notchy：是 Swift 单体，不是 Electron**（`swift-testing`／`swiftpm-*` 指纹、`Notchy_Notchy.bundle` 3,207 项、`Strings/*.json` 138 语）。链接 **ShazamKit**（辨歌）、libsqlite3、CoreBluetooth、AppIntents。dlsym 16 个（5.3 口径 B）。← **更正**：此前「Notchy 改窗口 alpha 与显示器 gamma」**查无实据**（二进制与资源全包搜 alpha／gamma 相关均为 0），说法已撤。
- **Droppy：十家里私有面最深**。dlsym 21 个（`DisplayServicesCanChangeBrightness`、`KeyboardBrightnessShortcutManager` 全家、SLS Connection／Space 组）；私有框架 13 个，其中 **Biome 全家**（`BiomeFoundation`／`BiomeLibrary`／`BiomeStorage`／`BiomeStreams`——Apple 的**行为流**框架，读使用记录），另有 HearingUtilities、MusicUI、MenuBarClientCore。隐私对照：它读的东西比我们多一个数量级。
- **Alcove：亮度写入有回退链**——DisplayServices 写失败 → `fallbackBrightnessUpKeyCode`／`fallbackBrightnessDownKeyCode`／`fallbackNormalMediaKeyStep`（发亮度键码）＋失败日志；**BetterDisplay 集成**（`BetterDisplayIntegrationRequestData`／`BetterDisplayOsdNotificationData`，和 MediaMate 一样避免 OSD 打架）；`storageRecoveryTask`；Keychain 重试（付费面，只看不碰）。**还有 per-app 特例清单**（`company.thebrowser.dia`／`net.whatsapp.WhatsApp`／`ru.keepcoder.Telegram`——在数据表里，无函数归属）。功能词频：Gesture 145／Space 159／Waveform 33／Artwork 27／Hover 34，**Shelf＝0**——它没有「卷帘条」概念，我们的收窗口是真差异；波形与封面画得实（我们[有意不抄私有绘制](scorecard.md)）。对照：我们有**集中政策层** `Compatibility/Policies.swift`（Finder／Safari／系统设置各有类型化策略，折叠恢复核心不感知具体 App）——结构比散落的 bundle-id 检查好。
- **Wins：可靠性三件套**——`automaticRetryDelay`／`displayConfigurationRetryDelay`（显示配置变化后重试）；登录项「Unable to enable launch at login. Attempting one more time.」（**失败重试一次**）；`drag.axWindowRectFallback`／`drag.windowListRectFallback`（**AX 拿不到矩形 → CGWindowList 兜底**）。另有 `[WindowDragPerf]` 内建性能日志、应用内直接写「Uses <30MB memory and 0,1% CPU.」、**`SLSConnectionGetPID`**（用 SLS 连接反查 PID——我们没有这条能力）。
- **ChainYourMac：源码路径泄漏**——`/Users/ahmedgagan/Documents/MyProjects/MacApps/ChainYourMac/PaneruApp/build/...`（SwiftUI，工程名 PaneruApp）；默认快捷键文案一组（`ctrl + alt + cmd - leftarrow` 等）；License* 组件（付费面，只看不碰）。
- **MediaMate：CoreAudio 卫生**——每个属性监听器都有配对的加/移除与失败日志；`Activation Error: couldn't access keychain`。
- **WindowMizer：回退与自愈**——`Finder overlay … missing from SCShareableContent; full-display fallback (Quartz ownerPid=%d)`（**抓屏缺窗 → 退回 Quartz 全屏**）；`AppURLs.json missing or invalid; using compiled fallback`（**配置坏了用编译内置**）；`demini_recovery phase=activate_process_raise_pulse`（恢复状态机带 phase 事件名）。

**三条可直接借的（我们本轮核过，确认为 0）：**

| 竞品做法 | 我们的现状 | 归 |
| --- | --- | --- |
| 亮度写入回退链（Alcove：DisplayServices → 亮度键码） | `NotchLevelControl.swift` dlsym 拿不到就把 `setBrightness = nil`，**没有第二条路** | 亮度 HUD 健壮性（E／H 系列） |
| 登录项失败重试一次（Wins） | `Preferences.swift:1084` 只调一次 `SMAppService.mainApp.register()` 并记日志，**不重试** | 与 R2 同族（系统集成自愈） |
| AX 几何拿不到 → CGWindowList 兜底（Wins／WindowMizer） | `Window/AXWindow.swift:27` `guard let … else { return nil }`，**没有兜底** | R20（窗口身份边界） |


### 三个点名对手：Thaw／LaunchNext／DockDoor（2026-10-15 按对手标准逐格看）

**Aaron 点名，当对手对待。** 三家全部 **GPL-3.0（DockDoor 的 GitHub 标签是 NOASSERTION，但 README/LICENCE 正文是 GPL-3.0——按许可地图：只借思路，一行代码都不取）**。读码方式：tarball（`codeload`，git 协议当天不通）。

| | Thaw | DockDoor | LaunchNext |
| --- | --- | --- | --- |
| 是什么 | 菜单栏管理器（**Ice 的续作**，代码含 Ice © 2023–2025） | Dock 增强（预览＋切换器＋挂件） | Launchpad 替代（**建在 LaunchNow 上**，为 macOS Tahoe 删了 Launchpad 而生） |
| ★／推送 | 12,056／**10-14** | 6,352／10-11 | 3,103／10-05 |
| 体量 | 405 档／111,066 行 | 207 档／39,696 行 | 103 档／53,351 行 |
| 开放 issue | 47 | 65 | 150 |
| 签名公证 | ✓（＋OpenSSF Gold 徽章、可验证发布文档） | ✓ | ✓（自述 2.4.2 起；「会员只保一年，可能不续」） |

#### DockDoor——与我们正面撞车的那家

**表面**：Dock 预览（跨桌面／显示器／最小化／隐藏，**每张预览带关闭/最小化按钮**）、**Alt+Tab 全窗口切换器（可打字搜索）**、**Cmd+Tab 叠层**（系统切换器之上叠窗口）、**Folder Pop**（悬浮 Dock 文件夹→可排序文件列表）、**音乐挂件**（悬浮出声的 App→控制＋歌词）、紧凑列表/大预览两种布局、**设置可搜索**（`settingsSearchTarget`；新设定必须挂进索引，写进了他们的 AGENTS.md）、触控板 3/4 指滑开切换器、Parall 等第三方 Dock 的互操作。

**从它的 release 语言抄进我们坑表的三条**（都是真实世界踩过的）：

1. **"Stuck dock and preview clicks now recover on their own"**——macOS 会临时禁止 App 发输入，点击从此失效，**必须有自愈**。↔ 我们 R1（环境巡检、tap 静默停用后重开）正是这一族。
2. **"Window switcher no longer freezes when an app is slow to respond"／"no longer freezes after waking from sleep when an app is hung"**——挂起的 App 会拖死切换器与预览。↔ 我们已测「枚举每 App 一次阻塞调用 4.5–10.5ms」，切换器/预览路径要按同一约束审一遍。**机制补充（源码级）**：它的 `DockObserver`＝**AX 观察（`handleSelectedDockItemChangedNotification`）＋`healthCheckTimer` 周期巡检兜底**，`cmdTabObserver` 另配 `cmdTabPollingTimer`——**「通知为主＋巡检兜底」两层，与我们的 R1（环境巡检）同族**，第三次在竞品里见到同一模式。
3. **Parall 快捷方式实例的窗口身份分离**（"Apps launched from Parall shortcuts keep their windows apart"）——第三方启动器的窗口身份串了。↔ 归我们 R20（窗口身份边界）。

**我们的对位**：窗口浏览/看一眼（95 vs 它 60）大幅领先；**切换器已有**（⌥Tab、最近使用序、数字直选、⌘W/⌘Q、鼠标点、卡榫/刘海里的窗口也能召回——它没有），且**默认不碰系统 ⌘Tab**（它做叠层）。**缺**：打字搜索、预览上的窗口控制按钮、Cmd+Tab 叠层、触控板滑开、Folder Pop、音乐挂件。→ 候选任务 O1–O5。

#### LaunchNext——启动台格的对手

**表面**：**一键从原生 Launchpad 数据库导入**（`/private$(getconf DARWIN_USER_DIR)com.apple.dock.launchpad/db/db`，`SQLITE_OPEN_READONLY` 打开，认 `apps`／`items` 两代 schema）——README 第一条卖点；CA 文件夹编排全家（创建/溶解/玻璃/合并）；**壁纸子系统一等公民**（身份/帧稳定/航拍预览/**缓存预算**/渲染，每个都有测试）；模糊搜索＋键盘导航；**CLI/TUI**；热角与 4/5 指手势；拖到 Dock；右键（Finder 显示/拷贝路径/重命名文件夹/卸载）；更新页带 Markdown 说明。

**它的签名史就是我们的 C2 教科书**：买不起 $99 证书 → README 教用户 `sudo xattr -r -d com.apple.quarantine` 绕 Gatekeeper → 2.4.2 起签名＋公证，但直言「会员只保一年，可能不续」。**和我们现在的处境一字不差**——别人已经趟过这条路：买、签、公证，没有第二种体面做法。

**我们的对位**：启动台已有文件夹、背景、拼音（含小鹤）搜索、卸载（进废纸篓可找回）、从刘海长出、拖到半屏/侧拉。**缺**：原生数据库一键导入、CLI/TUI、文件夹的 CA 编排动画、热角与 4/5 指手势（我们有别的手势面）。→ 候选任务 O6–O8。

#### Thaw——菜单栏格：不进战场，但有三条硬账

**表面**：隐藏/常藏区、悬停/点击/滚动/滑动/热键唤出、自动复藏、**图标闪烁时自动露出**、分组与占位符、图标间距、搜索跳转、**Thaw Bar（给带刘海 MacBook 单独一条栏放隐藏项）**、外观全家（纯色/渐变/**壁纸自适应取色**/阴影/边线/自定义形状/每 Space 覆盖）、**Profiles**（绑显示器/Space/Focus、导入导出、脚本钩子）、**Triggers**（前台 App/网络/VPN/蓝牙/显示器/Focus/热压力/摄像头麦克风/脚本，AND-OR 组合）、**Zen 模式**（一键全隐＋锁手势；演示时可自动进入）、`ThawCtl` CLI、`MenuBarItemService` 助手进程。

**`FREQUENT_ISSUES.md` 是一页现成的真实世界坑表**（我们直接纳入知识库）；最有价值的五条：

- **macOS 把新状态项插在最左端**——管理器会把它当「隐藏区」；要用「New Items 徽章」定默认落点。
- **布局漂移的三个真实原因**：宿主 App **以新身份重启状态项**；**显示器拓扑变化**（插拔、唤醒、Sidecar、KVM）；改间距需要**重启宿主 App**（画面像图标在跳/复制）。
- **「不能排列自动隐藏的菜单栏」**——macOS 的硬限制，报错要能解释清楚而不是默默失败。
- **第三方兼容**：Little Snitch、CodexBar 的项不保存位置；Live Activities 与 iPhone 镜像有专门行为。
- **「图标抖动/跳动」**是这一类产品的招牌 bug 族，他们在 FAQ 里单列。

**Triggers 查证（2026-10-15）**：README 宣称的 Triggers（电池/网络/VPN/蓝牙/显示器/Focus/热压力/摄像头麦/脚本，AND-OR 组合）**在开源 main 分支里找不到任何实现**（全库搜 `thermalState`／`vpn`／`exitCode`／Trigger 条件枚举均为零）——可能只在付费或更新版本。**后来者不必再挖这份代码**；我们要做场景自动化时，条件面照 README 的清单列。

**工程姿态（比表面更值得抄）**：Keep-a-Changelog ＋ `release.yml` 把 tag 段落**自动写进 GitHub Release 与 Sparkle appcast**；**升级说明纪律**（「Five fixes from field reports against 2.0.0, **nothing new**」；「No schema or `defaults` changes. Profiles and saved layouts **carry over untouched**」）；**OpenSSF Best Practices Gold ＋ Scorecard ＋ 可验证发布文档**——供应链姿态是我们目前完全没有的一栏。

**我们的三条硬账**：① **不吃这个 scope**——菜单栏管理不进入产品（诚实记入「有意不做」，理由是定位与体量）；② **不打架**——Thaw/Ice/Bartender 会搬动菜单栏项、控间距，**我们的刘海与 NotchWatch 读菜单栏项的行为必须与它们共存**（互操作测试项 O9）；③ **可借的四样**：图标闪烁时露出（对照我们的静默提醒）、壁纸自适应取色（启动台背景/刘海着色）、升级说明与状态迁移纪律（O10，接 R33/R34）、发布自动化到 appcast（O10）。

#### 交叉结论

- 三家的共同点：**都解决过「系统暂时禁止你发输入」「挂起的 App 拖死你」这一类韧性题**——与我们 R1／R20 同族；DockDoor 的自愈条款可以当验收语言直接搬。
- 三家全部 GPL 系：**只借思路、不取码**（许可地图已定）。
- 与我们的重叠面排序：**DockDoor（直接撞车，切换器＋预览）＞ LaunchNext（启动台格）＞ Thaw（不进战场，只做互操作与纪律借取）**。
- 一句话记法：**学习 Thaw 的纪律、堵住 DockDoor 的格、补齐 LaunchNext 的导入**。

### VibeIsland（2026-10-15，Aaron 点名＋供件；AI Agent 的灵动岛）

**身份（本机量）**：v1.0.53，通用二进位 56.6 MB（arm64 切片 27.1 MB／`__TEXT` 24.9 MB），**`__LINKEDIT` 只有 1.0 MB——人家剥符号**；`flags=0x10000(runtime)`＋`accepted / Notarized Developer ID: Guorong Luo (CU3QC9CXTJ)`。**$19.99 买断（含一年更新）**、brew cask、免费试用。捆 Sentry（崩溃上报）＋Sparkle；`Helpers/vibe-island-bridge`（助手，同我们的 hook 形制）；NOTICE.txt 带第三方许可。

**机制（这家的真本事）**：

- **往每个 agent 的配置里装 hooks，并提供一个「statusline 链」**（`~/.vibe-island/bin/vibe-island-statusline-chain`）——借 Claude Code 的 statusline 功能回传状态，零配置的关键；README 级清单管到 `~/.claude/settings.json`／`agents/`／`plugins`、`~/.kimi/config.toml`、`~/.gjc`、`~/.hermes`、Codex 的 `/hooks` 等十几处。
- **`PermissionRequest` 代理＋`AskUserQuestion` 特判**：`postReply(/permission/{id}/reply)` 回 decision；选项题直接回 `answers`——「⌘1 Production ⌘2 Staging」就是这么答的。
- **零配置检测**：扫 `~/.gemini`／`~/.cursor`／`~/.factory` 等目录判断装了谁。
- **`usage-pricing.json`**：额度→费用换算表随包发；`community-config.json`：社区配置。
- **`RemoteAgent`**：为 SSH 远程监控**按平台下发 hook 二进位**（darwin-amd64/arm64、freebsd…带 sha256），远端装同一个 hook。
- **终端覆盖 20+**（二进位实测：Cursor／tmux／iTerm2／kitty／Ghostty／Warp／Terminal.app／Hyper／Windsurf／Zed／WezTerm／VSCode／Alacritty）；`highlight.min.js` 做 Markdown/差异高亮。30 家 agent 图标随包。
- **私有面几乎为零**：dlsym 串只有 **2 个 CGS 读**（`CGSIsScreenWatcherPresent`、`CGSSessionScreenIsLocked`）、静态呼叫点 8 个——它不管窗口，所以不需要。同口径呼叫轮廓：**2,707 函数／408,422 个 `bl`；AX 267、事件 61、屏幕录制 6、定时器 2**（AX 那 267 大概率为「跳回终端」找窗口用）。它比我们干净，**因为它的身位是 HUD，不是窗口管理器**。

**对位（谁强在哪）**：

| 维度 | 我们 | 它 |
| --- | --- | --- |
| 授权强度 | **更强**：Touch ID、风险分型（shell 不猜安全）、费用保险库（30s 票）、**故障返回无决定绝不自动 allow**、119 秒决策窗 | 键盘确认（⌘Y/⌘N） |
| 调度能力 | **更强**：模型四槽位／effort／ultracode 工作流／费用确认 | 只看不改（观+批+跳） |
| 窗口语义 | **独有**：收纳不打断（卷帘条/刘海）、窗口浏览、后续按项目成组 | 无（不管窗口） |
| agent 覆盖 | 只有 Claude Code hook＋Codex 额度 | **30 家** |
| 终端回跳 | **无** | **20+**（含 tmux） |
| 配置上手 | 只生成粘贴配置（**不静默写用户配置**） | 一键装 hook＋零配置检测 |
| 计划/差异 | 无 Markdown 渲染 | 有（带高亮） |
| 远程 | 有 `RemoteMode` 地基 | `RemoteAgent` 远端 hook 已发 |

**判词**：**它把「看」做满，我们该把「管」做满。** $19.99 买断反过来验证这格有人付钱；我们的差异路线写死在 spec §1.7——**看得到＋管得住＋授权更硬**。它的两个做法值得抄进候选：**statusline 链**（比装 hook 更轻的零配置入口）与**远端 hook 按平台下发＋sha256**（我们要做 SSH 时照此形制）。


### 新线索批（2026-10-15，Aaron 点名 12 项；逐项处置）

**Dockset（多套 Dock 布局＋自订 Dock 挂件）**：自称「Your Dock. Reimagined.」——保存/切换多套 Dock 布局（快捷键、双指滑、⌘+滚、随 Focus 切），或开一个带挂件的独立 Dock（天气/日历/提醒/正在播放/电池/快捷指令/AirDrop 投放区……）；$14.99 买断＋14 天退款；macOS 13+。**收购传闻：公开检索查无实据（官网正常在售）——按 Aaron 的信息记录，两条并存。** 官网范式单列一节（见[竞品官网](competitive-websites.md)§五）。**对我们的意义**：Dock 定制＋按场景切换是一个付费市场；我们的 Dock 手势面（`DockClickHide`／`DockHoverObserver`）与它相邻但不重叠，**记在册，不启动**。

**Dockset 补充（2026-10-15 字串面挖取；TSV 两次尝试均在分析阶段停滞、未产出）**：① **用 Apple Shortcuts 当自动化总线**——AppleScript 驱动 `Shortcuts Events.app`＋`/usr/bin/shortcuts`，用户用快捷指令切换 Dock 布局／挂件（要单独授权）。② 挂件全集（字串频次）：AirDrop×9／提醒×6／日历×5／天气×4／电池×3／便签×2／备忘录×2／计时器／快捷指令／倒计时。③ **损坏状态的文案范式**（可借）：「把读不出的文件备份一份、以空配置重新开始；备份留在 Dockset 文件夹里；**你的授权和当前 macOS Dock 都不动**」——报错时说清「我们保住了什么」。④ 一条帮助串把「Dock 切换的顺滑」与「录屏权限」绑在一起（`About smooth Dock switching and Screen Recording`）——它那边顺滑切换大概也吃录屏权限。

**launchbad-revived / BackToCatalina（把 Catalina 时代 UI 弄回来）**：两者都要**关 SIP ＋ 引导参数 ＋ 往系统注入 dylib**（ammonia／AMFI 绕过）——**我们不碰**（边界：不绕过保护措施、不改系统完整性）。但它们是**两份现成的市场证词**：Tahoe 砍掉 Launchpad 后，用户不惜关 SIP 也要把它弄回来——**我们的启动台正是接住这个缺口的产品形态**（不动系统、装上就能用）。另有两条公开技巧记入知识：`defaults write -g NSConvolutionOverride1 -float N` 调窗口圆角（4＝Catalina／9＝Sequoia／15＝Golden Gate，**要不要暴露给用户将来单独议，App 不替用户写全局 defaults**）。

**glance（jonnyoo，MIT，macOS 15+）**：**Mac 人脸解锁**——摄像头＋Core ML 在本地做人脸识别，UI 生在刘海；**README 用大段警告自曝安全边界**（Mac 没有深度传感器：挡得住打印照片，挡不住一段你的录像）。**对我们的意义**：它们的诚实文案是安全功能文案的范本；我们的 Vision 人面子系统（`VisionFaceEmbedder`／`FaceGestureTracker`）与它相邻——**人脸解锁列候选（安全敏感，要慎）**，先只借「把边界说清楚」的写法。

**loupe（mysk-research）**：iOS 设备指纹面教学 app，把信号**按获取成本分三档：Passive（不用授权就看得见）／Needs Permission（弹窗才给）／Advanced（公开 API 的侧信道）**。**直接可借给我们 R37 隐私声明与隐私页的三档呈现**（我们的隐私登记 66 条 `interfaces` 正需要这种一眼看懂的分级）。

**tendedero（截图晾衣绳）**：截图**自动挂到屏幕上沿一条线**，鼠标停到菜单栏就滑下来，移开就收回；"Out of sight. Within reach."；玻璃相框视觉。**对我们**：`FileShelfView`／`FileShelfStore` 已有架面，**没有的是「截图自动上架＋边缘唤出」这两下**——列 O12；文案范式（一句话，说用户遇到的事）可借。

**Peninsula（Celve，GPL-3.0）**：不是卷轴工具——是**刘海枢纽**：点刘海展开，五个面（当前屏 App 切换器／通知中心／**Tray（暂存与取回收文件）**／菜单／设置）。**Cmd-Tab 替换做全**（搬自 alt-tab-macos：按住走、⇧ 反向、Esc 退、松手选定）且**带搜索**（打窗口名→只留匹配→回车切）。**对我们的意义**：它是「刘海＋切换器＋暂存架」三合一的最紧凑形态，切两刀都在我们的格上（窗口切换器、文件架）；代码血统（alt-tab-macos／NotchDrop）已记入许可地图，只借思路。

**用量三件套（CodexBar／openusage／v2ex 帖）**：两家的**逐 provider 凭据来源**已抄下（见下表）；产品语言是「**围绕重置时间规划**——别在额度快重置时开长活」；openusage 还做了 local daily spend、Rate Limit Resets 倒计时（蓝>7天／黄<7天／红<48小时）。**v2ex 帖本机网络取不到**（红迪同）——记「取不到」，不装懂。

| provider | 凭据来源（顺序） | 指标 |
| --- | --- | --- |
| Claude | ① 系统钥匙串（Claude Code 维护）② `~/.claude/.credentials.json`（认 `$CLAUDE_CONFIG_DIR`）③ Claude Desktop 加密缓存 ④ `CLAUDE_CODE_OAUTH_TOKEN` | 5h 会话／7 天周窗／**`limits` 数组里的模型专属窗**／额外用量／**额度重置券（带到期色点）**／本地日花销 |
| Codex | Codex CLI 的登录文件（认 `$CODEX_HOME`，钥匙串兜底；兼容 xswap 多账号） | 5h／7 天／Spark 模型窗／**重置券**／flex 信用（$＋credits）／本地花销；plan id→名字映射（`prolite`→Pro 100 等，与官方桌面版核对过） |
| Z.ai（GLM） | API key：`~/.config/zai/key.json`／`ZAI_API_KEY`／`GLM_API_KEY` | 5h／7 天／**月网络搜索次数** |

**「本地优先、联网要显式同意」定案建议**：我们现在只吃 **Codex app-server 的本地推送**（`UsageReading` 的 `account/rateLimits/updated`）；若为 Claude/GLM 额度要我们**自己去发网络请求**（上述工具都是拿凭据直连 API），就与「纯本地、无网络」的产品承诺冲突——**建议：额度面默认只显示能本地拿到的东西；要接联网读数的 provider，做成显式开关（默认关，开关旁写清楚会连谁）**。归 A11。

**open-appleremote（Siri Remote 一代协议）**：Linux 上用一代 Siri Remote 的完整协议实现＋`docs/PROTOCOL.md`（触摸面、按键、tvOS 手势逐条）。**我们已有** `SiriRemoteButtons`（12 键：上下左右/选中/返回/电视/播放暂停/静音/音量±/侧边）＋`WS2CompanionChannel` 的 `appleRemote` 信封——**对照它的协议文档把覆盖面核准**，归 O13；只借协议知识（MIT）。

**CarPlay 三件套（LIVI／playport／DiPlay）**：**边界已定案且已在我们代码里**——`WS2CarPlaySession.swift` 的身分来源模型写着「**只有 Apple 签发的身份会被直连接受；提取出来的与用户自备的一律不进直连**」。DiPlay 的自述确认了那条红线：它「捆了一个从 Carlinkit 固件回收的实验性配件身份」且「不是 Apple 认证产品」——**那条路我们永久作废**；LIVI 证明正路要 MFi 认证（对一个窗口管理器不成比例）。**结论：CarPlay 只做接收端与隔离探针，不做配件伪造。**

**少數派《MacBook 刘海屏个人优化食用指南》（2025-03-25，热血星仔）**：用户端最佳方案＝**自处理壁纸＋Bartender＋Alcove**。三条可用的一手证词：① **「只有 Bartender 不会和刘海屏媒体控制类工具，在刘海处发生操控逻辑冲突」**——我们的 O9「不打架」有了用户侧证据，且**要测的不止 Thaw，还有 Bartender／Ice 与「刘海媒体工具」们的组合**；② Alcove 的好评点：**刘海双指左右切歌**、**接管亮度/音量 OSD**（替代系统中间弹框）、AirPods 专属动画——对照我们的媒体/音量面（我们走刘海胶囊）；③ 一个真实 bug：**外接 Dock＋USB DAC 时调音量触发音频故障，Alcove 与 NotchNook 都能稳定复现**——我们做音量面时要在「音频设备拓扑变化 × 音量键」上专门验一遍。

**取不到的（如实记）**：Reddit Alcove 1.2 帖、v2ex GLM/火山帖、X 的 Dimillian 帖——本机网络触达失败（红迪/推特为该站封禁，v2ex 与 GitHub git 协议同期的连通问题）。**不装懂，留待能取时补。**

#### 这批件的出货面相与私有面（2026-10-15，全部抓件、同口径量，arm64 切片）

九家全部抓下官方发布件（DMG／zip，`codeload`／release 直链；Dockset 取自官网 `downloads.benja.dev`）。**九家全部 `accepted / Notarized Developer ID`、全部 `flags=0x10000(runtime)`**——对照之下，我们是这批里唯一没公证的（C2）。

| App | 版本 | 二进位 | `__TEXT` | `__LINKEDIT` | 私有面（三镜） | 呼叫轮廓要点 |
| --- | --- | ---: | ---: | ---: | --- | --- |
| Thaw | 2.0.1 | 10,145,920 | 8,896,512 | 819,200 | **静态链 49 个 CGS 呼叫点**：`CGSMainConnectionID`×21、`CGSGetProcessMenuBarWindowList`、`CGSSpaceGetType`、`CGSGetScreenRectForWindow`… | AX 53／事件 160——菜单栏管理是重私有活 |
| CodexBar | 0.75.0 | 38,388,752 | 33,751,040 | 3,293,184 | **零**（干净） | 仅 5 处 AX；36 MB `__TEXT` 是这家最重的件 |
| Dockset | 0.2.7 | 30,542,928 | 8,781,824 | **21,348,352**（68%） | SkyLight 字串；dlsym `CGSMainConnectionID`／`CGSSessionScreenIsLocked` | 机制见下 |
| OpenUsage | 0.7.14 | 14,282,800 | 5,750,784 | 8,159,232 | dlsym `SLSIsScreenWatcherPresent`／`SLSRegisterNotifyProc`；**「屏幕录制 17」是 SCNetworkReachability 假阳性** | 0 AX／0 事件——纯菜单栏轮询 |
| DockDoor | 1.40.7 | 4,716,720 | 4,096,000 | 327,680 | 静态 CGS 19：**`CGSHWCaptureWindowList`**（与我们 dlsym 的同名）、`CGSCopyManagedDisplaySpaces`；dlsym `SLSMoveWindowsToManagedSpace`、`SLSWindowIsOrderedIn` | AX 136／观察者 33——跨桌面预览靠搬 Space |
| Peninsula | 0.1 | 3,441,936 | 2,654,208 | 524,288 | 零 | AX 41／观察者 6 |
| LaunchNext | 2.4.2 | 5,380,208 | 4,702,208 | 311,296 | **零** | 全零——自绘网格，不碰窗口 |
| Glance | 1.2 | 1,716,096 | 1,435,776 | 212,992 | **静态 SLS 六件套：`SLSSpaceCreate`／`SLSShowSpaces`／`SLSRemoveWindowsFromSpaces`／`SLSSpaceAddWindowsAndRemoveFromSpaces`／`SLSMainConnectionID`／`SLSSpaceSetAbsoluteLevel`**＋`CGSSessionScreenIsLocked` | AX 5／事件 35——**给解锁 UI 造一个专用 Space**（与我们的 `LockSpaceBridge` 同族技术） |
| Tendedero | 1.5.0 | 956,112 | 344,064 | 573,440 | 零 | 6,037 个 `bl`，全场最轻 |

**机制三条（值钱的）**：

- **Dockset 的多套 Dock = 改 `com.apple.dock` plist ＋ `killall` 重启 Dock**（二进制里 `/com.apple.Dock.agent`、`/usr/bin/killall`、`com.apple.dock` 三个串都在），Custom Dock 那半边是**自绘窗口**（26 个 NSWindow 类引用、3 个 NSPanel）。**不用私有 API 就能换 Dock 布局，代价是 Dock 整个重启一次**——记在册：若我们将来碰 Dock 定制，这是下限，不是范本。
- **Glance 在锁屏上画 UI 靠「造专用 Space」**——六件套 SLS 与我们 `LockSpaceBridge` 的做法同族（这条互相印证了双方的技术选型）。
- **Thaw 菜单栏管理是静私立链**（`CGSGetProcessMenuBarWindowList` 是枚举菜单栏项的关键 API）——**12.1k 星的开源头部也走私有面，且是静态链接**：这反过来把我们的 C1 定性钉死——**这类产品的行规就是用私有 API，差别只在隔离、登记与软失败**。

**未产出的记录（2026-10-15）**：Droppy 的 TSV **两次尝试均未产出**——第一次（旧 session）路径错；第二次（`analyzeHeadless` 直驱）跑了 **2h45m、CPU 全程满速 159 分钟**，日志停在中途再无推进。**判定：长阶段而非卡死**（CPU 一直是 100%），按预定的 2h45m 硬线收工。**留档给未来**：重跑 Droppy（51 MB）要给它 **4 小时以上**预算，且单机只跑它一份。Droppy 的情报现有来源：静态面／三镜私有面／呼叫轮廓／README（见上）。

**同批的两个反例（干净得刺眼）**：LaunchNext 与 Tendedero **零私有面**；CodexBar 零私有面＋零类目呼叫点。**「私有 API 是行规」不等于「人人都用」**——把话说准。

### Agently（2026-10-15，Aaron 点名；**Mac 件在申请制后面，本轮取不到成品**）

**先说取件实况**：`agently.dev/mac` → 307 → `/access`（Request access）——**成品只在审批后发放，我们没有绕**，所以本轮做的是**官网面＋定位面**分析；二进制分析留待 Aaron 拿到件。

**它是什么**：AI「公司总管」——从你在用的工具里学公司怎么运转（**100 个来源 → 一张实体图谱**，含**时间性事实**：事实带有效期、被覆盖的留作历史），然后干活（起草回复、催发票、推进交易）；**凡是有分量的动作都在闸门前等你批**。产品形态三种输出：**Pages**（带来源的成品文档）、**推回你的工具**（Stripe 暂停催收、Gmail 存草稿、Salesforce 改日期）、**Routines**（定时的问 → 页或动作）。定价：免费档＋ **Pro $99/月**（3,000 credits、10 应用、10GB「大脑」）。合规话术：GDPR/DPA、传输与静态加密、**绝不用你的数据训练**。

**与我们正面撞的那一块**：**「Agently for Mac」＝刘海里的小助手**——官网原话「**Ask out loud. Jarvis answers in the notch, and your workspace keeps up.**」；触发 `Hey, Jarvis` 或 ⌘⇧Space。**这就是我们 Conductor 的正对面**（我们已有：语音听写带不确定词、审批走 Touch ID、119 秒决策窗）。

**三句值得抄进我们叙事的话**：① 「**The agent is the commodity. The brain is the product**」（他们的战略论点——对我们是个好对照：**我们的论点是「窗口语义/控制面才是产品」**，两者可以并存写成一句话）；② 「**Waits at the gate**——有分量的动作**带着推理一起**押在闸门」（= 审批卡不只给动作，**还要给为什么**＋来源）；③ 一次运行的账：「**5 writes · 1 held** 09:02 → 09:04」（**写入与押下的对账**，我们的轨迹/节拍可以借这个形态）。

**对我们的两个直接推论**：① **审批卡升级**：审批时附「推理＋来源」（我们已有风险分型，加这一层）；② **MCP 反向**：它的「大脑」是 MCP 服务器、Mac 端是客户端——**我们可以把窗口管理做成 MCP 服务器**（agent 问「屏幕现在什么样」「把编辑器放左、浏览器放右」）＝「窗口管理器作为 agent 控制面」的最直接形态 → 立为 **A14**（见 spec）。

**边界**：它的价值大头在云（100 源图谱、$99/月）；我们**不上云**的承诺不动，只借「闸门带推理」「运行对账」「MCP 面」三样。

### TileMyMac（2026-10-15，Aaron 点名「非常强劲」；全套 REA 已跑）

**身份**：v0.2.0，macOS 13+，$5 首发（原价 $19.99，1 Mac）、Dodo Payments 收款、7 天退款；14 MB DMG；[官网](https://tilemymac.app)署名 **「Made by nerdynikhil · Built on Paneru (MIT)」**——**引擎来源主动署名**，许可合规做对了。

**签名实况（2026-10-15 本机量）**：app `flags=0x2(adhoc)`、`TeamIdentifier=not set`、`spctl` 判 **`rejected`**；**DMG 本身 `code object is not signed at all`**。下载页原文：「right-click → Open；若 macOS 说无法验证，去 系统设置›隐私与安全 点 Open Anyway。**TileMyMac is going through Apple's notarization right now**，这个一次性步骤很快会消失。」
→ **对 C2 的意义**：**付费竞品同样未公证**——我们的不是独一份的丑，是**没做完的活**；区别只是「正在做」与「还没做」（LaunchNext／DockDoor／Thaw／Dockset／CodexBar／OpenUsage 六家都已做完）。

**架构（切片实测）**：**薄壳 ＋ 引擎**。壳 `TileMyMac`（arm64 切片 4.9 MB，`__TEXT` 仅 1.3 MB；**AX 6／CGS 0／事件 0／观察者 0／私有面为零**）；引擎 `tym-engine`（切片 14 MB，`__TEXT` 9.8 MB；**就是 Paneru 0.5.2 (LuaJIT)**——改名、bundle id 改 `app.tilemymac.engine`；**直链 SkyLight**、AX 33／CGS 35／观察者 9；dlsym `SLSWindowIteratorGetCornerRadii` 读窗口圆角）。

**引擎能力面（字串级全表）**：① 架构＝ **daemon ＋ Unix socket ＋ 结构化状态查询 ＋ 事件订阅 ＋ `paneru.state` 脚本存储 ＋ LuaJIT 脚本**；CLI 可 install／uninstall／reinstall 后台服务、装/卸 App 启动器到 `~/Applications`。② **事件面（可当我们的事件清单对照表）**：WindowCreated/Destroyed/Focused/Minimized/Deminimized、SwipeVertical、ScrollTick、TouchpadDown/Up、**SpaceChanged**、DisplayAdded/Removed/Moved/Resized/Configured/Changed、**MissionControlShowAllWindows/ShowFrontWindows/ShowDesktop/Exit**、**DockDidChangePref/DockDidRestart**、**MenuOpened/MenuClosed、MenuBarHiddenChanged**、**SystemWoke**、ThemeChanged…… ③ **LayoutOp 全表**：shrink/fullscreen/follow/balance/stack_east/unstack_west/**toggle_tabbed_display**（窗口标签页化！）/虚拟工作区一族/`set_frame`/`set_width`/**`copy_rule`＋`match` 正则规则**/`mouse_restart`/`print_state`。

**壳层加值（字串级）**：LicenseSecureStorage（Dodo 密钥）、**Setup needs attention** 巡检、Accessibility 引导（含真实坑「**Accessibility needs turning off and on again**」——权限要关一次再开）、支持附件 `engine.log`（并声明「**你的密钥永远不会被附带**」——支持面隐私卫生）、Update、Canvas。快捷键：⌃⌥←/→ 换窗、⌃⌥⇧←/→ 移窗、⌃⌥R 改宽 ½→⅔→满、⌃⌥F 铺满、⌃⌥C 居中；可改 Option 或 ⌘⌥ 起手。

**网站策略**：/compare 教「**snapping vs tiling vs scrolling**」三分法（品类教育＋SEO 双收）；价格首屏直给；FAQ 直说公证进行中；页脚署名上游。

**对我们的意义**：① **卷轴格的价格锚**：$5 起、$19.99 常价；② **引擎免费（MIT）、卖的是壳**（设置/引导/支持/更新）——与 ChainYourMac 同一玩法，**付费的是包装**；我们的引擎是自己写的，这一点在「凭什么收费」的叙事里要讲清；③ 「Accessibility 关一次再开」进 §1.5 坑表；④ **Tabbed display 与 regex 窗口规则**是我们没有的两个能力（记候选）；⑤ 它的**事件面全表**可直接当我们的事件订阅对照清单（尤其 `MenuOpened`／`MenuBarHiddenChanged`／`DockDidRestart`／`SystemWoke` 这些我们还没订的）。⑥ `print_state`＋daemon 模式＝「可脚本化」的完整形态（我们的 WS2 有 socket 与状态，但对外脚本面没有）。

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

### Paneru 源码深读（MIT，Rust，2026-10-14）——卷轴跟手的完整配方

它是 ChainYourMac 的祖宗，也是跟我们「卷轴」那一格最接近的实现。**架构上它是 ECS**（`src/ecs/`：`layout.rs`、`scroll.rs`、`workspace.rs`、`restore.rs`、`triggers.rs`、`systems.rs`）＋ 一层 **Lua API**（`src/lua/`）——和我们 Swift controller 式是两条路。下面四条是**它把推理写在注释里**、可以直接搬的：

**1. 藏起来的工作区停在「显示器右下角内侧、留 10 px 细边」。**
```rust
/// Hiding a workspace parks its strip this many pixels inside the display's
/// bottom-right corner, which keeps a small sliver on screen: macOS reassigns a
/// window whose frame has left the display entirely to whichever display it landed on.
pub(crate) const PARKED_STRIP_SLIVER: i32 = 10;
```
**这条同时是「为什么」和「怎么做」**：不能把窗口整个移出屏幕，否则 macOS 会把它改派给另一台显示器。它和前面 AeroSpace 的 `hideInCorner`（`bottomRightCorner − onePixelOffset`）是**同一招的两个独立实现**，而且解掉的正是我们 [niri.md](niri.md):90 记的那条限制。

**2. 跟手的时间步长纪律——两个不同的时间基准。**
```rust
/// 积分用：一帧被阻塞的 AX 往返拖慢时，velocity * dt * viewport_width 会一步把卷轴
/// 撞到远端夹紧边界。所以「无论这一帧实际多久，每次更新最多推进一个 30fps 帧」。
const MAX_STEP_SECS: f64 = 1.0 / 30.0;
/// 求导用：追帧时 dt 趋近 0，gesture_delta / dt 会发散。所以给一个下限。
const MIN_STEP_SECS: f64 = 1.0 / 1000.0;
```
它还专门说明：`Time::<Virtual>` 给了 10 秒 `max_delta`，是为了让 `elapsed()` 在卡帧后仍跟得上墙钟（手指抬起超时依赖它）——**但那是错的积分上界**，所以两个用途用两个界。→ **对我们的直接意义**：我们的 AX 用量很大（508 处），「一帧被 blocking AX 往返拖慢」不是假想。

**3. 惯性用指数衰减，而且「故意不设上限」。**
```rust
if scroll.velocity.abs() > 0.001 {
    // Unbounded on purpose: decay is monotonic toward zero, so a long
    // frame can only shed more momentum, never overshoot.
    scroll.velocity *= (-decay_rate * dt).exp();
} else { scroll.velocity = 0.0; }
```
用户正在跟手时直接 `continue`（不叠加惯性）。这句「**故意不设上限，因为衰减单调、长帧只会多消耗动量不会过冲**」是我们「甩一下」（94 分）那一格没有记过的推理。

**4. 栏内高度用 `binpack_heights` 打包，装不下回退均分。**
在 `layout.rs`（2,779 行）：`/// The floor every window in a column is packed against. Heights that would starve a sibling below it make binpack_heights fall back to averaging.`——一列叠多扇时的高度分配算法。

### OmniWM 两份可以直接抄的东西（GPL-2.0，读码，2026-10-14）

**1. 一份 18 个案例的「窗口分类」测试夹具**（`Tests/OmniWMTests/Fixtures/WindowClassification/`）——**这是这一轮找到的最可直接照搬的东西**：

```
01-standard-window-managed            02-accessory-without-close-unmanaged
03-nonstandard-subrole-dialog-floating 04-missing-fullscreen-button-floating
05-user-rule-force-float              06-browser-pip-unmanaged
07-user-rule-initial-niri-container-primary-span
08-chrome-parented-popup-unmanaged    09-chrome-parented-toolbar-unmanaged
10-chrome-help-tag-unmanaged          11-droppy-accessory-overlay-unmanaged
12-notchy-notch-overlay-unmanaged     13-loginwindow-lock-shield-unmanaged
14-root-floating-utility-managed      15-finder-quick-look-managed
16-word-search-toolbar-unmanaged      17-firefox-156-pip-unmanaged
18-firefox-157-pip-unmanaged
```

观察：每个案例一个 JSON 夹具，命名就写明**期望分类**（`managed`／`float`／`unmanaged`）；覆盖的边界包括 **PiP（Chrome／Firefox，还按 156／157 分版本）**、Chrome 的弹窗／工具条／帮助标签、**别的刘海 App 的浮层（Droppy、Notchy）**、登录窗口的锁屏遮蔽层、Finder 快速查看、Word 的搜索工具条、缺全屏按钮的窗口、accessory 无关闭按钮。
→ 对我们的意义：我们收窗口、做窗口浏览，**必须回答「哪些窗口该管、哪些该浮动、哪些根本别碰」**——这份夹具把**该问的问题**和**期望答案**都列好了；而且它第 11／12 条说明**竞品之间互相把对方当作要避开的浮层**。

**2. 它自己的「岛」子系统**（`Sources/OmniWM/Core/Shell/ShellIsland*.swift`）：`ShellIsland`／`ShellIslandConfig`／`ShellIslandConfigWriter`／`ShellIslandData`／**`ShellIslandDragMonitor`**／`ShellIslandDragState`／`ShellIslandLayout`。
- 岛的内容是**声明式 widget 命令流**：`add(widget:options:)`／`remove(id:)`／`move(id:index:)`／`enable(id:value:)`／`set(id:key:value:)`／`rootSetting(key:value:)`，回报 `components`／`rootSetting` 变更——与它的 Luau shell 一套。
- **拖放是状态机**：拖拽类型 `.file/.url/.text/.image`、状态 `dragged/began/ended`，并且**批量投递**（`batch.dragged=…`）＋ 唤醒（`wake`）。

→ 一位 GPL 的开源竞品，**把自己的「岛」也做成了可编程表面**，和我们从 DynamicLake 看到的是同一个方向（宿主拥有形状、内容方填槽），只是它用 Luau 而非 ExtensionKit。

### 补读的四家（2026-10-14 第二批）

**Paneru（MIT，Rust，2.4k★）——我们文件里那条「未核实」现在核实了。** [niri.md](niri.md):18 记「Paneru 要求打开『显示器具有单独空间』」，这一轮读到它 README 的原文，而且它**自己解释了那条限制的成因**：

> 「Paneru is moving the windows off-screen, hiding them to the left or right… when MacOS notices a window being moved too far off-screen it will relocate it to a different display – which confuses Paneru! The solution is to change the spatial arrangement of your additional display.」

观察：**把窗口移出屏幕、被 macOS 挪到别的显示器**——这正是我们 [niri.md](niri.md):90 记为限制的那件事，现在有被授权者自己的一手说明。它的解法是**要求用户改显示器空间排布**（而我们走的是「露一条边」）。**未核实 → 已核实。**

**OmniWM（`OmniNull/OmniWM`，GPL-2.0，3.3k★）——这一家把工程成熟度做成了可抄的清单。** 它不只是功能多，**它的工程基础设施值得逐条看**（读自仓库与 README，观察）：

- **`Core/Ax/` 把 AX 层拆到极细**：`AXWindowEnumeration`／`+Constraints`／`+Facts`／`+FrameWrites`／`+Fullscreen`／`+Geometry`／`+Minimization`／`AppAXContext+WindowDispatch`／`+WindowIdentity`，另有 **`AXStopWindowRestoration`**（专门处理「阻止系统恢复窗口」）。对照我们：`prototype/Window/AXWindow.swift` 一个文件装完。**这是一条可以直接学的分层。**
- **自研 ARC 稽核器**：`Scripts/arc-audit.sh` ＋ `arc-audit/ArcAudit.swift` ＋ `Counters.c/h`——**查循环引用**。
- **能耗剖析**：`Scripts/energy-profile.sh`。
- **完整 CI/CD**：`.github/workflows/` 的 `ci.yml`／`release.yml`／**`canary.yml`（金丝雀通道）**／`website.yml`。
- **IPC 契约用 codegen**：`Scripts/generate_ipc_wire.py`——线协议由脚本生成，不手写。
- **对外 disclose 私有 API**：README 原文「OmniWM uses **public frameworks and selected Apple private APIs** for window management and visual surfaces」——**公开声明**使用了哪些层面。
- **IPC 预设关闭**（「IPC is disabled by default. Enable IPC from the menu bar」）。
- **刘海处理有具名模式**：workspace bar 的 `workspaceBar.notchMode = "rightOfNotch"`——无刘海的屏幕居中、有刘海的**放在刘海右侧 8 点**（`8 points to the right of the notch`），可加横纵偏移。
- **可换壳的 Luau shell**：bar 由 `~/.config/omniwm/shell/` 的 Luau widget 画，自带四种样式（Wayline／Nocturne／Celestial／System）与十二套配色；**Effects Lab** 带 Metal 光照、reveal mask、blur 与 glass 材质。
- README 还写明：**Developer ID-signed and Apple-notarized**、**GPL-2.0-only**、**没有订阅／功能墙／试用限制**。

**PaperWM.spoon（MIT，`mogenson/PaperWM.spoon`）**：许可从「未记」变成 **MIT**（Tiled scrollable window manager for MacOS）。按我们的分级属「可借代码（带署名）」那一档。

**DockDoor 的许可：GitHub 判 `NOASSERTION` 是判错了，实际是 GPL-3.0。** 它的 LICENSE 在 GPLv3 正文前加了自己的标题行（`DockDoor - macOS Dock window preview and switcher / Copyright (C) 2024 ejbills`），识别器没对上；README 第 171 行明写「licensed under the GNU General Public License v3.0」，正文就是 GPLv3。→ **处理仍然是「只借思路、不取码」，但理由更强了：GPL-3.0 是传染性 copyleft，取码会波及整个工程。** 附带一条教训：**不要把 GitHub 的许可标签当结论，要读 LICENSE 与 README 原文。**（同一轮把 Paneru 核成 MIT、2,380★，OmniWM 核成 GPL-2.0、3,335★、最近一次推送就是今天。）

### DockDoor 源码深读（GPL-3.0，Swift，6.3k★，2026-10-14）——一份「长期在野外跑」的自愈清单

DockDoor 跟我们做的事最像（Dock 悬停看窗口、窗口浏览、实时预览、标题栏手势），而且是这批开源里唯一一个**把「装上去跑几个月也不坏」直接写进代码**的。它的 know-how 不在功能，在**失效检测与自愈**——这一块正好是 [production-maturity.md](production-maturity.md) 里 A 组「自愈」那条最缺料的地方。

**1. 事件投递金丝雀（canary）。** `postingCanarySubtype = 0x0D0D`。做法：造一个 `.applicationDefined` 的 `NSEvent`，用 `postToPid(getpid())` **投给自己**，本地监视器收到就证明「我们还发得出事件」；连续两次没回来就把 `canPostEvents` 置 false，**拆掉并重建每一个 observer 与 tap**（`(NSApp.delegate as? AppDelegate)?.recoverObserversAndTaps()`）。而且**只在「上次金丝雀之后有过 HID 输入」时才发**——用 `IOHIDSystem` 的 `HIDIdleTime` 判断空闲，空闲时不打扰。

观察：我们已经有 `tapDisabledByTimeout` / `tapDisabledByUserInput` 的重开（`GlobalInputFilter`、`ScrollTap`、`WindowSwitcher`、`TrackpadGestures`、`NotchLevelObserver` 五处），**但那是被动等系统告诉我们**。金丝雀是**主动探**，覆盖「系统不再送我们的合成事件、却也不报错」这一类。我们目前没有。

**2. 5 秒看门狗，一次查五件事**（`performHealthCheck`）：AX 权限被重新授予（`AXIsProcessTrusted()`）→ 提示重启；Dock 进程换了 pid → 全量 `reset()`；**订阅的 AX 元素失效**（`invalidUIElement` / `cannotComplete`）→ 全量 `reset()`，原文注释写着理由：「If the dock rebuilds its UI, the element becomes invalid and notifications stop」；订阅的元素对象换了（`!CFEqual`）→ `reset()`；**`CGEvent.tapIsEnabled(tap:)` 为假 → 重建 tap**。

观察：**我们 grep 不到 `tapIsEnabled`**——我们的 tap 只在收到 `tapDisabledBy*` 时重开。**tap 若在没有该事件的情况下死掉，我们不查。** 这是可以直接补的一条。

**3. 标题栏高度从关闭按钮推出来。** `windowFrame.maxY − closeButtonFrame.minY + 12`，夹在 `[48, 72]`；取不到关闭按钮就用 48。**整个标题栏矩形缓存 1.0 秒**（`titleBarCacheMaxAge`），过期才在主队列上刷新一次——因为 AX 往返贵，而滚轮事件很密。

观察：我们走的是另一条路——按 App 记常数（`titleBarHeight 28` / `classicTitleBarHeight 24` / `proxyTitleBarHeight 34` / `quickLookOriginalTitleBarHeight 38`，加 `fixedNonstandardChromeHeight(pid:)` 的逐 App 表），**准，但没见过的 App 得加常数**。它那条是**推出来的、自动适配**。两条互补，值得把「推」做成常数表没命中时的回退。

**4. 滚轮手势的四道闸**：`minimumTitleBarScrollDelta = 0.15`（太小不算）；**`scrollWheelEventMomentumPhase != 0` 直接丢**（手指离开后的惯性尾巴不算手势）；`titleBarScrollActionDebounceInterval = 0.35`；**`NSEvent(cgEvent:).isDirectionInvertedFromDevice` 翻正**（自然滚动两种方向都要对）。

观察：惯性相位与自然滚动我们多处已经处理（`GlobalInputFilter.swift:132`、`Notch.swift:5518`、`LaunchpadView.swift:639`）。**我们缺的是「读数最小步长」这一道**——它挡掉的是「手搭在触控板上轻微滚一下」的误触发，和 Wins 3.3／3.5.1 反复修的那个「拖动误触发」是同一类。

**5. 「同一动作再按一次 = 还原」带过期时间。** `pendingTitleBarRestoreState` 记住原 frame 与一个 `expirationDate`；**同一个窗口 ＋ 同一个动作 ＋ 没过期**，就把 frame 设回去、清掉状态。

观察：这正是 R07「暂时取消全部置顶／再按恢复」要的「再按一次回去」，而**带过期时间**比单纯的 toggle 稳——用户半小时后再按不会把窗口弹回半小时前的位置。

**6. 原生标签页合并（`NativeTabGrouping`）。** macOS 原生标签页（Finder、终端、Ghostty、Safari）在 AX 里**每个标签都是一扇独立窗口**，而且**没有任何 AX 属性能查从属关系**。它的判据：**同一个 pid ＋ 取整后完全相同的 frame** → 同一组；**在屏幕上的成员一律保留**（它们是实实在在的不同窗口），屏幕外的每组只留「最近访问」的那一个（并列时取大的 `CGWindowID`，保证结果与输入顺序无关）；不可归组的（最小化／隐藏／无窗口 App／零尺寸）永不合并。整个判据被抽成一个**不依赖 AX 与 AppKit 的纯函数**（`representativeIDs(from:)`），好测。

观察：我们的窗口浏览没有这一层——**一扇开了 5 个标签的终端窗口会出 5 条**。这可能是我们和 DockDoor 在「窗口浏览」上最直观的一处差距，而且是纯逻辑、不需要任何私有 API。

**7. 它的私有面清单（`PrivateApis.swift`）——我们记下来但不用。** 文件头第一行就写着出处：「Borrows from: https://github.com/lwouis/alt-tab-macos」，一手可查的谱系。清单：`_AXUIElementGetWindow`；**`_AXUIElementCreateWithRemoteToken`（暴力枚举 AX 看不见的窗口）**；`CGSHWCaptureWindowList`；**`CGSCopySpacesForWindows` / `CGSCopyManagedDisplaySpaces`（窗口属于哪个 Space、每块屏当前是哪个 Space）**；`CGSGetWindowLevel`；`CGSCopyWindowProperty`；`_SLPSSetFrontProcessWithOptions` / `SLPSPostEventRecordTo`（**把焦点给某扇窗但不切换 App**）；**`SLSMoveWindowsToManagedSpace`——走 `SLSBridgedMoveWindowsToManagedSpaceOperation` 把窗口搬去另一个 Space**；`CoreDockGetOrientationAndPinning` / `CoreDockSetAutoHideEnabled` / `CoreDockGetAutoHideEnabled` / `CoreDockIsMagnificationEnabled`。

→ 对我们是**只记不用**。我们现在的公开面（ScreenCaptureKit ＋ `CGWindowListCopyWindowInfo` ＋ AX ＋ 通知）够用；「把窗口搬去另一个 Space」与「暴力枚举」属于我们刻意没走的路（[competitors.md](competitors.md):101 的界线）。但「**不切 App 只把焦点给某扇窗**」这一条值得记一笔—— [niri.md](niri.md):82 的卷轴概览要求「面板不激活 WindowShade，前台 App 不变」，是同一个问题的另一面。

**8. 显示器身份用硬件 UUID，不用 displayID。** `NSScreen.uniqueIdentifier()` 走 `CGDisplayCreateUUIDFromDisplayID`，注释写明理由：**「CGDirectDisplayID is reassigned across reboots」**；另有 `legacyIdentifier()`（分辨率＋位深＋色彩空间的拼串）和 `migrateScreenIdentifier()` 把按旧格式存的键迁到新格式。

观察：我们 `NotchSpaceGate.swift:174` 已经用 `CGDisplayCreateUUIDFromDisplayID`。值得照这条**过一遍所有「按显示器落盘」的键**：键必须是 UUID，而且要有迁移路径。

**9. 新窗口的探测重试表。** `createdWindowRetryDelays = [0, 100ms, 250ms, 500ms, 1s]`，每一步先查缓存、再查 CG 候选，命中就退；并用 `createdWindowsInFlight` 去重，避免同一个 AX 元素并发登记。进门前还有一道：`!AXResponsiveness.isUnresponsive(pid)`（**先问一句这个 App 是不是已经卡住了**）。

观察：我们有 `forwardedTrafficRetryDelays = [0.035, 0.08, 0.14, 0.24, 0.40, 0.65]` 与 `journalRescueRetryInterval = 30`，思路一致。「窗口刚建出来时 CG 候选还没就绪、必须重试」这一条可以照它核对我们的新窗口路径。熔断层层面上，我们的 `AXWindow.swift:310/324` 是**按调用计**（更细），它是**进门前预判**（更便宜）——两条可以并存：**熔断在调用层，预判在进门前。**

**10. 事件 tap 有专属线程与 runloop（`EventTapThread`）。** 一个 `qualityOfService = .userInteractive` 的独立 `Thread` ＋ 它自己的 `CFRunLoop`，tap 的 source 装在它上面；拆的顺序是「先 `tapEnable(false)`，再 `CFRunLoopPerformBlock` 到那个 runloop 上移除 source ＋ `CFMachPortInvalidate` ＋ 清理，然后 `CFRunLoopWakeUp`」。

观察：**主 runloop 被长任务挡住 → tap 回调超时 → 系统停掉 tap**，这是 tap 莫名失效的头号原因。我们的 tap 装在哪需要核（`WindowShade.swift:977` 只是 `tapEnable`）。这条与第 2 条是同一个问题的两头：**装在不会被挡的 runloop 上，并且定期巡检。**

**11. 按 pid 分区的缓存 ＋ 抑制「深度计数」＋ 批量发布（`SpaceWindowCacheManager`）。** `withCoordinatorNotificationsSuppressed(pid:)` 用的是**深度计数**而不是布尔——嵌套调用不会因为内层先结束就提前放行；增删改先入队，**一个主队列 flush 合并**，并区分 removed/added/updated 三类，靠 `oldWindow != newWindow || oldWindow.viewSnapshot != newWindow.viewSnapshot` 判「真的变了」。

观察：我们侧栏与面板的重绘同样怕「一次操作掀出一串重绘」。**深度计数比布尔干净**，可以直接借这一层的形状。

**12. 窗口顺序落盘（`WindowOrderPersistence`）。** 按 **`bundleIdentifier|窗口标题`** 存 `lastAccessedTime` / `creationTime`，最多 500 条，同键取最近一次，退出时保存。

观察：对应我们 R07「回来时前后顺序不乱」。**它的键是「App ＋ 标题」，不是 windowID**——windowID 跨启动没有意义。这是一个容易踩的坑，值得照抄键的形状。

**13. 按 pid 限并发**（`LimitedConcurrency.map(items, maxConcurrent:)`，三个变体：抛错版／丢弃结果版／继续跑版）。对应我们 [niri.md](niri.md):46「挪窗口放在每个 App 各自的后台队列上」——我们的队列是有的，这一条只是形状上的对照。

**14. 它跟我们的差距不在机制，在「巡检」。** 上面 1–2、10 三条合起来是一个完整的命题：**长驻的窗口管理器必须有一套周期性的自我体检**，而不只是「被动等系统报错」。这是这一轮从开源码里拿到的最大一条，也是 [production-maturity.md](production-maturity.md) A 组「自愈」那条的具体形状。

### PaperWM.spoon 源码深读（MIT，Lua，Hammerspoon，2026-10-14）——同一堵墙的第三份第一手证词

**它的 README 直接把那堵墙写成了产品事实。** 原文（「Limitations」一节）：

> 「MacOS does not allow a window to be moved fully off-screen. Windows that would be tiled off-screen are placed in a margin on the left and right edge of the screen. They are still visible and clickable.」
> 「Arrange screens vertically to prevent windows from bleeding into other screens.」

观察：**这是第三份独立的第一手证词**。Paneru 说「移出太远会被搬去别的显示器，所以请改显示器空间排布」；PaperWM 说「macOS 不让窗口完全离开屏幕，我们把它们停在左右边缘的一条边距里，仍可见、仍可点」＋「把屏幕竖着排」；我们在 [niri.md](niri.md):90 记的是同一件事、答案是「露一条边」。**三家在这个点上收敛，而给出的缓解各不相同**——Paneru：屏幕角内侧 10 点；PaperWM：左右边缘 `screen_margin = 1` 的边距；AeroSpace：右下角外的一像素；我们：露一条边。**这一格以后可以直接引用三份一手材料，不必再靠推理。**

**新窗口「还没有 Space」——一份把时序讲清楚的第一手笔记。** `events.lua` 的注释原文：

> 「When a new window is created, We first get a windowVisible event but without a Space. Next we receive a windowFocused event for the window, but this also sometimes lacks a Space. Our approach is to store the window pending a Space in the `pending_window` variable and set a timer to try to add the window again later.」

做法：`windowVisible` 拿不到 Space 就存进 `pending_window`，`Timer.doAfter(Window.animationDuration, …)` 重来一次；`windowFocused` 若发现这扇窗就是 `pending_window`，同样**延后一个动画时长**再处理；并且**已经处理过的 `prev_focused_window` 再收到 `windowFocused` 直接忽略**（防回声）。

观察：卷轴「新窗口接在当前列右边」会撞上同一组时序。**这份注释的价值是它把三种到达顺序都点名了**：有号无 Space、聚焦时也无 Space、聚焦回声。可以照它写验收用例。

**自己动窗口那一下，要先把监听停掉。** `Windows.moveWindow`：

```lua
Windows.PaperWM.state.uiWatcherStop(id)
window:setFrame(frame)
Timer.doAfter(Window.animationDuration + padding, function()  -- padding = 0.02
    Windows.PaperWM.state.uiWatcherStart(id)
end)
```

注释写着 padding 的来由：「greater than 0.017 hs.window animation step time」。

观察：这就是「我们的写被我们自己的 `AXWindowMoved` 监听收回来、再触发一次重排」的自激环。**我们侧栏与 `FoldTransaction` 的写路径要对一遍**：应该是「写之前停听、写之后等一个动画时长再开听」，而不是靠比较 frame 去重。

**跟手滑动时怎么做（`slide_windows` 协程，BEGIN / MOVED / END）。** BEGIN 时**一次性缓存**所有窗口对象、frame 和「虚拟 x」（注释：「window lookup is expensive」），并**停掉每个窗口的 UI 监听**；MOVED 时只调 `setTopLeft`（注释：「avoid the animationDuration」），位置是 `clamp(virtual_x, left_margin − w, right_margin)`（**允许整扇滑到左边缘之外**，因为停靠靠的是 Space 而不是屏幕）；END 时**重新打开监听**，然后**确保有一扇「完全在屏幕上」的窗口是焦点**——焦点窗已经跑出屏幕，就按方向找最近的可见窗口并聚焦（聚焦会触发重排），否则原地重排。`getFirstVisibleWindow` 的判据也很干净：**先找「完全在屏幕上」的最近的**（`d = frame.x − screen.x ≥ 0`），找不到才退回屏幕外离屏幕最近的那一扇。

观察：对照我们 [niri.md](niri.md):46 的做法（「挪窗口放在每个 App 各自的后台队列上，慢 App 跟不上时跳过中间几帧，不拖慢手指」）——**目标一致（滑动期间只做最小动作），它多两点**：(a) 滑动期间**主动停听**自己的移动事件；(b) END 时**保证焦点落在可见窗口上**。

**另五件可记的小事**：

- `Config.window_filter`：**声明式地定义「哪些窗口归我管」**——`visible = true, fullscreen = false, hasTitlebar = true, allowRoles = "AXStandardWindow"`。与 OmniWM 的 18 个夹具是同一件事的两种写法（一个正面声明，一个反例清单）。
- `Config.window_ratios = { 0.23607, 0.38195, 0.61804 }`——**黄金比的三个共轭**，所以「大一级／小一级」每一步的倍率是常数、手感一致。我们是 ⅓ ½ ⅔ 整屏（不全等比）。属**手感层面**的可选改法。
- `Config.accordion_peek = 36`、`stack_min_height = 150`：堆叠列里每个标题栏露出的高度、以及共享高度的下限。
- `tileStackedColumn` 的注释：**「raising the active window makes it its app's main window, which steals focus when the app is frontmost」**，并且「apps may also refuse requested frames (minimum sizes), so achieved frames can never be trusted to settle」→ 所以它用 `stack_signature`（活动行 ＋ 成员 id 的拼串）**只在组成变化时重排 z 序**。
  → 对我们的层序有意义：**raise 会抢焦点**，所以「重排层序」必须由「组成变了」驱动，不能由「重排发生了」驱动。
- `update_virtual_positions`：**把「应该在哪」（模型）与「实际在哪」（App 可能拒绝）分开存**。这正是我们卷轴里「App 不肯缩到要的大小时怎么办」的那一层。

### 这一格的整体结论（策略层）

**卷轴／平铺这一格的 know-how 是免费可读的。** 十二家以上里只有 **ChainYourMac** 闭源，而它建在 MIT 的 Paneru 上（bundle id `com.ahmedgagan.paneru`）；其余（niri GPL-3.0／OmniWM GPL-2.0／AeroSpace MIT／Paneru MIT／PaperWM.spoon MIT／Rectangle／DockDoor／bobrwm MIT／Glide Apache-2.0／parket MIT／TrimWM MIT／Yashiki MIT／Nehir GPL-2.0／komorebi-for-mac）**都能读源码**。**闭源集中的是刘海的 HUD 那一格。**

## 五、量自己（C 线）

**本节 2026-10-15 上午整节重写。** 三件事：① 旧版开头「REA 在这台机器上还没有真正跑通」已作废（通路在 10-15 凌晨打通，技术史压缩在 5.6）；② 用同一套管線把**出货面（对九家竞品，十家同口径）→ 呼叫面（两个口径）→ 源码面**量齐；③ **量出来的第一条就把我们自己以前写的话推翻了**——见 C1。

### 5.1 三个样品

| 样品 | 路径 | 二进位 sha256 | 说明 |
| --- | --- | --- | --- |
| **1.0.16 候选包（主角）** | `.build/duo-validation/WindowShade.app` | `fc311f07…` | 1.0.16(16)，Oct 14 18:22；`Apple Development` 签名 |
| 9/22 旧包（对照） | `prototype/WindowShade.app` | `e2e666ce…` | 1.0.15 之前；旧的「量自己」用的就是它 |
| 源码树 | `prototype/` | — | 516 檔 / 150,402 行（9/22 时是 94 檔 / 33,352 行） |

（另有一个 `.build/duo-validation/windowshade` 裸二进位：adhoc linker-signed、与包内主程序同符号集——构建残渣，见 C9。）

### 5.2 出货面相：我们 vs 九家（2026-10-15 现测，arm64 切片）

| App | 二进位 | `__TEXT` | `__LINKEDIT` | hardened runtime | Gatekeeper |
| --- | ---: | ---: | ---: | :---: | --- |
| **WindowShade 1.0.16** | **19,794,624** | **12,386,304** | **6,619,136** | **✗** | **rejected** |
| Notchy | 112,004,784 | 39,928,832 | 70,041,600 | ✓ | accepted |
| MediaMate | 6,928,576 | 5,521,408 | 950,272 | ✓ | accepted |
| Alcove | 6,680,912 | 5,799,936 | 491,520 | ✓ | accepted |
| ChainYourMac | 5,103,824 | 1,540,096 | 3,473,408 | ✓ | accepted |
| WindowMizer | 4,828,592 | 4,276,224 | 262,144 | ✓ | accepted |
| LaunchOS | 4,243,728 | 3,538,944 | 442,368 | ✓ | accepted |
| Wins | 2,965,088 | 2,506,752 | 229,376 | ✓ | accepted |
| Swish | 1,521,312 | 1,163,264 | 196,608 | ✓ | accepted |
| Droppy | 51,588,224 | 47,497,216 | 1,490,944 | ✓ | accepted |

（Droppy 与 ChainYourMac 本就 arm64-only；其余七家为 thin arm64 切片。Gatekeeper 判定与 runtime 标志为同日 `spctl`／`codesign` 现测。）

三行结论：

- **Gatekeeper 这一列，九家里只有我们是 `rejected`。** 其余全部 `accepted / source=Notarized Developer ID`。
- **`__TEXT` 12.4 MB：十家里第三大，也是常规件里最大的**（比我们大的只有 Notchy 39.9 MB／Droppy 47.5 MB；次大的常规件是 Alcove 5.8 MB——我们是它的 2.1 倍）。原因见 C5／C6，不神秘：三周内源码涨 4.5×，且验收探针整副入库。
- **`__LINKEDIT` 6.6 MB：不是唯一一家胖的**（ChainYourMac 3.5 MB，占比更高），但多数在 0.2–1 MB——我们是最大的一份，且成因明确可修（C4）。

### 5.3 呼叫面：两个口径都要看（这次量出来的方法学升级）

**口径 A：静态呼叫点**（`/tmp/ws-research/xref/profile.py`，数 `bl` 指令到符号桩）：

| 面 | **我们 1.0.16** | 我们 9/22 | Alcove | MediaMate | Notchy |
| --- | ---: | ---: | ---: | ---: | ---: |
| AX（辅助功能） | **1175** | 508 | 13 | 3 | 339 |
| CGWindowServer 私有（静态） | 2（皆读） | 1 | 33 | 2 | 37 |
| CoreDock 私有（静态） | 0 | 0 | 0 | 0 | 0 |
| DisplayServices 私有（静态） | 0 | 0 | 24 | 9 | 0 |
| 定时器/轮询 | 12 | 4 | 2 | 1 | 12 |
| 观察者 | 24 | 20 | 0 | 1 | 38 |
| 显示链路（CVDisplayLink） | 0 | 0 | 0 | 0 | 0 |
| 事件（CGEvent…） | 478 | 118 | 11 | 5 | 119 |
| 蓝牙 | 0 | 0 | 0 | 0 | 0 |

**口径 B：运行时载入的私有面**（dlopen／dlsym——**符号表和口径 A 都看不见**；dlsym 的名字必须以字符串形式存在于二进制，所以剥离与否都量得到）。**加上静态链，一共三镜**，单看任何一镜都会得出错的排名（例：Alcove 在镜 A 有 33、镜 B 是 0、镜 C 有两家私有框架；Wins 镜 A 干净、镜 C 静态链着 SkyLight）：

| App | 私有框架路径 | 唯一 SLS API 名 | 其他运行时载入的私有符号 |
| --- | ---: | ---: | --- |
| **WindowShade 1.0.16** | **6** | **17** | DisplayServicesGet/SetBrightness、KeyboardBrightnessClient、CoreDockSendNotification、SACLockScreenImmediate、responsibility_get_pid_responsible_for_pid、CGSHWCaptureWindowList、CGSMainConnectionID、_CGSDefaultConnection、CGPostMouseEvent、CGWindowListCreateImage(FromArray) |
| Notchy | 9 | 8 | DisplayServices×2、KeyboardBrightnessClient、SACLockScreenImmediate、responsibility_get_pid…、CGSMainConnectionID |
| Droppy | 13 | 8 | 同上子集 |
| Wins | 0 | 1 | — |
| Alcove | 3 | 0 | （不用 dlsym：**静态链**私有框架，口径 A 的 33 个呼叫点就是它） |
| LaunchOS／MediaMate／Swish／WindowMizer／ChainYourMac | 0 | 0 | — |

读法三条：

- **三镜合起来读**：Alcove 静态 33／运行时 1／静态链 DisplayServices＋MediaRemote；我们静态 2／运行时最全（17 个 SLS 名＋整组私有符号）／静态链无（全走 dlsym）；Notchy 静态 37／运行时 16；Wins 静态干净但**静态链着 SkyLight**。
  **镜 C（静态链私有框架，`otool -L` → `PrivateFrameworks/`）**：Alcove＝DisplayServices＋MediaRemote；MediaMate＝CoreBrightness＋DisplayServices＋MediaRemote；Wins＝SkyLight；**我们＝无**。
- **我们在 AX 上下的注是全场最大的一笔**（1175 个调用点，约是 Alcove 的 90 倍）——「用公开 API 换正确性」不是口号，是这行数字。
- 我们 9/22 → 10/14 之间 **AX 翻倍、事件 4 倍**——功能洪峰主要落在这两个面上，与 5.2 的体积增长同源。

方法学三条（写在这里，免得下次又比错）：

- **`nm`／`bl` 都看不见 dlsym。** 我差点据此写下「DisplayServices 用法证伪」——查源码才发现 `App/NotchLevelObserver.swift:89` 用 `dlopen`＋`dlsym` 载入（[scorecard](scorecard.md):30 说的对，是我错）。**又一次踩在「断言『没有』要把全表过一遍」上，这次是在写进文件前抓住的。**
- **ObjC 消息发送走 `objc_msgSend`，两个口径都量不到。** 例：ScreenCaptureKit 在 `nm` 里有 `OBJC_CLASS_$_SCDisplay`／`SCScreenshotManager` 类引用（确实在用），表里只显示 0–1。**`^_SC` 类目还会撞上 `SCNetworkReachability`**：2026-10-15 量自己这批，OpenUsage 的「屏幕录制 17 处」逐条查完全是网络可达性轮询——**报「屏幕录制」之前必须展开到符号级**。
- **「函数个数」不可跨家比**（被剥离的件只剩导出的那几个；Alcove／MediaMate 量出来是 1）。跨家只能比呼叫点／字符串。

### 5.4 这批量出来的问题（C1–C10，按严重度）

**C1 · 私有面自述与实际不符：dlsym 那一层（本批最重，且推翻我们自己写过的话）。** [北极星](north-star.md)§二曾写「私有面只有 1 个只读会话查询 ＋ 12 个 IOHID 读——没有一处『写窗口服务器』」。**那是 `nm -u` 口径，只覆盖静态符号表；实际还有一整套运行时载入的私有 API**（`nm`、`bl` 呼叫轮廓都看不见，`strings` 才量得到）：

- `Private/SkyLightBridge.swift`（类 `PrivateSLSWindowMover`，**17 个文件在用**，含 `ShadeController`／`FoldTransaction`／`Rescue`／`PinnedPreview`／`OverlayPresentation` 等核心路径）：`SLSGetWindowAlpha`／**`SLSSetWindowAlpha`（写窗口服务器）**／`SLSMoveWindowWithGroup`／**`SLSMoveWindowsToManagedSpace`（把窗口搬进 Space）**／`SLSReassociateWindowsSpacesByGeometry`／`SLSManagedDisplayGet/SetCurrentSpace`（切当前 Space）／`SLSCopyManagedDisplaySpaces`／`SLSCopySpacesForWindows`。
- `Private/LockSpaceBridge.swift`（锁屏覆盖在用）：**`SLSSpaceCreate`／`SLSHideSpaces`／`SLSShowSpaces`**／`SLSRemoveWindowsFromSpaces`／`SLSSpaceAddWindowsAndRemoveFromSpaces`。
- `Private/DockBridge.swift`：`CoreDockSendNotification`；`Private/ScreenBezel.swift`：`DisplayShapes`。
- 亮度：`DisplayServicesGetBrightness`／`SetBrightness`（dlsym）＋ `KeyboardBrightnessClient`（`NSClassFromString`，CoreBrightness）。
- 捕获：`CGSHWCaptureWindowList`／`CGSMainConnectionID`／`_CGSDefaultConnection`／`CGWindowListCreateImage(FromArray)`。
- 其他：`SACLockScreenImmediate`（立即锁屏）、`CGPostMouseEvent`、`responsibility_get_pid_responsible_for_pid`（音频归属）、`SLSIsScreenWatcherPresent`（**被屏幕共享观察时自检**——这条是善意用法）、`TCC.framework`（权限面）。

**准确的自我描述应该是**：「私有 API 全部隔离在 `Private/` 四个文件、全部走 `isAvailable` 软失败（拿不到就当好功能不存在）、且全部登记在隐私登记表（66 条 `interfaces`）」。性质上与竞品同类（Notchy／Droppy 有同款子集，我们集最全）；**但『没有一处写窗口服务器』这句话作废**——`SLSSetWindowAlpha` 与 Space 搬运正是我们在别处记作『竞品欠的债』的那些操作。北极星的表述已按此改写；再对外说私有面时，**别引 `nm -u`，引这张表**。

**C2 · 未公证：九家里唯一被 Gatekeeper 拦的。** 全部九家竞品 `accepted / source=Notarized Developer ID`；我们 `rejected`。本机**只有一个签名身份**（`Apple Development`，没有 Developer ID）。这件事**已公开披露**（[README](../README.md):46、[update](update.md):351、官网 FAQ 都写了「还没公证，被拦就点仍要打开」）——不是隐瞒，但它是公认范畴「**装得上**」上开局就输的唯一一格，也是怀疑者第一眼会指的地方。修法：Apple Developer Program（$99/年，**要用户拍板**）→ 发布日签名链换成 `Developer ID + 主程序 -o runtime + notarytool + stapler`。

**C3 · 主程序没有 hardened runtime，而嵌套件全有。** `build.sh:373` 是 `codesign … "$APP"`（无 `-o runtime`），362 行注释写明「主程序照旧：不加新标志」；而 367–372 给 Sparkle／Autoupdate／Updater／guard／hook **每个都加了**。后果两条：① 与 C2 并列，主程序是整包里唯一没有 runtime 的执行体；② **Phase 0 验过的候选包 ≠ 发布日要公证的包**（公证要求主程序带 hardened runtime）——发布日等于要签一个从没被验过的组合。解法二选一：现在补上 runtime 重走一遍 Phase 0；或在 runbook 里写明差异并加一次发布日冒烟。

**C4 · 6.6 MB 符号表随包出货。** `__LINKEDIT` 6,619,136 = 二进位的 33%；`nm -a` 74,463 条符号。构建链**没有 strip、没有 `-dead_strip`**，`OPTIMIZATION_FLAGS` 只有 `-O -whole-module-optimization`。剥离对运行期零风险，预计省 ~6 MB。ChainYourMac 证明「不剥也能发」，但多数成熟件在 0.2–1 MB。**2026-10-15 补量：不剥的不止我们**——Dockset 0.2.7 的 `__LINKEDIT` 21.3 MB（占 68%）、OpenUsage 8.2 MB——但**这批里 Thaw 819 KB、DockDoor 328 KB、LaunchNext 311 KB、Glance 213 KB 都剥得干净**；这仍是十家里**成因最明确、修起来最快**的一格。

**C5 · 验收探针随包出货、且没有编译开关。** 全库 `#if DEBUG`／`#if PROBES` **0 处**；**102 个不重复的命令列开关**把整副验收装置编进发布二进位——**拆包清单**（按行数重数，2026-10-15）：GestureProbe 2,297｜DockHoverProbe 1,237｜WindowBrowserShotProbe 770｜GlanceProbe 693｜SilentMilestoneProbe 673｜WindowBrowserIdentityProbe 419｜StripPeekProbe 412｜LaunchpadKeysProbe 378｜WindowBrowserLiveAppProbe 375｜EffectSoakProbe 287｜ThumbnailProbe 268｜EffectWindowProbe 239｜FullScreenProbe 238｜NotchShapeProbe 237｜SLSOffscreenCheckProbe 230｜GapProbesRecovery 228｜GapProbesSlideOver 222｜FrameRhythmProbe 220｜WindowBrowserFixture 209｜GapProbesPlacement 207｜SettingsShotProbe 200｜PerfQualification 169｜GapProbesKeysPins 169……（`prototype/` 下命中 23+ 个文件、约 1.1 万行）。**符号级实证（2026-10-15，`nm`）**：探针类型符号全在出货二进位里——DockHoverProbe 29／EffectSoakProbe 102／SLSOffscreenCheckProbe 73／WindowBrowserShotProbe 47／**GlanceProbe 4,016（含 `GestureProbe.swift` 整个 extension）**／SilentMilestoneProbe 333／StripPeek 275／LaunchpadKeys 326／Thumbnail 1,020 个符号。**陷阱记一条**：**文件名 ≠ 类型名**（`GestureProbe.swift` 里是 `extension GlanceProbe`）——按文件名字符串查符号会得到「没出货」的错觉，查符号一律按**类型名**；这条差一步又栽在「说『没有』要把全表过一遍」上（今天第二次，均在写进文件前抓住）。后果：①「按 flag 启动就做奇怪的事」成为产品的一部分；② 直接喂大了 C6 的 12.4 MB `__TEXT`。成熟做法：`-DDUO_PROBES` 条件编译，或把探针拆成单独目标——**验收跑探针包，用户拿干净包**。

**C6 · 三周长 4.5 倍，是事实不是印象。** `prototype/`：**94 檔 / 33,352 行 → 516 檔 / 150,402 行**（v1.0.15 tag 与 10/14 之间 326 个提交）。`__TEXT` 1.96 MB → 10.79 MB。这是 review-handoff「范围比收敛快」的**量化版本**——不修代码，修入库闸门（§0.2 的 WIP＝6 与 §0.3 冻结就是冲它来的）。**衍生事实：1.0.16 在同版本号下已重发到第七次**（git 提交标题原文「第七次同版本号重发」）——用户手里的「1.0.16」是多个不同包之一，R34 的版本号纪律由此从「应该做」升级为「下不为例」。

**C7 · `libswift_Concurrency.dylib` 1.1 MB 陈留。** 主程序 `LC_LOAD_DYLIB` 指向**绝对路径** `/usr/lib/swift/libswift_Concurrency.dylib`（系统库）；包里那份是 `build.sh:258-261` 用 `cp -R "$SOURCE_FRAMEWORKS/."` 从**旧包整目录继承**来的（旧包 Frameworks 里只有它）。没有任何执行体经 @rpath 引用它——纯死重；且「包里有什么」取决于旧包的历史状态，这个继承机制本身要改。

**C8 · 源码里的那处 IOKit 写：宿主类是死码。** `AppleSPUAccelerometer.swift:225` 的 `IORegistryEntrySetCFProperty` 在源码里；但该类**全库无引用**（唯一提及是一句注释），候选包里 **0 条相关字串、`nm -u` 里没有 Set 符号**——Swift `-O`＋WMO 把未引用类型删掉了。**这不改变 C1 的结论**（C1 那批是真的在跑）；但要注意它与 C1 是两种「源码与出货面的落差」：C1 是**看见的比说出来的多**（dlsym 藏面），C8 是**说出来的比在跑的多**（死码）。将来真接入 SPU 时，`IORegistryEntrySetCFProperty` 会补进 C1 的清单。

**C9 · staging 目录里的裸二进位是残渣。** `.build/duo-validation/windowshade`（adhoc linker-signed，`Identifier=windowshade`）与包内主程序**符号集完全相同**（`nm` 双向差集皆空），是链接器原始输出留在发布目录里。发布包目录只应有一个 .app。

**C10 · 无 `PrivacyInfo.xcprivacy`**（与 N5 同一件事，在这份候选包上再次坐实；`find` 全包为 0）。

### 5.5 运行期数字（补记）

运行期在 [perf-energy](perf-energy.md)§一（AX 全枚举 4.5–10.5 ms/App、四属性读 0.1 ms、`CGWindowListCopyWindowInfo` 1.7 ms、`SCShareableContent` 32.1 ms、私有 `windowAlpha` 0.042 ms——**那个 `windowAlpha` 就是 C1 的 `SLSGetWindowAlpha`，dlsym 来的**；空闲探针 0 查询）。**那批数是在 9/22 那份构建上量的**，不是这份候选包——[scorecard](scorecard.md):43 的 R30（用当前版本重测）继续开着。

### 5.6 REA／Ghidra 的技术史与本轮实测

- **Hopper 那条永久作废**：本机那份是破解件（`Signature=adhoc`、主二进位链接 `libHopperCrack.dylib`）——不碰；建议卸掉。
- **Ghidra 通路已通且可复现**：`brew install ghidra`（走 Homebrew OCI 仓库 `ghcr.io/v2/homebrew/core/ghidra`，实测 315 KB/s，是 GitHub 直链的 240 倍）；`GHIDRA_INSTALL_DIR=/opt/homebrew/opt/ghidra/libexec`，`rea doctor` 八项全 healthy。
- **用法三条**：universal 件先 `lipo -thin arm64`；必须给 `--snapshot`；**一次只跑一份**（并行互相拖死）。
- **教训**：provider 起不来时，要区分「缺权限／缺依赖／供应商本身不可信／带宽」四种原因，**别默认是第一种**——这一条上我错过一次，挂了很久。
- **本轮实测（2026-10-15 上午）**：对 1.0.16 候选包起 `rea analyze --snapshot` → **`provider_timeout`**：`operation: list_documents`，`timeout_ms: 330000`。我们的 **20 MB／74k 符号比此前任何一份竞品件都大**，REA 的 330 秒预算连 `list_documents` 都过不去（§1.5 已有这一行：>3 MB 就别走 `rea analyze`，直驱 `analyzeHeadless`）。**已改走 headless 补跑**（不是 `rea` CLI，直驱 `analyzeHeadless`＋`DumpStrings.java`，与竞品同一支脚本；独立项目目录 `/tmp/ghproj-ours`，避免和另一份还在跑的 Notchy 分析抢项目锁）。产物预计落 `/tmp/ghout/WindowShade16.tsv`（字符串→函数映射）——这一次的目标不是「看一眼函数个数」，而是回答两个具体问题：**① 哪些字符串只在探针里（为 C5 的探针拆包提供清单）；② 出货二进制里有没有任何不该出的串。**

## 六、未核实 / 未开始

**未核实（二手或本轮取不到）**

- Alcove 的**逐版更新日志**：`alcove-releases` 仓库 404，**取不到**（但版本数据从官网前端 bundle 拿到了，见第三节）。
- NotchNook 已停摆：官网 402 ＋ 报道，**二手，未核实**。
- **我们自己的「亮度 DisplayServices」：已核实为真**（2026-10-15）——走 `dlopen`＋`dlsym` 运行时载入（`App/NotchLevelObserver.swift:89`、`App/NotchLevelControl.swift:213`），静态符号表看不见它。[scorecard](scorecard.md):30 说的对；此前两次量出 0 是口径问题，记在第五节 C1 与方法学注。
- **Paneru「显示器具有单独空间」：已核实**（读自它 README，见第四节补读），它自己解释了成因与解法。
- Rectangle 的许可证：本轮没核。
- **DockDoor 的许可证：已核实为 GPL-3.0**（此前采信 GitHub 的 `NOASSERTION`，是误判；读 LICENSE 正文与 README 第 171 行确认）。处理不变（只借思路），理由更硬（传染性 copyleft）。见第四节。
- **许可标签一律不采信 GitHub 的判断**：本轮核过原文的六家——Paneru MIT（2,380★）、PaperWM.spoon MIT、OmniWM GPL-2.0（3,335★，最近推送 2026-10-14）、DockDoor GPL-3.0、niri GPL-3.0、Atoll GPL-3.0。
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
  2. **decompiler provider 已通**（2026-10-15 凌晨）：Ghidra 12.1.4 经 Homebrew bottle 装上，`rea doctor` 全绿，**Wins 的函数级第一批结果已产出**（第三节末）。Hopper 那条因本机是破解件而永久作废。**还没做的**：其余七家（Alcove／Swish／LaunchOS／MediaMate／Notchy／Droppy／ChainYourMac）各跑一遍 `rea analyze --snapshot`，再逐函数 `rea decompile`。
- **开始每个目标前都要先回答条件 1「需不需要绕过保护」。** 已经撞到一条现成的：**Wins 3.6 自述加了防破解与防篡改**——那类就是不做，不试探、不绕过；本轮拿 3.5.1 是因为它不含那层保护（这一点已记在第三节，供律师看）。
- **我们自己的运行测量**（物理占用、常驻 CPU）：未做。需要机器空闲时启动一次再量（不想动到正在用的桌面）。
- **两家的函数级只做到「呼叫轮廓」。** 符号、框架、entitlements、包内资源这一层读得出来；**呼叫轮廓**（谁调了什么设施、多少处）已经用 `llvm-objdump` 做完了，见第三节末。还差的只有**伪代码**（函数体内的逻辑），那要一个 decompiler。**2026-10-14 深夜更新**：Hopper 那条**永久作废**（本机是破解件，不用）；Ghidra 已改走 **Homebrew bottle**（`ghcr.io`，实测 315 KB/s）并已装上——**这是唯一一条不用碰破解件、也不用真人点授权的原生分析路**。
- **开源码那一半不受这两条阻塞**，所以本轮把它做满了（第四节、第七节）。

## 七、总表：竞品 × 维度（逐处逐处挖的索引）

`✓` 已挖 ｜ `◐` 部分 ｜ `✗` 未做 ｜ `—` 不适用。括号里是本文档的出处节。

### 闭源（Aaron 供件，全部验签通过）

| 竞品 | 静态面 | 呼叫轮廓 | 进程架构 | 权限面 | 包装／发行 | 官网 | 机制要点 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Wins 3.5.1 | ✓ | ✓ | ✓（LoginItems helper） | ✓ | ✓ | ✓ | 私有 `_CGS*` 满架 ＋ 私有 `CoreDock`；`LSUIElement 1`；**函数级已挖**：219 个内部信号键（拖动四级几何回退链、`drag.axSizeSettable`、`resume.delayed.0.20/0.80`、`island.layoutJSON`、`missionControl.tapDisabled`、41 个例外 App） |
| Alcove 1.7.7 | ✓ | ✓ | ✓（**私有面关进 XPC**） | ✓ | ✓ | ✓ | `DisplayServices` 亮度；aggregate device 抓音频；`NotchContrastOutline*` |
| Swish 1.13.3 | ✓ | ✓ | ◐ | ✓ | ✓ | ✓ | **`CGEventTap`（事件拦截层）**＋大量 AX |
| ChainYourMac 2.2.5 | ✓ | ✓ | ◐ | ✓ | ✓ | ✓ | **bundle id 是 `com.ahmedgagan.paneru`**（Paneru 血脉）；零 entitlements |
| LaunchOS 2.4.0 | ✓ | ✓ | ✓（docktileplugin） | ✓ | ✓ | ✓ | `CGSHWCaptureWindowList`／`CGSSetMenuBarInsetAndAlpha`；21 语言 |
| Notchy 1.0.208 | ✓ | ◐ | ✓（Widget.appex） | ✓（**索取大量个人信息**） | ✓ | ✓ | 354 MB／138 语言 |
| Droppy 16.0.1 | ✓ | ◐ | ✓（Helpers／自家 Kit） | ✓ | ✓ | ✗ | sandbox=true；15 语言 |
| MediaMate 3.8.4 | ✓ | ✓ | ✓（XPC helper） | ✓ | ✓ | ✗ | 亮度 `DisplayServices`＋`CoreBrightness`；`SwiftUIHidden.framework` |
| WindowMizer 6.2.8 | ✓ | ✓ | ◐ | ✓ | ◐（**EULA 挡挂载**） | ✓ | **全域 tap ＋ 按程序 tap 两种并存**；223 条修复史 |
| DynamicLake 1.0 | ✓ | ✓ | ✓（LoginItems helper） | ✓ | ✓ | ✓（最全） | 自带私有框架副本；Gumroad 发行 |
| TileMyMac 0.2.0 | ✓ | ✓ | ✓（壳＋Paneru 引擎） | ✓ | ✓ | ✓ | **零签名零公证（付费竞品也裸奔）**；薄壳零私有面；引擎＝Paneru 0.5.2 (LuaJIT)（§三末） |
| Agently | ✗（申请制，取不到件） | — | — | — | — | ✓ | AI 总管＋**刘海端 Jarvis**；「闸门带推理」「5 writes·1 held」；MCP 服务器形态（§三末） |

### 开源（免取件，读码即可）

| 项目 | 许可 | 语言 | ★ | 我们读过码 | 今天从它身上拿到的 |
| --- | --- | --- | --- | --- | --- |
| niri | GPL-3.0 | Rust | 28.4k | ✓ | 手势跟踪器；手感值（1200 点／屏、150ms、0.997） |
| AeroSpace | MIT | Swift | 23.5k | ✓ | `hideInCorner`（角外一像素 ＋ 记原位）；「先显后隐」 |
| Rectangle | NOASSERTION | Swift | 30.1k | ◐ | 最小尺寸的 settling pass |
| Atoll | GPL-3.0 | Swift | 4.9k | ✓ | `DownloadManager`（下载完成判定、allocated size） |
| Paneru | MIT | Rust | 2.4k | ✓ | 时间步长纪律、惯性公式、停放 10 点、binpack（§四） |
| DockDoor | **GPL-3.0**（GitHub 误判 `NOASSERTION`） | Swift | 6.3k | ✓ | **自愈清单九条**：金丝雀、`tapIsEnabled` 巡检、标签页合并、标题栏推高、最小步长、带过期的还原、抑制深度计数、窗口顺序的键、显示器 UUID（§四） |
| Thaw | **GPL-3.0** | Swift | 12.1k | ✓ | Ice 续作；菜单栏管理全家（Profiles／Triggers／Zen）；`FREQUENT_ISSUES` 坑表；`release.yml`→appcast 自动化；OpenSSF Gold（§三末） |
| LaunchNext | **GPL-3.0** | Swift | 3.1k | ✓ | 原生 Launchpad 库一键导入；CA 文件夹编排；壁纸子系统带缓存预算（§三末） |
| OmniWM | **GPL-2.0**（`OmniNull/OmniWM`） | Swift | 3.3k | ✓ | 18 个分类夹具；岛的命令流；工程基础设施（§四） |
| PaperWM.spoon | **MIT** | Lua | — | ✓ | 屏幕外的第三份一手证词；新窗口时序；停听—写—再开听；声明式窗口过滤；黄金比档位（§四） |

**2026-10-15 三镜补记（闭源各家）**：Notchy＝Swift 单体（ShazamKit／AppIntents／sqlite；此前「改 alpha／gamma」说法已撤）；Droppy＝私有面最深（21 个 dlsym＋Biome 全家＋13 个私有框架）；Alcove＝BetterDisplay 集成＋亮度回退链；Wins＝SkyLight 静态链＋登录项／显示配置重试＋几何回退＋`SLSConnectionGetPID`。逐条见第三节末。

**这一格的许可地图（今天核过原文，不采信 GitHub 标签）**：**可借代码带署名**的是 MIT 那一档（AeroSpace／Paneru／PaperWM.spoon／bobrwm／parket／TrimWM／Yashiki／Glide(Apache-2.0)）；**传染性 copyleft、只借思路不取码**的是 GPL 那一档（niri GPL-3.0／Atoll GPL-3.0／**DockDoor GPL-3.0**／**OmniWM GPL-2.0**／Nehir GPL-2.0）。**在动手取任何一行代码之前，先读 LICENSE 与 README 原文。**

**新增的竞争场域（我们文件里原来没有的名字）**：ChainYourMac 的自营对比页列了 **Nehir**（`apphane-dev/nehir`，GPL-2.0，自称 OmniWM 的窄化版）与 **ScrollDesktop.spoon**；OmniWM 的冲突侦测名单列了 **bobrwm**（MIT）、**Glide**（Apache-2.0）、**parket**（MIT）、**Rift**、**Tangrid**、**TrimWM**（MIT）、**Yashiki**（MIT），外加 komorebi-for-mac（`LGUG2Z/komorebi-for-mac`）、AeroSpace、Amethyst、Paneru、yabai。

**这一格最值得记的结论：卷轴／平铺这一格几乎全是开源。** 上表 12 家以上里，只有 **ChainYourMac** 是闭源——而它是 **Paneru 的一个 Swift 外壳 ＋ 随包发行的 Paneru 引擎进程**（它自己随包带 `PaneruHelper`、用自己凭证重签，并在产品内写了 MIT 署名，见第一节与第三节第 1 条）。也就是说：**这一格的 know-how 免费可读**（读码 ＋ 按许可取用），**闭源集中的是刘海的 HUD 那一格**（Alcove／DynamicLake／Notchy／Droppy／MediaMate／Wins）。→ 想要「师夷长技」，**卷轴那半边应该去读源码，刘海那半边才需要一手材料与二进制分析**。

## 八、参考

一手公开材料（读取于 2026-10-14）

- **更新日志（单独成篇，626 个 release）**：[更新日志里的 real-world know-how](changelog-knowhow.md)——取自 11 个开源项目／同场的 GitHub Releases 与闭源竞品的一手更新史

- Wins：[更新日志](https://wins.cool/zh/changelog)
- Swish：[产品页](https://highlyopinionated.co/swish/)（当日为促销页）
- Alcove：[官网](https://tryalcove.com)（更新日志仓库 404）
- DockDoor：[仓库](https://github.com/ejbills/DockDoor)／[releases](https://github.com/ejbills/DockDoor/releases)
- DynamicLake 开发者面：[DynamicLakeKit 文件](https://docs.dynamiclake.com/documentation/dynamiclakekit/)／[插件市集](https://market.dynamiclake.com)／[Extensions 页](https://www.dynamiclake.com/extensions)／[验证注册表](https://github.com/rokach/DynamicLake-Trusted-Extensions)（已暂停）
- ChainYourMac 的**自营对比页**：[best-scrolling-window-managers-for-mac](https://chainyourmac.com/best-scrolling-window-managers-for-mac)（它自己列了 Nehir／komorebi for Mac／ScrollDesktop.spoon）
- OmniWM：[官网](https://omniwm.app)／[已知限制页](https://omniwm.app/help/known-limitations)／[仓库 `OmniNull/OmniWM`](https://github.com/OmniNull/OmniWM)（GPL-2.0）
- macEnhance 技术 blog：[Controlling the Dock with CoreDock](https://www.macenhance.com/blog/) 等（README 级联已改版，本轮路径 404）

**原始爬取与扫描输出**（**不进仓库**）：`/tmp/ws-research/sites/`（各站 HTML）、`/tmp/ws-research/xref/`（12 份呼叫轮廓 JSON）、`/tmp/ws-research/packaging/`（打包扫描脚本）。

开源码（读取于 2026-10-14，分支与 commit 如正文）

- Atoll（GPL-3.0）：[Ebullioscopic/Atoll](https://github.com/Ebullioscopic/Atoll) `dev@fdc1c14471ec`
- niri（GPL-3.0）：[niri-wm/niri](https://github.com/niri-wm/niri) `main@4263c9a17f80`
- AeroSpace（MIT）：[nikitabobko/AeroSpace](https://github.com/nikitabobko/AeroSpace) `main@74a1bf17e82d`
- Rectangle：[rxhanson/Rectangle](https://github.com/rxhanson/Rectangle) `main@1d46069c27b3`
- Paneru（MIT，2,380★）：[karinushka/paneru](https://github.com/karinushka/paneru) `main@8a213313538a`
- **DockDoor（GPL-3.0，6,344★）**：[ejbills/DockDoor](https://github.com/ejbills/DockDoor) `main@7be384b46da6`——本轮读的是 `NativeTabGrouping.swift`、`LiveWindowCapture.swift`、`DockObserver.swift`（1446 行）、`WindowUtil.swift`（1905 行）、`SpaceWindowCacheManager.swift`、`PrivateApis.swift`、`TrackpadSwipeTrigger.swift`、`EventTapThread.swift`、`LimitedTaskGroup.swift`、`NSScreen.swift`、`WindowOrderPersistence.swift`、`WindowSeeder.swift`
- **PaperWM.spoon（MIT）**：[mogenson/PaperWM.spoon](https://github.com/mogenson/PaperWM.spoon) `main@2a561eb63df4`——本轮读的是 `events.lua`、`tiling.lua`、`swipe.lua`、`windows.lua`、`config.lua`、`README.md`
- **OmniWM（GPL-2.0，3,335★）**：[OmniNull/OmniWM](https://github.com/OmniNull/OmniWM) `main@d1ca4444ea74`

本机

- 测量对象：`prototype/WindowShade.app`（二进制 2026-09-22），sha256 见第五节。
