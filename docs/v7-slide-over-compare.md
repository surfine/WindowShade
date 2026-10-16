# V7：侧拉与 iPadOS 27 Slide Over 的像素级比对（2026-10-17）

**结论：iPadOS 一侧的像素测量 `not_run`，侧拉一侧的常量已查实。** 模拟器能起、设置页能读，但这台机器当时负载均值约 400，往 Slide Over 的拖拽手势在模拟器里一次都没有注入成功，所以没有一张 Slide Over 的截图，下面表里 iPadOS 一栏不填任何数字。「约 10 pt、约 8 pt」仍然只是旧笔记里的说法，没有被这次验证，也没有被推翻。

## 1. 进 Slide Over 的路径（能确定的部分）

证据来自模拟器里的设置页和 iOS 27 运行时里的 SpringBoard 二进制，都不是猜的。

| 事实 | 证据 |
| --- | --- |
| 设置 > 多工处理与手势有三种模式：全萤幕 App、视窗 App、台前调度；**窗口模式（视窗 App）下没有 Slide Over**，只在「全萤幕 App」模式下可用 | 设置页截图 `12s.png`（当时选中视窗 App）、`13s.png`（切成全萤幕 App 后，缩略图里是一块浮在上面的窄窗） |
| iOS 27 的 SpringBoard 里还有完整的 Slide Over 实现：`slideOverTongue`（边上那一小片，即把手）、`slideOverCorner`（四个角）、`slideOverSizeWidth/Height`、`slideOverDodgesDock`、`ActivateSlideOverLeft/Right`、`ToggleSlideOverForDisplayItem`、「Floating Application (Slide Over) Settings」 | `strings` 对 `.../iOS 27.0.simruntime/.../SpringBoard.framework/SpringBoard` |
| 进入方式：全萤幕模式下，自底部上划露出 Dock，把 Dock 里的 App 图标**拖到屏幕左右边缘**（旧版 iPadOS 的做法；27 的二进制里有「draggingPlatterSlideOverActivationRegion」，即拖拽中的图标进到边缘区域才触发） | 二进制里的设置项名；**手势本身没能在模拟器里跑通** |
| Dock 图标长按弹出的菜单（以 Safari 为例）只有：起始页面、新增视窗、显示所有视窗、新增标签页……**没有 Slide Over** | 截图 `06-drag.png`、`16s.png` |
| 全萤幕模式下顶部没有旧版那个「•••」多任务按钮 | 截图 `14.png`、`17s.png` |

没跑通的原因：`xcrun simctl` 没有拖拽命令，只能用 MCP 的 `touch_path` / `swipe` 注入触摸。试了 5 种时序（按住 0.15 至 2 秒、分段移动、2.5 秒连续慢拖），结果要么触发 Dock 图标的长按菜单后拖拽被吞，要么根本没有拖起图标。长按菜单在按下约 0.7 秒后才出现，说明模拟器的触摸时序被负载拖歪了；这比手势本身不存在更可能。

## 2. 复测办法（把机器腾空后照做）

1. 关掉别的模拟器（当时还开着 Clio iPhone A/B、Clio iPad），`uptime` 负载降到个位数再开始。
2. `xcrun simctl boot C0E4E772-D502-41BF-AB30-D7E7A137665A`；设置 > 多工处理与手势选「全萤幕 App」（**这台模拟器现在已经是这个模式**，原先是视窗 App）。
3. 开 Files，自底部边缘（距底边 4 pt 以内，如 y = 1208.5）上划 88 pt 露出 Dock；Dock 约几秒后会收，要紧接着拖。
4. 在 Safari 图标上按下，约 0.2 秒内开始移动，匀速拖到右边缘（x ≥ 826），停约 1 秒再松手。若出现长按菜单，说明按得太久，点空白处关掉重来。
5. 竖屏、横屏各截一张：`xcrun simctl io <udid> screenshot x.png`；这台 iPad Pro 11 寸是 1668 × 2420 像素、834 × 1210 pt，倍数 2。
6. 量法：像素 ÷ 2 = pt。Slide Over 窗的外沿到屏幕边、上下留白（Dock 在与不在各一张）、圆角用外沿一段弧拟合半径、边缘玻璃/阴影的宽度、把手（收起后留在边上的那一小片）的宽高与离顶位置。
7. 收尾：`xcrun simctl shutdown <udid>`；想回到原来的窗口模式就在设置里选回「视窗 App」。

## 3. 侧拉一侧已查实的常量（macOS，原始码）

| 项 | 值 | 位置 |
| --- | --- | --- |
| 玻璃边框厚度 | 10 pt | `prototype/App/SlideOverChrome.swift:15` `thickness` |
| 窗口离屏幕边 | 18 pt（= 10 pt 边框 + 8 pt 缝；注释写「iPad 上边框外沿离屏幕边 8 点」） | `prototype/App/SlideOver.swift:68` `inset` |
| 上下留白 | 同 inset，18 pt | `SlideOver.swift:210、626` |
| 窗口内圆角 | 取窗口实测圆角，没测到用 17 pt；外圆角 = 内圆角 + 10（同心） | `SlideOverChrome.swift:17、238`（`defaultCornerRadius`、`outerRadius`） |
| 边框阴影 | 向下偏 4 pt、模糊 20 pt、浅色 0.20 / 深色 0.45 的黑；阴影只往外 | `SlideOverChrome.swift:253` |
| 阴影余量 | 26 pt | `SlideOverChrome.swift:19` `shadowMargin` |
| 把手（挂着时，角上一段弧） | 36 × 36 pt 命中区；弧线宽 3 pt（按下 3.5），垫一道 4.5 pt 的 35% 白 | `SlideOverChrome.swift:16、412–415` |
| 收起后边上的那一小片 | 16 × 76 pt，竖直居中于窗口；中间一个朝里的箭头 | `SlideOver.swift:909` `SlideOverTab.size` |
| 收起后窗口留在屏内 | 4 pt | `SlideOver.swift:66` `peek` |
| 最小宽度 / 最小高度 | 320 / 240 pt | `SlideOver.swift:69、626` |
| 贴边间距令牌 | `margin.edgeHug` = 8 | `docs/design-system.md:329` |
| 位移弹簧 | `glide`（0.42 / 0.88） | `docs/design-system.md:345` |

设计稿一侧：`docs/design-drafts/README.md` 里没有专讲侧拉的稿；令牌文字在 `docs/design-system.md` §5.5、§6-7，对照账在 `docs/design-grammar.md`。所以侧拉的这些数字目前没有稿可对。

## 4. 并排对照

| 项 | 我们（已查实） | iPadOS 27 Slide Over |
| --- | --- | --- |
| 边框 / 玻璃宽度 | 10 pt | **not_run**（旧笔记约 10 pt，未验证） |
| 窗口外沿离屏边 | 8 pt（边框外沿），窗口离屏边 18 pt | **not_run**（旧笔记约 8 pt，未验证） |
| 上下留白 | 18 pt | **not_run** |
| 圆角 | 内 = 窗口圆角（默认 17）、外 = 内 + 10 | **not_run** |
| 阴影 | 偏 4、模糊 20、alpha 0.20 / 0.45 | **not_run** |
| 把手 | 挂着：36 pt 角弧；收起：16 × 76 pt 玻璃片加箭头 | **not_run**（27 的二进制里叫 tongue，有「展开比例」一项） |
| 进入方式 | 窗口标题栏拖到边、菜单、快捷键 | 全萤幕模式下 Dock 图标拖到边；窗口模式不提供 |

## 5. 建议

**现在不改任何数字。** 没有 iPadOS 的实测值，改了就是凭印象改。复测拿到数字后，按下面决定：

1. 若实测边框厚度 = 10 ± 0.5 pt 且外沿离屏边 = 8 ± 0.5 pt：保持 `thickness` = 10、`inset` = 18，只在 `SlideOver.swift:67` 的注释里把「iPad 上……8 点」改成「2026-10-xx 实测」并写上日期。
2. 若实测的同心关系成立（外圆角 − 内圆角 = 边框厚度）：保持 `outerRadius = innerRadius + t`；若 iPad 的外圆角是固定值，则只改 `SlideOverChrome.swift:238` 的公式。
3. 把手：若实测收起后的那一片宽 < 16 pt 或高与 76 pt 差 > 8 pt，只改 `SlideOverTab.size`（`SlideOver.swift:909`），不动命中区的位置约束。
4. 阴影：对着实测的外扩宽度，只调 `blur` 和 `offset`（`SlideOverChrome.swift:253`），`shadowMargin` 须 ≥ blur 的 1.3 倍，当前 26 对 20 刚好够。
5. 动效：录下 iPadOS 把窗口拖到边缘的过程，对 `glide`（0.42 / 0.88）的停靠时长，不一致再提 §6-10。

## 6. 本次留下的状态与证据

截图都在 `/private/tmp/claude-501/-Users-aaron-Documents-WindowShade/e20dabbb-f268-4ba8-9581-ffaab367e5e6/scratchpad/v7/`（不入库）：`00-home.png`（启动中）、`01`、`03-files.png`（Files 全屏、无窗口控件）、`05-dock.png`（Dock 呼出）、`06-drag.png`（长按菜单）、`12s.png`（设置：三种模式，选中视窗 App）、`13s.png`（切成全萤幕 App）、`16s.png`、`18s.png`、`21s.png`（拖拽失败的现场）。模拟器已关机；它的多工处理模式从「视窗 App」改成了「全萤幕 App」，仅在模拟器内。
