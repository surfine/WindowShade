# 性能与能效：把「确保平衡」变成可量的

2026-10-15。这一份回答：**我们的能效现在到底什么水平、与竞品差在哪、要改成什么。** 依据：[scorecard](scorecard.md) 已有的实测、[竞品深挖](competitive-deep-dive.md)（含函数级）、[更新日志里的 real-world know-how](changelog-knowhow.md)（626 个 release）。要动手执行的条目已并入[重塑执行规格](product-reshape-spec.md)的 `E` 系列。

## 一、本轮实测基线（2026-10-15，第一次真的量到自己）

**这是整个调研里第一次跑我们的探针拿数字。** 用的是 `prototype/WindowShade.app`（**2026-09-22 那份构建**，不是当前源码——标注在此，别当成当前版本的对外数字）。三套都是现成的、**安全**的（早退拦截，不动任何窗口）。

### 1.1 AX 延迟基准（`--duo-ax-bench` → `App/AXLatencyBench.swift`）

**先分清两类操作——混在一起比会得出错的结论：**

| 类别 | 量 | 实测 |
| --- | --- | --- |
| **枚举**（发现有哪些窗口） | AX 完整枚举，**每个 App 一次** | **4.5 – 10.5 ms**（ZCode 4.5、MenuBarAgent 7.5、Clash Party 7.6、WindowShade 9.0、Safari 10.2、Finder 10.5） |
| 枚举 | 对照 · `CGWindowListCopyWindowInfo` 全量枚举 | **1.7 ms**（10-14 那次 128 个窗口是 2.156 ms） |
| 枚举 | 对照 · `SCShareableContent` | **32.1 ms**（10-14 那次） |
| **读单个窗口的属性** | AX 四项（位置／尺寸／标题／角色） | **平均每窗 0.1 ms**（逐项 0.0–0.1 ms） |
| 读单个窗口的属性 | 对照 · 私有 SkyLight `PrivateSLSWindowMover.windowAlpha(id:)` | **0.042 ms** |

**结论（比中途我在对话里说的那句更保守，也更准）：**

- **枚举这一层，私有没有明显优势，而 `CGWindowListCopyWindowInfo` 本来就是快路**（1.7 ms）。真正的坑是**别拿 `SCShareableContent` 去枚举**——那一步是 32.1 ms，**换回 CGWindowList 就是 19 倍**，而且纯公开 API。
- **读单个属性这一层，私有快约 2.4 倍**（0.042 vs 0.1 ms）——**是小赢，不是数量级**。所以「私有视窗伺服器更快吗」的正确回答是：**列举上是「不」，单属性读上是「一点」，而竞品用私有 API 的真正理由是「能力」不是「速度」**（与[竞品深挖](competitive-deep-dive.md)§三那条实测的结论一致）。
- 注意别张冠李戴：`windowAlpha` 是**单个窗口的一个属性**，`CGWindowList` 1.7 ms 是**全量枚举**——这两者不能直接比。
- **贵的是「发现窗口」，便宜的是「读它的属性」（相差 40–100 倍）。** 优化重点因此是**少枚举、复用句柄、缓存枚举结果**，不是省字段读取。这正好解释了 Wins 为什么要埋 `missionControl.axReadsMinimum` 与 `snapshotCacheHits`。
- **推论（可验）**：R3 的唤醒恢复若每一档都重新枚举一遍全部 App，**10 个 App 就是 45–105 ms**——所以三档恢复**必须幂等且有界**（每档先问「还需要恢复吗」）。这一条从设计偏好升级成了**实测约束**。
- 也解释得通 AeroSpace 为什么走 thread-per-application：**枚举是每个 App 一次阻塞调用**，一个 App 卡住，那一次调用就卡在那里。

### 1.2 空闲计数（`--window-browser-idle-probe`）

```
idle-probe: dockEnabled=false axQueries=0 thumbnailsInFlight=0 thumbnailBytes=0
idle-probe: afterStop axQueries=0 thumbnailsInFlight=0 thumbnailBytes=0 settingsRestored=true
```

**把窗口浏览的 Dock 触发关掉，AX 查询 0 次、飞行中缩图 0 张、缓存 0 字节**，并且探针**把设置原样恢复了**（`settingsRestored=true`）。这是「不需要时真的没做事」的**实证**，也是 §二那份账本里「快计时器多数已是表面绑定」的旁证。

### 1.3 静态足迹

| 量 | 实测 |
| --- | --- |
| bundle | **6.6 MB** |
| 主二进位 | **3.6 MB** |

**注意口径**：[scorecard](scorecard.md) 里那个「物理占用约 100 MB」是**执行期内存**，不是包体积。这两个数不能混着说——对外比较时必须写明是哪个（见 E2）。

## 二、Apple 芯片：我们已经在用什么、缺什么、怎么补

**先更正一个容易说错的判断。** 一眼看去「我们没用硬件能力」是**错的**——查下来是这样的：

| 硬件能力 | 我们 | 证据 |
| --- | --- | --- |
| **NPU（ANE）** | **已经在用** | `App/VisionFaceEmbedder.swift` 用 `VNGenerateImageFeaturePrintRequest`（钉死 revision 2）、`VNDetectFaceLandmarksRequest`、`VNDetectFaceCaptureQualityRequest`、`VNDetectRectanglesRequest`。**Vision 的推理默认跑在 Neural Engine 上** |
| **GPU** | **已经在用** | `Effects/FoldRenderer.swift` 是一个真的 Metal 渲染器：`MTLTexture`、纹理缓存（`FoldImageCache<MTLTexture>`）、mipmap；链接了 Metal／MetalKit／CoreImage |
| **硬件解码** | 已链接 | `VideoToolbox` |
| **功耗策略** | **已经有** | `App/PowerPolicy.swift` 读 `isLowPowerModeEnabled` ＋ `thermalState`，听 `NSProcessInfoPowerStateDidChange`／`thermalStateDidChangeNotification`；`App/AppNapActivity.swift` 用 `beginActivity` |
| **采集侧细节** | 已经对 | `showsCursor = false` 在 5 处都设了 |
| **vImage／Accelerate** | **完全没用** | 全仓 0 处 |

**所以问题不是「有没有用」，是「用够没有、用对没有」。** 下面四条是查出来的真缺口。

### 2.1 最硬的一条：`mirrorRoundCorners` 是标量 Swift 循环 + 逐像素 Float 除法

`Capture/PreviewRenderer.swift:183` 的实作是：

```swift
var origAlpha = [UInt8](repeating: 0, count: w * h)          // 第一趟：快照 alpha
for y in 0..<h { for x in 0..<w { origAlpha[y*w + x] = buf[y*bpr + x*4 + 3] } }

for y in 0..<h { let my = h - 1 - y                          // 第二趟：逐像素算
    for x in 0..<w {
        ...
        let f = Float(aMirror) / Float(aSelf)                // ← 每个像素一次浮点除法
        buf[i] = UInt8(Float(buf[i]) * f) ... x4             // ← 每通道一次浮点乘
    }
}
```

**两次全缓冲遍历、逐像素一次浮点除法、四次浮点乘**，而缓冲是 4K Retina 全宽（`pixelAnalysisQueue` 的定义注释自己写着「4K Retina 全宽可达数 MB 缓冲」）。同一个文件里还有 14 处循环（`nativeTitleStripLooksBroken` 等），是同一类写法。

**改法（两条路，优先第一条）**：

1. **交给 Metal**——`Effects/FoldRenderer.swift` 已经有 device、纹理、缓存，把「圆角镜像」做成一个 fragment pass，**CPU 完全不碰像素**。这条最顺，因为渲染器已经在跑了。
2. **退一步用 vImage**——`vImageVerticalReflect` 做镜像、`vImagePremultiplyData`／`vImageAlphaBlend` 做预乘合成，**SIMD（Apple Silicon 上是 NEON）加速**，改的是调用而不是算法。

**验收**：同一张 4K Retina 图，单次调用耗时**前后对比**（要有数字）；**输出逐像素一致**（可以拿同一张图跑新旧两条路做像素比对，不一致就是没改成等价）。
**注意**：这一条是**等价替换**，不许改变画面。它属于「补缺陷」里最干净的一类——不改行为、只换实现。

### 2.2 QoS：后台图像分析挂在 `.userInitiated`（性能核）

`WindowShade.swift:170`：`pixelAnalysisQueue = DispatchQueue(label:"WindowShade.pixels", qos: .userInitiated)`，注释自述「**纯 CPU 计算**」。全仓 QoS 分布是 `.userInteractive` ×9、`.userInitiated` ×8、`.utility` ×18。

**`.userInitiated` 会去抢性能核；`.utility` 优先落效率核，功耗显著更低。** 一个纯 CPU 的后台图像分析挂 `.userInitiated` 是可疑的。

**但要小心**：同一段注释也写着「挪出主线程**避免折叠瞬间卡 UI**」——说明它在折叠关键路径的旁路。**所以这一条必须先量再改**：

- 跑 `--fold-timing` 拿折叠延迟基线；
- 把它降成 `.utility`，再跑一次；
- **若能过，降；若手感变差，保持 `.userInitiated`，但把「非关键路径的那几处」（健康检查、圆角镜像的预处理）拆到 `.utility`**。

### 2.3 采集侧：sRGB 而非 P3，`captureResolution` 没设

`ScreenCaptureBridge.swift:414-418`：

```swift
configuration.pixelFormat = kCVPixelFormatType_32BGRA
configuration.colorSpaceName = CGColorSpace.sRGB        // ← 不是 displayP3
configuration.queueDepth = isPreviewStream ? 2 : 3
configuration.scalesToFit = true
```

对比 DockDoor 在 macOS 15+ 的写法：`captureDynamicRange = .hdrLocalDisplay`、`colorSpaceName = CGColorSpace.displayP3`、`captureResolution = .best`。

**在 P3 宽色域的屏上，用 sRGB 采集会让颜色变淡**（缩略图与外接屏预览都会被看出来），而且可能多一次色彩转换。**`captureResolution` 不显式设**，等于把「采多大」交给默认档——那会影响后续缩放的成本。

**改法**：按显示器能力选色彩空间（P3 屏用 displayP3）；显式设 `captureResolution`；macOS 15+ 上评估 HDR 档（**要连着看功耗**，HDR 采集更贵）。
**验收**：同一扇窗的缩略图与系统截图做色彩比对；P3 屏上不变淡；采集侧 CPU 占比不升。

### 2.4 ANE 的正确落点：把「已经很贵的图像理解」从启发式换成推理

**先把话说清楚，免得为用而用**：ANE 只在 **Vision／CoreML 推理**时才用得上；**窗口管理本身没有神经推理需求**。所以「把 NPU 用起来」的正确落点**不是到处塞模型**，而是——**把已经在做、且正在用像素启发式硬算的图像理解，换成 Vision 推理**。我们已经有一条（人脸），下面两条是同一类：

| 现在怎么做 | 换成什么 | 为什么这是净赚 |
| --- | --- | --- |
| **标题栏定位靠像素启发式**（chrome 高度扫描、`nativeTitleStripLooksBroken`） | `VNDetectRectanglesRequest`／`VNRecognizeTextRequest` **语义化地**找标题栏与内容边界 | **不只是更快，是更准**——尤其对自绘标题栏的 App。它同时补**产品缺陷**：R6 那族「做不了就说一声」的前提是「知道这扇窗长什么样」 |
| 窗口缩略图比例不合时**几何居中裁** | `VNGenerateAttentionBasedSaliencyImageRequest`（ANE）找注意力区域再裁 | 窗口浏览的卡片裁到「有意义」的地方，而不是把内容切掉 |

**风险与边界**：Vision 推理有**毫秒级固定开销**，**不能每帧跑**——只用在「一扇窗一次」的路径（窗口发现、缩略图生成）。低电量／热压力下要能退回现有的启发式（正好接 §2.5）。

### 2.5 统一内存与零拷贝：能拿 `CVPixelBuffer` 的地方别绕 CPU

ScreenCaptureKit 给的是 **`CVPixelBuffer`（IOSurface 支撑）**；Metal 可以用 `CVMetalTextureCache` **直接从它建纹理，不经 CPU**。而 `Effects/FoldRenderer.swift` 现在是从 `CGImage` 建纹理——**那一步要在 CPU 上传**。

**改法**：凡是能拿到 `CVPixelBuffer` 的路径（实时流的帧、部分截图路径），直接用 `CVMetalTextureCache` 建纹理。这才是「用 Apple 芯片」的核心优势——**统一内存 + 零拷贝**。
**验收**：那条路径上的 CPU 占比与内存带宽下降；画面一致。

### 2.6 新路径要进已有的功耗策略

`App/PowerPolicy.swift` 已经按 `thermalState` 与低电量模式调行为。**上面 2.1–2.5 新引入的 GPU／Vision 路径必须进这套策略**：低电量或热压力下**退回 CPU／降低质量／跳过非必要推理**，而不是照跑。这一条是前五条的收口，不能漏。

### 2.7 诚实清单：什么**不**该做

- **不为了「用上 NPU」引入模型**。没有推理任务就是没有——窗口管理没有。
- **不做「Metal 重写一切」**。只在**已经证明是瓶颈**的像素路径上换（2.1 是唯一有确凿证据的一条）。
- **不把 Vision 放上关键交互路径**。毫秒级开销在悬停、拖动的路径上是负担，不是优化。
- **不牺牲色彩与视觉正确性换性能**。2.3 是往*更准*的方向走，不是降质。

## 三、已有的实测资产（不要重测已知的）

**结论先说：能效不是空白，我们已经在测，而且已经找到并修掉过一次数量级级别的浪费。**

[scorecard](scorecard.md) 的「性能」一栏已经记着：

| 已有实测 | 数字 |
| --- | --- |
| 60 秒静置（build 16 前后） | 盒盖／倾斜效果**关着约 0.31%** |
| 同上 | **开着从 2.2–2.7% 降到约 0.45%**（铰链改推送、静止时不轮询） |
| 加速度计轮询 1000 µs（原来） | **4.55% / 5.42%** |
| 同一构建、只把间隔改成 16000 µs | **1.68% / 2.85%** |
| 改成 16000 µs 后的正式构建 | **2.70% / 2.25% / 2.18%** |
| 物理占用 | **约 100 MB** |

**这组数字本身就是一条方法论**：把 1000 µs 的轮询改成 16000 µs，常驻 CPU 从 4.55% 掉到 1.68%——**能效的大头永远是「空闲时还在轮询什么」，不是算法优化**。这跟 Atoll 那条「Reduced idle CPU from always-on notch hover polling… **by backing off when the app is idle**」是同一件事。

## 四、77 处计时器的账本（本轮新做的）

把全仓的 `Timer.scheduledTimer` / `Timer(timeInterval:` 全数出，共 **77 处**，间隔从 **0.005 秒（200 Hz）到 30 秒**。逐条看了 1 秒以内的生产计时器（探针里的不算）：

| 间隔 | 位置 | 性质 | 判断 |
| --- | --- | --- | --- |
| 0.05s | `App/LaunchpadView.swift:1172` | **编辑拖动期间**的跟手 | 表面绑定，拖动结束就停 ✓ |
| 0.2s | `PinnedPreview.swift:1097` | 置顶预览的看门狗 | **已设 `tolerance = 0.05`** ✓ |
| 0.25s | `App/NowPlayingCard.swift:1247` | 封面卡的「指针离开」判定 | **模范写法**：注释写明「指针在卡里、正在拖、列表开着……**不需要每 0.25 秒醒来**」，该 invalidate 就 invalidate，且 `tolerance = 0.1` ✓ |
| 0.35s | `App/Notch.swift:3269` / `:5482` | 两个 **一次性**（`repeats: false`）驻留判定 | ✓ |
| 0.5s | `App/ScrollStripRun.swift:148` | 卷轴运行期间的 `watch()` | 运行期绑定；**未设 tolerance**（可补） |
| 0.55s | `App/LaunchpadView.swift:792` / `App/TrackpadGestures.swift:1214` | 两个**一次性**长按判定 | ✓ |
| 0.6s | `WindowBrowser/WindowBrowserController.swift:1320` | `startLivenessSweep()` 扫已关窗口 | **要核它是不是常驻**——若是，空闲时仍有 1.7 Hz 唤醒；**未设 tolerance** |
| 2s | `WindowShade.swift:955` | tap 安装重试 | **成功即 `invalidate`** ✓ |
| 5s | `WindowShade.swift:1006` | **本轮新加的环境体检**（R1） | **常驻**，见下 |

**`tolerance` 的覆盖**：全仓 **约 10 处**已经设了（`PinnedPreview:1101` 0.05、`NowPlayingStream:156` `min(10, delay/4)`、`NowPlayingStream:190` 1、`NotchLevelObserver:479` `interval/4`、`PictureInPicture:285` 0.3、`WS2RemoteEffects:304` `max(0.1, seconds*0.1)`、`Carry:428` 0.5、`FileShelfView:273` 0.1 等）。**这不是空白，是习惯已经养成**；`ScrollStripRun:148` 与 `WindowBrowserController:1320` 是没覆盖到的两个。

**我新加的 5 秒环境体检要单独记账**：它是**常驻**的（0.2 Hz），每 5 秒做一次 `CGEvent.tapIsEnabled` ＋ `AXIsProcessTrusted()`——两者都是**本地检查，不发 AX 消息**，代价近似零，但它是**永久存在**的成本，换的是「通道死掉能自愈」。DockDoor 用同样的 5 秒。**它没有 surface 绑定，也不该有**（通道死了没有表面可依附）。这一条要在每次静置实测里单列出来看。

## 五、竞品的能效课（从 626 个 release ＋ 7 份函数级里抽出来的）

| 竞品做法 | 出处 | 我们 |
| --- | --- | --- |
| **空闲退避**：常驻的刘海悬停轮询与 OSDUIHelper 进程检查，**空闲时退避** | Atoll | 我们**不轮询**、也**不碰 OSDUIHelper**（`App/NotchLevelControl.swift:9` 明确写了）→ 更干净 |
| **把「AX 读取次数」做成可观测的计数器并压到最低**（`missionControl.axReadsMinimum`／`snapshotCacheHits`／`dragFastPath`） | Wins | **已有**：`WindowBrowserIdleProbe` 读 `controller.axQueryCount` |
| **缩略图缓存带成本账**，按代价决定留哪一个 | Alcove `cachedSnapshotCost` | **已有**：`thumbnails.cachedCostBytes`（`WindowBrowserIdleProbe` 里在读） |
| **触点帧压主线程**：一帧移动不送主线程，主线程投递从 94.2% 降到 0.53% | OmniWM 0.7.5 | **已有同形写法**：`App/TrackpadGestures.swift:2218` 注释「只在手指数变化时回主线程」 |
| **权限检查阻塞主线程 ~9.3 ms**，改成缓存 + 离开系统设置时刷新 | OmniWM | **2026-10-15 自纠**：此前写「我们不直接调那个检查」，**是错的**——本机 `nm -u` 显示二进制里有 `CGPreflightScreenCaptureAccess`／`CGRequestScreenCaptureAccess`，代码里 **6 处以上**（`Capture/WindowSnapshot.swift:54`、`App/Permissions.swift:13`、`Effects/DuoSettingsWindow.swift:1023`／`:1037`／`:1123`…）。→ **这一条从「我们已经做对」变成「要核」**：这些调用有没有落在主线程的**循环/高频**路径上（OmniWM 测出来单次 9.3 ms，落在热路径上就是灾难） |
| **锁屏／屏保时内存暴涨** | Ice 0.2.2 | **已有**：锁屏/屏保/唤醒各自暂停（五处观察者） |
| **切 App 时菜单栏覆盖层 CPU 飙** | Ice 0.10.0 | 待核（我们的菜单栏面） |
| **空闲时少用电池**、长时间空闲后第一次操作不迟滞 | alt-tab-macos v11.7.0 | 待核「长时间空闲后第一次操作」 |
| **AX 是阻塞 API，一个 App 不响应会拖住整个系统** → 每 App 一个线程 ＋ **请求可取消** ＋ **合并幂等请求** | AeroSpace v0.18.0 | **部分**：按 App 后台队列 ✓、逐调用 timeout ✓、按调用熔断 ✓；**「可取消」没有** |
| 限并发（`maxConcurrent`）、对不响应的 App 退避 | DockDoor | **已有**：`PinnedPreview.swift:633` 的退避 |
| **每个事件循环最多发一次 idle 通知**（高回报率鼠标下的卡顿） | niri | 不适用（我们没有那个事件循环），但**精神适用**：高频输入路径上不要每帧做工 |

**读出来的一句话**：竞品的能效课我们**大半已经上过了**，剩下的是「可取消的 AX 请求」与两处 `tolerance` 补齐。

## 六、差距在哪（三条硬的，按优先级）

1. **物理占用约 100 MB，而 Wins 自称 <30 MB。** 这是唯一一处我们**明确落后一个量级**的能效数字，也是对外最容易被抓住的一条。**先要做的不是优化，是查清口径**：它说的 30 MB 是物理占用（footprint）还是常驻集（RSS）？是空载还是含缓存？[competitive-analysis.md](competitive-analysis.md):43 已经记过一次「Wins 官网两处数字对不上（30 MB 与 70 MB）」。→ **动作 E2**：用同一口径分别量我们自己与它（它要在隔离机上跑，见[竞品深挖](competitive-deep-dive.md)§一的界线）。
2. **没在日常使用里和 1.0.15 比过卡顿**（scorecard 原话）。静置数字有了，**手感没有**。→ **动作 E3**：一次可比的长会话（同样的窗口数、同样的手势序列），记帧时间分布。
3. **静置口径没有例行化**：现在是一次性的记录，不是每版必过的项。→ **动作 E1**：进[重塑执行规格](product-reshape-spec.md)的发布清单。

## 七、动作（已并入执行规格的 E／H 系列）

| 编号 | 动作 | 验收 |
| --- | --- | --- |
| **E1** | **把 60 秒静置实测做成例行项**（每版必跑，数字进 scorecard）。口径固定：无操作、无手势、宿主不锁屏、同一台机、跑三次取中位 | 每次发版有一行数字，可对比 |
| **E2** | **查清内存口径并同口径对比**：先量清我们自己的 physical footprint 与 RSS、空载与「开了窗口浏览+几个常驻面」两种状态；再查 Wins 那 30 MB 的确切含义 | 一张同口径对照表；不引用对不上的数字 |
| **E3** | **一次可比的长会话卡顿对比**（对 1.0.15） | 帧时间分布 + 结论 |
| **E4** | **补两处 `tolerance`**：`App/ScrollStripRun.swift:148`（0.5s）、`WindowBrowser/WindowBrowserController.swift:1320`（0.6s，**同时核它是否常驻**） | 改动 + 静置数字不劣化 |
| **E5** | **AX 请求可取消**（AeroSpace 那条我们只做了一半） | 一个 App 卡住时，排队中的请求能取消，不吃满 timeout |
| **E6** | 核 Ice 那两条：**切 App 时菜单栏面 CPU**、**长时间空闲后第一次操作的迟滞** | 各一条探针 |

### H 系列 · Apple 芯片（理由见本文 §二）

| 编号 | 动作 | 验收 |
| --- | --- | --- |
| **H1** | **`mirrorRoundCorners` 换掉标量循环**（`Capture/PreviewRenderer.swift:183`，另有 14 处同类循环）。优先走 Metal（`Effects/FoldRenderer.swift` 已有 device／纹理／缓存），退一步用 `vImageVerticalReflect` ＋ `vImagePremultiplyData` | 同一张 4K Retina 图**单次调用耗时前后对比**；**输出逐像素一致**（等价替换，不许改画面） |
| **H2** | **`pixelAnalysisQueue` 的 QoS 复核**（`WindowShade.swift:170` 现为 `.userInitiated`）。**先量再改**：跑 `--fold-timing` 取基线 → 降 `.utility` → 再跑；关键路径上不能降的那几处单独保留 | 折叠延迟不劣化；非关键路径的 CPU 占比下降 |
| **H3** | **采集侧色彩与分辨率**（`ScreenCaptureBridge.swift:414-418` 现为 sRGB、未设 `captureResolution`）：按显示器能力选色彩空间（P3 屏用 `displayP3`），显式设 `captureResolution`，macOS 15+ 评估 HDR 档（**连着看功耗**） | 缩略图与系统截图色彩比对；P3 屏上不变淡；采集侧 CPU 不升 |
| **H4** | **Vision 用到该用的地方**（ANE）：标题栏定位从像素启发式换成 `VNDetectRectangles`／`VNRecognizeText`；缩略图裁剪用 `VNGenerateAttentionBasedSaliency`。**只在「一扇窗一次」的路径上跑，不每帧** | 同一批窗口比较「启发式 vs Vision」的定位；低电量／热压力下能退回启发式 |
| **H5** | **零拷贝**：能拿到 `CVPixelBuffer` 的路径用 `CVMetalTextureCache` 直接建纹理，别绕 `CGImage`（现在 `FoldRenderer` 是从 `CGImage` 建，要 CPU 上传） | 那条路径的 CPU 占比与内存带宽下降；画面一致 |
| **H6** | **新路径进 `App/PowerPolicy.swift`**（低电量／热压力下退回 CPU／降质／跳过非必要推理） | 低电量模式下新路径行为可解释 |

**不该做的（§2.7）**：不为「用上 NPU」引入模型；不做「Metal 重写一切」；不把 Vision 放上关键交互路径；不牺牲色彩正确性换性能。

## 八、口径（怎么测才算数）

- **静置**：宿主无操作、无手势、屏幕不锁不灭、同一台机、同一构建，**跑三次取中位**。数字进 [scorecard](scorecard.md) 的「性能」行，注明构建与日期。
- **不许引用对不上的数字**：竞品官网的自我宣称（Wins 的 30 MB）只能作为「它的宣称」引用，不能当基准；要对比就**同口径实测**。
- **真机证据**按 [Computer Use 验收](computer-use-qa.md)：工具退出 0 不算，日志打印不算。
- **能效改动一律要给前后数字**（这一次 1000 µs → 16000 µs 就是这么定案的）。
