# H4 评估：标题栏定位与缩略图裁剪，Vision 对像素启发式

日期 2026-10-16。规格 H4（[product-reshape-spec.md](product-reshape-spec.md)）：标题栏定位换 `VNDetectRectangles`／`VNRecognizeText`，缩略图裁剪用 `VNGenerateAttentionBasedSaliency`，验收是「同一批窗口比较启发式 vs Vision」。本篇只测量，没有改任何产品行为。

**结论：不采用。** 在一批真实窗口上，Vision 给出的标题栏带高比现有启发式更不准，也更慢；显著性裁剪几乎总是返回整张图，没有裁剪价值。详见末节。

## 一、现有的像素启发式在哪里、决定什么

| 位置 | 决定什么 | 实际是否在跑 |
| --- | --- | --- |
| `prototype/Capture/PreviewRenderer.swift:98` `preciseVisualChromeHeight` | 从截图顶部 130pt 里找浅色控件行，推出「刚好包住顶部控件」的标题栏裁切高度 | **实际上不会运行**，见下 |
| `PreviewRenderer.swift:230` `nativeTitleStripLooksBroken` | 裁出的条是否「坏了」（alpha／材质覆盖率），决定要不要镜像圆角 | 在跑，但判断的是健康度，不是定位 |
| `PreviewRenderer.swift:183` `mirrorRoundCorners` | 底部圆角镜像（H1 已优化） | 在跑，不是定位 |
| `PreviewRenderer.swift:528` | 调用点：`visualBarH = fixedBarH == nil && profile.preciseChrome ? preciseVisualChromeHeight(...) : nil` | — |

调用点的条件互相矛盾：`profile.preciseChrome` 来自 `needsControlPaddedChrome(pid:)`（`Window/ChromeProfile.swift:308`），它等于 `windowPolicy(for: pid).fixedChromeHeight != nil`（`Compatibility/WindowPolicy.swift:73`）；而 `fixedBarH` 就是同一个 `fixedChromeHeight`（`Compatibility/AppPredicates.swift:36`）。所以「`fixedBarH == nil` 且 `preciseChrome`」在同一时刻不可能成立，`preciseVisualChromeHeight` 现在是死代码（只有 WeChat 51.5、Elpass 50.5 两条策略带固定高度）。

绝大多数窗口的标题栏高度来自 AX（`Window/AXWindow.swift:596-713` 的 `chromeHeight`／`topChromeControlsHeight`、`Window/ChromeProfile.swift:137` `standardTitleBarCropHeight`，下限 `titleBarHeight = 28`，上限 `standardTitleBarMaxCropHeight = 64`，见 `WindowShade.swift:26,30`），不是像素。`Window/TitlebarPrefetchGate.swift` 只是预热门控与 52pt 缺省带高，不扫像素。

缩略图裁剪：我在 `prototype/` 里 grep 了 `aspectFill`／`resizeAspectFill`／`contentsGravity`（`WindowBrowser/*.swift`）没有命中，没有找到按内容裁剪缩略图的启发式；窗口浏览缩略图是整窗缩放。所以「缩略图裁剪换显著性」没有可替换的现有逻辑，只能当新功能评估。

## 二、评估器

- `tests/h4-vision-eval/HeuristicCopy.swift`：`PreviewRenderer.swift:98-181` 逐字拷贝（`sed -n 98,181p` 生成，该函数依赖整个 App 之外的东西为零，但文件本身依赖 WMO 大构建，所以拷贝）。
- `tests/h4-vision-eval/main.swift`：每张图输出启发式、Vision 文本带高、Vision 矩形带高、显著性外框、各自耗时。
  - 文本：`VNRecognizeTextRequest`（`.fast`、不做语言纠正），只看顶部 110pt；取顶部 70pt 内文字的最低底边，加与顶边对称的留白。
  - 矩形：`VNDetectRectanglesRequest`（最小置信度 0.5，宽度小于 90%），同样取顶部 70pt 内最低矩形底边加对称留白。
  - 显著性：整图 `VNGenerateAttentionBasedSaliencyImageRequest`，取最大显著对象外框。
  - 耗时：每种方法重复 5 次取墙钟最小的一次，同时记进程 CPU 时间（`clock()`）。

构建与运行（每次只编一个、不用 `prototype/build.sh`）：

```
S=/private/tmp/claude-501/-Users-aaron-Documents-WindowShade/e20dabbb-f268-4ba8-9581-ffaab367e5e6/scratchpad
swiftc -O tests/h4-vision-eval/main.swift tests/h4-vision-eval/HeuristicCopy.swift -o $S/h4eval
REPS=5 $S/h4eval $S/h4-images        # 结果存在 tests/h4-vision-eval/results-2026-10-16.tsv
```

图片集（不进仓库）：`$S/h4-images`，20 张。17 张是本机窗口用 `screencapture -l <窗口号> -o -x` 截的（Finder、文字编辑、终端机、系统设定、辞典、字体簿、地图、天气、时钟、计算机、活动监视器、系统监视程式、磁碟工具程式、无边记、Safari 起始页、便条纸 2 张）；仓库里已有的 `tests/fixtures/capture-indicator-{before-stream,stream-frame}@2x.png` 2 张和 `assets/windowshade-settings.png` 1 张。我没有截信息、提醒事项、Drafts、Claude 等可能含私人内容的窗口。

## 三、结果

「真值」是我逐张看图后定的：标题栏／工具栏到其下分隔线（或最后一排工具控件加下留白）的高度，单位 pt，容差 ±8pt。`-` 表示该方法没给出结果（算没答出）。同一台机器测量时负载很高（`uptime` 负载 14 到 900 之间摆动），墙钟数字偏大且抖动，所以同列了 CPU 时间；Vision 的 CPU 时间不含 ANE 与系统服务进程，偏小。

| 图 | 真值 | 启发式 | Vision 文本 | Vision 矩形 |
| --- | --- | --- | --- | --- |
| finder | 85 | 51.5 ✗ | 90.0 ✓ | 87.4 ✓ |
| textedit | 64 | 63.5 ✓ | 65.0 ✓ | 88.2 ✗ |
| fontbook | 50 | 51.5 ✓ | 89.0 ✗ | 74.1 ✗ |
| maps | 51 | 50.0 ✓ | 113.0 ✗ | 104.2 ✗ |
| activitymon | 50 | 51.5 ✓ | 92.0 ✗ | 77.9 ✗ |
| settings | 52 | 51.5 ✓ | - | 88.0 ✗ |
| dictionary | 88 | 51.5 ✗ | 140.0 ✗ | 86.1 ✓ |
| terminal | 32 | - | 108.0 ✗ | - |
| diskutil | 66 | 51.5 ✗ | 108.0 ✗ | 87.6 ✗ |
| safari-start | 53 | 51.5 ✓ | - | 52.0 ✓ |
| sysmonitor | 88 | 52.0 ✗ | - | 86.1 ✓ |
| clock | 48 | - | - | 51.8 ✓ |
| calculator | 48 | - | - | 51.6 ✓ |
| weather | 30 | - | - | - |
| ws-settings（自家设置图） | 40 | 51.5 ✗ | 38.5 ✓ | 94.4 ✗ |
| **答对（共 15）** | | **6** | **3** | **6** |
| 答错 | | 5 | 6 | 7 |
| 没答出 | | 4 | 6 | 2 |

另有无边记（全屏欢迎页，没有标题栏带）：三种方法都没答出，算正确。便条纸 2 张与 2 张录屏胶囊素材没有可判的标题栏，不计入。

要点：

- 启发式的 6 个「对」基本是撞上的：它在 11 张浅色窗口上几乎都返回 50 到 52（51.5 出现 9 次），而这批窗口的真实工具栏恰好也在 50 上下。碰到 66、85、88 这种较高的工具栏就错，碰到深色窗口就没答。它本来只为 WeChat／Elpass 调的，拿去量任意窗口本就超出设计。
- Vision 文本把内容区的字（终端机的「Last login」、地图的比例尺）当成标题栏，深色或无字的工具栏（图标按钮）没答出。
- Vision 矩形在深色窗口（时钟、计算机）和 Safari、系统监视程式上答得好，在浅色窗口里容易把下一排（列表表头、分段控件）也圈进去；两个方法加起来互相补不上，因为没有信号告诉我们这一次谁可信。
- AX 路径（现网真实使用的方案）这里没有测，因为评估器只吃 PNG；它不是被比较的对象，但比任何一种像素办法都更可靠，因为它读的是真实控件的位置。

### 耗时（20 张均值，墙钟／CPU，毫秒，单窗口一次）

| 方法 | 墙钟 | CPU |
| --- | --- | --- |
| 启发式 | 11.1 | 5.9 |
| Vision 文本（顶部 110pt） | 34.4 | 15.1 |
| Vision 矩形（顶部 110pt） | 81.6 | 24.1 |
| 显著性（整图） | 25.2 | 8.3 |

负载高时 Vision 的墙钟偏离很大（第一轮同一批图的显著性均值 435 ms，同批第二、三轮 159、172 ms），这里取的是最安静的一轮，可以当下限，不当典型值。

### 显著性裁剪

20 张里 18 张的外框宽高都不小于整图的 70%，多数从 (0,0) 起、宽度 90% 以上；只有时钟（59×93%）和一张录屏胶囊素材（74×66%）低于 70%。注意力显著性在这类以界面为主的截图上几乎总是圈出整张窗口，作为缩略图裁剪没有信息量。

## 四、建议：不采用

1. **标题栏定位**：没有一种 Vision 方法同时比现有路径更准。文本 3／15、矩形 6／15，启发式 6／15（且是撞上的），而现网实际走的是 AX。要用 Vision 只能当「AX 不可用时的兜底」，但兜底也要有可信度信号，目前没有；更便宜的做法是缺省 52pt（`TitlebarPrefetchGate.defaultBandHeight`），在这 15 张里 52pt 的命中数是 7，比启发式的 6 还多。
2. **耗时**：一扇窗一次 35 到 80 ms（安静时），而收起的第一次画面变化约 156 ms（H2 基线）。放在关键路径上会让收起变慢；规格自己也规定「不把 Vision 放上关键交互路径」，所以只能异步，异步的结果又赶不上第一帧。这是明确的回退风险，与「只做纯收益」的项目规则冲突。
3. **缩略图裁剪**：现网没有内容裁剪，显著性又基本返回整图，没有收益。
4. **低电量／热压力回退**：H4 验收里这一条未实现（这一轮是纯测量）。`App/PowerPolicy.swift` 是 H6 的入口。既然不采用，也无需实现。

如果以后仍想试，较低风险的两个方向：(a) 死代码 `preciseVisualChromeHeight` 要么删掉，要么先弄清 WeChat／Elpass 想走哪条路（现在走固定高度）；(b) 对「没有 AX 工具栏、又不在白名单」的未知 Electron 窗口，用 Vision 矩形加深色窗口判断做离线标注工具，而不是运行时。

## 五、局限

- 真值是我看图定的，不同的人对「标题栏到哪」可能差 8 到 16pt（如 Finder 的搜索栏一排）；容差 ±8pt 已较宽松。
- 样本是 15 张可判窗口，且这台机器是繁体中文系统与 macOS 27，浅色深色都有，但没有 Xcode 等重型工具栏窗口。
- 墙钟在高负载下不可靠，已同列 CPU，但 Vision 的 ANE／XPC 开销不在 CPU 列里。
- 没有测 ANE 能耗，规格里「能效」一项没验。
