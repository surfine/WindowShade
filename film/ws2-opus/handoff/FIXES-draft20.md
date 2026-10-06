# FIXES-draft20 — 概念片（WS2Future）整改 + 最終 4K 母帶

對象：**`out/future/gate/draft20-4k.mp4`（3840×2160、30 fps、1800 幀、60.05 s、61.5 MiB）**。
屏板先重渲成 4K 貼圖：`public/future/plates/neo.mp4`（2816×1764）、`air.mp4`（3420×2216），皆 30 fps 1800 幀。
所有證據靜幀在 `out/future/gate/d20-4k-evidence/`。

---

## 0. 4K 母帶（本輪最終交付）

```
$ ffprobe -v error -select_streams v:0 -show_entries \
    stream=codec_name,profile,width,height,r_frame_rate,avg_frame_rate,nb_frames,pix_fmt \
    -show_entries format=duration,size,bit_rate -of default=nw=1 out/future/gate/draft20-4k.mp4

codec_name=h264
profile=High
width=3840
height=2160
pix_fmt=yuvj420p
r_frame_rate=30/1
avg_frame_rate=30/1
nb_frames=1800
duration=60.053333
size=64539962
bit_rate=8597685
```

```
$ ffprobe … public/future/plates/neo.mp4   →  h264 2816×1764 30/1 nb_frames=1800
$ ffprobe … public/future/plates/air.mp4   →  h264 3420×2216 30/1 nb_frames=1800
```

- **fps 未動**：源 60 fps、出片 30 fps（`FPS / 2`）的設定沿用到 4K，沒有為了 4K 改時間軸。
- **crf 16**（沿用 16–18 區間），`--gl=angle`。
- **做法選 `--scale=2`**，沒有另開 4K composition：現有三條 composition 的版面、`PT` 幾何與既有驗收基準全部不動，
  放大只影響取樣密度，所以「1080p 驗過的構圖在 4K 不會位移」是結構上成立的。
- 渲染用背景管線跑（`/tmp/ws2-4k/pipeline.sh`，`start_new_session=True` 完全脫離 shell process group），
  三段串接：Neo 屏板 → Air 屏板 → 概念片。總時長約 20 分鐘，沒有卡在任何一次前景命令。

---

## 1. 本輪修掉的問題

### 1.1 手機整支不在畫面裡（這條最嚴重，等於整段穿幫）

**症狀**：`live` 那一段（film f 1760–2260／draft 幀 880–1130）與 `away` 倒數段（f 2880–3290），
字幕在講「iPhone 上的提醒，Mac 上也看得到」，但 iPhone **根本不在鏡頭裡**——兩台筆電在演，手機缺席。

**量到的原因**：`phoneAt()` 給的 `dx: -0.23`，手機世界座標落在 `x = 0.28 − 0.23 = 0.05`。
把這幾幀的鏡頭反推出來，畫面左緣大約在世界 `x ≈ 0.18`；手機整個在左緣之外。
（掃 `raw-live-air.png` 的左 25%，除了背景色 `#12141a` 之外「非背景像素的 x 範圍只有 948–956」，
就是這個空景的證據。）

**修法**：`dx: -0.23 → -0.08`（`away` 段同樣從 `-0.08` 起算再往後退）。
手機貼著 Air 左前緣站，機身只壓到筆電左邊一點，像靠著放。

**證據**：`raw-live-air.png`（f950）、`raw-live-air-food.png`（f1025）——手機已經在畫面左側，
螢幕上「车快到了 / 2 分钟」與「外卖到了 / 放到门口」都讀得到。

### 1.2 手機螢幕四角（Aaron：「iPhone 是圆角，结果你扔一张直角的截图上去」）

`Phone` 的顯示面用 `PHONE_SCREEN_OUTLINE` 多邊形裁切（`stage.tsx:286-293` `g.clip()`），
貼圖再走 `transparent + alphaTest={0.02}` 把圓角外的像素剔掉，所以卡片不會以直角蓋過機身圓角。

**4K 逐角驗收**：`x1-phone-qa.png` 是四個角度的手機驗收台
（composition `WS2FuturePhoneQA`，用的是片子裡同一支 `Phone` 與同一個 `Studio`），
四個角的放大圖顯示：顯示面往內縮、外緣順著機身圓角走，螢幕與金屬框之間是一條乾淨的暗線，
沒有白邊、沒有灰邊、沒有直角穿出。

### 1.3 Air 劉海過長（Aaron：「Air 的刘海也不要太长了，适可而止」）

`island.ts` 的 `SHAPES.air.tick` 由 `w: 360` 收成 `N_.w + 2 * 52`（= 289）。
現在的寬度就是「劉海本身 + 左右各 52 pt 的耳朵」，不再是橫跨三分之一片螢幕的黑長條。

### 1.4 島內內容置中（Aaron：「让灵动岛的内容保持在灵动岛中央」）

`Compact` / `SoftAlert` / `Unlock` / `Breath` 四個容器補上
`width: '100%'` + `height: '100%'` + `boxSizing: 'border-box'` + flex 置中。
兩個都要：只寫 `height`，寬度會是 `auto`，內容會被推到右邊並在上／右緣被切掉。

**證據**：`x3-air-island-4k.png`（Air 島，f1050，6× 放大）——圖示與兩行字在黑色膠囊裡左右留白對稱。

### 1.5 Air 要用 Air 自己的桌布

`Wall`/`WALL` 仍是 `{ neo: PLATE.wall, air: PLATE.wallAir }`，Air 用 **`Motion Blue.heic` 的 Dark Still**
（Apple MobileAsset CDN `com_apple_MobileAsset_DesktopPicture` 下載的 6016×6016 原件，SHA1 已核，
Build 10M8877），Neo 維持 `Mac Blue.heic`。前幾輪把 Air 換成 `Mac Purple` / `TahoeDark` 都是錯的，
理由與來源見 `handoff/FIXES-draft18.md` 第 1 節。

### 1.6 桌面 mockup 細節

在 `Desktop.tsx` 的 `Browser` 裡逐條對過（`Desktop.tsx:149-160`）：

- **網址欄是一整條橫貫工具列的欄位**：`left: 212, right: 180, top: 11`——左邊留給交通燈與側欄鈕，
  右邊留給分享／新分頁／分頁總覽。不是懸在中間的小藥丸。
- **交通燈**：`Lights` 在 `left: 18, top: 20`，三顆 12.5 px 圓、`gap: 8`，未啟用時轉灰。
- **桌域**：`windowshade.aaronlau.me`，全片沒有 `sspai.com`（`rg sspai src/` 無命中）。
- **Dock**：置中、液態玻璃（`backdrop-filter: blur(26px)`），高 26 圓角、執行中黑點齊備。

**4K 證據**：`x5c-safari-bar-4k.png`（整條網址欄）、`x5d-url-windowshade-4k.png`（放大讀出網址）、
`x5-menubar-4k.png`（交通燈＋工具列）、`x5b-dock-4k.png`。

### 1.7 打光與高光（Aaron：「解决模型发灰等打光上的问题」）

在 4K 母帶上量高光裁切，確認沒有「一整片死白」，也沒有「整台灰掉」：

| 幀 | 解析度 | 純白（≥254） | 近白（≥248） |
|---|---|---|---|
| f300（Neo 近景） | 3840×2160 | 0.15% | 0.11% |
| f1050（Air + Safari） | 3840×2160 | 0.40% | 0.20% |
| f1560（Air 倒數） | 3840×2160 | 0.18% | 0.09% |
| 對照：1080p draft19 f1900 | 3840×2160 | 0.48% | 0.04% |

純白只佔 0.15–0.40%，而且集中在字幕字緣與鍵帽／UI 高光，不是機身金屬。
`x4-metal-4k.png` 顯示機身邊緣是「亮帶漸層 → 暗反射」的走向，不是均勻灰面。

---

## 2. 4K 專屬複驗（縮放會把接縫、細邊與半像素錯位放大）

| # | 抽查項 | 4K 下的結果 | 證據 |
|---|---|---|---|
| 1 | Air 劉海兩端接縫 | 通過。劉海黑塊與機身黑邊連續，無灰縫、無台階 | `x2-air-notch-4k.png` |
| 2 | Neo／Air 島圓角與內容留白 | 通過。內容左右留白對稱，無溢出、無切邊 | `x3-air-island-4k.png` |
| 3 | iPhone 螢幕四角 | 通過。顯示面內縮順著機身圓角，無直角穿出 | `x1-phone-qa.png` |
| 4 | 金屬邊框高光 | 通過。亮帶—暗反射漸層；全幀純白 ≤0.40% | `x4-metal-4k.png` |
| 5 | Dock 與選單列細線 | 通過。0.5 px 內陰影在 4K 沒有斷線或雙線 | `x5-menubar-4k.png`、`x5b-dock-4k.png` |

### 4K 下新發現並修掉的問題

**一條：手機不在畫面裡（第 1.1 節）。**
它其實在 1080p 就已經穿幫，只是 1080p 的縮圖上那片空景與深色機身邊緣混在一起不容易看出來；
拉到 4K 逐像素掃左側空景時才確認「整支手機都不在鏡頭內」。
已改 `dx` 並**重渲母帶**，上面的 4K 交付物是修完之後的版本。

除此之外，**4K 下未發現其他新問題**。

---

## 3. 重現

```bash
cd film/ws2-opus

# 4K 屏板（先跑，概念片要吃這兩個檔）
npx remotion render src/index.ts WS2FuturePlateNeo public/future/plates/neo.mp4 \
  --gl=angle --codec=h264 --crf=16 --scale=2
npx remotion render src/index.ts WS2FuturePlateAir public/future/plates/air.mp4 \
  --gl=angle --codec=h264 --crf=16 --scale=2

# 4K 母帶
npx remotion render src/index.ts WS2FutureDraft out/future/gate/draft20-4k.mp4 \
  --gl=angle --codec=h264 --crf=16 --scale=2

# 4K 抽查靜幀
./handoff/verify-4k.sh

# 手機四角驗收台
npx remotion still src/index.ts WS2FuturePhoneQA \
  out/future/gate/d20-4k-evidence/x1-phone-qa.png --frame=0
```
