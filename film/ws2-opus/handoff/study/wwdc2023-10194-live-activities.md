# Design dynamic Live Activities（WWDC23 10194）+ HIG

來源：
- https://developer.apple.com/videos/play/wwdc2023/10194/
- https://developer.apple.com/design/human-interface-guidelines/live-activities

本輪（v13／draft13）把片子裡「靈動島／半島」交互與動畫對齊這兩份，不新造稿外交互。

## Chan：Dynamic Island 硬規則（審片尺子）

| 原則 | 成片要長什麼樣 |
| --- | --- |
| 硬體＋軟體同一系統層 | 島從洞長出；黑與洞一體，無假肩／台階 |
| 活的彈性體 | bloom／expand 有動量與可改向感，不是關鍵幀表演 |
| 同心（concentric） | 圓角圖塊與島外輪廓均勻邊距；字不頂進洞、不貼死側壁 |
| Compact 極窄 | 只留本質資訊，貼緊感測區，無空翼 |
| Expanded 環抱感測區 | 內容繞洞左右＋緊貼洞下；禁止大額頭空白 |
| 身分／家族感 | 不同活動用色與圖示可分；同屬一層系統 |
| 字重與形 | 偏厚圓角、偏重字重，一掃能讀 |
| App 不指向島 | 桌面 UI 不畫箭頭指島 |

## Mac：鎖屏 Live Activity 尺子（概念片若出現鎖屏活動）

- 圖形化排版，不要複製通知模板
- 一眼優先的尺寸層級；按鈕只給活動本體必要控制
- 與 App 個性一致（色／圖）
- 高度緊湊，可隨資訊多少動態長高／收矮
- 更新用 content / numeric 過渡，不是硬切

## 本輪改動對照

| 片子位置 | 改什麼 |
| --- | --- |
| Compact（車／外賣／番茄） | 翼更窄、字更重、貼洞 |
| Expanded／半島（提醒、確認、即時活動） | 環洞排版，去額頭；圖塊同心圓角 |
| 倒數 tick | 仍左右翼可讀；數字 tabular + 重字重 |
| 形變 | bloom／expand 加輕初速，彈性更明顯 |
| B 站島 | alert 同心邊距、compact 收窄、圖塊更厚 |
