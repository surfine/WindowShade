# draft10 未來概念片修改

只動 `film/ws2-opus/src/future/**` 與這支片的畫面素材。B 站剪輯版見 `FIXES-v10.md`。沒有推送，沒有動 `main`。成片是 1080p30，`WS2FutureDraft`（源 60fps 半速）。配樂仍是 `public/music/future/ws2-future-mix.wav`（−16.0 LUFS / −4.0 dBTP），沒有重混。Neo 與午夜色 Air 仍在同一場 three.js。彈簧沒有新造。

成片：`out/future/gate/draft10.mp4`  
接觸表／靜幀：`out/future/stills/draft10-*.png`

## 第一層

### C-R2　展開輪廓

靜止仍是量到的洞（`hole()`）。展開只走 `grownPill`：一整塊不透明圓角矩形，頂邊貼進邊框蓋住洞，左右豎直，底角用稿上的圓角。沒有頸，也沒有肩下的耳狀底座。`src/future/film/notchPath.ts`。

實體洞比島窄，只靠螢幕貼圖會在頂邊露出窄頸；展開時 `island-cover` 用整島寬度蓋住洞肩（`stage.tsx` `syncCover`），`notch-cap` 在展開時關掉。顯示網格維持不打光、無 clearcoat。

靜幀：`out/future/stills/draft10-live.png`（穩態「外卖到了」；像素抽樣頂到底同寬 ≈520px）。寬鏡 `draft10-expanded.png`。

### C-N3　即時活動兩行被切

字只排在洞下面的安全區（`airContentArea`），不再用整島高度置中把標題頂進洞裡。主行「外卖到了」、副行「iPhone · 放在门口了」在穩態完整可見。

靜幀：`out/future/stills/draft10-live.png`。

### C-N2　解鎖被畫成一個圓

拿掉蓋在時鐘上的單圓掃描。Neo 膠囊裡是兩枚點：先亮「臉」，再亮「手機」。密碼框一直在，再進桌面。不畫臉。

靜幀：`out/future/stills/draft10-factors.png`。

### C-N7　鎖上時鏡頭離開劉海

拿掉朝鍵盤俯衝的鏡頭鍵（原 `A(855, 500)`）。走開／倒數／鎖上全程對準劉海與上緣。手機先在旁邊再走開。

靜幀：`out/future/stills/draft10-phone-leave.png`、`draft10-lock.png`。

## 第二層

### C-N1　開頭「它沒有」

字幕先是「窗口收进刘海」，接著「这台没有刘海」。鏡頭停在 Neo 上邊框。不等片尾。

靜幀：`out/future/stills/draft10-open.png`。

### C-N4　即時活動從 iPhone 來

旁邊手機先顯示同一則活動，島上副行寫明 iPhone。沒有把 CarPlay 加回來。

靜幀：`out/future/stills/draft10-live.png`（及 `draft10-live-phone.png` 若保留）。

### C-N5　口型與點頭是一條鏈

島上先讀到「放到左半屏」，再變成「放到左半屏？」並打勾，左半屏虛線同時出來，窗口才滑進左半屏。

靜幀：`out/future/stills/draft10-lip.png`、`draft10-nod.png`。

### C-N6　番茄鐘

收起仍在。休息時點一下，窗口回來，島上休息計時接著走。字幕「点一下就回来，休息照走」。

靜幀：`out/future/stills/draft10-pomo.png`。

### C-N8　結尾

兩台都是解開的桌面，島上同一則「外卖到了」。不是兩張鎖屏。片名 WindowShade 2。

靜幀：`out/future/stills/draft10-end.png`。

## 鏡頭表

`src/future/film/SHOTS.md` 每一鏡都寫了對哪一張設計稿，以及這一鏡的畫面要證明什麼。
