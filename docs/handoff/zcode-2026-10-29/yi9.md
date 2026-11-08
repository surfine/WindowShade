# 乙 9 · 用量進會話卡 · 驗收記錄

分支 zcode/integration-乙9（基於 0438f5ab），worktree /Users/aaron/Documents/WindowShade-yi9。

## 前提核查

- main 上可靠的用量來源只有一路：自己啟動的 Codex 會話的 `account/rateLimits/updated`（`WS2OwnedCodexSession.onUsage` -> `UsageReading.parse`）。沒有 Claude 狀態欄來源（`rate_limits` 在 prototype/ 裡沒有讀取點）。
- 所以這一步只做視圖與模型，沒有新增任何來源、讀取點或網路請求。`tools/privacy/registry.json` 與隱私頁不變，故未跑 privacy 兩支腳本（沒有新讀取點）。

## 改動

- `prototype/Core/UsageReading.swift`：`UsageWindow.limitText`（300 分鐘寫「五小时余 N%」，10080 分鐘寫「本周余 N%」，別的時長不編名字）；`CodingSessionUsage.limitsLine`，`detailText` 以它開頭，展開格底一行成「五小时余 42% · 本周余 61% · 恢复时间 · 模型 · 强度」。
- `prototype/Core/NotchActivities.swift`：`CodingSessionActivities.usageWasLow`；掉到 10% 以內後，下一個回到 10% 以上的真實讀數返回一次「额度已刷新」bloom（走既有 `onSessionBloom` -> `announceWhenFree` 第 4 層，priority 4）；說完忘掉；會話 reset 也清掉。「等待用量更新」與讀數斷掉（nil）都不算恢復。
- `prototype/Resources/Localizable.xcstrings`：新增 `usage.limit.fiveHour`、`usage.limit.week`、`notch.usage.back`（簡體源、繁體、英文）。沒有孤兒鍵。
- `tests/UsageReadingTests.swift`：三檔假資料（充足 / 快用完 / 未知）、展開格實際帶這一行、恢復 bloom 只一次；原斷言「額度回來不提醒」改成「回來提醒一次」（這正是本步點名要改的行為）。

## 與工單字面的差異（帕累托，請 Aaron 看一眼）

- 工單說「快用完時右耳變『剩 p%』」。現況右耳有數據時一直是「剩 p%」（≤10% 琥珀色），既有測試也鎖著。這是已上線行為，沒有改成只在快用完時才出現。
- 沒有做 `usage.md` 的三個設定項（顯示用量／不足時提醒／恢復時提醒）；本步沒要求。

## 指令與結果

見提交訊息與回報。`bash tests/run-usage-tests.sh` 退出 0（65 條斷言）；`bash tests/run-session-activity-tests.sh` PASS 93 條；`./prototype/build.sh --check` 結果見末尾。

## 並發

未動主線程隔離、Mutex 或 actor；只改純邏輯結構體與字串。

## 要 Aaron 在真機看的

- 展開的會話卡底一行加長後（「五小时余 42% · 本周余 61% · 1 小时后恢复 · gpt-5 · 高」）是否被截斷、是否過擠。
- 用自己啟動的 Codex 會話跑到額度回升時，「额度已刷新」是否只出現一次、點了落到哪裡。
- Claude 訂閱的用量仍無來源，未接。

## 複核修正（第二個提交）

- 發現 1（成立，已修）：Codex 的 `account/rateLimits/updated` 可能只帶一個窗口。`CodingSessionUsage` 新增 `windowMinutes`（最緊窗口時長）與 `windowsSeen`（本次讀數帶了哪些窗口）；變「快用完」時記下卡住的窗口時長，恢復 bloom 只在新讀數非低、且讀數帶了那個窗口時才說。只帶 5 小時窗口的零散更新不再冒充周額度回來；來回交替也不誤報。新增 `testSparseUpdateAndRecoveryProject`。
  - 殘留：兩個窗口同時低、後來零散更新只帶其中一個且已回升時，仍可能早說一次（來源沒給完整快照，無從判斷）。另一額度池（limitId 非 codex）的更新仍按現有 parse 取值，未改。
- 發現 2（成立，已修）：`Bloom` 新增 `cwd`。變「快用完」時記下最近有消息的會話（label、cwd），恢復 bloom 副句寫該項目名，`WS2AppRuntime.wireCodingSessions` 點擊時優先用 `bloom.cwd`，其餘 bloom 行為不變（cwd 為空仍按會話查）。當時沒有任何會話時副句留空、點擊行為同前。reset 一併清掉。
- 並發：未動；`WS2AppRuntime` 只改一行取 cwd 的表達式。
- 測試：`bash tests/run-usage-tests.sh` 69 條通過；`bash tests/run-session-activity-tests.sh` 93 條通過；`./prototype/build.sh --check` 結果見提交訊息。
