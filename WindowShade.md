# WindowShade

这篇文章分两部分：前半是设计说明（面向普通人），后半是**历史考据**（也是大白话，读者不需要任何背景知识，遇到专业词会解释）。想写文章时，考据部分文末的参考资料可以直接引用。

---

## 这是什么

一句话：**把窗口“卷”起来，只留一条标题栏，需要时再展开。**

双击窗口标题栏，窗口内容像卷帘一样收起，原地只剩一条标题栏；再双击，内容原样展开。窗口没有关闭、没有最小化、没有离开桌面——它还在原来的位置，只是暂时把内容收起来了。

## 为什么要做这个

macOS 现有的窗口管理，大多是“把窗口送走”：最小化进 Dock、隐藏应用、Mission Control 概览、Stage Manager 舞台。它们都挺好，但都会把你从当前位置带走，或者改变原来的布局。

WindowShade 补的是中间状态：你只想临时看一眼前面挡着的东西，或者暂时降低窗口噪声，但不想动整个桌面布局。窗口的“壳”（标题栏）留在原地，你随时知道它在哪、怎么打开它。这种能力可以叫“空间记忆”——窗口即使收起来了，它在你的空间里的位置没有变。

| 机制 | 窗口去哪了 | 你保留了 | 代价 |
| --- | --- | --- | --- |
| **WindowShade** | 原地，只剩标题栏 | 位置、标题、快速恢复入口 | 折叠多了需要整理 |
| Dock 最小化 | Dock | 应用/窗口入口 | 恢复点离开了原位置 |
| 隐藏应用 | 整个 app 消失 | 应用状态 | 粒度太粗 |
| Mission Control | 临时重排所有窗口 | 全局窗口关系 | 打断当前操作 |
| Stage Manager | 进入舞台模式 | 任务组连续性 | 弱化原始桌面空间 |
| 窗口平铺 | 改变尺寸和位置 | 规整布局 | 不适合“只看一眼后面” |

WindowShade 不替代这些机制，它填补的是更日常的缝隙：**短暂释放遮挡，同时不破坏窗口排列。**

## 它怎么工作

对用户来说很简单：双击折叠，双击展开，或者用快捷键和菜单。背后的原理也直接：

1. 找到当前窗口，记住它的位置和大小。
2. 截取窗口顶部，做成卷帘条。
3. 把真实窗口藏起来——移出屏幕、隐藏或最小化，取决于应用允不允许。
4. 展开时把窗口放回原处。卷帘条可以拖动，拖到哪，窗口就在哪展开。

两种外观：

- **原貌卷帘**：截真实窗口的顶部，卷帘条长得和原窗口几乎一样，视觉上最像“窗口自己卷起来了”。
- **标准标题栏**：用统一的代理标题栏（应用图标 + 标题 + 交通灯），适合整理和专注，宽度也更规整。

原则是：能用真实截图就用真实截图。手绘一个“假工具栏”出来，一旦和真实应用状态对不上，比普通标题栏更误导。

## 哪些应用需要特殊照顾

macOS 的窗口差异很大，不是每个窗口都像标准文档窗口：

- **便笺**：它自己就有原生的卷起行为，我们让路，不抢。
- **微信、Elpass、Telegram**：自绘标题栏，高度不标准，需要固定裁切，避免把内容切进卷帘条。
- **Adobe 全家**：窗口形态最复杂。After Effects / Premiere 更像整个工作区，折叠时连工作区外壳一起收；Photoshop 有标签式文档和浮动文档，按文档窗口处理；工具面板不参与折叠。
- **快速预览（QuickLook）**：它不是普通 Finder 窗口，是系统预览浮层，有单独的规则（比如它只有“关闭”和“全屏”两颗灯）。
- **Finder、Codex、系统设置、计算器**：各有各的怪脾气，按应用做策略。

## 边界与限制

- 需要两个权限：**辅助功能**（找窗口、移动窗口）和**屏幕录制**（截标题栏、实时预览）。窗口内容不会上传。
- 有些窗口移不出屏幕，只能隐藏或最小化——这是 macOS 的限制，不是产品缺陷。
- 全屏、Split View、Stage Manager、多显示器、沙盒应用，可能需要额外适配。
- 每次折叠都会写一条恢复日志；异常退出后尽量把窗口救回来。它是安全网，不是系统级保证。
- 第三方应用无法真正修改其他窗口的内部绘制，所以实现上用的是“代理卷帘条 + 藏起真实窗口”的办法。

## 设计取向

- **卷帘条是窗口留下的壳，不是小控制面板**：可以拖、可以双击展开、可以悬停预览，但别往里面塞复杂操作。
- **菜单栏安静地列出入口就行**：它负责告诉你有哪些窗口折叠了、怎么展开，不做成仪表盘。
- **失败要安静**：缺权限、没有可折叠的窗口，用短提示和日志；只有成功折叠/展开才放轻量音效。
- **原生感优先**：系统已有成熟语法的地方（比如菜单快捷键），就服从系统，不另起炉灶。

## 一点历史

窗口卷帘来自 classic Mac OS：1990 年前后 Rob Johnston 写了这个第三方工具，苹果后来买下它并入 System 7.5，成了很多老 Mac 用户熟悉的能力。Mac OS X 之后它从系统里消失，窗口管理转向 Dock 最小化、Expose、Mission Control。

后来有几条第三方延续：Unsanity 的 WindowShade X（直接改系统，随系统升级变得脆弱）、WindowMizer（把标题栏增强做成了综合窗口管理器）、Deskovery（折叠到标题栏或缩略图两种模式）。它们都印证了同一件事：现代 macOS 上做 WindowShade，只能靠“代理壳 + 藏起真实窗口”来维持用户心里的那个模型。

想详细了解这段历史、怎么考证的、哪些还没查实，看下面的附录。

---

# 附录：历史考据（大白话版）

> 这一部分假设读者完全不了解 Mac 历史和术语，遇到专业词都会解释。文末的参考资料是研究笔记——条目多、语言密，是写文章时对照引用用的，不是给读者看的正文。

## 先认识两个词

- **标题栏**：窗口最上面那一横条，通常显示窗口名字，还有三个小按钮（关闭、最小化、放大）。
- **卷帘**：把窗口内容收起来、只留标题栏的动作。想象窗帘卷上去，只剩最上面那根杆。

## 窗口卷帘是谁发明的？

现在 macOS 里已经找不到窗口卷帘了，但在 1990 年代的老 Mac 上它很常见。而且它最早不是苹果做的，而是一个叫 Rob Johnston 的程序员写的第三方小工具，装在 System 6.0.7（Mac 在 1990 年代初用的系统）上，给窗口加了一个动作：双击标题栏，内容卷起来只留标题栏；再双击，展开。

后来苹果看上了这个功能，把它买下来，在 1994 年发布的 System 7.5 里直接内置。从此它不再是第三方插件，而是系统自带能力，很多老 Mac 用户都习惯了。到 Mac OS 8（1997 年）时，它被并进系统的“外观管理器”；再到 2001 年的 Mac OS X，苹果重新设计了整个窗口管理——用 Dock（屏幕底部的停靠栏）、Expose（快速浏览所有窗口）这些新东西——卷帘这个功能就从系统里消失了。

这些信息的来源：维基百科的 WindowShade 词条、WindowMizer 官网的历史页、老软件存档站 Macintosh Garden 上保存的 1.1 / 1.2 / 1.3.1 三个版本。

## 它后来为什么消失了？

主要是 Mac OS X 换了思路：苹果认为找窗口、收窗口应该靠 Dock 和 Expose，而不是“把窗口卷起来”这种动作。对老用户来说这是个损失，但对当时的设计来说，新方式更统一。消失不等于没人要——很多用户一直记着这个功能，这也是后来第三方工具出现的原因。

## 还有人想做这件事吗？

有，但从系统里消失后，只能靠第三方做，而且大多比较脆弱：

- **WindowShade X**：Unsanity 公司做的，把卷帘带回早期 Mac OS X。它是靠“改系统内部行为”实现的（这种插件有个专门的名字，叫 haxie），所以每次系统升级都可能坏。2010 年有用户为了等它支持新系统，甚至推迟升级。
- **WindowMizer**：不只是卷帘。它把标题栏扩展成一套完整的窗口管理工具——缩放、透明度、置顶、快捷键、按应用配置——卷帘只是其中一个招牌功能。
- **Deskovery**：提供两种模式：卷到只剩标题栏，或者卷成缩略图。它的文档还讲了一个现实：现代 macOS 不允许第三方真正修改别的窗口，所以只能“做一个假标题栏盖住窗口，把真窗口藏到屏幕外或最小化”。这也是 WindowShade 现在用的办法。

## 现在还有人需要它吗？

有，而且有用户侧的证据：

- 2021 年，TidBITS 论坛上有人讨论：一些用户长期依赖这类工具工作，系统升级后工具坏了，被迫找替代品；把窗口拖到屏幕边缘或角落，被认为只是“将就”。
- 2023 年，科技媒体 Stuff 在评论新 macOS 时，把“窗口卷帘”列为值得苹果复活的老功能，理由是它能看见窗口后面的内容，又不用去 Dock 里重新找。
- 有人做过“单桌面挑战”：把工作里的所有窗口放在一个桌面，问题就从“怎么切换桌面”变成“怎么降低眼前窗口的噪声”——窗口卷帘正好是轻量解法：比隐藏整个应用更局部，比 Stage Manager 更轻。

这些证据说明：这不是怀旧，是有些工作流真的需要这个动作。

## 哪些是确定的事实，哪些还没查实？

**基本可以确定**（多个来源互相印证）：

- 这个交互最早是第三方工具，作者指向 Rob Johnston，发行方是 Interactive Technologies Inc.。
- 苹果买下后，在 System 7.5 里内置。
- 后来在 Mac OS 8 并入外观管理器，到 Mac OS X 消失。

**还没完全查实**：

- Rob Johnston / System 6.0.7 / Interactive Technologies 这条线，目前靠维基、WindowMizer 官网和 Macintosh Garden 三个二手来源互相印证，还没找到更原始的开发者访谈、发行说明或最早发布帖。
- 一个据称 1989 年的发布帖（MacGUI）网页打不开，互联网档案馆也没有对应快照。
- Interactive Technologies 公司官网 1998 / 1999 / 2010 年的快照里只有舞台灯光控制产品，找不到 WindowShade 相关线索。

**如果想继续查**：老 Mac 共享软件档案（Info-Mac / UMich 软件库）、当年的 MacUser / Macworld 纸刊索引、System 7.5 自带文档，以及从老安装包里翻原始说明文件。

## 参考资料（研究笔记，供写作引用）

下面是研究过程中读过的资料。条目较密，是为了写文章时对照引用，不是给读者看的正文。

- Wikipedia contributors. [WindowShade](https://en.wikipedia.org/wiki/WindowShade). 读取定义、System 7.5/Mac OS 8/Mac OS X 迁移、第三方工具和 Rob Johnston 来源说明。
- John Gruber. [Three things OS X could learn from the Classic Mac OS](https://www.macworld.com/article/194590/macat25_classicmacos.html). Macworld, 2009-01-21. 读取作者对 WindowShade 与 Dock 最小化的比较。
- Craig Grannell. [Dashboard is reborn in macOS Sonoma. Apple: bring back these lost Mac features too](https://www.stuff.tv/features/dashboard-is-reborn-in-macos-sonoma-apple-bring-back-these-lost-mac-features-too/). Stuff, 2023-06-10. 读取对 WindowShade/window stashing、标题栏双击和 Dock 最小化可识别性的评论。
- Niléane Dorffer. [Single-Space Challenge: Trying to Manage My macOS Windows All in One Virtual Desktop](https://www.macstories.net/stories/single-space-challenge-trying-to-manage-my-macos-windows-all-in-one-virtual-desktop/). MacStories. 读取单 Space 窗口管理实验及其对低摩擦降噪的启发。
- Paul Horowitz. [Enable Single Application Mode in Mac OS X](https://osxdaily.com/2010/06/07/enable-single-application-mode-in-mac-os-x/). OS X Daily, 2010-06-07；页面显示 2022-01-24 更新。读取 Dock `single-app` 行为及其专注/演示/小屏幕语境。
- Apple. [Organize your Mac desktop with Stage Manager](https://support.apple.com/guide/mac-help/use-stage-manager-mchl534ba392/mac). 读取 Stage Manager 的官方定位：当前 app 居中、最近 app 在侧边、可组成工作组。
- David Nield. [Apple’s macOS Sequoia lets you snap windows into position — here’s how](https://www.theverge.com/24273664/apple-macos-sequoia-windows-snap-how-to). The Verge, 2024-10-10. 读取 Sequoia window tiling 与第三方窗口平铺工具背景。
- Charlie Sorrel. [Moom Helps You Control The Messy Windows on Mac](https://www.lifewire.com/moom-window-control-mac-8700400). Lifewire, 2024-08-23. 读取寻找窗口、反复 resize、Expose/Stage Manager/tiling 并存等用户痛点。
- Steven Jeuris, Paolo Tell, Steven Houben, Jakob E. Bardram. [The Hidden Cost of Window Management](https://arxiv.org/abs/1810.04673). arXiv, 2018-10-10. 读取窗口打开、resize、定位、切换和任务切换成本的研究问题。
- Tyler Sable. [System 7.5 and Mac OS 7.6: The Beginning and End of an Era](https://lowendmac.com/2014/system-7-5-and-mac-os-7-6-the-beginning-and-end-of-an-era/). Low End Mac, 2014-06-27；页面元数据显示 2025-05-10 修改。读取 System 7.5 将 WindowShade 等第三方/共享软件功能纳入系统的上下文。
- Ellen Siever. [What Is the X Window System](https://web.archive.org/web/20180518025028id_/http://www.linuxdevcenter.com:80/pub/a/linux/2005/08/25/whatisXwindow.html). LinuxDevCenter/O'Reilly, 2005-08-25；使用 Internet Archive 快照。读取 X 与 window manager 的职责划分，以及 shading 属于 window manager 行为的说明。
- Wikipedia contributors. [Appearance Manager](https://en.wikipedia.org/wiki/Appearance_Manager). 用于交叉核对 WindowShade 被购买并并入 System 7.5、在 Appearance Manager 语境下出现的描述。
- Wikipedia contributors. [Multiple-document interface](https://en.wikipedia.org/wiki/Multiple-document_interface). 读取 MDI/SDI/TDI 定义、Macintosh document-centric 描述、早期 Mac 应用窗口成组前置、以及 Photoshop 作为特殊案例的讨论；作为术语背景使用，不作为 Apple 一手规范。
- Microsoft. [SDI and MDI](https://learn.microsoft.com/en-us/cpp/mfc/sdi-and-mdi?view=msvc-170). 读取 MFC 对 SDI/MDI 的定义：SDI 一次一个 document frame，MDI 在同一应用实例中打开多个 document frame；用于避免把 macOS document-centric 简化成朴素 SDI。
- Microsoft. [Window Features](https://learn.microsoft.com/en-us/windows/win32/winmsg/window-features). 读取 overlapped window、child window、owned window 与 z-order 的系统定义，用于理解 Windows MDI frame / child window 语义和 Adobe 跨平台历史包袱。
- Adobe. [Rearrange document windows in Photoshop](https://helpx.adobe.com/photoshop/desktop/get-started/learn-the-basics/rearrange-document-windows.html). 读取 Photoshop 对 document tabs、undock、dock、tile、`Float in Window` 与 `Float All In Windows` 的官方说明。
- Adobe. [Workspaces, panels, and viewers in After Effects](https://helpx.adobe.com/after-effects/using/workspaces-panels-viewers.html). 读取 After Effects workspace、workspace bar、panel docking/grouping/floating 的官方说明，用于把 AE/Premiere 类应用识别为 application-frame/workspace 型窗口。
- Scott Gilbertson. [Mac and Windows Users Agree: Adobe's New UI Design Sucks](https://www.wired.com/2008/06/mac-and-windows-users-agree-adobe-s-new-ui-design-sucks/). Wired, 2008-06-02. 读取 CS4 beta 时用户对 Adobe 跨平台自绘控件、接管桌面、偏离平台习惯的争议；作为 Adobe unified UI 历史背景。
- 王译锋. `在 macOS 中关闭应用窗口，为什么默认设定不是完全退出？ - 知乎.pdf`，本地 PDF，生成日期 2026-06-21。读取 macOS 应用/窗口/文档分层、classic Mac application-grouped window 行为、以及评论区对 Photoshop 早期 Mac/Windows MDI 历史的补充；作为社区论述和问题提示使用。
- RGB World / WindowMizer. [History of WindowShade](https://www.windowmizer.com/windowshade-history). 页面版权显示 2025。读取厂商叙述；因其同时是产品站，只作为带有厂商视角的参考。
- Macintosh Garden. [WindowShade](https://macintoshgarden.org/apps/windowshade). 读取 WindowShade 1.1、1.2、1.3.1 归档信息、作者/发行方/兼容系统标注，以及说明文档的卷帘隐喻。
- Charles W. Moore. [Waiting for WindowShade X before Going Snow Leopard](https://lowendmac.com/misc/10mr/waiting-for-windowshade-x.html). Low End Mac, 2010-02-01. 读取早期 OS X 用户依赖 WindowShade X、推迟升级 Snow Leopard、认为 Dock 缩略图无法替代 windowshading 的叙述。
- TidBITS Talk. [Alternate apps for 'WindowShade' effect?](https://talk.tidbits.com/t/alternate-apps-for-windowshade-effect/14614/10). 讨论开始于 2021-01-07，最后可见帖为 2021-11-09。读取 WindowMizer 稳定性抱怨、替代工具寻找和用户退而求其次的做法。
- 23mac / 爱上MAC. [WindowMizer for Mac 窗口管理大师：核心详解与高效操作指南](https://www.23mac.com/blogs/jiaocheng/21522/). 页面元数据显示 2026-06-07 发布。作为中文二手教程，读取 WindowMizer 的标题栏按钮、手势、快捷键、按应用配置和权限故障排查。
- Neomobili. [Deskovery](https://www.neomobili.com/products/deskovery/), [Documentation](https://www.neomobili.com/products/deskovery/deskovery-documentation/), [Changelog](https://www.neomobili.com/products/deskovery/deskovery-changelog/), [F.A.Q.](https://www.neomobili.com/products/deskovery/deskovery-f-a-q/). 读取 minimize in place/window shading 定义、标题栏/缩略图两种模式、权限需求、代理实现说明、版本记录和授权信息。
- RGB World. `Introduction to WindowMizer for macOS.mp4` 与同名 `.srt` 字幕，本地文件。读取视频元数据、关键帧和字幕时间轴；详细分析见 [WindowMizer-video-analysis.md](WindowMizer-video-analysis.md)。
- Internet Archive / Wayback Machine. [Macintosh Garden WindowShade 2009-06-16 快照](https://web.archive.org/web/20090616131955/http://macintoshgarden.org:80/apps/windowshade). 用于核验 Macintosh Garden 归档页至少在 2009 年已被存档。
- Internet Archive / Wayback Machine. [Interactive Technologies 1998-12-05 快照](https://web.archive.org/web/19981205010646/http://www.interactive-online.com:80/), [1999-11-17 快照](https://web.archive.org/web/19991117142936/http://interactive-online.com:80/) 与 [2010-01-07 快照](https://web.archive.org/web/20100107092125/http://www.interactive-online.com/). 已读快照主要描述舞台、建筑和娱乐照明控制产品，未发现 WindowShade、Rob Johnston 或 classic Mac 软件线索。
- Internet Archive / Wayback Availability API. [MacGUI 1989 WindowShade 1.1 链接核验查询](https://archive.org/wayback/available?url=https://macgui.com/usenet/?author=Robert+George+Johnston+Jr.%26group=14%26id=40850). 本次查询没有返回可用快照。
