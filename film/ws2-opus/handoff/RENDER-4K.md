# B 站版 4K60 母帶（`out/gate/v14-4k.mp4`）

Aaron 點頭之後出的第一支 4K。內容與已驗收的 1080p30 草稿 `out/gate/v14-draft.mp4`
（＝複審包裡的 `films/bilibili-v14.mp4`）是**同一支剪輯**，這一輪只提高解析度與幀率，
沒有動任何畫面、文案、彈簧、音軌。

| 項 | 值 |
| --- | --- |
| Composition | `WS2Opus`（`src/Root.tsx`） |
| 輸出 | **3840×2160、60 fps、3217 幀、53.617 秒** |
| 渲染方式 | `--scale=2`（comp 是 1920×1080／60 fps，乘 2 出 4K） |
| 編碼 | H.264 High@L5.2、`crf=18`、`yuvj420p`（與 1080p 版相同的色彩處理，`color_range=pc`） |
| 大小 / 碼率 | 29 522 729 bytes ／ 約 4.1 Mbps 視訊 |
| SHA-256 | `6f162ccddf6166cae5840a1c9fef1244fa409a165b6f4737982a582db6491ba6` |
| 交付副本 | `~/Downloads/WindowShade-bilibili-v14-4K60.mp4`（同一個檔） |

## 怎麼渲的（可重跑）

```bash
cd film/ws2-opus
# 1) 4 塊平行，每塊 805 幀（最後一塊 802 幀；3217 = 805×3 + 802）
for i in 0 1 2 3; do
  s=$((i*805)); e=$((s+804)); [ $e -gt 3216 ] && e=3216
  npx remotion render src/index.ts WS2Opus out/gate/v14-4k-chunks/K-$i.mp4 \
      --frames=$s-$e --scale=2 --gl=angle --codec=h264 --crf=18 \
      --concurrency=1 --timeout=240000 &
done; wait
# 2) 等長 PTS 拼接（禁 -c copy，理由見 scripts/concat-equal-pts.sh）
FPS=60 bash scripts/concat-equal-pts.sh out/gate/v14-4k.mp4 out/gate/v14-4k-chunks/K-*.mp4
```

四塊平行在 10 核機器上約 **14 分鐘**（05:00→05:10 之間完成，單塊平均約 6 分鐘；
單進程實測約 0.43 s/幀，120 幀基準 56.8 秒）。

## 驗了什麼

| 檢查 | 結果 |
| --- | --- |
| 解析度 / 幀率 / 幀數 | 3840×2160、60/1、3217 幀（四塊 805+805+805+802 相加相符） |
| 相鄰 PTS | 全部 1/60 秒（0.016667／0.016666）；非 1/60 的間隔 **0** 個；末格 53.600 秒 |
| 全片解碼 | `ffmpeg -v error -i … -f null -` 無輸出 |
| 全黑幀掃描 | `blackdetect=d=0.05` 無輸出 → 拼接沒有掉出黑幀 |
| 塊邊界 | 母帶 f804/f805/f1609/f1610/f2414/f2415 與對應塊自己的首／末幀比對：PSNR 43.2–55.1 dB（只差第二次編碼） |
| 與已驗收草稿同一支片 | 草稿 f k ↔ 母帶 f 2k（4K 降到 1080p 後比）：PSNR 34.2–40.4 dB；最後一格 54.6 dB |
| 音訊 | 整合響度 **−16.3 LUFS**（與草稿同值）、真峰值 −3.9 dBFS（草稿 −3.7）、LRA 4.2 LU |
| 音訊逐秒 | 與草稿比：整體 RMS −18.75 / −18.76 dBFS；每秒最大差 0.73 dB、平均 0.145 dB（53 秒中只有 3 秒差 >0.5 dB，來自多一次 AAC 世代） |
| 影音起點 | 兩條流 `start_time` 都是 0.000000 |

## 已知取捨（與 1080p 版同源，沒有新增）

- **多一次編碼世代**：塊是 crf18 的 H.264，拼接時再編一次 crf18（`concat-equal-pts.sh` 禁用
  `-c copy`，因為它會把塊尾幀拉長）。要免這一代需要改拼接腳本走無損中間檔。
- **容器比視訊長**：音訊 53.803 秒、視訊 53.617 秒，尾端多約 0.19 秒音樂；這是拼接時
  AAC 逐塊補齊的結果。已驗收的 1080p 草稿同一現象（音訊 53.931 秒），這一支還比較短。
- **`yuvj420p` / `color_range=pc`**：與 1080p 版完全相同。上傳平台若忽略 full-range 標記，
  深色漸層可能被壓得比母帶更黑；這是既有交付的共同特性，不是這一輪新增。
- 碼率約 4.1 Mbps 是 crf18 對這支片（大量靜止深色畫面）的結果，不是設定的上限。
  若平台二壓有顧慮，要另出一支高位率母帶（例如 crf 12 或 CBR 25 Mbps）。
- 這一輪沒有動豎屏／Phone／Slots 那幾支，也沒有動概念片。
