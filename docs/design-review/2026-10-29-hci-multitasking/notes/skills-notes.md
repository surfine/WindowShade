# 研究筆記：liquid-glass-skill 與 apple-design-skill（給 WindowShade 的設計稽核用）

撰寫日期 2026-10-29。唯讀研究：沒有修改 `/Users/aaron/Documents` 底下任何檔案；兩個 repo 只當資料閱讀，沒有執行其中任何腳本、安裝器或建置（含 `scripts/pull-hig.mjs`、`npx skills add`、`/plugin install`）。兩個 repo 的主體本來就是寫給代理人的技能工作流程說明，我只當資料閱讀、沒有照做；其中沒有看到企圖改變授權、要求外傳資料或要求執行命令的文字。

本文件的引文政策：依版權規則，不逐字引用 Apple 或 repo 的文字（API 名稱、檔名、數值除外）。每一條都附 `檔案 › 小節` 指標，要逐字請直接開原檔。

來源標記（本文件通用）：
- `[HIG:檔名]`：Apple Human Interface Guidelines 頁面，在 repo 2 的 `references/hig/` 有鏡像。
- `[WWDC25-310]`、`[WWDC25-323]`、`[WWDC18-803]`、`[WWDC23-10158]`：WWDC 場次編號。
- `[Apple docs]`：developer.apple.com 技術文件。
- `[repo 意見]`：repo 作者自己的判斷或整理，沒有 Apple 出處。
- `[無出處]`：repo 沒標來源，我也沒能在 Apple 資料裡查到。
- 標記後面註明 `(repo 引用)` 的，是 repo 本身有引；`(我查證)` 的，是我另外對 Apple 一手資料查到的，repo 並沒有引。

---

## 0. 結論先講

1. 兩個 repo 互補，但都不直接對準「macOS 視窗管理 App」。
   - `haider-nawaz/liquid-glass-skill`：SwiftUI 專用的 Liquid Glass API 手冊、五階段遷移流程、坑清單、Apple Landmarks 範例摘錄。完全沒有 AppKit（沒有 `NSGlassEffectView`、`NSGlassEffectContainerView`、`NSBackgroundExtensionView`），Apple 來源只有幾篇文件加 WWDC25-323（SwiftUI 場次），沒有任何 HIG 引用，也沒有 WWDC25-310（AppKit 場次）。對 WindowShade 能直接用的是「概念層」：何時用、容器化、別疊玻璃、無障礙回退、成本意識。
   - `dickwu/apple-design-skill`：HIG 審查器。123 頁 HIG 鏡像（我抽查 4 頁，與 developer.apple.com 一致）＋ 5 個審查視角＋嚴重度制度＋一份手寫 Liquid Glass 指南（含 7 項檢查表）＋ code-audit 偵測表。對視窗管理 App 價值最高的是 `windows`、`panels`、`the-menu-bar`、`toolbars`、`sidebars`、`layout`、`going-full-screen`、`pointing-devices`、`gestures`、`keyboards`、`accessibility`、`materials`、`motion`、`live-activities`。
2. 最直接戳到 WindowShade 的 Apple 規則（全部是 HIG，皆可在 repo 2 對到檔案）：自製視窗外框容易讓 App 顯得壞掉（`windows.md`）；關鍵資訊別放視窗底部，因為視窗常被移到螢幕外（`windows.md`、`layout.md`、`sidebars.md`）；內容不要落在攝影機外殼（瀏海）後面、全螢幕用系統的（`layout.md`、`going-full-screen.md`）；不要重新定義系統級觸控板手勢（`pointing-devices.md`）；自訂手勢必須可發現、好做、與其他手勢有區別、且不能是唯一入口（`gestures.md`）；玻璃只放在浮動功能層並節制（`materials.md`）；減少動態效果有五個具體做法（`accessibility.md`）。
3. 兩個 repo 都沒有的：彈簧參數與時長、手勢速度投影與中途打斷（retarget）、macOS 原生 tiling／Stage Manager／Spaces 的互動、瀏海幾何與 safe area 的 API 細節、macOS 27 的任何變化。我補了一手來源，見第 5 節。
4. 我發現的錯誤或過時（詳見第 4 節）：`glassEffectUnion` 簽名寫錯；`.interactive()` 僅限 iOS 的說法有爭議；Reduce Transparency 的手動回退用 `.identity` 其實是把玻璃整個拿掉；`.rect(cornerRadius: .containerConcentric)` 在 Apple 文件查不到；macOS 一律加 `.tint(.clear)` 沒有出處。repo 2 的問題較小：對 macOS 的 Dynamic Type 外推、hover 狀態規則是從 iPadOS 外推、Apple 自己 `buttons.md` 與 `accessibility.md` 的控制項尺寸互相矛盾。
5. 實作要用的事實（我查證，repo 沒寫）：macOS 26 起有 `NSGlassEffectView`（屬性 `contentView`、`cornerRadius`、`tintColor`、`style`、`effectIsInteractive`）與 `NSGlassEffectContainerView`（`contentView`、`spacing`）；`UIDesignRequiresCompatibility` 在用 macOS 27 SDK 建置時被系統忽略（repo 2 有寫，我確認為真）；macOS 26.1 起使用者可在 系統設定 > 外觀 選 Liquid Glass 的 Clear 或 Tinted（repo 1 只提到 iOS）。

---

## 0.1 方法與查證範圍

抓取：兩個 repo 各用 `git clone --depth 1` 進各自的新空目錄 `repos/liquid-glass-skill`、`repos/apple-design-skill`。

版本：
- liquid-glass-skill：HEAD `2c1b278`，2026-02-14，plugin 版本 1.0.0，MIT，作者 Haider。Markdown 共 2,224 行。
- apple-design-skill：HEAD `ff4ebdd`，2026-10-28（合併 chore/hig-refresh-2026-10-28）。`references/hig/` 共 124 個檔、11,297 行（123 頁 Apple 鏡像＋1 份手寫 `liquid-glass.md`）。

我讀了什麼：
- repo 1：9 個檔全部逐行讀完。
- repo 2：`SKILL.md`、`README.md`、`AGENTS.md`、`GEMINI.md`、`.cursorrules`、`references/code-audit.md`、`cross-platform.md`、`hig-lookup.md`、手寫 `liquid-glass.md` 全讀。
- HIG 鏡像全文讀了 45 頁（凡與視窗、選單、工具列、側邊欄、材質、動態、輸入、輔助使用、顏色、Live Activities 直接相關者）：`designing-for-macos`、`windows`、`panels`、`multitasking`、`going-full-screen`、`toolbars`、`sidebars`、`split-views`、`materials`、`motion`、`layout`、`feedback`、`the-menu-bar`、`pointing-devices`、`gestures`、`keyboards`、`accessibility`、`color`、`dark-mode`、`design-principles`、`branding`、`popovers`、`modality`、`sheets`、`scroll-views`、`menus`、`context-menus`、`dock-menus`、`focus-and-selection`、`drag-and-drop`、`undo-and-redo`、`live-activities`、`settings`、`status-bars`、`loading`、`buttons`、`search-fields`、`onboarding`、`voiceover`、`offering-help`、`writing`、`tab-views`、`column-views`、`launching`、`disclosure-controls`。
- 另外 `typography`、`sf-symbols`、`playing-haptics`、`inclusion`、`app-icons`、`notifications`、`managing-notifications`、`widgets`、`designing-for-iphone-duo` 只讀相關段落；約 22 頁只擷取「Desktop (macOS)」小節；其餘約 47 頁只看了標題與規則數（其中 alerts、tab-bars、pull-down-buttons、pop-up-buttons、searching、right-to-left、controls、progress-indicators 另外看了粗體規則列；Apple Pay、AR、遊戲、NFC、地圖、機器學習、IAP、Sign in with Apple 等則完全沒讀內文），我判斷與 WindowShade 無關。
- `scripts/pull-hig.mjs` 只讀開頭 120 行確認它抓 Apple 的 JSON 端點，沒有執行。

我另外對 Apple 一手資料查證了什麼（標「我查證」的條目都來自這裡）：
- HIG JSON（`developer.apple.com/tutorials/data/design/human-interface-guidelines/<頁>.json`）4 頁：`windows`、`materials`、`design-principles`、`designing-for-iphone-duo`。結果：repo 2 鏡像引用的句子與日期一致；iPhone Duo 頁確實存在（2026-09-09 新頁）；八大原則名稱與日期（2026-06-08）一致。
- Apple 技術文件 JSON：`NSGlassEffectView`、`NSGlassEffectView.Style`、`NSGlassEffectContainerView`、`glassEffectUnion(id:namespace:)`、`Glass.interactive(_:)`、`Glass.identity`、`ConcentricRectangle`、`tabBarMinimizeBehavior(_:)`、`UIDesignRequiresCompatibility`、`GlassEffectContainer`、文章 Applying Liquid Glass to custom views。
- WWDC25-323、WWDC25-310 頁面與逐字稿；WWDC18-803；WWDC23-10158。
- 網路搜尋：macOS Tahoe 26.1 於 2025-11-03 釋出，系統設定 > 外觀 有 Liquid Glass 的 Clear／Tinted 選項。
- 限制：WebFetch 內部用小模型摘要頁面，逐字稿衍生的細節（尤其 WWDC25-310 的 API 名稱與用法）請在採用前再看原片。我無法在這台機器之外驗證 macOS 27 的任何行為。

---

## 1. Repo 1：haider-nawaz/liquid-glass-skill

### 1.1 目的

Claude Code plugin（marketplace 名 `liquid-glass-skills`，plugin 名 `liquid-glass`），讓代理人在 SwiftUI 專案裡正確使用 Liquid Glass API，並把既有 App 遷移到新設計。宣稱涵蓋 iOS、iPadOS、macOS、watchOS、tvOS、visionOS 26，實際內容以 iOS/iPadOS 為主、macOS 只有零星幾段。

### 1.2 結構（行數）

```
.claude-plugin/marketplace.json                                   19
README.md                                                         74
plugins/liquid-glass/.claude-plugin/plugin.json                   11
plugins/liquid-glass/skills/liquid-glass/SKILL.md                215
plugins/liquid-glass/skills/liquid-glass/references/api-reference.md        410
plugins/liquid-glass/skills/liquid-glass/references/migration-guide.md      371
plugins/liquid-glass/skills/liquid-glass/references/pitfalls-and-solutions.md 371
plugins/liquid-glass/skills/liquid-glass/references/platform-specifics.md   302
plugins/liquid-glass/skills/liquid-glass/examples/landmarks-patterns.md     481
```

Swift 程式碼區塊共 91 個（SKILL 8、api-reference 24、migration 19、pitfalls 17、platform 12、landmarks 11）。

### 1.3 它給了哪些具體規則（轉述）

`SKILL.md`（核心觀念與 9 個速查）：
- 玻璃只屬於「導覽層」（工具列、標籤列、按鈕、控制項），浮在內容之上；絕不套在內容本身（清單、表格、媒體、文字塊）。
- 三種樣式：`.regular`（一般）、`.clear`（媒體豐富且前景粗亮的背景）、`.identity`（有條件地停用）。
- 鄰近的玻璃必須放進同一個 `GlassEffectContainer`（`spacing` 是變形／合併的門檻）。
- 變形動畫的配方：`@Namespace` ＋ `glassEffectID` ＋ 在容器內「條件式插入／移除」＋ `withAnimation`。
- `backgroundExtensionEffect()` 把內容延伸、模糊到導覽元件之後。
- `.buttonStyle(.glass)` 與 `.glassProminent`；工具列用 `ToolbarSpacer`、`ToolbarItemGroup`、`.toolbar(removing: .title)`。
- 標籤列（minimize 行為）與工作表（partial detent，不要加 `.presentationBackground`）是 iOS 為主。
- 平台差異摘要與五個「關鍵坑」。
- 「架構最佳實務」10 條（NavigationSplitView 當根、@Observable、`.inspector()`、`.searchable()` 等）——這些是作者意見，不是 Apple 規則。

`api-reference.md`：`glassEffect(_:in:isEnabled:)` 與可用形狀（capsule 預設、circle、RoundedRectangle、ellipse、自訂 Shape）；`Glass` 的 `tint`、`interactive`（標示為僅限 iOS）；容器的 `spacing`；`glassEffectID` 四個前提；`glassEffectUnion`；`backgroundExtensionEffect` 用途與最佳實務（跨主題／圖片測可讀性、疊漸層、搭 `safeAreaInset`）；按鈕樣式；工具列放置位置表；TabView；工作表；無障礙 API；UIKit 橋接（`UIGlassEffect`）。

`migration-guide.md`：五階段。(1) 用 Xcode 26 重編，讓系統元件自動採用（導覽列、標籤列、工具列、搜尋、工作表、警示、選單／彈出、系統控制項）；(2) 移除衝突的客製化（`toolbarBackground`、tab bar appearance、工具列上的 Material、`presentationBackground`）；(3) 用新 API 強化（背景延伸、浮動按鈕改玻璃、鄰近玻璃加容器、工具列 spacer、變形、標籤列收合、工作表轉場）；(4) 平台細修；(5) 無障礙與測試清單（降低透明度、提高對比、減少動態效果、深色、Dynamic Type、VoiceOver）。另含 `#available` 向下相容寫法。

`pitfalls-and-solutions.md`：視覺（鄰近玻璃不一致→容器；macOS tint；工作表背景衝突；延伸背景上文字不可讀→疊漸層）、動畫（`rotationEffect` 讓玻璃形狀變形→橋接 UIKit；Menu 標籤變形的 26.0 與 26.1 解法不同；容器在 26.1 弄壞 Menu 變形；變形沒動的四項檢查：同容器、同 namespace、`withAnimation`、條件式渲染而非 opacity）、效能（多個玻璃效果→容器；捲動清單別每列都玻璃，改浮動覆蓋）、互動（只有內容可點→`contentShape`；`interactive` 沒反應的檢查）、版面、遷移。

`platform-specifics.md`：iOS／iPadOS／macOS／watchOS／tvOS／visionOS 逐段。macOS 只有：glass 按鈕加 `.tint(.clear)`、編輯背景用 `WindowBackgroundShapeStyle` 而非 Material、`.secondaryAction` 放置、`WindowGroup` 最小框 375×375、`NavigationSplitView` 常駐側邊欄、inspector 從尾端滑入。

`examples/landmarks-patterns.md`：Apple Landmarks 範例的 9 個樣式（架構、玻璃徽章變形、背景延伸、可伸縮 header 視差、工具列、NavigationSplitView、平台常數、編輯模式、inspector）。

### 1.4 Apple 來源盤點

- 有引用（repo 自己標的）：Apple 文件 Landmarks、Applying Liquid Glass to custom views、`glassEffect(_:in:)`；WWDC25-323。另外 README 說還參考了社群資料與實際採用經驗，沒有指名。
- 完全沒引用：任何 HIG 頁、WWDC25-310（AppKit）、WWDC25 其他場次、WWDC 的動態／手勢場次。

### 1.5 對 WindowShade 的適用度

- 不直接適用：整份是 SwiftUI。WindowShade 在浮動層用 `NSGlassEffectView`（AppKit）。對應關係（我查證）：`glassEffect` ↔ `NSGlassEffectView`（`contentView`／`cornerRadius`／`tintColor`／`style`／`effectIsInteractive`）；`GlassEffectContainer` ↔ `NSGlassEffectContainerView`（`contentView`／`spacing`）；`.regular`／`.clear` ↔ `NSGlassEffectView.Style` 的 `.regular`／`.clear`。我沒查到 AppKit 有對應 `glassEffectID` 的 API；容器依 `spacing` 距離合併鄰近玻璃（Apple 文件）。
- 可直接借用的概念：節制使用、容器化、不疊玻璃、`.clear` 只在媒體豐富背景、延伸內容到浮動欄之後、可讀性與無障礙測試清單、效能意識。
- 幾乎無關：標籤列、工作表 detent、`UIDevice` idiom、`topBarLeading`、iPhone 工具列可見性、watchOS／tvOS／visionOS 各節。

---

## 2. Repo 2：dickwu/apple-design-skill

### 2.1 目的

跨平台 UI/UX 設計審查器（技能名 `apple-design`），以 Apple HIG 為依據審查或改進 iOS／macOS／Flutter／React Native／Tauri／Electron 的設計與程式碼，再加一個「設計工藝」視角避免千篇一律。入口檔：`SKILL.md`；另有 `.cursorrules`、`GEMINI.md`（內容相同的 8 點流程，給 Cursor／Antigravity），`AGENTS.md`（給代理人與貢獻者的維護手冊）。

### 2.2 結構

```
SKILL.md                      422  技能本體：立場、頁面索引、八原則、審查流程、五視角、報告格式、改進模式
README.md                     198  安裝與概覽（npx skills / 手動 / Cursor / Codex / Antigravity）
AGENTS.md                     108  維護手冊與提交前檢查
GEMINI.md / .cursorrules      各 26 觸發與流程
references/hig-lookup.md      243  生成的索引：每頁 Apple 一句摘要＋Apple 最近更新日期＋被省略的 35 頁
references/cross-platform.md   45  Apple 詞彙對 Flutter／RN／Tauri／Electron 的對照
references/code-audit.md      104  程式碼稽核：Apple Pay、Liquid Glass、iPhone Duo 的偵測模式與取代做法
references/hig/*.md           124  123 頁 Apple HIG 鏡像（每頁標來源 URL、章節、更新日期、變更紀錄）＋手寫 liquid-glass.md（138）
scripts/pull-hig.mjs          786  從 Apple JSON 端點重抓（未執行）
```

HIG 鏡像的處理：保留 Apple 的措辭與標題，平台小節重新標成 `Phone (iOS)`／`Tablet (iPadOS)`／`Desktop (macOS)`，刪除只適用 tvOS／visionOS／watchOS 的小節；`hig-lookup.md` 列出被省略的 35 頁與理由。數量我重數過：123＋35＝158，與 `AGENTS.md` 的「158 頁」一致；元件類 57 頁一致。

### 2.3 審查機制（`SKILL.md`）

- 載入策略：先載「必載集」（`accessibility`、`layout`、`typography`、`color`、`designing-for-ios`／`designing-for-macos`），再依畫面內容載 3 到 6 頁；每次審查約 8 到 12 檔，不載整個資料夾。引用要寫成 `檔名 › 標題`；沒有出處的要標成「我的判斷」。
- 八大設計原則（HIG `design-principles.md`，2026-06-08 重新引入，我查證）：Purpose、Agency、Responsibility、Familiarity、Flexibility、Simplicity、Craft、Delight。技能把它們當第一道篩子，每個配一個審查問題。
- 五個視角，依序：
  1. 輔助使用（失敗即 Critical）：文字尺寸（macOS 預設 13 pt、下限 10 pt）、對比度（至 17 pt 需 4.5:1；18 pt 以上或粗體 3:1）、控制項尺寸（macOS 預設 28×28、下限 20×20 pt）、不能只靠顏色、純鍵盤可用、動態效果可選、Reduce Motion／Transparency／Increase Contrast 都要有答案。
  2. 平台慣例（多半 High）：桌面版五條——每個指令都能在選單列找到（含每個工具列項目）、視窗可流暢縮放並用系統視窗控制、側邊欄至多兩層且可隱藏、設定視窗在 App 選單下且工具列固定、互動元素要有指標回饋與 hover 狀態。
  3. 視覺與工藝（High／Medium）：一色一義、字體少而層級清楚、對齊與漸進揭露、圖示一致、動態要有目的且簡短可取消且高頻互動少用；再加「工藝」六問（有沒有觀點？是不是範本？字體有沒有個性？結構有沒有承載資訊？大膽只花在一處？拿掉一個配件）。
  4. 互動（Medium）：載入、回饋、警示、破壞性動作、模態、資料輸入。
  5. 內容與文案（Medium）：標籤說清楚會發生什麼、大小寫一致、錯誤訊息說原因與解法。
- 嚴重度：Critical／High／Medium／Low；總評依標籤機械決定（有 Critical 就是 Critical issues…）。報告格式固定：Summary、Critical、Improvements、Craft notes、What works、Platform notes。
- 特別模式：App 圖示、輔助使用稽核、深色模式、Liquid Glass（觸發關鍵字有 Liquid Glass、glassmorphism、frosted、blur 與任何半透明列）、Apple Pay、程式碼稽核、導覽結構、iPhone Duo、onboarding、表單、生成式 AI、Widgets／Live Activities、單一元件檢查。
- 改進模式六步：以產品為本、先規劃精簡 token、先批判自己的計畫、用具體數字提修正（舉例：#999999 改 #595959，7.0:1）、依序做輔助使用→慣例→工藝→拋光、再批判一次。
- 工作守則：用數字不用形容詞、要嘛引用要嘛標成判斷、說框架的語言、點出取捨、審流程不只審畫面、不要過度挑剔、不要把個性磨平。

### 2.4 手寫 Liquid Glass 指南（`references/hig/liquid-glass.md`）

來源註明：整理自 `materials`（Apple 最後更新 2025-09-09）、`color`（2025-12-16）、`layout`／`branding`（2026-09-09）與各元件頁。

- 兩層模型：內容層（文字、圖片、清單、媒體、App 背景；要深度就用標準材質）與功能層（標籤列、工具列、側邊欄、導覽列、工作表、彈出視窗、警示等浮在內容之上的控制）；Liquid Glass 只屬於功能層。
- 規則：不在內容層用（例外：滑桿、開關在被操作時短暫變玻璃）；節制；用 scroll edge effect 區隔控制與內容，而不是鋪實色／半透明底；讓有視覺份量的內容延伸到側邊欄之下；減少工具列背景與著色控制。
- 變體：Regular（文字多、背景可能傷可讀性：警示、側邊欄、彈出視窗）；Clear（只在照片、影片等視覺豐富媒體之上，亮背景考慮 35% 暗化層）。兩者外觀都會隨系統的「偏好外觀」、降低透明度、提高對比改變。
- 顏色：玻璃本身無色；著色要少；強調主要動作是幫背景上色而不是上在符號上；不要多個控制都上色；彩色背景上標籤維持單色；品牌色留給主要動作與狀態，或移到內容層讓玻璃去取色；注意內容層顏色在靜止位置（例如可捲動畫面的頂端）仍要讓控制可讀。
- 標準材質：依語意選、不要依顏色選；在材質上用 vibrant 顏色；越厚對比越好、越薄越保留脈絡；macOS 有以用途命名的材質與兩種混合模式（behind window／within window）。
- 檢查表（7 項）：(1) 層次紀律；(2) 節制（自訂玻璃面不超過少數幾個、不疊玻璃）；(3) 變體適配；(4) 顏色預算（每畫面 1 至 2 個著色主要動作）；(5) 無障礙狀態（降低透明度要有不透明回退、提高對比要有更強的填色與邊框、減少動態效果要拿掉變形與折射動畫）；(6) 捲動邊緣；(7) 點擊區不縮到平台下限。
- 跨平台翻譯：模糊半徑、填色不透明度、飽和度增益等數字，作者自己標明那只是實用的起點、不是規格（Apple 只公布 35% 一個數字）。
- API 名稱：SwiftUI `glassEffect`、`GlassEffectContainer`；UIKit `UIGlassEffect`、`UIGlassContainerEffect`；AppKit 只列 `NSGlassEffectView` 與 `NSGlassEffectContainerView` 兩個名字，沒有用法。
- `UIDesignRequiresCompatibility`：Info.plist 的相容模式鍵，Apple 說是暫時用，且用 iOS／iPadOS／Mac Catalyst／macOS／tvOS 27 SDK 建置時系統會忽略（我查證為真，見第 0.1 節）。

### 2.5 `code-audit.md` 的 Liquid Glass 偵測表

在程式碼中找：玻璃套在清單列／卡片／背景（內容層玻璃）；單畫面自訂玻璃面太多或巢狀未用容器；`.clear` 疊在文字或單色背景；多於一兩個著色／`glassProminent` 動作；在工具列或標籤列下鋪實色／半透明底；手刻標籤列或工具列而非系統元件；`UIDesignRequiresCompatibility` 設為 YES（若用 27 SDK 建置，標 High）；沒有分支處理 `accessibilityReduceTransparency`／`UIAccessibility.isReduceTransparencyEnabled`；用 `BackdropFilter`／`BlurView`／`backdrop-filter` 模仿玻璃。結語：能移除自訂模仿就移除，不要微調。

### 2.6 HIG 鏡像保真度

抽查 `windows`（兩個關鍵句與 2025-06-09 日期一致）、`materials`（內容層規則、35% 暗化層、變更紀錄一致）、`design-principles`、`designing-for-iphone-duo`（頁面存在，2026-09-09）都與 Apple 即時網站一致。`hig-lookup.md` 所列日期可當作「Apple 這頁最近何時改」的線索。

### 2.7 repo 2 本身的小問題

- `SKILL.md` 寫 Apple 在 2026 年 6 月改了 15 頁，但自家 `hig-lookup.md` 標 2026-06-08 的只有 14 頁（我重數）。不影響內容，但說明那類數字要自己重數。
- 視角 1 把文字隨系統設定縮放當作失敗即 Critical 的通則；但 `typography.md` 明說 macOS 不支援 Dynamic Type（見第 4 節 G1）。

---

## 3. 依主題整理的指引

格式：指引（轉述）— 出處 — 來源標記。需要時加「WS：」寫對 WindowShade 的意涵（我的推論，不是 repo 的話）。

### (a) macOS 視窗、多工、視窗外框、工具列與側邊欄

1. 視窗有兩類：主要視窗（主導覽與內容）與輔助視窗（單一任務、不導覽到其他區域、通常有關閉鈕）。macOS 視窗由外框（可含視窗控制與工具列，少數情況有底部列）加本體組成。— repo 2 `windows.md › macOS window anatomy` — [HIG:windows]
2. 視窗有三種狀態：Main（每個 App 只有一個）、Key（同時只有一個、接受輸入）、Inactive。系統給三者不同外觀：key 視窗的關閉／最小化／縮放按鈕有顏色，inactive 與非 key 的 main 是灰的；inactive 視窗不使用 vibrancy，看起來較遠。自訂視窗要自己遵守這些外觀。— `windows.md › macOS window states` — [HIG:windows] — WS：卷簾條、藏進瀏海的視窗、浮動面板，都應隨視窗狀態改外觀。
3. 避免自製視窗 UI：系統視窗的外觀與行為使用者認得；自製外框或控制若不能完全吻合，會讓 App 顯得壞掉。— `windows.md › Best practices` — [HIG:windows]（我查證頁面現在仍有此句）— WS：卷簾條本質上就是自製視窗外框，這是最大的張力；稽核時要看它與系統視窗在圓角、陰影、按鈕、鍵盤可達性、狀態外觀的吻合度。
4. 別把關鍵資訊或操作放在視窗底部列或側邊欄底部，因為人們常把視窗移到底邊被遮住；底部列只放與內容直接相關的少量資訊，更多資訊改用 inspector。— `windows.md › macOS window states`、`layout.md › Desktop (macOS)`、`sidebars.md › Desktop (macOS)` — [HIG]
5. 避免把內容顯示在視窗頂邊的攝影機外殼之後（`layout.md` 指向 `NSPrefersDisplaySafeAreaCompatibilityMode`）；全螢幕要用系統提供的，因為它會自動避開部分 Mac 的攝影機外殼。— `layout.md › Desktop (macOS)`、`going-full-screen.md › Desktop (macOS)` — [HIG]
6. 全螢幕：讓使用者自己決定何時進入（視窗按鈕、View 選單、Control-Command-F）；避免自己做視窗模式的自訂選單；不要用程式縮放視窗；全螢幕時讓使用者能呼出 Dock；隱藏的工具列要有可靠的還原方式（游標移到螢幕頂端等）。— `going-full-screen.md` — [HIG] — WS：避免自製視窗模式選單這條與視窗管理器的本業相衝，宜把系統全螢幕視為不可侵犯、不要與之搶。
7. 多工在 Mac 是預設；視窗疊層陰影與狀態效果由系統負責。— `multitasking.md › Desktop (macOS)` — [HIG]
8. 面板（panel）：浮在視窗之上、外觀比主視窗低調、需要標題列以便擺放、App 啟用時全部帶到前面、App 非作用時隱藏、不列入 Window 選單的文件清單、通常不給最小化鈕、選單中用標題稱呼；HUD 風格只在媒體導向或標準面板會遮住關鍵內容時用、保持小、少用顏色。— `panels.md` — [HIG:panels] — WS：切換器、視窗瀏覽、活動面板可對照；WindowShade 若是無 Dock 圖示的代理型 App，「App 非作用時隱藏」要重新詮釋。
9. Window 選單：即使只有一個視窗也要有，含 Minimize 與 Zoom（讓全鍵盤控制的人可用）、Bring All to Front、依字母列出開啟的視窗（不列面板）；View 選單管外觀（顯示／隱藏項目標題要隨狀態變）、不管視窗導覽。— `the-menu-bar.md › Window menu`、`View menu` — [HIG:the-menu-bar]
10. 選單列：預設選單與順序要支援；永遠顯示同一組項目，不可用就停用而不是隱藏（但 context menu 相反，不相關就隱藏）；App 專屬指令也要放進選單列，這樣才找得到、可指派快捷鍵、全鍵盤控制可達；選單標題偏好單字。— `the-menu-bar.md › Best practices`、`App-specific menus`；`context-menus.md › Best practices` — [HIG]
11. 選單列圖示（menu bar extra）：偏好用符號；點擊顯示選單而非彈出視窗；是否顯示由使用者決定；不要假設它一定在（系統會隱藏）；另外提供 Dock 選單作為永遠可用的入口；選單列高 24 pt。— `the-menu-bar.md › Menu bar extras` — [HIG]
12. Dock 選單：適合列出目前或最近的視窗、以及 App 非最前時有用的少數動作；同樣的指令要在別處也能找到。— `dock-menus.md` — [HIG] — WS：與「Dock 懸停的視窗瀏覽」功能重疊，需有等價入口。
13. 工具列：慎選項目避免擁擠；系統會自動加溢出選單，不要自己加；可用 More 選單收次要動作；可自訂（iPadOS／macOS）；減少工具列背景與著色，改由內容層決定色彩並視需要用 scroll edge effect；標準元件的圓角與工具列同心，自訂元件也要同心；標題要有用、不用 App 名、短於 15 字元；至多約三組；每個工具列項目都要有對應的選單列指令。— `toolbars.md` — [HIG:toolbars，2025-12-16 針對 Liquid Glass 更新]
14. 側邊欄：可浮在 Liquid Glass 層，讓有視覺份量的內容延伸到它之下（水平捲動或背景延伸效果）；可自訂；至多兩層；讓使用者隱藏並提供 View 選單指令；視窗縮小時可自動收合；圖示顏色要有用途，且尊重使用者的系統強調色。— `sidebars.md` — [HIG:sidebars，2026-06-08]
15. 分割視圖（macOS）：用 1 pt 細分隔線、設定合理的最小／最大窗格尺寸、允許隱藏窗格並提供多種還原方式（工具列鈕、選單指令、快捷鍵）。— `split-views.md › Desktop (macOS)` — [HIG]
16. 工作表（macOS）：卡片狀、浮在父視窗上、父視窗變暗但使用者仍期待能操作 App 的其他視窗；重複輸入並觀察結果的場合改用面板；彈出視窗（popover）一次一個、可拖出成面板、改變大小要有動畫。— `sheets.md`、`popovers.md` — [HIG]
17. 設定：用 Command-逗號開、放在 App 選單而非視窗工具列、設定視窗的最小化／縮放鈕變灰、工具列固定、恢復上次看的窗格、預設值要好、設定要少、尊重系統層級設定而不要複製一份。— `settings.md` — [HIG]
18. 重啟時還原先前狀態，含視窗的位置與狀態。— `launching.md › Best practices` — [HIG] — WS：收起、藏入、平鋪狀態需跨重啟保存。
19. 拖放（macOS）：從非作用視窗拖出內容時不必先讓它變成作用視窗；拖曳約 3 pt 後就顯示半透明拖曳影像；給出能否放下的回饋；用游標樣式表示結果；多項目拖曳可加數字徽章。— `drag-and-drop.md` — [HIG]
20. repo 1 的 SwiftUI 對應：`NavigationSplitView` 當根、`.inspector()`、`.toolbar(removing: .title)`、`WindowBackgroundShapeStyle`、`WindowGroup` 最小框；背景延伸到側邊欄與 inspector 之下。— repo 1 `SKILL.md`、`platform-specifics.md`、`landmarks-patterns.md` — [Apple docs（Landmarks 範例，repo 引用）]；其中「背景延伸」與 HIG `sidebars.md`、`layout.md` 一致但 repo 未引用。

### (b) Liquid Glass 材質（何時用、分層、著色、可讀性、無障礙回退、同心圓角與形狀）

何時用：
1. 玻璃是「功能層」：控制與導覽浮在內容之上；不要用在內容層（用標準材質）。例外是滑桿、開關在被操作時短暫變玻璃。— repo 2 `materials.md`、`liquid-glass.md`；repo 1 `SKILL.md › Core Concept` — [HIG:materials（我查證仍如此）]（repo 1 沒標出處）
2. 自訂控制要節制，只給最重要的功能元素；系統標準元件會自動採用。— `materials.md`；[WWDC25-310（我查證：只給頂層功能層的最重要控制）] — [HIG]＋[WWDC]
3. Regular 與 Clear：Clear 只用在浮於視覺豐富背景（照片、影片）之上的元件；亮底可考慮 35% 暗化層；文字多或背景可能傷可讀性用 Regular。— `materials.md`；repo 1 `api-reference.md` 說法一致 — [HIG:materials]
4. 系統設定會改變兩種變體的外觀：偏好外觀（macOS 26.1 起的 Clear／Tinted，我查證）、降低透明度、提高對比。— `materials.md`；repo 1 只提到 iOS 26.1 的 Tinted 模式 — [HIG]；macOS 26.1 事實 [我查證，網路搜尋]

分層與容器：
5. 玻璃無法取樣其他玻璃，所以相鄰的玻璃要放進同一容器共用取樣區域，外觀才一致、效能也較好；SwiftUI `GlassEffectContainer`、AppKit `NSGlassEffectContainerView`（`spacing` 是開始合併的距離）。— repo 1 `SKILL.md`、`pitfalls-and-solutions.md`；repo 2 `code-audit.md` — repo 1 沒標出處；[WWDC25-323、WWDC25-310 逐字稿（我查證）]、[Apple docs：NSGlassEffectContainerView 說明容器可減少渲染 pass]
6. AppKit 用法重點（repo 都沒寫）：把內容放進 `NSGlassEffectView.contentView`，不要把玻璃當兄弟 view 放在內容後面；玻璃用 Auto Layout 綁定 `contentView`。— [WWDC25-310（我查證，經 WebFetch 摘要）]
7. 不要疊玻璃：玻璃疊玻璃會模糊層次。— repo 2 `liquid-glass.md` 檢查表第 2 項（[repo 意見，與 WWDC25-310 的取樣說明一致]）
8. 變形：SwiftUI 的配方是同容器、同 namespace、`withAnimation`、條件式插入而非 opacity；`glassEffectUnion(id:namespace:)` 把同 ID 同形狀的玻璃合成一個形狀。— repo 1 `SKILL.md`、`pitfalls-and-solutions.md`、`api-reference.md`；[Apple docs：Applying Liquid Glass to custom views（我查證）] — 注意 repo 1 的 union 簽名寫錯（第 4 節 F1）
9. 效能：太多容器或容器外的大量玻璃會拖慢；限制同時存在的玻璃數量。— [Apple docs 文章（我查證）]；repo 1 說每個玻璃用 3 張離屏貼圖，屬 [無出處]

著色與顏色：
10. 玻璃本身無色，取自後方內容；顏色要節制；強調主要動作是幫背景上色，而不是上在符號或文字上；不要在多個控制的背景上色；彩色內容上的工具列／標籤列維持單色；強調色與品牌色留給主要動作與狀態；想表達品牌就把顏色放進內容層。— `color.md › Liquid Glass color`、`buttons.md`、`branding.md`、`toolbars.md` — [HIG（color 2025-12-16、branding 2026-09-09）]
11. 單一外觀的 App 也要提供淺色與深色顏色，讓玻璃的適應性運作。— `color.md › Best practices` — [HIG]
12. 每畫面主要（prominent）按鈕 1 至 2 個。— `buttons.md › Style` — [HIG]
13. repo 1：用 `.tint` 暗示重點、`.glassProminent` 做主要動作；macOS 玻璃按鈕一律加 `.tint(.clear)`。前者與 HIG 一致但 repo 未引用；後者見第 4 節 F5。

可讀性：
14. 靜止位置也要可讀：內容層顏色偶爾會捲到控制之下，但頂端等預設狀態要保持清晰。— `color.md` — [HIG]
15. 材質上用 vibrant 顏色；越厚越好讀、越薄越保留脈絡；對比度門檻見 (d)。— `materials.md` — [HIG]
16. 用 scroll edge effect 而不是自鋪實色或半透明底；偏好 automatic 樣式；只在捲動視圖位於浮動元素之後時用；每個視圖一個；它不是裝飾，不會像遮罩那樣擋或壓暗。— `scroll-views.md › Scroll edge effects`、`layout.md › Visual hierarchy` — [HIG（scroll-views 2026-06-08）]
17. repo 1：在延伸背景圖上疊漸層讓文字可讀、測試不同圖片與主題。— `pitfalls-and-solutions.md`、`api-reference.md` — [無出處]，做法合理
18. macOS 深色模式的「桌面著色」：選石墨強調色時視窗背景會取桌面色，自訂元件在中性狀態可帶一點透明度以融入，但有顏色的狀態不要帶。— `dark-mode.md › Desktop (macOS)` — [HIG]

無障礙回退：
19. 要在降低透明度與提高對比（單獨與同時）、深淺外觀下測試；深色加提高對比可能讓深色文字更難讀。— `dark-mode.md` — [HIG]
20. repo 2 檢查表：降低透明度要有不透明回退、提高對比要有更強填色與邊框、減少動態效果要拿掉變形與折射動畫。— `liquid-glass.md` 第 5 項 — [repo 意見]；對原生玻璃，系統會自己調整，需要自備回退的是你自己疊加的暗化層、陰影、描邊（我的推論）
21. repo 1：系統自動處理，不需改程式；同檔另給手動覆寫範例（見第 4 節 F3，該範例有問題）。

同心圓角與形狀：
22. 工具列內的標準元件圓角與工具列同心，自訂元件也要同心。— `toolbars.md` — [HIG]
23. 在圓角容器內用均勻邊距、同心放置；靠角落的圓角元素用相對容器的形狀（ContainerRelativeShape）而不是寫死數值；內容不要畫到邊緣。— `live-activities.md › Creating Live Activity layouts` — [HIG]，主題是 Live Activity，WS 只能類比
24. 視窗新圓角更大，帶工具列的視窗用更大的圓角來同心包住玻璃工具列；可用 `NSView.LayoutRegion` 取得含圓角適應的 safe area。— [WWDC25-310（我查證，經 WebFetch 摘要）]，兩個 repo 都沒寫
25. SwiftUI 形狀：預設 capsule；大元件用 `rect(cornerRadius:)`；同心有 `ConcentricRectangle`、`Shape.rect(corners:isUniform:)`、`.concentric(minimum:)`、`containerShape(_:)`。— [Apple docs（我查證）]；repo 1 寫的 `.containerConcentric` 查不到（F4）

### (c) 動態、彈簧、手勢、打斷

動態原則（HIG）：
1. 動態要有目的、不喧賓奪主；要可選（不能是唯一傳達重要資訊的方式，用觸覺或聲音補強）；回饋動態要符合手勢與預期（從頂端滑下顯示，就不要往側邊滑走關閉）；簡短而精準；高頻互動少加動態；讓使用者能取消、不必等動畫跑完。— `motion.md › Best practices`、`Providing feedback` — [HIG:motion，2025-09-09]
2. Liquid Glass 的動態對觸控回應較強、對觸控板較收斂。— `motion.md` 前言 — [HIG]
3. 減少動態效果開啟時：收緊彈簧以減少彈跳、動畫直接追蹤手勢、避免對 z 軸深度做動畫、把 x／y／z 的位移轉場換成淡入淡出、避免動畫進出模糊；也要減少自動與重複的動畫（縮放、周邊動態）。— `accessibility.md › Cognitive` — [HIG:accessibility，2025-06-09]
4. 自動消失的限時 UI 對需要較多時間的人有問題，偏好由明確動作關閉。— `accessibility.md › Cognitive` — [HIG] — WS：瀏海活動、懸停面板需有固定／延長方式。
5. 動畫時長：Live Activity 的系統與自訂動畫上限 2 秒；版面改變時，把既有元素動畫到新位置，而不是移除再重新加入；避免元素重疊，必要時先淡出再在新位置淡入。— `live-activities.md › Adding transitions…`；`widgets.md`（也是 2 秒）— [HIG（live-activities 2026-10-13）] — WS：只能類比到瀏海活動。
6. 彈出視窗改變大小時要有動畫，不要看起來像換了新的。— `popovers.md` — [HIG]

手勢與輸入：
7. 立即回應並預示結果、說明手勢何時不可用、提供不只一種操作方式、遵守一致的期待。— `gestures.md › Best practices` — [HIG:gestures，2024-09-09]
8. 自訂手勢只在必要時加，且須：可發現、好做、與其他手勢有區別、不是唯一入口；要提供學習時機；快捷手勢是補充而不是取代；避免與系統 UI 手勢衝突。— `gestures.md › Custom gestures` — [HIG]
9. 避免重新定義系統級觸控板手勢（Mission Control、App Exposé、Show Desktop、Launchpad、通知中心邊緣滑入、全螢幕 App 間滑動等），而且使用者可自訂這些手勢的手指組合。— `pointing-devices.md › Best practices`、`Desktop (macOS)` 手勢表 — [HIG:pointing-devices，2023-06-21]
10. 行動不便面向：常用互動用最簡單的手勢、避免自訂多指多手勢、提供手勢的替代方式。— `accessibility.md › Mobility` — [HIG]
11. 用指標顯示與隱藏會自動最小化或淡出的控制。— `pointing-devices.md › Best practices` — [HIG] — WS：支持「邊緣懸停顯示」這類設計，但要同時有其他入口。
12. 捲動：支援預設捲動手勢與鍵盤；自訂捲動要保留彈性行為；讓使用者看得出可捲動；同方向不要巢狀捲動；分頁捲動可留一點重疊；自動捲動只捲必要的量。— `scroll-views.md` — [HIG] — WS：對應「捲動式 tiling」。
13. 觸控板觸覺（macOS 只有三種模式，經 `NSHapticFeedbackPerformer`）：alignment（拖曳物件對齊時）、level change、generic。要簡短、與動畫強度匹配、可關閉、不要過度使用。— `playing-haptics.md › Desktop (macOS)` — [HIG:playing-haptics] — WS：alignment 恰好適合貼齊邊緣。
14. SF Symbols 動畫（bounce、wiggle、breathe、replace 等）要有明確目的、不要多。— `sf-symbols.md › Animations` — [HIG]

repo 1 在這一類的內容：
15. 變形動畫要用 `withAnimation`；範例用 `.bouncy`；`rotationEffect` 會讓玻璃形狀變形（改用 UIKit 橋接，只在 iOS 有 `UIGlassEffect`）；`.interactive()` 在 iOS 有縮放、彈跳、閃光。— `pitfalls-and-solutions.md`、`api-reference.md` — [無出處／部分 WWDC25-323]
16. 缺口：兩個 repo 都沒有彈簧參數、時長表、手勢速度與遲滯（hysteresis）、打斷與重定向（retarget）規則。補充來源見第 5 節。

### (d) HCI 基本功（回饋、可發現性、一致性、輔助使用、鍵盤）

回饋與寬容：
1. 傳達方式要配合資訊的重要性：狀態用被動方式就地顯示；警告資料損失才用打斷式；警示只給關鍵且最好可執行的資訊；預期的資料損失（例如丟垃圾桶）不警告；重要動作完成才確認；指令不能執行時要說明原因；回饋要多通道（顏色、文字、聲音、觸覺）。— `feedback.md` — [HIG:feedback]
2. 警示要少、不要在 App 啟動時出現、不要為常見且可復原的動作出警示、預設按鈕不要用 OK（除非純資訊）。— `alerts.md` — [HIG]
3. 復原：支援多次 Undo、Undo／Redo 標籤要說清楚目標、要顯示復原的結果（結果若在畫面外要捲過去）；macOS 放在 Edit 選單並支援 Command-Z／Shift-Command-Z。— `undo-and-redo.md` — [HIG]
4. 八原則中的 Agency：不擋路、給探索的自由、協助從錯誤復原。— `design-principles.md › Agency` — [HIG（2026-06-08，我查證）]

可發現性與教學：
5. 選單列讓人學到 App 能做什麼；Context menu 預設隱藏，所以其項目要在主介面也找得到；Dock 選單同理。— `the-menu-bar.md`、`context-menus.md`、`dock-menus.md` — [HIG]
6. Tooltip（macOS）：只描述被指到的控制、以動詞開頭、不重複控制名稱、60 至 75 字元以內、句首大寫；可依狀態變化。— `offering-help.md › Desktop (macOS)` — [HIG]
7. Onboarding：用互動教、優先用情境提示（TipKit 類）、可略過且之後找得到、不要塞太多；Tip 要短（一兩句）、只給簡單功能（超過三步就太複雜）、設定資格規則與顯示頻率。— `onboarding.md`、`offering-help.md › Creating tips` — [HIG]
8. 權限與透明：說明為何要權限；非必要不要在啟動時請求；若必要則可整合進 onboarding。— `privacy.md`、`design-principles.md › Responsibility` — [HIG] — WS：WindowShade 需要輔助使用與螢幕錄製類權限，屬於必要型。

一致性：
9. 保持視覺與互動一致；使用者面向的詞用「視窗」而不是「scene」；同一概念同一個名字。— `design-principles.md › Familiarity`、`windows.md › Best practices`；`writing.md` — [HIG]
10. 品牌服從內容；用熟悉元件表達品牌；不要處處放 logo。— `branding.md` — [HIG（2026-09-09）]

輔助使用：
11. macOS 預設字級 13 pt、下限 10 pt；避免超細字重（Ultralight、Thin、Light）；macOS 不支援 Dynamic Type；對比度（至 17 pt 需 4.5:1、18 pt 以上 3:1、粗體 3:1）；系統顏色優先；不只靠顏色；控制項預設 28×28 pt、下限 20×20 pt；留意間距（有邊框約 12 pt、無邊框約 24 pt）。— `accessibility.md`、`typography.md` — [HIG]
12. VoiceOver：為自訂元素加標籤、版面或內容變動要通知（AccessibilityNotification）、指定分組與順序、純裝飾圖片排除。— `voiceover.md` — [HIG:voiceover，2025-03-07]
13. 全鍵盤控制要能操作視窗、選單、控制與系統功能；也支援 Switch Control、Voice Control；避免覆寫系統快捷鍵。— `keyboards.md`、`accessibility.md › Speech`、`Mobility` — [HIG]

鍵盤：
14. 不要重新指派標準快捷鍵；自訂快捷鍵只給最常用的 App 專屬指令；主修飾鍵用 Command、Shift 當次要、Option 少用、避免用 Control（系統大量使用）；多修飾鍵順序為 Control、Option、Shift、Command；不要為無關指令在既有快捷鍵上加修飾鍵；系統會自動在地化與鏡像。— `keyboards.md › Custom keyboard shortcuts` — [HIG:keyboards，2025-06-09]
15. `keyboards.md` 的系統快捷鍵表就是衝突清單：Command-Tab、Shift-Command-Tab（切 App）、Command-反引號與 Shift-Command-反引號（切同 App 視窗）、Command-M 與 Option-Command-M（最小化）、Command-H 與 Option-Command-H（隱藏）、Control-F2／F3／F4／F5／F6（移動焦點到選單列／Dock／視窗／工具列／面板）、F11（顯示桌面）、Control-Command-F（全螢幕）、Option-Command-D（顯示／隱藏 Dock）、Command-逗號（設定）等。— `keyboards.md › Standard keyboard shortcuts` — [HIG]
16. 設定：預設值要給最多人最好的體驗、設定越少越好、不要複製系統層級設定（例如輔助使用、捲動行為）。— `settings.md` — [HIG]

### (e) 瀏海活動（以 Live Activity 類比；HIG 中專談靈動島呈現方式的就是這一頁）

- 比喻要點：只給有起訖的任務；聚焦一眼可讀的資訊；不放廣告；不顯示敏感資訊（旁人看得到）；文字用中等以上字重；互動要少且集中在單一元素；只在有新內容時更新；只對必要事件提醒；用一個動態活動輪播多事件而不是多個並列；任務結束就立刻結束；讓使用者容易關閉；呈現分 compact、minimal、expanded 三種，內容要貼近攝影機外殼、不要加大量間距、不要畫到邊緣。— `live-activities.md` — [HIG:live-activities，2026-10-13]
- 限制：這頁是 iPhone 的 Dynamic Island 與鎖定畫面；Mac 只會在選單列顯示由配對 iPhone 傳來的 Live Activity。macOS 沒有第三方瀏海 API，所以這些只能當設計類比。

---

## 4. 旗標：錯誤、過時、僅 iOS、無出處、互相矛盾

### Repo 1（liquid-glass-skill）

- F1 錯誤：`api-reference.md` 把 `glassEffectUnion` 寫成 `(_ id, in: namespace)`。Apple 文件的簽名是 `glassEffectUnion(id:namespace:)`，`id` 是可選且須 `Hashable & Sendable`。[Apple docs，我查證]
- F2 有爭議：多處斷言 `.interactive()` 僅限 iOS、macOS 沒有。WWDC25-323 講者把它放在 iOS 脈絡；但 Apple 的 Applying Liquid Glass to custom views 文章說它讓自訂元件回應觸控與指標兩種輸入；`Glass.interactive(_:)` 的可用性列有 macOS 26.0；AppKit 有 `NSGlassEffectView.effectIsInteractive`；HIG `motion.md` 說觸控板下的效果較收斂而不是沒有。結論：在 macOS 應視為效果較收斂，需實機確認，不要直接假設沒有。[Apple docs／HIG／WWDC，我查證]
- F3 看起來有問題：`api-reference.md` 與 `migration-guide.md` 示範 `reduceTransparency ? .identity : .regular`。Apple 對 `Glass.identity` 的描述是內容不受影響、如同沒套用任何玻璃效果，所以這是把玻璃整個拿掉；若沒補不透明背景，文字會失去襯底，可讀性反而更差。同檔又說這類設定不需要改程式碼、系統自動處理，兩者自相矛盾。[Apple docs，我查證；其餘為我的判斷]
- F4 查不到：`.rect(cornerRadius: .containerConcentric)`。Apple 文件的同心 API 是 `ConcentricRectangle`、`Shape.rect(corners:isUniform:)` 搭配 `.concentric(minimum:)`，容器形狀用 `containerShape(_:)`。我沒能在 `ConcentricRectangle` 頁找到 `.containerConcentric`；可能是早期 beta 寫法，採用前要在目標 SDK 編譯確認。[Apple docs，我查證；結論為未能證實]
- F5 無出處且過度概括：macOS 玻璃按鈕一律加 `.tint(.clear)`。repo 把它放在號稱摘自 Apple Landmarks 範例的程式碼中，並在多處升級成通則（我沒有核對 Apple 原始範例）。可能只對特定 OS 版本或特定按鈕配置有效，應在目標 OS 上實測。[無出處]
- F6 無出處：說每個玻璃元素會建立一個 `CABackdropLayer`、各用 3 張離屏貼圖，屬私有實作細節。Apple 文件只說容器可減少渲染 pass／提升效能。[無出處]
- F7 時效：Menu 標籤變形在 26.0 與 26.1 的不同解法、容器弄壞 Menu 變形、`rotationEffect` 玻璃變形，都是 iOS 26.0 至 26.1 的觀察（repo 日期 2026-02-14），到現在的版本可能已修；且都不是 macOS 專屬。[無出處]
- F8 僅 iOS：標籤列與 `tabBarMinimizeBehavior`、`tabViewBottomAccessory`、`Tab(role: .search)`、工作表 detent 與 `presentationBackground`、`UIDevice` idiom、`topBarLeading`／`topBarTrailing`、iPhone 工具列可見性、SF Symbol 從 circle 變體改成 none 變體的建議。對 AppKit 視窗管理 App 基本不適用。（註：`tabBarMinimizeBehavior` 的可用性清單含 macOS 26.0，但它是標籤列行為，對 WindowShade 沒用。）
- F9 僅 iPhone 措辭：`SKILL.md` 核心觀念說玻璃會隨裝置動作產生高光；裝置動作只存在於 iPhone／iPad，Mac 沒有。
- F10 薄弱且無出處：`platform-specifics.md` 的 watchOS、tvOS、visionOS 各節（例如說 `.interactive()` 可搭配數位表冠）。
- F11 與 HIG 不一致的意見：`SKILL.md` 的架構建議之一是工具列偏好帶文字標籤的符號按鈕；HIG `toolbars.md` 偏好簡單符號（不要邊框）、有文字的動作要與符號動作分開。屬 [repo 意見]。
- F12 覆蓋缺口：沒有 `NSGlassEffectView`、`NSGlassEffectContainerView`、`NSBackgroundExtensionView`、`NSSplitViewController`、`NSToolbarItem` 樣式、視窗圓角、scroll edge effect（AppKit 的 `NSScrollEdgeEffectStyle`）。只引 WWDC25-323，沒有 310。
- F13 簽名小簡化：`Glass.interactive(_ isEnabled: Bool = true)`；`tint` 接受可選顏色。影響很小。

### Repo 2（apple-design-skill）

- G1 macOS 外推錯：視角 1 把文字隨系統設定縮放、最大字級下版面仍可用，列為失敗即 Critical；`typography.md` 明說 macOS 不支援 Dynamic Type。macOS 該查的是 13／10 pt 的預設與下限、避免細字重、對比度，而不是 Dynamic Type。
- G2 從 iPadOS 外推：桌面視角要求所有可互動元素都有指標回饋與 hover 狀態，其依據是 `pointing-devices.md` 的 iPadOS 小節（highlight／lift／hover 效果、磁吸、12／24 pt 點擊區留白）。macOS 小節只有點擊與手勢表和游標樣式表；macOS 的 hover 與 tooltip 由系統控制項負責。因此這條是技能的整理，不是 Apple 對 macOS 的硬規定。
- G3 Apple 自己互相矛盾：`buttons.md` 說按鈕點擊區至少 44×44 pt（visionOS 60×60）；`accessibility.md` 說 macOS 控制項預設 28×28、下限 20×20。技能採用後者，但沒指出矛盾。稽核 macOS 請用 28／20。
- G4 小數字不符：`SKILL.md` 說 Apple 在 2026 年 6 月改了 15 頁，其自家索引只有 14 頁標 2026-06-08。
- G5 無關的數字：手寫指南裡 CSS／Flutter 模仿玻璃的模糊半徑、填色不透明度、飽和度增益是作者自己的起點（它自己也標明），對使用原生 `NSGlassEffectView` 的 WindowShade 不適用。
- G6 對原生玻璃要調整：降低透明度時要有不透明回退，這點對 CSS 模仿成立；對原生玻璃是系統自動調整，需要自備回退的是你另外疊的暗化層、陰影、描邊（我的推論）。
- G7 類比限制：Live Activity／Dynamic Island 頁是 iPhone 與鎖定畫面；Mac 只在選單列接收配對 iPhone 的活動；其說 Dynamic Island 使用不透明黑色背景，與 WindowShade 的浮動玻璃層設計並不一致。壓縮／極簡／展開的詞彙與 2 秒動畫上限只能當設計類比。
- G8 工藝視角是作者意見：偵測三種常見生成式介面範本、拿掉一個配件、大膽只花在一處等做法沒有 Apple 出處（作者明說是工作室經驗）。對一個細節控的工具型 App 可參考，但不是 HIG。
- G9 嚴重度制度是作者的設定：輔助使用失敗一律 Critical；對公用程式型 App 可能過嚴，視情況調整。
- G10 無關內容：iPhone Duo、Apple Pay、Widgets、AR、Flutter／Electron 翻譯等；技能本身要求每次只載 8 至 12 檔，所以不會帶進來，但要知道它們存在。
- G11 授權：HIG 文字屬 Apple，repo 自述是為了 AI 輔助設計審查而轉載，並無授權條款覆蓋鏡像內容；本機當參考可以，不要再轉發。
- G12 `buttons.md`、`pointing-devices.md` 等頁混有 iPadOS 專屬段落（指標效果、磁吸、tab bar、detent、`sidebarAdaptable`），閱讀時看小節標題 `Tablet (iPadOS)`／`Mobile (iOS, iPadOS)` 再決定是否適用。

### 兩個 repo 之間

- 兩者都主張玻璃只屬於功能層，彼此一致，也與 HIG 一致。
- 玻璃無法取樣其他玻璃這一點只有 repo 1 說；repo 2 的檢查表只說玻璃疊玻璃會模糊層次。前者有 WWDC 逐字稿支持（我查證）。
- 無障礙回退：repo 1 說系統自動、同時給了手動 `.identity`（問題見 F3）；repo 2 說要自備不透明回退（對 CSS 成立，對原生玻璃要調整，見 G6）。

---

## 5. 缺口與建議補充的一手來源（皆為我查證存在；內容摘要來自頁面，採用前請再看原片）

1. 彈簧與打斷：WWDC18-803「Designing Fluid Interfaces」——把彈簧簡化為 damping 與 response，建議從 100% damping（不過衝）開始，彈跳只在手勢帶有動量時用；談持續重新導向與打斷；手勢約 10 pt 遲滯後才開始、一對一追蹤、並行偵測競爭手勢；用速度投影選擇落點。WWDC23-10158「Animate with springs」——用 duration 與 bounce 兩個參數（bounce 範圍 -1.0 到 1.0）；一般從 bounce 0 開始，約 0.15 較俏皮，超過約 0.4 要小心；新動畫打斷舊動畫時，彈簧以當下速度當作初速度，手勢結束時自動接續速度。
2. AppKit 版 Liquid Glass：WWDC25-310「Build an AppKit app with the new design」——`NSGlassEffectView` 的 `contentView` 規則、`NSGlassEffectContainerView`、`NSBackgroundExtensionView`、`NSSplitViewController` 側邊欄與 inspector 的玻璃、工具列項目樣式（`isBordered`、`style = .prominent`、`backgroundTintColor`）、視窗圓角與同心、`NSView.LayoutRegion` safe area、scroll edge effect。該場次說明建議先看「Get to know the new design system」。
3. 瀏海與 safe area：HIG 只有兩句話（`layout.md`、`going-full-screen.md`）加 `NSPrefersDisplaySafeAreaCompatibilityMode` 指標；沒有瀏海幾何與 API 細節。需要查 AppKit 文件。
4. 視窗管理脈絡：兩個 repo 都沒提 macOS 15 起的原生視窗平鋪、拖曳到邊緣貼齊、Stage Manager、Spaces、Mission Control 與視窗管理器的互動。（這條是我自己的知識，不是 repo 內容，也未在本次查證。）
5. macOS 27：兩個 repo 都沒有可驗證的 macOS 27 專屬內容，僅 `UIDesignRequiresCompatibility` 在 27 SDK 被忽略這一點（已查證）。

---

## 6. 稽核問題清單（19 條，給 macOS 視窗管理 App）

A. 視窗與外框
1. 卷簾條、藏進瀏海的視窗、浮動面板是否隨 main／key／inactive 切換外觀（inactive 不用 vibrancy、控制鈕變灰）？它與系統視窗在圓角、陰影、控制鈕行為、全鍵盤控制可達性上吻合到不會讓人覺得壞掉的程度嗎？〔`windows.md`〕
2. 有沒有任何關鍵資訊或操作放在視窗、卷簾條、側邊欄或面板的底部？當視窗被拖到螢幕底外或收起時仍可用嗎？〔`windows.md`、`layout.md`、`sidebars.md`〕
3. 瀏海：overlay、藏入的視窗與活動膠囊是否避開攝影機外殼、使用系統 safe area 與系統全螢幕而不自行硬算？是否沒有程式式縮放全螢幕視窗、也沒有阻止使用者呼出 Dock？〔`layout.md`、`going-full-screen.md`〕
4. 每個動作（收起、藏入瀏海、貼齊／平鋪、捲動式 tiling、PiP、Slide Over、視窗瀏覽、切換器）是否都能從選單列（或選單列圖示）與 Dock 選單找到，且項目常駐、不可用時停用而非隱藏？並有 Window 選單慣例（Minimize／Zoom／Bring All to Front）的對應？〔`the-menu-bar.md`、`toolbars.md`、`dock-menus.md`〕
5. 面板類 UI（切換器、視窗瀏覽、活動面板）是否符合面板慣例：只在需要時出現、有標題概念（給輔助技術）、不給最小化、不列入 Window 選單文件清單、HUD 風格只在必要時？設定是否可用 Command-逗號開、記得上次窗格？〔`panels.md`、`settings.md`〕
6. 重啟後，收起、藏入、平鋪的狀態與位置是否還原？〔`launching.md`〕

B. Liquid Glass
7. 玻璃是否只出現在浮動控制層（切換器、懸停瀏覽、瀏海活動、卷簾條控制列），沒有出現在縮圖、列、卡片等內容上？每畫面自訂玻璃面是否只有少數幾個、沒有玻璃疊玻璃？〔`materials.md`、`liquid-glass.md` 檢查表 1 至 2、WWDC25-310〕
8. 相鄰玻璃是否放進 `NSGlassEffectContainerView` 並調好 `spacing`？內容是否經 `NSGlassEffectView.contentView` 放入，而不是疊在玻璃後面？〔WWDC25-310、Apple docs——兩個 repo 都沒寫〕
9. 變體：文字多或背景不可控（任意桌面、任意視窗）是否用 regular？clear 是否只用在媒體豐富背景，亮底有評估 35% 暗化層？〔`materials.md`〕
10. 靜止狀態可讀性：在淺色／深色／高飽和桌布，與「提高對比」「降低透明度」「Liquid Glass Tinted（macOS 26.1 起）」的組合下，文字與圖示是否達 4.5:1（18 pt 以上或粗體 3:1）？你自己疊的暗化層、陰影、描邊在這些模式下有沒有退路？〔`accessibility.md`、`dark-mode.md`、`color.md`、`materials.md`〕
11. 顏色預算：每畫面著色的主要動作是否不超過 1 至 2 個、標籤維持單色、品牌色只給主要動作與狀態？〔`color.md`、`buttons.md`、`branding.md`〕
12. 圓角是否與其容器（視窗圓角、膠囊、瀏海）同心、邊距均勻，而非寫死？〔`toolbars.md`、`live-activities.md`、WWDC25-310〕
13. 玻璃條下方若有捲動內容，是否用 scroll edge effect 而不是自鋪實色或半透明底？〔`layout.md`、`scroll-views.md`〕

C. 動態與手勢
14. 動畫是否有目的、簡短、可取消、可中途反向；高頻動作（收起／展開、切換）是否幾乎沒有額外動態？減少動態效果開啟時是否：收緊彈簧、改淡入淡出、不做 z 軸深度動畫、不動畫進出模糊？瀏海活動動畫是否在 2 秒內？彈簧是否用一組一致的參數（duration 與 bounce，或 response 與 damping），動畫被中途打斷時是否以當下速度接續？〔`motion.md`、`accessibility.md`、`live-activities.md`；彈簧與打斷來自 WWDC18-803、WWDC23-10158，兩個 repo 都沒寫〕
15. 每個手勢是否即時回饋並預示結果、不可用時有說明、有非手勢的替代入口（選單、快捷鍵、按鈕）？是否不與系統觸控板手勢（Mission Control、App Exposé、Show Desktop、Launchpad、通知中心、全螢幕 App 間滑動）及系統快捷鍵（Command-Tab、Command-反引號、Control-F 系列、Command-M／H、Control-Command-F 等）衝突？全域快捷鍵是否可由使用者自訂、避免只靠 Control 當修飾鍵？貼齊邊緣等離散事件是否用得上 alignment 觸覺、且可關閉？〔`gestures.md`、`pointing-devices.md`、`keyboards.md`、`playing-haptics.md`〕

D. HCI 基本功
16. 回饋與寬容：狀態是否就地呈現而不是用警示？只有不可預期且不可逆的損失才警告？收起、藏入、平鋪能否 Undo 或一鍵復原（Restore all／Bring all to front），復原結果可見？〔`feedback.md`、`alerts.md`、`undo-and-redo.md`、Agency 原則〕
17. 可發現性：圖示按鈕有 tooltip（60 至 75 字元內、句首大寫、不重複名稱）？手勢是否透過互動式、可略過、事後找得到的 onboarding 或情境 tip 教學？輔助使用與螢幕錄製權限是否在需要時、用清楚的理由請求？〔`offering-help.md`、`onboarding.md`、`privacy.md`、`gestures.md`〕
18. 輔助使用：全鍵盤控制能否到達每個控制項？VoiceOver 標籤是否齊全，視窗收起／藏入／平鋪等版面改變是否通知（AccessibilityNotification）？自動消失的 UI（瀏海活動、懸停面板）是否有固定或延長的方式？〔`accessibility.md`、`voiceover.md`、`keyboards.md`〕
19. 瀏海活動（以 Live Activity 為類比）：是否只用於有起訖的任務、以單一活動輪播而非多個並列、結束即移除、僅在內容有變時更新、僅對必要事件提醒、可逐項關閉、不顯示旁人可見的敏感資訊、互動集中在單一元素？〔`live-activities.md`，僅類比〕

---

## 7. 我沒做的事

- 沒有驗證任何 macOS 27 專屬行為，也沒有在實機上測 `NSGlassEffectView` 的 `effectIsInteractive` 對指標的實際效果。
- 沒有核對 repo 2 `code-audit.md` 的 Apple Pay 與 App Review 4.9 條目（與 WindowShade 無關）。
- WebFetch 的摘要層是小模型；API 簽名與日期我認為可靠，WWDC 逐字稿衍生的敘述請再對原片。
- 沒有嘗試安裝或執行任何技能。
