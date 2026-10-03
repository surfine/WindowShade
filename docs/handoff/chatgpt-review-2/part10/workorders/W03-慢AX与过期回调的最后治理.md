# W03　慢AX与过期回调的最后治理

负责人：窗口执行者；主模型审查并发与私有接口。合入依赖：W01。

## 实际阅读与修改范围

`prototype/App/Reconcile.swift`

`prototype/Window/AXHelpers.swift`

`prototype/App/WS2FoldCallbackGuard.swift`

`prototype/Core/WS2FoldCallbackStamp.swift`

`prototype/App/FoldTransaction.swift`

`prototype/Effects/EffectFrameAwaiter.swift`

`docs/performance.md`


## 不退回旧行为

v9 的 stamp、route、三态和异步整批通知已经存在。保留这些语义；这单解决跨应用调度与慢 IPC，不恢复“读不到即成功”、windowID批量结算或嵌套RunLoop。

先记录每应用一次实际AX读取耗时、并发数、样本年龄和丢弃原因，不采窗口标题/内容。用原 App 上的快/慢测试窗口对照，确认是否确有整轮阻塞。没有证据不要先把所有读取搬到更多线程。

有阻塞证据时，原 Reconcile 里保留每应用一个在途状态与下一次最早准入时间。全局在途默认最多4，各应用轮转；同应用未回不重发。一次回调只更新其原不可变结果，不能等待其他应用才呈现已返回结果，也不能提前释放真正还在执行的槽位。

超时仅使其结果失效，不宣称调用被取消。明确永久阻塞时的可见降级：相关自动巡检停用、保留人工恢复，其他能独立处理的应用继续。若要进程隔离，主模型审查IPC和AX对象如何重新创建、权限持有、有限队列与退出；不得把跨进程不可用对象直接序列化。

## SDK与能耗

按实际 SDK 确认 AX 超时设置的签名、作用对象和错误码；文档页壳不算契约。更短超时可能增加unknown，不可为了减少耗时把它改成成功。记录主线程停顿及wakeups；原默认值都是工程参数，不是承诺。

## 验收

一个慢应用不堵住快应用的新一轮；旧读取返回不修改新事务；连续锁/解锁不积累读取；同一应用并发不超过1；总并发不超过预算；禁用后不启动新读取。实际IPC未返回时如实显示仍占用，不能计为已释放。
