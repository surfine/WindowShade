<h1 align="center">
  <img src="assets/app-icon/windowshade-app-icon.png" alt="WindowShade 应用图标" width="128"/><br>
  WindowShade
</h1>

<p align="center">
  <strong>把挡路的窗口原地收起，位置和标题还留在桌面上。</strong><br>
  一个 macOS 菜单栏小工具，把经典窗口卷帘动作带回现代桌面。
</p>

<p align="center">
  <a href="https://github.com/surfine/WindowShade/releases/latest"><img src="https://img.shields.io/github/v/release/surfine/WindowShade?style=flat-square&label=release" alt="最新版本"></a>
  <a href="https://github.com/surfine/WindowShade/stargazers"><img src="https://img.shields.io/github/stars/surfine/WindowShade?style=flat-square" alt="GitHub stars"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-black?style=flat-square" alt="macOS 14+">
  <a href="README.md"><img src="https://img.shields.io/badge/readme-English-blue?style=flat-square" alt="English README"></a>
</p>

<p align="center">
  <a href="https://www.bilibili.com/video/BV1m5Kf6bE6k/" title="观看演示视频">
    <img src="assets/windowshade-hero.png" alt="观看 WindowShade 演示视频" width="900"/>
  </a>
  <br>
  <a href="https://www.bilibili.com/video/BV1m5Kf6bE6k/">观看演示视频</a>
</p>

---

WindowShade 解决的是一个很小但很常见的桌面动作：窗口挡住了东西，可它仍然应该待在你刚才放好的位置。

它会把窗口内容原地卷起，只留下一条标题栏式的卷帘条。窗口还在原来的位置，标题还看得到，之后可以从卷帘条、菜单栏或快捷键展开——不用去翻 Dock，也不用重排桌面。

## 它做什么

| 模式 | 发生什么 | 适合什么 |
| --- | --- | --- |
| **折叠** | 窗口内容原地收起，只留下可识别、可拖动、可展开的标题栏入口。 | 看一眼后面的窗口，清出桌面空间，保留文档位置。 |
| **置顶** | 把窗口变成实时悬浮预览。 | 参考资料、iPhone 镜像、仪表盘，或者任何需要一直看着的窗口。 |

## 为什么要做这个？

macOS 已经有 Dock 最小化、Mission Control、Spaces、Stage Manager 和窗口平铺。WindowShade 做的是更小的一步：不切换工作空间，不重排窗口，只把眼前挡路的内容先收起来。

Mission Control 适合找窗口，Dock 最小化适合把窗口暂时放走。WindowShade 处理的是中间情况：窗口还留在这里，内容先卷起来。

它不是“关闭”“退出”“隐藏”或“最小化”。应用和文档都还活着，窗口的身份、位置和恢复入口始终留在桌面上。这种“空间记忆”——即使窗口卷起来了，你也知道它就在那里——正是 WindowShade 的全部意义。

## 工作原理

WindowShade 一次只处理一个窗口，动作始终可逆：

1. 找到当前聚焦窗口，记住它的精确位置和尺寸。
2. 截取真实窗口顶部，让卷帘条保持原生观感。
3. 根据应用允许的方式，把真实窗口隐藏、移到屏幕外或最小化。
4. 在原地留下一条细卷帘条；展开时窗口回到原来的位置，或者你拖动卷帘条后所在的位置。

两种卷帘样式可选：

| 样式 | 外观 | 适合 |
| --- | --- | --- |
| **原貌卷帘** | 实时截取真实窗口的顶部 chrome | 让卷帘条和原窗口视觉上保持一致 |
| **标准标题栏** | 应用图标、标题和交通灯的标准条 | 专注整理、统一宽度、收拾桌面 |

## 亮点

- 用 `Control + Command + C` 折叠 / 展开当前窗口。
- 双击标题栏，折叠 / 展开指定窗口。
- 单击卷帘条，快速预览被收起的内容。
- 用 `Control + Command + P` 把窗口置顶成实时预览。
- 用 `Control + Command + 1...9` 按菜单顺序展开窗口。
- 用 `Control + Command + 0` 整理卷帘条，或进入专注 shelf。
- 可调卷帘样式、标题栏双击、置顶、半透明、音效和登录启动。

## 兼容性

大多数普通桌面窗口开箱即用。自绘标题栏的窗口按应用做了专门处理：

- **便笺（Stickies）** — 让位给它原生的卷起行为。
- **微信、Elpass、Telegram** — 固定 chrome 高度和标题栏裁切规则，避免卷帘条切进内容区。
- **Adobe 应用**（Photoshop、Illustrator、InDesign、After Effects、Premiere）— After Effects / Premiere 折叠整个工作区框架；Photoshop 折叠浮动文档；工具面板默认不参与。
- **Finder、快速预览、Codex、系统设置、计算器** — 为实时预览、全屏处理和不可缩放窗口准备了专门的策略。

## 权限

WindowShade 会要两个 macOS 权限：

- **辅助功能**：用来找到、移动、聚焦和恢复窗口。
- **屏幕录制**：用来截取窗口顶部，并显示实时预览。

窗口内容不会离开你的 Mac。

## 说明

WindowShade 更适合普通桌面窗口；全屏、Split View、Stage Manager、多显示器和沙盒应用可能需要专门适配。有些窗口无法稳定移到屏幕外，会改用隐藏或最小化。每折叠一个窗口都会记录到恢复日志，异常退出后尽量把窗口救回来——这是安全网，不是系统级事务保证。

## 下载

到 [Releases](https://github.com/surfine/WindowShade/releases/latest) 下载最新版 zip，解压后打开 `WindowShade.app`。

WindowShade 常驻菜单栏，不会出现在 Dock。

## 基本用法

| 动作 | 快捷键 / 手势 |
| --- | --- |
| 折叠 / 展开当前窗口 | `Control + Command + C` |
| 折叠 / 展开指定窗口 | 双击标题栏 |
| 预览折叠窗口 | 单击卷帘条 |
| 置顶 / 取消置顶当前窗口 | `Control + Command + P` |
| 按菜单顺序展开窗口 | `Control + Command + 1...9` |
| 整理卷帘条 / 专注 shelf | `Control + Command + 0` |
| 管理所有窗口 | 菜单栏图标 |

三击标题栏会保留系统原本的标题栏缩放动作。

## 从源码构建

需要 macOS 14 或更新版本，以及 Xcode command line tools。

```sh
cd prototype
./build.sh
open WindowShade.app
```

脚本会把源码编译进现有的 `WindowShade.app` 并签名。它使用固定的 Apple Development 身份；把 `build.sh` 里的 `IDENTITY` 改成你自己的证书，就能让 macOS 在重复构建后仍记住辅助功能和屏幕录制授权。

## 设计说明

主代码在 [`prototype/WindowShade.swift`](prototype/WindowShade.swift)。历史背景、设计取舍和各应用兼容细节见 [`WindowShade.md`](WindowShade.md)。
