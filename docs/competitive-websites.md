# 竞品官网与对表面（逐站）

2026-10-14，读取于当日。承接 [竞品深挖](competitive-deep-dive.md)（机制）与 [包装与发行面](competitive-packaging.md)（包层面）；这一份是**它们对外的样子**——站点结构、定价模式、文案定位、FAQ 题目、开发着面、法律面。

**方法**：逐站抓站内所有内容页（首頁＋功能／定价／FAQ／changelog／docs／blog／market／privacy／terms）；Framer 站的收合内容用已验证的 payload 解法解出（见 [DynamicLake 更新日志](dynamiclake-changelog.md) 的说明）。**原始 HTML 只落 `/tmp/ws-research/sites/`，不进仓库**；这里只放分析。

## 一、横向对照

| 站 | 站内页 | 定位语（一手） | 价格 | 内容面 |
| --- | --- | --- | --- | --- |
| **wins.cool** | 首頁／`/changelog`／`/pricing`／`/support` | 「Wins - Mac窗口管理器」；「Mac 桌面窗口管理器，像 Windows 一样分屏，Dock 窗口预览快速切换」 | ¥139／¥279／¥356（按装置数） | 中文优先（`/zh`）；有 changelog、pricing、support 三件套 |
| **highlyopinionated.co/swish** | 首頁／`download`／`changelog` | 「Supercharge your Mac with magical trackpad gestures」 | $16（促销 $8／€5）；Setapp | **FAQ 最密（14 条）**；促销语言重 |
| **tryalcove.com** | 首頁／`/changelog`／`/download` | 「Dynamic Island for your Mac」「An entirely new way to experience Mac」 | $14.99 | 极简；FAQ 在另一页（一手读过于 10-05） |
| **windowmizer.com** | 首頁／`/about`／`/faq`／`/privacy` | 「**Roll-up your desktop windows like a windowshade!**」 | $25 新购／$20、$15 升级 | 首頁 **195 KB**（重）；有完整版本史页 ＋ FAQ |
| **chainyourmac.com** | 首頁／**`/buy`／`/buy/3`／`/buy/5`／`/buy/20`**／`/privacy`／`/terms` | 「scrolling window manager…windows on an endless strip, like Niri or PaperWM…Try the live demo」 | **$19.99 起，按装置数分页**（$49.99／$79.99／**$299.99**） | **首頁就是可操作的 demo**（不是影片）；另有一份**自营对比页**（把我们没列的 Nehir／komorebi／ScrollDesktop.spoon 都列了） |
| **launchosapp.com** | 首頁／`/features`／`/blog`／`/faq` | 「Best Launchpad Alternative for macOS 26 & 27」 | 免费 Basic ＋ $11.99／$18.99／$35.99（Paddle） | **有 blog**（内容行销）；features 独立页 |
| **macenhance.com/dockmate** | 首頁 ＋ **`/docs/dockmate/faq.html`** ＋ **`/docs/dockmate/changes.html`** | 「Window previews and controls for your Dock」 | $14.99 | **按 App 一套 docs**（FAQ ＋ Recent Changes）；另有技术 blog（见第四节） |
| **dynamiclake.com** | 首頁／`/changelog`／`/buy`／`/blog`／`/extensions` ＋ **`market.`／`docs.` 两个子域** | 「Dynamic Island Mac…Inspired by Apple Dynamic Island」 | Gumroad（`avirok1.gumroad.com/l/nyyfw`） | **最完整**：changelog（79 版）、blog、docs 子域（DynamicLakeKit）、market 子域（插件市集）、Extensions 页 |
| **omniwm.app** | 首頁 ＋ **每个功能一页**（8 页：`/features/overview`、`command-palette`、`quake-terminal`、`workspace-bar`、`scratchpads`、`hidden-bar`、`app-rules`）＋ **`/help/known-limitations`** | 「macOS tiling window manager, Niri & Hyprland style」 | 免费（GPL-2.0） | **按功能拆页** ＋ **自己列已知限制** ＋ 完整 docs（Luau API、CLI/IPC、架构指南） |

## 二、四条可借的做法

**1. 首頁放「能操作的 demo」，不是影片。** ChainYourMac 首頁自己写：「**A working model of ChainYourMac, not a video**」——可以拖标题栏重排、点 Dock 图标开 App、按红点关窗。对照 DynamicLake 与 Wins 首頁都是**演示影片**。→ 能操作的东西比影片有说服力，也更难被抄（要真做出来）。

**2. 按功能拆页，而不是一页堆全部。** OmniWM：每个功能一页（命令面板／Quake 终端／工作区条／暂存区／隐藏栏／App 规则）＋ 独立的 `/help/known-limitations`；DynamicLake 也是（changelog／extensions ／market／docs 各自成页）。对照 WindowMizer 那种**首頁 195 KB 全塞一页**的做法，前者的搜索命中与分享单元都更细。

**3. 「自己列已知限制」是成熟信号。** OmniWM 那页（[omniwm.app/help/known-limitations](https://omniwm.app/help/known-limitations)）把要求写成可核对的表：
- Intel Mac **不支持**；核心窗口管理要 macOS 26，隐藏栏与某个可选功能要 26+／27+
- **SIP 保持开启**——官方发行版**不需要关 SIP**
- **权限分级**：辅助功能**必须**（发现／聚焦／移动／改变窗口）、输入监控**必须**（全局热键）；**屏幕录制可选**（没有它仍能平铺，只是概览缩图／拖拽预览／隐藏栏图标不可用）、**完全磁盘访问可选**（只有隐藏栏用）
- 「显示器具有单独空间」必须开；关掉时**照常运行但暂停窗口管理**
- **一份 14 个同类的名单**：启动时侦测 `AeroSpace、Amethyst、bobrwm、Glide、komorebi、Nehir、Paneru、parket、Rift、Tangrid、TrimWM、yabai、Yashiki`，**发现冲突就不启动窗口管理**，等对方退出
→ 这是**把限制、权限、冲突都写成可核对的表**，而不是藏在 FAQ 里。对我们是直接的模板（我们的 [blueprint](blueprint.md) 有「硬要求」，但没有一页对外的「已知限制」）。

**4. 定价按装置数分成独立页。** ChainYourMac 的 `/buy`／`/buy/3`／`/buy/5`／`/buy/20`（$19.99 → $299.99）、LaunchOS 的 1／2／5 台档、Wins 的 ¥139／¥279／¥356。→ **按台数的分档页**是这类工具的常见卖法（我们目前是免费 MIT，这条只作记录）。

## 三、开发者面（一家做到了极致）

**DynamicLake** 是唯一一家把「对外平台」做齐的：

- **`docs.dynamiclake.com`**：DynamicLakeKit 文件（Extensions ＋ JSON Plugins 两套机制、20+ 主题页，见 [深挖 § 扩展平台](competitive-deep-dive.md)）
- **`market.dynamiclake.com`**：插件市集，规则公开——**只收开源（要公开 repo）**、安装走**签名链接**、**插件装完被改动就停止执行**；投稿四步（想清楚 → 打包 executable＋icon＋`plugin.json` → 送 repo 由官方测 → 拿到一键安装的签名链接）
- **免费 Playground**：「不买完整 App 也能跑你的 extension 或 plugin」
- 另有**验证注册表**（[github.com/rokach/DynamicLake-Trusted-Extensions](https://github.com/rokach/DynamicLake-Trusted-Extensions)，目前暂停）

## 五、Dockset（2026-10-15，Aaron 点名：「他的产品官网要特别借鉴」）

**背景**：Dockset＝多套 Dock 布局＋可带挂件的独立 Dock（$14.99 买断、14 天退款、macOS 13+）。**收购传闻公开检索查无实据，官网正常在售**——按 Aaron 的信息与检索现状两条并存记录。

**官网结构（2026-10-15 读取，`dockset.app`）**：一级导航＝ **Menu／Product／Pricing／Resources／Manual／Changelog／Support**。首页顺序：

1. **可玩的演示，不是截图**：「Your Dock. Reimagined.」下面直接是能操作的场景——「Everyday」条（Work／Personal／Gaming ＋ 一个 9:41 的时钟），右侧一台演示机。
2. **模式切换就长在首页**：`Dockset Mode: macOS Dock ／ Custom Dock ／ Both`——用户不用看文档就懂产品有几种用法；旁边紧跟「Add Widget」按钮，点了就能加。
3. **挂件画廊全列名**：Stock／Calendar／Reminders／Now Playing／Weather／Focus Timer／Stripe／Sticky Note／Battery／Shortcut／Paddle／Watchlist／Shopify／Clock／World Clock／Stopwatch／Countdown／Alarm……
4. **两条路都照顾**：开 Custom Dock 的人看挂件；**不想换 Dock 的人也有路**——「Keep your familiar Dock. Save different app layouts and switch between them. No Custom Dock needed.」
5. **定价块**：`From $14.99 · One-time purchase · 14-day money-back guarantee` 一行说完（价格、买断、退款承诺）。
6. **Manual 与 Changelog 是一级导航**——成熟产品的信号，不是营销页。

**可借的四条**（对我们的官网 `site/`）：① **首页要能玩**：产品最好的一面直接可操作，不靠截图；② **模式选择前置**：我们把「它怎么接管你的刘海/窗口」做成首页可切换的状态（收着／展开／卷帘条），而不是藏在功能列表里；③ **定价表达**：一口价＋退款保证一行说完（**我们的价格与授权还没定案——这条是模板不是结论**）；④ **Manual/Changelog 进一级导航**。

## 四、其它值得记的（观察）

- **macEnhance 有技术 blog**：`Controlling the Dock with CoreDock`、`What is Library Validation`、`System Integrity Protection`、`Apple Silicon: A New Hope`——**竞品公开发的私有 API 与系统机制心得**（CoreDock 正是我们前面在 Wins／LaunchOS／DockMate 的符号面里见到的那一族）。
- **法律面**：ChainYourMac 有 `/privacy` ＋ `/terms`；DynamicLake 有 `/privacy-policy` ＋ `/termsofuse`，**FAQ 里还放了冒名澄清**（「Is AppleLake or Dynamiclake.net the same as DynamicLake?」——对应它这个名字被恶意广告冒用过的历史）；页脚挂 **FFmpeg 的 LGPLv3 声明**。
- **社群**：DynamicLake 有 **Discord** 邀请 ＋ X `@avirok1`；OmniWM 文档站里有 Discord 与 GitHub 入口。
- **文案定位**里最常见的两句话：一是**对标系统**（「like Niri or PaperWM」「Niri & Hyprland style」「Best Launchpad Alternative」），二是**claim Apple 血统**（「Inspired by Apple Dynamic Island／Liquid Glass」）。**没有一家靠讲功能活下来——都在讲「我像什么」**。
