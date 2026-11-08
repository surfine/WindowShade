# 甲2 · 拆开 owner "pomodoro"（验收记录，2026-10-29）

分支 `zcode/integration-甲2-owners`（worktree `WindowShade-zcode-jia2`，从本地 `main` @ 9c3806c2 开出）。
单提交，不推送、不合 main。

## 做了什么

番茄钟、计时器、日程卡各自一个主人，`show` 不再互相顶掉：

1. **App/NotchLeases.swift**：`Owner` 加 `countdownTimer`（计时器卡：选分钟 / 正在走 / 时间到）、`calendarCard`（日程大卡）；层表（`.opened`）与协调器 permits 表同步。
2. **App/CountdownTimerCard.swift**（两处 show）：`ownerID: "pomodoro"` → `"countdownTimer"`。
3. **App/CalendarPresenter.swift**（openCard）：`ownerID: "pomodoro"` → `"calendarCard"`，并带 `borrowsSeat: true`。
4. **App/WS2AppRuntime.swift**（FocusTimerCard）：保持 `"pomodoro"`。
5. **借座位语义**（三张卡同名问题的根）：
   - `Core/Contracts.swift`：`WS2.LeaseRequest` 加 `var borrowsSeat: Bool = false`。
   - `Core/InteractionCoordinator.swift`：`acquire` 里 `borrowsSeat` 且都是 .opened 且主人不同 → 按 `.suspended` 撤旧页（挂起、parkedContent、让出后原样回来），**不是**显式换页的 `.preempted`（旧页不回来）。同主人显式再开仍是换页。
   - `App/NotchLeases.swift`：`show` 加 `borrowsSeat:` 参数，为真时请求带 `suspends` 且不传 `replacing`。
   - **App/Notch.swift** 的 `cancelLease` switch 补两个新 case（编译期穷尽）。

## 验收（全部实跑）

| 命令 | 结果 |
| --- | --- |
| `bash tests/run-interaction-coordinator-tests.sh` | PASS，11 场景 / 80 断言 / 0 失败（新增 R8：计时器卡开着 → 日程卡借座位出现、计时器 `.suspended` 不拆；日程卡收了计时器拿新租约原样回来、无 `.preempted` 拆除；同主人显式换页照旧抢占） |
| `bash tests/run-focus-timer-tests.sh` | PASS（T1: 18 cases, 54 assertions, 0 failures） |
| `bash tests/run-appkit-tests.sh NotchLeaseHostTests` | 见下「没跑成」 |
| `./prototype/build.sh --check` | 退出 0 |

## 没跑成 / 待真机

- `tests/run-appkit-tests.sh NotchLeaseHostTests`：先编后跑，编译退出 1 —— 我曾在其中加的宿主级用例需要 `NotchController`（测试环境没有），已把验收移到协调器纯逻辑层（R8）并撤掉该用例；改后该脚本未再单独跑（`run-appkit-tests.sh all` 在 `NotchActivityViewTests` 因 Metal library 环境问题崩，与本步无关）。**待 Aaron 的环境复核**。
- 真机看护：日程提醒（最后 10 秒点开大卡）盖在计时器卡上、关掉后计时器原样回来，这一幕要真机过一遍（挂起页的进场不重播、相机避让不受影响）。
