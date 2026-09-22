# WindowShade 开发指南

面向开发者的构建、签名、模块结构、调试与发布流程。用户向内容见 [README](README_CN.md)。

## 环境要求

- macOS 14 或更新版本
- Xcode Command Line Tools
- 用于签名的 Apple Development 证书（构建脚本强制要求，拒绝 ad-hoc 签名）

## 模块结构

```text
prototype/
├── main.swift                        # 入口（NSApplication + AppDelegate）
├── WindowShade.swift                 # 全局常量 + AppDelegate 骨架（启动、观察者、生命周期）
├── ScreenCaptureBridge.swift         # SCStream 捕获（置顶预览的实时流）
├── PinnedPreview.swift               # 置顶预览控制器（目标解析、watchdog、交互接管）
├── PinnedPreviewPanel.swift          # 预览面板与菜单实时缩略图
├── App/                              # AppDelegate 扩展（按功能拆分的控制器）
│   ├── MenuBarController.swift       # 状态栏图标、菜单重建与菜单代理回调
│   ├── Reconcile.swift               # 折叠会话监控（reconcile 定时核对/并行快照）
│   ├── EventTap.swift                # 全局快捷键、事件 tap、标题栏双击/三击
│   ├── EventTapCallback.swift        # CGEventTap 的 C 回调与标题栏带预过滤
│   ├── Permissions.swift             # 权限检测与隐私设置跳转
│   ├── StatusBarIcon.swift           # 状态栏模板图标
│   ├── Preferences.swift             # 设置窗口与引导页
│   ├── OverlayPresentation.swift     # 覆盖层展示与 Space 不变量
│   ├── HoverPreview.swift            # 悬停预览（peek / 菜单悬停）
│   ├── OverlayFactory.swift          # 覆盖层窗口工厂（截图条/经典条/代理标题栏）
│   ├── ArrangeController.swift       # 卷帘条整理与专注 shelf
│   ├── FocusSession.swift            # 专注会话
│   ├── FoldTransaction.swift         # 折叠事务辅助（隐藏/恢复/验证/转发/通知）
│   ├── FoldCompletion.swift          # 窗口动作与标题栏手势共用的完成等待
│   ├── ShadeController.swift         # 折叠入口（shade/toggle/折叠计划/截图）
│   └── FoldExit.swift                # 折叠出口（unshade/清理/交通灯/QuickLook）
├── Private/
│   └── SkyLightBridge.swift          # SkyLight 私有 API 隔离层（全部有 fallback）
├── Compatibility/
│   ├── WindowPolicy.swift            # 窗口策略协议 + CaptureMode/HidingStrategy
│   ├── Policies.swift                # 具体策略 + windowPolicy(for:)
│   └── AppPredicates.swift           # 按应用的判断（特殊外框高度、应用识别）
├── Core/
│   ├── WindowState.swift             # 折叠操作状态机（非法转换拒绝）
│   └── ShadeModels.swift             # 折叠相关值类型（ShadeState、策略、外框画像）
├── Capture/
│   ├── WindowSnapshotCache.swift     # 折叠截图 500ms 短 TTL 缓存
│   ├── PreviewRenderer.swift         # 渲染与图像分析（chrome 扫描、圆角镜像、条制备）
│   └── ShareableContentCache.swift   # SCShareableContent 短 TTL 缓存
├── Overlay/
│   ├── ShadeStripPool.swift          # 简单卷帘条窗口池（OverlayWindow 复用）
│   └── ShadeStrip.swift              # 覆盖层视图（代理标题栏/经典条/预览窗/调色板）
├── Window/
│   ├── WindowRegistry.swift          # app 元数据（名称/bundleID）短 TTL 缓存
│   ├── AXWindow.swift                # AX 辅助（几何/ID 解析/chrome 探测/按钮交互）
│   ├── AXHelpers.swift               # 交通灯、QuickLook 重开、系统标题栏设置、唤回回调
│   ├── AppWindows.swift              # 应用窗口枚举（事务备忘/并发）与显示标题
│   ├── ChromeProfile.swift           # 窗口外框画像与缓存
│   ├── Coordinates.swift             # AX / Cocoa 坐标换算与屏幕归属
│   └── WindowListCache.swift         # WindowServer 窗口列表缓存与单窗口查询
├── Effects/                          # 合盖桌面效果与窗口收起动画（Metal 渲染、传感器、设置窗口）
├── WindowBrowser/                    # 窗口浏览：Dock 悬停与“选择窗口…”面板
│   ├── WindowBrowserController.swift # 会话、目录、截图请求与面板生命周期
│   ├── WindowBrowserViews.swift      # 视图共用部分（协议、图标缓存、表面样式）
│   └── WindowBrowser*View.swift 等   # 每个视图一个文件：卡片、列表行、详情、大图预览、内容视图
├── Support/
│   └── Diagnostics.swift             # 日志、主线程活动标记、慢调用日志、卡顿哨兵
└── Recovery/
    ├── Journal.swift                 # 恢复日志数据层（持久化/匹配/生命周期标记）
    └── Rescue.swift                  # 离屏窗口救援编排（后台扫描 + 主线程写回）
```

`build.sh` 会自动收集上述目录里的 `.swift` 文件（排序稳定，排除 `WindowShade.app`、
`dist` 与 `.build`），新增源文件无需手工维护编译列表。

## 构建

构建脚本原地更新 `prototype/WindowShade.app`（保留 bundle、Info.plist 与资源）。
全新克隆没有 bundle 时，脚本会用仓库里的 `Info.plist` 与
`assets/app-icon/WindowShade.icns` 自动 bootstrap 一个最小 bundle；已有 bundle
则继续原地替换 Mach-O，保留 TCC 授权身份。

```sh
cd prototype
./build.sh
open WindowShade.app
```

只想验证编译、不签名也不改动 app bundle：

```sh
./build.sh --check
```

### 签名

`build.sh` 的签名身份来自环境变量或本机未跟踪配置文件（不写入 Git）：

```sh
WINDOWSHADE_CODESIGN_IDENTITY="Apple Development: Your Name (TEAMID)" ./build.sh
```

也可以写在 `prototype/local-codesign.env` 里（该文件已在 `.gitignore` 中）：

```sh
WINDOWSHADE_CODESIGN_IDENTITY="Apple Development: Your Name (TEAMID)"
```

构建脚本默认拒绝 ad-hoc 签名：macOS 的 TCC 授权（辅助功能 / 屏幕录制）绑定签名
身份，重建 bundle 或换 ad-hoc 签名会重置权限。

### 编译验证（不签名，仅验证）

```sh
cd prototype
./build.sh --check
```

`--check` 复用 `build.sh` 同一份自动收集的源文件清单，只做 swiftc 类型检查，
不签名、不修改 app bundle。README 与本文档不再需要第二套独立的 swiftc 文件清单。

## 调试

- 设置与纸面组件的隔离验收入口：见 [设计规范 v1 落地与验证](docs/design-v1.md)。
- 纸面组件事件与命中区域回归：`bash tests/run-paper-tests.sh`，使用离屏 AppKit 视图，不操作用户窗口。
- 设置页恢复与滚动保持：`bash tests/run-settings-tests.sh`，编译生产 AppKit 视图的独立入口；使用隔离偏好设置，不显示或操作用户窗口。
- 经典卷帘条辅助操作与点击边界：`bash tests/run-appkit-tests.sh ClassicStripTests`；直接调用生产视图的事件处理，不注入系统事件，浅深色组件图输出到 `.build/appkit-tests/strip-shots/`。设置测试也复用这个构建入口，保留原命令作为包装。
- 窗口动画生命周期：`bash tests/run-appkit-tests.sh WindowFoldEffectsTests`；用无捕获任务检查旧回调隔离、取消、回退移交、隐藏超时代数和重入，不操作真实窗口。测试扩展仅拼入临时源码快照，以访问生产类型的私有生命周期。
- 日志写在 `/tmp/windowshade.log`，5MB 自动轮转（旧文件为 `.1`）。
- 主线程卡顿：日志里搜 `main-thread stall`。
- 慢操作：日志里搜 `slow:` 前缀。
- 状态机：日志里搜 `state:` 前缀；非法状态转换会记录 `state: illegal transition`。
- 私有 API 降级：SkyLight 不可用时相关调用返回失败，日志可见 `private SLS ... unavailable`。
- 卡顿归因：`main-thread stall` 会附带卡顿窗口内累计占用最久的标记及占比，
  `未标记` / `占 0%` 说明阻塞落在所有标记之外（多半在异步回调里）。
- AX / SkyLight 调用成本基准：`WindowShade.app/Contents/MacOS/WindowShade --duo-ax-bench`
  （只读；必须用签名后的 bundle 运行，否则拿不到辅助功能权限）。
  输出首次/重复完整枚举、原始 AX 列表、新建/复用应用句柄、ID 匹配及过滤成本。
  加 `--ax-raw-first` 会先读原始列表，用来区分系统首次读取与生产过滤成本；
  两种顺序应分别运行，不能把相邻热查询的中位数当作首次响应或 p95/p99。
- 标题栏控件输入回归：签名后的隔离应用运行 `--duo-window-test --input-test`。探针启动自己的临时窗口，在标题栏放入输入框并预热裁剪缓存，确认真实 AX 命中后调用生产双击/三击处理函数，检查输入没有被吞掉或排入窗口操作。需要辅助功能权限及系统标题栏双击动作；不发送全局模拟点击，输出耗时不包含系统事件交付。测试会短暂激活临时窗口，以核对聚焦查找；结束后仅在前台仍是临时窗口时恢复原应用，不覆盖用户中途切换。

### 系统集成与质感批次

- 这批改动的评审索引（改动位置、行为、证据、验证命令、未验证项）见
  [系统集成与质感批次](docs/system-integration-polish.md)。
- 两个可复现检查脚本：`scripts/check-settings-appearance.sh`（设置页浅深色自适应）、
  `scripts/check-standard-menu.sh`（关于面板与代理应用主菜单下的 ⌘V）。
- 其余入口：`--settings-shots`（设置页真实截图）、`--window-browser-shots`（窗口浏览
  组件截图 + 卷帘条配色检查）、`--standard-menu-probe`（打包探针）。

### 窗口浏览（Dock 悬停 / 窗口选择面板）

- 纯逻辑与离屏 AppKit 回归：`bash tests/run-window-browser-tests.sh`
  （身份/目录/动作/缩略图/布局/状态机；不请求权限、不操作用户窗口）。

  - 该脚本编译窗口浏览的生产源文件并运行 690 项断言，另运行预览启动取消/乱序和元数据队列阻塞回归；每次都会打印 50/200 窗口的
    首屏耗时，便于和 `docs/window-browser-performance.md` 的数字对照。
  - 生产源文件清单与 `prototype/build.sh` 的自动收集保持一致；新增窗口浏览源文件
    时同步更新该脚本（只是显式列出，不复制实现）。

- 真实组件截图（隔离构建，不停止正在使用的应用）：

  ```sh
  cd prototype && WINDOWSHADE_CODESIGN_IDENTITY="Apple Development: …" ./build.sh --stage
  cd .. && .build/duo-validation/WindowShade.app/Contents/MacOS/WindowShade \
    --window-browser-shots .build/window-browser-shots
  ```

  输出 16 张 PNG 与 `manifest.txt`（OS/SDK/缩放率/数据来源）。截图来自生产
  `WindowBrowserPanel` 组件，数据是内置记录与本地占位画面，不打开真实窗口。
  `WINDOWSHADE_SHOTS_DEBUG=1` 会打印首张卡片的 frame 摘要。

- 激活应用统一用 `NSApp.activate()`（macOS 14+ 协作式），不要再用将被取代的
  `activate(ignoringOtherApps:)`；键盘面板的激活重试与聚焦逻辑在
  `WindowBrowserPanel.presentKeyboardPanel()`。
- 设置窗口页面截图（离屏、不需要录屏权限）：
  `./build.sh --stage` 后运行
  `.build/duo-validation/WindowShade.app/Contents/MacOS/WindowShade --settings-shots .build/settings-shots`
  输出每页的浅色/深色 PNG 与 `manifest.txt`；侧栏由系统材质绘制、效果页的 Metal 预览
  画布也不会出现在离屏图里。窗口可自由缩放，`WINDOWSHADE_SETTINGS_SHOTS_SIZE=1115x680`
  可以把同一批页面渲染成别的尺寸（内容列左右留白是否对称只能在非默认宽度上看出来）。
  每次渲染都会打印一行内容列居中自检（`内容列居中偏移 0.0pt PASS`）：收起侧栏后详情区变成
  整窗宽，内容列必须仍然居中，贴左会在右半边留下大片空白。
  `WINDOWSHADE_SETTINGS_SHOTS_SIDEBAR=collapsed|expanded` 会在拍卷帘页前切换侧栏并核对窗口宽度
  没变（`侧栏展开时窗口宽 900pt（切换前 900pt）PASS`）——设置窗口的最小尺寸只能用
  `window.contentMinSize` 表达，给 split view 挂 required 宽高约束会让 AppKit 在展开侧栏时把整扇
  窗口撑大一个侧栏宽度（实测 900 → 1115）。
- 设置页外观自适应回归：`bash scripts/check-settings-appearance.sh`
  （逐页比较浅色/深色平均亮度，防止静态颜色被冻结的缺陷复发）。
- 系统外观（材质 / 对比度边线 / 薄纱 / 动画 / 可访问性文案）集中在
  `prototype/Overlay/SystemAppearance.swift`：新增自定义表面时用 `SystemMaterialView`
  并在 `applySystemAppearance(capabilities:)` 里读取 `SystemAppearancePolicy`，
  不要在调用点各自判断 `accessibilityDisplayShould*`。`tests/run-paper-tests.sh`
  覆盖策略本身与各表面的接线（材质、薄纱、边线、VoiceOver 文案）。
- 代理应用的主菜单：WindowShade 是 `LSUIElement`，不显示菜单栏，但文本编辑快捷键与
  ⌘W 依赖主菜单的 key equivalent。菜单由 `prototype/App/StandardMenu.swift` 生成，
  在 `applicationDidFinishLaunching` 里安装；改动菜单后跑
  `bash scripts/check-standard-menu.sh` 复核关于面板、无主菜单不粘贴、有主菜单可粘贴
  （打包探针会临时激活应用约 1 秒）。
- 编译期玻璃能力探测：`build.sh` 与测试脚本都会检查当前 SDK 是否包含
  `AppKit.framework/Headers/NSGlassEffectView.h`，包含时定义
  `WINDOWSHADE_SDK_HAS_GLASS`。旧 SDK 构建时玻璃分支不参与编译，运行时再用
  `#available(macOS 26.0, *)` 决定是否启用；玻璃实现单独放在
  `prototype/WindowBrowser/WindowBrowserMaterial.swift` 的
  `WindowBrowserGlassBackdrop` 里。

- 性能对照脚本（同机、同数据、基线 worktree）：

  ```sh
  git worktree add /tmp/ws-baseline 05e5472370e199e92b147f1e0af72175c6429288
  /tmp/run-perf.sh    # 内容见 .build/window-browser-perf/ 的说明
  ```
- 隔离 fixture（不进入正式 AppDelegate，按钮只改 fake 状态）：

  ```sh
  cd prototype && WINDOWSHADE_CODESIGN_IDENTITY="<身份>" bash build.sh --stage
  APP=../.build/duo-validation/WindowShade.app/Contents/MacOS/WindowShade
  WINDOWSHADE_BROWSER_FIXTURE=many WINDOWSHADE_BROWSER_FIXTURE_AUTOEXIT=3 "$APP" --window-browser-fixture
  ```

  `WINDOWSHADE_BROWSER_FIXTURE` 可选 `mixed / many / empty / long / nopermission`，
  `WINDOWSHADE_BROWSER_FIXTURE_SIZE=small` 用小屏尺寸，
  `WINDOWSHADE_BROWSER_FIXTURE_APPEARANCE=dark|light` 强制浅/深色外观，
  `WINDOWSHADE_BROWSER_FIXTURE_STYLE=list|grid` 会在自动退出前像用户一样点一次
  分段控件（用来验证“点了就换布局”，输出里的 `renderedStyle/renderedRows/renderedCards`
  是真实渲染结果）。
- 只读真机探针（不移动用户指针、不捕获用户窗口；详见
  [窗口浏览进度](docs/window-browser-progress.md) 的命令清单）：
  `--window-browser-dock-probe`、`--window-browser-hover-probe`、
  `--window-browser-catalog-probe`、`--window-browser-capture-probe`
  （只捕获本应用自己的探针窗口）、`--window-browser-thumbnail-probe`、
  `--window-browser-stream-probe`、`--window-browser-panel-probe`、
  `--window-browser-ui-probe`、`--window-browser-idle-probe`
  （临时关闭 Dock 开关后测空闲查询数，结束时恢复设置）、
  `--window-browser-identity-probe`（真实 AX 身份解析：包含同名同位置的两个原生窗口、
  歧义拒绝、关闭后不替换目标与协调器拒绝分支；不修改用户窗口）。
  例外：`--window-browser-live-app-probe` 会对**另一个正在运行的 WindowShade**
  走一遍真实状态栏菜单项并打开一次面板（随后按 Esc 关闭）。它只读用户窗口、不改设置，
  但会短暂占用菜单栏与屏幕，请在不需要用机的时机运行。
  `--window-browser-hover-live-probe` 会把系统指针移到 Dock 图标上约 1.2 秒再放回，
  用于验证真实悬停通知；只悬停、不点击、不激活，运行前请确认当前没有正在进行中的
  拖拽或需要保持指针位置的操作。

用户向说明（入口、权限、兼容限制）见 [docs/window-browser.md](docs/window-browser.md)。

需要外部/更高智能模型复检时，用 [复检交接与提示词](docs/review-handoff.md)：里面是
可直接粘贴的评审提示词、按任务书逐条列出的需求与状态、已知缺口、冲突消解记录和复检命令。

动手优化这一带之前先读 [docs/performance.md](docs/performance.md)：那里记了
实测的调用成本量级、已走通的手法、以及已经证伪的方向（比如用 SkyLight
绕开目标 App 在 SIP 开启时不可行），可以省掉重新走一遍的时间。

## 发布前测试清单

在以下应用上验证折叠 / 展开、双击标题栏、卷帘条预览、置顶预览、菜单管理、`⌃⌘1...9`、`⌃⌘0`：

- Finder
- Safari
- Chrome
- Telegram
- WeChat
- Adobe Photoshop
- Premiere
- After Effects
- System Settings

异常场景：

- 杀掉 WindowShade 进程后，journal 能把停车窗口救回（启动后自动救援）。
- 无录屏权限时原貌卷帘降级为代理标题栏，不崩溃。
- 快速连续双击 / 快捷键不破坏窗口状态（状态机拒绝非法转换）。

## 发布流程

1. 在 `prototype/Info.plist` 升级 `CFBundleShortVersionString` 和 `CFBundleVersion`。构建脚本在签名前同步这两个字段，不手改生成的 bundle。
2. `./build.sh --stage` 隔离构建并签名，产物为 `.build/duo-validation/WindowShade.app`，不会停止或覆盖日常运行的应用。运行相关回归检查并验证签名、版本、架构。
3. 打包（版本号统一从 `CFBundleShortVersionString` 读取，不用手改示例）：

   ```sh
   cd prototype
   VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Info.plist)
   mkdir -p dist
   ditto -c -k --sequesterRsrc --keepParent ../.build/duo-validation/WindowShade.app "dist/WindowShade-v${VERSION}.zip"
   (cd dist && shasum -a 256 "WindowShade-v${VERSION}.zip" > "WindowShade-v${VERSION}.zip.sha256")
   ```

4. 将实际构建的源文件、版本与发布说明提交并推送后，打新标签并发布；发布包必须与提交的源码一致：

   ```sh
   # 仍在 prototype/ 目录下执行
   VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Info.plist)
   git tag "v${VERSION}" && git push origin "v${VERSION}"
   gh release create "v${VERSION}" \
     "dist/WindowShade-v${VERSION}.zip" "dist/WindowShade-v${VERSION}.zip.sha256" \
     --title "WindowShade v${VERSION}" \
     --notes-file "../docs/releases/v${VERSION}.md"
   ```

`prototype/dist/` 已在 `.gitignore` 中，发布产物不会污染工作区。默认构建架构为本机架构；发布说明须标明实际架构。Apple Development 签名不等于公证，不宣称已经 notarized。

### 同一版本重新发布

只更换安装包、不升版本号时（例如修好某个功能后重发包），沿用同一个 tag 覆盖发布：

```sh
# 仍在 prototype/ 目录下执行
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Info.plist)
git tag -f "v${VERSION}" && git push --force origin "v${VERSION}"
gh release edit "v${VERSION}" --notes-file "../docs/releases/v${VERSION}.md"
gh release upload "v${VERSION}" \
  "dist/WindowShade-v${VERSION}.zip" "dist/WindowShade-v${VERSION}.zip.sha256" --clobber
```

tag 会被移动到新的发布提交，Release Notes 与附件一并替换；请确保签名身份不变，
否则用户覆盖安装后需要重新授权辅助功能与屏幕录制。
