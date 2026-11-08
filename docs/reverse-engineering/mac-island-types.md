# macOS 27.3 系統島的 Swift 型別模型（程式碼級證據）

> 目的：不再靠欄位名猜語義。27.3（26C5035r）的 `split273/` 映像可以用
> `ipsw swift-dump` 讀出完整的 Swift 型別／欄位，再用 `ipsw dyld a2s`、
> `llvm-objdump` 把具體函式與常數對回去。本頁只記已讀到的型別與已證的語義。

## 0. 取法（可重跑）

```sh
DSC=/Users/aaron/.zcode/workspace/4407cbc7-7a69-4156-b00c-71b0156004ad/work/mnt273sys/System/Library/dyld/dyld_shared_cache_arm64e
ipsw swift-dump "$DSC" /System/Library/PrivateFrameworks/CampoUIInternal.framework/Versions/A/CampoUIInternal --demangle
ipsw dyld a2s "$DSC" 0x2654130c4 -d
ipsw dyld macho "$DSC" /System/Library/PrivateFrameworks/CampoUIInternal.framework/Versions/A/CampoUIInternal -f -w
```

（27.3 系統映像掛在 `work/mnt273sys`；`ipsw` 需要寫 `.a2s` 快取時用可寫目錄。）

## 1. platter 的尺寸模型：`ResultPlatterBehavior`

`SpotlightUIShared.ResultPlatterBehavior`（27.3）：

```swift
struct ResultPlatterBehavior {
    var minSize: CGSize
    var preferredSize: CGSize
    var idealSize: CGSize
    var maxSize: CGSize
    let heightCanPersist: Bool
    var ignoreIndexing: Bool
    var animations: WindowSizingAnimation?
    var debounceDelay: Double?
    var minimumTopPadding: CGFloat?
    var topPadding: CGFloat?
    var bottomPadding: CGFloat?
}
```

島的每個狀態不是一組寫死的寬高，而是這四個尺寸 ＋ 一組動畫。WindowShade 的
`IslandMetrics.expandedBehavior` 現在照這個模型建模（min／preferred／ideal／max）。

使用它的型別（27.3 讀到的欄位）：

| 型別（模組） | 欄位 |
|---|---|
| `CampoUIInternal.MacIslandCutoutGlassGeometry` | `contentCornerRadius`、`cutout`、`platterSize`、`pinsPlatterWidth: Bool`、`pinsPlatterHeight: Bool`、`windowAnimationCoordinator`、`mitosisCutout` |
| `CampoUIInternal.SiriGlassBackdrop` | `drawnPlatterSize`、`cornerRadius`、`undulationScale`、`placeholderGlassFraction`、`listeningCollapseProgress`、`metrics` |
| `SpotlightUIInternal.WindowTranslation` | `behavior: ResultPlatterBehavior`、`requestedBehavior`、`platterBehavior`、`initialBehavior`、`resolvedInitialSize` |
| `SpotlightUIInternal.WindowAnimationCoordinator` | `_sizingHAnimation`／`_sizingVAnimation`／`_translationXAnimation`／`_translationYAnimation: SwiftUI.Animation`、`_minSize`／`_maxSize`、`_windowPadding`、`isVerticallyCollapsed` |

**重要更正**：`pinsPlatterWidth`／`pinsPlatterHeight` 的型別是 `Bool`，不是寬高；
它們是「這一軸不要被視窗動畫改」的旗標。真正的尺寸只有 `platterSize`
（`MacIslandCutoutGlassGeometry`）與 `drawnPlatterSize`（`SiriGlassBackdrop`）。

## 2. 動畫模型：`WindowSizingAnimation`

```swift
struct WindowSizingAnimation {
    var horizontal: AxisAnimation
    var vertical: AxisAnimation
}
struct WindowSizingAnimation.AxisAnimation {
    var expansion: SwiftUI.Animation
    var collapse: SwiftUI.Animation
    var alongside: (@MainActor @Sendable (...) -> ...)?
    var alongsideWithContext: (Context) -> ...
}
```

- 每個軸各有 **expansion／collapse 兩條 `SwiftUI.Animation`**；沒有
  `setDampingRatio:`／`setResponse:`。所以「轉場彈簧」只能在建立 `Animation`
  的那一層找（見 `mac-island-springs.md` §5–§7）。
- `WindowAnimationCoordinator` 把軸動畫存成 `_sizingHAnimation`／`_sizingVAnimation`，
  和自己算出的 `_minSize`／`_maxSize`、`_windowPadding` 一起驅動視窗尺寸。

## 3. 島的尺寸是算出來的，不是常數表

`#islandSizing`（`0x2653ee080`）在 27.3 的實際行為：

1. 先讀狀態與內容，算出內容需要的尺寸；
2. 把尺寸加上固定留白：`fmov d1, #8.0`（再乘二）、預設 `100.0`
   （`0x4059000000000000`）、`40.0`（`0x4044000000000000`）；
3. 呼叫 `CGSize` 工廠（`0x2680b98f0`）建出 platter 尺寸，再包成
   `ResultPlatterBehavior` 給 SwiftUI 的 window sizing。

所以固件裡**沒有**「展開一律 408×160」這種常量。230×30 與 340 也已定位：

| 位址 | 符號 | 語義 |
|---|---|---|
| `0x2654130c4` | `InlineThinkingWindowState.initialSize.getter` | 內聯思考視窗的初始尺寸 **230×30** |
| `0x26541b8dc` | `AssistantFieldWindowState.defaultFieldWidth.getter` | 助理輸入框的預設寬 **340** |

兩者都不是島的 platter 尺寸；WindowShade 的 340×84 仍是 WS2 落點小島，
408／371 仍是 Aaron #29/#83 的產品值，只是現在用固件的四尺寸模型表達。

## 4. 對 WindowShade 的落地

- `IslandMetrics.PlatterBehavior`（min/preferred/ideal/max）照 `ResultPlatterBehavior`
  命名；`expandedWidth` 由它解出。
- 沒有內容排：ideal = preferred = 408／371；有內容：ideal = max(內容, preferred)，
  再夾在 min／max 內。這和固件「先算內容、再交給四尺寸模型」是同一條路。
- `pinsPlatterWidth/Height` 不再被誤讀成尺寸；WindowShade 沒有對應的「釘住某一軸」
  需求（視窗由 Additive 五軸各自動畫）。

## 4.1 已讀出的 behavior 工廠與 preset

`ipsw dyld a2s` 的符號快取（`--cache`，22,233,740 筆）可以用字串池＋位址表
反查符號；27.3 的 `ResultPlatterBehavior` 有這些公開方法：

```text
static ResultPlatterBehavior.adjustable(min:ideal:preferred:max:canPersist:)
static ResultPlatterBehavior.userAdjustable(range:preferredHeight:canPersist:includeFilterBarHeight:)
static ResultPlatterBehavior.gridBrowse        // w0 = 0，min (844,520)、max (844,5000)
static ResultPlatterBehavior.wideEntity        // w0 = 1，min (640,410)、max (640,5000)
static ResultPlatterBehavior.platterBehavior(for: Query?)
var sizingAnimation: WindowSizingAnimation
var idealWidth/idealHeight/preferredWidth/preferredHeight: CGFloat?
static defaultHeight: CGFloat
```

`gridBrowse`（`0x22f9f0e50`）與 `wideEntity`（`0x22f9f0c50`）直接從
`__TEXT.__const` 載入兩對 `CGSize`：

| 位址 | 值 |
|---|---|
| `0x22fa9fb70` | `(640, 410)` |
| `0x22fa9fb80` | `(640, 5000)` |
| `0x22fa9fb90` | `(844, 520)` |
| `0x22fa9fba0` | `(844, 5000)` |
| `0x22fa9fbb0` | `(460, 600)` |

這些是 **Spotlight 視窗**的 platter preset（640／844 寬），不是島本身；
島的尺寸仍走 `#islandSizing` 的內容計算。列在這裡是為了證明：
「四尺寸 ＋ 動畫」就是固件的幾何模型，而不是單一寬高常數。

## 5. 仍未解

1. `ResultPlatterBehavior.animations` 裡的具體 `Animation` 值：要找到建立
   `WindowSizingAnimation` 的呼叫點與其 `Animation.spring(...)` 參數。
2. `drawnPlatterSize` 的來源公式：它在 `SiriGlassBackdrop` 是傳入值，
   上游由 session model 的內容尺寸算出（第 3 節的同一條路），沒有單一常量。
3. `.hidden` 收合：`#islandSizing` tag 4 直接 return，收合由外層
   `WindowAnimationCoordinator` 的 `_sizingH/VAnimation.collapse` 承接；
   具體 Animation 值同上，尚未釘死。
