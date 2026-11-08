# 向生产级成熟演进：竞品 know-how 落地 + 长效机制

2026-10-14。依据：[竞品深挖](competitive-deep-dive.md)（九份正版件验签＋静态面＋呼叫轮廓、DynamicLake 79 版更新日志、DynamicLakeKit 官方文件、ChainYourMac／OmniWM／WindowMizer 等的一手材料）、[每个领域的分数](scorecard.md)、[蓝图](blueprint.md)、[方向](direction.md)。

这一份只回答一个问题：**把竞品那些「看起来成熟」的东西，变成我们可执行的下一步和一条能一直跑下去的路。**

## 一、先说结论：短板不在工程质量，在**出货**

先说我们**已经有的**（核实过，不是自夸）：

- **工程纪律强**：隐私登记（[privacy-page.md](privacy-page.md)，65 个登记项）、**228 个 Swift 测试档 ＋ 215 支 runner 脚本**（`tests/`，自制的 `@main + expect` 模式）、成套真机探针、[设计文法](design-grammar.md) 388 行四层分工、[逐条对账](design-grammar.md) 的对照账。
- **签名有了**：`prototype/WindowShade.app` 有代码签名（`Apple Development: openkams@gmail.com`，Team `FVGLY6W6S4`）。
- **自动更新已经接好**：`prototype/Vendor/Sparkle.framework` ＋ `prototype/App/UpdaterSparkle.swift`／`UpdaterCopy.swift`——这一条不用再从头做。
- **历史上发过版**：`git tag` 有 **22 个**（v1.0.5 … v1.0.15）。

**缺的是出货节拍和分发门槛**：

| 事实 | 出处 |
| --- | --- |
| `v1.0.15`（2026-09-26）之后 **170 个提交、0 次发布、0 个新 tag** —— **已作废（2026-10-15）**：1.0.16 已于 2026-10-14 发布（appcast 1 条、tag v1.0.16）；但**同版本号重发到第七次**——发布恢复，节拍未稳 | 原文：[gpt6-review/README](handoff/gpt6-review-2026-10-06/README.md)；更正依据：本机 `git log` ＋ `site/public/appcast.xml` |
| 应用内检查更新／一键更新／坏包换回都做了，但**「一次真实的下载安装还没走过」** | [scorecard](scorecard.md):41 |
| 构建 `flags=0x0(none)`——**没有 hardened runtime** | 本机 `codesign -dvvv` |
| 分数**没有一格经过 Aaron 或用户亲手确认** | [scorecard](scorecard.md):44 |
| 公証与 Developer ID：**都没有**（只有 Apple Development 凭证） | 本机 `codesign` ＋ [direction.md](direction.md):37 |

**对比竞品：九份正版件，九个 `flags=0x10000(runtime)`、九个 Gatekeeper `accepted / Notarized Developer ID`。** 这就是「生产级」与「实验产品」在他们眼里最大的分野——不是功能多少，是**别人能不能安全地装上你的东西、你能不能持续地发出去**。

## 二、竞品在这九件事上的一致做法（逐条带证据）

| 生产级要件 | 竞品证据 | 我们（已核实） |
| --- | --- | --- |
| Developer ID 签名 ＋ 公证 ＋ hardened runtime | Wins 3.5.1／Alcove／Swish／ChainYourMac／LaunchOS／Notchy／Droppy／DockMate／MediaMate／WindowMizer **全部** `accepted / Notarized Developer ID` ＋ `flags=0x10000(runtime)` | 有签名但是**开发凭证**；`flags=0x0`；**无公证** |
| 自动更新 | Wins／WindowMizer／MediaMate 内嵌 **Sparkle**；Alcove 自家；ChainYourMac Sparkle | **已接好**（Vendor Sparkle ＋ UpdaterSparkle.swift），但端到端没验 |
| 固定发版节拍 | DynamicLake **79 版 / 2024→2026**；ChainYourMac **两天三版**；WindowMizer **66 版**并带 release notes | **170 提交 / 0 发布** |
| 登录项 helper | Wins `WinsHelper.app`；DynamicLake 1.0 `LaunchAtLoginHelper.app` | 有登入项相关代码（`WindowShade.swift`／`Preferences.swift`），未核 |
| 崩溃自愈 ＋ 日志 | ChainYourMac 官网明写 **「self-healing engine」**＋引擎日志 | **未见** |
| 私有 API 隔离 | Alcove／MediaMate：**主 App 0 个 `MR*` 符号，18 个全在 XPC helper 里** | 我们完全不用私有（更干净），但也**没有隔离层** |
| 扩展／自动化面 | OmniWM `omniwmctl` NDJSON socket；ChainYourMac URL scheme＋Raycast＋CLI；DynamicLake Market＋Plugin（`.dynamiclakeplugin`＋JSON socket） | [niri.md](niri.md):91 列为**不追** |
| 把设计规矩写成**可检验条款** | DynamicLake Design Guidelines：紧凑区不放描述性文字／不放旁人可见的敏感信息／不放推广 | [design-grammar.md](design-grammar.md) 有准入，**缺「常驻可见面」的内容级规矩** |
| 支持面 | DynamicLake：FAQ 16 题、Discord、逐版 changelog、10 条实名口碑（其中一条专夸修 bug 快） | 有详尽内部文档；对外支持面未见 |

## 三、动作清单（分成两组，差别是「要不要先花那笔钱」）

### A 组：不必等开发者账号，今天就能动

1. **发版列车（最高优先，其余动作都挂在它上面）**：把「发布」从一次性事件变成节拍。一条脚本走完：版本号 → `build.sh --check` → 签名 → 打 tag → 写 appcast 条目 → 生成 release notes。
   **2026-10-15 已定案（Aaron）**：**发布这一步由 Aaron 点头，不自动发**——所以列车要拆成两段：**① 准备候选包 ＋ 一页发布清单**（版本号／build 号／`--check` 结果／探针结果／appcast 条目／release notes 草稿）；**② Aaron 回一句「发」之后，分发动作由脚本一次走完**。
   **瓶颈的成因不是授权，是签字的成本**——所以这一条的执行标准是**把签字压到 30 秒**，而不是把授权拿掉。
   **验收**：连续两周、**每周至少一次候选包 ＋ 一页清单**；`git tag` 更新；旧版 App 能通过 appcast 看到新版本。**若某一周连候选包都出不来，说明任务没收敛，要回头看而不是延长周期。**
2. **打开 hardened runtime**：`codesign --options runtime`——**开发凭证也能开**，与账号无关。
   **验收**：`codesign -dvvv` 显示 `flags=0x10000(runtime)`；**探针全绿**（风险在运行时行为变化，所以先跑探针再合入）。
3. **把更新链路端到端跑一次**：[scorecard](scorecard.md):41 自己记着「一次真实的下载安装还没走过」。
   **验收**：旧版 → 检查更新 → 下载 → 安装 → 重启后是新版，且**辅助功能与屏幕录制授权不丢**（[direction.md](direction.md):37 已经分析过为什么不会丢，现在把它验掉）。
4. **自愈与诊断（两层）**：
   - **进程级**（照 ChainYourMac 的做法上最小的一条）：崩溃或被 `kill -9` 之后能自己拉起，并留一份**人类可读**的日志说明发生了什么。
     **验收**：杀掉主进程后自恢复；日志能读出「什么时候、因为什么、重启了几次」。
   - **常驻子系统级**（照 DockDoor 的做法，见[竞品深挖](competitive-deep-dive.md) 第四节的 14 条）：长驻的窗口管理器必须有一套**周期性的自我体检**，而不只是「被动等系统报错」。DockDoor 的 5 秒看门狗一次查五件事——AX 权限被重新授予、Dock 进程换了 pid、**订阅的 AX 元素失效**（`invalidUIElement`／`cannotComplete`，原文注释：「If the dock rebuilds its UI, the element becomes invalid and notifications stop」）、订阅的元素对象换了、**`CGEvent.tapIsEnabled(tap:)` 为假**；另有一个**事件投递金丝雀**（给自己投一个带魔数 subtype 的 `.applicationDefined` 事件，收到才算「还发得出事件」，连续两次没回来就重建全部 observer 与 tap）。
     **我们已有的**（被动那一半，五处）：`GlobalInputFilter`、`ScrollTap`、`WindowSwitcher`、`TrackpadGestures`、`NotchLevelObserver` 都处理了 `tapDisabledByTimeout`／`tapDisabledByUserInput` 的重开；`AXWindow.swift:441` 也挡了 `invalidUIElement`／`cannotComplete`。
     **我们缺的**（主动那一半）：没有 `tapIsEnabled` 的周期巡检（grep 不到），没有事件投递金丝雀。**tap 若在没有 `tapDisabledBy*` 事件的情况下死掉，我们不查。**
     **验收**：人为停掉一个 tap（或让它超时死掉），5 秒内自愈且日志说明；模拟「系统不再送我们的合成事件」，能自愈。
5. **真人验收闸门**：这是**我们自己写在 [scorecard](scorecard.md):44 的规矩**（「没有一格经过 Aaron 或用户亲手确认」）。
   **验收**：每一格标注「谁、在哪个签名构建上、什么时候确认过」；**对外数字只引用已确认项**（R30 也是这个意思）。
6. **常驻可见面的三条内容规矩**（借 DynamicLake，写进 [design-grammar.md](design-grammar.md) 准入）：紧凑区**不放描述性文字**（只放时长型内容）、**不放旁人可能看到的敏感信息**、**不放推广文字与无关动作**。
   **验收**：常驻面出现其中任一项即不合规。
7. **扩展面表态**：要么在 [blueprint.md](blueprint.md) 里写明「不做，理由是 X」（现在 [niri.md](niri.md):91 只有一句「不追」），要么做**最小切口**——`windowshade://` URL scheme ＋ 一个 CLI。三家竞品都发了，这是**市场期望**而不是可选项。
   **验收**：文档里有明确立场；若做，最小切口能被一条脚本调用。
8. **竞品 changelog 进料机制**：见第四节。

### B 组：要先开 Apple Developer Program（$99/年，只有 Aaron 能决定）

9. **Developer ID 签名 ＋ 公证 ＋ stapler**。有了账号，这就是脚本里的两步：`xcrun notarytool submit` ＋ `xcrun stapler staple`。
   **验收**：`spctl -a -vv` 返回 **`accepted / source=Notarized Developer ID`**——就是竞品那九份的样子。
   **为什么这条重要**：现在这份构件是开发凭证签的，别人机器上装不了（Gatekeeper 会拦）。**没有这一条，前面所有成熟度都出不了这台机器。**

## 四、长效机制：把上面变成能一直跑的四件事

前一节是一次性动作；这一节是为了**不再回到「170 提交 0 发布」**。

1. **发版列车（固定节拍）**：一周一版，不做例外。版本号、changelog、签名、appcast 全部脚本化——`prototype/build.sh --check` 只是列车的第一站，不是终点。
   **配套（2026-10-15 定案）**：发布由 Aaron 点头；**候选包与一页清单必须是自动产出的**，否则签字成本降不下来、节拍就还是假的。**版本号纪律（规格 R34）从下一次发布起生效：重发必须递增 `CFBundleVersion`，不再出现「第 N 次同版本号重发」。**
   - 反例就在眼前：DynamicLake 靠**一周多版**把 79 个版本堆出来，ChainYourMac 两天发三版；我们攒了 170 个提交不发（截至 10-06）。**2026-10-15 更新**：1.0.16 已发布，但重发到第七次——反例从「不发」变成了「发得没有版本号纪律」，R34 就是冲这个来的。
2. **生产就绪清单（每版必过，过不了就不发）**：
   - [ ] `build.sh --check` 退出 0、无新增降级警告
   - [ ] 探针全绿（真机，签名构建）
   - [ ] 隐私登记无「新增未登记」项
   - [ ] 签名正确（B 组后可加：公证通过、`stapler` 装上）
   - [ ] appcast 条目写好，旧版能读到
   - [ ] release notes 写好（用户能看懂「这一版修了什么」）
   - [ ] scorecard 里被这一版改动的格子，标注「谁在哪个构建上确认」
3. **竞品进料表**（我们这一轮手工做的，改成常设）：一张表，每次竞品发版就加一行——**谁、什么时候、哪个版本、从它的 changelog 里抽到几条候选验收用例、进了哪条探针**。
   - 现成底稿：[更新日志里的 real-world know-how](changelog-knowhow.md)——**11 个开源项目／同场的 626 个 release 已按 13 个失效家族归好，逐条标了「我们已在做／部分／未做／待核」**；再加上 [docs/dynamiclake-changelog.md](dynamiclake-changelog.md)（79 版／1,946 行）、[竞争深挖](competitive-deep-dive.md) 里 WindowMizer 的 223 条修复史、Wins 3.1→3.6 与 LaunchOS 37 个版本。
   - 这些是拿来做验收用例的，不是拿来看的：**它们修过的边界，就是我们该验的边界**。上面那份文档第四节已经把「先做哪条」排好了序。
4. **季度复评**：重跑这一轮的四步（**验签 → 回答「要不要绕保护」 → 静态面 → 呼叫轮廓**），拉一次各家的最新 changelog，更新对照表。
   - 门槛已经现成：`spctl -a -vv`（验签）、`otool -l | grep LC_ENCRYPTION_INFO`（闸门）、`nm -u`（符号面）、`xcrun llvm-objdump` ＋ 本文档第三节的呼叫轮廓脚本（函数级）。

## 五、这一轮从竞品身上真正拿走的东西（按性质分三类）

- **可以直接抄的做法**：宿主／内容方契约（谁拥有形状、谁只填 slot）；常驻可见面的三条内容规矩；真机验收用例（从它们的修复史里取）。
- **印证我们方向对的**：AX ＋ 观察者驱动（Wins 也是）、公开 API 优先（九家里只有四家用私有且瓶颈在预览与刘海覆盖）、私有 API 关进 XPC 的隔离模式（我们不用私有，但这是一条「万一要用」的干净做法）。
- **它们做得比我们成熟的**：出货面全部（签名层级／公证／节拍／release notes）、**常驻子系统的周期巡检**（我们只做了被动那一半：五处 `tapDisabledBy*` 重开，缺 `tapIsEnabled` 巡检与事件投递金丝雀）、扩展面、对外支持面。

**一句话**：竞品教我们的不是功能，是**把功能变成产品的那些动作**。而这九条里，**八条今天就能动，只有一条要你先花那笔钱**。
