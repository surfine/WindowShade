# I1e：遥控器按钮生命周期

本份是完整纯逻辑实现与可运行测试，不是请你重写的参考骨架。按给出的文件安装，原样编译、跑测，贴原始结果。遇到决定表未覆盖的情况就停止并报告输入、状态与缺口，不自行发明新行为。

## 可写文件

`prototype/Core/SiriRemoteButtons.swift`、`tests/SiriRemoteButtonsTests.swift`、`tests/run-siri-remote-buttons-tests.sh`。测试支撑 `tests/support/WS2TestSupport.swift` 和共享 `prototype/Core/Contracts.swift` 由主模型只安装一次，执行本包时只读。

不修改App、构建脚本、签名、发布、权限、个人设置或其他包。若目标路径已有同名实现，先比较SHA256；仅当主模型确认它是第一轮骨架并批准替换后才覆盖。本包工具默认输出新暂存目录，不覆盖仓库。

## 前置与既有符号

规格来源：`docs/input-devices.md；docs/handoff/deepseek-input.md`。共享类型必须是本份contracts版本，不能另造Context/Token/RequestID。完整符号索引见 `../../contracts/existing-symbols.md`。

不调用既有App符号。本核只依赖Foundation、WS2契约和本文件值类型。对外副作用都是枚举，必须由后续App包调用既有接口；不要为了看到效果把Cocoa/CGEvent/AX带进本核。授权边界统一参照AuthorizationService.swift:28，纯核不直接调用它。

## 决定表

|情况|怎么做|为什么|
|---|---|---|
|已知HID usage的非零值|down一次，新pressID；自动重复报告不再down|避免重复动作|
|已知usage归零|同按压up一次；没有down的孤立up忽略|禁止凭空点击|
|达到500ms/1000ms|各发一次长按阈值，顺序half→one；up仍带原pressID|路由器可消费尾部|
|在1秒整点抬起|先补到点threshold，再up|长按和抬手同刻不会变成短按|
|tick|只推进仍按住键的未发阈值；没有阈值就nextWake=nil|不常驻轮询|
|disconnect/disable/lock|cancelAll发cancel，不补up；清held|旧按键不能穿越连接|
|未知usage/power|忽略；当前12项表没有真实power就不编造|HID映射须来自实测或规格|
|序号耗尽/时间倒流|报告generation/time错误并停止新按压|不能回绕成旧pressID|

## 时钟、并发和回调归属

宿主串行驱动一个实例；Swift Sendable表示可以安全传值，不表示允许多个线程同时改同一实例。用同一WS2Clock，测试注入Instant。UI/HID/后端序号统一由宿主事件入口分配，来源原始seq不能直接跨源比较。先处理环境撤销，再丢旧代次；其余保持接收顺序。same instant允许多个不同seq。关闭/暂停不重置令牌编号源。

## 常量及出处

500ms/1000ms来自遥控长按规格；12项usage表原文见源码常量附录。pressID UInt64不回绕。C/42...45四方向、C/80中心、1/86返回、C/60TV、C/CD播放、C/E2静音、C/E9/EA音量、C/04侧键；属于来源规格，I5a仍要验证真实设备。

下面列出实现中含数值或静态常量的原始行，防止实施时漏掉内联边界。数学0/1、数组索引、纳秒换算和格式位数是实现常量；只有上段明确写“规格”的才来自产品规格，其余产品/安全边界均属本轮推荐，待主模型冻结。不要把它们描述成真机测量。

```swift
// L6
let id: UInt64
// L12
private var nextID: UInt64 = 0
// L14
static let half: UInt64 = 500 * WS2.Duration.millisecond
// L15
static let one: UInt64 = WS2.Duration.second
// L17
static func button(page: UInt32, usage: UInt32) -> WS2.Button? {
// L19
case (0x0c, 0x42): return .up
// L20
case (0x0c, 0x43): return .down
// L21
case (0x0c, 0x44): return .left
// L22
case (0x0c, 0x45): return .right
// L23
case (0x0c, 0x80): return .select
// L24
case (0x01, 0x86): return .back
// L25
case (0x0c, 0x60): return .tv
// L26
case (0x0c, 0xcd): return .playPause
// L27
case (0x0c, 0xe2): return .mute
// L28
case (0x0c, 0xe9): return .volumeUp
// L29
case (0x0c, 0xea): return .volumeDown
// L30
case (0x0c, 0x04): return .side
// L38
mutating func report(page: UInt32, usage: UInt32, value: Int, at now: WS2.Instant) -> [WS2.ButtonEvent] {
// L39
guard value == 0 || value == 1, let button = Self.button(page: page, usage: usage), time.accept(now) else { return [] }
// L41
if value == 1 {
// L42
guard held[button] == nil, nextID < UInt64.max else { return out }
// L43
nextID += 1
// L58
let out = WS2.Button.allCases.compactMap { b in held[b].map { event(b, .cancel, $0, now) } }
```

## 文案、图标、动效

此层没有文字、SF Symbol或动画。I1f/D1负责动作和展示。不能在这里调用系统媒体控制。

数值取 `docs/design-system.md:332–347` 的令牌。UI示意映射只约束后续App，纯核不得为这些项额外引入动画对象。所有原始状态/动作字符串另见 `COPY.md`；动态private值不能写日志。

## 验收

在交付包根：
```sh
bash packages/I1e/tests/run-siri-remote-buttons-tests.sh
```
安装到仓库后，从仓库根：
```sh
bash tests/run-siri-remote-buttons-tests.sh
```
退出码必须0，stdout包含 `PASS I1e:`、`0 failures`，不出现 `FAIL ` 或编译error。精确用例/断言数量及完整输出见本包`VALIDATION.txt`；不要把这份历史输出贴成你的Mac实测。

本机再执行 `cd prototype && bash ./build.sh --check`，退出0并包含“==> 编译验证通过”。方法和禁止事项见BuildBaseline；Linux通过不能证明AppKit、硬件、身份、网络和能耗通过。脚本不靠SwiftPM拉依赖，不联网。

## 测试输入与结果

见 `TEST-CASES.md`。每一行对应测试代码的同名CASE，并提供原文件行范围。测试有明确输入值、状态和效果断言；不是只检查有没有字符串或文件。

## 不要做

不读IOHID设备、不改hidutil、不伪造power、不用固定重复timer重复发送held事件。

不删断言、不降Swift语言版本、不加try?吞掉编译/测试失败、不用mock结果冒充硬件支持。不得签名、安装运行App、改hooks或提交仓库；这些由主模型按授权处理。
