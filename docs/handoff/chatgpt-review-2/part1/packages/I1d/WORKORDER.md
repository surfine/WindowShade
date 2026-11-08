# I1d：完整触点组轻点识别

本份是完整纯逻辑实现与可运行测试，不是请你重写的参考骨架。按给出的文件安装，原样编译、跑测，贴原始结果。遇到决定表未覆盖的情况就停止并报告输入、状态与缺口，不自行发明新行为。

## 可写文件

`prototype/Core/TouchTap.swift`、`tests/TouchTapTests.swift`、`tests/run-touch-tap-tests.sh`。测试支撑 `tests/support/WS2TestSupport.swift` 和共享 `prototype/Core/Contracts.swift` 由主模型只安装一次，执行本包时只读。

不修改App、构建脚本、签名、发布、权限、个人设置或其他包。若目标路径已有同名实现，先比较SHA256；仅当主模型确认它是第一轮骨架并批准替换后才覆盖。本包工具默认输出新暂存目录，不覆盖仓库。

## 前置与既有符号

规格来源：`docs/input-devices.md；docs/handoff/deepseek-input.md`。共享类型必须是本份contracts版本，不能另造Context/Token/RequestID。完整符号索引见 `../../contracts/existing-symbols.md`。

不调用既有App符号。本核只依赖Foundation、WS2契约和本文件值类型。对外副作用都是枚举，必须由后续App包调用既有接口；不要为了看到效果把Cocoa/CGEvent/AX带进本核。授权边界统一参照AuthorizationService.swift:28，纯核不直接调用它。

## 决定表

|情况|怎么做|为什么|
|---|---|---|
|输入单位未知|桥接器停止，不调用核|normalized不是毫米、原始ellipse不自动是平方毫米|
|触控板三/四指|组内所有指都ended且符合时长/位移才发一次tap|不能前三指先落就触发三指|
|新指晚于150ms|整组poison，等全空重新开始|不把连续加指当同时轻点|
|组结束超过250ms|拒绝|按住不是轻点|
|任何指位移≥1.5mm|拒绝|拖动不能误触|
|面积无效/≥140mm²/取消/重复ID|整组拒绝直至空帧|异常不会局部删一指后伪认三指|
|上帧活动指静默丢失|拒绝，不能假装已抬起|桥接丢帧不是用户tap|
|完整空帧|清组状态；未完成组只取消，不生成tap|重新建立边界|
|Magic Mouse两个活动触点|输出持续twoFingersDown；超过250ms仍可保持|两指弦键不是轻点|
|多于16指/倒序seq/时间回退|返回fault或cancel，不执行|防ABI错误扩大为行为|
|实时传帧|使用借用UnsafeBufferPointer入口，固定16槽；不保留指针|避免每帧大量分配；数组入口只为测试|

## 时钟、并发和回调归属

宿主串行驱动一个实例；Swift Sendable表示可以安全传值，不表示允许多个线程同时改同一实例。用同一WS2Clock，测试注入Instant。UI/HID/后端序号统一由宿主事件入口分配，来源原始seq不能直接跨源比较。先处理环境撤销，再丢旧代次；其余保持接收顺序。same instant允许多个不同seq。关闭/暂停不重置令牌编号源。

## 常量及出处

150ms、250ms、1.5mm来自规格；16槽、掌面积140mm²为本轮推荐探针起点。等于1.5mm/140mm²拒绝；150ms/250ms边界按源码包含。实际MT ABI和面积换算未验证，不能启用真机源。

下面列出实现中含数值或静态常量的原始行，防止实施时漏掉内联边界。数学0/1、数组索引、纳秒换算和格式位数是实现常量；只有上段明确写“规格”的才来自产品规格，其余产品/安全边界均属本轮推荐，待主模型冻结。不要把它们描述成真机测量。

```swift
// L8
let id: Int64
// L21
var id: Int64 = 0
// L24
var origin = WS2.Point(x: 0, y: 0)
// L26
static let maxContacts = 16
// L27
static let simultaneous: UInt64 = 150 * WS2.Duration.millisecond
// L28
static let maximumDuration: UInt64 = 250 * WS2.Duration.millisecond
// L29
static let maximumTravelMM = 1.5
// L31
static let palmAreaMM2 = 140.0
// L40
mutating func frame(_ contacts: [Contact], sequence: UInt64, at now: WS2.Instant) -> Output {
// L41
contacts.withUnsafeBufferPointer { frame($0, sequence: sequence, at: now) }
// L44
mutating func frame(_ contacts: UnsafeBufferPointer<Contact>, sequence: UInt64, at now: WS2.Instant) -> Output {
// L50
let wasIncomplete = slots.contains(where: { $0.active }) || poisoned
// L56
guard c.pointMM.isFinite, c.areaMM2.isFinite, c.areaMM2 > 0,
// L63
var active = 0
// L64
for c in contacts where c.phase != .ended { active += 1 }
// L66
return Output(tap: nil, twoFingersDown: !poisoned && active == 2, cancelled: poisoned, fault: nil)
// L71
if !contacts.contains(where: { $0.id == slot.id }) { poisoned = true; return bad(nil) }
// L75
if let existing = slots.firstIndex(where: { $0.used && $0.id == c.id }) {
// L79
guard c.phase == .began, let free = slots.firstIndex(where: { !$0.used }) else {
// L96
if slots.contains(where: { $0.active }) { return Output(tap: nil, twoFingersDown: false, cancelled: false, fault: nil) }
// L97
let count = slots.reduce(0) { $0 + ($1.used ? 1 : 0) }
// L98
let tap: Tap? = count == 3 ? .threeFingers : count == 4 ? .fourFingers : nil
```

## 文案、图标、动效

识别器无文案/图标/弹簧。动作成功由统一动作通道反馈；不能为每一帧触点弹通知。

数值取 `docs/design-system.md:332–347` 的令牌。UI示意映射只约束后续App，纯核不得为这些项额外引入动画对象。所有原始状态/动作字符串另见 `COPY.md`；动态private值不能写日志。

## 验收

在交付包根：
```sh
bash packages/I1d/tests/run-touch-tap-tests.sh
```
安装到仓库后，从仓库根：
```sh
bash tests/run-touch-tap-tests.sh
```
退出码必须0，stdout包含 `PASS I1d:`、`0 failures`，不出现 `FAIL ` 或编译error。精确用例/断言数量及完整输出见本包`VALIDATION.txt`；不要把这份历史输出贴成你的Mac实测。

本机再执行 `cd prototype && bash ./build.sh --check`，退出0并包含“==> 编译验证通过”。方法和禁止事项见BuildBaseline；Linux通过不能证明AppKit、硬件、身份、网络和能耗通过。脚本不靠SwiftPM拉依赖，不联网。

## 测试输入与结果

见 `TEST-CASES.md`。每一行对应测试代码的同名CASE，并提供原文件行范围。测试有明确输入值、状态和效果断言；不是只检查有没有字符串或文件。

## 不要做

不调用MultitouchSupport、不照搬未经核对的MTTouch C struct、不按dlsym存在就宣称接口可用、不靠首三指计数触发。

不删断言、不降Swift语言版本、不加try?吞掉编译/测试失败、不用mock结果冒充硬件支持。不得签名、安装运行App、改hooks或提交仓库；这些由主模型按授权处理。
