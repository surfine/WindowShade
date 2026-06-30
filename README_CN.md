<p align="center">
  <img src="assets/windowshade-menubar.svg" alt="WindowShade" width="96"/>
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

WindowShade 是一个 macOS 小工具，想把 classic Mac OS 里的窗口卷帘手感带回来。

有时候你只是想看一眼后面的窗口。不想关掉文档，不想隐藏整个应用，也不想把窗口最小化到 Dock 之后再找回来。

WindowShade 做的事情很小：窗口内容先收起，标题、位置和恢复入口还留在原处。

## 现在能做什么

先说清楚：这还是早期版本。现在这版已经能做这些事：

- 常驻菜单栏，不出现在 Dock；
- `Control + Command + C` 折叠 / 展开当前窗口；
- 双击标题栏卷起窗口内容，三击标题栏交还系统缩放；
- 折叠后留一条标题栏入口，不把窗口送进 Dock；
- 单击卷帘条看预览，也能从原地、菜单栏或 `Control + Command + 1...9` 找回来；
- 菜单栏能查看已折叠窗口，也能一次性全部展开；
- 专注 shelf 可以把其他 app 收到屏幕顶部；
- 在原貌卷帘和标准标题栏之间切换；
- 登录时自动启动；
- 对快速预览、便笺、微信、Adobe 应用做了一些兼容处理。

全屏空间、自绘标题栏、Stage Manager、多显示器环境还需要继续适配。

## 大概怎么做的

它用 Accessibility API 找到当前窗口，用 ScreenCaptureKit 截取窗口顶部，再生成一条 AppKit 覆盖层作为卷帘条。真实窗口会被移到屏幕外、隐藏或最小化。用户看到的效果是：窗口还在原处，只是卷起来了。

## 权限

WindowShade 会要两个 macOS 权限：

- 辅助功能：用来找到和移动窗口。
- 屏幕录制：用来截取窗口顶部，生成折叠后的标题栏。

它不会上传窗口内容。本地诊断日志写在 `/tmp/windowshade.log`。如果你折叠过带文件路径或窗口标题的窗口，日志里可能会出现这些信息。

## 构建

需要 macOS 14 或更新版本，以及 Xcode command line tools。

```sh
cd prototype
./build.sh
open WindowShade.app
```

构建脚本会创建 `WindowShade.app`，默认使用 ad-hoc 签名。如果你希望 macOS 在重复构建后仍记住辅助功能和屏幕录制授权，可以用自己的开发者证书签名：

```sh
cd prototype
CODESIGN_IDENTITY="Apple Development: Your Name (TEAMID)" ./build.sh
```

## 其他

主代码在 [`prototype/WindowShade.swift`](prototype/WindowShade.swift)。历史背景和设计想法见 [`WindowShade.md`](WindowShade.md)。
