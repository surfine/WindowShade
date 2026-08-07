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
├── WindowShade.swift                 # AppDelegate 骨架 + 文件级基础设施（日志、缓存、全局辅助）
├── ScreenCaptureBridge.swift         # SCStream 捕获（置顶预览的实时流）
├── PinnedPreview.swift               # 置顶预览控制器（目标解析、watchdog、交互接管）
├── PinnedPreviewPanel.swift          # 预览面板与菜单实时缩略图
├── App/                              # AppDelegate 扩展（按功能拆分的控制器）
│   ├── MenuBarController.swift       # 状态栏图标、菜单重建与菜单代理回调
│   ├── Reconcile.swift               # 折叠会话监控（reconcile 定时核对/并行快照）
│   ├── EventTap.swift                # 全局快捷键、事件 tap、标题栏双击/三击
│   ├── Preferences.swift             # 偏好设置与引导页
│   ├── OverlayPresentation.swift     # 覆盖层展示与 Space 不变量
│   ├── HoverPreview.swift            # 悬停预览（peek / 菜单悬停）
│   ├── OverlayFactory.swift          # 覆盖层窗口工厂（截图条/经典条/代理标题栏）
│   ├── ArrangeController.swift       # 卷帘条整理与专注 shelf
│   ├── FocusSession.swift            # 专注会话
│   ├── FoldTransaction.swift         # 折叠事务辅助（隐藏/恢复/验证/转发/通知）
│   ├── ShadeController.swift         # 折叠入口（shade/toggle/折叠计划/截图）
│   └── FoldExit.swift                # 折叠出口（unshade/清理/交通灯/QuickLook）
├── Private/
│   └── SkyLightBridge.swift          # SkyLight 私有 API 隔离层（全部有 fallback）
├── Compatibility/
│   ├── WindowPolicy.swift            # 窗口策略协议 + CaptureMode/HidingStrategy
│   └── Policies.swift                # 具体策略 + windowPolicy(for:)
├── Core/
│   └── WindowState.swift             # 折叠操作状态机（非法转换拒绝）
├── Capture/
│   ├── WindowSnapshotCache.swift     # 折叠截图 500ms 短 TTL 缓存
│   └── PreviewRenderer.swift         # 渲染与图像分析（chrome 扫描、圆角镜像、条制备）
├── Overlay/
│   ├── ShadeStripPool.swift          # 简单卷帘条窗口池（OverlayWindow 复用）
│   └── ShadeStrip.swift              # 覆盖层视图（代理标题栏/经典条/预览窗/调色板）
├── Window/
│   ├── WindowRegistry.swift          # app 元数据（名称/bundleID）短 TTL 缓存
│   └── AXWindow.swift                # AX 辅助（几何/ID 解析/chrome 探测/按钮交互）
└── Recovery/
    ├── Journal.swift                 # 恢复日志数据层（持久化/匹配/生命周期标记）
    └── Rescue.swift                  # 离屏窗口救援编排（后台扫描 + 主线程写回）
```

> 新增源文件后，记得把它加进 `prototype/build.sh` 的 swiftc 编译列表。

## 构建

构建脚本原地更新 `prototype/WindowShade.app`（保留 bundle、Info.plist 与资源），所以需要先有一个 app bundle——全新克隆时先从 [Releases](https://github.com/surfine/WindowShade/releases/latest) 下载一份，或复制已有 bundle。

```sh
cd prototype
./build.sh
open WindowShade.app
```

### 签名

`build.sh` 顶部有一个固定的 Apple Development 身份：

```sh
IDENTITY="Apple Development: Your Name (TEAMID)"
```

把它改成你自己的证书。保留 bundle + 固定签名身份的原因：macOS 的 TCC 授权（辅助功能 / 屏幕录制）绑定签名身份，重建 bundle 或换 ad-hoc 签名会重置权限。

### 直接编译（不签名，仅验证）

```sh
cd prototype
env CLANG_MODULE_CACHE_PATH="$(cd .. && pwd)/.build/module-cache" swiftc -O -o /tmp/windowshade-check \
  $(find . -maxdepth 2 -name '*.swift' | sort) \
  -framework Cocoa -framework Carbon -framework ApplicationServices \
  -framework ScreenCaptureKit -framework QuartzCore -framework CoreText \
  -framework AVFoundation -framework ServiceManagement
```

> 直接编译用 `find` 自动收集源文件；新增文件无需手工维护此命令（`build.sh` 的列表仍需手动追加）。

## 调试

- 日志写在 `/tmp/windowshade.log`，5MB 自动轮转（旧文件为 `.1`）。
- 主线程卡顿：日志里搜 `main-thread stall`。
- 慢操作：日志里搜 `slow:` 前缀。
- 状态机：日志里搜 `state:` 前缀；非法状态转换会记录 `state: illegal transition`。
- 私有 API 降级：SkyLight 不可用时相关调用返回失败，日志可见 `private SLS ... unavailable`。

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

1. 升级版本号：`prototype/Info.plist` 与 `prototype/WindowShade.app/Contents/Info.plist` 的 `CFBundleShortVersionString`。
2. `./build.sh` 构建并签名。
3. 打包：

   ```sh
   cd prototype
   mkdir -p dist
   ditto -c -k --sequesterRsrc --keepParent WindowShade.app dist/WindowShade-v1.0.8.zip
   shasum -a 256 dist/WindowShade-v1.0.8.zip > dist/WindowShade-v1.0.8.zip.sha256
   ```

4. 打标签并发布：

   ```sh
   git tag v1.0.8 && git push origin v1.0.8
   gh release create v1.0.8 dist/WindowShade-v1.0.8.zip dist/WindowShade-v1.0.8.zip.sha256 \
     --title "WindowShade v1.0.8" --notes "..."
   ```

`prototype/dist/` 已在 `.gitignore` 中，发布产物不会污染工作区。
