# WindowShade 设计规范 v1 落地

参考：[WindowShade 设计规范 v1](https://claude.ai/code/artifact/ad9bf7aa-e7e0-477b-864d-88437748c3ed)，原代码基线 `ae65fcd`。

## 实现

- 设置采用 `NSSplitViewController`、系统 source list 与 unified 工具栏。分节名显示在窗口副标题，侧边栏支持键盘导航和折叠，列表的选中、失焦、辅助功能交给 AppKit。
- 默认窗口 900 × 680，最小 820 × 580；侧边栏初始 214，内容左对齐、上限 640，页边距左右 28、上下 22。
- 四页和引导权限区复用 `NSBox.custom` 分组盒：系统实色、圆角 10、无描边无阴影。分组标题纯文字，分隔线左端缩进 16。
- 传感器状态并入效果页说明，数字采用等宽数字字体。暂停和录屏设置按钮归入相应分组；实验性选项放在末尾。
- 静态预览改为四条冷白横带和底部卷轴；进度滑杆独占图形下方一行。静态图不启动持续渲染时钟。
- 卷帘与置顶面板使用共享纸面边缘和阴影参数。影子由鼠标穿透的子窗口绘制，不扩张父窗口的源窗口对齐坐标；同步移动、缩放、显隐、透明度与层级，回收时清除。
- 标准标题栏使用 popover 材质、顶边高光及 0.5pt 内边；置顶标题使用 HUD 材质，悬停时出现。预览缩略图圆角统一为 6。
- 菜单折叠项带 16pt 应用图标，角度行带状态图标，菜单栏数量使用等宽数字。
- 权限状态集中在行尾：待授权橙点、已授权绿勾；不再用整行黄色背景。引导与设置使用同一个权限行构建函数。
- 页面/悬停状态过渡使用 0.15s ease-out；减少动态效果开启时跳过新增过渡。折叠驱动、快捷键与四分节划分保持原有行为。

## 代理应用的主菜单（1.0.13 之后）

WindowShade 是 `LSUIElement` 代理应用，屏幕顶部不显示菜单栏；但 AppKit 的文本编辑
快捷键（⌘X/⌘C/⌘V/⌘A/⌘Z）与 ⌘W 都通过**主菜单的 key equivalent** 派发。实测（同一
份代码、真实键盘面板、应用已激活且面板为 key window）：

| 情况 | 菜单是否认领 ⌘V | 搜索框内容 |
| --- | --- | --- |
| 没有主菜单 | `handled=false` | `""`（粘贴不生效） |
| 安装标准最小主菜单 | `handled=true` | `"粘贴内容"` |

因此新增 `prototype/App/StandardMenu.swift`：应用菜单（关于/设置…/服务/隐藏/退出）、
编辑菜单（撤销/重做/剪切/拷贝/粘贴/删除/全选）与窗口菜单（关闭 ⌘W、最小化 ⌘M）。
它不改变代理应用的菜单栏行为，只让窗口浏览搜索框、排除清单、快捷键录制等所有文本框
恢复系统习惯，并让 ⌘W 走面板自己的取消路径（先取消排布预览再关闭）。

“关于”面板用系统标准面板（版本/构建号 + 一句用途说明 + MIT 许可与仓库链接），从
状态栏菜单的「关于 WindowShade」进入；菜单栏临时提示只显示短标题（≤14 字符、按
标点收尾），完整文案放在 tooltip 与可访问性值里，避免一句长提示把菜单栏挤宽。

激活统一改用 macOS 14 起的协作式 `NSApp.activate()`（应用自身的关于面板、引导页、
设置窗口、键盘面板与卷帘条恢复路径共 8 处，全部由用户操作触发）。实测对比：协作式
`activate()` 与旧的强制激活在最少用户手势的场景下都得到
`active=true key=true`，因此不再使用将被取代的 `activate(ignoringOtherApps:)`。

复现：`bash scripts/check-standard-menu.sh`（结果写到
`.build/design-review/standard-menu-check.txt`，包含关于面板是否出现、无/有主菜单下
⌘V 的对照，以及真实键盘面板的端到端结果）。

## Space 只读大图预览（1.0.13 之后）

任务书里标为“可选增强”的 Space 大图预览已实现：`WindowBrowserQuickLookPolicy` 决定
取图来源（视图缓存 → 折叠快照 → 应用图标）、窗口尺寸（按比例放进可见区域 70%，
小图不放大）与无图时的说明；控制器只读显示，不激活/展开/移动源窗口，也不为预览
发起截图。Escape 的分层顺序是“大图 → 排布预览 → 关闭面板”。

顺带修掉一个真实小缺陷：`searchFieldIsFocused` 写成
`window?.firstResponder === searchField.currentEditor() || …`，在没有窗口时两边都是
nil，`nil === nil` 会误判成“正在编辑”，使 Space/方向键被当作文本输入交给 super。
现在要求窗口与 first responder 都存在；相应地，⌘F 的断言改为在真实窗口里验证
（旧断言曾因此假通过）。

## 已弃用快速预览接口的可见降级（1.0.13 之后）

折叠条与悬停预览的“快速单窗预览”走的是 `CGWindowListCreateImage`（通过 dlsym 动态取
符号，Apple 已把该接口标记为废弃、建议改用 ScreenCaptureKit）。当前系统上它仍可用且
比异步 SCK 路径便宜；一旦未来系统移除该符号，`LegacyQuickCapture` 会记录一次
`capture: CGWindowListCreateImage unavailable…`，调用方已有的降级随之生效：
折叠条退回代理标题栏、悬停预览退回“没有预览”，不会静默损坏或崩溃。

仍然依赖该接口的功能需要在未来某个版本切换到 SCK（本次未改，避免在没有权限的
隔离构建里改动捕获主路径）。

## 状态栏菜单的标题与置顶列表（1.0.13 之后）

- 菜单里的窗口标题统一走 `StandardMenu.menuTitle(_:limit:)`（默认 42 字、去空白、
  超出加省略号），折叠列表与置顶列表一致，避免单项把菜单撑到屏幕宽。
- 置顶列表去掉“1  标题”这样的编号：这些条目并没有 ⌃⌘ 快捷键，编号会让人误以为有；
  真正带快捷键的折叠列表保留编号。

## 页脚结果状态的读屏播报（1.0.13 之后）

面板页脚里的**结果性**状态（实时预览回退、排布结果、首次说明等）现在会在变化时播报
一次，读屏用户不必盯着界面才知道“已回到快照”或“排布结果无法确认”；刷新型文字
（“正在刷新窗口…”）与重复内容不播报。规则抽成
`WindowBrowserStatusAnnouncement.shouldAnnounce`，断言覆盖“播一次”“不重复播”
“刷新文字不打断”“空状态不播”。

## 状态栏菜单的折叠窗口分区（1.0.13 之后）

折叠窗口多时，原来会把全部窗口内联列出，而快捷键只到 ⌃⌘9，后面那些没有任何说明。
现在前 9 个内联并带 ⌃⌘1…⌃⌘9，其余进「更多已折叠窗口（N）」子菜单（同样的动作、图标
与目标身份，只是不带快捷键）。切分与快捷键映射抽成 `StandardMenu.splitFoldedWindows`
与 `foldedWindowShortcut(index:)`，断言覆盖“短列表不分段”“长列表保序不丢项”
“前 9 个有快捷键、其余没有”。

## 可访问性“按下”契约（1.0.13 之后）

VoiceOver 焦点移到卡片/行（见上文）之后，VO-Space 的“按下”必须真的能激活窗口，否则
读屏用户只能靠自定义动作。现在：

- 窗口浏览的卡片与列表行 `accessibilityPerformPress()` 直接走与鼠标点击相同的
  `browserItemDidActivate` 路径（未配置时返回 false）；
- 截图卷帘条与经典卷帘条同样把“按下”映射到双击展开。

断言覆盖“配置后的卡片/行的按下触发一次激活并返回 true”“未配置的卡片返回 false”。

## 设置页字号跟随系统文字大小（1.0.13 之后）

设置/引导页原来把标题写 13pt、说明 12pt、次级 11pt、引导标题 20pt 写死；macOS 14+
可以按 App 调整“文字大小”，写死字号不会跟随。现在这些字号统一走
`SystemAppearancePolicy.font(relativeToBody:)`（正文字号来自
`NSFont.preferredFont(forTextStyle: .body)`，delta 保持原来的相对关系，下限 9pt）。
行本身用的是最小高度而不是固定高度，字号变大时行会自然长高。

验证：默认文字大小下设置页**内容区**与改动前逐像素零差异（同一离屏口径的 `pixdiff`
报告 `differing pixels=0 maxDelta=0.000`，两张页面），说明观感未变；断言覆盖
“delta 0/-1/-2 相对关系”“默认下仍是 13/12/11/20”。归档截图后来改成整窗截图
（含系统侧栏材质），因此不能再拿新旧归档图直接做整图比对。

## 动态颜色必须在视图自己的外观下解析（1.0.13 之后）

把语义颜色写进 `CALayer` 时，`NSColor.cgColor` 会按 `NSAppearance.currentDrawingAppearance`
取值——在 `viewDidChangeEffectiveAppearance` 内那次解析可能仍取到**切换前**的外观，
于是层颜色被冻住。实测：浅色下创建行、切到深色后，行背景亮度仍是 1.000（期望 0.118），
面板浅色 + 行深色/反之的错配就是这样产生的。

修复：`SystemAppearancePolicy.cgColor(_:for:)` 在 `view.effectiveAppearance.performAsCurrentDrawingAppearance`
**块内**解析并返回 `CGColor`（`.cgColor` 本身也要在块内调用），窗口浏览的卡片/行/图片区、
材质宿主、控制层、截图卷帘条、悬停与置顶缩略图、设置页权限卡片与行全部改用它。

验证：

- 单元断言：切到深色后行背景亮度 < 0.5（修复前为 1.000），切回浅色 > 0.6。
- 真实像素：`--window-browser-shots` 的列表页在浅色面板下重新变为浅色行，
  归档图 `docs/visual-qa/window-browser/keyboard-list-eight.png` 已更新。

## 每个表面都能说明自己是哪个窗口（1.0.13 之后）

- 截图卷帘条：VoiceOver 名称/帮助/“展开窗口”动作之外，新增鼠标悬停 tooltip
  （`应用 — 标题`，无标题时退回应用名），与经典卷帘条一致。
- 悬停缩略图（`SafariStylePreviewView`）与菜单里的实时缩略图
  （`PinnedLivePreviewView`）现在接收窗口名，同时设置 VoiceOver 标签与 tooltip；
  创建点分别来自折叠会话（`shaded[id]`）与置顶会话快照。
- 断言覆盖“缩略图朗读并提示窗口名”与“无标题时退回‘窗口预览’”。

## 系统设置深链（1.0.13 之后）

权限与“减少动态效果”的跳转统一走 `SystemSettingsLinks`：macOS 13 起隐私/辅助功能面板
由 ExtensionKit 承载（本机实测 `com.apple.settings.PrivacySecurity.extension`、
`com.apple.Accessibility-Settings.extension`），旧系统仍是 `com.apple.preference.security`
与 `com.apple.preference.universalaccess`。实现按**本机是否存在新面板扩展**决定尝试
顺序，并保留另一套标识作为兜底，避免在旧系统上打开一个不存在的面板。

验证：`tests/run-paper-tests.sh` 断言两种顺序与保留的锚点（如 `Seeing_Display`），并打印
本机探测结果 `hasModernPane=true hasModernAccessibilityPane=true`；不再有硬编码在视图
里的深链列表。

## 玻璃形状的容器协调（1.0.13 之后）

窗口浏览面板有两块相邻玻璃（面板背景 + 控制层）。它们现在都放进同一个公开
`NSGlassEffectContainerView`（`WindowBrowserGlassContainerHost`，`spacing = 8`）由系统
批量处理，而不是两个各自独立的玻璃视图；材质宿主在玻璃被容器接管后不再自行摆放，
容器缺失/系统不支持时仍走原来的纸面与原生材质回退。断言覆盖“容器存在且面板玻璃
确实位于容器宿主内”，以及不支持玻璃的环境不创建容器。

## 经典卷帘条的配色刷新（1.0.13 之后）

经典卷帘条的配色由“应用图标色调 × 当前外观”推出，原实现把结果存成 `let`，浅深色
切换后已折叠的卷帘条会停留在旧外观上。现在 `ClassicTitleStripView` 持有 pid 并提供
`refreshPalette()`，`viewDidChangeEffectiveAppearance` 与系统外观变化观察者都会调用
它重算配色。

验证（`--window-browser-shots`，生产视图渲染）：

- `classic-strip-palette PASS`：在浅色下创建 → 切到深色 → `refreshPalette()`，
  与“直接在深色下创建”的纸面/文字/控件颜色逐项一致（亮度差 < 0.02）。
- 样例图：`docs/visual-qa/system-appearance/classic-strip-{normal,contrast,dark}.png`
  分别对应普通、提高对比度与深色外观。

## 设置窗口截图与动态颜色（1.0.13 之后）

新增 `--settings-shots [输出目录]`：用生产设置窗口渲染每一页（浅色/深色），
不需要屏幕录制权限，结果写到 `.build/settings-shots/`（示例归档在
`docs/visual-qa/settings/`）。默认走 `CGWindowListCreateImage` 抓自己这扇窗，因此
系统侧栏材质（浅色 242 / 深色 45）也在图内；只有整窗截图拿不到结果时才退回
`cacheDisplay` 离屏渲染，那时侧栏区域会是透明块。效果页的 Metal 预览画布在两条
路径里都是以生产视图渲染的，需要交互录制时仍用 `--duo-design-preview`。

逐页外观巡检固化为 `bash scripts/check-settings-appearance.sh`：它跑一遍截图入口，
比较每页内容区的浅色/深色平均亮度（要求浅色 > 0.6、深色 < 0.5、差 ≥ 0.4），
并检查侧栏材质区域不透明（`meanAlpha > 0.95`，防止退回成透明块还当成“截图正常”），
结果写入 `.build/design-review/settings-appearance-check.txt`。当前五页实测
（整窗截图口径，效果页的白色部分是纸面预览画布本身）：

| 页面 | 浅色 | 深色 | 差 |
| --- | --- | --- | --- |
| 效果 | 0.964 | 0.414 | 0.550 |
| 卷帘 | 0.966 | 0.193 | 0.773 |
| 窗口浏览 | 0.949 | 0.202 | 0.748 |
| 权限与启动 | 0.986 | 0.190 | 0.796 |
| 高级 | 0.969 | 0.189 | 0.780 |
| 侧栏材质 alpha | — | — | 1.000 |

这条路径暴露并修掉了一个真实缺陷：设置页分组盒的填充色由
`NSColor.controlBackgroundColor.blended(...)` 得到，而 `blended` 返回**已解析的静态
颜色**，于是深色模式下卡片仍是浅色、配浅色文字几乎不可读（实测填充值在两种外观下
都是 0.965）。现在改用 `SystemAppearancePolicy.groupBoxFill()` 的动态颜色，在绘制时
按当前外观解析，不再依赖外观回调补救；`tests/run-paper-tests.sh` 断言浅色填充亮度
比深色高 0.3 以上。

## 系统外观对齐（1.0.13 之后）

全应用的材质、边线、薄纱与动画时长集中到 `prototype/Overlay/SystemAppearance.swift`
的一份策略里，卷帘条、悬停缩略图、置顶预览、代理标题栏、引导页背景与窗口浏览面板
都读同一份结果：

- **减少透明度**：这些表面改用不透明语义底色 + `withinWindow` 混合，并去掉内容
  薄纱；窗口浏览面板按同一规则退回纸面。
- **提高对比度**：细线从 0.5 pt 加粗到 1 pt、去掉装饰性顶边高光、纸面阴影加深，
  置顶预览的描边同步加粗。
- **减少动态效果**：新增过渡时长归零（置顶标题淡入、窗口浏览面板出现与消失）。
- **浅深色**：所有自定义表面用语义颜色并在 `effectiveAppearance` 变化时重画，不再
  把颜色一次性转成 CGColor 永久缓存。
- **系统开关变化时刷新已打开的表面**：`NSWorkspace.accessibilityDisplayOptionsDidChange`
  与 `NSApp.effectiveAppearance` 的 KVO 会刷新卷帘条、悬停缩略图、置顶预览与窗口
  浏览面板；只改材质/边线/阴影，不动窗口状态、不触发任何捕获。
- **系统颜色与强调色**：除了辅助功能开关与浅深色，还观察 `NSColor.systemColorsDidChangeNotification`，
  强调色/系统颜色变化时同样刷新自定义表面的语义颜色。
- **代理标题栏文字**改用系统 `labelColor`（深色、提高对比度、增强活力下由系统给值），
  悬停提示用 `secondaryLabelColor`，不再手调灰阶。
- **状态栏**：模板图标保持跟随菜单栏明暗与选中高亮；按钮新增 VoiceOver 名称与
  “没有折叠的窗口 / N 个折叠窗口”的值，临时提示期间读出提示内容。
- **悬停语言**：窗口浏览的卡片/列表行采用系统列表的弱强调悬停底色，配合右侧对齐的
  紧凑操作条与末尾“更多”入口；选中另由边线颜色与宽度区分。
- **可访问性**：截图卷帘条与经典卷帘条现在都有 VoiceOver 名称、帮助与“展开窗口”
  自定义动作；悬停缩略图与置顶预览只作为一个图像/分组播报窗口名，视频与命中层不再
  单独进入可访问性树；窗口浏览的动作结果只在真实操作结束后播报一句。
- 玻璃与材质的边界保持一致：只有真正的操作层（窗口浏览控制层）使用公开的
  `NSGlassEffectView`，内容与预览表面保持系统材质，不在窗口画面上再叠折射。

真实像素对照（`--window-browser-shots` 渲染生产视图，`docs/visual-qa/system-appearance/`）：

| 样例 | 说明 |
| --- | --- |
| `classic-strip-normal.png` | 经典卷帘条：0.5 pt 细线 + 顶边高光 |
| `classic-strip-contrast.png` | 同一视图注入“提高对比度”：1 pt 边线、无高光（与上图逐像素对比：3,098 个像素不同，最大亮度差 0.41） |
| `peek-preview.png` | 悬停缩略图注入“减少透明度”：不透明底 + `withinWindow` 混合，去掉内容薄纱 |

注入方式只影响绘制读取的外观读数（`ClassicTitleStripView.appearanceCapabilities`、
`applySystemAppearance(capabilities:)`），不改变系统设置本身。

## 与示意稿的语义对齐

标准卷帘的恢复交互原本需要双击，因此提示写作“**双击展开**”，没有照抄会误导操作的“点按展开”。真实窗口截图模式继续保留源应用的原貌；系统绘制的窗口标题和圆角跟随当前 macOS，而不覆盖系统内部视图。

## 开发验收入口

使用仓库构建脚本和已有开发签名构建，再运行（签名配置见 [开发指南](../DEVELOPMENT.md)）：

```sh
./prototype/build.sh --stage
.build/duo-validation/WindowShade.app/Contents/MacOS/WindowShade --duo-design-preview
```

该入口创建真实设置界面，但不启动传感器、全局事件监听、恢复扫描；效果参数不写入用户偏好。菜单提供浅色/深色、默认/最小/加宽尺寸、引导页、截图导出、阴影生命周期检查和纸面组件样例。截图使用 ScreenCaptureKit，只捕获当前预览窗口，输出到 `.build/design-review/`。

“组件状态：移入/移出”直接调用真实视图的跟踪事件处理器，供状态快照检查，不移动系统指针。样例的真实鼠标事件和跟踪范围记入 `.build/design-review/pointer-events.txt`。离屏回归命令 `bash tests/run-paper-tests.sh` 覆盖范围、显示/隐藏、标题点击穿透与缩放；不注入全局事件或操作用户窗口。

其他设置页的开关仍接生产动作，检查布局时不要随意更改登录项等实际设置。正常启动不进入此预览分支。

## 验证记录

2026-09-13：设计规范 v1 的实现、交付资料和验收完成。

- 50 个 Swift 文件完整编译、Apple Development 签名构建通过；验证包在 `.build/duo-validation/WindowShade.app`。原应用包未替换。
- `bash tests/run-duo-tests.sh` 通过：状态与恢复、帧元数据、捕获及集成边界、Metal 检查。`git diff --check` 通过。
- 真实 AppKit 界面已检查四分节、侧边栏键盘选择与折叠恢复、默认 900 × 680、最小 820 × 580 和加宽 1200 × 800。修正了标题遮挡、窗口被内容约束撑大及说明文字过窄的问题；效果页一次滚动可到达末尾。
- 最终构建于 00:59 完成。未指定验收尺寸时，窗口直接以 900 × 680 打开；实际把右下角拖向更小尺寸后，`windowDidEndLiveResize` 报告 820 × 580。修复了工具栏高度重复叠加造成的 600pt 下限，按实际工具栏高度换算最小尺寸。隔离预览也不再读写正式设置窗口的尺寸存档。
- 浅色/深色背景、引导页、待授权橙点和已授权绿勾已查看实际画面。README 使用 [浅色截图](../assets/windowshade-settings.png) 与 [深色截图](../assets/windowshade-settings-dark.png)，按阅读器主题切换。截图来自隔离预览，传感器显示未启动；窗口左上角紫色标志是 macOS 捕获指示。
- 阴影的真实窗口生命周期检查通过：父窗口几何不变、鼠标穿透、显隐、移动、缩放、透明度、层级和回收清理；本机报告在 `.build/design-review/shadow-check.txt`。
- 纸面事件验收发现并修复两处问题：标准标题栏窗口提前吞掉 `mouseExited`，以及 macOS 14 起默认不裁切视图导致 `inVisibleRect` 跟踪范围超出内容。现在退出事件继续交给 AppKit，纸面视图显式裁切到边界。
- `bash tests/run-paper-tests.sh` 通过：初始标题隐藏，移入显示，移出隐藏，可见标题不截获内容点击，缩放后视频与跟踪区域保持在内容边界内。实际窗口日志也确认标题区域点击到达内容回调。
- 通过真实组件状态入口查看了浅色/深色的提示与 HUD 标题，以及退出后无标题遮挡的画面。CUA 普通点击只产生移动/点击事件，未产生系统跟踪事件；因此这里采用组件事件测试与状态快照作为验收证据，没有把普通点击声称为物理鼠标悬停测试。

| 规范范围 | 实现与验收依据 |
| --- | --- |
| 原生分栏、四分节、标题栏 | `DuoSettingsWindow` 的 source list、split controller 与工具栏；真实键盘/折叠恢复检查 |
| 分组盒、文字层级与间距 | `SettingsGroupBox` 及共用行构建函数；四页/引导实际画面，40/48pt 行高和6/18pt间距约束 |
| 纸面预览与滑杆 | `artwork()` 的四横带和卷轴；静态 Metal 预览与独立进度行，README 明暗截图 |
| 浮动纸面、标题与缩略图 | 统一材质、10/6pt圆角、0.5pt边缘、1像素高光和共享阴影；组件状态检查、阴影生命周期检查 |
| 权限、引导与菜单 | 共用权限行，橙点/绿勾实测；菜单应用图标16pt、角度图标与等宽数字源码核对 |
| 过渡与原有交互 | 0.15s ease-out 与减少动态效果分支；折叠驱动和快捷键实现未改，核心回归通过 |
| 交付资料 | 中英文 README、明暗截图、本文与开发入口；签名验证包供本机检查 |

构建保留一条既有 `ScreenCaptureBridge.swift:104` 的 `stopCapture` 异步 API 建议警告。尚未提交、安装替换或发布。
