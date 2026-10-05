# 交給 ChatGPT：複審 WindowShade 2（v11 / draft11）

製作先停。這次只審，不改片、不渲染、不提交。

上一輪審的是 `v10` / `draft10`（報告在 `prior-review/`）。作者說已按那份報告整改，打出 `v11` / `draft11`。Aaron 看過最新草稿後的判斷：**問題還是很多**——聲音忽大忽小；UI 像山寨、沒有蘋果的嚴謹；動效廉價，遠不如 [Mark View](https://www.markview.work/projects) 那般絲滑入扣，「土到掉渣」。請以成片為準複審，不要只信作者的 `FIXES-*.md`。

## 審片前先做（強制）

1. 讀完 [`study/chan-karunamuni-curriculum.md`](study/chan-karunamuni-curriculum.md)，並打開裡面的兩支 WWDC 官方影片學完再寫結論：  
   - Designing Fluid Interfaces（WWDC18 / 803）  
   - Design dynamic Live Activities（WWDC23 / 10194，含 Dynamic Island）  
2. 打開 [`study/mark-view.md`](study/mark-view.md) 與 https://www.markview.work/projects ，建立「絲滑入扣」的標杆。  
3. 再讀本包 `rulings.md`、`state.md`、設計稿、`copy-guide.md`。

沒有走完學習步驟就給「動效／UI 品質」結論，視為審片不合格。

## 只看這兩支

| 片 | 檔 | 規格 |
|---|---|---|
| B 站剪輯版 | `films/bilibili-v11.mp4` | 1920×1080、30 fps、約 53.6 秒 |
| 未來概念片 | `films/concept-draft11.mp4` | 1920×1080、30 fps、約 60.3 秒 |

SHA-256 見 `source-manifest.json`。對照的成功片說明見 `promo-README.md`。更早的過程片不要當現況。

## 先讀

1. [`rulings.md`](rulings.md)：Aaron 的決定和原話。衝突時以較晚的為準；**最新一條是 v11「聲音忽大忽小／山寨 UI／動效土到掉渣」**。  
2. [`state.md`](state.md)：分支、成片路徑、模型與音樂。  
3. 上一輪報告：`prior-review/WindowShade-v10-review.md`。作者整改聲稱見 `FIXES-v11.md`、`FIXES-draft11.md`——逐條核對成片有沒有真的修到。  
4. 設計稿：`design-drafts/README.md`，再打開片子用到的 HTML。形狀、彈簧、開口、收起以稿的畫面為準。  
5. 概念片鏡頭表：`SHOTS.md`。  
6. 文案：`copy-guide.md`。  
7. 音量客觀證據：`audio/*-level.txt`（每秒 RMS；B 站片短時可有約 8 dB 跳變）。**仍必須自己聽**，對上畫面切點與壓音。

## 審的時候特別看（本輪優先）

### A. 聲音是否忽大忽小

- 全片聽感是否平穩、正向；有沒有段落突然變響／變悶。  
- 是否為了「重點段落」過度 ducking／UNDER，造成泵感。  
- 對照 `audio/bilibili-v11-level.txt`、`audio/concept-draft11-level.txt` 的最大跳變秒點，寫明時間與主觀感受是否對得上。

### B. UI 是否像山寨、缺蘋果嚴謹

用 Chan 的尺子（見 study）：同心邊距、島與硬體洞一體、字重與圓角家族、無假描邊／廉價陰影／貼紙感。對設計稿逐鏡，不要用「功能演示清楚了」當過關。

### C. 動效是否廉價（對 Mark View + Fluid Interfaces）

- 是行為驅動還是關鍵幀表演？可打斷嗎？動量連續嗎？  
- 鏡頭／島／窗口／字幕是否同秒搶戲？  
- 收放、展開、確認是否「入扣」，還是卡點簡報？

### D. 上一輪與調性

- v10 報告的 P0／P1 與 B10／C10 聲稱項：成片有沒有真清零。  
- 「CIA／線民」監視感是否還在；能不能發上網。  
- 不要提議稿外新交互。

## 做完的樣子

一份意見，兩支片分開寫。每條寫：時間點、畫面或聲音上看到什麼、對哪一張設計稿或哪一條 Chan／Mark View 尺子、作者對照表有沒有聲稱修到、成片實際有沒有修到。

建議結構：

1. **總判**：能不能發上網（通過／有條件／不通過）。  
2. **學習應用**：用 3–6 條寫明你如何把 Fluid Interfaces／Dynamic Island 理論用到本片判決（禁止空話）。  
3. **聲音**：忽大忽小是否成立，列時間點。  
4. **UI 嚴謹度**：山寨感來源（島形、字、層級、機身、螢幕）。  
5. **動效品質**：對 Mark View 的差距，列時間點。  
6. **上一輪未清零**／**本輪新問題**。  

沒看的段落寫明沒看。不要附新渲染，不要改工程。
