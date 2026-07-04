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

它会把窗口内容原地卷起，只留下一条标题栏式的卷帘条。窗口还在原来的位置，标题还看得到，之后可以从卷帘条、菜单栏或快捷键展开。

## 它做什么

| 模式 | 发生什么 | 适合什么 |
| --- | --- | --- |
| **折叠** | 窗口内容原地收起，只留下可识别、可拖动、可展开的标题栏入口。 | 看一眼后面的窗口，清出桌面空间，保留文档位置。 |
| **置顶** | 把窗口变成实时悬浮预览。 | 参考资料、iPhone 镜像、仪表盘，或者任何需要一直看着的窗口。 |

## 为什么要做这个？

macOS 已经有 Dock 最小化、Mission Control、Spaces、Stage Manager 和窗口平铺。WindowShade 做的是更小的一步：不切换工作空间，不重排窗口，只把眼前挡路的内容先收起来。

Mission Control 适合找窗口，Dock 最小化适合把窗口暂时放走。WindowShade 处理的是中间情况：窗口还留在这里，内容先卷起来。

## 亮点

- 用 `Control + Command + C` 折叠 / 展开当前窗口。
- 双击标题栏，折叠 / 展开指定窗口。
- 单击卷帘条，快速预览被收起的内容。
- 用 `Control + Command + P` 把窗口置顶成实时预览。
- 用 `Control + Command + 1...9` 按菜单顺序展开窗口。
- 支持原貌卷帘、标准标题栏、半透明、音效、专注 shelf 和登录启动。

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
| 管理所有窗口 | 菜单栏图标 |

三击标题栏会保留系统原本的标题栏缩放动作。

## 说明

WindowShade 更适合普通桌面窗口。自绘标题栏可能需要针对具体 app 适配。

目前已经对快速预览、便笺、微信、Adobe 应用和一些非标准窗口做了兼容处理。

## 权限

WindowShade 会要两个 macOS 权限：

- 辅助功能：用来找到和移动窗口。
- 屏幕录制：用来截取窗口顶部，并显示实时预览。

它不会上传窗口内容。

## 从源码构建

需要 macOS 14 或更新版本，以及 Xcode command line tools。

```sh
cd prototype
./build.sh
open WindowShade.app
```

构建脚本会创建 `WindowShade.app`。如果你希望 macOS 在重复构建后仍记住辅助功能和屏幕录制授权，可以用自己的开发者证书签名：

```sh
cd prototype
CODESIGN_IDENTITY="Apple Development: Your Name (TEAMID)" ./build.sh
```

## 其他

主代码在 [`prototype/WindowShade.swift`](prototype/WindowShade.swift)。历史背景和设计想法见 [`WindowShade.md`](WindowShade.md)。
