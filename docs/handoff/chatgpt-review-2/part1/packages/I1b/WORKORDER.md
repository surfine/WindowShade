# I1b：每事件设备分类

本份是完整纯逻辑实现与可运行测试，不是请你重写的参考骨架。按给出的文件安装，原样编译、跑测，贴原始结果。遇到决定表未覆盖的情况就停止并报告输入、状态与缺口，不自行发明新行为。

## 可写文件

`prototype/Core/InputDeviceKind.swift`、`tests/InputDeviceKindTests.swift`、`tests/run-input-device-kind-tests.sh`。测试支撑 `tests/support/WS2TestSupport.swift` 和共享 `prototype/Core/Contracts.swift` 由主模型只安装一次，执行本包时只读。

不修改App、构建脚本、签名、发布、权限、个人设置或其他包。若目标路径已有同名实现，先比较SHA256；仅当主模型确认它是第一轮骨架并批准替换后才覆盖。本包工具默认输出新暂存目录，不覆盖仓库。

## 前置与既有符号

规格来源：`docs/input-devices.md；docs/handoff/deepseek-input.md`。共享类型必须是本份contracts版本，不能另造Context/Token/RequestID。完整符号索引见 `../../contracts/existing-symbols.md`。

不调用既有App符号。本核只依赖Foundation、WS2契约和本文件值类型。对外副作用都是枚举，必须由后续App包调用既有接口；不要为了看到效果把Cocoa/CGEvent/AX带进本核。授权边界统一参照AuthorizationService.swift:28，纯核不直接调用它。

## 决定表

|情况|怎么做|为什么|
|---|---|---|
|每事件有已验证关联|按vendor/product/HID class与事件连续性分类|枚举列表不证明这一条事件来源|
|仅枚举/最近连接/没有来源|unknown，保持原事件|禁止猜最近动过哪个设备|
|已验证Apple0323|magicMouse，不走滚轮平滑|保留系统连续滚动|
|已验证Apple0315|siriRemote，不当鼠标|按钮与触控另走I5|
|HID类明确trackpad|trackpad，保留原事件|避免Apple未知product误当滚轮|
|第三方普通鼠标且非连续非momentum|wheelMouse，可由I3使用平滑核|需要每事件证据加类别|
|未知Apple product即使mouse类|unknown，不降成wheelMouse|公开PID有限，不能编全产品表|
|permission丢失/设备解绑|分类unknown，正在平滑的对应流取消|错误来源不能延续增强|
|magicMouse方向修正|mayRewrite只表示可改方向，I3仍按kind区分；不代表可平滑|布尔值不是一切增强的通行证|

## 时钟、并发和回调归属

宿主串行驱动一个实例；Swift Sendable表示可以安全传值，不表示允许多个线程同时改同一实例。用同一WS2Clock，测试注入Instant。UI/HID/后端序号统一由宿主事件入口分配，来源原始seq不能直接跨源比较。先处理环境撤销，再丢旧代次；其余保持接收顺序。same instant允许多个不同seq。关闭/暂停不重置令牌编号源。

## 常量及出处

0x05ac供应商、0x0323鼠标、0x0315遥控器来自上传input规格，尚不等于本机实物探针已通过。没有扩大PID清单。非连续/非momentum为枚举条件，不是时间阈值。

下面列出实现中含数值或静态常量的原始行，防止实施时漏掉内联边界。数学0/1、数组索引、纳秒换算和格式位数是实现常量；只有上段明确写“规格”的才来自产品规格，其余产品/安全边界均属本轮推荐，待主模型冻结。不要把它们描述成真机测量。

```swift
// L12
let vendorID: UInt32
// L13
let productID: UInt32
// L32
if device.vendorID == 0x05ac && device.productID == 0x0315 {
// L35
if device.vendorID == 0x05ac && device.productID == 0x0323 {
// L41
if device.vendorID != 0x05ac && device.hidClass == .mouse && !value.continuous && !value.hasMomentum {
```

## 文案、图标、动效

纯分类不显示设备品牌推断；unknown显示层固定“未识别的输入设备”，符号questionmark.circle；无动画。不得用“妙控鼠标”掩盖unknown。

数值取 `docs/design-system.md:332–347` 的令牌。UI示意映射只约束后续App，纯核不得为这些项额外引入动画对象。所有原始状态/动作字符串另见 `COPY.md`；动态private值不能写日志。

## 验收

在交付包根：
```sh
bash packages/I1b/tests/run-input-device-kind-tests.sh
```
安装到仓库后，从仓库根：
```sh
bash tests/run-input-device-kind-tests.sh
```
退出码必须0，stdout包含 `PASS I1b:`、`0 failures`，不出现 `FAIL ` 或编译error。精确用例/断言数量及完整输出见本包`VALIDATION.txt`；不要把这份历史输出贴成你的Mac实测。

本机再执行 `cd prototype && bash ./build.sh --check`，退出0并包含“==> 编译验证通过”。方法和禁止事项见BuildBaseline；Linux通过不能证明AppKit、硬件、身份、网络和能耗通过。脚本不靠SwiftPM拉依赖，不联网。

## 测试输入与结果

见 `TEST-CASES.md`。每一行对应测试代码的同名CASE，并提供原文件行范围。测试有明确输入值、状态和效果断言；不是只检查有没有字符串或文件。

## 不要做

不读IOKit，不从CGEventSourcePID推出物理设备，不缓存“最近设备”作为证明，不给未知Apple产品塞默认轮鼠类型。

不删断言、不降Swift语言版本、不加try?吞掉编译/测试失败、不用mock结果冒充硬件支持。不得签名、安装运行App、改hooks或提交仓库；这些由主模型按授权处理。
