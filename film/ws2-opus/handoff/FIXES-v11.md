# B 站版 v11

只改 `film/ws2-opus/` 裡 B 站這一條（與共用螢幕板）。概念片見 `FIXES-draft11.md`。沒有推送，沒有動 `main`。成片是 1080p30，沒有 4K。配樂檔 `public/music/ws2-opus-mix.flac` 沒改，USDZ Air 和設計稿彈簧仍在。

成片：`out/gate/v11-draft.mp4`  
`@remotion/cli` 4.0.484，`remotion render src/index.ts WS2OpusDraft`，`--gl=angle --codec=h264 --crf=18`。  
1920×1080，30 fps，1609 幀，約 53.6 秒。螢幕先渲 `WS2Screen`（2320×1502、60 fps、3217 幀）換成 `public/screen/plate.mp4`，再鋪上這支片子。

實測響度：−16.3 LUFS，真峰值 −3.7 dBFS（與 v10 同級；混音檔未再壓）。

對 v10 複審 `B10-*` / 第六節驗收。上一輪已核銷項（標題安全區／藥丸／相機停住的核銷邊界／開場擁擠／iPhone 載體／引文時機／兩因素／實時活動字／番茄鐘返回／片尾雙機桌面）沒有改回去——其中「動作時鏡頭停住」按 B10-04 改為保留空間參照的取景，其餘不變。

## 靜幀

| 報告 | 路徑 | 片子時間 |
| --- | --- | --- |
| B10-01 三声回饋 | `out/gate/stills/v11-tone-19.png` | ≈00:19（draft 幀 584） |
| B10-02 引文結果 | `out/gate/stills/v11-cite-26.png` | ≈00:26（draft 幀 780） |

## B10-01　畫這一筆改變什麼（18–22s）

對 `docs/design-drafts/指挥模式.html`：曲線抬手後島／手機顯示「三声 · high」「下一轮」類既有回饋，再說一句 → 草稿 → 播放發出。

改 `src/timeline.ts`（`CONDUCT_TONE`）、`src/scene.ts`（valley STROKE + tone phase）、`src/Film.tsx` Remote 與島 stroke 內容。

## B10-02　工作成果不是灰線（24–28s）

`src/parts/Mock.tsx` `DraftWin`：三處可讀短句，變藍時看得出改了什麼；島「引文已核对」對得上畫面。

## B10-03　點頭確認可辨（29–35s）

候選與確認狀態分開；字幕改向「静音操作」（copy-guide），少用「它懂你」。見 `src/cut.ts` 標題與 `src/parts/Island.tsx`。

## B10-04　取景尺度

收起／放回／落位／啟動台：特寫前後保留能看全窗口與目標區的景別；不改回「動作時鏡頭停住」。改 `src/camera.ts` framing（near／close 收斂）。
