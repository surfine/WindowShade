# 媒体/文件架边界复核（NP-4 正在播放大卡、FS-04 文件架卡）

定稿人：设计 QA（本文件只核对实现与设计稿，不跑 App、不调用音频 / 系统 / 网络、不读真实文件架或用户数据）。
行号对应**当前未提交工作区**的真实文件（非 HEAD 克隆）。

读取范围（只读这些）：
- `prototype/App/NowPlayingCard.swift`（1252 行）、`prototype/App/AudioOutputRoutes.swift`（121 行）
- `prototype/App/FileShelfView.swift`（1328 行）、`prototype/App/FileShelfStore.swift`（356 行）
- `prototype/Core/NowPlayingCardLogic.swift`（428 行）、`prototype/Core/FileShelfModel.swift`（268 行）
- `docs/design-drafts/正在播放.html`、`docs/design-drafts/文件架.html`、`docs/copy-guide.md`

---

## 1. 两种表面的公开构造器 / 模型字段 / 安全 fixture 注入

### 1.1 正在播放大卡（NP-4）

| 项 | 实际源码 | 说明 |
| --- | --- | --- |
| 视图构造器 | `NowPlayingCard.swift:275` `init(geometry: NotchGeometry)` | `NotchGeometry`（`:179-183`）= `width` / `height` / `virtual`，`Equatable`。**唯一**公开入口，无参数默认值 |
| 版式常量 | `NowPlayingCardLogic.swift:18-122` `NowPlayingCardLayout` | `width 420`、`referenceNotchHeight 33.5`、`contentHeight 142`、`totalHeight = 33.5 + 142 = 175.5`、`bottomRadius 28`、`margin 14`；`frames(cardWidth:)` 返回全部坐标（`:75-91`） |
| 注入点（闭包，全部可直接替换） | `:185-200` | `onCancel`、`inputIsCurrent`、`onCommand`、`onSeek`、`onSelectRoute`、`onSizeChange`、`onInteractionChange`、`onPointer`、`clock: () -> Double`（默认 `Date().timeIntervalSince1970`） |
| 内容注入 | `:393` `update(_ next: NowPlayingCardContent, artwork image: NowPlayingArtworkImage?)` | `NowPlayingCardContent`（`NowPlayingCardLogic.swift:174-187`）= `title` / `artist` / `isPaused` / `bundleID` / `timeline: NowPlayingTimeline?` / `seekable`，`Equatable, Sendable` |
| 时间线（纯值，无时钟依赖） | `NowPlayingCardLogic.swift:127-171` | `NowPlayingTimeline(duration:elapsed:stamp:rate:)`；`position(atEpoch:)`、`fraction(atEpoch:)`、`secondsUntilNextTick(atEpoch:)` 都由调用方传入 `now` |
| 进度条状态机 | `NowPlayingCardLogic.swift:236-309` `NowPlayingScrub` | 纯 struct；`press(at:trackWidth:)` / `drag(to:trackWidth:)` / `release(at:trackWidth:duration:now:)` |
| 收回条件 | `NowPlayingCardLogic.swift:315-345` `NowPlayingRetractClock` | `update(now:pointerInside:dragging:listOpen:)`、`isDue(now:)`、`remaining(now:)` |
| 可注入的读数 | `:205-228` | `private(set) var content`、`scrub`、`routes`（默认 `[]`）、`listOpen`、`volumeShown`、`volumeValue`、`volumeMuted`、`pendingTimerCount`；`var onVolumeSet: ((Double) -> Void)?` |
| 题面**默认**会碰系统 | `:192` `var loadRoutes: () -> [AudioOutputRoute] = { AudioOutputRoutes.list() }` | 见 1.3 与 §3 |

安全 fixture 做法（不读系统）：构造 `NowPlayingCard(geometry: .init(width: 420, height: 33.5, virtual: false))`，先把 `clock` 换成假钟（如闭包返回固定 `Double`），再 `update(content, artwork: nil)`；`loadRoutes` 换成返回手写 `[AudioOutputRoute]`（`NowPlayingCardLogic.swift:367-373` 的纯 struct，字段 `id: UInt32` / `uid: String` / `name: String` / `kind: AudioOutputKind` / `isCurrent: Bool`）。`NowPlayingArtworkImage` 属于 `NowPlayingArtwork.swift`，**不在本次授权读取范围内**，未核对其构造器。

### 1.2 文件架卡（FS-04）

| 项 | 实际源码 | 说明 |
| --- | --- | --- |
| 总管 | `FileShelfView.swift:71` `final class FileShelfController: NSObject, NSSharingServiceDelegate, @preconcurrency QLPreviewPanelDataSource, QLPreviewPanelDelegate` | |
| 构造器 | `FileShelfView.swift:96` `init(store: FileShelfStore = FileShelfStore())` | 默认参在构造时就实例化 `FileShelfStore`（其默认 `root = FileShelf.defaultRoot`，`FileShelfStore.swift:91`，指向 `~/Library/Application Support/WindowShade/文件架`）；**不会**立刻读写磁盘（真正的读写都在 `start()` 里进 `io` 队列） |
| 视图构造器 | `FileShelfView.swift:177` `FileShelfView(controller: self, hasNotch: strip.hasNotch, strip: Double(strip.height))` | 在 `FileShelfView.swift` 内调用；**该类型的声明不在本次授权范围内**（1328 行内的其余片段未读），构造器签名未核对 |
| 存取层可注入 | `FileShelfStore.swift:91-96` | `init(root: URL = FileShelf.defaultRoot, undoDelay: TimeInterval = 5, isEnabled: @escaping @Sendable () -> Bool = { FileShelf.enabled })` —— **root 与开关都可换成 temp 目录 / 恒 true 闭包**，这是唯一干净的隔离点 |
| 纯模型 | `FileShelfModel.swift:86-95` | `FileShelfModel(items:)`、`private(set) var items: [FileShelfEntry]`（最新在前）、`capacity 24`、`stackThreshold 5` |
| 条目字段 | `FileShelfModel.swift:18-24, 27-37` | `FileShelfMember(name:path:isFolder:bookmark:identity:)`；`FileShelfEntry(id:kind:name:members:takenFile:addedAt:)`，`kind ∈ {file, folder, stack, text, image, link}` |
| 失效状态 | `FileShelfModel.swift:60-72` | `FileShelfAvailability.available/inTrash/volumeOffline/missing`，`label` 给出灰格文案 |
| 控制器注入点 | `FileShelfView.swift:88-92` | `hostStrip: () -> (hasNotch: Bool, height: CGFloat)`、`onRowsChanged`、`airDropHandler: (([URL]) -> Void)?` |
| 打开卡前置 | `FileShelfView.swift:173-192` | `openCard()` 要求 `FileShelf.enabled == true`、`!rows.isEmpty`、`leases != nil`（`NotchLeaseHub`，见 §3） |

安全 fixture 做法：`FileShelfStore(root: <临时目录>, isEnabled: { true })` → `FileShelfController(store:)`。要纯数据可用 `FileShelfModel(items: [...])`，`isValid`（`:43-56`）会逐条过滤，所以构造的条目必须自洽（如 `.file` 必须 `members.count == 1` 且 `path` 非空或 `bookmark != nil`）。
注意 `FileShelfController.cell`（`:109`）会读 `FileShelf.enabled`（`FileShelfStore.swift:12-15`，最终落到 `UserDefaults.standard`）和 `ReleaseDefaults`（不在本包范围，未读）；`ReleaseDefaults.swift` 与 `SystemQuietState`/`NotchLeaseHub`/`NotchRow`/`FileShelfActions`/`FileShelfCardLayout`/`FileShelfClearUndo`/`FileShelf.enabled` 的实现都在授权范围外，**均在 1328 行之内被引用但未在本包逐一核对签名**。

### 1.3 属于这两条路径、但本次不可安全调用的入口（明确列出，不发明替代）

- `AudioOutputRoutes.list()`（`AudioOutputRoutes.swift:13`）：遍历 `kAudioHardwarePropertyDevices`，对每个设备读 `kAudioObjectPropertyName`（设备名，可能含人名）——**会碰到系统声音配置**。
- `AudioOutputRoutes.currentKind()`（`:26`）：读默认输出设备的传输类型与名字。
- `AudioOutputRoutes.select(_:)`（`:34`）：`setDefault(kAudioHardwarePropertyDefaultOutputDevice)`（`:38`）并把 `kAudioHardwarePropertyDefaultSystemOutputDevice` 一起换掉（`:40`）——**真的改这台机器的声音输出**，绝不能进工具链。
- `FileShelfController.start()`（`FileShelfView.swift:114-119`）→ `FileShelfStore.start()`（`FileShelfStore.swift:106-125`）：读 `items.json`、订阅 `NSWorkspace.didMount/didUnmount`、跑一次 `sweep(.launch)`（`:123`），`sweep` 会解析书签并对真实路径 `fileExists`。**没有安全 fixture 路径**，除非换掉 `root`。
- `FileShelfController.openCard()`（`:173-192`）：内部调 `store.refreshForCardOpen()`（`:188`）→ `sweep(.cardOpen)`（`FileShelfStore.swift:137`），同样触及真实文件。
- 真实书签：`FileShelfBookmarks.member(for:)`（`FileShelfStore.swift:28-37`）建 bookmark data（`options: []`，普通书签，**不是 security-scoped**，`:32-33`）与 `identity(of:)`（`:49-56`，读 `systemFileNumber`）；`resolve(_:)`（`:40-47`）用 `.withoutUI / .withoutMounting` 解析。成员应只用手写 `bookmark: nil` + 假 `path` 构造。
- QuickLook：`FileShelfThumbnails.generate`（`FileShelfView.swift:44-58`）走 `QLThumbnailGenerator`，`preview(rowID:)`（`:364-385`）走 `QLPreviewPanel.shared()` + `NSApp.activate()`。都会真读文件并抢窗口焦点。缩略图 fixture 只能靠 `FileShelfController.image(for:)`（`:165-167`）在缓存为空时退回 `FileShelfIcons.icon(for:)`（`:24-32`）——即**类型图标**，不走 QuickLook。
- `NSWorkspace.shared` 系列：`open(rowID:)`（`:294`）、`open(rowID:withApplicationAt:)`（`:300`）、`reveal(rowID:)`（`:306`）、`applications(for:)`（`:320`）、`airDrop`→`NSSharingService`（`:330-336`）、`NSPasteboard.general`（`copyToPasteboard`，`:312-314`）。全部真实副作用，不入 fixture。

---

## 2. 源码 ↔ 设计稿差异（最多 6 项，均给文件行号与源码原文）

### D1 — 列表总高与“卡往下长”的字面公式不一致（确定）
- 实际源码：`NowPlayingCardLogic.swift:104-107`
  `static func listTotalHeight(deviceCount: Int) -> CGFloat { 84 + CGFloat(visibleRows(deviceCount: deviceCount)) * rowHeight + 36 }`，`visibleRows`（`:102`）= `min(5, max(1, deviceCount))`，`rowHeight = 34`（`:54`）。
- 稿的具体依据：`正在播放.html` 稿与 `NowPlayingCardLogic.swift:11` 抄录的稿面数字“输出设备列表：卡往下长到放得下，每行 34，超过 5 行就滚；总高 = 84 + 行数 × 34 + 36”。
- 差异：公式本身逐字一致；但**取整规则不同源**——`visibleRows` 对 `deviceCount = 0` 回落到 `1`，即稿面“空列表”会算成 1 行高（84 + 34 + 36 = 154），而稿说的是“放得下”。若设计意图是 0 行时只有头部与页脚（84 + 0 + 36 = 120），此处是缺陷；稿面未画出 0 行状态，**判定为待复现**：需要设计稿对“一个设备都没有”这一刻给出明确高度。
- 行数展开见 D3。

### D2 — 进度条时长来源：稿面写“时长”，实现按“流健康度”决定（确定）
- 实际源码：`NowPlayingCardLogic.swift:199-201`
  `static func isSeekable(streamHealthy: Bool, duration: Double?, artist: String) -> Bool { guard streamHealthy, let duration, duration > 0 else { return false }; return !isAdvertisement(duration: duration, artist: artist) }`
- 稿的具体依据：`正在播放.html` 推进度条那一段（`NowPlayingCardLogic.swift:9` 抄录：进度条宽 = 卡宽 − 28，感应带 80…100；平时 4 高，按下 8 高）——稿把拖动写成进度条自身的行为，没有“先看推送流是否健康”这一前置。
- 差异：实现额外要求 `streamHealthy == true`，而 `streamHealthy` 由 `NowPlayingStreamVerdict.isGivenUp`（`:417-422`）决定，是**不可从 `NowPlayingCardContent` 推出的运行时状态**。稿面若要求“有进度条就能拖”，则退路（Music / Spotify）下不可拖即为缺陷。稿在此处未写，**判定为待复现**，需设计确认退路期间的进度条是否显示为不可拖。

### D3 — 广告判据用到“没有歌手”，稿面按“无歌手的短音频”描述（确定，取向待复现）
- 实际源码：`NowPlayingCardLogic.swift:191-196`
  `static let adMaximumDuration: Double = 60`；`isAdvertisement(duration:artist:)` = `duration != nil && artist.trimmingCharacters(in: .whitespaces).isEmpty && duration <= 60`（注释：稿“边缘情况”）。
- 稿的具体依据：`正在播放.html` “边缘情况”一节 → 实现注释 `NowPlayingCardLogic.swift:190` 明确写“没有歌手且时长不超过 60 秒当作广告（稿“边缘情况”）”。
- 差异：**取值口径**。`trimmingCharacters(in: .whitespaces)` 只裁空格与制表符一类字符，**不裁换行**（`.whitespaces` 不含 `.newlines`）；同一文件对文字输入用的是 `trimmingCharacters(in: .whitespacesAndNewlines)`（`FileShelfStore.swift:166`）。若某播放器把歌手写成 `"\n"`，这里判不成广告、进度条反而可拖——与稿面“没歌手 = 广告”的意图相左。这是实现内部不一致，可判为缺陷；稿面没有写“空白”的具体字符集，**结论待复现**（需要设计或播放器样本确认歌手字段会不会只含换行）。

### D4 — “歌名 13 半粗 / 歌手 11（字色取封面）”与实现字号一致，但歌手字色的来源有一个未核实的缺口（待复现）
- 实际源码：`NowPlayingCard.swift:246-247`
  `private let titleField = NowPlayingCard.label(13, .semibold)`；`private let artistField = NowPlayingCard.label(11, .medium)`；`label` 定义在 `:301-309`，默认 `alpha 0.92`，`textColor = NSColor.white.withAlphaComponent(alpha)`。
- 稿的具体依据：`正在播放.html`（`NowPlayingCardLogic.swift:8` 抄录：“歌名 13 半粗在 (82, 37)，歌手 11 在 (82, 55)，**歌手用封面的字色**”）。
- 差异：构造处用的是白色 0.92，稿要求歌手取封面取色。`NowPlayingCard.swift` 确有 `private var palette: ArtworkPalette = .neutral`（`:209`）与封面取色的接线意图，但**“把 artistField.textColor 换成 palette 取色”的那一段在本次未读区间内，未核对**。因此这里**只报待复现**，不判缺陷：需要复核 `FileShelfView` 之外的 `NowPlayingCard.swift:401-1252` 是否真的给歌手单独上色。

### D5 — 文件架“全部移出”/ 撤销的标题串与稿面文案：代码里写死，稿面另有来源（待复现，缺口）
- 实际源码：`FileShelfView.swift:263-276`（`removeAll()`：`clear.begin(count: now:)`、`store.removeAll()`、`announce(FileShelfActions.cardSpoken(count: 0) + "，可以撤销")`、`Timer` 用 `FileShelfCardLayout.clearHold`）；`:283-290`（`undo()`：`clear.undo(at: now:)` + `store.undoRemove()`）；`:245-248`（`announce(_:)`）。
- 稿的具体依据：`文件架.html` “全部移出”一节（`FileShelfView.swift:2-3` 抄录：规则与数字照 `文件架.html` 的“文件架卡”“一格能做的”“全部移出”）；`docs/copy-guide.md` 相关用词。
- 差异/缺口：**代码只提供 `clear`（`FileShelfClearUndo`）、`FileShelfActions.*`、`FileShelfCardLayout.clearHold` 三处符号，三者的定义都不在本次授权读取范围内**（`FileShelfView.swift` 1328 行中其余片段未读）。因此无法核对“文件架空了”“撤销”这两个串是否照 `docs/copy-guide.md` 的用词，也无法核对 `clearHold` 是否等于稿面的 5 秒（注释 `:263` 写“5 秒后卡收回”，`FileShelfStore.swift:91` 的 `undoDelay` 默认写 `5`，但两者是不同常量）。**此处只指出缺口：需要能读到 `FileShelfClearUndo` / `FileShelfActions` / `FileShelfCardLayout` 的定义才能结案，不在此处发明实现。**

### D6 — 文件架格子数与失效文案：模型层一致，视图层的“暂存”灰化读取不可核对（缺口）
- 实际源码：`FileShelfModel.swift:87` `static let capacity = 24`；`:97` `var isFull: Bool { items.count >= Self.capacity }`；`:231` `static func missingNotice(count: Int) -> String? { count > 0 ? "\(count) 个找不到了" : nil }`；`FileShelfStore.swift:346-348` `count(_:)` 供“落点小岛”灰化。
- 稿的具体依据：`文件架.html` “存什么、存在哪”与“边缘情况”；`FileShelfModel.swift:2` 注释“规则来自 `docs/design-drafts/文件架.html` 的‘存什么、存在哪’和‘边缘情况’”；文案 `找不到`/`在废纸篓里`/`硬盘没接上` 在 `FileShelfModel.swift:64-71`。
- 差异：**“暂存”这一处境的实际调用入口不在本次范围内**（注释 `FileShelfStore.swift:345` 写“落点小岛靠它把‘暂存’灰掉”，落点小岛的视图不在授权读取清单里）。`count(_:)` 是异步的（`io.async`），而 `isFull` 在 `FileShelfModel` 是同步值——两者都能给出“满/未满”，但**没有任何证据说明落点小岛用的是哪一个**。判定为待复现：需要能读到落点小岛那一侧才谈得上差异。

**没有更多能确定的差异**：`正在播放.html` / `文件架.html` 的其余条款（420×175.5、底角 28、封面 56×56 圆角 14、感应带 80…100、按下 8 高、每行 34、最多 5 行、叠放阈值 5、一叠上限 999、格子 24）在源码里都能逐条对上（`NowPlayingCardLogic.swift:19-55`、`FileShelfModel.swift:28, 87-88`），不再重复列出。

---

## 3. 下一批最小原生状态矩阵（两种表面）

### 3.1 正在播放大卡

| 状态 | fixture | 断言点（源码） |
| --- | --- | --- |
| 正常 | `Timeline(duration: 240, elapsed: 72, stamp: t0, rate: 1)`，`seekable: true`，`isPaused: false` | `fraction(atEpoch: t0+…)`、两次时钟（`clock` 闭包换假钟，`:199-200`）之间 `NowPlayingCardText.clock/remaining`（`:209-221`）、`pendingTimerCount`（`:228`）在暂停后回 0 |
| 空 | `title == ""`、`artist == ""`、`timeline: nil`（直播） | `NowPlayingCardContent.spoken`（`:182-186`）应只念标题或空串；`NowPlayingTimeline.isLive == true`（`:148`）时 `fraction == nil`（`:158-161`），剩余时间不画 |
| 长标题 | `title` 远超 `frames.title.width`（`420 - 82 - 14 = 324`，`:83`），`artist` 同样超长，含 CJK 与 emoji | `NowPlayingCard.label` 的 `lineBreakMode = .byTruncatingTail`（`:305`）、`maximumNumberOfLines = 1`（`:306`）；行高 `titleHeight 18` / `artistHeight 15`（`:37, 39`）不被撑破 |
| 失效（设备/流） | `loadRoutes` 回 `[]` 或全 `isCurrent == false`；`streamHealthy == false` | `AudioOutputList.currentSymbol(in:)` 回落到 `speaker` 符号（`:397-399`）；`isSeekable` 为 false（`:199-201`）→ `NowPlayingScrub.press` 返回 false（`:265-271`）、`barHeight` 保持 `restHeight`（`:248`） |
| 失效（列表行） | 手写 `AudioOutputRoute` 全 `isCurrent == false` | `NowPlayingRouteRow.checked` 初值 `route.isCurrent`（`:67`），无勾选时列表里没有“正在使用” |

### 3.2 文件架卡

| 状态 | fixture | 断言点（源码） |
| --- | --- | --- |
| 正常 | `FileShelfStore(root: 临时目录, isEnabled: { true })`；`FileShelfModel(items: [一项 .file / 一项 .folder])` | `FileShelfEntry.isValid`（`:43-56`）；`FileShelfModel.judge(path:volumeMounted:exists:)`（`:208-214`） |
| 空 | `FileShelfModel()` | `items.isEmpty`；`FileShelfModel.missingNotice(count: 0) == nil`（`:231`）；`FileShelfController.openCard()` 因 `rows.isEmpty` 返回 false（`FileShelfView.swift:174`） |
| 长标题 | 12 个 CJK 字符的 `name`（`FileShelfStore.shortName` 的上限，`FileShelfStore.swift:339-343`）与超长 `path` | `shortName` 的截断与 `/:\n\r\t → 空格` 替换；`FileShelfView.swift:27` 取 `entry.takenFile ?? entry.members.first?.name ?? entry.name` 的回落链 |
| 失效 | 四态各一条：`inTrash`（`path` 含 `.Trash`，`:212`）、`volumeOffline`（`volumeMounted: false`）、`missing`（`exists: false`）、叠放混合 | `FileShelfModel.combine(_:)` 取最差（`:217-220`）；`sweepIDs(states:phase:)`（`:223-229`）——`.launch` 清废纸篓、`.cardOpen` 清找不到、`.volumeChange` 一个都不清 |
| 容量 | `capacity 24`、`stackThreshold 5`、`maxStackCount 999` | `add(files:)` 整批拒收 `Rejection.full`（`:144-147`）、`add(taken:name:takenFile:)` 的 `.full`（`:160`）、`chunks`（`:265-267`） |

### 3.3 哪些操作**不能**安全调用（一律排除在矩阵外）

- 音频：`AudioOutputRoutes.list()` / `currentKind()` / `select(_:)`（`AudioOutputRoutes.swift:13, 26, 34`）。
- 真实书签 / 磁盘：`FileShelfBookmarks.member(for:)` / `resolve(_:)` / `identity(of:)` / `mountedVolumeUUIDs()`（`FileShelfStore.swift:28, 40, 49, 59`）；`FileShelfStore.start()` / `stop()` / `refreshForCardOpen()` / `clearAll()` / `add` / `addText` / `addImage` / `addLink` / `remove` / `removeAll` / `undoRemove`（`FileShelfStore.swift:106-245`，全部真读写 `items.json` 与“拿来的”目录）。
- QuickLook / 前台抢占：`FileShelfThumbnails.generate`（`FileShelfView.swift:44`）、`preview(rowID:)`（`:364`，含 `NSApp.activate()`）、`closePreview()`（`:387`）。
- 系统副作用：`open` / `open(withApplicationAt:)` / `reveal` / `copyToPasteboard` / `applications(for:)` / `airDrop`（`FileShelfView.swift:292-337`）。
- 全局开关：`FileShelf.enabled`（`FileShelfStore.swift:12-15`，写 `UserDefaults.standard`）——写它等于改这台机器的真实设置；`FileShelfController.setEnabled`（`FileShelfView.swift:122-137`）还会 `store.clearAll()` 删真实目录。

---

## 4. 替换 / 避开清单（默认路由列表、真实书签、QuickLook）

- **默认路由列表**：`NowPlayingCard.loadRoutes`（`NowPlayingCard.swift:192`）默认闭包 `{ AudioOutputRoutes.list() }` **必须替换**为返回手写 `[AudioOutputRoute]` 的闭包，否则每一次“点开播放到”都会去读系统声音输出与设备名。
- **真实书签**：`FileShelfStore.root`（`FileShelfStore.swift:91`）默认 `FileShelf.defaultRoot`（`:17-21`，`~/Library/Application Support/WindowShade/文件架`）**必须替换**成临时目录；`isEnabled` 默认读 `FileShelf.enabled`（`:12-15`）**必须替换**成 `{ true }` 之类的常返闭包，避免依赖 `UserDefaults` 的真实值。成员一律 `bookmark: nil` + 假 `path` + 显式 `identity`，绕开 `FileShelfBookmarks`。
- **QuickLook**：缩略图与预览不可调用；需要“有图”的画面一律退到 `FileShelfController.image(for:)` 的类型图标分支（`FileShelfView.swift:165-167`）。
- **默认 `store`**：`FileShelfController.init(store:)`（`:96`）的默认参会在构造时就建出指真实目录的 `FileShelfStore`；即使不调 `start()` 也不该依赖它，一律显式传 temp store。
- **不改产品**：以上都靠既有闭包/参数（`:88-92`、`:192`、`FileShelfStore.swift:91-92`）注入，**没有改任何产品源码，也没有新增实现**。

---

## 5. 明确不做的事

- 不生成假截图，不声称任何视觉通过（本包未渲染、未跑 App）。
- 不调用音频 / 系统 / 网络，不读真实文件架或用户数据目录。
- 不提交、不签名、不发布。
- **缺口（不发明实现）**：`NowPlayingArtworkImage`、`NotchLeaseHub`、`NotchRow`、`SystemQuietState`、`FileShelfActions`、`FileShelfCardLayout`、`FileShelfClearUndo`、`ReleaseDefaults`、`FileShelfView`（视图类型本身的声明）、`NowPlayingCard.swift:401-1252` 中未读片段 —— 均未在本包范围内，涉及这些的判断已在 D4–D6 里标注为“待复现”。
