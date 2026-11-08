# Chan Karunamuni 公開設計作品筆記（給 WindowShade 的互動與動效研究）

研究日期：2026-10-29。唯讀研究：沒有聯絡任何人，沒有改動 /Users/aaron/Documents 內任何檔案。

## 0. 怎麼讀這份筆記

證據標記：

- [V] 本輪直接讀到官方來源（Apple Developer 逐字稿 HTML、Apple Newsroom、Apple Support、HIG JSON、Apple 文件 .md、Google Patents 原文、chankarunamuni.com 原始 HTML）。
- [V2] 經第三方鏡像或索引確認（fxtwitter 公開 API 取得的貼文文字、Non-Strict WWDC Index、社群程式碼）。
- [I] 推論：把來源原則翻成桌面（游標、觸控板、鍵盤）的判斷，不是 Apple 或 Chan 說的。
- [U] 未驗證。

引文政策：因版權限制，本檔只有一處逐字引文（不到 15 字，在 C2 列），其餘全部改寫。每一條改寫都附 Apple 逐字稿的 [mm:ss]，打開對應頁面的 Transcript 分頁就能核對。時間點取自逐字稿 HTML 的 data-start 秒數，是句級近似值，誤差約數秒。逐字稿裡 Apple 寫「iPhone 10」，本檔一律寫 iPhone X。概念名稱（response、damping、projection、hysteresis、rubberbanding 等）是講座用的術語，不算引文。

## 1. 先講結論

1. 你列的六件作品全部在他官網上，也全部有 Apple 或貼文的對應來源；但官網只有 7 個連結，沒有日期、說明、文章或新聞。
2. 「Chan 的」講座其實是多人合講。803 的彈簧與投影（projection）是 Nathan de Vries 講的，點按與滑動細節是 Marcos Alonso 講的；Chan 自己講的是原則、教學、遊玩與原型。10194 只有後半（動態島）是 Chan；219 只有前約 6 分鐘（Dynamics）是 Chan。
3. 最能直接搬進桌面視窗管理器的是 803 的五件事：隨時可打斷並改向、用加速度而不是計時器判斷停頓、用減速率投影決定落點、一比一跟手加持續回饋、彈簧只用 response 與 damping 兩個參數。
4. iPhone X 手勢（2017）沒有 Apple 逐字稿，但同一批人（含 Chan、Nathan、Marcos）掛名的專利 US10203866B2 把「停頓 vs 甩出」的判斷寫成了可量的條件（投影 150 ms、30% 大小、¼ 螢幕高等），是 803 原則的具體實作樣本。這些數字是專利實施例，不是已證實的出貨常數。
5. WindowShade 的 docs/design-system.md 與 prototype/Core 已經吸收了 803 的大部分（見第 9 節）；還沒落地的主要是以指標減速取代懸停計時器（目前是計時器加位移與速度閘），以及幾處文件引用對不上來源或程式碼。

## 2. 他的官網：全部項目（chankarunamuni.com）

官網原始 HTML 只有：標題 Chan Karunamuni、og:description 寫 UI 設計師、7 個作品連結、1 個 mailto 聯絡連結。沒有日期、描述、文章、新聞、社群圖示。7 個連結都指向 X 貼文，不是直接指向 Apple 頁面。日期欄是由貼文 ID（Snowflake 時間戳）算出，並與 fxtwitter 回傳的 created_at 一致。[V][V2]

| # | 官網標籤 | 貼文（日期，UTC） | 貼文說了什麼（改寫） | Apple 端對應 | 狀態 |
|---|---|---|---|---|---|
| 1 | iPhone X Gestural UI | https://twitter.com/chan_k/status/926496978019557376（2017-11-03） | 做了約一年半的專案終於上線，邀大家試 iPhone X 新的流動手勢介面；附 4 秒影片 | Apple Newsroom 2017-09-12：iOS 11 以快速流暢的手勢取代 Home 鍵，從底部上滑回主畫面 https://www.apple.com/newsroom/2017/09/the-future-is-here-iphone-x/ | [V] |
| 2 | Designing Fluid Interfaces WWDC Talk | https://twitter.com/chan_k/status/1004771568633798656（2018-06-07） | 他在 WWDC18 談 iPhone X 流動手勢介面的設計；同場另有 @atnan 談動態、@malonso 談手勢；連到 803；附 16 秒影片 | WWDC18 803，Apple 頁 uploadDate 2018-06-06，片長 64:41（Non-Strict）https://developer.apple.com/videos/play/wwdc2018/803/ | [V] |
| 3 | Dynamic Island | https://twitter.com/chan_k/status/1570795751764295682（2022-09-16） | 稱這是他設計的新專案；目標是做成像有生命、有彈性的氣泡，能流暢變形成不同的提醒與體驗；附 58 秒影片 | Apple Newsroom 2022-09-07：與硬體融為一體的設計，即時變形顯示提醒與活動，長按可存取控制，可流暢展開成不同形狀（例如 Face ID 驗證）https://www.apple.com/newsroom/2022/09/apple-debuts-iphone-14-pro-and-iphone-14-pro-max/ | [V] |
| 4 | Dynamic Island WWDC Talk | https://x.com/chan_k/status/1666826781498957830（2023-06-08） | 他在講座下半場分享動態島設計背後的想法與範例；連到 10194；附 71 秒影片 | WWDC23 10194，片長 14:59，章節 7:37 起是 Dynamic Island https://developer.apple.com/videos/play/wwdc2023/10194/ | [V] |
| 5 | Flashlight | https://x.com/chan_k/status/1835729051178451013（2024-09-16） | 說這是他今年做的一個小副專案，設計 iOS 18 新手電筒介面；附 17 秒影片 | 沒有 Apple 設計講座；只有 Support 文件（見第 7 節）https://support.apple.com/en-us/105001 | [V]，設計動機 [U] |
| 6 | Liquid Glass | https://x.com/chan_k/status/1932185261162766459（2025-06-09） | 說最新專案是 Liquid Glass，與一整批設計師與工程師合作；設計成能彎折塑形光線、同時像有彈性的材質，可動態變形，讓 App 更流動有機；附 42 秒影片 | Apple Newsroom 2025-06-09 https://www.apple.com/newsroom/2025/06/apple-introduces-a-delightful-and-elegant-new-software-design/ | [V] |
| 7 | Liquid Glass WWDC Talk | https://x.com/chan_k/status/1932185423532654730（2025-06-09） | 邀請看深入談 Liquid Glass 思考、哲學與原則的設計講座；連到 219 | WWDC25 219，片長 19:33，章節 0:00 Introduction／1:29 Dynamics／6:00 Adaptivity／10:31 Principles／18:53 Next steps https://developer.apple.com/videos/play/wwdc2025/219/ | [V] |

對照你的清單：六件全部對得上。「Liquid Glass」在官網是兩個連結（專案貼文＋講座貼文）。貼文裡的影片（約 4、16、58、71、17、42 秒，依表格順序）我沒有下載或觀看 [U]。

他的 X 簡介（fxtwitter）：自稱 Apple 的 Human Interface 設計師；帳號 2008-04 建立；約 10.8 萬追蹤；109 則貼文；網站 chankarunamuni.com。[V2]

找不到的東西：沒找到他本人的訪談、Podcast、研討會講座或部落格（兩輪搜尋都沒有）。2025-12 有新聞說 Alan Dye 離職、Steve Lemay 接任，Chan 在 X 表示期待；那是搜尋結果摘要，我沒有打開原文。[U]

## 3. 誰講哪一段

| 講座 | 講者與段落（逐字稿時間） | 來源 |
|---|---|---|
| 803 Designing Fluid Interfaces | Chan Karunamuni 00:36–23:01（原則）與 57:28–64:30（教學、遊玩、把互動當媒介）；Nathan de Vries 23:01–49:06（動態、彈簧、投影）；Marcos Alonso 49:06–57:28（手勢） | 逐字稿自我介紹 [V]；全名取自 Non-Strict WWDC Index 與專利發明人欄 [V2] |
| 10194 Design dynamic Live Activities | Mac Tyler 00:00–07:39（鎖定畫面、StandBy）；Chan 07:39–14:48（Dynamic Island） | 逐字稿 [V]；Apple 章節 7:37 [V] |
| 219 Meet Liquid Glass | Chan 00:07–05:51（導言、Dynamics）；Shubham Kedia 06:00–10:31（Adaptivity）；Bruno Canales 10:31–結尾（Principles） | 逐字稿 [V]；全名 Non-Strict [V2] |

專利 US10203866B2 的發明人欄同時列出 Chanaka G. Karunamuni、Marcos Alonso Ruiz、Nathan de Vries 等人；「Chanaka G. Karunamuni」就是 Chan Karunamuni 這件事，靠共同發明人與主題重疊強烈暗示，但沒有 Apple 或他本人頁面明說。[V][I]

## 4. WWDC18 803：原則與技巧逐項（Apple 逐字稿）

ID 供第 8 節引用。全部為改寫。

### Chan（第一段：原則）

| ID | 時間 | 原則／技巧（改寫） | 備註 |
|---|---|---|---|
| C0 | 01:49–02:09、03:04–04:18 | 流動不等於高幀率：60 fps 仍可能不對勁。標準是工具像心智的延伸；歷史上不斷剝掉介面與內容之間的層，直接操作內容就是魔法所在，任何一點不對勁都會打破幻覺 | 這是整場的價值判斷 |
| C1 | 05:33–06:51 | response：人對延遲極敏感，稍有延遲就斷崖式下滑，變成心理負擔。連硬體都為了更快偵測手指而改。要在每一種互動找延遲，不只滑動，還有點按與按壓；設計過程中延遲與計時器會悄悄滲進來，要保持警覺 | 對應 M1、M4、M5 |
| C2a | 06:51–07:58 | 隨時改向：像走到一半發現忘了東西，立刻轉身，不必走到盡頭。iPhone X 是完全可改向的兩軸手勢：水平在 App 間移動、垂直回主畫面，兩軸可混用，回家途中可偷看多工再決定去不去 | |
| C2b | 07:58–09:22 | 不可改向的替代設計會變成線性：先想、再做、再放手。可改向時思考與手勢並行，比先想再做快；它是一個多軸手勢空間而非多個分離手勢；有助探索（沿著既有手勢的路徑發現新手勢），也讓手勢能以思考的速度疊加 | |
| C2c | 09:22–10:41 | 疊加範例（慢動作模擬）：回主畫面的同時翻頁；App 啟動中打斷去多工；啟動錯 App 時中途甩回主畫面；啟動中就開始操作 App。重點是介面永遠在回應，這決定使用者敢不敢信任它；對「動作中途改變」同樣要回應 | |
| C2d | 10:41–11:33 | 判斷「停頓」：計時器太慢（使用者期待立刻進多工），改看手指加速度。停下時加速度有明顯尖峰，停得越快越早偵測到 | 逐字引文（≤15 字）：the faster you stop, the faster we can detect it（Chan, 803, 約 11:17） |
| C3 | 11:47–13:28 | 空間一致：模仿物體恆存。從哪裡離開就該從哪裡回來，進出走對稱路徑。導覽推入從右邊滑入、返回往右邊滑出；這也強化手勢，因為使用者知道它住在哪裡，可以自己把它滑回去。反例：進入是滑入、返回卻往下，像是被送到別處，除非你就是要表達「送走」 | |
| C4 | 13:28–14:39 | 順著手勢方向給暗示：人會預測軌跡。物件應在手勢或動畫中，從起始狀態朝最終狀態長出去。例：控制中心模組被按壓時朝手指方向長大，最後彈開 | 手勢因此顯得可預期 |
| C5 | 14:39–16:56 | 輕輸入、放大輸出：多點觸控的輕盈是被低估的優點。用位置、速度、力道等全部資訊建立手勢的慣性輪廓（inertial profile），再延伸成放大的輸出；捲動就是範例，若沒有它要靠冗長的滑動；回主畫面手勢輕而液態，還沿用按鈕的肌肉記憶。點按也要有令人滿意的回應 | 對應 N11 |
| C6 | 17:01–18:14 | rubberbanding：用軟邊界告知到頭了，且全程持續跟手。沒有它會像撞牆、像壞掉，分不出是手機凍結還是已到邊界。也適用於換手：從上滑 Dock 轉成上滑 App，兩者用平滑曲線交棒，不是一個停住另一個才接手 | 換手（handoff）是容易漏掉的一半 |
| C7 | 18:14–20:49 | 平順的影格：相鄰影格差異太大就會頻閃，所以不只是幀率，而是影格裡有什麼；60 fps 比 30 fps 容許更快的移動；可用動態模糊、以及動態拉伸（motion stretching，向速度方向拉伸）編碼更多資訊。iPhone X 啟動 App 時圖示彈性下拉變成 App，關閉時向上拉伸 | |
| C8 | 20:49–21:48 | 行為取代動畫：真實世界沒有預設曲線，動畫應是使用者與物件之間的對話。例：照片較輕（質量小）、App 切換較重（質量大） | 質量是設計參數 |
| C9 | 21:48–23:01 | 小結：response、空間一致、順著手勢暗示、輕輸入放大輸出、軟邊界與換手、平順的動態行為 | |

### Nathan de Vries（第二段：動態）

| ID | 時間 | 原則／技巧（改寫） | 備註 |
|---|---|---|---|
| N1 | 23:53–25:11 | 計時動畫是設計師接手控制再交還；流動介面中設計師改為設計持續運行的動態行為，與互動並行 | 後面所有都建立在這句 |
| N2 | 25:54–27:32 | seamless motion：以車子煞車的位置曲線為例，曲線不中斷、方向無突變，連停下的瞬間都無法察覺 | 連續位置與連續速度 |
| N3 | 28:21–29:58 | 捲動是範本：拖曳時由身體提供流動性；放手後保留動量滑行；摩擦力恆定所以可預測；停下時難以察覺，這傳達內容隨時可動，所以再次按下就能接手，不必等任何東西結束 | 「不必等」是設計目標 |
| N4 | 30:08–32:30 | 彈性（elasticity）：回到靜止狀態的傾向。iPhone X 點圖示時彈性行為把 App 拉向你、從底部上滑時放回主畫面的位置；捲動過界後以彈性拉回。把內容想成接在彈簧上的球，現值被拉向目標；彈簧天生無縫 | |
| N5 | 32:30–35:14 | 把質量、剛度、阻尼收在幕後，只暴露兩個參數：damping（100% 無過衝、0% 永遠振盪）與 response（多快趨近目標）。刻意避開 duration 這個詞，因為它暗示一次性，而彈簧始終在動、隨時可改去別處。技術名稱：damping ratio、frequency response | |
| N6 | 35:47–36:39 | 從簡單開始：工具要用得上就不該擋路；預設 100% damping（無過衝），不必用會彈的彈簧，這樣動態平順優雅不干擾任務（例：快速寄一封信） | |
| N7 | 36:39–37:46 | 何時彈：如果驅動動態的手勢本身帶有動量，就該用少量過衝回報它；有動量卻沒有過衝會顯得壞掉或不滿足。Music 例：點迷你播放列（沒有朝向展開方向的動量）用 100% damping；滑動關閉（有動量）用 80% damping，帶一點彈與擠壓 | 80% damping 約等於 bounce 0.2 |
| N8 | 37:46–38:56 | 彈跳也能當功能性暗示：iPhone X 鎖定畫面的手電筒按鈕要較有意識的按壓才啟動；輕點時按鈕以彈性回應，告訴你它有反應、而且再用力一點就會開（朝動作方向暗示） | 也見 M4 |
| N9 | 38:56–39:57 | 超越動態：光、色彩、質感、聲音都是感知動態的方式；把動態行為與聲音、觸感行為結合，會讓同一個捲動變成觸感介面 | |
| N10 | 39:57–41:06 | 維持一致性格：行為是一個家族。例：手動捲動（捲動行為）與點狀態列回到頂端（彈性行為），頁面看起來移動得一樣；整個 App 都該符合同一性格，使用者學會一種行為就能舉一反三 | |
| N11 | 41:06–48:35 | 讓落點對準意圖：按鈕的意圖明確；滑動的意圖編碼在動作裡。FaceTime 子母畫面有四個隱形終點。只看位置找最近角落，要拖過一半才會換角，甩動則回到最近角，不放大輸入。解法：沿用捲動熟悉的減速率，把釋放速度投影出一個不顯示的假想位置，再找離「投影位置」最近的終點，然後用重定目標（retarget）把子母畫面送過去。同一函式可用於位置、縮放、旋轉及其組合。小結：彈跳要有目的，要平衡性格與功能；一定要投影動量 | 公式在投影片上，見第 7 節 |

### Marcos Alonso（第三段：手勢）

| ID | 時間 | 原則／技巧（改寫） | 備註 |
|---|---|---|---|
| M1 | 50:00–51:12 | 點按：按下的瞬間立刻高亮（顯示系統有反應）；但到手指抬起才確認；點擊區外擴一圈邊界，避免移動造成誤取消；允許改變心意：手指拖出區外再放開就取消，拖回來又會高亮並可確認 | 計算機按鈕範例 |
| M2 | 51:12–52:50 | 滑動：手指必須移動一段距離（hysteresis，iOS 通常 10 點）才算滑動；此刻可決定方向（水平或垂直）；之後手指與內容合為一體移動，保留相對位置，絕不以內容中心作為拖曳點；拖曳中持續記錄位置與速度，結束時不用最後一點而用觸控歷史，動量才能平順交給內容 | |
| M3 | 52:50–53:47 | 一比一跟手（1:1 tracking）：是 iOS 的核心原則，一旦不再一比一使用者立即察覺（捲動時這代表已到內容盡頭）；不限於觸控螢幕，Apple TV 的操作也圍繞「手勢與介面之間有直接連結」設計 | 觸控板同理，見第 8 節 |
| M4 | 53:47–55:00 | 持續回饋：貫穿整個互動，不只滑動。手電筒按鈕大小隨按壓力道變化，既確認動作也教你用力按會開；Apple TV 的焦點引擎持續顯示選取將往哪走。因此要避免只在結束時才通知的辨識器（例如 UISwipeGestureRecognizer），改用原始觸控或能提供位置、速度、壓力、接觸大小的辨識器 | |
| M5 | 55:00–56:49 | 多手勢並行：聯絡人清單同時有捲動與按住預覽。若等到最終手勢才給回饋就會有延遲；因此一開始就偵測所有可能的手勢，意圖確定後取消其餘。有時延遲無可避免：用了雙擊，所有單擊都要等（照片縮放範例約延遲半秒）；設計時要意識到並盡量避免 | |

### Chan（第四段：怎麼做流動介面）

| ID | 時間 | 原則／技巧（改寫） | 備註 |
|---|---|---|---|
| T1 | 57:38–60:26 | 教學：手勢不明顯，所以要友善地帶使用者。視覺提示：列表底部被切掉暗示還有內容；分頁指示點；可抓取的把手；把可互動元素抬到另一層（開關的旋鈕）；用靜態動畫呼應手勢（Safari 按 x 關分頁時分頁往左滑走，暗示你也能自己往左滑）；明確說明要節制，只給「在很多地方反覆使用」的手勢說一次，間歇使用的手勢說了也記不住 | |
| T2 | 60:26–61:41 | 遊玩：趣味是把一切做對的自然結果；讓人發現介面而不是學會介面；自己先玩，也交給別人看他們怎麼把玩 | |
| T3 | 61:41–63:30 | 把互動當媒介：互動設計與視覺不可分、不是事後補；做互動原型，一個互動示範勝過大量靜態稿，也為工程設定目標；這就是 iPhone X 介面的做法，做出來也不易被抄 | |
| T4 | 63:30–64:30 | 結語：回應、可改向、可打斷的手勢，動態行為，優雅的手勢處理，是 iPhone X 手勢介面的核心 | |

## 5. WWDC23 10194：Chan 的 Dynamic Island 段（07:39–14:48）

| ID | 時間 | 內容（改寫） |
|---|---|---|
| DI1 | 07:39–08:09 | 動態島是各種提醒與活動指示的統一家；硬體與軟體融合的單一系統層，能有機地在各種狀態間變形；目標是照看背景活動並提供快速互動 |
| DI2 | 08:09–08:18 | 每個項目的外觀、手感與動畫各自獨特，但整體仍是一家人；獨特性幫助一眼分辨並減輕認知負擔 |
| DI3 | 08:18–09:37 | 行為與質感：受生物形態與運動啟發，像活的有機體；刻意的彈性是對固定硬體的趣味對比；單車 App 例：離開 App 時 App 像是飛進去並實際住進那個空間，並帶著 App 的身分與個性；用動畫與持續更新的資料讓它有生命；形狀更圓更厚、文字更大更粗、用色彩表達身分 |
| DI4 | 09:37–10:55 | 貼合：對形狀與位置極敏感；放入物件要與島的形狀同心（圓形元素邊距均勻）；非圓形元素用視覺質心，可把物件模糊後檢查結果是否與外框同心；內容與文字維持同心邊距，避免戳進角落或太貼側牆；用內縮形狀或分隔線區分區塊，不要畫到邊 |
| DI5 | 10:55–11:19 | 三種大小：Compact（水平延伸）、Expanded（綻開）、Minimal（小） |
| DI6 | 11:19–12:18 | Compact 最常見，用來一邊使用手機一邊照看活動；它要提供資訊而不只是回 App 的連結；盡量窄、不浪費空間、內容貼緊感測器區；盡量填滿，必要時縮短單位或給較不精確的資料；多個工作階段時輪流顯示；有事件要提醒時，盡可能展開動態島而不是另發推播 |
| DI7 | 12:18–12:41 | 動態島和通知一樣浮在 App 之上；App 不該畫出指向動態島或與它互動的 UI |
| DI8 | 12:41–13:39 | Expanded：按進去放大查看並使用必要控制；抓住活動的精華，不要太少也不要太多；像有個迷你版 App 住在裡面；compact 與 expanded 之間盡量維持元素相對位置以保持連貫；高度從高到藥丸矮版不等，避免剛好卡在兩種高度的邊界；不要在上方留一塊額頭（forehead）去強調感測器，改為緊貼並環繞它，讓它幾乎消失 |
| DI9 | 13:39–14:16 | Minimal：多個活動並存時顯示；別退化成只放 logo，小小一格也要持續傳達資訊 |
| DI10 | 14:16–14:48 | 小結：這是一個 App 可以棲身的新系統層；身分要適配此空間；要處理貼合與位置；整體可視為一種新的多工與新的 App 互動方式 |

HIG Live Activities（書面配套，[V]）補充的可量細節：動畫最長 2 秒、AOD 降亮度時系統不做動畫；版面變化要把既有元素動畫移到新位置，不要移除再重入；避免元素重疊；互動限縮在單一控制以防誤點；多事件用單一活動輪播；結束的活動立即從動態島移除；Dynamic Island 是黑色不透明背景，暗色模式下有色邊線。https://developer.apple.com/design/human-interface-guidelines/live-activities

## 6. WWDC25 219：Chan 的 Dynamics 段（00:07–05:51）與其他講者的相關句

| ID | 時間 | 講者 | 內容（改寫） |
|---|---|---|---|
| LG1 | 00:07–01:06 | Chan | Liquid Glass 是柔性、動態的一層；承襲 Mac OS X 的 Aqua、iOS 7 的即時模糊、iPhone X 的流動、動態島的彈性、visionOS 的沉浸；不是重造物理材質，而是一種新的數位超材質（meta-material），動態地彎折與聚光，同時有機移動，像輕盈的液體，回應觸控的流動與現代 App 的動態 |
| LG2 | 01:29–01:55 | Chan | 圓潤、浮動的形狀貼合現代裝置的圓角；形狀易點按，貼合手指的自然幾何 |
| LG3 | 01:55–03:10 | Chan | 以 lensing（透鏡）界定自身；用光的扭曲傳達存在、運動與形態，在分層時又讓內容透出；出現與消失不是淡入淡出，而是逐步調整折光與透鏡效果（materialize），保持材質的光學完整 |
| LG4 | 03:10–03:51 | Chan | 視覺與動態一體設計；參照液體那種平滑、有回應、毫不費力的運動；互動時立即彎曲並以光量充能，讓介面有回應感、令人滿足、像活的 |
| LG5 | 03:51–04:10 | Chan | 類凝膠的彈性，傳達短暫、可塑的性質，隨互動同步移動，與我們思考與動作的動態相符 |
| LG6 | 04:10–04:32 | Chan | 元素在互動時可暫時升起成玻璃；靜止時保持安靜，互動時活起來；對控制項來說，透明的液態透鏡讓你能看見下方的數值 |
| LG7 | 04:32–05:24 | Chan | 在不同情境間，玻璃動態變形，維持單一浮動平面；選單是氣泡就地彈開，一切留在剛剛點按的位置，明確表達按鈕與內容的關係 |
| LG8 | 05:24–05:51 | Chan | 總結：App 的使用感更有機、更沉浸、更流動 |
| SH1 | 07:40–08:01 | Shubham | iPad 與 Mac 上同一套原則：玻璃層是浮在一切之上的控制與導覽功能層；玻璃控制項嵌入視窗圓角、維持同心 |
| BR1 | 12:05–12:23 | Bruno | 互動時材質從內部發亮作為回饋，光從指尖下方擴散到元素乃至附近的玻璃 |
| BR2 | 12:37–12:46 | Bruno | Mac 或 iPad 上視窗失去焦點時，玻璃改變外觀、視覺上退後以引導注意力 |
| BR3 | 12:46–13:34 | Bruno | 玻璃只保留給浮在內容之上的導覽層；內容層（例：表格）不要用；避免玻璃疊玻璃，上層元素改用填色、透明度與 vibrancy |
| BR4 | 18:06–18:53 | Bruno | 減少動態效果會降低部分效果的強度，並停用材質所有彈性屬性 |

Apple 文件旁證：HIG Motion 開頭明講 Liquid Glass 的動態對直接觸控較強調，對觸控板操作則較收斂；HIG Motion 還建議頻繁的 UI 互動少加動態、讓使用者可取消動態（不必等動畫完成）。[V] https://developer.apple.com/design/human-interface-guidelines/motion

AppKit 與 SwiftUI 對應 API（macOS 26 起）：NSGlassEffectView 有 effectIsInteractive（互動時的視覺回應）、NSGlassEffectContainerView 在 spacing 範圍內合併玻璃；SwiftUI 有 GlassEffectTransition.materialize 與 matchedGeometry。[V] 文件來源見第 10 節。

## 7. 沒有逐字稿的三件：iPhone X 手勢、Dynamic Island 2022、Flashlight

### 7.1 iPhone X 手勢介面（2017）

- Apple 說法：iOS 11 以快速流暢的手勢取代 Home 鍵，從底部上滑回主畫面。[V]
- 803 的實作細節見 C2a–C2d、C6、M2、M3。
- 專利 US10203866B2，Devices, methods, and graphical user interfaces for navigating between user interfaces and interacting with control objects，申請日 2018-01-24（Google Patents 欄位），發明人含 Chanaka G. Karunamuni、Marcos Alonso Ruiz、Nathan de Vries 等。https://patents.google.com/patent/US10203866B2/en [V]。以下是描述段裡「e.g.」的實施例，不是已證實的出貨常數：
  - 停頓與否的條件：上滑途中，在一個時間門檻內減速超過門檻量，且放手前後續移動小於門檻，就顯示多工；沒偵測到減速就回主畫面；放手前繼續移動超過門檻會推翻停頓條件。
  - 放手時用投影：假設卡片以放手瞬間的速度再走一段固定時間（例：150 ms），或是以摩擦係數遞減速度，算出投影位置與大小。
  - 例：投影大小小於整個螢幕的 30% 則回主畫面；否則看投影位置是否離底邊中點超過螢幕高的 ¼；再看方向（相對底邊超過 30 度為向上或向下，否則為橫向）與放手速度（例：至少每秒 ⅛ 螢幕高）決定去向。
  - 受保護狀態：全螢幕或不該被意外打斷的情境（遊戲、導航），手勢需要二次驗證才會離開（專利 Method 900）。
  - 專利全文很長（描述約 88 萬字元），我只讀了與減速、投影、受保護狀態相關的段落。[U] 其他家族成員（例如 US10635294B2 App 切換介面、US11188220B2 dock）未讀。
- 相鄰的 Apple 資源 Designing for iPhone X（2017-09-12 的 Tech Talk，網址現在落在 /videos/play/tech-talks/801/）談的是安全區、版面邊距、Home 指示條的對比與邊緣保護（需要兩次滑動才離開 App，只在絕對必要時使用）；逐字稿沒有講者姓名、沒有出現 Chan，所以它不是 Chan 的講座。[V]

### 7.2 Dynamic Island（2022）

- Apple 說法：Newsroom 2022-09-07 描述為模糊硬體與軟體界線的設計；即時調整以顯示重要提醒、通知與活動；保持主動狀態，長按（tap-and-hold）可輕鬆存取控制；Maps、Music、計時器等背景活動保持可見且可互動；iOS 16 的第三方 Live Activities 可使用；會流暢展開成不同形狀以呈現 Face ID 驗證等。[V]
- Chan 本人的說法見官網項目 3、4；設計思路見第 5 節（講座 10194）。

### 7.3 iOS 18 Flashlight（2024）

- Chan 的唯一文字：一個小的副專案，設計 iOS 18 新手電筒介面。[V2]
- Apple Support（該頁註明 Dynamic Island 見於 iPhone 14 Pro 與之後的 Pro 機型；其他機型是否支援光束調整我沒驗證）：開啟手電筒後點一下動態島，長按光線圖示並拖曳，可改變光束的寬度與長度；亮度可在控制中心長按手電筒按鈕後上下拖曳滑桿調整。https://support.apple.com/en-us/105001（發佈 2025-12-11）[V]
- iOS 18 使用手冊：開啟後螢幕上會出現手電筒的圖像，在圖像上上下拖曳可調亮度。https://support.apple.com/guide/iphone/turn-the-iphone-flashlight-on-or-off-iphf574afb44/18.0/ios/18.0 [V]
- 設計動機、動畫細節：找不到 Apple 或 Chan 的書面說明。[U]
- 值得記一筆：803 裡 Nathan 與 Marcos 都拿「iPhone X 鎖定畫面的手電筒按鈕」當教材（彈跳當暗示、按壓力道連續回饋），而 Chan 在 2024 又做了新一代手電筒；兩者是不同的東西，別混。

### 7.4 投影公式與彈簧換算（官方投影片未讀）

- 803 的投影片 PDF 超過 10 MB，WebFetch 讀不了；我沒有下載二進位檔。所以講座中口述為「投影函式」的程式碼與公式沒有對官方投影片驗證。[U]
- 社群轉錄的形式：projected = position + (v/1000)·r/(1−r)，r 為 UIScrollView 的減速率。這是每毫秒速度乘 r 的等比級數和，數學上自洽；Apple 文件只確認 UIScrollView.DecelerationRate 有 normal（預設）與 fast 兩個常數，沒有給 0.998 與 0.99 的數值。[V2][U]
- response 與 damping 換成彈簧參數：mass 1、stiffness = (2π/response)²、damping = 4π·dampingRatio/response。出處是社群程式碼（Guilherme Rambo 的 Sheet 專案 FluidTimingCurve.swift）與 Nathan Gitter 的文章（該頁回 403，我只看到搜尋摘要）；它等於「response 是無阻尼週期、damping ratio 是 c/(2√(km))」的標準代換。UIKit 本身沒有 init(damping:response:)，只有 init(dampingRatio:initialVelocity:)、init(mass:stiffness:damping:initialVelocity:) 與 init(duration:bounce:)。[V2][V]
- SwiftUI Animation.spring(response:dampingFraction:blendDuration:) 的預設值是 response 0.5、dampingFraction 0.825；文件明說同屬性上的新彈簧會取代舊彈簧並保留速度，response 為 0 表示極硬、適合驅動互動動畫。[V]

## 8. 翻成桌面（游標＋觸控板＋鍵盤）視窗管理器

### 8.1 觸控概念到桌面概念的對照 [I]

| 803 的概念 | 桌面對應 |
|---|---|
| touch-down／touch-up | mouseDown／mouseUp、觸控板接觸開始／結束、keyDown／修飾鍵放開 |
| hysteresis（約 10 點） | 滑鼠拖曳門檻、觸控板捲動事件的 begin 後累積位移；專案目前 8 pt |
| 一比一跟手 | 游標拖曳保持抓取偏移；觸控板用 precise scrolling delta（點）直接映射，增益固定 |
| 釋放速度 | 最後約 100–150 ms 的事件歷史（含時間戳）算出的速度；不是最後一個事件 |
| 加速度尖峰判斷停頓 | 指標速度對近期峰值的驟降（要先平滑，滑鼠事件有雜訊） |
| 壓力／按壓力道 | 有 Force Touch 的觸控板可用 NSEvent.pressure（文件 [V]） |
| 觸覺 | 觸控板的 NSHapticFeedbackManager（design-system 原則 12 提到 .alignment 與 .levelChange） |
| touch-and-hold | 按住、或以指標減速判斷的懸停意圖 |

### 8.2 做什麼、避免什麼（每條掛來源 ID）

| # | 做 | 避免 | 對應 WindowShade 功能 | 依據 |
|---|---|---|---|---|
| 1 | 釋放時用投影落點選終點：把釋放速度乘減速因子投影出假想位置，找離它最近的終點，用釋放速度當初速度開彈簧去追（retarget）。適用子母畫面四角、貼齊與平鋪格位、收進瀏海、捲簾收合與否，也適用縮放比例 | 只看釋放瞬間的位置找最近區；要求拖過一半才換區；甩動被吸回最近角 | 畫中画、貼邊/平鋪、瀏海收纳、捲簾 | N11、C5；專利 US10203866B2 的 150 ms 投影（實施例）|
| 2 | 所有動畫都可被打斷：新輸入以「當下位置＋當下速度」重定目標；不要排隊、不要鎖輸入；每個屬性只保留一個（目標、速度）狀態 | 固定時長的緩動；動畫結束前忽略輸入；用 duration 當 API 參數；等彈簧「停穩」才接下一步 | 全部 | C2a–C2c、N1、N5、N3；Apple 10158（不要等 settling duration）[V] |
| 3 | 以指標減速取代懸停計時器：懸停展開、視窗瀏覽預覽、拖曳到瀏海上方的「意圖」都以減速尖峰觸發，停得快就偵測得快 | 固定 120–500 ms 的 dwell 計時器；用「游標停在某處多久」當意圖 | 瀏海 hover 展開、拖曳落點、捲簾條預覽 | C2d；專利的減速條件 [V]；現況見第 9 節（NotchHoverPolicy 是 0.12 s 計時器加位移與速度閘）；design-system §4.7 的 dwell.hoverExpand 0.12 s 是計時器，文件已計畫改（§6-14）|
| 4 | 回饋永遠在你自己的圖層：移動、貼齊預覽、捲簾動畫用覆蓋視窗或 CALayer 快照以顯示器刷新率繪製，真實視窗的 AX 寫入跟在後面（放手時提交，或低頻同步） | 讓視覺回饋等 AX 呼叫往返；用輪詢 AX 位置來做動畫 | 貼齊、捲簾、瀏海收纳、平鋪重排 | C1（延遲無所不在）；AX 往返是桌面版的延遲來源 [I] |
| 5 | 一比一跟手：拖曳時視窗或條帶以固定增益貼著手指／游標，保持抓取偏移；觸控板滑動用連續事件（捲動事件的 phase、precise delta，或 NSEvent.trackSwipeEvent 的連續回呼 [V]）驅動進度；必要時換手時保持速度連續 | 把視窗中心貼到游標；對拖曳位置做低通濾波；只靠離散的 swipe 事件（結束才通知）；每台裝置不同的增益 | 觸控板標題列手勢、平鋪捲動、側拉 | M2、M3、M4 |
| 6 | 滑動先過 hysteresis 再鎖方向；之後的決定用歷史而非最後一點 | 一按下就開始動畫或鎖方向；用最後一個事件的速度 | 標題列手勢 | M2；專案 hysteresis.pan = 8（design-system §4.5）|
| 7 | 並行辨識所有可能手勢：按下立刻給回饋（高亮），意圖明確後取消其餘；點按是「按下高亮、在區內放開才確認、拖出取消、拖回再高亮」，命中區外擴 | 為了等雙擊而延遲單擊的動作；mouseDown 就觸發不可逆動作；只用懸停提交 | 標題列（點擊、拖曳、雙擊、上滑）、瀏海、捲簾條 | M1、M5；專案文件 §4.7 的 tap.doubleWindow 說單擊先給按下回饋（只讀了文件，沒讀實作）|
| 8 | 手勢進行中朝最終狀態「長」：標題列上滑時視窗內容按進度逐步捲起；貼齊預覽框從目前外框朝目標長出去；游標靠近瀏海時島朝視窗鼓起；按壓捲簾條時略朝展開方向膨脹 | 到門檻才突然跳出的預覽；用計時器出現的預覽 | 捲簾、貼齊、瀏海 | C4 |
| 9 | 空間一致：捲簾與展開走同一條軸；收進瀏海與放回走同一路徑；Alt-Tab 清單的進出、Shift 反向動畫對稱；視窗瀏覽的縮圖從真實視窗位置長出、回到真實位置；平鋪捲動的進出方向固定 | 展開從另一個地方冒出來；收起往上、展開卻從下面來；跨顯示器或跨桌面回來時從錯的地方飛入 | 全部 | C3 |
| 10 | 邊界要軟：平鋪條帶到頭、視窗瀏覽到頭、拖曳視窗超出可放區域、視窗已到 App 的最小尺寸時，用橡皮筋阻力而不是硬停；兩個追蹤者之間換手也走平滑曲線 | 硬夾緊；分不出是 WindowShade 沒反應還是 App 拒絕縮小 | 平鋪、視窗瀏覽、貼齊、瀏海下拉 | C6 |
| 11 | 彈簧只用 response 與 damping：預設 100% damping；只有手勢本身帶動量朝向終點、或回彈本身是提示時才給 80–90%（bounce ≤ 0.2）；觸控板與滑鼠再收斂一些 | 為了活潑加彈；頻繁動作（每次切焦點、每步 Alt-Tab）加彈；用 duration 描述 | 全部 | N5–N8；HIG Motion（觸控板較收斂、頻繁互動少加動態）[V]；專案 Mac 上限 0.2 已符合 |
| 12 | 同一家族的行為：手勢觸發與鍵盤觸發的同一轉場必須看起來一樣（用同一彈簧令牌）；大視窗與小縮圖可用不同「質量」（response 略不同），但仍同一族 | 熱鍵走一條緩動、手勢走一條彈簧 | 全部 | N10、C8；質量差異是我的延伸 [I] |
| 13 | 快速移動的飛行（收進瀏海、側拉、甩出）對快照做動態拉伸或模糊，並依 Reduce Motion 關閉；120 Hz 上以顯示連結驅動、以經過時間算位置 | 只靠調快彈簧；忽略大位移每幀頻閃 | 瀏海收納、側拉、子母畫面 | C7 |
| 14 | 教學靠「動畫方向對齊手勢方向」與視覺線索：按捲簾按鈕的動畫方向 = 上滑手勢的方向；邊緣露出一小截鄰窗／被收起的窗暗示可捲動；側拉與捲簾條有可抓取把手；可互動元素在懸停時升起；明確說明只給會到處重複用的手勢，一次；每個手勢都要有選單或鍵盤替代 | 首次啟動就講完所有手勢；為偶爾使用的手勢設彈出提示 | 全部 | T1；HIG Gestures（多於一種方式、替代輸入）[V]；專案文件原則 11 已要求每條教學有次數上限 |
| 15 | 受保護狀態：全螢幕、遊戲、簡報、影片時，邊緣或瀏海手勢需要第二個明確動作才觸發 | 在全螢幕遊戲裡懸停就展開 | 瀏海、側拉、捲簾條 | 專利 Method 900；Tech Talk 801 的邊緣保護 [V]；映射到 Mac 是 [I] |
| 16 | 不劫持系統手勢：避開系統預設佔用的多指橫掃與捏合手勢（具體哪幾個由使用者的系統設定決定 [I]），標題列手勢限定在標題列範圍內 | 覆蓋 Mission Control、Spaces 手勢 | 觸控板手勢 | HIG Gestures（避免與存取系統 UI 的手勢衝突）[V] |
| 17 | 用「動作」而非「位置」判斷意圖：Alt-Tab 清單出現在靜止游標下時，不要因游標位置而改選取；游標真的移動了才把懸停當選取 | 覆蓋層一出現就被靜止游標偷走選取 | Alt-Tab 式切換器 | N11 的精神（意圖編碼在動作裡）；具體案例 [I] |
| 18 | 切換器的提交不等動畫：按下鍵就給回饋，放開修飾鍵就提交，Esc 當作「拖出取消」；快速點一下直接切到上一個，不需等覆蓋層 | 為了顯示覆蓋層而延遲提交 | Alt-Tab | C1、M1；鍵盤版的按下／放開分離 [I] |

### 8.3 瀏海活動（Dynamic Island 的 10194 → Mac 瀏海）

| # | 做 | 避免 | 依據 |
|---|---|---|---|
| a | 一個會變形的整體，不是一堆彈窗；各活動有自己的身分，同時屬於同一家族；多個活動時分開與合併、或輪播 | 每個活動各開一個視窗或浮層 | DI1、DI2、DI9；HIG（單一活動輪播）[V] |
| b | 內容與島同心，邊距均勻；非圓形內容以視覺質心對齊（模糊檢查）；區塊用內縮形狀或分隔線；Compact 緊貼瀏海、兩側等寬；Expanded 保持與 Compact 相同的相對位置，包住瀏海，不留額頭；展開高度避開兩種尺寸的分界 | 內容畫到邊、戳進角落；左右不對稱；在島的上方留一塊空白 | DI4–DI8；專案 §4.1、§4.5 已對應 |
| c | 提醒用「展開島」，不另開通知；只為必要更新提醒；動畫最長 2 秒；顯示器變暗或低電量時少做動畫 | 為每件小事展開；長動畫 | DI6；HIG Live Activities [V]；低亮度與電量的延伸 [I] |
| d | 彈性只放在島的黑色膠囊與周圍光暈，硬體缺口本身不動；視窗收進瀏海時，內容要像飛進去、住進那個空間 | 讓缺口看起來在變形；收進時只有淡出 | DI3 |
| e | 瀏海上的元素不指向瀏海：WindowShade 自己的覆蓋也不要畫箭頭或強調框指著它 | 在 App 或提示上畫指向瀏海的 UI | DI7 |
| f | 控制項放在它所控制的東西旁邊，畫結果不畫參數；階梯式深入：點 = 開關，點島 = 展開，按住拖曳 = 細調（手電筒的做法）。放到 WindowShade：在島裡畫一個迷你版排版，直接拖它來改視窗配置 | 用設定面板裡的滑桿調參數 | iOS 18 手電筒的 Apple 說明 [V]；推廣到視窗配置 [I]；專案 design-system 原則 7 已有 |

### 8.4 Liquid Glass 相關（材質層）

| # | 做 | 避免 | 依據 |
|---|---|---|---|
| a | 條帶、瀏海面板、提示浮窗的玻璃用系統元件；互動回饋用 NSGlassEffectView.effectIsInteractive；出現與消失走系統的 materialize 過渡，不用 alpha 淡入淡出 | 手畫高光；用透明度動畫模擬玻璃顯隱（專案 §4.7 的 fade 令牌包含「玻璃顯隱」，值得核對是否改走系統過渡）| LG3、LG4；文件 [V] |
| b | 靜止時安靜、互動（懸停／按下）時「升起」；Mac 觸控板與游標的效果比觸控收斂 | 常駐的強發光 | LG6；HIG Motion [V] |
| c | 失去焦點的視窗與其捲簾條退後（降低對比或收斂），不要加灰色遮罩 | 用額外的暗色蓋層標示非焦點 | BR2 |
| d | 控制項層用玻璃，內容層（視窗畫面、縮圖）不用；層上層不疊玻璃，改用填色、透明度與 vibrancy | 玻璃疊玻璃 | BR3；專案 V3 已定 |
| e | 減少動態效果時停用彈性屬性，改為淡入淡出或原地替換 | 只調小幅度 | BR4；專案 reduced 令牌已有 |

### 8.5 起始參數（拿來做手感試驗的起點，不是定值）

| 參數 | 來源值 | 性質 |
|---|---|---|
| 彈簧預設阻尼 | 100%（無過衝）| 803 N6 [V] |
| 帶動量的彈簧 | 80% damping，約 bounce 0.2（Music 滑動關閉）| 803 N7 [V] |
| 點按到滑動的 hysteresis | 約 10 點（iOS 觸控）| 803 M2 [V]；桌面指標門檻要自己量 [I] |
| 雙擊造成的單擊延遲 | 約 0.5 秒（照片縮放範例）| 803 M5 [V]；用來當「不能接受」的量級 |
| SwiftUI 預設彈簧 | response 0.5、dampingFraction 0.825 | Apple 文件 [V] |
| Live Activity 動畫上限 | 2 秒 | HIG [V] |
| 投影時間窗 | 150 ms | 專利實施例 [V]，需自己驗證 |
| 回主畫面／多工分界 | 投影大小約 30%、離底 ¼ 螢幕高、放手速度約每秒 ⅛ 螢幕高、方向帶 30 度 | 專利實施例 [V]，需依視窗與螢幕比例縮放 [I] |
| 減速率 | normal 與 fast 兩個常數 | Apple 文件只給名稱；0.998 與 0.99 為社群與專案常用值 [U] |

### 8.6 還需要原型驗證的問題 [I]

1. 滑鼠事件速率從 125 Hz 到 1000 Hz 不等，且帶雜訊：要先平滑再取減速尖峰，門檻如何隨事件率縮放。
2. 觸控板標題列手勢該用 NSEvent.trackSwipeEvent、捲動事件 phase，還是原始 NSTouch；各自在三指與四指被系統佔用時的行為。
3. macOS 系統慣性的減速曲線與 iOS 的 0.998 是否一致；若自己做慣性，要與系統捲動手感對齊。
4. 桌面上「投影終點」常常是離散的格位與視窗外框，多個終點近乎等距時，是否偏好「延續當前方向」的那個。
5. 120 Hz 與 60 Hz 外接螢幕混用時，同一動畫的頻閃感差異。

## 9. 與 WindowShade 現況對照（只列我讀過的證據）

已落地（[V]，檔案行號為本輪讀到的）：

- docs/design-system.md §2（第 51–78 行）的十二條原則已對應 803：原則 3 空間一致、4 跟手與可打斷（含「看加速度尖峰」）、5 彈簧（100% 阻尼預設）、6 投影、11 教學、12 動效與觸感同一性格。
- docs/design-system.md §4.6（第 334–358 行）：response／damping 令牌表；prototype/Core/FlickMotion.swift 第 151–177 行有 MotionSpring 令牌，第 492 行起 FluidMotion.rubberBand，第 507 行 FluidMotion.projection(velocity:decelerationRate:)，預設 0.998。
- 調用點：prototype/App/Notch.swift 第 3939 行以 0.99 投影；prototype/Core/ScrollStrip.swift 第 55 行 releaseDecelerationRate = 0.998、第 863 行用投影；prototype/Core/TrackpadGesture.swift 第 460 行 decelerationRate = 0.99。

尚未落地：

- 懸停展開仍是計時器加條件，不是 803 C2d 的加速度尖峰：prototype/Core/NotchHoverPolicy.swift 的 dwell 0.12 s、stillRadius 8 pt、sweepSpeed 600 pt/s，且 defaultEnabled = false（預設關；關著時是進來 0.12 秒就展開，見 prototype/App/Notch.swift 第 3839–3925 行）。design-system 第 366 行寫的 Notch.swift:1209–1236 行號已對不上現在的程式碼（那一段現在是 pointerPanel 與音量鍵處理）；文件寫的後續是改成看指針減速（§6-14）。對應本檔表 8.2 第 3 條。
- 玻璃顯隱目前列在 fade 令牌下（design-system §4.7），LG3 說玻璃是用調整折光出現，值得核對。

文件與來源對不上的地方（以來源為準，原檔未動）：

1. design-system.md 第 53 行與第 62 行把 iPhone X 手勢案例標為 fall2017 801。Apple 的 Designing for iPhone X（Tech Talk 801）談安全區與 Home 指示條，逐字稿沒有講者姓名也沒出現 Chan；Chan 官網的 iPhone X 項目連的是他 2017-11-03 的貼文。801 只能算相鄰資源，不能算 Chan 的講座。
2. 同一行寫「七个参考案例」，列出的只有六項；官網是 7 個連結（Liquid Glass 專案貼文與講座貼文各一）。
3. design-system.md 第 64 行把投影公式掛在 803 名下：逐字稿文字沒有公式（在投影片上，我沒讀到）；與社群轉錄一致但未對官方投影片驗證。
4. design-system.md 第 336 行把 stiffness＝(2π/response)² 與 damping＝4πζ/response 掛在 WWDC23 10158 名下：10158 逐字稿只說會有三條「bounce 與 duration 換成質量、剛度、阻尼」的公式（在投影片上），不是 response 與 damping ratio 的換算；response 換算的出處是社群程式碼（見 7.4）。第 355 行「bounce 超過 0.4 就夸張（10158）」我在逐字稿文字裡找不到對應句，可能在投影片上。這幾條都是 [U]。

## 10. 來源清單

Chan 本人：

- 官網 https://chankarunamuni.com （原始 HTML 已讀）
- 七篇貼文見第 2 節表格；貼文文字取自 fxtwitter 公開 API（https://api.fxtwitter.com/chan_k/status/<id>），x.com 本身回 402。

Apple 官方：

- WWDC18 803 https://developer.apple.com/videos/play/wwdc2018/803/
- WWDC23 10194 https://developer.apple.com/videos/play/wwdc2023/10194/
- WWDC25 219 https://developer.apple.com/videos/play/wwdc2025/219/
- WWDC23 10158 https://developer.apple.com/videos/play/wwdc2023/10158/
- Designing for iPhone X（Tech Talk 801）https://developer.apple.com/videos/play/tech-talks/801/
- Newsroom：https://www.apple.com/newsroom/2017/09/the-future-is-here-iphone-x/ ；https://www.apple.com/newsroom/2022/09/apple-debuts-iphone-14-pro-and-iphone-14-pro-max/ ；https://www.apple.com/newsroom/2025/06/apple-introduces-a-delightful-and-elegant-new-software-design/
- Support：https://support.apple.com/en-us/105001 ；https://support.apple.com/guide/iphone/turn-the-iphone-flashlight-on-or-off-iphf574afb44/18.0/ios/18.0
- HIG：https://developer.apple.com/design/human-interface-guidelines/live-activities ；…/motion ；…/gestures
- 文件：NSEvent.trackSwipeEvent、NSEvent.momentumPhase、NSEvent.pressure、NSGlassEffectView、NSGlassEffectContainerView（developer.apple.com/documentation/appkit/…）；SwiftUI Animation.spring(response:dampingFraction:blendDuration:)、GlassEffectTransition；UIKit UISpringTimingParameters、UIScrollView.DecelerationRate

第三方：

- Non-Strict WWDC Index（講者與片長）https://nonstrict.eu/wwdcindex/wwdc2018/803 ；…/wwdc2023/10194 ；…/wwdc2025/219
- Sheet 專案的彈簧換算 https://git.shadowfacts.net/shadowfacts/Sheet/src/branch/master/Sheet/Animation/FluidTimingCurve.swift
- 專利 https://patents.google.com/patent/US10203866B2/en

未打開原文的搜尋結果：2025-12 關於 Alan Dye、Steve Lemay 與 Chan 貼文的新聞（MacTech、9to5Mac、apfelpatient 等）；patentleaderboard（回 403）。

## 11. 未能驗證的清單

- 803 投影片 PDF 的程式碼、投影公式與彈簧換算的官方版本（檔案超過 10 MB，未下載）。
- 貼文內影片的內容（未下載、未觀看）。
- Flashlight 與 Liquid Glass 的設計動機之外的第一手說明；他本人的訪談、Podcast、部落格（沒找到）。
- UIScrollView 減速率 0.998 與 0.99 的官方數值。
- 專利門檻值在量產中的實際值；專利其他家族成員。
- 專利發明人「Chanaka G. Karunamuni」等同於 Chan Karunamuni（強烈暗示，無明說）。
- 2025-12 人事新聞細節。
- 第 8 節所有標 [I] 的桌面翻譯，都沒有做過實機或原型驗證。
