<div align="center">

<img src="assets/app-icon/windowshade-app-icon.png" alt="WindowShade" width="112">

<samp>把经典 Mac 的一个好习惯，放回桌面。</samp>

# WindowShade

**暂时让开，位置还在。**<br>
把窗口卷成一条标题栏，需要时，在原处展开。<br>
原生 macOS 菜单栏工具，也能置顶预览，让桌面随屏幕开合而动。

[![版本](https://img.shields.io/github/v/release/surfine/WindowShade?style=flat-square&color=303b49)](https://github.com/surfine/WindowShade/releases/latest)
[![macOS](https://img.shields.io/badge/macOS-14%2B-303b49?style=flat-square)](#下载)
[![Apple Silicon](https://img.shields.io/badge/download-Apple%20Silicon-303b49?style=flat-square)](#下载)
[![许可](https://img.shields.io/badge/license-MIT-303b49?style=flat-square)](LICENSE)

[**下载应用**](https://github.com/surfine/WindowShade/releases/latest) · [**产品官网**](https://windowshade.pages.dev/) · [**互动考古**](https://windowshade.pages.dev/history/) · [English](README.md)

![MacBook 屏幕合拢时，WindowShade 桌面效果随之卷起](assets/windowshade-demo.gif)

<sub>合盖桌面效果的真实录屏。日常窗口折叠也可以用快捷键或标题栏手势触发。</sub>

</div>

## 窗口少一点，桌面还是你的桌面

参考文档挡住了正在写的稿子。你只需要借用它占着的空间一会儿，又想记住它放在哪里。

WindowShade 留下一条卷帘：标题还在，展开的入口还在。双击卷帘条，窗口回来；拖动卷帘条，窗口就在新位置展开。桌面上那些帮助你认路的小线索，也一起保留下来。

## 1.0.12 的变化

- **窗口浏览。** 鼠标停在 Dock 的应用图标上，就能以缩略图卡片或紧凑列表查看该应用的真实窗口，可搜索、可逐窗操作；菜单里的“选择窗口…”或自设快捷键打开同一个键盘面板。默认关闭。
- **动作绑定真实身份。** 每个卡片动作都绑定你所选窗口的完整身份，执行前重新核对；折叠与展开复用原有事务、恢复验证与恢复日志。
- **缩略图与可选的实时画面。** 先出标题和缓存，截图只针对目标窗口；实时预览默认关闭，临时面板最多新增一路流。

[发布说明与下载 →](https://github.com/surfine/WindowShade/releases/tag/v1.0.12)

## 三种腾出空间的方式

| | 能做什么 | 适合什么时候 |
| --- | --- | --- |
| **卷起窗口** | `⌃⌘C` 或双击标题栏，原地留下一条卷帘；双击卷帘条展开。可选原貌截图或标准标题栏。 | 让参考资料暂时让开，同时记住它的位置。 |
| **置顶预览** | `⌃⌘P` 创建浮动实时预览，空闲时降低捕获频率。 | 把参考、镜像画面或仪表盘放在工作旁边。 |
| **让桌面随合盖而动** | 支持的 MacBook 上，桌面随屏幕开合卷起、后退或模糊。轻柔、标准、磨砂三种质感，触发角度可调，预览可以拖着看。 | 让机器的物理动作与屏幕上的画面有一点联系。 |

窗口折叠动画跟随手动折叠、展开操作；铰链传感器驱动桌面效果。实验性的“随设备倾斜”在机型提供相应传感器时，增加一点视差。

## 日常操作，交给原生界面

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/windowshade-settings-dark.png">
  <img src="assets/windowshade-settings.png" alt="WindowShade 原生设置：侧边栏、纸面预览与动态效果控件" width="100%">
</picture>

<sub>真实 AppKit 设置界面，随你的 GitHub 主题切换。截图来自隔离设计预览，图中传感器未启动。</sub>

效果、卷帘、权限与启动、高级，四页各有职责。工作时常用的窗口列表与操作放在菜单栏，不占 Dock 位置。

## 老想法里，哪些值得留下

卷帘有用的地方是**连续性**：内容可以暂时看不见，位置仍然可见。一个小手势也值得尊重个人偏好；窗口收起来以后，仍然应该认得出它是谁。

| 档案里的几个停靠点 | 值得留意的细节 |
| --- | --- |
| **1994 · 一个小工具** | 1 月的 Mini’app’les 通讯记载 WindowShade 1.2，署名 Rob Johnston / Interactive Technologies，版权区间为 1989–92；这不等于已核实的首发日期。 |
| **System 7.5 · 个人的节奏** | 控制面板允许双击或三击、修饰键和声音。 |
| **Mac OS 8 · 看得见的入口** | 独立的卷起按钮把这个动作放进窗口边框。 |
| **Mac OS X 之后 · 各自的去处** | Dock、后来出现的 Exposé、第三方工具，以及便笺里保留下来的卷起行为，接着讲述这个故事。 |

[**进入有图、有出处、可以亲手操作的历史 →**](https://windowshade.pages.dev/history/)

改一改重绘的旧控制面板，对比卷起与最小化，或者通过 [Infinite Mac](https://infinitemac.org/) 启动 System 7.5、Mac OS 8.0 和 Mac OS X 10.1。重绘会明确标注，原始资料就放在叙述旁边。

今天的 WindowShade 是一个**独立的 Swift / AppKit 实现**，继承的是交互想法，不是 Rob Johnston、Apple 或 Unsanity WindowShade X 的代码。[最初的设计与考据笔记](WindowShade.md) 仍保留在仓库里，后续史料修正见互动长文。

## 下载

到 [Releases](https://github.com/surfine/WindowShade/releases/latest) 下载 **WindowShade-v1.0.12.zip**，解压，把 `WindowShade.app` 移到“应用程序”并打开。它会出现在菜单栏。

- **macOS 14+ · Apple Silicon。** 下载包是 arm64，本次不包含 Intel 二进制。
- **使用 Apple Development 签名，尚未公证。** 如果 macOS 阻止首次打开，可在“系统设置 → 隐私与安全性”中，对刚下载的应用使用“仍要打开”。无需关闭 Gatekeeper。
- 升级保留 bundle 标识和签名身份；系统仍可能因安装位置或系统状态要求重新授权。
- 每次发布同时提供 zip 与 SHA-256 校验文件。

## 快捷键

| 动作 | 快捷键 / 手势 |
| --- | --- |
| 折叠 / 展开当前窗口 | `⌃⌘C` |
| 折叠指定窗口 | 双击标题栏 |
| 展开折叠窗口 | 双击卷帘条 |
| 预览折叠窗口 | 悬停；原貌截图条也可单击唤出预览 |
| 置顶 / 取消置顶当前窗口 | `⌃⌘P` |
| 按菜单顺序展开 | `⌃⌘1…9` |
| 整理卷帘条 / 专注布局 | `⌃⌘0` |
| 打开窗口选择面板 | 菜单 → “选择窗口…”；也可在设置中录制独立快捷键 |

窗口浏览入口还可以让鼠标停在已运行应用的 Dock 图标上，查看并操作该应用的窗口
（设置 → 窗口浏览中开启，默认关闭）。它不会替换系统 Dock，也不接管原生
Command-Tab。细节、权限与兼容限制见 [窗口浏览说明](docs/window-browser.md)。

## 权限、恢复与兼容性

**辅助功能**用于寻找、移动、聚焦和恢复窗口；**屏幕录制**用于原貌截图、预览和效果。实时预览默认关闭，开启时才检查录屏访问。窗口内容在本机处理。

隐藏截图卷帘的源窗口前，应用会记录恢复信息。恢复检查与持久日志帮助意外中断后的窗口回到桌面。不同应用可能采用移出屏幕、隐藏或最小化等不同策略，卷帘条是这些操作留给你的可见入口。

主要面向普通桌面窗口。自绘工具栏仍可能需要单独适配；全屏、Split View、Stage Manager、Adobe 工作区和多显示器组合存在兼容边界。截图上看得见的工具栏按钮，并不都能直接操作。欢迎[提交可复现的窗口案例](https://github.com/surfine/WindowShade/issues)，附上 macOS 版本、应用版本与操作步骤。

合盖效果需要受支持的铰链角度传感器；实验性倾斜还需要本机 AppleSPU 加速度计接口。读不到时会明确显示不可用。

## 构建与参与

需要 macOS 14+、包含 Metal 编译器的 Xcode command line tools，以及 Apple Development 签名证书。

```sh
git clone https://github.com/surfine/WindowShade.git
cd WindowShade/prototype
./build.sh --check   # Swift 类型检查与 Metal 编译
./build.sh           # 使用本机配置的身份构建、签名
open WindowShade.app
```

通过 `WINDOWSHADE_CODESIGN_IDENTITY` 或未跟踪的 `prototype/local-codesign.env` 配置签名。项目沿用 `swiftc` 脚本构建，签名、隔离构建与发布步骤见 [DEVELOPMENT.md](DEVELOPMENT.md)。

| 仓库入口 | 内容 |
| --- | --- |
| [`prototype/`](prototype/) | 原生应用：窗口策略、捕获、覆盖层、效果与恢复 |
| [`tests/`](tests/) | 状态、恢复、帧、Metal 与纸面组件检查 |
| [`site/`](site/) | 部署在 Cloudflare Pages 的中英文官网与互动考古 |
| [`docs/performance.md`](docs/performance.md) | 实测结果，以及尝试过但没有奏效的办法 |
| [`docs/releases/`](docs/releases/) | 历次发布说明 |
| [`WindowShade.md`](WindowShade.md) | 最初的设计理由与研究笔记 |

修改窗口行为时，请写明应用和窗口类型、修改前后的表现，以及做过的检查。沿用现有兼容策略和恢复边界，比笼统宣称“支持所有应用”更有帮助。

## 致谢与许可

本项目代码采用 [MIT](LICENSE)。历史软件和名称属于各自作者。互动历史感谢 [Infinite Mac](https://infinitemac.org/)、Marcin Wichary 的 [《偏好之形》](https://aresluna.org/frame-of-preference/)，以及提供时代外观实现参考的 [AI System 6](https://github.com/surfine/AI-System-6)。随站点分发的字体和参考资源许可保留在 [`site/public/fonts/`](site/public/fonts/)。
