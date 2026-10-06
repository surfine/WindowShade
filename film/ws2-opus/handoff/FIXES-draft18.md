# FIXES-draft18 — 概念片（WS2Future）本輪整改

對象：`out/future/gate/draft18.mp4`（1920×1080、30 fps、1800 幀，源 60 fps 半速）。
螢幕板先重渲：`public/future/plates/neo.mp4`（1408×882）、`air.mp4`（1710×1108），皆 30 fps 1800 幀。

## 1. 壁紙：Air 要用 MacBook Air 自己的那張（本輪主修）

**前情**：A16-04 那一輪我把 Air 換成 `Mac Purple`，那也是**錯的**——Mac Purple 不是 Air 的桌布。

**查證**（2026-10-06）：`Mac Blue / Mac Pink / Mac Purple / Mac Yellow` 是 **MacBook Neo 自己那套彩色桌布**
（泡泡線條拼出 "Mac" 字樣，隨 MacBook Neo 首發，macOS 26.4 才下放給其它 Mac）。
Air 的桌布是 **macOS 26 預設那張波浪**（NeptuneOne），有淺/深兩版跟著外觀切換。

- 來源檔（本機）：`/System/Library/ExtensionKit/Extensions/NeptuneOneWallpaper.appex/Contents/Resources/TahoeDark.heic`（6016×6016）
- 匯出：`sips -s format jpeg -s formatOptions 92 -Z 2400 TahoeDark.heic --out src/future/assets/wall-air.jpg`
- Neo 不動，仍是 `Mac Blue.heic`（它自己的桌布）。
- 選擇深色版：片裡兩台都跑深色外觀（視窗 `#1c1c1e`、鎖屏、島都是深的），且 Air 是午夜色機身、時鐘 21:41。

量測（畫面左側桌面平均色，排除黑島）：

| 幀 | 機器 | draft17 | draft18 |
|---|---|---|---|
| f1070 | Air | 130,96,165（紫） | 27,20,104（深藍） |
| f310 | Neo | 53,106,174（未動） | 53,106,174 |

## 2. 選單列：整列以前只有字、沒有列本身，最左那顆蘋果還是空字串

`Screen.tsx` 的 `MenuBar` 原本 `<span>{''}</span>`——蘋果標誌從缺，而且整個列沒有任何底色，
白字直接浮在桌布上（Neo 那張亮藍桌布上幾乎讀不出來）。這一輪：

- `glyphs.tsx` 新增 `AppleLogo`（實心蘋果）。
- 選單列改成 macOS 深色外觀那條玻璃列：`linear-gradient(rgba(12,12,16,.66),…,.58)`＋`backdrop-filter: blur(30px) saturate(180%)`，底下補一條 0.5px 內陰影。
- 鎖屏時整列收掉（`opacity: desk`）——macOS 鎖屏沒有選單列，之前電池／Wi-Fi 會留在鎖屏上。
- `Desktop.tsx` 的選單列同步改（同一套材質）。

量測（Neo 屏板，同一列寬 1408）：

| 幀 | 狀態 | 選單列帶平均 | 同幀帶下方桌布 |
|---|---|---|---|
| f400（60 fps 800，已解鎖） | 桌面 | 46,83,109 | 39,134,195 |
| f100（60 fps 200，還在鎖屏） | 鎖屏 | ＝桌布（整列收掉） | — |

## 3. 手機時鐘跟 Mac 對不上

手機鎖屏狀態列原本寫死 `9:41`（蘋果宣傳稿那個時間），Mac 是 `10月4日 周日 21:41`，
同一支片子兩支錶。改成一律 `21:41`（`stage.tsx` 的 `phoneCard`）。

## 4. 這輪沒動、留著的話要說清楚

- **藥丸幾何／居中**：能量到的都對得上（島內容重心與島中心：Neo 番茄鐘 167 px 寬、偏差 0.0；
  Air 鎖定倒數 359 px、偏差 0.0）。前景那幾張截圖裡的藥丸，對應的是比 draft17 更早的草稿。
- **劉海與邊框貼合**：維持 v17 的 `darkShell()`（上緣 236 → 69），本輪沒有回退。
- **島內文案與片尾那句**：沿用 v17。

## 動到的檔案

- `src/future/assets/wall-air.jpg`：換成 TahoeDark（macOS 26 預設）
- `src/future/assets.ts`：註解改寫，寫清楚哪台用哪張、為什麼不能互換
- `src/future/glyphs.tsx`：新增 `AppleLogo`
- `src/future/film/Screen.tsx`：`MenuBar` 材料、蘋果標誌、鎖屏收列
- `src/future/Desktop.tsx`：同一套選單列材料
- `src/future/film/stage.tsx`：手機時鐘

## 重現指令

```bash
cd film/ws2-opus
npx remotion render src/index.ts WS2FuturePlateNeo public/future/plates/neo.mp4 --gl=angle --codec=h264 --crf=16
npx remotion render src/index.ts WS2FuturePlateAir public/future/plates/air.mp4 --gl=angle --codec=h264 --crf=16
npx remotion render src/index.ts WS2FutureDraft out/future/gate/draft18.mp4 --gl=angle --codec=h264 --crf=18
```

---

# draft19：機身邊緣不再刷白、倒數環改回剩餘量、網址欄改成一整條

起因：Aaron 指出 draft18 仍有五處穿幫。逐項查證後動手的有三件、待確認的兩件。

## 1. 機蓋／機身的側壁在掠射角被刷成純白（實測 255）

不是顏色太淺，兩個原因疊在一起：

- 官方 USDZ 每張材質都帶 **0.25 清漆**。清漆那層高光是白色的，跟 baseColor 無關——
  「把顏色乘小」壓不掉它（舊的 `darkShell` 就是只乘了 0.16，等於沒用）。
- 金屬的回應幾乎全是環境反射。上面的柔光板亮度是 `0xfff1e0 × 7`，乘 0.45 進來還是爆表。

三處材料：

- `darkShell()`（機蓋外殼）：清漆歸零、`metalness 0.18 / roughness 0.62`、`envMapIntensity 0.10`。
- `finish()`（機身、鍵盤、底殼）：一律關清漆；底殼從 `metalness 1 / roughness 0.3`
  （鏡面，會把柔光板原樣反射）改成 `0.9 / 0.42`；環境反射統一 `0.65`。
- `Phone()`（官方 iPhone USDZ）：同一個病，之前完全沒處理——清漆歸零、鏡面收斂、環境反射 `0.62`。

驗證（f950，draft18 vs draft19，同一支鏡頭）：機蓋上緣那條亮帶由接近白變成深灰，
午夜色的側壁不再是路邊的白縫。ffmpeg 取幀比對見 `/tmp/ab-air.png`。

## 2. 倒數藥丸的環：畫的是「已經過了多少」，看起來是一顆亂掛的點

`frac={1 - left / 1500}`（休息那顆同理）。番茄鐘剛開始那一格 frac≈0，
只剩一小段弧、端點又是圓頭，看起來就是灰圈上掛著一顆不知道哪來的紅點。

Apple 的 `ProgressView(timerInterval:)` 畫的是**剩餘量**：一開始整圈滿的，時間過去一圈一圈退掉。
兩處改成 `frac={left / 1500}` / `frac={left / 300}`，端點改平頭（0 與滿圈兩端都乾淨）。

驗證：交付第 1200 幀（內部 2400）「10 分」那格，環是一整圈紅的。

## 3. Safari 網址欄是一整條，不是懸在中間的小藥丸

`Browser()` 原本是 `left:'50%'` + `width: min(420, w*0.44)` 置中的小藥丸，
左右留一大片空。改成 `left: 212, right: 180` 的橫貫欄位，右側按鈕群加寬到 148，
交通燈由 `top: 18` 挪到 `top: 20`（工具列 52 高、圓 12.5，置中應為 19.75）。

## 待 Aaron 指認的兩張

draft18 的另外兩張截圖（暗底上一道淺灰圓弧＋深藍；暗底＋淺灰弧＋數字「2」）我沒能對到幀。
已排除的是「字幕」——`Caption` 那行白字就落在畫面上緣，量到的白色橫列是它，不是金屬。
若那是 iPhone 或 Air 的機身圓角，第 1 項應該已經覆蓋；若還在，請給一個時間碼。

## 重渲指令

```bash
cd film/ws2-opus
npx remotion render src/index.ts WS2FuturePlateNeo public/future/plates/neo.mp4 --gl=angle --codec=h264 --crf=16
npx remotion render src/index.ts WS2FuturePlateAir public/future/plates/air.mp4 --gl=angle --codec=h264 --crf=16
npx remotion render src/index.ts WS2FutureDraft out/future/gate/draft19.mp4 --gl=angle --codec=h264 --crf=18
```
