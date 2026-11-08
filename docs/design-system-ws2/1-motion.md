# 動效

位移一律用彈簧描述，不用時長，不用貝塞爾曲線。正文和稿只寫令牌名；非寫數字不可時，寫成 `response / ζ`，並標明是阻尼比 ζ（SwiftUI 的 `bounce = 1 − ζ`）。

換算（WWDC23 10158 用 duration + bounce；803 用 response + damping，兩種寫法是同一個彈簧）：質量 1，剛度 `(2π / response)²`，阻尼 `4πζ / response`。代碼裡的令牌在 `prototype/Core/FlickMotion.swift` 的 `MotionSpring`（App 裡別名 `Motion.Spring`），由 `tests/MotionTokensTests.swift` 逐項釘住。

## 彈簧令牌

| 令牌 | response / ζ | bounce | 帶初速度 | 什麼時候用 | WS2 場景 |
|---|---|---|---|---|---|
| `calm` | 0.34 / 1.0 | 0 | 否 | 沒有動量的變化：收回、換狀態、緊湊退場 | 全部 |
| `settle` | 0.38 / 1.0 | 0 | 飛進劉海時帶；尺寸變化不帶 | 尺寸變化；截圖飛進劉海；緊湊進場 | 3 |
| `expand` | 0.40 / 0.92 | 0.08 | 否 | 展開那一排 | 3 |
| `bloom` | 0.42 / 0.84 | 0.16 | 否 | 提醒、教學開口 | 首啟、教學 |
| `catch` | 0.40 / 0.80 | 0.20 | 應帶拖動速度（代碼還沒帶） | 拖著窗口到劉海時的落點小島 | 3 |
| `glide` | 0.42 / 0.88 | 0.12 | 必須 | 甩一下標題欄後窗口滑到落點；排窗代理跟到槽位 | 2 |
| `flyOut` | 0.38 / 0.90 | 0.10 | 必須 | 從劉海放回，沿原路飛出 | 3 |
| `pull` | 0.36 / 0.86 | 0.14 | 必須（夾在 ±30） | 劉海下拉、上推松手彈回 | 3 |
| `fold` | 0.25 / 1.0 | 0 | 否 | 卷帘條卷起、放下；收起代理收成條（Aaron 10-31 定，代碼 `FlickMotion.swift:177`） | 1 |
| `pop` | 0.30 / 0.75 | 0.25 | 否 | 只給小元素的確認：提示浮窗終點圖標 | 2 |
| `reduced` | 0.25 / 1.0（劉海）；0.30 / 1.0（窗口滑行） | 0 | 否 | 減少動態效果時替換以上全部；挪位置改為原處淡出、目標處淡入 | 全部 |
| `islandPrompt` | 0.408 / 0.27 | 0.73 | 否 | 島的 listening／prompt（WindowShade 映射為 `.interaction`） | 島 |
| `islandSizing` | 0.3571428536916519 / 0.7500006097576885 | 0.2499993902 | 否 | 島的 thinking／response／transient | 島 |
| `islandHidden` | 0.3 / 0.8 | 0.2 | 否 | 島的 `.hidden` 收合（27.3 `WindowSizingAnimation.default`） | 島 |

`islandPrompt`、`islandSizing`、`islandHidden` 是 2026-11-09 新增的**系統島令牌**：直接照 macOS 27.3 `CampoUIInternal`／`SpotlightUIShared` 的值，列為 §4.6 上限（Mac bounce ≤0.2）的唯一具名例外，只准用在島。來源與 tag 表見 `docs/reverse-engineering/mac-island-springs.md` §7；`.hidden` 由 `WindowSizingAnimation.default` 的 `Spring(0.3, bounce 0.2)` 承接。

`expand`、`bloom`、`catch`、`pop` 的回彈是已知例外：WWDC23 10158 允許為了活潑加一點，HIG Motion 說觸控板上效果要更收斂，所以 Mac 上 bounce 上限 0.2，只有 `pop` 到 0.25（自定）。新表面不再加例外。

## 規則

1. **頻率決定動多少。** 一天上百次的（緊湊兩耳出現、格子懸停看一眼、卷帘條收放）只用 `calm` / `settle`，不回彈；只有收進劉海那一下、首啟引導的示範允許表現。依據：HIG Motion「經常發生的互動少加動作」。
2. **疊加，不重來。** 換目標時拿當時的速度作初速度，位置和速度都連續；不同屬性可以各自在不同時刻結束（10158）。做到一半松手或改方向，從當時的位置繼續（803）。
3. **不等停穩。** 後續動作不等 `settlingDuration`；它和感知時長不是一回事（10158）。
4. **形狀先走，內容後到。** 形狀走到約四成，內容用 `fade-in` 淡入；退場時內容先 `fade-out`，形狀再用 `calm` 收回。
5. **從哪裡出去，就從哪裡回來。** 卷帘條在原處卷起、在原處放下；收進劉海和放回走同一條路；排窗撤銷沿原路回到排之前的位置（803 空間一致）。
6. **松手看投影落點。** 803 只口頭說用速度和減速率估終點；公式 v/1000 · r/(1−r) 在投影片上、逐字稿裡沒有，引用時寫「803 投影片」。甩標題栏、畫中畫落角 r = 0.998；劉海下拉 r = 0.99（故意停得快）。
7. **Mac 上沒有「動畫 ≤ 2 秒」以外的時長規定。** HIG Live Activities 給 iOS 的岛動畫上限 2 秒，Mac 沿用；我們的彈簧感知時長都在 0.5 秒內。
8. **減少動態效果。** 用 `reduced`，不帶速度，不飛行，島不鼓；示範停在最能說明問題的那一幀；位移換成淡入淡出（HIG Accessibility）。

## 已知的散落值（待收）

- 啟動台另有 14 組彈簧、11 條貝塞爾曲線（`rg -n "perceptualDuration|controlPoints" App/Launchpad*.swift`），其中 bounce 0.3 和控制點 1.05 會過衝。啟動台不在 WS2 三個場景裡，只記帳不改。
- `FoldSpring`（ω = 5.83 / response，只有臨界阻尼）只給合蓋與鎖屏覆蓋，屬於已移出 WS2 的線。
