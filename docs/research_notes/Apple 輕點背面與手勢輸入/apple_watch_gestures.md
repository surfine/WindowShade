# Apple Watch 免觸控手勢：AssistiveTouch、Double Tap、Wrist Flick、watchOS 27 單捏

（研究日期 2026-11-01；舊資訊已註明年份。共 17 次工具呼叫，Apple 一手來源優先。）

## 1. AssistiveTouch for Apple Watch（無障礙起點，2021）

### Takeaway
2021 年 5 月 Apple 以無障礙功能預告 AssistiveTouch：用陀螺儀、加速度計與光學心率感測器，加上裝置端機器學習，偵測「肌肉動作的細微差異」，讓上肢差異的使用者用捏合、握拳等手勢操作手錶並驅動螢幕上的動作指標。現行支援文件把手勢稱為 Tap／Double tap／Clench／Double clench，每個手勢都能重新指派動作或 Siri 捷徑。

### Cited Findings
- 2021-05 預告的原文：「Using built-in motion sensors like the gyroscope and accelerometer, along with the optical heart rate sensor and on-device machine learning, Apple Watch can detect subtle differences in muscle movement」；用途是讓使用者「navigate a cursor on the display through a series of hand gestures, like a pinch or a clench」。— [Apple Newsroom 2021-05](https://www.apple.com/newsroom/2021/05/apple-previews-powerful-software-updates-designed-for-people-with-disabilities/)
- 目標族群與能力：「allows users with upper body limb differences to enjoy the benefits of Apple Watch」，可接聽來電、控制 onscreen motion pointer、開通知中心和控制中心等。預告說「Later this year」隨軟體更新推出（也就是 2021 秋季的 watchOS 8）。— [Apple Newsroom 2021-05](https://www.apple.com/newsroom/2021/05/apple-previews-powerful-software-updates-designed-for-people-with-disabilities/)
- 現行預設手勢：Tap = Forward（下一項）、Double tap = Back（上一項）、Clench = Tap（點選）、Double clench = 顯示 Action Menu。— [Apple Support: Use AssistiveTouch on Apple Watch](https://support.apple.com/guide/watch/use-assistivetouch-apdec70bfd2d/watchos)
- Motion Pointer：「control your Apple Watch by tilting the watch up and down and side to side」，可從 Action Menu 的 Interaction 開啟，可調靈敏度、啟動時間、移動容差和熱區邊緣（hot edges）。— [Apple Support](https://support.apple.com/guide/watch/use-assistivetouch-apdec70bfd2d/watchos)
- 可設定的項目：每個手勢可指派任意動作或 Siri 捷徑；掃描方式可選 Automatic 或 Manual；可設高對比與高亮顏色；Action Menu 可加常用動作、改位置與大小、設自動捲動速度；可用 AssistiveTouch 確認付款和側鍵雙擊。啟用路徑是 Settings > Accessibility > AssistiveTouch > Hand Gestures。— [Apple Support](https://support.apple.com/guide/watch/use-assistivetouch-apdec70bfd2d/watchos)
- Quick Actions（AssistiveTouch 的衍生功能）：在提醒出現時用手勢回應，也可貪睡鬧鐘、停止計時器、開始偵測到的體能訓練、在相機 App 拍照；可設 Always、Only when AssistiveTouch is on 或 Off；外觀分 Full 與 Minimal。— [Apple Support](https://support.apple.com/guide/watch/use-assistivetouch-apdec70bfd2d/watchos)
- 相關專利（不代表已出貨）：Apple 2021 年公開的專利申請描述，手錶背面的光源與光學感測器偵測手勢造成的反射光變化，來源可能是肌肉收縮、裝置位移、皮膚拉伸或與皮膚距離改變；發明人曾參與 Apple Watch 心率演算法。— [AppleInsider 2021-05-27](https://appleinsider.com/articles/21/05/27/apple-research-defines-how-new-apple-watch-accessibility-features-could-work)、[MacTech 2021-05-27](https://www.mactech.com/2021/05/27/apple-patent-filing-involves-apple-watches-with-optical-sensors-for-gesture-control)
- 另一份以 PPG 訊號偵測手指、手腕動作的專利文件 US20200150772A1（「Sensing Hand Gestures Using Optical Sensors」）；搜尋結果未顯示受讓人，無法確認是否屬 Apple。— [PatSnap](https://eureka.patsnap.com/patent-US20200150772A1)

### Inferences
- 2021 年新聞稿用「pinch／clench」，現行支援文件改稱「Tap／Double tap／Clench」，很可能是為了與 2023 年 Double Tap 的用詞一致（推測，未見 Apple 說明）。
- AssistiveTouch 已經用同一組感測器（IMU + 光學心率）加 ML。Double Tap 是把這條技術路線縮成「一個手勢、一個動作」，並交給更快的神經網路引擎常駐偵測。

### Gaps
- AssistiveTouch 最初的支援機型（記憶中為 Series 6／SE 起，後來擴大），以及 Quick Actions 首見於哪個 watchOS 版本（記憶中為 watchOS 9），這兩點本輪未找到一手來源，未證實。
- machinelearning.apple.com 上未找到專門談手錶手勢偵測的文章（本輪未直接查到，無法斷言沒有）。

## 2. Double Tap（雙指互點，2023，主流化）

### Takeaway
Double Tap 於 2023-09 隨 Series 9／Ultra 2 發表，2023-10-25 隨 watchOS 10.1 正式推出，預設開啟。S9 SiP 的 4 核神經網路引擎用「新的機器學習演算法」處理加速度計、陀螺儀與光學心率資料，辨識手腕微動與血流變化的特徵。它觸發畫面的「主要動作」，Smart Stack 與播放時的行為可以在 iPhone 上改。從 watchOS 11 起，第三方 App 可用 SwiftUI `.handGestureShortcut(.primaryAction)` 指定主要動作。

### Cited Findings
- 推出與預設：「The new double tap gesture comes to Apple Watch Series 9 and Apple Watch Ultra 2 starting today with the release of watchOS 10.1」（2023-10-25）；「enabled by default … It can be disabled in settings」。watchOS 10.1 支援 Series 4 以上，但手勢只限新機型。— [Apple Newsroom 2023-10](https://www.apple.com/newsroom/2023/10/apple-watch-double-tap-gesture-now-available-with-watchos-10-1/)
- 機制：偵測「the unique signature of tiny wrist movements and changes in blood flow」；由神經網路引擎以新的 ML 演算法處理加速度計、陀螺儀、光學心率感測器的資料。— [Apple Newsroom 2023-10](https://www.apple.com/newsroom/2023/10/apple-watch-double-tap-gesture-now-available-with-watchos-10-1/)；二手轉述 2023-09 發表會同樣說法 — [MacTech 2023-09-12](https://www.mactech.com/2023/09/12/the-apple-watch-series-9-has-a-new-s9-sip-chip-a-double-tap-gesture-more)
- 晶片：S9「25 percent more power efficient than the previous generation」，4 核神經網路引擎的 ML 任務速度最高為前代兩倍。— [Apple Newsroom 2023-10](https://www.apple.com/newsroom/2023/10/apple-watch-double-tap-gesture-now-available-with-watchos-10-1/)、[Hackster.io](https://hackster.io/news/apple-watch-series-9-launches-with-quad-core-neural-engine-for-on-wrist-machine-learning-c977175582fc)
- 預設行為：在多數 App 與通知裡選主要動作，例如停止計時器、播放／暫停、貪睡鬧鐘、接聽或掛斷電話、相機遙控、從錶面打開 Smart Stack 並捲動。— [Apple Newsroom 2023-10](https://www.apple.com/newsroom/2023/10/apple-watch-double-tap-gesture-now-available-with-watchos-10-1/)、[Cult of Mac](https://www.cultofmac.com/790236/apple-watch-series-9-launch/)
- 可自訂的範圍很窄：在 iPhone 設定裡，Smart Stack 可選「advancing through widgets … or selecting the first available widget」，播放時可選「playing or pausing media … or skipping to the next track」。— [Apple Newsroom 2023-10](https://www.apple.com/newsroom/2023/10/apple-watch-double-tap-gesture-now-available-with-watchos-10-1/)
- 現行支援機型：Series 9 以上、Ultra 2 以上、SE 3。設定路徑為 Settings > Gestures > Tap Gestures。— [Apple Support 108413](https://support.apple.com/en-afri/108413)
- SE 3（2025-09-09）因採用 S10 晶片，成為第一款支援 Double Tap 與 Wrist Flick 的 SE。— [Placera（Apple 新聞稿轉載）](https://www.placera.se/pressmeddelanden/apple-apple-introduces-apple-watch-se-3-20250909)、[Engadget](https://www.engadget.com/wearables/apple-watch-se-3-has-an-s10-chip-and-always-on-display-173033538.html)
- 不能用的情況（Apple 官方列表，等於它的省電與防誤觸邊界）：螢幕沒亮（要先抬腕）、Wrist Detection 關閉、Low Power Mode／睡眠專注／劇院模式／Water Lock 開啟、手錶上鎖或配戴不貼合、戴錯手腕、AssistiveTouch／Quick Actions／手勢縮放／手勢 VoiceOver 開啟（互斥）、Apple Watch For Your Kids 設定、Depth App 或 ECG 使用中、動作干擾（建議坐著或站穩）、手腕刺青可能干擾。不支援的畫面或 App 會讓 double tap 圖示出現並搖動。— [Apple Support 108413](https://support.apple.com/en-afri/108413)
- 開發者 API（已以官方文件核實）：「In watchOS 11 and later, you can assign a buttonlike control, such as a Button or Toggle as the scene's primary action」。修飾子為 `handGestureShortcut(_:isEnabled:)`，參數 `HandGestureShortcut.primaryAction`。可加在 Button、Toggle、NavigationLink、TextField，以及 Smart Stack 的 widget 和 Live Activity（含從 iOS 來的遠端 Live Activity）。每個 scene 只能有一個 primary action。優先順序：1. Primary action，2. Scroll view，3. Vertical tab pagination。控制項不在畫面上時，系統會一次捲一頁靠近它。系統會自動高亮被觸發的控制項，形狀可用 `clipShape(_:style:)` 調整。List、ScrollView、垂直分頁 TabView 自動獲得預設捲動行為。— [Apple Developer: Enabling the double-tap gesture on Apple Watch](https://developer.apple.com/documentation/watchos-apps/enabling-double-tap)、[HandGestureShortcut.primaryAction](https://developer.apple.com/documentation/swiftui/handgestureshortcut/primaryaction)
- 第三方能否接到更多手勢：開發者論壇有人問 watchOS 11 能否處理四種手勢，未見官方回答；官方 API 只公開 primaryAction。— [Apple Developer Forums 765831](https://developer.apple.com/forums/thread/765831)

### Inferences
- 「只在螢幕亮起時偵測」加「需配戴貼合與 Wrist Detection」是 Apple 控制功耗和誤觸的主要手段：偵測器不是全天常駐，而是在抬腕喚醒的短窗口內跑，並依賴光學感測器與皮膚貼合（推測，Apple 未公開偵測窗口細節）。
- 與 AssistiveTouch 互斥，說明兩者大概共用同一條感測與模型管線；Double Tap 是同一技術的主流化包裝（推測）。
- 開發者 API 刻意只給「指定哪個控制項是主要動作」，不給原始手勢事件，讓系統保留語義、優先順序與高亮回饋的一致性。

### Gaps
- Apple 未公開模型架構、取樣率、誤觸率或準確率數字；本輪未找到獨立的誤觸率或電池量測。
- 「battery impact is minimal」只見於二手報導轉述 Apple 說法（[Stuff.tv](https://www.stuff.tv/?p=912394)），未找到 Apple 一手原文。

## 3. Wrist Flick（甩腕，watchOS 26，2025）

### Takeaway
Wrist Flick 確實存在，2025-06 WWDC 隨 watchOS 26 發表，2025 秋季推出。動作是把手腕翻過去再翻回來。它可關閉通知與來電、讓計時器與鬧鐘靜音、回到錶面。偵測只用加速度計與陀螺儀，加上機器學習模型；與 Double Tap 不同，Apple 沒提光學心率感測器。支援機型與 Double Tap 相同。

### Cited Findings
- Apple 原文：「It uses the accelerometer and the gyroscope — along with a machine learning model — to analyze a user's wrist movement」；「Wrist flick joins the double tap gesture to allow users to do even more on Apple Watch with only one hand」，情境如牽狗或拿咖啡。發表時機型為 Series 9、Series 10、Ultra 2。— [Apple Newsroom 2025-06 watchOS 26](https://www.apple.com/newsroom/2025/06/watchos-26-delivers-more-personalized-ways-to-stay-active-and-connected/)
- 動作：關閉通知和來電、讓計時器與鬧鐘靜音、回到錶面。設定路徑為 Settings ➝ Gestures ➝ Wrist Flick。— [MacRumors 2025-07-17](https://www.macrumors.com/2025/07/17/new-apple-watch-gesture-watchos-26-newer-models/)、[9to5Mac 2025-06-11](https://9to5mac.com/2025/06/11/watchos-26-adds-new-wrist-flick-gesture-for-these-apple-watch-models/)
- 舊機型有相同感測器卻不支援，Apple 未解釋；MacRumors 認為原因是新的 ML 模型需要新晶片，這是推測。— [MacRumors 2025-07-17](https://www.macrumors.com/2025/07/17/new-apple-watch-gesture-watchos-26-newer-models/)
- 2025-09 之後機型擴充到 Series 11、Ultra 3、SE 3。— [Tom's Guide](https://www.tomsguide.com/wellness/smartwatches/dismissing-apple-watch-notifications-just-got-a-whole-lot-easier-how-to-use-the-wrist-flick-gesture-in-watchos-26)；SE 3 的使用情境（抬腕看了通知但還不想回應）— [Placera（Apple 新聞稿轉載）](https://www.placera.se/pressmeddelanden/apple-apple-introduces-apple-watch-se-3-20250909)
- 2026 年使用心得補充：也可用來關閉 App。— [9to5Mac 2026-02-04](https://9to5mac.com/2026/02/04/watchos-26-added-a-new-apple-watch-trick-that-ive-been-loving/)
- 同一份 watchOS 26 新聞稿也提到 Smart Stack hints「will appear on the display as a gentle visual prompt」，屬於可發現性設計。— [Apple Newsroom 2025-06](https://www.apple.com/newsroom/2025/06/watchos-26-delivers-more-personalized-ways-to-stay-active-and-connected/)

### Inferences
- Wrist Flick 的語義是「拒絕／收起」，Double Tap 是「確認／主要動作」，兩者形成一對肯定與否定的單手手勢。
- 不用光學感測器，可能因為翻腕是大動作，IMU 已足夠；這也可能讓它的功耗低於 Double Tap（推測，無官方資料）。

### Gaps
- 未找到 Wrist Flick 的誤觸率、功耗或「何時偵測」的官方說明；照理也只在螢幕亮起、有提醒時有效，但本輪未查到 Apple 一手說法（未證實）。
- 「關閉 App」是否為官方功能，只有 9to5Mac 心得文提到。

## 4. 2026 年更新：watchOS 27 的單捏（single pinch/tap）

### Takeaway
2026-06-08 WWDC 發表的 watchOS 27 加入第三個手勢：拇指與食指互點一次（single tap／pinch），用來在 Smart Stack 選取目前高亮的 widget。雙擊仍負責打開與前進 Smart Stack。資訊全部來自二手報導，Apple Newsroom 原文本輪未取到；機型清單各家說法不一。

### Cited Findings
- 單捏用於選 Smart Stack widget；雙捏仍打開 Smart Stack，單捏跳進高亮的 App。— [allthings.how](https://allthings.how/whats-new-in-watchos-27-dynamic-app-grid-siri-ai-and-one-tap-gestures/)、[TWiT](https://twit.tv/posts/tech/how-master-new-apple-watch-controls-watchos-27)、[Wccftech](https://wccftech.com/apples-watchos-27-lets-siri-ai-brainstorm-workouts-and-read-your-mail-mid-call-while-a-new-pinch-gesture-makes-widget-selection-a-breeze/)
- 首個開發者 beta 為 2026-06-08，預期 9 月正式推出。— [fone.tips](https://fone.tips/watchos-27-features/)
- 機型爭議：有來源說 watchOS 27 不再支援 Series 9、初代 Ultra、SE 2；另有來源把 Series 9 列為相容。— [BGR](https://bgr.com/2191261/watchos-27-adds-new-features-skips-old-models/)、[Gizchina](https://www.gizchina.com/apple/watchos-27-announced-with-dynamic-app-grid-new-gesture-controls-and-smarter-features)
- 使用者回饋：有人希望能分辨捏的是哪根手指；有人抱怨進 App Grid 現在要兩個動作。— [MacRumors Forums](https://forums.macrumors.com/threads/watchos-27-features-dynamic-app-grid-new-gesture-control-and-more.2483577/)

### Inferences
- 時序上手勢詞彙在逐年擴張：2023 雙擊（確認）→ 2025 甩腕（拒絕）→ 2026 單擊（選取）。這正是 AssistiveTouch 2021 年那組完整詞彙（單／雙 tap、clench）逐步被主流化的過程。

### Gaps
- 單捏的官方名稱、支援機型、是否開放給開發者 API（例如 `HandGestureShortcut` 是否新增成員），本輪都未以 Apple 一手文件核實。watchOS 27 是否已於 2026-09 正式發布也未核實。

## 5. 功耗、誤觸與使用者評價

### Takeaway
沒有獨立量測。Apple 的省電策略可從官方「不能用」清單看出來：只在螢幕亮起時偵測、低耗電模式下停用、要求配戴貼合。評測普遍正面，但也記錄了反覆抬腕的疲勞與實用性有限的批評。

### Cited Findings
- Double Tap 只在螢幕喚醒時工作，Low Power Mode 下停用。— [Apple Support 108413](https://support.apple.com/en-afri/108413)
- 轉述 Apple 稱電池影響「minimal」。— [Stuff.tv](https://www.stuff.tv/?p=912394)
- Engadget 評測者抱怨測試時反覆抬腕很累。— [Engadget Series 9 review](https://www.engadget.com/apple-watch-series-9-review-freedom-from-touching-your-screen-130009764.html)
- BGR 認為實用性遠不如預期。— [BGR](https://bgr.com/tech/apple-watch-double-tap-feature-is-nowhere-near-as-useful-as-i-hoped)；Trusted Reviews 則稱之為多年來最好的新功能。— [Trusted Reviews](https://www.trustedreviews.com/news/watchos-10-1-unlocks-the-best-new-apple-watch-feature-in-years-4384549)
- Which? 認為電池與準確度比這個手勢更影響日常體驗。— [Which?](https://www.which.co.uk/news/article/what-is-the-apple-watch-double-tap-feature-and-is-it-worth-it-a4HMy8D5Kd6q)
- Apple 官方承認動作會干擾辨識，建議坐好或站穩；刺青也可能干擾（光學訊號問題）。— [Apple Support 108413](https://support.apple.com/en-afri/108413)

### Inferences
- 用「螢幕亮起」做閘門有兩個作用：省電，同時讓大部分日常手部動作不會被誤判，因為使用者沒在看手錶時，手勢根本不生效。

### Gaps
- 誤觸率、偵測延遲、每日功耗佔比沒有可信數字；相關網路指南（如 digitechbytes）品質低，未採用。

## 6. 從無障礙到主流的軌跡與可發現性

### Takeaway
同一套「IMU + 光學 + 裝置端 ML」技術，先在 2021 年以無障礙功能出貨（完整詞彙、可全面重映射、帶動作指標），2023 年縮成一個預設開啟、語義固定的「主要動作」手勢，成為硬體賣點，之後逐年加詞。可發現性靠系統在畫面上給回饋：觸發時高亮控制項，不支援時讓圖示搖動，Smart Stack 也有視覺提示。

### Cited Findings
- 2021 為上肢差異族群設計。— [Apple Newsroom 2021-05](https://www.apple.com/newsroom/2021/05/apple-previews-powerful-software-updates-designed-for-people-with-disabilities/)
- 2023 預設開啟、免設定，並作為 Series 9 主打功能。— [Apple Newsroom 2023-10](https://www.apple.com/newsroom/2023/10/apple-watch-double-tap-gesture-now-available-with-watchos-10-1/)
- 系統自動高亮被觸發的控制項。— [Apple Developer](https://developer.apple.com/documentation/watchos-apps/enabling-double-tap)；不支援時 double tap 圖示出現並搖動 — [Apple Support 108413](https://support.apple.com/en-afri/108413)
- watchOS 26 的 Smart Stack hints 以「gentle visual prompt」提示。— [Apple Newsroom 2025-06](https://www.apple.com/newsroom/2025/06/watchos-26-delivers-more-personalized-ways-to-stay-active-and-connected/)
- 兩者互斥：開了 AssistiveTouch／Quick Actions 就不能開 Tap Gestures。— [Apple Support 108413](https://support.apple.com/en-afri/108413)

### Inferences
- 設計取捨：主流版本犧牲「可自訂」（只在 Smart Stack 與播放兩處有選項），換來「零學習成本、語義可預測」。完整可重映射的能力留給無障礙版本。
- 「被拒絕時圖示搖動」是負回饋，讓使用者知道手勢有被收到、只是這裡不適用，可避免使用者懷疑是辨識失敗。這是低成本、可參考的可發現性做法。

### Gaps
- Apple 未公開說明「從 AssistiveTouch 演化」的內部關係；兩者共用模型的說法屬推測。
</content>
</invoke>
