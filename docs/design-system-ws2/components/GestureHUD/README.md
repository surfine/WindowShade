手勢提示浮窗：標題欄手勢做到一半時，告訴你松手會得到什麼。

**什麼時候用**：場景 2，在標題欄上滑、甩、捏合的過程中；出現在手勢發生的那扇窗旁邊（P6），不在屏幕正中。

**結構與令牌**：起點符號 → 1:1 跟手的進度條（填充方向和手指一致）→ 終點符號與結果名 `hud-label`（13 semibold `label-secondary`）。符號 14 medium，軌道高 4。290×63，固定圓角 `radius-hud` 24（照 macOS 27 音量浮窗實測，不是膠囊）；離邊 `margin-edge`；內邊距 16。

**材質**：控件層。macOS 26+ `NSGlassEffectView` regular；14/15 `NSVisualEffectView` `.hudWindow`。減少透明度改不透明 `window-bg`，邊 0.5 pt（增強對比度 1 pt）`label`。

**狀態**：跟手中 → 越過門檻（終點變 `accent`、`pop` 彈一下、`.alignment` 觸感，三重提示不只靠顏色）→ 完成後 `fade-hud` 淡出。撤銷時顯示「撤銷 左半屏」這種寫明那一步的字（#20）。

**不要**：在浮窗裡再疊一層玻璃；寫成菜單。
