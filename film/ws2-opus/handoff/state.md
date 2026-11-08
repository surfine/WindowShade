# 現況（v11 / draft11）

## 倉庫

- 工作樹：`/private/tmp/ws2-g8-opus`
- 分支：`grok/g8-opus`
- 沒有推送，沒有合進 `main`。
- 成片在 `film/ws2-opus/out/`（git 忽略）。審程式時看磁碟，不要只看舊 commit。

## 只審這兩支（最新草稿）

| 片 | 包內檔 | 倉庫路徑 | 規格 |
|---|---|---|---|
| B 站剪輯版 | `films/bilibili-v11.mp4` | `out/gate/v11-draft.mp4` | 1920×1080、30 fps、1609 幀、約 53.6 秒 |
| 未來概念片 | `films/concept-draft11.mp4` | `out/future/gate/draft11.mp4` | 1920×1080、30 fps、1800 幀、約 60.3 秒 |

作者聲稱對 v10 報告做了 B10／C10 整改；對照表在 `FIXES-v11.md`、`FIXES-draft11.md`。**Aaron 看過後仍判問題很多**——聲音泵感、山寨 UI、廉價動效。

## 技術摘要（作者報；請重核）

B 站：`film/ws2-opus/src/`，USDZ→glb Air，three.js，配樂 `public/music/ws2-opus-mix.flac`。作者報約 −16.3 LUFS／真峰值 −3.7 dBFS。

概念片：`src/future/`，Neo＋午夜 Air 同場，配樂 `public/music/future/ws2-future-mix.wav`。螢幕吃預渲板 `public/future/plates/air.mp4`（與 neo 板）。作者報 −16.0 LUFS／−4.0 dBFS。

本包 `audio/*-level.txt` 是打包時對 MP4 的每秒 RMS 抽樣，用來協助找「忽大忽小」秒點，不能替代聽感。

## 設計稿

包內 `design-drafts/` 含 README 與本輪相關 HTML。書面令牌在原倉庫 `docs/design-system.md`、`docs/motion-direction.md`（未全量打進包）；稿和令牌不一致時以稿的畫面為準。
