窗口擋住你時，讓它讓開；回來時不用找。這套系統只服務 WindowShade 2 的三個場景和帶人走過它們的首啟引導：**收起、看一眼、放下**；**一甩就排好、一捏就撤回**；**看不見的東西都在劉海裡**。場景 3 的劉海也住著實時活動（正在播放、計時器）和耳機、妙控外設的電量：窗口是主角，它們用同一個宿主、同一套形狀。「認出你」是不對外主推的另一條線（實驗、默認關），用同一副兩耳和下巴。已移出 WS2 的只有 CarPlay 和指揮模式（#105），它們的稿只歸檔。

讀法：先讀「原則」，它決定什麼能做；再讀令牌（顏色、字、間距、圓角、時序）和「動效」章；畫一個表面之前讀它的元件說明。這是 WindowShade 設計系統的唯一入口（AARON-DECISIONS #111）。`WindowShade-internal/docs/design-system.md` 降為「硬件幾何與驗收」附錄（機型表、DisplayShape、肩的 S1–S2、驗收步驟），`design-grammar.md` 歸檔。數字只在這裡寫；和 AARON-DECISIONS 較新的條目不一致時以決定為準，並回寫到這裡。

## 原則

每條都從 Apple 官方來源推出來，2026-11-06 從官方頁面重讀核對；括號裡是那一頁的小標題或時間碼。「怎麼用」那一欄是給 WindowShade 的具體規矩。

| # | 原則 | 出處 | 怎麼用 |
|---|---|---|---|
| P1 | **系統已有的，先用系統的；系統在場時讓位。** | [HIG Designing for macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos)（Best practices）；[Apple Newsroom 2026-10-28](https://www.apple.com/newsroom/2026/10/apple-unveils-groundbreaking-macbook-pro-with-proled-xdr-display/)（Dynamic Island 來到 Mac，是 Spotlight、Live Activities、Siri 的新家） | 有系統灵動岛的觸控 MacBook Pro 上不在岛上自己畫（#18、#38）；系統已顯示的同一件事不重複（#39）；macOS 自帶平鋪、Rectangle 在時不打架。新表面先問：系統是不是已經有一個？ |
| P2 | **形狀從硬件長出來；沒有硬件就不畫硬件。** | [WWDC25 356](https://developer.apple.com/videos/play/wwdc2025/356/)（Design Language：形狀與硬件、窗口邊緣同心）；[HIG Live Activities](https://developer.apple.com/design/human-interface-guidelines/live-activities)（Compact：貼近攝像頭）；[HIG Layout](https://developer.apple.com/design/human-interface-guidelines/layout)（macOS：不把內容放在劉海後面） | 貼劉海的形狀接著劉海自己的輪廓長（`radius-hw-notch` 從 DisplayShape 取）。外接屏、Neo、「避開劉海」模式只畫菜單欄膠囊，不畫假劉海。 |
| P3 | **三種形狀：固定、膠囊、同心。** 子半徑 = 父半徑 − 邊距；矮條用膠囊；沒有父容器用固定半徑兜底。 | [WWDC25 356](https://developer.apple.com/videos/play/wwdc2025/356/)（Fixed / Capsule / Concentric；macOS 小控件保留圓角矩形）；HIG Live Activities（同心邊距，用 `ContainerRelativeShape` 不寫死半徑） | 展開 28 − 14 = 格子 14；提醒 24 − 14 = 教學台面 10。高度會變的形狀不在膠囊和圓角矩形之間跳。 |
| P4 | **一個會變形的整體，只有五種呈現。** | HIG Live Activities（Compact / Minimal / Expanded：展開時元素位置與緊湊一致；版面變化用既有元素移動，不移除再加入）；[WWDC23 10194](https://developer.apple.com/videos/play/wwdc2023/10194/) | 最小、緊湊、短暫提醒、展開、交互。不發明第六種；新需求先找它是哪一種。兩耳讀成一件事，展開是緊湊的放大，不留額頭。 |
| P5 | **材質三層，不疊玻璃。** 硬件層純黑；控件層用系統玻璃；內容層不加材質。 | [HIG Materials](https://developer.apple.com/design/human-interface-guidelines/materials)（玻璃是控制與導覽的獨立功能層，不用在內容層；多數情況用 Regular）；[WWDC25 219](https://developer.apple.com/videos/play/wwdc2025/219/)（Principles 10:31：不疊玻璃，玻璃上的元素用填色、透明度；著色只給主要動作）；HIG Live Activities（島內一律不透明黑底） | 劉海、膠囊、落點小島 = `notch-fill`；提示浮窗、排窗代理 = `NSGlassEffectView` regular（14/15 用 `NSVisualEffectView`）；卷帘條是窗口自己的標題欄、看一眼卡片是窗口畫面，都不加材質。不手畫高光、折射、灰玻璃。 |
| P6 | **從哪裡出去，就從哪裡回來。** | [WWDC18 803](https://developer.apple.com/videos/play/wwdc2018/803/)（空間一致） | 卷帘條在原處、放回到原處、收進劉海和放回走同一條路、撤銷回到排之前的位置。這就是產品的那句話：Roll it up. Keep its place. |
| P7 | **跟手、可打斷、半路可改方向。** | WWDC18 803（完全可重導向；松手看速度與歷史）；[WWDC23 10158](https://developer.apple.com/videos/play/wwdc2023/10158/)（彈簧帶初速度、改向時接上當前速度）；[HIG Motion](https://developer.apple.com/design/human-interface-guidelines/motion)（讓人能取消，不必等動畫跑完） | 標題欄手勢、劉海下拉上推、排窗代理全程 1:1 跟手；松手看投影落點，不在一開始鎖死方向；彈簧疊加，速度連續。 |
| P8 | **頻繁的動作少動，用彈簧不用時長。** | HIG Motion（動效只在支持體驗時加；頻繁重復的互動不加自訂動效）；WWDC23 10158（不確定時 bounce 0；約 0.15 還不太彈，約 0.3 明顯，超過 0.4 對 UI 太誇張）；803（從 100% 阻尼開始調） | 見「動效」章。一天上百次的不回彈；只有收進那一下和首啟示範允許表現。 |
| P9 | **畫結果，不畫參數。** | iOS 18 手電筒按鈕（Chan Karunamuni 作品）；WWDC18 803 | 排窗代理畫窗口排好後的樣子，不畫菜單；落點小島畫「放進來」的口子。越過門檻時終點彈一下，告訴人「松手就成」，不彈確認框。 |
| P10 | **先演示，少說話，只在卡住時說。** | [HIG Onboarding](https://developer.apple.com/design/human-interface-guidelines/onboarding)（短、可略過、邊做邊學；權限等第一次用到才問，除非沒有它就不能用） | 首啟引導邊做邊學，每步讓人真的做成一次；教學只講會反復用的手勢，講一次，有次數上限。 |
| P11 | **每個表面都有四個無障礙答案，外加一條不用手的路。** | [HIG Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)（18 pt 以下 4.5:1；Reduce Motion 減少自動與重復動畫；macOS 文字最小 10 pt、控件最小 20×20）；WWDC25 219（降低透明度變霧、提高對比加邊、降低動態關彈性）；HIG Designing for macOS（所有命令放進菜單欄、支援快捷鍵） | 減少動態效果、減少透明度、增強對比度、VoiceOver 各有答案；每個手勢都有菜單項或快捷鍵；狀態不只靠顏色（換粗細或符號）。 |
| P12 | **一個東西一個名字，用 Apple 的口氣。** | [HIG Writing](https://developer.apple.com/design/human-interface-guidelines/writing)；[HIG Color](https://developer.apple.com/design/human-interface-guidelines/color)（一種顏色只代表一種意思；不挪用語義色）；copy-guide.md | 「收起窗口」「看一眼」「收進劉海 / 放回」「回到原處 / 去」。內部叫法（岛、肩、硬件層、隱形劉海）不進界面。不借 Apple 的功能名當自己的。 |

## 翻案的規矩

劉海的樣子在 10 月到 11 月翻了三次（兩耳 → 掛下來 → 兩耳）。以後要改任何一個已定的外觀，按下面的順序找依據，答不出就不改：

1. **這台硬件上系統自己怎麼做？**（P1）有就照它，或讓位。
2. **Apple 官方寫明的範式是什麼？**（HIG Live Activities、Materials、Motion）照它的呈現和規則。
3. **硬件幾何給的約束是什麼？**（P2、P3，design-system.md §3）
4. **以上都沒說的，才是我們的品味。** 品味的改動先做小樣，標「自定」，和 Aaron 確認一次後寫進 AARON-DECISIONS。

改的時候在對照帳記一行：推翻哪一條、依據落在上面第幾級、哪些稿因此作廢。

## 內容與文案

- 對用戶說用戶遇到的事，不列功能：「窗口擋住你時，讓它讓開」，不說「窗口管理」。
- 動詞固定：收起 / 放下（卷帘條）；看一眼；收進劉海 / 放回；回到原處（窗口回到面前）/ 去（你過去別的桌面）；撤銷 + 那一步的名字（「撤銷 左半屏」）。
- 手勢按設備說：觸控板說「兩指」「三指」；組合鍵符號第一次出現時說是哪個鍵，例如「⌃（Control）」。
- 順利時不說話。不推銷，不糾正他用系統辦法已經做成的事。
- 不替 Apple 的硬件下定義：不說「劉海是 Mac 的新入口」。
- 中文先行，英文同步；讀屏念整句（「Put Safari back where it was」）。

## 視覺基礎

- **顏色**：只用系統語義色（`label`、`label-secondary`、`separator`、`window-bg`、`accent`、`problem`），App 裡寫 NSColor 名字，不寫 RGB。劉海一族（`notch-*`）固定深色，是唯一不跟隨淺深色的表面，理由是它要和實體劉海接上。
- **字**：一律系統字體 SF Pro；個數用 SF Pro Rounded 等寬數字。macOS 正文 13（`mac-body`），最小 10。劉海上字號少而粗：耳內 13 semibold、符號 16。
- **間距**：島內四周 `inset-island` 14；浮層 `inset-panel` 12；貼邊 `margin-edge` 8；浮著的離邊 `margin-float` 16。兩耳 `gap-ear` 0。
- **圓角**：連續曲率（`.continuous`），不用圓弧。硬件值運行時取；窗口級 13、卡片 12、行 8、控件 6；島的大狀態 22 / 24 / 28；矮條用膠囊。
- **陰影**：只給看一眼的卡片（`shadow-glance`），沿卡片路徑畫。硬件層不加陰影。
- **觸感**：越過門檻 `.alignment`；落點確認 `.levelChange`；收進劉海、放回不加。不加聲音（提示音只屬於已移出的計時線）。
- **符號**：SF Symbols，劉海裡單色白，設置裡 hierarchical 放在圓角色塊。收起 / 展開窗口 `rectangle.compress.vertical` / `rectangle.expand.vertical`；收進劉海 `rectangle.topthird.inset.filled`；劉海那一排 `macwindow.on.rectangle`；看一眼 `eye`；左右半屏 `rectangle.lefthalf.inset.filled` / `rectangle.righthalf.inset.filled`。

## 三個場景用到的表面

| 場景 | 表面（元件） |
|---|---|
| 1 收起、看一眼、放下 | `ShadeStrip` 卷帘條、`GlanceCard` 看一眼 |
| 2 一甩就排好、一捏就撤回 | `SnapProxy` 標題欄排窗代理、`GestureHUD` 手勢提示浮窗 |
| 3 看不見的東西都在劉海裡 | `NotchEars` 緊湊兩耳（窗口、實時活動、電量共用）、`NotchRow` 展開那一排、`DropIsland` 落點小島、`MenuBarCapsule` 外接屏膠囊 |
| 另一條線：認出你 | `NotchEars` 加下巴；按稿《从锁屏到窗口》，修正後的衝突見稿件審查 |
| 首啟引導 | `Welcome` 首啟引導的一步 |

還有四章：「動效」；「矛盾清單」記下文件、稿、代碼彼此對不上的地方；「稿件審查」把 41 份稿按這套系統過一遍；「已定問題」記下 Aaron 對這套系統的決定。
