# draft12 未來概念片修改

只動 `film/ws2-opus/src/future/**` 與這支片的畫面素材。B 站剪輯版見 `FIXES-v12.md`。沒有推送，沒有動 `main`。成片是 1080p30，`WS2FutureDraft`。Neo 與午夜色 Air 仍在同一場 three.js。彈簧沒有新造。拼接用等長 PTS，禁止 `-c copy`。

實測響度：−16.1 LUFS，真峰值 −3.9 dBFS。

成片：`out/future/gate/draft12.mp4`（1080p30，1800 幀，約 60 秒）  
鏡頭表：`src/future/film/SHOTS.md`  
螢幕板：重渲 `public/future/plates/neo.mp4` 與 `air.mp4`。

對 v11 複審 `C11-*`。已核銷項寫保留。

## 靜幀

| 報告 | 路徑 | 片子時間 |
| --- | --- | --- |
| C11-05 收進 | `out/future/stills/draft12-tuck-10.png` | ≈00:10（draft 幀 300） |
| C11-02 確認 | `out/future/stills/draft12-ok-26.png` | ≈00:26（draft 幀 780） |
| C11-03 手機 | `out/future/stills/draft12-phone-31.png` | ≈00:31（draft 幀 930） |
| C11-04 島內 | `out/future/stills/draft12-island-35.png` | ≈00:35（draft 幀 1050） |
| C11-06 片尾 | `out/future/stills/draft12-end-55.png` | ≈00:55（draft 幀 1650） |

## T11-01　長幀

同 B 站：`setpts=N/30/TB`，不 `-c copy`。

## C11-02　確認文案進成片

候選主行「等你确认」，確認後主行「已确认 · 正在落位」。`glide` 接到 `ok`（1440）後很短一截（1488）。必重渲 Neo 板。保留點頭本身，不刪確認。

## C11-05　開頭先收窗

先讓備忘錄收進膠囊，字幕「窗口收进刘海」對準這段；再停上邊框說「这台没有刘海」。Neo 段延到 720 再交 Air。鏡頭拉開看得見窗與膠囊。

## C11-03　手機完成度

對齊 B 站 Remote：圓角機身、厚度、側鍵，同源即時活動。不撤手機來源。

## C11-04　島內排版

展開內邊距收緊（少空額頭），不改已核銷的島外形／蓋板寬度公式。

## C11-06　片尾第一幀無鎖屏

保留 3300 硬切。`lockedAt` 在片尾前兩源幀已是桌面，右側 Air 不得帶鎖屏時鐘。

## A11

概念起伏較小；仍略減 SFX duck。不簽好聽。

## 保留（C11-01）

標題安全區、展開島無超寬橫條、倒數可讀、鎖滿硬切主路徑、兩因素、即時活動來源、番茄鐘點一下回來：保留。
