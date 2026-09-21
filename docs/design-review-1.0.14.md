# 设计评审：WindowShade 1.0.14（应用与官网）

用 `apple-design`（Apple 的动效与手感原则）与 `apple-design-hig`（HIG 逐页语料 + craft 视角）两套
标准做的发版前评审。引用格式为 `文件.md › 小节`，HIG 语料在 `~/.codex/skills/apple-design-hig/references/hig/`。

## 概要

**评审对象**：macOS 14+ 原生 Swift / AppKit 菜单栏应用（窗口浏览面板、卷帘条、悬停预览、设置窗口、
状态栏菜单），以及 Cloudflare Pages 上的双语官网与互动考古长文。

**用什么看**：应用是生产组件的离屏截图 `docs/visual-qa/`（2x，macOS 27.0 / SDK 26.5，包含一张真实合成器
玻璃截图）；官网是在 1440 / 1100 / 767 / 390 / 340 宽、浅色与深色下用 Chromium 实拍，加上直接读源码；
数字取自代码常量、截图采样和浏览器里的实测。

**评级：Good。** 没有 Critical 项。应用侧两条 High（底部 Dock 标签带把系统气泡当成自己的标签；列表行按两行
预留高度）、一节可访问性 Medium（11 pt 次要状态文字的对比度 3.98:1）；官网侧一条 Medium（中文大标题字距）
已在安全的范围内修好，另有两处确定性问题（面板尺寸数字过期、中文页的引号方向）已修。

**两个设计论点**。应用：*把一个老动作（把窗口让开）做成看得懂、能后悔、只读不擅自动手的面板*——它记住了
自己的身份、状态和当前选中项。网站：*一页克制的产品说明 + 一篇可以亲手操作的档案文章*。两者的记忆点分别是
"底部标签带把 Dock 气泡变成面板自己的标签"（前提是真机对齐成立）和"四个年代的标题栏复刻"。

## Critical

无。

## 改进项

### High · 底 Dock 面板把系统气泡当成自己的标签

**问题**：面板底部留 38 pt 标签带，指望系统的应用名气泡落进带里；气泡收起后由面板自己的标签接替
（`WindowBrowserLayoutParams.dockCaptionHeight = 38`、`dockBottomGap = 4`）。这两个数是从用户截图推算的，
不是系统提供的度量：Dock 缩放、字号、系统版本或图标大小变化都会让气泡落偏，那时带里要么空着、要么和应用名
重复——正是这一轮要修掉的现象。

**依据**：`panels.md › Best practices`："Write a brief title that describes the panel's purpose … Create a
short title … that can help people recognize the panel onscreen." 面板的身份应当由面板自己给出，而不是借用
另一个应用（Dock）的浮层。`designing-for-macos.md › Best practices` 要求用系统控件与约定，而不是复制它的
视觉位置。这一条里"38 pt 是从截图推算"属于我的判断，HIG 没有对应的数字。

**建议**：先按 `docs/window-browser-visual-qa.md` 的手工步骤在真机上确认三种 Dock 大小（小/中/大）与
两档系统字号下的气泡落点；把标签带高度改成从气泡的实测基线推出的常量，并给"气泡没出现"的情况留同一位置
的兜底文字（现在只有"气泡消失后接替"这一半）。若真机上永远对齐不了，宁可去掉这条带、让面板自己写应用名
（多花 20 pt 高度，但不再依赖别的进程）。

### High · 列表行按两行预留高度

**问题**：列表行固定 `listRowHeight = max(52, 标题 16 + 状态 13 + 间距 8×3) = 53 pt`，行距 4 pt；
没有状态的窗口也占满这个高度（`WindowBrowserGeometry.derivedParams`）。卡片侧已经修好了同一个问题
（`cardStatusLineVisible`：没有状态就不留状态行），列表行没有跟上。截图 `dock-list-many.png`（18 个窗口，
54 处行距实测 56 pt）里绝大多数行只写标题。

**依据**：`lists-and-tables.md › Best practices`："Prefer displaying text in a list or table … the row-based
format is especially well suited to making text easy to scan and read." 行高不服务内容时，扫描成本上升。
`designing-for-macos.md › Best practices` 要求"maintaining a comfortable information density"。

**建议**：在 `derivedParams` 里对行做和卡片同样的判断——这一批窗口都没有状态时
`listRowHeight = 标题行 + 间距×3 ≈ 40 pt`（有状态仍 53 pt）。18 个窗口的面板因此少滚一屏。

### Medium · 11 pt 次要状态文字的对比度 3.98:1

**问题**：`已收起` / `正在展开` 这类状态行用 `NSColor.secondaryLabelColor`、字号 `detailSize`（默认 11 pt）。
在浅色卡片 `#FBFBFB` 上采样得到 `#7D7D7D`，对比度 **3.98:1**，低于 HIG 引用的 WCAG AA 门槛。
`SystemAppearancePolicy` 在"提高对比度"下改的是描边宽度与选中指示，没有动文字颜色。

**依据**：`accessibility.md › Vision`——"Up to 17 pts / All / 4.5:1"，以及"If your app doesn't provide this
minimum contrast by default, ensure it at least provides a higher contrast color scheme when the system
setting Increase Contrast is turned on."；`color.md › Inclusive color` 要求不要把可读性押在单一手段上。

**建议**：在 `increaseContrast` 分支里把状态文字从 `secondaryLabelColor` 提到 `labelColor`（或
`labelColor.withAlphaComponent(0.75)`），与同一条策略里已经加粗的边线保持一致。默认外观是否也提到 4.5:1
属于观感取舍：系统的 `secondaryLabelColor` 本身就在这个量级，先修"提高对比度"这条更稳。

### Medium · 中文大标题的字距按拉丁文取值

**问题**：`.hero h1` 用 `letter-spacing:-.055em`，`h2` 用 `-.045em`，中英文共用。对全角汉字，这等于把每个
字身压掉 5.5%；实测"窗口挡路？"在 74.88 px 下 **374.4 px → 353.8 px**（每字 −4.12 px），"窗/口""让/开"
在 2x 截图里笔画几乎贴在一起。

**依据**：`typography.md › Specifications › macOS tracking values`——系统字体在 24 pt 以上字距转正
（48 pt 是 +8/1000 em，76 pt 是 +1/1000 em）；`apple-design` 的 §15 也把"按字号取字距、绝不一个值通吃"
列为规则。

**已经做的**：中文首页 hero 改为 `-.02em`（每字 −1.5 px）。在 390 / 767 / 820 / 900 / 1440 / 1600 宽下
逐行比对，除 hero 自身变宽 9 px 外，**所有标题的断行与基线结构和改动前完全一致**。

**没有做的**：section `h2` 的 `-.045em` 保留。放宽到 `-.025em` 会让 9 字行超出文本列——"需要一直看的东西，"
与"全是你要选的东西。"在 1440 宽下各自多断一行（439 pt 的列放不下 447 pt 的行）。要真正修好得同时把 h2
降到约 48 px 或把文案列加宽到约 470 px，这是字阶决策而不是一处字距，留作下一轮；改动点与实测数字都在
这里的记录里。

### Low · 中文页的两处引号方向（已修）

FAQ 的"要什么权限？""怎么装？"两条里，`”屏幕录制”`、`”应用程序”`、`”系统设置 → 隐私与安全性”`、
`”仍要打开”` 用了右引号当左引号（`content.mjs`）。依据：`writing.md` 要求标点与平台的排印规范一致，
同一页里混用两种引号会被当成没校对。已改为成对的 `“ ”`。

### Low · 历史页的面板渲染是上一版（已修）

`site/public/media/bridge-windows.webp` 还是"页眉写应用名、没有标签带"的旧面板，而正文描述的是当前面板。
已用当前生产组件重出（`--window-browser-shots` 的 `dock-three`，1824 × 572 @2x → 1102 × 348）。

## Craft 笔记

- **有一个克制的论点，不是模板。** 应用不靠渐变、大数字或插画，靠系统材质与状态表达；官网靠排版节奏
  和一套真的能点的复刻控件。把它们放到同类工具里能认出来。
- **最该删的一样东西：底部标签带。** 按"去掉一件配饰"的标准，这条 38 pt 的带子是唯一一处"为了配合另一个
  进程的浮层"而存在的设计。真机验证通过就留着，验证不过就删——面板自己写应用名更符合面板的身份规则。
- **官网的品牌感放在标题和历史上，控件仍走系统语言。** 正文 16 px / 1.85、小字 11–12 px，浅色下 `--muted`
  对背景 **5.05:1**、深色下 **8.44:1**；强调色上的白字 **5.43:1**、深色强调色上的深字 **6.99:1**，都过线。
- **动效都在该在的地方。** 面板尺寸 120 ms、选中 100 ms、首图 80 ms，减少动态效果下全部关闭；
  官网只有 hero 入场和折叠/置顶演示有动效，都在 `prefers-reduced-motion` 下退回交叉淡变或静态。
  没有发现"频繁交互上加了花哨动画"的情况。
- **一处不对称**：键盘面板的搜索框、详情栏、分段控件与 Dock 面板的页眉是同一套视觉语言，但 Dock 面板
  故意不画键盘选中环——这是有意的（Dock 面板不吃键盘焦点），文档也写明了，保留。

## 值得保留的做法

- **玻璃只用在功能层，而且只有一层。** `materials.md › Liquid Glass`："Don't use Liquid Glass in the
  content layer." 面板根视图是唯一一层 `NSGlassEffectView`（`regular`，HIG 给文字多的弹窗的档），卡片、
  行、详情栏用系统填充色；真实合成截图（`liquid-glass-panel.png`）能看到内容确实在玻璃里。
- **四条回退路径都真的存在**：减少透明度（不透明纸面）、提高对比度（更粗边线 + 选中不只靠颜色）、
  减少动态效果（不动画）、旧系统（`.active` 材质）。`accessibility.md › Vision` 与 `color.md` 要求的
  正是"每个上下文都有答案"。
- **命中区与字号守住了平台基线**：操作按钮 28 × 28、间距 4；正文字号跟随系统"文字大小"，次要文字下限
  10 pt（`accessibility.md › Mobility` 给 macOS 的默认 28 × 28、最小 10 pt）。
- **状态表达不只靠颜色**：折叠/最小化/置顶用系统符号 + 文字，警告色只留给真的警告
  （`color.md › Inclusive color`）。
- **官网的无障碍是可用的**：跳转链接、`aria-expanded`、`aria-live` 状态区、`details/summary` 的键盘可达、
  浅深两套语义色、`prefers-reduced-motion` / `prefers-reduced-transparency` 都有对应分支。
- **历史文章把"示意"标清楚**：复刻界面标为示意、史料逐条给来源、1989–92 版权区间不当作首发日期。
  这是 `writing.md` 意义上的诚实文案。

## 平台说明

- **应用（macOS）**：这是一个 `LSUIElement` 菜单栏应用，没有主窗口，所有命令都从状态栏菜单、快捷键和设置
  窗口进入；设置窗口走标准的 App 菜单 ⌘, 与侧栏式分页（`settings.md › Desktop`）。面板不是窗口：
  它不吃键盘焦点、不占 Dock、不进窗口菜单，键盘路径由独立的"窗口选择"面板承担。这条分工是对的，评审里
  的 High/Medium 都落在面板自身而不是分工上。
- **官网（web）**：只适用 HIG 的基础部分（色彩、排版、布局、可访问性、写作）与八条设计原则，不适用
  macOS 的平台约定——网页不该照搬 13 pt / 28 pt 这类桌面控件基线。历史页的年代界面是**刻意的例外**，
  它复刻的是当年的像素规范，不是今天的 HIG。

## 这次评审的边界

- 应用截图来自离屏的生产组件渲染，玻璃的折射只有一张屏幕截图能证明；1x、多显示器、真实 Dock 气泡位置
  都没有样本，所以上面两条 High 只能给方向和验证方法，不能给"已经对齐"的结论。
- 官网在 **Chromium（headless shell）与 WebKit 两个引擎**里都复核过（WebKit 用 Playwright 自带的
  构建，需要把 `DYLD_FRAMEWORK_PATH` 指到那份 bundle，否则会去加载系统 WebKit 而符号不匹配）。
  逐宽度比对（390 / 767 / 900 / 1100 / 1440）：**每个标题的断行数完全一致**，绝对字宽 WebKit 小约 2%
  （例如 hero 每行 358 px vs Chromium 367 px，`窗口挡路？` 在 54 px 下 258.3 px vs 264.6 px）。
  一处可见差异是**全角标点**：WebKit 给 `？` `。` 留出完整字身（看起来与前面的汉字有间隔），
  Chromium 会把它压紧。这与本次改动无关——把 `letter-spacing` 设回 0 或 `-.055em`，两个引擎的差异
  一样存在。中文排版上 WebKit 的呈现更接近全角标点的常规，故没有为它改 CSS。
- 对比度是从截图采样（`#7D7D7D`）而不是从最终合成色计算；深色与提高对比度下的应用截图没有逐像素采样，
  那里的判断来自代码路径而不是测量。
- 评审覆盖了应用的面板、卷帘条、悬停预览、设置与菜单，以及官网首页与历史页；没有覆盖金属渲染的合盖
  动效画面本身（它属于效果而不是界面）。
