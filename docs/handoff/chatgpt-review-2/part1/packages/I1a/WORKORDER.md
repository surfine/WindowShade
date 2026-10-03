# I1a：滚轮平滑积分

本份是完整纯逻辑实现与可运行测试，不是请你重写的参考骨架。按给出的文件安装，原样编译、跑测，贴原始结果。遇到决定表未覆盖的情况就停止并报告输入、状态与缺口，不自行发明新行为。

## 可写文件

`prototype/Core/SmoothScroll.swift`、`tests/SmoothScrollTests.swift`、`tests/run-smooth-scroll-tests.sh`。测试支撑 `tests/support/WS2TestSupport.swift` 和共享 `prototype/Core/Contracts.swift` 由主模型只安装一次，执行本包时只读。

不修改App、构建脚本、签名、发布、权限、个人设置或其他包。若目标路径已有同名实现，先比较SHA256；仅当主模型确认它是第一轮骨架并批准替换后才覆盖。本包工具默认输出新暂存目录，不覆盖仓库。

## 前置与既有符号

规格来源：`docs/input-devices.md；docs/handoff/deepseek-input.md`。共享类型必须是本份contracts版本，不能另造Context/Token/RequestID。完整符号索引见 `../../contracts/existing-symbols.md`。

不调用既有App符号。本核只依赖Foundation、WS2契约和本文件值类型。对外副作用都是枚举，必须由后续App包调用既有接口；不要为了看到效果把Cocoa/CGEvent/AX带进本核。授权边界统一参照AuthorizationService.swift:28，纯核不直接调用它。

## 决定表

|情况|怎么做|为什么|
|---|---|---|
|离散滚轮输入|每轴单独核，按所选preset累加目标|不混合xy|
|同向追加|先推进旧解析解，再累计目标，保持速度|输入不能因帧率不同丢失|
|反向输入|先取消旧方向尚未发出的余量和速度，不补一小段旧方向|避免已经反向仍往旧方向走|
|帧率/长帧|使用临界阻尼解析解，无固定帧步长|60/120Hz等只影响采样不影响总目标|
|接近目标|最后一帧补足余量，速度清零，isFinished=true|停止阈值不丢积分|
|NaN/无穷/超大值/倒流|返回nil且不执行任何事件|异常源不能让主线程产生灾难位移|
|取消/设备失联|只记录cancelledResidual，不再发送残量|用户停止功能后不能继续滚|
|积分核算|totalInput = position + pending + cancelledResidual|反向取消是明确撤销量，不伪装成已发位移|
|触控板/Magic Mouse|只有I1b证明离散滚轮才进入本核；其他设备走原始路径|避免二次平滑|
|精细一格一行|留给I3保留原生line单位，不硬编码12pt等于一行|点数不是排版行高|

## 时钟、并发和回调归属

宿主串行驱动一个实例；Swift Sendable表示可以安全传值，不表示允许多个线程同时改同一实例。用同一WS2Clock，测试注入Instant。UI/HID/后端序号统一由宿主事件入口分配，来源原始seq不能直接跨源比较。先处理环境撤销，再丢旧代次；其余保持接收顺序。same instant允许多个不同seq。关闭/暂停不重置令牌编号源。

## 常量及出处

本轮推荐手感而非实测：light 24pt/notch、ω32；medium36、ω24；trackpadLike48、ω18。输入单次≤120notches，绝对目标≤1e12，收敛误差和速度均<1e-5才补尾。临界阻尼方程数学常数0/1不属于HIG弹簧令牌。

下面列出实现中含数值或静态常量的原始行，防止实施时漏掉内联边界。数学0/1、数组索引、纳秒换算和格式位数是实现常量；只有上段明确写“规格”的才来自产品规格，其余产品/安全边界均属本轮推荐，待主模型冻结。不要把它们描述成真机测量。

```swift
// L9
switch self { case .light: return 24; case .medium: return 36; case .trackpadLike: return 48 }
// L12
switch self { case .light: return 32; case .medium: return 24; case .trackpadLike: return 18 }
// L19
private(set) var position = 0.0
// L20
private(set) var target = 0.0
// L21
private(set) var velocity = 0.0
// L23
private(set) var cancelledResidual = 0.0
// L24
private(set) var totalInput = 0.0
// L28
var isFinished: Bool { position == target && velocity == 0 }
// L33
guard notches.isFinite, abs(notches) <= 120 else { return nil }
// L35
let reversing = delta != 0 && ((pending != 0 && pending.sign != delta.sign) ||
// L36
(velocity != 0 && velocity.sign != delta.sign))
// L38
guard (proposedBase + delta).isFinite, abs(proposedBase + delta) <= 1e12,
// L43
cancelledResidual += pending; target = position; velocity = 0
// L44
frame = Frame(delta: 0, finished: true)
// L56
guard let previous, !isFinished else { return Frame(delta: 0, finished: isFinished) }
// L58
guard dt > 0 else { return Frame(delta: 0, finished: isFinished) }
// L68
(abs(position - target) < 0.00001 && abs(velocity) < 0.00001) {
// L69
position = target; velocity = 0
// L76
target = position; velocity = 0
```

## 文案、图标、动效

没有文字、SF Symbol或UI弹簧。滚动传递函数不可替换成刘海calm/expand；不产生新的浮窗。

数值取 `docs/design-system.md:332–347` 的令牌。UI示意映射只约束后续App，纯核不得为这些项额外引入动画对象。所有原始状态/动作字符串另见 `COPY.md`；动态private值不能写日志。

## 验收

在交付包根：
```sh
bash packages/I1a/tests/run-smooth-scroll-tests.sh
```
安装到仓库后，从仓库根：
```sh
bash tests/run-smooth-scroll-tests.sh
```
退出码必须0，stdout包含 `PASS I1a:`、`0 failures`，不出现 `FAIL ` 或编译error。精确用例/断言数量及完整输出见本包`VALIDATION.txt`；不要把这份历史输出贴成你的Mac实测。

本机再执行 `cd prototype && bash ./build.sh --check`，退出0并包含“==> 编译验证通过”。方法和禁止事项见BuildBaseline；Linux通过不能证明AppKit、硬件、身份、网络和能耗通过。脚本不靠SwiftPM拉依赖，不联网。

## 测试输入与结果

见 `TEST-CASES.md`。每一行对应测试代码的同名CASE，并提供原文件行范围。测试有明确输入值、状态和效果断言；不是只检查有没有字符串或文件。

## 不要做

不创建CGEvent、不读取设备、不做NSEvent事件关联猜测、不加固定16ms Timer、不“按手感”改测试门槛。

不删断言、不降Swift语言版本、不加try?吞掉编译/测试失败、不用mock结果冒充硬件支持。不得签名、安装运行App、改hooks或提交仓库；这些由主模型按授权处理。
