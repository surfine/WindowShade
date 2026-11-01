# Mac 上對應 Back Tap / Double Tap 的低成本觸發管道（截至 2026-11）

研究日期 2026-11-01。本機佐證來自這台 Mac（Apple M5、`hw.model = Mac17,4`、macOS 27.0.1）的唯讀 `ioreg` 查詢。網頁來源多為 GitHub README、開發者論壇與科技媒體；未能用一手來源佐證的說法放在 Gaps 或標「未證實」。

## 觸控板：Force Touch 壓力與私有 MultitouchSupport 原始觸點

### Takeaway
公開 API（`NSPressureConfiguration`、`pressureChange(with:)`、`NSEvent.stage == 2`）只在游標落在自己 App 的 view 上時收得到，適合 WindowShade 自己的卷簾條、刘海面板內的「深按」，不能做全域觸發。全域、任意位置的多指手勢要靠私有 `MultitouchSupport.framework`（BetterTouchTool、Glide 等的做法），需關沙盒、要執行動作時需輔助使用權限，且每次 macOS 大改版都可能壞。

### Cited Findings
- `NSPressureConfiguration` 控制 Force Touch 觸控板對拖曳或壓力序列的反應，可指派給 view 與 gesture recognizer；辨識中途不建議改設定 — [Apple: NSPressureConfiguration](https://developer.apple.com/documentation/appkit/nspressureconfiguration.md)；[Apple: NSGestureRecognizer.pressureConfiguration](https://developer.apple.com/documentation/appkit/nsgesturerecognizer/pressureconfiguration.md)
- `primaryDeepClick` 支援兩段，開始拖曳後停用第 2 段，進出第 2 段時有觸覺回饋 — [Apple: PressureBehavior.primaryDeepClick](https://developer.apple.com/tutorials/data/documentation/appkit/nsevent/pressurebehavior-swift.enum/primarydeepclick.md)
- `NSEvent.stage` 在按壓超過一般按下時為 2；Apple 建議第 2 段用來觸發查詢或立即動作；階段可能跳躍（2 直接回 0） — [Apple: NSEvent.stage](https://developer.apple.com/documentation/appkit/nsevent/stage.md)
- 實務寫法：覆寫 `pressureChange(with:)`，記錄前一個 stage，只在第一次進入 stage 2 時觸發（Ghostty 終端機的提交採用此法） — [Ghostty commit mirror](https://git.uoc.run.place/Applied-Software/ghostty/commit/c165cef0a660e76f05fa941e65584e1add526069)；[Stack Overflow 鏡像](https://kiwix.lema.org/stackoverflow.com_en_all_2023-11/questions/39852290/nstextfield-allow-editing-only-with-force-touch-cocoa)
- 多個開源專案包裝私有 `MultitouchSupport.framework` 讀原始觸點：MultitouchKit（Swift）、OpenMultitouchSupport（README 說必須關閉 App Sandbox）、trackpad-rs（警告不適合上 App Store）、Hammerspoon 模組、go-macos/multitouch（框架沒有公開標頭） — [MultitouchKit](https://github.com/akinazuki/MultitouchKit)；[OpenMultitouchSupport](https://awesome.ecosyste.ms/projects/github.com%2Fkyome22%2Fopenmultitouchsupport)；[trackpad-rs](https://www.github.com/DeepSignSecurity/trackpad-rs)；[HS multitouch](https://github.com/catokolas/HS_ModulesContrib-multitouch)；[go-macos/multitouch](https://pkg.go.dev/github.com/go-macos/multitouch)
- mactic 以 dlopen/dlsym 載入框架，並指出 Apple Silicon 的 arm64e 指標驗證（PAC）會讓直接呼叫私有框架出現 bus error；每指 96 位元組的結構是經驗推出的 — [mactic](https://hn.jakechampion.name/reader/https://github.com/MatMercer/mactic)
- Glide 在執行期載入 MultitouchSupport 取得原始觸點，並要求 App 列入輔助使用清單才能執行手勢動作 — [Glide](https://gh.r-mj.com/Vatsal057/Glide)
- Swish（觸控板視窗管理）因需低階系統操作無法沙盒化、不上 App Store，需輔助使用權限；開發者宣稱支援 Intel 與 Apple Silicon、有 macOS 14 更新 — [Swish（highlyopinionated.co）](https://highlyopinionated.co/swish/)；[Softpedia](https://mac.softpedia.com/get/Utilities/Swish.shtml)
- Jitouch 是免費開源的多點觸控手勢擴充（MacBook、Magic Mouse、Magic Trackpad），評論說不太穩定；未找到 Sonoma 以後的相容說明 — [habr 評測](https://habr.com/en/articles/709402)；[AlternativeTo](https://alternativeto.net/software/jitouch)
- BetterTouchTool 論壇：macOS 更新後權限常錯亂，版主建議移除再加回輔助使用，並確認 BTT 不在輸入監控清單；有人在 Sequoia 15.7 上權限顯示已給卻當掉；Tahoe 26.2 有「BTT 6.143 讓所有滑鼠鍵盤輸入卡死直到退出 BTT」的回報 — [macOS Sequoia Discussions](https://community.folivora.ai/t/macos-sequoia-discussions/37603)；[BTT crashing in Sequoia](https://community.folivora.ai/t/btt-crashing-in-sequoia/45131?page=2)；[Tahoe 26.2 blocks input](https://community.folivora.ai/t/bettertouchtool-6-143-on-macos-tahoe-26-2-blocks-all-mouse-clicks-keyboard-input-until-btt-is-quit/46198)；[Trackpad gestures not working](https://community.folivora.ai/t/trackpad-gestures-not-working-after-clean-reinstall-all-permissions-granted/43962)

### Inferences
- 對 WindowShade：卷簾條／刘海面板本來就是自己的視窗，所以「在卷簾條上深按 = 展開/置頂」幾乎零權限、零私有 API，是最便宜的 Force Touch 用法。代價是外接非 Force Touch 滑鼠用不到，也必須有替代操作。
- 全域多指點擊（例如三指輕點、四指輕點觸發視窗瀏覽）要走 MultitouchSupport，私有 API 本身 WindowShade 可接受，但維運成本在每個 macOS 版本都要回歸測試；BTT 論壇在 15/26 都有權限與輸入卡死回報，代表這條路的「失敗模式」可能傷到整台機器的輸入，不只是功能失效。
- 讀觸點本身（被動監聽）在已知專案中並不要求輔助使用權限，權限是「執行動作」時才需要（Glide、Swish 的描述）；但這是從 README 推論，未見 Apple 文件。

### Gaps
- MultitouchSupport 在 macOS 26/27 上是否仍可用、是否新增 TCC 檢查：未找到一手來源；BTT 仍在 26.2 上運作可間接推論可用，但未證實。
- BetterTouchTool、Swish 實際使用的底層機制：官方未公開；未證實 Swish 用 MultitouchSupport。
- Force Touch 壓力的全域監聽（`addGlobalMonitorForEvents` 是否能收 `.pressure`）：Apple 文件頁擷取失敗，未證實。

## 機身敲擊：Intel 的 SMS 與 Apple Silicon 的 SPU 加速度計／陀螺儀／蓋子角度

### Takeaway
2006 年的 SmackBook 用 Intel/PowerPC 筆電的 Sudden Motion Sensor 拍機身切桌面；Apple Silicon 時代（2025–2026）有人找到 SPU 底下未公開的 IMU（推測 Bosch BMI286），透過 IOKit HID 以約 800 Hz 讀取，並已有商業產品（Knock、SlapMac）用它做「敲機身/拍桌觸發」。讀取需要 root（或 root 的 launchd 服務），支援機型不一致，M1 基本款普遍不支援。這台 M5 MacBook Air 上確認有對應的 HID 裝置。

### Cited Findings
- SmackBook（2006，Erling Ellingsen）：拍 Mac 側邊在虛擬桌面間切換，基於 Sudden Motion Sensor，程式碼公開 — [hoaxes.org](https://hoaxes.org/weblog/comments/smackbook)；[TidBITS 2006](https://tidbits.com/2006/05/29/sudden-motion-sensor-hacks/)；[Smackbook-Yosemite](https://github.com/dabockster/Smackbook-Yosemite)
- olvvier/apple-silicon-accelerometer：IMU 位於 `AppleSPUHIDDevice`、vendor usage page `0xFF00`，usage 3 = 加速度計、usage 9 = 陀螺儀；驅動 `AppleSPUHIDDriver`；以 `IOHIDDeviceCreate` + `IOHIDDeviceRegisterInputReportCallback` 收 22 位元組報告；原生約 800 Hz；**讀取需要 root**；只在 M3 Pro MacBook Pro、macOS 15.6.1 測過；已知不相容：Intel、2020 M1 MacBook Pro、Mac Studio M4 Max；作者標為實驗性、可能隨 macOS 更新失效 — [olvvier/apple-silicon-accelerometer](https://github.com/olvvier/apple-silicon-accelerometer)；[macimu (PyPI)](https://pypi.org/project/macimu/)
- taigrr/spank：拍 MacBook 播音效；用 STA/LTA、CUSUM、峰度、峰值/MAD 做振動偵測；預設最小振幅 0.05 g、冷卻 750 ms；需 sudo，或以 root 的 launchd 服務執行；支援 M2 以後或 M1 Pro，其他 M1 不支援；感測器程式碼移植自 olvvier；約 5k stars — [taigrr/spank](https://github.com/taigrr/spank)
- Knock（Product Hunt，2026-03-16 首發，付費）：敲筆電側邊觸發自訂捷徑（截圖、開 App、靜音、切桌面、跑腳本），用內建加速度計；有使用者問到放下筆電或大力打字的誤觸處理，頁面上無回覆 — [Knock on Product Hunt](https://www.producthunt.com/products/knock-7)
- SlapMac（2026-03，Tonino Catapano）：拍 MacBook 發聲，力度決定音量；報導稱需 Apple Silicon MacBook、macOS 14.6+、非 App Store；首三天逾 7,000 次安裝（二手報導數字） — [TechSpot](https://www.techspot.com/news/111862-app-makes-macbook-moan-when-you-slap-going.html)；[iPhoneSoft](https://iphonesoft.fr/2026/03/28/slapmac-application-absurde-gemir-macbook)
- 支援機型說法衝突：一篇報導說 M1 到 M4 都有；macimu 列 2020 M1 MBP 不相容；spank 說 M1 Pro 可以、其他 M1 不行；SlapDash 標 M1 Pro 以後 — [lavx news](https://news.lavx.hu/article/the-hidden-sensor-inside-your-macbook-developers-tap-into-apple-silicon-s-undocumented-accelerometer)；[macimu](https://pypi.org/project/macimu/)；[spank](https://github.com/taigrr/spank)
- 蓋子角度感測器：Sam Gold 的 LidAngleSensor 顯示開蓋角度並可播開門吱嘎聲；FAQ 說感測器始於 2019 16 吋 MacBook Pro，但回報在 M1/M2（M1 Air、M1/M2 Touch Bar MBP）不能用，作者只在 M4 MBP 測過；另有 pybooklid、maclidsensor（只依賴 hidapi）、lid-angle-rs — [LidAngleSensor](https://github.com/samhenrigold/LidAngleSensor)；[pybooklid](https://pypi.org/project/pybooklid/)；[maclidsensor](https://pypi.org/project/maclidsensor/)；[Gigazine 2025-09-08](https://gigazine.net/gsc_news/en/20250908-macbook-sensor-angle-screen-hinge)
- **本機佐證（2026-11-01，M5 MacBook Air Mac17,4，macOS 27.0.1）**：`ioreg -r -c AppleSPUHIDDevice` 列出 `PrimaryUsagePage = 65280 (0xFF00)` 下含 `PrimaryUsage = 3` 與 `= 9`，與上列專案描述的加速度計/陀螺儀一致；另有 `PrimaryUsagePage = 32 (0x20, HID Sensor)`、`PrimaryUsage = 138 (0x8A)` 的裝置，推測是蓋子角度（未讀數值、未證實）。未嘗試實際讀取，因此「非 root 能否讀」在 macOS 27 上未驗證。

### Inferences
- 「敲機身兩下」是最接近 iPhone Back Tap 的 Mac 對應，但成本結構不同：需要 root 常駐 helper（`SMAppService` daemon 或 launchd），會讓 WindowShade 安裝流程多一次管理員授權，也擴大攻擊面；800 Hz 持續讀取 + 訊號處理有常駐功耗（未找到量測數據）。
- 誤觸是核心風險：打字、放下筆電、桌面震動都會觸發；spank 的單次閾值設計不足以當產品級觸發，至少要做「雙敲 + 時間窗 + 打字中抑制 + 蓋子開啟角度條件」。
- 只適用 MacBook 本體，外接螢幕闔蓋模式、桌機（Mac mini/Studio）不可用；Magic Keyboard/Trackpad 無此感測器。
- 蓋子角度可當「低打擾情境訊號」（例如半闔時自動收起敏感視窗），比當主動觸發更合適。

### Gaps
- 非 root 讀取 SPU HID 是否可行（例如透過 Input Monitoring 的 `IOHIDRequestAccess`）：沒有來源測試過。
- Knock 與 SlapMac 是否需要管理員 helper：產品頁沒寫，未證實。
- 持續讀 IMU 的功耗：無量測資料。
- 機型支援表：各來源互相矛盾，無 Apple 官方資料；需在目標機型實測。

## Magic Mouse、外接 Magic Trackpad 與鍵盤（修飾鍵雙擊、Fn/🌐、Touch ID、觸控列）

### Takeaway
修飾鍵雙擊（⌘⌥⌃⇧）是 Mac 上最成熟、可發現性最好的「Double Tap」對應：Raycast（2022 起）、Alfred、Keyboard Maestro、開源 Magnet 都支援，只需監聽 flagsChanged；權限上走 listen-only event tap 只需輸入監控，或用輔助使用。Magic Mouse 表面與外接 Magic Trackpad 走同一個 MultitouchSupport 路徑。Touch ID 沒有找到任何第三方可偵測「輕觸」的方法，第三方只能透過 LocalAuthentication 拿到驗證成功/失敗。

### Cited Findings
- Raycast 1.42.0（2022-10-26）起支援以雙擊修飾鍵當熱鍵，支援 ⌘ ⌥ ⌃ ⇧ — [Raycast changelog 1.42.0](https://www.raycast.com/changelog/macos-v1/1-42-0)；[Raycast manual: hotkeys](https://manual.raycast.com/command-aliases-and-hotkeys.md)
- Alfred 支援雙擊修飾鍵觸發；論壇回報雙擊 Shift 在接著按其他鍵時仍誤觸發 — [Alfred forum](https://www.alfredforum.com/topic/17107-possibility-to-change-double-tap-sensitivity/)
- Keyboard Maestro 論壇討論以雙擊 Cmd/Opt/Shift/Control 當熱鍵 — [KM forum](https://forum.keyboardmaestro.com/t/double-tap-cmd-opt-shift-control-as-hotkeys/30449)
- 開源 Magnet 熱鍵函式庫支援「像 Alfred 一樣」的雙擊修飾鍵熱鍵 — [Magnet](https://github.com/DivineDominion/Magnet)
- Mac App Store 上的 Double Tap App 可把修飾鍵雙擊映射成捷徑；有 Reddit 使用者回報給了權限仍無效 — [App Store: Double Tap](https://apps.apple.com/app/id6739712671)；[r/macapps](https://reddit.birdcat.cafe/r/macapps/comments/1k1chwb/dont_sprain_your_finger_with_your_cmdoptshiftg)
- Event tap 權限分流（論壇，Apple DTS Kevin Elliott 的說法，非官方文件）：`defaultTap` 觸發輔助使用請求、`listenOnly` 觸發輸入監控請求；輔助使用涵蓋「發送與監聽」，輸入監控只涵蓋「監聽」；`CGRequestListenEventAccess()` 有時不會把 App 加進清單，建議用 `IOHIDRequestAccess()` — [Apple Developer Forums 828052](https://developer.apple.com/forums/thread/828052)；Mumble 以 listen-only tap 改成只需輸入監控 — [mumble PR 7065](https://github.blesdmm.dns-dynamic.net/mumble-voip/mumble/pull/7065)
- Jitouch 支援 Magic Mouse 與 Magic Trackpad 的額外手勢；MultitouchSupport 包裝庫（trackpad-rs）同時涵蓋 Trackpad 與 Magic Mouse — [AlternativeTo: Jitouch](https://alternativeto.net/software/jitouch)；[trackpad-rs](https://www.github.com/DeepSignSecurity/trackpad-rs)
- Touch ID：搜尋到的資料只顯示第三方透過 LocalAuthentication 取得「是否為擁有者」的驗證結果，未找到任何偵測裸觸碰的方法 — [Apple Forums: Touch ID existence](https://developer.apple.com/forums/thread/71930)；[Electron Touch ID PR](https://ayakael.net/mirrors/electron/commit/46a24c82ff115221d17f158911bb41f53a01c1e1)

### Inferences
- WindowShade 已用輔助使用權限做視窗操作，因此加修飾鍵雙擊不增加新權限；誤觸要用「兩次按放間隔 < ~300 ms、中間沒有其他鍵、沒有搭配滑鼠點擊」來擋（Alfred 的 Shift 回報就是缺這個檢查）。⌘/⌥ 雙擊已被 Raycast、Alfred、ChatGPT 類 App 大量佔用，選鍵要讓使用者自訂並偵測衝突。
- Fn/🌐 雙擊：系統把 🌐 用於切換輸入法、表情符號、聽寫（雙擊 Fn 預設是聽寫，見 Gaps），衝突風險高，不建議預設。
- Touch ID 當觸發：視為不可行（找不到證據，且 LocalAuthentication 每次都會彈驗證框，打擾成本高）。
- 觸控列：已從現行機型移除，不列入。

### Gaps
- 「雙擊 Fn 預設啟動聽寫」與 🌐 鍵行為的官方說明本輪未查證。
- `addGlobalMonitorForEvents` 監聽 `.flagsChanged` 是否需要輔助使用：Apple 文件頁擷取失敗；一般認知是鍵盤類事件需輔助使用信任，未在本輪以一手來源證實。
- Touch ID 是否存在任何私有 HID 事件可讀：沒有來源，標「未證實（推定不可行）」。

## 游標與捲動：熱角、撞邊、推入刘海、捲軸手勢

### Takeaway
這類觸發不需要特殊硬體，權限低（追蹤游標位置用公開 API 即可，滑鼠移動的全域監聽不需輔助使用），WindowShade 本身的刘海互動就屬這類。本輪沒有找到第三方掛入系統「熱角」的官方介面，第三方 App 的做法是自己偵測游標位置。

### Cited Findings
- 本輪未取得此主題的可引用來源（搜尋配額用於其他主題）。

### Inferences
- 「游標推入刘海 + 停留/再推一次」是 WindowShade 最自然的 Double Tap 對應：零新權限、所有 Mac 都有（無刘海螢幕則用頂邊中央），可發現性靠首次引導。風險是與系統選單列自動顯示、全螢幕 App 選單列、系統熱角搶同一位置。
- 捲軸手勢（在選單列或卷簾條上雙指捲動）只要事件落在自己的視窗即可收，和 Force Touch 一樣是低成本的「本地」觸發。

### Gaps
- 系統熱角是否有公開/私有 API 讓第三方註冊動作（`com.apple.dock` 的 `wvous-*` 偏好鍵只能選內建動作）：未查證。
- 撞邊觸發的誤觸率、與 Stage Manager／Dock 自動顯示衝突的具體資料：無來源。

## 麥克風敲桌與相機手勢

### Takeaway
2026 年的「拍桌」產品（Knock）其實用的是加速度計而非麥克風；麥克風偵測需要麥克風權限且常駐錄音指示燈會亮，打擾與隱私成本高於收益。相機手勢在系統層有現成實作（Pointer Control 的臉部表情），第三方自己做需要相機權限並讓相機燈常亮。

### Cited Findings
- Knock 官方描述用「內建加速度計」偵測敲擊，不是麥克風 — [Knock on Product Hunt](https://www.producthunt.com/products/knock-7)
- 2006 年有以 iSight 加動作感測器的實驗 — [headingeast 2006-06](https://www.mexicanpictures.com/headingeast/2006/06/motion-sensing-and-isight-hack.html)

### Inferences
- 麥克風常駐監聽會讓選單列出現麥克風使用指示，與 WindowShade「低打擾」目標相反；不建議。

### Gaps
- 未找到 2024–2026 年以麥克風偵測敲桌的現役 Mac 產品或專案。

## macOS 無障礙觸發：Pointer Control 替代動作、Accessibility Keyboard、Switch Control

### Takeaway
Pointer Control 的「替代指標動作」可把臉部表情（微笑、張嘴、挑眉、吐舌）或開關映射到點擊、右鍵、拖曳等滑鼠動作，需相機權限；本輪沒有找到第三方 App 可直接註冊為其動作目標的介面。可行的掛入方式是間接的：讓系統動作產生一個鍵盤快捷鍵或點擊，再由 WindowShade 接收。

### Cited Findings
- 替代指標動作位於 輔助使用 › 指標控制 › 替代控制方式，可用開關或臉部表情取代滑鼠動作；內建表情有微笑、張嘴、挑眉、吐舌；可開啟音效與視覺回饋；需相機權限 — [How-To Geek](https://www.howtogeek.com/788217/how-to-use-your-head-and-face-to-control-your-mac/)；[AbilityNet: pointer actions](https://mcmw.abilitynet.org.uk/how-to-set-up-pointer-actions-in-macos)；[thoughtbot: Head Pointer](https://thoughtbot.com/blog/an-introduction-to-macos-head-pointer)
- 頭部指標可移動游標，啟用時鍵盤、滑鼠、觸控板仍可用 — [AbilityNet: head pointer](https://mcmw.abilitynet.org.uk/how-to-use-the-head-pointer-in-macos)；[MacMost](https://macmost.com/controlling-your-mac-with-head-movements.html)

### Inferences
- 替代動作若能映射為「按某鍵盤快捷鍵」（未證實），WindowShade 只要提供可自訂的全域快捷鍵就能被無障礙使用者用表情或外接開關觸發；這是零成本的相容策略，比自己做相機手勢好。
- Switch Control 與 Accessibility Keyboard 的自訂面板可加按鈕發送按鍵（未證實細節），同樣靠「WindowShade 有快捷鍵」這一前提。

### Gaps
- 替代指標動作能否設成發送任意鍵盤快捷鍵：本輪來源只列滑鼠動作，未證實。
- Switch Control、Accessibility Keyboard 面板編輯器能否呼叫第三方 App Intents／捷徑：未查證。
- 這些系統功能是否有第三方可用 API：未找到。

## 各觸發比較（權限、誤觸、功耗、可發現性、衝突、版本）

### Takeaway
依成本排序：自家視窗內的 Force Touch 深按／捲動 ≈ 游標推入刘海 < 修飾鍵雙擊 < 全域多指觸控（私有 MultitouchSupport） < 機身敲擊（SPU IMU，需 root） < 麥克風／相機。Touch ID 輕觸視為不可行。

### Cited Findings
- 各列依據見上方各節的引用；下表「權限」欄的 SPU 需 root 來自 [olvvier](https://github.com/olvvier/apple-silicon-accelerometer) 與 [spank](https://github.com/taigrr/spank)，輸入監控/輔助使用分流來自 [Apple Forums 828052](https://developer.apple.com/forums/thread/828052)。

| 觸發 | 權限 | 誤觸風險 | 功耗 | 可發現性 | 系統衝突 | 版本/硬體限制 |
| --- | --- | --- | --- | --- | --- | --- |
| 自家視窗內深按（stage 2） | 無 | 低 | 無額外 | 低（需引導） | 與系統「查詢」深按同手勢，但只在自家視窗 | 需 Force Touch 觸控板 |
| 游標推入刘海／頂邊 | 無（追游標） | 中（經過選單列） | 低 | 中 | 選單列自動顯示、熱角 | 全機型 |
| 修飾鍵雙擊 | 輸入監控（listen-only）或輔助使用 | 中（需間隔與獨按檢查） | 低 | 高（Raycast/Alfred 已教育使用者） | 與 Raycast、Alfred 等搶鍵 | 全機型 |
| 全域多指手勢 | 讀取：未證實需權限；執行：輔助使用；需非沙盒 | 中 | 低～中 | 中 | 系統三/四指手勢 | 私有 API，每版需回歸 |
| 敲機身（SPU IMU） | root helper | 高（打字、放下） | 常駐取樣，未量測 | 低 | 無 | MacBook M1 Pro/M2+，機型表衝突；桌機無 |
| 麥克風敲桌 | 麥克風 | 高 | 中 | 低 | 麥克風指示燈 | 全機型 |
| 相機表情 | 相機 | 中 | 高 | 低 | 系統 Pointer Control | 有相機機型 |
| Touch ID 輕觸 | — | — | — | — | — | 未證實，推定不可行 |

### Inferences
- 若 WindowShade 要一個「Back Tap 等級」的旗艦觸發，建議組合是：預設「游標推入刘海」+ 可自訂修飾鍵雙擊；把「敲機身兩下」當實驗功能（需 root helper、機型偵測、打字抑制），不當預設。

### Gaps
- 所有項目都缺功耗量測；誤觸率缺數據。
- macOS 27（本機版本）上的行為除 SPU HID 裝置存在外，其餘皆未實測。
