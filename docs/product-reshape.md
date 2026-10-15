# 重塑：把竞品身上「被反复修过的知识」换成我们的实现

2026-10-15。这一份是**从研究到动手的桥**。依据：[竞品深挖](competitive-deep-dive.md)（九份正版件、静态面 ＋ 呼叫轮廓 ＋ 函数级；Ghidra 12.1.4 通路已通）、[更新日志里的 real-world know-how](changelog-knowhow.md)（626 个 release 归成 13 个失效家族）。

> **要动手执行的，读 [重塑执行规格](product-reshape-spec.md)**：同一批任务写成了可直接执行的形式（每条带依据、现状行号、改动要点、验收方法、风险、依赖），外加执行前提、纪律铁律（建置闸门／中文日志串棘轮／文案三条规矩）、执行顺序与验证命令速查。这一份保留「为什么」，规格那一份管「怎么做」。

## 一、判据：什么叫「成熟」

不是功能多。**是被反复修过、并且在多个独立实现里收敛到同一个形状的东西。**

这一轮学到的知识有两条铁证，值得先立在这儿：

- **三家独立实现撞同一堵墙、给出同一类解法**：停在屏幕外的窗口会被 macOS 搬走——Paneru（角内侧 10 点）、PaperWM（边缘一条边距）、AeroSpace（角外一像素）、我们（露一条边）；显示器身份不能信 `CGDirectDisplayID`——DockDoor、OmniWM、Wins 都用硬件 UUID（第四家）。**四家收敛，就不是某家的偏好，是平台的形状。**
- **两家独立实现、两张几乎不相交的逐 App 例外名单**：Wins（微信／QQ／钉钉／WPS／ToDesk／哔哩哔哩）、Alcove（Slack／WhatsApp／Telegram／Spotify／**英雄联盟三个 bundle**／GeForce Now）、WindowMizer（Premiere／Safari／iCal／Chrome／Vivaldi）。**三张不相交的名单说明「逐 App 例外表」是结构上躲不掉的**，不是可以靠通用规则消掉的东西。

所以下面每一条都带：**症状 → 谁修过（几处独立印证）→ 我们的现状（带文件名与行号）→ 改成什么 → 怎么验**。

## 二、重塑清单

### A 组：今天就能动，风险低

**1. 事件通道的周期体检**

- **症状**：装了几个月之后，「点一下窗口」忽然没反应；没有报错，也没有崩溃。系统会在回调超时或输入洪泛时**静默停掉**我们的 event tap。
- **谁修过**：DockDoor 有一个 5 秒看门狗，其中一项是 `CGEvent.tapIsEnabled(tap:)` 为假就重建；**Wins 把 `missionControl.tapDisabled` 当成一个专门的埋点**——两家独立印证。
- **我们的现状**：`WindowShade.swift:950` 有一个 2 秒重复计时器，但它只在**安装失败**时重试；`:977` 装好之后，只在收到 `tapDisabledByTimeout`／`tapDisabledByUserInput` 时才重开（`App/GlobalInputFilter.swift:360`、`App/ScrollTap.swift:158`、`App/WindowSwitcher.swift:74`、`App/TrackpadGestures.swift:2242`、`App/NotchLevelObserver.swift:294` 五处）。**缺的正是「装好之后的周期巡检」**：tap 在没有那两个事件的情况下死掉，我们不查。
- **改成什么**：一个低频（5 秒）健康计时器，检查 `eventTap != nil && CGEvent.tapIsEnabled(eventTap)`；为假就重建，并记一行日志说明「第几次、因为什么」。
- **怎么验**：人为 `CGEvent.tapEnable(tap, false)` 模拟静默失效，10 秒内自愈且日志有记录。
- **✅ 2026-10-15 已动手**：`prototype/WindowShade.swift` 新增 `startEnvironmentWatch()`／`runEnvironmentCheck()`，装好之后每 5 秒查一次；通道被静默停掉就**重开同一支 port**（不重建、不新起线程，与五处 `tapDisabledBy*` 保持同一形状），并记 `tapSilentStops` 计数。同一次体检里**顺带盯了辅助功能权限的「有→无」与「无→有」**（见第 2 条，目前只记状态与日志，用户可见那一句待补文案）。
  **踩到并修掉的一条仓库纪律**：第一次改动让 `build.sh --check` 失败——**中文**字面量行数从基线 1034 涨到 1037（`防漏网：中文字面量行数超过棘轮基线，只许降不许升`）。**这个仓库的日志串一律用英文，中文只走 `WSL10n` 的用户可见文案。** 三句 `wlog` 改成英文后通过。→ **以后往这个仓库加日志串，一律写英文。**

**2. 辅助功能权限被撤掉，要告诉用户**

- **症状**：用户在系统设置里关掉辅助功能，App 从此**静默失灵**——所有窗口动作还在「跑」，但没有一件能生效，且不报错。
- **谁修过**：WindowMizer 的更新史明写「**Display an alert when Accessibility is turned off while WindowMizer is running**」。
- **我们的现状**：**47 处**读 `AXIsProcessTrusted()`，**0 处**在「从有变无」时告诉用户。
- **改成什么**：在既有的低频路径上核对权限状态；从「有」变为「无」时出一个可见提示，说明「因为你关掉了辅助功能，这些动作现在不会生效」，并给一个打开对应系统设置面板的按钮（照 Wins `dockLock.hud.openSystemSettings` 的做法）。
- **怎么验**：运行中关掉辅助功能 → 10 秒内出现说明；重新打开 → 提示消失或说明恢复。

**3. 唤醒恢复收成三档重试**

- **症状**：睡一觉醒来，手势／悬停／快捷键里总有一两样没回来；用户只能重启 App。DockDoor 多条更新日志、alt-tab-macos、OmniWM、LaunchOS **连修两版**、Wins 两次（唤醒后预览里出现红绿灯）——这是整份日志里**出现最多的一件事**。
- **谁修过**：**Wins 的 `resume.*` 命名空间给了确切数值**：`resume.immediate` ＋ `resume.delayed.0.20` ＋ `resume.delayed.0.80`——立即一次、0.20 秒后一次、0.80 秒后一次。
- **我们的现状**：**十处**各自独立处理唤醒（`App/PinnedPreview.swift:263`、`App/WS2AppRuntime.swift:102`、`App/NotchActivityController.swift:251`、`App/SplitView.swift:117`、`App/Notch.swift:204`、`App/AwaySummaryController.swift:61`、`App/NotchWatch.swift:139`、`App/BystanderTuck.swift:155`、`App/WS2RemoteHost.swift:918`、`App/FaceScanExperiment.swift:137`、`App/PresenceLockDriver.swift:316`）。**没有一处重试，也没有一个共同的收口。**
- **改成什么**：一个 `WakeRecovery` 收口，在 `didWake`／`screensDidWake` 上按**立即／0.20／0.80** 三档跑一遍：重建事件通道 → 重新确认订阅的 AX 元素 → 刷新屏信息。各处的唤醒观察者保留（它们各自有职能），但**恢复动作走同一条路**。
- **怎么验**：睡一次、醒一次，逐项功能在 1 秒内恢复；日志能读出三档各自做了什么、第几次成功。

### B 组：高价值，改动面稍大

**4. 原生标签页合并**

- **症状**：一扇开了 5 个标签的终端／访达，在窗口浏览里出 5 条。
- **谁修过**：**四处独立印证**——DockDoor 做了合并（`NativeTabGrouping`：同 pid ＋ 取整相同的 frame 判为一组；在屏的一律保留；屏外每组留「最近访问」那一个；不可归组的永不合并），而且还要修「**被拖出来的标签各自成条**」；Paneru 连着两个版本「Improved detection of native tabs」；Rectangle「Add title bar tab group support」；Wins 修「Finder 多标签窗口」。
- **我们的现状**：**没有**。`AXTabGroup` 只作为 AX 角色出现在两个命中测试名单里（`Core/TrackpadGesture.swift:750`、`Window/AXWindow.swift:490`、`:504`），不是用来分组的。
- **改成什么**：照 DockDoor 的判据实现一个纯函数（不依赖 AX 与 AppKit，便于单测）。
- **怎么验**：5 标签的终端只出一条；**把其中一个标签拖出来**，它各自成条。

**5. 设置：备份／导出／导入 ＋ 前向迁移纪律**

- **症状**：新版加了一个必填项，用户的设置被整体换成默认值，且**没有任何办法找回**。
- **谁修过**：OmniWM 用三代版本换来的教训（0.6.2→0.6.3 把 `settings.toml` 换成默认、原文「**your configuration stops applying** until you restore it」；0.6.4 起明确「Migration is **forward-only**」；0.7.3 起每次升级都留 `settings.toml.pre-v4` 备份）。DockDoor 把「Back up and restore settings **as a JSON file**」做成设置里的一项，**并且设置搜索能搜到 backup／export／import／restore**。
- **我们的现状**：只有**一个**迁移点（`WindowShade.swift:46` 的 `ShadeSoundMigrationVersion`，逻辑在 `:531`–`:548`）；**没有备份，没有导出/导入**。
- **改成什么**：（a）每次改动设置格式前，原文件留一份带版本号的备份；（b）迁移**只补缺的字段**，不整体回默认；（c）设置里能导出一份 JSON、能导回来，且能被设置搜索找到。
- **怎么验**：拿旧版设置文件启动新版，设置照旧；导出→清空→导入，回到原样。

**6. 几何读取的四级回退链**

- **症状**：某些窗口读不到 AX 外框（App 不响应、元素刚建出来），于是排布／落点算错。
- **谁修过**：**Wins 的 `drag.*` 里就是这么一条链**：`windowServerRect` → `axWindowRect` → `axWindowRectFallback` → `windowListRectFallback`。顺序说明了主次：**先 WindowServer，再 AX，再两层回退。**
- **我们的现状**：未记载，各处各自读。
- **改成什么**：把「取窗口外框」收成一个函数，按上面的顺序回退，并记下用了哪一层（可观测）。
- **怎么验**：拿一个 AX 不响应的 App（`kill -STOP`）当对象，排布仍拿到正确外框。

**7. 排布前先问「这扇窗能不能改大小」**

- **症状**：把计算器、系统设置这类固定大小的窗口拿去排布，结果是假装做了——窗口没动，用户以为功能坏了。
- **谁修过**：**Wins 的 `drag.axSizeSettable` 就是这一步的具名环节**（它的更新日志里 3.5 也写了「自动忽略无法调整大小的窗口」）；Rectangle 的做法是提示「达到最小尺寸」。
- **我们的现状**：`isAXSizeSettable` 定义在 `Window/AXWindow.swift:83`，**唯一调用点在同文件 `:101`**——只用在了卷帘条自身。**魔法平铺（`Core/MagicTiling.swift`）与排布（`App/ArrangeController.swift`）完全没接。**
- **改成什么**：排布前判断；做不了时按 [scorecard](scorecard.md) 的 R46「浮窗说一句，不假装做了」给出可见说明。
- **怎么验**：计算器／系统设置参与排布时出现说明，而不是静默不动。

### C 组：记在账上，按需取

**8. 还原时压掉 App 自己发的 `unhideAllWindows`／`orderFront`**（WindowMizer 的 `Suppressed unhideAllWindows orderFront for CollapsedWindow during restore guard`）——App 会在我们还原时插一脚抢顺序。**待核**我们的折叠还原路径有没有这一条。

**9. 孤儿占位条要主动收掉 ＋ 还原串行队列带深度**（WindowMizer `Reduce produced orphan placeholder; closing`／`Queued serial placeholder restore queueDepth=`）。我们有折叠事务（`App/FoldTransaction.swift`），但这两条没有。

**10. 收起高度读 `axToolbarH`**（WindowMizer `Finder reduceToTitlebar … axMinH=%f axToolbarH=%f`）。我们逐 App 记常量（`fixedNonstandardChromeHeight(pid:)`），**没读 AX 工具条高度**。

**11. 与别的系统工具互通，而不是抢地盘**——**四家**：MediaMate 内置 Lunar 支持 ＋ 一整个 `BetterDisplaySupport/` 模块；Alcove 与 MediaMate 都带 `betterDisplay*` 字段；ChainYourMac 检测别的窗口管理器。我们现在只对 Swish 说一次。

**12. 接管系统 HUD 必须留一个「还给你」的开关**（MediaMate 的 `Disable Hiding Native OSD`）。我们压掉系统 OSD 时没有这条路。

**13. 崩溃上报**（WindowMizer 内嵌 PLCrashReporter，并收集 `hw.model`／`kern.osrelease`）。[production-maturity](production-maturity.md) 里我们那条至今空白。

**14. 成本感知的快照缓存**（Alcove 的 `cachedSnapshotCost`／`cachedSnapshotCosts`：不是「都缓存」，按代价决定留哪个）。我们的 `Capture/ShareableContentCache.swift` 是短 TTL 缓存，没有成本维度。

**15. 启动台读系统那份 SQLite**（LaunchOS 的 `SELECT item_id, title, bundleid, storeid FROM apps`——正是 Launchpad 数据库的表结构）。启动台（85）这一格的直接可查路径；**要核当前系统版本的路径与字段，且系统升级会改 schema，必须有回退**。

**16. 手势按类别分栈**（Swish 的 12 个原语 ＋ 九类设置栈）。我们是单文件 `App/TrackpadGestures.swift`（2200+ 行）。

**17. Secure Input 的可见说明**（OmniWM：菜单栏一个红锁 ＋ 一行说明「哪些快捷键被 macOS 扣住了」）。我们只在 `App/HabitContext.swift:844` 把它当排除项用，**用户看不到原因**。

## 三、顺序与理由

1. **A 组三条先做**：它们都是「装了几个月之后忽然不好用」那一类，**用户感知最强、而我们完全没有防线**；改动面小、可单独验。
2. **B 组 4／5 条**：一条抬窗口浏览那一格，一条是数据安全。
3. **B 组 6／7 条**：把「做不了」变成「说得出」。
4. **C 组**按需。

## 四、来源

- 机制与函数级证据：[竞品深挖](competitive-deep-dive.md)（含 Ghidra 12.1.4 的函数级结果与取用方法）。
- 失效家族与「我们暴露在哪」：[更新日志里的 real-world know-how](changelog-knowhow.md)。
- 我们的分数与欠账：[scorecard](scorecard.md)。自己的代码位置以本文档的行号为准，改完要同步回对账。
- **界线不变**（[竞品深挖](competitive-deep-dive.md)§一）：不绕过保护措施；不搬代码；GPL 那几家只借思路；每一条标「观察」或「推论」。
