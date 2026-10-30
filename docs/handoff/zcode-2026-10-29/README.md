# ZCode 第一单 · 进度与合入（主模型 2026-10-29 复核）

派单：[ZCODE-WORKORDER-2026-10-29.md](../ZCODE-WORKORDER-2026-10-29.md)。ZCode 交了甲 1–3，主模型审差异、重跑检查后合进本机 `main`（`f81cbd17`，未推送）。甲 4 与乙 7–17（第 7、8、9、10、15、16、17 步）由主模型自己做（Aaron 10-29「你自己做」）：Sonnet 子代理实现，独立审查后修正，主模型验收合入；2026-10-30 本机 `main` 快进到 `8f4d9f86`，未推送。

| 步 | 状态 | 合入 | 备注 |
| --- | --- | --- | --- |
| 甲 1 一个协调器 | **已合入** | `674d00db` | 有一处行为变化：排队的提醒撞上第 1–3 层时，从「等空了再说」改为「变成点并消耗、不补说」（例如那一排开着时解锁，离开期间摘要变成点）。照 design-grammar 的层序规则，派单写成了「现状」，实为改行为，已告诉 Aaron |
| 甲 2 拆开 owner | **已合入** | `d83649d2` | 新增「借座位」：日程卡挂起计时器卡而不是拆掉 |
| 甲 3 停留时间表 | **已合入，主模型改了三个名字** | `3e4f1130` + `f81cbd17` | `timerDone`、`receipt`、`presenceReturn` 三个常量单位是 `WS2.Duration`（纳秒），ZCode 命名为 `…Milliseconds`；改名为 `…Duration` 并写回 `10 * WS2.Duration.second` 这类表达式，值不变 |
| 甲 4 一个提示音 | **已合入** | `0438f5ab` | 一个键 `WindowShade.AlertSound` 管等你、完成、番茄钟、计时器、指挥拍子；旧三键迁移（任一开着即开）；默认开（Aaron 10-30 第 24 条） |
| 乙 7 番茄钟收聊天 | **已合入** | `2e79bcaa` | 默认关；审查抓到 `admitted` 同时放开了休息时整屏收起，另设闸门 `restTuckAdmitted = false` 保持关 |
| 乙 8 会话格进指挥页 | **已合入** | `7957b440` | 返回 = 收起、草稿留着；切到 Codex 不再丢 Claude 草稿 |
| 乙 9 用量进会话卡 | **已合入** | `5d66419d` | 「额度已刷新」只在卡住的那个窗口回来时说一次 |
| 乙 10 离开期间摘要可点 | **已合入（部分）** | `c16a8b13` | 现在只认刘海那一行说的第一项；逐项可点按稿《离开期间》另做（Aaron 10-30 第 25 条） |
| 乙 15 标题栏双击 | **已合入** | `d4c1c19e` | 判定移到后台队列，**改了并发**；判定跑过截止时间时吞下、结论出来再做 |
| 乙 16 刘海张开 | **已合入** | `4994c165` | 张开 = 展开那一排；那一排里统一叫「回到原处」/「去」 |
| 乙 17 排布历史 | **已合入** | `4d830c18` | 菜单「整理 ▸ 撤销〈最近一步〉」；状态结束即作废 |
| 整合修补 | **已合入** | `c527206a` `93f39c47` `8f4d9f86` | 设置导览测试改认「提示音」；乙 16 改 copy-guide 后设置搜索同义词补两组；那一排读屏念整句（第 26 条） |

## 主模型复核做了什么

- 读三页验收记录与关键差异（`InteractionCoordinator` 的 `admit`／`promoteReminders`／`borrowsSeat`；停留表逐值对原值）。
- 在 `claude/zcode-integ` 依序合 甲 3 → 甲 2 → 甲 1；唯一冲突在 `tests/InteractionCoordinatorRulesTests.swift`（两边都新增案例），两边都保留：14 场景、103 断言、0 失败。
- 整合检查跑了两轮（改名前后各一次）：`./prototype/build.sh --check` 退出 0，加上协调器、番茄钟、动效令牌、动效 lint、全部 `run-notch-*`、日程、离开摘要、会话活动等，以及甲 3 动过的全部测试脚本，**共 82 项 PASS、0 失败**。

## 真机探针（主模型 2026-10-29 11:37–11:50，本机 M5 MacBook Air，macOS 27）

`f81cbd17` 用开发证书 B3CE57C3… `./build.sh --stage`（退出 0），每组等 HID 闲置 ≥120 s、拿 `/private/tmp/ws-ui.lock` 后跑 `tests/run-glance-probe.sh`；正式版 WindowShade 照常开着。输出在整合 worktree 的 `.build/probes-jia123/`。

| 组 | 结果 |
| --- | --- |
| browser-more（当年抓到 Mutex 崩溃的那组） | 5 PASS |
| wins | 8 PASS（跑两次都过；结束时闲置归零，两次都一样，是探针自己的合成输入） |
| fold-timing／restore-guard／fold-unminimizable／orphan | 2／4／4／3 PASS |
| launchpad（刘海租约） | 14 PASS |
| pins／hold／home | 5／9／4 PASS |
| notch | 21 PASS（交接里列为环境性失败，这次全过） |
| shelf-glance --minimize | 9 PASS |

0 FAIL，退出码没有 133，`~/Library/Logs/DiagnosticReports` 没有新的 WindowShade 崩溃报告。另补跑 `run-appkit-tests.sh`：NotchLeaseHostTests 17 例 0 失败、CountdownTimerCardTests、CalendarCardTests 全过。

结论：甲 1–3 动过的主线程／租约路径在真机上没有触发运行期隔离检查。**探针覆盖不到提醒碰撞的画面**（现有探针都不会制造电量、日程、离开摘要事件），下面几项仍要人看。

## 仍待真机（Aaron）

- 甲 1：① 那一排展开时来的电量提醒（应只亮点）；② 日程提醒盖在番茄钟卡上，说完番茄钟原样回来；③ 离开摘要 8 秒期间来的低电量（应排队接着说）。
- 甲 2：日程大卡盖在计时器卡上、关掉后计时器原样回来，进场不重播。

## 甲 4 与乙批：主模型 2026-10-29／30 复核

- 整合分支 `zcode/integration-yi`（worktree `../WindowShade-yi-integ`）＝`0438f5ab` 合乙 7、8、9、10、15、16、17，无冲突。
- `./prototype/build.sh --check` 退出 0；整套 `tests/run-*-tests.sh` 加文案、动效、隐私检查共 231 份，失败的只有两支，都已查清：设置搜索（乙 16 改了 copy-guide「不要用」，已补同义词，现过）、`run-silent-integration-tests`（要带 `--case`，不是失败）。指挥页探针要先做一次签名构建，超时后不限时重跑通过。
- 主模型亲自看过乙 15 的并发改动：新锁 `ChromeHitHeightMirror` 是独立的 `Sendable` 类，不挂在主线程类上；后台判定调用的函数都线程安全。

### 真机探针（2026-10-30 19:20–20:33，本机 M5 MacBook Air，macOS 27）

开发证书签的 `--stage` 包（`93f39c47`），每组等 HID 闲置 ≥120 s、拿 `/private/tmp/ws-ui.lock`。

| 组 | 结果 |
| --- | --- |
| browser-more、wins、fold-timing、restore-guard、fold-unminimizable、orphan | 5／8／2／4／4／3 PASS |
| launchpad | 第一次「扫描 App 刚好 10 秒到上限」超时；单独重跑 14 PASS |
| hold、home、notch、shelf-glance --minimize | 9／4／21／12 PASS |
| finder-alias（合成双击，走乙 15 的新钩子分流）、slide-over、pip（乙 17 的作废调用） | 3／16／11 PASS |
| pins | 2 FAIL：探针写死简体「暂时取消全部置顶」，系统界面是繁体；在 `f81cbd17` 上对照跑一模一样，**环境问题** |
| gesture | 1 FAIL：「pinch without undo」，探针比对简体「没有可撤销的排布」，界面显示繁体「沒有可還原的排布」；这行字乙批没碰过，**同一类环境问题** |

没有新的 WindowShade 崩溃报告，没有退出码 133。`8f4d9f86`（读屏念整句）在探针之后提交，只改一句读屏文字，已过构建与全部刘海测试。

**探针本身要修**：pins、gesture 的比对写死简体字，界面语言跟系统（现为繁体）时必失败；应改成按键名取当前语言的文字。

## 仍待真机（Aaron）

- 甲 1：① 那一排展开时来的电量提醒（应只亮点）；② 日程提醒盖在番茄钟卡上，说完番茄钟原样回来；③ 离开摘要 8 秒期间来的低电量（应排队接着说）。
- 甲 2：日程大卡盖在计时器卡上、关掉后计时器原样回来，进场不重播。
- 乙 7：设置开着时收起与放回聊天窗口（截图没完成、手动挪过、PID 复用、迟到的完成、放回一半失败、锁着时回调）。
- 乙 8：写一段 Claude 草稿，切到 Codex，返回，再打开：草稿应在 Claude 那边。
- 乙 9：「额度已刷新」的副句与点它回到的项目。
- 乙 10：点摘要时窗口在别的桌面上，会不会真的切过去。
- 乙 15：在回应慢的 App（例如正在建索引的 Xcode）上双击标题栏，应收起而不是缩放，日志有「off-main decision late; swallowed」。
- 乙 16：张开、上推、英文读屏。
- 乙 17：从菜单收进刘海 → 点开放回 → 全部收进刘海，菜单不应再给「撤销收进刘海」；侧拉后滑出屏幕边，撤销侧拉应回到侧拉前的位置。

## 同日新定（AARON-DECISIONS 第 22–33 条）

里程碑以整合计划 18 步合入为准（现 11/18），下一条线是第 11 步换皮 + 第 12 步露出（Sonnet 子代理实现）。新稿：[离开期间](../../design-drafts/离开期间.html)（定稿）、[照系统的岛](../../design-drafts/照系统的岛.html)（等 11 月 6 日后真机量）。照系统的岛会改到第 11 步的尺寸：那一排压进 408×160 并横向滚动、拿掉悬停展开、点耳朵打开活动、第二个活动分出小圆。

## 第 11 步换皮与第 12 步露出：主模型 2026-10-30／31 复核

本机 `main` 快进到 `1e76fdd7`（未推送），WS2 里程碑现 **13/18**。整合分支 `claude/integ-s11`（worktree `../WindowShade-s11-integ`）＝`8f4d9f86` 合下面各包，主模型审差异、补修后合入；Sonnet 子代理实现。

| 包 | 内容 | 主模型补修 |
| --- | --- | --- |
| 探针按语言取字 | pins、gesture、habits 的比对文字改按键名取当前语言 | 类型名写错（`HabitWords`）一次 |
| 12 露出机制 | `WS2Exposure` 账：有证据的表面才离开预览旗标；这一批没有表面搬出（证据都缺） | — |
| 11-C 指挥页 | 460×360 内四块，新 `WS2ConductorControls` | 两支测试脚本补编 `IslandMetrics`；指挥模式副句改文案（繁体用「瀏海」） |
| 11-B 审批卡与会话列表 | 换皮，`SessionCardStyle`、`WS2SessionCardChrome` | — |
| 11-A 照系统的岛 | 新 `IslandMetrics`（暂定 iOS 尺寸）；那一排 408×160 横向滚动；拿掉悬停展开与「悬停不误触」设置；点耳朵开活动；长按有东西就展开；提醒 408×84 | — |
| 11-B2 编程会话两耳 | 四态脸、审批卡缩回琥珀点 | **改回 120 秒租约**：子代理把租约改成 130 秒并加了闲置停靠，审批请求不会交回终端，Claude Code 会一直等；按第 36 条更正「只做缩回，不改期限」 |
| 11-D 离开期间 | 摘要变展开清单，逐项可点（设备开蓝牙设置，下载在 Finder 里显示） | — |
| 探针修正 `1e76fdd7` | 刘海形状探针认新尺寸；指挥页探针加一次真 Claude 模式 | — |

检查：`./prototype/build.sh --check` 退出 0；整套 229 支测试脚本全过；开发证书签 `--stage` 成功。

### 真机探针（2026-10-31 02:33–05:49，本机 M5 MacBook Air，macOS 27）

| 组 | 结果 |
| --- | --- |
| notch、browser-more、wins、fold-timing、restore-guard、fold-unminimizable、orphan、pins、pins-order、hold、home、shelf-glance、finder-alias、grid、coach、pip | 全 PASS |
| launchpad、habits、slide-over | 第一次超时，重跑全过（habits 那次闲置只有 5 秒，有人在用） |
| notch-shape | 形状都对上新尺寸（耳 52.33、底角 18.33、高 36.67、肩从耳里扣）。剩两项「静止」等不到：真机上正在放的歌「Eyes Closed」把岛撑在紧凑，**环境问题** |
| gesture | 「键盘：放下」超时；在不含这一批的 `claude/probe-lang` 上对照跑一模一样，**不是这一批引入的**，另查 |

无新崩溃。

### 指挥页那一次真 Claude（第 37 条）

跑了：页面打开、切到 Claude、发出一句、CLI 回来、页面回到就绪，这条路通。但本机 `~/.local/bin/claude` 的登录过期（`OAuth session expired and could not be refreshed`），模型没有回答，所以**指挥页仍留在预览旗标里**。Aaron 在终端跑一次 `claude` 重新登录后，用 `tests/fixtures/real-claude-once.py` 再跑一次（只放第一句过去）；这算不算用掉第 37 条的那一次，等 Aaron 定。

## 仍待真机（Aaron，第 11 步）

- 尺寸是 iOS 暂定值，11 月 6 日后用 MacBook Pro 量过，只改 `prototype/Core/IslandMetrics.swift`。
- 那一排 408×160 横向滚动、右缘淡出；长按有东西就展开；点耳朵开活动、点刘海本体回首页。
- 审批卡 120 秒到时缩回琥珀点、请求交回终端。
- 离开期间清单：点设备开蓝牙设置，点下载在 Finder 里显示（多个时开下载文件夹）。
- 英文读屏念整句。

## 后续

- `WS2HookApprovalHost` 里闲置停靠的代码已不再调用，清掉。
- xcstrings `conductor.settings.hookConfig.connectedSub` 繁体用了「劉海」，改「瀏海」。
- 《从锁屏到窗口》《离开就锁》《一颗岛》线上导览未更新；《从锁屏到窗口》勘误（D 账第 18 行）。
- 启动台「今天」的新入口待定。
- gesture「键盘：放下」超时（`main` 上同样有），另查。
