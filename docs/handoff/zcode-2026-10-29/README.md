# ZCode 第一单 · 进度与合入（主模型 2026-10-29 复核）

派单：[ZCODE-WORKORDER-2026-10-29.md](../ZCODE-WORKORDER-2026-10-29.md)。ZCode 交了甲 1–3，主模型审差异、重跑检查后合进本机 `main`（`f81cbd17`，未推送）。

| 步 | 状态 | 合入 | 备注 |
| --- | --- | --- | --- |
| 甲 1 一个协调器 | **已合入** | `674d00db` | 有一处行为变化：排队的提醒撞上第 1–3 层时，从「等空了再说」改为「变成点并消耗、不补说」（例如那一排开着时解锁，离开期间摘要变成点）。照 design-grammar 的层序规则，派单写成了「现状」，实为改行为，已告诉 Aaron |
| 甲 2 拆开 owner | **已合入** | `d83649d2` | 新增「借座位」：日程卡挂起计时器卡而不是拆掉 |
| 甲 3 停留时间表 | **已合入，主模型改了三个名字** | `3e4f1130` + `f81cbd17` | `timerDone`、`receipt`、`presenceReturn` 三个常量单位是 `WS2.Duration`（纳秒），ZCode 命名为 `…Milliseconds`；改名为 `…Duration` 并写回 `10 * WS2.Duration.second` 这类表达式，值不变 |
| 甲 4 一个提示音 | **进行中，未提交** | — | worktree `WindowShade-zcode-jia4` 有未提交改动（新增 `Core/AlertSound.swift`、测试与 9 个文件改动），**基于旧 `main` 9c3806c2**；继续之前先 rebase 到新 `main`（甲 3 动过 `CountdownTimerCard.swift` 等同名文件） |
| 乙 7–乙 17 | 未开始 | — | — |

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
