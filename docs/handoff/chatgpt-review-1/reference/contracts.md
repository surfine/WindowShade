# 共享合同：主模型先冻结，执行包只消费

这份文件提出边界，不冒充原库已经存在这些接口。既有类型与建议新类型分开。最终文件名、符号名和写入允许列表由主模型绑定到实际工作区。

## 已存在、必须复用的部分

上传源码中 `App/AuthorizationService.swift` 的 `AuthorizationService` 为 `@MainActor` 服务。已有 `consume(_:purpose:currentTarget:) -> AuthFailure?`，**返回 nil 才表示消费成功**。`Core/SessionLockState.swift` 和原授权账负责锁态/epoch。`AuthPurpose` 已有 `approveAgentAction`、`enrollDevice`、`startRemoteControl`、`requestOSUnlock` 等值；不要另造不兼容的 `pairRemote` 字符串。

认证完成的公钥必须来自本机已登记可信身份，不能使用 hook 请求顺带送来的公钥。原账在锁屏/睡眠推进代次，且执行时检查 unlocked。系统解锁是主模型独立范围，不得删掉检查让普通 grant 能在锁态批准其他动作。

`Core/NotchActivities.swift` 的 store 有 upsert/end/prune/select 等行为，容量和普通活动优先级不能替代授权账。`App/NotchActivityController.swift` 现有入口不全是公开接口；执行包不能直接假定存在通用 `publish(activity:)`。由主模型增加必要的最小入口，不新建并行协调器。动效复用原 `Motion` 和 reduce-motion 设置，不引入第二套常驻时钟。

## 事件信封与时钟

建议内部事件至少有 provider、connectionEpoch、sessionIdentity、receiverSequence、commandID；涉及轮次时有 threadID/turnID，涉及遥控时有已验证 peerKeyDigest。源设备填可信绑定或 unknown。receiverSequence 由接收端单调生成，不接受远端任意大序号替换本地排序。重复或旧 epoch 事件不产生动作。

一个串行 reducer 处理状态和副作用决定。不可因回调线程不同而先处理授权再处理已发生的锁屏。UI 在 MainActor；底层用自己串行队列，跨边界传 Sendable 值快照。不要用 `@unchecked Sendable` 掩盖结构设计问题。

纯逻辑只接收已验证有限值的连续时钟秒数；回退时间、NaN、infinity 明确拒绝。系统适配使用 ContinuousClock 等连续单调时钟。[S01](../sources.md#s01) 番茄专注的暂停原因是集合；手动暂停不能被 wake 或 unlock 意外清掉。休息的截止时间跨睡眠继续走。Calendar 自然日和时区变化独立处理，不能拿开机秒数算“今天”。

## 三种票据不要互换

`EffortTicket` 只是用户确认昂贵模型配置，绑定对端、项目身份、会话、连接代次、能力版本、模型、最终 effort、workflow、草稿摘要、截止时刻。它不能批准文件/网络/系统动作。

`AgentApproval` 是待审请求，绑定 provider、当前连接/会话、宿主请求ID及规范化动作/目标摘要。展示文字不是签名目标。不能因截断标题、不同路径指向同一显示名而变成同一请求。

`AuthorizationGrant` 由原权威服务签发并一次消费。审批响应发出前，在同一隔离域重新核请求仍挂起、epoch/锁态/目标不变，再消费正确 purpose 的 grant，立即入队一份不可变响应。中间不 await。输出队列也要在实际发送边界处理锁态取消；已发出的执行无法靠UI收回，应标注真实结果。超时、连接关闭、失去前台批准界面、换会话均取消待决租约。

一个全局审批交互租约决定谁能接确认输入，各屏只展示对应状态。普通 store 满了不得挤掉审批或让不同显示器分别批准不同请求。正文可以滚动/展开看完整动作；八字文案规则不适用于隐藏风险信息。

## 输入边界

未启用、未授权、锁屏、未知设备、非目标设备、服务故障时透传。continuous/momentum 字段只是事件特征，不能唯一识别鼠标型号。按可信归属做 opt-in；无法可靠归属时宁可不提供该设备特定改写，也不偷改所有设备。

同一 down 的所有者要负责 drag/up。一旦替换原始按下，后续序列保持平衡；暂停/掉线/模式切换不能同时补发和透传同一 up。所有自产事件统一 tag，进回调先识别而不再次处理。源码已有 HabitKeys tag，主模型分配不冲突空间。

Play 短按在 release 才认定；长按触发一次并抑制该次 release 的短按。确认候选要求新的按下，画手势结束时的残留接触不算确认。中心 Select 是独立键，不吞并为触控点。TV 长按阈值按原规格 0.5s，Play 模式长按按原规格 1s；双 Back 的间隔、各模式导航优先级如原规格缺失，由主模型补全测试表，执行包不私自猜。

## 隐私、性能、证据

新输入源接线前在 registry 登记用途、读取内容、存储位置/权限、保留期、目的地、控制开关、失败行为。远端 CLI 子进程出网也算数据离开本机；不能只检查本 App 的 URLSession。日志不写原始命令、草稿、完整项目路径、窗口标题、PIN、密钥或生物样本。文件0600、目录0700和symlink防护是基础；同 UID 仍非可信证明。

每个能力分六级记录：声明/枚举/收到数据/正确解码/目标行为/回归验收。只有后一层通过才升级。没有设备时保留 not_run。能耗比较固定硬件、显示器、电源、签名构建、输入和设置，改前后成对测；CA 动画和隐藏面板也要记 WindowServer 成本。
