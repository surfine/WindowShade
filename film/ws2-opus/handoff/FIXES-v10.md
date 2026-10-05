# B 站版 v10

只改 `film/ws2-opus/` 裡 B 站這一條，沒有動 `src/future/**`。成片是 1080p30，沒有 4K。配樂檔 `public/music/ws2-opus-mix.flac` 沒改，USDZ Air 和設計稿彈簧仍在。

成片：`out/gate/v10-draft.mp4`  
`@remotion/cli` 4.0.484，`remotion render src/index.ts WS2OpusDraft`，`--gl=angle --codec=h264 --crf=18`。  
1920×1080，30 fps，1609 幀，約 53.8 秒。螢幕先渲 `WS2Screen`（2320×1502、60 fps、3217 幀）換成 `public/screen/plate.mp4`，再鋪上這支片子。

實測響度：−16.4 LUFS，真峰值 −3.7 dBFS。積分響度在 −16。AAC 編碼後真峰值比 −4 dBTP 高出 0.3 dB，混音檔本身沒有再壓。

接觸表：`out/gate/v10-contact-sheet.jpg`

## 靜幀

| 報告 | 路徑 | 片子時間 |
| --- | --- | --- |
| B-R2 展開島，對設計稿 M1 | `out/gate/v10-result.png` | 00:27 |
| B-R2 / B-N4 島上的候選 | `out/gate/v10-island.png` | 00:31 |
| B-R1 標題不再被銀邊切開 | `out/gate/v10-title.png` | 00:12 |
| B-R1 後段同一條 | `out/gate/v10-title-46.png` | 00:46 |
| B-N1 開場擠滿 | `out/gate/v10-open.png` | 00:01 |
| B-N2 手機上的草稿 | `out/gate/v10-phone.png` | 00:21 |
| B-N3 引文結果 | `out/gate/v10-result.png` | 00:27 |
| B-N5 島裡的終端縮圖 | `out/gate/v10-card.png` | 00:06.5 |
| B-N6 片名 | `out/gate/v10-wordmark.png` | 00:50 |

## B-R2 / P0 展開後的輪廓

`src/motion/notchPath.ts`。靜止仍是量出來的硬體洞（肩圓 + 底圓）。展開後改成一塊不透明圓角矩形：頂邊貼齊螢幕上沿並蓋住洞，左右在展開寬度上豎直，只倒底角。沒有頸，也沒有肩下兩段四分之一圓外撇。填色是取樣黑。螢幕仍不打清漆。

00:27 的島是平頂藥丸，「引文已核对 / 改了 3 处 · 文章草稿」。00:31 特寫是同一塊藥丸，字是「左半屏 / 文章草稿」。

## B-R1 / P0 標題被銀邊切開

`src/camera.ts` 的 `clearTitle` 每一幀都把機身上緣推到標題帶下面。中文一行和英文一行都在暗背景上，不跨玻璃和金屬。00:12「拖到刘海，选个位置」、00:33 一帶「不出声，点头就照做」、00:46「回来看一眼，窗口都在」、片尾片名，抽幀都在機身外面。

## B-R3 / P1 鏡頭和界面搶

`src/camera.ts`。收起、放回、島展開、窗口變形時鏡頭停住，dolly 只走在兩拍之間、主角已經停穩之後。同一時刻一個主角。開場、畫一筆、說一句、讀口型、點頭這幾鏡整段都停住。

## B-N1 開場要擠滿

`src/scene.ts`。開場那一扇終端改成幾乎鋪滿螢幕（`OPEN_TERM`），旁邊的備忘、聊天、音樂從母帶第 1400 幀就在，收起之前桌面是堆滿的。00:01 的畫面和字幕「窗口太多，桌面挤满了」是同一件事。鏡頭拉近，鍵盤只留一條。

## B-N2 / B-N3 畫一筆，說一句

不在 Mac 觸控板上畫。照《指揮模式》：畫面左側的 iPhone，觸控區畫一筆，側邊按鈕說一句，鬆開是草稿，播放鍵發出去。

`src/timeline.ts` 的 `CONDUCT_IN` → `CONDUCT_TALK` → `CONDUCT_DRAFT` → `CONDUCT_SEND` → `CONDUCT_RESULT`，三處引文在 `CONDUCT_MARKS`。這一段裡走完草稿、發出、結果，不把「核对三处引文」空掛十秒。島上先是「核对三处引文 / 草稿 · 播放键发出去」，發出後是「发出去了」，結果是「引文已核对」。藍色引文標記在這一段的文章裡出現（`src/parts/Mock.tsx`），不留到後一段才看見。

靜幀：`v10-phone.png`（草稿）、`v10-result.png`（三道藍）。

## B-N4 口型與點頭

一條鏈：島上先給出可讀的候選「左半屏 / 文章草稿」，點頭回正之後窗口才動（`WINDOW_MOVE = NOD_DONE + 14`）。沒有假臉，點頭是島上的 AirPods。00:31 的特寫是候選還在、窗口還沒動。

## B-N5 放回的縮圖

`src/parts/Island.tsx` 的 `card`。島裡那張縮圖是同一扇終端：紅綠燈、標題「終端」、`$ swift build`、`Compiling WindowShade`、`[132/186] Notch.swift`。飛回去的也是這扇。靜幀 `v10-card.png`。

## B-N6 片尾

`WORDMARK_AT` 改到片尾這一鏡的第一幀（曲子第 98 拍），停到淡出，不壓在上一段標題上。`WindowShade 2` 用章節標題的 1.45 倍，網址 `windowshade.aaronlau.me` 縮小、變淡，當次要的一行。靜幀 `v10-wordmark.png`。
