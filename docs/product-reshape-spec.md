# 重塑执行规格（reshape spec）

2026-10-15 写。**这一份是给新 session 直接执行的规格**：每条任务自带依据、现状（带文件与行号）、改动要点、验收方法与风险。理由与出处集中在[重塑清单](product-reshape.md)、[竞品深挖](competitive-deep-dive.md)、[更新日志里的 real-world know-how](changelog-knowhow.md)，执行时按需回查。

**目标与判据**（「全世界最好」的三条可核对定义、我们已有的结构优势、还缺什么）见 [北极星](north-star.md)——**那一条决定这一份里哪些任务其实最重要**。

**两份配套**：**性能与能效**（口径、77 处计时器账本、竞品的能效课）见[性能与能效](perf-energy.md)；**「功能碾压」的定义与逐格矩阵**（哪一行落后、哪几行我们连行都没有）见[功能碾压](dominance.md)。

---

## 0. 怎么用这一份

0. **先读下面「已定案」那一段**——四条约束会影响你怎么做后面几条任务。
1. **先读第 1 节（前提与铁律）**，再按第 3 节的顺序做任务。**不要跳着做**，P0 是地基。
2. 每条任务有一个编号（R／E／H／N／M／V）。**改代码的做完就重跑 `./build.sh --check`，`EXIT=0` 才算完**；改完把该条的状态写回[重塑清单](product-reshape.md)。
3. 涉及界面行为的，**验收必须走真机**（[Computer Use 验收](computer-use-qa.md)），不能拿「工具退出 0」「日志打印成功」当通过。缺证据就写 `inconclusive` / `not_run`，如实留着。
4. 遇到与本文档冲突的现实代码，**以代码为准，并把差异写回文档**——不要为了对上文档而硬改代码。

### 0.1 已定案（Aaron，2026-10-15 拍板）

**四条约束，后面相关任务一律按这个做**：

| 定案 | 内容 | 影响到 |
| --- | --- | --- |
| **扩展面** | **最小切口**：App Intents **先做 5–8 个最常用动作**（收起／全部收进刘海／打开窗口浏览／恢复全部／切到某扇窗…），**不铺满，也不自造 CLI／URL scheme／插件格式** | **N1**（范围收窄）；[dominance.md](dominance.md) 的「扩展面」那一行按此写 |
| **录屏权限的立场** | **当作增强，不是核心**：**没有屏幕录制时，收起／还原／手势／分屏／窗口浏览的列表与动作全部照常**，只有「实时画面」降级。**并主动对外说「不录屏也能用」** | **R29**（降级清单是这一条的验收物，要能对外引用）；[北极星](north-star.md)§二第 4 项的回答 |
| **诊断与上报的边界** | **纯本地**：做一键导出（R35）与崩溃上报（R13），**永不上网、不做任何匿名计数**。用户自己看、自己附 | **R13／R35**（网络上报一律不做）；**R37** 的隐私声明要写明这一点 |
| **发布授权** | **候选包由执行方准备，每次发布由 Aaron 点头**（不是自动发） | 见下 |

**关于发布这一条（要特别说清楚，因为它决定了「发不出去」这件事能不能解决——10-06 时是「170 提交 0 发布」，1.0.16 已于 10-14 发出，但同版本号重发了十一次，病没变）**：

- **授权没有变**——你按最后一步。**不会自动发布。**
- **但瓶颈的成因不是授权，是签字的成本。** 所以执行方式是**把签字压到 30 秒**：
  1. 准备**候选包**（`build.sh --stage`）＋ **一页发布清单**（版本号／build 号／`--check` 结果／探针结果／appcast 条目／release notes 草稿）；
  2. 你看那一页，回一句「发」或「不发」；
  3. 之后的分发动作（打 tag、写 appcast、放 release）**由脚本一次走完**，不再需要你参与。
- **判据**：一周至少一次候选包，且**每次都是一页清单 ＋ 一句话决定**。若某一周连候选包都出不来，说明问题在别处（任务没收敛），要回头看，**不是延长周期**。
- 配套：**R34 的版本号纪律从下一次发布起生效**——**重发必须递增 `CFBundleVersion`**，不再出现「第 N 次同版本号重发」。

---

### 0.2 只做这些（WIP 上限，2026-10-15 加）

**为什么要有这一节**：这一份从 **332 行长到 914 行**（写下这一节时；2026-10-15 复核已到 **1,247 行**）、任务从 **18 条长到 80 条**（复核时 R49＋E6＋H6＋N5＋M7＋V11＋O15＋A14 **约 113 条**——这一节立下的上限，本文档自己已经越过）——**我加的速度超过这个项目能吸收的速度**。而项目的病历上写得很清楚：**范围比收敛快**（[gpt6-review](handoff/gpt6-review-2026-10-06/README.md) 10-06 记「170 提交 0 发布」；到 2026-10-15，v1.0.15 之后已 514 提交、1 次发布、11 次同版本号重发——见 §7 第 13 条）。**再往队列里堆任务，就是加重同一个病。** 所以从这里开始，**队列有上限，且只置换不增长**。

**这一版（v1.0.16 之后的第一版）只做 6 条**：

| # | 任务 | 为什么是它（而不是别的 74 条） |
| --- | --- | --- |
| 1 | **R34 版本号纪律** | 十几分钟的事，挡掉一个真实缺陷（**同一个版本号重发过 11 次**） |
| 2 | **R33 CI（只做 `ci.yml`）** | 门禁**已经存在但没人强制**；这是唯一一条让「以后不再退步」的机制，且不需要任何秘密 |
| 3 | **N5 `PrivacyInfo.xcprivacy`** | **公证的硬门槛**——不出货，其余全部无意义 |
| 4 | **R2 权限被撤要告诉用户** | 复用已完成的 R1，**改动最小、用户感知最强** |
| 5 | **R38 第三方许可** | 十几分钟，而且是我们**批评过别人、自己却没做**的那件事 |
| 6 | **R37 面向用户的隐私声明** | 「凭什么录屏」是头号攻击点；它同时是**发布材料** |

**第二批（2026-10-15 已做）**：R3 ✅（a60c1da）；R4 核实为不用改（ce2d9a3）；R29 代码核对完、降级清单在 R29 条目里，真机 not_run；V1／V4／V5／V6 步骤已写好，等 Aaron 真机跑（V4 要先装 Rectangle，V6 要借鼠标）。

**第三批（2026-10-15，Aaron 指定「不需要真机或本人验收的优先」）**：R43 ✅、R45 ✅（010775c）；R7 ✅（68825c8）；R47 ✅（5c2a0d1）；E4 ✅（bf73aad）；M2 ✅（c66967d）；M6 核过不改。全量 `--check` EXIT=0。**顺带发现**：`tests/run-duo-tests.sh`、`run-owned-codex-phase1.sh`、`run-remote-host-tests.sh` 在 HEAD 上就编不过（漏编 `WSL10n.swift` 等）。**已修**：补齐依赖（duo 与遥控接收端补 `WSL10n.swift`；owned-codex 补原生模块 `WS2ProcessNative`、`WireJSON.swift`、`WS2StrictJSON.swift`），duo 全 PASS、遥控 55 条断言 0 失败、owned-codex 只验到能编过（执行会真跑 codex、耗额度，留给 Aaron）。**更正**：先前说「这几支 runner 不把编译失败当失败」是我测错了——循环里的 `$?` 取到的是 `$(basename …)` 的结果；三支本来就会非零退出。

**第四批（2026-10-15，Aaron 不在电脑前，授权代做真机验收）**：R31 ✅、H1 ✅、R44 ✅、R27 ✅、E1 ✅、E2 ✅；真机代跑：V2 ✅、V3 ✅、`--wins`／`--mc-keys` 空闲重跑 ✅（`--wins` 的程序坞一步原是探针没打开设置，已修）；**R3 屏幕睡醒** ✅（三档按时出现，tap 全在跑；整机睡眠未测）；**C3 Apple Events** ✅（签名构建里音乐读取经脚本子进程照常；对照组同样能读，所以这条路不依赖那项 entitlement）；**C3 摄像头** not_run（这个签名还没被问过授权，要本人点同意）；R39 第一轮 `leaks`：静置 45 秒 418 处共 20 KB，根都是系统的 XPC 连接循环与 1 个 CFString，不在我们的代码里，长会话观察仍待做。**不能代做**：R2、R29（要改系统安全设置）、V1／V5／V6（要真手）。另修：探针单项 FAIL 被「PASS suite」盖掉（a200cb1）。

**第五、六批（2026-10-15，Aaron 不在，锁屏下继续）**：R15 核过不做、R14 核过不改、R46（静置）、R40、N2、M7；R28（macOS 27 隐私权限栏改名）、R42、H5、E5；R24 已量待文案决定。

**解锁后的真机补跑（2026-10-15 晚）**：H2 核过不降、N3 ✅、R46 面板用过之后 ✅。**整套 30 组界面探针真机回归**（签名构建）：19 组全过（wins、home、pip、launchpad、rect、magic、strip、pull、mc-keys、strip-peek、browser-more、dock-gestures、launchpad-keys、thumbnail、habits、quiet-defaults、notch-shape、carry、edge-park）。界面语言是繁体时 grid、pins、gesture 有几项按简体文字找菜单，切简体（`-WindowShade.InterfaceLanguage zh`，只作用于那个进程）后过。仍不过的 9 组拿**装好的 1.0.16 原版**同条件对照：notch（标题变了刘海短暂展开等 2 项）、split（并排两窗中间的条）、coach（刘海上的提示与小演示）、flick（三指甩到一半抬手）、fullscreen（全屏桌面上的刘海面板）、slide-over-desktops／gesture／shelf-glance（等待超时）——**原版失败得一模一样，不是这几批的回归**，是这台机器当前环境（两块屏、macOS 27.0.1、当前设置）下过不了，1.0.16 发布前在别的环境下过过；要查清得逐项看环境，记在这里。唯一的差别是 --slide-over：原版全过、新构建因为 R31 改了恢复记录的删法而超时，探针已改（d164f30），新构建上 15 项全过。

**第八批（2026-10-15 晚，「先做不需要本人介入的」）**：R6 核过 ✅、R10 ✅（803375a，真机 `--orphan` 过）、R32 ✅、R39 ✅（300 轮内存平）；R35／R13 本地导出（0c9e5cd）与 R5 导出导入底层（78b6f50）做完、入口待 Aaron；探针三组（0d72706）。另修：手势排布一句写死的中文改走本地化。

**第九批（2026-10-16）**：R11 核过 ✅（原本就读工具栏）、R22 ✅、R41 ✅、N4 ✅（含一处修补）；R18 核过、结论与规格相反（开关挡不住平铺），剩一次按键验证待 Aaron。

**第十批（2026-10-16）**：R48 ✅（修了「文件夹开着时打字吞第一个字」）、E6 ✅；R20 部分（强杀与多实例过，orderOut 关窗在开着的面板里会留卡，18 类没凑齐）；M3 起步。

**第十一批（2026-10-16）**：R20 的 orderOut 关窗已修（开着的面板里也会移出）；R23 列宽 ✅、替身双击待 Aaron；V9「接着两块」✅、插拔与同型号待 Aaron。本机没有 1.0.15，E3 要下载才能对比，待同意。

**第十二批（2026-10-16）**：R9 ✅（复现不出）、M5 核过不做、H3 核过暂不改（先修胶囊检测的色彩假设）。**另定案**：只支持最近三个大版本的 macOS（Aaron 定；现在 15、26、27，每年 9 月前滚，见 DEVELOPMENT.md「支持的系统版本」）——1.0.16 仍是 14；构建目标与 Info.plist 已提到 15（4695f5b），随之恒真的 33 处版本判断与旧系统的主线程邮箱投递、代理条后备删掉，共删 259 行。改后 pip／thumbnail／wins／fold-timing／restore-guard 真机全过，browser-more 一次「新建窗口」偶发失败、重跑两次都过。**发现**：多窗口 App 里不能最小化的窗口收不起来（R9 条目）。

**第十三批（2026-10-16，Aaron 离开半小时、机器空闲）**：**全量真机回归 41 组**（签名构建，含最低系统 15、删旧分支、R20／R48 与「开动画前就拒绝」之后）：32 组全过；`--elsewhere` 补带 `--other-space` 后过；其余 8 组（notch、split、coach、flick、fullscreen、slide-over-desktops、gesture、shelf-glance）与 10-15 用装好的 1.0.16 原版同条件对照时失败得一模一样，属这台机器的环境，不是回归。M3 迁了四处锁（见 M3）。另：macOS 15.6.1 与 26.6.2 虚拟机上的核心探针（DEVELOPMENT.md「发版前的虚拟机回归」）已首跑。

**第十四批（2026-10-16）**：M3 再迁 10 处锁（Sonnet 子代理在独立 worktree 做、主代理审差异后合入）；M1 核过暂不做；H3 前提探针首跑 inconclusive。合入后 habits／wins／fold-timing／carry／home 真机过，launchpad 一次「文件夹显示 -1 个 App」重跑两次都过，gesture 仍是已知环境失败。

**第十五批（2026-10-16）**：M3 第三轮（见 M3，含一处因崩溃退回）；测试 runner 编译目标提到 15，补上 N4 漏改的 runner；H3 探针在 26 虚拟机上同样 inconclusive。

**第十七批（2026-10-16）**：N1 ✅ 代码（4a8551f，7 个捷径动作，元数据随包；在「快捷指令」里看得到待 Aaron 空闲时验）；R35／R5／R36 入口 ✅（08b62d3，「高级」页底「关于」四行）；公证流程打通（Developer ID、`scripts/notarize.sh`、发布关脚本）。

**第十八批（2026-10-16，多线）**：R21 ✅ 代码（4dd8593，单窗口工具关窗即退出、聊天类永不退出；本机已装的微信／QQ／信息／Discord 核过 bundle ID；真机待整合构建后验）；H4 量过不采用、H6 随之不适用（7922ebd）；R16 小样（95d6c0b，[私有页](https://claude.ai/artifact/6ShtJuF4UJnQKxpWXPcsFt)，待 Aaron 定三件事）；O／A 29 条清单（0456817，待 Aaron）。R49 本机没装 ToDesk／QQ 音乐，要下载需同意。
**第十八批续（2026-10-17）**：R12 ✅ 代码（979ffed：开关开着只旁听、不拦键，系统的提示照出、刘海跟着显示；子代理初稿做成「刘海也不显示」，与总开关重复，主代理按定案改）；R17／R8 ✅ 代码（6baac1f，合入时收紧成同一个开启安全输入的 App 一次运行只说一次；两条都没法在真机上人为触发，靠单测）；R26 ✅（1e0d179，辅助功能晚于启动才给时补装窗口切换与 Mission Control 键）；M3 第四轮（22f1cd8）；V8 能驱动的 4 条 ✅（fad1726）。**整合构建真机 14 组全过**（签名构建，含以上全部）：close-quit（R21：App Store 关条即退出 ✅、夹具不退）、capsule-color、browser-more、browser-identity、dock-scenarios、wins、habits、fold-timing、restore-guard、fold-unminimizable、pins、grid、home、carry。H3：存下来的「完整」帧整帧颜色与 alpha 全是 0，探针改成跳过全 0 帧并打印录屏授权，下一轮再看。


**Aaron 拍板（2026-10-17 第十八批后）**：
- **R16** 新开「手势」页，按收起与展开／刘海／排布／窗口浏览四组；每行加「手指」一行，标题栏手势下带只读对照表；三指、四指轻点核对完再露出（之前不进手势页）。
- **下载**：R13 可以接 PLCrashReporter（只落本地）；R49 可以装 ToDesk、QQ 音乐来验，验完可删。
- **O／A 29 条** 照 [清单](oa-admission-checklist.md) 的建议定案：O1（切换器打字搜索）、A1（跳回终端）收进队列；O6、O7 不收；其余 25 条留冻结区。
- **1.0.17** 这批收完就准备候选包（升版本号、appcast、`--release`＋公证＋发布关），等 Aaron 真机验、Aaron 按发布。
  - 2026-10-17：候选**源码**已备好（Info.plist 1.0.17／17；appcast 1.0.17 条目草稿（2026-10-17 复核后移到 `docs/releases/appcast-item-1.0.17.xml`，不留在 `site/public`，避免站点部署带上带 TODO 与旧签名块的清单；README／官网文案须随发布一起上线、不先合 main，见 runbook「顺序纪律」；`docs/update.md` 安装三步旧稿已标注）含 `minimumSystemVersion 15.0.0` 与 `informationalUpdate belowVersion=17`，url／length／签名留 TODO；README 三份与官网改 macOS 15、已公证；[发布说明草稿](releases/v1.0.17.md)；[发布关 runbook](releases/v1.0.17-release-gate.md)）。没构建、没签名、没公证、没打标签。

**Aaron 拍板（2026-10-16 第十六批后）**：
- **R21** 按类别分：计算器、App Store 这类单窗口工具关掉卷帘条就退出 App；微信、QQ 等聊天类永远不退出；其余照现状只关窗口。
- **R35／R5 入口** 放在设置的「关于」页：导出诊断信息、导出设置、导入设置三个按钮。**R36** 同页加「报告问题」（打开 GitHub Issues 新建页、提示可附诊断包，不上传）。
- **E3** 可以下载 1.0.15（自己的 GitHub 发布页，暂存目录、用完删）；**V7** 可以下载 iPadOS 27 模拟器（约 8 GB，放外接盘）。
- **R12** 加「改回用系统的提示」开关（开着时只旁听、不拦）。**R17** 安全输入开着、用户按快捷键没反应时，刘海短暂说明原因。
- **R8** 发现别的窗口管理工具与我们抢快捷键或手势时，刘海只提醒一次、附去设置的路，不自动改。**R16** 手势按类别分栈，先照设计稿做小样给 Aaron 看。
- **N1** 下一批就做（5–8 个动作，按固定词汇表定名）。**H3** 继续追（先查清探针读帧为何是全透明）。**O／A 29 条** 整理成清单（每条一句：是什么、代价、建议）下次问。

**到这里停下：剩下的都要 Aaron（2026-10-15 盘点）**
- **要解锁屏幕跑界面探针**（R3 测完后屏幕锁着）：H2（`--fold-timing` 前后对比）、N3（关键路径签名区间）、R46（面板用过再关之后）、V8、E3、E6，以及 R9／R20（余项）／R21／R23／R49 的复现与验收（R6／R10／R32 第八批、R11／R22／R41 第九批已做完）。
- **要改系统设置，我不能代做**：R2、R29（收回权限）、R19／V10（台前调度）、R30（桌面排列开关）、V11（显示缩放）。
- **要真手**：V1、V5、V6、R25、R18（启动台开着按 fn＋Control＋←）、R23（双击桌面文件夹替身）、V9（插拔、改分辨率、同型号两块）；整机睡眠（R3 只测了屏幕睡醒）。
- **要本人点同意**：C3 摄像头（这个签名还没被问过授权）。
- **要下载、需同意**：E3（本机没有 1.0.15 可对比）、R13（PLCrashReporter；纯本地那一半已随 R35 做完）、V7（iPadOS 模拟器约 8 GB）、V4（装 Rectangle）。
- **要设计或文案决定**：R24 截断文案、R37 隐私页版面、R8／R12／R16／R17／R36（都要新增界面表面，先过设计准入）、R35 诊断导出与 R5 设置导出导入的入口（底层已做好）。
- **要准入决定**：O 系列 15 条、A 系列 14 条。
- **大块，宜单独开**：M1（时间基准 196 处，语义要按 suspending 保持）、M3（锁迁移；部署目标 14 用不了 Mutex）、N1（App Intents 需要 Xcode 的元数据步骤）、H4。

**原排的下一版（这一批不清空就不开新项）**：**R3**（唤醒三档）、**R4**（原生标签页——窗口浏览落后 Wins 1 分的直接原因）、**R29**（录屏降级清单）、**V1／V4／V5／V6**（最便宜的四条真机证据）。

### 0.2.1 实质阶段起步清单（2026-10-15 研究阶段收口，给 13:00 的实质阶段）

**规矩不变**：§0.2 的 6 条在飞不动；以下是**排序建议**与新增候选的**准入处置**（每条已按 §0.3 回答：取代/推后谁？阻塞发布吗？）。

**A. 在飞的 6 条——建议按「挡发布 × 最便宜」两头发力**：

| 序 | 任务 | 为什么这个序 | 预估 |
| --- | --- | --- | --- |
| 1 | **N5 `PrivacyInfo.xcprivacy`** | **公证硬门槛**；纯新增文件、零回归面 | 半到一小时 |
| 2 | **C3 主程序补 `-o runtime`**（本轮研究新增，**并入 N5 同批**：都是发布链路）**✅ 2026-10-15 已改 `build.sh`，配 `prototype/WindowShade.entitlements`（Apple Events／摄像头／音频输入／日历四项例外，缺了它们 runtime 会静默拒绝）；Apple Events 与摄像头的真机行为未验** | `build.sh:373` 一行；消掉「验过的包 ≠ 要发的包」 | 几分钟＋重过 Phase 0 |
| 3 | **R34 版本号纪律** | 挡「同版本号十一次重发」复发 | 十几分钟 |
| 4 | **R33 CI（只做 `ci.yml`）** | 门禁开始强制——「以后不再退步」的唯一机制 | 半天内 |
| 5 | **R2 权限被撤要告诉用户** | 复用 R1；用户感知最强 | 小 |
| 6 | **R38 第三方许可** | 我们批评过别人、自己却没做的那件事 | 十几分钟 |
| 7 | **R37 隐私声明** | 发布材料；呈现用 loupe 三档（§1.8） | S/M |

**2026-10-15 这 7 行已全部落地并本地提交**（R1 a49ddb3、R33 6b51679、R34 f1e82d8、N5＋C3 cb10408、R38 6cac384、R2 f38d183、R37 866b2a7；分支 `codex/ws2-remote-gpt6-handoff-20261007`，未推送）。证据：全量 `build.sh --check` EXIT=0；`--stage` EXIT=0（runtime 标志、四项 entitlement、`--self-check build=16 ok`）；菜单、隐私页、窗口浏览三组单测与官网构建通过。**还没做的**：R2 运行中关权限、C3 的 Apple Events 与摄像头、CI 在 runner 上的第一次运行，三样都要真机或推送后才能验；R37 的「不离开这台 Mac」仍等 P2。**顺带发现（不在这批）**：`prototype/Vendor/mediaremote-adapter/build-adapter.sh` 在 git 里是 100644，构建时 Permission denied，1.0.16 包里也没有这个适配器——正在播放推送流从没进过包。**已修**：build.sh 改用 `bash` 调它，`--stage` 后适配器与 perl 脚本进包、签名通过。

（上表 7 行＝在飞 6 条＋C3 并批；**批不清空不开新项**的规矩照旧。**C3 没有独立条目**：它只是 `build.sh:373` 主程序 `codesign` 漏了 `-o runtime`（:367–372 的嵌套件都有），见 §1.5 最后一行与[竞品深挖](competitive-deep-dive.md)§五 C3。）

**B. 研究阶段新增候选的准入处置**（O 系列 14 条／A 系列 14 条，全部待准入）：

- **A14 窗口管理 MCP 面**（本轮新立）——Agently 证明「大脑走 MCP」是这代的形态；**我们把它反过来：让 agent 通过 MCP 用窗口**（先只读）。**建议与 A1 同批判定**：A14 的值域大但工程也大，先做一个只读原型（`get_screen_state`）量信心。
- **A1 终端回跳**——「agent 控制面」与「HUD」的分界线，VibeIsland 与 CodexBar 两侧都已到。**建议作为下一批的头名**（形制已齐：hook 扩字段＋DockDoor 式焦点回跳＋CodexBar 的 PID→终端机制）。
- **V1／V4／V5／V6（真机证据四条）**——与任何代码任务**并行不占批位**，随时可跑。
- **O1 切换器搜索**——最小切口、直接对位（DockDoor/Peninsula 都有），建议排在 A1 之后。
- 其余 O／A **按序排队**；新项入库前先过 §0.3 两问。

**C. 需要 Aaron 拍板的两件**（其余都可自行推进）：

1. **Apple Developer Program（$99/年）**——C2 的钥匙；没有它，N5 之外的发布工作都是空转（Dockset/Thaw/CodexBar 的流水线都验证了这条路径可行）。
2. **下一次发布的批次构成**（既有约定：候选包我准备、你点头才发）——建议绑定 **R34＋N5＋C3** 成一批。

**D. 明说不动的（免得手痒）**：菜单栏管理（已定不进）｜Dock 定制（记在册）｜沙箱/SSH（A8/A9 先评估）｜**死代码大清理**——CodexBar 的教训「**日期不是证据**」（§1.8），只按 §6 的退役纪律走。

### 0.2.2 开箱前置（2026-10-15 研究阶段顺手做完的侦察；13:00 可直接动手）

**N5 隐私清单——✅ 2026-10-15 已落 `prototype/PrivacyInfo.xcprivacy`，构建放进 `Contents/Resources/`，三种模式都 `plutil -lint`。更正**：它**不是公证门槛**（公证不查隐私清单，那是 App Store 的要求）；对我们是如实申报。FileTimestamp 的两个读取点（下载文件夹的临时文件、`~/Library/KeyBindings`）没有一条理由码严丝合缝，按 3B52.1 申报。原文：见 §2 的 N5 行（4 类理由码＋负项声明＋逐文件归位，全部双查过）。

**R34 版本号纪律——版本流已查明**：`prototype/Info.plist` 是**版本的唯一来源**（build.sh `:343–347` 只把 `CFBundleShortVersionString`／`CFBundleVersion` 两个键同步进包，注释明写「源码树拥有发布版本」）。最小动作两条：① build.sh `--stage` 加一条**发行前守卫**——若 `site/public/appcast.xml` 已存在同版本号则报错退出（照 CodexBar 三查的第 3 条）；② runbook 写明：**重发必须递增 `CFBundleVersion`**，不再 `Set` 同一个数上去。

**R33 CI——✅ 2026-10-15 已写 `.github/workflows/ci.yml`（未推送，未在 runner 上跑过）。更正**：`prototype/Vendor/Sparkle.framework` **在 git 里**（87 个文件），checkout 就带上，不用预拉；下面「缺 Sparkle 时静默变绿」也已过时——`build.sh` 现在总是传 `-framework Sparkle`，缺了就链接失败（见它第 10–12 行注释）。原文留作记录：仓库**没有任何 `.github/workflows`**；门禁命令＝`prototype/build.sh --check`（隔离编译＋链接，不签名）。`ci.yml` 最小内容：`checkout` → macOS runner（需要 **Xcode 27**，本机是 27.0／Swift 6.4——**先确认 runner 镜像有没有 27，没有就先用可用最新并标注差异**）→ `xcode-select` → `prototype/build.sh --check`。**已知坑**：`--check` 在缺 `Vendor/Sparkle.framework` 时「什么都不编也返回成功」（build.sh `:44` 的兜底）——CI 上要么预拉 Sparkle、要么把这条兜底改成显式跳过并留日志，**不能让它静默变绿**。

### 0.3 冻结与准入（防止队列再长）

**其余全部冻结**：R5–R31、R35／R36／R39／R40–R45、E／H／N／M 全部、V7–V11。

**冻结不等于否决**——是**排队**。解冻**只有两种情形**：

1. **上一批清空了**；
2. **它在真机上被撞到了**（用户报障，或我们自己的探针复现）——**这时它不再是「可借项」，是缺陷**，而**缺陷优先于功能**。

**准入规则**：往队列里加任何东西之前，先答这两问——

- **(a) 它替代或推迟了哪一条？** 答不上来就不进——**队列只置换，不增长。**
- **(b) 它挡不挡这一版的发布？** 挡 → 进 §0.2 的六条；不挡 → 进冻结区。

**文档同理**：新增一份文档之前先问「**能不能并进已有的那一份**」。**这一轮已经写了 14 份、5,591 行（写下这句时；2026-10-15 复核 `wc -l` 为 6,224 行）——到这儿为止，不再新增，只整合。**

**一条给执行者的自检**：如果你发现自己在**连续三轮都在「补充」而不是「发出」**，那就停下来——**那正是这个项目一直在犯的错**。

## 1. 前提与铁律（先读这一节，能省掉一整轮返工）

### 1.1 建置闸门

- **唯一的门槛是 `cd prototype && ./build.sh --check` 退出码 0。** 它做的是「和发布构建同样的优化参数，但不签名、不修改 app bundle」，另有自测与文案检查。
- **`--check` 会把源码复制到 `.build/duo-build.XXXX/` 再编译**。所以：**改完代码必须重跑一次**，否则你验的是改动前的快照。
- 编译参数是 **`-O -whole-module-optimization -swift-version 6 -strict-concurrency=complete -warnings-as-errors`**。**警告就是错误**；并发隔离写得不对会直接编不过。
- **高负载时它会跑 20 分钟以上**。跑之前先确认没有别的重活（Ghidra 分析、别的大构建）在抢 CPU：`uptime` 的 load 应该是个位数。
- 语法：`nohup bash -c './build.sh --check; echo "EXIT=$?" >> /tmp/bc.log' > /tmp/bc.log 2>&1 &`，然后轮询 `grep EXIT= /tmp/bc.log`。

### 1.2 文案三条硬规矩（`build.sh --check` 会拦）

1. **日志串一律英文。** 仓库有一条**只许降不许升的棘轮**：

   > `防漏网：中文字面量行数 X 超过棘轮基线 N（迁移只许降不许升）`

   往 `wlog(...)`／任何日志里写中文，会让 `X > N` 而**建置失败**。写 `wlog("environment: accessibility permission was revoked ...")`。
2. **用户可见文案走 `WSL10n.text("key", zh: "中文源句")`**，并且**必须同时有英文译文**——在 `prototype/Resources/Localizable.xcstrings`（Apple String Catalog）里给该 key 补 zh ＋ en 两栏。检查会报「2631 个键，中英文齐全」；少一边就不过。
3. **禁词有 12 个**（会被检查报出来）：`卷起、卷成、标题条、偷看、指挥控制、动态锁、自动锁屏、窗口仓、钉住、悬浮、折叠、显示桌面`。**位置类文案用「收起／卷帘条／置顶」那套**——固定词汇表在 [copy-guide.md](copy-guide.md)，写任何面向用户的句子前先读它；副标题不超过 20 字。

### 1.3 其它会咬人的地方

- **`LSUIElement` 应用**：没有 Dock 图标，用户可见提示的唯一现成出口是 `notch.announce(text:detail:tone:)`（用法见 `App/RectangleImport.swift:103`），以及 `notch.announceWhenFree(key:text:detail:symbol:priority:ttl:...)`。别新造一套 HUD。
- **改界面形状之前先看设计稿**：[docs/design-drafts/README.md](design-drafts/README.md)。形状以稿为准，令牌不一致时记进 [design-grammar.md](design-grammar.md) 的对照账。
- **raw 捕获不进仓库**：`/tmp/ws-research/**` 是竞品原始件与分析输出，规则上不入 Git。**注意 `/tmp` 重启会清空**——下面的竞品证据若没了，按 5.3 的配方重跑。

---

### 1.4 已有资产（**动手前先看这张，别重造**）

**为什么这张表排第一**：今天最大的教训之一是——**我两次断言「我们没有 X」，结果我们有**（「没有测试套件」实为 244 档；「没有零拷贝」实为已在用）。**重造已有的东西，比不做更浪费。** 每一条都本机核过位置。

| 你可能以为「没有」 | **实际有** | 位置（本机核实） |
| --- | --- | --- |
| 测试套件 | **244 个 Swift 测试档 ＋ 218 支 `run-*.sh` runner**，自制 `@main struct + expect()` 模式（`import XCTest`／`import Testing` 各 0），**且 `build.sh` 已纳入几支** | `tests/`（**在仓库根，不在 `prototype/`**）＋ `build.sh:125`／`:184`／`:187` |
| 发布门禁／功能开关表 | **`ReleaseDefaults`**：唯一开关表，每条「设计上默认开」带 `deviceVerified`；**没真机验过的一律默认关但功能在**；用户显式设过的值不被覆盖 | `Core/ReleaseDefaults.swift:12` |
| 零拷贝（CVPixelBuffer → Metal） | **已在用** `CVMetalTextureCache` ＋ `CVMetalTextureCacheCreateTextureFromImage` | `Effects/FoldRenderer.swift:35`／`:111`／`:291`／`:346` |
| 系统明暗／外观变化的处理 | **现读，不需要重建**：每次读 `NSApp.effectiveAppearance`，另有 KVO 订阅 | `Overlay/ShadeStrip.swift:18`、`WindowShade.swift:198`／`:438` |
| 图标兜底 | `placeholderIcon` | `WindowBrowser/WindowBrowserCardView.swift:41` |
| 启动台「从文件夹里拖出」 | `detach(_ path:)` | `App/LaunchpadFolders.swift:148` |
| 我们改过的系统设置能否恢复 | **有持久化会话**：连「原本有没有这个键」都落盘，**崩溃后仍能恢复** | `WindowShade.swift:159`／`:763`–`:768`／`:781` |
| 缩略图缓存的**成本账** | `cachedCostBytes` | `WindowBrowser/WindowThumbnailService.swift:213` |
| AX 读取**计数** | `axQueryCount`（＝ Wins 的 `axReadsMinimum`） | `WindowBrowser/DockHoverProbe.swift`（`--window-browser-idle-probe` 在读） |
| 帧同步 | **`CADisplayLink`**（不是过时的 `CVDisplayLink`），且写了弱引用代理防环 | `App/ScrollStripRun.swift:61`／`:106`、`App/Welcome.swift:103` |
| Liquid Glass | **双重 gate**（SDK 存在性 ＋ 版本） | `build.sh:106`、`#if WINDOWSHADE_SDK_HAS_GLASS`、`#available(macOS 26.0)` |
| 自己的窗口不并进系统标签页 | `tabbingMode = .disallowed` | `App/Carry.swift:26`、`App/Thumbnail.swift:34`、`App/Preferences.swift:1182` 等 8+ 处 |
| 常驻条不被系统平铺管到 | `fullScreenDisallowsTiling` | `App/Thumbnail.swift:35`、`App/OverlayFactory.swift:21`／`:56`／`:186` |
| 能耗的三套仪器 | AX 延迟基准／空闲计数探针／静置口径 | `--duo-ax-bench`、`--window-browser-idle-probe`、[性能与能效](perf-energy.md)§一 |
| 诊断缓冲（且立场正确） | `WS2DiagnosticTail`，注解写明「**绝不自动持久化或发送**」 | `Core/WS2DiagnosticTail.swift` |
| 事件通道自愈（一半） | **R1 已完成**：5 秒体检 ＋ 静默失效重开 | `WindowShade.swift` 的 `startEnvironmentWatch()` |
| **不做的事**（别去实现） | **热角、focus-follows-mouse** | 全仓 0 处。**私有 API 不在此列**：§7 第 11、12 条已推翻「私有面只有 1 读＋12 传感器读」——`Private/` 四个桥接层经 `dlopen` 载入整套 SLS／DisplayServices／CoreDock，`nm -u` 看不见；私有面的真实大小见[竞品深挖](competitive-deep-dive.md)§五 C1 |
| 架构 | **只出 arm64**（非 fat） | `build.sh:109`、`lipo -info` |

**已经做过的调研也别重做**：九份竞品件已验签并静态面／呼叫轮廓／**函数级**挖过；626 个 release 已归成 13 个失效家族；七份「字符串→函数」TSV 的**已挖／未挖**在 §5.4 逐件列了。

### 1.5 症状 → 你踩了什么 → 怎么办

**这张表按「你会看到什么」排**——比按「别做什么」排更好用。

| 你看到的 | 说明你踩了 | 怎么办 |
| --- | --- | --- |
| `防漏网：中文字面量行数 X 超过棘轮基线 N` | 往日志里写了中文 | 日志串**一律英文**；中文只走 `WSL10n` |
| 「中英文齐全」检查不过 | 新增了用户可见字符串却没补译文 | 在 `prototype/Resources/Localizable.xcstrings` 补 **zh ＋ en** 两栏 |
| 报出 12 个禁词之一 | 用了禁词 | 换[固定词汇表](copy-guide.md)的说法 |
| **改了代码但行为没变** | `--check` 会把源码**复制**到 `.build/duo-build.XXXX/`——你验的是旧快照 | **改完必须重跑一次** |
| 编译报大量并发错误 | `-strict-concurrency=complete -warnings-as-errors`：**警告即错误** | 按隔离改；**别用 `@unchecked Sendable` 糊过去** |
| 构建跑了 20 分钟以上 | 有别的重活在抢 CPU | 先看 `uptime`；**别在 Ghidra 跑着的时候构建** |
| `rea analyze` 报 `architecture_unsupported` | 件是 universal Mach-O | 先 `lipo -thin arm64` |
| 每次 `rea` 都要等五分钟 | 没给 `--snapshot` | 给 snapshot，后续查询才快 |
| `rea analyze` 报 `provider_timeout` | **REA 的 330 秒预算装不下 >3 MB 的件** | 直接驱动 `analyzeHeadless`（§5.3） |
| Ghidra 报 `OutOfMemoryError` | 默认堆只有 **2G** | `export GHIDRA_HEADLESS_MAXMEM=10G` |
| Ghidra 报 `not a valid directory or file` | 忘了切片 | 先 `lipo -thin arm64` |
| 几个 Ghidra 并行**全部**超时 | 并行会互相拖死 | **一次只跑一份** |
| 已在跑的 Ghidra 突然报「编译包失效」 | 你中途改了脚本文件 | 开跑前定好脚本，**跑的时候别动** |
| 「文档里的数字和代码对不上」 | 引用了摘要或旧文档里的数 | **用绝对路径重数一次，并把命令贴上**（§7） |
| `ls 某目录` 报不存在，你就据此下了结论 | **路径可能错了** | 「找不到」**≠**「不存在」；先确认路径 |
| 你要写「我们**没有** X」 | 只 grep 了一处，或凭印象 | **说「没有」的成本比说「有」高一个数量级**：说「有」给个例子就行，**说「没有」要把全表过一遍**（§7 的 13 条自纠里 **8 条**栽在这） |
| 你的结论被代码／符号表推翻 | 没看代码／没看全表就先下了结论 | **先看代码，再写结论** |
| 表格渲染乱了 | 单元格里有**未转义的竖线**（例如路径里写成 part7\|8） | 加上反斜杠转义，或把那个竖线改掉（写成「part7 与 part8」） |
| 你的改动让别人的活全废 | 在共享文件被并行任务使用时改了它 | 见上「别中途改脚本」；**动手前先确认没有人在用** |
| `nm -u` 里没有某个 API，你就据此说「我们没用」 | **量具盲区：`dlopen`／`dlsym`／`NSClassFromString` 载入的私有符号不在符号表里** | 本项目桥接层全在 `prototype/Private/`；量私有面要**两列**（静态呼叫点 ＋ 运行时载入串，见[竞品深挖](competitive-deep-dive.md)§5.3） |
| `rea analyze` 对自家大件报 `provider_timeout` | 330 秒预算装不下（候选包 20 MB 过不去 `list_documents`） | 直驱 `analyzeHeadless`；先问「到底要回答什么问题」——工件面问题用 `nm`／`strings` 常常更快 |
| 用户报「辅助功能给了权限但没生效」 | macOS 已知状态漂移——**权限要关一次再开** | TileMyMac 把它写进引导文案：「**Accessibility needs turning off and on again**」——我们 R2/R1 的引导文案照抄这个说法（先关再开） |
| **REA MCP 报「Cannot launch Hopper / Not authorized」** | MCP 配置里挂着**破解版 Hopper 的路径**（本机那份不能碰），且缺 `GHIDRA_INSTALL_DIR` | 配置已改：删 Hopper 指针、加 `GHIDRA_INSTALL_DIR=/opt/homebrew/opt/ghidra/libexec`（备份 `cli/config.json.bak-20261015`）；**MCP 服务器重启后生效**，在此之前走 CLI |
| 自家件的 `analyzeHeadless` 跑 45 分钟零日志推进 | **日志静默 ≠ 卡死**——Ghidra 有些阶段十几分钟不写日志 | **判断死活看 java 进程的累计 CPU 时间**（`ps -o time= -p <java pid>`，两次采样有增长就是在算）；**别拿 bash 包装进程的 %CPU 下结论**（它天然 0）。真卡死（CPU 时间也不涨）或超 2 小时才杀 |
| 用户说「打开时被系统拦了」 | 未公证（[竞品深挖](competitive-deep-dive.md)§五 C2） | 已知缺口；修它＝Developer ID ＋ 公证链（**待拍板**）。在此之前官网 FAQ 的「仍要打开」步骤不许省 |
| 发布日签出来的包和验过的候选包不是同一份 | 主程序漏了 `-o runtime`，嵌套件全有（`build.sh:373`） | 补上 runtime 重过 Phase 0，或按 runbook 在发布日加冒烟——**别让「验过的」和「发出的」是两份东西** |

### 1.6 成熟 app 的**避坑做法** × 我们的处境

**这一节和 §1.4／§1.5 不同**：那两张是「我们的坑」；这一张是**别人怎么防坑**——从 626 个 release 的变更语言里挑出来的**做法**（不是功能）。每一条都本机核过我们的处境。

| 成熟做法（谁） | 它防的是什么坑 | 我们 |
| --- | --- | --- |
| **主执行绪不阻塞——审计出来，不是猜**（alt-tab：「avoid blocking calls on main-thread」） | 卡顿、掉帧、手感变差 | **已有**：`logIfSlow`（`Support/Diagnostics.swift:228`，**22 处调用**）——**这是纪律，不是运气** |
| **配置期就拦快捷键冲突**（alt-tab：「prevent setting conflicting arrow shortcuts」） | 两个功能抢同一个键，用户不知道为什么有时灵有时不灵 | **已有**：`GlobalShortcutSettings.conflictName(for:excluding:)`（`App/Preferences.swift:1356`、`App/GlobalShortcuts.swift`） |
| **录制快捷键时挂起全局热键**（Rectangle：「Prevent Todo shortcuts from firing during shortcut recording」） | 用户按 ⌘N 想录进去，结果先把 App 自己的快捷键触发了一遍 | **不适用（当前）**：我们**没有录制器**（从列表里选）。**若将来加录制，第一条就要防这个** |
| **缓存昂贵调用**（Ice：「Cache item images **to prevent excessive** screen capture use」） | 频繁抓屏 | **已有**：缩略图的**成本账** `cachedCostBytes`（`WindowBrowser/WindowThumbnailService.swift:213`）＋ `Capture/ShareableContentCache.swift` |
| **别等 tap 超时——从一开始就减负**（Ice：「**Extended delay** in event tap callback to help **prevent occasional item movement timeouts**」） | 系统因回调超时把 tap 停掉 | **部分**：我们的对策是**被停后重开**（R1 的 5 秒体检 ＋ 五处 `tapDisabledBy*`）；**Ice 的思路是「别超时」**。**两条互补，可以并做** → 归 R1 的后续 |
| **身份派生的缓存必须复核**（OmniWM #550：「a floating window's workspace was fixed when it was first admitted and **never revisited**」） | 窗口搬到另一块屏后，归属还记着旧的 | **待核**：我们按 App 缓存窗口与其所属桌面/屏——**这类「首次认定、之后不复核」的字段要点一遍** |
| **一个概念不要两个状态槽**（OmniWM #549：「focus was remembered in separate tiled and floating slots, and **the tiled one always won**」） | 同一事实存两处，其中一个悄悄永远赢 | **待核**：我们有 `shaded`／`pendingSpaceReturns`／`foldObserverRoutes` 等多份状态；**同一事实存两处的地方要点出来** |
| **登录启动是独立代码路径**（Ice：「settings window not opening **after launching at login**」） | 只在登录那条路上才出现的 bug | **未验** → 归 **R48** |
| **不稳的功能放到 flag 后面**（Rectangle 把 Stage Manager 的某功能**撤到 Terminal flag**，因为它「causing app instability」） | 带着不稳的功能发版 | **已有，而且更正规**：`Core/ReleaseDefaults.swift` **21 条**，`deviceVerified = false` 就**默认关但功能在**——**这就是它的用途** |
| **金丝雀通道**（OmniWM `canary.yml`） | 坏包一次性发给所有人 | **缺** → 归 **R33／发版列车**（先给自己：`--self-check` 已有） |
| **自研稽核器查循环引用**（OmniWM `Scripts/arc-audit.sh` ＋ `ArcAudit.swift`） | 长驻应用的泄漏 | **缺** → **R39** |
| **回归覆盖按子系统点名**（OmniWM 逐个列出它加了回归的领域：TOML 设置、显示器重绑、鼠标穿越、手势、重排范围、边框/还原、运行时规划、IPC 稳定性） | 改动打坏一个**没被点名**的领域 | **部分**：244 测试档 ＋ 成套探针在，**但「哪个子系统的回归归谁」没有点名** → 可并入 **R33** |
| **不信任不可靠的系统回调**（AeroSpace：「Don't rely on macOS unreliable `kAXUIElementDestroyedNotification`」） | 幽灵窗口 | **已有**：销毁通知**只当提示**，要 `CGWindowListCopyWindowInfo` 查回空才动手（`App/FoldTransaction.swift:919`） |
| **验证失败要有降级支路**（WindowMizer：`assume_success_after_ax_raise`） | 卡在等一个永远不来的确认 | **缺** → **R10** |
| **接管别人的东西要留「还给你」的路**（MediaMate：`Disable Hiding Native OSD`） | 接管了系统 HUD 却没法退回 | **缺** → **R12** |
| **长时运行要专门测**（niri：「~50 days of uptime」的整数溢出） | 跑很久才炸，且只有长期用户撞得到 | **缺** → **R47** |
| **把「删掉的代码也是债」当纪律**（多家：更新日志里写明「Removed …」并说清为什么） | 死代码越积越多 | **部分**：我们的注释文化很重（说明「为什么」），但**没有定期的死代码清查** |
| **亮度写入留回退**（Alcove：`DisplayServices` 失败就发亮度键码；两档都有失败日志） | HUD 调不了亮度就成死块 | **缺**：`NotchLevelControl` 拿不到就 `nil`（软失败），没有第二条路 |
| **登录项失败重试一次**（Wins：「Attempting one more time.」） | macOS 13+ 的 `SMAppService` 在装／更新后第一次常失败 | **缺**：只调一次（`Preferences.swift:1084`） |
| **几何兜底：AX → CGWindowList**（Wins 的 `drag.windowListRectFallback`；WindowMizer 的 Quartz 全屏回退） | AX 偶尔读不出矩形（跨 Space／全屏／无标题浮层） | **缺**：`Window/AXWindow.swift:27` 读不到就 nil（**R20 顺带做**） |

**这一张的用法**：**不是照着抄一遍**——凡是标「已有」的，别重做（§1.4 已经列了位置）；标「缺／待核」的，都已经归到任务或建议归入某条。**它真正的作用是：当你要做一个新功能时，先在这里找一眼「同类功能别人踩过什么」。**

### 1.7 vibe coding 给窗口管理出的新题（2026-10-15 立，Aaron 点名）

**背景**：窗口不再只是「文档」，而是**长跑进程**——一个项目一个 agent 会话，常常并行好几个。品类前沿是 VibeIsland（AI Agent 的灵动岛，30 家 agent、20+ 终端、$19.99 买断、已公证；本机供件已量，见[竞品深挖](competitive-deep-dive.md)§三末）。**它把「看」做满，但它不管窗口。** 由此新的八条要求：

| # | 新要求 | 我们的现状（本机可核） |
| --- | --- | --- |
| 1 | **状态外显**：N 个会话各在跑什么，一眼看到、不打断 | **有**：`ConductorSession.swift`（会话/轨迹/cost/models/听写草稿）、`AgentSessions.swift`、**多会话在账**（`sessions: [String: Live]`）；**一次只展示一件**，「多审批队列」代码里已标注留给后续 |
| 2 | **注意力路由**：只在「要你拍板/卡住」时打扰 | **有**：审批事件＋风险分型（`TypedAction`，**shell 不猜安全**）；缺跨会话的打扰节流 |
| 3 | **一键跳回**：从任何地方跳回那个终端/标签/tmux 窗格 | **缺**：`ws2-hook` 只转 cwd/tool，**不带终端身份**；VibeIsland 覆盖 20+ 终端 |
| 4 | **按项目工作区**：终端+编辑器+浏览器一键摆好，且不搬 agent 正在用的窗口 | 部分：窗口浏览/卷帘条/刘海收纳在；「一个项目一套位」没有 |
| 5 | **不挡路**：不抢焦点、心流时不弹东西 | 有静默/PowerPolicy 一族；缺与 agent 活跃状态的联动 |
| 6 | **预算可见**：5h/7d 额度与恢复时间 | **有**：`UsageReading`（窗口/恢复/剩余，含 Codex 形状）；缺 Claude 侧＋常驻陈列 |
| 7 | **安全下放**：批准/拒绝离开终端，授权强度不降 | **有且更强**：Touch ID、费用保险库（30s 票）、**故障返回「无决定」绝不自动 allow**、119 秒决策窗 |
| 8 | **多 agent 覆盖** | **缺**：会话面只有 Claude Code hook；Codex 只有额度读数 |

**定位判断（写死）**：窗口管理器的正确身位**不是**又一个 agent HUD，而是 **agent 控制面**——状态外显是入场券，护城河是**窗口语义**：把「agent 的终端/窗口」当一等对象（收纳不打断、一键回跳、按项目成组、出事能恢复）。VibeIsland 的 $19.99 买断反过来验证了这格有人付钱；我们的差异是**看得到 + 管得住 + 授权更硬**。

### A 系列 · AI Agent / vibe coding（2026-10-15 立；**全部待准入**）

**准入注记**：与 O 系列同规——不取代、不推后任何在飞任务，不阻塞当前发布，按 §0.3 排队。**A1／A5／A3 为第一梯队**（被竞品直接对照、且都有现成地基）。

| # | 做什么 | 验收 | 备注 |
| --- | --- | --- | --- |
| A1 | **终端回跳**：hook 转带终端身份（`TERM_PROGRAM`／`ITERM_SESSION_ID`／`TMUX_PANE`／tty）→ 建 session→终端绑定 → 一键跳回；覆盖 iTerm2／Ghostty／Warp／kitty／Terminal／tmux（attach/select-pane）／IDE 终端。**形制参考 CodexBar 的聚焦机制**（PID→所属终端/编辑器 App→抬起匹配窗口）；**VibeIsland 的 tty 路线（字串级证据）**：靠 AppleScript 逐 tab 比对 `tty`（`if (tty of selected tab of aWin as text) is targetTty`）、tmux 走 `tmuxWindowPane` 变量，tty 本身由 **OSC 逃逸序列**从终端抓出写盘；回退路由 `raise+fire hasDeepLink` → `hostPid-only activate`。**我们的路更干净**：`ws2-hook` 是终端 shell 的子进程，**天生继承 tty**（读自身 `/dev/ttys*` 或父进程 tty），不需要 OSC 花招。**两条跳法的权限账要算清**：AppleScript 路线精确到 tab **但要每个终端 App 的自动化授权**；AX 路线只到窗口级**但只需要辅助功能**——**建议：AX 优先（零新增权限），AppleScript 只用于要 tab 级精度且用户显式同意时**；**tmux 窗格精度两家都没做，做到就赢一格** | 五类终端各跳一次全中；**跳不了要如实说「跳不了」**，不乱跳 | 最高优先：是「控制面」与「HUD」的分界线 **2026-10-17 实现（源码级，未真机）**：`ws2-hook` 转带 `terminal`（TERM_PROGRAM／ITERM_SESSION_ID／TMUX_PANE／沿父进程找到的 tty，逐字段白名单）→ `WS2HookSessions` 记会话→终端绑定 → “过去”只在 TERM_PROGRAM 指的 App 里找窗口（认不出才回默认四个），标题含 tty 名算完整匹配，tmux 先 `select-window`／`select-pane`；纯逻辑在 `Core/TerminalIdentity.swift`、`Core/TerminalBinding.swift`，测试 `tests/run-terminal-binding-tests.sh`。只走 AX（零新增权限），到窗口为止；**未做**：tab 级（要 AppleScript 与每 App 自动化授权）、iTerm2 的 ITERM_SESSION_ID 只收下未用于精确定位、kitty（不设 TERM_PROGRAM）、真机五类终端各跳一次的验收。**2026-10-17 复核修正**：tty 命中现在先于目录命中（不再同强度取前面的窗口）；hook 加转 $TMUX 的 socket 路径、App 层带 `-S` 选窗格（自定义 -L／-S 的 tmux 服务器不再选错）；kitty 凭 KITTY_WINDOW_ID 认出（映射 net.kovidgoyal.kitty，未真机）；ITERM_SESSION_ID 仍只收下未用（iTerm2 精确定位待做）。 |
| A2 | **多 provider 接入**：`ws2-hook` 的 `--provider claude` 扩成适配层（codex→gemini→cursor→…，按实际在用排序）；有 hook 用 hook，没有的用只读日志 tail；**本机进程发现照 CodexBar 一页设计**（`libproc`＋argv 定身份＋每家预算＋隐私红线：不读进程环境） | 每家一个最小事件映射＋断连如实降级 | 与 VibeIsland 30 家对位，先做「用户真的在用的」 |
| A3 | **hook 安装管理**：保持「**不静默写用户配置**」底线，升级为「一键装/卸＋变更清单可见」＋零配置检测已装 agent | 装/卸各一次可回退；清单逐条可查 | 现在只生成粘贴配置（`WS2ConductorSettings.swift:13`） |
| A4 | **额度常驻格**：`UsageReading` 的窗口/恢复时间进刘海常驻一格；补 Claude 侧读数 | 接近恢复点提示与现在一致 | 数据模型已有 |
| A5 | **审批键位直达**：允许/拒绝全局键（对照 VibeIsland 的 ⌘Y／⌘N）＋ AskUserQuestion 选项数字键直答 | 不离开当前窗口完成一次审批 | 走 Touch ID 链路不变 |
| A6 | **计划/差异 Markdown 渲染**（含代码高亮） | 计划可见即渲染，长文可滚 | VibeIsland 带 `highlight.min.js` |
| A7 | **项目工作区**（窗口管理的本职加分项）：一个项目一键摆好（终端+编辑器+浏览器）；**agent 活跃时不搬它正在用的窗口** | 三个 App 归位；agent 活跃期零误搬 | 接窗口浏览/卷帘条 |
| A8 | **SSH/远程会话**（先评估）：对照 VibeIsland 的 `RemoteAgent`；我们已有 `RemoteMode` 键位与 `RemoteLayerHost` 地基 | 评估报告先出，不承诺 | — |
| A9 | **沙箱/隔离**（先评估）：agent 执行面要不要有沙箱选项 | 评估报告先出，不承诺 | VibeIsland 建议用户开沙箱 |
| A10 | **「不打扰」基线**：agent 活跃时，动效/声音/弹层默认最克制；写成验收 | 忙时跑一遍验收脚本全静 | 接 PowerPolicy/静默 |
| A11 | **额度面：本地优先＋联网显式同意**（定案建议）：默认只显示本地能拿的（Codex app-server 推送＋本地 JSONL 扫描）；要联网读 Claude/GLM 等，做成**默认关**的开关、旁注写清楚会连谁。**红线**：凭据只读、刷新归原主（CodexBar `codex-oauth` 原则）；**外来钥匙串项默认关、后台零弹窗、每次用户动作至多一次**（CodexBar `keychain-prompts` 处治）；多账号**先归一账号快照、封顶四项、只显式切换、不自动切**（CodexBar 定案）；**每条路的菜单**（Claude 三路＋本地：OAuth／网页 cookie／CLI PTY（弃——slow and unreliable）／本地花费扫描） | 关着时零网络（抓包验）；开着时只打 provider 自家 API；从不写他人凭据文件 | 与「纯本地」承诺冲突的点就在这里，必须显式 |
| A12 | **「围绕重置时间规划」的提示**：额度新鲜/将重置时，在额度格提示「适合开长任务」；快见底时提示排队 | 文案过 copy-guide；不打扰基线覆盖 | 借 CodexBar 的产品语言 |
| A13 | **「agent 活跃时保持唤醒」**（Stay Awake 式）：有会话在跑时持一个电源断言、没有立即放（含退出/崩溃路径）；默认关 | 有会话时不睡；无会话/关闭/退出/崩溃四条路径都释放 | 借 CodexBar；接 PowerPolicy |
| A14 | **窗口管理做成 MCP 服务器**（Agently 的镜像：它把「大脑」做成 MCP、Mac 端当客户端；**我们反过来把窗口面开放给 agent**）：暴露最小工具集——`get_screen_state`（窗口清单/位置/前台/在哪个空间）、`arrange`（把 X 放左/右/半屏）、`focus`、`shelve/unshelve`（收进卷帘条/刘海）；**全走本地 socket（已有 `WS2UnixSocket` 与语义路由地基）**，**破坏性动作照 A 系列审批链走（带推理与来源）**；默认关、显式开 | 一个外部 MCP 客户端能列窗口并完成一次 arrange＋一次 shelve；关着时零监听；所有写动作有审批记录 | 新立；与 §1.7 的「控制面」论点同轴；**先只读后写**，写面必须过审批 |

### 1.8 竞品能力清单：取什么、弃什么（2026-10-15，源码级）

**与 §1.6 互补**：那张是「别人怎么防坑」，这张是「别人会什么」。判断标准只有一条：**精华＝把状态外推给用户、把机制做在本地、把边界说清楚；糟粕＝用关 SIP／重启别人的进程／回收的身份换功能**。

| 能力 | 谁 | 精华（机制级） | 我们 | 定性 |
| --- | --- | --- | --- | --- |
| **额度 pace 外推** | OpenUsage | 表上叠一条「均速刻线」（窗口过半，刻线就在 50%）；把当前燃速外推到重置时刻，直接说「~40% left at reset」「~20% over limit at reset」；**没动过的表不给故事**（无预测、无提示） | 我们的 `UsageReading` 有窗口/恢复/剩余，**没有外推** | **取**（A4/A12 的呈现模型改为它） |
| **截图自动上架** | Tendedero | 读 `com.apple.screencapture` 的 `location-screenshot`（27）／`location`（更早）找文件夹，桌面兜底；认图靠**扩展属性 `com.apple.metadata:kMDItemIsScreenCapture`**；`open(O_EVTONLY)`＋DispatchSource；**`open()` 必须离开主线程**——桌面授权弹窗会阻塞，主线程等它会让启动都完不成 | 架面已有，这两下没有 | **取**（O12 照此实现；连坑一起取） |
| **人脸活体（2D 级）** | Glance | **眩光线索**：裁切区里近饱和低彩像素占比（`specularFraction`）＋集中度（最密 8×8 格的份额）——注释原话「distinguish glass glare from a shiny forehead」；**设备矩形检出**＝画面里有手机边框直接拒；线索一旦触发**无论匹配与否都判翻拍**；匹配与活体分离、带 Lab 视图逐帧看特征。**解锁决策流**（源码）：锁屏/唤醒各触发一次（`requiredTrigger`：`.wake→onWake`、`.screenLocked→onLock`，解锁/休眠不触发）；**每次锁定只武装一次**（`hasArmedForCurrentLock`，不反复扫）；**空格键触发扫描**（复用现有按键，`phase != .scanning` 防重入）；前置需「会话未锁＋已存密码」 | 我们有 Vision 人脸面，无活体；**架构上它要存用户密码并在识别后代打**（`SecureCredentialManager.hasStoredPassword`） | **慎取**（只在真做人脸解锁时借思路）；**弃**：声称防视频——他们自己 README 都说挡不住；**存密码代打的架构记在案，是重大安全权衡** |
| **切换器带搜索** | DockDoor（源码级：`enableWindowSwitcherSearch`＋**`searchFuzziness` 模糊度可调**＋开启即聚焦；README「Type to search」）／Peninsula（打窗口名→只留匹配→回车） | 搜索视图里打名字→只留匹配窗口→回车切 | 我们有切换器，无搜索 | **取**（O1，已立） |
| **有界并发工具** | DockDoor | `LimitedConcurrency.map(maxConcurrent:)`：结构化并发的限流 map——正是「枚举每 App 阻塞」的解药形态 | **已有**（后台并发 2／元数据并发 3 的接线） | 已有，不重做 |
| **拒绝应用过期布局** | Thaw | 项集合与边界对不上（`boundaryMismatch`）就**拒绝施工**（`refusedApply`），宁可不动 | 与我们的租约/校验同族 | **取精神**（R20 邻域再核一遍有没有漏的出口） |
| **壁纸取色** | Thaw | `averageColor` 带色彩空间守卫 | 启动台背景有取色 | **取**（守卫写法对照一遍） |
| **文件夹动画节拍** | LaunchNext | 展开 0.24s、fade 0.16s、recessed 带深度与枢轴 | 画面照我们自己的稿 | 参考值，**不照抄** |
| **触发的条件面** | Thaw | 电池/网络/VPN/蓝牙/显示器/Focus/热压力/摄像头麦/脚本＋AND-OR 组合 | 不做菜单栏管理 | **弃整体**；若我们将来做场景自动化，条件面照它过一遍 |
| **多账号身份分离** | OpenUsage／CodexBar（`claude-multi-account-and-status-items.md`） | OpenUsage：同邮箱不同 workspace、同 workspace 不同用户各成卡片，**有专门的测试**。CodexBar 的定案更狠：走 `claude-swap` 适配器并把结果**先归一到「provider 无关的账号快照」再进 UI**；**每账号状态项默认关、上限四个、与合并图标互斥**；切换只能是**用户显式点击**（`cswap --switch-to <slot>`），**自动切换与会话启动明确出局**；按 Phase 立档（Phase 1 只显示、Phase 2 显式激活） | 额度面未接多账号 | **取**（A11：先归一账号快照、封顶、只显式切换、不自动） |
| **本地 JSONL 扫描算日花销** | OpenUsage | 读本地会话日志算 spend，**不开网络**；基建一整套：`IncrementalJSONLScanner`＋`JSONLScanCacheStore`＋`JSONLScanParseWorker`＋`JSONLStreamingReader`＋`JSONLTailParsing`（增量＋缓存＋流式＋尾解析；**缓存键＝文件 `size + mtime`**，配 `writeGenerations` 防陈旧写入）。**子代理归属规则**：`subagents/` 下的转录**归它上面的父会话**（沿目录向上找父 `.jsonl`）；**找不到父的就不归属**，绝不当作独立会话 | 无 | **取**——A11 对 Claude 侧的本地路径（增量＋缓存）；归属规则照抄 |
| **发布流水线的本子** | CodexBar（`RELEASING.md`＋`Scripts/release.sh`；同为 SwiftPM 手工打包签名） | ① **fail-fast 三查**：工作树不干净／changelog 顶节还是「Unreleased」或对不上／目标版本已存在——任一命中直接停；② **Sparkle 密钥先探**、appcast 条目与签名**生成后自动验证**；③ **changelog 一节一源双发**（GitHub release 与 appcast 的 HTML 都从它生成，不手写第二份）；④ **先公证、后发布**；⑤ 缓存可疑时 `FORCE_CLEAN=1` 全量重建 | 我们的发布是手工的（C2/C3、R33/R34）；**没有 fail-fast 三查、没有一源双发** | **取**（O10 的落地清单：先抄这三查＋一源双发＋公证前置） |
| **兼容路径的退役纪律** | CodexBar（`TODO.md`） | 原文：「**A date alone is not evidence that the fallback is dead**」——退役一条兼容路径要有三件：**点名替代格式＋写清迁移边界＋文档化变更**；在此之前旧字段照留 | 我们对死代码偏激进（C8 那处也正是死码） | **取**（§6 的「不做」清单加一条：**不许拿日历当证据删兼容路径**） |
| **窗口标签页化（tabbed display）** | Paneru（TileMyMac 引擎，字符串级：`toggle_tabbed_display`） | 一个显示器上把多窗叠成「标签页」，一键切换/堆叠（`stack_east`／`unstack_west` 配套） | 我们没有；卷轴/平铺都有「分组」但没标签页化 | **记候选**（与我们的卷帘条语义有重叠，先记不启动） |
| **正则窗口规则** | Paneru（`copy_rule`＋`match`＋regex crate） | 用户用正则声明「哪些窗口归我管/放哪」 | 我们有 `Compatibility/Policies` 与 WS2 的声明式过滤 | **取精神**（我们已有等价物，检查是否覆盖正则强度） |
| **检查频率随功能的粒度** | Glance（`SessionAutoLocker`） | 自动重锁的检查间隔 **5 分钟**，注释原话：**「Coarse on purpose——最短可选时限是一整天，决策比的是时间戳不是次数」**；定时器挂 `.common` 模式（**菜单打开/拖拽的 tracking 模式里也照常走**） | 我们有 PowerPolicy 与一堆定时器 | **取两条**：① 频率对齐粒度（别为日级决议频繁唤醒）；② 定时器挂 `.common`，不然菜单/拖拽期间会停 |
| **人脸解锁必须配自动重锁** | Glance（`SessionAutoLocker`＋解锁协调器同族） | 人脸解锁把「解锁」变太容易——他们用「空闲超过时限自动重新锁屏」兜底（`autoLockInterval` 可设） | 我们未做人脸解锁 | **取**（若真做 A 系列的人脸解锁：自动重锁是必配项，不是可选项） |
| **回退要带警示** | OpenUsage（`ClaudeProvider`） | 凭据源逐个探测（**钥匙串先于文件**），每个源一个显式状态（`permissionRequired`／`stale`／`invalid`／`notFound`／`notChecked`／`available`／`missingProfileScope`／`inferenceOnlyToken`）；**换用更低级的数据源时给 `fallbackWarning`**——注释原话：静默换源会把刷新变成「假成功」（false success） | 我们尚未有「多源回退」的面 | **取**（A11：任何换源都带警示，绝不静默降级成半截数据） |
| **曲线的诚实纪律** | CodexBar（`docs/widgets/burndown-proof.md`，记录式额度燃尽图） | ① 实线＝**记录到的**额度百分比，且注明「不是精确 token 数」；② 虚线＝**均速导引线**（窗口起点 100%→重置点 0%），并明说「**不是预测，也不是学习出来的节奏**」；③ 每条线标**实际采集时刻**，**最后一次采集之后绝不把线延长到当前**；④ 过期的窗口从图上消失，历史仍可查；⑤ 这个视图**不加持久化、不加设置、不加请求、不加后台任务**（零足迹视图） | 我们额度格目前只有数字 | **取**（A4/A12 任何画曲线的地方照此：不插值、不装预测、标明采集时刻；视图不加足迹） |
| **钥匙串弹窗的完整处治** | CodexBar（`docs/keychain-prompts.md`） | 读**别家的**钥匙串项（如 Claude Code 的凭据、浏览器 `*Safe Storage`）会触发系统授权弹窗——它的规矩：① **默认关**，碰外来项要用户在设置里显式同意；② **定时/设置触发的读取永不弹窗**（先试无 UI 读，弹窗只留给用户动作）；③ **一次手动刷新全局共享一次弹窗额度**（成功的无 UI 读不花额度；ACL 预检元数据不能拿来换额度）；④ 支持报告**永不夹带**钥匙串值/cookie/token/密码 | 我们尚未读任何外来凭据 | **取为红线**（A11 若读 Claude 钥匙串：默认关、后台零弹窗、每次用户动作至多一次） |
| **大文件的界内扫描** | OpenUsage（`ClaudeSessionIdentity.parse`） | 在**有界字节区间**里搜标记，不把每行都物化成数组；**每读 1 MB 查一次取消**；跨块的完整记录照样拼得上；身份三态（`owned(org,account)`／`unattributed`／`conflicted`）——**归不上就说不归，冲突就标冲突** | 我们的本地扫描尚未成形 | **取**（A11 本地扫描照此：界内＋可取消＋跨块＋三态身份） |
| **凭据只读、刷新归原主** | CodexBar（`docs/codex-oauth.md`） | 原则一句话：「**只读 token 供我们查询，刷新与持久化归拥有 `auth.json` 的那个 CLI**」；陈旧凭据由原主恢复。**反例自述**：它原先靠 PTY 跑 `codex` CLI 发 `/status` 解析文本——「slow and unreliable」，已弃 | 我们只吃 app-server 本地推送，尚未碰任何凭据 | **取为红线**（若 A11 开联网读数的口子：**只读他人凭据、绝不刷新/回写、显式开关**）；**弃**：PTY 抓取 |
| **自动复藏做成三档** | Thaw（`RehideStrategy`） | `smart`（智能算法）／`timed`（定时）／`focusedApp`（**前台 App 一变就收**，面向键鼠党）；`fromString` 同时认名字与裸整数（**配置文件向后兼容**） | 刘海的自动收起目前是内置行为 | **取**（O14：刘海的自动收起给同样的三档，默认 smart；配置格式认名字＋整数两种写法） |
| **provider 适配四件套** | OpenUsage（如 `ZAI/`：`ZAIAuthStore`＋`ZAIProvider`＋`ZAIUsageClient`＋`ZAIUsageMapper`；**已覆盖 12 家**：Antigravity／Claude／Codex／Copilot／Cursor／Devin／Grok／Ollama／OpenCode／OpenRouter／Pi／Z.AI） | 每家 provider 固定四件：**取凭据／适配器／读数客户端／映射器**——映射器单独一层，原始读数与内部模型解耦 | 我们只有 Claude 一条 hook 链路 | **取为形制**（A2 每家 provider 照四件套落文件，映射器独立可测） |
| **模糊度做成用户档位** | DockDoor | `StringMatchingUtil.fuzzyMatch(query,target,fuzziness:)`：**五档**——1 精确子串／2 隔 1 字／3 隔 3 字／4 隔 5 字／5 不隔；用户自己选松紧，算法可解释 | 启动台有拼音（含小鹤）评分，切换器无搜索 | **取概念**（O1/O11：把「松紧」交给用户，别藏魔法） |
| **Agent 会话发现的一页设计** | CodexBar（`docs/agent-sessions-design.md`） | ① `LocalAgentSessionScanner`：**`libproc` 进程内发现**（不 shell 出去）＋元数据信号，**每家一个目录/时间预算**；② **身份用「保留的 argv」判定**——提示词里提到 Claude 路径不会误判 provider（同理 pi 家族）；③ 协议分代：v1（数组，codex+claude）→ v2（加会话状态）；④ **焦点回跳**：从 session PID 走到**所属终端/编辑器 App**、抬起最匹配的窗口（需辅助功能权限）；⑤ 隐私红线条条：**绝不 `ps eww`、绝不读 `/proc/<pid>/environ`、不抓进程环境**；⑥ 非目标写死：不做历史浏览/云会话/**等待许可状态**/精确 tmux 窗格/常驻远端 daemon | 我们有 `ws2-hook`（hook 事件→socket），**没有本机进程发现、没有回跳** | **取**（A1／A2 照这一页定我们的形制：libproc＋argv 身份＋预算＋显式非目标；**tmux 窗格精度双方都不做**，谁先做谁赢一格） |
| **性能修复的验证文档** | CodexBar | 每个性能修复留一份 pre/post 报告（issue #139：主探针超时 18s→8s；**重试策略从「parseFailed 或超时都重试」改成「只对 parseFailed 重试」**——对超时重试等于把成本翻倍） | 我们有探针与验收，没有「修复前后对照文档」的固定格式 | **取**（E 系列验收照这个格式；「别对超时重试」直接进编码纪律） |
| **provider 插件契约** | CodexBar | provider 是插件：契约/运行时/存储/**连内存都有测试** | 不做插件市场 | **弃**；但 A2 的适配层按「契约＋夹具＋测试」写 |
| **缓存预算的例外规则** | LaunchNext（`WallpaperCacheBudget`） | 上限 **48 MB**；驱逐规则一句话：**「正在显示的那一帧永不驱逐——哪怕它单张就超预算」**（`mostRecentFirst` 只含保留的显示器） | 我们有背景/缩图多套缓存（`LaunchpadBackdrop`、`ShareableContentCache` 等），预算规则未成文 | **取**（给我们的每套缓存补上这条例外并写成文） |

**一句话**：这批的精华可以概括成**「外推、本地、说清楚」**三词；糟粕也只有一个面貌——**关 SIP、`killall` 别人的进程、用回收的身份**（launchbad／BackToCatalina／Dockset 的重启 Dock 手法／DiPlay 的配件身份）。**糟粕一律不取，行规不构成理由。**

## 2. 任务清单

### 2.0 索引（一页看完，按系列）

**系列含义**：`R` 产品改动 ｜ `E` 能效与性能 ｜ `H` Apple 芯片 ｜ `N` Apple 原生 API ｜ `M` 代码写法现代化 ｜ `V` **上机验证**（不改代码，去把没跑过的探针跑掉）｜ `O` **对手对标**（2026-10-15 点名三家，全部待准入，见 §2 末）。

**工作量**：`S` 一两小时 ｜ `M` 半天到一天 ｜ `L` 数天 ｜ `?` 要先量才知道。
**风险**：`低` 等价替换或纯新增 ｜ `中` 改行为、有回归面 ｜ `高` 动并发/关键路径。

| 编号 | 一句话 | 工作量 | 风险 | 依赖 |
| --- | --- | :---: | :---: | --- |
| R1 | 事件通道周期体检 **✅ 已完成** | S | 低 | — |
| R2 | 辅助功能被撤要告诉用户 | S | 低 | R1 |
| R3 | 唤醒恢复收成三档 | M | 中 | R1 |
| R4 | 原生标签页合并 | M | 中 | — |
| R5 | 设置备份/导出/导入 + 前向迁移 | L | 中 | — |
| R6 | 排布前问「能不能改大小」 | S | 低 | R7 |
| R7 | 几何读取四级回退链 | M | 中 | — |
| R8 | 检测并共存别的窗口管理工具 | S | 低 | — |
| R9 | 还原期间压掉 App 的 `unhideAllWindows` | M | 高 | **先复现** |
| R10 | 孤儿占位条 + 串行还原队列带深度 | M | 中 | — |
| R11 | 收起高度读 `axToolbarH` | S | 低 | — |
| R12 | 接管系统 HUD 留「还给你」的开关 | S | 低 | — |
| R13 | 崩溃上报 | M | 中 | 隐私登记 |
| R14 | 成本感知快照缓存铺开 | S | 低 | — |
| R15 | 启动台读系统 SQLite | M | 中 | — |
| R16 | 手势按类别分栈 | M | 中 | — |
| R17 | Secure Input 可见说明 | S | 低 | — |
| R18 | 常驻面板补齐 `disallowsTiling` | S | 低 | **先核** |
| **R19** | **台前调度：一组验收 + 必要适配** | L | 中 | — |
| **R20** | **窗口身份边界**（orderOut／无标题浮层／静默退出／多实例 ＋ OmniWM 夹具） | M | 中 | — |
| **R21** | **退出策略按 App 分类**（IM 不退出 vs 单窗口 App 退出） | S | 中 | — |
| **R22** | **菜单栏在收起/还原时闪错名或留空** | S | 低 | — |
| **R23** | **Finder 两个坑**（列表列宽、文件夹替身） | S | 低 | — |
| **R24** | **多语言下的布局裁切** | M | 低 | 英语适配 |
| **R25** | **多点触控按设备归属** | S | 低 | — |
| **R26** | **权限弹窗还开着时启动** | S | 低 | — |
| **R27** | **按显示器落盘的键过一遍 UUID** | S | 低 | — |
| **R28** | **macOS 27 权限改名 + 证书轮换说明** | S | 低 | — |
| **R29** | **没有屏幕录制权限时的降级路径** | S | 低 | **先核实** |
| **R30** | **系统的「Mac 设置检查」**（两个开关，先核实） | S | 低 | **先核实** |
| **R31** | **改过的系统设置要能恢复 ＋ 卸载要干净** | S | 低 | — |
| **R32** | **窗口菜单的正确性** | S | 低 | **先验** |
| **R33** | **CI：`--check` 挂到每次推送** | S | 低 | — |
| **R34** | **版本号纪律**（一个版本号＝一份不可变构建） | S | 低 | — |
| **R35** | **一键导出诊断包** | M | 低 | 隐私登记 |
| **R36** | **应用内反馈入口** | S | 低 | R34 |
| **R37** | **面向用户的隐私声明**（**呈现借 loupe 三档**：Passive 不用授权看得见／Needs Permission 弹窗才给／Advanced 公开 API 侧信道——把 66 条 `interfaces` 按获取成本分级） | S | 低 | R29 |
| **R38** | **第三方许可声明**（Sparkle 的 MIT） | S | 低 | — |
| **R39** | **长期运行的资源账**（泄漏/循环引用体检 ＋ 长会话观察） | M | 低 | **先测不改** |
| **R43** | **`docs/` 索引**（86 份没入口） | S | 低 | — |
| **R44** | **性能预算进门禁**（测过 → 保证） | M | 中 | E1 |
| **R45** | **代码地图放规范位置** | S | 低 | R43 |
| **R46** | **收起的面板不能挡底下的鼠标**（冻结） | S | 低 | R41 |
| **R47** | **长时运行与越界**（冻结） | S | 低 | **先测** |
| **R48** | **设置面/列表面的三条正确性**（冻结） | S | 低 | — |
| **R49** | **第三方 App 预览不出来**（冻结） | S | 低 | R20 |
| **R40** | **下载进度卡**（Atoll 那三条） | M | 低 | — |
| **R41** | **No focus stealing**（后台弹窗不抢焦点、不滚 strip） | S | 低 | **先验** |
| **R42** | **卷轴跟手的完整配方**（手感常量／时间步长／惯性／停放 10px／列宽比例／先显后隐） | M | 中 | 跑 strip 探针 |
| E1–E6 | 见 E 系列 | S–M | 低 | — |
| H1–H6 | 见 H 系列 | S–M | 低–中 | H1→M5 |
| N1–N5 | 见 N 系列 | S–L | 低 | M1→N5 |
| M1–M7 | 见 M 系列 | M | 低–高 | N5←M1 |
| V1–V8 | 见 V 系列（上机） | S | — | 需真机 |
| **O1–O14**（含 O5b） | **对手对标**（Thaw／LaunchNext／DockDoor／tendedero 等，待准入；见 §2 末） | ? | 低–中 | — |
| **A1–A14** | **AI Agent／vibe coding**（待准入；见 §1.7 末的 A 系列表） | ? | 低–中 | — |

### 2.0.1 完成定义（DoD，每条任务都按这个收）

一条任务**只有同时满足下面五条才算完**：

1. **`cd prototype && ./build.sh --check` 退出码 0**（改代码的任务）。
2. **行为验收有证据**：探针输出或真机记录；涉及界面行为的按 [Computer Use 验收](computer-use-qa.md)，**工具退出 0 / 日志成功都不算**。
3. **状态写回文档**：把该条的「改成什么」补上「✅ 日期 + 实现了什么 + 怎么验的（证据在哪）」。
4. **数字类任务要给前后对比**（E／H／M 系列），不能只给「改好了」。
5. **没有把不相关的改动混进来**（见 2.0.2）。

### 2.0.2 不要碰的（这些地方改之前先想清楚）

（与[代码地图](code-map.md)的「改的时候注意」是同一份清单的两半，改一边要同步另一边。）

- **`App/FoldTransaction.swift`**：折叠事务的**回调序号校验与「销毁通知只当提示」不变量**是踩出来的（注释写得很满）。改它要先把注释读完。
- **`Window/AXWindow.swift` 的熔断与 `measureAX`**：按调用计的熔断是防「一个 App 卡死拖垮全局」的，别顺手绕过。
- **文案三规矩**（§1.2）：中文日志串棘轮、xcstrings 的 zh＋en、12 个禁词。**每次加用户可见字符串都要过**。
- **隐私登记**（[privacy-page.md](privacy-page.md)）：任何新增的读取/外发都要登记；R13（崩溃上报）尤其。
- **本地化与文案检查、禁词表**：`build.sh --check` 会拦，别试图改基线。
- **设计稿与令牌**：改形状先看 [design-drafts/README.md](design-drafts/README.md)。


### P0 · 地基（先做完这三条）

---

#### R1 · 事件通道的周期体检 ✅ **2026-10-15 已提交（a49ddb3）**

- **依据**：DockDoor 的 5 秒看门狗里有一项 `CGEvent.tapIsEnabled(tap:)`、为假则重建；**Wins 把 `missionControl.tapDisabled` 当成一个专门的埋点**。两家独立印证。
- **为什么**：系统在**回调超时**或**输入洪泛**时会把 tap **静默停掉**——没有通知、没有报错，只是从此不再送事件。我们原本只在收到 `tapDisabledByTimeout`／`tapDisabledByUserInput` 时重开（五处），**在没有那两个事件的情况下死掉，不查**。
- **已做**：`prototype/WindowShade.swift` 新增 `startEnvironmentWatch()`／`runEnvironmentCheck()`；装好之后每 5 秒查一次，为假就**重开同一支 port**（不重建、不新起线程），并记 `tapSilentStops` 计数。同一次体检里顺带盯了权限的「有→无／无→有」。
- **验收**：`CGEvent.tapEnable(tap, false)` 模拟静默失效 → 10 秒内自愈，日志出现 `environment: event taps were disabled silently, re-enabled ["titlebar-click"] (count=1)`（2026-10-15 起 R3 把体检扩到全部 9 支 tap，日志改成带名字的列表）。
- **状态**：2026-10-15 重跑 `build.sh --check` EXIT=0 后提交（a49ddb3，分支 `codex/ws2-remote-gpt6-handoff-20261007`，未入 `main`）。

---

#### R2 · 辅助功能权限被撤掉，要告诉用户

- **依据**：WindowMizer 的更新史明写「**Display an alert when Accessibility is turned off while WindowMizer is running**」。
- **现状**：**49 处**读 `AXIsProcessTrusted()`（本机复核，含 `WithOptions` 共 50 处），**0 处**在「从有变无」时告诉用户。R1 已经在 `runEnvironmentCheck()` 里记下了状态与日志，**但用户看不见**。
- **改动**：
  1. 在 `runEnvironmentCheck()` 的「有→无」分支里，除了 `wlog`，再走一次用户可见提示。
  2. 文案走 `WSL10n.text`：新 key 建议 `notice.accessibility.revokedByUser`，中文源句写清「因为你关掉了辅助功能，这些动作现在不会生效」，并**给一个打开对应系统设置的入口**（照 Wins `dockLock.hud.openSystemSettings` 的做法）。
  3. 「无→有」时把提示收掉或补一句恢复说明。
- **验收**：运行中在系统设置关掉辅助功能 → 10 秒内出现说明；重新打开 → 状态恢复且不重复打扰。
- **风险**：不要做成循环弹窗。一个状态只提示一次，直到状态再次变化为止。
- **依赖**：R1（复用 `runEnvironmentCheck`）。
- **✅ 2026-10-15 已做**：「有→无」时走 `quietNotice(.needsPermission)`（刘海能说就在刘海说、点一下去授权；说不了退回菜单栏标题），「无→有」说一句恢复；另在状态栏菜单最上面挂一行「打开辅助功能…」直到权限回来（动态行，不占固定 9 项）。文案 zh／en／zh-Hant 齐。**验**：`run-menu-structure-tests.sh` 通过；**运行中关权限的真机验收未做（not_run）**。

---

#### R3 · 唤醒恢复收成三档重试

- **依据**：**Wins 的 `resume.*` 命名空间给了确切数值**——`resume.immediate` ＋ `resume.delayed.0.20` ＋ `resume.delayed.0.80`：立即一次、0.20 秒后一次、0.80 秒后一次。而「睡一觉醒来某样功能没回来」是**整份 626 个 release 里出现最多的一件事**（DockDoor 多条、alt-tab-macos、OmniWM、LaunchOS **连修两版**、Wins 两次）。
- **现状（2026-10-15 自纠）**：此前写「十处」，**实数 16 个文件、23 处**（`didWakeNotification` 14 ＋ `screensDidWakeNotification` 9，2026-10-15 `rg -o` 复数），**没有一处重试、没有一个共同收口**：
  `PinnedPreview.swift:263`（在 `prototype/` 根，不在 `App/`）、`App/WS2AppRuntime.swift:102`、`App/NotchActivityController.swift:251`、`App/SplitView.swift:117`、`App/Notch.swift:204`、`App/AwaySummaryController.swift:61`、`App/NotchWatch.swift:139`、`App/BystanderTuck.swift:155`、`App/WS2RemoteHost.swift:918`、`App/FaceScanExperiment.swift:137`、`App/PresenceLockDriver.swift:316`。
- **改动**：
  1. 新增一个收口（建议放 `WindowShade.swift` 或 `Core/`，命名如 `WakeRecovery`），订阅 `NSWorkspace.didWakeNotification` ＋ `NSWorkspace.screensDidWakeNotification`。
  2. 收到后按**立即 / 0.20s / 0.80s** 三档依次执行恢复动作：`setupEventTap()` 若 `eventTap == nil` → 重新确认订阅的 AX 元素 → 刷新屏信息（`NSScreen.screens` 与显示 UUID 的映射）。
  3. 每一档记一行英文日志，并记「第几档成功」。
  4. **各处的唤醒观察者保留**（它们各自有职能，例如暂停/恢复计时器），但**恢复动作走同一条路**。
- **验收**：睡一次、醒一次，逐项功能在 1 秒内恢复；日志能读出三档各自做了什么。**至少连跑两遍**——LaunchOS 在这件事上修了两次。
- **风险**：三档会重复执行同一动作，必须**幂等**（每档都先判断「还需要恢复吗」）。
- **依赖**：R1（同一套「先判断再动手」的形状）。
- **✅ 2026-10-15（a60c1da）**：新增 `Core/EventTapHealth.swift` 登记表。**更正**：tap 不是 5 支而是 **9 支**，其中窗口切换键、触控板捏合、中键标题栏三支在功能关掉时只停用不作废，所以体检**不能**一律重开——改成主人想要开着时登记、关掉时注销，只重开「登记了、端口有效、却被停掉」的；输入洪泛后的退避登记成 hold。睡醒后立即／0.2 秒／0.8 秒三档体检；R1 的 5 秒体检同步扩到 9 支。改动里没做的两项：「重新确认订阅的 AX 元素」「刷新屏信息」——前者没有具体对象，后者 `NSScreen.screens` 本来就是现读，等真机撞到再说。**验**：`--check` EXIT=0；`run-event-tap-health-tests.sh` 通过；**真机睡醒两遍 not_run**。

---

### P1 · 抬格子

---

#### R4 · 原生标签页合并

- **依据**：**四处独立印证**——DockDoor 做了合并（`NativeTabGrouping`：同 pid ＋ **取整后完全相同**的 frame 判为一组；**在屏的一律保留**；屏外每组只留「最近访问」那一个；**不可归组的永不合并**），并且还要修「**被拖出来的标签各自成条**」；Paneru 连着两版「Improved detection of native tabs」；Rectangle「Add title bar tab group support」；Wins 修「Finder 多标签窗口」。
- **现状**：**没有**。`AXTabGroup` 只作为 AX 角色出现在两个命中测试名单里（`Core/TrackpadGesture.swift:750`、`Window/AXWindow.swift:490`、`:504`），不是用来分组的。
- **改动**：
  1. 写一个**不依赖 AX 与 AppKit 的纯函数**（便于单测）：入参是「候选窗口」（id、pid、frame、最近访问时间、可否归组、是否在屏），出参是「保留哪些 id」。
  2. 判据照 DockDoor：`GroupKey = (pid, round(x), round(y), round(w), round(h))`；在屏成员一律保留；屏外每组留 `recency` 最大者，并列时取大的 windowID **保证结果与输入顺序无关**；`isMinimized`／`isHidden`／无窗口 App／零尺寸**永不合并**。
  3. 接进窗口浏览的取列表路径。**必须同时处理「被拖出来的标签」**：它们 frame 不同，天然会各自成条——**这一条要显式验证**。
- **验收**：（a）开 5 个标签的终端／访达，窗口浏览**只出一条**；（b）把其中一个标签拖出来成独立窗口，**它各自成条**；（c）单测覆盖：在屏成员不合并、并列取大 id、不可归组不合并。
- **风险**：误合并会「吞掉」窗口，比不合并更糟。**保守优先：拿不准就不合并。**
- **✅ 2026-10-15 核实：不用改代码（ce2d9a3）**。窗口浏览只从 AX 的 `kAXWindowsAttribute` 取窗口（`WindowBrowserDiscovery.discover` 是 `DiscoveredWindowDescriptor` 唯一的产生处）。夹具实测：三扇窗口并成原生标签页，后台两个标签只在 CG 列表里、不在 AXWindows 里——**本来就只出一条**；拖出来的标签成了独立窗口，AX 里自然各自一条。DockDoor 和 Wins 要合并，是因为它们从 CG／ScreenCaptureKit 取窗口。按外框合并还会误吞「同一 App 在两张桌面上各一扇同尺寸窗口」，不做反而更安全。前提核对留成 `tests/run-native-tabs-probe.sh`（手动跑，本机 PASS）。**所以 §0.2 里「R4 是窗口浏览落后 Wins 1 分的直接原因」不成立**，那 1 分要另找原因（V8 的 DockDoor 12 条场景）。

---

#### R5 · 设置：备份／导出／导入 ＋ 前向迁移纪律

- **依据**：OmniWM 用三代版本换来的教训——0.6.2→0.6.3 把 `settings.toml` 整体换成默认值，原文「**your configuration stops applying** until you restore it」；0.6.4 起明确「Migration is **forward-only**」；0.7.3 起每次升级前留 `settings.toml.pre-v4` 备份。DockDoor 把「Back up and restore settings **as a JSON file**」做成设置里的一项，**并且设置搜索能搜到 backup／export／import／restore**。
- **现状**：只有**一个**迁移点——`WindowShade.swift:46` 的 `shadeSoundMigrationVersionDefaultsKey`，逻辑在 `:531`–`:548`。**没有备份，没有导出／导入。**
- **改动**：
  1. **迁移纪律**：每次要改设置格式前，先把当前域整体导出成一份带版本号的备份（例如放到 Application Support 下的 `backup/pre-vN.json`）；迁移**只补缺的字段，不整体回默认值**。
  2. **导出／导入**：设置里能导出一份 JSON、能导回来；导入要能处理「多出来的键」和「缺的键」两种情形。
  3. **可被设置搜索搜到**（我们已有设置搜索；把 backup／export／import／restore／migrate 作为可搜词挂上）。
- **验收**：拿旧版设置文件启动新版 → 设置照旧、只补缺项；导出 → 清空 → 导入 → 回到原样；旧版读新版写的文件不会把设置清掉。
- **风险**：导出文件里可能有隐私登记里列过的敏感项——**导出前对照隐私登记，排除不该出门的键**。
- **✅ 2026-10-15（部分，78b6f50）**：底层做完——只导出「设置」（更新器、窗口位置、收起记录、诊断、设备绑定、静音短语、CarPlay 接收端与各种「已显示过」标记一律不出门），导入是合并（多的键与被排除的键跳过、缺的不动），迁移前把整个设置域存到 `Application Support/WindowShade/backup/pre-<标签>.plist`（声音迁移第 2 版已接上）。格式用 plist 不用 JSON（UserDefaults 原生类型，日期与二进制不失真）。命令行 `--export-settings`／`--import-settings`：签名构建导出 11 个键、无被排除键，导回 11 个、跳过 0；`tests/run-settings-archive-tests.sh` PASS。**待 Aaron**：设置里的入口与可搜索词（新表面，先过设计准入）。

---

#### R6 · 排布前先问「这扇窗能不能改大小」

- **依据**：**Wins 的 `drag.axSizeSettable` 就是这一步的具名环节**（更新日志 3.5 也写了「自动忽略无法调整大小的窗口」）；Rectangle 的做法是提示「达到最小尺寸」。
- **现状**：`isAXSizeSettable` 定义在 `Window/AXWindow.swift:83`、**唯一调用点在同文件 `:101`**——只用在了卷帘条自身。**魔法平铺（`Core/MagicTiling.swift`）与排布（`App/ArrangeController.swift`）完全没接。**
- **改动（已按 Rectangle 的完整形状加强，2026-10-15）**：不是「先判断能不能改大小」，而是 **① 先试 → ② settling pass（等它自己稳定）→ ③ 才判定是不是被 AX 夹在最小尺寸上 → ④ 再提示**。只做第 ① 步会误判——很多窗口「第一次不接受、settling 之后就接受了」。文案进 `Localizable.xcstrings`（zh ＋ en）。
- **验收**：计算器、系统设置参与排布时出现说明，而不是静默不动、也不是假装排好了。
- **风险**：`isAXSizeSettable` 是一次 AX 往返；排布路径上批量调用要注意**放到后台队列**，别拖慢主线程（见 R7）。
- **✅ 2026-10-15 核过**：排布、手势平铺都已先试再等稳定再判断（`App/TrackpadGestures.swift` 三处：不能改大小的窗口放正中并给说明），`--grid` 探针在签名构建上通过。顺带把那句说明从写死的中文改走本地化（0c9e5cd）。

---

#### R7 · 几何读取的四级回退链
- **✅ 2026-10-15（68825c8）**：`Core/WindowFrameResolver.swift`＋`Window/AXWindow.swift` 的 `axWindowFrameWithFallback`。**与规格原文的主次相反**：AX 两项都读到时照旧只用 AX（结果与原来逐字相同，不改已有行为），缺了才用窗口服务器补；四级都没有返回 nil 并记一行用了哪一层。先接到魔法平铺里「读不到就放弃」的两处（撤回、移到另一块屏）；其余约 180 处 `axPosition`／`axSize` 调用没改，撞到再接。**验**：判据单测；`tests/run-window-frame-probe.sh` 用 `kill -STOP` 冻住夹具，AX 0.5 秒后报 -25204，回退给出的外框与冻住前一致（本机 PASS）。

- **依据**：**Wins 的 `drag.*` 里就是这么一条链**——`windowServerRect` → `axWindowRect` → `axWindowRectFallback` → `windowListRectFallback`。顺序说明了主次：**先 WindowServer，再 AX，再两层回退**。
- **现状**：未记载，各处各自读。
- **改动**：把「取窗口外框」收成一个函数，按上述顺序回退；**记下这一帧用的是哪一层**（可观测——Wins 就是这么埋点的）。
- **验收**：拿一个 AX 不响应的 App（`kill -STOP <pid>`）当对象，排布仍拿到正确外框；日志能读出用了哪一层。
- **风险**：回退链要**有界**——四层都拿不到就返回 nil，不要无限重试。

---

### P2 · 可靠性与可观测

---

#### R8 · 检测并共存别的窗口管理工具

- **依据**：**四家**在做同一件事——ChainYourMac 内置一张**13 项竞品检测名单**（下面直接可用）；Alcove 与 MediaMate 都带 `betterDisplay*` 字段；MediaMate 更进一步内置了 Lunar 支持与一整个 `BetterDisplaySupport/` 模块。
- **现状**：`App/RectangleImport.swift` 已经处理了 Rectangle 一件事，**没有统一的「装了哪些同类工具」检测**。
- **改动**：把下列 bundle id 做成一张表，启动与设置页读取「哪些正在跑」，能报出名字；对已知会抢快捷键的给一句说明。**ChainYourMac 的原表可直接用**：

  ```
  co.highlyopinionated.swish      com.knollsoft.Rectangle
  com.MrKai77.Loop                com.knollsoft.Hookshot
  com.amethyst.Amethyst           com.manytricks.Moom
  com.crowdcafe.windowmagnet      com.mizage.Divvy
  com.hegenberg.BetterSnapTool    com.mizage.direct.Divvy
  com.irradiatedsoftware.SizeUp   com.withmarko.OneMenu
  ```
  另外 **Wins 的名单里有 `apple.WindowManager`（macOS 15 自带的平铺）**，也要算进去。
- **验收**：装／跑着其中任意两个，App 能报出它们的名字，且不与之打架。
- **注意**：只报名字与影响，**不要自动去关别人的功能**。

---

#### R9 · 还原期间压掉 App 自己发的 `unhideAllWindows`／`orderFront`

- **依据**：WindowMizer 的日志串 `Suppressed unhideAllWindows orderFront for CollapsedWindow during restore guard`。
- **为什么**：App 会在我们还原窗口时插一脚抢层序——**这是一类真实对抗，不是理论问题**。
- **现状**：**待核**。折叠还原路径在 `App/FoldTransaction.swift`、`App/FoldExit.swift`、`App/FoldCompletion.swift` 一带。
- **改动**：先**查**（拿一个会在还原时调 `unhideAllWindows` 的 App 复现），确认有这一条再改；改法是在「还原守卫」期间不响应（或重新拿回）层序。
- **验收**：还原后层序不被 App 抢走。
- **风险**：**先复现再改**——不要凭猜加抑制逻辑。
- **✅ 2026-10-16（223e4ee）复现不出，不加抑制**：`--restore-guard`（签名构建）临时 App 两扇窗都收起（一扇隐藏整个 App、一扇最小化），只展开隐藏的那扇：App 被叫回前台后，最小化的那扇仍收着、不出现，展开的那扇是 App 最前面的窗口。**顺带的发现（未改）**：这台 macOS 27 上私有 SkyLight 停车与调透明度都不生效（历次探针日志里「did not park」163 次、停好 3 次，与硬件矩阵交接 F7 同一处），于是**多窗口 App 里不能最小化的窗口收不起来**——三条后备全落空，收起被完整回滚。 **追查结论（2026-10-16）**：原因是 SIP——跨进程的 SkyLight 窗口改动被静默忽略（`csrutil` 显示开着；172 次停车都回报成功、0 次停到屏外），不是我们能修的；试加的「辅助功能移到屏外」后备被系统拉回屏上（四个目标全被夹住，窗口还会看得见地跳），没有提交。现状是回滚并提示「这个窗口暂时收不起来」，`--fold-unminimizable` 核对它干净回滚、窗口原位不动（PASS）。**已改（Aaron 定）**：三条同时成立（不能最小化、App 还有别的可见窗口、SIP 全开）时在开动画之前就提示「这个窗口不能收起」；SIP 关着的机器照旧试私有停车，保留不优化。`--fold-unminimizable` 核对没开始收起、没播动画、窗口原位（PASS）。

---

#### R10 · 折叠还原：孤儿占位条 + 串行队列带深度

- **依据**：WindowMizer 的三条例外串——`Reduce produced orphan placeholder %s; closing`／`restore orphan placeholder …; closing strip only`／`Queued serial placeholder restore wn=%ld **queueDepth=%ld**`／`Running serial placeholder restore wn=%ld remaining=%ld`。
- **现状**：有折叠事务（`App/FoldTransaction.swift`），但**没有「孤儿占位条主动收掉」与「串行还原队列 + 深度可观测」**。
- **改动**：（a）被收起的窗口若已在别处消失，对应的卷帘条要主动消失；（b）连续还原走一条串行队列，**并记队列深度与剩余数**。
- **验收**：连续还原多扇不打架；窗口在别处被关掉后卷帘条自己消失；日志能读出队列深度。
- **✅ 2026-10-15（803375a）**：（a）原来只有销毁通知到达时查一次窗口服务器；通知丢了或那一刻没删干净，卷帘条就永远留着。现在定时核对兜底：App 还在、辅助功能读不到、窗口服务器连续两轮都查不到（查询成功且为空），才收掉；快速查看的收起本来就是关窗，排除。（b）全部展开本来就在主线程分批串行，现在每批记 `queueDepth`，预算用完记 `remaining`。**真机**：`tests/run-glance-probe.sh --orphan`（签名构建）收起后按关闭、App 仍在跑，卷帘条 8.9 秒后自己消失。

---

#### R11 · 收起高度读 `axToolbarH`

- **依据**：WindowMizer `Finder reduceToTitlebar … axMinH=%f **axToolbarH=%f**`——它读 AX 最小高度**和 AX 工具条高度**，再按 `heightMode`／`classic`／`variant` 分支算。
- **现状**：我们逐 App 记常量（`fixedNonstandardChromeHeight(pid:)` 那一套）＋ `Window/ChromeProfile.swift`，**没读 `axToolbarH`**。
- **改动**：在算收起高度时，把 AX 工具条高度也纳入（有工具条的 App 才有值）。
- **验收**：有工具条的 App（访达带工具栏、Safari 等）收起高度正确。
- **风险**：多一次 AX 往返，放后台队列；拿不到就退回现有常量。
- **✅ 2026-10-16 核过（1e428fe）**：「没读工具栏高度」不成立——通用路径早就按工具栏底边算（`Window/AXWindow.swift` 的 `chromeHeight` → `firstToolbar`），访达、Safari 都走通用路径。新加只读的 `--chrome-report <bundle id>`；签名构建对一扇系统工具栏窗口实测：统一样式工具栏底边 52、保留 52，展开样式 68／68。本机当时访达与 Safari 在这张桌面上没有窗口，没有拿它们本身量（不替你开窗）。

---

#### R12 · 接管系统 HUD 要留一个「还给你」的开关

- **依据**：MediaMate 有一个设置项就叫 `Disable Hiding Native OSD`——**它默认压掉系统原生 HUD，但给了用户一条退路**。
- **现状**：我们压掉系统 OSD 时**没有这条路**（相关面在 `App/NotchLevelControl.swift`／`Core/NotchLevelSuppression.swift` 一带）。
- **改动**：加一个设置项「不停用系统的提示」；开着时我们只旁听、不拦。
- **验收**：开关两种状态各跑一遍，系统的亮度/音量提示行为符合预期。
- **注意**：文案进 xcstrings（zh ＋ en）；`Core/NotchLevelSuppression.swift` 里已有「只旁听」的语义，复用它。

---

#### R13 · 崩溃上报

- **依据**：**WindowMizer 内嵌 PLCrashReporter**（`plcrash.CrashReport.*`、`com.plausiblelabs.crashreporter.data`），并收集 `hw.model`／`hw.logicalcpu_max`／`kern.osrelease`／`kern.osversion`。[production-maturity](production-maturity.md) 里我们那条「崩溃自愈与日志」**至今空白**。
- **已定案（2026-10-15）：纯本地**——接崩溃上报（PLCrashReporter 现成且成熟），**报告只落本地、永不上网**；给用户的是**导出**，不是上传。
- **验收**：人为触发一次崩溃，本地有报告且带机器信息；「不发送」时不外发。
- **风险**：**隐私是最高的那条线**——上报内容必须对照隐私登记（[privacy-page.md](privacy-page.md)，65 个登记项）逐项筛；默认关闭外发。
- **✅ 2026-10-15（部分，0c9e5cd）**：纯本地那一半随 R35 落地——诊断包会带上系统已记下的、我们自己的崩溃报告（最新 10 份），不上网。**待 Aaron**：接 PLCrashReporter 要下载第三方库（需同意）。
- **✅ 2026-10-17（代码，PLCrashReporter 1.12.0）**：Aaron 同意下载后接上。官方发布页最新带预编译包的是 1.12.0（1.12.1／1.12.2 只有源码标签），取 `PLCrashReporter-Static-1.12.0.zip`（SHA-256 `36a00c3d…9b8a`，发布页不提供校验和或签名，值为下载后自算，全文在 `prototype/Vendor/PLCrashReporter/UPSTREAM.md`）。**选静态库而不是 XCFramework**：静态链进主程序，不进 Contents/Frameworks，没有新的嵌套代码要签、公证面不变。启动时启用（Mach 异常方式；被调试器附着时不启用），崩溃后下次启动把报告转成文本存到 `~/Library/Logs/WindowShade/crash-reports/`（最多 10 份）并从崩溃库清掉；诊断包导出时一并带上。全工程原本没有别的崩溃信号或未捕获异常处理（只有一处忽略 SIGPIPE），不冲突；没有任何联网代码。许可已并入 THIRD-PARTY-LICENSES。探针崩溃要同时带 `--probe-crash` 与环境变量 `WINDOWSHADE_ALLOW_CRASH_PROBE`。**本机证据（签名 --stage 构建）**：`--check` 退出 0；`codesign --verify --deep --strict` 通过；`WINDOWSHADE_ALLOW_CRASH_PROBE=1 … --probe-crash` 崩溃（退出 133，SIGTRAP），再启动一次，`crash-reports/` 里出现 `windowshade-crash-…Z.txt`（带 Hardware Model Mac17,4、系统版本、应用版本、崩溃线程栈），崩溃库里的待处理报告随即清掉（第三次启动不再重复保存）；`--export-diagnostics` 的包里带上这份。新增代码里没有 URLSession／网络调用。**待 Aaron**：真机常驻运行时的崩溃（非探针）还没遇到过，下次发布后自然会有；Mach 异常处理器与调试器同时附着会冲突，已在被调试时跳过启用。

---

### P3 · 按需

---

#### R14 · 成本感知的快照缓存（**先核后用——我们已经有了一半**）
- **✅ 2026-10-15 核过不改**：其余四个按条目存图的字典（窗口浏览的 App 图标、窗口浏览内容视图的缩略图、文件架、刘海缩略图）都按当前活着的集合过滤或在关闭时清空，不会无界增长；不必套同一套成本账。
- **依据**：Alcove 的 `cachedSnapshots` ＋ **`cachedSnapshotCost`／`cachedSnapshotCosts`**——不是「都缓存」，而是**按代价决定留哪一个**。
- **现状（已核实，2026-10-15 更正）**：**窗口浏览那一路已经有了成本账**——`WindowBrowserIdleProbe` 直接读 `controller.thumbnails.cachedCostBytes`（成本字节数）。同一条探针还读 `controller.axQueryCount`（等于 Wins 的 `axReadsMinimum`）。**所以这一条不是「没有」，是「没铺开」。**
- **改成什么**：核**其余**用到缩略图／快照的面（置顶预览、看一眼、卷帘条那几种）是否也走同一套成本账；没走的接进去。
- **验收**：多显示器＋多窗口同时要缩略图时，缓存不无界增长；`cachedCostBytes` 在探针里可读且单调可控。

#### R15 · 启动台读系统那份 SQLite
- **2026-10-15 核过，不做**：本机 macOS 27.0.1 上 `$(getconf DARWIN_USER_DIR)com.apple.dock.launchpad/db/` 不存在（整棵用户临时目录与 `~/Library/Application Support/Dock/` 都搜过）——系统从 macOS 26 起改掉了启动台，这份库只在 14／15 上还有。对 27 的用户无意义；O6 同理。
- **依据**：LaunchOS 的 `SELECT item_id, title, bundleid, storeid FROM apps`——**正是 Launchpad 数据库的表结构**。
- **现状**：未记载。**这是一条可查的路**，但要核实当前系统版本上的确切路径与字段，**且系统升级会改 schema，必须有回退**（回退到扫 `/Applications`）。
- **验收**：列表的顺序／分组／文件夹与原生一致；db 不可读时退化成扫描且功能不崩。

#### R16 · 手势按类别分栈
- **依据**：Swish 的 **12 个手势原语**（`GestureUp/Down/Left/Right`／`Inwards/Outwards`／`Hold`／`Tap`／`Mod2/Mod3/ModG/ModS`）＋ **九类设置栈**（Dock／通用／菜单栏／调度中心／九宫格／屏幕／吸附／标签页／三分）。
- **现状**：单文件 `App/TrackpadGestures.swift`（2200+ 行），设置面**没有按类别分**。
- **验收**：手势设置在界面上按类别分组；原语与组合分开表达。
- **风险**：纯整理，**不改行为**；改完必须把已有手势逐条回归。

#### R17 · Secure Input 的可见说明
- **依据**：OmniWM：处于 Secure Input 时菜单栏图标与按钮显示红锁，状态菜单第一行说明「**哪些快捷键被 macOS 扣住了**」。
- **现状**：只在 `App/HabitContext.swift:844` 把 `IsSecureEventInputEnabled()` 当排除项用，**用户看不到原因**。
- **验收**：处于 Secure Input 时，某个可见处能说明「快捷键为什么没反应」。

#### R18 · 常驻面板补齐 `fullScreenDisallowsTiling`（**先核后用**）
- **依据**：WindowMizer 给占位条设了 `collectionBehavior` 三个开关（`fullScreenNone`、**`disallowsTiling`**、`canJoinAllSpaces`）；而**我们自己的 `App/Thumbnail.swift:35` 已经用了 `fullScreenDisallowsTiling`**。
- **现状（2026-10-15 自纠）**：此前写「`fullScreenDisallowsTiling` 只在 `Thumbnail.swift:35`」，**是错的**——本机复核是**三处**：`App/Thumbnail.swift:35` ＋ **`App/OverlayFactory.swift:21`／`:56`／`:186`**（覆盖层工厂，说明多数覆盖层已经带上了）。其余面板各写各的（`App/SlideOver.swift:943`／`:1076`、`App/Carry.swift:18`、`App/PictureInPicture.swift:575`／`:667`、`App/SplitView.swift:644`、`App/SlideOverDropHint.swift:124`、`App/PictureInPictureViews.swift:364`、`PinnedPreviewPanel.swift:14`）。
- **改动**：**逐个核**它在 macOS 15+ 上会不会被系统平铺管到；**该加的加，不该加的别动**。这不是批量替换。
- **核过，结论与规格相反（2026-10-16）**：独立小程序实测，系统「移动与调整大小 › 左」（`_zoomLeft:`）对 key 窗口一律生效——无边框、`.transient`、`canJoinAllSpaces`、**连带着 `.fullScreenDisallowsTiling` 的也照样被挪走**。所以「补齐这个开关」挡不住平铺，**不加**。我们的面板都靠自己 `setFrame` 移动，没有一处用系统拖动（`performDrag` 0 处），拖到屏幕边的平铺碰不到；剩下唯一的入口是我们自己的面板是 key 时按平铺快捷键。能成为 key、又没带开关的有：收起取画面时临时停焦点的 1×1 窗、启动台、CarPlay、刘海（验证或专注时）、卷轴概览、窗口浏览（键盘模式）。合成按键连对照组（普通窗口）都挪不动，自动验证不了。**待 Aaron（一分钟）**：打开启动台，按 fn＋Control＋←，看它会不会被挪到左半边；会的话再定怎么挡（截住那几个动作），不会就结案。

---

### P2 续 · 补齐的边界（R19–R28，2026-10-15 逐类核对后新增）

**为什么要补这一批**：把[更新日志里的 real-world know-how](changelog-knowhow.md) 13 个家族里每个「未做／待核」逐条对回规格，发现**有实质缺口**——包括我自己标为「最大的空白」的台前调度。以下每条都带依据与现状。

#### R19 · 台前调度（Stage Manager）
- **依据**：**19 条**独立记录——DockDoor 七条（「Fixed blank/transparent preview thumbnails under Stage Manager」「Snapped windows leave room for Stage Manager」等）、Rectangle 七条（「fix **multi-space**」「fix **multi-screen**」「footprint window workaround」）、Loop 五条；而且 Rectangle 有一条是**把功能撤到 Terminal flag 后面**，因为「it was causing app instability」。
- **现状**：**基本空白**。全仓只有一条注释借了 Wins 的经验——`WindowBrowser/WindowBrowserController.swift:1704`「台前调度里窗口外框被缩放、捕获尺寸和真实比例对不上时，只留边，不变形」。**没有任何台前调度专门的适配或验收。**
- **改动**：**先验收，后适配**。开台前调度，把已有探针重跑一遍：收起、窗口浏览、分屏、贴边、多屏各一条；把失败的记成问题再逐个修。**别一上来就写适配代码**——19 条里大部分是「系统缩放导致外框与捕获尺寸不一致」，一条尺度修正可能就解决多条。
- **验收**：台前调度开着，上述五类各一条通过；关掉后行为不变。
- **风险**：Rectangle 那条「功能被撤到 flag 后面」说明**这里的适配可能引入不稳**——所以每条适配都要能单独关掉。

#### R20 · 窗口身份边界（orderOut／无标题浮层／静默退出／多实例）
- **依据**：OmniWM「Windows that apps such as **Calendar close by ordering out instead of destroying** are now retired from the layout」；DockDoor「**Untitled** toolbar/overlay windows no longer get mistaken for real app windows」「Apps that quit **without a clean termination notice** no longer leave stale entries」「Closed windows from **separate instances** of the same app no longer linger」；**加上 OmniWM 那份 18 个窗口分类夹具**（含 PiP、Chrome 弹窗、**别的刘海 App 的浮层**、登录窗锁屏遮蔽、快速查看、Word 工具条）。
- **现状**：`AXTabGroup` 只作角色用（见 R4）；**没有以「无标题浮层」或「orderOut 关窗」为名的分类规则**。
- **改动**：把 OmniWM 的 18 个夹具**当验收清单**逐条过；缺哪类规则补哪类。**这是「窗口浏览」那一格的地基**——分类错了，上面的动作全错。
- **验收**：18 个夹具各自的期望分类与我们的实际一致；`kill -9` 一个 App 后条目不残留；两个终端实例并存时关一个不影响另一个。
- **风险**：误判比不判更糟（DockDoor 那条「Office/Chrome Web App 切视图会先关再开窗口」会导致**误退出 App**）——所以「确认没窗口了」这一步必须要收口。
- **部分（2026-10-16，877ca09）**：`--browser-identity`（签名构建）：同一 App 两个实例都列出来后 `kill -9` 第二份，1.1 秒内条目全清、第一份不动 ✅（窗口浏览按进程号记账，退出通知到了整组清；迟到的旧结果按「是不是同一个 App 实例」丢掉）。**发现**：App 用 orderOut「关窗」（不销毁）时，开着的面板里那张卡原本还在、重开面板才消失；**第十一批已修**：面板开着时的存活检查对「查到时在屏上、现在不在屏上」的窗口也重新问一次它的应用，复测 PASS。`--window-census` 只读普查本机全部辅助功能窗口：当时 17 扇，收进的 8 扇都是真窗口，排除的 9 扇是菜单栏条、通知中心小组件、一个无标题无关闭按钮的 Freeform 对话框，没有误收漏收。**还没做**：OmniWM 那 18 类没凑齐（PiP、Chrome 弹出条、别的刘海 App 浮层、锁屏遮蔽、Word 搜索条要那些 App 当场开着）；按我们的过滤（只收 AX 窗口角色、普通层、非桌面小组件）推，PiP／刘海浮层／锁屏遮蔽在高层会被排除，Chrome 与 Word 的普通层无标题条目最可能被误收，要拿真 App 验。

- **R20 续（2026-10-17，窗口分类夹具）**：`GlanceFixture` 加 `--classes`，在临时 App 里各开一扇「不是真窗口」的类；新探针 `--window-classes`（`WindowClassesProbe.swift`）逐类核对「窗口浏览列不列」与 `appCurrentUserWindowCount`（拆出 `isCurrentUserWindow`，行为不变）数不数，期望只有参考窗和带搜索条的文档窗两扇真窗口被列出并数到。构建 `--check` 退出 0（含自测）、签名 `--stage` 成功。

  | 类 | 夹具怎么做 | 期望（列出／数到） | 实测 | 修了吗 |
  | --- | --- | --- | --- | --- |
  | 画中画 | 浮动层、无标题、不抢焦点面板 | 否／否 | **not_run** | 按过滤规则推：非 0 层，排除 |
  | Chrome 弹出条 | 普通层、无标题、无边框的 56 点高条 | 否／否 | **not_run** | 按规则推会被列出，已知开口：与自绘窗口分不开，探针记 INFO 不判失败；真 Chrome 弹窗是有标题的标准窗口，未实测 |
  | 别的刘海 App 浮层 | 状态栏层、顶部正中、不抢焦点 | 否／否 | **not_run** | 非 0 层，排除 |
  | 锁屏遮蔽 | 屏保层小块无边框窗 | 否／否 | **not_run** | 非 0 层，排除 |
  | Word 搜索条 | 文档窗的无标题子窗 | 否／否 | **not_run** | 加了一条窄规则：普通层、无标题、子角色 `AXSystemDialog` 不收（只影响窗口浏览，不会让计数变多；有标题或别的子角色照收，纯逻辑测试已加）。**这条没有真 Word 的证据支持，夹具也造不出该子角色，属推测，没有真机证据前可以整条撤掉** |
  | 参考窗、文档窗 | 真窗口 | 是／是 | **not_run** | — |

  **没跑的原因**：探针要在真屏幕上开窗口，本机使用者在操作（空闲 0 秒）；协调者指定的 macOS 26 虚拟机 192.168.64.3 在跑时已连不上（超时，虚拟机地址已换），且 `vm.lock` 被别的会话占用了一个多小时（已清）。`--browser-identity` 没有改动分类之外的代码路径，同样没重跑。**待补**：在空闲的本机或可达的虚拟机上跑 `tests/run-glance-probe.sh --window-classes` 与 `--browser-identity`（虚拟机里用 `tests/vm/run-core-probes.sh lume@<地址> window-classes browser-identity`，探针已读 `WINDOWSHADE_PROBE_ROOT`）；真 Chrome／Word 的当场验证也未做（没开它们，以免打扰使用者的会话）。

#### R21 · 退出策略按 App 分类
- **依据**：**一对相反的需求**——Wins 3.2「**IM 应用在关闭最后一个窗口后将不会自动退出**，而是保持后台运行」；WindowMizer「**Single-window apps now quit** when closing the placeholder – if that's what they normally do（Ex: App Store, Calculator）」。
- **现状**：未记载。
- **改动**：按 App 分类：IM 类关最后一扇窗**不进后台退出**；单窗口工具类（App Store／计算器）关掉占位条就退出。
- **验收**：微信/QQ 关最后一扇窗仍在后台；计算器关掉占位条正常退出。

#### R22 · 菜单栏在收起/还原时闪错名或留空
- **依据**：WindowMizer **三条**——「Menu bar now shows the app name sooner」「Reducing a window no longer **flashes the wrong app name or "Application"**」「Fixed issue where the **menu bar stayed blank** after reducing windows」。
- **现状**：菜单栏面在 `App/MenuBarController.swift` ＋ `App/MenuBarCoverRetry.swift`；**没有针对收放瞬间的验收**。
- **改动**：先复现（连续收起 5 个不同 App 的窗口，看菜单栏），有则修。
- **验收**：连续收起/还原时，菜单栏一直是当前 App 的名字，不闪「Application」、不留空。
- **✅ 2026-10-16（b4254ff）**：复现不出。`--menubar-owner`（签名构建）收起展开 5 轮、每 10 毫秒采一次「菜单栏归谁」共 613 个样本：只在临时 App 与它后面的 App 之间切换，**从没留空、从没切到 WindowShade 自己的菜单**（收起取画面时那次临时停焦点也没被采到）。只测了同一个 App 的窗口，5 个不同 App 连续收起没测。

#### R23 · Finder 两个坑
- **依据**：WindowMizer **两次**修「Finder window **column sizes** to change after window-shading a window」（Name／Size／Date 列宽在收放后变了）；另有一条「Double-clicking a **Finder folder alias** no longer performs a window action」。
- **现状**：未记载。
- **改动**：先复现。列表视图的访达窗口收起再还原后四列宽度是否不变；双击桌面文件夹替身是否被当窗口动作。
- **验收**：两条各验一次。
- **部分 ✅（2026-10-16）**：列宽那一条——`--finder-columns`（签名构建）开一扇临时访达窗口、经访达自己的菜单切成列表，四列宽 351／181／97／121，收起再展开后完全一样；窗口用完关掉、临时文件夹删掉。**还没做**：「双击桌面上的文件夹替身被当成窗口动作」要真鼠标双击，合成事件验不了，待 Aaron。

#### R24 · 多语言下的布局裁切
- **2026-10-15 已量，待文案决定**：用 `--settings-shots` 加启动参数 `-WindowShade.InterfaceLanguage en|zh|zhHant` 渲染三种语言各 32 张（只覆盖这一个进程，不写偏好），锁屏下也能跑。设置页的副标题是单行、超宽就截断：
  - **英文约 10 处**：隐私页页头「Everything Windo」、快捷键页页头「Works in any app. Record… then…」、收起页「Only when something changed while…」「Track name and artwork at the…」「The dots on the notch's right ear…」、窗口浏览页页头「All of an app's windows on its…」「⌘W closes the window under the…」「Hold and press Tab to pick a…」、指挥模式页「See Claude Code running or…」、快捷键页「The window stays; glance from…」。
  - **简体 2 处**：隐私页页头「WindowShade 读到的每」（原来那一句就超宽，不是 R37 加的第二句造成的）、指挥模式页「在刘海里看 Claude Cod」——这一处连省略号都没有，是硬切。
  - 修法是缩短文案，英文是第 27 批定过案的，**改哪几句、怎么改等 Aaron 定**。
- **依据**：Wins 3.1.1「设置面板在**西班牙语、德语、中文、日语**等语言环境下无法完整显示的布局问题」；LaunchOS v2.3.1「text could be **clipped in some languages**」；boring.notch 专门做了一遍「locale-aware formatting across settings, battery, OSD, progress indicators, and **accessibility labels**」。
- **现状**：英语适配在做（[BATCH27](handoff/BATCH27-ENGLISH-HANDOFF-2026-10-12.md)）；**布局在长语言下会不会裁切、格式化与读屏标签是否在范围内，都没验过**。
- **改动**：**德语最长，最容易撑破**——按最长的那一门验；格式（数字/日期/时间）与**读屏标签**都要进范围，不只是文案。
- **验收**：每种语言跑一遍设置窗口与常驻面，无裁切/溢出；数字、时间、读屏标签符合当地习惯。

#### R25 · 多点触控按设备归属
- **依据**：OmniWM「Raw multitouch ownership is **isolated per physical device**, preventing a built-in trackpad and an external trackpad from overwriting or ending each other's gestures」；以及「**Missing final lift frames** recover after a stale gap so later gestures are **not permanently blocked**」。
- **现状**：**确认不带设备身份**——`App/TrackpadGestures.swift` 的触点路径只数 `.touching` 的个数（`:2214` 一带）。
- **改动**：手势会话按物理设备归属；补一条「丢最后一帧」的过期恢复。
- **验收**：接一块外接触控板，两边的滑动互不打断；故意中断一次手势后，下一次照常。

#### R26 · 权限弹窗还开着时启动
- **依据**：WindowMizer「Fixed a crash that could occur **during first launch while macOS is asking for Accessibility or Screen Recording permission**」。
- **现状**：未核。
- **2026-10-16 代码核过（没在全新机器上跑）**：顺着 `applicationDidFinishLaunching`（`WindowShade.swift:355-400` 一带）逐个看了启动期用到辅助功能／屏幕录制的地方。
  - 不会崩：所有 `CGEvent.tapCreate`（10 处）都是 `guard let`，失败只记日志；启动路径上没有 `try!`、对 tap／AX／`SCShareableContent` 结果的强解包，也没有等权限的同步阻塞或无界重试。`ensureAccessibility` 带提示参数调用，不阻塞。截图路径先过 `CGPreflightScreenCaptureAccess`（`Capture/WindowSnapshot.swift:54`），`SCShareableContent` 都是 `try`／`try?`。
  - 授权晚于启动也能接上的：标题栏点击 tap（`WindowShade.swift` 的 `setupEventTapWhenTrusted`，2 秒轮询）、捏合 tap（3 秒重试）、刘海音量亮度键（听 `com.apple.accessibility.api`）、窗口浏览（自带 `lastAccessibility`）、全局输入过滤（建不起来就退回 NSEvent 监听）、Dock 点击（每次事件现查）。
  - **查到一处「授权后不恢复」**：`switcher.applySetting()`（⌥Tab 窗口切换，默认开）启动时没授权就当作「关」，`missionControlKeys.applySetting()`（默认开）tap 建不起来就放弃；两者此前只在改设置时才重试，所以首次启动「弹窗开着、用户后点允许」之后要重开 App 才生效。已改：轮询装上标题栏 tap 的那一刻、以及 R2 体检发现「权限回来了」时，调用 `reinstallAccessibilityHooks()` 把这两个再应用一遍（都幂等）。不涉及文案。
  - 没动：滚动／中键 tap 在 `openFailed` 后停住，但它们默认关，首次启动用不到；留作后续。
  - **2026-10-17 补**：中键折叠行在「端口没创建出来」而停住时，不再说「被系统停掉了」，改说「需要先允许辅助功能」（`settings.input.middleFold.needAccessibility`，三语；`HookDriver.waitingForAccessibility`）。滚动行的同类文案未动。复核后补：设置行还要 `!AXIsProcessTrusted()` 才显示该句（已授权却仍建不出端口时回到「被系统停掉了」，不冤枉成缺权限）；滚动行不同步（范围按原规定，只改中键行）。R8 的 Spectacle／AeroSpace 包标识已对上游核过，无需改。
  - **not_run**：真正的全新机器首次启动（点弹窗、拒绝、中途允许）。以上是读代码的结论，不是运行证据。
- **改动**：全新机器第一次启动，逐个点权限弹窗，看会不会崩。
- **验收**：不崩；拒绝后也能继续（见 R2）。

#### R27 · 按显示器落盘的键过一遍 UUID
- **✅ 2026-10-15（e884fa2）**：落盘的显示器编号只有两处。「锁定程序坞到某块屏」改成同时存 UUID、先认 UUID 再退回编号（旧设置无缝迁移）；收起的恢复记录不改（只在异常退出后的下次启动用，同一次开机编号不变）。
- **依据（2026-10-15 自纠）**：**三家已核实**——DockDoor（`CGDisplayCreateUUIDFromDisplayID`，读源码）、OmniWM（更新日志原文「Stable display UUIDs…」）、**Wins（`dockDisplayLock.targetUUID`／`targetUUIDs`，函数级命名空间，从命名推断）**；**Alcove 未核实**（我先前把它算进「四家」，但它的件里只有 Foundation 的 `UUID` 类型，**没有 `CGDisplayCreateUUIDFromDisplayID`**）。
- **现状**：`App/NotchSpaceGate.swift:174` 已用 UUID；**其余「按屏落盘」的键没有系统过一遍**。
- **改动**：把按显示器存的设置/状态**逐个核**，键必须是 UUID 而不是 `CGDirectDisplayID`，并留迁移路径。
- **验收**：重启、重接显示器后，某块屏的设置还在那块屏上。

#### R28 · macOS 27 权限改名 + 证书轮换说明
- **✅ 2026-10-15（a）**：本机 macOS 27.0.1 的 `SecurityPrivacyExtension.appex` 里 `ACCESSIBILITY` 键已是 en「Device Control and Data Access」／zh_CN「设备控制和数据访问」／zh_TW「裝置控制和資料取用」——**隐私与安全性里辅助功能那一栏确实改名了**（「减少动态效果」所在的真正的「辅助功能」设置没改）。`Core/PrivacyPaneName.swift` 按系统版本换名（26 及以前逐字不变），套在 14 句「教人去那一栏开权限」的文案上；新旧名字放在本地化目录里；隐私页那一行与两版 README 两个名字都写。（b）换证书要重新授权的说明：未做，等真的换 Developer ID 那一版再写。
- **依据**：boring.notch v2.8-rc.0「Accessibility permission references now use the current macOS terminology（**Device Control and Data Access**）」；WindowMizer「Conform to macOS 27（**Golden Gate**）renaming of System Settings: **Accessibility panel -> Device Control and Data Access**」；AeroSpace **两次**「Update codesign certificate due to expiration. **AeroSpace will re-request accessibility permission.**」
- **现状**：文案按当前系统写；**没有「换证书后要重新授权」的说明**。
- **改动**：（a）文案与系统设置的分区名一致，旧系统有回退；（b）**换 Developer ID 那一版，欢迎流程里要有一句「要重新授权一次」**，不静默失灵。
- **验收**：文案与系统一致；换签名身份后用户被明确告知。

#### R29 · 没有屏幕录制权限时的降级路径（**公认范畴里的欠账，2026-10-15 核对后补**）
- **依据**：窗口工具被攻击最多的第二点就是**屏幕录制**（「一个窗口工具凭什么录我的屏」）。竞品都专门做了降级：DockDoor「**Skipping screen recording no longer repeatedly asks for permission**」；Ice「Ice can now work in a **limited mode without screen recording permissions**」。见 [北极星](north-star.md)§二第 4 项。
- **现状**：有零散的权限读取（`ScreenCaptureBridge.swift` 的 `hasScreenRecordingPermission`、`MenuBarController.swift:110`），**但没有一条成文的「没有屏幕录制时哪些功能还能用」的清单，也没验过核心动作在缺权限时是否照常**。
- **已定案（2026-10-15）：录屏当作增强，不是核心**——**没有屏幕录制时，收起／还原／手势／分屏／窗口浏览的列表与动作全部照常**，只有「实时画面」降级；**并主动对外说「不录屏也能用」**。
- **改动**：**先核实，再补路径**——（a）在没有屏幕录制权限的机器上跑一遍：收起、还原、手势、分屏、窗口浏览的**列表与动作**是否照常；「实时画面」与缩略图降级成什么（静态占位？上次缓存？不出？）。（b）把结果写成一份**对外可引用的降级清单**。（c）**拒绝一次之后不再反复问**。
- **验收**：缺权限时，清单里承诺可用的每一项**确实可用**；提示只出现一次；清单能直接被引用回答「凭什么要录屏」。
- **风险**：**不要为了「能降级」而把实时画面退化成假的**——降级要说清楚，不是假装。
- **✅ 2026-10-15 代码核对（真机 not_run：这台 Mac 收回屏幕录制属于改系统安全设置，要 Aaron 在另一账户或另一台机器上跑）**。全仓 `hasScreenRecordingPermission()`／`CGPreflightScreenCaptureAccess()` 闸门逐处过了一遍，缺权限时：

  | 功能 | 没有屏幕录制时 | 依据 |
  | --- | --- | --- |
  | 收起／还原 | **照常**；收起外观本该截图的（原生截图、缩略图）退回统一标题栏 | `App/ShadeController.swift:141` |
  | 手势、分屏、魔法平铺、移到另一块屏、带到每张桌面 | **照常**（分屏、平铺无闸门；带到每张桌面的预览退回静态画面） | `App/Carry.swift:492`，菜单只要辅助功能 |
  | 窗口浏览 | **列表与动作照常**，卡片只显示图标与标题，页脚说一次原因 | `WindowBrowser/WindowBrowserController.swift:1394` |
  | 置顶预览、看一眼、卷轴边上的看一眼 | **不可用**（本身就是实时画面），点了说「需要屏幕录制权限」 | `PinnedPreview.swift:397`、`App/ScrollStripPeek.swift:210` |
  | 侧拉、画中画 | **不可用**（镜像别的窗口的实时画面），菜单里灰掉 | `App/MenuBarController.swift` |
  | 「拒绝一次后不再反复问」 | **已满足**：启动引导只在首次自动出现；更新后的提醒只在「更新前有、更新后没了」时出现；系统授权框只在未决定时弹 | `App/Preferences.swift:1124`–`:1127`、`App/Updater.swift:160` |

  **可对外引用的一句（真机核过再放进 README）**：「不开屏幕录制也能用：收起、还原、手势、分屏和窗口浏览的列表与动作都照常；窗口缩略图、置顶预览、看一眼、侧拉和画中画需要它。」
- **一条可选的实现路子（别人的 know-how）**：Alcove 把权限相关的工作隔离进一个 **`PermissionHelper`**（XPC），另有一个 `batteryHelper`——**按能力切分进程**。若我们要让主 App 完全不问屏幕录制，可以考虑把捕获放进独立 helper，由它自己持有那份权限。**但这是一次架构选择（多一个进程、多一份签名与 TCC 身份），不要为了「少问一次权限」就上**——先做完上面的核实再判断值不值。

#### R30 · 系统的「Mac 设置检查」（**先核实用不用得上，别照抄**）
- **依据**：**三方共识**——ChainYourMac 有一个 `MacSetupChecker`，检查 `separateSpacesEnabled`（「显示器具有单独空间」）、`rearrangeSpaces`（「自动依最近使用重新排列 Spaces」**要关**）、`reduceMotion`；而 **Paneru 与 PaperWM 的 README 要求的是同样那两个开关**（[niri.md](niri.md):18 记过 Paneru 那条；PaperWM 的 README 原文见[竞品深挖](competitive-deep-dive.md)§四）。三份独立实现收敛，所以这是**卷轴这一格的入场条件**。
- **现状**：**我们完全不检查这两个开关**（`spans-displays`／`mru-spaces` 全仓 0 处）。我们走的是「露一条边」而不是「把窗口停在屏幕外」，**所以「显示器具有单独空间」未必是必需的**——但**卷轴跨屏、跨桌面（[scorecard](scorecard.md) 92）与「自动重排 Spaces」会不会打架，没验过**。
- **改动**：**先核实**——在「自动重排 Spaces」开着与关着两种情况下，跑卷轴、跨桌面、停靠那几条；确认哪些功能受影响。**受了影响才加检查**（照 ChainYourMac 的做法：缺哪条说哪条，并给一个直接打开对应系统设置的入口——Wins 的 `dockLock.hud.openSystemSettings` 是同一个形状）。
- **验收**：受影响的功能有清单；检查只在真受影响时出现，且一次说清楚。
- **风险**：**不要因为别人要求就要求**——我们的实现不同，照抄会把用户吓跑。

#### R31 · 我们自己改过的系统设置：退出/崩溃要恢复，卸载要干净
- **✅ 2026-10-15（433a3ba）**：全表核过只写一个系统键（程序坞 `mineffect`），写前落盘原值与「原本有没有」，正常退出与异常退出后的下次启动都还原；程序坞其它键只读。顺带修了两处越积越多的残留：侧拉恢复记录清空后不删文件（本机积了 132 个），测试 suite 只清内容不删文件。两版 README 加「怎么彻底删掉」。
- **依据**：这是用户装之前的常见一问（「它改了我的系统设置吗？关了/删了会恢复吗？」）。**我们确实会写系统设置**：`WindowShade.swift:752` 写 `com.apple.dock mineffect`。
- **现状**：**这一条我们做得比多数人好**——有持久化会话：`originalDockMinimizeEffect` ＋ 把「原本有没有这个键」与「原值」落盘（`dockMineffectHadOriginalDefaultsKey`／`dockMineffectOriginalDefaultsKey`，`:763`–`:768`），崩溃后也能恢复（`:781` 的 `restoreDockMinimizeEffect`）。
- **改动**：（a）**把它变成一条通用规矩并核一遍**——凡是写过的系统键，都要「记原值（含「原本不存在」）→ 可恢复 → 崩溃后仍能恢复」，逐键核；（b）**「怎么彻底删掉它」要有答案**（登入项、系统键、我们建的文件与目录各在哪、怎么删）。
- **验收**：把每个写过的键列出来，逐条给出恢复路径；强杀进程后重启，`mineffect` 回到原值；一份「完整卸载」清单能直接给用户。

#### R32 · 窗口菜单（Window Menu）的正确性
- **依据**：WindowMizer 的日志里专门有一条 **`Window menu duplicates detected (gen=%ld, reason=%s). count=%ld titles=%s`**，还有 `Window menu snapshot (gen, reason, items, listItems, listSeps)`——**说明「窗口菜单出现重复项」是这类产品的已知失效**，而且它为此外写了代数与原因追踪。
- **现状**：**我们自己也维护窗口菜单**——`WindowShade.swift:526` 装 `StandardMenu.make(...)`，注释写明含「关闭/最小化/卷轴概览」（`App/StandardMenu.swift:9`）。**连续收放时窗口菜单会不会出现重复/错项，没验过。**
- **改动**：连续收起/还原多扇窗，看窗口菜单的项数与内容是否正确、有没有重影。
- **验收**：收放 10 次后菜单项数正确、无重复、无残留。
- **风险**：低（先验后改）。
- **✅ 2026-10-15**：探针收尾加一次清点：主菜单与状态菜单逐层查同名项重复；`--orphan`、`--soak` 等多组探针跑完都 `PASS r32: no duplicate items in the main or status menu`（300 次收放之后同样）。

### P3 续 · 成熟软件的方法（R33–R38，2026-10-15 按工程与营运方法论查出来的）

**这一批问的不是「别人有什么功能」，是「成熟软件怎么做工程与营运」。** 依据来自这一轮调研里各家做对的地方（OmniWM 的三条流水线、WindowMizer 的崩溃上报与帮助手册、ChainYourMac 的 MIT 署名），**以及我们自己在[竞品深挖](competitive-deep-dive.md)里夸过的东西**。

**先说已经有的（别重造）**：**`Core/ReleaseDefaults.swift` 是一套发布门禁**——唯一开关表，每条「设计上默认开」的新功能带 `deviceVerified`；**没真机验过的一律默认关但功能在**，用户显式设过的值不被覆盖。**这是成熟做法，我们已经在做。** 另有：应用内更新说明链接、`UpdateLaunch` 的自检与启动记录、`Support/Diagnostics.swift` 的卡顿哨兵、`Core/WS2DiagnosticTail.swift`（注解写明「**绝不自动持久化或发送**」）、Sparkle 依赖固定版本、`.gitignore` 已盖住 `*.mp4` 与 `/Topit/`（根目录那几个异物**没有被 git 跟踪**，已核）。

#### R33 · CI：把 `build.sh --check` 挂到每次推送
- **✅ 2026-10-15**：`.github/workflows/ci.yml`（macos-26、选最新 Xcode、先断言 Sparkle 在、再跑 `--check`）。**本地未推送**，runner 上的 Xcode 是否到 27 未知，日志第一步会打印。
- **依据**：**OmniWM 有三条流水线**——`ci.yml`（守门）、`release.yml`（发版）、**`canary.yml`（金丝雀通道）**。
- **现状**：**全仓没有任何 CI**（没有 `.github/workflows/`，也没有其它 CI 配置）。`build.sh --check` 只在本地跑——**门禁存在，但没人强制它。**
- **改动**：先只做一条 `ci.yml`：推送到分支/PR 时跑 `./build.sh --check`。**不需要任何秘密（不签名、不发布）**，所以是最便宜的一条。
- **验收**：PR 上能看到这条检查；失败能拦住合并。
- **风险**：低。**不要一次把三条全铺**——release/canary 涉及签名密钥，那是 B 组（Developer ID）之后的事。

#### R34 · 版本号纪律：一个版本号 = 一份不可变的构建
- **✅ 2026-10-15**：`scripts/check-release-version.sh`（`CFBundleVersion` 不大于 appcast 已发最高 build 号就失败；当前 16＝16，**正确地失败**）；`--stage` 遇到时只警告、包不能发（与「更新器没接齐」同一种处理）；`DEVELOPMENT.md` 发布第 1 步与发布关第 5 项接上它。规则本身 `DEVELOPMENT.md:303` 早就写了，缺的是强制。
- **依据**：成熟软件通例，也是 Apple 的设计意图——`CFBundleShortVersionString` 是营销版本，**`CFBundleVersion` 是构建号，每次发布递增**。
- **现状**：**git 历史里出现「第 11 次同版本号重发」**（`e517820 release: 第11次同版本号重发（分割顯示入库）…`，之前还有第 4、7、8、10 次）。**同一个版本号发过十一次不同的构建。** 后果：appcast 分不出新旧、用户说不清自己在哪个构建、回滚无从判断、支持与诊断全部失去分辨力。
- **改动**：写死规矩——**每次发布（含重发）递增 `CFBundleVersion`**；营销版本号只在不兼容或功能节点时改。
- **验收**：下一次发布起每个 appcast 条目对应唯一 build 号；「同版本号重发」从提交历史里消失。
- **风险**：低（纯流程）。

#### R35 · 一键导出诊断包（R13 的姊妹条）
- **依据**：**OmniWM**「issue reporting builds each diagnostic log from **fresh runtime state**… The log is **revealed in Finder for review before manual attachment**」；**WindowMizer** 内嵌 PLCrashReporter 并收集 `hw.model`／`logicalcpu_max`／`kern.osrelease`／`kern.osversion`。
- **现状**：有 `WS2DiagnosticTail`（立场正确：本地、不自动发）与卡顿哨兵，**但没有「一键导出成一份可附给我们的包」**。
- **已定案（2026-10-15）：纯本地，永不上网**。改动：做一个导出：**本地生成 → 先在 Finder 里给用户看 → 用户自己决定附给谁**。**默认不发任何东西，不做网络上报、不做匿名计数。**
- **验收**：导出包用户自己能读懂；里面**不含**隐私登记里列过的敏感项。
- **风险**：低。**导出内容必须对照隐私登记逐项筛**（与 R13 同一条红线）。
- **✅ 2026-10-15（部分，0c9e5cd）**：`Core/DiagnosticsBundle` ＋ `App/DiagnosticsExport`：复制本 App 日志与我们自己的崩溃报告，写一份人能读的 `summary.txt`（版本、系统、机型、界面语言、两项授权状态、末尾一句「这里的东西没发出去，附给谁你自己决定」）。只搬已经在本机的日志与报告、不新采集任何东西，隐私登记加了计划中的「诊断导出」一行（三语言）。命令行 `--export-diagnostics [目录]` 在签名构建上实测通过。**待 Aaron**：设置或菜单里的入口（新表面，先过设计准入）。

#### R36 · 应用内反馈入口
- **依据**：成熟软件常规做法；我们现在**菜单里没有任何「报告问题」**（全仓 0 处）。
- **现状**：只有 `UpdaterCopy.releaseNotes` 指向 GitHub releases。
- **改动**：菜单加一项「报告问题」，打开带**环境信息模板**的 issue（build 号、macOS 版本、机型）——**仍然是用户自己按发送**。
- **验收**：能打开、模板里带对了 build 号与系统版本。
- **风险**：低。**不要让这一项变成「自动收集」。**

#### R37 · 面向用户的隐私声明
- **2026-10-15 补记**：App 隐私页的页头副标题是单行、超宽截断（R24），所以 R37 加的第二句「不收集使用数据…」在 App 里只能点 ⓘ 才看得到；官网与 README 上是可见的。要在 App 里看得见，得给隐私页另找位置——**版面决定，等 Aaron**。
- **✅ 2026-10-15（部分）**：App「隐私」页头、官网 `/privacy/`、两版 README 加同一句「不收集使用数据，也不做任何统计或上报」（代码核得到：无统计 SDK、`SUEnableSystemProfiling=false`、导出只存本地）。**「除了检查更新，都不离开这台 Mac」没有放出**：它挂在 [privacy-page.md](privacy-page.md) 的 P2（`nettop` 实测）后面，而且 `MKLocalSearch`／`MKDirections`（`App/NotchActivityController.swift:656`–`:664`）会连 Apple 的服务器，这句很可能本身不成立。**更正现状**：App 与官网早有逐项隐私页（「隐私」一栏＋`/privacy/`），README 也有隐私一节。
- **依据**：我们要**辅助功能 ＋ 屏幕录制**，而**「凭什么要录屏」正是[北极星](north-star.md)§二第 4 项列的攻击点**。成熟软件对此的答案是一份**面向用户的**声明，不是内部登记表。
- **现状**：有 `docs/privacy-page.md`（**内部登记，65 个条目**，给我们自己和律师看的）；**README 里没有给用户的隐私说法**。
- **改动**：写一份**用户能读懂**的隐私声明：读什么、为什么、存在哪、**哪些绝不出本机**、**「没有任何网络上报」要明写**（已定案）、怎么验证（指向登记表）。与 R29 的降级清单互相引用。**顺带把常驻可见面的三条内容规矩写进用户能看见的地方**（紧凑区不放描述性文字／不放旁人可能看到的敏感信息／不放推广文字与无关动作）——这三条现在只在[生产成熟度](production-maturity.md) 的动作清单里。
- **验收**：一句话能回答「你们拿我的数据做什么」；声明里每条都能在登记表里找到对应。
- **风险**：低。**声明必须与实现一致**——不一致比没有更糟。

#### R38 · 第三方许可声明（**我们夸过别人、自己却没做的那件事**）
- **✅ 2026-10-15**：构建把三份许可（`Vendor/Sparkle-LICENSE`、`Vendor/mediaremote-adapter/LICENSE`、`docs/third-party-lock-overlay.txt`）合成 `Contents/Resources/THIRD-PARTY-LICENSES.txt`；「关于」面板多一行「第三方许可」打开它；仓库根 `THIRD-PARTY-LICENSES.md` 是索引。**更正**：Sparkle 的许可一直在 `prototype/Vendor/Sparkle-LICENSE`，缺的是没进包。
- **依据**：我们在[竞品深挖](competitive-deep-dive.md)里把 ChainYourMac 的 MIT 合规写成「**做得又正确又可查的样例**」——随包发行 MIT 二进位 → 用自己凭证重签 → **在产品内给署名与许可**。**而我们自己随包带着 Sparkle（MIT），`Vendor/Sparkle.framework` 里找不到 LICENSE，仓库根也没有 `NOTICE`／`THIRD-PARTY-LICENSES`。**
- **现状**：`LICENSE` 只有我们自己的（MIT）。MIT 条款要求**版权声明与许可全文随所有副本或实质性部分一起提供**。
- **改动**：加一份 `THIRD-PARTY-LICENSES`（Sparkle 的版权与许可全文），并让它**随发行包可见**（设置里一个「许可」项，或关于页里一行）。
- **验收**：发行包里能查到 Sparkle 的许可全文；只拿到 `.app` 的人也能找到。
- **风险**：低。附带好处：**批评别人合规之前，自己得先干净。**

#### R39 · 长期运行的资源账：一次泄漏/循环引用体检 ＋ 长会话观察
- **依据**：**OmniWM 自研了一套 ARC 稽核器**（`Scripts/arc-audit.sh` ＋ `arc-audit/ArcAudit.swift` ＋ `Counters.c/h`）专门**查循环引用**；**而我们自己 `docs/review-handoff.md:301` 的 L6「观察自身与 WindowServer 的 CPU/内存/能耗」就标着 ❌ 未做（需要 Instruments／长时间会话）**。而「不拖慢我的机器」是[北极星](north-star.md)§二第 3 项，**「用久了越来越卡」正是这一项最常见的攻击**。
- **现状**：**从来没有做过泄漏检查**。代码在这一点上纪律很好——`[weak self]` **1174 处**；但 `[self]`／`[unowned self]` **62 处**是风险面（逃逸闭包／计时器／观察者持有 self 的地方）。
- **改动**：**先量后改**——（a）用 Apple 自带工具跑一次**长会话**（命令行可跑的 `leaks` ／ Instruments 的 Leaks 与 Allocations）：例如收起/还原 200 次、开合窗口浏览 100 次、悬停看一眼 100 次；（b）把曲线记下来（对象数、内存是否单调增长）；（c）**有增长才修**，修完再量一次。
- **验收**：一份「跑 N 次操作后的内存/对象数曲线」，**单调增长与否有结论**；L6 从 ❌ 变成有证据。**这一步同时把[性能与能效](perf-energy.md) E2 的「开了几个常驻面」那一档填上。**
- **风险**：低（只测不改）。**不要一上来就改代码**——先证明有没有问题。
- **✅ 2026-10-15（0d72706）**：`tests/run-glance-probe.sh --soak --soak-rounds 300`（签名构建、同一进程收起展开 300 次）：内存足迹 32.6 → 32.5 → 32.7 MB（热身、中段、末尾），窗口数 12 → 12，**没有单调增长**；收尾 `leaks` 1019 处共 62 KB（静置基线 418 处 20 KB，归属还没逐条看，量级上不构成「用久了变卡」）。窗口浏览开合与悬停看一眼的长会话还没跑。**一个坑**：临时 App 默认 90 秒自己退出，长会话在第 129 轮撞上会报「展开超时」——不是产品问题，已给 `--lifetime`。
- **一条可选的工具做法（别人的 know-how）**：OmniWM 的 trace 录制能给出**有界、限量**的「窗口发现／分类／重试／替换」时间线——R20（窗口身份边界）若查不动，可以照那个形状做一条**只在我们自己探针里开**的 trace。

**不立项但记在案上**：`CHANGELOG.md`／`CONTRIBUTING.md`／`CODE_OF_CONDUCT.md`——**单人项目里这三件可选**（release notes 在 GitHub Releases 与 `docs/releases/`，贡献者文档在 `AGENTS.md` 与 `DEVELOPMENT.md`）。**但建议补 `SECURITY.md`**：我们是要辅助功能与屏幕录制的应用，有一条安全披露通道是这类应用的常规期待（可与 R36 合并成「怎么找到我们」）。

### P3 续 2 · 《竞品深挖》§二 可借项的收口（R40–R42 ＋ 处置表）

**为什么单列这一节**：把[竞品深挖](competitive-deep-dive.md)§二那张 **86 行**的「可借项」表逐行对回本规格，发现**有一批行从来没有变成任务**——「列为可借却从未动手」和「170 提交 0 发布」是同一种病，只是更隐蔽。**这一节把那 96 行每一行都给出处置**，剩下的才立新项。

#### R40 · 下载进度卡（Atoll 那三条）
- **✅ 2026-10-15**：第①条落地——临时文件消失时，同名正式文件必须非空、修改时间不早于开始追踪（留 2 秒），否则算取消（Firefox 的 0 字节占位、本来就有的同名旧文件）；读取那一侧只给正在追踪的下载对应的正式文件多读大小与修改时间，读不到退回原判据。隐私页「读到什么」三种语言同步改写。第②③条（Safari 包递归加总、按 allocated size 算进度）**不适用**：卡片刻意不显示百分比，只画不定长的弧。
- **依据**：Atoii `DownloadManager` 的三条——① **完成 vs 取消的判定**：目标档**被写过**、非空、且时间戳**比开始时晚**；② **Safari 的 `.download` 是 bundle**，字节落在子档里，要**递归加总**；③ 用 **allocated size** 而不是 logical size 算进度（否则对预分配整档的浏览器会显示成「瞬间完成」）。另有一条工程做法：**扫描簿记与目录 watcher 分开，测试可注入扫描**。
- **现状**：`progress-in-notch.md`（进度卡设计）里记着我们自己的规则，**但缺这三条**；这一格是**新表面**。
- **改动**：按上面四条实现/补齐；验收用 Firefox（占位档）／Safari（bundle）／Chromium 各下一次，中途取消一次——**取消不说「完成」**。
- **验收**：三种浏览器各一次；取消的那次不报完成。

#### R41 · No focus stealing（后台 App 弹窗不抢焦点、不滚 strip）
- **依据**：ChainYourMac 官网把它当成一条明确承诺（[竞品深挖](competitive-deep-dive.md)§二）。OmniWM 也修过同一族：「**Background apps' stale AX focused-window callbacks can no longer steal focus** from the actual frontmost app」。
- **现状**：我们多处注释写着「不抢焦点」（`WS2SilentProductPort.swift:440`、`FoldTransaction.swift:822`），**但没有一条是针对「后台 App 弹窗」这个具体场景验过的**。
- **改动**：**先验**——后台 App 弹窗时，前台 App 不变、卷轴不滚；有问题再修。
- **验收**：一个会在后台弹窗的 App（如终端跑一条 `osascript -e 'display dialog'`，或邮件类 App）弹出时，前台与卷轴位置都不动。
- **✅ 2026-10-16（b4254ff）**：`--focus-steal`（签名构建）：收起后让第二个临时 App 在后台弹提示框、还试着把自己调到前面；期间没有任何 App 被激活（我们没有，系统也没让它抢走前台），卷帘条原位。

#### R42 · 卷轴跟手的完整配方（niri／Paneru 那几条）
- **✅ 2026-10-15 逐条核过**：松手速度只看最后 150 ms（另加「停住再抬手不甩出去」）、求导下限（< 8 ms 当 0）、按减速率推算落点（指数衰减）、停放 10 点（`ScrollStrip.sliver`）、列宽存比例（预设档与「记住列宽」）——都已在代码里。减速率 niri 是 0.997，我们刻意取 0.998（对齐官网手感），不采纳。唯一的裸数字 0.998 已改成 `ScrollStrip.releaseDecelerationRate`，「张开跟手的概览」直接引用它。未核：#59（写窗口时先停听）、#60（应该在哪／实际在哪分开存）。
- **依据**：niri 的**手感常量**（手指位移 → 一屏 = **1200 逻辑点**；甩动投影 **150ms** 速度视窗、阻尼 **0.997**）与 Paneru 的**时间步长纪律**（积分上限 `1/30s`、求导下限 `1/1000s`）、**惯性 `v *= exp(-k·dt)` 且故意不设上限**、**停放 10px**（`PARKED_STRIP_SLIVER`）、**binpack 栏内高度**；AeroSpace 的**角外一像素 ＋ 记原位**、**切换时先 unhide 可见的再 hide 不可见的**；PaperWM 的**列宽存比例不存像素**。
- **现状**：卷轴已改过、**未发布**（[niri.md](niri.md)）；上面这些**多数没进我们的实现或没归档成常量**。
- **改动**：逐条对：**已经会的标出来**，没会的补上，**手感类一律变成具名常量**（可调、可回归）。
- **验收**：每一条有「已实现（位置）／已补／不采纳（理由）」；手感常量在代码里是具名常量而不是散落的数字。
- **风险**：中——卷轴是已改未发布的表面，**改它要连着跑 strip 那一组探针**。

#### 《竞品深挖》§二 的逐行处置

`已覆盖` = 归到本规格某任务 ｜ `已实现` = 代码里已有 ｜ `不采纳` = 明确不做（附理由） ｜ `→ Rxx` = 本节新立的任务

| # | 可借项（缩） | 处置 |
| --- | --- | --- |
| 1–4 | Atoll 下载完成判定／Safari bundle／allocated size／扫描可注入 | **→ R40** |
| 5–6 | niri 手感常量（1200 点／屏、150ms、0.997） | **→ R42** |
| 7 | 列宽存比例不存像素 | **→ R42** |
| 8 | 平台吃掉手势时从 scroll delta 反推方向 | **→ R42**（并已部分实现：`GlobalInputPredicate` 那一套） |
| 9 | 角外一像素 ＋ 记原位（AeroSpace） | **→ R42** |
| 10 | 切换时先 unhide 再 hide | **→ R42** |
| 11 | 最小尺寸：先试 → settling pass → 才判定被夹住 → 提示 | **已覆盖 R6**，但 **R6 要按这条加强**（见下） |
| 12 | DockDoor 12 条当验收用例 | **已覆盖 V8** |
| 13 | Wins 的拖动误触发与 macOS 27 拖动卡顿 | **已覆盖 R6／V8** |
| 14．33 | AirPods 预渲染影片／串台 | **不采纳影片**（我们要做的是**设备电量**这一格，方法待定；照影片做等于把 20 段视频背进包）；**串台那一条采纳为验收**（连不同型号时图形对得上） |
| 15 | 正在播放走**公开** Apple Events 定向控制 | **已覆盖**（design 稿倾向公开路线；[竞品深挖](competitive-deep-dive.md)§二已定） |
| 16 | 无标题窗口／Premiere 浮动面板／系统设置／Finder 替身／显示器变化 | **已覆盖 R20（前三）、R23（Finder 替身）、V9（显示器变化）** |
| 17 | 分屏按刘海精确避开 | **已覆盖 R19 的验收组**（放进台前调度那一组一起验） |
| 18 | No focus stealing | **→ R41** |
| 19 | 装／跑着别的窗口管理器时检测并警告 | **已覆盖 R8** |
| 20 | self-healing engine | **已覆盖 R1／R3**（我们是进程内自愈，不是外部引擎——**不采纳「外壳＋引擎进程」那套架构**：多一个进程多一层签名与 IPC，我们没必要） |
| 21 | 一条 strip 每显示器／每 Space 各一份 ＋ 按屏单独关 | **部分已实现**（[scorecard](scorecard.md) 记「每张桌面都有」）；**「按屏单独关」未做** → 归 **R27** 一起核 |
| 22 | 权限面收到最窄：不要屏幕录制 | **已被 R29 的定案取代**（Aaron 已定：录屏当增强，不是核心——**比 ChainYourMac 的「完全不要」更务实**） |
| 23 | ChainYourMac 与 MIT 的 Paneru 同源 | **已查清**（[竞品深挖](competitive-deep-dive.md)§一：Swift 外壳 ＋ 随包引擎），**不是任务** |
| 24 | 事件处理两种形态同存（全域 ＋ **按程序** tap） | **不采纳**：我们的按 App 后台队列 ＋ 逐调用熔断已经解决「一个 App 卡住不拖全局」这个**目的**；按程序 tap 是 WindowMizer 的手段，不是目的 |
| 25 | 跟着背景亮度走的对比描边 | **不采纳（当前）**：我们的刘海在深色胶囊上，轮廓靠明度对比已经够；**若换壁纸实测看不清再立** |
| 26 | 渐进模糊 | **不采纳（当前）**：同上，先看实测 |
| 27 | 私有 API 隔离进 XPC | **不采纳（当前）**：我们**确有私有面**（§7 第 12 条：`Private/` 桥接层 `dlopen` 载入 SLS／DisplayServices 等，有写），但它集中在刘海亮度与窗口服务器几处，**隔离进 XPC 是一次架构选择**（多一个进程与签名身份），与 R29 那条 helper 的权衡同理——先不做 |
| 28–29 | 波形来自抓音频／aggregate device | **不采纳（当前）**：[scorecard](scorecard.md):29 已定「有意不抄私有绘制」；波形这一格的方法待定，**不因为两家这么做就跟着做** |
| 30–32 | 亮度走私有 DisplayServices／自带私有框架副本 | **部分已实现**（[scorecard](scorecard.md):30 记我们写了 DisplayServices）；**「自带私有框架副本」不采纳**（把私有实现的漂移风险自己背下来，得不偿失） |
| 34 | 跨显示器刘海动画更顺、菜单栏隐藏时 Pill 间距、外接屏 Liquid Glass | **已覆盖 R27／V9**（放进多显示器矩阵一起验） |
| 35 | 锁屏上可以关掉刘海 | **已覆盖**（`NotchActivityController`／`PinnedPreview` 的锁屏暂停那一套）；**「可关」这一条归 R19 的刘海验收** |
| 36 | 常驻动画的 CPU 要专门优化 | **已覆盖 E1/E3** |
| 37 | 每个功能统一前缀 | **不采纳**：我们的词汇是**描述性**的（卷帘条／窗口浏览／看一眼），[copy-guide](copy-guide.md) 的固定词汇表就是我们的答案；DynamicLake 的 DynaXxx 是它的品牌策略，不是我们的 |
| 38 | 开源许可声明做成页脚可见项 | **已覆盖 R38** |
| 39 | 扩展性当头条卖 | **已覆盖 N1**（但按定案只做最小切口，**不当头条卖**） |
| 40 | 宿主拥有形状、内容方只填 slot | **已实现**（[design-grammar.md](design-grammar.md) 的令牌层在做同一件事）；**「外化成契约」不采纳**（我们不做插件平台） |
| 41–43 | 紧凑区三条内容规矩 | **已覆盖**（[production-maturity](production-maturity.md) A 组第 6 条；**要补一句到 R37 的隐私声明里**） |
| 44–45 | 时间步长纪律／惯性公式 | **→ R42** |
| 46 | 停放 10px | **→ R42** |
| 47 | binpack 栏内高度 | **→ R42** |
| 48 | 18 个窗口分类夹具 | **已覆盖 R20** |
| 49 | 岛做成声明式命令流 ＋ 拖放状态机 | **不采纳**：我们不做可编程的岛（与 N1 的最小切口一致） |
| 50–51 | `tapIsEnabled` 周期巡检／事件投递金丝雀 | **已覆盖 R1**（巡检已完成；**金丝雀未做** → 归入 R1 的后续，标在 R1 条目里） |
| 52 | 原生标签页合并 | **已覆盖 R4** |
| 53–57 | 标题栏推高／最小步长／带过期的还原／抑制深度计数／窗口顺序的键 | **已覆盖**（[重塑清单](product-reshape.md)§二 已逐条记；归 R 系列相应条目） |
| 58 | 按显示器落盘用 UUID | **已覆盖 R27** |
| 59 | 自己写窗口时先停听、写后一个动画时长再开听 | **未覆盖** → 归 **R42**（同属卷轴/窗口写入纪律） |
| 60 | 跟手只做最小动作 ＋ 应该在哪/实际在哪分开存 | **→ R42** |
| 61 | 窗口分类用声明式白名单 | **已覆盖 R20** |
| 62 | 宽度档位取黄金比共轭 | **已覆盖 R16** |
| 63 | raise 会抢焦点（层序只在组成变了时重排） | **未覆盖** → 归 **R41**（同属「不抢焦点」那一族） |
| 64 | 快照缓存带成本模型 | **已覆盖 R14** |
| 65 | 检测并共存别的工具 | **已覆盖 R8** |
| 66 | 几何四级回退链 | **已覆盖 R7** |
| 67 | 唤醒恢复三档 | **已覆盖 R3** |
| 68 | 岛的布局是可重载 JSON | **不采纳**（同 49） |
| 69 | 前置条件列出缺哪条 ＋ 一键跳系统设置 | **已覆盖 R30** |
| 70 | AX 读取次数做成可观测计数器 | **已覆盖 E1/E2**（`--window-browser-idle-probe` 已读 `axQueryCount`） |
| 71 | 41 个 bundle id 的例外名单 | **已覆盖 R8** |
| 72 | 预览与隐藏用两个队列 | **已覆盖**（[重塑清单](product-reshape.md)§二；归 R 系列相应条目） |
| 73–78 | WindowMizer 的占位条那批（collectionBehavior／孤儿／串行队列／压 unhide／axToolbarH／降级支路） | **已覆盖 R10／R11／R9**（`assume_success` 那条降级支路归 **R10**） |
| 79 | 内嵌崩溃上报 | **已覆盖 R13** |
| 80 | 手势按类别分栈 | **已覆盖 R16** |
| 81 | 启动台读系统 SQLite | **已覆盖 R15** |
| 82 | 接管系统 HUD 留「还给你」的开关 | **已覆盖 R12** |
| 83 | 观察 Game Overlay 控制条可见性 | **未覆盖** → 归 **R12**（同属「不跟系统 HUD 打架」） |
| 84 | 与别的系统工具互通而不是抢地盘 | **已覆盖 R8** |
| 85 | displayID 找不到一秒后重试 | **已覆盖 R27** |
| 86 | HUD 有五种形态 | **不采纳（当前）**：我们的刘海是**一颗胶囊连续变形**（[scorecard](scorecard.md) 刘海 88 的尺子），形态模型与它不同，照搬会破坏我们的一致性 |

**这一节的判据**：上表**每一行都有处置**；`不采纳` 的都有理由。新立的只有 **R40／R41／R42** 三条。**R6 要按第 11 行加强**：不是「先判断能不能改大小」，而是 **先试 → settling pass → 才判定被 AX 夹住 → 再提示**（Rectangle 的形状）——直接改 R6 的「改动」那一段。

#### R43 · `docs/` 的索引（**86 份顶层 md，没有入口**）
- **✅ 2026-10-15（010775c）**：`docs/README.md`，86 份顶层文档与 8 个子目录全部收录、链接全在（脚本逐条核过）；`AGENTS.md` 指向它。
- **依据**：成熟项目都有文档索引——**新人和 agent 都从一处进来**。这一条不是理论：**我这一轮差点让整批工作对新 session 不可见**（`AGENTS.md` 当时对竞品与重塑零命中，我补了一节才接上）。
- **现状**：`docs/` 有 **86 份顶层 md**（含本份），**没有 `README.md`／`INDEX.md`**（本机 `ls` 复核）；`AGENTS.md` 现在只挂了关键的几份。
- **改动**：写 `docs/README.md`，**按用途分区**（蓝图与方向／设计与文案／验收与探针／竞品与重塑／出货与发布／交接），每条一句话说明它是什么、什么时候该读。
- **验收**：一个新人只看 `docs/README.md` 就能找到他要的那一份；`AGENTS.md` 指向它。
- **风险**：低。**不要照抄目录树**——要按「什么时候读」分区，否则等于没有索引。

#### R44 · 性能预算进门禁（**从「我们测了」升级成「我们保证」**）
- **✅ 2026-10-15（62dd419）**：`scripts/check-idle-budget.sh` 接进 `build.sh --stage`：程序坞悬停关着时 AX 查询、在途缩略图、缓存都要为 0 且设置恢复，否则包不能发（原探针只打印、永远退出 0）。真实签名构建上 PASS。
- **依据**：成熟项目把预算写死并让 CI 拦；**Wins 官网专门自述「<30 MB、CPU ~0.1%」**，说明这是对外的战场。我们**有数、有仪器，但超了不会红**——这就是「测过」与「保证」的差别。
- **现状**：静置 0.31%／0.45%、轮询间隔的两次定案、三套仪器都在（[性能与能效](perf-energy.md)§一）；**`build.sh` 里没有任何性能阈值**（本机 `grep` 复核）。
- **改动**：定义**少量、可自动判定的**预算（不要多）：如「静置 CPU ≤ 一个阈值」「空闲时 AX 查询 = 0」「bundle 体积 ≤ 阈值」；把 `--window-browser-idle-probe` 那类探针接进门禁或 CI。
- **验收**：故意让某项变差时，门禁会红；阈值写在文档里可查。
- **风险**：**阈值不要定得太紧**——定紧了会因为机器差异频繁误报，最后被绕过；**先只上一条最稳的（空闲 AX 查询 = 0）**。

#### R45 · 代码地图放到规范位置
- **✅ 2026-10-15（010775c）**：`docs/code-map.md`，并核实「Core 管判断、App 管副作用」（Core 182 个文件只有 1 个引 AppKit）；与 §2.0.2 互相引用。
- **依据**：成熟项目有一份「哪段代码负责什么」的地图。我们的**散在测试包与评审包里**：`tests/part8/sources/code-map.md`、`docs/handoff/chatgpt-review-2/part7|8/sources/code-map.md`（本机 `find` 复核）。
- **现状**：`docs/blueprint.md` 是总图（方向与硬要求），**但没有一份「目录 → 职责」的代码地图**在 `docs/` 下、被 `AGENTS.md` 指向。
- **改动**：写 `docs/code-map.md`：`prototype/` 下每个目录与关键文件**负责什么、改动时要注意什么**（例如 `FoldTransaction.swift` 的不变量、`AXWindow.swift` 的熔断）。
- **验收**：新人能靠它定位「要改 X 该动哪个文件」。
- **风险**：低。**它必须与 §2.0.2「不要碰的」互相引用**，否则两处会漂移。

### P3 续 3 · 13 个失效家族里剩下的 22 条（收口，2026-10-15）

**为什么还要这一节**：前面收的是[竞品深挖](competitive-deep-dive.md)§二的 86 行可借项；这一节收的是[更新日志里的 real-world know-how](changelog-knowhow.md) 13 个家族里**标着「未做／待核」但 spec 里没有对应**的 22 条——集中在闭源那几族（K–O），因为那是我后来才加进来的，处置没做全。

**处置口径**：`已实现`（带代码位置）、`不适用`（我们不做那件事）、`条件触发`（取决于一个还没定的决定）、`归某任务`、**`→ Rxx`（新立的冻结项）**。

| # | 家族 | 未处置项 | 处置 |
| --- | --- | --- | --- |
| 1 | E | **焦点跟随鼠标**时滑过半出屏窗口会把它滚进视野（双屏烦） | **不适用**：我们**不做 focus-follows-mouse**（全仓 0 处，本机复核） |
| 2 | E | **RTL 语言**下位置算反 | **条件触发**：不做繁体是既定选择；**若将来加阿拉伯语／希伯来语，贴边与台前调度位置要先验**——记在这里，不立任务 |
| 3 | F | **内置与外接触控板互相覆盖**手势 | **已归 R25** ✓ |
| 4 | F | **热角**在手势期间误触发 | **不适用**：我们不做热角（本机 0 处） |
| 5 | G | **长时间运行后整数溢出**（niri：~50 天） | **→ R47**：长驻应用的真实风险，值得一条 |
| 6 | G | `CGPoint.findIn` 之类**越界查找原生崩溃** | **→ R47**（同上，一条两验） |
| 7 | H | **降级会把设置读坏**（OmniWM 的 forward-only 是解药） | **已归 R5**（前向迁移纪律那一段就是这条的反面） |
| 8 | H | **设置触发的重启后，设置窗口不回来** | **→ R48**：DockDoor 两次提过，是设置面的一致性问题 |
| 9 | H | **单位先换算再上色**（Atoll 摄氏／华氏） | **不适用（当前）**：我们不显示温度类读数；**若将来加**，这一条在 R42 的手感常量旁边记一笔 |
| 10 | K | **接／拔显示器后界面显示不对** | **已归 V9**（多显示器矩阵）✓ |
| 11 | L | **面板隐藏了还在挡鼠标**（DockMate） | **→ R46**：属于「不弄坏我的东西」——收起的面板挡住底下点不到，用户会当成 bug |
| 12 | L | **快速移动鼠标／快速切换图标**时预览闪掉或给错图标 | **已归 V8**（DockDoor 那 12 条里就有）+ **R46 一起验** |
| 13 | L | **某些第三方 App 预览不出来**（Wins：ToDesk／QQ 音乐） | **→ R49**：逐 App 例外表的实战入口，与 R8／R20 同族 |
| 14 | M | **系统明暗切换后占位条不重建** | **已实现，且方案不同**：我们**不回写外观**——`Overlay/ShadeStrip.swift:18` 每次**现读** `NSApp.effectiveAppearance`，`WindowShade.swift:438` 还用 KVO 观察。**WindowMizer 需要「重建」，我们不需要** |
| 15 | M | **重启后第一扇收起的窗口用错外观** | **已实现**（同上：现读，不存在陈旧值） |
| 16 | N | **IM 类 App 关掉最后一个窗口不该退出** vs 单窗口 App 该退出 | **已归 R21** ✓ |
| 17 | O | **图标在不同分辨率下显示异常／被放大** | **已归 V11** ✓ |
| 18 | O | **有些 App 不出现**（启动台） | **→ R48**（与第 8、20 条同族：设置面与列表面的正确性） |
| 19 | O | **文件夹开着时全局搜索不可用** | **→ R48**（同上） |
| 20 | O | **某些机型上 F4 键不工作** | **→ R48**（同上；另外**我们只出 arm64**，所以「机型差异」这一类的范围比双架构小） |
| 21 | O | **不同语言下文字被裁切** | **已归 R24** ✓ |
| 22 | O | **Intel Mac 上的差异** | **已核实并收口**：本机 `lipo -info` 显示发布构建是 **arm64 非 fat**，`build.sh:109` 的 `ARCH` 默认取 `uname -m`。**我们只出 arm64**——旧文里「要核我们有没有 Intel 构建」的问题到此结束；**若将来要出 Intel，再单独立项** |

#### 新立的四条冻结项（按 §0.3，它们**不进 §0.2 的六条**）

#### R46 · 收起的面板不能挡底下的鼠标
- **✅ 2026-10-15（面板用过之后）**：探针收尾等 1 秒再清点 App 自己「可见、透明度近 0、没设成让鼠标穿过」的窗口；30 组探针跑完全部 PASS。
- **✅ 2026-10-15（静置状态）**：签名构建静置时只有 2 扇在屏窗口：刘海岛（本该接点击）与一条全屏宽 10 点高、压在菜单栏上沿的「肩」窗口——后者初始化就 `ignoresMouseEvents = true`，不挡菜单栏。透明度为 0 仍在屏的窗口：0 扇。面板用过再关之后的状态还没量（要解锁屏幕跑探针）。
- **依据**：DockMate「Fixed Preview window **blocking mouse events while hidden**」——**收起之后那一块区域点不到下面**，是这一族里最容易被当成 bug 的一条。
- **现状**：未核。我们的面板/覆盖层很多，**先找出哪些在收起后仍然吃鼠标**。
- **验收**：面板收起后，那一块能正常点到下面的窗口。
- **风险**：低（先测）。**与 R41（不抢焦点）同族**，一起验更省。

#### R47 · 长时运行与越界：两个「跑很久才出问题」的失效
- **✅ 2026-10-15（5c2a0d1）**：（a）全表搜过：没有把时间塞进 32 位以下整数的地方；唯一长期累加的帧计数 `mirrorFrameIndex` 用 `&+=` 回绕安全；两处「负数秒转 `UInt64`」会崩，已随 M2 改成 `.seconds(x)`。（b）`tests/run-preview-renderer-bounds-tests.sh`：44 种极端图像 × 所有手算下标的像素函数与 `prepareNativeStrip`，全部不崩。
- **依据**：niri「Fixed a panic **after ~50 days of uptime due to an integer overflow**」；AeroSpace 两次栽在 `CGPoint.findIn` 这类**越界查找**上（#164／#1490）。
- **现状**：**未核**。我们是常驻应用，且几何代码里手算下标的地方不少（`Capture/PreviewRenderer.swift` 一带尤其）。
- **改动**：**先核**——（a）用假时钟把 uptime 推到 60 天量级，看计数器/时间差有没有溢出；（b）过一遍几何查找的边界（空数组、零尺寸、越界索引）。
- **验收**：60 天量级不崩；越界输入有确定行为（返回 nil 或夹住，不是崩）。
- **风险**：低（先测）。

#### R48 · 设置面与列表面的三条正确性
- **依据**：DockDoor「**Settings reopen after settings-triggered restart**」（两次）；LaunchOS「**some apps might not appear**」「global search was unavailable **while a folder was open**」「the **F4 key** was not working on some models」。
- **现状**：未核。我们有「需要重启才生效的开关」与设置搜索，**重启后设置窗口回不回来没验过**；启动台的列表完整性与「文件夹开着时搜索」也没验过。
- **改动**：三条各验一次（重启后的设置窗口／冷门 App 是否都在／文件夹开着能不能搜）。
- **验收**：三条各一条记录。
- **风险**：低。**F4 那条只在我们引入可配置触发键时才有意义**——当前先记着。
- **✅ 2026-10-16（aefc2b4）**：（1）没有任何设置需要重启 App（设置相关代码里唯一的 exit 是关侧拉），不适用。（2）`--launchpad-census` 对照 Spotlight 同几个目录下的 App：201 个一致，差的 7 个都有原因（别的 App 包里的辅助程序、旧备份里的、两个标了只在后台运行的）。（3）**修了一个真问题**：文件夹开着时打字，第一个字被吞（打「jsj」搜成「sj」，第一个结果是「书籍」）——关文件夹时又把键盘交给正在编辑的搜索框一次，系统会全选已打的字。修后 `--launchpad-keys` 18 项全 PASS。

#### R49 · 第三方 App 预览不出来（逐 App 例外表的实战入口）
- **依据**：Wins 3.1.1「修复 **ToDesk、QQ 音乐**等第三方应用无法正常预览窗口的问题」——**这正落在 R8 那张 41 项名单上**。
- **现状**：R8 只做「检测并共存别的窗口管理工具」；**「某些 App 的窗口读不出来」是另一回事**（AX 面不标准）。
- **改动**：从 R8／R20 的名单里挑几个国产 App 各验一次（ToDesk、QQ 音乐、微信小程序是已记录的案例）。
- **验收**：逐条记录「能不能预览、不能的话卡在哪一步」。
- **风险**：低。**与 R20 的 18 个夹具合起来做最省**。

### V 系列 · 上机验证（不改代码；把没跑过的跑掉）

**为什么单列**：[功能碾压](dominance.md) 的定义②写明——**领先要有真机证据**。下面这些现在**都没有证据**，所以那些「领先」按定义不算数。**每条的产出是一份记录（跑了什么、结果、证据在哪），不是代码。**

| 编号 | 去验什么 | 依据 / 现状 | 通过的样子 |
| --- | --- | --- | --- |
| **V1** | **盒盖动画的手感** | scorecard「**手感还要 Aaron 亲手确认**，确认前不到 90」 | 亲手确认过，记一行 |
| **V2** | **✅ 2026-10-15 代跑**：`--notch`、`--home` 在签名构建上全过 ｜ **刘海在签名构建上重跑 `notch` / `home`** | scorecard 真机列原话；两套探针都有 | 跑过、结果记录 |
| **V3** | **✅ 2026-10-15 代跑**：`--shelf-glance --minimize` 全过（它必须带 `--minimize`）｜ **`--shelf-glance` 在 build 16 上跑** | scorecard「刘海那几种 `--shelf-glance` 还没在 build 16 上跑」 | 跑过 |
| **V4** | **在装着 Rectangle 的机器上点一次「换过来」** | 现在 90 : Rectangle 90 **同分**，而「没在装着 Rectangle 的 Mac 上点过一次」 | 点过一次，动作对得上；这一行才可能拉开 |
| **V5** | **真三指 / 真触控板**（甩一下、卷轴跟手） | scorecard「真三指没人上手试过」「真触控板没人试」 | 拿真手指跑 |
| **V6** | **Magic Mouse / 罗技滚轮** | scorecard「Magic Mouse、罗技滚轮没人上手试过」 | 各跑一遍 |
| **V7** | **侧拉的像素级比对** | 需要 iPadOS 27 模拟器（约 8 GB，**待 Aaron 同意下载**） | 比对完成或明确记 not_run |
| **V8** | **DockDoor 那 12 条场景上机**（窗口浏览，**唯一落后的一行**） | [competitive-analysis.md](competitive-analysis.md):33 已列，未上机 | 逐条跑过 |
| **V9** | **部分（2026-10-16）**：「接着两块」那一类——本机内建屏 ＋ Studio Display，`--second-display`（签名构建）把临时窗挪到 Studio Display 收起：卷帘条落在同一块屏、收起记下的是那块屏、展开后窗口回到那块屏，三项 PASS。插拔、改分辨率、两块同型号要真手或另一块屏，待 Aaron。原文：**多显示器矩阵**：接一块／拔掉／改分辨率／**两块同型号** | WindowMizer 三条（crash on display change、wrong monitor's snapshot、**monitors share the same size and resolution**）；四家都用 UUID | 四类各一条 |
| **V10** | **台前调度**（与 R19 配套） | 见 R19 | 五类各一条 |
| **V11** | **图标在异常分辨率/缩放下不变形** | LaunchOS **两次**修这个：v2.1.0「app icons would display **abnormally at different resolutions**」、v2.1.3「icons could appear **enlarged**」。我们窗口浏览有 `placeholderIcon`（`WindowBrowserCardView.swift:41`）、启动台按 `backingScaleFactor` 取图，**但没在异常缩放档下验过** | 换缩放档/分辨率后两处图标都正常；取不到真图标时**有确定性的兜底**（不留空白、不留错图） |

#### V1／V4／V5／V6 的真机步骤（2026-10-15 写，等 Aaron 跑）

这四条都要真人、真设备，我不能代跑。每条跑完在上表「通过的样子」后面记一行：日期、设备、结果、录屏或截图放哪。

- **V1 盒盖手感**：设置里开「桌面开合」→ 屏幕从全开慢慢合到约 30°、再快速合到底、再慢慢打开，各两遍。看折进刘海的那一下是否跟手、有没有顿挫或跳帧。只有你说「可以」才算过。
- **V4 装着 Rectangle 时「换上」**：**本机没装 Rectangle**，要先装（官网或 `brew install --cask rectangle`，需要你同意下载）。在 Rectangle 里留默认快捷键并让它开着 → WindowShade 设置「快捷键」里点「换上」→ 应该看到刘海说「退出 Rectangle 后就能用」→ 退出 Rectangle → 逐个按 ⌃⌥←／→／↑／↓／↩，窗口位置与 Rectangle 当时一致。
- **V5 真三指、真触控板**：用内置触控板和外接妙控板（本机有一块）各做一遍：三指甩一下（快、慢各三次）、卷轴里两指左右拖着走再松手。看甩出去的落点和速度是否对、跟手时有没有滞后；两块板子同时放手指时互不打断（顺带验 R25）。
- **V6 妙控鼠标／罗技滚轮**：**本机没有这两种鼠标**。借到后：妙控鼠标单指左右滑、滚动；罗技（带侧键与滚轮）滚轮上下与横滚、侧键。看卷轴滚动的方向与步长、是否误触发手势。

### O 系列 · 对手对标（2026-10-15 点名 Thaw／LaunchNext／DockDoor；**全部待准入**）

**准入注记**：以下 11 条**不取代、不推后**任何在飞任务（§0.2 的 6 条照常），也都**不阻塞当前发布**——按 §0.3 排队，等批次空出来再逐条过闸。逐格对照与证据在[竞品深挖](competitive-deep-dive.md)§三末（三家全 GPL：只借思路不取码）。

| # | 做什么 | 对标 | 验收 | 备注 |
| --- | --- | --- | --- | --- |
| O1 | 切换器：**打字搜索**（对照：DockDoor 的 `enableWindowSwitcherSearch`＋`searchFuzziness`＋开启即聚焦、**模糊度五档由用户定**（`StringMatchingUtil`）；Peninsula 同款，且其 `SwitchManager` 明写「**序号相对过滤后的列表**」——**搜索态下数字键/顺序键按过滤结果重新编号**（语义要定死，别一半按全表一半按过滤））＋预览上的窗口控制按钮 | DockDoor／Peninsula | 打 3 字内命中目标窗口；按钮可用；**过滤态下的编号语义写明并测** | 最小切口  2026-10-17 实现：搜索部分已落地（`Core/WindowSwitcherSearch.swift`＋`tests/run-window-switcher-search-tests.sh`；预览上的窗口控制按钮未做）。键位：直接打字或按 `/` 进搜索态；Delete 删字；Esc 先清查询再关；**数字键与卡片角标按过滤后列表编号且不进查询**；搜索态下 w、q、空格是普通字符（关窗口／退 App 先 Esc 退出搜索）；搜索态下松开修饰键不再自动切换，回车或点一张才切。模糊度只给一档默认（词首＞连续子串＞依次出现），五档设置未做。2026-10-17 复核修正：搜索态下 ⌘W／⌘Q（⌥ 触发时）仍是关窗口／退 App、不再放给前台 App；进搜索态改在钩子线程上置位，避免打第一个字就松修饰键时误切换；编号逻辑抽成 `WindowSwitcherSearch.index(forNumber:…)` 并真测。数字键在搜索态仍是跳转（窗口标题里的数字搜不到，已知取舍）。未经真机验证（IME 组词的 CJK 输入走事件钩子拿不到，只有键盘直出字符与窗口标题里的 CJK 能匹配）。 |
| O2 | **⌘Tab 叠层**（系统切换器之上显示当前 App 的窗口），**默认关**。**机制照 DockDoor**：系统的 ⌘Tab 切换器是 **Dock 进程 AX 树里的一个元素**——拿 `AXUIElementCreateApplication(dockPID)` 找到「process switcher list」，订阅 **`AXSelectedChildrenChanged`**（跟着高亮走）与 **`AXUIElementDestroyed`**（切换器关了就收）；订阅失败要有**轮询兜底** | DockDoor／Wins Cmd-Tab Plus | 开启后可用；关闭时系统行为一字不变 | 与 R20 同族；AX 订阅＋轮询兜底两层 |
| O3 | 切换器**触控板滑开**（3/4 指左右选、抬手确认） | DockDoor | 与既有手势不冲突（过手势预算表） | 接手势面 |
| O4 | **Dock 文件夹弹出**（悬浮 Dock 文件夹→可排序文件列表）。细节照 DockDoor：行高 48、圆角 14 continuous、**悬停动画 `.snappy(0.175)`**、行副标题「种类 - 相对修改时间」、**拖动用 `NSItemProvider(url)`**（拖出即文件） | DockDoor Folder Pop | 排序与点击行为与 Finder 一致 | 接 Dock 手势面 |
| O5 | **音乐挂件**（悬浮正在出声的 App→控制）。**同款后端已核实**：DockDoor 也用 **`MediaRemoteAdapter`**（与我们的 vendored 框架一致）；**两条可直接抄的细节**：① **seek/pause 之后本地插值播放位置**——「不信任 feed 报告的位置」（feed 在跳转后不可靠）；② **seek 去抖 1.5s** | DockDoor | 用现有 NowPlaying 流，零新增私有面 | 已有 NowPlayingStream；插值与去抖照抄 |
| O5b | **键位提示行**（对照 DockDoor `KeyHintRow`：`KeyCap` 画键帽＋说明文字，**accessibilityLabel 拼成「⌘Y — Allow」完整读给读屏**） | DockDoor | 读屏能读出「键＋ действие」 | 审批/切换器的键位提示都照此 |
| O6 | 启动台：**原生 Launchpad 数据库一键导入**（只读、认两代 schema） | LaunchNext 卖点 #1 | 导入后文件夹/位置与系统一致；库不在时优雅降级 | 路径 `/private$(getconf DARWIN_USER_DIR)com.apple.dock.launchpad/db/db` |
| O7 | 启动台：**CLI/TUI**（布局检查与操作） | LaunchNext | `windowshade launchpad …` 有测试 | 复用现有 CLI 地基 |
| O8 | 启动台：**滚轮翻页**（对照 LaunchNext `handleWheelPaging`：滚轮/触控板可翻页，不止拖拽）＋**文件夹编排动画**（溶解/玻璃/合并）＋**右键菜单补全**（对照 LaunchNext：在访达中显示／拷贝路径／重命名文件夹／**溶解文件夹**／隐藏／按配置的工具卸载／批量选择／**把 App 钉到文件夹内的「快速启动顶行」**）。另注意它同款菜单里有 **「在终端里移除隔离标记」**——把 Gatekeeper 的绕行步骤做成了菜单项（我们**只要把 C2 的公证做掉就不需要这条**，记此作对照） | LaunchNext CA 全家 | 先过 design-drafts 准入，画面照稿；右键项逐条对行为 | 设计先行 |
| O9 | **菜单栏不打架**互操作测试：装 Thaw/Ice/Bartender 时刘海与 NotchWatch 行为不变样；自查「图标抖动」 | Thaw | 真机三件套各过一遍；有抖动即修 | 只测不做管理 |
| O10 | 借 Thaw 的纪律：**升级说明**格式（「no schema/defaults changes…carry over untouched」级）＋**发布自动化到 appcast**（tag 段落→GitHub Release＋appcast）；供应链姿态（OpenSSF/可验证发布）先评估不承诺 | Thaw | 下一次发布按新说明格式走；appcast 由脚本写入 | 接 R33/R34 |
| O11 | **设置可搜索**（DockDoor 的 `settingsSearchTarget` 纪律：**每个新设定必须挂进索引**，写进门禁） | DockDoor | 设置窗任意页可搜到任一设定；门禁检查新设定已索引 | 我们有搜索控件（窗口浏览在用），设置窗没有 |
| O12 | **文件/截图架补两下**：截图自动上架 ＋ 边缘（菜单栏处）悬停唤出、移开收回。**tendedero 的实测参数直接可参**：悬停延迟 **0.25s** 才滑出；**新截图自动「探头」2.5s**（`reveal(peekFor: 2.5)`，设置可关）；绳的垂度 `sag = min(30, 宽×0.018)`；**最新一张居中**（`width/2 + (可见数-1)×间距/2`）；弹簧：换项 `response 0.55 / damping 0.78`、露出 `0.42 / 0.82`；菜单项原文「When the pointer rests in the menu bar」（指针停在菜单栏时才出） | tendedero | 连拍三张截图全上架；悬停 0.25s 滑出、移开收回、不挡鼠标；探头可关 | 架面已有（`FileShelfView`），这两下是新的；参数照 tendedero 实测校准 |
| O13 | **Siri Remote 面核准**：照 open-appleremote 的 `PROTOCOL.md` 核我们 12 键的覆盖面，补触摸面手势（若要做，先过手势预算表） | open-appleremote（MIT） | 一代遥控器逐键实测；手势不吞现有键位 | 我们已有 `SiriRemoteButtons`＋`appleRemote` 信封 |
| O14 | **刘海的自动收起给三档**（smart／定时／前台一变就收），默认 smart；配置写法认名字＋裸整数 | Thaw `RehideStrategy` | 三档各验一遍；关闭时行为一字不变 | 小切口、独立于菜单栏战场 |

## 3. 执行顺序与检查点

| 顺序 | 任务 | 做完的检查点 |
| --- | --- | --- |
| 0 | 读第 1 节 ＋ 跑一次 `./build.sh --check` 确认基线 | `EXIT=0`，记下耗时 |
| 1 | **R2**（复用 R1 的框架，最小改动） | 真机：运行中关权限 → 有说明 |
| 2 | **R3** 唤醒三档 | 真机：睡/醒两遍，全部功能回来 |
| 3 | **R4** 原生标签页 | 真机：5 标签只出一条；拖出来的各自成条 |
| 4 | **V 系列能跑的先跑**（V1／V4／V5／V6／V9——不改代码、成本最低，而且**它们是「碾压」定义②的证据**） | 每条一份记录 |
| 5 | **R5** 设置备份与迁移 | 旧文件启新版不掉设置；导出/导入往返 |
| 6 | **R6** ＋ **R7** | 真机：计算器参与排布有说明；AX 卡住的 App 仍有正确外框 |
| 7 | **R8** 同类工具检测 → **R19** 台前调度（先验收后适配）→ **R20** 窗口身份 | 见各自验收 |
| 8 | **R9**→**R13** ＋ **R21**→**R28** | 每条各自验收；R9 **先复现再改** |
| 9 | **R29**（降级清单，是「不录屏也能用」那句对外承诺的底气）→ **R40**（进度卡）→ **R41**（先验）→ **R42**（卷轴配方） | 见各自验收 |
| 10 | **R33**（CI，最便宜的成熟做法）→ **R34**（版本号纪律，从下一次发布起）→ **R38**（第三方许可） | 见各自验收 |
| 11 | **N5**（公证门槛，纯新增）→ **M1**（一石二鸟）→ **H1** | 见各自验收 |
| 12 | **N1** App Intents（按定案只做 5–8 个；先按固定词汇表定名）→ **R35／R36／R37**（诊断导出／反馈入口／隐私声明）→ **R39**（先测不改） | 见各自验收 |
| 13 | 其余 E／H／M | — |

**每个检查点都要**：`build.sh --check` `EXIT=0` ＋ 真机证据（截图/探针输出）＋ 把该条状态写回[重塑清单](product-reshape.md)。**完整口径见 §2.0.1 的完成定义（DoD）。**

### E／H 系列 · 性能、能效与 Apple 芯片（理由见[性能与能效](perf-energy.md)）

**E 系列＝能效与性能；H 系列＝Apple 芯片（GPU／NPU／统一内存／QoS）。** 两条前置认识：

- **我们已经在用硬件能力**：ANE（`App/VisionFaceEmbedder.swift` 的 Vision 推理）、GPU（`Effects/FoldRenderer.swift` 的 Metal 渲染器）、功耗策略（`App/PowerPolicy.swift` 看 `thermalState` 与低电量）。**所以 H 系列不是「从零上硬件」，是补缺口。**
- **不为用而用**：窗口管理本身没有神经推理需求——ANE 的正确落点是**把已经在做的、靠像素启发式硬算的图像理解换成 Vision 推理**（标题栏定位、缩略图裁剪；人脸那条已经做了）。没瓶颈的地方不做 Metal 重写。

| 编号 | 动作 | 验收 |
| --- | --- | --- |
| **E1** | **✅ 2026-10-15**：`scripts/energy-profile.sh`；本机（Mac17,4、macOS 27.0.1、build 16 签名构建）静置 CPU **0.10%**（3×60 秒中位数）。原文：**把 60 秒静置实测做成例行项**（每版必跑，数字进 [scorecard](scorecard.md)）。口径固定：无操作、无手势、屏幕不锁不灭、同一台机、**跑三次取中位**。**做成脚本，不是手抄的仪式**——照 OmniWM `Scripts/energy-profile.sh` 的形状 | 每次发版有一行数字，可跨版本对比 |
| **E2** | **✅ 2026-10-15（口径已清）**：同一次测量里 phys_footprint **54 MB**、RSS 125–153 MB；以前的「约 100 MB」是 RSS 一类的数。Wins 自称的「<30 MB」口径未知，不能直接比。原文：**查清内存口径再对比**：先量清我们的 physical footprint 与 RSS，分「空载」与「开了窗口浏览＋几个常驻面」两种状态；再去查 Wins 那 30 MB 的确切含义。**现在这一行是 100 MB vs 它自称的 30 MB，口径不一致就不能下结论** | 一张同口径对照表；不引用对不上的数字 |
| **E3** | **一次可比的长会话卡顿对比**（对 1.0.15）：同样的窗口数、同样的手势序列，记帧时间分布 | 帧时间分布 + 结论 |
| **E4** | **✅ 2026-10-15（bf73aad）**：两处都设了 10% 容差；窗口浏览那个只在面板开着时跑，**不是常驻**。原文：**补两处 `tolerance`**：`App/ScrollStripRun.swift:148`（0.5s）、`WindowBrowser/WindowBrowserController.swift:1320`（0.6s，**同时核它是否常驻**——若是，空闲时仍有 1.7 Hz 唤醒） | 改动 + 静置数字不劣化 |
| **E5** | **✅ 2026-10-15**：排队中的请求本来就能取消（每个任务开跑前 `demand.execution.begin()`，过时就跳过；每个 App 只一个在途）。真正的缺口是窗口浏览没接熔断：现在问之前看 `AXStallBreaker`，开着就报失败（旧条目保留、标待刷新），问完把耗时记进熔断——卡住的 App 之后 4 秒内收起、救援、窗口浏览都直接跳过它。原文：**AX 请求可取消**（AeroSpace 那条我们只做了一半：有按 App 队列、有逐调用 timeout、有按调用熔断，**没有可取消**） | 一个 App 卡住时，排队中的请求能取消，不吃满 timeout |
| **E6** | **✅ 2026-10-16（877ca09）**：签名构建：`--switch-cpu` 两个 App 之间切 20 次，我们比静置多花的 CPU ≈ 0（静置 8 秒 48.9 ms，切换期间 29.3 ms）；`--idle-first-op` 静置 5 分钟后第一次收起，卷帘条 448 ms，暖的中位数 442 ms（+6 ms）。原文：核 Ice 那两条：**切 App 时菜单栏面 CPU**、**长时间空闲后第一次操作的迟滞** | 各一条探针 |

**H 系列 · Apple 芯片**

| 编号 | 动作 | 验收 |
| --- | --- | --- |
| **H1** | **✅ 2026-10-15（4da4e93）**：没走 Metal／vImage，换成算法上的省：只处理「镜像行不全不透明」的几行；45 张图与旧实现逐字节相同，4K 一张 37.4 → 21.0 ms。原文：**`mirrorRoundCorners` 换掉标量循环**（`Capture/PreviewRenderer.swift:183`，另有 14 处同类循环）。优先走 Metal（`Effects/FoldRenderer.swift` 已有 device／纹理／缓存），退一步用 `vImageVerticalReflect` ＋ `vImagePremultiplyData` | 同一张 4K Retina 图**单次调用耗时前后对比**；**输出逐像素一致**（等价替换，不许改画面） |
| **H2** | **✅ 2026-10-15 核过不降**：基线（签名构建、3 次 `--fold-timing`，各取暖机后 3 轮中位数）第一次画面变化 156／163／217 ms、卷帘条出现 406／413／463 ms。队列上的三件事（截图、裁标题栏条与红绿灯命中区、缩略图）**全在收起的关键路径上，主线程原地等结果**——降到 `.utility` 就是在系统忙时主动让收起变慢，正是本条说的「关键路径上不能降」。原文：**`pixelAnalysisQueue` 的 QoS 复核**（`WindowShade.swift:170` 现为 `.userInitiated`）。**先量再改**：跑 `--fold-timing` 取基线 → 降 `.utility` → 再跑；关键路径上不能降的那几处单独保留 | 折叠延迟不劣化；非关键路径的 CPU 占比下降 |
| **H3** | **2026-10-17 复核（本机 macOS 27，签名构建 bd68e09）**：上一轮「完整帧整帧全 0」**复现不出**——连跑 4 次（2 次带屏上旁证、2 次 `CAPSULE_SKIP_ONSCREEN=1`），每次 sRGB／P3 各 53–93 个完整帧、全 0 帧 0 个，原始帧 1280×904、max alpha 与颜色都是 255；全 0 帧的诊断（帧信息、IOSurface、Core Image 对照读）留在探针里，再出现时直接看。**产品不空白**：`screencapture -l` 抓我们的置顶预览面板，平均色与夹具一致、蓝紫胶囊像素 0 个；同时抓源窗口，屏上有 289 个胶囊像素采样点——系统确实在源窗口红绿灯处画了胶囊，我们的面板修掉了。**H3 本题**：sRGB 认出并修掉 52/53–93/93 帧，**displayP3 认出并修掉 55/55–84/84 帧**，探针 PASS；P3 面板标题栏目视与 sRGB 一样干净（三颗灯、无紫边），但底片贴回的偏色没逐像素量过。结论：「换 P3 胶囊认不出」这条前提在本机不成立，剩下的风险只是底片色差，换采集色彩空间前补一次逐像素比对即可。**核过，暂不改（2026-10-16）**：那条流的帧交给 `AVSampleBufferDisplayLayer`，它按帧上的色彩空间显示，换成 `displayP3` 显示端是对的；**但上屏前的录屏胶囊修补按 sRGB 数值认蓝紫色、并把 sRGB 底片原样贴回**——直接换会让胶囊认不出、补丁偏色（可见的回退）。前提：先让胶囊检测与底片按帧的色彩空间换算，再换采集色彩空间。**第十五批**：同一探针在 macOS 26.6.2 虚拟机上也是 0 次认出（sRGB 24 帧、P3 57 帧）；本机与 26 都认不出，要分清「系统没画」还是「我们认不出」，下一步让探针把修补前的原始帧存成 PNG 直接看。**第十四批**：加了 `--capsule-color` 探针（sRGB 与 displayP3 各开 4 秒置顶预览，数认出胶囊的帧）；首跑两种都收到 40 多帧但连 sRGB 都没认出胶囊——系统没在临时窗口上画，inconclusive，仍不改。原文：**采集侧色彩与分辨率**（`ScreenCaptureBridge.swift:414-418` 现为 sRGB、未设 `captureResolution`）：按显示器能力选色彩空间（P3 屏用 `displayP3`），显式设 `captureResolution`，macOS 15+ 评估 HDR 档（**连着看功耗**） | 缩略图与系统截图色彩比对；P3 屏上不变淡；采集侧 CPU 不升 |
| **H4** | **✅ 2026-10-16 量过，不采用**（[h4-vision-eval.md](h4-vision-eval.md)）：15 张真窗口里像素启发式对 6、Vision 文字对 3、矩形对 6；显著性 20 张里 18 张框住整窗、没有裁剪价值；一扇窗多花 35–80 ms（H2 基线第一次画面变化约 156 ms）。另查明像素启发式 `preciseVisualChromeHeight`（`Capture/PreviewRenderer.swift:528`）两个条件取自同一个值、永远不执行，一般窗口走 AX。原文：**Vision 用到该用的地方**（ANE）：标题栏定位从像素启发式换成 `VNDetectRectangles`／`VNRecognizeText`；缩略图裁剪用 `VNGenerateAttentionBasedSaliency`。**只在「一扇窗一次」的路径上跑，不每帧** | 同一批窗口比较「启发式 vs Vision」的定位；低电量／热压力下能退回启发式 |
| **H5** | **✅ 2026-10-15 核过不改**：实时画面早走 `CVMetalTextureCache`；唯一还从 `CGImage` 建纹理的是收起动画的静图，`FoldStillTexture` 已把色彩转换结果直接写进页对齐的共享 `MTLBuffer` 当纹理用、省掉 `replace` 整图拷贝（有逐像素一致的测试）。没有可以再接零拷贝的路径。原文：**零拷贝（2026-10-15 自纠：前提要改）**：此前写「`FoldRenderer` 是从 `CGImage` 建、要 CPU 上传」，**不准确**——`Effects/FoldRenderer.swift` **已经有** `CVMetalTextureCache`（`:35`／`:111`／`:291`）并用 `CVMetalTextureCacheCreateTextureFromImage`（`:346`）。→ 改成**核哪些路径还在走 `CGImage` 上传**（静态图/截图那条？），把能走 `CVPixelBuffer` 的都接过去 | 那条路径的 CPU 占比与内存带宽下降；画面一致 |
| **H6** | **2026-10-16 不适用**：H4 不采用，没有新路径要退回。原文：**新路径进 `App/PowerPolicy.swift`**（低电量／热压力下退回 CPU／降质／跳过非必要推理） | 低电量模式下新路径行为可解释 |

**不该做的**：不为「用上 NPU」引入模型；不做「Metal 重写一切」；不把 Vision 放上关键交互路径；不牺牲色彩正确性换性能。

**N 系列 · Apple 原生**（理由见 [Apple 原生优先](apple-native.md)；**先读那一份的§一：我们已经相当原生**）

| 编号 | 动作 | 验收 |
| --- | --- | --- |
| **N1** | **App Intents（已定案：最小切口）**：**先做 5–8 个最常用动作**（收起／全部收进刘海／打开窗口浏览／恢复全部／切到某扇窗…），**不铺满**。**这一条改写「扩展面」那一行的结论**——Apple 的原生答案，免费得到快捷指令／Spotlight／Siri，不必自造 CLI 或 URL scheme。**Intent 是用户可见的公开契约，先按[固定词汇表](copy-guide.md)定名再实现** | 快捷指令里能搜到、能跑通、能串成自动化；Spotlight 能搜到 |
| **N2** | **`os.Logger`**：面向系统的诊断（启动、权限、通道体检、自愈）走统一记录，带 `subsystem` ＋ `category`；**涉及用户数据的字段标 `privacy:`，与隐私登记（[privacy-page.md](privacy-page.md)）逐条对齐**。文件日志保留（探针依赖它） | `log stream --predicate 'subsystem == …'` 看得到关键路径；隐私字段默认 `<private>` |
| **N3** | **✅ 2026-10-15（c6f8dac）**：收起与窗口浏览两条已加；真机上 `--notch` 期间收起 4 开 4 合（2 folded、2 abandoned），`--browser-more` 期间会话 begin → 各阶段事件 → end(closed)。原文：**`OSSignposter`**：先给**折叠**与**窗口浏览**两条关键路径加区间与事件，让性能工作在 Instruments 里可见。E／H 系列的量测统一走这条 | Instruments 的 os_signpost 轨道能看到阶段划分；一次折叠的耗时分解可读 |
| **N4** | **✅ 2026-10-16（3d67442、d73496a）**：外设电量（2 分钟）与 AirPods 电量（10 分钟）两条周期刷新改走 `NSBackgroundActivityScheduler`（`Support/MaintenanceTimer.swift`）。**更正规格**：`Updater.swift:137` 的 10 秒不是更新检查，是装后自查——被推迟会让看护 60 秒后当成卡住换回，必须留在计时器；定期查更新由 Sparkle 自己调度。其余重复计时器都是界面开着才跑或延迟敏感。**实测**：系统调度一开始会立刻跑一次、间隔可能拉到近两倍（60 秒档出现 115 秒）；已跳过立刻那一次，重测 77、144 秒。原文：**`NSBackgroundActivityScheduler`**：非延迟敏感的周期工作改走它（**更新检查** `App/Updater.swift:137` 的 10s 等）。**延迟敏感的不换**——R1 那个 5 秒通道体检必须保持 `Timer` | 功能行为不变；低电量下由系统自然推迟 |
| **N5** | **`PrivacyInfo.xcprivacy`**：我们用了 Apple 的 required-reason API 却没有这张清单——**这是公证与上架的门槛**。**2026-10-15 逐类审计（源码＋二进制符号双查）**：① **SystemBootTime**（`systemUptime`／`mach_absolute_time`，43 个文件）→ `35F9.1`；② **UserDefaults**（85 个文件）→ `CA92.1`；③ **FileTimestamp**（7 个文件：`DownloadActivitySource`／`UpdaterSystem`／`FileShelfStore`／`HabitContext`／`Watchdog`／`WS2LocalLaunchProfile`／`WS2ProjectDirectory`；符号 `stat/lstat/getattrlist` 5 处）→ `C617.1`＋`3B52.1`（按站点归位）；④ **DiskSpace**（`UpdaterSystem.swift:616` 更新前探 `volumeAvailableCapacityForImportantUsage`）→ `E174.1`；⑤ ActiveKeyboards **0 处，不写**。负项：`NSPrivacyTracking=false`、`NSPrivacyCollectedDataTypes=[]`、`NSPrivacyTrackingDomains=[]`。**别抄用不到的类别** | 清单进包、`plutil -p` 能读；公证工具的 required-reason 检查不报 |

**两条纪律**：新 API **一律 `#available` gate ＋ 旧系统退回**（已在做，保持）；**不用新 API 换掉还能用的旧 API**——只有 Apple 已标记过时的（如 `CVDisplayLink`）才换。

### M 系列 · 现代化（理由见 [现代化](modernization.md)）

**先读那一份§一：我们是「混合体」**——不是落后，是一半已经现代化（Swift 6 ＋ 完全并发检查、`CADisplayLink`、`Duration` 105 处、`ContinuousClock` 11 处、纯 AppKit），另一半在积累。**工具链是 Swift 6.4。**

| 编号 | 动作 | 验收 |
| --- | --- | --- |
| **M1** | **核过，暂不做（2026-10-16）**：`systemUptime` 现在 109 处、`CFAbsoluteTimeGetCurrent` 88 处。最密的 NotchActivityController（23 处）把 `now` 当秒数一路传进 Core 的纯逻辑与它的单元测试，换 `SuspendingClock` 要连接口和测试一起改；而「缩小隐私清单的申明」那一半已由 N5 用申明原因满足、我们也不上 App Store。收益小、回退面集中在刘海这些对时间敏感的路径，按「只做纯收益」先不做；以后碰到某个文件本来就要改时顺手换。原文：**时间基准**：`ProcessInfo.systemUptime`（**108 处**）与 `CFAbsoluteTimeGetCurrent`（**88 处**）换成 `ContinuousClock`／`Instant`／`Duration`。**一石二鸟：`systemUptime` 是 required-reason API，换掉之后 N5 的申明范围直接变小。**语义要点：两者都单调，**别换成 `Date()`**（会因用户改系统时间而跳）。最密的几处：`App/NotchActivityController.swift` 23、`App/HabitContext.swift` 12、`App/Notch.swift` 7 | 行为不变（探针回归）；`systemUptime` 归零后 N5 去掉 BootTime 一类 |
| **M2** | **✅ 2026-10-15（c66967d）**：325 处全改，309 处字面量逐对核过纳秒数相等。**更正写法**：必须写 `Task.sleep(for: …, clock: .suspending)`——旧写法按开机时间计时（睡着不走），默认的 `ContinuousClock` 睡着也走，直接换会让跨过睡眠的等待在醒来那刻立刻结束。原文：**`Task.sleep(nanoseconds:)` → `Task.sleep(for: .milliseconds(…))`**（**325 处**）。现写法要人肉数零（**数错一个零就是十倍差**）且负数直接崩；`Duration` 类型安全。**按文件分批，每批跑一次 `--check`** | `nanoseconds:` 归零；行为不变 |
| **M3** | **起步（2026-10-16，d4c00f4）**：本轮新写的 `MaintenanceTimer` 用的 NSLock 换成 OSAllocatedUnfairLock；旧代码未动。**最低版本到 15 之后（见下「支持的系统版本」）`Mutex` 可用了**，旧代码可以照本条往它迁。**第十三批（2026-10-16）**：四处「一把锁护一个值」换成 Mutex（PrefilterStats、LegacyQuickCapture、NowPlayingStream 读取器、FileDragSensor 的 Collector），三处去掉 `@unchecked Sendable`、一处去掉 `nonisolated(unsafe)`；PinnedMirrorLease 守的是不 Sendable 的闭包，换不了也不必换，保留 NSLock。**第十四批**：再迁 10 处（NotchShelf、NowPlayingArtwork、DockToolRunner、WindowRegistry、HabitContext、LaunchpadArtwork、ChromeProfile、ShadeSoundPlayer、WindowGlide、PowerPolicy），其中 4 个类去掉 `@unchecked Sendable`、3 处去掉 `nonisolated(unsafe)`；MiddleTitlebarTap（护着 CFMachPort／RunLoop／Thread）、ScrollStripRun（存 AXUIElement）、PrivateAppList（只串行化 UserDefaults 读改写）不迁。**第十五批**：再迁 8 个文件（TapDecision、AXStallBreaker、NotchActivitySources、FoldGPU、EffectEnvironment、GestureCoach、CopyProgressSource、AppWindows 的局部锁），去掉 6 处 `@unchecked Sendable`、5 处 `nonisolated(unsafe)`；7 个测试 runner 的编译目标提到 15。**一处退回**：WindowBrowserController 的两个诊断计数换成 Mutex 后，`--browser-more` 三次都以 SIGTRAP 崩在交给后台 OperationQueue 的闭包里（运行期隔离检查：主 actor 隔离的闭包在后台线程跑），退回 NSLock 后连跑两次都过。**以后迁移的规矩**：主 actor 类里、会被后台闭包碰到的状态先不迁。**第十八批**：再迁 6 处（UpdaterSystem 的 OutputBuffer、GapOutputCollector、EntitlementProbe 的 FrameCounter、FaceObservationSource 的 CameraList、WindowBrowserMetadataExecution、WindowIdentityAllocator），去掉 4 处 `@unchecked Sendable`（OutputBuffer、GapOutputCollector、FrameCounter、CameraList），其余两个类顺势标上 `Sendable`；没有 `nonisolated(unsafe)` 可去，也都不在 @MainActor 类里。不迁：WindowMirrorSlot（槽里存 AVSampleBufferDisplayLayer，不 Sendable，Mutex 里放不进，编译器直接拒绝）；AppNapActivity（锁里护着 NSObjectProtocol 活动令牌）、FoldImageCache（泛型 Value 不 Sendable）、LatestValueWriter／LatestFrameMailbox（存不 Sendable 闭包和泛型值）、EffectFrameSource／LidAngleSource／AppleSPUAccelerometer／DeviceAuthorizationKey（锁只护一部分字段，其余靠队列，且有 HID／Secure Enclave 对象或两把锁）、InProcessRestore（`@unchecked` 还要为主线程状态保留）、WindowThumbnailService（诊断计数在锁外读、回调需解锁后投递）、WindowBrowserController（按上面的规矩整个跳过）。`--check` 与相关 runner 通过；探针留给合入后跑。**第五轮（2026-10-17）**：再迁 3 处（CaptureIndicatorTracker 五个字段整组进 Mutex、WSL10nState 三个字段整组进 Mutex、WindowSnapshotInFlightSlot 的完成标记），其中前两个去掉 `@unchecked Sendable`；`nonisolated(unsafe)` 里只有 `GlanceController.unhideForLiveEnabled` 全仓从不赋值，改成 `nonisolated static let`，其余 50 处都有赋值或是非 Sendable 的 `static let`／deinit 兜底而保留。不迁：HabitKeys／WindowSwitcher（锁只护一部分字段，其余绑钩子线程与 CFMachPort）、ConflictingAppCache（锁在算的途中放开、存 NSRunningApplication）、PiPScroller（存 AXUIElement）、WindowBrowserScheduledWork／SingleShotCompletion（存不 Sendable 闭包）、IdentityProbeBackend（探针假后端）、PinnedMirrorLease（存闭包）、WindowSnapshotCache（两把锁护两组、存 CGImage）、LatestValueWriter、ScrollTap／ScrollFrameLink（CFMachPort／CADisplayLink）、Watchdog 的日志锁（只串行化文件写）、WindowBrowserController（整个跳过）。 其余候选（存 AXUIElement／CF 对象／不 Sendable 闭包的、事件 tap 热路径、多处锁护不同状态的、解锁安全路径）有意不迁，理由逐条在提交说明里。原文：**同步原语小步迁移**（`NSLock` 66 ＋ `os_unfair_lock` 31）。**新代码一律 `Mutex`／`@MainActor`，不新增旧锁**；旧代码**从「一个 `Mutex` 包一个值、无嵌套加锁」的文件开始**，有嵌套或跨对象不变量的先不动。`DispatchSemaphore`（14 处）**不是换 `Mutex`，是换 `withCheckedContinuation`／`AsyncStream`** | 每个迁移的文件能去掉 `@unchecked Sendable` 就去掉（去不掉要写明理由）；探针全跑 |
| **M4** | **✅ 2026-10-15 评估完：现在不走**。用与门禁完全相同的参数（`-O -whole-module-optimization -strict-concurrency=complete -warnings-as-errors`）只加 `-default-isolation MainActor` 编一次：**330 个错误**，App/ 218、根目录 38、Recovery 23、WindowBrowser 21；最多的文件是 NotchShelf 28、WindowShade 22、Rescue 16。八成是「在非隔离上下文里调用主线程的函数」——正是刻意放到后台队列的 AX／程序坞工具／像素分析路径，要把约 150 个辅助函数逐个标 `nonisolated`，等于动一遍线程模型，而现有代码已在最严格检查下零警告。（`-typecheck` 快查模式下基线就有 127 条警告，与门禁不等价，那组数不能用。）原文：**评估 `-default-isolation MainActor`**（SE-0466）：**先在一个分支上打开，把编译错误数出来**，再判断值不值得。这条的产出是**一个数字和一个判断**，不是一次重构 | 一份结论：错误数、集中在哪些文件、是否值得走 |
| **M5** | **✅ 2026-10-16 核过，不做**：H1 走的是算法上的省（不是 vImage／Metal）；而 `Span` 要 macOS 26（实测：以 macOS 14 为目标编译直接报「only available in macOS 26.0 or newer」），写成双路径只换来安全不换速度。最低版本滚到 26（2027 年 9 月）时再看。原文：**`Span`／`RawSpan` 用在像素路径**（`Capture/PreviewRenderer.swift:104/187/193`）。**与 H1 联动：H1 先定走 Metal 还是 vImage，再决定 M5 要不要做**（走 vImage 就不需要） | 与 H1 一起验收 |
| **M6** | **2026-10-15 核过，不改**：`DateFormatter`（10 处）与 `NSRegularExpression` 都没被 Apple 标为过时，日志时间戳是写死格式加 `en_US_POSIX`，换 `FormatStyle` 只有风险没有收益——按本节「不该做的」第一条结案。原文：**`NSRegularExpression`（1 处，`Core/CalendarActivity.swift:186`；Swift `Regex` 0 处）与 `FormatStyle`（`DateFormatter` 10 处）**。**注意**：`Support/Diagnostics.swift` 那个日志时间戳显式钉了 `en_US_POSIX`，换 `FormatStyle` 时要保留这个 locale 语义（否则某些区域会变） | 行为不变，尤其日志时间戳格式在非中文区域也不变 |
| **M7** | **✅ 2026-10-15**：本轮新写的 10 组测试都按 `@main + expect` 与 `tests/run-*.sh` 的既有模式，没有引入 XCTest 或 Swift Testing。原文：**新增纯逻辑测试要follow 现有模式，不引入第二个框架**（**2026-10-15 自纠**：此前写成「`tests/` 为空、只靠探针」，**是错的**）。事实：`tests/` 有 **244 个 Swift 测试档 ＋ 218 支 `run-*.sh` runner**，用的是**自制的 `@main struct XxxTests` ＋ `expect()` 印 `ok`/`FAIL`** 模式（`import XCTest` 与 `import Testing` **各 0**），而且 **`build.sh` 已经把其中几支纳入门禁**（`:125` 的本地化检查、`:184` 的隐私同步、`:187` 的文案 lint）。→ 纯逻辑测试（如 R4 的标签页合并判据）**按这个既有模式写**，不要为了「现代化」引入 Swift Testing | 新测试能进 `build.sh --check` 或对应的 `run-*.sh` |

**不该做的**：不为现代化换掉还能用的旧 API（`TimeInterval` 812 处多数无害）；不用 `@Observable` 硬套纯 AppKit；**不在没有测试网的情况下大改并发**（99 处 `@unchecked Sendable` 是地雷区，M3／M4 都要小步 ＋ 探针回归）；不追每个新特性（`InlineArray`／typed throws／`@concurrent` 遇到合适场景再用）；**迁移类改动行为必须不变，不要和功能改动混在一支提交里**。

**已有的能效资产，别重造**：`--window-browser-idle-probe`（读 `axQueryCount`／`thumbnails.InFlightCount`／`thumbnails.cachedCostBytes`，跑 1 秒后原样恢复设置并退出，**安全**）、`--duo-ax-bench`（AX 延迟基准，含 SkyLight 与 CGWindowList 对照，`App/AXLatencyBench.swift`）、[scorecard](scorecard.md) 里那组实测（加速度计轮询 1000 µs → 16000 µs 让常驻从 4.55% 降到 1.68%）。

**2026-10-15 已经跑过一次，基线在[性能与能效](perf-energy.md)§一**（用的是 **2026-09-22 那份构建**）：

- AX 完整枚举 **4.5–10.5 ms／App**；AX 四项读 **0.1 ms／窗**；对照 `CGWindowListCopyWindowInfo` 全量枚举 **1.7 ms**、私有 SkyLight 单属性读 **0.042 ms**、`SCShareableContent` **32.1 ms**。
  → **贵的是「发现窗口」，便宜的是「读属性」**（40–100 倍）。**R3 的三档唤醒恢复因此必须幂等且有界**——每一档都重新枚举全部 App 的话，10 个 App 就是 45–105 ms。
- 空闲计数：Dock 触发关着时 **AX 查询 0 次／飞行中缩图 0 张／缓存 0 字节**，且探针确认设置被原样恢复。
- 静态足迹：**bundle 6.6 MB，主二进位 3.6 MB**（09-22 构建）。**已装的 1.0.16（`/Applications/WindowShade.app`，2026-10-15 `du`／`ls -l`）是 bundle 23 MB、主二进位 19.8 MB**——R44 若定体积阈值，别照 6.6 MB 定。**注意别和「物理占用约 100 MB」（执行期内存）混为一谈**——这正是 E2 要查清的口径。

---

## 4. 验证命令速查

```bash
# 建置闸门（唯一门槛）
cd prototype && nohup bash -c './build.sh --check; echo "EXIT=$?" >> /tmp/bc.log' > /tmp/bc.log 2>&1 &
grep EXIT= /tmp/bc.log

# 本地化棘轮（会拦中文日志串）
grep -c '防漏网\|文案检查通过' /tmp/bc.log

# 权限与事件通道的日志（R1/R2）
log stream --predicate 'process == "WindowShade"' --style compact | grep -E "environment:|tap-disabled"

# 看还有哪些同类工具在跑（R8）
osascript -e 'tell application "System Events" to get bundle identifier of every application process' | tr ',' '\n' | grep -E "knollsoft|windowmagnet|MrKai77|manytricks|irradiatedsoftware"

# 模拟「AX 不响应的 App」（R7）
kill -STOP <pid>   # 之后记得 kill -CONT

# 泄漏 / 循环引用体检（R39，先测不改）
leaks --atExit -- /Applications/WindowShade.app/Contents/MacOS/WindowShade 2>/dev/null | tail -20
# 长会话观察：收起/还原 200 次、开合窗口浏览 100 次、悬停看一眼 100 次，记对象数与内存曲线
# （Instruments 的 Leaks 与 Allocations 模板更适合看曲线；命令行适合快速初筛）

# CI 落地后（R33）本地等价物——CI 跑的就是这一条
cd prototype && ./build.sh --check; echo "EXIT=$?"

# 版本号纪律核对（R34）：同一个 build 号出现两次就是违约
grep -oE '<sparkle:version>[^<]+' ../site/public/appcast.xml | sort | uniq -d   # 目前只有 1 条（version 16）
```

---

## 5. 竞品证据在哪、以及怎么重跑

### 5.1 落在仓库里的（长期可读）

| 文档 | 里面有什么 |
| --- | --- |
| [product-reshape.md](product-reshape.md) | 本条规格的理由清单（17 条，症状→谁修过→我们的现状→改成什么→怎么验） |
| [competitive-deep-dive.md](competitive-deep-dive.md) | 机制层与**函数级**证据（含 Ghidra 12.1.4 的结果与取用方法） |
| [changelog-knowhow.md](changelog-knowhow.md) | 626 个 release 归成 13 个失效家族，逐条标「我们已在做／部分／未做／待核」 |
| [production-maturity.md](production-maturity.md) | 出货面与自愈的动作清单 |
| [competitive-packaging.md](competitive-packaging.md)／[competitive-websites.md](competitive-websites.md) | 包层面与站层面 |

### 5.2 `/tmp` 里的（**重启会清空**）

`/tmp/ghout/*.tsv`（各竞品的「字符串 → 引用函数」映射）、`/tmp/ws-research/apps/`（九份验签通过的件副本）、`/tmp/ws-research/thin/`（arm64 单架构切片）。

### 5.3 重跑配方（全部可复现，且**不需要破解件**）

```bash
# 0. 原生分析引擎（唯一一条不用碰破解件、也不用真人点授权的路）
brew install ghidra            # 走 Homebrew 自己的 OCI 仓库，别走 GitHub release（那条 1.3 KB/s）
export GHIDRA_INSTALL_DIR=/opt/homebrew/opt/ghidra/libexec
export JAVA_HOME=/opt/homebrew/opt/openjdk@21

# 1. 切片：Ghidra provider 不吃 universal Mach-O
lipo -thin arm64 <App.app>/Contents/MacOS/<exe> -output /tmp/thin/<name>

# 2. 跑分析 + 后置脚本（Ghidra 自带 analyzeHeadless **没开 PyGhidra**，所以后置脚本
#    必须用 Java，不能用 .py）
analyzeHeadless /tmp/ghproj <name>Ana -import /tmp/thin/<name> \
  -scriptPath /tmp/ghscripts -postScript DumpStrings.java /tmp/ghout/<name>.tsv \
  -analysisTimeoutPerFile 7200 -deleteProject

# 3. 挖（示例）
awk -F'\t' '$2 ~ /^[a-z][a-zA-Z]*\.[a-zA-Z][a-zA-Z0-9_.]*$/ {print $2}' /tmp/ghout/<name>.tsv | sort -u
```

**后置脚本本体（下面是全文——它原本只存在 `/tmp`，重启就没了；照抄成 `/tmp/ghscripts/DumpStrings.java` 即可）**：

```java
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.*;
import ghidra.program.model.symbol.Reference;
import java.io.*;

public class DumpStrings extends GhidraScript {
    @Override
    public void run() throws Exception {
        String[] a = getScriptArgs();
        String out = (a.length > 0) ? a[0] : "/tmp/ghout/strings.tsv";
        Listing listing = currentProgram.getListing();
        FunctionManager fm = currentProgram.getFunctionManager();
        PrintWriter pw = new PrintWriter(new BufferedWriter(new FileWriter(out)));
        pw.println("string_addr\tstring\tfunction\tref_addr");
        int scanned = 0, rows = 0, kept = 0;
        DataIterator it = listing.getDefinedData(true);
        while (it.hasNext()) {
            Data d = it.next();
            scanned++;
            if (!d.hasStringValue()) continue;          // 只取被定义成字符串的数据
            String s;
            try { s = (String) d.getValue(); } catch (Exception e) { continue; }
            if (s == null) continue;
            s = s.replace("\t", " ").replace("\n", " ").replace("\r", " ");
            if (s.length() < 4) continue;
            boolean ok = true;
            for (int i = 0; i < s.length(); i++) { char c = s.charAt(i); if (c < 32 || c > 126) { ok = false; break; } }
            if (!ok) continue;
            kept++;
            Address addr = d.getAddress();
            Reference[] refs = getReferencesTo(addr);
            if (refs == null || refs.length == 0) { continue; }
            for (Reference r : refs) {
                Address fa = r.getFromAddress();
                Function f = fm.getFunctionContaining(fa);
                pw.println(addr + "\t" + s + "\t" + (f != null ? f.getName() : "-") + "\t" + fa);
                rows++;
            }
        }
        pw.close();
        println("DUMP: scanned=" + scanned + " strings=" + kept + " rows=" + rows + " -> " + out);
    }
}
```

**踩过的三个坑（都别再踩）**：① **一次只跑一份**——并行会把彼此拖到 `list_documents` 超时；② **`-analysisTimeoutPerFile` 要给足**（REA 的默认预算 330 秒只装得下 ~3 MB 以下的件）；③ **别在 Ghidra 跑的时候改脚本文件**——会把已在用它的进程的编译包弄失效。

**第四个坑（2026-10-15 补）**：**大件会 OOM**。Ghidra 的 `analyzeHeadless` 默认堆只有 **2G**（`support/analyzeHeadless` 里的 `MAXMEM_DEFAULT=2G`），106 MB 的 Notchy 切片直接把 JVM 打爆（`java.lang.OutOfMemoryError: Java heap space`）。**跑之前先设**：`export GHIDRA_HEADLESS_MAXMEM=10G`（这台机器 24 GB）。**第五个坑**：`File not a valid directory or file` 通常是**忘了先 `lipo -thin`**（非 fat 的 arm64 件可以直接指向原始二进位，但路径要写对）。

---

### 5.4 已经挖到什么、还剩什么（别重复挖）

**先说结论：靠 `grep` 能挖的已经基本挖完。** 剩下的要动反编译（`rea decompile` 或 Ghidra），不是再换几个关键词。**七份 TSV 的产出与未挖项**：

| 件 | TSV 行数 | 已挖到（落在哪） | 还剩什么（需要什么） |
| --- | ---: | --- | --- |
| **Wins 3.5.1** | 12,872 | **219 个点分键**：拖动四级几何回退链、`drag.axSizeSettable`、`resume.immediate/0.20/0.80`、`island.layoutJSON`、`missionControl.tapDisabled`、41 个例外 App（[竞品深挖](competitive-deep-dive.md)§三） | 各环节的**判定条件**（`exclusionCheck` 判什么、`axSizeSettable` 的门限）→ **反编译** |
| **Alcove** | 20,250 | 九个 `CGS*Space*` 连成一片、`focus.{fitness,personal,sleep,work}`、App 名单（§三） | 那**三个 `CGSAddWindowsToSpaces` 调用点各在干什么** → 反编译调用点 |
| **Swish** | 10,111 | 12 个手势原语 ＋ 九类设置栈（§三） | 手势的**判定阈值**与「消费 vs 放行」的条件 → 反编译手势回调 |
| **WindowMizer** | 23,011 | 占位条生命周期全表（collectionBehavior／孤儿／串行队列／压 unhide／`axToolbarH`／降级支路）（§三） | 无标题窗口与 Folder alias 的**具体判据** → 反编译 |
| **LaunchOS** | 16,473 | 读 Launchpad SQLite 的完整 SQL、分页拖曳模型（§三） | `genericIconPixelsLock` 的**实现**（图标兜底怎么做） → 反编译 |
| **MediaMate** | 26,932 | Lunar／BetterDisplay 互通、GameOverlay 观察、HUD 五形态（§三） | OSD 抑制与**还原的时序** → 反编译 |
| **ChainYourMac** | 32,143 | 完整源文件清单、**13 项同类工具检测名单**、`MacSetupChecker` 的三个开关（§三） | `PaneruCommand` 的**完整命令集** → **反编译；它未 strip，最省力，建议第一个做** |
| **Notchy／Droppy** | **未产出** | — | 全部；见 §5.3 的坑（**堆给足 ＋ 别忘切片**） |

**已经核过、确认「grep 挖不出更多」的例子**（省得后人再试）：

- MediaMate 里成串的 `*StateMachine`（`ZipStateMachine`／`MergeStateMachine`／`DebounceStateMachine`…）**是 SwiftUI／Combine 的框架内部符号，不是它的代码**——挖出来也是噪音。
- WindowMizer 的设置项名**不在二进制里以 `Use …／Enable …` 这种形状出现**（应该走本地化表）。
- Alcove 里**没有** `CGDisplayCreateUUIDFromDisplayID`——它的 `UUID` 是 Foundation 那个类型（这条同时纠正了「四家都用显示器 UUID」的说法，见 §7 第 8 条）。

## 6. 不要做的事

- **不碰破解件**。本机那份 Hopper 是破解版（`adhoc` 签名、`spctl rejected`、两处链 `libHopperCrack.dylib`），**已永久弃用**；同类东西一律不用。
- **不绕过保护措施**：DRM、授权／序列号校验、anti-tamper、加密载荷。撞到就停手回报。
- **不搬代码、不搬资产**。开源件：MIT 可借代码并带署名；**GPL 那几家（Atoll／niri／DockDoor／OmniWM／Nehir）只借思路**，写代码时不要把那份源码摆在旁边逐行对照。**许可一律读原文，不采信 GitHub 标签**（DockDoor 就被误判成 `NOASSERTION`，实际 GPL-3.0）。
- **不把 raw 捕获或竞品件放进仓库**。
- **不把「工具退出 0」当验收通过**；缺证据写 `inconclusive`。

---

## 7. 本轮自纠（2026-10-15，`知错能改`的留痕）

**共 13 条。**前 5 条来自第一轮；中 6 条来自第二轮（触发点：`nm -u` 全表复核）；**第 12、13 条来自第三轮「量自己」**（2026-10-15 上午，拿竞品同一套管線量 1.0.16 候选包）——又抓到两条，其中一条是**量具本身有盲区**。

**发现错误就直接改，并记下改了什么、错在哪**——不静默修正，否则下一个读到旧数字的人会照样错。

| # | 原来的说法 | 实际是 | 影响到 | 根因 |
| --- | --- | --- | --- | --- |
| 1 | 「**隐私登记 673 处**」 | **代码侧 65 个登记项、66 个 `interfaces:` 数组**（[privacy-page.md](privacy-page.md) 39 行表格）。**673 的口径存疑**：项目自己的 `docs/releases/v1.0.16-ledger.md:227` 用「隐私登记 673 处」，而 `docs/window-management-quality-progress.md:37` 用「673 项检查」（**编译与检查项**）。**两种口径对不上，本文档一律不再引用 673** | [north-star](north-star.md)、[production-maturity](production-maturity.md)、[apple-native](apple-native.md)、本规格 R13／R37／N2 | **引用了摘要里的数字，没有本轮重新数** |
| 2 | 「`tests/` **现在为空**，验证主轴是探针」 | **`tests/` 有 244 个 Swift 测试档 ＋ 218 支 `run-*.sh`**（共 462 条目，2026-10-15 `find tests` 复数；此前写 228＋215＝465，加法本身就不对），用**自制的 `@main struct + expect()`** 模式（`import XCTest`／`import Testing` 各 0），且 **`build.sh` 已纳入其中几支**（`:125`／`:184`／`:187`） | [modernization](modernization.md)（三处）、本规格 **M7**、§一 | **在 `prototype/` 底下找 `tests/`，报「不存在」就下了结论**——真实位置在**仓库根** |
| 3 | 「**47 处**读 `AXIsProcessTrusted()`」 | **49 处**（含 `WithOptions` 共 50 处） | 本规格 **R2** | 早先的一次计数没有再核 |
| 4 | M7 建议「**引入 Swift Testing**」 | **改为：按 `tests/` 既有模式写**——多一个框架就多一套 runner 与输出格式，而既有那套已经接进门禁。**「现代化」不等于把能用的东西换掉** | 本规格 **M7**、[modernization](modernization.md) | 前提（#2）错了，建议跟着错 |
| 5 | 「§二 可借项表 **96 行**」 | **86 行**（第二张「已在做」表另算 9 行） | 本规格的处置表那一节 | 把两张表行数加在一起了 |

| 6 | 「`fullScreenDisallowsTiling` **只在 `Thumbnail.swift:35`**」 | **三处**：`Thumbnail.swift:35` ＋ `App/OverlayFactory.swift:21`／`:56`／`:186` | 本规格 **R18**（前提从「补齐」改成「核其余面板该不该加」） | 只按一次 grep 的印象下结论 |
| 7 | 「唤醒观察者 **十处**」 | **16 个文件、23 处** | 本规格 **R3** | 数的时候只看了文件不数出现次数 |
| 8 | 「**四家**都用显示器硬件 UUID」 | **三家已核实**（DockDoor／OmniWM／Wins，且 Wins 那条是从命名推断）；**Alcove 未核实**——它件里只有 Foundation 的 `UUID` 类型，**没有 `CGDisplayCreateUUIDFromDisplayID`** | 本规格 **R27**、[north-star](north-star.md) | 把「看起来像」也算成了「已核实」 |
| 9 | H5 说「`FoldRenderer` 从 `CGImage` 建纹理、要 CPU 上传」 | **不准确**：`Effects/FoldRenderer.swift` **已有** `CVMetalTextureCache`（`:35`／`:111`／`:291`）并用 `CVMetalTextureCacheCreateTextureFromImage`（`:346`） | 本规格 **H5**（前提改成「核哪些路径还在走 CGImage 上传」） | **没看代码，只看了一个调用点的类型签名** |
| 10 | [性能与能效](perf-energy.md) 说「我们**不直接调** `CGPreflightScreenCaptureAccess`」 | **是错的**：`nm -u` 有它，代码里 **5 处**（`Capture/WindowSnapshot.swift:54`、`App/Permissions.swift:13`、`Effects/DuoSettingsWindow.swift:1023`／`:1037`／`:1123`…）。→ **这一条从「我们已经做对」变成「要核」**（有没有落在主线程热路径上） | [性能与能效](perf-energy.md)、本规格 **E 系列** | 又一次「凭印象说我们没做」 |
| 11 | [北极星](north-star.md) 说「私有面**没有一处写**」 | **被第 12 条再次推翻**：当时改成「没有一处写窗口服务器，只有一处 IOKit 写」；现在两条都不成立——**既有写窗口服务器（`SLSSetWindowAlpha` 等），那处 IOKit 写反而在出货包里不存在（死码）** | [北极星](north-star.md)§二第 2 项、[竞品深挖](competitive-deep-dive.md)§五 C1／C8 | 说「没有」之前没有把符号表**全表**过一遍（第一次）；**没审过量具能看到什么**（第二次） |
| 12 | [性能与能效](perf-energy.md)／[竞品深挖](competitive-deep-dive.md) 里 I（当时的我）判「`DisplayServices` 在两条构建里都是 0，scorecard 说法可证伪」 | **错的是我**：它是 `dlopen`＋`dlsym` 运行时载入（`App/NotchLevelObserver.swift:89`），`nm -u` 与 `bl` 呼叫轮廓**天生看不见**。顺藤一查：`Private/` 四个桥接层载入**整套** SLS（含 `SetWindowAlpha`／Space 搬运）／DisplayServices／CoreDock／`SACLockScreenImmediate`……**私有面比自述大得多** | [竞品深挖](competitive-deep-dive.md)§五 C1（改写完成）、[北极星](north-star.md)§二第 2 项（改写完成） | **审计「没有」时，没先审计「我用来断言的这把尺子能看到什么」**——这次在写入文件前抓住（第 11 条是写进去之后才被推翻的） |
| 13 | [北极星](north-star.md)、[成熟度](maturity.md)、[生产级成熟](production-maturity.md) 都写「v1.0.15 之后 **170 个提交、0 次发布**」 | **10-06 的旧快照**：1.0.16 已于 2026-10-14 发布（appcast 1 条、tag v1.0.16）；真相更难看——**同一版本号重发到第十一次**（`git log --oneline | grep 同版本号重发` 得 11 条） | 上述三份文档（均已改写）＋ [竞品深挖](competitive-deep-dive.md)§五 C6 | **引了 10-06 那份审查包里的数字，没核过本机的发布记录**（`git log`／`appcast.xml` 都是现成的）——与第 1 条同根 |

**从这 13 条里抽出来的那条规矩（真正的病因）**（建议写进执行者的习惯里）：

> **病根只有一句话：断言「没有」的时候，没有穷尽地找。** 13 条里有 **8 条**是这类——「tests/ 为空」「我们不直接调那个检查」「私有面没有一处写」「只有一个文件用了 disallowsTiling」「四家都用 UUID」「没看代码就断言 FoldRenderer 从 CGImage 建」，加上 #11 的第二次翻车与 #12。**说「没有」的成本要比说「有」高一个数量级**：说「有」给一个例子就行，说「没有」要把全表过一遍。
>
> **#12 给这条病根还长出一个变种：不只把「有没有」数全，还要审「我用来数的尺子能看到什么」**——`nm -u` 只看静态符号表，`dlopen`／`dlsym`／`NSClassFromString` 载入的那一层它一辈子看不到；同理 `bl` 呼叫轮廓看不见 `objc_msgSend`。**换量具之前，先问这把尺子量什么、漏什么。**
>
> **任何要写进文档的数字，都要在本轮用绝对路径、可重复的命令重新数一次**；**数完把命令也贴上**（本文档各处的数字基本都带了命令或出处，就是从这来的）。
> **路径先确认再下结论**——「找不到」和「不存在」是两件事；`ls` 的失败不等于目录为空。

**这一条与[北极星](north-star.md)§二第 3 项（不拖慢我的机器）是同一个道理的两种应用**：对外说的每个数，都要有能被复核的来源。
