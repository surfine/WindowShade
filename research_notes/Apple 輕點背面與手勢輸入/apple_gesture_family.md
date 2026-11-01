# Apple 其他「低打擾／免觸控」輸入手勢家族（與 Back Tap、Apple Watch Double Tap 的橫向比較）

> 調查日期：2026-11-01。現況以 2026 年 11 月為準，舊資訊註明年份。標「未證實」者為找不到一手來源或只有二手報導。
> 方法限制：support.apple.com 與 HIG 部分頁面以 WebFetch 抓取時只拿到標題或摘要（HIG Gestures 頁抓取失敗），凡此類段落已在 Gaps 註明。

## 問題一：各功能的推出時間、觸發方式、感測器與機制、可配置性

### Takeaway
這個家族可以分成三類：(a) 穿戴／配件上的 IMU 或壓力感測手勢（AirPods 點頭搖頭、Watch Wrist Flick、Pencil 擠壓／滾動），(b) 相機視覺追蹤（Vision Pro 眼＋捏、iPhone/iPad Eye Tracking 與 Head Tracking、Mac head pointer 與臉部表情），(c) 實體按鍵的多段語意（Action Button、Camera Control 輕壓）。幾乎每一項都可在設定裡開關或改映射，很多是從無障礙功能先出、再有主流版本。

### Cited Findings

**Apple Vision Pro（visionOS 1，2024；visionOS 2，2024-09；visionOS 26，2025）**
- 基本互動：看著目標，拇指和食指碰一下即「點按」；另有捏住拖曳、捏住甩動快速捲動、捏住不放叫出更多選項、虛擬鍵盤可直接用手指點 — [Apple Support 117741](https://support.apple.com/en-asia/117741)
- visionOS 2 系統手勢：看手掌出現按鈕後點按回主畫面；看手掌再翻手出現狀態列，再點開控制中心；看著狀態列捏住左右移動可調音量；看手掌捏住不放叫 Siri — [Apple Support 117741](https://support.apple.com/en-asia/117741)；[AppleInsider（2024-09-16）](https://appleinsider.com/articles/24/09/16/apple-releases-visionos-2-with-new-gestures-and-persona-changes)
- visionOS 2 之前是「抬頭看、點出現的控制中心按鈕」；visionOS 2 起此舊法改成無障礙選項「Look Upwards for Control Center」（設定 > 輔助使用 > 互動）— [Apple Support 117741](https://support.apple.com/en-asia/117741)
- 開發者回報 visionOS 2 的系統手掌手勢與自家 App 的手掌 UI 衝突 — [Apple Developer Forums 757044](https://developer.apple.com/forums/thread/757044)
- visionOS 26：Look to Scroll（看內容捲動），Apple 自家 App 先用並開放 API — [Apple Developer Forums 793858](https://developer.apple.com/forums/thread/793858)；[heise（visionOS 26）](https://heise.de/-10438242)
- 2026-05-19 無障礙預告（將隨 visionOS 27 在 2026 下半年推出）：Vision Pro 將支援「face gestures」執行點按與系統動作；Dwell Control 新增用眼選取元素的方式；用 Vision Pro 眼動追蹤控制電動輪椅（Tolt、LUCI，美國） — [MacRumors 2026-05-19](https://macrumors.com/2026/05/19/new-accessibility-features-with-apple-intelligence/)；[AppleInsider 2026-05-19](https://appleinsider.com/articles/26/05/19/apple-intelligence-powered-accessibility-features-in-os-27-detailed-ahead-of-wwdc)
- 2024 年無障礙稿：Vision Pro 可用「眼、手、語音的任意組合」控制，並有 Switch Control、Sound Actions、Dwell Control — [Apple Newsroom 2024-05-15](https://www.apple.com/newsroom/2024/05/apple-announces-new-accessibility-features-including-eye-tracking/)

**AirPods 頭部手勢（iOS 18，2024-09；WWDC24 2024-06-10 宣布）**
- 點頭（上下）＝接聽來電／回覆通知與訊息；搖頭（左右）＝拒接來電／略過通知與訊息 — [Apple AirPods 使用手冊：控制與手勢](https://support.apple.com/guide/airpods/devb2c431317)；[MacRumors 2024-06-10](https://www.macrumors.com/2024/06/10/head-gestures-airpods-pro-later-this-year/)
- 前提：要開「以 Siri 播報來電」與「播報通知」；在 iPhone／iPad 的 AirPods 設定裡開頭部手勢 — [Apple Support 102536](https://support.apple.com/102536)
- 支援機型（Apple 現行頁面）：AirPods Max 2、AirPods Pro 2、AirPods Pro 3、AirPods 4（兩款）、Powerbeats Pro 2；手冊另列 AirPods 5（此項只見於搜尋摘要，未證實）— [Apple Support 102536](https://support.apple.com/102536)。2024 年時的報導只列 AirPods Pro 2（AirPods 4 尚未發表）— [MacRumors iOS 18 AirPods 指南](https://macrumors.com/guide/ios-18-airpods-pro)
- 可配置：可關閉，且可對調（搖頭＝是、點頭＝否）；iOS 18 設定內有引導式練習 — [Croma 教學](https://croma.com/unboxed/how-to-use-head-gestures-on-airpods)（二手）
- macOS Sequoia 起在 Mac 上也能用頭部手勢回應 Siri 問題 — [Apple Support 102536](https://support.apple.com/102536)
- 感測器：AirPods 內建 IMU；開發者在 CoreMotion 的 `CMHeadphoneMotionManager` 拿得到頭部姿態資料 — [MacPaw Research](https://research.macpaw.com/publications/headphones-accessibility.md)；[awareframework AirPods sensor](https://github.com/awareframework/com.awareframework.ios.sensor.airpods)

**Apple Pencil（Pencil 2 雙擊，2018；Pencil Pro，2024-05「Let Loose」）**
- Pencil Pro：筆身感測器偵測擠壓，預設叫出工具調色盤（換工具、線寬、顏色）— [MacTrast 2024-05](https://www.mactrast.com/2024/05/apple-unveils-new-apple-pencil-pro-featuring-new-squeeze-gesture-haptic-feedback-find-my/amp/)；[MacRumors 2024-05-09](https://macrumors.com/2024/05/09/apple-pencil-pro-features)
- Barrel roll：筆內陀螺儀偵測旋轉，改變形狀筆刷／筆尖的方向 — [GSMArena](https://m.gsmarena.com/apple_pencil_pro_brings_squeeze_and_roll_gestures_haptic_feedback-news-62758.php)
- 觸覺回饋：自製觸覺引擎在擠壓、雙擊、吸附到智慧形狀時輕敲確認 — [MacTrast 2024-05](https://www.mactrast.com/2024/05/apple-unveils-new-apple-pencil-pro-featuring-new-squeeze-gesture-haptic-feedback-find-my/amp/)
- 擠壓只有 Pencil Pro 支援 — [Apple Developer：Handling squeezes from Apple Pencil](https://developer.apple.com/documentation/applepencil/handling-squeezes-from-apple-pencil.md)

**iPhone／iPad**
- Eye Tracking（2024-05-15 預告，iOS/iPadOS 18）：前鏡頭幾秒內完成設定與校準，不需額外硬體；以 Dwell Control 停留啟動元素，實體按鈕、滑動、手勢都可只用眼睛完成；設定與控制資料都留在裝置上 — [Apple Newsroom 2024-05-15](https://www.apple.com/newsroom/2024/05/apple-announces-new-accessibility-features-including-eye-tracking/)
- Vocal Shortcuts（同稿）：使用者錄製 Siri 能辨識的自訂語句（設定時重複錄數次）來啟動捷徑；新聞稿也提到用「自訂聲音」執行任務 — [Apple Newsroom 2024-05-15](https://www.apple.com/newsroom/2024/05/apple-announces-new-accessibility-features-including-eye-tracking/)
- 同稿：Switch Control 可用 iPhone/iPad 相機把「手指點擊手勢」辨識成開關；AssistiveTouch 新增虛擬觸控板 — [Apple Newsroom 2024-05-15](https://www.apple.com/newsroom/2024/05/apple-announces-new-accessibility-features-including-eye-tracking/)
- Head Tracking（2025-05-13 預告，iOS/iPadOS 26）：用頭部動作控制 iPhone／iPad，類似 Eye Tracking；Eye Tracking 新增「用開關或停留」選取；鍵盤停留計時器、QuickPath；Switch Control 新增腦機介面（BCI）協定（iOS、iPadOS、visionOS）— [Apple Newsroom 2025-05-13](https://www.apple.com/newsroom/2025/05/apple-unveils-powerful-accessibility-features-coming-later-this-year/)；BCI 與 Synchron 合作、早期使用者覺得明顯較慢 — [TechCrunch 2025-05-13](https://techcrunch.com/2025/05/13/apple-announces-new-accessibility-features-including-support-for-brain-implants)
- 2026-05-19 預告（iOS 27）：Action Button 可直接叫出 VoiceOver Image Explorer 與放大鏡；Voice Control 支援自然語言描述畫面元素（「點紫色資料夾」）— [MacRumors 2026-05-19](https://macrumors.com/2026/05/19/new-accessibility-features-with-apple-intelligence/)
- Camera Control（iPhone 16，2024-09）：輕壓一下出現覆蓋層，可調整縮放、曝光等單一控制；第三方相機 App 要採用 AVKit 的 `AVCaptureEventInteraction` 接收按鍵事件、採用 `LockedCameraCapture` 才能從按鍵／鎖定畫面啟動 — [Apple Developer：Enhancing your app experience with the Camera Control](https://developer.apple.com/tutorials/data/documentation/avfoundation/enhancing-your-app-experience-with-the-camera-control.md)
- Camera Control 的「半按」最初不鎖對焦／曝光，與傳統相機習慣不符，之後加的 AE/AF 鎖定與原有半按語意打架（2025-01 評論）— [Six Colors 2025-01](https://sixcolors.com/post/2025/01/apple-wrote-checks-camera-control-cant-cash/)

**Apple Watch：Wrist Flick（watchOS 26，2025-06 WWDC 宣布）**
- 動作：手腕翻過去再翻回來；可略過通知、拒接來電、靜音計時器／鬧鐘、回到錶面 — [MacRumors 2025-06-10](https://www.macrumors.com/2025/06/10/watchos-26-gesture-dismiss-notifications/)；[iPhoneLife](https://iphonelife.com/content/apple-watch-wrist-flick-gesture)
- 限 Series 9／10／Ultra 2 及以後；設定 > 手勢 > Wrist Flick 開關 — [MacRumors 2025-07-17](https://www.macrumors.com/2025/07/17/new-apple-watch-gesture-watchos-26-newer-models/)；[9to5Mac 2025-06-11](https://9to5mac.com/2025/06/11/watchos-26-adds-new-wrist-flick-gesture-for-these-apple-watch-models/)
- 感測器：加速度計＋陀螺儀＋機器學習模型（9to5Mac 說法，未找到 Apple 一手來源）— [9to5Mac 2025-11-20](https://9to5mac.com/2025/11/20/watchos-26-added-a-new-apple-watch-trick-that-ive-been-loving/)

**Mac**
- Pointer Control（macOS Catalina 10.15，2019；部分來源指 10.15.4）：「Enable alternate pointer actions」與「Enable head pointer」兩項，都需相機權限；用頭部移動游標 — [How-To Geek](https://www.howtogeek.com/788217/how-to-use-your-head-and-face-to-control-your-mac/)；[MacMost](https://macmost.com/controlling-your-mac-with-head-movements.html)；版本分歧見 [thoughtbot](https://thoughtbot.com/blog/an-introduction-to-macos-head-pointer)
- 臉部表情作為指標動作：微笑、張嘴、吐舌、揚眉、眨眼、皺鼻、嘟嘴（外、左、右），可映射到左鍵、右鍵、雙擊、三擊、拖放 — [How-To Geek](https://www.howtogeek.com/788217/how-to-use-your-head-and-face-to-control-your-mac/)；[MacSales](https://eshop.macsales.com/blog/64948-control-mac-with-head-gestures/)。所以「macOS 13 才有臉部表情」不成立，Catalina 就有。
- 回饋：可開「Play Sounds」（動作時播放聲音）與「Show Actions Visually」（視覺確認）— [AbilityNet：pointer actions in macOS](https://mcmw.abilitynet.org.uk/how-to-set-up-pointer-actions-in-macos)
- head pointer 精度不如手，長時間把頭維持某角度會不舒服 — [MacSales](https://eshop.macsales.com/blog/64948-control-mac-with-head-gestures/)
- Apple Mac 使用手冊（版本選單已到 macOS 27）仍列「Use head pointer」為行動能力主題 — [Apple Mac 使用手冊](https://support.apple.com/guide/mac-help/use-pointer-control-mchl0b9e6b3a/mac)
- 2025-05 稿的 macOS 項目為 Magnifier for Mac、Braille Access、Accessibility Reader、Vehicle Motion Cues，沒有新的手勢輸入 — [Apple Newsroom 2025-05-13](https://www.apple.com/newsroom/2025/05/apple-unveils-powerful-accessibility-features-coming-later-this-year/)
- 2026-05 稿的 macOS 項目：Generated Subtitles、助聽器配對、Sony Access controller（iOS/iPadOS/macOS，可自訂按鍵與搖桿、可合併兩支）— [MacRumors 2026-05-19](https://macrumors.com/2026/05/19/new-accessibility-features-with-apple-intelligence/)

### Inferences
- Mac 上沒有官方的 Back Tap 或「敲機身」類手勢；最接近的是 Pointer Control 的臉部表情與 head pointer（相機）、Mac 上的 AirPods 頭部手勢（只限回應 Siri）、以及 macOS 早有的 Switch Control／Dwell。Mac 端 2025、2026 兩年的無障礙預告都沒有新手勢輸入，這是 WindowShade 可以填的空位（推論，依兩份預告稿的 macOS 清單）。
- 家族的共同機制是「既有感測器＋裝置端 ML 分類」：AirPods 的 IMU、Watch 的 IMU（Wrist Flick、Double Tap）、Pencil 的壓力感測與陀螺儀、Vision Pro／iPhone／Mac 的相機。幾乎沒有一項是為手勢新增專用硬體（Pencil Pro 擠壓感測器是例外）。

### Gaps
- Apple Pencil 2 雙擊的推出時間（一般認知為 2018-10，搭 iPad Pro 2018）與 `UIPencilInteraction` 初版（一般認知為 iOS 12.1）這次沒有抓到一手來源，未證實。
- Apple Watch Double Tap（watchOS 10.1，2023）本身的感測器描述（加速度計、陀螺儀、光學心率感測器＋Neural Engine）不在本次範圍，未重新核對。
- Back Tap（iOS 14，2020，輔助使用 > 觸控）未在本次重新核對。
- visionOS 26／27 是否有「手掌翻轉」以外的新系統手勢（如 2026 預告的 face gestures 具體是哪些表情）只見預告，細節未證實。
- Action Button（iPhone 15 Pro，2023）本身的設定細節未重新核對；Camera Control 目前（iOS 26）的半按行為是否已調整，未證實。
- macOS 26／27 是否新增任何手勢類輸入：兩份預告稿皆未提，WWDC25/26 的 macOS 發表內容本次未逐項查，不能斷言「沒有」。

## 問題二：確認／回饋設計、誤觸處理、「始終偵測」的功耗

### Takeaway
Apple 的模式是「能確認就確認、預設保守」：Pencil Pro 用觸覺敲擊確認，Mac 指標動作可選聲音或視覺確認，Camera Control 輕壓先出覆蓋層再改值，AirPods 頭部手勢只在 Siri 已經開口問的時候才聽（有明確上下文窗口），Vision Pro 的系統手勢必須先「看手掌」才會出現按鈕。功耗方面 Apple 公開資料幾乎不談。

### Cited Findings
- Pencil Pro 的觸覺引擎在擠壓、雙擊、吸附智慧形狀時輕敲確認 — [MacTrast 2024-05](https://www.mactrast.com/2024/05/apple-unveils-new-apple-pencil-pro-featuring-new-squeeze-gesture-haptic-feedback-find-my/amp/)
- Mac 指標動作可開 Play Sounds 與 Show Actions Visually — [AbilityNet](https://mcmw.abilitynet.org.uk/how-to-set-up-pointer-actions-in-macos)
- Camera Control 輕壓先出現覆蓋層，再調整單一控制 — [Apple Developer：Camera Control](https://developer.apple.com/tutorials/data/documentation/avfoundation/enhancing-your-app-experience-with-the-camera-control.md)
- AirPods 頭部手勢只用於回應 Siri 播報的來電與通知（必須開播報），時效性通知或直接訊息會先播一聲提示音再播報 — [Apple Support 102536](https://support.apple.com/102536)
- Vision Pro 的回主畫面／控制中心要先「看手掌」才出現按鈕或狀態列，之後再點或翻手 — [Apple Support 117741](https://support.apple.com/en-asia/117741)
- visionOS 的 Look to Scroll 只建議用在「內容」型捲動區，每個場景最多六個、需關閉分頁，過小或過多的捲動視圖可能被系統自動停用（後者出自第三方整理的 Xcode 26.4 beta header diff，待核對）— [Apple Developer：lookToScrollAxes](https://developer.apple.com/documentation/uikit/uiscrollview/looktoscrollaxes.md)；[dotnet/macios wiki](https://github.com/dotnet/macios/wiki/UIKit-tvOS-xcode26.4-b2/a1032b6212a10631e4866f50b591c5ad906c4b7d)
- Eye Tracking 的設定與控制資料全部留在裝置上 — [Apple Newsroom 2024-05-15](https://www.apple.com/newsroom/2024/05/apple-announces-new-accessibility-features-including-eye-tracking/)
- Wrist Flick 與 AirPods 手勢都限較新硬體（Watch Series 9+；AirPods 新款），且需韌體更新 — [MacRumors 2025-07-17](https://www.macrumors.com/2025/07/17/new-apple-watch-gesture-watchos-26-newer-models/)；[Digital Trends](https://digitaltrends.com/home-theater/airpods-pro-2-ios-18-updates-head-tracking)
- 誤觸／語意衝突的反例：Camera Control 半按語意重載，評論者批評 — [Six Colors 2025-01](https://sixcolors.com/post/2025/01/apple-wrote-checks-camera-control-cant-cash/)
- BCI 開關控制早期使用者覺得明顯較慢 — [TechCrunch 2025-05-13](https://techcrunch.com/2025/05/13/apple-announces-new-accessibility-features-including-support-for-brain-implants)

### Inferences
- 防誤觸的主要手段是「上下文閘門」而非「更嚴格的辨識」：AirPods 只在 Siri 問話窗口內聽頭部動作，Vision Pro 只在注視手掌時接受系統手勢，Wrist Flick 只在有通知／來電／計時器時有意義。這對 Mac 端（例如 WindowShade 的觸發手勢）是可借用的原則：只在某個狀態下才接受該手勢。
- 新手勢只開給新硬體（Series 9+、新 AirPods）很可能和 ML 模型所需的算力或感測器品質有關，這是推論，Apple 沒有明說。

### Gaps
- 任何一項「始終偵測」的功耗數字或省電策略（如 AirPods 頭部手勢只在播報期間啟動 IMU 分類、Wrist Flick 是否只在螢幕亮起時偵測）都找不到 Apple 一手說明。
- AirPods 頭部手勢辨識成功時有沒有確認音：只見「時效性通知先播提示音」，辨識後的回饋音未證實。
- Wrist Flick 的確認回饋（觸覺？動畫？）未找到可靠來源。

## 問題三：哪些開放了開發者 API，哪些只有系統能用

### Takeaway
開放程度分三級：完整開放（Pencil 雙擊／擠壓、Camera Control、Look to Scroll、Vision Pro 間接捏合）、只給原始資料（AirPods 頭部姿態，手勢要自己辨識）、系統專用（AirPods 點頭搖頭語意、Wrist Flick、Vision Pro 手掌系統手勢、Eye/Head Tracking、Mac 臉部表情、Back Tap）。

### Cited Findings
| 功能 | 開發者能做什麼 | 來源 |
| --- | --- | --- |
| Pencil 擠壓 | `UIPencilInteraction`＋delegate，`pencilInteraction(_:didReceiveSqueeze:)`；讀 `UIPencilInteraction.preferredSqueezeAction` 尊重使用者偏好；SwiftUI 有對應 view modifier | [Apple Developer：Handling squeezes](https://developer.apple.com/documentation/applepencil/handling-squeezes-from-apple-pencil.md)；[Developer Forums 751284](https://developer.apple.com/forums/thread/751284) |
| Pencil barrel roll | `UIPencilHoverPose.rollAngle`（雙擊／擠壓時的懸停姿態含方位、高度、懸停距離、滾動角） | [Apple Developer：UIPencilHoverPose](https://developer.apple.com/documentation/uikit/uipencilhoverpose.md) |
| Camera Control／Action Button | `AVCaptureEventInteraction`（按壓分 phase，可分 primary／secondary；也收 Action Button）；`LockedCameraCapture` 讓第三方相機從鎖定畫面啟動（iOS 18+） | [Apple Developer：Camera Control](https://developer.apple.com/tutorials/data/documentation/avfoundation/enhancing-your-app-experience-with-the-camera-control.md)；[WWDC25 253 索引](https://nonstrict.eu/wwdcindex/wwdc2025/253/) |
| visionOS Look to Scroll | UIKit `UIScrollView.lookToScrollAxes`（visionOS 26）；SwiftUI `.scrollInputBehavior(.enabled, for: .look)` | [Apple Developer：lookToScrollAxes](https://developer.apple.com/documentation/uikit/uiscrollview/looktoscrollaxes.md)；[Developer Forums 793858](https://developer.apple.com/forums/thread/793858) |
| AirPods 頭部動作 | `CMHeadphoneMotionManager` 只給頭部姿態資料，更新率由韌體決定、不可程式設定；點頭／搖頭要 App 自己做分類器，沒有現成手勢回呼 | [awareframework](https://github.com/awareframework/com.awareframework.ios.sensor.airpods)；[iOSDC Japan 2025 講稿](https://speakerdeck.com/kantacky/iosdcjapan2025) |
| Music Haptics | 2024 稿宣布會開放 API | [Apple Newsroom 2024-05-15](https://www.apple.com/newsroom/2024/05/apple-announces-new-accessibility-features-including-eye-tracking/) |
| Switch Control BCI | 新協定給 BCI 裝置廠商 | [Apple Newsroom 2025-05-13](https://www.apple.com/newsroom/2025/05/apple-unveils-powerful-accessibility-features-coming-later-this-year/) |
| Vision Pro 系統手掌手勢 | App 不能停用；開發者回報與自家手掌 UI 衝突 | [Developer Forums 757044](https://developer.apple.com/forums/thread/757044) |
| Wrist Flick | 報導只描述系統設定與系統行為，未見 API | [MacRumors 2025-06-10](https://www.macrumors.com/2025/06/10/watchos-26-gesture-dismiss-notifications/) |

### Inferences
- 規律是：當手勢的語意綁在特定內容上（畫筆工具、拍照、捲動內容），Apple 開放 API 並要求 App 尊重使用者偏好；當手勢的語意是系統層（回應 Siri、關通知、叫控制中心），Apple 留給系統。
- 對 Mac 第三方 App 而言，系統層的這類手勢沒有可掛的公開 API；要做類似功能只能自己接感測器（相機、IMU 資料、觸控板原始事件），並自己負責確認回饋與誤觸防護。

### Gaps
- Apple Watch Double Tap 的開發者 API（watchOS 11 的 `handGestureShortcut` 主要動作）不在本次範圍，未重新核對。
- Eye Tracking／Head Tracking 有沒有 App 端可用的訊號（除了 App 本身支援輔助使用元素外）：未找到，判斷為無，但未證實。
- 2026 年 visionOS 27 的 face gestures 是否開放 API：只有預告，未證實。

## 問題四：Apple HIG 有沒有明文原則

### Takeaway
HIG Gestures 頁面這次抓取失敗，無法逐字引用；可確認的明文來自 API 文件與 HIG 相關段落的方向：尊重使用者在系統設定的偏好（Pencil 偏好動作）、Look to Scroll 只用在內容區、不要和系統手勢衝突。

### Cited Findings
- Pencil 擠壓應讀 `preferredSqueezeAction` 並依使用者偏好行動 — [Apple Developer：Handling squeezes](https://developer.apple.com/documentation/applepencil/handling-squeezes-from-apple-pencil.md)
- Look to Scroll 建議只用在 App 的「內容」捲動區 — [Apple Developer：lookToScrollAxes](https://developer.apple.com/documentation/uikit/uiscrollview/looktoscrollaxes.md)
- HIG Gestures 頁 URL：[developer.apple.com/design/human-interface-guidelines/gestures](https://developer.apple.com/design/human-interface-guidelines/gestures)（抓取只得標題）

### Inferences
- 一般認知的 HIG 手勢原則（不覆蓋系統手勢、自訂手勢要少而易做、即時回饋、重要動作不只藏在手勢裡、每個手勢都有替代輸入路徑）與上面觀察到的產品行為一致，但這次沒有逐字核對，報告引用時要標「未逐字核對」。

### Gaps
- HIG 的 Gestures、Accessibility、Apple Pencil、watchOS Double tap 頁面原文未取得；建議主代理或使用者在本機用瀏覽器打開 HIG 逐字核對後再引用。

## 問題五：共同設計原則歸納（無障礙起源→主流化、確認回饋、避免誤觸、可發現性）

### Takeaway
Apple 這類輸入幾乎都沿同一條路：先在輔助使用裡做（Mac head pointer 2019、iPhone Eye Tracking 2024、Head Tracking 2025、Vision Pro Dwell／face gestures 2026），或先做成有明確上下文的小動作（AirPods 只回應 Siri、Wrist Flick 只關東西），再擴到主流；回饋靠觸覺或覆蓋層；防誤觸靠上下文閘門與限新硬體；可發現性靠設定裡的引導式練習與預設關閉／可對調。

### Cited Findings
- 無障礙起源：Vision Pro「Look Upwards」從主流手勢變成無障礙選項（反向流動），而 Eye Tracking、Head Tracking 都是以無障礙功能身分發布 — [Apple Support 117741](https://support.apple.com/en-asia/117741)；[Apple Newsroom 2024-05-15](https://www.apple.com/newsroom/2024/05/apple-announces-new-accessibility-features-including-eye-tracking/)；[Apple Newsroom 2025-05-13](https://www.apple.com/newsroom/2025/05/apple-unveils-powerful-accessibility-features-coming-later-this-year/)
- 2024 稿把相機辨識手指點擊當作 Switch Control 開關，屬於無障礙先行的「免觸控」輸入 — [Apple Newsroom 2024-05-15](https://www.apple.com/newsroom/2024/05/apple-announces-new-accessibility-features-including-eye-tracking/)
- 可發現性：AirPods 頭部手勢在設定有引導式練習；可對調點頭／搖頭 — [Croma](https://croma.com/unboxed/how-to-use-head-gestures-on-airpods)
- 可發現性反例：Camera Control 半按語意被批評不直覺 — [Six Colors 2025-01](https://sixcolors.com/post/2025/01/apple-wrote-checks-camera-control-cant-cash/)
- 隱私：Eye Tracking 資料只在裝置上；2026 稿的 Tim Cook 聲明強調「privacy by design」— [Apple Newsroom 2024-05-15](https://www.apple.com/newsroom/2024/05/apple-announces-new-accessibility-features-including-eye-tracking/)；[MacRumors 2026-05-19](https://macrumors.com/2026/05/19/new-accessibility-features-with-apple-intelligence/)

### Inferences
- 歸納出的五條原則（推論，非 Apple 明文）：
  1. **上下文閘門**：手勢只在系統正在「問」或使用者正在「看」時生效（AirPods、Vision Pro 手掌、Wrist Flick）。
  2. **動作語意小而可逆**：主流化的免觸控手勢多半是「接受／拒絕／關閉／叫出選單」，不是破壞性動作。
  3. **明確確認**：觸覺（Pencil Pro、Watch）、覆蓋層（Camera Control、Vision Pro 狀態列）、可選聲音或視覺（Mac 指標動作）。
  4. **使用者可設定**：開關、可對調、可改映射；第三方 App 要尊重系統偏好。
  5. **無障礙與主流互相流動**：功能可從無障礙走向主流，舊的主流手勢也可退到無障礙選項保留。
- 對 Back Tap（iOS 14，輔助使用 > 觸控，至今仍放在輔助使用內、無 API）與 Watch Double Tap（2023 從 AssistiveTouch 的捏合手勢主流化）的對照：Double Tap 是「無障礙→主流」的典型；Back Tap 則停在無障礙設定裡，可映射到捷徑但沒有 App API。此兩點出自一般認知，本次未重新抓來源，報告引用前需核對。

### Gaps
- Apple 官方是否有文件明說「無障礙先行再主流化」的策略：未找到，只能從產品時間線推論。
- Watch Double Tap 源自 AssistiveTouch 手勢（watchOS 8，2021）的時間線，本次未重新核對。
