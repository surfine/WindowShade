# 代码地图

`prototype/` 下每个目录负责什么、改的时候要注意什么。要改某件事先在这里找到该动哪个目录，再进文件读头注释。
改之前也看一眼[重塑执行规格](product-reshape-spec.md) §2.0.2「不要碰的」——那里列的不变量和下面「改的时候注意」是同一份清单的两半，改一边要同步另一边。
2026-10-15 按本机源码整理（文件数用 `find <目录> -name '*.swift' | wc -l` 数）。

## 一条总规矩：App 管副作用，Core 管判断

| 目录 | 文件数 | 放什么 |
| --- | ---: | --- |
| `Core/` | 182 | 纯逻辑：状态机、判定、文案、模型。181 个只引 Foundation（例外是 `ShadeModels.swift`），所以能脱离整个 App 单独编译测试——`tests/run-*.sh` 大多就是这么编的。 |
| `App/` | 199 | 有系统副作用的控制器：AppKit 窗口、AX 读写、事件 tap、通知观察、刘海与面板。160 个引 Cocoa/AppKit。 |

新写的判断逻辑放 `Core/`、配一个 `tests/run-*.sh`；`App/` 里只留把判断接到系统上的那一层。

## 目录

| 目录 | 负责什么 | 改的时候注意 |
| --- | --- | --- |
| 根目录 `main.swift` | 进程入口；更新器的 `--self-check` 要在建 App 之前返回 | `build.sh --stage` 会 grep 这里的接线，少接一处包就不能发 |
| 根目录 `WindowShade.swift` | `AppDelegate` 骨架：启动顺序、观察者、生命周期、事件 tap 安装、5 秒体检、睡醒恢复 | 全局常量与 defaults 键也在这；迁移点在 `shadeSoundMigrationVersionDefaultsKey` |
| 根目录 `PinnedPreview*.swift`、`ScreenCaptureBridge.swift` | 置顶预览（镜像流的单槽租约）与 ScreenCaptureKit 的流封装 | 流的状态全在 `stateLock` 和串行 `frameQueue` 上，别在别的线程碰 |
| `App/` | 见上。大块：刘海 `Notch*`（20）、启动台 `Launchpad*`（12）、更新 `Updater*`（8）、刷脸 `Face*`、程序坞 `Dock*`、侧拉 `Slide*`、卷轴 `Scroll*`/`Strip*`、偏好设置 `Preferences.swift`、菜单 `MenuBarController.swift`/`StandardMenu.swift`、WindowShade 2 的 `WS2*` | 9 支事件 tap 分散在 `EventTap`、`GlobalInputFilter`、`ScrollTap`、`HabitKeys`、`MiddleTitlebarTap`、`MissionControlKeys`、`NotchLevelObserver`、`TrackpadGestures`、`WindowSwitcher`：**新加的 tap 要在开着时向 `Core/EventTapHealth.swift` 登记、关掉时注销** |
| `App/FoldTransaction.swift`、`FoldExit.swift`、`FoldCompletion.swift` | 收起／展开的事务 | **回调序号校验与「销毁通知只当提示」是踩出来的不变量**，改前把注释读完 |
| `Core/` | 见上。大块：刘海策略 `Notch*`（16）、静音会话 `WS2Silent*`（11）、刷脸 `Face*`（9）、遥控 `Remote*`、发布开关 `ReleaseDefaults.swift`、本地化 `WSL10n.swift` | `ReleaseDefaults.swift` 是唯一开关表：没真机验过的一律默认关但功能在 |
| `Window/` | AX 读写与窗口几何：`AXWindow`、坐标换算、窗口列表缓存、外框画像 | **`AXStallBreaker` 的单次预算与按进程熔断**防一个 App 卡死拖垮全局，别绕过 |
| `WindowBrowser/` | 窗口浏览（Dock 悬停与键盘面板）：发现、目录、缩略图、动作、探针 | 窗口只从 AX 的 `kAXWindowsAttribute` 发现（`WindowBrowserDiscovery`），原生标签页的后台标签因此本来不出现（规格 R4） |
| `Capture/` | 截图与采集：快速截图、私有快照、缓存、采集尺寸 | 每个入口先判屏幕录制权限；没有权限时退回无画面路径（规格 R29 的降级清单） |
| `Effects/` | 合盖／倾斜的 Metal 效果（`Duo.metal`、`FoldRenderer`）、锁屏装饰、效果探针 | `FoldRenderer` 已用 `CVMetalTextureCache` 零拷贝；探针类文件只在显式参数下进入 |
| `Overlay/` | 卷帘条、看一眼卡片、手势提示、系统外观策略 | 外观每次现读 `NSApp.effectiveAppearance`，不缓存 |
| `Compatibility/` | 按 App 的特殊处理：隐藏策略、特殊外框高度 | 所有 App 特例集中在这里，别散到调用点 |
| `Private/` | 私有框架桥：SkyLight、程序坞通知、锁屏 Space、屏幕形状 | 全部 `dlopen`／`dlsym` 运行时载入，`nm -u` 看不见；量私有面要连这里一起数 |
| `Recovery/` | 恢复日志与离屏窗口救援：异常退出后把窗口找回来 | 日志字段坏值拒绝、不截断（`JournalNumeric`） |
| `Support/` | 诊断日志、Sendable 担保、本机 socket、进程通道、配对加密、CarPlay 接收端 | `SendableSystemHandles.swift` 里每条担保都要写清为什么安全 |
| `Watchdog/` | 更新看护 `WindowShadeUpdateGuard.app` | 只能依赖 Foundation/AppKit 和几份共用的更新文件（见 `build.sh` 的 `GUARD_SOURCES`） |
| `Native/` | 原创的 C 进程监督（`WS2Child.c`） | 同一实例只用一个串行执行器；没有全局 SIGCHLD |
| `Vendor/` | Sparkle 2.10.0 与 mediaremote-adapter（第三方，不改） | 许可随包，见仓库根 `THIRD-PARTY-LICENSES.md` |
| `Resources/` | `Localizable.xcstrings`（zh-Hans／en／zh-Hant） | 新的用户可见句子三栏都要有；`build.sh --check` 会查 |

## 不在 prototype/ 里但常要动的

- `tests/` — 在**仓库根**：`*.swift` 测试档加 `run-*.sh` runner，自制 `@main + expect` 模式；`build.sh` 门禁会跑其中几支。
- `tools/` — 探针、隐私登记表（`tools/privacy/registry.json`）、编程会话 hook（`tools/ws2-hook`）。
- `site/` — 官网；隐私页由登记表生成并与 App 逐字对照。
- `scripts/` — 发布前检查（如 `check-release-version.sh`）。
