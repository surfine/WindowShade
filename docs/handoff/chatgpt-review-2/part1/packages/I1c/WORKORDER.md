# I1c：中键拖动判定

本份是完整纯逻辑实现与可运行测试，不是请你重写的参考骨架。按给出的文件安装，原样编译、跑测，贴原始结果。遇到决定表未覆盖的情况就停止并报告输入、状态与缺口，不自行发明新行为。

## 可写文件

`prototype/Core/MiddleDrag.swift`、`tests/MiddleDragTests.swift`、`tests/run-middle-drag-tests.sh`。测试支撑 `tests/support/WS2TestSupport.swift` 和共享 `prototype/Core/Contracts.swift` 由主模型只安装一次，执行本包时只读。

不修改App、构建脚本、签名、发布、权限、个人设置或其他包。若目标路径已有同名实现，先比较SHA256；仅当主模型确认它是第一轮骨架并批准替换后才覆盖。本包工具默认输出新暂存目录，不覆盖仓库。

## 前置与既有符号

规格来源：`docs/input-devices.md；docs/handoff/deepseek-input.md`。共享类型必须是本份contracts版本，不能另造Context/Token/RequestID。完整符号索引见 `../../contracts/existing-symbols.md`。

不调用既有App符号。本核只依赖Foundation、WS2契约和本文件值类型。对外副作用都是枚举，必须由后续App包调用既有接口；不要为了看到效果把Cocoa/CGEvent/AX带进本核。授权边界统一参照AuthorizationService.swift:28，纯核不直接调用它。

## 决定表

|情况|怎么做|为什么|
|---|---|---|
|down位置region不明确|passOriginal，不截获|无法证明标题栏就不赌|
|位移未超过10pt|继续跟踪；up原样点击|抖动不等于拖动|
|超过10pt但xy接近|继续等待主轴；最后仍不明确则cancel，不补点击|拖过阈值不能误变点击|
|主轴占优1.25倍|固定该轴；同轴反向可变符号|避免拖动中不断横竖跳|
|进度|(绝对主轴位移-10)/(180-10)，夹0...1|阈值之后才开始反馈|
|抬手进度≥0.6|commit对应action；否则cancel|提交阈值明确可测|
|曾越阈值后回原点|cancel，不发中键单击|消除拖完打开链接|
|标题栏四方向|四个titlebar意图，App调用既有动作|不在此核重新实现窗口控制|
|普通区域|上Mission Control，下应用窗口，左右空间切换|与输入规格一致|
|取消/锁屏/断线|结束当前跟踪，不造up/click|动作由租约拥有者决定|

## 时钟、并发和回调归属

宿主串行驱动一个实例；Swift Sendable表示可以安全传值，不表示允许多个线程同时改同一实例。用同一WS2Clock，测试注入Instant。UI/HID/后端序号统一由宿主事件入口分配，来源原始seq不能直接跨源比较。先处理环境撤销，再丢旧代次；其余保持接收顺序。same instant允许多个不同seq。关闭/暂停不重置令牌编号源。

## 常量及出处

10pt、180pt来自规格边界；主轴1.25倍和commit0.6是本轮推荐冻结。Cocoa屏幕点x右y上，不是触点毫米。

下面列出实现中含数值或静态常量的原始行，防止实施时漏掉内联边界。数学0/1、数组索引、纳秒换算和格式位数是实现常量；只有上段明确写“规格”的才来自产品规格，其余产品/安全边界均属本轮推荐，待主模型冻结。不要把它们描述成真机测量。

```swift
// L21
var progress = 0.0
// L26
static let threshold = 10.0
// L27
static let dominance = 1.25
// L28
static let fullTravel = 180.0
// L29
static let commitProgress = 0.6
// L68
c.progress = min(1, max(0, (abs(signed) - Self.threshold) / (Self.fullTravel - Self.threshold)))
// L71
action = axis == .horizontal ? (signed >= 0 ? .titlebarRight : .titlebarLeft)
// L72
: (signed >= 0 ? .titlebarUp : .titlebarDown)
// L74
action = axis == .horizontal ? (signed >= 0 ? .spaceRight : .spaceLeft)
// L75
: (signed >= 0 ? .missionControl : .appWindows)
```

## 文案、图标、动效

纯核只输出进度与方向。I4使用同一目标预览，反馈跟手；松手回位calm，有动量的既有动作沿用其自身glide。SF Symbol取既有窗口动作，不新画手势广告。

数值取 `docs/design-system.md:332–347` 的令牌。UI示意映射只约束后续App，纯核不得为这些项额外引入动画对象。所有原始状态/动作字符串另见 `COPY.md`；动态private值不能写日志。

## 验收

在交付包根：
```sh
bash packages/I1c/tests/run-middle-drag-tests.sh
```
安装到仓库后，从仓库根：
```sh
bash tests/run-middle-drag-tests.sh
```
退出码必须0，stdout包含 `PASS I1c:`、`0 failures`，不出现 `FAIL ` 或编译error。精确用例/断言数量及完整输出见本包`VALIDATION.txt`；不要把这份历史输出贴成你的Mac实测。

本机再执行 `cd prototype && bash ./build.sh --check`，退出0并包含“==> 编译验证通过”。方法和禁止事项见BuildBaseline；Linux通过不能证明AppKit、硬件、身份、网络和能耗通过。脚本不靠SwiftPM拉依赖，不联网。

## 测试输入与结果

见 `TEST-CASES.md`。每一行对应测试代码的同名CASE，并提供原文件行范围。测试有明确输入值、状态和效果断言；不是只检查有没有字符串或文件。

## 不要做

不全局吞中键，不合成补发down/up，不访问AX，不把未知region当普通区域成功。

不删断言、不降Swift语言版本、不加try?吞掉编译/测试失败、不用mock结果冒充硬件支持。不得签名、安装运行App、改hooks或提交仓库；这些由主模型按授权处理。
