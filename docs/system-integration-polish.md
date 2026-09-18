# 系统集成与质感批次（作为 1.0.14 交付）

本文是这批“与系统浑然一体”改动的评审索引：每一项都给出改动位置、行为与验证证据。
用户确认“时机成熟”后，本批改动按 §8 交付为 **1.0.14**：本地提交、推送、tag 与 GitHub
Release 一并完成，本机应用用同一签名身份原地替换。版本历史见
[`docs/releases/v1.0.14.md`](releases/v1.0.14.md)；下面的验证结果仍按提交前的测量原样保留。

## 一句话范围

在 1.0.13 的窗口浏览改版之上，把全应用的自定义表面接到同一份系统外观策略上，
补齐代理应用缺失的 AppKit 契约（主菜单、协作式激活、深链、标签页），修掉三类
“颜色/外观被冻结”的真实缺陷，并把可访问性补到“能操作、能听见、能理解”。

## 1. 统一外观与材质

| 改动 | 位置 | 证据 |
| --- | --- | --- |
| 新增全应用 `SystemAppearancePolicy`（材质、边线、薄纱、阴影、动画、字号） | `prototype/Overlay/SystemAppearance.swift` | `tests/run-paper-tests.sh` 策略断言 |
| 卷帘条、悬停缩略图、置顶预览、代理标题栏、引导页背景、窗口浏览面板统一走该策略 | `Overlay/*`、`PinnedPreviewPanel.swift`、`App/OverlayFactory.swift`、`App/Preferences.swift` | 材质接线断言 + `docs/visual-qa/system-appearance/*.png` |
| 减少透明度 / 提高对比度 / 减少动态效果 / 浅深色变化时刷新已打开表面 | `WindowShade.swift` 的外观观察者 | `classic-strip-palette PASS`、设置页外观检查 |
| 面板背景与控制层两块玻璃交给公开 `NSGlassEffectContainerView` 协调 | `WindowBrowserMaterial.swift`、`WindowBrowserViews.swift` | 容器存在与归属断言 |
| 窗口浏览面板 100–120 ms 淡出，遵守减少动态效果 | `WindowBrowserPanel.swift`、`WindowBrowserController.swift` | 代码路径 + 设置页外观检查 |
| 首次显示只做一次整面板刷新（首次说明只改页脚文本） | `WindowBrowserController.swift` | 代码路径（Dock 与键盘两条入口都已合并） |
| 左/右 Dock 的网格列数上限收紧到两列、面板 ≤640 pt | `WindowBrowserGeometry.swift` | 几何断言（side Dock ≤2 列、bottom Dock 仍 3 列） |
| 圆角统一到一份刻度：窗口级 13 pt（本机实测 macOS 27 窗口）、卡片 12、控件 6，嵌套按“外圆角 − 间距”同心，图层一律连续曲率；经典卷帘条改为“上两角圆、下边缘直切” | `Overlay/SystemAppearance.swift`（`SystemCornerRadius` / `SystemCornerPath`）、`WindowBrowserGeometry.swift`、`ShadeStrip.swift`、`PaperSurfaceStyle.swift`、`PinnedPreviewPanel.swift`、`PreviewSurfaces.swift`、`Preferences.swift` | `tests/run-paper-tests.sh` 与 `tests/run-window-browser-tests.sh` 的刻度/同心/路径断言 + `docs/visual-qa/**` 重新生成的截图 |

## 2. 修掉的三类真实缺陷

1. **动态颜色在错误外观下解析**：`NSColor.cgColor` 必须在该视图的
   `effectiveAppearance` 块内解析。实测修复前“浅色行 + 深色面板”错配；
   现在行背景 `1.000 → 0.118 → 1.000`（浅→深→浅），并有断言。
   位置：`SystemAppearancePolicy.cgColor(_:for:)` 及全部调用点。
2. **设置页分组盒填充被冻结**：`blended(withFraction:)` 返回静态颜色，深色下卡片
   仍是浅色、文字几乎不可读；改为绘制时解析的动态颜色，并有“浅色比深色亮 0.3”
   的断言与设置页逐页亮度检查（0.744–0.842）。
3. **经典卷帘条配色不随外观更新**：配色改为持有 pid + `refreshPalette()`；
   探针验证“浅色创建 → 切深色 → 刷新”与“直接深色创建”逐项一致。

## 3. AppKit 契约

| 问题 | 修复 | 证据 |
| --- | --- | --- |
| 代理应用（`LSUIElement`）没有主菜单 → ⌘X/⌘C/⌘V/⌘A/⌘Z、⌘W 全部无效 | 新增 `StandardMenu`（应用/编辑/窗口菜单），启动时安装 | `scripts/check-standard-menu.sh`：无主菜单 `handled=false searchText=""`；有主菜单 `handled=true searchText="粘贴内容"` |
| `activate(ignoringOtherApps:)` 将被取代 | 8 处改为 macOS 14 起的协作式 `NSApp.activate()` | 同一脚本对比两种方式均 `active=true key=true` |
| 设置/引导/面板可能被系统并成标签页 | 显式 `tabbingMode = .disallowed` | `tests/run-window-browser-tests.sh` 断言 |
| 权限与“减少动态效果”深链用旧面板标识 | 按本机是否存在 ExtensionKit 面板决定顺序，保留旧标识兜底 | 断言 + 打印 `hasModernPane=true hasModernAccessibilityPane=true` |

## 4. 可访问性

- 卡片/列表行：标签、值、帮助、自定义动作共享同一份能力模型；**VO 焦点跟随方向键与
  搜索**；**VO-Space 与鼠标点击走同一条激活路径**（未配置返回 false）。
- 卷帘条：截图条与经典条都有 VoiceOver 名称/帮助/“展开窗口”动作、tooltip 与 VO-Space。
- 悬停缩略图、菜单缩略图、置顶预览：朗读并提示“是哪个窗口”，无标题时退回通用文案。
- 动作结果与页脚结果状态各播报一次；刷新型文字不打断。

## 5. 交互

- Space 打开当前窗口的**只读大图预览**（Quick Look 习惯）：只用已有画面，不激活/
  展开/移动源窗口；Escape 分层为「大图 → 排布预览 → 关闭面板」，点击大图也关闭；
  取图顺序为「新鲜服务缓存 → 过期快照 → 折叠快照 → 应用图标 + 原因」，过期画面会在
  说明行标成「快照（画面可能已过期）」；窗口尺寸按比例放进可见区域并**整体钳制回可见
  区域**（极小屏幕/负坐标/退化可用区域都有断言）。
- 搜索框 Escape 先清空文本；⌘F 聚焦搜索；键盘面板可拖背景移动；操作条靠右、
  末尾固定“更多”入口（与右键同菜单）。
- 状态栏：折叠窗口前 9 个带 ⌃⌘1…9、其余进“更多”子菜单；置顶列表去掉误导性编号；
  菜单标题统一截断；临时提示只显示短标题（完整文案在 tooltip/可访问性值）。
- 排版：窗口浏览与设置页字号改为“相对正文字号”，跟随系统“文字大小”；默认外观下
  设置页**内容区**与改动前逐像素零差异（同一离屏口径的 `pixdiff` 报告
  `differing pixels=0`；归档截图后来改成整窗截图，多出来的只是系统侧栏材质）。

## 6. 验证命令与结果

```sh
bash tests/run-window-browser-tests.sh    # PASS：589 项断言
bash tests/run-paper-tests.sh             # PASS（策略/接线/文案/字号）
bash tests/run-duo-tests.sh               # PASS
cd prototype && ./build.sh --check        # 编译验证通过
./build.sh --stage                        # 隔离构建 + 签名成功

bash scripts/check-settings-appearance.sh # 五页外观自适应全部 PASS
bash scripts/check-standard-menu.sh       # 关于面板 + ⌘V 对照全部 PASS

# 真实组件截图（生产视图，无需录屏权限）
.build/duo-validation/WindowShade.app/Contents/MacOS/WindowShade \
  --window-browser-shots .build/window-browser-shots   # classic-strip-palette PASS
.build/duo-validation/WindowShade.app/Contents/MacOS/WindowShade \
  --settings-shots .build/settings-shots
```

只读探针（隔离构建）：`--window-browser-idle-probe`（功能关闭时 0 AX 查询）、
`--window-browser-thumbnail-probe`（2 次物理截图、4 次投递、`running=0`）、
`--window-browser-hover-probe`（无授权时不产出目标并干净停止）。

## 7. 未验证与已知限制

- 实机悬停/焦点/折叠/排布、玻璃折射整窗截图、1x、多显示器与 120 Hz、能耗与长会话
  footprint 仍需要在授权构建与额外硬件上手工验证（步骤见 `window-browser-visual-qa.md`）。
- 快速单窗预览仍依赖 Apple 已弃用的 `CGWindowListCreateImage`：当前可用，符号被移除时
  会记录一次并退回代理标题栏/无预览；未来某版应切到 SCK。
- 卷帘条拖拽没有加入“吸附回原位”：这个手势没有对应的系统惯例，且应用已经提供显式
  排布动作，磁吸可能反而干扰精细定位（保留为有意不做）。

## 8. 交付记录（2026-09-18）

```sh
# 1) 本地提交：08dab48 Release 1.0.14: system integration and native polish（73 个文件）

# 2) 发 1.0.14：Info.plist 1.0.14 / 14 + docs/releases/v1.0.14.md + README 双语
#    + build.sh --stage（同一 Apple Development 身份）+ ditto 打包 + sha256
#    + git push origin main + tag v1.0.14 + gh release create（附件 zip 与 sha256，标记 Latest）
#    zip：3,702,219 字节，sha256 620bb348e0d1379189d5f9ec823c17557e260d4eae3b5de2e32ed5e4d7390852

# 3) 原地替换本机应用（会短暂停止并重启 WindowShade）
cd prototype && WINDOWSHADE_CODESIGN_IDENTITY="Apple Development: openkams@gmail.com (G3TN2MBQ2Q)" \
  ./build.sh && open WindowShade.app        # pid 20543 → 14370，bundle 1.0.14 / build 14

# 4) 站点：site/scripts/content.mjs 增补空格大图预览与 1.0.14 设置说明，npm run deploy
```

发版前的完整验证结果见 §6；替换后的实机只读探针数字见
[`docs/window-browser-progress.md`](window-browser-progress.md) 的 1.0.14 段落。
