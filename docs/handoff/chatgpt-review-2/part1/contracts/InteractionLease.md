# 全局交互租约与每屏显示合同 v1

**交主模型审定，尚未冻结，也未接入现有 App。** 本文件中的新协调器接口是施工合同，不冒充已有实现。可编译的数据类型在 `Contracts.swift`。现有 `NotchActivityStore` 只继续管普通实时活动；身份批准、输入接管不得借它的可见三条容量来排队。

## 1. 唯一所有权

同一时刻全应用只有一个能接收操作的租约。每个显示器仍有自己的布局快照和普通活动，其他屏幕不能偷偷拥有另一份按钮焦点。租约令牌绑定 ownerID、display、environmentEpoch；结构本身可构造，所以实际路由还要和协调器持有的当前对象逐字段匹配。令牌不等于身份授权。

ownerID 固定为 `authorization`、`conductor`、`notchShelf`、`launchpad`、`windowBrowser`、`pomodoro`；新增 owner 先改合同。owner 同名也不能复用上一轮 token。申请者不能自行决定更高层级：宿主用固定表校验。authorization 仅1层；conductor 正在输入是2层；普通展开视图是3层。没有输入的倒计时、音乐和任务状态是5层，不申请交互租约。

|层|触发与内容|全局输入|占用与离开|
|---|---|---|---|
|1 授权|已经过真实性校验、当前实际需要回答的审批；现有身份视图|有，最高|用户明确操作或请求截止；同层 FIFO，不抢正在确认的请求；锁屏撤销|
|2 正在交互|指挥轨迹、选档、录音、窗口手势|有|真实接触期间或有明确未结束的交互；结束释放；可被1抢占|
|3 用户主动展开|负一屏、启动台、窗口浏览、番茄钟详情|有|打开期间；可被1或2抢占；抢占后不自动弹回|
|4 提醒|后台状态的一次短提醒|无|最多4秒，连续更新合并窗口0.6秒；被1–3挡住就只留次要圆点，不事后补播|
|5 持续状态|番茄钟、音乐、任务等|无|各屏最多3条；从最新模型重算，不保留被抢占时的旧动画|
|6 静默|没有可见内容|无|取消计时器与显示链接，不做空转刷新|

4秒、0.6秒、最多3条取 `docs/blueprint.md`；不得拿 `design-system.md` 旧提醒2.6秒覆盖新版六层仲裁。动画令牌取 design-system §4.6；本合同不新增弹簧常数。

## 2. 状态转换和同一时刻规则

|当前状态 / 事件|确定动作|原因|
|---|---|---|
|空闲 + 合法1/2/3层申请|建立新token、写入当前owner与屏幕、返回 acquired|避免多屏各自批准|
|同一owner同一token的内容更新|更新快照，不更新期限、不生成新租约|更新文字不能无限续期|
|同层另一owner申请|返回 busy；请求队列由请求所属模型保管，不复制进协调器|避免抢焦点|
|更高层申请|先同步取消旧owner的输入/捕获，再撤旧租约，最后发布新层|旧手指松开不能点击新审批|
|更低层申请|返回 busy；原模型继续运行，界面不自动重试抢位|避免后台任务夺焦点|
|释放、到期|撤销对应token；本屏由最新状态回到5/6层|不恢复旧交互、未发音频、轨迹或待确认弹层|
|结束后的迟到回调|token/epoch不匹配就丢弃|不能复活旧面板|
|锁屏、锁态未知、睡眠、会话切走、功能关闭|先environmentEpoch加1，清全局租约，取消所有输入源和私密内容；5层敏感内容也隐藏|不能等淡出动画结束才停止输入|
|解锁或唤醒|读取真实锁态，重新枚举屏幕，只发布非敏感最新持续状态；不自动重连控制、录音、审批|解锁不代表再次同意执行旧动作|
|当前显示器被拔出|撤当前token并取消输入；不把仍按着的手势搬到另一屏|换屏须新的一次操作|
|其他屏幕被拔出|删除该屏快照；不改有效全局租约|避免无关显示变化中断输入|
|屏幕参数改变但显示器ID不变|保持token但重算坐标；正在依赖旧几何的拖动取消|旧归一化基准不可继续使用|
|手动把同一展开视图转到另一屏|原租约释放，再以新token申请；原手势取消|显示器属于租约身份|
|更高层离开，旧层还有未完成后端任务|任务继续；只允许5层状态出现；用户重新打开才申请3层|任务生命周期和界面生命周期不同|

事件总线先在唯一串行入口分配严格递增的本机 sequence。UI、HID、触控、助手和计时器共用这一编号域；设备原始序号只用于来源校验。`receivedAt` 取同一 `WS2Clock`。正常事件保持入口顺序，不能为了优先级把后到的审批移到旧按下之前再给新序号。

锁屏/睡眠/会话撤销是批次屏障：先撤销环境代次，再丢弃该批旧代次输入，不把它们当作一个乱序的普通 Envelope 发给 reducer。一次主循环批次里现成输入先于到点回调提交；L1 另有 `handleBatch`，显式把用户输入/取消放在 `commitLock` 前。到点的实际OS请求一旦已发出，后来输入无法保证撤回，所以 L1 分 prepare 与 commit 两步，实际锁态回执才决定归属。

确认必须满足：当前授权租约、当前请求仍待答、未超时、开始时间不早于该审批发布、开始序号大于 `shownAfterSequence`。按键按下时保存其序号，不能以 up 的新序号替换。双击只收到clickOnly的源必须由桥接器维护真实事件顺序；没有down/up的来源不得编造一次旧按压。

## 3. 接口签名

以下接口由后续主模型实现于 `prototype/App/InteractionCoordinator.swift`。这些是要实现的接口，不在本份交付的纯逻辑代码中假装运行。

```swift
@MainActor
protocol InteractionCoordinating: AnyObject {
    func acquire(_ request: WS2.LeaseRequest) -> WS2.LeaseDecision
    func release(_ lease: WS2.LeaseHandle, at: WS2.Instant)
    func isCurrent(_ lease: WS2.LeaseHandle) -> Bool
    func invalidate(_ reason: WS2.LeaseRevocation, at: WS2.Instant)
    func removeDisplay(_ id: WS2.DisplayID, at: WS2.Instant)
    func snapshots(at: WS2.Instant) -> [WS2.VisibilitySnapshot]
}
```

新协调器在 MainActor 串行使用。`acquire` 必须先读权威锁态和当前显示列表；不接受过期 deadline、未知owner、错误层级、无效显示器。各子系统TokenSource使用固定TokenDomain；同一boot只创建一次，禁用/重开不得重建编号源。协调器使用interaction域。整体重建状态需轮换bootID并作废全部旧回调，不可在同一编号域从1重来。environmentEpoch 增长禁止 `&+=` 回绕；溢出停用本次进程交互。期限由对应模型给定，不设一个能无穷续租的通用心跳。提醒、滚动帧和设备采样不续租。

协调器的 `onRevoke(owner, reason)` 先同步调用输入适配器 cancel（I1e.cancelAll、I1f切回遥控、D1.cancelInput、触点cancel），确认无新的合成事件，再让 NotchPanel 清内容。A1待答请求不能由协调器自动“拒绝全部”：关闭/过期的协议响应交回A2/D6按其确定能力处理。

## 4. 现有代码的精确接点

行号相对本轮上传快照；锚点与签名比行号更权威。源码变了先对照，不把旧整文件盖回去。

|文件:行|既有符号/签名|接法|
|---|---|---|
|`prototype/Core/NotchActivities.swift:86,135`|`struct NotchActivityStore`；`mutating func upsert(_ activity: NotchActivity, now: Double) -> Bool`|只存5层普通活动；不得加入approval.kind来争抢3条名额；时间使用同一适配后的单调秒域|
|同文件:168,180|`end(id:generation:now:)`、`prune(now:)`|模型到期产生持续状态变化，重算各屏快照；不得复活墓碑中的旧generation|
|同文件:194,201|`select(id:) -> Bool`、`moveSelection(by:)`|只有当前租约owner可操作选择；未获租约的屏幕只能显示|
|`prototype/App/NotchActivityController.swift:51,62–64`|`configure()`、`private suspend(_ reason: String)`、`private resume(_ reason: String)`、`private stop()`|环境屏障先撤租约再暂停来源；resume只取新快照，不恢复旧操作|
|同文件:103,117|`private publish()`、`perform(_ action: NotchActivityAction)`|publish改为向协调器提交候选；perform入口先核租约、当前目标、锁态；不直接绕过协调器点按钮|
|`prototype/App/Notch.swift:29,67–71`|`NotchController`、`activities`、`authentication`、`authenticationPanel`|控制器持有唯一协调器；现有authentication继续作1层，不新建第二套身份面板|
|同文件:126,131,139,145,149|`notchScreen`、`notchRect(...)`、`slotRect(...)`、`private static displayID(_ screen:)`、`panel(for:)`|复用现有按屏几何与面板查找；不要用NSScreen.main覆盖租约的目标屏|
|同文件:186–187|现有 `onActivityAction`、`onActivityMove` 接线|发送时附当时lease，不从回调里事后取一个新lease补上；旧回调令牌拒绝|
|同文件:231|`authentication.reconcile()`|在协调器决定1层呈现与结束时重调；背景publish不能把authenticationPanel覆盖|
|同文件:749|`func tuckAll(on screen: NSScreen? = nil) -> Int`|T1/L1副作用只在App边界执行，并单独保存本次归属集合；返回数目不是恢复凭据|
|同文件:1314,1428,1440|`NotchPanel`、`setAuthentication(_:animated:)`、`setActivities(_:selected:)`|由协调器输出驱动。1层存在时停发会覆盖内容的活动更新；3条裁剪只属于普通活动|
|`prototype/App/AuthorizationService.swift:28–29`|`consume(_:purpose:currentTarget:) -> AuthFailure?`|返回nil才成功。只由审批执行服务调用，不把这个方法暴露给任意输入回调|
|`prototype/Core/AuthorizationLedger.swift:83,99,124,151`|`begin(target:ttl:)`、`complete(_:signature:publicKey:lock:)`、`consume(_:expectedPurpose:currentTarget:lock:)`、`advanceSessionEpoch()`|保持唯一授权账；按实际target重算摘要，恰好一次消费。WS2 Token、CostTicket、RSSI和voice Bool都不能替代grant|

注意：上表简写的符号参数须以附录 `existing-symbols.md` 的原始声明为准；没有列出的 private 成员不得直接改成 public 来绕封装。

## 5. 授权与纯模型之间的唯一桥

A1是待审批请求状态的所有者，D1是当前一条审批的输入呈现。A1的 `.requestAuthorization(intent)` 交现有身份服务；D1的 `.approvalChoice(...)` 先交A1.choose，再走同一服务。普通请求同样走服务，没有快捷 allow。`auxiliaryVoicePassed` 只供流程选择；服务要从挑战仓库拿回与请求摘要/代次/有效期匹配的证据，不能相信 UI 传来的Bool。

协议真实动作（类型化request ID、方法、thread/turn/item/approval ID、规范化的实际命令/路径/权限变更）组成 AuthTarget；不能用显示摘要、窗口标题、模型文本来签授权。服务消费前再次确认当前pending和授权租约，重算target，核锁态，调用consume，成功后只发一次协议应答，再发送 `.dispatched` 给A1。A1收到dispatched不再回复第二次。

A1请求最初保存与展示的时机由桥接器负责：若还在排队，不可令一个“已可见”的标记提前生效。UI挂载完成、当前1层lease生效后才向该视图交 `ApprovalRequest`，并把此时的总线序号填入 shownAfterSequence。未展示条目可以保存在上游受限队列，A1也能保存其状态，但桥接器不允许对未展示条目调用choose。现有纯模型不会证明真实像素已上屏，这条必须在A3/D3适配层测试。

实际OS解锁是另一用途。现有 ledger.complete 要求 unlocked，不能为了 L1 返回候选改成“锁着也批准任意用途”。L1只产生返回身份流程候选；F1/L3与锁屏后端探针未过，不实现输密码、不称已能刷脸解锁。

## 6. 必须跑的宿主集成场景（本轮未执行）

|ID|输入|必须看到|
|---|---|---|
|LEASE-01|两屏同时展开不同视图|只有一屏能响应，另一屏申请busy|
|LEASE-02|按住中心键后收到审批，再松开|不确认审批；新按压才进入身份流程|
|LEASE-03|录音时1层抢占|麦克风停止、旧转写丢弃、不发送草稿|
|LEASE-04|提醒被审批挡住、4秒后审批关闭|不补播旧提醒，持续状态从最新模型计算|
|LEASE-05|锁屏与发送同批|epoch屏障生效；零新submit/allow/合成键|
|LEASE-06|显示器拔掉后旧手势回调|旧token拒绝；其他屏无自动点击|
|LEASE-07|审批完成后后端继续发任务状态|状态不遮住尚未结束的身份流程；结束后只刷新持续状态|
|LEASE-08|窗口自动收起后用户自行移动/恢复，再自动恢复|归属账排除用户已接管窗口；不恢复整套历史布局|
|LEASE-09|重复dispatched或网络重试|零重复allow；后端原request ID只终结一次|
|LEASE-10|未知锁态 / session resign / app disable|所有交互清空，敏感像素和音频不继续|

这些测试不能用纯模型测试代替。下一批App施工单必须按这些ID给出具体测试入口。
