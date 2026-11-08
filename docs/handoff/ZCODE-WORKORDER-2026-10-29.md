# ZCode 派單 · 把整個 App 有機整合（第一單，2026-10-29）

一次跑完，不中途停下來問。依據：[INTEGRATION-PLAN-2026-10-29.md](INTEGRATION-PLAN-2026-10-29.md)（含末尾增補）、[AARON-DECISIONS-2026-10-29.md](AARON-DECISIONS-2026-10-29.md) 第 1–20 條、檢討報告 [design-review/2026-10-29-hci-multitasking](../design-review/2026-10-29-hci-multitasking/README.md)。行號是 `main` @ 9c3806c2 的行號，動手前用 `git show main:<路徑>` 重核一次，對不上就以符號名找。

程式碼倉庫：`/Users/aaron/Documents/WindowShade`（`prototype/`）。內部文件倉庫：`/Users/aaron/Documents/WindowShade-internal`（`docs/`）。

## 做什麼

分兩批，共十一步。**甲批四步是共用件，互不依賴，先做**；乙批七步各自獨立，甲批全過後再做。每一步一個 worktree、一個分支、一個提交。

### 甲批：共用件

**甲 1 · 一個協調器**（計畫第 1 步）
- 現況：`NotchLeaseHub`／`InteractionCoordinator`（App/NotchLeases.swift、Core/InteractionCoordinator.swift:123-157）之外，還有 `announceWhenFree` 佇列（App/Notch.swift:1415-1520，自帶 priority／ttl／0.6 s 合併）與面板本地的 `alert`／`meter`／`dropState`。
- 要：把佇列併進協調器的第 4 層（短暫提醒）；`alert`／`meter`／`dropState` 改向協調器申請；編程會話 bloom 的優先順序不再是 0（WS2AppRuntime.swift:225-232）。
- 行為不變：提醒撞上第 1–3 層時變成點並消耗、不補說；離開期間摘要、日程、會話完成的先後照現在。
- 驗收：`tests/InteractionCoordinatorRulesTests.swift` 補規則（提醒撞上 1–3 層變點並消耗；三種來源的先後）；`tests/run-interaction-coordinator-tests.sh` 與所有 `tests/run-notch-*.sh` 全過。

**甲 2 · 拆開 owner `"pomodoro"`**（第 2 步）
- 現況：番茄鐘卡、計時器卡、日程卡共用 `ownerID: "pomodoro"`（CountdownTimerCard.swift:318、340；CalendarPresenter.swift:301；WS2AppRuntime.swift:479；InteractionCoordinator.swift:71 的層表），`show` 會互相頂掉。
- 要：三者各自一個 owner（照 `nowPlaying` 拆出來的做法），層表同步。
- 驗收：新單元測試「計時器卡開著時日程卡出現，計時器掛起後原樣回來」；`tests/run-interaction-coordinator-tests.sh`、`tests/run-focus-timer-tests.sh` 全過。

**甲 3 · 一張停留時間表**（第 3 步）
- 現況：`Motion.Hold.alert` 2.6（Motion.swift:35）之外，同一件事散在各檔：`WS2.alertSeconds`（Contracts.swift:334）、`PowerFlashPolicy.holdSeconds`、`CalendarPresentation.minimumHold`、`NotchAlerts.baseHold/maxHold`、`NotchLevelEars.holdSeconds`、`AwaySummary.holdSeconds`、`CountdownTimerPresenter.doneHold`、核准卡 `receiptHold`、`FaceScanStatusController` 兩個 hold、`PresenceLock.returnHold`、`NotchActivity standardHold`（NotchActivities.swift:245）。
- 要：全部收進 `Motion.Hold` 一張表，各處引用；**數值一個都不改**（帕累托）。
- 驗收：`rg` 在 `prototype/` 裡每個停留秒數只剩一處定義；`tests/run-motion-tokens-tests.sh`、`tests/run-motion-lint.sh` 全過。

**甲 4 · 一個「提示音」**（第 4 步；拍板第 1 條）
- 現況：`ShadeSoundEnabled`（番茄鐘借用它，WS2AppRuntime.swift:614-615）、`Timer.chimeEnabled`（CountdownTimerHost.swift:104）、`WindowShade.Conductor.Sound`（WS2ConductorSettingsCore.swift:8）三個開關；編程會話沒有聲音。
- 要：一個新鍵「提示音」管等你、完成、番茄鐘、計時器、指揮拍子；卷簾收起／展開的效果聲**保留自己那一行**（它是動作聲，不是提醒）。舊鍵遷移：新鍵沒存過時，任一舊提醒鍵開著就開；三個舊鍵都沒存過，照 `Core/ReleaseDefaults.swift` 裡現在的提示音預設。編程會話等你／完成補聲音，用既有的播放器，不新增音檔。設定裡只剩一行「提示音」。
- 驗收：遷移單元測試（三種舊組合 + 全新安裝）；`tests/run-conductor-sound-tests.sh`、`tests/run-focus-timer-tests.sh` 全過；新字串進 xcstrings。

### 乙批：各自獨立

**乙 7 · 番茄鐘收聊天：解開閘門，預設關**（第 7 步；拍板第 21 條）
- `WS2FocusWindowPort.admitted` 由 false 改 true（WS2FocusWindowPort.swift:11），設定裡去掉「現在只計時」（WS2FocusSettings.swift 約第 48 行）。
- 預設改成**關**：`WS2FocusSettings.tuckChat` 的 `?? true` 改 `?? false`（WS2FocusSettings.swift:11），`Core/ReleaseDefaults.swift` 若有這個鍵就同步。已經在設定裡明確打開過的人照舊。
- 那一行的名字照 MAIN-MODEL-DECISIONS D02 改回「专注时收起聊天窗口」（現在是「专注时把聊天收进刘海」，WS2FocusSettings.swift:5）；xcstrings 同步，隱私登記表 `tools/privacy/registry.json` 裡的名字（約 :958）與原始碼快照（約 :4728 的 `?? true`）一起更新，再重新生成隱私頁並跑 `tests/run-privacy-page-sync.sh`。
- 驗收：單元測試「全新安裝不收起；明確打開過的照舊收起」；`tests/run-focus-surface-tests.sh`、`tests/run-focus-timer-tests.sh` 全過；收起／放回的真機探針標為「待 Aaron」。

**乙 8 · 那一排的會話格 → 指揮頁；指揮頁不依賴遙控；返回 = 收起**（第 8 步；拍板第 2、4 條）
- 會話格點按改成走進指揮頁（NotchActivityController.swift:194-196 → WS2AppRuntime.swift:392-427 的 `openConductor`）；「過去」保留在指揮頁頭部。
- 指揮頁的 Mac 本機部分（按住說話、Codex／Claude 只讀）在遙控模式關著時也可用。
- 指揮頁開著時 iPhone 返回鍵 = 收起頁面、草稿留著；丟草稿只用頁面上的「丢弃」。
- 驗收：`tests/run-claude-conductor-tests.sh` 與相關 conductor 測試全過；有能跑的頁面探針（`tests/run-conductor-claude-page-probe.sh`）就跑，跑不了寫明原因。

**乙 9 · 用量進會話卡**（第 9 步；拍板第 7 條）
- 展開的會話卡底一行「五小時余 42% · 本周余 61%」；快用完時右耳變「剩 p%」，恢復時第 4 層提醒一次。範圍照 `docs/usage.md`。
- 先查 `main` 上有沒有可靠的用量來源。**沒有就只做視圖與模型，用 fixtures 測，不接真實來源、不發任何網路請求**，在報告裡寫明。
- 驗收：三檔假資料單元測試（充足、快用完、未知）；新字串進 xcstrings；新讀取點先登記 `tools/privacy/registry.json` 並跑 `run-privacy-page-sync.sh`。

**乙 10 · 離開期間摘要可點**（第 10 步）
- 摘要每一項是那一排的一格，點了照拍板第 15 條：窗口「回到原處」，別的桌面上的「去」（AwaySummaryController.swift；Notch.swift:1502 `showAwaySummary`）。
- 驗收：`tests/run-away-summary-tests.sh` 全過並補「點一項 → 呼叫對應的回到原處／去」的測試。

**乙 15 · 標題欄雙擊**（增補第 15 步；拍板第 17 條）
- 判斷移到事件攔截線程，不再有主線程超過 500 ms 就放行給系統（EventTapCallback.swift:51、105-118）。
- 設定加一項「照系統設定」：選了就把雙擊交給系統。
- 首次打開 A1 頁補一句：雙擊標題欄改成收起窗口（原來是縮放）。文案照 `docs/copy-guide.md`。
- 修飾鍵：程式碼是按任何修飾鍵都跳過（EventTapCallback.swift:65-74），文件只說 ⌥。**照程式碼現況改文件**，不改行為。
- 驗收：`tests/run-event-tap-tests.sh`、`tests/run-event-tap-health-tests.sh` 全過，並補「主線程卡 600 ms 時雙擊不漏給系統」的測試。

**乙 16 · 刘海張開／上推；那一排的詞**（增補第 16 步；拍板第 15、16 條）
- 刘海張開 = 展開那一排；上推 = 全部收進刘海（Notch.swift:5575-5586 的 `magnify`；516-530 的 `.back`）。啟動台開著時的「返回」行為照舊。
- 那一排裡點一格的動作名統一「回到原处」；別的桌面上的窗口叫「去」。各表面自己的動詞（展开、放回、拉出）不動。
- 驗收：所有 `tests/run-notch-*.sh` 全過；內部倉庫 `docs/notch.md`、`docs/gestures.md` 同步；新字串進 xcstrings。

**乙 17 · 排布歷史**（增補第 17 步；拍板第 20 條）
- 現況：每扇窗一格、只記外框、手動挪過就丟（TrackpadGestures.swift:943-952、2130-2147）。
- 要：本次開機內的排布歷史（最近若干步，數量自己定、寫進文件），覆蓋收起、收進刘海、側拉、畫中畫與排布；狀態列選單加「撤销 〈那一步〉」（不能撤時變灰，不隱藏）；捏合仍是手勢入口，行為照現在。
- 驗收：單元測試「收起 → 收進刘海 → 左半屏，三次撤銷依次回去」；手動挪過的窗口不再被錯撤；`./prototype/build.sh --check` 退出 0。

## 交付

| 項 | 內容 |
| --- | --- |
| 分支 | 每步一個：`zcode/integration-甲1-coordinator` 這樣命名；從**本機 `main`** 用 `git worktree add` 開，不用遠端作基底 |
| 提交 | 每步一個，訊息說清做了什麼、驗收命令與結果 |
| 驗收記錄 | 每步一頁，寫到內部倉庫 `docs/handoff/zcode-2026-10-29/<步>.md`：改了哪些檔、跑了哪些命令、退出碼、測試輸出摘要、沒跑成的與原因 |
| 總報告 | `docs/handoff/zcode-2026-10-29/README.md`：十一步各自的狀態（完成／部分／停下）、要 Aaron 真機看的清單 |

## 界線

1. **不推送、不合進 `main`、不改版號、簽名與發佈流程。** 合入由主模型審差異、重跑檢查後做。
2. **帕累托：已上線的行為不退步。** 除了本單點名要改的行為，預設值一個都不改；拿不準是不是退步，就停下來寫進報告。
3. **`./prototype/build.sh --check` 退出 0 才算那一步完成**；那一步點名的測試全過。測試與探針輸出用 ASCII。
4. **文案只走 WSL10n／xcstrings**，照 `docs/copy-guide.md` 的固定詞彙（尤其「回到原处」「去」「提示音」「撤销上次排布」）；簡體源句，繁體與英文按既有流程補。
5. **新的讀取點先登記** `tools/privacy/registry.json`，再重新生成隱私頁並跑 `run-privacy-page-sync.sh`。
6. **不發真實模型請求、不發網路請求**；Claude 相關測試用 `tests/fixtures/fake-claude.py`。
7. **動到主線程隔離或並發的地方**（甲 1 尤其），在報告裡標出，列入「要真機探針」清單：曾經有 `@MainActor` 類別裡的 Mutex 在主線程外被碰到而崩潰。
8. **不在本單：** 第 5 步（認你搬進刘海宿主）、第 6 步（代填密碼與聲紋，涉及安全，要真機與主模型）、第 11 步（新表面換皮）、第 12 步（設定兩頁與露出）、增補第 13、14 步（代理先動與描邊代理，設計密集，要先做小樣給 Aaron 看）、第 18 步（觸控 MacBook Pro 真機調研，11 月 6 日後）。碰到這些範圍就停，寫進報告。
9. 行號對不上、某步的前提不成立（例如找不到用量來源、預設不是關）：**不要猜，寫進報告，接著做下一步。**
