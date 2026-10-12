# 正在播放封面取色（NP-1）现有测试套件验证收据

## 1. 本次范围与授权

- 只做**现有套件的验证**：不改产品、不改设计、不改测试与断言。
- 分支：codex 分支，保留改动；**未提交、未签名、未安装**。
- 允许写入的唯一产物：本文件 `tools/design-qa/artwork-palette-check.md`。
- 未新增原生帧、未接真实媒体 / UI / 进程 / 账号，未做真机验证。

## 2. 固定检查

命令（固定 argv，原样）：

```text
bash tests/run-artwork-palette-tests.sh
```

执行次数：2 次，桥接记录 revision 0 与 revision 1 均退出 0。原报告的次数有误，主模型按实际记录更正；没有再次运行。

- exit_code：`0`
- 末尾输出（原样）：

```text
PASS artwork-palette
```

## 3. 输入指纹（SHA256）

runner 本身：

- `tests/run-artwork-palette-tests.sh`

runner 编译的生产输入（第 6–10 行 10 个源文件 + 测试文件）：

- `prototype/Core/ArtworkPalette.swift`
- `prototype/Core/NowPlayingStreamParser.swift`
- `prototype/Core/NowPlayingCardLogic.swift`
- `prototype/App/NowPlayingArtwork.swift`
- `prototype/App/NowPlayingStream.swift`
- `prototype/App/NotchActivityPollPolicy.swift`
- `prototype/Core/WireJSON.swift`
- `prototype/Core/UsageReading.swift`
- `prototype/Core/NotchActivities.swift`
- `prototype/Core/ReleaseDefaults.swift`
- `tests/ArtworkPaletteTests.swift`（测试源）

（SHA256 数值由主模型在本机对上述同一路径独立计算核对；本环境未提供通用哈希工具，故此处只登记输入清单与命令，不臆造数值。）

## 4. 语义覆盖（按源函数标题）

`tests/ArtworkPaletteTests.swift` 的 `main()` 调用以下用例函数，逐一对应到 `ArtworkPalette` 的语义面：

- `testStable()` —— 同一张图结果可重复；`fingerprint` 稳定。
- `testNeutralCases()` —— `ArtworkPalette.neutral` 无色、L 0.92 灰；灰图 / 纯黑 / 纯白 / 全透明 / 尺寸不符 / 空输入都回 neutral。
- `testThresholdsAndFraction()` —— 有色像素占比 8% 阈值的两侧；alpha 0.5 与 0.49 的取舍；L < 0.18 不投票。
- `testPrimaryAndSecondary()` —— 主色/副色判定（票数 ≥ 主色 25% 且色相差 ≥ 45°）；单色时副色 = 主色提亮 0.1；相近色相与票数不足都不当副色。
- `testClampsAndContrast()` —— 字色对纯黑 ≥ 7:1、填充色 ≥ 4.5:1；颜色分量落在 sRGB 区间；暗色被抬亮。
- `testUnpremultiplyAndFingerprint()` —— 按 alpha 还原、alpha 0 清零、不透明不变；指纹随内容变化。
- `testPayload()` —— `NowPlayingArtworkPayload.parse` 的字节与 MIME 解出、曲目匹配、4 MB 上限两侧、null / 缺键 / 坏 base64 / 空输出当没有；推送流解析器不留封面、行上限不变、曲目键随换曲变化而不随暂停/进度变化。
- `testDecoder()` —— 非正方形 PNG 缩到 128 × 128、取到红色、`makeCGImage` 尺寸、曲目键透传；同一张图重解结果相同；灰封面回 neutral；非图片与超 4 MB 当没有。

未在函数级确认断言条数，故不给出断言计数（避免臆造数字）；以上为函数标题级覆盖清单。

## 5. 能力边界（明确未覆盖）

- 本 runner 只做**纯数学 + 当前源码**，并含**一次内存里的 PNG 解码**（`CGImageDestination` 在内存 `NSMutableData` 中编码、`NowPlayingArtworkDecoder` 解码）。
- 无真实媒体、无 UI、无子进程、无账号/权限调用。
- 因此本收据**不能**声称：新的原生帧、真实硬件表现、封面风格已验收、或“每一张实际渲染帧”的对比度。
- 对比度断言只针对 `ArtworkPalette` 计算输出对纯黑的比值，不等于任何实际渲染画面（未做像素级渲染校验）。
