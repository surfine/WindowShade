<div align="center">

<img src="assets/app-icon/windowshade-app-icon.png" alt="WindowShade" width="112">

# WindowShade

**收起視窗，留下位置。**<br>
按兩下標題列，視窗收成一條捲簾條，停在原處；再按兩下，它原樣回來。<br>
指標停在捲簾條上，不用展開就能看一眼。<br>
免費開源的 Mac 視窗小工具。

[![版本](https://img.shields.io/github/v/release/surfine/WindowShade?style=flat-square&color=303b49)](https://github.com/surfine/WindowShade/releases/latest)
[![macOS](https://img.shields.io/badge/macOS-14%2B-303b49?style=flat-square)](#下載)
[![Apple Silicon](https://img.shields.io/badge/download-Apple%20Silicon-303b49?style=flat-square)](#下載)
[![許可](https://img.shields.io/badge/license-MIT-303b49?style=flat-square)](LICENSE)

[**下載 Mac 版**](https://github.com/surfine/WindowShade/releases/latest) · [**官網**](https://windowshade.aaronlau.me/) · [**介紹影片**](https://www.bilibili.com/video/BV1K7ag6WEdH/) · [**視窗往事**](https://windowshade.aaronlau.me/history/) · [简体中文](README_CN.md) · [English](README.md)

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/readme-desk-dark.png">
  <img src="assets/readme-desk.png" alt="「參考資料」視窗收成一條捲簾條，停在原處，露出後面的文章草稿" width="720">
</picture>

<sub>官網首頁的互動示意：「參考資料」收起後，後面的草稿露了出來。<a href="https://windowshade.aaronlau.me/">去官網親手試一試 →</a></sub>

</div>

## 讓開的辦法有三種，只有一種不用回頭找

視窗擋住了後面的東西，你多半會關掉它，或者最小化。兩種都管用，只是回來的時候要費點工夫。

| | 視窗去了哪兒 | 回來的時候 |
| --- | --- | --- |
| **關掉** | 沒了 | 重新開啟，再翻回剛才那一頁 |
| **最小化** | 進了 Dock | 先在 Dock 裡認出它 |
| **收起** | 收成一條捲簾條，還在原處 | 按兩下捲簾條，它就回來 |

收起和最小化不一樣：視窗不離開這張桌面。把卷簾條拖到別處，視窗就在新位置展開。

## 下載

到 [Releases](https://github.com/surfine/WindowShade/releases/latest) 下載最新的 ZIP，解壓，把 `WindowShade.app` 拖進“應用程式”開啟，按提示給權限。它住在選單列裡，不佔 Dock 位置。

- **要 macOS 14 以上、Apple Silicon。** 沒有 Intel 版。
- **1.0.16 下載包：** ZIP 9.77 MB，解壓後的應用檔案合計 25.10 MB（十進位制；檔案系統實際佔用可能不同）。包裡多了更新器，所以比上一版大。
- **安裝包還沒公證。** 第一次開啟如果被系統攔住，去“系統設定 → 隱私權與安全性”點“仍要開啟”。不用關掉系統的安全檢查。
- 每次釋出都附 SHA-256 校驗檔案。每個版本改了什麼，見 [更新記錄](https://github.com/surfine/WindowShade/releases)。

## 它能做什麼

**收起視窗。** 按兩下標題列或按 `⌃⌘C`，視窗收成一條捲簾條；按兩下捲簾條展開。收起後的樣子可以選“跟原來一樣”，也可以選“統一標題列”。捲簾條在最前面時按 `⌘W`、`⌘M`、`⌘H`、`⌘Q`、`⌘N`，作用在它背後的視窗和 App 上；按 `⌘Q` 會先把視窗放下來，要問“是否儲存”時你看得見。

**在標題列上滑一下。** 把指標放在標題列上，用兩根手指滑：往上推，它收成一條捲簾條；往下拉，它鋪滿選單列和 Dock 之間的螢幕；再往上推回到原來的大小。鬆手才算數，滑到一半往回拉，就當沒發生過；滑動時旁邊有一塊和系統音量提示同樣樣式的小浮窗，寫著鬆手會做什麼。左右滑佔半螢幕；朝同一邊再滑，變成三分之二、三分之一；那邊還有一塊螢幕的話，再滑就移過去。左右滑到位後接著往下或往上拐，視窗占那個角。兩指張開也是鋪滿，捏合撤銷上次排布。拖著標題列快速甩出去再鬆手，視窗帶著這股勁滑到甩的那一邊：往上收起，往下鋪滿，左右走同一架梯子，明顯朝著角落甩就佔那一角。普通滑鼠在標題列上滾三格算一次；Magic Mouse 的支援還在真機上驗證。細節見 [標題列手勢說明](docs/gestures.md)。

**看一眼。** 指標在捲簾條上停一下，捲簾條下面就掛出一張卡片，按原來的大小顯示視窗裡的內容；移開，它自己收回去。按一下卡片才真正展開。捲簾條留在原處，卡片和它隔著一道縫，一看就知道這是預覽，不是視窗本身。它不會切換當前的 App，也不會動任何視窗。收起時被最小化的視窗拿不到即時畫面，這時看到的是收起時的畫面，角落會寫明。細節見 [看一眼說明](docs/glance.md)。

**帶到每張桌面、置頂。** 按 `⌃⌘G` 把當前視窗帶到每張桌面：視窗留在原處，別的桌面右上角出現它的捲簾條；停在上面看一眼（視窗被隱藏或最小化時改顯示帶提示的截圖），按一下畫面就回到它，再按一次放下。按 `⌃⌘P` 把那扇視窗置頂，你切到別的視窗，它也不會被蓋住；選單列裡能看到所有置頂的視窗，也能一次全部取消。

**視窗瀏覽。** 把指標停在 Dock 裡的應用圖示上，這個應用開著的視窗會一起列出來，每扇都帶畫面和標題。面板只用來看：按下卡片上的按鈕，才會動那扇視窗；選中一扇按空格開啟大圖預覽，視窗不會被切到前面；左右、四角、居中、填滿或移到別的螢幕，都先畫出視窗要去的位置，你同意了才移動，移好了還能撤銷。也可以從選單列的“選擇視窗…”開啟，或者按你自己設的快速鍵——Dock 入口預設關閉。面板是臨時的：不替換系統 Dock，也不接管 Command-Tab。細節見 [視窗瀏覽說明](docs/window-browser.md)。

**彩蛋：合上蓋子，桌面留在原處。**

<img src="assets/windowshade-lid.gif" alt="MacBook 合蓋時，桌面像留在原處，越往上越暗、越模糊" width="620">

在帶鉸鏈感測器的 Apple Silicon MacBook 上，合蓋時，螢幕合下來，桌面卻像一頁紙留在原處，越往上越暗、越模糊；開蓋就復原。質感有輕柔、標準、磨砂三種。它只是個彩蛋，收起視窗和置頂都用不著它。

## 這個按兩下，比你的 Mac 還老

三十年前的 Mac 使用者，大多會這一招。後來系統換了思路，把視窗送進 Dock，它就慢慢被人忘了。我們把這段往事寫成了一篇可以動手的長文 **[視窗往事](https://windowshade.aaronlau.me/history/)**：七章，四個動手實驗，14 條原始史料。結尾還能 [啟動一台舊 Mac](https://windowshade.aaronlau.me/history/#lab)（System 7.5、Mac OS 8、Mac OS X 10.1，由 [Infinite Mac](https://infinitemac.org/) 執行），沿著當年的選單自己找到這個設定。

今天的 WindowShade 是獨立的 Swift / AppKit 實現，借用了老名字和老想法，程式碼從頭寫起。它不是 Apple 的產品，也沒有用 Rob Johnston、Apple 或 Unsanity WindowShade X 的程式碼。

## 快速鍵

自己在“設定 → 快速鍵”裡錄，也可以一鍵換上 Rectangle 那一套。1.0.16 新裝的一項都不預設；從 1.0.15 及以前升級上來的，保留下面這幾組。快速鍵都能改鍵或關掉；某個組合被別的應用佔用時，會提示你一次。

| 快速鍵（升級上來的） | 做什麼 |
| --- | --- |
| `⌃⌘C` | 收起或展開當前視窗 |
| `⌃⌘P` | 置頂或取消置頂當前視窗 |
| `⌃⌘G` | 把當前視窗帶到每張桌面，再按一次放下 |
| `⌃⌘1…9` | 按選單裡的順序展開收起的視窗 |
| `⌃⌘0` | 排好捲簾條，或進入專注佈局 |
| `⌃⌘←` `⌃⌘→` `⌃⌘↑` `⌃⌘↓` | 排布當前視窗：左右排布，變小一級，變大一級 |

按兩下標題列收起，按兩下捲簾條展開。

## 你的視窗，只留在你的 Mac 上

WindowShade 要兩項權限。**輔助使用**：找到、移動、恢復視窗。**螢幕錄製**：拍下視窗畫面做預覽。“螢幕錄製”只是系統給這個權限起的名字，畫面只在你的電腦上處理，不會傳到別處。應用萬一意外退出，視窗也會自動恢復原樣。

普通視窗都能收起。便箋用系統自己的收起方式；Adobe 這類自己畫標題列的應用會單獨處理。全螢幕、分割畫面、台前排程和多顯示器還有少數情況沒覆蓋，建議先在你常用的應用裡試一次。碰到問題歡迎[回饋](https://github.com/surfine/WindowShade/issues)，寫上 macOS 版本、應用名和操作步驟。

## 開發中

當前下載版是 **1.0.16**——上面那段瀏海功能都在裡面，另有三步歡迎視窗、“WindowShade 讀到的”隱私權頁和介面語言開關。新安裝時，瀏海及其即時活動、檔案架、配件電量提醒、音量亮度提示和“讓開這個 App”預設關閉，需要時在設定裡開啟。[釋出說明](docs/releases/v1.0.16.md) · [預設值](docs/releases/v1.0.16-defaults.md) · [驗收報告](docs/releases/v1.0.16-acceptance/gate-0B-verification.md)

下面這些還沒進下載版：

- **介面語言** —— 設定 → 高階裡的介面語言可選**跟隨系統 / 簡體中文 / 繁體中文 / English**，切換立即生效，不用重啟；繁體用台灣用語（瀏海、捲簾條、快速鍵、輔助使用）。
- **英文介面** —— 1.0.16 覆蓋整個設定視窗和瀏海上的靜音短句；選單、視窗瀏覽、隱私權等還在逐批遷移。[說明](docs/handoff/BATCH27-ENGLISH-HANDOFF-2026-10-12.md)
- **瀏海 Touch ID** —— 選單裡選“驗證 Touch ID…”，瀏海展開顯示系統指紋提示，確認本次 WindowShade 請求；它不解鎖 macOS。[說明](docs/touch-id-island.md)
- **啟動台與新動作** —— 按 `⌃⌘L` 開啟主螢幕（末頁是 App 資料庫）、魔法並排、卷軸、子母畫面、帶分割畫面把手的側拉、`⌥`+Tab 按視窗切換、一鍵換上 Rectangle 快速鍵、點 Dock 讓開後隱藏，等等。[啟動台](docs/launchpad.md) · [標題列手勢](docs/gestures.md)
- **實驗或有裝置限制** —— 刷臉、離開就鎖、遙控和 CarPlay 仍有實驗與裝置限制，不能據此聲稱支援系統刷臉解鎖或完整 CarPlay 接收。

## 構建與參與

需要 macOS 14+、包含 Metal 編譯器的 Xcode command line tools，以及 Apple Development 簽名證書。

```sh
git clone https://github.com/surfine/WindowShade.git
cd WindowShade/prototype
./build.sh --check   # Swift 型別檢查與 Metal 編譯
./build.sh           # 使用本機設定的身份構建、簽名
open WindowShade.app
```

通過 `WINDOWSHADE_CODESIGN_IDENTITY` 或未跟蹤的 `prototype/local-codesign.env` 設定簽名。簽名、隔離構建與釋出步驟見 [DEVELOPMENT.md](DEVELOPMENT.md)；介面和官網文案按 [文案規則](docs/copy-guide.md) 寫。

| 倉庫入口 | 內容 |
| --- | --- |
| [`prototype/`](prototype/) | 原生應用：視窗策略、捕獲、覆蓋層、效果與恢復 |
| [`tests/`](tests/) | 狀態、恢復、幀、Metal 與紙面元件檢查 |
| [`site/`](site/) | 部署在 Cloudflare Pages 的中英文官網與視窗往事 |
| [`docs/performance.md`](docs/performance.md) | 實測結果，以及嘗試過但沒有奏效的辦法 |
| [`docs/releases/`](docs/releases/) | 歷次釋出說明 |
| [`WindowShade.md`](WindowShade.md) | 最初的設計理由與研究筆記 |

修改視窗行為時，請寫明視窗型別、修改前後的表現，以及做過的檢查。

## 致謝與許可

本專案程式碼採用 [MIT](LICENSE)。歷史軟體和名稱屬於各自作者。視窗往事感謝 [Infinite Mac](https://infinitemac.org/)、Marcin Wichary 的 [《偏好之形》](https://aresluna.org/frame-of-preference/)，以及提供時代外觀實現參考的 [AI System 6](https://github.com/surfine/AI-System-6)。隨站點分發的字型和參考資源許可保留在 [`site/public/fonts/`](site/public/fonts/)。
