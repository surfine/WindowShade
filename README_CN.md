<h1 align="center">
  <img src="assets/app-icon/windowshade-app-icon.png" alt="WindowShade 应用图标" width="128"/><br>
  WindowShade
</h1>

<p align="center">
  <strong>窗口挡在前面，又不想关掉它。</strong><br>
  一个 macOS 菜单栏小工具，把窗口像卷帘一样收起来。
</p>

<p align="center">
  <a href="https://github.com/surfine/WindowShade/releases/latest"><img src="https://img.shields.io/github/v/release/surfine/WindowShade?style=flat-square&label=release" alt="最新版本"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-black?style=flat-square" alt="macOS 14+">
  <a href="README.md"><img src="https://img.shields.io/badge/readme-English-blue?style=flat-square" alt="English README"></a>
</p>

---

![合上屏幕时，桌面随铰链角度卷起](assets/windowshade-demo.gif)

WindowShade 把窗口内容原地卷成一条卷帘条：位置还在、标题还在、双击就回来。它没有最小化，也没有躲进 Dock，桌面上你放好的东西一件都不会动。

它适合这样的时刻——参考文档挡住了正在写的稿子，或者你只是想暂时让桌面安静一点，但不想打乱任何布局。

## 能做什么

| 能力 | 说明 |
| --- | --- |
| **折叠窗口** | `⌃⌘C` 或双击标题栏，把内容收成一条卷帘条；单击预览，再点展开 |
| **置顶预览** | `⌃⌘P` 让窗口变成始终可见的实时预览，参考资料、镜像画面、仪表盘都合适 |
| **动态卷帘** | 屏幕合拢时，桌面或窗口内容随铰链角度卷起、后退、模糊，再原样展开 |
| **整理与专注** | `⌃⌘0` 把卷帘条排整齐，或进入专注布局 |

## 设置

![设置里的动态效果页面](assets/windowshade-settings.png)

效果、卷帘、权限与启动、高级四个页面按 macOS 原生排版重做：三种质感（轻柔 / 标准 / 磨砂）、触发角度、校准、实时预览、诊断日志、恢复默认值都在页面里。菜单栏负责当前窗口、窗口列表和铰链角度状态；“随设备倾斜”是实验功能，会给桌面效果加一点随机器姿态变化的视差。

## 快捷键

| 动作 | 快捷键 / 手势 |
| --- | --- |
| 折叠 / 展开当前窗口 | `⌃⌘C` |
| 折叠 / 展开指定窗口 | 双击标题栏 |
| 预览折叠窗口 | 单击卷帘条 |
| 置顶 / 取消置顶当前窗口 | `⌃⌘P` |
| 按菜单顺序展开窗口 | `⌃⌘1…9` |
| 整理卷帘条 / 专注布局 | `⌃⌘0` |

## 权限与隐私

WindowShade 按功能使用两项系统权限，另加一项实验性的本地传感器读取：

- **辅助功能**：寻找、移动、聚焦和恢复窗口。
- **屏幕录制**：截取标题栏、生成窗口预览和动态效果。
- **Apple Silicon 加速度计**：不是系统权限项。“随设备倾斜”开启后读取本机 HID 报告，部分机型或安全上下文会显示为不可用。

实时预览默认关闭，只有主动开启时才会检查屏幕录制权限。窗口内容不会上传，也不会离开这台 Mac。

## 兼容性

大多数普通桌面窗口可以直接使用。自绘标题栏的应用（Chrome、Electron 等）走专门的兼容策略；全屏、Split View、Stage Manager、多显示器和沙盒应用可能需要额外适配。

动态效果需要机型提供铰链角度传感器（Apple Silicon MacBook）；“随设备倾斜”还要求系统暴露 AppleSPU 加速度计。

## 下载

到 [Releases](https://github.com/surfine/WindowShade/releases/latest) 下载最新版 zip，解压后打开 `WindowShade.app`。它常驻菜单栏，不会出现在 Dock。

- 系统要求：macOS 14 或更新版本
- 签名身份保持不变，覆盖安装不会重置辅助功能与屏幕录制授权

## 从源码构建

需要 macOS 14 或更新版本、Xcode command line tools，以及用于签名的 Apple Development 证书。

```sh
git clone https://github.com/surfine/WindowShade.git
cd WindowShade/prototype
./build.sh
open WindowShade.app
```

只检查编译：

```sh
./build.sh --check
```

签名身份通过 `WINDOWSHADE_CODESIGN_IDENTITY` 或本机未跟踪的 `prototype/local-codesign.env` 提供，构建、测试与发布细节见 DEVELOPMENT.md。

## 项目结构

实现都在 `prototype/` 下，按职责分模块：`App/` 负责菜单、设置与折叠入口，`Capture/` 负责截图与缓存，`Effects/` 负责动态效果与渲染，`Recovery/` 负责恢复日志与窗口救援，另有 `Overlay/`、`Window/`、`Compatibility/` 和隔离私有 API 的 `Private/`。设计背景见 WindowShade.md。

## 许可

[MIT](LICENSE)。动态效果、传感器与恢复链路都是本仓库自己的实现。
