<p align="center">
  <img src="assets/windowshade-menubar.svg" alt="WindowShade" width="96"/>
</p>

<p align="center">
  <strong>WindowShade</strong><br>
  把 macOS 窗口原地卷起来。
</p>

<p align="center">
  <a href="README.md">English</a> · <a href="README_CN.md">简体中文</a>
</p>

<p align="center">
  <img src="assets/windowshade-hero.png" alt="WindowShade 把窗口卷成标题栏" width="900"/>
</p>

---

WindowShade 是一个 macOS 小原型，想把 classic Mac OS 里的窗口卷帘手感带回来。

按 `Control + Command + C`，或者双击标题栏。窗口会收成一条细条，之后还能从原来的位置展开。细条还留在原地，桌面也不用重排。

## 现在能做什么

先说清楚：这还不是正式发布版。

现在这版主要做了这些事：

- 常驻菜单栏，不出现在 Dock；
- 折叠和展开当前窗口；
- 从菜单栏列表里找回已折叠窗口；
- 使用真实窗口顶部截图，或标准代理标题栏；
- 提供基础预览、整理、音效和权限设置。

有些地方还会露馅。全屏空间、自绘标题栏、Stage Manager、多显示器环境，都需要继续磨。

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

主代码在 [`prototype/WindowShade.swift`](prototype/WindowShade.swift)。

历史背景和设计想法见 [`WindowShade.md`](WindowShade.md)。
