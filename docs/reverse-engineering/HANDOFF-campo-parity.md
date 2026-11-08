# HANDOFF：把 WindowShade 的島做到與系統 CampoUI 一比一

> 寫於 2026-11-09。給下一個 session 直接接手，不必重跑已完成的部分。

## 一、最終目標（不要偏離）

WindowShade 自己的島／實時活動，**尺寸與動畫彈簧都要與 macOS 27 在 PROLED MacBook Pro 上的
系統靈動島（內部代號 Campo／Jindo）一比一**；在任何機型上都要接近原生體驗。
有系統島的機型（PROLED）讓位，不與系統打架。

## 二、已完成（分支 `feat/system-island`，三筆 commit）

| commit | 內容 |
|---|---|
| `89242d26` | 島機讓位（`MGCopyAnswer("DeviceSupportsDynamicIsland")`）、幾何單一來源、變形容器只脹不縮 |
| `2c0e3061` | Mac 島底座參數集與常數掃描（文件） |
| `bbd49a0c` | 尺寸成為動畫量、貼頂兩個自由度 |

關鍵檔案：
- `prototype/Core/SystemIsland.swift` — 能力判斷（三態，問不到不當有島；`Notch.systemIsland` 可覆寫）
- `prototype/Core/IslandMetrics.swift` — 唯一幾何來源：本體 36、圓角 18（＝高/2）、最小 36²、展開 230×64、貼頂 340×84、`interpolate(from:to:progress:)`
- `prototype/App/Notch.swift` — `SlotKind`（notch / systemIsland / virtual）、`containerFloor`
- 測試：`tests/run-island-metrics-tests.sh`、`test/run-system-island-tests.sh`、capsule / display-shape

驗證：`./build.sh --check` EXIT=0（編譯＋2700 鍵本地化＋隱私登記 759 點＋文案）；四組測試綠。

## 三、還沒做（唯一缺口）

**每個轉場的彈簧參數**（damping / response）。系統用共用的
`AnimationKit.SpringAnimationBehaviorSettings(dampingRatio:response:)`。
已知 iOS 側量到 response **0.574** 與一組 damping（0.39／1.2／1.1／0.8／0.92／0.24／0.255／0.289），
但**哪個 damping 對哪個轉場，Mac 側還沒配對出來**。現階段我們仍用自己的 `calm` 令牌。

### 建議做法（純 objdump，不需 Ghidra、不需真機）

1. 從 `__objc_methname` 取 `setDampingRatio:`、`setResponse:` 的字串位址；
2. 掃 `__text`，找 `adrp x1, page` + `add x1, x1, #imm` 解出指向那兩個位址的呼叫點；
3. 每個呼叫點往回找最近一次 `adrp + ldr dN` 的常數 →「selector = 值」配對；
4. 把配對寫進 `Motion.notchSpring` 的單一出口，跑完整 build 與測試。

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
| 27.3 beta 安裝器＋解密資產 | `/Volumes/TiPlus 7100/ws-macos-27.3/`（AppleArchive 索引層未解，系統卷未取出） |
| iOS 27.3b1 拆分映像 | `/Volumes/TiPlus 7100/ios_split/`（含模擬器版 SpringBoard 符號表） |

## 五、工程注意事項

- `build.sh --check` 一次約 12–15 分鐘；549 個 Swift 檔、`-O -whole-module-optimization`。
- 建置有硬門檻：本地化鍵（`Resources/Localizable.xcstrings`，中文源句必須逐字一致）、
  隱私登記（`tools/privacy/registry.json`，任何 `UserDefaults` 讀取都要登記）、文案檢查。
- 測試執行器多數不是可執行檔，用 `bash tests/run-xxx.sh`。
- 測試檔改動常需要同步更新 runner 的編譯檔案清單（例如新增 `Core/IslandMetrics.swift`）。
- 不要同時跑兩個 build（會互相搶 CPU 且日誌難判）；背景建置請在**同一個 turn 內**輪詢到 `EXIT=`。

## 六、完成判準

1. `Motion.notchSpring` 的每個轉場數值都能指回 `CampoUIInternal` 的某個 `setDampingRatio:`／`setResponse:` 配對；
2. `IslandMetrics` 的尺寸與圓角全部由同一條模型推出，且以動畫量插值；
3. `./build.sh --check` EXIT=0、四組測試綠；
4. 文件更新：`docs/reverse-engineering/island-metrics.md` 與 `mac-island-platter.md`。
