# iPhone 輕點背面（Back Tap）與 iPhone/iPad AssistiveTouch

研究日期：2026-11-01。共約 17 次搜尋／抓取。Apple 官方頁面能直接讀到的只有 Back Tap 支援頁（support.apple.com/111772）和 AssistiveTouch 支援頁（support.apple.com/111794）；AppleInsider 回 403，Apple Newsroom 原文沒抓到，所以相關內容引用的是轉述的二手來源。

## 1. Back Tap 推出版本、支援機型與到 iOS 26 為止的變化

### Takeaway
Back Tap 在 WWDC 2020（2020 年 6 月 22 日那週）隨 iOS 14 公布，支援 iPhone 8 及更新機型（含 iPhone SE 第 2 代起）。iOS 18 加了一批可綁定的動作。iOS 26 有沒有改 Back Tap，查不到證據。

### Cited Findings
- 官方說法：「iOS 14 or later」、「iPhone 8 or later」，設定路徑是 設定 > 輔助使用 > 觸控 > 輕點背面，再選「點兩下」或「點三下」並指定動作 — [Apple Support 111772](https://support.apple.com/en-us/111772)；舊編號 [HT211781](https://support.apple.com/en-us/HT211781)
- Apple 使用手冊的「支援輕點背面的機型」頁列出 iPhone 8 起與 iPhone SE（第 2 代及更新） — [Apple iPhone User Guide aside (iOS 15)](https://support.apple.com/en-kg/guide/iphone/aside/iph005001f91/15.0/ios)
- AppleInsider 在 2020-06-22（WWDC20 開幕當天）就報導這是 iOS 14 新的輔助使用功能（URL 日期可證；正文 403 抓不到） — [AppleInsider](https://appleinsider.com/articles/20/06/22/control-iphone-with-new-back-tap-ios-14-accessibility-feature)；同期 [iMore](https://www.imore.com/ios-14-accessibility-feature-performs-actions-tapping-your-iphone)、[Disability Insider 2020-06-23](https://disabilityinsider.com/2020/06/23/accessibility/ios-14-adds-back-tap-new-accessibility-feature/)
- iOS 18 新增 6 個可綁定動作：Front Camera、Music Haptics、Vehicle Motion Cues、Hover Typing、Live Recognition、Assistive Access。其中 Assistive Access 和 Vehicle Motion Cues 要先在各自的設定裡開啟，才會出現在 Back Tap 清單。Front Camera 是 iOS 17「Detection Mode」改名而來，該項以前非 Pro 機型沒有 — [Gadget Hacks](https://ios.gadgethacks.com/how-to/your-iphones-hidden-back-tap-button-has-6-more-actions-available-with-ios-18-0385612)；[iPhoneIslam](https://iphoneislam.com/en/2024/09/ios_18_hidden_back_tap_features/148516)
- 第三方指南說，可用動作會因機型和 iOS 版本而不同 — [Gadget Hacks](https://apple.gadgethacks.com/how-to/how-to-enable-back-tap-on-iphone-and-pick-the-best-actions/)

### Inferences
- 支援門檻定在 iPhone 8，和 iOS 14 的最低支援機型（iPhone 6s／SE 第 1 代）不同。推測（未證實）：要靠 A11 起的感測器或協處理器能力，或者偵測模型只在這些機型上做過訓練和驗證。
- 隨新輔助功能上線，Back Tap 的動作清單也一直在加，說明 Apple 把它當成「通用快捷觸發器」，不是固定功能。

### Gaps
- 搜尋結果裡沒有 iOS 26 改 Back Tap 的報導，出現的 iOS 26 結果講的是「滑動返回」手勢，不是 Back Tap（[MacRumors 2025-06-10](https://www.macrumors.com/2025/06/10/ios-26-tweaks-swipe-back-gesture/)）。沒找到不等於沒改，要確認得看 iOS 26 的實機設定。
- iOS 15–17 各版是否加減了動作，沒有逐版查到。
- Apple 官方沒有說明為什麼 iPhone 8 是門檻。

## 2. Back Tap 偵測機制、專利、功耗、手機殼與誤觸

### Takeaway
Apple 從未公開 Back Tap 的偵測原理。「加速度計／陀螺儀 + 分類器」是業界通行做法，有 Amazon 專利和 Google 的 Pixel Quick Tap 為證，但 Apple 自己的實作屬推測。厚殼導致漏偵測、甚至頻繁誤觸，都有使用者回報。

### Cited Findings
- Apple 支援頁不談原理，也不提手機殼 — [Apple Support 111772](https://support.apple.com/en-us/111772)
- 媒體和社群普遍說 Back Tap 利用加速度計偵測背面敲擊，有些說法還加上陀螺儀 — [AppleVis podcast](https://applevis.com/podcasts/revisiting-how-use-back-tap-ios)；[TWiT Hands-On Apple 238 transcript](https://twit.tv/posts/transcripts/hands-apple-238-transcript)
- 常被當成「Back Tap 用機器學習」證據的專利 US 9,235,278 B1「Machine-learning based tap detection」，**受讓人是 Amazon Technologies, Inc.，不是 Apple**。2014-07-24 申請，2016-01-12 核准，發明人包括 Peter Cheng、Steven Scott Noble。內容是從加速度計／陀螺儀資料抽特徵向量，用機器學習模型（請求項提到 random forest）判斷是否「敲擊裝置背面」 — [Google Patents US9235278](https://patents.google.com/patent/US9235278)；[Justia](https://patents.justia.com/patent/9235278)
- 2013 年學術原型 BackTap 用手機內建的麥克風、陀螺儀、加速度計，以輕量啟發式方法偵測背面敲擊，可見非 ML 的閾值法也做得到 — [ACM DOI 10.1145/2508468.2514735（via Unpaywall）](https://unpaywall.org/10.1145%2F2508468.2514735)
- 對照：Google 的 Pixel 版（代號 Columbus，後名 Quick Tap）確認使用 TensorFlow 模型。開源移植 Tap, Tap 只需加速度計、陀螺儀和 ML 支援 — [Kieron Quinn, Medium](https://medium.com/@KieronQuinn/tap-tap-v1-0-restarting-from-scratch-2b87c241d176)；[XDA](https://forum.xda-developers.com/t/app-1-5-tap-tap-double-tap-on-back-of-device-gesture-from-android-12-port.4140573/post-83175315)
- 手機殼：多篇排障指南把厚殼、強化殼列為最常見的偵測失敗原因，建議拿掉殼測試或改用薄殼；OtterBox 之類可能要敲得更用力 — [iGeeksBlog](https://www.igeeksblog.com/iphone-back-tap-not-working/)；[BGR 2021](https://bgr.com/tech/iphone-hidden-features-back-tap-screenshot-setup/)
- 使用者回報兩極：一位 iPhone 13 Pro／iOS 18 使用者說大約 5 次只成功 1 次（歸因於節奏和厚殼），另一位則一直誤觸，戴殼也一樣 — [Apple Community 討論串 255939220](https://discussions-jp-prz.apple.com/thread/255939220)
- 誤觸的建議做法：從「點兩下」改成「點三下」，或綁定影響較小的動作 — [Wondershare Dr.Fone](https://drfone.wondershare.com/what-is/what-is-back-tap-iphone-s-hidden-gesture-feature.html)
- 有說法稱軟體會過濾意外碰撞，且手機鎖定或螢幕朝下時不會觸發。來源只是二手搜尋摘要，**未證實** — 見 [easyit.com](https://www.easyit.com/backtap/)（低可信度）

### Inferences
- Apple 的實作「很可能」也是 IMU 訊號加上某種分類器（ML 或規則），理由是業界同類產品（Amazon 專利、Google Quick Tap）都這麼做。但這是**推測**，Apple 沒有公開專利、WWDC 講座或工程訪談可以佐證。
- 推測（未證實）：功耗應該很低，因為 iPhone 的動作協處理器本來就常駐處理 IMU 資料。沒有任何量測或官方數據。

### Gaps
- 找不到 Apple 名下明確對應 Back Tap 的專利，也找不到 WWDC 講座或工程訪談講偵測原理。
- 沒有功耗量測、誤觸率的官方或系統性數據，只有零星使用者回報。

## 3. 可綁定動作、兩下／三下、第三方 App 能否偵測

### Takeaway
點兩下、點三下各綁一個動作，選項涵蓋系統動作、輔助使用動作、捲動手勢和任一捷徑。iOS 18 起又多了幾項。第三方 App **沒有**公開 API 可以偵測 Back Tap，間接做法是讓使用者把 Back Tap 綁到 App 提供的捷徑／App Intent。

### Cited Findings
- 官方舉例：打開控制中心、截圖、輔助使用動作、輔助使用快捷鍵（可開啟 AssistiveTouch、捷徑、放大鏡、便於單手操作、VoiceOver）等 — [Apple Support 111772](https://support.apple.com/en-us/111772)
- iOS 14 的完整清單（第三方整理）。系統類：輔助使用快捷鍵、App 切換器、控制中心、主畫面、鎖定螢幕、靜音、通知中心、便於單手操作、截圖、搖動、Siri、Spotlight、調低／調高音量。輔助使用類：AssistiveTouch、經典反相、放大鏡、智慧型反相、朗讀螢幕、VoiceOver、縮放。捲動類：向下捲動、向上捲動。另外可綁任一捷徑 — [MacMost](https://macmost.com/the-best-hidden-feature-of-ios-14-back-tap.html)；[Beebom](https://beebom.com/customize-back-tap-accessibility-feature-ios-14)；[MacRumors how-to](https://macrumors.com/how-to/trigger-actions-back-tap-iphone)
- 「搖動」可以拿來做「撤銷」，「便於單手操作」把畫面上半部拉下來 — 同上（Beebom/MacMost）
- iOS 18 新增動作見第 1 節 — [Gadget Hacks](https://ios.gadgethacks.com/how-to/your-iphones-hidden-back-tap-button-has-6-more-actions-available-with-ios-18-0385612)
- 越獄社群：Backtrix（FoxfortMobile，約 US$2.25，2021 年 1 月）把 Back Tap 移植到越獄的 iOS 13 和不支援的機型，提供 25 種以上動作，能接 Activator — [iDownloadBlog 2021-01-31](https://www.idownloadblog.com/2021/01/31/jailbreak-tweaks-of-the-week-1-31-2021/)；[iOSHacker](https://ioshacker.com/cydia/backtrix-tweak-brings-back-tap-feature-to-ios-13-and-unsupported-devices)
- 搜尋沒有找到 Apple Developer Forums 或文件中可讓第三方偵測 Back Tap 的 API — （搜尋未果；Apple 開發者文件也沒有對應類別）

### Inferences
- 第三方 App 的實際整合方式是透過捷徑：App 暴露 App Intent／Shortcuts 動作，使用者自己把 Back Tap 綁上去。這是根據「Back Tap 可執行任一捷徑」推出來的，屬可行路徑，不是專用 API。
- Backtrix 的存在說明，用越獄層的感測器資料可以自己重做偵測。但它是重新實作，還是呼叫 iOS 14 的私有元件，查不到。

### Gaps
- 沒有找到逆向分析 Apple Back Tap 私有框架（例如 SpringBoard／AccessibilityUtilities／CoreMotion 內的相關類別名）的公開文章，私有類別名稱**未證實**。
- 沒有找到 Apple 工程師在開發者論壇明確表態「不提供 API」的貼文。

## 4. 從輔助使用功能變成主流「隱藏技巧」，以及為何放在輔助使用設定

### Takeaway
Back Tap 一推出就被科技媒體稱為「iOS 14 最好的隱藏功能」，之後幾年 BGR、Gadget Hacks 等一再以「祕密按鈕」為題報導，捷徑社群拿它當通用觸發器。Apple 沒有公開解釋為什麼把它放在輔助使用而不是一般設定。

### Cited Findings
- MacMost 標題就是「The Best Hidden Feature Of iOS 14: Back Tap」 — [MacMost](https://macmost.com/the-best-hidden-feature-of-ios-14-back-tap.html)
- BGR 2021-04 報導：快一年了，大家還在討論這個隱藏技巧 — [BGR 2021-04-06](https://bgr.com/2021/04/06/iphone-hidden-features-back-tap-screenshot-setup)
- Gadget Hacks 標題稱 iPhone 有個「祕密按鈕，能跑成百上千種動作」，強調搭配捷徑使用 — [Gadget Hacks](https://ios.gadgethacks.com/how-to/your-iphone-has-secret-button-can-run-hundreds-even-thousands-actions-but-you-have-unlock-first-0385356)
- BGR 在「就算不需要也值得試的 iOS 輔助使用功能」裡收錄 Back Tap — [BGR](https://www.bgr.com/2253363/ios-accessibility-features-worth-using/)
- iDropNews 的 iOS 26 新手指南仍把「打開 Back Tap，多兩個隱藏按鈕」列為一個章節，表示到 2025–26 年它仍被當成主流技巧推薦 — [iDropNews](https://www.idropnews.com/how-to/ios-26-new-iphone-user-tips-guide/235708/8)
- 無障礙社群（AppleVis、AbilityNet）把它當成行動不便和視障使用者的捷徑手勢介紹 — [AppleVis](https://applevis.com/podcasts/revisiting-how-use-back-tap-ios)；[AbilityNet](https://mcmw.abilitynet.org.uk/how-enable-back-tap-shortcut-gesture-ios-14-iphone)

### Inferences
- 推測（未證實）：放在輔助使用而不是一般設定的可能理由有三。(1) 機制可能誤觸，預設關閉、藏在較深的地方能降低一般使用者撞到的機會；(2) 它是「替代觸控／按鍵」的輸入方式，和 AssistiveTouch 同屬「觸控」分類；(3) Apple 一貫把非標準的輸入方式（AssistiveTouch、iPadOS 13 的滑鼠支援）先放在輔助使用試水溫，再看要不要主流化。iPadOS 13 的滑鼠支援確實走過「先輔助使用、後於 13.4 移到一般設定」這條路（見第 5 節），可作類比。

### Gaps
- 沒有 Apple 官方或工程訪談解釋 Back Tap 的放置決策。
- 沒有使用率數據。

## 5. iPhone/iPad AssistiveTouch：起源、浮動按鈕、自訂選單、Dwell、指標裝置、Home 鍵損壞時的用法

### Takeaway
AssistiveTouch 是 iOS 5 的功能，2011 年 7 月在 iOS 5 beta 3 中啟用，正式版 2011 年秋季推出。它的核心是一顆可拖到螢幕邊緣的浮動按鈕，能替代實體按鍵、手勢和裝置動作。iOS 13／iPadOS 13（2019）起它成為滑鼠與指標裝置的承載層（含 Dwell）；iPadOS 13.4 把一般的觸控板／滑鼠支援移到一般設定，自訂按鍵仍靠 AssistiveTouch。很多人在 Home 鍵壞掉時用它當虛擬 Home 鍵，這讓它成了大眾知道的功能。

### Cited Findings
- 德國 macerkopf 2011-07-12：AssistiveTouch 在 iOS 5 beta 2 已暗藏，beta 3 啟用。主要給身障者用，也適合實體按鍵壞掉的人 — [macerkopf.de](https://www.macerkopf.de/2011/07/12/beta-3-ios-5-mit-assistive-touch-video/)
- Apple 社群文件：AssistiveTouch 需要 iOS 5 — [Apple Discussions DOC-3401](https://discussions.apple.com/docs/DOC-3401)
- 官方說明列出的功能：調音量、鎖定螢幕、重新開機、截圖；取代實體按鍵和裝置動作（叫 Siri、模擬搖動）；不用滑動就能開控制中心、通知中心、Spotlight、主畫面、App 切換器、朗讀螢幕。浮動按鈕可拖到任一螢幕邊緣並停在那裡 — [Apple Support 111794](https://support.apple.com/en-us/111794)
- 開啟方式：設定 > 輔助使用 > 觸控 > AssistiveTouch；請 Siri 開啟；設為輔助使用快捷鍵（側邊鍵或 Home 鍵按三下，或從控制中心） — 同上
- 自訂：「自訂最上層選單」可替換圖示，用 +／− 增減數量，也能重置；「自訂動作」可分別為單點、點兩下、長按指定功能，並調整點兩下的逾時和長按時間；「製作新手勢」可錄製點按和滑動（含多指，分段錄製後合併播放），並選 2–5 根虛擬手指 — 同上
- 指標裝置：可接有線或藍牙滑鼠、觸控板，控制畫面上的指標 — 同上
- iPadOS 13 先以輔助使用功能的形式提供陽春的滑鼠支援；iPadOS 13.4（2020-03）推出一般用途的觸控板／滑鼠支援，在 設定 > 一般 加了「觸控板與滑鼠」 — [TidBITS 2020-03-28](https://tidbits.com/2020/03/28/the-ipad-gets-full-trackpad-and-mouse-support/)；[Six Colors](https://sixcolors.com/post/2020/03/the-ipad-cursor-is-here-no-wait-required/)；[AppleInsider forum](https://forums.appleinsider.com/discussion/215119)
- 13.4 之後若要自訂滑鼠按鍵，仍要開 AssistiveTouch，在 輔助使用 > 指標控制 / AssistiveTouch > 裝置 調整 — [Cult of Mac](https://www.cultofmac.com/695057/how-to-customize-ipad-mouse-pointer-control-settings/)；[AppleInsider forum](https://forums.appleinsider.com/discussion/215119)
- iPadOS 13 起，AssistiveTouch 成為滑鼠和眼控裝置操作 iPad 的通用方式；Apple 也支援第三方 MFi 眼動追蹤裝置 — [Cricksoft](https://www.cricksoft.com/us/support/kb/mouse-eyegaze-ipad)；[Apple Accessibility (mobility)](https://www.apple.com/my/accessibility/mac/mobility/)
- Dwell：指標在項目上停留一段時間就算選取。iOS 18／iPadOS 18 的內建眼動追蹤（前鏡頭 + 裝置端 ML）就是用 Dwell 來觸發元素和實體按鍵／手勢，據報需要 iPhone 12 以上 — [MacRumors 2024-05-15](https://www.macrumors.com/2024/05/15/ios-18-accessibility-features)；[PhoneArena](https://www.phonearena.com/news/ios-18-brings-eye-tracking-and-dwell-control-to-the-iphone-and-ipad_id159341)
- Home 鍵損壞時的主流用法：Computerworld（2012）、iMore、How-To Geek、MacRumors 都有教學，教人用 AssistiveTouch 的「主畫面」圖示取代壞掉的 Home 鍵或電源鍵 — [How-To Geek](https://www.howtogeek.com/245286/how-to-use-an-iphone-with-a-broken-home-button/)；[iMore](https://www.imore.com/how-remedy-bad-home-button-or-power-button-iphone-using-assistive-touch)；[MacRumors how-to](https://macrumors.com/how-to/create-virtual-home-button-ios)；[Shelly Palmer 2013](https://shellypalmer.com/2013/08/iphone-with-broken-home-button/)
- 使用者經驗：有人 iPhone 5 的 Home 鍵壞了之後一直用到 iPhone 7 Plus；到了 iPhone X 的手勢時代則覺得它變慢 — [MacRumors Forums](https://spy.macrumors.com/threads/anyone-still-using-assistive-touch.2133851/)
- 延伸：2021 年 5 月 Apple 宣布 Apple Watch 版 AssistiveTouch（watchOS 8），以手部肌肉和肌腱活動辨識捏合、握拳來操作，支援 Apple Watch SE 和 Series 6 以上 — [Daring Fireball 轉述 Apple Newsroom](https://daringfireball.net/linked/2021/05/19/apple-new-accessibility-features)；[Computerworld](https://www.computerworld.com/article/3619889/accessibility-takes-a-magic-leap-with-apple-watch-gesture-control.html)；[Apple Watch User Guide](https://support.apple.com/bn-in/guide/watch/apdec70bfd2d/9.0)

### Inferences
- 兩個功能都屬於「替代輸入路徑」。AssistiveTouch 把硬體按鍵和多指手勢搬上螢幕；Back Tap 把機身背面變成按鍵。兩者都從輔助使用起步，靠「硬體壞掉」或「省一個動作」的需求被大眾發掘。
- 從 iPad 的指標支援可以看出 Apple 的模式：先在輔助使用裡做（AssistiveTouch 指標），確認可行後，把主流的部分（觸控板／滑鼠）移到一般設定，進階自訂留在輔助使用。

### Gaps
- iOS 5 正式版發布日期（2011-10-12）是依記憶，本輪沒有用來源核對。
- AssistiveTouch 在 iOS 13 加入 Dwell 的具體版本和官方說明，沒找到 Apple 原始頁面，只有二手來源（Cricksoft 等）。
- 沒有 Home 鍵故障率或 AssistiveTouch 使用率數據。

## 6. Android 等平台對照

### Takeaway
Google 的同類功能 Columbus 先出現在 Android 11 開發者預覽版，後來被撤下，Android 12 以 Pixel 專屬的「Quick Tap」名義上線（只有點兩下），偵測用 TensorFlow 模型。社群用 Tap, Tap 把它移植到其他 Android 手機。

### Cited Findings
- Columbus 首見於 Android 11 早期 DP，以 TensorFlow ML 模型實作，正式版前被擱置；Android 12 用不同的程式碼帶回 — [Kieron Quinn, Medium](https://medium.com/@KieronQuinn/tap-tap-v1-0-restarting-from-scratch-2b87c241d176)；[9to5Google 2021-01-22](https://9to5google.com/2021/01/22/android-12-should-mark-return-of-columbus-double-tap-gesture-for-pixels/)
- Android 12 Beta 2 確認名稱是 Quick Tap，Pixel 專屬，點兩下背面觸發動作 — [9to5Google 2021-06-09](https://9to5google.com/2021/06/09/android-12-beta-2-quick-tap-pixel-5/)；[Android Authority](https://www.androidauthority.com/quick-tap-1233864)
- Tap, Tap（開源）只需加速度計、陀螺儀和 ML 支援，就能把 Pixel 的模型移植到其他機型；模型隨 Pixel 7 等新機更新過 — [XDA](https://forum.xda-developers.com/t/app-1-5-tap-tap-double-tap-on-back-of-device-gesture-from-android-12-port.4140573/post-83175315)；[Medium](https://medium.com/@KieronQuinn/tap-tap-v1-0-restarting-from-scratch-2b87c241d176)

### Inferences
- Google 時間線（2020 年初 DP、2021 年正式）和 Apple（2020 年 6 月公布、9 月正式）幾乎同時，可見「機身背面當按鍵」是兩家在同一時期各自得出的方案。Google 走一般設定（手勢），Apple 走輔助使用，放置策略不同。

### Gaps
- 有網址提到 Samsung 有背面敲擊類功能，但來源不可信，沒有查證。
- Pixel Quick Tap 是否已支援點三下或有其他後續變化，沒有查。
