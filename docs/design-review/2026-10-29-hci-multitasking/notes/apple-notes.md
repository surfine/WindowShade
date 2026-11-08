# Apple 官方視窗與多工指引簡報（供 WindowShade 稽核）

產出日：2026-10-29。資料全部來自 Apple 一手來源（developer.apple.com 的 HIG、WWDC 場次、文件與版本說明、apple.com 新聞稿與產品頁、support.apple.com）。本機為 macOS 27.0.1（build 26A434），少數項目用本機讀取補證。

標記：
- [V] 本次抓取並讀過原文，已核對。
- [D] 在這台 macOS 27.0.1 上讀取到的證據（非公開文件）。
- [U] 未驗證，或只是推論，使用前要再查。
- [P] 只有媒體報導，沒有 Apple 一手來源（本文只用來標示「不採信」）。

引文都是 Apple 原文（英文），每段不超過 20 字。API 名稱、介面標籤、網址保持原文。

---

## 0. 先讀這幾件最影響稽核的事

1. HIG 對 macOS 的視窗管理幾乎沒寫。我把 HIG 全部 172 頁抓下來全文搜尋：「Stage Manager」0 頁、「hot corner」0 頁、「Touch on Mac」0 頁、「notch」在內文 0 次；「tiling／tiled」只出現在 Multitasking 的 iPadOS 段，以及 The menu bar 的 Window 選單（Arrange in Front「neatly tiled arrangement」）；Right to left 那一筆是 multilingual 的字串誤中。也就是說，Sequoia 的視窗磁貼、Stage Manager、Mission Control 拖曳等行為，要以 support.apple.com 與 WWDC 為準，不能指望 HIG。[V]
2. HIG 的「Split views」是 App 內的 NSSplitView 元件，不是 macOS 的「Split View」全螢幕雙 App 模式。HIG 沒有 macOS Split View 模式的頁面。[V]
3. macOS 27 在視窗管理上，Apple 一手來源能確認的只有：所有視窗改成同一種較緊的圓角、Liquid Glass 調整、統一工具列、邊到邊側邊欄、觸控（Touch on Mac）、新 MacBook Pro 的 Dynamic Island、原生 Live Activities、新快速鍵、`disableScreenCornerInteractions`。磁貼、Stage Manager、Mission Control、Split View 的使用者流程，在 support 頁面上 macOS 15、26、27 三版沒有實質差異（我把「Tile windows」、快速鍵表、移動與排列、全螢幕、Split View、Spaces、Mission Control、Stage Manager 八頁逐頁 diff 過；只有設定標籤改名與空白差異）。[V]
4. 10 月 28 日（昨天）Apple 發表帶觸控與 Dynamic Island 的新 MacBook Pro（11 月 6 日開始到貨）。HIG、Mac 使用手冊都還沒收錄觸控與 Dynamic Island；我加上快取破壞參數重抓 7 頁相關 HIG，內容沒變。要看觸控與 Dynamic Island，只有新聞稿、產品頁與三支 Tech Talk。[V]
5. 本機實證：macOS 27 設定裡，TCC「Accessibility」服務的顯示名稱是「Device Control and Data Access」。Apple 的 macOS 27 Mac 使用手冊隱私頁仍寫「Accessibility」，文件落後。repo 的 README_CN 提到這個改名，是對的。[D]

---

## 1. HIG：與視窗管理有關的規則

網址格式：`https://developer.apple.com/design/human-interface-guidelines/<頁名>`。抓取用 JSON 鏡像 `https://developer.apple.com/tutorials/data/design/human-interface-guidelines/<頁名>.json`（HIG 的 HTML 頁面由 JS 渲染，WebFetch 讀不到內文）。

### 1.1 Windows（/windows）
最後更新 2025-06-09。[V]
- 視窗分 primary（主導覽與內容）與 auxiliary（單一任務、不可導覽到別處）。
- 「Avoid creating custom window UI.」接著寫：「System-provided windows look and behave in a way that people understand and recognize.」又說：「…can make your app feel broken.」（沒做到與系統完全一致時）。對 WindowShade 的卷帘條、PiP 視窗、自繪浮層都適用。
- 「Make sure that your windows adapt fluidly to different sizes to support multitasking and multiwindow workflows.」
- macOS 視窗有三種狀態：main、key、inactive。「The system gives main, key, and inactive windows different appearances to help people visually identify them.」非 key 的視窗用灰色（紅黃綠燈變灰）；「inactive windows don’t use vibrancy」。自繪 UI 要自己做出這三態。
- 底部列：「people often relocate a window in a way that hides its bottom edge」，所以別把重要資訊放在視窗底部。
- iPadOS：視窗可以自由縮放，「The system remembers window size and placement even when an app is closed.」；「Make sure window controls don’t overlap toolbar items.」
- 「Use the term window in user-facing content.」文案要用「視窗」，不用 scene。

### 1.2 Multitasking（/multitasking）
最後更新 2025-06-09。[V]
- 「Apps don’t control multitasking configurations or receive any indication of the ones that people choose.」多工模式屬於使用者與系統，不是 App。
- macOS 段只有兩句：多工是預設體驗；多個視窗時，系統用投影讓視窗「appear layered on the desktop」。沒有任何磁貼、Stage Manager 的內容。
- iPadOS：「The system provides window controls for common tiling configurations, entering full screen, minimizing, and closing windows.」前景視窗的視窗控制鈕上色，後方視窗有投影。視窗可縮放，行為「similar to macOS」。PiP 可疊在全螢幕與視窗化 App 之上。

### 1.3 Going full screen（/going-full-screen）
最後更新 2025-06-09。[V]
- macOS：「Use the system-provided full-screen experience.」理由之一：「some Mac models include a camera housing that occupies an area at the top-center of the screen」，系統全螢幕會自動避開。
- 「Always let people choose when to enter full-screen mode.」可用綠鈕、View 選單或 Control-Command-F；「Avoid offering a custom menu of window modes.」
- 「don’t programmatically resize your window」（全螢幕時不要程式改視窗大小）；「Let people choose when to exit full-screen mode.」
- 「Except in games, let people reveal the Dock…」（全螢幕仍要能叫出 Dock）；選單列在全螢幕時自動隱藏、游標移到螢幕頂端會出現。

### 1.4 Split views（/split-views）——App 內元件
最後更新 2025-06-09。[V]
- macOS：窗格可垂直、水平或兩者；分隔線可拖曳。「Prefer the thin divider style.」細分隔線 1 pt 寬。
- 「Set reasonable defaults for minimum and maximum pane sizes.」窗格太小時「the divider can seem to disappear」。
- 與 macOS「Split View」模式無關；Split View 模式的行為見 §2.4。

### 1.5 Drag and drop（/drag-and-drop）
最後更新 2023-10-24。[V]
- 「Display a drag image as soon as people drag a selection about three points.」
- 「Display highlighting or other visual cues only while the content is positioned above the destination」；落點能不能接受要明示，不能接受時給「not allowed」回饋。落到無效位置或失敗，要有視覺回饋（回彈或淡出）。
- 「Offer alternative ways to accomplish drag-and-drop actions.」（選單指令等）
- macOS：「Let people drag selected content from an inactive window without first making the window active.」
- 持有 Option 拖曳 = 複製；可用 spring loading。偏好可復原（Undo）。

### 1.6 Gestures、Pointing devices、Keyboards
Gestures（/gestures，最後更新 2024-09-09）[V]
- 「Avoid conflicting with gestures that access system UI.」
- 自訂手勢要：Discoverable、Straightforward to perform、Distinct from other gestures，且「Not the only way to perform an important action in your app or game」。
- 「Use shortcut gestures to supplement standard gestures, not replace them.」
- 「Avoid using a familiar gesture like tap or swipe to perform an action that’s unique to your app」。

Pointing devices（/pointing-devices，2023-06 版）[V]
- 「Avoid redefining systemwide trackpad gestures.」且「Mac users can customize the gestures for performing systemwide actions.」
- macOS 系統手勢表（HIG 列出）：Swipe between full-screen apps、Mission Control（觸控板三或四指上滑；Magic Mouse 雙指雙點）、App Exposé（三或四指下滑）、Launchpad（拇指加三指捏合）、Show Desktop（拇指加三指展開）、Notification Center（從邊緣滑入）、Smart zoom、Swipe between pages、Look up（Force click 或三指點）。
- 游標樣式：resize left/right、up/down 等，是縮放視窗或元件時該用的游標。

Keyboards（/keyboards，2025-06 版）[V]
- 「In general, don’t repurpose standard keyboard shortcuts for custom actions.」
- 「Avoid using the Control key as a modifier.」理由：「The system uses Control in many systemwide features and shortcuts」。
- Command 當主修飾鍵；Shift 當輔助；「Use the Option modifier sparingly for less-common commands or power features.」
- 修飾鍵順序寫成 Control、Option、Shift、Command。
- HIG 標準快速鍵表中與視窗有關的：Command-Tab（下一個最近使用的 App）、Command-`（前景 App 的下一個視窗）、Control-Command-F（進入全螢幕）、Command-M（最小化；加 Option 為全部）、Option-Command-D（顯示/隱藏 Dock）、Command-H、Control-F3（焦點移到 Dock）、Control-F4（焦點移到作用中視窗）、Control-F6（下一個面板）、F11（顯示桌面）。另有 Control-Command-C = 複製格式設定、Control-Command-V = 套用格式設定、Control-Command-Space = 特殊字元視窗、Control-Command-D = 查字典。

### 1.7 Feedback、Motion、Materials、Accessibility
Feedback（/feedback）[V]
- 「Show people when a command can’t be carried out and help them understand why.」
- 「Make sure all feedback is accessible.」（顏色加文字、聲音、觸覺並用）

Motion（/motion，2025-09-09 加入 Liquid Glass 段）[V]
- 「Add motion purposefully, supporting the experience without overshadowing it.」
- 「Make motion optional.」「Let people cancel motion.」
- 「In apps, generally avoid adding motion to UI interactions that occur frequently.」
- Liquid Glass 的動態：觸控時反應較強，「produces a more subdued effect when a person interacts using a trackpad」。

Materials（/materials，2025-09-09）[V]
- 「Don’t use Liquid Glass in the content layer.」
- 「Use Liquid Glass effects sparingly.」自訂控制項只用在最重要的功能元件。
- 「Only use clear Liquid Glass for components that appear over visually rich backgrounds.」亮背景上用 clear 時，建議加 35% 不透明度的深色壓暗層。
- 系統設定（偏好外觀、降低透明度、提高對比）會改變 regular 與 clear 的外觀。
- macOS：用 `NSVisualEffectView.Material` 與兩種 blending mode（behind window、within window）；vibrancy 要用系統語意顏色。

Accessibility（/accessibility，2025-06）[V]
- 「Offer alternatives to gestures.」「Support simple gestures for common interactions」，避免自訂多指手勢。
- 「Avoid overriding system-defined keyboard shortcuts」，並支援 Full Keyboard Access。
- 「Minimize use of time-boxed interface elements.」（定時自動消失的元件）
- Reduce Motion 時：收緊彈簧、手勢直接驅動、避免 z 軸深度動畫、「Replacing transitions in x-, y-, and z-axes with fades to avoid motion」、避免進出模糊。
- macOS 控制項尺寸：預設 28x28 pt、最小 20x20 pt；文字最小 10 pt、預設 13 pt；對比 4.5:1（17 pt 以下）。

### 1.8 其他與視窗相關的 HIG 頁
- Layout（/layout，2026-09-09 更新「reflect current best practices」，內文看不出差異）：macOS 段「Avoid placing controls or critical information at the bottom of a window.」「Avoid displaying content behind the camera housing at the top edge of the window.」（對應 `NSPrefersDisplaySafeAreaCompatibilityMode`）。「Instead of applying a solid or semi-opaque background color beneath controls, use a scroll edge effect」[V]
- The menu bar（/the-menu-bar）：Window 選單「Provide a Window menu even if your app has only one window.」Zoom「Avoid using Zoom to enter or exit full-screen mode.」Option 鍵把 Bring All to Front 變成 Arrange in Front（整齊磁貼排列）。選單列額外項目：「Avoid relying on the presence of menu bar extras.」「Display a menu — not a popover — when people click your menu bar extra.」「Let people — not your app — decide whether to put your menu bar extra in the menu bar.」選單列高度 24 pt。[V]
- Panels（/panels）：「Prefer standard panels.」HUD 面板只在媒體類 App、標準面板會擋住關鍵內容、不需要控制項時用，並「Keep HUDs small.」App 啟用時把面板帶到前面、App 不在前景時隱藏面板。[V]
- Dock menus（/dock-menus）：「a Dock menu can list all currently or recently open windows」，且選單項目要在別處也提供。[V]
- Toolbars / Sidebars / Scroll views（Liquid Glass，2026-06-08 更新了 Sidebars、Scroll views）：自訂元件圓角要與容器同心（「ensure that its corner radius is also concentric with the bar’s corners」）；「Scroll edge effects aren’t decorative.」「Only use a scroll edge effect when a scroll view is behind floating interface elements.」「Apply one scroll edge effect per view.」側邊欄：「Extend visually rich content beneath the sidebar.」macOS 側邊欄也別把重要資訊放在底部。[V]
- Playing video（/playing-video）：「Use the system video player to give people a familiar and convenient experience.」系統播放器提供 PiP；自訂播放器要仿系統行為。macOS 的 PiP 就是這個系統元件（見 §2.8）。[V]
- Live Activities（/live-activities，2026-10-13 更新）：macOS 段「Active Live Activities automatically appear in the Menu bar of a paired Mac」，點一下開 iPhone Mirroring；macOS 尺寸沿用 iOS 尺寸。這一頁還沒寫 Mac 原生 Live Activities 與 Dynamic Island。[V]
- Designing for macOS（/designing-for-macos）：「Let people resize, hide, show, and move your windows to fit their work style and device configuration」。[V]

---

## 2. macOS 內建視窗管理（15 / 26 / 27）

### 2.1 視窗磁貼（Sequoia 15 引入）
來源：Mac 使用手冊 `tile-app-windows-mchlef287e5d`、`mac-window-tiling-icons-keyboard-shortcuts-mchl9674d0b0`、`change-window-tiling-settings-on-mac-mchl118087b0`（版本網址 `/15.0/mac/15.0`、`/26/mac/26`、`/27/mac/27`）；WWDC24 What's new in AppKit（10124）；新聞稿 2024-06-10。[V]
- 方法五種：拖到螢幕邊緣（左、右、四角；拖到選單列 = 填滿桌面）、拖曳時按 Option（立刻顯示最近磁貼預覽）、綠鈕懸停選單、Window 選單、快速鍵。
- 「When you drag a window all the way through the top edge of the screen, Mission Control opens.」可在 Desktop & Dock 關閉「Drag windows to top of screen to enter Mission Control」。
- 桌面與 Dock 設定 → Windows 的四個開關：macOS 15 頁面寫「Drag windows to screen edges to tile」，macOS 26 與 27 改寫「Drag windows to left or right edge of screen to tile」；其餘三個相同：「Drag windows to menu bar to fill screen」、「Hold ⌥ key while dragging windows to tile」、「Tiled windows have margins」（磁貼視窗之間留空隙）。預設是否開啟，Apple 頁面沒寫 [U]；本機 `defaults read com.apple.WindowManager` 看到 `EnableTiledWindowMargins = 0` [D]。
- 15 到 26 的標籤改名是否伴隨行為變更（例如頂端或角落是否仍磁貼），文件沒說清 [U]；26 與 27 的「Tile windows on Mac」頁仍寫左、右、任一角落可磁貼。
- 快速鍵（macOS 15、26、27 三版 diff：除了 15 頁多一句「Window tiling is available in macOS Sequoia 15 or later」外完全相同）：
  - Fill：Fn-Control-F；Center：Fn-Control-C；Return to Previous Size：Fn-Control-R
  - 半屏：Fn-Control-左／右／上／下；四個角落：沒有預設快速鍵
  - 雙視窗：Fn-Control-Shift-左（Left & Right）、-右（Right & Left）、-上（Top & Bottom）、-下（Bottom & Top）
  - 三視窗：Fn-Control-Option-Shift-左／右／上／下（半屏加兩個四分之一）；Quarters 沒有快速鍵
  - Full Screen Tile（Entire Screen、Left of Screen、Right of Screen、Exit Full Screen）：沒有快速鍵
- 內建的吸附：拖曳視窗靠近另一個視窗時「it aligns without overlapping」；拉邊緣靠近相鄰視窗邊緣時對齊並停住（Move and arrange app windows 頁）。
- WWDC24（10124）對開發者：兩個並排磁貼的視窗可以同時調整比例；磁貼視窗拖離位置會還原成未磁貼的大小；新開視窗以未磁貼大小出現。App 端建議：設定視窗最小／最大尺寸、`resizeIncrements`、用新的 `cascadingReferenceFrame` 取得「未磁貼」框架來層疊新視窗。NSWindowController 預設會處理。
- 我在 NSWindow 文件的符號清單裡搜尋 tile，只找到 `minFullScreenContentSize` / `maxFullScreenContentSize`（「fit when it is in full screen in a tile」，即全螢幕磁貼）與 `dockTile`；`NSWindow.CollectionBehavior` 另有 `fullScreenAllowsTiling` / `fullScreenDisallowsTiling`。沒有看到視窗磁貼（Sequoia 那一種）的專屬 API。[V]

### 2.2 綠鈕、標題列、雙擊
- 綠鈕：「Hold the pointer over the green button in the upper-left corner of the active window.」按 Option 看更多版面。選單分三區：Move & Resize（半屏、四分之一）、Fill & Arrange（多視窗排列、Fill、Center）、Full Screen（Entire Screen、Left of Screen、Right of Screen）。點綠鈕本身 = 進全螢幕；最大化後按住 Option 點綠鈕可還原。Split View 中的綠鈕選單另有 Replace Tiled Window、Move Window to Desktop、Make Window Full Screen。[V]
- 標題列雙擊動作（Desktop & Dock → Dock →「Window title bar double-click action」）：Fill、Zoom、Minimize、No Action。macOS 15 頁面舊稱「Double-click a window’s title bar to」、選項「Do Nothing」。[V]
- Window 選單（macOS 27 release notes）：「Window > Move & Resize and Window > Full Screen Tile menus can be used to move, resize, open and save panels…」——27 起連非 sheet 的開啟、儲存面板都能用。[V]

### 2.3 Mission Control、Spaces、熱角
- 進入方式：三指上滑、Mission Control 鍵或 Control-Up Arrow、Magic Mouse 雙指雙點、拖視窗到螢幕頂端。App Exposé：Control-Down Arrow（三或四指下滑）。顯示桌面：Command-Mission Control 或展開拇指與三指。「Apps」：捏合拇指與三指（26 起取代 Launchpad）。[V]
- 拖曳視窗到螢幕邊緣停一下會移到下一個 Space：「After a moment, the window moves to the next space.」Control-Left／Right Arrow 切 Space。[V]
- Multi-Touch 頁（2026-05-06 版）：四指上滑 Mission Control，四指下滑 App Exposé，四指左右切換桌面與全螢幕 App；註腳「In some versions of macOS, this gesture uses three fingers instead of four.」三指拖曳在輔助使用裡開。[V]
- 熱角：Desktop & Dock → Mission Control → Hot Corners。macOS 27 新增 `NSApplication.PresentationOptions.disableScreenCornerInteractions`：前景 App 可停用熱角。[V]
- 「Displays have separate Spaces」必須開啟，才能在其他螢幕用 Split View 或使用 Stage Manager。[V]

### 2.4 全螢幕與 Split View
- 全螢幕：綠鈕或 Full Screen > Entire Screen；選單列與 Dock 靠游標移到邊緣顯示；三或四指左右在全螢幕 App 間切換。[V]
- Split View：綠鈕 > Full Screen > Left/Right of Screen，建立在新的桌面空間。「Make one side bigger: Move the pointer over the separator bar located in the middle, then drag it left or right. To return to the original sizes, double-click the separator bar.」（這是系統層「分割視圖分隔條」。）[V]
- 15 到 27 這幾頁文字無實質差異（diff 結果只有空白與連結標籤）。[V]

### 2.5 Stage Manager
- 「Your recently used apps are neatly arranged along the left side of the screen」；游標移到左緣會短暫顯示最近 App；可分組。設定：Show recent apps、All at Once／One at a Time。需要「Displays have separate Spaces」。[V]
- Desktop & Dock 的「Show Desktop」（舊稱 Click wallpaper to reveal desktop）：Always on Wallpaper Click／Only in Stage Manager on Click。[V]
- 開發者面：`NSWindow.CollectionBehavior` 的 `primary`、`auxiliary`、`canJoinAllApplications` 只適用全螢幕與 Stage Manager，三者互斥；另有 `canJoinAllSpaces`、`moveToActiveSpace`、`stationary`、`managed`、`transient`、`participatesInCycle` / `ignoresCycle`。[V]
- 本機：`com.apple.WindowManager` 有 `GloballyEnabled = 0`（Stage Manager 關）、`AppWindowGroupingBehavior = 1`。這些是未公開的偏好鍵，只能當偵測線索 [D][U]。

### 2.6 Dock
- Mac 使用手冊（27）：點一下開啟、Command-click 在 Finder 顯示、Option-click 切到前一個 App 並隱藏目前的、Control-click 開捷徑選單。文件沒有「懸停顯示視窗縮圖」功能；HIG 建議的做法是 Dock 選單列出視窗。（這是「文件沒寫」，沒有在機器上實測 [U]。）
- Dock 設定：Magnification、位置（左／下／右）、自動隱藏、Minimize windows into application icon。[V]

### 2.7 切換與鍵盤
- Command-Tab（App）、Command-`（同 App 視窗）、Control-Up/Down（Mission Control／App Exposé）、Control-Left/Right（Space）。[V]
- macOS 27 新增（Siri AI 開啟時）：Shift-Command-Space（詢問作用中視窗）、Shift-Command-6（詢問選取區域）。Command-Space 是 Spotlight。Fn-A（Dock）、Fn-C（Control Center）、Fn-N（通知中心）、Fn-Shift-A（Apps）。[V]
- Mac 快速鍵頁還列了：Control-Command-Up Arrow（Finder 在新視窗開啟上層資料夾）。[V]
- Cooperative activation（AppKit 2023）：「App activation is now driven by the user」；`activate()` 與 `NSRunningApplication.activate(from:options:)` 都「doesn’t guarantee app activation」，需對方 `yieldActivation(to:)`。對跨 App 把視窗帶到前面的切換器、視窗瀏覽有影響。[V]
- `NSApplication.PresentationOptions.disableProcessSwitching` 可在 kiosk 類情境停用 Command-Tab 介面。[V]

### 2.8 畫中畫（PiP）
- macOS 的系統 PiP 是影片專用：Safari「Play a video in a movable window that ‘floats’ on top of everything else」；可拖到任一角落，切換桌面空間仍留在原處，可縮放。HIG 把 PiP 放在 Playing video。沒有「任意視窗 PiP」的系統功能。[V]
- 螢幕擷取：macOS 15 release notes 寫「Applications utilizing deprecated APIs for content capture such as CGDisplayStream & CGWindowListCreateImage can trigger system alerts」，要改用 ScreenCaptureKit 與 `SCContentSharingPicker`。macOS 15 另新增錄製單一視窗時紫色視窗選單的「Stop Recording This Window」。權限名稱為「Screen & System Audio Recording」。[V]

### 2.9 macOS 26 Tahoe（2025 秋）
- Liquid Glass 視窗外觀；選單列「completely transparent」；Spotlight 大改；iPhone 的 Live Activities 出現在選單列（26 起；設定「Allow Live Activities from iPhone」）。[V]
- 26.1 加入 Liquid Glass 的 clear／tinted 選項。[V]
- 視窗圓角：視窗有工具列者半徑較大、僅標題列者較小（WWDC25 310，見 §4.3）。
- 磁貼、Stage Manager、Mission Control 沒有可查到的功能變更；Tahoe 26.x 更新說明沒有任何視窗管理條目（我 grep 過）。[V]

### 2.10 macOS 27 Golden Gate（2026 秋）——確認的項目
來源：WWDC26 Keynote（101）、Platforms State of the Union（102）與 Recap（122）、Modernize your AppKit app（289）、新聞稿 2026-06-08、apple.com/os/macos、macOS 27 與 27.2 release notes、Tech Talks。[V]
- 視窗圓角：Keynote「every window on macOS now has the same tighter corner radius」；SOTU 加「ensuring greater consistency across all apps」；apple.com 寫「updated window shapes」。即使沒重編譯的 App 也一樣。
- Liquid Glass：更好的擴散、較暗的邊緣與較亮的高光；新增從 ultra-clear 到 fully tinted 的滑桿，「Apps already using Liquid Glass get these improvements automatically」；系統「adapts to a variety of accessibility settings」（降低透明度、提高對比）；macOS 27 新增環境值 show borders。
- 統一工具列（內容捲到浮動列下方時出現）、側邊欄延伸到視窗邊緣、側邊欄圖示恢復顏色（「more clear which window is key」）。標準捲動邊緣效果在標題等自由浮動文字下會改成 hard。
- AppKit：`cornerConfiguration` / `NSViewCornerConfiguration` / `NSViewCornerRadius.containerConcentric`（macOS 27+）；玻璃的點擊彈性效果；status item 的 `expandedInterfaceSession`（顯示自訂視窗時要用它管理鍵盤焦點）；`NSTitlebarAccessoryViewController` 預設可畫在邊界外；選單與右鍵選單預設隱藏符號圖示（`preferredImageVisibility`）；手勢辨識器為輸入的主要方式；`NSWindow.preventsApplicationTerminationWhenModal` 提醒。
- 新快速鍵：Shift-Command-Space、Shift-Command-6（Siri AI）。
- 顯示器：apple.com「your display arrangements stay exactly as you left them」；超寬螢幕更高解析度。27.2 release notes 已知問題：外接螢幕連接時「display settings might not be restored correctly, and the display arrangement might change」。
- 系統動畫更順：Keynote 點名「entering Mission Control, or moving between spaces on Mac」。
- macOS 27 僅支援 Apple silicon（developer news 2026-09-09：「macOS 26 is the final release supporting Intel Mac computers and Rosetta」）。同一系列的 2026-09-01 公告卻寫「macOS 27: Final release to support Rosetta」，兩則對 Rosetta 的說法互相矛盾 [U]；對 WindowShade 只需記得：Intel Mac 最高到 macOS 26，README 已寫 Apple Silicon 限定。
- 本機已安裝 27.0.1；Apple Support 的更新頁（2026-10-26 發布日）列有 27.2。
- 我找不到 Apple 一手來源說明的：Stage Manager、磁貼、Mission Control、綠鈕選單的新行為；紅黃綠燈新設計（只有媒體報導 [P]，不採信）。

### 2.11 觸控 Mac 與 Dynamic Island（2026-10-28 發表）
來源：新聞稿 `https://www.apple.com/newsroom/2026/10/apple-unveils-groundbreaking-macbook-pro-with-proled-xdr-display/`、產品頁 `https://www.apple.com/macbook-pro/proled-xdr-display/`、developer.apple.com/touch-on-mac/、三支 Tech Talk。[V]
- 硬體：MacBook Pro with PROLED XDR Display，14／16 吋，2026-11-06 起到貨。macOS 27 另可用 Sidecar 連接的 iPad 測觸控（TN3212、Tech Talk）。
- 觸控手勢（Apple 說明）：「double-tap a window to fill the screen, or flick to tile it into place」。系統層多指手勢（Tech Talk）：三指上滑 Mission Control、三指下滑 App Exposé、拇指加三指捏合顯示 Apps、展開顯示桌面、三指左右切桌面、頂端往下滑叫出選單列、底部往上滑叫出 Dock、右緣往左滑通知中心、右上往下滑 Control Center、在 Dynamic Island 上滑叫 Siri。「These gestures are controlled by macOS and are therefore not available to any app running.」
- 設計規則（Tech Talk「Design for touch on Mac」）：觸控目標 36 pt；「Avoid adding gestures that only work with touch.」手勢動作要在選單等處也有；觸控沒有 hover：「Direct touches don’t have an equivalent to mouseMoved events.」（Bring Touch 那支）；不是原生觸控的 UI 框架，AppKit 會套用滑鼠模擬（輕點 = click、一指滑 = scroll、長按 = 右鍵、雙指捏合 = 縮放與旋轉），可用 Info.plist 的 `NSIsTouchNative` 關閉。
- 視窗層級：`NSWindow.disablesDirectTouchSystemGestures` 可關閉直接觸控的系統手勢（Tech Talk 提到；公開文件頁在 2026-10-29 查不到 [U]）。「Use great care when it comes to disabling system gestures.」
- Dynamic Island on Mac：新聞稿「The Dynamic Island comes to the Mac, serving as the new home for Spotlight, Live Activities, and Siri AI」；產品頁寫成新機型的功能。Tech Talk「Bring Live Activities to Mac」：「On a Mac with Dynamic Island, Live Activities blend in seamlessly into the top edge of the device.」「On other devices and displays, they are shown in the menu bar.」macOS 27 起 Mac App 可直接建立 Live Activities（ActivityKit、WidgetKit、App Intents）。新聞稿註腳寫：「Spotlight only moves to the Dynamic Island if Siri AI is available and enabled.」
- 沒有任何 Apple 來源說舊款有瀏海的 MacBook 也會得到 Dynamic Island [U]。
- 觸控也可能影響標題列行為（雙擊填滿、輕撥磁貼）：Apple 沒有說明這些觸控動作如何與第三方 CGEvent tap 互動 [U]。

### 2.12 瀏海（camera housing）API 與相容模式
- `NSScreen.safeAreaInsets`（macOS 12+）：「On some Macs, the insets reflect the portion of the screen covered by the camera housing.」`auxiliaryTopLeftArea`、`auxiliaryTopRightArea` 給出瀏海左右兩側可用區域。[V]
- 相容模式：「The system activates this compatibility mode when an app that requires it places a window behind the camera housing…」啟動後系統把顯示區域縮到攝影機下方；支援頁（102125）寫整個同一空間的 App 都會下移，直到該 App 結束。Info.plist 鍵 `NSPrefersDisplaySafeAreaCompatibilityMode`：審查後設 false；有問題設 true。[V]
- HIG 全螢幕頁：用系統全螢幕就自動避開瀏海。[V]

### 2.13 三版對照（視窗外觀與行為）

| 項目 | macOS 15 | macOS 26 | macOS 27 |
| --- | --- | --- | --- |
| 視窗磁貼 | 引入；四個設定；Fn-Control 快速鍵 | 同；第一個設定改名為「left or right edge」 | 同（文字無差異） |
| 視窗圓角 | 傳統 | 依視窗樣式不同：有工具列者較大、僅標題列者較小 | 所有視窗同一種較緊的半徑 |
| 工具列、側邊欄 | 傳統 | 玻璃浮動；側邊欄為內縮浮動玻璃 | 統一工具列、側邊欄貼齊視窗邊緣、圖示有顏色 |
| 選單列 | 半透明 | 完全透明 | 選單與右鍵選單預設隱藏符號圖示 |
| Liquid Glass | 無 | 引入；26.1 有 tinted 選項 | 調整擴散與高光；ultra-clear 到 fully tinted 滑桿；show borders 環境值 |
| 瀏海／島 | 同一組 API | 同 | 同一組 API；新 MacBook Pro 有 Dynamic Island；原生 Live Activities |
| 觸控 | 無 | 無 | 新 MacBook Pro 與 Sidecar iPad |
| 熱角 | 未見公開的 App 層級開關 | 同 | `disableScreenCornerInteractions`（release notes 列為新功能） |

---

## 3. iPadOS 26 視窗系統（為何、怎麼做）

來源：新聞稿 2025-06-09、WWDC25 Elevate the design of your iPad app（208）、HIG Windows 與 Multitasking、Adopting Liquid Glass、iPad 支援頁（125309、123635）、iPadOS 26 更新說明（123074）。[V]

- 為何：新聞稿寫「all while maintaining the immediacy and simplicity that iPad users expect」。WWDC25 208 開場：「At its core, iPad is about simplicity.」SOTU（2025）：「iPadOS now shares many of the same layout considerations as macOS, including consistent placement of common elements, as well as dynamically scalable windows and floating controls.」
- 縮放視窗：每個支援多工的 App 右下角有把手，拖曳就變成浮在桌布上的視窗；「windows resize fluidly down to a minimum size」（Adopting Liquid Glass），不再是固定的預設尺寸。上次縮放過的 App 重開時回到同一個大小與位置。
- 視窗控制（紅黃綠）：左上角，點一下變大顯示功能，長按展開一組版面捷徑。「Window controls will appear on the leading edge of your app toolbar.」建議把工具列「wrap around」視窗控制，以免保留安全區。支援頁：Close、Minimize、Zoom；長按可重新排列。
- 磁貼：新聞稿「enables users to arrange their windows with a simple flick」；26.0 說明「side by side, in thirds, or in quarters」；26.2 加「drag and drop gestures for tiling app windows and creating a Slide Over window」、從 Dock 拖 App 圖示到邊緣。
- Exposé：看到所有開啟視窗；外接鍵盤用 Exposé 鍵或 Globe-Up Arrow。iPadOS 26.4 的更新說明加入「Open window indicator」。
- 選單列：下滑或游標移到頂端；Apps 可自訂；WWDC25 208 指示：選單項目依使用頻率排序、不要隱藏選單或項目（變灰而不是消失）、View 選單放分頁與側邊欄切換。
- 新文件開新視窗：「Open in Place」行為「is no longer recommended」；新視窗要有獨特標題，因為 App 選單有視窗清單。「Name each window with a unique string」。（對 WindowShade 視窗瀏覽與切換器的標題顯示有啟發。）
- 與 Stage Manager 並存：Windowed Apps、Full Screen Apps、Stage Manager 三選一（設定 > Multitasking & Gestures 或控制中心）。HIG：「Apps don’t control multitasking configurations」。
- Slide Over：26.1 說明「Slide Over lets you keep a window on top of other windows, and easily hide off screen when not in use」，視窗可調整大小；iPad 多工頁寫「In iPadOS 26.2 or later, you can set one window as a Slide Over window」（26.1 與 26.2 的差異文件沒解釋 [U]）。操作：拖 App 到邊緣箭頭、拖頂端移到另一側、滑到螢幕外隱藏、從邊緣滑回、拖到畫面中間離開。一次只有一個 Slide Over 視窗。
- iPadOS 27：iOS App 在 iPad 與 iPhone Mirroring 上可縮放（WWDC26 SOTU、278）；apple.com/ipados 示範捷徑句「When I connect a keyboard, turn on Windowed Apps and tile Safari and Notes side by side」（Shortcuts 的視窗動作是否也在 macOS 開放，沒有來源 [U]）。

---

## 4. Liquid Glass

### 4.1 設計規則（WWDC25 219、356；HIG Materials）[V]
- 層級：「it is best reserved for the navigation layer that floats above the content of your app」；「always avoid glass on glass」。
- 兩種變體 Regular 與 Clear，「They should never be mixed」。Clear 只在三個條件同時成立時用：位於媒體豐富內容上、內容層可以承受壓暗層、上面的內容粗而亮。
- 著色只用在主要動作；不要所有元素都著色；內容層才放品牌色。
- 視窗失焦：「when a window loses focus on the Mac or iPad, Liquid Glass shifts its appearance and visually recedes」。
- 同心：「Glass controls nest perfectly into the rounded corners of windows, maintaining concentricity throughout the UI.」三種形狀：fixed、capsule、concentric（半徑 = 父層減去內距）。356：「For iPad and Mac, use a concentric shape that aligns with the window edge」。macOS 的 mini、small、medium 控制項維持圓角矩形，large 與 x-large 是膠囊。
- 捲動邊緣效果：soft（預設）與 hard（macOS 較常用）；不裝飾、不遮蓋，只在浮動元素後方使用。
- 自訂控制項：「apply the material directly to the control, not its inner views」（356）。
- 無障礙：降低透明度讓玻璃更霧（「frostier」）；提高對比讓元素變黑白並加對比邊框；降低動態減少效果強度並停用彈性。系統層級設定開了就全部套用（219）；macOS 27 的 Apple 說法是自動適應（SOTU）。
- 與使用者偏好：26.1 的 clear／tinted、27 的滑桿；已採用者自動套用。

### 4.2 AppKit 做法與 API（WWDC25 310；Adopting Liquid Glass；API 文件）[V]
- `NSGlassEffectView`（macOS 26.0+）：「A view that embeds its content view in a dynamic glass effect.」屬性：`contentView`、`cornerRadius`、`style`（`.regular`／`.clear`）、`tintColor`、`effectIsInteractive`（「Enables interactive glass behavior, which adds a visual response to user interactions」）。310：把內容放進 `contentView`，不要把 NSGlassEffectView 當成兄弟視圖放在內容後面。
- `NSGlassEffectContainerView`（macOS 26.0+）：「efficiently merges descendant glass effect views together when they are within a specified proximity」；`contentView`、`spacing`（預設 0，只做批次處理，不做合併變形）。理由：「glass can’t directly sample other glass」，近距離的多個玻璃要放同一個容器，視覺一致、效能較好（單次取樣）。
- `NSButton.BezelStyle.glass`（26.0+）、`NSBackgroundExtensionView`（26.0+）、`NSView.LayoutRegion`（26.0+，角落避讓）、`NSScrollEdgeEffectStyle`（26.1+）、`NSToolbarItem.Style.prominent`、`prefersCompactControlSizeMetrics`。
- macOS 27：`NSViewCornerConfiguration`、`NSViewCornerRadius.containerConcentric`、`NSView.cornerConfiguration`（27.0+）。
- 側邊欄：若用 `NSVisualEffectView` 當側邊欄材質，「it will prevent the glass material from showing through」，要移除。
- 不要自訂工具列、分割視圖的背景：「Reduce your use of custom backgrounds in controls and navigation elements.」
- 舊外觀退路：`UIDesignRequiresCompatibility`（Adopting Liquid Glass 提到；macOS 27 是否仍生效，我沒查到說明 [U]）。
- 15 支援：上述玻璃 API 都是 26+，macOS 15 要回退到 `NSVisualEffectView`（HIG Materials 的 macOS 段）。

### 4.3 視窗外框與圓角
- macOS 26（WWDC25 310）：「windows now have a softer, more generous corner radius, which varies based on the style of window」；有工具列的視窗用較大半徑、「designed to wrap concentrically around the glass toolbar elements」；僅標題列視窗半徑較小。大圓角會裁到靠邊內容，要用 `NSView.LayoutRegion` 做角落避讓。
- macOS 27：所有視窗同一種較緊的半徑（§2.10）。Apple 沒公布數值，我在讀過的一手來源裡沒找到可讀取系統視窗圓角的公開 API [U]。
- 對自繪浮層（卷帘條、磁貼預覽、PiP）的含意：不可寫死圓角；15、26、27 三版都要實機比對。

### 4.4 無障礙相關 API
`NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`、`accessibilityDisplayShouldReduceTransparency`（「don’t use semitransparent backgrounds… use only opaque windows」）、`accessibilityDisplayShouldIncreaseContrast`，通知 `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification`。[V]

---

## 5. 與 WindowShade 功能的重疊與衝突

說明：WindowShade 預設快速鍵與功能描述取自 repo 的 README_CN.md（非 Apple 來源，只用來對照）。1.0.16 起新裝不預設快速鍵；升級者保留 ⌃⌘C、⌃⌘P、⌃⌘G、⌃⌘1…9、⌃⌘0、⌃⌘方向鍵；另有 ⌥+Tab 切換、⌃⌘L 開啟主畫面。

| 功能 | Apple 內建對應 | 重疊或衝突 | Apple 規則或證據 | 風險 |
| --- | --- | --- | --- | --- |
| 收起成卷帘條（雙擊標題列、⌃⌘C） | 最小化（Command-M、Minimize into app icon）、標題列雙擊動作（Fill／Zoom／Minimize／No Action）、Stage Manager | 雙擊同一個標題列會與系統動作同時觸發；⌃⌘C 與 HIG 表的「Control-Command-C = 複製格式設定」同鍵；觸控 Mac 的「雙擊視窗填滿」 | 「Avoid creating custom window UI」；視窗三態；不要重新定義系統手勢；Control 不建議當修飾鍵 | 高 |
| 塞進瀏海 | `NSScreen.safeAreaInsets`、auxiliary 區域、相容模式、「Scale to fit below built-in camera」；新 MacBook Pro 的 Dynamic Island（Spotlight、Live Activities、Siri AI） | 在瀏海後面放視窗可能觸發相容模式，使整個空間的 App 下移；新機型瀏海區由系統接管；選單列額外項目在空間不足時會被系統隱藏（HIG） | HIG Layout「Avoid displaying content behind the camera housing」；`NSPrefersDisplaySafeAreaCompatibilityMode` | 高 |
| 左右半屏與格線吸附 | Sequoia 磁貼全套（拖曳邊緣、Option、綠鈕選單、Window 選單、Fn-Control 快速鍵、margins、拖曳吸附相鄰視窗） | 完全重複；邊緣拖曳區被多功能共用：磁貼預覽、頂端 = Mission Control、拖到選單列 = 填滿、邊緣停留換 Space、Stage Manager 左緣最近 App 欄、熱角；Fn-Control-方向鍵若重複註冊會互搶；系統有「Return to Previous Size」記憶 | 系統磁貼文件；`disableScreenCornerInteractions`（27） | 高 |
| 魔法平鋪 | 無對應 | 落點回饋必須符合 drag and drop 規則 | HIG Drag and drop：只在游標位於落點上方時高亮；無法接受時要明示；提供替代方式（選單） | 中 |
| 捲動式（niri 式）平鋪 | 無直接對應；最近的是 Stage Manager、Mission Control、Spaces | 橫向捲動與三、四指橫掃（切 Space／全螢幕 App）、兩指橫掃（上一頁）衝突；全螢幕視窗在獨立 Space，無法平鋪；Control-Left／Right 是 Space 切換 | HIG：不要重新定義系統手勢；不要與存取系統 UI 的手勢衝突 | 中高 |
| 任意視窗 PiP | 系統 PiP 只支援影片（Safari、AVKit、FaceTime） | 擷取視窗需 ScreenCaptureKit；舊 API 會觸發系統警示；權限「Screen & System Audio Recording」；PiP 視窗要跨 Space、浮在最上層，需要正確的 `collectionBehavior` 與視窗層級 | macOS 15 release notes；HIG Playing video | 中 |
| 側拉（Slide Over） | macOS 沒有；iPad 26.1/26.2 才有 | 沒有 macOS 對應，只能仿 iPad 語意：單一視窗、邊緣箭頭、滑出滑入、拖到中間離開 | 見 §3 | 低 |
| 分屏分隔條 | macOS Split View 的分隔條（拖曳調整、雙擊還原）；磁貼雙視窗可同時調整 | 重複；若同時作用在已進 Split View 的視窗，位置會被系統接管 | Mac 使用手冊 Split View；HIG Split views（1 pt 分隔線、最小尺寸）；游標用 resize left/right | 中 |
| Dock 懸停的視窗瀏覽 | Dock 選單（可列視窗）、App Exposé、Mission Control、Stage Manager；沒有文件化的懸停縮圖 | 與 Dock 自動隱藏、放大、位置（左／下／右）互動；觸控沒有 hover；跨 App 帶到前面受 cooperative activation 限制 | HIG Dock menus；Tech Talk：沒有 mouseMoved、要有點一下的替代 | 中 |
| Alt-Tab 式切換器 | Command-Tab（App）、Command-`（視窗）、Mission Control | 不得覆寫 Command-Tab；⌥+Tab 不在 Apple 的標準表內，符合「Option 用於進階功能」 | HIG Keyboards | 低 |
| 標題列觸控板手勢（兩指上下滑收起／填滿、左右半屏） | 兩指捲動是系統手勢；Swipe between pages 是兩指橫掃；觸控 Mac 的單指捲動；Force click 不在所有裝置上存在（Magic Mouse、MacBook Neo 觸控板沒有） | 與標準捲動與橫掃重疊；沒有 hover 的觸控；三指拖曳（輔助使用） | HIG：自訂手勢要可發現、有替代方式、不是唯一入口；Accessibility：Offer alternatives to gestures | 高 |
| 瀏海活動（notch activities） | 新 MacBook Pro 的 Dynamic Island + 原生 Live Activities（27）；其他 Mac 與外接螢幕用選單列；26 起 iPhone 的 Live Activities 在選單列 | 功能重複，且系統層會佔用同一個位置；「Dynamic Island」手勢（觸控滑過叫 Siri） | HIG Live Activities；Motion／Accessibility（時間限制元素） | 高 |
| 快速鍵整體 | HIG 標準表、Mac 快速鍵頁、Fn-Control-方向鍵（磁貼）、Control-方向鍵（Mission Control、Space）、Control-Command-F、Shift-Command-Space（27） | ⌃⌘↑ 在 Finder 是「開啟上層資料夾於新視窗」；⌃⌘C 見上；⌃⌘F 全螢幕不可佔用 | HIG：避免 Control 當修飾鍵；不要重新定義標準快速鍵 | 中高 |
| 自繪 UI 外觀 | Liquid Glass、27 的統一圓角、清晰↔著色滑桿、降低透明度等 | 自繪玻璃／模糊與系統不一致；失焦時未退讓；圓角寫死 | HIG Materials；WWDC25 219／356／310 | 中 |
| 權限與選單列 | Accessibility（27 顯示為 Device Control and Data Access）、Screen & System Audio Recording、Input Monitoring | 名稱變動影響引導文案；選單列項目可被系統隱藏 | HIG Menu bar extras | 低 |

### 5.1 WindowShade 既有快速鍵對 Apple 清單（我用 grep 核對 HIG 鍵盤頁與 support.apple.com/en-us/102650）

| WindowShade（README_CN） | 在 Apple 清單裡的狀況 |
| --- | --- |
| ⌃⌘C（收起） | HIG 表：Control-Command-C = 複製選取內容的格式設定（App 內功能）。同鍵 |
| ⌃⌘↑ | Mac 快速鍵頁：Control-Command-Up Arrow = Finder 在新視窗開啟上層資料夾。同鍵 |
| ⌃⌘↓、⌃⌘←、⌃⌘→ | 兩份清單都沒列；但系統的 Control-方向鍵（Mission Control、Space）與 Fn-Control-方向鍵（磁貼）在相鄰組合上 |
| ⌃⌘P、⌃⌘G、⌃⌘L、⌃⌘0、⌃⌘1…9 | 兩份清單都沒列（只代表 Apple 沒文件化；其他 App 仍可能使用） |
| ⌥+Tab（切換器） | 兩份清單都沒列；HIG 對 Option 的定位是「less-common commands or power features」，符合 |
| 全部都以 Control 為修飾鍵 | HIG：「Avoid using the Control key as a modifier.」 |

注意：Apple 清單裡已被佔用的 ⌃⌘ 組合有 Control-Command-F（全螢幕，HIG 與 Mac 快速鍵頁）、Control-Command-Space（Character Viewer）、Control-Command-D（查字典，HIG）、Control-Command-Q（鎖定畫面，Mac 快速鍵頁）、Control-Command-C／V（複製與套用格式，HIG）、Control-Command-Up Arrow（Finder）。WindowShade 若新增 ⌃⌘ 組合，要先對照這幾個。

---

## 6. 稽核檢查清單（可操作）

視窗與外觀
1. 卷帘條與浮層有 key／main／inactive 三態外觀；失焦時退讓。（HIG Windows；219）
2. 圓角不寫死；15、26、27 各截一張與同機真實視窗並排比對；工具列視窗與僅標題列視窗各一。（310、Keynote）
3. 15 用 `NSVisualEffectView`，26+ 用 `NSGlassEffectView`；相鄰玻璃放進 `NSGlassEffectContainerView`；沒有玻璃疊玻璃。（310、219）
4. 打開降低透明度、提高對比、降低動態：浮層仍可讀、動畫降級成淡入淡出。（219、HIG Accessibility）
5. 27：切換 Liquid Glass 滑桿（ultra-clear ↔ fully tinted）仍可讀。（SOTU）
6. 自訂控制項觸控目標 ≥ 36 pt（觸控 Mac），≥ 28 pt 預設（滑鼠）。

邊緣與磁貼
7. 列出所有邊緣、角落、頂端的拖曳反應，與系統並存時誰先反應；在「Drag windows to left or right edge…」、「…to menu bar…」、「Hold ⌥…」、「Tiled windows have margins」、「Drag windows to top… Mission Control」各組合下實機驗證。
8. 拖到邊緣停留時，系統「移到下一個 Space」是否被干擾。
9. 與系統磁貼視窗互動：不破壞「Return to Previous Size」（Fn-Control-R）；兩個並排的系統磁貼視窗仍可同時調整比例。
10. 偵測 Stage Manager、全螢幕與 Split View 視窗，不去移動它們；「Displays have separate Spaces」關閉時的行為。
11. 外接螢幕重接後位置回復；27.2 已知問題（顯示器排列可能被改）。

快速鍵與手勢
12. 預設快速鍵全部對照 §2.1、§2.7 與 HIG 表；⌃⌘C、⌃⌘↑、⌃⌘F、⌃⌘Space、⌃⌘D 特別標註。避免 Control 當修飾鍵；Fn-Control-方向鍵不要用。（HIG Keyboards）
13. 每個手勢功能都有選單或快速鍵替代入口。（HIG Gestures、Accessibility）
14. 標題列手勢在 Magic Mouse、無 Force Touch 的觸控板、觸控螢幕上的行為各測一次。（WWDC26 272；Tech Talk）
15. 觸控 Mac：Dock 懸停瀏覽、綠鈕懸停類 UI 要有輕點的替代入口；若要關閉直接觸控的系統手勢，只在關鍵互動期間、只作用在自家視窗（Tech Talk：「Use great care when it comes to disabling system gestures.」）。

瀏海與選單列
16. 沒有任何視窗落在瀏海後面時觸發相容模式；Info.plist 有沒有 `NSPrefersDisplaySafeAreaCompatibilityMode`；用 `safeAreaInsets` 與 auxiliary 區域定位。
17. 新 MacBook Pro 與外接螢幕（選單列）兩種情境，瀏海活動不與系統 Dynamic Island、Live Activities 同時搶位。
18. 選單列項目被系統隱藏時，仍有第二入口（HIG：「Avoid relying on the presence of menu bar extras」）。
19. 由 status item 顯示自訂視窗時，使用 expanded interface session（WWDC26 289）。
20. 時間限制元素（自動消失的提示或活動）提供「保留」方式。（HIG Accessibility）

擷取與權限
21. 預覽與 PiP 全部走 ScreenCaptureKit，不用 `CGWindowListCreateImage` 與 `CGDisplayStream`。（macOS 15 release notes）
22. 權限引導文案：27 的名稱「Device Control and Data Access」與「Accessibility」並列說明。

跨 App 切換
23. 視窗瀏覽與切換器把視窗帶到前面時，考慮 cooperative activation：`activate(from:options:)` 不保證成功，要有失敗處理。
24. 視窗標題要能辨識（iPadOS 26 的做法：每個視窗有獨特標題）。

---

## 7. 我確認不了的事（使用前要再查）

1. 舊款有瀏海的 MacBook 會不會在 macOS 27.x 得到 Dynamic Island。沒有 Apple 來源。
2. 紅黃綠燈在 27 是否改版。只有媒體說法 [P]。
3. 各版系統視窗圓角的數值與讀取方式。
4. 磁貼 margins 預設值。
5. 系統頂端／角落拖曳在 26、27 的細部判定（磁貼、填滿、Mission Control 的先後）。support 文字三版相同，但設定標籤在 26 改了。
6. Dock 懸停縮圖：文件沒寫，我沒有在機器上實測。
7. 觸控的「雙擊視窗填滿、輕撥磁貼」如何傳給第三方（CGEvent tap、AX）。
8. `disablesDirectTouchSystemGestures` 與 `exclusiveGestureBehavior` 的公開文件頁（2026-10-29 查詢 404）。
9. iPadOS Slide Over 的引入版本是 26.1 還是 26.2（兩份 Apple 文件說法不同）。
10. HIG 尚未更新觸控與 Mac 的 Dynamic Island；之後可能補，之前下的結論要再核對。

---

## 8. 本機證據與重現方式

- `sw_vers`：macOS 27.0.1，build 26A434。
- `defaults read com.apple.WindowManager`：`EnableTiledWindowMargins = 0`、`GloballyEnabled = 0`、`AppWindowGroupingBehavior = 1`（未公開鍵，只作偵測線索）。
- `/System/Library/ExtensionKit/Extensions/SecurityPrivacyExtension.appex/Contents/Resources/Localizable.loctable`（`plutil -convert json -o -`）：英文 `ACCESSIBILITY => Device Control and Data Access`。
- HIG 全頁搜尋：抓取檔在 `…/scratchpad/research/txt/higall/*.txt`（172 頁，1.5 MB）；例：`cd …/txt/higall && grep -l -i "Stage Manager" *.txt`（輸出空）、`grep -l -i -E "tiling|tiled" *.txt`（multitasking、the-menu-bar；right-to-left 是 multilingual 的誤中）。
- 版本比對：`…/txt/support/v15.0_*.txt`、`v26_*.txt`、`v27_*.txt` 為 support 頁三個 macOS 版本的內文，用 `diff` 比對。
- WWDC 逐字稿：`…/txt/wwdc20*-*.txt`；Tech Talk 逐字稿網頁沒有內文，我從影片的英文字幕軌（HLS 的 subtitles/en）取純文字：`…/txt/techtalk-1114*-clean.txt`。
- 版本與發表日期的出處：developer.apple.com/news（RSS）、support.apple.com/en-us/127257（macOS 27 更新）、support.apple.com/en-us/122868（Tahoe 更新）。

---

## 9. 一手來源索引

HIG（`https://developer.apple.com/design/human-interface-guidelines/` 之後接頁名）：windows、multitasking、going-full-screen、split-views、drag-and-drop、gestures、pointing-devices、keyboards、feedback、motion、materials、accessibility、layout、the-menu-bar、panels、dock-menus、toolbars、sidebars、scroll-views、playing-video、live-activities、designing-for-macos、designing-for-ipados。

WWDC：
- 2026：`https://developer.apple.com/videos/play/wwdc2026/101/`（Keynote）、`/102/`（Platforms State of the Union）、`/122/`、`/289/`（Modernize your AppKit app）、`/269/`、`/272/`、`/278/`、`/223/`、`/250/`
- Tech Talks：`https://developer.apple.com/videos/play/tech-talks/111456/`（Design for touch on Mac）、`/111468/`（Bring Touch to your Mac app）、`/111467/`（Bring Live Activities to Mac）
- 2025：`https://developer.apple.com/videos/play/wwdc2025/219/`、`/356/`、`/310/`、`/208/`、`/282/`、`/256/`、`/102/`
- 2024：`https://developer.apple.com/videos/play/wwdc2024/10124/`、`/10148/`

新聞稿：
- `https://www.apple.com/newsroom/2024/06/macos-sequoia-takes-productivity-and-intelligence-on-mac-to-new-heights/`
- `https://www.apple.com/newsroom/2025/06/macos-tahoe-26-makes-the-mac-more-capable-productive-and-intelligent-than-ever/`
- `https://www.apple.com/newsroom/2025/06/ipados-26-introduces-powerful-new-features-that-push-ipad-even-further/`
- `https://www.apple.com/newsroom/2026/06/apple-unveils-next-generation-of-apple-intelligence-siri-ai-and-more/`
- `https://www.apple.com/newsroom/2026/10/apple-unveils-groundbreaking-macbook-pro-with-proled-xdr-display/`
- `https://www.apple.com/macbook-pro/proled-xdr-display/`、`https://www.apple.com/os/macos/`、`https://www.apple.com/os/ipados/`

Mac 使用手冊與支援（`https://support.apple.com/guide/mac-help/` 之後接）：tile-app-windows-mchlef287e5d/mac、mac-window-tiling-icons-keyboard-shortcuts-mchl9674d0b0/mac、change-window-tiling-settings-on-mac-mchl118087b0/mac、work-with-app-windows-mchlp2469/mac、use-apps-in-full-screen-mchl9c21d2be/mac、use-apps-in-split-view-mchl4fbe2921/mac、use-stage-manager-mchl534ba392/mac、view-open-windows-spaces-mission-control-mh35798/mac、work-in-multiple-spaces-mh14112/mac、change-desktop-dock-settings-mchlp1119/mac、open-apps-from-the-dock-mh35859/mac、whats-new-in-macos-27-apd07d671600/mac。其他：`https://support.apple.com/en-us/102650`（Mac 快速鍵）、`/102482`（Multi-Touch 手勢）、`/127257`（macOS 27 更新）、`/122868`（Tahoe 更新）、`/102125`（瀏海下方縮放）、`/120684`（iPhone Live Activities 在 Mac）、`/125309`（iPad 多工）、`/123635`、`/123074`；Safari：`https://support.apple.com/guide/safari/play-web-videos-ibrw27291639/mac`。

開發者文件：
- `https://developer.apple.com/documentation/appkit/nsglasseffectview`、`/nsglasseffectcontainerview`、`/nsviewcornerconfiguration`、`/nsviewcornerradius`、`/nsview/layoutregion`、`/nsbackgroundextensionview`
- `https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct`、`/nsapplication/presentationoptions-swift.struct`、`/nsscreen/safeareainsets`
- `https://developer.apple.com/documentation/bundleresources/information-property-list/nsprefersdisplaysafeareacompatibilitymode`
- `https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass`
- `https://developer.apple.com/documentation/macos-release-notes/macos-27-release-notes`、`/macos-27_2-release-notes`、`/macos-15-release-notes`
- `https://developer.apple.com/documentation/updates/appkit`
- `https://developer.apple.com/documentation/technotes/tn3212-adopting-gesture-recognizers-for-sidecar-touch-support`
- `https://developer.apple.com/touch-on-mac/`、`https://developer.apple.com/news/?id=i9boeiqc`
