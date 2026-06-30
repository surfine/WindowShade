# WindowShade 设计笔记

资料整理日期：2026-06-14  
最近整理：2026-06-28

## 核心定义

WindowShade 是 classic Mac OS 的窗口折叠交互：双击窗口标题栏后，窗口内容像卷帘一样收起，只留下标题栏；再次双击，内容从原处展开。

它解决的不是关闭窗口，也不是把窗口送进 Dock，而是在“窗口完全展开”和“窗口离开当前桌面”之间补一个中间态：内容暂时退场，窗口的身份和位置仍留在原处。

一句话说：**WindowShade 是保留空间记忆的临时折叠。**

## macOS 窗口模型的启发

macOS 的历史语义一直区分应用、窗口和文档：关闭窗口不等于退出应用，窗口也不只是应用进程的外壳。更准确地说，classic Mac / macOS 传统不是朴素 SDI，而是偏 document-centric、application-grouped 的窗口模型：一个应用可以拥有多个文档窗口，应用生命周期、窗口生命周期和文档生命周期彼此分离。

这和 Windows 式 MDI/SDI 术语不是一一对应关系。经典 Mac 没有 Windows MDI 那种必须装下所有子窗口的父 frame window；但它也不是“一个窗口就是一个应用实例”的朴素 SDI。早期 Mac 甚至会把同一应用的多个窗口作为一组带到前台，这说明窗口在用户模型中既是文档入口，也是应用组的一部分。

WindowShade 应该顺着这套模型设计，而不是把折叠理解成 Windows 式的“关掉这个窗口就结束这个任务”。

因此，WindowShade 的产品语义是逐窗口的：

- 折叠不是退出应用，菜单栏工具本身也不应该替用户管理应用生命周期。
- 折叠不是关闭文档，恢复应尽量回到同一个窗口对象，而不是重新打开。
- 折叠不是隐藏应用；即使实现上偶尔需要 app hide 作为 fallback，用户模型仍是“这个窗口被卷起”。
- 折叠条是窗口的临时壳，交通灯、缩放、最小化等系统动作应该转发给真实窗口，而不是由 WindowShade 重新定义。

## Adobe 应用的特殊性

Adobe 系软件不能按“普通 macOS 文档窗口”统一处理。它们的历史包袱来自三股力量叠加：早期 Mac 式 document/window 分离、Windows MDI frame window、以及 CS4 以后更强的跨平台统一界面。结果是 Photoshop、Illustrator、InDesign、After Effects、Premiere 等应用在 macOS 上经常呈现 application frame、tabbed document、floating document、dockable panels/workspace 的混合形态。

因此，Adobe 适配的第一原则不是“给 Adobe 一个固定标题栏高度”，而是先判断窗口语义：

- `applicationFrame`：例如 After Effects / Premiere 的主工作区窗口。标题栏下方还有 Adobe 自己的 application/document frame、workspace bar、panel group 等。用户把这一整段上方 chrome 当成“工作区外壳”。折叠时应保留比标准标题栏更高的应用 chrome，避免只剩一条 macOS 原生标题栏而丢失项目/工作区身份。
- `tabbedDocumentFrame`：例如 Photoshop / Illustrator / InDesign 默认文档 tab 嵌在主窗口内。折叠外层 frame 语义上是折叠整个工作区，而不是单个 PSD/AI/INDD 文档。这里应尽量保留 document tabs 所在的上方 band，让用户仍能识别当前文档组。
- `floatingDocumentWindow`：用户执行 `Window > Arrange > Float in Window` 或 `Float All in Windows` 后，文档更接近独立窗口。这时才适合按普通 document window 做 WindowShade：保留真实文档标题栏/文档 tab 条，逐窗口折叠和恢复。
- `floatingPanel`：工具面板、颜色面板、效果控件等不应默认参与 WindowShade。它们已经是 Adobe workspace 的子结构，折叠它们会把 panel 管理和窗口管理混在一起，容易破坏专业软件的布局。

实现上应给 Adobe 单独的 `AdobeChromeProfile`：

- 用 bundle id 前缀 `com.adobe.` 进入 Adobe 兼容路径，但不要只靠 app 名判断。
- 优先通过 AX role/subrole、窗口尺寸、标题、是否存在 document tab / toolbar / panel group、截图中的上方 chrome band 来分类。
- 对 After Effects / Premiere 默认使用 `applicationFrame`；折叠高度应覆盖原生标题栏 + Adobe 灰色 frame band / workspace header，且 hover preview 才显示完整工作区。
- 对 Photoshop / Illustrator / InDesign 默认先识别是否存在 floating document；若不是 floating document，则按 `tabbedDocumentFrame` 处理，保留文档 tab 与应用 frame。
- 对 Adobe 的 panel/palette 窗口默认忽略；只有用户显式触发当前聚焦 panel 且它有稳定标题栏时，才考虑折叠。
- 双击命中区可以扩展到 Adobe application frame 的上方 band，但视觉卷帘条不能盲目截取整个内容区；命中区和保留高度应分开建模。
- 恢复时优先恢复同一个 `CGWindowID`；如果 Adobe 重建窗口导致 id 改变，再用 pid + 标题 + 几何 + document title 近似匹配。

这一路线承认 Adobe 的 UI 是混合体：不是 classic Mac 的纯文档窗口，也不是单纯 Windows MDI，而是专业软件为跨平台、一致 workspace、面板停靠和多文档编辑折中出来的结构。WindowShade 要适配的是用户看到的工作区外壳，而不是教条地寻找“真正的标题栏”。

## 为什么有价值

现代 macOS 已经有 Dock 最小化、隐藏应用、Mission Control、Stage Manager 和窗口平铺，但它们大多会把用户带到另一个位置、另一个模式，或改变原来的窗口布局。

WindowShade 的价值恰好相反：

- 用户只想看一眼背后的东西，不想重新整理桌面。
- 窗口入口留在原地，不需要去 Dock 或概览里找回来。
- 标题栏继续显示窗口身份，适合作为轻量上下文标记。
- 操作是局部、可逆、逐窗口的，不表达“任务完成”。

这让 WindowShade 更接近“把遮挡物卷起来”，而不是“把窗口拿走”。

## 与其他机制的区别

| 机制 | 窗口去了哪里 | 用户保留了什么 | 主要代价 |
| --- | --- | --- | --- |
| WindowShade | 原地，只剩标题栏 | 位置、标题、快速恢复入口 | 折叠太多时需要轻量整理 |
| Dock 最小化 | Dock | 应用/窗口入口 | 恢复点离开原位置 |
| 隐藏应用 | 整个 app 消失 | 应用状态 | 粒度太粗 |
| Mission Control / Expose | 临时重排全局窗口 | 全局窗口关系 | 打断当前局部操作 |
| Stage Manager | 进入舞台/工作组模式 | 任务组连续性 | 弱化原始桌面空间关系 |
| Sequoia Window Tiling | 改变窗口尺寸和位置 | 规整布局 | 不适合“只看一眼后面” |

WindowShade 不替代这些机制。它填补的是更日常、更细小的缝隙：**短暂释放遮挡，同时不破坏窗口排列。**

## 现代实现的产品原则

### 1. 空间连续性优先

折叠条的位置就是用户对窗口位置的记忆。拖动折叠条，未来展开位置应该跟着变；但临时整理卷帘条不应改写用户原来的空间安排。

逐窗口身份也属于空间连续性的一部分。实现应优先按 `CGWindowID` 追踪同一个真实窗口，再退回到标题或几何近似；不能因为同一应用有多个窗口，就把折叠或恢复退化成应用级操作。

### 2. 标题栏是壳，不是小控制面板

折叠条应该像窗口留下来的壳：可拖动、可双击展开、可悬停预览。不要给每条折叠栏塞进右键菜单或复杂操作入口。管理入口集中在菜单栏和快捷键。

### 3. 菜单栏是入口，不是仪表盘

菜单栏只负责列出已折叠窗口并提供 `⌃⌘1...9` 这样的临时入口。它应该服从 macOS 菜单自己的语法：标题在正文列，快捷键在系统快捷键列，选中态和间距交给 AppKit。

不要为了图标、卡片、自绘行或手工快捷键列，把菜单变成一个小型窗口管理 dashboard。桌面上的折叠条已经承担空间锚点；菜单栏只要安静地把入口列出来。

### 4. 原貌卷帘和标准标题栏分工不同

`原貌卷帘` 的价值是视觉真实性：它保留真实窗口 chrome 的截图，因此不应在整理态裁切、压缩或重绘。

`标准标题栏` 是语义代理：它可以在整理态临时缩到足够容纳标题的宽度，因为整理只是 housekeeping；展开或转发真实窗口操作时，仍应回到整理前保存的位置和语义。

真实 toolbar 与标准标题栏的优先级应保持清楚：

- 如果 ScreenCaptureKit 能裁出健康的真实 toolbar，就显示真实 toolbar。尤其是 iPhone Mirroring、Adobe、Safari 这类有自绘或扩展标题栏的窗口，真实 chrome 本身就是窗口身份的一部分。
- 不要为了“看起来像原 app”去手绘假的 toolbar、假按钮或 app-specific 装饰。假 chrome 一旦和真实 app 状态不一致，会比普通标准标题栏更误导。
- fallback 的目标不是复刻某个 app，而是提供一个可靠、普通、可交互的标准标题栏代理。
- 降级判断应尽量基于截图本身是否可靠，而不是只基于 app 名或 AX 语义。AX 可能报告存在标题栏，但截图中的标题栏已经变成悬浮胶囊、孤岛、半透明残影或缺少左侧连续承托。
- 对“悬浮胶囊”这类坏截图，可以用像素健康检查识别：左侧 traffic-light 背后没有连续标题栏材质，而中部/右侧有大面积 capsule material，说明它不是可保真的 toolbar，应 fallback。
- 检测必须保守。真实 toolbar 的左侧、中部、右侧通常会形成连续承托，即便没有 AX window-management 能力，也不应因为 `hasToolbar=false` 或 `windowManagement=none` 就直接降级。

### 4.1 QuickLook 是特殊窗口，不是普通 Finder 窗口

QuickLook 表面上属于 Finder，但交互语义更接近系统预览浮层。WindowShade 不能把它当成普通 Finder 窗口处理，否则会出现 Finder 窗口被移动、被全屏、或 proxy 标题栏跑到另一个 Space 的错觉。

QuickLook 适配应遵守这些约束：

- QuickLook 折叠后，proxy 的交通灯语义属于 QuickLook 预览本身，不属于 Finder。点击关闭只清掉 QuickLook proxy；点击全屏应重新打开 QuickLook 并作用于新出现的 QuickLook 窗口。
- 不要给 QuickLook 画假的 toolbar 或假的全屏按钮。能显示真实截图就显示真实截图；不能保真时才 fallback 到普通标准标题栏。标准标题栏也必须使用 AppKit 原生交通灯，不要在原生绿灯上叠自绘 glyph。
- QuickLook 只有关闭和全屏两颗灯。proxy 不应凭普通窗口习惯塞进第三颗最小化按钮；第二颗灯视觉上是全屏，但 Accessibility 底层可能仍暴露为 `AXZoomButton`，不能用名字反推产品语义。
- QuickLook 原貌卷帘高度必须固定。AX 有时会把 PPT 缩略图、预览内容或顶部内容区算进标题栏高度，导致 `finalBarH` 漂到 105pt 一类错误值；原貌 QuickLook chrome 应固定为 38pt，并把交通灯命中区固定到这条 chrome 的中线。
- QuickLook proxy 和真实 QuickLook/Finder 窗口不能长期同框。一旦真实源窗口已经可见，proxy 和 preview 应立即让位，而不是继续浮在真实窗口上。
- QuickLook 全屏不要依赖单一 `AXPress` 返回值。`AXPress(AXZoomButton)` 可能返回成功但只做 zoom 或没有进入 fullscreen Space。必要时应使用真实按钮坐标的人类式点击，并在点击后验证 `AXFullScreen`；验证失败再考虑重试或快捷键兜底。

### 5. 失败反馈要安静

WindowShade 应该像系统里一个小 affordance，而不是一个频繁提醒用户的窗口管理器。普通失败，如没有可折叠窗口、缺权限、截图不可用，应使用短提示和日志；成功折叠/展开才使用用户配置的轻量音效。

## Stickies 的启发

Stickies 是现代 macOS 中仍保留 WindowShade 精神的第一方遗存样本。它的便条可以折叠成一条窄控制带，保留颜色、位置和可恢复入口；它不是把窗口送进 Dock，也不是生成一个缩略图。

对当前原型的启发：

- 对 `com.apple.Stickies` 应让路，委派给它自己的折叠行为。
- “尊重窗口自己的 chrome”比“统一成一种漂亮标题栏”更重要。
- 折叠是逐窗口、逐对象状态；恢复不是重新打开窗口，而是把同一个窗口从折叠几何恢复到展开几何。
- 动画应服务于“内容卷起，壳留在原处”，而不是 Dock Genie 或 app hide。

## 风险与边界

- 可发现性：现代用户未必知道双击标题栏可以折叠，因此需要菜单项、快捷键或设置入口辅助。
- 标题栏堆积：折叠太多时会产生横条杂乱，需要整理、悬停预览、置顶/半透明等辅助，但这些辅助不能变成完整窗口管理系统。
- 现代 macOS 限制：第三方 app 很难真正改变其他应用窗口的内部绘制，因此实现上常需要代理壳、离屏/隐藏/最小化策略、辅助功能权限和屏幕录制权限。
- 兼容性：自绘标题栏、沙盒 app、多显示器、全屏空间、Stage Manager、Split View 都需要内部兼容层；不应把这些复杂性暴露成用户必须管理的偏好。

## 设计原则摘要

- 临时状态应该便于恢复，恢复入口就在原地。
- 窗口管理不只有显示/隐藏二元状态，也可以有“保留壳、收起内容”的中间态。
- 空间记忆是生产力界面的一部分，减少位置迁移就能减少认知成本。
- 原生感优先于可控感：系统已有成熟语法的地方，例如菜单快捷键列，应服从系统。
- WindowShade 的美感来自少做一点，不是把窗口管理能力全都搬进来。

## 历史与考据

### Classic Mac OS

WindowShade 最初并非苹果从零设计。维基条目和 WindowMizer 历史页都指向 Rob Johnston 为 System 6.0.7 编写的第三方工具；WindowMizer 历史页进一步把开发者身份指向 Interactive Technologies, Inc.。苹果后来买下权利，并在 System 7.5 中把它作为控制面板扩展纳入系统。

System 7.5 后，WindowShade 成为 classic Mac OS 用户熟悉的标准能力。Low End Mac 在回顾 System 7.5 和 Mac OS 7.6 时，把它列为用户可能已经喜欢的功能：任意窗口可通过双击标题栏折叠到只剩标题栏，也可配合修饰键使用。

Macintosh Garden 保存了 WindowShade 1.1、1.2、1.3.1 三个 classic Mac 版本，标注作者为 Rob Johnston，发行方为 Interactive Technologies Inc.，面向 68k Mac、System 6.x 到 System 7.x。归档页也转述了随附说明中的卷帘隐喻：窗口内容像旧式卷帘一样收起，标题栏留在原处。

到 Mac OS 8，WindowShade 不再作为独立控制面板出现，而是纳入 Appearance Manager。到 Mac OS X，这项能力从系统中消失，窗口管理转向 Dock 最小化、Expose 和后续的 Mission Control / Stage Manager。

### 第三方延续

Unsanity 的 WindowShade X 把这一能力带回早期 OS X，但它属于 haxie 式系统修改，随系统升级变得脆弱。Low End Mac 2010 年文章记录了用户因 WindowShade X 尚未支持 Snow Leopard 而推迟升级，并认为 Dock 缩略图无法替代完整标题栏的可识别性。

WindowMizer 是另一条路线。它没有只复刻折叠窗口，而是把标题栏增强扩展成窗口缩放、透明度、置顶、多显示器移动、鼠标手势、快捷键和按应用配置。本地视频 `Introduction to WindowMizer for macOS.mp4` 中，开发者把 roll up windows 称为 flagship feature，但产品重心已明显变成综合窗口管理。

Deskovery 使用 minimize in place / window shading 叙述，提供折叠到标题栏和折叠到缩略图两种模式。它的文档说明现代实现通常需要辅助功能权限和屏幕录制权限，并透露其 window shading 是在真实窗口副本上完成，源窗口会被移到屏幕外或最小化到 Dock。这说明现代 macOS 上的 WindowShade 往往只能通过代理壳维持心理模型。

TidBITS Talk 2021 年讨论提供了用户侧证据：有人长期依赖 WindowShade/WindowMizer，但在 Mojave 上遇到稳定性问题后被迫寻找替代；把窗口挪到大屏边缘或角落被认为只是退而求其次。这说明 WindowShade 的价值不是纯怀旧，而是某些工作流中的真实需求。

### 现代语境

Stuff 在 2023 年评论 macOS Sonoma 桌面小组件时，把 WindowShade/window stashing 列为值得复活的旧功能，理由是它能快速看见窗口后面的内容，且避免 Dock 最小化带来的重新寻找成本。

MacStories 的 Single-Space Challenge 从现代单桌面工作流侧面印证了这一点：当用户把所有窗口放在一个 Space 中，问题就从“如何切换桌面”变成“如何降低眼前窗口的噪声”。WindowShade 的优势是比隐藏应用更局部，比 Stage Manager 更轻，比窗口平铺更不破坏自由重叠关系。

OS X Daily 对 Single Application Mode 的介绍说明，“只让当前 app 主导视野”是长期存在的需求；但系统级 single-app 会让其他窗口离开画布。WindowShade 更适合做 soft version：让不用的窗口退到低声量，而不是消失。

## 参考文献与阅读记录

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

## 尚待进一步核验

Rob Johnston / System 6.0.7 / Interactive Technologies Inc. 这条来源有维基、WindowMizer 和 Macintosh Garden 的旁证，但仍缺少更原始的开发者访谈、发行说明或可访问的早期发布帖。

当前核验状态：

- WindowMizer 历史页列出的 MacGUI 1989 年 WindowShade 1.1 发布帖，当前站点直连失败；Wayback Availability API 对精确 URL 没有返回可用快照。
- Macintosh Garden 的 WindowShade 归档页有 2009-06-16 Wayback 快照；这只能证明归档页较早存在，不能把页面中的作者/发行方/版本信息直接提升为 1989/1992 年的一手证据。
- `interactive-online.com` 在 1998、1999、2010 年有 Wayback 快照，但已读快照描述的是舞台、建筑和娱乐照明控制产品，未出现 WindowShade、Rob Johnston 或 Mac 软件语境。

若要继续做严谨历史考证，下一步应查 classic Mac shareware 档案、旧版 Info-Mac/UMich 软件库、MacUser/Macworld 纸刊索引、Apple System 7.5 随附文档，以及能否从 MacGUI、Usenet 或压缩包内原始 readme 中恢复早期发布记录。
