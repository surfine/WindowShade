# 島與實時活動：一比一追趕計畫與現狀（2026-11-09）

> 目標：WindowShade 的島與實時活動在**尺寸與動畫彈簧**上對齊 macOS 27 的系統島
> （Campo／Jindo），不靠「差不多」。本文件是 `HANDOFF-campo-parity.md` 之後的
> 工作現狀與下一步；證據細節在 `mac-island-springs.md`、`island-metrics.md`。

## 0. 一句話現狀

27.3 的兩組島彈簧已證得並接進 `Motion.notchSpring`；島的彈簧現在由
「狀態 ＋ 方向」決定，不再由形狀猜。幾何的落點小島已收成單一來源；`.hidden`
的收合由誰承接仍未證得，保留 `islandSizing` 並列為真機 backlog。實時活動已標上
六態，系統島的 ActivityKit 消費端已在 27.3 二進位中確認。

## 1. 狀態表

| 項目 | 結論 | 狀態 | 證據 |
|---|---|---|---|
| 27.3 島的 listening／prompt 彈簧 0.408／0.27 | 已接進 `islandPrompt` | **proven** | `mac-island-springs.md` §7.3／§7.4 |
| 27.3 島的 thinking／response／transient 彈簧 ≈0.3571／0.75 | 已接進 `islandSizing` | **proven** | 同上（mass 2.0 / stiffness 619.0216 / damping 52.7788） |
| 六態 tag 0–5 → `.listening/.thinking/.response/.transient/.hidden/.prompt` | 已證，`IslandMotionState.systemTag` | **proven** | 呼叫點 log 字串，§7.4 |
| `.hidden` 不跑島自己的尺寸動畫 | 已證（tag 4 直接 return） | **proven** | §7.4 |
| `.hidden` 的收合由外層 window sizing 承接 | 型別鏈成立，具體彈簧未釘死 | **provisional** | §7.6 |
| 島的 `_windowAnimation` 是 `SpotlightUIShared.WindowSizingAnimation?` | `_symbolic` 相鄰可讀，未逐欄位解析 | **inferred** | §7.6 第 3 點 |
| WindowManager `SpringBehavior` 預設 response 0.38／0.30、damping 1.0 | 已讀出 accessor | **proven（值）／未接（用途）** | §7.6 第 4 點 |
| 無劉海膠囊展開 230×64 | WS2 設計值，不是 Mac 系統島值 | **provisional** | `island-metrics.md` §8 |
| 落點小島 340×84／22 | WS2 `DropIsland`，已收單一來源 | **provisional（血緣）** | `IslandMetrics.dropIslandSize` |
| 劉海／外接展開上限 408／371、高 160 | Aaron #29/#83；shelf 內容排可超 408 | **provisional（產品決定）** | `island-metrics.md` §8 |
| 13 種實時活動 → 六態 | 已接進 `resolve`：錄音／等你的會話用 `islandPrompt`，其餘按種類 | **inferred（語義）** | `Core/NotchActivityMotion.swift`、C02-06／C03 |
| macOS 27.3 系統島消費 ActivityKit | 已證（連結＋Controller＋Watcher） | **proven（基礎設施）** | `docs/live-activities.md` |
| macOS 第三方發／收 Live Activity | SDK 的 Activity API 標了 `@available(macOS, unavailable)` | **blocked（API 未開放）** | `Core/ActivityKitBridge.swift`、C06 |
| 系統島呈現時抑制重複耳朵 | 策略已落地，預設 `.inAppOnly` | **provisional** | `ActivityKitBridge.shouldPublishOwnEars` |
| `drawnPlatterSize`／`pinsTopPlatterWidth/Height` 執行時值 | 需要真機或 runtime | **blocked** | `mac-island-platter.md` §5 |

## 2. 已落地的改動（`f0926fd1` 程式／`89dc8a06` 測試與探針）

- **六態模型**：`Core/IslandMotionState.swift`；`Motion.notchSpring(for:transition:)`
  以狀態取令牌，`notchSpring(for shape:)` 只留作 shape adapter。
  `Notch.swift` 的 `spring()` 改走狀態，並用 assert 守住 `motionShape()` 的等價性。
- **幾何單一來源**：`dropIslandSize`／`dropIslandRadius` 收斂
  `StripNotchExchange`、`FileDragSensor.FileDropGeometry`、`Notch.dropZone`；
  新增 `expandedMaxWidth(hasNotch:)` 與 shelf 例外說明。
- **活動狀態**：`Core/NotchActivityMotion.swift` 把 13 種活動標成
  thinking／response／transient／prompt，並在 `NotchController.motionState()` 的緊湊分支
  用撐起兩耳的那條活動覆蓋：錄音、等你的編程會話 → `islandPrompt`（0.408／0.27），
  其餘仍 `islandSizing`；排序與三件上限不動。
  幾何不需要另改：最小形走 `IslandMetrics.minimalSize`，耳朵／展開排走劉海寬與
  `NotchRow` 的內容寬，活動卡高 142 是內容高（≤`expandedMaxHeight` 160），
  沒有再寫一份 230／340。
- **驗證**：`MorphRetarget` 與 `Motion.spring` 的測試（C04／C05）、
  `FrameRhythmProbe` 接進 `main.swift`、`run-system-island-tests` 不再假設本機
  一定不是島機、`run-motion-lint` 增加「島的彈簧只能來自令牌」、CI 加六個快速 runner。

## 3. 測試與驗證

| 層級 | 指令 |
|---|---|
| 六態 | `bash tests/run-island-motion-state-tests.sh` |
| 活動映射 | `bash tests/run-notch-activity-motion-tests.sh` |
| 接力／彈簧 | `bash tests/run-island-transition-tests.sh` |
| 幾何 | `bash tests/run-island-metrics-tests.sh`、`run-capsule-shape-tests.sh`、`run-display-shape-tests.sh`、`run-system-island-tests.sh` |
| 令牌 | `bash tests/run-notch-token-tests.sh`、`run-motion-tokens-tests.sh`、`run-motion-lint.sh` |
| 合併 | `cd prototype && ./build.sh --check`（EXIT=0 才算過） |
| 真機轉場 | `prototype/build.sh --stage` 後執行 `WindowShade --glance-probe --island-transition-probe`（需真劉海屏） |

2026-11-09 05:31：`build.sh --check` EXIT=0（含活動令牌與轉場探針），上面十二個快速
runner 全綠（C01 80、C02 79、C03 22、C04 31、C05 47 條斷言；StripNotchExchange 90 條）。

## 4. 真機 backlog（依證據種類排序）

1. **hidden 收合**：PROLED MacBook Pro 上對 `.hidden` 轉場取樣。若收合不彈
   （dampingRatio ≈ 1.0），新增 `islandHidden = (0.38, 1.0)` 並把 `.hidden` 指過去；
   目前不改（見 `mac-island-springs.md` §7.6）。
2. **`drawnPlatterSize` / `pinsTopPlatterWidth/Height`**：執行時讀值。需要能注入
   的 metrics 介面；目前 `IslandMetrics` 已預留常數位置。
3. **ActivityKit**：用簽名構建發一條 Live Activity，確認是否出現在系統島；
   若會，新增 ActivityKit 來源並在系統島讓位時抑制重複耳朵（Aaron #39）。
4. **PROLED 讓位實測**：`run-system-island-tests` 已能在 raw=1 的機器上跑；
   仍需在真機確認 `SlotKind.systemIsland` 與面板不畫。

## 5. 非目標

- 不重寫 `Notch.swift` 的 `NotchCanvasView`：additive 五軸接力與 `MorphRetarget`
  保留，只換令牌來源。
- 不放寬 §4.6 的 Mac bounce 上限：`islandPrompt`／`islandSizing` 是 §4.6.1
  的具名例外，只准用在島。
- 不在本輪改發布路徑、認證、指揮頁與設定。
