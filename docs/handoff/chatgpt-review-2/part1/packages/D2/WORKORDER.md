# D2：能力、槽位和开销票据

本份是完整纯逻辑实现与可运行测试，不是请你重写的参考骨架。按给出的文件安装，原样编译、跑测，贴原始结果。遇到决定表未覆盖的情况就停止并报告输入、状态与缺口，不自行发明新行为。

## 可写文件

`prototype/Core/ConductorCapabilities.swift`、`tests/ConductorCapabilitiesTests.swift`、`tests/run-conductor-capabilities-tests.sh`。测试支撑 `tests/support/WS2TestSupport.swift` 和共享 `prototype/Core/Contracts.swift` 由主模型只安装一次，执行本包时只读。

不修改App、构建脚本、签名、发布、权限、个人设置或其他包。若目标路径已有同名实现，先比较SHA256；仅当主模型确认它是第一轮骨架并批准替换后才覆盖。本包工具默认输出新暂存目录，不覆盖仓库。

## 前置与既有符号

规格来源：`docs/conductor-v2.md；固定Codex Schema；docs/handoff/reference/mac-facts-2026-10-03.md`。共享类型必须是本份contracts版本，不能另造Context/Token/RequestID。完整符号索引见 `../../contracts/existing-symbols.md`。

不调用既有App符号。本核只依赖Foundation、WS2契约和本文件值类型。对外副作用都是枚举，必须由后续App包调用既有接口；不要为了看到效果把Cocoa/CGEvent/AX带进本核。授权边界统一参照AuthorizationService.swift:28，纯核不直接调用它。

## 决定表

|情况|怎么做|为什么|
|---|---|---|
|有native档位|只有实际能力列表明确包含才解析成功|支持列表优先于猜测模型名字|
|无支持值|返回unavailable，不降低成high/xhigh|不得把菜单标签伪装成能力|
|Claude ultra|仅已注册具体workflow可把ultra映射xhigh+workflowID；无workflow就不可用|ultra不是自动存在的原生枚举|
|Codex ultra|只按自己的能力，不能借用Claude组合策略|提供商边界|
|四模型槽|恰好4个位置，存稳定ID；列表重排不换目标|避免按index选错模型|
|重复能力记录|同ID多条视为不确定，拒绝解析|不挑第一条掩盖冲突|
|高开销确认|候选30秒内、显示后新输入才签本地费用票；票也30秒|票只是费用确认，不是身份许可|
|草稿/模型/档位/workflow/能力版本/context/candidate改变|原票不匹配；尝试消费即作废|不可先试错再拿票执行别的目标|
|重复consume|第一次无论成功失败都销毁；后续拒绝|恰好一次|
|实际后端回执|accepts只验证证据值是否属于能力，不合成actual|请求和实际分离|

## 时钟、并发和回调归属

宿主串行驱动一个实例；Swift Sendable表示可以安全传值，不表示允许多个线程同时改同一实例。用同一WS2Clock，测试注入Instant。UI/HID/后端序号统一由宿主事件入口分配，来源原始seq不能直接跨源比较。先处理环境撤销，再丢旧代次；其余保持接收顺序。same instant允许多个不同seq。关闭/暂停不重置令牌编号源。

## 常量及出处

4模型槽来自规格；30秒候选/票有效期为本轮推荐。supportedEfforts、wire model ID来自实际model/list快照；不得把测试的虚构model-1发往服务端。capabilityRevision为宿主递增版本，不能重用旧版。

下面列出实现中含数值或静态常量的原始行，防止实施时漏掉内联边界。数学0/1、数组索引、纳秒换算和格式位数是实现常量；只有上段明确写“规格”的才来自产品规格，其余产品/安全边界均属本轮推荐，待主模型冻结。不要把它们描述成真机测量。

```swift
// L8
let revision: UInt64
// L12
!model.modelID.isEmpty && model.modelID.utf8.count <= 512 &&
// L13
!supportedEfforts.isEmpty && supportedEfforts.count <= 32 &&
// L14
supportedEfforts.allSatisfy { !$0.isEmpty && $0.utf8.count <= 64 } &&
// L15
(ultracodeWorkflowID.map { !$0.isEmpty && $0.utf8.count <= 512 } ?? true)
// L52
guard slots.count == 4, slots.compactMap({ $0 }).allSatisfy({ !$0.modelID.isEmpty }) else { return nil }
// L60
guard (1...4).contains(number) else { return .unavailable("模型只有四个位置") }
// L61
guard let model = slots[number - 1] else { return .unavailable("位置 \(number) 的模型不可用") }
// L62
let matches = completeSnapshot.filter { $0.model == model && $0.isValid }
// L63
guard matches.count == 1 else { return .unavailable("位置 \(number) 的模型不可用") }
// L64
return .available(matches[0])
// L72
let shownAfterSequence: UInt64
// L81
static let lifetime: UInt64 = 30 * WS2.Duration.second // 本轮推荐；真实费用尚未测量。
// L85
sequence: UInt64, now: WS2.Instant) -> Bool {
```

## 文案、图标、动效

严格文字“不支持这个档位”“位置 N 的模型不可用”“模型只有四个位置”；具体字符串以源码与COPY为准。纯核没有符号/弹簧；D3费用确认沿用checkmark与calm，不能显示假的费用金额。

数值取 `docs/design-system.md:332–347` 的令牌。UI示意映射只约束后续App，纯核不得为这些项额外引入动画对象。所有原始状态/动作字符串另见 `COPY.md`；动态private值不能写日志。

## 验收

在交付包根：
```sh
bash packages/D2/tests/run-conductor-capabilities-tests.sh
```
安装到仓库后，从仓库根：
```sh
bash tests/run-conductor-capabilities-tests.sh
```
退出码必须0，stdout包含 `PASS D2:`、`0 failures`，不出现 `FAIL ` 或编译error。精确用例/断言数量及完整输出见本包`VALIDATION.txt`；不要把这份历史输出贴成你的Mac实测。

本机再执行 `cd prototype && bash ./build.sh --check`，退出0并包含“==> 编译验证通过”。方法和禁止事项见BuildBaseline；Linux通过不能证明AppKit、硬件、身份、网络和能耗通过。脚本不靠SwiftPM拉依赖，不联网。

## 测试输入与结果

见 `TEST-CASES.md`。每一行对应测试代码的同名CASE，并提供原文件行范围。测试有明确输入值、状态和效果断言；不是只检查有没有字符串或文件。

## 不要做

不写提供商API、不改变安全/审批策略、不增加Rust依赖、不把max/ultra默认标支持、不把费用票当AuthGrant。

不删断言、不降Swift语言版本、不加try?吞掉编译/测试失败、不用mock结果冒充硬件支持。不得签名、安装运行App、改hooks或提交仓库；这些由主模型按授权处理。
