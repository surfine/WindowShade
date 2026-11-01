# 低打擾手勢靠上下文閘門取勝

研究日期 2026-11-01。依據為 `research_notes/Apple 輕點背面與手勢輸入/` 下四份筆記，加上本輪對 WindowShade 原始碼的唯讀核對。

Apple 這一族低打擾、免觸控的輸入，幾乎都沒有為手勢加新硬體，用的是既有感測器（IMU、光學心率、相機、壓力感測）加分類器。真正讓它們好用、少誤觸的是**上下文閘門**：Watch 的 Double Tap 只在螢幕亮起時偵測，AirPods 點頭搖頭只在 Siri 播報時有效，Vision Pro 的系統手勢要先看手掌才出現。演算法更嚴格是次要的。推出路線上，多數先以輔助使用功能出貨，完整、可重映射；之後再縮成一兩個語義固定、預設開啟的主流手勢。Apple Watch 從 2021 年的 AssistiveTouch 到 2023 年的 Double Tap 是最清楚的例子。Back Tap 是例外：它從 iOS 14 起一直留在輔助使用設定裡，也沒有開放 API。開發者 API 的分界也有規律：手勢語義綁在 App 內容上的才開放（Pencil 擠壓、Camera Control、Watch 的 primaryAction、Look to Scroll）；系統層語義（關通知、回應 Siri、叫控制中心、Back Tap）只留給系統。這讓 Mac 上的第三方 App 無處可掛，只能自己接感測器，自己負責回饋與防誤觸。對 WindowShade 的結論是：最划算的兩個觸發已經在手上。一個是游標推入刘海，另一個是卷簾條上的 Force Touch 深按，後者在 `prototype/App/TrackpadGestures.swift` 已實作為「看一眼」。下一步依序是：可自訂的修飾鍵雙擊；選擇性的全域多指手勢；最後才是實驗性的「敲機身兩下」。麥克風、相機表情與 Touch ID 不值得做。有兩件事要先知道。第一，Back Tap 的偵測機制 Apple 從未公開，常被引用的「機器學習敲擊偵測」專利屬於 Amazon。第二，Mac 的 Pointer Control 臉部表情從 macOS Catalina 就有了，不是新功能。

## 一張表看完這個家族：多數先進輔助使用，主流版只留一兩個語義

下表整理各功能的推出時間、觸發方式與機制。「機制」欄只寫有來源的部分；Apple 沒公開的標「未公開」。

| 功能 | 推出 | 觸發 | 感測器／機制 | 可配置動作 | 開發者 API |
| --- | --- | --- | --- | --- | --- |
| iPhone 輕點背面 | iOS 14（WWDC 2020 公布），iPhone 8 起 | 背面點兩下／點三下 | **Apple 未公開**；媒體普遍說是加速度計（部分加陀螺儀） | 兩下、三下各綁一個：系統動作、輔助使用、捲動、任一捷徑；iOS 18 新增 6 項 | 無；只能經捷徑／App Intent 間接綁 |
| iPhone／iPad AssistiveTouch | iOS 5（2011 年 7 月 beta 3 啟用） | 螢幕浮動按鈕、自訂手勢、指標裝置、Dwell | 軟體層 | 最上層選單、單點／兩下／長按、錄製 2–5 指手勢 | 無 |
| Watch AssistiveTouch | 2021-05 預告，watchOS 8 | 捏合、握拳（現稱 Tap／Double tap／Clench／Double clench）、Motion Pointer | 陀螺儀、加速度計、光學心率＋裝置端 ML | 每個手勢可指派任意動作或 Siri 捷徑 | 無 |
| Watch Double Tap | watchOS 10.1（2023-10-25），預設開啟 | 拇指食指互點兩下 | 加速度計、陀螺儀、光學心率，由 S9 神經網路引擎跑新 ML 演算法 | 只有 Smart Stack 與播放兩處可選 | watchOS 11 起 `handGestureShortcut(.primaryAction)` |
| Watch Wrist Flick | watchOS 26（2025-06 WWDC 發表） | 手腕翻過去再翻回 | 加速度計＋陀螺儀＋ML 模型（沒提光學感測器） | 開關 | 未見 API |
| Watch 單捏 | watchOS 27（2026-06-08 首個 beta） | 互點一次，選 Smart Stack 高亮 widget | 未核實 | 未核實 | 未核實 |
| Vision Pro 捏合與手掌手勢 | visionOS 1（2024）；手掌手勢 visionOS 2（2024-09） | 看＋捏；看手掌出按鈕、翻手出狀態列 | 眼動＋手部追蹤相機 | 舊「抬頭看」退為輔助使用選項 | 捏合間接可用；手掌系統手勢 App 不能停用 |
| AirPods 點頭搖頭 | iOS 18（2024-09） | 點頭＝接受，搖頭＝拒絕 | AirPods 內建 IMU | 可關、可對調、有引導練習 | 只有 `CMHeadphoneMotionManager` 原始姿態 |
| Apple Pencil Pro 擠壓 | 2024-05 | 擠壓筆身；barrel roll 旋轉 | 筆身壓力感測器、陀螺儀；觸覺引擎確認 | 系統偏好動作 | `UIPencilInteraction` 擠壓回呼、`UIPencilHoverPose.rollAngle` |
| iPhone／iPad Eye Tracking | iOS／iPadOS 18（2024-05 預告） | 注視＋Dwell | 前鏡頭＋裝置端 ML，資料留在裝置 | Dwell 參數；iOS 26 起可用開關選取 | 未找到 App 端訊號（未證實） |
| iPhone／iPad Head Tracking | iOS／iPadOS 26（2025-05 預告） | 頭部動作 | 相機 | 未詳查 | 未找到 |
| Mac Pointer Control 臉部表情 | macOS Catalina 10.15（2019；另有來源說 10.15.4） | 微笑、張嘴、吐舌、揚眉、眨眼、皺鼻、嘟嘴 | 相機 | 映射到左鍵、右鍵、雙擊、三擊、拖放；可開音效與視覺確認 | 無 |
| iPhone Camera Control | iPhone 16（2024-09） | 輕壓出覆蓋層，再滑動調值 | 壓力與觸控按鍵 | 系統設定 | `AVCaptureEventInteraction`、`LockedCameraCapture` |

上表的依據：Back Tap 版本與機型見 Apple 支援頁 ([Apple Support 111772](https://support.apple.com/en-us/111772))，iOS 18 新增動作見 ([Gadget Hacks](https://ios.gadgethacks.com/how-to/your-iphones-hidden-back-tap-button-has-6-more-actions-available-with-ios-18-0385612))。AssistiveTouch 起源見 ([macerkopf.de](https://www.macerkopf.de/2011/07/12/beta-3-ios-5-mit-assistive-touch-video/))，自訂項目見 ([Apple Support 111794](https://support.apple.com/en-us/111794))。Watch 三種手勢分別見 ([Apple Newsroom 2021-05](https://www.apple.com/newsroom/2021/05/apple-previews-powerful-software-updates-designed-for-people-with-disabilities/))、([Apple Newsroom 2023-10](https://www.apple.com/newsroom/2023/10/apple-watch-double-tap-gesture-now-available-with-watchos-10-1/))、([Apple Newsroom 2025-06](https://www.apple.com/newsroom/2025/06/watchos-26-delivers-more-personalized-ways-to-stay-active-and-connected/))。Vision Pro 見 ([Apple Support 117741](https://support.apple.com/en-asia/117741))，AirPods 見 ([Apple Support 102536](https://support.apple.com/102536))，Pencil 見 ([Apple Developer：Handling squeezes](https://developer.apple.com/documentation/applepencil/handling-squeezes-from-apple-pencil.md))。Eye Tracking 見 ([Apple Newsroom 2024-05-15](https://www.apple.com/newsroom/2024/05/apple-announces-new-accessibility-features-including-eye-tracking/))，Head Tracking 見 ([Apple Newsroom 2025-05-13](https://www.apple.com/newsroom/2025/05/apple-unveils-powerful-accessibility-features-coming-later-this-year/))。Pointer Control 見 ([How-To Geek](https://www.howtogeek.com/788217/how-to-use-your-head-and-face-to-control-your-mac/))，版本分歧見 ([thoughtbot](https://thoughtbot.com/blog/an-introduction-to-macos-head-pointer))。Camera Control 見 ([Apple Developer：Camera Control](https://developer.apple.com/tutorials/data/documentation/avfoundation/enhancing-your-app-experience-with-the-camera-control.md))。

功耗是整張表最大的空白。Apple 沒有為任何一項公開功耗數字。最接近的是 S9 晶片「比前代省電 25%」，加上二手報導轉述 Apple 說 Double Tap 對電池影響「minimal」，後者找不到 Apple 原文 ([Stuff.tv](https://www.stuff.tv/?p=912394))。能確定的只有 Apple 怎麼「不讓它常駐」：這點留到後面講。

## Back Tap：Apple 從沒說它怎麼偵測，ML 專利其實是 Amazon 的

Back Tap 隨 iOS 14 在 WWDC 2020 公布，支援 **iPhone 8 及更新機型、iPhone SE 第 2 代起**，路徑是 設定 > 輔助使用 > 觸控 > 輕點背面 ([Apple Support 111772](https://support.apple.com/en-us/111772))。iOS 14 本身支援到 iPhone 6s，Back Tap 的門檻卻定在 iPhone 8。為什麼，Apple 沒說明；筆記推測和 A11 起的感測器或協處理器有關，屬未證實。可綁的動作從一開始就很廣：App 切換器、控制中心、截圖、搖動（可當撤銷）、便於單手操作、VoiceOver、縮放、上下捲動，以及任一捷徑 ([MacMost](https://macmost.com/the-best-hidden-feature-of-ios-14-back-tap.html))。iOS 18 再加 6 項：前鏡頭、Music Haptics、Vehicle Motion Cues、Hover Typing、Live Recognition、Assistive Access ([Gadget Hacks](https://ios.gadgethacks.com/how-to/your-iphones-hidden-back-tap-button-has-6-more-actions-available-with-ios-18-0385612))。iOS 26 有沒有改 Back Tap，本輪搜不到報導。搜不到不代表沒改，要看實機設定才能確定。

偵測機制必須分清事實和推測。**Apple 的支援頁完全不談原理，也不提手機殼**；Apple 名下也找不到對應的專利、WWDC 講座或工程訪談。媒體與 AppleVis 社群普遍說它靠加速度計，有些加上陀螺儀 ([AppleVis](https://applevis.com/podcasts/revisiting-how-use-back-tap-ios))。常被當成「Back Tap 用機器學習」證據的 **US 9,235,278 B1「Machine-learning based tap detection」，受讓人是 Amazon Technologies, Inc.**，2014 年申請、2016 年核准，內容是從 IMU 資料抽特徵、用 random forest 判斷背面敲擊 ([Google Patents](https://patents.google.com/patent/US9235278))。它只能證明業界有這種做法，不能證明 Apple 這樣做。可以確定的旁證有兩個。Google 同期的 Pixel Quick Tap（代號 Columbus，Android 12 上線）確實用 TensorFlow 模型 ([Kieron Quinn](https://medium.com/@KieronQuinn/tap-tap-v1-0-restarting-from-scratch-2b87c241d176))。2013 年的學術原型 BackTap 則顯示，不用 ML、只靠麥克風加 IMU 的啟發式閾值也做得到 ([ACM](https://unpaywall.org/10.1145%2F2508468.2514735))。所以「Apple 用 IMU 加某種分類器」是合理推測，ML 或規則都有可能，仍不是事實。功耗低的說法也只是推論，理由是 IMU 本來就由動作協處理器常駐處理，沒有任何量測。另有說法稱手機鎖定或螢幕朝下時不觸發，來源可信度低，**未證實** ([easyit.com](https://www.easyit.com/backtap/))。

誤觸與漏偵測都有使用者回報，而且兩極。厚殼是排障指南列為漏偵測的頭號原因 ([iGeeksBlog](https://www.igeeksblog.com/iphone-back-tap-not-working/))。Apple 社群同一串討論裡，有人五次只成功一次，也有人戴殼仍頻繁誤觸 ([Apple Community](https://discussions-jp-prz.apple.com/thread/255939220))。常見的緩解是把「點兩下」改成「點三下」，或只綁影響小的動作 ([Dr.Fone](https://drfone.wondershare.com/what-is/what-is-back-tap-iphone-s-hidden-gesture-feature.html))。第三方 App **沒有公開 API** 偵測 Back Tap。實際可行的整合是：App 暴露 App Intent，使用者自己把 Back Tap 綁到那個捷徑。

Back Tap 也說明了「無障礙功能被大眾發掘」這條路。它一推出就被稱為「iOS 14 最好的隱藏功能」([MacMost](https://macmost.com/the-best-hidden-feature-of-ios-14-back-tap.html))。到了 iOS 26，新手指南仍把它當「多兩個隱藏按鈕」推薦 ([iDropNews](https://www.idropnews.com/how-to/ios-26-new-iphone-user-tips-guide/235708/8))。但它始終沒有搬出輔助使用設定，Apple 也沒解釋為什麼。可作對照的是 iPad 的指標支援：iPadOS 13 先放在輔助使用（AssistiveTouch），13.4 才把觸控板／滑鼠移到一般設定，進階的按鍵自訂仍留在 AssistiveTouch ([TidBITS](https://tidbits.com/2020/03/28/the-ipad-gets-full-trackpad-and-mouse-support/))。AssistiveTouch 自己則靠「Home 鍵壞了」這個大眾需求出圈，大量教學教人用它當虛擬 Home 鍵 ([How-To Geek](https://www.howtogeek.com/245286/how-to-use-an-iphone-with-a-broken-home-button/))。

## Apple Watch 把 AssistiveTouch 的整套詞彙，一年拆一個成主流手勢

2021 年 5 月，Apple 以無障礙功能預告 Watch 版 AssistiveTouch。原文說它用陀螺儀、加速度計、**光學心率感測器加裝置端機器學習**，偵測「肌肉動作的細微差異」，對象是上肢差異的使用者 ([Apple Newsroom 2021-05](https://www.apple.com/newsroom/2021/05/apple-previews-powerful-software-updates-designed-for-people-with-disabilities/))。它提供完整詞彙：Tap 預設往下一項，Double tap 往上一項，Clench 是點選，Double clench 開 Action Menu。另有傾斜手錶移動的 Motion Pointer。每個手勢都能重指派到任意動作或 Siri 捷徑 ([Apple Support](https://support.apple.com/guide/watch/use-assistivetouch-apdec70bfd2d/watchos))。初始支援機型為 SE 與 Series 6 以上，這點只有轉述 Apple 新聞稿的二手來源 ([Daring Fireball](https://daringfireball.net/linked/2021/05/19/apple-new-accessibility-features))，另一份筆記標為未以一手來源核實。

2023 年的 Double Tap 把這套技術縮成「一個手勢、一個語義」。Apple 說它由 S9 的 4 核神經網路引擎，用新 ML 演算法處理加速度計、陀螺儀、光學心率資料，辨識「手腕微動與血流變化的特徵」。它**預設開啟**，觸發畫面的主要動作 ([Apple Newsroom 2023-10](https://www.apple.com/newsroom/2023/10/apple-watch-double-tap-gesture-now-available-with-watchos-10-1/))。代價是可自訂性幾乎歸零，只有 Smart Stack 和播放時兩處可選。支援機型現為 Series 9 以上、Ultra 2 以上、SE 3 ([Apple Support 108413](https://support.apple.com/en-afri/108413))；SE 3 因改用 S10 晶片才加入 ([Engadget](https://www.engadget.com/wearables/apple-watch-se-3-has-an-s10-chip-and-always-on-display-173033538.html))。它和 AssistiveTouch／Quick Actions 互斥，所以「兩者共用同一條感測管線」的推測合理，但 Apple 沒說。

2025 年 watchOS 26 的 Wrist Flick 補上「拒絕／收起」的語義：關通知與來電、靜音計時器與鬧鐘、回錶面。關於感測器，兩份筆記有落差：一份說只找到 9to5Mac 的說法；另一份直接引到 Apple Newsroom 原文：「uses the accelerometer and the gyroscope — along with a machine learning model」，**沒提光學感測器** ([Apple Newsroom 2025-06](https://www.apple.com/newsroom/2025/06/watchos-26-delivers-more-personalized-ways-to-stay-active-and-connected/))。本報告以 Apple 原文為準。舊機型有同樣的感測器卻不支援，MacRumors 推測是新模型需要新晶片 ([MacRumors 2025-07-17](https://www.macrumors.com/2025/07/17/new-apple-watch-gesture-watchos-26-newer-models/))。2026 年 watchOS 27 再加單捏，用來選 Smart Stack 裡高亮的 widget，但資訊全來自二手報導 ([Wccftech](https://wccftech.com/apples-watchos-27-lets-siri-ai-brainstorm-workouts-and-read-your-mail-mid-call-while-a-new-pinch-gesture-makes-widget-selection-a-breeze/))。機型清單互相矛盾：BGR 說不再支援 Series 9，Gizchina 列為相容 ([BGR](https://bgr.com/2191261/watchos-27-adds-new-features-skips-old-models/))；官方名稱與是否開放 API 都未核實。三年下來的順序是：**確認（2023）→ 拒絕（2025）→ 選取（2026）**，等於把 2021 年 AssistiveTouch 的詞彙逐個主流化。

開發者 API 是刻意收窄的。watchOS 11 起只能用 `handGestureShortcut(.primaryAction)` 指定「哪個控制項是主要動作」，每個 scene 只能一個。系統負責優先順序（primary action、捲動、垂直分頁）和觸發時的高亮，App 拿不到原始手勢事件 ([Apple Developer](https://developer.apple.com/documentation/watchos-apps/enabling-double-tap))。開發者論壇有人問能否處理其餘手勢，未見官方回應 ([Forums 765831](https://developer.apple.com/forums/thread/765831))。

Apple 對 Double Tap 列出的「不能用」清單，等於它的省電與防誤觸設計。包括：螢幕沒亮時、低耗電模式、睡眠專注、劇院模式、Water Lock、配戴不貼合、Wrist Detection 關閉、戴錯手、ECG 或 Depth App 使用中、手臂在動。刺青也可能干擾 ([Apple Support 108413](https://support.apple.com/en-afri/108413))。偵測器不是全天常駐，只在抬腕亮屏的短窗口內跑。這樣既省電，也讓使用者沒在看手錶時的日常手部動作根本不會被判讀。評價則兩極：Trusted Reviews 稱它多年來最好的新功能 ([Trusted Reviews](https://www.trustedreviews.com/news/watchos-10-1-unlocks-the-best-new-apple-watch-feature-in-years-4384549))；Engadget 抱怨反覆抬腕累 ([Engadget](https://www.engadget.com/apple-watch-series-9-review-freedom-from-touching-your-screen-130009764.html))；BGR 認為實用性遠不如預期 ([BGR](https://bgr.com/tech/apple-watch-double-tap-feature-is-nowhere-near-as-useful-as-i-hoped))。

## 其他家族成員：防誤觸靠上下文，API 只開給綁內容的手勢

Vision Pro、AirPods、Pencil 三者，正好各示範一種上下文閘門。Vision Pro 的基本點按是「看＋拇指食指互碰」。visionOS 2 加入手掌手勢：看手掌出現按鈕可回主畫面，翻手出現狀態列，捏住左右移動調音量。舊的「抬頭看叫控制中心」則退成輔助使用選項 ([Apple Support 117741](https://support.apple.com/en-asia/117741))。這是一次反向流動：主流手勢退到無障礙設定保留。代價是 App 不能停用系統手掌手勢，開發者回報與自家手掌 UI 衝突 ([Forums 757044](https://developer.apple.com/forums/thread/757044))。AirPods 的點頭接受、搖頭拒絕，前提是開啟 Siri 播報來電與通知，所以只在 Siri 正在問的窗口內有意義 ([Apple Support 102536](https://support.apple.com/102536))。支援機型 Apple 頁面列到 AirPods Pro 3、AirPods 4、Powerbeats Pro 2 等；「AirPods 5」只見於搜尋摘要，未證實。macOS Sequoia 起在 Mac 上也能用，但只限回應 Siri。Pencil Pro 的擠壓用筆身壓力感測器偵測，是這族裡少見為手勢新增的專用硬體，並由觸覺引擎輕敲確認 ([MacTrast](https://www.mactrast.com/2024/05/apple-unveils-new-apple-pencil-pro-featuring-new-squeeze-gesture-haptic-feedback-find-my/amp/))。

相機類全部以無障礙功能出貨。iOS 18 的 Eye Tracking 用前鏡頭幾秒校準，靠 Dwell 啟動元素，資料只留在裝置上 ([Apple Newsroom 2024-05-15](https://www.apple.com/newsroom/2024/05/apple-announces-new-accessibility-features-including-eye-tracking/))。據報需 iPhone 12 以上 ([MacRumors](https://www.macrumors.com/2024/05/15/ios-18-accessibility-features))。iOS 26 加了 Head Tracking，以及給腦機介面的 Switch Control 協定 ([Apple Newsroom 2025-05-13](https://www.apple.com/newsroom/2025/05/apple-unveils-powerful-accessibility-features-coming-later-this-year/))。2026-05 預告 visionOS 27 會支援臉部手勢點按，細節未證實 ([MacRumors 2026-05-19](https://macrumors.com/2026/05/19/new-accessibility-features-with-apple-intelligence/))。Mac 這邊要更正一個常見誤解：**Pointer Control 的臉部表情不是 macOS 13 才有，Catalina 10.15 就有**。部分來源說是 10.15.4，這個分歧保留 ([thoughtbot](https://thoughtbot.com/blog/an-introduction-to-macos-head-pointer))。微笑、張嘴、吐舌、揚眉、眨眼、皺鼻、嘟嘴可映射到左鍵、右鍵、雙擊、三擊、拖放，需相機權限 ([How-To Geek](https://www.howtogeek.com/788217/how-to-use-your-head-and-face-to-control-your-mac/))；可開「播放聲音」與「以視覺方式顯示動作」做確認 ([AbilityNet](https://mcmw.abilitynet.org.uk/how-to-set-up-pointer-actions-in-macos))。缺點是精度不如手，長時間維持頭部角度不舒服 ([MacSales](https://eshop.macsales.com/blog/64948-control-mac-with-head-gestures/))。Apple 2025、2026 兩年的無障礙預告，macOS 項目都沒有新的手勢輸入。這不能證明 macOS 26／27 完全沒有，因為 WWDC 的 macOS 內容沒有逐項查過。

開發者能接到什麼，整理如下。規律很清楚：語義綁在 App 內容上的手勢（畫筆工具、拍照、捲動內容）才開放，而且 Apple 要求 App 尊重使用者的系統偏好；系統層語義一律不開。

| 功能 | 開放程度 | API／限制 |
| --- | --- | --- |
| Pencil 擠壓、雙擊 | 完整 | `UIPencilInteraction`、`pencilInteraction(_:didReceiveSqueeze:)`；應讀 `preferredSqueezeAction` 照使用者偏好行動 |
| Pencil barrel roll | 完整 | `UIPencilHoverPose.rollAngle` |
| Camera Control／Action Button | 完整 | `AVCaptureEventInteraction`（分 phase、primary／secondary）；`LockedCameraCapture`（iOS 18+） |
| visionOS Look to Scroll | 完整（visionOS 26） | `UIScrollView.lookToScrollAxes`；SwiftUI `.scrollInputBehavior(.enabled, for: .look)`；只建議用在內容區 |
| Watch Double Tap | 只能指定目標 | `handGestureShortcut(.primaryAction)`，每 scene 一個 |
| AirPods 頭部 | 只給原始資料 | `CMHeadphoneMotionManager` 姿態；點頭搖頭要自己做分類器，更新率不可設 |
| Back Tap、Wrist Flick、AirPods 點頭搖頭語義、Vision Pro 手掌手勢、Eye／Head Tracking、Mac 臉部表情 | 系統專用 | 未見 API |

表內依據：Pencil 擠壓見 ([Apple Developer：Handling squeezes](https://developer.apple.com/documentation/applepencil/handling-squeezes-from-apple-pencil.md))，barrel roll 見 ([UIPencilHoverPose](https://developer.apple.com/documentation/uikit/uipencilhoverpose.md))。Camera Control 見 ([Apple Developer：Camera Control](https://developer.apple.com/tutorials/data/documentation/avfoundation/enhancing-your-app-experience-with-the-camera-control.md))，Look to Scroll 見 ([lookToScrollAxes](https://developer.apple.com/documentation/uikit/uiscrollview/looktoscrollaxes.md))，Watch 見 ([HandGestureShortcut.primaryAction](https://developer.apple.com/documentation/swiftui/handgestureshortcut/primaryaction))，AirPods 見 ([awareframework](https://github.com/awareframework/com.awareframework.ios.sensor.airpods))。另外，HIG 的 Gestures 頁本輪抓取失敗。「不覆蓋系統手勢、自訂手勢要少、每個手勢都有替代路徑」這幾條，是業界對 HIG 的一般認知，**未逐字核對**。

## 設計取捨：誤觸靠閘門、可發現性靠負回饋、主流化靠砍掉自訂

把各產品攤開比，Apple 處理誤觸的主手段是上下文閘門，不是更嚴格的分類器。Double Tap 只在亮屏時有效；AirPods 只在 Siri 播報時有效；Vision Pro 要先看手掌；Wrist Flick 只在有通知、來電或計時器時有意義。上述行為都有來源，但「這是 Apple 的刻意原則」是本報告的歸納，Apple 沒有明文。第二個手段是讓主流手勢的語義**小而可逆**：接受、拒絕、關閉、叫選單，沒有一個是破壞性動作。反例是 Camera Control：它把「半按」先定義成出覆蓋層，後來又加 AE／AF 鎖定，兩種語義打架，被 Six Colors 批評 ([Six Colors 2025-01](https://sixcolors.com/post/2025/01/apple-wrote-checks-camera-control-cant-cash/))。可見重載語義的代價比誤觸還高。

可發現性方面，Apple 用了三招便宜的做法。一是觸發時系統自動高亮被選中的控制項。二是在不支援的畫面做 Double Tap 時，手勢圖示會出現並搖動 ([Apple Support 108413](https://support.apple.com/en-afri/108413))。這是負回饋：告訴使用者「收到了，只是這裡不適用」，避免他誤以為辨識失敗。三是設定裡的引導練習，例如 AirPods 頭部手勢 ([Croma](https://croma.com/unboxed/how-to-use-head-gestures-on-airpods))，以及 watchOS 26 Smart Stack 的「gentle visual prompt」([Apple Newsroom 2025-06](https://www.apple.com/newsroom/2025/06/watchos-26-delivers-more-personalized-ways-to-stay-active-and-connected/))。確認回饋則依硬體而定：Pencil 用觸覺，Camera Control 和 Vision Pro 用覆蓋層，Mac 指標動作用可選的聲音或視覺確認。

從無障礙走向主流，Watch 給的模型很具體。主流版犧牲可自訂性，換來零學習成本與可預測的語義；完整的重映射能力留在無障礙版本，兩者互斥。Back Tap 走了另一條路：功能完整、可映射到捷徑，但一直停在輔助使用、預設關閉，靠科技媒體「隱藏功能」的口碑擴散。這兩條路都說得通。前者適合「每個人每天都會用」的動作，後者適合「進階使用者自己挑」的快捷鍵。新手勢只開給新硬體（Watch Series 9+、新款 AirPods），很可能與模型算力或感測器品質有關，Apple 沒有明說。

## 對 WindowShade：最便宜的兩個觸發已經在手上，敲機身留到最後

Mac 上沒有官方的 Back Tap 或敲機身手勢，第三方也沒有任何系統手勢可以掛。所以每個觸發都要 WindowShade 自己接訊號、自己做閘門與回饋。下表按成本排序；權限與風險欄的依據放在表後。

| 觸發 | 權限 | 誤觸 | 成本／功耗 | 可發現性 | 衝突 | 硬體與版本 |
| --- | --- | --- | --- | --- | --- | --- |
| 卷簾條／刘海面板上深按（`NSEvent.stage == 2`） | 無 | 低 | 無額外 | 低，需引導 | 與系統「查詢」同手勢，但只在自家視窗 | 需 Force Touch 觸控板 |
| 自家視窗上捲動 | 無 | 低 | 無額外 | 中 | 無 | 全機型 |
| 游標推入刘海／頂邊中央 | 無（追游標） | 中，游標會經過選單列 | 低 | 中 | 選單列自動顯示、熱角 | 全機型；無刘海螢幕用頂邊 |
| 修飾鍵雙擊 | listen-only 走輸入監控，或輔助使用 | 中，需獨按與間隔檢查 | 低 | 高，Raycast／Alfred 已教育使用者 | 與 Raycast、Alfred 搶鍵 | 全機型 |
| 全域多指手勢（私有 `MultitouchSupport`） | 讀取權限未證實；執行動作要輔助使用；不可沙盒 | 中 | 低至中 | 中 | 系統三指／四指手勢 | 私有 API，每個大版本都要回歸 |
| 敲機身兩下（SPU 加速度計） | 外部專案說要 root；與 WindowShade 自家程式碼衝突，見下文 | 高：打字、放下筆電、桌面震動 | 常駐取樣，有實測 CPU 成本 | 低 | 無 | 只限 MacBook；機型表互相矛盾 |
| 麥克風敲桌 | 麥克風，指示燈常亮 | 高 | 中 | 低 | 隱私指示 | 全機型 |
| 相機臉部表情 | 相機，相機燈常亮 | 中 | 高 | 低 | 系統 Pointer Control | 有相機機型 |
| Touch ID 輕觸 | — | — | — | — | — | 找不到任何可偵測裸觸碰的方法，推定不可行 |

表的依據如下。深按 API 見 ([Apple: NSEvent.stage](https://developer.apple.com/documentation/appkit/nsevent/stage.md))；`primaryDeepClick` 進出第二段帶觸覺回饋見 ([Apple: primaryDeepClick](https://developer.apple.com/tutorials/data/documentation/appkit/nsevent/pressurebehavior-swift.enum/primarydeepclick.md))。修飾鍵雙擊：Raycast 1.42.0（2022-10-26）起支援 ([Raycast changelog](https://www.raycast.com/changelog/macos-v1/1-42-0))；Alfred 有「雙擊 Shift 接著打字仍誤觸」的回報 ([Alfred forum](https://www.alfredforum.com/topic/17107-possibility-to-change-double-tap-sensitivity/))。權限分流是 Apple DTS 在論壇的說法，不是官方文件：`listenOnly` tap 只要輸入監控，`defaultTap` 要輔助使用 ([Forums 828052](https://developer.apple.com/forums/thread/828052))。多指手勢：OpenMultitouchSupport 要求關沙盒 ([OpenMultitouchSupport](https://awesome.ecosyste.ms/projects/github.com%2Fkyome22%2Fopenmultitouchsupport))；mactic 指出 arm64e 指標驗證會讓直接呼叫出 bus error ([mactic](https://hn.jakechampion.name/reader/https://github.com/MatMercer/mactic))。風險不只是功能失效：BetterTouchTool 在 macOS 26.2 有「所有滑鼠鍵盤輸入卡死直到退出 BTT」的回報 ([folivora 論壇](https://community.folivora.ai/t/bettertouchtool-6-143-on-macos-tahoe-26-2-blocks-all-mouse-clicks-keyboard-input-until-btt-is-quit/46198))，最壞情況會拖垮整台機器的輸入。

敲機身是最像 Back Tap 的對應，證據衝突也最多。外部專案說加速度計在 `AppleSPUHIDDevice`、vendor page `0xFF00`、usage 3（陀螺儀為 usage 9），原生約 800 Hz，**讀取需要 root**，作者只在 M3 Pro、macOS 15.6.1 測過 ([olvvier](https://github.com/olvvier/apple-silicon-accelerometer))。spank 用 STA／LTA、CUSUM 等偵測振動，預設 0.05 g 閾值與 750 ms 冷卻，需 sudo 或 root 的 launchd 服務；它支援 M2 以後與 M1 Pro，其他 M1 不行 ([spank](https://github.com/taigrr/spank))。2026 年 3 月已有付費產品 Knock 用它觸發捷徑，但有人問「放下筆電或大力打字會不會誤觸」，頁面上無人回答 ([Knock](https://www.producthunt.com/products/knock-7))。機型支援各家說法互相矛盾，Apple 沒有官方資料。

WindowShade 自己的程式碼和「需要 root」這個說法並不一致。`prototype/Effects/AppleSPUAccelerometer.swift` 在 App 行程內直接用 `IOHIDManagerOpen` 開這個裝置，沒有 root helper；它的註解記錄了一次實測：報告間隔 1000 µs 時每秒 807 次回呼，約占常駐 CPU 3 個百分點；改成 16000 µs（每秒 62 次）後，60 秒平均 CPU 從 4.6–5.4% 降到 1.7–2.9%。依 `docs/performance.md` 第 468 行，這個類型目前沒有任何呼叫方。本輪沒有重跑，所以「macOS 27 上非 root 能不能讀」仍要真機確認。研究筆記在這台 M5 MacBook Air（macOS 27.0.1）上用 `ioreg` 確認了 usage 3 與 9 的裝置存在，但同樣沒有實際讀值。這組數字還帶出一個本報告的推論：62 Hz 對傾斜效果足夠，但敲擊是短脈衝，偵測可能需要更高取樣率。所以敲擊偵測的 CPU 成本可能接近 3 個百分點那一檔，不是 1.7% 那一檔，要量過才能定。

**補記（2026-11-01）：** 2026-10-30 開源的 [LidTap](https://github.com/harsha20599/lidtap) 的設計文件明確寫著讀加速度計與陀螺儀「需要 Input Monitoring 權限，不需要 root」，跟 WindowShade 在 App 內直接開裝置的做法一致，所以「需要 root」這個外部說法應該是過時或過度保守。它的 Python 原型實測約占一顆核心的 3–5%、延遲約 170 ms，Swift 版的目標是 3% 左右，跟上面 807 Hz 那一檔的實測相符。

建議的優先順序如下。它延續 Apple 的三個做法：上下文閘門、小而可逆的語義、明確回饋。

| 順位 | 觸發 | 做法 | 理由 |
| --- | --- | --- | --- |
| 1 | 游標推入刘海＋卷簾條深按 | 已有（深按「看一眼」在 `TrackpadGestures.swift` 第 1735 行起）。補上 Apple 式回饋：不適用時也給負回饋，不要沉默 | 零新權限、全機型（深按要 Force Touch）、語義綁在自家表面，和 Pencil 擠壓、Watch primaryAction 同一類 |
| 2 | 修飾鍵雙擊 | 預設不綁或讓使用者選鍵，偵測與 Raycast／Alfred 衝突；判定為「兩次按放在約 300 ms 內、中間沒有其他鍵、沒有搭配點擊」 | WindowShade 已有 `flagsChanged` 處理（`HabitKeys.swift`）與輔助使用權限，不增加新權限；可發現性最高 |
| 3 | 全域快捷鍵／App Intent 作相容層 | 確保每個手勢動作都有快捷鍵或 App Intent 可呼叫 | 對應 HIG 的「每個手勢有替代路徑」（未逐字核對）；無障礙使用者可經系統功能間接觸發，見下文的保留 |
| 4 | 全域多指手勢 | 只為一兩個高價值動作做，例如視窗瀏覽，並在每個 macOS 大版本做回歸 | 私有 API 可接受，但失敗模式會傷到整機輸入 |
| 5 | 敲機身兩下 | 實驗開關、預設關；閘門至少包括：開蓋且在使用、最近 N 毫秒沒有打字、雙敲時間窗、冷卻；先實測非 root 可讀性、取樣率與 CPU | 最像 Back Tap，但誤觸最高、桌機與闔蓋模式不可用、機型表不可靠 |
| 不做 | 麥克風、相機表情、Touch ID、Fn／🌐 雙擊 | — | 麥克風與相機會讓隱私指示燈常亮，與「低打擾」相反；臉部表情系統已有；Touch ID 推定不可行；🌐 鍵已用於輸入法與聽寫（雙擊 Fn 預設聽寫，本輪未查證） |

第三順位有一個未證實的前提：Pointer Control 的替代動作、Switch Control 或輔助使用鍵盤，能不能送出任意鍵盤快捷鍵或呼叫第三方 App Intent？本輪來源只列出滑鼠動作。這件事要在系統設定裡實際看過才能寫進產品文案。另外，依 `docs/product-reshape-spec.md` §0.2，目前的工作隊列只置換、不增長。以上第 2 到第 5 項是候選，不是自動加進隊列的新工作。

## 結論

這輪研究扭轉的一個判斷是：「Back Tap 等級」的觸發，難處不在偵測。Apple 自己都不公開偵測方式，Google 和 Amazon 各用 ML 做出來，2013 年的閾值法也做得到。難處在決定**什麼時候不偵測**。Apple 每個成功的低打擾手勢，都先砍掉大部分時間的可觸發性，例如只在亮屏、只在 Siri 問話時、只在看手掌時，再給一個小而可逆的語義。照這個標準，WindowShade 在刘海與卷簾條上的觸發天生就帶閘門：游標在那裡，就是使用者在「看」。這比機身敲擊這類全時段訊號更接近 Apple 的做法，也更接近 Apple 的品質。

第二個判斷是 Mac 上的空位。2025、2026 兩年 Apple 給 macOS 的無障礙預告都沒有新手勢；第三方又無處掛系統手勢。所以 WindowShade 若要在這條線上有差異，重點不在多做一種感測器，而在把 Watch 的那套可發現性做齊：觸發時的高亮、不適用時的負回饋、首次引導。再加上 Back Tap 式的「進階使用者自選映射」。敲機身值得做成實驗，主要價值是展示，不是主力輸入；它上線前要回答的三個問題（非 root 可讀性、敲擊所需取樣率的 CPU 成本、打字中的誤觸率）目前都沒有數據。
