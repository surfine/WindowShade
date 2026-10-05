# B 站版 v12

只改 `film/ws2-opus/` 裡 B 站這一條（與共用螢幕板）。概念片見 `FIXES-draft12.md`。沒有推送，沒有動 `main`。成片是 1080p30，沒有 4K。USDZ Air 和設計稿彈簧仍在。

成片：`out/gate/v12-draft.mp4`  
`@remotion/cli` 4.0.484，`remotion render src/index.ts WS2OpusDraft`，`--gl=angle --codec=h264 --crf=18`。  
1920×1080，30 fps，1609 幀，約 53.6 秒。螢幕先渲 `WS2Screen` 換成 `public/screen/plate.mp4`，再鋪上這支片子。分塊拼接用 `scripts/concat-equal-pts.sh`（`setpts=N/30/TB`，禁止 `-c copy`）。

實測響度：−16.4 LUFS，真峰值 −3.7 dBFS。

對 v11 複審 `T11` / `A11` / `B11`。上一輪已核銷項沒有改回去。

## 靜幀

| 報告 | 路徑 | 片子時間 |
| --- | --- | --- |
| B10-01 三声 | `out/gate/stills/v12-tone-19.png` | ≈00:19（draft 幀 570） |
| B11-02 引文 | `out/gate/stills/v12-cite-26.png` | ≈00:26（draft 幀 780） |
| B11-04 取景 | `out/gate/stills/v12-frame-30.png` | ≈00:30（draft 幀 900） |
| B11-03 窗框 | `out/gate/stills/v12-win-33.png` | ≈00:33（draft 幀 990） |
| B11-04 落點 | `out/gate/stills/v12-frame-34.png` | ≈00:34（draft 幀 1020） |

## T11-01　交付檔長幀間隔

根因：分塊後 `ffmpeg -c copy` 把每塊最後一幀拉長。拼接改為解碼 + `setpts=N/30/TB` + `-r 30`，每源幀等長 1/30s，不插幀、不升 60fps。

## A11　28–33s / 41–45s 泵感

聽過後減 UNDER：低 2 dB、低通約 4 kHz、進出約 0.5 s；SFX duck 約 2.5 dB。重跑 `scripts/score.py`。不簽「已好聽／達到 Mark」。禁止整首只靠 loudnorm 交差、禁止真靜音。

## B11-02　引文成果對得上「改了 3 处」

`DraftWin` 三處短句 + 出處一行；變藍時看得出核對哪一句。島「引文已核对／改了 3 处」對同一畫面。

## B11-03　粗白高亮

去掉窗外大圓角白框。焦點改窗內同心 inset，圓角與窗一致。

## B11-04　收放／確認取景

`tuck`／`back`／`lips` 改 `medium`，窗下緣與左半屏落點在畫內。動作時鏡頭仍可停；不加搖鏡。

## B11-05　草稿窗完成度

標題下列工具列，正文加密度，引文帶出處。不把工時花在轉電腦。

## 保留（C11-01／核銷表）

標題安全區、展開島無超寬橫條、倒數可讀、鎖滿硬切、兩因素、即時活動來源、番茄鐘點一下回來：保留。
