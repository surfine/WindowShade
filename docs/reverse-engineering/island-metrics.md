# 系統靈動島的量法（Apple 自己的度量模型，iOS 27.3b1 實證）

> 目的：把「我們的島」畫成系統島的一比一複刻，先要知道 Apple 量什麼、怎麼算。
> 來源：iOS 27.3b1（24C5037i，iPhone19,2）dyld shared cache。
> 取法：`ipsw class-dump` 拿介面、`ipsw dyld disass` 拿指令、`ipsw dyld dump --size N -b` 拿常數。

## 1. Apple 的兩個度量類

### `SAUILayoutMetrics`（SystemApertureUI）——八個尺寸

```
CGSize _minimumExpandedSize, _maximumExpandedSize
CGSize _minimumMinimalSize,  _maximumMinimalSize
CGSize _minimumCompactSize,  _maximumCompactSize
CGSize _maximumHorizontalMinimalViewSize
CGSize _maximumLeadingTrailingViewSize
```

每個狀態都是 **min/max 一對**：內容只在這段區間裡長，超出就換狀態。這正是我們缺的——
今天我們的島每個樣子各自寫死一組數字，狀態之間沒有共同的上下界，過渡自然會跳。

### `SBUISystemApertureLayoutMetrics`（SpringBoardUIServices）——實際算法

比八個尺寸更細，多出來的是形狀與留白：

| 屬性 | 意義 |
|---|---|
| `sensorRegionSize` | 島的「感測器區」本體尺寸（膠囊的基準） |
| `interSensorRegionInWindowSpace` | 島在視窗座標裡的位置 |
| `minimumScreenEdgeInsets` | 離螢幕邊的最小留白 |
| `minimumCompactSize` / `maximumCompactSize` | 緊湊（兩耳／膠囊） |
| `minimumMinimalSize` / `maximumMinimalSize` | 最小（一顆圓／小膠囊） |
| `maximumHorizontalMinimalViewSize` | 最小形旁邊還能放多寬的內容 |
| `maximumLeadingTrailingViewSize` | 左右兩耳的內容上限 |
| `compactConcentricAreaSize` | 緊湊狀態的同心圓區域（圓角＝同一個圓心） |
| `minimumMicroNoticeSize` / `maximumMicroNoticeSize` | 微提示（比最小再小一級） |
| `minimumExpandedSize` / `maximumExpandedSize` | 展開 |
| `maximumPossibleSizeWhilePresentingMenu` | 展開時開選單能長到多大 |
| `minimumContinuousCornerRadius` / `maximumContinuousCornerRadius` | 連續圓角的上下限 |
| `displayCornerRadiusIgnoringZoom` | 螢幕本身的圓角（島要和它同心） |

## 2. 已經解出來的常數（真的數字）

從 `SpringBoardUIServices` 的 `__const` 區（0x1a8572280 起）讀出，並對上反編譯裡的 `adrp/ldr`：

| 常數 | 值（pt） | 用在哪 |
|---|---|---|
| sensor 高度 | **36.6667** | 島本體高度；緊湊／最小的基準 |
| sensor 寬度 A/B/C | **94.6667 / 125.0 / 125.3333** | 依機型（ProductType 分支）三選一 |
| 最小連續圓角 | **18.3333** | `= sensorRegionSize.height × 0.5`（反編譯直接看到 `fmul d0, d1, 0.5`） |
| 最小形 | **36.6667 × 36.6667** | 正方形＝一顆圓 |
| 最小形旁邊的橫向內容 | **45.0** | `maximumHorizontalMinimalViewSize` |
| 微提示 | **185.3333 × 66.6667** | `minimumMicroNoticeSize` |
| 微提示增量 | **−66.6667** | `maximumMicroNoticeSize` 的差值 |
| 其餘表值 | 45.0 / 66.6667 / 29.6667 / 38.3333 / 32.3333 / 4.6667 / −73.3333 / 185.3333 | 未逐條對上屬性 |

**最重要的一條規則**：膠囊狀態的圓角就是高度的一半（`minimumContinuousCornerRadius = height / 2`）。
我們今天的 `NotchCapsule` 已經是 `height/2`，這一條是對的；錯的是展開／提醒／落點各自寫死
28 / 24 / 22 三個半徑——狀態一換，圓角就跳，這是「動畫不對」最可能的來源。


## 2.5 算法（反編譯已完整解出）

`bl` 到 0x1b00xxxx 的位置都是 **帶 selector 的 objc_msgSend stub**，反編譯會把 selector 標在旁邊，
所以算法可以逐條讀出來：

| getter | 實作 | 值 |
|---|---|---|
| `inertSize` | 島的基準尺寸（本體） | `CGSize(w, 36.6667)` |
| `sensorRegionSize` | 先用 `effectiveArtworkSubtype` 分流（2556/2622/2736/2796/2868），再用 `screenPixelWidthIsEven` 二選一 | 寬 94.6667 / 125.0 / 125.3333，高 36.6667 |
| `minimumCompactSize` | 尾呼叫 `inertSize` | 與本體同尺寸 |
| `maximumCompactSize` | `(deviceWidth − 73.3333, inertSize.height)` | 螢幕寬減 2×36.667 |
| `minimumMinimalSize` | `CGSize(inertSize.height, inertSize.height)` | 36.6667 × 36.6667（圓） |
| `minimumContinuousCornerRadius` | `inertSize.height × 0.5` | 18.3333 |
| `maximumHorizontalMinimalViewSize` | 常數 | 45.0 |
| `maximumPossibleSizeWhilePresentingMenu` | `d0 + d0`（兩倍） | 依 base 算 |
| `maximumExpandedSize` | 兩次 `maximumWidth` 打包成 CGSize | 依螢幕算，不是常數 |

重點：
1. **所有尺寸都從 `inertSize`（本體）推出來**，不是各狀態各自寫死。
2. 緊湊最寬 = 螢幕寬 − 2 × 本體高；最小 = 本體高見方；圓角 = 本體高的一半。
3. 展開寬度是螢幕算出來的（`maximumWidth`），所以沒有單一常數可以直接抄。


## 2.6 動效常數（SpringBoard 的設定類）

iOS 27.0 模擬器 runtime 的 `SpringBoard` **帶完整本機符號表（162,083 筆）**，
所以可以直接按方法名反組譯（`xcrun llvm-objdump --start-address`）：

| 方法 | 位址 |
|---|---|
| `-[SBSystemApertureSettings setDefaultValues]` | `0x71fea0` |
| `-[SBSystemApertureTransitionSettings setDefaultValues]` | `0x6022f4` |
| `-[SBSystemAperturePulseSettings setDefaultValues]` | `0x69cb0c` |
| `-[SBSwitcherSystemApertureSettings setDefaultValues]` | `0x32abe4` |

寫法固定是「每個 child behavior 一個設定物件」：

```
ldr  d11, [x8, #0x200]      ; 共用的 response
...
bl   _objc_msgSend$setDampingRatio:
ldr  d12, [x8, #0x2c8]      ; 這個 behavior 的 damping
mov.16b v0, v11
bl   _objc_msgSend$setResponse:
```

`__const`（0xa68ef0 起）讀出來的值：

| 位址 | 值 | 候選用途 |
|---|---|---|
| 0xa69200 | **0.574** | 共用 `response`（彈簧時間常數） |
| 0xa692c8 | 0.02 | 第一個 behavior 的 `dampingRatio`（候選） |
| 0xa693c8–0xa693f8 | 0.39 / 1.2 / 1.1 / 0.8 / 0.92 / 0.24 / 0.255 | 各段轉場的 response / damping 候選 |
| 0xa69400– | 0.24 / 0.289 | 同上 |

證據檔：`macos27/evidence/aperture-settings.txt`、`switcher-aperture-settings.txt`
（暫存在分析工作區，未進倉庫）。

**注意（誠實標註）**：上面「候選」欄位是靠每段 `ldr dN → mov v0,dN → msgSend` 的相鄰關係推的，
還沒逐個 behavior 對上名字（`setChildBehaviorSettingsNamePrefix:` 會給名字，但字串在 x2）。
再看一輪就能把「哪個轉場用哪一組彈簧」釘死。

**Mac 27.2 不適用（2026-11-09 補）**：同一組 0.574／0.39／1.2／1.1／0.92／0.24／0.255／0.289
在 `CampoUIInternal` 裡完全不存在；這顆二進位也沒有任何 `setDampingRatio:`／`setResponse:` 呼叫。
Mac 島的底座動畫是 SwiftUI `Animation`，由 Spotlight 的 `WindowSizingAnimation` 傳入。
完整證據與真正的 Mac 候選來源見 `docs/reverse-engineering/mac-island-springs.md`。


## 7. macOS 27.2（PROLED 機型出貨版）的島本體

- 已下載 `UniversalMac_27.2_26B123_Restore.ipsw`（24 GB）到外接碟，SystemOS DMG 已用
  `ipsw mount sys --device Mac17,4` 掛在 `/Volumes/TiPlus 7100/mnt272`，27.2 的 dyld cache 可直接讀。
- 島相關字串在 27.2 的分佈（`ipsw dyld str`）：

| 映像 | 字串數 | 判斷 |
|---|---|---|
| `WidgetKit` | 37 | 島的內容 API（`DynamicIsland`／compact layout／expanded region） |
| **`CampoUIInternal`** | 22 | **macOS 島的宿主 UI**（另有 `MacAssistantIslandSessionModel`） |
| `AgentCanvasUICore` / `AgentCanvasUI` | 18 / 5 | 島上的代理畫布 |
| `AssistantIslandClient` | 6 | 島的客戶端模型 |
| `SpotlightUIInternal` | 6 | Spotlight 在島上的入口（`IslandSearchResultsHostingView`） |
| `libMobileGestalt` | 1 | `DeviceSupportsDynamicIsland` 這個能力鍵 |

- ~~動效引擎是全系統共用的 **`AnimationKit`**：`SpringAnimationBehaviorSettings(dampingRatio:response:)`，
  iOS 的 `setDampingRatio:`/`setResponse:` 也是同一組語意，所以 iPhone 上量到的彈簧值可以直接當 Mac 的起點。~~
  **2026-11-09 否證**：CampoUIInternal 沒有 `AnimationKit` 依賴，也沒有任何
  `setDampingRatio:`／`setResponse:` 呼叫；Mac 島的形狀動畫是 SwiftUI `Animation`
  （外層 `WindowSizingAnimation` 傳入）。見 `mac-island-springs.md`。
- 下一步（未完成）：把 `CampoUIInternal` 從 27.2 cache 抽出來，讀它的尺寸／彈簧常數。
  `ipsw dyld extract` 在 macOS cache 上會失敗（symbol remap），要用 `ipsw dyld split`（會花幾分鐘、輸出數 GB）。
- **27.3 beta 已拆（2026-11-09 補）**：`SharedSupport.dmg` → AEA → `payloadv2` →
  `ipsw ota patch rsr --cryptex` → 2.7 GB APFS → `ipsw dyld split`。
  27.3 的 `CampoUIInternal` 仍然沒有 selector／AnimationKit，但多了
  `MacAssistantIslandSessionModel` 自己的彈簧 token（`(0.408, 0.27)`、
  `(≈0.3572, 0.75)`）。產物與細節見 `mac-island-springs.md` §7。


### 27.2 的島參數名（CampoUIInternal，Swift 反射欄位）

`ipsw dyld split` 拆出 4,115 個映像（6.5 GB，`/Volumes/TiPlus 7100/mac272_split`）後，
從 `CampoUIInternal` 的 `__swift5_reflstr` 讀到 Mac 島的實時活動參數名：

```
activityContentDefaultSize        activityContentHorizontalInset
activityCornerRadius              activityMaxContentHeight
activityThinkingMaxTextWidth      drawnPlatterSize
drawsGlassPlatter                 activityContentWidth
```

**決定性否定**：把 `CampoUIInternal` / `WidgetKit` / `AssistantIslandClient` / `SpotlightUIInternal`
整檔掃過 8-byte double，**沒有** iOS 那組 36.6667 / 18.3333 / 125.0 / 94.6667；
`CampoUIInternal` 只有 `36.0` 出現 3 次。→ **Mac 的島不是照抄 iPhone 的尺寸**，是另一組。

**27.3 已補上（2026-11-09）**：`drawnPlatterSize` 本身仍是執行時由承載視窗算出的
`AnimatableData`，靜態常數掃描讀不到；但 27.3 的系統卷已拆出
（`/Volumes/TiPlus 7100/tmp273/cryptex-system-arm64e.dmg` 與 `split273/`），
`MacAssistantIslandSessionModel` 的兩組島彈簧已取到，見 `mac-island-springs.md` §7。
不需要再用 Ghidra 開 `CampoUIInternal`。


## 8. 已按預設採用的幾何與動效（可一處改回）

2026-11-08 拍板前先照以下預設實作，全部集中在 `Core/IslandMetrics.swift`：

| 項目 | 採用 | 改回的位置 |
|---|---|---|
| 本體高／圓角 | 36 ／ 18（＝高/2） | `IslandMetrics.inertHeight` |
| 最小形 | 36×36 的圓（Apple `minimumMinimalSize`） | `IslandMetrics.minimalSize` |
| 無劉海膠囊展開 | 230×64（只給 `NotchCapsule`，不是劉海島） | `IslandMetrics.capsuleExpandedSize` |
| 劉海／外接屏展開上限 | 408／371、高 ≤160（Aaron #29/#83） | `notchExpandedMaxWidth`／`externalExpandedMaxWidth`／`expandedMaxHeight` |
| 落點小島 | 340×84、圓角 22（WS2 `DropIsland`，不是系統 `pinsTopPlatterWidth/Height`） | `dropIslandSize`／`dropIslandRadius` |
| 動效（2026-11-09 更新） | 27.3 Mac 島的兩組：`interaction` 用 `islandPrompt`（0.408／0.27），其餘用 `islandSizing`（0.3571428536916519／0.7500006097576885）；`.minimum` 收合暫用 `islandSizing`（hidden 未解，見 `mac-island-springs.md` §7.4） | `Motion.notchSpring`／`Core/FlickMotion.swift` |

理由：幾何前三項有 Mac／iOS 交叉證據；230×64 與 340×84 的血緣已分開標註；
408／371／160 來自 Aaron #29/#83；動效已從 27.3 `MacAssistantIslandSessionModel`
的 `#islandSizing` 分支取得精確值（見 `mac-island-springs.md` §7），不是盲調。

**shelf 例外（2026-11-09）**：408／371 只約束「沒有內容排」的展開寬度。
WindowShade 的窗口排（那一排最多 8 格）按內容寬度排版，3 格＝416、活動卡＝420，
會超過 408；這是刻意的產品例外，不是幾何漂移。收合／展開的高度仍受
`expandedMaxHeight = 160` 約束（142 是卡片內容高，不是島總高）。

**單一來源（2026-11-09）**：落點小島的 340×84／22 只留在 `IslandMetrics`
（`dropIslandSize`／`dropIslandRadius`）；`StripNotchExchange.landingSize`、
`FileDropGeometry.islandSize`、`Notch.dropZone` 都改成引用，不再各寫一份。

## 3. 還沒拿到的（誠實標註）

1. **展開尺寸**：`minimumExpandedSize` / `maximumExpandedSize` 的常數不在這一頁，
   而且它們由 `metricsForWindowScene:` 依螢幕算，靜態取值需要跑起來。
2. **動效參數**：`Jindo Dynamics` / `Jindo Top Outset` / `Jindo Bounds Oval` / `Baby Jindo`
   是 SpringBoard 的原型設定（字串在 SpringBoard 裡），預設值在設定類的初始化子裡；
   SpringBoard 太大、`class-dump` 不給 dump，沒有拿到彈簧的 damping/stiffness。
3. **模擬器量不到**：iOS 27.0 模擬器（iPhone 17 Pro）截圖的頂部中央是純白——
   系統島是 Simulator 視窗自己畫的外框，不在 framebuffer 裡。
4. macOS 27.3 的系統卷已拆（見 `mac-island-springs.md` §7.1）；仍未拿到的是
   `drawnPlatterSize`／`pinsTopPlatterWidth/Height` 的**執行時值**，不是映像本身。

## 4. 對我們的意義

把「我們的島」改成同一個模型，而不是同一組魔術數字：

- 每個狀態給 `min/max` 一對，狀態機只在區間內插值；
- 圓角一律由高度推（`min(height/2, maximumContinuousCornerRadius)`），不再按狀態寫死；
- 最小形＝高度見方的圓；微提示另立一級；
- 島要跟螢幕圓角同心（`displayCornerRadiusIgnoringZoom`）。

要不要直接把 iPhone 的 36.6667 / 18.3333 搬到 Mac 的劉海上（會改變現在的外觀），
還是只搬規則、數字仍由 Mac 劉海量出來的尺寸決定——這是產品決定，等 Aaron 拍板。
