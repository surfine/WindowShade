<p align="center">
  <img src="assets/app-icon/windowshade-app-icon.png" alt="WindowShade 应用图标" width="128"/>
</p>

<p align="center">
  <strong>WindowShade</strong><br>
  把 classic Mac OS 的窗口卷帘带回 macOS。
</p>

<p align="center">
  <a href="README.md">English</a> · <a href="README_CN.md">简体中文</a>
</p>

<p align="center">
  <a href="https://www.bilibili.com/video/BV1m5Kf6bE6k/" title="观看演示视频">
    <img src="assets/windowshade-hero.png" alt="观看 WindowShade 演示视频" width="900"/>
  </a>
  <br>
  <a href="https://www.bilibili.com/video/BV1m5Kf6bE6k/">观看演示视频</a>
</p>

---

WindowShade 是一个 macOS 菜单栏小工具，用来把窗口临时收起来，但不丢掉它。

它给窗口增加了两种临时状态：

- **折叠**：窗口内容原地收起，只留下标题栏入口。之后可以从卷帘条、菜单栏或快捷键找回来。
- **置顶**：把窗口变成实时悬浮预览。鼠标移进去时，可以直接操作真实窗口。

它适合这种小场景：你只是想看一眼后面的内容，或者想让 iPhone 镜像窗口一直浮在上方，又不想关闭文档、隐藏整个应用，也不想去 Dock 里找回来。

## 下载

到 [Releases](https://github.com/surfine/WindowShade/releases) 下载最新版 zip，解压后打开 `WindowShade.app`。

WindowShade 常驻菜单栏，不会出现在 Dock。

## 基本用法

- `Control + Command + C`：折叠 / 展开当前窗口。
- 双击窗口标题栏：折叠 / 展开这个窗口。
- 单击卷帘条：显示 / 收回窗口内容预览。
- `Control + Command + P`：置顶 / 取消置顶当前窗口。
- `Control + Command + 1...9`：按菜单顺序展开已折叠窗口。
- 菜单栏：管理已折叠窗口、置顶预览、专注 shelf、外观、音效、权限和登录启动。

三击标题栏会保留系统原本的标题栏缩放动作。

## 说明

WindowShade 更适合普通桌面窗口。全屏空间、Stage Manager、自绘标题栏和复杂专业软件可能需要单独适配。

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
