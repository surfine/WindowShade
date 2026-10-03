# L1：在场与自动锁状态机

本份是完整纯逻辑实现与可运行测试，不是请你重写的参考骨架。按给出的文件安装，原样编译、跑测，贴原始结果。遇到决定表未覆盖的情况就停止并报告输入、状态与缺口，不自行发明新行为。

## 可写文件

`prototype/Core/PresenceLock.swift`、`tests/PresenceLockTests.swift`、`tests/run-presence-lock-tests.sh`。测试支撑 `tests/support/WS2TestSupport.swift` 和共享 `prototype/Core/Contracts.swift` 由主模型只安装一次，执行本包时只读。

不修改App、构建脚本、签名、发布、权限、个人设置或其他包。若目标路径已有同名实现，先比较SHA256；仅当主模型确认它是第一轮骨架并批准替换后才覆盖。本包工具默认输出新暂存目录，不覆盖仓库。

## 前置与既有符号

规格来源：`docs/dynamic-lock.md；docs/handoff/deepseek-dynamic-lock.md`。共享类型必须是本份contracts版本，不能另造Context/Token/RequestID。完整符号索引见 `../../contracts/existing-symbols.md`。

不调用既有App符号。本核只依赖Foundation、WS2契约和本文件值类型。对外副作用都是枚举，必须由后续App包调用既有接口；不要为了看到效果把Cocoa/CGEvent/AX带进本核。授权边界统一参照AuthorizationService.swift:28，纯核不直接调用它。

## 决定表

|情况|怎么做|为什么|
|---|---|---|
|初始/不可用/未知锁态|unknown，不能当away或unlocked|读取不到不是人离开|
|明确断线|已识别的当前generation才变away，开始1.5秒静默宽限|旧连接断线不能杀新连接|
|无新读取|保留在场状态；只有已经发出的具体read在2秒无回应才away|修正5秒读一次却2秒判断开的冲突|
|read回调错generation/request|忽略，不能重建已删除的连接|异步归属必须一致|
|手机+必需手表|两者都明确away才倒数；任一unknown/connecting阻止|避免失能误锁|
|RSSI很低|不据此判离开|弱信号不是身份/离席证明|
|宽限后|倒数10秒；到点只prepareCommit，宿主最终排空取消再commit|提供真正最后取消点|
|输入与commit同批|handleBatch先处理输入，取消并进入连续60秒静默期|晚到定时器不抢用户|
|静默期还有输入|从最后一次输入重算60秒|不是第一次取消后固定一分钟|
|锁屏提交|按tuckPrivate→pauseKnownMedia→requestLock发意图；3秒内实际锁态回执才ownedLock|不能把API调用成功当屏幕已锁|
|相机刚开就无人/坏帧/停回调|不判离开；需先有健康有人帧、30秒无人输入、10秒连续健康缺人|黑屏和失能不能当离席|
|手动锁屏|不拥有自动锁归属；不会形成返回授权候选|避免接管用户主动锁|
|返回候选|自己的锁、新连接且读回执晚于锁、刷脸与返回均启用、RSSI严格>-60连续2秒|只启动受限身份流程，不直接解锁|
|返回RSSI等于阈值/NaN/断样>1秒|清连续时长|严格边界和坏值不能凑足两秒|
|返回尝试|每次唯一token，每次结束重新积累，最多3次|防无限挑战和重放|
|关闭/睡眠后旧锁回执|不建立新归属；唤醒须真实锁态和新连接|过期回调不能赋权|
|faceEnabled=false|不开放手机单因素返回|这是保守冻结项；改变需Aaron另作明确决定|

## 时钟、并发和回调归属

宿主串行驱动一个实例；Swift Sendable表示可以安全传值，不表示允许多个线程同时改同一实例。用同一WS2Clock，测试注入Instant。UI/HID/后端序号统一由宿主事件入口分配，来源原始seq不能直接跨源比较。先处理环境撤销，再丢旧代次；其余保持接收顺序。same instant允许多个不同seq。关闭/暂停不重置令牌编号源。

## 常量及出处

规格值：宽限1.5秒、倒数10秒、读取超时2秒、输入静默60秒、相机前置空闲30秒、返回强信号2秒、默认阈值-60dBm、最多3次。推荐冻结：缺人10秒、相机帧新鲜度2秒、RSSI最大间隔1秒、锁回执3秒；RSSI合法范围-127...20和可配阈值-100...-20只做输入防错，不是距离标定。L2五秒调度不在此核实现。

下面列出实现中含数值或静态常量的原始行，防止实施时漏掉内联边界。数学0/1、数组索引、纳秒换算和格式位数是实现常量；只有上段明确写“规格”的才来自产品规格，其余产品/安全边界均属本轮推荐，待主模型冻结。不要把它们描述成真机测量。

```swift
// L18
var returnThresholdDBm: Double = -60 // 源规格；不是距离测量。
// L22
case connected(Device, generation: UInt64)
// L23
case disconnected(Device, generation: UInt64)
// L24
case readStarted(Device, generation: UInt64, request: UInt64)
// L25
case readSucceeded(Device, generation: UInt64, request: UInt64)
// L27
case rssi(generation: UInt64, dbm: Double)
// L43
private struct Probe: Sendable { let id: UInt64; let deadline: WS2.Instant }
// L45
var generation: UInt64 = 0; var status = Status.unknown
// L46
var probe: Probe?; var lastRequest: UInt64 = 0; var replyAt: WS2.Instant?
// L48
static let grace: UInt64 = 1_500 * WS2.Duration.millisecond
// L49
static let countdown: UInt64 = 10 * WS2.Duration.second
// L50
static let responseTimeout: UInt64 = 2 * WS2.Duration.second
// L51
static let inputCooldown: UInt64 = 60 * WS2.Duration.second
// L52
static let cameraIdle: UInt64 = 30 * WS2.Duration.second
// L53
static let cameraMissing: UInt64 = 10 * WS2.Duration.second // 推荐，需由主模型冻结。
// L54
static let cameraFreshness: UInt64 = 2 * WS2.Duration.second
// L55
static let returnHold: UInt64 = 2 * WS2.Duration.second
// L56
static let rssiFreshness: UInt64 = 1 * WS2.Duration.second
// L57
static let lockReceiptTimeout: UInt64 = 3 * WS2.Duration.second // 推荐，超时不认作自己锁定。
// L61
private(set) var returnAttempts = 0
// L73
private var phoneGenerationAtLock: UInt64 = 0
// L88
let a = priority($0.element), b = priority($1.element)
// L89
return a == b ? $0.offset < $1.offset : a < b
// L91
return sorted.flatMap { handle($0.element, at: now) }
// L125
generation > 0, links[device]?.status != .unknown else { return [] }
// L161
receiptDeadline = nil; returnAttempts = 0; nearSince = nil; lastRSSI = nil
// L168
returnAttempts = 0; pendingReturn = nil; nearSince = nil; lastRSSI = nil; receiptDeadline = nil
// L179
if links[.phone]?.generation == generation && (!dbm.isFinite || !(-127 ... 20).contains(dbm)) {
// L185
configuration.returnThresholdDBm.isFinite, (-100 ... -20).contains(configuration.returnThresholdDBm),
// L186
dbm.isFinite, (-127 ... 20).contains(dbm),
// L192
if lastRSSI.map({ now.elapsed(since: $0) > Self.rssiFreshness }) ?? true { nearSince = now }
// L204
var deadlines = links.values.compactMap { $0.probe?.deadline }
// L210
let step = remaining == 0 ? 0 : ((remaining - 1) % WS2.Duration.second) + 1
// L232
returnAttempts < 3, pendingReturn == nil, let since = nearSince, let last = lastRSSI,
// L235
returnAttempts += 1; pendingReturn = attempt; nearSince = nil; lastRSSI = nil
// L260
cooldownUntil.map({ now >= $0 }) ?? true else { return nil }
// L286
let n = deadline.elapsed(since: now); return Int(n / WS2.Duration.second + (n % WS2.Duration.second == 0 ? 0 : 1))
// L290
case .disable, .sleep, .sensorUnavailable, .lockStateUnknown, .userInput, .systemLocked, .systemUnlocked: return 0
// L291
case .tick, .commitLock: return 2
// L292
default: return 1
```

## 文案、图标、动效

倒数文案“将在 N 秒后锁定”；取消“已取消”；信号失能“暂不可用”。图标lock.fill，倒数timer，取消xmark。calm/reduced令牌，不播恐吓音。不显示“已解锁”，本核没有unlock效果。

数值取 `docs/design-system.md:332–347` 的令牌。UI示意映射只约束后续App，纯核不得为这些项额外引入动画对象。所有原始状态/动作字符串另见 `COPY.md`；动态private值不能写日志。

## 验收

在交付包根：
```sh
bash packages/L1/tests/run-presence-lock-tests.sh
```
安装到仓库后，从仓库根：
```sh
bash tests/run-presence-lock-tests.sh
```
退出码必须0，stdout包含 `PASS L1:`、`0 failures`，不出现 `FAIL ` 或编译error。精确用例/断言数量及完整输出见本包`VALIDATION.txt`；不要把这份历史输出贴成你的Mac实测。

本机再执行 `cd prototype && bash ./build.sh --check`，退出0并包含“==> 编译验证通过”。方法和禁止事项见BuildBaseline；Linux通过不能证明AppKit、硬件、身份、网络和能耗通过。脚本不靠SwiftPM拉依赖，不联网。

## 测试输入与结果

见 `TEST-CASES.md`。每一行对应测试代码的同名CASE，并提供原文件行范围。测试有明确输入值、状态和效果断言；不是只检查有没有字符串或文件。

## 不要做

不调用CoreBluetooth/IOBluetooth、Vision、CGSession，不抓心率，不写密码，不从RSSI或识别人脸框推出身份，不修改现有授权账以允许锁屏万能授权。

不删断言、不降Swift语言版本、不加try?吞掉编译/测试失败、不用mock结果冒充硬件支持。不得签名、安装运行App、改hooks或提交仓库；这些由主模型按授权处理。
