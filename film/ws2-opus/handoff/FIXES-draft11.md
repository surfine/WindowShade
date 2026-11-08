# draft11 未來概念片修改

只動 `film/ws2-opus/src/future/**` 與這支片的畫面素材。B 站剪輯版見 `FIXES-v11.md`。沒有推送，沒有動 `main`。成片是 1080p30，`WS2FutureDraft`（源 60fps 半速）。配樂仍是 `public/music/future/ws2-future-mix.wav`（−16.0 LUFS / −4.0 dBTP），沒有重混。Neo 與午夜色 Air 仍在同一場 three.js。彈簧沒有新造。

成片：`out/future/gate/draft11.mp4`（1080p30，1800 幀，約 60 秒）  
接觸表／靜幀：`out/future/stills/draft11-*.png`  
鏡頭表：`src/future/film/SHOTS.md`  
螢幕板：重渲 `public/future/plates/air.mp4`（`WS2FuturePlateAir`）。  
實測響度：−16.0 LUFS，真峰值 −4.0 dBFS。

對 v10 複審 `C10-*` / 第六節驗收。上一輪已核銷項（標題安全區以外已核銷的 B 站項、兩因素、實時活動字、番茄鐘返回、片尾雙機桌面）沒有改回去。

## 第一層（P0）

### C10-01　展開島上方更寬黑橫條（00:35）

根因：`island-cover` 比螢幕貼圖 `grownPill` 更寬，合成直角台階。

`src/future/film/stage.tsx`：蓋板半寬與 `grownPill` 同一公式（outer-hole `perPt` × grownPill half × 0.93），深度只蓋洞高／需要蓋的相位（alert／share／row／face）；ticks 倒數段不加蓋板，免得蓋住數字。

靜幀：`out/future/stills/draft11-island-35.png`。頂邊與內容面同寬，無左右伸出硬橫條。

### C10-02　概念片標題穿銀邊（00:08、00:45）

B 站有 `clearTitle`；概念片補同等安全區。`src/future/film/shot.ts`／`Film.tsx`：每一幀把機身上緣壓到中文標題帶下面。不靠縮字。

靜幀：`draft11-title-08.png`、`draft11-title-45.png`。

### C10-03　剛鎖上同一鏡自動回桌面（00:53–00:55）

`Screen.tsx`／`island.ts`：`lockedAt` 停滿到源幀 3300，再硬切片尾雙機桌面。禁止連續同機疊化自解鎖。

靜幀：`draft11-lock-54.png` → `draft11-end-55.png`／`draft11-end-56.png`。

### C10-04　倒數入畫但不可讀（00:51–00:53）

Air 加寬島：左翼「鎖 + 动一下就取消」、右翼大號數字（字避開實體洞中央）。重渲 `public/future/plates/air.mp4` 後成片才會帶上（概念片吃預渲板，不是即時 Screen）。

靜幀：`draft11-count-52.png`、`draft11-plate-count.png`。

## 第三層（表達 + CIA 調性）

### C10-05　開頭動作承擔「窗口收进刘海」

先片內窗口收進，再切「这台没有刘海」。不是黑屏空標題。

靜幀：`draft11-open-02.png`、`draft11-tuck-10.png`。

### C10-06　手機道具對齊 B 站 Remote 級別

鈦邊 iPhone 先顯示同源即時活動，再進島。保留同源活動，不另造交互。

### C10-07 + 調性　靜音操作、可辨確認

縮短候選空等。字幕走「静音操作」语境，少用「它懂你」。候選寫「等你確認」，點頭後「已確認 · 正在落位」。仍演刷臉／口型／點頭／走開就鎖，但每次服務看得懂的任務。不改深色舞台、不換配樂、不加未核安全承諾。

靜幀：`draft11-lip-22.png`。
