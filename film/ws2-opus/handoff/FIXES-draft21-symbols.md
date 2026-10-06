# 符號方向驗收：overlay 為什麼是廢圖、怎麼修、證據在哪

日期：2026-10-06　範圍：`film/ws2-opus`

## 1. 上一版 overlay 為什麼讀不出東西（根因）

`overlay-checkmark.png` 只畫出一條左下到右上的細斜線，既不是官方的勾、也不是我們的勾。
根因不在路徑，在**我自己寫的那支光柵器**：

```python
acc = Image.new('1', (K, K), 0)              # 1-bit 圖
ImageDraw.Draw(m).polygon(pts, fill=1)       # 1-bit 上 fill=1
acc = ImageChops.logical_xor(acc, m)         # 反覆 XOR
```

PIL 的 `ImageDraw.polygon` 遇到 `mode == '1'` 時，`fill=1` 會被寫成 1-bit 的「0」，
所以每一條子路徑畫出來都是空的；`logical_xor` 累積下來只剩外框的殘留像素，
看起來就是一條斜線。實測（220×220 方框）：

| mode | fill | 畫完的墨跡 |
|---|---|---|
| `1` | 1 | `histogram()[:2] = [11919, 36481]` 反了 → 墨跡其實是 **0** |
| `L` | 255 | `[11919, 0]` → 墨跡 36481 ✔ |
| `L` | 1 | `[11919, 36481]` → 墨跡 36481 ✔ |

也就是說：**只要 mode 是 `1`，`fill=1` 就等於沒填**。這條產線從頭到尾都是壞的，
它印出來的任何判定（包含「方向正確」）都不能算數。

## 2. 修法：不比手算的點陣，比兩邊都跑生產路

`tools/compare-symbols.py` + 新 composition `WS2FutureSymbolOverlay`
（`src/future/film/SymbolOverlayQA.tsx`）：

1. **下半格**＝本專案生產用的 `<Sym>`（`src/future/glyphs.tsx`）畫成黑字白底 480 px。
   走 Remotion，跟片子同一條渲染路。
2. **上半格**＝AppKit 官方點陣（`tools/official-symbol.swift` 產的 PNG）。
3. Python 只做「切圖、二值化、等比縮放到高 256、貼色」——**不做任何幾何換算**，
   不再發生「官方那半被同一個 bbox 正規化吃掉」。

判讀：黑＝重合、紅＝只有官方、藍＝只有我們。

### 結果（IoU，等比以高對齊）

| 符號 | IoU | 官方墨跡比例 | 我們的墨跡比例 |
|---|---|---|---|
| faceid | 0.9739 | 1.0000 | 1.0000 |
| checkmark | **0.9858** | 1.0281 | 1.0250 |
| checkmark.circle.fill | **0.9925** | 1.0000 | 1.0000 |
| xmark.circle.fill | 0.9774 | 1.0000 | 1.0000 |
| iphone | 0.9714 | 0.6289 | 0.6292 |
| lock.fill | 0.9740 | 0.7070 | 0.7083 |
| lock.open.fill | 0.9852 | 1.0323 | 1.0312 |

七顆全部 > 0.97，且兩邊墨跡的**長寬比**逐顆對得上（差 < 0.002）。
方向反了的話勾那顆會掉到 0.07 左右（先前量過），所以這組數字同時證明了方向。

## 3. 成品緊凑裁切（NEAREST ×8，不縮、不插值）

`island-40.png` / `after-223.png` 這兩張**不能當證據**，實測如下：

| 檔 | 內容 | 綠色墨跡 |
|---|---|---|
| `out/future/symbols/after-223.png` | WindowShade App 視窗（不是島） | 只有一顆 44 px 的綠點 |
| `out/future/symbols/sym-callsites/island-40.png` | MacBook Neo 桌面 | 484 個散落的單像素，沒有字形 |

所以裁切改從 **`out/future/symbols/islandqa.png`**（`WS2FutureIslandQA`，用片子那支
`IslandLayers` 1:1 渲染的驗收台）：

| 位置 | 這是什麼 | 綠色墨跡 bbox |
|---|---|---|
| row 1（y306–612，f660） | 已收進劉海：綠格裡的勾 | x893–1034, y335–364 |
| row 3（y918–1224，f1500） | 已確認：純勾 `Check ring={false}` | x912–1001, y949–975 |

兩張都裁成 NEAREST ×8/×14，眼睛看得出是 `✓`（短臂在左下、長臂往右上）。

> 附帶找到一個驗收台自己的 bug：`IslandQA` 的列標籤與島內容**對不上**。
> y0 那一列的標籤寫 `f440 認人（解鎖）`，但島畫的是 f660 的「已收進劉海」；
> 綠墨跡實際落在 row 1（y335）而不是 row 0。標籤是 row 自己的，
> 但島的位置往下偏了一列——量測時要用綠色墨跡的實際 y，不要相信列標籤。

## 4. Face ID：已是真符號

`islandqa.png` row 0（f440）的島：左邊是官方 `faceid`、右邊是官方 `iphone`，
兩個都是 `symbols.ts` 那批向量（`tools/gen-symbols.mjs` 從 macOS 符號資料抽的），
不是手畫。證據見 `evidence-sheet.png` 右下那格。

## 5. 這一批產物

| 檔 | 內容 |
|---|---|
| `out/future/symbols/evidence-sheet.png` | **交付用**：疊圖 ×3 ＋ 成品裁切 ×8 ＋ Face ID |
| `out/future/symbols/overlay-*.png` | 七顆符號的紅藍疊圖（256²） |
| `out/future/symbols/overlay-scores.json` | 上面那張 IoU 表 |
| `out/future/symbols/film-frames/` | 片子實幀 f655 / f1500 / f1880 / f2100 / f2200 / f3050 |
| `tools/compare-symbols.py` | 疊圖比對（新） |
| `tools/evidence-sheet.py` | 拼交付圖（新） |
| `src/future/film/SymbolOverlayQA.tsx` | 疊圖用的上下兩格（新） |
| `src/future/film/SymbolCallsites.tsx` | 三個呼叫點 1:1（新） |

## 6. 還沒過的

- **iPhone 在鏡頭裡的位置**：`phoneAt` 已經從 `dx: -0.08` 退到 `-0.12`
  （材質：metalness 0.78 / roughness 0.26–0.42 / envMapIntensity 1.45）。
  但 f1880 這一幀整張提亮後仍**看不到手機**——`live` 段的鏡頭（zoom 2.6、focus
  `A(855, 80)`）看向 Air 的右半，手機被推到畫面外。要決定：是把鏡頭放寬，
  還是手機再進來一點。這一條沒定案前不開 4K。
