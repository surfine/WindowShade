# 效能與能效審計落地：LEDGER

> 對應審計：`~/Downloads/WindowShade-Performance-Energy-Audit-2026-10-06.md`
> 基線：`cursor/silent-effect-receipts`，審計釘住的 `3866ac0`。
> 狀態分四類：**程式碼**／**測試**／**真機**／**人工**。真機欄一律 `not_run`，除非註明。
> 這一頁是這批工單的唯一事實來源；其他文件向它對齊。

## 狀態總表

| 工單 | 批次 | 程式碼 | 測試 | 真機 | 人工 | 提交 |
| --- | --- | --- | --- | --- | --- | --- |
| PERF-01 診斷器非常駐 | A | 待做 | 待做 | not_run | 待 | — |
| PERF-02 預覽尺寸統一出口 | A | 待做 | 待做 | not_run | 待 | — |
| PERF-03 輸入回呼准入／執行拆分 | A | 待做 | 待做 | not_run | 待 | — |
| PERF-04 舊系統有界背壓 | A | 待做 | 待做 | not_run | 待 | — |
| PERF-11 最小：soak 階段與數值化 | A | 待做 | 待做 | not_run | 待 | — |
| PERF-05 圖像準備移出 MainActor | B | 待做 | 待做 | not_run | 待 | — |
| PERF-06 page/mipmap 僅來源變更重建 | B | 待做 | 待做 | not_run | 待 | — |
| PERF-07 相機節流與 ANE 退路 | B | 待做 | 待做 | not_run | 待 | — |
| PERF-08 活動來源輪詢縮減 | C | 待做 | 待做 | not_run | 待 | — |
| PERF-09 選單列／鉸鏈有界重試 | C | 待做 | 待做 | not_run | 待 | — |
| PERF-10 縮小活動聲明 | C | 待做 | 待做 | not_run | 待 | — |
| PERF-11 完整：效能資格測試 | C | 待做 | 待做 | not_run | 待 | — |

## 護欄核對（收尾時填）

- [ ] 首幀資格／呈現回執／代際驗證／鎖屏 unknown 拒絕／恢復日誌未被刪。
- [ ] 未對探針特判。
- [ ] `bash prototype/build.sh --check` 退出 0。
- [ ] 相關既有 runner 實跑（duo／notch-activity／face-gesture／lid-source）。
- [ ] 第一節「已做對的部分」未被回退。

## 未做與不確定

（收尾時逐條列出：哪些項目本輪只到程式碼／測試，哪些真機項仍 `not_run`。）
