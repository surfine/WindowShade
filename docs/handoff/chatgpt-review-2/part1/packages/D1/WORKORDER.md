# D1：指挥模式完整状态机

本份是完整纯逻辑实现与可运行测试，不是请你重写的参考骨架。按给出的文件安装，原样编译、跑测，贴原始结果。遇到决定表未覆盖的情况就停止并报告输入、状态与缺口，不自行发明新行为。

## 可写文件

`prototype/Core/ConductorSession.swift`、`tests/ConductorSessionTests.swift`、`tests/run-conductor-session-tests.sh`。测试支撑 `tests/support/WS2TestSupport.swift` 和共享 `prototype/Core/Contracts.swift` 由主模型只安装一次，执行本包时只读。

不修改App、构建脚本、签名、发布、权限、个人设置或其他包。若目标路径已有同名实现，先比较SHA256；仅当主模型确认它是第一轮骨架并批准替换后才覆盖。本包工具默认输出新暂存目录，不覆盖仓库。

## 前置与既有符号

规格来源：`docs/conductor-v2.md；docs/handoff/deepseek-conductor.md`。共享类型必须是本份contracts版本，不能另造Context/Token/RequestID。完整符号索引见 `../../contracts/existing-symbols.md`。

唯一调用的既有业务实现是 `prototype/Core/ConductorGesture.swift:47` 的 `ConductorRecognizer.recognize(_ stroke: [ConductorPoint]) -> Result<ConductorGesture, ConductorRejection>`、`:73`的 `beatPreview(_:) -> Int`、`:179`的 `ConductorEffort.requested(by:)`。保持该文件字节不变；基准副本在baseline，仅供离线测试。依赖同包集D2的完整ConductorCapabilities，不接受第一轮旧结构混装。

## 决定表

|情况|怎么做|为什么|
|---|---|---|
|初始/首次连接|默认关闭；显式enable+可信context+支持能力后连接，还要等snapshot才可提交|连接不等于后端空闲|
|多设备抢同一会话|已有可信对端时拒绝另一个peer；切换必须撤旧连接并推进epoch|保持单输入所有者|
|轨迹中|只显示形状和beatPreview，不提前改档|五拍前四拍不能先选xhigh|
|抬手|只调用已有ConductorRecognizer；坐标非法、>2048点、>6秒或灰区拒绝|不改已验证识别器凑成功|
|声调/节拍|一二三四声映射low/medium/high/xhigh；1...6拍映射low...ultra；模型域只有1...4槽|域不同不能混淆|
|model槽位|稳定provider+modelID；空槽/5拍/6拍明确拒绝；跨provider只请求新会话|不按目录序号或显示名匹配|
|不支持档位|D2拒绝，没有静默降档；capability变化作废旧候选|用户要的档位不能是假标签|
|max/ultra|先cost候选；只收候选显示后新按压/新点按；绑定草稿摘要和上下文|防旧松手、换稿复用费用确认|
|录音开始|需显式source；发startCapture后等audioSamples才显示正在听|按钮按下不是已录到声音|
|录音结束|松手停止；有样本才等转写；转写形成草稿，不自动发送|用户仍保有提交决定|
|输入源失效|停止本次capture、不自动选别的麦克风；旧transcript不写草稿|避免偷换来源|
|人工改稿后转写才到|baseRevision不符则保留人工草稿|旧异步结果不覆盖新输入|
|播放：空闲且有稿|发一次submit，绑定精确配置、commandID、context、digest|不靠合成Enter提交|
|播放：运行且有稿|发turn/steer意图，绑定当前turnID；等steerAccepted才说已补入|请求已发不是已接收|
|播放：运行且无稿|发interrupt；真实中断回执才说已停止|不把发送成功当任务结束|
|已请求/已接受/已开始|三个状态分开；start可先到，后续accept不得把UI倒退|异步先后不稳定|
|实际配置未知/不一致|不知道就说“实际档位还没确认”；读回值不同明确显示请求与实际|不能把requested复制成actual|
|15秒无回执|进入不确定，查询同commandID；不重发；证明未执行后还需人再按|超时不能安全推断未执行|
|运行中选下一档|仅nextConfig改变，currentRequested/actualConfig保持本轮证据|下一轮选择不能重写当前事实|
|TV单击/长按/仅click源双击|down/up源短按换域、0.5秒开会话；clickOnly350ms窗口双击开列表，单击到期才换域|不用猜不存在的按钮阶段|
|返回|先取消眼前审批/候选/列表；草稿第一次提示，2秒内第二次丢弃|不把同一按键同时作用两层|
|普通审批|只向A1.choose发confirm意图；旧按压松手不能确认|所有批准通过同一授权账|
|高/未知风险审批|新确认后一次随机口令挑战；phrase+voice只能作为附加证据；失败/超时走现有主身份路径|声纹布尔值不是授权|
|审批在前台后台发消息|保留approval/voice/authenticating显示，不被任务状态覆盖|只对看见的对象操作|
|切回遥控/抢占/取消输入|取消轨迹、录音、候选与旧按键尾部；不interrupt后台任务|输入生命周期不等于任务生命周期|
|锁屏/断线/重连|锁屏清敏感稿和context；断线保留未发稿但新epoch先snapshot；跨会话旧稿不可直接提交|防旧回调与目标漂移|
|电源按钮|只退出当前指挥连接，后端任务继续|指挥域不继承遥控域息屏动作|

## 时钟、并发和回调归属

宿主串行驱动一个实例；Swift Sendable表示可以安全传值，不表示允许多个线程同时改同一实例。用同一WS2Clock，测试注入Instant。UI/HID/后端序号统一由宿主事件入口分配，来源原始seq不能直接跨源比较。先处理环境撤销，再丢旧代次；其余保持接收顺序。same instant允许多个不同seq。关闭/暂停不重置令牌编号源。

## 常量及出处

来自conductor-v2：四声/六拍、四模型槽、0.5秒长按、6秒识别窗口、运行与下一轮分开。其余是本轮推荐冻结：轨迹2048点、草稿32768字节、录音60秒、最终转写10秒、命令回执15秒、clickOnly双击350ms、丢稿二按2秒、点按50...250ms且extent<0.03、0.03...0.15拒识、列表拖动步长0.12、挑战最长30秒。能力最多256、会话列表64、D2票30秒均为本地防错边界。详见常量原行和逐用例。

下面列出实现中含数值或静态常量的原始行，防止实施时漏掉内联边界。数学0/1、数组索引、纳秒换算和格式位数是实现常量；只有上段明确写“规格”的才来自产品规格，其余产品/安全边界均属本轮推荐，待主模型冻结。不要把它们描述成真机测量。

```swift
// L30
case .accepted(let provider, let effort): return effort.map { "\(provider.displayName) 接受了 · \($0)" } ?? "实际档位还没确认"
// L31
case .running: return "开始跑了" // turnID 是不透明 ID，不能伪装成“第 4 轮”。
// L89
case approvalChoice(WS2.ApprovalKey, confirm: Bool, deny: Bool, beganAt: WS2.Instant, sequence: UInt64, voicePassed: Bool)
// L93
struct Draft: Equatable, Sendable { let text: String; let digest: WS2.Digest; let revision: UInt64; let owner: WS2.Context }
// L94
private struct Press: Sendable { let id: UInt64; let beganAt: WS2.Instant; let sequence: UInt64; var consumed = false }
// L95
private struct Stroke: Sendable { let beganAt: WS2.Instant; let sequence: UInt64; var points: [ConductorPoint] }
// L97
let id: WS2.Token; let sourceLabel: String; let baseDraftRevision: UInt64
// L107
private struct Confirmation: Sendable { let beganAt: WS2.Instant; let sequence: UInt64 }
// L109
static let maximumStrokePoints = 2048
// L110
static let maximumDraftBytes = 32_768
// L111
static let captureLimit: UInt64 = 60 * WS2.Duration.second
// L112
static let transcriptionLimit: UInt64 = 10 * WS2.Duration.second // 推荐；超时保留已有草稿。
// L113
static let commandLimit: UInt64 = 15 * WS2.Duration.second // 推荐；不是“失败”判据，只进入未知态。
// L114
static let doubleClick: UInt64 = 350 * WS2.Duration.millisecond
// L115
static let discardInterval: UInt64 = 2 * WS2.Duration.second
// L116
static let tapLimit: UInt64 = 250 * WS2.Duration.millisecond
// L117
static let tapMinimum: UInt64 = 50 * WS2.Duration.millisecond
// L118
static let tapExtent = 0.03 // 推荐；0.03…0.15 的灰区拒识，不猜点按。
// L131
private var lastEpoch: UInt64 = 0
// L143
private var lastPressID: UInt64 = 0
// L147
private var draftRevision: UInt64 = 0
// L193
validCapabilities(caps), caps.contains(where: { $0.accepts(initial) }),
// L194
let slots = ConductorModelSlots(modelSlots), !project.isEmpty, project.utf8.count <= 512,
// L195
sessions.count <= 64, sessions.allSatisfy({ $0.context.isValid && !$0.label.isEmpty && $0.label.utf8.count <= 512 }),
// L201
lastPressID = 0; self.capabilities = caps; self.slots = slots; choices = sessions
// L218
actual.map({ $0.model.provider == envelope.context.session.provider }) ?? true else { return [.fault(.malformedInput)] }
// L226
guard validID(id), !label.isEmpty, label.utf8.count <= 256, capture == nil else { return [.fault(.malformedInput)] }
// L250
guard actual.map({ $0.model.provider == envelope.context.session.provider }) ?? true else { return [.fault(.malformedInput)] }
// L255
guard actual.map({ $0.model.provider == envelope.context.session.provider }) ?? true else { return [.fault(.malformedInput)] }
// L279
guard turn == runningTurn, summary.utf8.count <= 1024 else { return [] }
// L289
guard validID(turn), actual.map({ $0.model.provider == envelope.context.session.provider }) ?? true else { return [.fault(.malformedInput)] }
// L292
guard summary.utf8.count <= 1024 else { return [.fault(.malformedInput)] }
// L326
if let p = presses[.tv], !p.consumed { deadlines.append(p.beganAt.adding(500 * WS2.Duration.millisecond)) }
// L327
if let s = stroke { deadlines.append(s.beganAt.adding(6 * WS2.Duration.second)) }
// L330
private mutating func handleButton(_ b: WS2.ButtonEvent, sequence: UInt64, now: WS2.Instant) -> [Effect] {
// L347
let next = max(0,min(choices.count - 1,selected + (b.button == .down ? 1 : -1)))
// L385
private mutating func touch(_ phase: TouchPhase, point: WS2.Point, sequence: UInt64, now: WS2.Instant) -> [Effect] {
// L387
guard point.isFinite, (0...1).contains(point.x), (0...1).contains(point.y) else {
// L398
guard s.points.count < Self.maximumStrokePoints, now.elapsed(since: s.beganAt) <= 6 * WS2.Duration.second else {
// L403
let steps = Int(((start - point.y) / 0.12).rounded(.towardZero))
// L404
sessionList = max(0,min(choices.count - 1,original + steps))
// L409
return show(.trajectory(points: Array(s.points.suffix(128)), beats: min(6,ConductorRecognizer.beatPreview(s.points))))
// L414
let extent = max((xs.max() ?? 0) - (xs.min() ?? 0),(ys.max() ?? 0) - (ys.min() ?? 0))
// L440
let cap = capabilities.first(where: { $0.model == current.model }) else { return [.fault(.missingDependency)] }
// L448
case .tone(let n): gestureName = ["一声","二声","三声","四声"][n - 1]
// L449
case .beats(let n): gestureName = ["一拍","二拍","三拍","四拍","五拍","六拍"][n - 1]
// L476
challenge = Challenge(id: id, confirmation: confirmation, deadline: min(request.deadline,now.adding(30 * WS2.Duration.second)))
// L498
capabilities.contains(where: { $0.accepts(config) }) else { return show(.message("能力信息不可用，请重新选择")) }
// L534
private mutating func replaceDraft(_ text: String, digest: WS2.Digest, sequence: UInt64, now: WS2.Instant) -> [Effect] {
// L535
guard let owner = context, text.utf8.count <= Self.maximumDraftBytes, draftRevision < UInt64.max else { return [.fault(.malformedInput)] }
// L536
draftRevision += 1; draft = text.isEmpty ? nil : Draft(text: text, digest: digest, revision: draftRevision, owner: owner)
// L542
private mutating func proposeCost(_ config: WS2.ExecutionConfig, label: String, sequence: UInt64, now: WS2.Instant) -> [Effect] {
// L574
sessionList = choices.firstIndex(where: { $0.context == context }) ?? 0
// L580
return show(.sessions(choices.map { "\($0.label) · \($0.context.session.provider.displayName) · \($0.running ? "在跑" : "空闲")" }, selected: index))
// L582
private mutating func expire(sequence: UInt64, at now: WS2.Instant) -> [Effect] {
// L606
if let p = presses[.tv], !p.consumed, now >= p.beganAt.adding(500 * WS2.Duration.millisecond) {
// L609
if let s = stroke, now >= s.beganAt.adding(6 * WS2.Duration.second) {
// L642
private func validID(_ text: String) -> Bool { !text.isEmpty && text.utf8.count <= 512 }
// L644
!caps.isEmpty && caps.count <= 256 && caps.allSatisfy(\.isValid) && Set(caps.map(\.model)).count == caps.count
```

## 文案、图标、动效

所有原字在ConductorNotch.text与`COPY.md`，不可润色。推荐D3图标：轨迹hand.draw、已录到waveform、无音源mic.slash、请求发出paperplane、等待确认lock.fill、确认完成checkmark、断开wifi.slash。文字/图标切换calm；列表展开expand；有变化的一次提醒bloom；减少动态reduced。纯核不绘SF Symbols，不伪画Touch ID或Face ID。

数值取 `docs/design-system.md:332–347` 的令牌。UI示意映射只约束后续App，纯核不得为这些项额外引入动画对象。所有原始状态/动作字符串另见 `COPY.md`；动态private值不能写日志。

## 验收

在交付包根：
```sh
bash packages/D1/tests/run-conductor-session-tests.sh
```
安装到仓库后，从仓库根：
```sh
bash tests/run-conductor-session-tests.sh
```
退出码必须0，stdout包含 `PASS D1:`、`0 failures`，不出现 `FAIL ` 或编译error。精确用例/断言数量及完整输出见本包`VALIDATION.txt`；不要把这份历史输出贴成你的Mac实测。

本机再执行 `cd prototype && bash ./build.sh --check`，退出0并包含“==> 编译验证通过”。方法和禁止事项见BuildBaseline；Linux通过不能证明AppKit、硬件、身份、网络和能耗通过。脚本不靠SwiftPM拉依赖，不联网。

## 测试输入与结果

见 `TEST-CASES.md`。每一行对应测试代码的同名CASE，并提供原文件行范围。测试有明确输入值、状态和效果断言；不是只检查有没有字符串或文件。

## 不要做

不改ConductorGesture.swift，不发真实CLI请求、不造workflow、不下载模型、不抓全局麦克风、不用转写口令当编码草稿、不以voiceCheck Bool生成allow。

不删断言、不降Swift语言版本、不加try?吞掉编译/测试失败、不用mock结果冒充硬件支持。不得签名、安装运行App、改hooks或提交仓库；这些由主模型按授权处理。
