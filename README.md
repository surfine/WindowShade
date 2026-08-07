# WindowShade

WindowShade 是一个 macOS 菜单栏工具原型，用来把当前窗口“原地卷起”。代码里的核心动作叫 `shade` / `unshade`：折叠时保留一条标题栏式的卷帘条，隐藏或移走真实窗口；展开时再把真实窗口恢复到原位置。

这个项目不是一个泛泛的窗口管理器。它要补的是 macOS 里一个很具体的中间态：窗口暂时不需要完整显示，但也不该离开当前桌面、跑去 Dock、进入 Mission Control，或改变原来的布局。

从 macOS 的应用 / 窗口 / 文档分层来看，WindowShade 也不是“关闭”“退出”或“隐藏应用”的替代品。macOS 传统更接近 document-centric、应用分组的窗口模型，而不是朴素 SDI；WindowShade 给单个窗口增加一个可逆的临时折叠态：应用继续存在，文档没有被关闭，窗口身份和空间位置仍留在桌面上。

## 代码现状

当前仓库只保留一条主线实现：

- `prototype/WindowShade.swift`：WindowShade 主实现。它通过 Accessibility API 找到窗口，通过 ScreenCaptureKit 截取窗口顶部，用 AppKit 无边框覆盖层生成卷帘条，再按不同策略隐藏、移走或最小化真实窗口。

早期曾有一条“直接把真实窗口高度压到标题栏”的 MVP 路线。它证明了概念，但受应用最小窗口高度限制，内容也只是被压扁，不是真正消失，无法达到 classic WindowShade 的产品目标。因此这条路线已经移除，不再作为维护对象。

`prototype/build.sh` 编译的是 `WindowShade.swift`，并把产物替换进现有 `WindowShade.app`。脚本刻意保留 app bundle、`Info.plist` 和资源，并要求使用固定 Apple Development 证书签名，目的是避免频繁重建 bundle 后重置 macOS TCC 权限。

## 用户能做什么

这些能力来自 `WindowShade.swift` 的菜单、快捷键和偏好设置代码：

- 菜单栏常驻，不进入 Dock。
- `⌃⌘C` 折叠或展开当前窗口。
- 双击普通窗口标题栏可以折叠；双击卷帘条可以展开。
- 菜单栏图标旁显示已折叠窗口数量。
- 菜单列出已折叠窗口，并用 `⌃⌘1` 到 `⌃⌘9` 快速展开对应窗口。
- `⌃⌘0` 在“原貌卷帘”模式下整理卷帘条；在“标准标题栏”模式下触发当前 app 专注整理。
- 支持“全部展开”。
- 支持悬停预览和菜单悬停预览。
- 支持偏好设置：卷帘样式、标题栏双击、卷帘条置顶、半透明、折叠/展开音效、权限入口。

偏好设置里的两个外观模式对应 `ShadeAppearanceMode`：

- `nativeScreenshot`：原貌卷帘。截取真实窗口顶部，尽量保留原窗口 chrome 的样子。
- `proxyTitleBar`：标准标题栏。用语义代理标题栏显示应用图标、标题和交通灯，适合整理、专注和统一宽度。

## 它怎么工作

主流程在 `WindowShade.swift` 里很直接：

1. `toggle()` 找到当前聚焦窗口。
2. `windowID(of:)` 把 AX 窗口映射到 `CGWindowID`。
3. 如果窗口已经在 `shaded` 字典里，就调用 `unshade` 展开。
4. 如果还没折叠，就调用 `shade` 创建卷帘条并隐藏真实窗口。
5. `ShadeState` 记录原始位置、尺寸、窗口元素、覆盖层、预览图、隐藏方式和 app 信息。
6. `restoreAll()` 和菜单项会逐个调用 `unshade`，把窗口恢复回来。

折叠时并不是每个应用都用同一种隐藏方式。代码里有 `ShadePolicy`：

- `offscreenThenFallback`：优先把窗口移到屏幕外，失败后走备用路径。
- `offscreenForLivePreview`：为了保留动态预览，优先屏幕外停放。
- `hiddenIfSingleWindowElseMinimized`：单窗口 app 可隐藏，多窗口 app 尽量只最小化对应窗口。

这说明 WindowShade 的实现目标不是“强行统一所有窗口”，而是在 macOS 限制下尽量维持同一个用户模型：卷帘条在原地，真实窗口可恢复。

这里的 `hiddenIfSingleWindowElseMinimized` 是实现层 fallback，不是产品语义。即使底层不得不用 app hide 或最小化来绕过 macOS 限制，用户面对的模型仍然应该是“这个窗口被卷起来了”，而不是“这个应用被收起了”。

## 兼容策略

`AppCompatibilityKind` 里已经把一些应用单独列出：

- Finder
- Codex
- System Settings
- WeChat / 微信
- Elpass
- Adobe 应用
- Stickies / 便笺
- Calculator / 计算器

这些分支不是装饰代码，而是现代 macOS 窗口差异带来的实际处理。比如 Stickies 自带类似 classic WindowShade 的原生折叠行为，所以代码里会让路，调用 `performNativeStickiesShade` 或放行它自己的双击标题栏逻辑。微信、Elpass 这类非标准窗口则有固定 chrome 高度或特殊标题栏裁切策略，避免卷帘条截到内容区。

Adobe 应用需要更特殊的判断。Photoshop、Illustrator、InDesign、After Effects、Premiere 等经常混合 application frame、tabbed document、floating document 和 dockable panels。WindowShade 不应把它们一律当普通 macOS 文档窗口：After Effects / Premiere 更像折叠整个 workspace frame；Photoshop 等在 floating document 模式下才更接近逐文档窗口；工具面板默认不应参与折叠。详细策略见 `WindowShade.md` 的 “Adobe 应用的特殊性”。

## 权限与限制

这份代码依赖两个系统权限：

- 辅助功能：读取、移动、聚焦、恢复其他 app 的窗口。
- 屏幕录制：截取真实标题栏和窗口预览。

它还使用了这些系统能力：

- AppKit 菜单栏、窗口和覆盖层。
- Carbon 全局快捷键。
- ApplicationServices / AXUIElement。
- ScreenCaptureKit 截图。
- QuartzCore 绘制和图层效果。

现代 macOS 不允许第三方 app 真正修改其他 app 的窗口内部绘制，所以当前实现采用“代理卷帘条 + 隐藏真实窗口”的方式。代码里也能看到几个边界：

- `_AXUIElementGetWindow` 是私有 API，用来补强 AX 窗口到 `CGWindowID` 的映射。
- 全屏、Split View、Stage Manager、多显示器、自绘标题栏和沙盒应用都可能需要专门兼容。
- 有些窗口不能稳定移到屏幕外，只能隐藏或最小化。
- `ShadeJournalEntries` 会记录折叠状态，尽量在异常退出或窗口丢失后救回窗口，但它不是系统级事务保证。

## 历史渊源

WindowShade 的交互来自 classic Mac OS。早期第三方 WindowShade 工具让用户双击标题栏，把窗口像卷帘一样收起，只留下标题栏；再次双击展开。后来这类能力进入 System 7.5，成为许多 classic Mac 用户熟悉的窗口操作。

Mac OS X 之后，系统窗口管理转向 Dock 最小化、Expose、Mission Control、Stage Manager 和窗口平铺。这个项目的代码选择回到 classic WindowShade 的核心模型：不把窗口送走，而是在原地留下一个可恢复的壳。

仓库里的 `WindowShade.md` 和 `WindowMizer-video-analysis.md` 记录了历史和参照产品。尤其是 WindowMizer 视频分析提到，它把 roll up windows 当作 flagship feature，并强调不必去 Dock 搜索窗口。这一点也正是当前代码反复维护 `shaded` 状态、菜单列表、卷帘条位置和恢复日志的原因。

## 今天的价值

从代码看，WindowShade 的价值不是“多一个窗口管理模式”，而是把一个常见动作做轻：

- 临时看后面的窗口，不重排桌面。
- 暂时降低窗口噪声，但保留标题、位置和入口。
- 让多个任务以卷帘条待命，而不是散落到 Dock 或别的空间。
- 通过快捷键和菜单快速恢复，不重新寻找窗口。

这也是为什么当前实现花了很多代码处理标题栏高度、预览、菜单快捷键、应用兼容和恢复日志：它真正要保护的是用户对窗口位置的记忆。

换句话说，WindowShade 继承的是 macOS 将应用、窗口和文档分开的传统：关闭、退出、隐藏、最小化都已有系统语义；WindowShade 只负责补上“内容卷起，壳仍在原地”的窗口级状态。

## 编译与运行

已有 `WindowShade.app` bundle 时：

```sh
cd prototype
./build.sh
```

直接编译源码：

```sh
cd prototype
swiftc -O -o windowshade WindowShade.swift \
  -framework Cocoa -framework Carbon -framework ApplicationServices \
  -framework ScreenCaptureKit -framework QuartzCore -framework CoreText \
  -framework ServiceManagement
```

首次运行后，需要在系统设置中授予辅助功能和屏幕录制权限。

## 140 字介绍

WindowShade 是一个 macOS 菜单栏工具原型，用 `⌃⌘C` 或双击标题栏把窗口原地卷起。当前主力代码会截取真实标题栏生成卷帘条，再隐藏或移走真实窗口。窗口位置、标题和恢复入口留在桌面上，适合临时看后面内容、降低噪声，又不破坏布局。

## 280 字介绍

WindowShade 复兴 classic Mac OS 的窗口卷帘交互，但当前实现以现代 macOS 能允许的方式完成：`WindowShade.swift` 通过 Accessibility API 找窗口，用 ScreenCaptureKit 截取真实标题栏，生成 AppKit 覆盖层作为卷帘条，再把真实窗口隐藏、移到屏幕外或最小化。用户可以用 `⌃⌘C` 折叠/展开，也可以双击标题栏；菜单栏会列出已折叠窗口，支持 `⌃⌘1` 到 `⌃⌘9` 快速恢复。它解决的是“不想关闭、不想隐藏、不想去 Dock 找，只想暂时卷起窗口”的问题。

## 500 字介绍

WindowShade 是一个 macOS 菜单栏工具原型，目标是把 classic Mac OS 时代的 WindowShade 交互带回现代桌面。它不做完整窗口管理器，而是专注一个动作：把当前窗口原地卷起，只留下标题栏式卷帘条；需要时再从原处展开。

当前主力实现是 `WindowShade.swift`：它读取聚焦窗口，映射到 `CGWindowID`，用 ScreenCaptureKit 截取窗口顶部，用 AppKit 覆盖层生成卷帘条，再根据 `ShadePolicy` 把真实窗口移到屏幕外、隐藏或最小化。`ShadeState` 保存窗口原始位置、尺寸、覆盖层、预览图和隐藏方式，展开时由 `unshade` 恢复。早期直接压缩真实窗口高度的 MVP 路线已经移除，因为它受最小窗口高度和绘制限制，无法提供干净的卷帘体验。

用户侧能力也都来自这份代码：`⌃⌘C` 折叠/展开，双击标题栏触发，菜单栏显示折叠数量，`⌃⌘1...9` 恢复对应窗口，`⌃⌘0` 整理卷帘条或进入专注整理；偏好设置提供原貌卷帘/标准标题栏、置顶、半透明、音效和权限入口。代码还为 Stickies、Finder、微信、Elpass、Adobe、系统设置等应用写了兼容分支，并用恢复日志尽量救回异常状态。

它的价值不在怀旧本身，而在保留空间记忆：窗口没有离开，只是暂时安静地卷起来。
