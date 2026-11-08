# R24 三语裁切清单与缩短文案提案（待 Aaron 定，未应用）

2026-10-17。规格 R24（`docs/product-reshape-spec.md` 的「多语言下的布局裁切」）。本文只列清单和提案；**没有改任何用户可见文案**，改哪几句、怎么改等 Aaron 定。

## 1. 先说结论

1. 规格里说的「硬切」是一个代码缺口，不是文案问题。副标题进 `WS2SettingsCopy.line(_:)` 以后，查不到短句表就按 16 个字符硬截，**不带省略号**（`prototype/App/WS2SettingsInfo.swift` 的 `line(_ subtitle: String)` 和繁体分支）。英文走带词边界加「…」的另一条路，所以只有走了老路的行才硬切。已在布局层修好：被截就一律以「…」收尾，全文仍在 ⓘ 和 tooltip 里（见提交 `fix(settings): 副标题超宽时一律以省略号收尾…`）。
2. 清单里**绝大多数不是屏幕宽度不够，而是代码里写死的字数预算**：中文、繁体 16 字，英文 34 字符（`englishLineBudget`）。普通开关行的副标题区实测能放约 70 个拉丁字符或约 80 个汉字；带分段控件、下拉的行约 40 个拉丁字符。所以第 5 节另列一条「不改文案」的选项：调预算。
3. 副标题区的真实容量（从截图量，900×680 窗口，11pt 副标题字）：

| 行类型 | 拉丁字符 | 汉字 |
| --- | --- | --- |
| 只有开关 | 约 70 | 约 80 |
| 带 ⓘ 加下拉或分段控件 | 约 40 | 约 30 |
| 日程行（开关加提前量下拉加 ⓘ） | 约 44 | 约 17 |

   用户给的「约 45 拉丁、约 20 汉字」是控件行的保守值，下面提案按它写。

## 2. 扫描范围与口径

- 来源：`.build/release-acceptance-2026-10-17/phase0/settings-shots-{zh,zhHant,en}/`，每种语言 11 个设置页加 7 张引导窗，浅色为主。深色版的裁切位置与浅色逐页一致，没有额外发现。
- 默认侧栏只有 8 页（效果、卷帘、刘海、手势、窗口浏览、快捷键、隐私、高级）；鼠标与触控板、遥控器、指挥模式 3 页在预览开关后面，**优先级低**。
- 引导窗三种语言都没有裁切（文字自动换行，按钮和卡片都放得下）。
- 局限：截图只是每页的第一屏（900×680），刘海、快捷键、窗口浏览等长页折叠线以下没有覆盖；这些行走同一条代码路径，同类问题会同样出现，但本清单没有逐行数到。
- 「硬切」指半个字被切、没有省略号；「省略号」指末尾已经是「…」。

## 3. 数量

| 语言 | 可见 8 页：硬切 | 可见 8 页：省略号 | 隐藏 3 页 | 合计 |
| --- | --- | --- | --- | --- |
| 简体 | 8 | 0 | 1（硬切） | 9 |
| 繁体 | 9 | 0 | 1（硬切） | 10 |
| 英文 | 5 | 13 | 1（省略号） | 19 |

提交了布局修复后，三种语言的硬切都会变成省略号；省略号这一类要靠改文案或调预算才会消失。

规格原文写的「英文约 10 处、简体 2 处」是当时口径：英文只数了页头和几条，简体只数了隐私页头和指挥模式。这次逐行扫，数目更大，因为把刘海页、卷帘页、手势页里 16 字硬切的行也算进来了。

## 4. 清单与提案

提案里的英文按 `docs/copy-guide.md`：说用户遇到的事、一句话一件事、固定词汇（实时活动 / Live activities、卷轴概览 / strip overview、刘海 / notch、窗口之间留缝 / Gap between windows）。提案都不依赖改 `Localizable.xcstrings` 的原文：写进 `WS2SettingsInfo.swift` 里已有的 `short`（简体）、`shortHant`（繁体）、`shortEn`（英文）三张行内短句表即可，ⓘ 里仍是原来的全文。

### 4.1 英文

| 页面 | 可见 | 行 | 看到的 | 键 | 全文 | 类型 | 提案 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 刘海 | 是 | Hover guard | Expands the notc | `settings.hoverGuard.sub` | Expands the notch only when the pointer rests on it, not when it passes by | 硬切 | Opens only when you pause on it |
| 刘海 | 是 | Now playing | Track name and artwork at the… | `settings.shade.nowPlaying.sub` | Track name and artwork at the notch | 省略号（35 字符，被 34 预算截） | 原句够短，调预算即可；要改写：Song and artwork at the notch |
| 刘海 | 是 | Volume & brightness | Shows while you press the volume… | `settings.shade.levelKeys.sub` | Shows while you press the volume or brightness keys | 省略号 | Shows on volume and brightness keys |
| 刘海 | 是 | One merged row | Windows and live activities in a… | `settings.shade.mergedRow.sub` | Windows and live activities in a single row | 省略号（42，被预算截） | 原句够短，调预算即可 |
| 卷帘 | 是 | Remember each app's column width | An app you resiz | `settings.stripWidths.sub` | An app you resized opens at that width in the strip next time | 硬切 | Resized apps reopen at that width |
| 卷帘 | 是 | When you reach a column | Keep near: least moving. Center:… | `settings.shade.centering.sub` | Keep near: least moving. Center: always in the middle | 省略号 | Keep near: move least. Center: stay centered |
| 卷帘 | 是 | Center when it fits | When the columns fit on one… | `settings.shade.centerWhenFits.sub` | When the columns fit on one screen, center the group | 省略号 | Center the group when columns fit one screen |
| 卷帘 | 是 | What a rolled-up window looks like | Keep the bar, use one consistent bar, o… | `settings.shade.collapse.sub`（短句 `shortEn` 50 字符） | Keep the bar as-is, use one consistent title bar, or shrink to a thumbnail in place | 省略号（这一条是真的宽度不够，分段控件占了右边） | Keep, one consistent bar, or thumbnail |
| 手势 | 是 | Strip overview can tuck into the notch | Drag a window to | `settings.stripNotch.sub` | Drag a window to the notch in the strip overview and let go to tuck it away | 硬切 | Drop a window on the notch to tuck it away |
| 手势 | 是 | Drag the title bar to reorder | Drag a title bar | `settings.stripTitleDrag.sub` | Drag a title bar in the strip to swap columns; pull further to leave the strip | 硬切 | Drag a title bar to swap columns |
| 手势 | 是 | Drop onto a window to split | Drag a window onto another; they… | `settings.shade.dropSplit.sub` | Drag a window onto another; they sit side by side | 省略号 | Drop onto another window to sit side by side |
| 窗口浏览 | 是 | 页头 | All of an app's windows on its… | `settings.browser.subtitle` | All of an app's windows on its Dock icon | 省略号（40，被预算截） | 原句够短，调预算即可 |
| 窗口浏览 | 是 | ⌘W closes a window in Mission Control | ⌘W closes the window under the… | `settings.browser.missionControlClose.sub` | ⌘W closes the window under the pointer | 省略号（38，被预算截） | 原句够短，调预算即可 |
| 窗口浏览 | 是 | Switch by window | Hold and press Tab to pick a… | `settings.browser.byWindow.sub` | Hold and press Tab to pick a window | 省略号（35，被预算截） | 原句够短，调预算即可 |
| 快捷键 | 是 | 页头 | Works in any app. Record… then… | `settings.shortcuts.subtitle` | Works in any app. Record… then press the new combination; Clear turns the shortcut off. | 省略号 | Record, then press the keys. Works in any app |
| 快捷键 | 是 | Carry this window to every desktop | The window stays; glance from… | `settings.shortcuts.carry.sub` | The window stays; glance from anywhere | 省略号（38，被预算截） | 原句够短，调预算即可 |
| 隐私 | 是 | 页头 | Everything Windo | `settings.privacy.headerLead` 加 `settings.privacy.noReporting` 拼成的整句 | Everything WindowShade reads No usage data is collected, and nothing is counted or reported. | 硬切 | Everything it reads; nothing reported |
| 高级 | 是 | Export Diagnostics | Saved to a folder. Nothing is… | `settings.about.diagnostics.sub` | Saved to a folder. Nothing is sent. | 省略号（35，被预算截） | 原句够短，调预算即可 |
| 指挥模式 | 否（隐藏页） | Coding session | See Claude Code running or… | `conductor.settings.coding.sub` | See Claude Code running or waiting in the notch | 省略号 | See Claude Code's state in the notch |

### 4.2 简体

| 页面 | 可见 | 行 | 看到的 | 键 | 全文 | 类型 | 提案 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 刘海 | 是 | 日程 | 快开会时在刘海里倒数；打开时系统 | `settings.shade.calendar.subNotAsked` | 快开会时在刘海里倒数；打开时系统会问你一次 | 硬切 | 会前在刘海里倒数；首次开启要授权 |
| 刘海 | 是 | 浏览器下载 | 读取「下载」文件夹，看有没有没下 | `settings.shade.downloads.sub` | 读取「下载」文件夹，看有没有没下完的文件 | 硬切 | 查看没下完的下载文件 |
| 刘海 | 是 | 悬停不误触 | 指针在刘海上停一下才展开，路过不 | `settings.hoverGuard.sub` | 指针在刘海上停一下才展开，路过不展开 | 硬切 | 停一下才展开，路过不展开 |
| 刘海 | 是 | 文件架 | 拖到刘海暂存的文件放在这里；关掉 | `settings.shade.fileShelf.sub` | 拖到刘海暂存的文件放在这里；关掉后清空 | 硬切 | 拖到刘海的文件暂存在这里 |
| 卷帘 | 是 | 记住每个 App 的列宽 | 改过宽度的 App，下次开在卷轴 | `settings.stripWidths.sub` | 改过宽度的 App，下次开在卷轴里还是那个宽度 | 硬切 | 记住改过的列宽，下次沿用 |
| 手势 | 是 | 卷轴概览能收进刘海 | 在卷轴概览里把窗口拖到刘海，松手 | `settings.stripNotch.sub` | 在卷轴概览里把窗口拖到刘海，松手就收进去 | 硬切 | 把窗口拖到刘海，松手收进去 |
| 手势 | 是 | 拖标题栏换位置 | 在卷轴里拖标题栏换列；拉远一点才 | `settings.stripTitleDrag.sub` | 在卷轴里拖标题栏换列；拉远一点才离开卷轴 | 硬切 | 拖标题栏换列；拉远才离开卷轴 |
| 隐私 | 是 | 页头 | WindowShade 读到的每 | `settings.privacy.headerLead` 加 `settings.privacy.noReporting` 拼成的整句 | WindowShade 读到的每一样都列在这里。不收集使用数据，也不做任何统计或上报。 | 硬切 | 读到的都列在这里，不统计不上报 |
| 指挥模式 | 否（隐藏页） | 编程会话 | 在刘海里看 Claude Cod | `conductor.settings.coding.sub` | 在刘海里看 Claude Code 在跑还是在等你 | 硬切 | 看 Claude Code 在跑还是在等你 |

### 4.3 繁体

写法照台湾用语；这一批的繁体全文跟简体一一对应，所以裁切的行也一一对应，另外多一行「放得下就置中」（繁体全文多一个字，17 字）。

| 页面 | 可见 | 行 | 看到的 | 全文 | 类型 | 提案 |
| --- | --- | --- | --- | --- | --- | --- |
| 瀏海 | 是 | 日程 | 快開會時在瀏海里倒數；開啟時系統 | 快開會時在瀏海里倒數；開啟時系統會問你一次 | 硬切 | 會前在瀏海裡倒數；首次開啟要授權 |
| 瀏海 | 是 | 瀏覽器下載 | 讀取「下載」資料夾，看有沒有沒下 | 讀取「下載」資料夾，看有沒有沒下完的檔案 | 硬切 | 查看沒下完的下載檔案 |
| 瀏海 | 是 | 停留不誤觸 | 指標在瀏海上停一下才展開，路過不 | 指標在瀏海上停一下才展開，路過不展開 | 硬切 | 停一下才展開，路過不展開 |
| 瀏海 | 是 | 檔案架 | 拖到瀏海暫存的檔案放在這裡；關掉 | 拖到瀏海暫存的檔案放在這裡；關掉後清空 | 硬切 | 拖到瀏海的檔案暫存在這裡 |
| 捲簾 | 是 | 放得下就置中 | 列加起來不到一螢幕時，整組放在正 | 列加起來不到一螢幕時，整組放在正中 | 硬切（只差最後一個字） | 列加起來不到一螢幕時，整組置中 |
| 捲簾 | 是 | 記住每個 App 的列寬 | 改過寬度的 App，下次開在卷軸 | 改過寬度的 App，下次開在卷軸裡還是那個寬度 | 硬切 | 記住改過的列寬，下次沿用 |
| 手勢 | 是 | 卷軸概覽能收進瀏海 | 在卷軸概覽裡把視窗拖到瀏海，鬆手 | 在卷軸概覽裡把視窗拖到瀏海，鬆手就收進去 | 硬切 | 把視窗拖到瀏海，鬆手收進去 |
| 手勢 | 是 | 拖標題列換位置 | 在卷軸裡拖標題列換列；拉遠一點才 | 在卷軸裡拖標題列換列；拉遠一點才離開卷軸 | 硬切 | 拖標題列換列；拉遠才離開卷軸 |
| 隱私權 | 是 | 頁首 | WindowShade 讀到的每 | WindowShade 讀到的每一樣都列在這裡。不收集使用資料，也不做任何統計或回報。 | 硬切 | 讀到的都列在這裡，不統計不回報 |
| 指揮模式 | 否（隐藏页） | 程式設計工作階段 | 在瀏海里看 Claude Cod | 在瀏海里看 Claude Code 在跑還是在等你 | 硬切 | 看 Claude Code 在跑還是在等你 |

顺带发现（不在 R24 范围，没改）：繁体里「瀏海里倒數」「在瀏海里看 Claude Code」的「里」应是「裡」（简体「里」直接转过来的）；提案里已用「裡」。

## 5. 不改文案的另一种做法

英文里有 7 句本身只有 35 到 42 个字符（Now playing、One merged row、窗口浏览页头、⌘W closes…、Switch by window、Carry this window…、Export Diagnostics），是被 `englishLineBudget = 34` 截掉的，普通开关行实际放得下约 70 个。把预算从 34 调到 45 上下，这 7 条英文立即完整显示，而且不动一句文案；带分段控件的行（如「When you reach a column」约 40）才需要走第 4.1 节的缩短句。简体、繁体的 16 字预算同理，调到 20 能救回「悬停不误触」「文件架」「拖标题栏换位置」这类 16 到 20 字的句子，剩下更长的靠提案。

这是文案取舍加布局取舍，由 Aaron 定：A 只用缩短句；B 调预算加缩短句；C 全用缩短句并保留预算。

## 6. 五条最该先看的

1. 刘海页「Hover guard / 悬停不误触」：三种语言里都是硬切，而且是用户最先看到的一页；提案三种语言一并缩成「停一下才展开，路过不展开 / Opens only when you pause on it」。
2. 隐私页头：三种语言都硬切，而且是页头的第一句、隐私承诺所在；整句是两句话拼出来的，短句表里没有对应项，提案是给拼好的整句加一条短句。
3. 指挥模式「编程会话」：隐藏页，但简体、繁体都切在 Claude Cod，这是规格里点名的那一处，提案一句可共用。
4. 手势页两条卷轴行（卷轴概览能收进刘海、拖标题栏换位置）：三种语言都硬切，一句话里有两个动作，按「一句话一件事」顺手拆成一个动作。
5. 刘海页「日程」：这一行右边挤了提前量下拉，是真的宽度不够的那种；提案把「首次开启系统会问你一次」缩成「首次开启要授权」，原话留在 ⓘ。
