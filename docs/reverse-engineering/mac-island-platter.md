# Mac 島底座的參數集（27.2 `CampoUIInternal` 代碼級證據）

> 目的：不靠真機，把 PROLED MacBook Pro 上系統靈動島的「底座」（platter）量法從二進位裡讀出來。
> 樣本：macOS 27.2（26B123）dyld cache 拆出的
> `System/Library/PrivateFrameworks/CampoUIInternal.framework/Versions/A/CampoUIInternal`
> （9,207,808 bytes，SHA-256 `833c34a5e77dbacbcc1eb103f4f6bbb3781ebff1df065b32512b2e0b8755c28e`）。

## 1. 取法

Swift 把一個型別的欄位名按**宣告順序**連續寫進 `__swift5_reflstr`。所以在檔案裡定位
`drawnPlatterSize` 的字串（偏移 `0x5af110`），往前往後按 NUL 切開，就得到同一結構的欄位序列。

```python
data = open(binary, "rb").read()
i = data.find(b"drawnPlatterSize")
chunk = data[max(0, i-600):i+600]
names = [s for s in chunk.split(b"\x00") if len(s) > 2]
```

## 2. 島底座的 6 個可動畫參數

```
subvariantName
cornerRadius
undulationScale
placeholderGlassFraction
drawnPlatterSize          ← 底座尺寸
listeningCollapseProgress
```

同一個 View 的 `AnimatableData` 還包含：

```
timeOffset, scale, pivot, state, topEdge, placeholderFraction, glass
pinsTopPlatterWidth, pinsTopPlatterHeight      ← 「貼頂」版的兩個獨立自由度
```

結論一：Mac 島的底座不是「一組固定尺寸」，而是
**圓角＋底座尺寸＋佔位比例＋收合進度一起插值的動畫量**。這解釋了兩件事：
1. 為什麼 iPhone 的 36.6667 / 18.3333 在 Mac 二進位裡找不到——Mac 不是換一組常數，是換一套模型；
2. 為什麼我們把每個狀態各自寫死尺寸與圓角，過渡時一定會跳。

結論二：`pinsTopPlatterWidth` / `pinsTopPlatterHeight` 是貼頂狀態的**獨立**寬高，
我們目前只有一個 `expandedSize`，少一個自由度。

## 3. 常數掃描的結果（決定性否定）

對整個映像做 8-byte double 掃描（允許到三位小數、1–800 之間）：

- 出現的數值群：0.5×5、1.0×3、4.0×6、8.0×4、10.0×4、15.0×5、16.0×7、18.0×8、
  20.0×3、24、28×2、32、36×2、40、43、50×2、100、110×2、146、150、160、230、255、315、340。
- **沒有** iPhone 的 36.6667 / 18.3333 / 125.0 / 94.6667。
- 也沒有成對相鄰的 `CGSize` 常數（掃描所有相鄰 double 對，只找到 11×11、15×15、18×16 這類圖示尺寸，
  沒有 230×64、340×84 這種底座尺寸）。

→ 底座尺寸不是常量表，是**執行時由承載視窗（Spotlight／canvas）算出來**再交給 `AnimatableData` 插值。
所以「抄一個數字」在 Mac 上根本不成立。

## 4. 對 WindowShade 的具體結論

要 1:1，改的不是常數，是**模型**：

| 我們現在 | 系統的做法 | 應該改成 |
|---|---|---|
| 每個狀態一組 `CGSize` 常數（`IslandMetrics.expandedSize` 等） | `drawnPlatterSize` 是動畫量，狀態之間插值 | 底座尺寸改成 `AnimatableData` 的成員，跟著同一條彈簧插值 |
| 只有一個展開尺寸 | `pinsTopPlatterWidth` / `pinsTopPlatterHeight` 兩個自由度 | 貼頂與非貼頂分開兩個尺寸來源 |
| 圓角由高度推、狀態邊界換算 | `cornerRadius` 也是動畫量 | 圓角進同一組動畫量，與尺寸同步插值 |
| 佔位／收合是布林式切換 | `placeholderGlassFraction`、`listeningCollapseProgress` 是連續量 | 改成 0…1 的進度量，形狀跟著量走 |

這正好對上我們這輪已經做的兩件事（圓角不再各態寫死、容器只脹不縮），
下一步是把「尺寸」也從常量改成動畫量——只動 `NotchCapsule` 與 `IslandMetrics` 兩個檔案。

## 5. 未解與界線

- 底座在執行時的确切值仍要真機量（因為它由視窗尺寸算出來）；但**要改的結構**已經明確，不必等真值。
- `pinsTopPlatterWidth/Height` 的來源函式還沒定位（需要對 `__text` 做常量＋偏移的模式掃描，或讓 Ghidra 的 `-process` 跑完）。
- 底座動畫的**彈簧來源**已另案處理：CampoUIInternal 沒有 `setDampingRatio:`／`setResponse:`，
  形狀動畫是 SwiftUI `Animation`（外層傳入）。候選來源與完整掃描見
  `docs/reverse-engineering/mac-island-springs.md`。
- 本文所有結論都來自 27.2 正式版二進位；27.3 beta 的對應映像尚未拆（AppleArchive 索引層未解）。
