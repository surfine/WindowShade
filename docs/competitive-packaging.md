# 竞品包装与发行面（逐家）

2026-10-14。承接 [竞品深挖](competitive-deep-dive.md)（那一份是**机制**：符号面、呼叫轮廓、私有 API），这一份只做**包装与发行**——同一批件（十份，全部通过 `spctl`／`codesign` 验签，见 [深挖 § 六家的二进制静态面](competitive-deep-dive.md)）的 DMG 版面、bundle 组成、语言覆盖、更新机制、体积构成。

**方法**：只读挂载、**不安装**；`hdiutil attach -readonly` ＋ `find`／`ls`／`defaults read`／`codesign`。授权与防篡改元件**只记录存在，不看逻辑**。

## 一、横向对照表

| 应用 | 版本 | DMG 版面 | 语言 | 内嵌框架 | 插件／扩展 | 更新 | 体积（DMG→App） |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Wins | 3.5.1 | 全套 ① | **11**（含 zh-HK／zh-Hans／zh-Hant／zh-TW） | Paddle ＋ Sparkle | `Library/LoginItems/WinsHelper.app` | Sparkle | 57 → 75 MB |
| Alcove | 1.7.7 | 全套 ① | 1（`Localizable.strings`） | 无 | **`XPCServices/AlcoveHelper.xpc`** | 自家 | 15 → 23 MB |
| Swish | 1.13.3 | 全套 ① | 1 | Paddle ＋ Sparkle | 无 | Sparkle | 5 → 11 MB |
| ChainYourMac | 2.2.5 | ①（无背景图） | **0**（英文基底） | Sparkle | 无 | Sparkle | 7 → 18 MB |
| LaunchOS | 2.4.0 | 全套 ① | **21**（含 zh-Hans／zh-Hant） | Sparkle | **`PlugIns/LaunchOSDockTile.docktileplugin`** | Sparkle | 9 → 16 MB |
| Notchy | 1.0.208 | 全套 ① | **138** | Sparkle | **`PlugIns/NotchyWidget.appex`** ＋ `Helpers/` | Sparkle | 123 → 354 MB |
| Droppy | 16.0.1 | ①（无背景图） | **15**（含 zh-Hans／zh-Hant） | **`DroppyKit.framework`**（自家） | `Helpers/` | 自家 Kit | 45 → 90 MB |
| MediaMate | 3.8.4 | 全套 ① | 1（＋nl） | Sparkle ＋ **`SwiftUIHidden.framework`** | **`XPCServices/MediaMateHelper.xpc`** | Sparkle | 10 → 20 MB |
| WindowMizer | 6.2.8 | 全套 ① ＋**挂载时 EULA** | 未取（21 MB 包） | Sparkle | 无 | Sparkle | —（EULA 挡） |
| DynamicLake | 1.0 | 全套 ① | 0（1.0 时） | **`CoreBrightness`／`DisplayServices`／`MediaKeyTap`**（自带私有） | `Library/LoginItems/LaunchAtLoginHelper.app` | 无（后来才加） | 4 → 3.2 MB |
| DockMate | 0.8.7 | 只给了裸 `.app` | 1 | `CocoaMarkdown`／`LetsMove`／Paddle／Sparkle | **`PlugIns/CalendarPlugin.bundle` ＋ `MusicPlugin.bundle`** | Sparkle | 13 MB |

①「全套 DMG 版面」＝ **`Applications` 符号链接（拖进去即安装）＋ 自订 volume 图标 ＋ `.DS_Store`（窗口版面已排好）**；标「全套」的另有自订背景图。

## 二、四条值得记的（观察）

**1. 拖进 Applications 的 DMG 版面是唯一惯例。** 十份里凡是有 DMG 的，**全部**是 `Applications` 符号链接 ＋ `.DS_Store` 预排 ＋ 自订 volume 图标；多数还有背景图。没有一份用 `.pkg` 安装器。→ 我们要发版就得做这个版面（背景图 ＋ 图标位置 ＋ volume 图标），这是**用户第一眼看到的东西**。

**2. 语言覆盖从 0 到 138，跨度大得离谱。**
- **Notchy 报 138 种**（`af`／`ak`／`am`／`as`／`ay`… 连很多小语种都进了）——看这个列表的形状，更像**批量机器翻译铺满**（推论），而不是 138 个母语译者。
- **Wins 11 种，但中文拆成四套**（`zh-HK`／`zh-Hans`／`zh-Hant`／`zh-TW`）——繁体里把香港与台湾分开，是我们该注意的粒度。
- **LaunchOS 21 ／ Droppy 15** 都含 zh-Hans＋zh-Hant。
- **反面：Swish／Alcove／ChainYourMac／MediaMate 基本只有英文**（ChainYourMac 一个 `lproj` 都没有）。
→ 结论：**「中文市场」在刘海这一格不是空白**（Wins／Droppy／LaunchOS／DynamicLake 后来都覆盖了），单纯靠中文不能当差异化；要靠**中文做得比机器翻译好**。

**3. Sparkle 是事实标准，但两条路线并存。** 8/10 内嵌 `Sparkle.framework`；**Droppy 用自家的 `DroppyKit.framework`**，Alcove 也是自家。我们已经把 Sparkle vendor 进来了（`prototype/Vendor/Sparkle.framework`），**方向是对的**。

**4. 「把一部分功能做成插件 bundle」是常见结构，不是特例。** `LaunchOSDockTile.docktileplugin`（Dock 磁贴）、`NotchyWidget.appex`（Widget）、`DockMate` 的 `CalendarPlugin.bundle`／`MusicPlugin.bundle`（它自己的日历与音乐小组件）。→ 功能拆成可独立装载的 bundle，是**包层面的模块化**；我们的「七条线」目前都在一个 App 里。

**5.（只记录）授权后端**：`Paddle.framework` 出现在 **Swish／Wins／DockMate** 三家里；其余是自研（Alcove 明写「validate your license」走本地网路；MediaMate 有 `aps-environment` ＋ iCloud container 做跨设备）。**这一层我们没有碰，也不打算碰。**

**6. Helper 的三种形态**：`Library/LoginItems/*.app`（Wins／DynamicLake 1.0，登录项）、`XPCServices/*.xpc`（Alcove／MediaMate，私有面隔离）、`Helpers/` 目录（Notchy／Droppy）。**同一个需求三种做法，都合规、都公证通过。**

## 三、对我们（推论）

| 我们缺的 | 参照 | 做到什么程度算数 |
| --- | --- | --- |
| **发行版面** | 十份的 DMG 全部 | 一张做好的背景图 ＋ `Applications` 链接 ＋ 排好位置的 `.DS_Store` ＋ volume 图标 |
| **中文粒度** | Wins 的 `zh-HK`／`zh-Hant`／`zh-TW` 分开 | 决定要不要跟（香港繁体 vs 台湾繁体）——我们目前是单数「繁体」 |
| **语言广度** | Notchy 的 138 vs ChainYourMac 的 0 | **不必比数量**（138 那种像机器铺量）；但要决定「不做」并写进文档，而不是漏掉 |
| **功能模块化** | LaunchOS 的 docktileplugin／Notchy 的 Widget | 至少问一次：我们的某条线该不该是独立 bundle／Widget／Extension |
| **登录项与自愈** | Wins／DynamicLake 的 LoginItems ＋ ChainYourMac 的 self-healing engine | 见 [向生产级成熟演进](production-maturity.md) 第 4 条 |

**一句话**：包装这一层没有秘密——**十份件的做法几乎一模一样**（拖曳版面 ＋ Sparkle ＋ 公证），差别只在**语言广度、模块化程度、以及把哪些功能拆出去**。它值得做一遍的原因不是学新招，是**我们这一层目前是空的**。
