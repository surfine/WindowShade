# 窗口浏览面板细化设计稿（Claude，基于 1.0.14 复检）

> **落地状态（2026-09-19，未提交）**：§2–§11 已实现并有断言，见
> `docs/window-browser-progress.md` 同日条目。落地时的两处调整：列表选中行改用系统列表的
> 强调色实心底（非 key 时为非强调灰底）而不是描边环，网格卡片仍用描边环；缺少屏幕录制权限时
> 卡片只留应用图标，原因与“打开设置”入口只在页脚出现一次。玻璃路径的阴影经整窗截图核对未见重复，保持现状。实机检查结果见
> `docs/window-browser-visual-qa.md`。

适用范围：`prototype/WindowBrowser/` 的 Dock 悬停面板、键盘面板、大图预览（Space）与排布预览，
以及它们读取的 `prototype/Overlay/SystemAppearance.swift`。基线是 tag `v1.0.14` → `480a7fd`
（当前 `main` `a1a0a01` 只多了文档）。本文按 `docs/review-handoff.md` §7.1 的目录组织。

标注约定：
- **〔系统〕**：由 AppKit / 系统提供，不能也不应自定，只能选择用不用、用哪个变体；
- **〔项目〕**：项目参数，需实测校准；
- **〔未验证〕**：本文作者没有在实机上看到结果，只有代码、头文件或离屏截图依据。

依据只引用两类来源：Apple 官方文档（HIG *Materials*、*Accessibility*、*Buttons*、
*Adopting Liquid Glass*，取自 `developer.apple.com/tutorials/data/…json` 的原文）和本机
SDK（`MacOSX26.5.sdk` 的 AppKit 头文件）。复检中发现的缺陷编号（R1…）见本文末尾的对照，
正文只在需要时引用。

---

## 1. 目标与边界

面板只服务一件事：**在不改变源窗口的前提下，认出一个窗口并对它做一次动作**（激活、折叠/展开、
置顶预览、排布）。因此：

- 允许“有声有色”的只有**选中/悬停反馈**和**真实窗口画面**；其余表面交给系统材质与系统颜色。
- 面板本身是功能层（类比 popover），用 Liquid Glass；窗口画面、标题、状态是内容，不上玻璃。
- 面板里不出现第二层玻璃、不出现给卡片单独加的材质视图、不自绘模糊/渐变/高光。
- 受保护子系统（`WindowCatalog`、完整 `WindowKey`、事务式隐藏/恢复与恢复验证、
  `WindowMirrorSlot` 镜像租约）不在本稿修改范围内；本稿只改视图、材质、几何参数与时序。

---

## 2. 分层与材质

### 2.1 三层结构（玻璃路径，macOS 26+，跟随系统，未开减少透明度）

```
NSPanel (borderless, nonactivating, isOpaque=false, backgroundColor=.clear)
└─ contentView = NSGlassEffectView            ← 唯一一层玻璃〔系统〕
     style = .regular, tintColor = nil, cornerRadius = 13
     └─ contentView = WindowBrowserContentView  ← 页眉、搜索框、滚动区、详情、页脚全部在这里
          ├─ 页眉：应用图标 + 名称 + 窗口数 + 显示方式（系统 NSSegmentedControl）
          ├─ 搜索框（仅键盘面板，系统 NSSearchField）
          ├─ NSScrollView → NSCollectionView / NSTableView
          │    └─ 卡片 / 行：无材质视图，只用系统填充色（systemFill 系列）+ 选中环
          │         └─ 窗口画面：普通图层（CGImage / 实时视图），不叠任何效果
          ├─ 详情栏（列表模式、宽度足够时）
          └─ 页脚（仅有状态文字时）
```

要点与依据：

1. **把内容放进玻璃的 `contentView`**（修 R1 / 任务书 §11.2 / handoff §3-G1）。
   头文件原文：“`NSGlassEffectView` only guarantees the `contentView` will be placed inside the
   glass effect; arbitrary subviews aren't guaranteed specific behavior with regard to z-order”
   （`NSGlassEffectView.h`）。当前实现把玻璃包在 `WindowBrowserGlassBackdrop` 里作为内容的
   **兄弟视图**，`WindowBrowserMaterialView.contentHost` 从未被使用。
2. **玻璃不被父图层裁切**：删除 `WindowBrowserMaterialView.apply(kind:)` 对宿主
   `masksToBounds = true` 的设置；圆角只交给 `NSGlassEffectView.cornerRadius`〔系统〕。
3. **变体**：`.regular`〔系统〕。HIG *Materials*：“Use the regular variant … when components have
   a significant amount of text, such as alerts, sidebars, or popovers.” `clear` 只用于媒体背景，
   面板不用。
4. **不上色**：`tintColor = nil`。选中强调落在卡片的选中环上，不落在玻璃上。
5. **卡片不再用 `NSVisualEffectView`**（修 R2）。现状在玻璃面板里给每张卡片/行/详情加
   `NSVisualEffectView(.contentBackground, .withinWindow)`，从归档截图
   `docs/visual-qa/system-appearance/liquid-glass-panel.png` 看，它把卡片渲染成接近不透明的白块，
   面板只剩 12 pt 宽的玻璃边，这正是“不像液态玻璃”的直接原因。依据：
   - *Adopting Liquid Glass*：“Audit the backgrounds of sheets and popovers. Check whether you add
     a visual effect view to your popover's content view, and remove those custom background
     views…”
   - *Materials*：标准材质用来“convey a sense of structure in the content **beneath** Liquid
     Glass”，并要求“use vibrant colors on top of materials”。卡片是浮在玻璃**上面**的内容分组，
     用系统填充色（`NSColor.quinarySystemFillColor` 等，macOS 14+，头文件 `NSColor.h:270–276`）
     表达分组即可，不需要第二种材质。
6. **`NSGlassEffectContainerView` 不启用**：面板永远只有一个玻璃形状，容器没有合并对象。
   删除 `WindowBrowserGlassContainerHost` 与 `coordinateGlassBackdrops()`（现为死代码，且
   `spacing = 8` 与头文件建议的默认 0 不一致）。
7. **控制层不单独成面**：删除 `WindowBrowserControlSurface`。玻璃路径下它本来就是透明的；
   纸面路径下它画出一个跨满页眉、上沿被裁掉的描边圆角框（`states-without-image.png` 顶部可见，R14）。
   系统控件（分段控件、搜索框）自带外观〔系统〕，页眉文字直接放在面板底色上。
8. **阴影**：玻璃路径不安装 `PaperSurfaceStyle.installShadow`，改为 `panel.hasShadow = true`
   交给系统〔系统〕；纸面与旧系统路径保留现有纸面阴影。〔未验证〕玻璃自身是否已带投影、
   两者是否重复，需要用 §11 的整窗截图对比后再定；若系统阴影与玻璃边缘不贴合，退回现状。

### 2.2 回退路径（每条一个明确结果）

| 条件 | 面板表面 | 卡片/行 | 依据 / 说明 |
| --- | --- | --- | --- |
| macOS 26+，跟随系统 | `NSGlassEffectView(.regular)`，内容在 `contentView` | 系统填充色 + 选中环 | 见 §2.1 |
| 用户选“纸面” | 不透明 `windowBackgroundColor` + 0.5 pt（1 px）`separatorColor` 边线 | `controlBackgroundColor` + 1 px 细线 | 〔项目〕保留现状 |
| 开启**减少透明度** | 同“纸面” | 同“纸面” | 保留现状（已验证路径）。HIG 说玻璃会随该设置自行变化〔系统〕，是否改为“保留玻璃、交给系统变实”列为待决项，需实机对比后再改 |
| 开启**提高对比度** | 玻璃路径不变（系统自行加强）〔系统〕；纸面边线 1 pt `labelColor` | 静止态加 1 pt `separatorColor` 边；选中环 2.5 pt；悬停填充升一级 | HIG *Accessibility*：“ensure it at least provides a higher contrast color scheme when … Increase Contrast is turned on” |
| 开启**减少动态效果** | 所有时长为 0，不做位移/缩放；透明度切换即时 | 同左 | 保留现状 |
| macOS 14/15 或旧 SDK | `NSVisualEffectView(.popover, .behindWindow)`，**`state = .active`** | 系统填充色 + 选中环 | 修 R6：现状 `.followsWindowActiveState` 在永不成为 key 的 Dock 面板上恒为非激活外观；`SystemMaterialView` 已用 `.active`，两处统一。〔未验证〕14/15 实机 |

“玻璃”只在第一行出现；旧系统的模糊不称作 Liquid Glass（沿用 G8）。

---

## 3. 尺寸与几何

所有数值单位为 pt。公式里的 `P = panelPadding = 12`、`S = cardSpacing = 12`、`cw = 288`。

### 3.1 卡片（网格）

卡片自上而下：`8 内边距 | 画面区 144 | 8 | 标题 18 或 34 | 4 | 信息行 28 | 8 内边距`。

- **信息行**把现在的“状态行（13）+ 操作条（23）”两行合成一行：左侧状态符号 + 文字，右侧操作按钮
  （悬停/选中时出现）。这样没有状态的卡片不再留一条空带（`dock-three.png` 里未选中卡片标题下的
  空白），操作条出现时也不挤动标题。状态文字与按钮重叠时，状态文字先截断。
- **卡片高度**：单行标题 `8+144+8+18+4+28+8 = 218`（与现状相同）；两行标题 234。
- **画面区** 272 × 144。窗口画面按比例缩放后**以实际画面矩形**居中放置，圆角与细线落在画面矩形上，
  而不是 272×144 的外框上（现状外框有 0.5 pt 边线和 `windowBackgroundColor` 底，横向留白处看起来像
  “画框里的画”，见 `liquid-glass-panel.png`）。无画面时占位层填满外框。

### 3.2 面板

| 场景 | 列数 | 面板尺寸（无页脚） | 有页脚 | 备注 |
| --- | --- | --- | --- | --- |
| 单窗口，底部 Dock | 1 | **312 × 274** | 312 × 288 | 宽 = cw + 2P；高 = 40 + 4 + 218 + 12 |
| 2 窗口，底部 Dock | 2 | 612 × 274 | 612 × 288 | 宽 = 2cw + S + 2P |
| **3 窗口，底部 Dock** | **3** | **912 × 274** | 912 × 288 | 〔项目〕现状是 2 列 2 行 612 × 504，第二行只有一张卡；改为优先单行 |
| 4 窗口，底部 Dock | 2 | 612 × 504 | 612 × 518 | 2×2 比 3+1 整齐 |
| 5–6 窗口，底部 Dock | 3 | 912 × 504 | 912 × 518 | |
| ≥7 窗口或纵向放不下 | 列表 | 宽 ≤ 544（列表自然宽 520 + 2P） | | 保持现状（`autoListThreshold = 6`） |
| 左/右 Dock | ≤2 | 2 窗口 612 × 274；3–4 窗口 612 × 504 | | 保持现状上限 |
| 键盘面板 | 网格 ≤3 / 列表 | **800 × 560**，受可见区域 − 2×12 约束 | | 保持现状 |

- 有页脚时页脚 18 + 间隔 8 取代底部 12 pt 内边距，面板 +14；现状为 +15（页脚 19）。页脚高度改为 `detailLine + 5 = 18`。
- 列数规则（`WindowBrowserGeometry.gridColumns` 的 `preferred`）：底部 Dock
  `count ≤ 3 → count；count == 4 → 2；count ≥ 5 → 3`；侧边 Dock 仍以 `sideDockMaximumColumns = 2`
  封顶；宽度放不下时仍按宽度退列。〔项目〕
- `WindowBrowserGeometry.contentPlan` 调 `gridColumns` 时要传入与 `layoutPlan` 相同的列数上限
  （现状 `contentPlan` 不传 `maximumColumns`，侧边 Dock 只是碰巧因宽度退到 2 列）。
- 冷启动与数据补全：沿用现状（首帧小面板、首次完整数据允许一次尺寸调整、缩略图到达不改尺寸）。
  尺寸动画见 §9。

### 3.3 列表行与键盘面板

- **列表**：`NSTableView.style = .plain`，`intercellSpacing = (0, 4)`，
  `selectionHighlightStyle = .none`（修 R4）。实测：未设 style 时 `effectiveStyle == .inset`，
  500 pt 宽的列会生成 x = 16、宽 532 的行，行间距为 0（几何按 4 计算），因此归档图里行的右侧
  圆角与“更多”按钮被裁掉，左侧还多出系统选中灰块。
- **行**：高 52，圆角 8，左右内边距 10；图标 20 × 20，垂直居中；文字起点 x = 38；标题一行；
  有状态时标题 + 状态两行整体垂直居中，**无状态时标题单独垂直居中**（现状标题固定在上半部，R13）；
  右侧操作区宽 `3×28 + 2×4 = 92`，距行右缘 8。
- **键盘面板纵向**：页眉 40 → 间隔 8 → 搜索框（`NSSearchField` 常规尺寸的 `intrinsicContentSize`
  高度，SDK 26.5 下约 28〔未验证〕）→ 间隔 8 → 列表/网格 → （页脚 8 + 18）→ 底部内边距 12。
- **详情栏**：宽 `clamp(floor((内容宽 + 12) × 0.3), 200, 260)`；800 宽面板下为 236，列表宽 528。
  详情栏内部自上而下：画面（宽 = 栏宽 − 20，按画面比例，最高为栏高的 55%）→ 8 → 标题（最多两行）
  → 4 → 状态。现状画面贴在栏底、标题与画面之间留一大段空白（`keyboard-list-eight.png`）。

### 3.4 安全区与滚动

沿用现状：面板 frame 限定在屏幕 `visibleFrame` 内缩 12 的区域；网格纵向放不下改列表；列表超出后滚动。
面板与图标间距 `panelGap = 10`；过渡走廊容差 10。

---

## 4. 间距、圆角与边线

### 4.1 间距

基础序列 4 / 8 / 12 / 16 / 24 不变。面板内边距 12、卡片间距 12、卡片内边距 8 不变；
操作按钮之间 2 → **4**（HIG *Accessibility*：“Consider spacing between controls as important as
size”；无边框按钮建议的约 24 pt 留白在 28 pt 高的信息行里做不到，取 4 作为密度与误触的折中，〔项目〕）。

### 4.2 圆角

| 层级 | 现状 | 建议 | 说明 |
| --- | --- | --- | --- |
| 面板（玻璃 / 纸面） | 13 | 13 | `SystemCornerRadius.window`。现状依据是实测 Finder/ChatGPT 的**窗口**圆角；Dock 面板更接近 popover，popover/菜单的实际圆角本稿未测〔未验证〕，先沿用 13 |
| 卡片、列表行、详情栏 | 12 | **8** | 现状违反仓库自己引用的同心规则：卡片距面板边 12，按“外 − 间距”应为 13 − 12 = 1，12 与 13 几乎相等，内角显得比外角还圆。1 pt 不可用，取介于面板 13 与控件 6 之间、与外层至少差 5 的 8〔项目〕 |
| 画面 | `max(4, 12 − 8) = 4` | `max(4, 8 − 8) = 4` | 数值不变，公式随卡片走 |
| 控件（操作按钮悬停底、chip） | 6 | 6 | `SystemCornerRadius.control` |
| 大图预览面板 / 画面 | 13 / `max(4, 13 − 12)` | 不变 | |
| 排布预览轮廓 | 13（但用正圆 `CGPath(roundedRect:)`） | 13，**连续曲率**：`SystemCornerPath.cgPath` | 修 R9 |

所有图层圆角保持 `.continuous`。备选：若视觉评审认为 8 太方，卡片可取 10（画面仍为 4）；
不建议保留 12。

### 4.3 边线

- 保留：纸面面板外框（1 px `separatorColor`，提高对比度 1 pt `labelColor`）；纸面卡片 1 px；
  选中环；画面在纸面路径上的 1 px 细线（画面本身常为白底，需要边界）。
- 删除：玻璃路径的卡片静止边线（玻璃上用填充表达分组）；画面外框的 0.5 pt 边线与
  `windowBackgroundColor` 底（改为画在实际画面矩形上，且只在纸面路径）；控制层描边框（随 §2.1-7 删除）。
- 1x/2x：细线一律用 `WindowBrowserSurfaceStyle.hairlineWidth(for:)`（1 / backingScale），
  现状多处直接写 0.5，在 1x 屏会被抗锯齿成灰线〔未验证：本机无 1x 屏〕。

---

## 5. 排版与图标

| 用途 | 字体 | 行高 | 截断 |
| --- | --- | --- | --- |
| 页眉应用名 | 正文字号 semibold（默认 13） | `lineHeight(font)` | 尾部截断 + tooltip |
| 页眉窗口数、状态、页脚 | 正文 − 2（默认 11），**下限 10** | 同上 | 尾部截断 |
| 卡片标题 | 正文 medium | 1 行 18 / 2 行 34 | 最多两行，末行尾部截断 + tooltip |
| 列表标题 | 正文 medium | 18 | 一行尾部截断 + tooltip + AX 标签 |

- 次级字号下限由 9 改为 **10**（`WindowBrowserTypography.detailSize`、
  `SystemAppearancePolicy.fontSize(relativeToBody:)`）。HIG *Accessibility* 表格：macOS
  默认 13 pt、最小 10 pt。
- 页眉里写死的高度（名称 16、窗口数 14、分段控件 84 × 26、控件区 96/200）改为从
  `WindowBrowserTypography.lineHeight(_:)` 与控件 `intrinsicContentSize` 派生（R12）。
- SF Symbols：状态符号与操作符号 point size = 次级字号，weight `.regular`，
  `NSImage.SymbolConfiguration(pointSize:weight:scale: .medium)`；符号与文字首行基线对齐。
  沿用现有符号名（`WindowBrowserActionPresentation`、`WindowPlacementAction`）。
- 大字号降级顺序（沿用 E9）：先让文本长高 → 减列数 → 隐藏详情栏 → 滚动。

---

## 6. 状态矩阵

记号：`fill(q)` = `quaternarySystemFillColor`，`fill(t)` = `tertiarySystemFillColor`，
`fill(s)` = `secondarySystemFillColor`，`fill(5)` = `quinarySystemFillColor`；
`ring` = 2 pt `controlAccentColor` 描边（提高对比度 2.5 pt），画在卡片边界内侧。
所有颜色经 `SystemAppearancePolicy.cgColor(_:for:)` 在视图自己的外观下解析。

### 6.1 卡片（网格）

| 状态 | 玻璃路径 | 纸面 / 旧系统 | 操作按钮 | 文案 / 符号 |
| --- | --- | --- | --- | --- |
| 默认 | `fill(5)` | `controlBackgroundColor` + 1 px 细线 | 隐藏（位置保留） | 标题；有状态时显示状态 |
| 悬停 | `fill(q)` | 底色混入 7% `labelColor`（沿用） | 显示 | 不改变源窗口 |
| 键盘选中 | `fill(q)` + `ring` | 同左 + `ring` | 显示 | VO 焦点跟随 |
| 按下（鼠标在内按住） | `fill(t)` | 底色混入 14% | 显示 | 拖出后回到悬停/默认，不提交 |
| 禁用（动作不可用） | 同默认 | 同默认 | 对应按钮 `isEnabled = false`，tooltip 与 AX 帮助写原因 | 卡片本身仍可激活 |
| 忙碌（动作执行中） | 同当前态 | 同当前态 | 被执行的按钮换成 `NSProgressIndicator`（small，spinning），其余按钮禁用 | 状态：“正在展开”等 |
| 失败 | 同当前态 | 同当前态 | 恢复 | 状态行 `exclamationmark.triangle` + 原因，`systemOrange`；只有真实失败与权限缺失用警告色 |
| 无画面 | 画面区 `fill(q)`，中心应用图标 32 + 一行原因 | 画面区 `windowBackgroundColor` | 同默认 | 原因短句，见 §10 |

Dock 面板不能成为 key window，**不显示键盘选中环**；“当前项”由悬停决定，用于缩略图升档与实时预览
挂载（现状单窗口 Dock 面板恒显示蓝色选中环，见 `liquid-glass-panel.png`）。〔项目〕

### 6.2 列表行

与卡片相同的底色与环；差异：默认态玻璃路径不加 `fill(5)`（行之间靠 4 pt 间隔分组）；
失败/无画面只体现在状态行与详情栏，不在行内放占位图。

### 6.3 操作条按钮（28 × 28 命中区）

| 状态 | 表现 |
| --- | --- |
| 默认 | 符号 `secondaryLabelColor`，无底 |
| 悬停 | 6 pt 圆角 `fill(q)` 底，符号 `labelColor` |
| 按下 | `fill(t)` 底 |
| 开启态（已置顶、已折叠对应的“取消”动作） | 符号 `controlAccentColor` |
| 危险（仅菜单里的关闭窗口） | 菜单项红色文字；操作条上不出现 |
| 禁用 | 系统禁用外观，tooltip“动作名（原因）” |
| 忙碌 | 见 6.1 |

### 6.4 搜索框、页脚、详情、大图预览

| 组件 | 默认 | 焦点/输入 | 无结果 | 失败/缺权限 |
| --- | --- | --- | --- | --- |
| 搜索框〔系统〕 | 占位“搜索应用名或窗口标题” | 系统焦点环；输入法 marked text 优先 | 列表区中央：“没有匹配的窗口”（次级字号，`secondaryLabelColor`），页脚“搜索：xx（0 个结果）” | — |
| 页脚 | 不占位 | — | 见上 | 一行说明，结果性状态读屏播报一次（沿用） |
| 详情栏 | 当前项画面 + 标题 + 状态 | — | 隐藏 | 画面位换成图标 + 原因 |
| 大图预览 | 画面 + 标题 + 来源说明 | — | — | 图标 + 原因；过期画面标“快照（画面可能已过期）”（沿用） |

---

## 7. 交互与时序

| 环节 | 规格 | 落点 |
| --- | --- | --- |
| 首次悬停 → 出现 | 意图延迟 250 ms；指针离开上下文后 180 ms 隐藏；同应用锚点变化只挪位置 | `showDelay`、`hideDelay`（不变） |
| 已打开时切到另一图标 | 立即换内容与位置，不重付延迟 | 不变 |
| 网格 ↔ 列表 | 立即切换；只迁移实时视图，不新开流 | 不变 |
| 方向键 | 按真实列数移动 | 不变 |
| **PageUp / PageDown** | 按“视口可见行数 − 1”移动选择；网格按行计 | **新增**（R5：keyCode 116/121 现未处理） |
| Home / End | 首项 / 末项 | 不变 |
| Return | 激活当前项 | 不变 |
| Escape | 大图 → 排布预览 → 清空搜索 → 关面板 | 不变 |
| Tab / Shift-Tab | 搜索框 ↔ 列表/网格 ↔ 显示方式控件；设置 `nextKeyView` 明确键视图循环 | **新增**（现依赖 AppKit 自动计算，未测） |
| ⌘F | 聚焦搜索 | 不变 |
| Space | 大图预览（只读） | 不变 |
| 焦点归还 | 取消时仅在仍持有焦点时归还给打开前的应用；成功激活后焦点留在目标 | 不变 |
| 悬停反馈（Dock 面板） | 跟踪区域选项改为 `.activeAlways`（面板不会成为 key） | **修 R3**：现为 `.activeInKeyWindow`，Dock 面板里 `mouseEntered` 不会发生 |
| 排布预览 | 显示后 2.0 s 自动消失，计时器绑定本次预览的令牌；消失时同时清掉页脚“预览：…” | **修 R9**：现 1.6 s 计时器会取消之后发起的另一次预览，页脚文字残留 |

---

## 8. 可访问性

- **朗读顺序**：面板名（“窗口浏览” / “窗口选择”）→ 页眉（应用名，窗口数）→ 搜索框 →
  列表/网格（行优先）→ 详情 → 页脚。
- **卡片/行**：role `group`；label “应用名，标题[，状态]”；value = 状态；help = “激活或展开这个
  窗口；菜单命令可访问全部操作”；自定义动作 = 能力模型里启用的动作（沿用）。
  操作按钮各自有 label；禁用时 help 写原因（沿用）。
- **目标尺寸**：操作按钮命中区 **28 × 28**（HIG *Accessibility* 表：macOS 默认 28 × 28、最小 20 × 20；
  现状约 28 × 23，R16）。
- **对比度**：文字只用 `labelColor` / `secondaryLabelColor`（系统颜色随材质与对比度设置调整）；
  HIG 要求至少 4.5:1，提高对比度时必须有更高对比方案 —— 由 §2.2 的对比度行满足。
  玻璃上文字的实际对比度〔未验证〕，需按 §11 用 Accessibility Inspector 在浅/深/彩色壁纸下测。
- **不只靠颜色**：选中 = 描边环（形状）+ 填充；失败 = 符号 + 文字 + 颜色。
- **播报**：只播报结果性状态，一次；列表刷新、缩略图到达不播报（沿用）。

---

## 9. 动效

| 事件 | 时长 | 曲线 | 属性 | 减少动态效果 | 状态 |
| --- | --- | --- | --- | --- | --- |
| 面板出现 | 160 ms | easeOut | alpha 0→1 | 0 ms | 已实现（仅 Dock 面板；键盘面板建议同样淡入） |
| 面板消失 | 110 ms | easeIn | alpha 1→0 | 0 ms | 已实现 |
| 选中/悬停底色与环 | 100 ms | easeInEaseOut | `backgroundColor`、`borderColor`、`borderWidth` 的隐式图层动画 | 0 ms | **未实现**（`selectionDuration` 现在只用于面板尺寸动画） |
| 首图替换 | 80 ms | linear | `CATransition(type: .fade)` 加在画面图层 | 0 ms | **未实现**（`firstImageDuration` 从未被读取） |
| 面板尺寸变化（页脚出现/消失、首次数据补全） | 120 ms | easeInEaseOut | window frame | 0 ms | 现为 100 ms（借用 `selectionDuration`），发布说明写 120 ms；新增 `panelResizeDuration = 0.12` |
| 实时预览挂载 | 0 | — | — | — | 不做过渡 |

60/120 Hz：全部由 Core Animation 驱动，不跑自定义显示循环；120 Hz 下期望同样时长、更多帧〔未验证〕。

---

## 10. 边界场景

| 场景 | 卡片画面区 | 状态行 | 页脚 |
| --- | --- | --- | --- |
| 缺屏幕录制权限 | 应用图标 + “需要屏幕录制权限” | — | 一次：“没有屏幕录制权限，只显示图标与标题 · 在设置中开启…”（带按钮，走现有权限页面） |
| 折叠且屏外 | 已保存折叠快照，标“快照” | `rectangle.compress.vertical`“已折叠”（中性色） | — |
| 最小化 | 最后快照或图标 + “已最小化，无最新画面” | “已最小化” | — |
| 应用隐藏 | 同上，“应用已隐藏” | “应用已隐藏” | — |
| 截图失败 | 保留合法旧图；没有则图标 + “画面暂不可用” | 失败原因（警告色） | — |
| 操作失败 | 不变 | 失败原因，3 s 后恢复原状态 | 结果播报一次 |
| 搜索无结果 | — | — | 见 §6.4 |
| 同名窗口 | 标题后加“· 序号”（沿用） | — | — |
| 超长标题 / 路径 | 两行末行截断（卡片）/ 一行截断（行），tooltip 全文 | — | — |
| 极窄屏 | 按 §3.2 退列、改列表、滚动 | — | — |
| 多显示器 / 负坐标 / 1x | 纯几何（沿用断言）；细线按 backing scale | — | 〔未验证〕实机 |

画面区的原因文案删掉“显示应用图标和标题”这类描述界面本身的后半句（现状每张卡都重复一遍，
`states-without-image.png`），权限缺失只在页脚说一次。

---

## 11. 落地映射（参数表）

| # | 项 | 当前值 | 建议值 | 依据 | 落点 |
| --- | --- | --- | --- | --- | --- |
| 1 | 玻璃挂载 | 兄弟视图 `WindowBrowserGlassBackdrop` | `NSGlassEffectView.contentView = WindowBrowserContentView` | 头文件 `NSGlassEffectView.h`；任务书 §11.2 | `WindowBrowserMaterial.swift`（重写 `WindowBrowserMaterialView` 为面板根视图）、`WindowBrowserPanel.swift:50` |
| 2 | 玻璃变体 / 着色 | `.regular` / nil | 不变〔系统〕 | HIG *Materials* | `WindowBrowserMaterial.swift:115` |
| 3 | 宿主裁切 | `masksToBounds = true` | 不裁切 | 玻璃边缘由系统绘制 | `WindowBrowserMaterial.swift:185` |
| 4 | 卡片材质 | `NSVisualEffectView(.contentBackground)` | 删除；用 systemFill 系列 | *Adopting Liquid Glass*（popover 背景审计） | `WindowBrowserViews.swift:79–94, 142–147`；三处 `cardBackdrop` |
| 5 | 控制层表面 | `WindowBrowserControlSurface` | 删除 | §2.1-7 | `WindowBrowserMaterial.swift:274–377`、`WindowBrowserViews.swift:1185, 1784–1788` |
| 6 | 玻璃容器 | 条件创建（恒不触发） | 删除 | 单一玻璃形状 | `WindowBrowserMaterial.swift:239–272`、`WindowBrowserViews.swift:1427–1459` |
| 7 | 旧系统材质状态 | `.followsWindowActiveState` | `.active` | Dock 面板不会成为 key | `WindowBrowserMaterial.swift:203` |
| 8 | 面板圆角 | 13 | 13〔未验证 popover 实测〕 | 现有实测 | `SystemCornerRadius.window` |
| 9 | 卡片/行/详情圆角 | 12 | **8**〔项目〕 | 同心规则（仓库自引） | `SystemCornerRadius.card` 或 `WindowBrowserLayoutParams.cardCornerRadius`（设置页分组盒仍用 12，拆成两个常量） |
| 10 | 画面圆角 | 4 | 4 | `concentric(8, 8)` 下限 | `WindowBrowserLayoutParams.make` |
| 11 | 画面区高度 | 120（无状态吸收到 141） | **144** 固定 | 与信息行合并后的整数布局 | `imageMaxHeight`、`cardImageHeight` |
| 12 | 状态行 + 操作条 | 13 + 8 + 23 | **信息行 28** | §3.1 | `cardStatusHeight`、`actionBarHeight` → 新增 `cardMetaRowHeight = 28` |
| 13 | 操作按钮命中区 | ≈ 28 × 23，间距 2 | **28 × 28**，间距 4 | HIG *Accessibility* 28×28 默认 | `buttonHitHeight`、`WindowBrowserActionBar.layout()` |
| 14 | 三窗口列数（底部 Dock） | 2 | **3**〔项目〕 | §3.2 | `WindowBrowserGeometry.gridColumns` 的 `preferred` |
| 15 | 页脚高度 | 19 | 18 | `detailLine + 5` | `WindowBrowserLayoutParams.make`（`footerHeight`） |
| 16 | 键盘面板：页眉→搜索间距 | 12 | 8 | 4/8 序列 | `searchFieldBottomGap` |
| 17 | 搜索框高度 | 26（写死） | `intrinsicContentSize.height` | 系统控件尺寸〔系统〕 | `searchFieldHeight` 改为运行时取值 |
| 18 | 列表样式 | 未设（effective `.inset`） | `.plain`，`intercellSpacing (0,4)`，`selectionHighlightStyle .none` | 实测 inset 行宽溢出 | `WindowBrowserViews.swift:1270–1281` |
| 19 | 行圆角 / 图标 | 12 / 18 | 8 / 20 | §3.3 | `cardCornerRadius`、`iconSize` |
| 20 | 次级字号下限 | 9 | 10 | HIG macOS 最小 10 pt | `WindowBrowserTypography.swift:13`、`SystemAppearance.swift:121` |
| 21 | 跟踪区域 | `.activeInKeyWindow` | `.activeAlways` | Dock 面板 `canBecomeKey == false` | `WindowBrowserViews.swift:558, 799` |
| 22 | 选中/悬停动画 | 无 | 100 ms | 任务书 §12 | 新增，读 `selectionDuration` |
| 23 | 首图淡入 | 无 | 80 ms | 任务书 §12 | 新增，读 `firstImageDuration` |
| 24 | 面板尺寸动画 | 100 ms | 120 ms | 与发布说明一致 | 新增 `panelResizeDuration` |
| 25 | PageUp/PageDown | 无 | 按视口行数翻页 | 任务书 §13 / F26 | `WindowBrowserViews.swift` `keyDown`、`WindowBrowserMoveDirection` |
| 26 | 排布预览描边 | 2 pt 居中于边界（外半被裁）、正圆路径、`cgColor` 在 init 冻结 | 路径内缩 1 pt、`SystemCornerPath.cgPath`、`viewDidChangeEffectiveAppearance` 刷新；10% 强调色填充〔项目〕 | F14、连续曲率约定 | `WindowPlacement.swift:362–384` |
| 27 | 排布预览时长 | 1.6 s，不校验令牌 | 2.0 s，令牌校验，同时清页脚 | §7 | `WindowBrowserController.swift:1741–1745` |
| 28 | 玻璃路径阴影 | 纸面子窗口阴影 | `hasShadow = true`〔未验证〕 | §2.1-8 | `WindowBrowserPanel.swift:54` |
| 29 | Dock 面板选中环 | 始终显示首项选中 | 不显示；当前项 = 悬停项 | §6.1 | `WindowBrowserController.refreshPanel`（Dock 分支）与 `applySelectionStyling` |

受保护子系统没有任何一行落在上表中。

---

## 12. 线框（尺寸单位 pt）

### 12.1 单窗口 Dock 面板（底部 Dock）—— 312 × 274

```
x: 0  12                                                300 312
   ┌───────────────────────────────────────────────────────┐ y=0      ← NSGlassEffectView（r=13）
   │  [■20] Safari                         [▦│☰] ← 仅 ≥2 窗口显示   │
   │        1 个窗口                                         │ y=40     页眉 40
   │ ┌───────────────────────────────────────────────────┐ │ y=44     卡片 288×218（r=8，fill(5)）
   │ │ ┌───────────────────────────────────────────────┐ │ │ y=52
   │ │ │        ┌───────────────────────────┐          │ │ │          画面区 272×144
   │ │ │        │  窗口画面（按比例，r=4）   │          │ │ │          画面矩形居中，
   │ │ │        └───────────────────────────┘          │ │ │          圆角落在画面上
   │ │ └───────────────────────────────────────────────┘ │ │ y=196
   │ │  Safari — OpenAI                                  │ │ y=204–222 标题 1 行
   │ │  (状态符号 状态文字)            [⇕][📌][…] 28×28  │ │ y=226–254 信息行 28
   │ └───────────────────────────────────────────────────┘ │ y=262
   │                                                       │ 底部内边距 12
   └───────────────────────────────────────────────────────┘ y=274
                          ▲ panelGap 10
                        [Dock 图标]
```

有状态文字（如“正在刷新窗口…”）时底部 12 pt 内边距换成 8 + 18 页脚 → 312 × 288。

### 12.2 三窗口 Dock 面板（底部 Dock）—— 912 × 274

```
x: 0 12        300 312       600 612       900 912
   ┌─────────────────────────────────────────────┐ y=0
   │ [■] Safari  3 个窗口                  [▦│☰]  │ y=40
   │ ┌──────────┐ ┌──────────┐ ┌──────────┐      │ y=44
   │ │ 画面 272 │ │ 画面     │ │ 画面     │      │ 卡片 288×218，间距 12
   │ │   ×144   │ │          │ │          │      │
   │ │ 标题     │ │ 标题     │ │ 标题     │      │
   │ │ 状态  ⋯  │ │  (悬停:  │ │          │      │ 悬停卡：fill(q) + 操作按钮
   │ └──────────┘ └──fill(q)─┘ └──────────┘      │ y=262
   └─────────────────────────────────────────────┘ y=274
```

窄屏（可用宽 < 936）时按宽度退为 2 列 → 612 × 504；左/右 Dock 恒为 ≤2 列 → 612 × 504。

### 12.3 键盘面板：列表 + 搜索 —— 800 × 560

```
x: 0 12                                    540 552                788 800
   ┌─────────────────────────────────────────────────────────────────┐ y=0
   │ 窗口选择                                             [▦│☰]     │ y=40   页眉（无图标时标题从 x=12 起）
   │ ┌─────────────────────────────────────────────────────────────┐ │ y=48
   │ │ 🔍 Safari                                               ⓧ │ │ y≈76   NSSearchField（固有高度）
   │ └─────────────────────────────────────────────────────────────┘ │
   │ ┌──────────────────────────────────────┐ ┌────────────────────┐ │ y=84
   │ │[■] Safari — OpenAI        [⇕][📌][…]│ │ ┌────────────────┐ │ │ 行 528×52，r=8
   │ │    ring + fill(q)                    │ │ │ 画面 216×≤135  │ │ │ 选中行
   │ ├ 4 ───────────────────────────────────┤ │ └────────────────┘ │ │ 详情栏 236 宽
   │ │[■] Safari — 文档草稿                 │ │ Safari — OpenAI    │ │ 画面在上，标题、状态在下
   │ ├──────────────────────────────────────┤ │ (状态)             │ │
   │ │[■] 终端 — 恢复中                     │ │                    │ │
   │ │    ⟳ 正在展开                        │ │                    │ │
   │ │   …（滚动）                          │ │                    │ │
   │ └──────────────────────────────────────┘ └────────────────────┘ │ y=522
   │ 搜索：Safari（6 个结果）                                         │ y=530–548 页脚
   └─────────────────────────────────────────────────────────────────┘ y=560
```

无页脚时列表底边到 y = 548。列表区高 438（有页脚）/ 464（无页脚），可见约 7.8 / 8.3 行。
搜索无结果：列表区中央一行“没有匹配的窗口”。

### 12.4 排布预览（以 1440 × 900 屏、左半屏为例）

```
┌──────────────────── 屏幕 visibleFrame（菜单栏与 Dock 已扣除） ────────────────────┐
│╭─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─╮                                                        │
│┊  强调色 10% 填充            ┊   目标 frame = visibleFrame 左半（例：720 × 835）      │
│┊  2 pt 虚线描边（6/4）       ┊   描边路径内缩 1 pt，r=13 连续曲率                     │
│┊  点击穿透、不激活            ┊   窗口本身不动                                        │
│┊                             ┊                                                        │
│╰─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─╯        ┌ 键盘面板 ──────────────┐                        │
│                                       │ …                      │                        │
│                                       │ 页脚：预览：左半屏      │                        │
│                                       │ （不移动窗口）          │                        │
│                                       └────────────────────────┘                        │
└──────────────────────────────────────────────────────────────────────────────────────┘
```

2.0 s 后自动消失（令牌校验）；Escape 立即取消；再发起另一次预览时先撤掉上一次；减少动态效果下
出现/消失无淡入淡出。

---

## 13. 与现状的差异与影响

### 保留

单层 `.regular` 玻璃不上色；纸面与减少透明度回退；面板 13 pt 圆角；间距序列与面板/卡片内边距；
单窗口 312 × 274；键盘面板 800 × 560；意图延迟、出现/消失时长；Escape 分层；Space 大图；
能力模型与可访问性动作；受保护子系统全部不动。

### 修改

| 改动 | 影响面 | 需更新的断言 / 截图 / 文档 |
| --- | --- | --- |
| 玻璃改为面板根视图 + `contentView` | `WindowBrowserMaterialView`、`WindowBrowserPanel`、`WindowBrowserContentView.materialHost` 及诊断属性 | `tests/WindowBrowserTests.swift:2400–2461`（“panel glass hangs directly in the material host”“control layer never adds a second glass”等改为“内容视图是玻璃的 contentView”）；`system-glass-*.png`、`liquid-glass-panel.png` 重拍 |
| 删除卡片材质、控制层表面、玻璃容器 | 三个视图类、`adoptCardSurface` 协议 | 同上一组断言；`adoptedCardSurfaceForDiagnostics` 相关断言删除 |
| 卡片信息行合并、画面 144、圆角 8 | `WindowBrowserCardView.layout()`、`WindowBrowserLayoutParams.make` | 卡片高度、画面框、圆角同心断言；`dock-*.png`、`states-without-image.png`、`paper-*.png` 重拍 |
| 列表 `.plain` + 行布局 | `WindowBrowserContentView` 初始化、`WindowBrowserListRowView.layout()` | 新增“行宽 == 列表宽、行间距 == 4”断言；`keyboard-*.png`、`dock-list-many.png` 重拍 |
| 3 窗口 3 列 | `gridColumns` | `docs/window-browser-visual-qa.md` 与 handoff §7.3 的“三窗口 612 × 519” |
| 跟踪区域、Dock 选中环 | 卡片、行、控制器 Dock 分支 | `tests/WindowBrowserTests.swift:1231–1245` 目前直接调用 `mouseEntered`，需增加对跟踪区域选项的断言 |
| 旧系统材质 `.active` | `WindowBrowserMaterialView` | 材质回退断言 |
| 次级字号下限 10 | 全应用字号 | `tests/run-paper-tests.sh` 的字号断言（若断言了 9） |
| 排布预览 | `WindowPlacementPreviewWindow`、控制器计时器 | 新增“后一预览不被前一计时器取消”断言 |

### 新增

PageUp/PageDown；明确的 Tab 键视图循环；选中 100 ms / 首图 80 ms / 尺寸 120 ms 动画；
操作按钮忙碌态进度指示；搜索无结果空态；缺权限页脚里的“在设置中开启…”按钮。

### 文档同步

`docs/window-browser-polish.md`“材质与回退”表与容器段落、`docs/design-v1.md`“玻璃形状的容器协调”
与“系统外观对齐”两节、`SystemAppearance.swift` 文件头注释、`visual-qa/window-browser/manifest.txt`
里“控制层为真实 AppKit 玻璃”的描述，均需改为“面板根视图是唯一玻璃，内容在其 contentView”。

---

## 14. 明确不做

与 handoff §7.4 一致，另加本稿自身的边界：

- 不自造 Liquid Glass：不加自定义模糊、渐变、高光、折射，不用私有 API / KVC / 动态 selector。
- 不在内容层放玻璃：卡片、行、画面、详情栏、大图预览都不用 `NSGlassEffectView`；
  操作按钮不用 `NSButton.BezelStyle.glass`（它在玻璃面板里会形成玻璃叠玻璃）。
- 不给玻璃上色；不用 `clear` 变体。
- 不在画面上叠任何材质或薄纱。
- 不启用 `NSScrollEdgeEffectStyle`：该类型（macOS 26.1）只通过标题栏 / 分栏附属视图控制器生效，
  面板里没有对应宿主；列表也不与页眉重叠。
- 不改动 `WindowCatalog`、完整 `WindowKey`、事务式隐藏/恢复与恢复验证、`WindowMirrorSlot` 镜像租约，
  不引入另一套隐藏/恢复系统。
- 不把 §11 中标〔未验证〕的项写成已完成；本稿不替代实机验收。

---

## 附：本稿引用的复检编号

R1 玻璃 contentView 未落实 · R2 玻璃面板里的卡片材质 · R3 Dock 面板悬停跟踪不触发 ·
R4 列表 `.inset` 样式溢出与重复选中 · R5 PageUp/PageDown 缺失 · R6 旧系统材质非激活态 ·
R9 排布预览描边与计时器 · R12 页眉写死尺寸 · R13 行/详情排版 · R14 控制层描边框 ·
R16 操作按钮高度。完整清单见复检报告。
