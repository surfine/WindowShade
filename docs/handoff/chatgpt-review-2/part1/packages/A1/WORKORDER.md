# A1：助手会话与审批聚合

本份是完整纯逻辑实现与可运行测试，不是请你重写的参考骨架。按给出的文件安装，原样编译、跑测，贴原始结果。遇到决定表未覆盖的情况就停止并报告输入、状态与缺口，不自行发明新行为。

## 可写文件

`prototype/Core/AgentSessions.swift`、`tests/AgentSessionsTests.swift`、`tests/run-agent-sessions-tests.sh`。测试支撑 `tests/support/WS2TestSupport.swift` 和共享 `prototype/Core/Contracts.swift` 由主模型只安装一次，执行本包时只读。

不修改App、构建脚本、签名、发布、权限、个人设置或其他包。若目标路径已有同名实现，先比较SHA256；仅当主模型确认它是第一轮骨架并批准替换后才覆盖。本包工具默认输出新暂存目录，不覆盖仓库。

## 前置与既有符号

规格来源：`docs/agents-in-notch.md；docs/handoff/deepseek-menu-agents.md`。共享类型必须是本份contracts版本，不能另造Context/Token/RequestID。完整符号索引见 `../../contracts/existing-symbols.md`。

不调用既有App符号。本核只依赖Foundation、WS2契约和本文件值类型。对外副作用都是枚举，必须由后续App包调用既有接口；不要为了看到效果把Cocoa/CGEvent/AX带进本核。授权边界统一参照AuthorizationService.swift:28，纯核不直接调用它。

## 决定表

|情况|怎么做|为什么|
|---|---|---|
|会话键|provider+sessionID；上下文另含可信peer、project和epoch|同目录可以有多个会话|
|新会话/新epoch|显式opened才建立；高epoch替换前清旧pending|迟到事件不隐式新建|
|进程已退出后同epoch事件|拒绝，需更高epoch明确opened|防失联状态复活|
|重复/倒序/倒流|EventGate/TimeGate拒绝|总线严格单调|
|observed和owned|观察能展示；owned才允许控制回执改变运行轮次|看到终端不代表接管它|
|tool重复开始|按ID集合幂等；end只删该工具|重复事件不虚增并发|
|600秒没消息|stale，不声称disconnected|沉默不证明进程死了|
|普通/高/未知风险|typed只读/编辑/明确测试为normal；网络/删除/越界/安全变更high；shell与未知unknown|不靠字符串猜“安全命令”|
|同审批键同摘要重复|不延长期限、不重复排队|重试不等于新请求|
|同键不同摘要|撤原请求并deferToHost+fault，不覆盖内容|目标不能在批准前偷换|
|确认|校验新按压和期限，标authorizing，发AuthorizationIntent|没有allow捷径|
|服务dispatched|必须匹配已authorizing的键和摘要，只清状态|服务已答过，不二次回复|
|拒绝/返回宿主/超时|只发deny或deferToHost；后端协议怎么终结由A2/D6负责|无决定不能默认为允许|
|上限到达|拒绝新项并报告，不挤掉待答审批|避免漏审批换成默认放行|
|锁屏/隐藏|suspend清私密摘要与pending，显示列表空；resume只查询owned新快照|恢复不重放旧输入|

## 时钟、并发和回调归属

宿主串行驱动一个实例；Swift Sendable表示可以安全传值，不表示允许多个线程同时改同一实例。用同一WS2Clock，测试注入Instant。UI/HID/后端序号统一由宿主事件入口分配，来源原始seq不能直接跨源比较。先处理环境撤销，再丢旧代次；其余保持接收顺序。same instant允许多个不同seq。关闭/暂停不重置令牌编号源。

## 常量及出处

所有容量与超时是本轮推荐冻结：64会话、128待答全局、每会话8待答、64工具、120秒审批最长展示期限、600秒静默标陈旧。摘要16KiB与ID界限取共享合同防错上限，不是协议服务端限制。

下面列出实现中含数值或静态常量的原始行，防止实施时漏掉内联边界。数学0/1、数组索引、纳秒换算和格式位数是实现常量；只有上段明确写“规格”的才来自产品规格，其余产品/安全边界均属本轮推荐，待主模型冻结。不要把它们描述成真机测量。

```swift
// L44
static let maximumSessions = 64
// L45
static let maximumApprovals = 128
// L46
static let maximumApprovalsPerSession = 8
// L47
static let maximumToolsPerSession = 64
// L48
static let inactivity: UInt64 = 600 * WS2.Duration.second
// L49
static let maximumApprovalLifetime: UInt64 = 120 * WS2.Duration.second
// L58
if $0.context.session.provider.rawValue != $1.context.session.provider.rawValue {
// L59
return $0.context.session.provider.rawValue < $1.context.session.provider.rawValue
// L61
return $0.context.session.id < $1.context.session.id
// L136
pending.keys.filter({ $0.session == key }).count < Self.maximumApprovalsPerSession else {
// L145
if pending.keys.contains(where: { $0.session == key }) { session.status = .waiting }
// L152
beganAt: WS2.Instant, sequence: UInt64, voicePassed: Bool = false,
// L220
let stale = sessions.values.filter { [.idle, .running].contains($0.status) }.map { $0.lastUpdate.adding(Self.inactivity) }
// L234
let keys = pending.keys.filter { $0.session == session }.sorted(by: approvalOrder)
// L238
return keys.map { .finishApproval($0, .deferToHost) }
// L242
sessions[key]?.status = pending.keys.contains(where: { $0.session == key }) ? .waiting : fallback
// L245
sessions.keys.sorted { $0.provider.rawValue == $1.provider.rawValue ? $0.id < $1.id : $0.provider.rawValue < $1.provider.rawValue }
// L258
private func valid(_ summary: String) -> Bool { !summary.isEmpty && summary.utf8.count <= 16_384 }
// L259
private func validID(_ id: String) -> Bool { !id.isEmpty && id.utf8.count <= 512 }
```

## 文案、图标、动效

状态文字“运行中”“等待确认”“已完成”“出错了”“状态还没更新”“已断开”，只在真实对应状态显示。图标terminal/clock/checkmark/xmark.circle/questionmark/wifi.slash；审批lock.fill。持续状态calm，用户展开expand，reduced替代。普通活动不展示假的百分比。

数值取 `docs/design-system.md:332–347` 的令牌。UI示意映射只约束后续App，纯核不得为这些项额外引入动画对象。所有原始状态/动作字符串另见 `COPY.md`；动态private值不能写日志。

## 验收

在交付包根：
```sh
bash packages/A1/tests/run-agent-sessions-tests.sh
```
安装到仓库后，从仓库根：
```sh
bash tests/run-agent-sessions-tests.sh
```
退出码必须0，stdout包含 `PASS A1:`、`0 failures`，不出现 `FAIL ` 或编译error。精确用例/断言数量及完整输出见本包`VALIDATION.txt`；不要把这份历史输出贴成你的Mac实测。

本机再执行 `cd prototype && bash ./build.sh --check`，退出0并包含“==> 编译验证通过”。方法和禁止事项见BuildBaseline；Linux通过不能证明AppKit、硬件、身份、网络和能耗通过。脚本不靠SwiftPM拉依赖，不联网。

## 测试输入与结果

见 `TEST-CASES.md`。每一行对应测试代码的同名CASE，并提供原文件行范围。测试有明确输入值、状态和效果断言；不是只检查有没有字符串或文件。

## 不要做

不启动CLI、不读取完整会话历史、不改hooks、不按窗口标题识别进程、不把请求塞进NotchActivityStore的3条可见活动，不签grant。

不删断言、不降Swift语言版本、不加try?吞掉编译/测试失败、不用mock结果冒充硬件支持。不得签名、安装运行App、改hooks或提交仓库；这些由主模型按授权处理。
