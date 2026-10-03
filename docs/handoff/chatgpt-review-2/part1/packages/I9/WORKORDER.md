# I9：四向焦点导航

本份是完整纯逻辑实现与可运行测试，不是请你重写的参考骨架。按给出的文件安装，原样编译、跑测，贴原始结果。遇到决定表未覆盖的情况就停止并报告输入、状态与缺口，不自行发明新行为。

## 可写文件

`prototype/Core/FocusNavigator.swift`、`tests/FocusNavigatorTests.swift`、`tests/run-focus-navigator-tests.sh`。测试支撑 `tests/support/WS2TestSupport.swift` 和共享 `prototype/Core/Contracts.swift` 由主模型只安装一次，执行本包时只读。

不修改App、构建脚本、签名、发布、权限、个人设置或其他包。若目标路径已有同名实现，先比较SHA256；仅当主模型确认它是第一轮骨架并批准替换后才覆盖。本包工具默认输出新暂存目录，不覆盖仓库。

## 前置与既有符号

规格来源：`docs/input-devices.md；docs/handoff/deepseek-input.md`。共享类型必须是本份contracts版本，不能另造Context/Token/RequestID。完整符号索引见 `../../contracts/existing-symbols.md`。

不调用既有App符号。本核只依赖Foundation、WS2契约和本文件值类型。对外副作用都是枚举，必须由后续App包调用既有接口；不要为了看到效果把Cocoa/CGEvent/AX带进本核。授权边界统一参照AuthorizationService.swift:28，纯核不直接调用它。

## 决定表

|情况|怎么做|为什么|
|---|---|---|
|输入矩形|屏幕点、y向下；宽高>0、坐标和边界有限|与触点y向上不同，适配器必须明确换算|
|只选候选|本显示器、visible、enabled且中心在方向半平面|不跳到隐藏或别屏|
|无有效当前焦点|按y、x、稳定ID找第一个|不依赖数组/字典顺序|
|同组有方向候选|先同组，再跨组|维持组导航|
|重新进组|该方向仍有效的组记忆格优先|保留用户上次位置而不跳到身后|
|几何比较|组/记忆优先后，垂直于方向的投影重叠长度从大到小，再欧氏距离、横向差、ID|真正比较重叠量，不只分有/无|
|边缘无候选|保持原焦点，默认不绕回|不意外飞到另一端|
|空数组|none，交给调用者清焦点|没有可点目标|
|ID重复/非法矩形/超过512项|invalidInput，不挑第一项凑结果|上游布局错误要暴露|
|元素消失|清不再有效的组记忆；不保留窗口标题作ID|不定位已关闭的目标|

## 时钟、并发和回调归属

宿主串行驱动一个实例；Swift Sendable表示可以安全传值，不表示允许多个线程同时改同一实例。用同一WS2Clock，测试注入Instant。UI/HID/后端序号统一由宿主事件入口分配，来源原始seq不能直接跨源比较。先处理环境撤销，再丢旧代次；其余保持接收顺序。same instant允许多个不同seq。关闭/暂停不重置令牌编号源。

## 常量及出处

512项上限为本轮推荐；排序是确定词典序，无魔法加权系数。可选边缘绕回未在本版实现；施工模型不得自行加。ID用不透明稳定标识，不能用标题。

下面列出实现中含数值或静态常量的原始行，防止实施时漏掉内联边界。数学0/1、数组索引、纳秒换算和格式位数是实现常量；只有上段明确写“规格”的才来自产品规格，其余产品/安全边界均属本轮推荐，待主模型冻结。不要把它们描述成真机测量。

```swift
// L9
var valid: Bool { [x,y,width,height,x+width,y+height].allSatisfy(\.isFinite) && width > 0 && height > 0 }
// L10
var cx: Double { x + width / 2 }; var cy: Double { y + height / 2 }
// L18
static let maximumItems = 512
// L21
guard items.count <= Self.maximumItems, items.allSatisfy({ !$0.id.isEmpty && !$0.group.isEmpty && $0.rect.valid }),
// L23
let eligible = items.filter { $0.visible && $0.enabled && $0.display == display }
// L24
remembered = remembered.filter { pair in eligible.contains { $0.group == pair.key && $0.id == pair.value } }
// L26
guard let currentID, let origin = eligible.first(where: { $0.id == currentID }) else {
// L28
if $0.rect.y != $1.rect.y { return $0.rect.y < $1.rect.y }
// L29
if $0.rect.x != $1.rect.x { return $0.rect.x < $1.rect.x }
// L30
return $0.id < $1.id
// L31
}[0]
// L45
case .right: forward = dx; cross = abs(dy); overlap = max(0, min(item.rect.y + item.rect.height, origin.rect.y + origin.rect.height) - max(item.rect.y, origin.rect.y))
// L46
case .left: forward = -dx; cross = abs(dy); overlap = max(0, min(item.rect.y + item.rect.height, origin.rect.y + origin.rect.height) - max(item.rect.y, origin.rect.y))
// L47
case .down: forward = dy; cross = abs(dx); overlap = max(0, min(item.rect.x + item.rect.width, origin.rect.x + origin.rect.width) - max(item.rect.x, origin.rect.x))
// L48
case .up: forward = -dy; cross = abs(dx); overlap = max(0, min(item.rect.x + item.rect.width, origin.rect.x + origin.rect.width) - max(item.rect.x, origin.rect.x))
// L50
guard forward > 0, forward.isFinite, cross.isFinite else { return nil }
// L56
if $0.sameGroup != $1.sameGroup { return $0.sameGroup }
// L57
if $0.remembered != $1.remembered { return $0.remembered }
// L58
if $0.overlap != $1.overlap { return $0.overlap > $1.overlap }
// L59
if $0.distance != $1.distance { return $0.distance < $1.distance }
// L60
if $0.crossDistance != $1.crossDistance { return $0.crossDistance < $1.crossDistance }
// L61
return $0.item.id < $1.item.id
```

## 文案、图标、动效

无新文案/图标。既有焦点环由App用calm更新，减少动态用reduced；导航算法不等待动画完成。

数值取 `docs/design-system.md:332–347` 的令牌。UI示意映射只约束后续App，纯核不得为这些项额外引入动画对象。所有原始状态/动作字符串另见 `COPY.md`；动态private值不能写日志。

## 验收

在交付包根：
```sh
bash packages/I9/tests/run-focus-navigator-tests.sh
```
安装到仓库后，从仓库根：
```sh
bash tests/run-focus-navigator-tests.sh
```
退出码必须0，stdout包含 `PASS I9:`、`0 failures`，不出现 `FAIL ` 或编译error。精确用例/断言数量及完整输出见本包`VALIDATION.txt`；不要把这份历史输出贴成你的Mac实测。

本机再执行 `cd prototype && bash ./build.sh --check`，退出0并包含“==> 编译验证通过”。方法和禁止事项见BuildBaseline；Linux通过不能证明AppKit、硬件、身份、网络和能耗通过。脚本不靠SwiftPM拉依赖，不联网。

## 测试输入与结果

见 `TEST-CASES.md`。每一行对应测试代码的同名CASE，并提供原文件行范围。测试有明确输入值、状态和效果断言；不是只检查有没有字符串或文件。

## 不要做

不读AX、不合成键盘，不修改Launchpad当前布局，不把跨屏导航默认为允许，不把阴影/动画边界当实际可点矩形。

不删断言、不降Swift语言版本、不加try?吞掉编译/测试失败、不用mock结果冒充硬件支持。不得签名、安装运行App、改hooks或提交仓库；这些由主模型按授权处理。
