# HANDOFF：把 WindowShade 的島做到與系統 CampoUI 一比一

> 寫於 2026-11-09。給下一個 session 直接接手，不必重跑已完成的部分。

## 一、最終目標（不要偏離）

WindowShade 自己的島／實時活動，**尺寸與動畫彈簧都要與 macOS 27 在 PROLED MacBook Pro 上的
系統靈動島（內部代號 Campo／Jindo）一比一**；在任何機型上都要接近原生體驗。
有系統島的機型（PROLED）讓位，不與系統打架。

## 二、已完成（分支 `feat/system-island`）

| commit | 內容 |
|---|---|
| `89242d26` | 島機讓位（`MGCopyAnswer("DeviceSupportsDynamicIsland")`）、幾何單一來源、變形容器只脹不縮 |
| `2c0e3061` | Mac 島底座參數集與常數掃描（文件） |
| `bbd49a0c` | 尺寸成為動畫量、貼頂兩個自由度 |
| `fdf0cfcf` | HANDOFF（本文件） |
| `57011fd9` | 接上 27.3 Mac 島的兩組彈簧（`islandPrompt`／`islandSizing`） |
| `c08dc665` | 27.3 島彈簧證據、映射與 27.2 否證（文件） |

**2026-11-09 追加（已提交）**：`f0926fd1` 島的六態模型
（`Core/IslandMotionState.swift`）、活動令牌（`Core/NotchActivityMotion.swift`）、
落點幾何單一來源；`89dc8a06` `MorphRetarget`／`Motion.spring`／活動映射測試、
`--island-transition-probe`、`FrameRhythmProbe` 接線與 CI 快速 runner。
`.hidden` 的追蹤結論見 §三末；完整現狀與真機 backlog 見
`docs/reverse-engineering/island-parity-plan.md`；27.3 的 Swift 型別模型
（`ResultPlatterBehavior`／`WindowSizingAnimation`／`MacIslandCutoutGlassGeometry`）
見 `docs/reverse-engineering/mac-island-types.md`。

關鍵檔案：
- `prototype/Core/SystemIsland.swift` — 能力判斷（三態，問不到不當有島；`Notch.systemIsland` 可覆寫）
- `prototype/Core/IslandMetrics.swift` — 幾何單一來源：本體 36、圓角 18（＝高/2）、最小 36²、
  無劉海膠囊展開 230×64（`capsuleExpandedSize`）、劉海展開上限 408／外接 371／高 160、
  落點小島 340×84（`dropIslandSize`）、`expandedWidth(hasNotch:availableWidth:contentWidth:)`
  （沒有內容排時 408／371，有內容時內容優先）
- `prototype/App/Notch.swift` — `SlotKind`（notch / systemIsland / virtual）、`containerFloor`
- 測試：`tests/run-island-metrics-tests.sh`、`tests/run-system-island-tests.sh`、capsule / display-shape

驗證：`./build.sh --check` EXIT=0（編譯＋2700 鍵本地化＋隱私登記 759 lexical sites＋文案）；四組測試綠。

## 三、缺口現狀（selector 路徑已關閉）

**每個轉場的彈簧參數**（damping / response）。原本假設 Mac 島會在 CampoUIInternal 裡呼叫
`setDampingRatio:`／`setResponse:`。2026-11-09 的完整掃描否證了這個假設：

- CampoUIInternal 的 `__TEXT,__objc_methname` size = 0；selector 只在 dyld 共享池
  （`setDampingRatio:` `0x1f481b6a0`、`setResponse:` `0x1f5389ca0`）。
- 2,500 個 `__objc_selrefs` 沒有一筆指向它們；1,917 個 `_objc_msgSend$…` stub 也沒有。
- 4,115 個 split 映像的 `adrp+add` 掃描 0 命中。
- 二進位內沒有 iOS SpringBoard 的 0.574／0.39／1.2／1.1／0.92／0.24／0.255／0.289。

島的底座動畫是 SwiftUI `Animation`：`SiriGlassBackdrop` 的 body 是
`.animation(Animation?, body:)`，形狀（`drawnPlatterSize`、`pinsTopPlatterWidth/Height`）
是 `AnimatableData`；`_windowAnimation` 由 Spotlight 的 `WindowSizingAnimation` 傳入。

真正的 Mac 候選來源已寫在 `docs/reverse-engineering/mac-island-springs.md`：

- `WindowManager.WindowSpringBehavior` 預設 `(damping 1.0, response 0.38)` 與
  `(1.0, 0.30)`（`0x1d2aa5758`／`0x1d2aa5794`）；
- SpotlightUIInternal 另有 `(0.4, 0.7)`／`(0.2, 0.7)`／`(0.2, 1.0)`／`(0.5, 1.0)`
  四個已解出的 `Animation.spring` token。

selector 路徑不再是唯一選項：27.3 的 `MacAssistantIslandSessionModel` 自己就有
明確的島彈簧，且已接進 `Motion.notchSpring`（見下）。

**27.3 beta 已複核（2026-11-09）**：從 `SharedSupport.dmg` 的 AEA 資產解出
`cryptex-system-arm64e`（RIDIFF10），用 `ipsw ota patch rsr --cryptex` 套成
2.7 GB APFS 映像，拆出 27.3（26C5035r）的 dyld cache。結果：

- 27.3 `CampoUIInternal` 仍然沒有 `setDampingRatio:`／`setResponse:` 參照
  （2,537 個 selrefs、1,947 個 stub、全 4,142 映像掃描皆 0）。
- 仍然沒有 AnimationKit 依賴；`SiriGlassBackdrop` 的 body 仍是
  `.animation(Animation?, body:)`。
- **但** `MacAssistantIslandSessionModel.swift` 有島自己的兩組彈簧：
  `(response 0.408, damping 0.27)` 與 `(response 0.3571428536916519,
  damping 0.7500006097576885；原 mass 2.0 / stiffness 619.0216 / damping 52.7788)`。
- `#islandSizing`（`0x2653ee080`）的 jump table 已對到狀態，且由呼叫點的 log
  字串直接證得：tag 0 `.siri(.listening)`、1 `.siri(.thinking)`、2 `.siri(.response)`、
  3 `.siri(.transient)`、4 `.hidden`、5 `.prompt`；0／5 用 0.408／0.27，
  1–3 用 0.3571／0.75，4 不跑尺寸動畫。
- 已接進 `Motion.notchSpring`：`.interaction` → `islandPrompt`（0.408／0.27），
  其餘形狀 → `islandSizing`（0.3571／0.75）；`.minimum` 因我們沒有另一個
  window 動畫承接收合，仍用 `islandSizing`。

產物在 `/Volumes/TiPlus 7100/tmp273/`（映像與 `split273/`），詳見
`mac-island-springs.md` §7。selector 那條路已確認在 27.2／27.3 都不存在，
不再追。

**`.hidden` 的收合（2026-11-09 已釘死）**：27.3 的 `#islandSizing` 在 tag 4
直接 return；收合由外層 window sizing 的默認動畫承接。`WindowSizingAnimation.default`
（`0x22f9efc10`）兩軸都用 `AxisAnimation.default`，後者初始化器
（`0x22f9ef4bc`）用 `Spring(duration: 0.3, bounce: 0.2)` 經
`Animation.spring(_:blendDuration:)` 建出動畫。WindowShade 已落
`islandHidden`（response 0.3／dampingRatio 0.8），`.hidden` 不再借用
`islandSizing`；WindowManager 的 0.38／0.30 仍不用（見 §7.6）。

**ActivityKit（2026-11-09）**：27.3 `CampoUIInternal` 直接連結
`/System/Library/Frameworks/ActivityKit.framework`，並有
`CampoUILiveActivityController`、`LiveActivityMonitoring`、
`LiveActivityRequestMonitor`、`LiveActivityPresentationWatcher`，以及
`didStartLiveActivity`／`canStartLiveActivity`／`awaitingLiveActivity` 狀態。
系統島是 ActivityKit 的消費端。但 macOS SDK 的 `Activity`／`ActivityAuthorizationInfo`
全部標了 `@available(macOS, unavailable)`：能 `import ActivityKit`，不能在 macOS 上
發或收 Live Activity（不是 entitlement 問題）。WindowShade 的骨架
`Core/ActivityKitBridge.swift` 只做運行時探測＋讓位策略（預設 `.inAppOnly`，
真機 spike 才切 `.yieldToSystem`）；探針 `--activitykit-probe`。見
`docs/live-activities.md` 與 C06。

### 已經失敗的路（不要重複）

- **Ghidra `-process`**：這台機器載入這個 9 MB Swift 二進位超過 9 分鐘無輸出；中斷會留下
  `/Volumes/TiPlus 7100/ghidra_proj/CampoUI.lock`，下次會一直等鎖，要先 `rm`。
- **PyGhidra**：未啟用（`Ghidra was not started with PyGhidra`），Python 腳本不可用；Java 腳本可編譯但同樣卡在 `-process`。
- **stub 符號**：`CampoUIInternal` 是 strip 過的，`objc_msgSend$setDampingRatio:` 符號 0 筆，
  模擬器 SpringBoard 那招（objdump 直接標 selector）在 Mac 上用不了。
- **常數掃描**：整檔沒有 iPhone 的 36.6667／18.3333／125／94.6667，也沒有相鄰的底座 `CGSize`
  → 底座尺寸是執行時由承載視窗算出（`drawnPlatterSize` 屬 `AnimatableData`），不是常量表。

## 四、素材位置（外接碟 `TiPlus 7100`，勿重下）

| 素材 | 路徑 |
|---|---|
| macOS 27.2 IPSW（26B123） | `/Volumes/TiPlus 7100/ws-macos-27.2/UniversalMac_27.2_26B123_Restore.ipsw` |
| 27.2 SystemOS（唯讀掛載） | `/Volumes/TiPlus 7100/mnt272`（dyld cache 在 `System/Library/dyld/`） |
| 27.2 拆分映像（4,115 個） | `/Volumes/TiPlus 7100/mac272_split/` |
| Ghidra 專案（已匯入） | `/Volumes/TiPlus 7100/ghidra_proj`（`CampoUI:/CampoUIInternal`） |
| 27.3 beta 安裝器＋解密資產 | `/Volumes/TiPlus 7100/ws-macos-27.3/`（AEA → `payloadv2`；已用 `ipsw ota patch rsr --cryptex` 解出） |
| 27.3 系統映像（已解） | `/Volumes/TiPlus 7100/tmp273/cryptex-system-arm64e.dmg`（2.7 GB APFS） |
| 27.3 拆分映像（4,142 個） | `/Volumes/TiPlus 7100/tmp273/split273/` |
| iOS 27.3b1 拆分映像 | `/Volumes/TiPlus 7100/ios_split/`（含模擬器版 SpringBoard 符號表） |

## 五、工程注意事項

- `build.sh --check` 一次約 12–15 分鐘；549 個 Swift 檔、`-O -whole-module-optimization`。
- 建置有硬門檻：本地化鍵（`Resources/Localizable.xcstrings`，中文源句必須逐字一致）、
  隱私登記（`tools/privacy/registry.json`，任何 `UserDefaults` 讀取都要登記）、文案檢查。
- 測試執行器多數不是可執行檔，用 `bash tests/run-xxx.sh`。
- 測試檔改動常需要同步更新 runner 的編譯檔案清單（例如新增 `Core/IslandMetrics.swift`）。
- 不要同時跑兩個 build（會互相搶 CPU 且日誌難判）；背景建置請在**同一個 turn 內**輪詢到 `EXIT=`。

## 六、完成判準

1. `Motion.notchSpring` 的每個轉場數值都能指回**一個已證實的 Mac 二進位來源**
   （檔案、位址、值）；若來源只到 `WindowManager`／`SpotlightUIInternal` 而不是
   `CampoUIInternal` 的 selector，文件必須逐條寫清楚，不能假裝是 selector 配對。
   `.minimum`（hidden）已不是例外：27.3 tag 4 不跑島自己的尺寸動畫，
   收合由 `WindowSizingAnimation.default` 的 `Spring(0.3, bounce 0.2)` 承接，
   已落成 `islandHidden`（見 §三末與 `mac-island-springs.md` §7.6）。
2. `IslandMetrics` 的尺寸與圓角全部由同一條模型推出，且以動畫量插值。
   目前 36／18／36² 已收斂；230×64 只給無劉海膠囊（`capsuleExpandedSize`）；
   340×84／22 已收斂到 `dropIslandSize`，`StripNotchExchange`／`FileDragSensor`／
   `Notch.dropZone` 都改成引用；408／371 已接進 `legacyBaseTarget()` 的展開寬度
   （`expandedWidth(hasNotch:availableWidth:contentWidth:)`，沒有內容排時 408／371），
   160 約束單層內容高度；多窗口 shelf 刻意可以超過 408（見 `island-metrics.md` §8）。
3. `./build.sh --check` EXIT=0（2026-11-09 05:31）；快速測試全綠：
   island-metrics、capsule-shape、display-shape、system-island、notch-token、
   motion-tokens、island-motion-state（C02 79）、notch-activity-motion（C03 22）、
   island-transition（C04 31／C05 47）、file-drag、strip-notch-exchange、motion-lint。
   真機轉場探針：`WindowShade --glance-probe --island-transition-probe`（需真劉海屏）。
4. 文件更新：`docs/reverse-engineering/island-metrics.md`、`mac-island-platter.md`、
   `mac-island-springs.md`、`island-parity-plan.md` 與設計系統 §4.6.1。
