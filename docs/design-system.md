# WindowShade 设计系统

> 2026-09-29 定稿，尚未实现。这份文件规定四件事：界面怎么贴合硬件，各个表面取哪些数值，各个表面怎么动，
> 怎样才算做到了 Apple 的水准。产品方向以 [direction.md](direction.md) 为准；参加 Swift Student Challenge 是“入戏”用的品味标准，
> 见 [ssc.md](ssc.md)。面向用户的文字一律按 [copy-guide.md](copy-guide.md) 写。
>
> 文中的“岛”“肩”“硬件层”“隐形刘海”是给开发看的内部叫法，不进界面。“下巴”按 copy-guide 只在说明里用。

**数值标注**

| 标注 | 含义 |
|---|---|
| **[Apple]** | Apple 官方页面、HIG 或 WWDC 讲座原文写明的 |
| **[图稿]** | 从 Apple Design Resources 的 Product Bezels（M5 Air、M5 Pro、Neo）量出来的。授权素材只能用来测量，图片和 PSB 不进仓库 |
| **[系统]** | 本机 Mac17,4（MacBook Air 15″ M5，macOS 27）用只读脚本读到的系统数据。**完成 §7.3 的物理校准之前，不写成“实测”** |
| **[推断]** | 由其它数值推出来的 |
| **[现值]** | 代码里现在写着的，文件和行号相对 `prototype/` |
| **[自定]** | WindowShade 自己定的，不是 Apple 的数字 |
| **[改值 §6-n]** | 目标值和现值不同，要按 §6 第 n 条单独改、单独验收 |

测量原始数据在当次会话的 scratchpad 里（`ds/wf-bezel.md`、`ds/all.txt`、`ds/summary.json`、`hwfit/getters_out.txt`、`hwfit/screens_out.txt`），没有入库。

**单位与换算**

- px 指**面板物理像素**，pt 指**当前显示模式下的 Cocoa 点**。硬件数值一律按 px 存，用的时候再换成 pt，代码里不写死点数。
- 换算只用 `pxPerPt = 原生面板像素宽 ÷ screen.frame.width`，**不要用 `backingScaleFactor`**。本机默认模式 1710×1107 时 pxPerPt = 2880/1710 = 1.684，`backingScaleFactor` 却是 2；只有 2× 模式（1440×932）两者才相等。
- 原生面板宽这样取：`CGDisplayCopyAllDisplayModes(id, [kCGDisplayShowDuplicateLowResolutionModes: true])`，找 `ioFlags` 带 native 标志（`0x2000000`）的那个模式，读它的 `pixelWidth`。**当前模式的 `CGDisplayModeGetPixelWidth` 给的是帧缓冲宽（本机 3420），不是面板宽（2880）**，不能拿来换算 [系统]。

---

## 1. Apple 的价值观与 Liquid Glass 初衷

从 [ssc.md](ssc.md) §4 压缩成六条设计原则。它们和 §2 的十二条一起用：十二条讲“怎么做得像 Apple”，这六条讲“做什么、不做什么”。
§5 的每个组件都有一行“价值观”，写明它怎么满足这六条；满足不了的，写进 §6 当差距。

| # | 原则 | 出处 | 在 WindowShade 里 |
|---|---|---|---|
| V1 | **一眼就熟悉。** 更有表现力，但不丢掉用户已经熟悉的东西 | Apple Newsroom 2025-06-09（新设计发布稿）；Adopting Liquid Glass | Mac 已经有的做法优先。新东西从刘海长出来，长得像系统的一部分，不另起窗口。从 iPad、Windows、niri 搬来的行为不当默认（§8 问题 4）。不借用 Apple 的功能名和口号（Apple 商标准则） |
| V2 | **内容优先。** 界面退后，让内容突出 | WWDC25 219；HIG Materials | 内容层（窗口画面、缩略图）不加材质。顺利时刘海一声不吐（direction.md）。浮层用完就走，停稳后不压在内容上 |
| V3 | **玻璃只在控件层，不叠玻璃。** 玻璃是浮在内容上的导航和控件那一层 | WWDC25 219；HIG Materials | 分三层：硬件层纯黑、浮层用系统玻璃、内容层不加材质（§4.2）。浮层里再分块，用填充、透明度、分隔线，不再套一层玻璃 |
| V4 | **用系统玻璃，不自己仿。** 光学质感和流动感说的是系统材质本身 | Adopting Liquid Glass；WWDC25 310；ssc.md §4 | macOS 26+ 用 `NSGlassEffectView` / `NSGlassEffectContainerView`，14/15 用 `NSVisualEffectView`。不手画高光、折射和灰色“玻璃”。刘海是硬件层，永远不是玻璃 |
| V5 | **无障碍从第一行开始。** 为所有人设计，不是事后补 | apple.com/accessibility；HIG Accessibility；HIG Gestures | 每个表面都处理减少动态效果、减少透明度、增强对比度，并有 VoiceOver 名称（§4.9）。每个手势都有菜单或快捷键可以代替。少造新手势。状态不只靠颜色区分 |
| V6 | **Apple 式文案。** 清楚、能少就少、少说“我们” | HIG Writing；Apple Style Guide；copy-guide.md | 一个东西一个名字。组合键符号 ⌃⌘⌥ 第一次出现时说明是哪个键。按设备描述手势（触控板说“两指”）。不替 Apple 的硬件下定义：对外不说“刘海是 Mac 的新入口”，候选说法如“卡住时，刘海帮你一把”，由 Aaron 挑 |

另外两条照旧：画面只在本机处理，不上传；常驻耗电是 direction.md 里的“迷失信号”，所以 §3.4 的形状模型不轮询、不截图。

---

## 2. 原则

七个参考案例来自 Chan Karunamuni 个人网站列出的作品：iPhone X 手势界面（2017，fall2017 801）、Designing Fluid Interfaces（WWDC18 803）、
灵动岛（2022）、Design dynamic Live Activities（WWDC23 10194）、iOS 18 手电筒（2024）、Liquid Glass（WWDC25 219）。
WWDC25 356、WWDC23 10158 和 HIG 是其他讲者或文档给的补充来源。共同点归成下面十二条。

| # | 原则 | 出处 | 在 WindowShade 里 |
|---|---|---|---|
| 1 | **形状从硬件来。** 硬件边框的精度决定界面的曲率、尺寸和比例 | WWDC25 356；HIG Live Activities（灵动岛圆角 44 pt，形状与原深感摄像头一致）；fall2017 801 | 贴着刘海的形状都接着刘海自己的轮廓长：肩和刘海底角取硬件数值（§3）。刘海周围用纯黑，要求几何上无缝；不同屏幕的黑不保证一样深（§3.3） |
| 2 | **同心。** 子半径 = 父半径 − 边距；没有父容器时用兜底的固定半径；矮条用胶囊 | 356；HIG Live Activities；iPad Pro 13 尺寸图（显示区圆角是外壳圆角向内平移 8.19 mm，偏差 ≤0.07 mm，见 `ds/wf-adg.md`） | 岛里的内容和岛同心。靠近屏幕角落的表面不改半径，只做包含测试、挪位置（§4.1 规则 3） |
| 3 | **空间一致。** 从哪里出去就从哪里回来 | 803 | 收进刘海和放回走同一条路。启动台从刘海长出来，也收回刘海。提示浮窗出现在手势发生的窗口旁边 |
| 4 | **跟手、随时可打断、中途可以改方向。** 过程中持续反馈；判断停顿看手指的加速度尖峰，不用计时器 | 803；fall2017 801 | 刘海上的每个手势，过程中都要动。弹簧叠加播放，换目标时位置和速度连续。松手时按投影落点决定去向，不在一开始锁死方向 |
| 5 | **用弹簧描述动效，不用时长。** 默认 100% 阻尼；只有动作本身带动量，或者回弹本身是提示时才回弹 | 803（点按没有动量用 100% 阻尼；锁屏手电筒按钮的回弹是提示）；WWDC23 10158；HIG Motion | 所有动效引用 §4.6 的弹簧令牌。10158 允许为了显得活泼加一点回弹：提醒 `bloom`、展开 `expand` 按这一条保留已上线的值，列为已知例外。HIG Motion 说用触控板时效果更收敛，所以 Mac 上回弹上限定为 0.2，小元素确认 `pop` 0.25 [自定] |
| 6 | **顺着手势方向提示，轻输入、放大输出。** 用减速率把松手速度投影成落点，再找最近的目标 | 803（投影 = v/1000 · r/(1−r)） | 画中画落角 r=0.998，刘海下拉 r=0.99，甩一下标题栏都用投影落点。过程中的形变朝最终状态长 |
| 7 | **控件长在它控制的硬件旁边；画结果，不画参数。** 防误触靠更有意的动作加回弹提示，不弹确认框 | iOS 18 手电筒；803 | 和刘海有关的事都从刘海出现。落点小岛画窗口排好后的样子，不是菜单。越过阈值时终点弹一下，告诉用户“松手就成” |
| 8 | **一个会变形的整体，而不是一堆弹窗。** 多个会话可以分开、合并 | 灵动岛；10194；`NSGlassEffectContainerView` | 岛只有一个形状，在各状态之间变形。以后的第二个会话（收在边上的侧拉、藏起来的画中画）用“分开 / 合并”的语法 |
| 9 | **紧凑样式读起来是一件事；展开是紧凑的放大版；不留额头。** | 10194；HIG Live Activities（两段读起来是一件事，两侧大小相近，内容紧贴摄像头，不加内边距） | 紧凑样式左右两段紧贴刘海、等宽。提醒和展开保留两段的位置，内容绕着刘海排 |
| 10 | **材质分层。** 玻璃只用在浮在内容上的控件层；不叠玻璃；着色只给主要操作 | 219；HIG Materials | 见 V3 与 §4.2 |
| 11 | **少说话，先演示再用文字。** 文字只讲会反复用到的手势，讲一次 | 803；direction.md“只在他卡住时说” | 卡住时刘海演示一遍手指怎么动，旁边一句话。每条教学有次数上限 |
| 12 | **动效、触感、声音是同一种性格；辅助设置自动跟随。** | 803；219；HIG Playing haptics | 越过阈值给 `.alignment`，落点确认给 `.levelChange`（[现值]，不是 HIG 的规定，见 §4.8），不加声音。三项辅助设置每个表面都有对应处理（§4.9） |

**拿这些原则检查新东西**（和 direction.md 的四问一起用）：
- 它是从刘海长出来的，还是另起一个窗口？刚换到 Mac 的人一眼认得出它吗？
- 它的形状是从硬件或父容器推出来的，还是写死的？
- 手势做到一半松手或改方向，会发生什么？
- 减少动态效果、减少透明度、增强对比度打开时，它长什么样？VoiceOver 怎么念？

---

## 3. 硬件形状

### 3.1 事实

**天圆地方。** 五款机型（Neo、Air 13/15、Pro 14/16）都是顶部两个圆角、底部两个直角。底角的缺角面积：五张 PNG（含全部配色）和 Air 的 2× 内嵌图稿都是 0；Pro 的 2× 内嵌图稿有极小的缺角，换成原生 Pro 14 约 0.6、Pro 16 约 2.1 px²，仍按直角处理 [图稿]。
规格页脚注写的是 “rounded corners at the top” [Apple]。本机 `bezelPath` 的两个底角是直线，WindowServer 的 `SLSDisplayGetCornerRadii` 也是“两个 0、两个非 0” [系统]。

**屏幕顶角**是连续曲率曲线，不是圆弧：
- Air 和 Pro 比 `.continuous` 更方（超椭圆指数 n≈3.0–4.3），Neo 的 n≈2.5，基本就是 `.continuous` [图稿]。
- 各机型换成物理尺寸，等效圆半径都约 4 mm [图稿]。
- **可以用 `.continuous` 画。** 五款机型、两份独立渲染上，`.continuous` 的最大偏差都 ≤0.5 px（`ds/all.txt`）。要到 ≤0.2 px 才需要超椭圆。
- 本机 `bezelPath` 的顶角和图稿边界点相比，内部最大偏差左上 0.32 px、右上 0.51 px，45° 内缩 9.97 对 9.76 px。图稿对 `.continuous` 的最大偏差是 0.29–0.32 px，所以 `.continuous` 离 `bezelPath` 的上界约 0.85 px（右上 0.51 + 0.32，三角不等式，未直接拟合）。
- 顶角几乎总在菜单栏下面，贴顶角的工作优先级低。

**刘海** [图稿][系统]：
- 直边主体居中，偏差 ≤0.3 px。
- **肩和底角是同一族连续曲线。** 两处“45° 内缩 ÷ 延伸长度”都是 0.209（`bezelPath`，`hwfit/fit_out.txt`）。
  - 底角用 `.continuous` 画，误差在噪声底（rms 0.03–0.06 px）。
  - 肩用 `.continuous` 画，最大偏差 ≤0.3 px。图稿报告把肩判成圆 R 8.8 px，是分辨率不够时的等价结论：这么小的角，圆和连续角差不到 0.1 px。本系统统一按连续曲线。
- 肩是显示区在（刘海竖边, 屏幕顶边）处的凸角，被切掉的那一小块是边框，没有像素。

**系统给的和不给的**：
- 公开 API 只给刘海主体矩形：`safeAreaInsets.top`，加上 `auxiliaryTopLeftArea` / `auxiliaryTopRightArea` 中间那段空隙（macOS 12+）。
  - 它按 0.5 pt 取整，**不是外框**：本机 aux 宽 185.0 pt，`bezelPath` 是 185.25 pt（竖边在 x = 762.375 和 947.625），每边反而窄 0.125 pt；深度 33.5 对 33.26，深 0.24 pt [系统]。
  - 不含肩，没有任何曲线。
- 屏幕圆角、刘海底角、肩都没有公开 API。
- `NSViewCornerConfiguration`、`NSView.effectiveCornerRadii` 在 SDK 头文件里标的是 `API_AVAILABLE(macos(27.0))`，只处理窗口和容器的圆角，不描述屏幕形状 [系统，SDK 头文件]。
- 画连续角路径要自己生成：`NSBezierPath` 的圆角矩形是圆弧，`NSGlassEffectView.cornerRadius` 只有一个统一值。

**配件准则**（ADG R31，404 页）里没有 Mac 屏幕几何。能借用的只有术语：显示玻璃分成 active area（显示区）和 non-active area（边框）（p.229–231）。

### 3.2 机型表

表的键是**内建屏 + 原生面板像素尺寸**，五款互不相同。面板与刘海模组相同的旧代机型（例如 M2–M4 的 Air）共用同一行 [推断]。

**表 A：屏幕开口与顶角**（px；括号内是 2× 模式下的 pt）

| 面板 px / ppi | 机型 | 默认模式（pxPerPt） | 2× 模式 | 顶角 `.continuous` r | 最大偏差 | 45° 内缩 d45 | 等效圆 R | 底角 | 刘海 | 来源 |
|---|---|---|---|---|---|---|---|---|---|---|
| 2408×1506 / 219 | MacBook Neo（Mac17,5） | 1408×881（1.710）[三方，未核实] | 1204×753 | 33.6（16.8） | ≤0.25 | 9.8（4.9） | 34.0±0.5 | 直角 | 无 | 图稿（只有 PNG 一份） |
| 2560×1664 / 224 | Air 13″ M2–M5 | 1470×956（1.741）[三方] | 1280×832 | 34.8±0.3（17.4） | ≤0.46 | 10.0（5.0） | 35.1±0.4 | 直角 | Air 型 | 图稿 ×2 |
| 2880×1864 / 224 | Air 15″ M2–M5 | 1710×1107（1.684）[系统] | 1440×932 | 34.1±0.3（17.1） | ≤0.38 | 9.7（4.9）；`bezelPath` 9.97 | 34.4±0.4 | 直角 | Air 型 | 图稿 ×2；系统 |
| 3024×1964 / 254 | Pro 14″ 2021–2026 | 1512×982（2.0）[三方] | 1512×982 | 39.7±0.8（19.9） | ≤0.47 | 11.4（5.7） | 40.1±0.8 | 直角 | Pro 型 | 图稿 ×2 |
| 3456×2234 / 254 | Pro 16″ 2021–2026 | 1728×1117（2.0）[常见值，未核实] | 1728×1117 | 40.3±0.3（20.1） | ≤0.46 | 11.5（5.75） | 40.6±0.3 | 直角 | Pro 型 | 图稿 ×2 |

- 分辨率、ppi、“rounded corners at the top”来自 Apple 规格页 [Apple]；其余是 [图稿]。
- 2× 内嵌图稿的数值已按“原生宽 ÷ 内部开口宽”换回原生 px 再平均。

**表 B：刘海**（px；括号内是 2× 模式下的 pt）

| 型 | 主体宽×高 | 底角 `.continuous` r | 肩 `.continuous` r | 占屏宽 | 高宽比 | 物理尺寸 | 来源 |
|---|---|---|---|---|---|---|---|
| Air 型（13″ / 15″） | 312×56（156×28） | 18.0–18.5（9.0–9.2） | 8.5–8.7（4.3） | 13″ 12.2%；15″ 10.8% | 0.18 | 35.4×6.4 mm | Air 15 的 `bezelPath` 与 aux [系统]；Air 13 图稿 |
| Pro 型（14″ / 16″） | 369.7×64.0（184.9×32.0） | 20.5–20.8（10.3–10.4） | 9.5–10.2（约 4.9） | 14″ 12.2%；16″ 10.7% | 0.173 | 37.0×6.4 mm | 图稿 ×2；和第三方 NSScreen 读数 185×32 pt @1512 一致；**未在真机核对** |

- **Air 15 的图稿把刘海画小了约 2%**（305.6×54.8 px），不采用。原因是两份 Air 的 PSB 共用同一个刘海图形，缩放比例却不同（13″ 0.4921，15″ 0.4820）。Air 15 用 macOS 的读数，Air 13 的图稿和它只差 +0.5 / −0.3 px。
- Pro 型和 Air 型不是同一个模组（370×64 对 312×56），不能拿一边的毫米值推另一边。
- Air 13 与 Air 15 同 ppi，按同一模组处理 [推断]；证据是 Air 13 图稿与 Air 15 的系统读数一致。

**本机（Air 15″）换算成 pt，供对照现有代码**

| 项 | 1710×1107（默认） | 1440×932（2×） | 来源 |
|---|---|---|---|
| 刘海主体 | 185.0×33.5（aux）；185.25×33.26（`bezelPath`） | 156×28 | 系统 |
| 刘海底角 r | 10.7（`bezelPath` 拟合）；图稿 10.9 | 9.0–9.2 | 系统；图稿 |
| 肩 r / 延伸 | 5.06 / 7.1–7.7 | 4.3 / 6.0–6.5 | 系统 |
| 顶角 `.continuous` r | 20.2 | 17.1 | 图稿 |
| 顶角 d45 | 5.8（`bezelPath` 5.9） | 4.9 | 图稿；系统 |
| 菜单栏 | 34 | — | 系统 |

代码里写死的 10（静止第一帧、下巴、悬停、下拉起步）在两个模式下都只差约 1 pt（1710 下 10 对 10.7，1440 下 10 对 9.0）；紧凑样式的 12 在两个模式下都不接近。

### 3.3 不确定度

- **顶角**：半径 ±0.3–0.8 px，主要来自 Apple 两份渲染之间的差异，Pro 14 最大（1.5 px）。d45 ±0.2 px，是最稳的描述量，验收用它。超椭圆的 R 和 n 会互相补偿，单独看都不稳。
- **肩和底角**：肩 ±0.4 px，底角 ±0.2 px，刘海主体 ±0.4 px。Pro 两份图稿的刘海高度相差 0.45 px（63.6 对 64.05）。
- **延伸长度没有唯一定义**：连续曲线的尾段和直边相差 <0.1 px。`bezelPath` 给顶角延伸 65 px、肩 12 px；图稿按拟合给 52 px、13 px。所以**存曲线或 `.continuous` 的 r，不存延伸量**。
- **作废的数**：`hwfit/fit_out.txt` 和 `hwfit/wf-design.md` 里“顶角最佳 `.continuous` r 24.2 pt、偏差 1.6 pt”是拟合脚本的 bug（只采曲线段、漏了直线段），不是数据矛盾，不能引用。
- **`.continuous` 是不是同一条曲线**：图稿拟合用的是 iOS 7 的连续角曲线。macOS 上 `CALayer.cornerCurve = .continuous` 与 SwiftUI `RoundedRectangle(style: .continuous)` 是否同一条，可以离线验证，不用跑 App：
  - `CALayer.cornerCurveExpansionFactor(.continuous)` 应读到 1.5287；
  - 把两者的路径渲染进同一个 `CGContext` 比较。
- **`SLSDisplayGetCornerRadii`**：内建屏返回 `0, 0, 21.05, 21.05`，Studio Display 四个都是 0（`hwfit/getters_out.txt`）[系统]。
  - 这是 WindowServer 独立给出的“天圆地方”信号。
  - 单位不确定：按当前模式的 pt 算，21.05 × 1.684 = 35.4 px，接近等效圆 R；按 2× 的 pt 算，21.05 × 2 = 42.1 px，接近 65 ÷ 1.5287 = 42.5 px [推断]。
  - 函数签名是猜的，随产品发布有崩溃风险。只放在探针里做诊断和交叉校验，不进产品。
- **黑色不等于实体刘海的黑**：Air 和 Neo 是 IPS 屏（Neo 规格页原文 “LED-backlit display with IPS technology”），(0,0,0) 仍会透出背光，斜看有 IPS 泛光；Pro 是 mini-LED，有光晕。验收只要求几何无缝，暗环境下亮度可能略有差异（§7）。

### 3.4 运行时拿形状的顺序

所有表面都只从一个模型拿形状：`DisplayShape`（新文件 `Window/DisplayShape.swift`，私有读取放 `Private/ScreenBezel.swift`，做法和 `Private/SkyLightBridge.swift` 一致）。

- 启动时和收到 `NSApplication.didChangeScreenParametersNotification` 时各算一次（`App/Notch.swift:75` 已在监听）。
- 缓存键是 `displayID + IODisplayModeID + frame.size`。
- 不轮询，不截图，不加定时器。和 Notch.swift 已有的 2 秒对账定时器无关。

| 字段 | ① macOS 给的 | ② 机型表（按面板 px 查） | ③ 安全默认（= 现版本） |
|---|---|---|---|
| 有没有刘海、刘海位置 | **公开 API 永远说了算**：`safeAreaInsets.top > 0` 且 aux 两块都在 | —（表只补曲线，不决定有没有刘海） | 没有刘海 |
| 刘海主体的精确边 | `bezelPath` 的竖边和底边，要求与 aux 相差 ≤1 pt | aux 矩形 | aux 矩形 |
| 刘海底角、肩 | `bezelPath` 的曲线 | 表 B | 底角 10 / 12（现值），不画肩 |
| 屏幕顶角 | `bezelPath` | 表 A 的 `.continuous` r | 直角 |
| 屏幕底角 | `bezelPath` | 0 | 0 |
| 菜单栏高 | `frame.maxY − visibleFrame.maxY`（>0 时） | — | `max(24, 实测)`（现值） |
| 表里没有的机型 | 有 `bezelPath` 就用 | — | 现版本几何。机型类别只用来决定欢迎窗口里迷你 Mac 的示意画法 |

**机型类别**：`UTType(tag: hw.model, tagClass: UTTagClass(rawValue: "com.apple.device-model-code"), conformingTo: nil)`，再判断它是否属于
`com.apple.mac.notched-laptop` 或 `com.apple.macbookneo`。这个 tag class 没有写进文档，但调用的是公开 API。
本机查询结果：Mac17,4 属于 notched；Mac17,5 是 `com.apple.macbookneo-2026`，属于 `com.apple.macbookneo`、不属于 notched；Mac14,7、MacBookAir10,1 都不属于 notched [系统，`hwfit/ut`]。

**`bezelPath` 的守卫**（任何一条不满足就退到机型表，并且只在 §8 问题 1 同意后才进产品）：
1. 先 `responds(to:)`，再确认返回的是 `NSBezierPath`。
2. **路径用全局坐标**（本机 Studio Display 的 bounds 是 (−435, 1107, …)）。和全局 `frame` 比较，各边相差 ≤0.5 pt；布局前再转成屏内坐标。
3. aux 报告有刘海时，按几何特征找到“两段凹曲线、两条竖边、两段凸曲线、一条底边”，竖边与 aux 相差 ≤1 pt。按特征解析，不按元素下标（本机 43 个元素，以后的系统可能换段数）。
4. aux 报告没有刘海时，路径里不能有缺口。
5. `CGDisplayRotation ≠ 0` 时按没有刘海、四角直角处理。
6. 在 Diagnostics 里记一次实际用了哪个来源。

`bezelPath` 只在 macOS 27 上验证过。项目最低支持 14.0（`Info.plist` 的 `LSMinimumSystemVersion`），所以查表这条路在 14/15 上真的会被用到。

**帕累托**：`source == .fallback` 时，所有表面的几何必须与现版本逐一相等。只有能确认形状的屏才改外观。

### 3.5 特殊情况

- **缩放模式**：只影响 pxPerPt，物理形状不变。只有 2× 模式能逐像素对齐（表 A 的 2× 列）；其它模式只要求抗锯齿带 ≤1 px。本机 1710 模式下，刘海竖边落在帧缓冲 x=1524.75，本来就不在整像素上，缩放器用什么滤波也不知道。
- **半点**：窗口原点只能落在整点，刘海高 33.5 pt 这类半点靠在面板里偏移半点处理。现有代码已经这样做。
- **“避开刘海”模式**（1440×900、1710×1068 等）：API 报告没有刘海，顶部一条带熄灭，MBA 64 px [系统]，MBP 74 px [推断，1964−1890]。顶角延伸约 65 px，和熄灭带差不多高，可见区的角实际就是直角。按“无刘海、直角”处理，隐形刘海放在可见区顶部正中（现状）。
- **MacBook Neo**：天圆地方，没有刘海，摄像头在一圈均匀的边框里。Apple 规格页确认 2408×1506、219 ppi、IPS、顶部圆角；“没有刘海”Apple 没有写，依据是系统机型类别（上文）和产品图。刘海相关的功能走隐形刘海。顶角可以直接用 `.continuous` r=33.6 px。
- **外接屏**：
  - Studio Display 的 `bezelPath` 就是 `frame`，四角直角，没有刘海；`SLSDisplayGetCornerRadii` 四个 0 [系统]。
  - 本机外接屏的 `visibleFrame == frame`，`_revealedMenuBarHeight` 是 0，也就是这块屏上根本没有菜单栏（推测“显示器具有单独的空间”关着）。所以菜单栏高保持 `max(24, 实测)`，**不**改成 30，也不调私有的 `SLSGetDisplayMenubarHeight`。
  - Sidecar（iPad）和 AirPlay 屏实物是圆角，但拿不到数据，按直角处理（等于现状）。
  - 隐形刘海槽位保持 190 宽：它是拖窗口的瞄准范围，`App/LaunchpadController.swift:153` 也在用；缩小就是已上线交互的退化。
- **排列**：要在“外接屏设为主屏、内建屏不在原点”的排列下实测一次 `bezelPath` 的坐标。
- **合盖只用外接屏**：内建屏不在 `NSScreen.screens` 里，`notchScreen()` 返回 nil，自然走隐形刘海。
- **镜像**：只有一个 `NSScreen`，刘海按它的 API 为准；拿不准时按直角、无刘海处理，待实测。
- **旋转**：内建屏正常不能旋转；万一 `CGDisplayRotation ≠ 0`，按守卫 5 处理。

---

## 4. 设计令牌

动效令牌放在 `App/Motion.swift`（现在只有 `reduced`），形状令牌放在 `Overlay/SystemAppearance.swift:189–209` 的 `SystemCornerRadius` 旁边。各表面只引用令牌，不写魔法数。

**改值规则**：令牌先填**现值**，第一轮（§6-5）只把现值收进令牌，参数逐字不变。目标值和现值不同的，一律标 **[改值 §6-n]**，汇总在 §4.10，一条一条改、一条一条验收。不能笼统地说“只收拢，不改值”。

### 4.1 圆角

**硬件（运行时从 `DisplayShape` 取，单位 pt）**

| 令牌 | 含义 | 本机 1710 / 1440 |
|---|---|---|
| `hw.screenTop` | 屏幕顶角，`.continuous` r | 20.2 / 17.1 |
| `hw.screenBottom` | 屏幕底角 | 0 / 0 |
| `hw.notchBottom` | 刘海底角，`.continuous` r | 10.7 / 9.0–9.2 |
| `hw.notchShoulder` | 刘海肩，和底角同族的连续曲线，`.continuous` r；延伸量记作 e | r 5.06，e 7.1–7.7 / r 4.3，e 6.0–6.5 |

**系统（固定值）**

| 令牌 | 值 | 用在 | 来源 |
|---|---|---|---|
| `system.window` | 13 | 只有标题栏的窗口级表面：浮窗、卷帘条、预览面板 | [现值]，实测 macOS 27 标准窗口 |
| `system.card` | 12 | 内容卡片、画中画、设置分组 | [现值] |
| `system.item` | 8 | 窗口浏览里的卡片、行 | [现值] |
| `system.control` | 6 | 自绘小按钮、chip | [现值] |
| `capsule` | 高 ÷ 2 | 矮条：隐形刘海、分屏把手、胶囊按钮 | WWDC25 356 |

带工具栏的窗口圆角更大；macOS 27 上从 `effectiveCornerRadii` 读，不写死。

**岛（从刘海长出来的形状）**

| 令牌 | 现值 | 目标 | 状态 |
|---|---|---|---|
| `island.hug` | 10（第一帧、下巴、悬停、下拉起步，Notch.swift:1338、1343）；12（紧凑） | = `hw.notchBottom` | [改值 §6-3] |
| `island.shoulder` | 无 | = `hw.notchShoulder`，按 §5.1 的 S1–S5 | [改值 §6-3] |
| `island.pull` | 10 + 下拉量/4，最大 22（Notch.swift:1274–1285） | 起点改为 `island.hug`，上限不变 | [改值 §6-3] |
| `island.drop` | 22 | 不变 | [现值] |
| `island.alert` | 24 | 不变 | [现值] |
| `island.expanded` | 28 | 不变 | [现值] |

**派生规则**：
1. **接着刘海长。** 贴着刘海的形状 = `notchPath(body:)`：主体矩形的两条竖边在 `body` 上，肩从竖边向外弯到顶边，底角从 `island.hug` 过渡到目标半径。拓扑固定，可以直接做路径插值。所有角都是连续曲线，路径要自己生成（§3.1）。
2. **同心（容器内）。** 子半径 = 外层半径 − 边距，最小 4。
   - 展开：28 − 14 = 14（格子）。
   - 提醒：24 − 14 = 10（图标台、教学台面）。
3. **靠近屏幕角落（包含测试）。**
   - 只在 `visibleFrame` 伸到屏幕顶边时才可能碰到（自动隐藏菜单栏、全屏空间）。
   - 判据：拿表面的实际轮廓和 `DisplayShape` 的屏幕轮廓做包含测试，同时避开刘海所在的那一列（`safeAreaInsets`）。不要用“离两条边都不到 6 pt”这种只看 45° 的判据：贴着顶边的东西，离侧边三十多点以内都可能被切（离侧边 10 pt 处，屏幕边向内切约 2.9 pt）。
   - 不通过时**只挪位置，不改半径**。“屏幕角半径 − 边距”要求两边边距相等，现有表面基本都不满足（卷帘架是 10 和 8）。
   - 屏幕底角是直角，下半部的角落一律用自身令牌。
4. **胶囊只给矮条。** 高度会变的形状用固定半径，不在“胶囊”和“圆角矩形”之间来回跳。

### 4.2 材质

| 层 | 用在 | macOS 26+ | macOS 14/15 | 减少透明度 | 增强对比度 |
|---|---|---|---|---|---|
| **硬件层** | 刘海岛各状态、下巴、截图飞进刘海的最后一段 | 纯黑 `(0,0,0,1)`，不用材质，不加朝上的阴影 | 同左 | 不变 | 边线 `white 0.14 → 0.5` [改值 §6-11] |
| **浮层** | 手势提示浮窗、窗口浏览面板、侧拉的玻璃边框 | `NSGlassEffectView`，style `.regular`；内容放进 `contentView`，不把玻璃当兄弟视图垫在后面；彼此靠近的几块放进 `NSGlassEffectContainerView` | `NSVisualEffectView`：提示浮窗 `.hudWindow`，面板 `.popover` | 不透明的 `windowBackgroundColor` | 不透明底上的边线加粗到 1 pt、用 `labelColor`（窗口浏览是现值，WindowBrowserMaterial.swift:232–234；提示浮窗现在是 `separatorColor` [改值 §6-11]）；用玻璃时不另加边（现值） |
| **内容层** | 窗口画面、缩略图、画中画画面和压在上面的按钮、看一眼的卡片 | 不加材质 | 同左 | — | — |

使用规则：
- **不叠玻璃**（HIG Materials；WWDC25 219）。浮层里再分块，用填充、透明度、分隔线。
- **不用 Clear 玻璃**，一律 Regular。画中画没有控制条：按钮是无边框的白色图标，散在四角和正中，直接压在画面上，底下是 0.45 / 0.12 / 0.45 的渐变暗层，不用材质（PictureInPictureViews.swift:54、67–105）。这比加一条玻璃更符合 V2，保持。
- **着色**只给主要操作和“已对准”，用 `controlAccentColor`。
- **交互发光**：`effectIsInteractive` 只在 macOS 27 有 [系统，SDK 头文件]。给被按住或拖动的小片玻璃用，例如侧拉边上那一小片。
- **显隐**：AppKit 没有 Liquid Glass 的“显形”API，淡入淡出要短（`fade`），不让玻璃停在半透明状态。
- **外观**：深浅色和辅助设置都要**持续监听**（`NSWorkspace.accessibilityDisplayOptionsDidChangeNotification`、`effectiveAppearance` 变化），不能只在挂上时取一次。
- **不自己仿**（V4）：自绘的灰色“玻璃”、手画高光、合盖和倾斜效果都属于仿造或装饰。合盖 / 倾斜效果已定默认关（direction.md），其余在 §6-8 逐个过。

### 4.3 颜色

只用系统语义色，不写 RGB。

| 令牌 | 值 | 用在 | 来源 |
|---|---|---|---|
| `accent` | `controlAccentColor` | 主要操作；落点已对准；教学提示的边（0.8）；提示浮窗越过阈值的终点 | [现值] |
| `problem` | `systemOrange`，边 0.75、1.5 pt | 出了问题的提醒 | [现值] Notch.swift:1312 |
| `destructive` | `systemRed` | 只给退出 App、关掉这类不可撤销的操作 | — |
| `label.*` | `labelColor` / `secondaryLabelColor` / `tertiaryLabelColor` | 浮层里的文字 | — |
| `notch.fill` | 纯黑 | 硬件层 | 现值有两处例外：已对准 `white 0.12`（1294），隐形刘海 `black 0.88`（1330、1335）[改值 §6-2] |
| `notch.text` | 白 1.0（标题）；白 0.92（个数） | 刘海上的主文字。刘海永远是深色，不跟随外观 | [现值] 2068、2084；2013 |
| `notch.textSecondary` | 白 0.60 | 次要文字 | 现值 0.55（2070）和 0.6（2088）并存 [改值 §6-10] |
| `notch.stroke` | 白 0.14；增强对比度时 0.5 | 岛的边线 | 0.14 [现值] 932、1314；0.5 [改值 §6-11] |
| `notch.dim` | 黑 0.6 | 岛内压在画面上的标签底 | [现值] 2212 |

规则：
- 落点“已对准”的现状：边线 `accent` 0.9、2 pt，加 `white 0.12` 填充（Notch.swift:1294–1297）；未对准是 1 pt 白 0.14 的边线。改值只有一项：去掉灰色填充，统一成纯黑。之后两者只剩边线的区别，仍不只靠颜色（粗细也不同，HIG Accessibility），越过阈值的触感不变；要先做小样确认一眼分得出来（§6-2）。
- 隐形刘海的 0.88 黑随 §8 问题 2 一起定。

### 4.4 字体

一律用系统字体（SF Pro），数字用等宽数字，刘海上的个数用 SF Pro Rounded。灵动岛的“大号、粗体、用颜色表明身份”放到 Mac 的刘海上，就是字号少而粗。

| 令牌 | 值 | 用在 | 来源 |
|---|---|---|---|
| `notch.title` | 13 semibold | 提醒的主句 | [现值] 2068、2084 |
| `notch.detail` | 11 regular | 提醒的次句 | 现值 10.5（2070）和 11（2088）并存 [改值 §6-10] |
| `notch.count` | min(13, 槽高 − 10) semibold rounded，等宽数字 | 紧凑样式右边的个数 | 字号、字重、rounded 是现值（Notch.swift:2010–2013）；等宽数字 [改值 §6-10] |
| `notch.hint` | 12 medium | 下拉、悬停时的提示 | [现值] 1843 |
| `coach.caption` | 主句 = `notch.title`，次句 = `notch.detail` | 教学旁边那句话。示范画面里 9 pt 的小字属于插画，不算正文 | 现值 13 semibold ＋ 10.5 regular 白 0.55（Notch.swift:2066–2070）；次句和提醒一起统一成 11、0.6 [改值 §6-10] |
| `panel.*` | 沿用 `WindowBrowserTypography`：正文跟随系统字号，次要文字 = 正文 − 2，不小于 10 | 窗口浏览、设置 | [现值] |
| `welcome.*` | 标题 24、导语 14、眉题 12 | 欢迎窗口 | [现值] |

### 4.5 间距

| 令牌 | 值 | 用在 | 来源 |
|---|---|---|---|
| `inset.island` | 14，上下左右一样（非圆形元素按视觉重心算） | 岛内四周边距 | [自定]。HIG 对灵动岛只要求边距均匀、同心；10194 和 HIG 里的 14 pt 是锁屏实时活动的边距。展开已是 14；提醒图标上下 11、左右 14（2059–2061）[改值 §6-4] |
| `inset.panel` | 12 | 窗口浏览面板内边距 | [现值] |
| `margin.float` | 16 | 画中画离屏幕边 | [现值] Core/PiPLayout.swift:34 |
| `margin.edgeHug` | 8 | 贴边的东西：侧拉把手、提示浮窗的夹边、卷帘架离顶 | [现值] |
| `gap.ear` | 0 | 紧凑样式两段紧贴刘海 | 10194；HIG Live Activities |
| `hit.pad` | 6 | 刘海按下的容差；移动超过 6 pt 不算点按 | [现值] Notch.swift:1717–1731 |
| `hysteresis.pan` | 8 | 锁方向前的滞后距离 | [现值] 1778；803 说 iOS 通常 10 |

### 4.6 动效（弹簧）

两个参数：`response`（秒）和阻尼比 ζ。SwiftUI 的 `bounce = 1 − ζ`（ζ ≤ 1）。换成弹簧：mass 1，stiffness `(2π/response)²`，damping `4πζ/response`（WWDC23 10158）。

| 令牌 | response / ζ（bounce） | 带初速度 | 何时用 | 现值出处 | 状态 |
|---|---|---|---|---|---|
| `calm` | 0.34 / 1.0（0） | 否 | 没有动量的变化：悬停、收回、换状态 | Notch.swift:1352 | [现值] |
| `settle` | 0.38 / 1.0（0） | 飞进刘海时带；尺寸变化不带 | 尺寸变化；截图飞进刘海（终点是个口子，不回弹） | FlickMotion.swift:155；Notch.swift:873 | [现值] |
| `expand` | 0.40 / 0.92（0.08） | 否 | 展开一排 | Notch.swift:1351 | [现值]，原则 5 的已知例外 |
| `bloom` | 0.42 / 0.84（0.16） | 否 | 有变化时提醒、教学 | Notch.swift:1350 | [现值]，原则 5 的已知例外 |
| `catch` | 0.40 / 0.80（0.2） | 现在否 → 带拖动速度 | 拖着窗口到刘海时的落点小岛 | Notch.swift:1349 | [改值 §6-10]（速度） |
| `glide` | 0.42 / 0.88（0.12） | 必须 | 甩一下标题栏后的窗口滑行位置；画中画落角沿用同一手感 | FlickMotion.swift:153 | [现值] |
| `flyOut` | 0.38 / 0.90（0.1） | 必须 | 截图从刘海飞出 | Notch.swift:873 | [现值] |
| `pull` | 0.36 / 0.86（0.14） | 必须（夹在 ±30） | 刘海下拉松手弹回 | Notch.swift:1255 | [现值] |
| `pop` | 0.30 / 0.6（0.4） → 0.75（0.25） | 否 | 只给小元素的确认：提示浮窗的终点图标 | GestureHUD.swift:448–455 | [改值 §6-10] |
| `reduced` | 0.25 / 1.0（刘海）；0.30 / 1.0（窗口滑行） | **否** | 减少动态效果时替换以上全部；挪位置改为原处淡出、目标处淡入 | Notch.swift:1348；FlickMotion.swift:157 | [现值] |

- `glide`、`flyOut`、`pull` 是同一类“带动量”的弹簧，可以合并成一个 `momentum`（约 0.4 / 0.88），但这是改值，列为 §6-10 的可选项，试手感后定。
- 启动台另有 14 组弹簧（response 0.3–0.5，bounce 0–0.3）和 11 条贝塞尔曲线，分散在 LaunchpadFolders、LaunchpadView、Launchpad、LaunchpadOpenWith、LaunchpadLibrary 五个文件里。清单不抄行号，用 `rg -n "perceptualDuration|controlPoints" App/Launchpad*.swift` 生成。按 §6-9 改成最接近的令牌；其中 bounce 0.3（LaunchpadFolders.swift:946）超过上限，LaunchpadView.swift:1329 的控制点 1.05 会过冲，两处都属于改值。

规则：
- **上限**：Mac 上 bounce ≤ 0.2，`pop` ≤ 0.25 [自定]。超过 0.4 对界面来说就夸张了（10158）。
- **打断**：一律叠加播放。换目标时用当时的速度作初速度，位置和速度都连续；不同属性可以各自在不同时刻结束（10158）。
- **不等停稳**：后续动作不等 `settlingDuration`，它和感知时长不是一回事（10158）。
- **位移不用贝塞尔曲线描述。**

### 4.7 时序

| 令牌 | 值 | 性质 |
|---|---|---|
| `fade` | 入 0.18 s / 出 0.10 s（ease） | [现值] Notch.swift:1661、1646。岛内内容换层、玻璃显隐 |
| `fade.hud` | 0.12 s | [现值] GestureHUD.swift:362 |
| `dwell.hoverExpand` | 0.12 s | [现值] Notch.swift:1209–1236；以后改成看指针的减速（§6-14） |
| `tap.doubleWindow` | `NSEvent.doubleClickInterval`，最长 0.3 s | [现值] Notch.swift:1058–1078；单击先给按下的反馈，不让用户干等 |
| `drop.confirmHold` | 0.55 s | [现值] Notch.swift:1183–1190 |
| `alert.hold` | 2.6 s | [现值][自定] Notch.swift:1148，不是 Apple 的数字 |
| `alert.throttle` | 同一扇窗口 30 s 内最多提醒一次；一直在变的只标个点 | [自定] |
| `announce.hold` | 1.8 s + 0.05 s × 字数，最长 4.5 s | [现值][自定] Notch.swift:527 |
| `coach.hold` | 6.6 s | [现值][自定] Notch.swift:553 |
| `coach.limit` | 每条最多 3 次，两次之间至少隔 300 s；用过或点掉就不再出现 | [自定] Core/GestureCoach.swift:55–72 |
| `projection.notch` | r = 0.99（故意停得快，不想一碰就拿出来） | [现值] Notch.swift:1247 |
| `projection.pip` | r = 0.998（普通滚动的减速率） | 803；[现值] Core/PiPLayout.swift:94–95 |
| `rubberband` | c = 0.55 | 业界对 UIScrollView 的反推，**不是官方数字** |

### 4.8 触感

| 时刻 | 反馈 | 性质 |
|---|---|---|
| 越过阈值（已对准） | `.alignment` | [现值] Notch.swift:1202；HIG 里 alignment 就是“对齐”，合适 |
| 落点确认（五格里任一格） | `.levelChange` | [现值] Notch.swift:1186（`confirmDrop`，拖到哪一格松手都触发）。HIG 里 levelChange 指“在不同的按压力度档位之间切换”，确认更接近 `.generic`；改不改见 §6-10，试手感后定 |
| 甩一下标题栏收进刘海（`swallow()`，Notch.swift:343、1407–1428）；放回 | 无 | [现值]。加触感属于改值，建议不加：甩进时松手后手指已经离开触控板，飞行结束时的触感基本感觉不到；放回是点一下，点按本身就有触控板的反馈 |
| 声音 | 不加 | [自定] |

### 4.9 辅助设置

每个表面都要有下面几项，缺哪项就是 §6 的差距。

| 设置 | 处理 |
|---|---|
| 减少动态效果 | 用 `reduced` 弹簧，不带速度，不飞行；岛不鼓；示范动画停在最能说明问题的那一帧（HIG Motion） |
| 减少透明度 | 浮层改为不透明 |
| 增强对比度 | 浮层的不透明底加 1 pt `labelColor` 边（§4.2）；`notch.stroke` 升到 0.5 |
| VoiceOver | 每个可操作的东西有名字；提醒和教学同时发播报 |
| 键盘 | 每个刘海手势都有菜单项或快捷键可以代替 |
| 不只靠颜色 | “已对准”“出了问题”同时改边线粗细或图标，不只换颜色 |

### 4.10 改值清单

| 令牌或数值 | 现值 | 目标 | 条目 |
|---|---|---|---|
| `notch.fill`（已对准、隐形刘海） | 已对准：填充白 0.12，边线 `accent` 0.9、2 pt；隐形刘海：黑 0.88 | 纯黑；已对准的边线不变 | §6-2 |
| `island.hug` | 10；12 | `hw.notchBottom`（1710 下 10.7，1440 下 9.0–9.2） | §6-3 |
| `island.shoulder` | 无 | `hw.notchShoulder`，只给悬停、下拉、紧凑样式（§5.1 S3） | §6-3 |
| 岛宽度上限 | 不是一个上限：格子数 = floor((屏宽 − 44) / 132)，岛宽 = max(刘海 + 120, min(格子数, 8) × 132 + 20)（Notch.swift:1168–1171、1301） | 屏宽 − 2 ×（顶角延伸 + e + 8），只在画肩时生效，所以只随 §6-3 的可选项（宽状态画肩）落地；守卫：任何屏宽下格子数不少于现版本 | §6-3 |
| 截图飞进的终点 | 40×26，在刘海底上 2 pt（Notch.swift:337） | `notch.rect` 中心，大小不超过刘海高 | §6-3 |
| 提醒图标 | 30，上下 11、左右 14 | 24，四周 14，高度不变；加高 6 pt 只作备选 | §6-4 |
| 启动台弹簧和贝塞尔曲线 | 14 组 + 11 条 | 引用令牌 | §6-9 |
| `pop` | ζ 0.6 | ζ 0.75（或起始缩放 1.22 → 1.12） | §6-10 |
| `catch` 初速度 | 不带 | 带拖动速度 | §6-10 |
| `glide` / `flyOut` / `pull` 合并 | 三组 | 一个 `momentum`（可选） | §6-10 |
| `notch.textSecondary` | 0.55 与 0.6 | 0.6 | §6-10 |
| `notch.detail` | 10.5 与 11 | 11 | §6-10 |
| `notch.count` | 比例数字 | 等宽数字 | §6-10 |
| 落点确认触感 | `.levelChange` | `.generic`（可选） | §6-10 |
| `notch.stroke`（增强对比度） | 不变 | 0.5 | §6-11 |
| 提示浮窗不透明底的边（增强对比度） | `separatorColor` 1 pt | `labelColor` 1 pt，和窗口浏览一致 | §6-11 |
| 教学台面半径 | 8 | 10 | §6-12 |

---

### 4.11 符号（SF Symbols）

Aaron 2026-10-03：“整个 app 多用 SF Symbols，不要大段大段文字。”规则见 copy-guide 第 7 条。下表的符号名都在这台 Mac 上用
`NSImage(systemSymbolName:)` 核对过（`trackpad` 不存在，用 `rectangle.and.hand.point.up.left`）。设置行的符号放在系统设置那样的圆角色块里，
用 hierarchical 渲染；刘海里用单色白。

| 概念 | 符号 |
| --- | --- |
| 收起窗口 / 展开窗口 | `rectangle.compress.vertical` / `rectangle.expand.vertical` |
| 收进刘海 / 刘海那一排 | `rectangle.topthird.inset.filled` / `macwindow.on.rectangle` |
| 看一眼 | `eye` |
| 置顶 / 取消置顶 | `pin` / `pin.slash` |
| 左半屏 / 右半屏 / 铺满 / 分屏 | `rectangle.lefthalf.inset.filled` / `rectangle.righthalf.inset.filled` / `rectangle.inset.filled` / `rectangle.split.2x1` |
| 网格 / 魔法平铺 / 卷轴 | `rectangle.split.3x3` / `wand.and.stars` / `scroll` |
| 侧拉 / 画中画 | `sidebar.right` / `pip` |
| 启动台 / 调度中心 / 窗口浏览 | `square.grid.3x3` / `rectangle.3.group` / `rectangle.on.rectangle` |
| 快捷键 / 卡住时提示 | `command` / `lightbulb` |
| 实时活动：音乐 / 耳机 / 录音 | `music.note` / `airpods` / `waveform` |
| 番茄钟 / 休息 | `timer` / `cup.and.saucer` |
| 设备：妙控鼠标 / 触控板 / 键盘 / Siri 遥控器 / 手柄 / iPhone | `magicmouse` / `rectangle.and.hand.point.up.left` / `keyboard` / `appletvremote.gen4` / `gamecontroller` / `iphone` |
| 电量 | `battery.75percent`（按实际电量取 0/25/50/75/100） |
| 刷脸解锁 / Touch ID / 隐私 | `viewfinder` / `touchid` / `lock.shield` |
| 指挥模式 / 说话 | 自绘指挥棒（`wand.and.stars` 已经给了魔法平铺）/ `mic.fill` |
| 更多说明 | `info.circle` |

`faceid` 只能指 Apple 的 Face ID，刷脸解锁不用它；`touchid` 只在真的调用 Touch ID 时用。

## 5. 组件

每个组件写五项：结构、令牌、状态与动效、贴合硬件、价值观。

### 5.1 刘海岛（App/Notch.swift）

**结构**：
- 一个形状 = 主体（矩形加连续底角）+ 两个肩。上面叠一条边线（`notch.stroke`，只描两侧和底边）和一层内容。
- 刘海区没有像素，岛在刘海内部怎么画都看不见；但刘海外面必须和硬件轮廓一致，贴着刘海边不能留抗锯齿缝。
- **静止时不画**（Notch.swift:1360 设 `bare`，1548 的 `setBare` 把透明度设成 0），这一点保持。真正会露出来的是两个瞬间：变形开始前把岛亮出来（1382），动画停下后把岛藏回去（1401）。这两个瞬间、下巴、紧凑样式两侧，都必须等于硬件轮廓。
- 现状在这些瞬间已经在半个面板像素以内（每边窄 0.21 px，底边低 0.41 px，底角 r10 对 10.71）。本节落地后，肉眼能看出的变化只有悬停、下拉和紧凑样式两侧多出来的肩。

**状态、令牌和动效**

| 状态 | 大小（现值） | 底角 | 肩 | 弹簧 |
|---|---|---|---|---|
| 静止 | = 刘海，不画 | — | — | — |
| 变形第一帧 / 停稳藏回 | = 刘海 | `island.hug` | 与硬件肩重合 | — |
| 悬停提示 | 左右各 +5、下 +3 | `island.hug` | 紧凑样式上按 S1（肩跟着外移 5，外沿等于现版本悬停外沿）；下巴上按 S3，外扩 | `calm` |
| 下巴 | 刘海宽，下 +8 | `island.hug` | 与硬件肩重合 | `calm` |
| 紧凑样式 | 两侧各 `sideWidth`（最宽 34、最窄 26，Notch.swift:1126–1145） | `island.hug`（现值 12） | S1，从 `sideWidth` 里扣 | `calm` |
| 两指下拉 | 1:1 跟手，带橡皮筋，加宽 ≤20 | 从 `island.hug` 过渡到 22 | S3 | 松手 `pull`，带速度 |
| 落点小岛 | 340×84（Notch.swift:1010） | `island.drop` 22 | 无（S3） | `catch` |
| 提醒 | 宽 max(刘海 + 200, 400)，高 刘海 + 52 | `island.alert` 24 | 无（S3） | `bloom` |
| 教学 | 宽 max(刘海 + 300, 500)，高 刘海 + 84 | `island.alert` 24 | 无（S3） | `bloom` |
| 展开一排 | 宽 ≥ 刘海 + 120，高 刘海 + 142 | `island.expanded` 28；格子 14 | 无（S3） | `expand` |

**肩的硬约束**（帕累托：肩永远不能让用户失去菜单栏空位或点击）：
- **S1 不占新的菜单栏空位。** 紧凑样式里，主体每侧宽 + e ≤ 现在的 `sideWidth`（34 起，按 NotchWatch 量到的空位收窄）。
  - 主体每侧不能少于 26（图标 18 加两边各 4）。扣掉肩之后不够 26，就**不画肩**，形状和现版本一样。
  - 退回下巴的门槛不变（空位 < 26）。**不因为肩多退一次下巴。**
- **S2 不吃点击。** 肩所在区域点击穿透，面板窗口的命中范围不因肩扩大。
  - 推荐做法：两个肩放在单独的子窗口里，`ignoresMouseEvents = true`，面板窗口的矩形不变。
  - 如果肩画在面板窗口里：`reach`（1377–1380）和停稳后的 `settled`（1394 的 `NSIntegralRect`）都要并上 e，否则肩会被窗口边切掉；这时必须实测肩区的点击能落到菜单栏上。
  - 两种都做不到，就不画肩。
- **S3 其它比刘海宽的状态**：主体矩形保持现值，肩在顶边外扩 e。肩只占菜单栏最顶上一个约 e×e 的小角，并且点击穿透。
  - 肩的外沿必须落在 NotchWatch 量到的空位以内，超了这一侧不画肩。NotchWatch 只量刘海两侧各 34 pt（`reach = sideWidth`，Notch.swift:1134–1137；NotchWatch.swift:101–105、184、235–238）。
  - 悬停（每侧 +5）、下拉（每侧最多 +20）加上 e 都在 34 pt 以内，可以画肩。
  - 落点、提醒、教学、展开的肩外沿都在 34 pt 以外（落点每侧超出刘海约 77 pt），那里没有空位数据，**这四个状态不画肩**，顶角保持现在的直角。
  - 以后要给这四个状态画肩，只能在进入状态时把 `reach` 扩到“半宽 + e”再量一次，只在状态切换时量、不常驻。这是 §6-3 的可选项，先做小样。
- **S4 胶囊和隐形刘海不画肩**（`allCorners` 状态、外接屏、Neo、“避开刘海”模式），等 §8 问题 2 定了再说。
- **S5 有肩和没肩之间的切换**：
  - 状态本身决定的（例如从悬停变成展开）不算跳：肩的 e 跟主体用同一个弹簧缩到 0，或从 0 长出来，路径拓扑不变。
  - 空位变化引起的，用 `fade` 过渡；同一次变形中途不切换。这是“不在有肩和直角之间来回跳”的唯一例外。

**实现要点**：
- 肩是两块 `CAShapeLayer`，**用自己的叠加弹簧**，不能只挂主体的 position 弹簧。主体的 position 和 bounds.size 是分开加弹簧的（1614–1627），宽度一变，只挂 position 的肩就会在半路离开主体；肩按 S5 缩到 0 的途中也一样。
  - 横向位移 = `moved.dx ∓ resized.width/2`，纵向位移 = `moved.dy + resized.height/2`；弹簧参数相同，和主体在同一个 transaction 里加。弹簧是线性的，这样中途打断时的叠加也完全一致。
- 主体继续用 CALayer 的 `cornerRadius` + `maskedCorners` + `.continuous`（1579–1597），前提是 §3.3 的离线比较证明 CALayer 的 `.continuous` 和拟合曲线相差 ≤0.5 px；否则换成 `CAShapeLayer` 路径。
- **边线**：白色 0.14 的边线如果一路描到肩上，最后约 1 pt 会贴着屏幕顶边横着走，留下一条亮线。现在靠“上沿多出 2 pt 被裁掉”（1510、1582）避免；肩的描边要在切线变成水平之前结束，或者渐隐收尾。
- **宽度上限** `frame.width − 2 × (顶角延伸 + e + 8)` 保证肩碰不到屏幕顶角，只在画肩时生效。现在的展开一排没有宽度上限，而是按屏宽算格子数：floor((屏宽 − 44) / 132)（1168–1171、1301）。新上限可能让格子变少，所以守卫是“任何屏宽下格子数不少于现版本”，竖放的外接屏、低分辨率模式要在 §7.1 扫一遍屏宽。按 S3 现定，展开不画肩，这条随 §6-3 的可选项一起落地。
- 探针 `islandFillsPanel`（1082–1092）要把肩算进去；另加 `notch-shape` 探针，见 §7。

**不留额头**（原则 9）：
- 提醒时，App 图标或语气符号放进刘海左右的“耳朵”，句子排在刘海下方。
- 展开时，保留紧凑样式里左边图标、右边个数的位置，格子排在下面。
- 刘海两侧不出现空的黑条。这是外观改动，先做小样给 Aaron 看。
- 内部边距四周都是 14：提醒图标现在 30，上下 11、左右 14（2059–2061）。改成相等的做法是图标 30 → 24，上下自然各 14，高度保持刘海 + 52（1309）[改值 §6-4]。把提醒加高 6 pt 也能做到，但会多压 6 pt 内容、偏离 V2，只作备选，要小样对比。

**价值观**：V1 岛从刘海本身长出来，看起来像硬件在动，不另起窗口。V2 顺利时不出声，提醒只说真正要紧的事。V3/V4 岛属于硬件层，永远纯黑，不用玻璃，岛里的内容也不加玻璃。V5 减少动态效果时不鼓、不带速度；增强对比度时边线 0.5；提醒同时发 VoiceOver 播报。差距：不是每个刘海手势都有菜单项或快捷键可以代替，单扇窗口的“收进刘海”（甩一下标题栏、拖到落点）两样都没有，见 §6-19。V6 提醒的文字按 copy-guide 写（“有变化时提醒”“收进刘海 / 放回”）。

### 5.2 收进刘海 / 放回（截图飞行）

- **收进**：从窗口当前位置出发，接着甩出去的速度飞，用 `settle`，不回弹。终点现在是 40×26、在刘海底上 2 pt（Notch.swift:337），改为 `notch.rect` 中心、大小不超过刘海高 [改值 §6-3]。最后一段被刘海自然挡住；隐形刘海才淡出。
- **放回**：沿同一条路出来，用 `flyOut`（0.38 / 0.9），圆角 10。
- **收下那一刻**：岛鼓一下（`swallow()`，1407–1428），没有触感。拖到落点松手时的 `.levelChange` 是落点确认给的，不是收下给的（§4.8）；甩进来的这一下建议也不加。
- **减少动态效果**：不飞，原处淡出、目标处淡入（Motion.swift）。
- **价值观**：V1 这是整套设计里最像灵动岛“嗖地飞进去”的一段，进出同一条路，一看就懂。V2 飞行只在动作发生时出现。V5 减少动态效果有对应处理。差距：菜单和快捷键里只有“全部收进刘海”（⌃⌘H，再按一次放回），单扇的“收进刘海”没有菜单项，也没有快捷键（§6-19）。V6 说法固定为“收进刘海 / 放回”，不说“塞进”“收纳”。

### 5.3 隐形刘海（外接屏、Neo、“避开刘海”模式）

- 现状：菜单栏正中一颗胶囊，80 宽，上下各缩 3，`capsule` 圆角，0.88 黑（Notch.swift:1326–1330）；放不下时退成 72×12、r6 的下巴（1333–1335）。
- 槽位（瞄准、放回起点、启动台起点）是 190 宽、高 `max(24, 菜单栏高)`（111–115）。槽位是点击目标，不是外观，保持 190。
- direction.md 已定“没有刘海的屏幕保持看不见的顶部正中”。它打开时长什么样（浮着的胶囊，还是从顶边长出来的形状）见 §8 问题 2；定下来之前外观不动。
- **价值观**：V1 不在没有刘海的屏上假装有硬件（原则 1 反过来也成立：没有硬件，就不画硬件的形状）。V5 胶囊和槽位的 VoiceOver 名称与真刘海一致。V6 这块屏上“收进刘海”怎么说，随问题 2 一起补进 copy-guide。

### 5.4 教学提示（App/NotchCoach.swift、Core/GestureCoach.swift）

- **结构**：岛进入教学状态，里面一段手势示范加一句 `coach.caption`。
- **令牌**：台面半径 = `island.alert − inset.island` = 10，与岛同心（现在 8，NotchCoach.swift:17）[改值 §6-12]。示范里的小刘海画成缩小版刘海的形状（带肩和底角），不画四角全圆的 28×7 小药丸（158–165）。
- **时机**：只在卡住时出现，受 `coach.limit` 约束，规则表见 [stuck-habits.md](stuck-habits.md)。成功播报“收进了 N 扇”（Notch.swift:614–616）也算进次数限制。
- **动效**：`bloom` 展开，示范循环播放；减少动态效果时停在关键帧。
- **价值观**：V1 教的是 Mac 的做法，不是把旧系统搬过来（direction.md）。V2 顺利时不开口。V5 同时发 VoiceOver 播报；示范不只靠动画，旁边一定有一句话。V6 触控板手势说“两指”“三指”；组合键符号第一次出现时说明，例如“⌃（Control）”；按 Apple Style Guide 写组合键顺序。

### 5.5 侧拉（App/SlideOver.swift、App/SlideOverChrome.swift、App/SlideOverDropHint.swift）

- **结构**：窗口外面那一圈（玻璃边框）、角上那段弧（把手）、收到屏幕边外时露出的一小片。界面上不给它们起名字（copy-guide）。
- **令牌**：那一圈的外半径 = 窗口实测圆角 + 10（238，同心公式不变）。路径改成连续曲线，现在是圆弧（239–240）。
- **材质**：现在是自绘的灰色“玻璃”（252–268），深浅色只在挂上时取一次（57）。改为 macOS 26+ `NSGlassEffectView`，边上那一小片开 `effectIsInteractive`（27）；14/15 用 `NSVisualEffectView`；持续监听外观和辅助设置。
- **状态**：挂着、拖动、收到边外、拉回、换边。松手后按投影落点决定去向，动效 `glide`。
- **贴合硬件**：只在 `visibleFrame` 伸到顶边时按 §4.1 规则 3 做包含测试，不通过就把把手往下挪，不改半径。
- **价值观**：V1 侧拉是从 iPad 搬来的，是否默认开见 §8 问题 4。V3/V4 这是现在最明显的“自己仿玻璃”，换成系统玻璃后，减少透明度、增强对比度自动生效。V5 把手有无障碍标签（373–374），保持。V6 界面只说“侧拉当前窗口 / 收起侧拉的窗口 / 拉出侧拉的窗口 / 退出侧拉”。

### 5.6 画中画（App/PictureInPicture.swift、App/PictureInPictureViews.swift、Core/PiPLayout.swift）

- **结构**：内容层画面；按钮直接压在画面上，加渐变暗层，不用材质（PictureInPictureViews.swift:54、67–105），保持；藏起来后的小标签“拿回画中画”（Core/PiPLayout.swift:109 的 `tabFrame`）。
- **令牌**：`system.card` 12，连续曲线（PictureInPictureViews.swift:26）；离边 `margin.float` 16；落角用 `projection.pip` 和 `glide`。
- **贴合硬件**：只在 `visibleFrame` 伸到顶边时做包含测试。小标签要挪出顶角弧区和刘海那一列。半径不变，底部是直角，不用处理。
- **价值观**：V1 画中画在 Mac 上是视频的功能，“任意窗口画中画”是从 iPad 搬来的，见 §8 问题 4。V2 画面属于内容层，不加材质；按钮下面只有一层暗层，不另加玻璃条。V3 画中画里没有玻璃。V5 每个按钮有名字；“回到原处 / 关掉画中画”有菜单项。

### 5.7 启动台（App/Launchpad*.swift）

- **结构**：整屏面板（在菜单栏下面，层级 dock−1，屏幕圆角由硬件裁）、图标、文件夹、App 资料库。
- **搜索在哪**：主屏幕和负一屏共用底部正中一枚玻璃胶囊（iPad 的排法，Aaron 2026-10-01 给的 iPadOS 27 参照图），
  落在程序坞上面，页码点压在它上面；翻到 App 资料库时同一枚挪到顶端、放大成资料库搜索。
  放底部也避开从顶部正中长出来的刘海（`LaunchpadView.layoutPill`，钉在 `tests/LaunchpadViewTests.swift`）。
- **负一屏**：照 iPad 排——左边日期/时钟与当月日历，右边实时活动与四个快捷方式；不带自己的搜索小组件
  （`LaunchpadToday.swift`，出图看 `tests/run-launchpad-visual-fixture.sh`）。
- **从刘海长出来 / 收回刘海**：遮罩路径改用 `notchPath(body:)`，从精确的刘海轮廓（带肩、硬件底角）长到整屏，拓扑固定，可以直接做路径插值（LaunchpadOpenWith.swift:119–162）。中间态不再四角全圆，顶边始终带肩；终点是整屏矩形，顶角交给硬件去裁。
- **拖图标到“收进刘海”的高亮**：改成刘海长大后的轮廓，不再是四角 r18 的圆块（LaunchpadView.swift:1371–1410；LaunchpadController.swift:152–156；Core/LaunchpadModel.swift:149–150）。命中范围不变。
- **令牌**：图标后的玻璃块圆角 = 图标圆角 + 间距（LaunchpadLibrary.swift:113，已同心）。弹簧和贝塞尔曲线改成令牌（§4.6）。
- **价值观**：V1 启动台用了 Apple 的功能名，也是从旧系统搬回来的，是否默认开、怎么说，见 §8 问题 4。V3/V4 图标后的块、文件夹底板、App 资料库底板都是自己仿的玻璃：`LaunchpadGlass` 用 CIGaussianBlur、提饱和度、蒙一层白（Launchpad.swift:215–260）。代码注释把它定为“内容层的磨砂”（244），算内容层还是仿玻璃，在 §6-8 定；换系统材质时，同心公式保持不变。这几块不能再叠在另一层玻璃上。V5 已响应减少透明度、增强对比度（Launchpad.swift、LaunchpadFolders.swift），保持。V6 词汇按 copy-guide（主屏幕、App 资料库、文件夹、编辑主屏幕）。

### 5.8 手势提示浮窗（Overlay/GestureHUD.swift）

- **结构**：起点图标、1:1 跟手的进度条（填充方向和手指一致）、终点图标，外面一层浮层材质。出现在手势发生的窗口旁边。
- **令牌**：290×63（129），固定圆角 24（297）。注释里的“胶囊”删掉（GestureHUD.swift:2、295）：24 ≠ 31.5，照本机 macOS 27 音量浮窗实测。离边 `margin.edgeHug`（257–268）。
- **状态**：跟手中；越过阈值时终点变 `accent` 并弹一下，同时给 `.alignment`；完成。
- **动效**：终点弹一下用 `pop` [改值 §6-10]；显隐 `fade.hud`。
- **价值观**：V3/V4 已用系统玻璃（macOS 26+ Regular，14/15 `.hudWindow`）。V5 减少透明度时换成不透明底（463–490），已做到；不透明底的边线平时 0.5 pt、增强对比度时 1 pt，颜色是 `separatorColor`（538–539），改成 `labelColor`，和窗口浏览一致 [改值 §6-11]。越过阈值同时变色、弹一下、给触感，不只靠颜色。

### 5.9 窗口浏览面板（WindowBrowser/*）

- **结构**：一个浮层面板，里面是卡片、行、操作条。
- **令牌**：面板 `system.window` 13；卡片和行 `system.item` 8（严格同心会退成 1，这里有意取兜底值）；内边距 `inset.panel` 12；字体 `panel.*`。
- **材质**：已经符合 §4.2（WindowBrowserMaterial.swift、WindowBrowserContentView.swift），保持。
- **贴合硬件**：面板从 Dock 旁边出来，离顶边远，不涉及刘海和顶角。
- **价值观**：V1 停在 Dock 图标上看窗口，是 Mac 用户熟悉的位置。V3/V4 已用系统玻璃，卡片里不再叠玻璃。V5 正文跟随系统字号。V6 功能名只叫“窗口浏览”，菜单项叫“选择窗口…”。

### 5.10 看一眼、卷帘条、带到每张桌面

- **看一眼的卡片**（Overlay/GlancePanel.swift）：内容层，不加材质；圆角 = 源窗口实测圆角（App/Glance.swift:455）；阴影沿卡片路径画。有画面时不加底和边，代码注释写明原因：窗口画面自带边缘，多一层会在角上露出月牙；只有拿不到画面时才有底色和细边（GlancePanel.swift:78、87、204–211）。
- **卷帘条**：`SystemCornerRadius.surfaceRadius(forHeight:)`，不超过高度的一半。
- **带到每张桌面的卷帘条**（Core/CarryShelfLayout.swift:23–26；App/Carry.swift:49–52）：在右上角，离边 10、离顶 8，圆角 9。`visibleFrame` 伸到顶时做包含测试，不通过才往下挪；半径保持 9。
- **价值观**：V1 收起窗口是 WindowShade 的来历，用的是 Mac 标题栏的样子（“跟原来一样 / 统一标题栏”）。V2 看一眼移开就收回。V5 看一眼拿不到实时画面时明说“收起时的画面”或“不是实时画面”。

### 5.11 欢迎窗口（App/Welcome.swift）

- **结构**：迷你桌面舞台，每一步一段循环演示。
- **贴合硬件**：迷你 Mac 按这台 Mac 的 `DisplayShape` 等比例画：
  - 舞台天圆地方（现在四角都是 r12，202）；
  - 刘海按本机算，不写死比例：Air 13 和 Pro 14 占屏宽 12.2%，Air 15 10.8%，Pro 16 10.7%；高宽比 Air 0.18、Pro 0.173；带肩（现在画成 15%、没有肩，328–339）；
  - Neo 画成顶部圆角、没有刘海；没有内建屏的 Mac 画成直角屏加隐形刘海。
- **内容**：按 direction.md 先问一句“你之前常用哪个？”（Windows / iPad / 一直用 Mac）。步数见 §8 问题 3。按钮只用“继续 / 上一步 / 跳过 / 开始使用”，没授权时“稍后再说”。
- **动效**：示范用 `calm` / `glide`；减少动态效果时停在关键帧。
- **价值观**：V1/V6 第 5 页标题“刘海是一个入口”替 Apple 的硬件下定义，第 6 页“像 iPad 一样多任务”和“教 Mac 的做法”相反（Welcome.swift:17–18；ssc.md §4），两个标题都要改。V2 七页、十几个手势太多，交给刘海在卡住时教。V5 每段演示旁边有一句话，VoiceOver 能读到。V6 标题说用户得到什么，不列功能。

### 5.12 App 图标（assets/app-icon/WindowShade.icns，build.sh:127）

- 现在的图标画死了圆角、阴影和高光，照搬了窗口和红绿灯。
- 按 HIG App Icons 重做：用 Icon Composer 分层，不自带高光和阴影，不照搬界面控件，让系统给出浅色、深色、着色、透明几种外观。
- **价值观**：V1 放在 Dock 和访达里要像一个 Mac App。V4 高光和折射交给系统。

### 5.13 官网与宣传片（App 以外）

- 舞台天圆地方；刘海带肩，按一台参照机型的真实比例画（例如 MacBook Air 15″：刘海占屏宽 10.8%，高宽比 0.18）。比例数字只写在代码注释里；页面和图片的替代文字最多写“按 15 英寸 MacBook Air 的比例画”（copy-guide 第 1、5 条：几何和比例数字不进用户文字）。
- 现在刘海画大了（site/style.css:582 的 `.tnotch` 宽 17%；646 的 `.island` 高宽比约 0.37），没有肩（site/island.js:36–41；promo/）。
- **价值观**：V1 画出来的 Mac 要和用户手里的一样。V6 宣传语不替 Apple 的硬件下定义，不模仿 Apple 的口号（ssc.md §4），候选由 Aaron 挑。

---

## 6. 与现状的差距

按影响从大到小排。每一条都写明帕累托守卫：做不到守卫，就不合入。

### 落代码进度（2026-09-30，Codex）

已经落到产品里的（都是文档里已定的值，不涉及要 Aaron 拍板的概念）：

- **§6-10 改值清单的四项**：`pop` 阻尼比 0.6 → 0.75（`Overlay/GestureHUD.swift`）；
  `notch.textSecondary` 0.55 → 0.6、`notch.detail` 10.5 → 11（教学提醒那一行，`Notch.swift`）；
  `notch.count` 改成等宽数字（还是圆体，`NSFont.monospacedDigitSystemFont` + `.rounded`）。
- **§6-11 增强对比度**：岛和内容之间那条细边的透明度跟随设置（关 0.14 / 开 0.5，`NotchPanel.hairline`），
  并且刘海现在也监听系统外观变化（`AppDelegate.systemAppearanceOptionsChanged` → `notch.refreshAppearance()`），
  开关一拨就重画；提示浮窗的边从 `separatorColor` 改成 `labelColor`，和窗口浏览一致。
- **§6-17 注释更正**：GestureHUD 不再叫「胶囊」（写明固定圆角 24）；橡皮筋的 c = 0.55 不再写成「Apple 的」。
- **§6-19 单扇「收进刘海」**：菜单栏新增一条只对当前窗口的「收进刘海」（`MenuBarController`），
  快捷键默认不占、可在设置 → 快捷键 → 排布当前窗口里自己录（`GlobalShortcut.tuckCurrent`），
  事件分派在 `EventTap`，动作是 `NotchController.tuckFocused()`（走和拖放、甩标题栏同一条 `tuck` 路径；
  对话框、浮动面板、全屏窗口收不进去时在刘海上说一声）。整批那条（⌃⌘H）行为不变。
- **§6-5 动效令牌收拢**（2026-10-01）：§4.6 那张表收进 `Core/FlickMotion.swift` 的 `MotionSpring`
  （App 里叫 `Motion.Spring`，别名），刘海、截图飞行、窗口滑行、提示浮窗的调用点改成引用令牌，
  参数逐字不变；对照测试 `tests/MotionTokensTests.swift` + `tests/run-motion-tokens-tests.sh` 逐项比对。
  令牌放在 Core 是因为只编译 `FlickMotion.swift` 的单测也要能用（放在 App 层曾让 9 个 runner 编不过）。

还等视觉确认的：上面这几项的眼睛检查（要和改前的截屏对比）——2026-09-30 那次屏幕锁着，
探针截图要等解锁后补；`--settings-shots` / `--notch-shape` / `--gesture` 都能出图。

仍未做：§6-1 之外的几何（§6-2/3/4 要先做小样）、§6-7/8 玻璃审计、
§6-13 欢迎窗口标题（要 Aaron 挑）、§6-16 App 图标（要 Aaron 认概念）。

**1. 建 `DisplayShape`（地基，不改外观）**
- 改什么：来源顺序、`bezelPath` 守卫（问题 1 定之前只在探针里用）、机型表（按 px 存）、pxPerPt 换算；加 `hardware-fit` dump 探针；离线比较 CALayer 与 SwiftUI 的 `.continuous`。
- 文件：新文件 `Window/DisplayShape.swift`、`Private/ScreenBezel.swift`；`Overlay/SystemAppearance.swift:189–209` 增加硬件令牌。
- 守卫：任何表面的几何都不变；只在屏幕参数变化时计算，不增加常驻耗电。

**2. “已对准”去掉灰色填充，统一纯黑**
- 现状：已对准 = 边线 `accent` 0.9、2 pt，加 `white 0.12` 填充（Notch.swift:1294–1297）。
- 改什么：只去掉灰色填充，硬件层统一纯黑；边线不变。隐形刘海的 0.88 黑（1330、1335）随问题 2。
- 守卫：去掉填充后，已对准和未对准只剩边线的区别（1 pt 淡白对 2 pt `accent`），必须先做小样确认仍然一眼分得出来，否则不合入；越过阈值的触感不变。

**3. 刘海岛贴合硬件**
- 改什么：第一帧、下巴、紧凑两侧等于硬件轮廓；`island.hug` 替换写死的 10 和 12；悬停、下拉、紧凑样式挂上肩（自己的叠加弹簧，S1–S5）；肩的描边在水平前收尾；截图飞进的终点跟刘海走；探针把肩算进去。
- 可选项（先做小样）：落点、提醒、教学、展开也画肩。前提是进入这些状态时把 `reach` 扩到“半宽 + e”再量一次空位，只在状态切换时量，不常驻；同时启用宽度上限，守卫“任何屏宽下格子数不少于现版本”。
- 文件：App/Notch.swift 1271–1345、1360–1401、1524–1597、1600–1633，探针 1082–1092，飞行 337、416、874；可选项另涉及 Notch.swift:1134–1137、1168–1171 和 App/NotchWatch.swift。
- 守卫：`source == .fallback` 时逐一等于现版本；退回下巴的次数不增加（S1）；菜单栏的点击不减少（S2）；打断、跟手、内容裁剪回归通过。

**4. 提醒和展开不留额头（先做小样）**
- 改什么：内容绕着刘海排；展开时保留紧凑样式的元素位置；提醒图标 30 → 24，四周 14，高度不变。加高 6 pt 只作备选（会多压 6 pt 内容），要小样对比。
- 文件：Notch.swift:1299–1319、1891、2053–2061。
- 守卫：文字截断不比现在多；提醒停留时长和节流不变。

**5. 动效令牌收拢（第一轮只搬现值）**
- 改什么：扩写 Motion.swift，把刘海、截图飞行、窗口滑行、提示浮窗的参数改成引用令牌。
- 文件：App/Motion.swift；Notch.swift:1255、1347–1353、873–874；Core/FlickMotion.swift:153–157；Overlay/GestureHUD.swift:448–455。
- 守卫：每个调用点的 response、ζ、初速度和改之前逐字相等（写一条对照测试）。改值另走 §6-10。

**6. 刘海手势全程跟手、可以改方向**
- 改什么：横滑时岛朝手指方向伸长、露出下一个 App；上推时收紧，带橡皮筋；捏合时随手指缩放。下拉、上推、横滑放进同一个二维空间，按松手时的投影落点决定去向（803）。
- 文件：Notch.swift:1717–1814。
- 守卫：同样的手势在同样的阈值下得到同样的结果；`hysteresis.pan`、`hit.pad` 不变；取消时一定弹回。

**7. 侧拉的玻璃边框**
- 改什么：连续曲线路径；系统材质；持续监听外观和辅助设置；边上那一小片按包含测试挪位置。
- 文件：App/SlideOverChrome.swift:57、188、238–268、430–457；App/SlideOver.swift:611–617、904–908。
- 守卫：把手的命中区和位置不变；14/15 上不比现在差。

**8. 玻璃用量逐个过一遍（V3、V4）**
- 改什么：列出所有玻璃和自绘材质，检查“只在控件层”“不叠玻璃”“不自己仿”；合盖 / 倾斜效果按 direction.md 默认关。
- 文件：用 `NSGlassEffectView` 的有 Overlay/SystemAppearance.swift、Overlay/GestureHUD.swift、WindowBrowser/WindowBrowserMaterial.swift、WindowBrowser/WindowBrowserContentView.swift、App/Launchpad.swift；自绘的有 App/SlideOverChrome.swift、App/Launchpad.swift:215–260（`LaunchpadGlass`，用在 LaunchpadFolders.swift:26、Launchpad.swift:304 和 466、LaunchpadLibrary.swift:111、LaunchpadToday.swift:65；遮罩另用它的 `filters`，LaunchpadFolders.swift:508、LaunchpadView.swift:145）；合盖和倾斜在 Effects/（FoldRenderer.swift、LidAngleSource.swift、DuoController.swift）。
- 守卫：只删叠层和仿造，不删功能；设置里还能打开合盖 / 倾斜效果。

**9. 启动台从刘海长出**
- 改什么：遮罩和落点高亮都改用刘海轮廓；弹簧和贝塞尔曲线改成令牌（bounce 0.3 和控制点 1.05 的过冲属于改值）。
- 文件：App/LaunchpadOpenWith.swift:119–162；App/LaunchpadController.swift:152–160、243–245；App/LaunchpadView.swift:1371–1410。弹簧和曲线共 14 组 + 11 条，清单用 `rg -n "perceptualDuration|controlPoints" App/Launchpad*.swift` 生成，不抄行号。
- 守卫：槽位和命中范围不变（LaunchpadController.swift:153 用 `slotRect`）；打开、收回的感知时长不变长。

**10. 改值清单（§4.10 里除 §6-2、3、4、11、12 以外的项）**
- 改什么：`pop` ζ 0.6 → 0.75；`catch` 带拖动速度；`notch.textSecondary` 统一 0.6；`notch.detail` 统一 11（含教学的次句）；`notch.count` 用等宽数字；可选：`glide` / `flyOut` / `pull` 合并，落点确认触感改 `.generic`。
- 文件：GestureHUD.swift:448–455；Notch.swift:1186、1349、2010–2013、2070。
- 守卫：每项单独提交，单独对比手感；可选项手感不更好就不改。

**11. 增强对比度**
- 改什么：`notch.stroke` 跟随设置升到 0.5，并持续监听；提示浮窗不透明底的边从 `separatorColor` 改成 `labelColor`，和窗口浏览一致。
- 文件：Notch.swift:932、1297、1314；Overlay/GestureHUD.swift:538–539。
- 守卫：设置关着时像素不变。

**12. 教学**
- 改什么：台面半径 8 → 10；示范里画刘海形；成功播报算进次数限制。
- 文件：App/NotchCoach.swift:17、158–165；Notch.swift:614–616、2053；Core/GestureCoach.swift:55–72。
- 守卫：`coach.limit` 的语义不变，只是多算一种播报。

**13. 欢迎窗口**（问题 3）
- 改什么：迷你 Mac 按真实比例画、天圆地方；步数按问题 3；改掉第 5 页“刘海是一个入口”和第 6 页“像 iPad 一样多任务”两个标题，候选由 Aaron 挑。
- 文件：App/Welcome.swift:12、17–18、202、328–339、542–695。
- 守卫：授权流程、菜单里“欢迎使用 WindowShade…”能随时再打开，这两点不变。

**14. 意图判断**
- 改什么：悬停展开从 0.12 s 计时器改成看指针在刘海上的减速；单击不等双击间隔，先给按下的反馈。
- 文件：Notch.swift:1058–1078、1209–1236。
- 守卫：误展开不增加（划过刘海不展开），双击仍然能用。

**15. 贴角的表面：包含测试探针**
- 改什么：写一个几何断言探针，覆盖画中画标签、侧拉把手、带到每张桌面的卷帘条、提示浮窗、悬停预览、专注时的卷帘架；只修真正不通过的，只挪位置。
- 文件：Core/PiPLayout.swift:34、69–109（标签“拿回画中画”是 109 的 `tabFrame`）；App/SlideOver.swift:904–908；Core/CarryShelfLayout.swift:23–26；Overlay/GestureHUD.swift:257–268；App/HoverPreview.swift；App/FocusSession.swift。
- 守卫：菜单栏显示时（绝大多数情况）位置和半径逐一不变。按现有边距估算，卷帘架、提示浮窗、画中画在本机都不会被切。

**16. App 图标**
- 改什么：按 HIG App Icons 用 Icon Composer 分层重做。
- 文件：assets/app-icon/WindowShade.icns；prototype/build.sh:127。
- 守卫：旧系统（14/15）上仍有图标。

**17. 注释更正**
- 改什么：GestureHUD 的“胶囊”注释删掉，写明固定圆角 24（GestureHUD.swift:2、295）；橡皮筋 c=0.55 不写成“Apple 的”（Core/FlickMotion.swift:253–259，Notch.swift 1260 附近）。
- 守卫：只改注释。

**18. 官网与宣传片**
- 改什么：天圆地方，刘海按参照机型的真实比例、带肩。
- 文件：site/style.css:582、646；site/island.js:36–41；promo/。
- 守卫：单独处理，不和 App 改动一起发。

**19. 单扇“收进刘海”的键盘入口（V5）**
- 现状：菜单和快捷键里只有“全部收进刘海”（⌃⌘H，再按一次放回）。单扇窗口的“收进刘海”只能甩一下标题栏或拖到落点，没有菜单项，也没有快捷键。
- 改什么：加一个对当前窗口的“收进刘海”菜单项；快捷键默认不占，设置里可以录，和 `GlobalShortcuts` 里默认不占键的那些排法同一做法。
- 文件：App/MenuBarController.swift:140；App/GlobalShortcuts.swift:30、112、152；App/Preferences.swift。
- 守卫：不新占默认快捷键；“全部收进刘海”的行为和 ⌃⌘H 不变；菜单文字按 copy-guide 用“收进刘海”。

---

## 7. 验收

**7.1 纯几何测试**（不碰屏幕，用 dump 下来的 `bezelPath` 和表 A、表 B 当夹具）
- 在 1710 和 1440 两个模式下，把每个岛状态栅格化到面板 px：
  - 岛包住整个刘海；
  - 刘海外面，与“硬件轮廓按目标长大”的期望掩码只在 1 px 抗锯齿带里有差异；
  - 第一帧、下巴、紧凑两侧等于硬件轮廓；
  - 岛接触顶边的范围：带肩的状态恰好从左肩起点到右肩终点，不带肩的状态等于主体宽。
- `source == .fallback` 时，各状态的矩形和半径与旧常量逐一相等。
- **S1**：把空位从 0 扫到 40 pt，紧凑样式的外沿不超过现版本，退回下巴的门槛不变。
- **S2**：肩区不在面板窗口的命中范围里。
- **S3**：落点、提醒、教学、展开不画肩；悬停、下拉的肩外沿在量到的空位以内。
- **展开的格子数**（宽度上限落地时）：屏宽从竖放外接屏的窄值扫到最宽，含低分辨率模式，每个屏宽下格子数不少于现版本的 floor((屏宽 − 44) / 132)。
- **曲线**：`cornerCurveExpansionFactor(.continuous)` = 1.5287；CALayer 与 SwiftUI 的 `.continuous` 渲染到 `CGContext` 后相差 ≤0.1 px；刘海底角和肩对 `bezelPath` ≤0.3 px。顶角先对 `bezelPath` 直接拟合 `.continuous`，按实测定阈值；三角不等式给的上界约 0.85 px，不能拿左上角的 0.65 px 当阈值，否则右上角可能误报。
- **包含测试**：§6-15 的各表面在“自动隐藏菜单栏”下都在屏幕轮廓内，并避开刘海那一列。

**7.2 截屏检查**（ScreenCaptureKit，用现有的 ScreenCaptureBridge）
- 只查轮廓内侧几点宽的一圈，排除内容和边线，要求纯黑。有格子和文字时，“岛内全部 (0,0,0)”必然失败，不能这么查。
- 在岛那一侧，硬件轮廓外 2 px 的环带里不能有非黑像素。这一条专门抓灰色细缝。
- 逐像素结论只在 2× 模式下成立；1710 模式只要求抗锯齿带 ≤1 px。

**7.3 物理校准**（请 Aaron 亲眼看，一次性）
- 切到 1440×932，全屏画一张校准图：面板第 1282–1286 列、第 1594–1598 列放 1 px 交替色，第 54–58 行同样处理；肩和屏幕顶角画斜向阶梯。
- Aaron 用放大镜或手机微距看硬件边缘落在哪一列、哪一行，拍照留档。
- 确认之前，`bezelPath` 的数值只标 [系统]，不标“实测”。所有自动测试都拿 `bezelPath` 当标准，它们只能证明“和 `bezelPath` 一致”，证明不了“和实物一致”；这一步补的就是这个。
- **黑色是否一样深不作为通过条件**：IPS 有背光漏光和泛光，mini-LED 有光晕，只记录，不判不通过。

**7.4 亲眼过一遍**
- 浅色壁纸，1710、1440 和最大“更多空间”三个模式，把每个岛状态过一遍：刘海边有没有灰线或亮边，肩上有没有台阶，岛的底角和刘海底角是不是一家，屏幕顶边上有没有边线留下的亮线。
- 在每个带肩的状态下，点肩旁边的菜单栏，菜单要照常打开（S2）。
- 自动隐藏菜单栏时看四个角；Studio Display 上看隐形刘海的位置。

**7.5 辅助设置与文案**
- 每个改过的表面，在减少动态效果、减少透明度、增强对比度下各看一次，VoiceOver 读一遍。
- 新增和改动的用户可见字符串按 copy-guide 的自检四问过一遍；内部叫法（岛、肩、硬件层、隐形刘海）不出现在界面上。

**7.6 能耗**
- 没有新增定时器；`DisplayShape` 只在屏幕参数变化时重算，在 Diagnostics 里计数核对。

---

## 8. 已定（Aaron，2026-09-29）

1. 读私有的 `NSScreen.bezelPath`，带守卫和校验，失败退回机型表。
2. 没有刘海的屏：浮着的胶囊（选项一）。
3. 欢迎窗口缩成三步。
4. 搬来的行为逐项定，结果见 [direction.md](direction.md)“设计系统与‘少做’的逐项决定”：启动台、侧拉、画中画、卷轴、魔法平铺、晃一晃保持默认开；
   ⌃⌘ 默认快捷键全部不占（老用户保留正在用的）；“让开这个 App”加守卫并对换机的人默认关；变化提醒只加“让开系统”；主动推销类的提示删掉。

---

## 9. 出处

**Apple 讲座**
- WWDC18 803 Designing Fluid Interfaces：https://developer.apple.com/videos/play/wwdc2018/803/
- Designing for iPhone X（fall2017 801）：https://developer.apple.com/videos/play/fall2017/801/
- WWDC23 10158 Animate with springs：https://developer.apple.com/videos/play/wwdc2023/10158/
- WWDC23 10194 Design dynamic Live Activities：https://developer.apple.com/videos/play/wwdc2023/10194/
- WWDC25 219 Meet Liquid Glass：https://developer.apple.com/videos/play/wwdc2025/219/
- WWDC25 356 Get to know the new design system：https://developer.apple.com/videos/play/wwdc2025/356/
- WWDC25 310 Build an AppKit app with the new design：https://developer.apple.com/videos/play/wwdc2025/310/

**HIG 与开发者文档**
- Materials：https://developer.apple.com/design/human-interface-guidelines/materials
- Motion：https://developer.apple.com/design/human-interface-guidelines/motion
- Playing haptics：https://developer.apple.com/design/human-interface-guidelines/playing-haptics
- Live Activities：https://developer.apple.com/design/human-interface-guidelines/live-activities
- Layout：https://developer.apple.com/design/human-interface-guidelines/layout
- Accessibility：https://developer.apple.com/design/human-interface-guidelines/accessibility
- Gestures：https://developer.apple.com/design/human-interface-guidelines/gestures
- Writing：https://developer.apple.com/design/human-interface-guidelines/writing
- App icons：https://developer.apple.com/design/human-interface-guidelines/app-icons
- Adopting Liquid Glass：https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass
- `safeAreaInsets`：https://developer.apple.com/documentation/appkit/nsscreen/safeareainsets
- `auxiliaryTopLeftArea`：https://developer.apple.com/documentation/AppKit/NSScreen/auxiliaryTopLeftArea-uglc
- Design Resources（Product Bezels）：https://developer.apple.com/design/resources/
- Accessory Design Guidelines R31 与尺寸图：https://developer.apple.com/accessories/dimensional-drawings/

**Apple 规格与新闻**
- MacBook Air 规格：https://www.apple.com/macbook-air/specs/ ；MacBook Air 15″ M5：https://support.apple.com/en-us/126321
- MacBook Pro 规格：https://www.apple.com/macbook-pro/specs/
- MacBook Neo 规格：https://www.apple.com/macbook-neo/specs/ ；https://support.apple.com/en-us/126322
- 新设计发布稿（2025-06）：https://www.apple.com/newsroom/2025/06/apple-introduces-a-delightful-and-elegant-new-software-design/
- iPhone 14 Pro 发布稿（灵动岛，2022-09-07）：https://www.apple.com/newsroom/2022/09/apple-debuts-iphone-14-pro-and-iphone-14-pro-max/
- 无障碍：https://www.apple.com/accessibility/

**测量与审查**（会话 scratchpad，未入库）
- 图稿测量：`ds/wf-bezel.md`、`ds/all.txt`、`ds/summary.json`
- 配件准则：`ds/wf-adg.md`
- 参考案例：`ds/wf-cases.md`
- 本机系统读数：`hwfit/getters_out.txt`、`hwfit/screens_out.txt`、`hwfit/wf-hw.md`、`hwfit/wf-api.md`
- 代码审计与硬件贴合方案、审查：`hwfit/wf-code.md`、`hwfit/wf-design.md`、`hwfit/wf-critique.md`、`ds/wf-review.md`
