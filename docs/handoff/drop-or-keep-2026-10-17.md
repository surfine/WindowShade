# 19 条存疑项：放弃还是留下（2026-10-17）

结论：19 条里 **放弃 5 条、算完成 5 条、留下以后做 9 条、留下现在做 0 条**。没有一条值得插进当前批次。留下的 9 条里有 6 条不必单独排期，并进已有的真机批次或机器探针合集顺手做（O1、A1、R19、V8、V9、R33）。依据是 [重塑规格 §0.2](../product-reshape-spec.md)：这一版只做 6 条，队列只置换不增长；冻结区（L180：R5–R31、R35／R36／R39–R45、E／H／N／M 全部、V7–V11）只在「上一批清空」或「真机上被撞到」时解冻。

每条的调研由子代理分头做，本文做了交叉核对。核对中改了 4 处判断，见文末「交叉核对的更正」。

## 总表

| 编号 | 一句话 | 建议 | 放弃的代价 | 剩余成本 | 谁能做 |
| --- | --- | --- | --- | --- | --- |
| V7 | 侧拉与 iPadOS 27 Slide Over 像素比对 | 放弃 | 几乎为零：侧拉已上线，比对最可能的结论是「不改数字」 | 1–2 h，脚本注入两次失败，只能手拖或用 iPad 真机 | Aaron |
| R49 | ToDesk／QQ 音乐／小程序预览不出来 | 放弃 | 极小：没有用户报告，也没有我们自己的复现；唯一来源是 Wins 的一句「兼容性改善」 | 3–5 h，大半花在装管理员级远控软件，另有一个 403 安装包 | 机器＋Aaron |
| R30 | Mac 设置检查（mru-spaces、spans-displays） | 放弃（并入 V9） | mru-spaces 无影响（我们用 ManagedSpaceID）；spans-displays 只是推测会影响多屏卷轴 | 核实 2–3 h；spans-displays 需要两块真屏 | 机器＋Aaron |
| H3 | 采集改 displayP3、显式 captureResolution、评估 HDR | 放弃（记「核过不做」） | 只有 P3 色域外的高饱和内容在预览里被夹到 sRGB；背景 ΔE 1.08，低于阈值 2.3 | 4–8 h，再加 HDR 2–4 h，要 P3／HDR 屏 | 机器＋Aaron |
| V1 | 盒盖动画手感确认 | 放弃（不再单列） | 记分卡这一格停在 88；功能默认关；「无同类」本来就不成立（有 Latch） | Aaron 10–15 min，另 0.5 h 改矩阵 | Aaron |
| M3 | NSLock／os_unfair_lock 迁到 Mutex | 算完成 | 无：剩下 54 处每处都有不迁的书面理由 | 改规格和台账两处文字 | 机器（Aaron 点头） |
| R25 | 多点触控按设备归属 | 算完成（真手验并入 V5） | 无：代码已在 9c0d1e1，有单设备等价单测 | 台账更正 5 min；V5 里多一步 10–15 min | 机器＋Aaron |
| R36 | 设置里的「报告问题」入口 | 算完成 | 无：代码已上，一行 NSWorkspace.open | 点一次，0.1 h；规格正文对齐定案 | 机器＋Aaron |
| R37 | 面向用户的隐私声明 | 算完成 | 三档分级和「不离开这台 Mac」没上；后一句按现在的代码不成立 | 剩余部分转冻结区小项 | 机器＋Aaron |
| N1 | App Intents 7 个动作 | 算完成（发布关里查一行） | 无：元数据自动检查已 PASS | 0.5 h，在快捷指令和 Spotlight 里搜一遍 | 机器（computer-use） |
| E3 | 对 1.0.15 的长会话卡顿比较 | 以后做 | 回答不了「326 个提交后手感有没有变差」 | 2–3 h 机器时间，要屏幕解锁 | 机器 |
| R39 | 窗口浏览／悬停看一眼各 100 轮长会话 | 以后做 | 两个最重的界面上的泄漏要连用多天才会显出来；核心路径 300 轮已平 | 1–1.5 h 机器时间 | 机器 |
| R19 | 台前调度验收与适配 | 以后做（只留重跑探针） | 用台前调度的用户（约 12%，样本是自选投票）可能遇到收起、分屏异常 | 重跑 1–1.5 h；若确有缺陷再适配 2–4 h | 机器＋Aaron |
| V8 | DockDoor 12 条场景上机 | 以后做（剩余 3 类） | 窗口浏览是对照表里唯一落后的一行，放弃就等于不补这一分 | 3–4 h，其中真机 1–1.5 h | 机器＋Aaron |
| V11 | 异常缩放下图标不变形 | 以后做（先查清 1x FAIL） | 图标变形风险很窄；1x 下启动台「did not show」原因不明，可能更严重 | 1–2 h | 机器 |
| R33 | CI 跑 build.sh --check | 以后做（首次推送时顺带验） | 少一道推送后的保险；本机已有同一道门禁加 Stop hook | 0.5–1.5 h，必须由 Aaron 推送 | Aaron |
| O1 | 切换器键入即搜 | 以后做（并入 1.0.17 真机批次） | 真机没验就上线，⌥Tab 主路径有回退风险；功能本身对标 DockDoor | Aaron 0.5–1 h | Aaron |
| A1 | 终端回跳 | 以后做（并入 1.0.17 真机批次） | 代码已写完；不验的话，「agent 控制面」这一格不算数 | Aaron 1–2 h（六类终端） | Aaron |
| V9 | 多显示器矩阵 | 以后做（收窄成插拔＋改分辨率） | 笔记本接外屏是主流场景，错屏或崩溃就是真事故 | Aaron 约 20 min 到 2 h | Aaron |

计数：放弃 5（V7、R49、R30、H3、V1）；算完成 5（M3、R25、R36、R37、N1）；留下以后做 9（E3、R39、R19、V8、V11、R33、O1、A1、V9）；留下现在做 0。

## 逐条

**V7 放弃。** 我方常量已全部查实（[v7-slide-over-compare.md](../v7-slide-over-compare.md) §3）。iPadOS 一侧 not_run：脚本注入两次都进不了 Slide Over。规格 L1108 的验收写的是「比对完成或明确记 not_run」，这个低门槛已经满足。被比的对象自己也在变：iPadOS 26 拿掉了 Slide Over，26.1 换成绿色按钮入口带回来（[Six Colors](https://sixcolors.com/post/2025/10/ipados-26-1-beta-brings-back-slide-over-adds-microphone-adjustments/)、[9to5Mac](https://9to5mac.com/2025/10/06/ipados-26-1-beta-2-restores-slide-over-multitasking-back-to-ipad/)）。拿它当像素基准，等于追一个移动靶。以后要重开，条件是：iPadOS 27 正式版交互稳定，而且 Aaron 手上有 iPad。

**R49 放弃。** Wins 3.1.1 原文只是「Improved window preview compatibility with apps like ToDesk and QQ Music」（[wins.cool/changelog](https://www.wins.cool/changelog)），说的是 Dock 预览，没写原因。规格把它转述成「修复无法预览」，说重了。DockDoor、AltTab、Rectangle 的 issue 里都没搜到这两个 App。我们已有逐 App 政策（[Policies.swift](../../prototype/Compatibility/Policies.swift)）和 R20 的 `--window-classes` 夹具，读不到窗口时的处理是不列，不会崩溃。为一句二手日志装管理员级远控软件，风险大于收益。处理方式：在 R20 待办里记一行「有用户报告某 App 缺图时补一类」，R49 编号收回。

**R30 放弃，并入 V9。** 要求开这两个开关的，是别人的实现约束：Paneru 把窗口整个移出屏幕，会被 macOS 搬到别的显示器（[Paneru README](https://github.com/karinushka/paneru)）。我们只露一条边，而且用 ManagedSpaceID 认 Space（[SkyLightBridge.swift:156](../../prototype/Private/SkyLightBridge.swift)），桌面顺序重排不影响窗口归属。唯一可能的影响是 spans-displays 下的多屏卷轴，这是推测，没有实测。处理方式：V9 真机跑多屏时，顺手关一次「显示器具有单独空间」，看卷轴边缘。

**H3 放弃，账上记「核过不做」。** 本机 10-17 逐像素比对：P3 帧按 P3 解码后，与 sRGB 帧的背景差 ΔE 1.08，低于可察觉阈值 2.3。如果把 P3 数值误当 sRGB 贴回，差值是 2.74，91% 的像素超过阈值。所以真换成 P3，胶囊检测和底片的换算都要重写，一处做错就是可见的偏色回退，不符合「只做纯收益的改动」。Mozilla libwebrtc 的修法也是显式设成 sRGB（[补丁](https://asuth.searchfox.org/mozilla-central/source/third_party/libwebrtc/moz-patch-stack/0114.patch)），和我们现在的做法一致（[ScreenCaptureBridge.swift:437](../../prototype/ScreenCaptureBridge.swift)）。captureResolution 和 HDR 都没有独立依据，真机上看到缩略图发糊或发灰时再开新条。

**V1 放弃，不再单列。** 这个功能在 [direction.md](../direction.md) 里定为「最舍得让出来的」，默认关。性能已有实测：效果关时约 0.087%，开时约 0.445%（[performance.md](../performance.md)）。矩阵里写的「无同类」不成立：[Latch](https://www.producthunt.com/products/latch-lid-actions-animations) 同样读铰链角度，有 8 种动画。所以手感确认之后，这一格最多也只是持平。处理方式：[dominance.md](../dominance.md) 这一格改成「默认关、对 Latch 持平、手感未确认」。Aaron 做 V5 真手测试时，顺手开合两遍，记一行。

**M3 算完成。** 规格 L1232 的收口提议已经逐个核过剩下的 54 处，每一处都不同时满足「一把锁只护一个 Sendable 值、不在 @MainActor 类里、不在热路径」。再往下迁就要改类型设计：拿掉一个 `@unchecked Sendable`，又得新包一个，没有净收益。第四轮在真机上出过 SIGTRAP，已经付过这个代价（见 memory「Mutex in MainActor class trap」）。今天重数：`NSLock(` 34 处，`@unchecked Sendable` 98 行。[modernization.md](../modernization.md) 起初写的是 99，所以「去掉 @unchecked」这个目标基本没达成，需要如实记下，但不必为它再开第七轮。两条长期纪律写进规格 §1：新代码一律用 Mutex；主 actor 类里会被后台闭包碰到的状态不迁。

**R25 算完成。** 代码在 9c0d1e1（[TouchOwnership.swift](../../prototype/Core/TouchOwnership.swift)），单设备时与旧计数逐帧一致，有单测（[run-touch-ownership-tests.sh](../../tests/run-touch-ownership-tests.sh)）。依据确实存在：[OmniWM v0.6.5](https://newreleases.io/project/github/BarutSRB/OmniWM/release/v0.6.5) 原文写了按设备隔离和缺帧过期恢复。[spec-ledger](spec-ledger-2026-10-17.md) 第 47 和 117 行写「完全没动」，已经过期，我核过属实。这次改动走的是所有用户都会经过的手势计数路径，所以真手验收不能省，并进 V5，验收句写明：两块板同时放手指，手势不被对方打断；故意中断一次后，下一次照常。

**R36 算完成。** 「报告问题」在 [DuoSettingsWindow.swift:929–933、991–992](../../prototype/Effects/DuoSettingsWindow.swift)，打开 GitHub 的 issues/new。Aaron 10-16 定案不带环境信息模板，只提示可以附上 R35 诊断包。规格 L435 和 L873 还写着旧的「带模板」，改成定案。剩下点一次的操作并进 1.0.17 的真机清单（台账 L146 已有这一行）。

**R37 算完成。** 验收句是「一句话能回答你们拿我的数据做什么，且每条都能在登记表里找到」，已经满足：「不收集、不上报」写在 App、官网、README 三处，65 个登记项与 WS2PrivacyData.swift 逐字校验。「除了检查更新，都不离开这台 Mac」不能放出来：MKLocalSearch／MKDirections（NotchActivityController.swift:656）、CarPlay WebSocket 和 Bonjour 都会联网或监听。开关 `showsNetworkPromise` 默认关，这样处理是对的。它是 §0.2 那 6 条之一，关掉它对本版也有意义。剩下两件转冻结区小项：一是如实改写网络承诺，二是 loupe 三档分级。三档分级属于新界面，要先过设计准入。

**N1 算完成。** 7 个 AppIntent 在 [WindowShadeIntents.swift](../../prototype/App/WindowShadeIntents.swift)（4a8551f），35185e2 的自动检查 PASS：动作数、三语标题与说明、与源码一致都核过了。范围按定案收在 5–8 个。剩下的是在快捷指令和 Spotlight 里搜一遍，归到 1.0.17 发布关（台账 L148），没搜到再重开。外部只核了两家：Rectangle Pro 走 URL API，Moom 走 AppleScript。其他竞品有没有 App Intents，没有核。

**E3 以后做。** 这是唯一能回答「326 个提交后手感有没有变差」的一项。[tests/e3/](../../tests/e3/) 脚本已经定稿（f8f7bf2、0a41594），剩下的是便宜的机器时间。它不挡任何发布，单场景、单机器的结论强度也有限。外部只确认了 Wins 一家在 macOS 27 上出过拖动卡顿（[competitive-deep-dive](../competitive-deep-dive.md) L43、L269）。处理方式：作为 1.0.17 发布关的机器步骤录一次，每版 15 秒，导出后删掉 trace，开跑前先查磁盘（以前写出过 7.1 GB）。如果 1.0.17 发布前一直排不上，就降为放弃。

**R39 以后做。** 规格 L67 写的「R39 ✅」只覆盖收起展开 300 轮（32.6→32.7 MB，平）。窗口浏览和悬停看一眼两条没跑，所以台账记「剩余」是对的，规格正文需要改成一致。探针已在 41452be 补齐，提交信息写着「本次未运行」。竞品确实栽过这类问题（[Thaw 1.0.0-beta.1](https://newreleases.io/project/github/thaw-app/Thaw/release/1.0.0-beta.1)、[DockDoor 1.31](https://newreleases.io/project/github/ejbills/DockDoor/release/1.31)）。放进下一次真机探针合集。跑之前先确认 GlanceProbe 会不会移动真实鼠标。

**R19 以后做，只留重跑探针。** 唯一的 FAIL（restore-guard）出现在虚拟机里，当时宿主负载高，临时 App 也没被激活，不能算产品缺陷的证据。探针修正 2fa27e1 还没重跑。它和 V8(f) 是同一个台前调度场景、同一个探针问题，**合并成一次重跑**。适配那一半改成「撞到再做」，做的时候要带可以单独关闭的开关。使用率唯一的数字来自 [TidBITS 2023](https://tidbits.com/2023/08/07/do-you-use-it-stage-manager-sees-weak-adoption/) 的自选投票，约 12%，读者偏技术型，不代表整体。

**V8 以后做，但排在以后做的最前面。** 子代理建议「不再当作唯一落后一行的阻塞项」，这和 [dominance.md](../dominance.md) L27、L54 冲突。那里写明补这 1 分的路径就是「原生标签页合并 ＋ DockDoor 12 条场景上机」，而 R4 已核实为不用改，所以 V8 是剩下的唯一路径。已在真机 PASS 的有 4 类，外加 r46／r32（[dock-scenarios-2026-10-17.log](../visual-qa/dock-scenarios-2026-10-17.log)）。剩下三类：(b) 自动隐藏，脚本已修，但需要真指针；(e) 唤醒后，要整机睡眠一次；(f) 台前调度，和 R19 合并。DockDoor 在这三处都反复修过（[1.39.5.3](https://newreleases.io/project/github/ejbills/DockDoor/release/1.39.5.3)、[1.40.0](https://newreleases.io/project/github/ejbills/DockDoor/release/1.40.0)），说明问题是真的。另外，台账里「其余几条没有逐条记录」要先补成 12 行清单，否则「4／12」这个分母本身就不可核。

**V11 以后做。** 代码已按 backingScaleFactor 取图（[LaunchpadArtwork.swift:91](../../prototype/App/LaunchpadArtwork.swift)、[WindowBrowserViews.swift:208](../../prototype/WindowBrowser/WindowBrowserViews.swift)）。真正的风险不是图标变形，而是 1x 下启动台探针报「did not show」，原因还没查清。如果确认 1x 下启动台真的弹不出来，就升级为现在做。在那之前，规格里保持「待查是缩放问题还是环境问题」，不要记成通过。

**R33 以后做。** [ci.yml](../../.github/workflows/ci.yml) 已在 6b51679。它是 §0.2 那 6 条之一，不能放弃，可是剩下的一步（推送）是不可逆动作，只能由 Aaron 做。[macos-26 runner](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md) 默认 Xcode 26.6，没有 27，加上 `-warnings-as-errors`，第一次跑有相当概率变红。私有仓库的 macOS 分钟按 10 倍计费。处理方式：下次推送时看一眼 Actions。绿了就记完成。红了按错误三选一：给 CI 放宽警告、等映像升到 Xcode 27、或改成 `workflow_dispatch`。

**O1 以后做，并进 1.0.17 真机批次。** 代码已在（[WindowSwitcherSearch.swift](../../prototype/Core/WindowSwitcherSearch.swift)，有单测）。它改的是 ⌥Tab 的键盘事件钩子，所以真机验收不能省。六项检查：键入三个字母命中窗口；搜索状态下 ⌘W／⌘Q；数字键对应过滤后的列表；打第一个字后立刻松开修饰键；Esc 先清空再关闭；普通 ⌥Tab 行为不变。来不及验就把键入入口藏起来，不带着没验过的入口发布。五档模糊度和预览上的窗口按钮现在就砍掉，DockDoor 的做法见 [1.23](https://newreleases.io/project/github/ejbills/DockDoor/release/1.23)、[1.28](https://newreleases.io/project/github/ejbills/DockDoor/release/1.28)。

**A1 以后做，并进 1.0.17 真机批次。** Claude Code 官方把「点通知聚焦正确的终端窗口」关成了 not planned（[#30672](https://claudeissues.com/issue/30672-notification-click-should-focus-the-correct-terminal-window-multi-window-support)），[Vibe Island](https://vibeisland.app/precise-jump/) 把这个功能当卖点。我们的代码已写完，只走 AX，不需要新权限（TerminalBinding.swift 等三个文件，共 244 行）。在 iTerm2、Ghostty、Warp、kitty、Terminal、tmux 里各跳一次。哪个终端跳不了，就如实显示「跳不了」，不为它追加 AppleScript 或 tab 级精度。

**V9 以后做，收窄。** 内建屏加 Studio Display 的三项已在签名构建上 PASS。保留「插拔一次」和「改一次分辨率」，两项合计约 20 分钟真手。这两种情况最常见，崩溃和错屏的风险也最大，WindowMizer 修过三次同类问题（[changelog-knowhow](../changelog-knowhow.md) L158、L160）。「两块同型号」从通过标准里删掉，改记「已知未验，靠 UUID 键的单测兜底」。留一个机器可做的待核项：收起时记下的屏，是按 UUID 存还是按 displayID 存？目前只有 DockLock 的 UUID 解析有单测（[DisplayKeyResolverTests.swift](../../tests/DisplayKeyResolverTests.swift)）。R30 的 spans-displays 也在这一轮顺手看。

## 交叉核对的更正

1. **V8**：调研说它不该再算唯一落后行的阻塞项。dominance.md 写明它是补那 1 分的路径，R4 已不用做，所以 V8 留下，并排在以后做的最前面。
2. **R19 与 V8(f)**：两边是同一个台前调度场景，卡在同一个探针问题上（临时 App 被收进缩略条），合并成一次重跑，不重复记成本。
3. **V1**：调研写「1.0.16 之后 170 个提交、0 次发布」，这句不对。170／0 是 10-06 对 1.0.15 之后的统计。规格 §0.1 写的是 1.0.16 已于 10-14 发出，同一个版本号重发了 11 次。放弃的结论不变。
4. **R33、R37**：两条都在 §0.2「只做 6 条」里。R37 关掉没问题。R33 不能放弃，只是剩下那一步得由 Aaron 推送。
5. **R39**：规格 L67 的「✅」只指 300 轮收起展开，不能当成整条完成。规格正文和台账要改成一致。

## 需要 Aaron 拍板的

**放弃**（同意后，在规格和台账里改成「放弃，附理由与重开条件」）：

- V7：重开条件是 iPadOS 27 正式版交互稳定，且手上有 iPad。
- R49：编号收回，在 R20 里留一行「有用户报告再补」。
- R30：spans-displays 并进 V9 看一眼。
- H3：记「核过不做」，ΔE 数据留在账上。
- V1：dominance 这一格改成「对 Latch 持平、默认关」，不再靠 V1 加分。
- O1 的五档模糊度与预览窗口按钮（O1 本身留下）。
- V9 的「两块同型号」一项（V9 本身留下）。

**以后做**（确认归到哪一批）：

- 并进 1.0.17 真机批次：O1（来不及就藏入口）、A1、R36 点一次、N1 搜一遍、R25（放进 V5）。
- 下一次机器探针合集（要屏幕解锁）：E3、R39、R19＋V8(f) 合并重跑、V11 查 1x FAIL。
- 需要 Aaron 真手、发布后排：V8(b)(e)、V9 插拔与改分辨率。
- R33：下次推送时看 Actions。红了怎么处理，是放宽警告、等 Xcode 27，还是改成手动触发？

**算完成**（同意后改台账状态）：

- M3：两条纪律写进 §1；同时如实记下 `@unchecked Sendable` 只从 99 减到 98。
- R25：更正台账 L47、L117。
- R36：规格 L435、L873 改成无模板的定案。
- R37：网络承诺改写和三档分级转冻结区小项。
- N1：「快捷指令能搜到」留在发布关清单里。
