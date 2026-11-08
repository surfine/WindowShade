# 第九份决策账

全部容量和时间为工程值或既有项目默认，不是 Apple 性能保证。状态区分纯核、源码和实际系统。

|编号|决定|落点|证据状态|
|---|---|---|---|
|R9-01|使用精确 v8 增量，统一包直接使用 v9 候选|manifest/stage|已暂存核对|
|R9-02|隐藏观察分 hidden、visible、unknown|FoldVerifier/observeFoldHide|纯核通过，Mac 未测|
|R9-03|缺失 AX 或应用对象不兑换隐藏成功|WS2FoldCallbackGuard|实际源码，Mac 未测|
|R9-04|普通 on-screen 缺席不作为快速成功|FoldTransaction|实际调用已移除|
|R9-05|AX 最小化仅接受真实 CFBoolean|ws2ObservedBoolean|CoreFoundation 测试通过|
|R9-06|未知结果不跨策略追加最小化|scheduleFoldVerification|实际源码与 reducer 测试|
|R9-07|只有原方法 minimized 才允许同策略有限重试|salvage|实际写前检查，Mac 未测|
|R9-08|未知保留原 journal 和人工恢复入口|retainUnconfirmedFold|候选 UI 路径，未真机|
|R9-09|仅绑定本次捕获且仍存活的 token|bindFoldWaiters|实际完成账测试通过|
|R9-10|完成必须是指定 transaction，不按窗口批量成功|FoldCompletion|旧问题复现、新边界通过|
|R9-11|整批回调先取出，后排主队列|FoldCompletion/EvidenceAdapter|测试宿主通过|
|R9-12|每个成功投递前重查原成功 stamp|foldCallbackIsCurrent|锁/换代/期限测试通过|
|R9-13|false 允许表示未知，不宣称已经恢复|Browser 契约/工单|已明确|
|R9-14|旧 stamp 不因解锁或显示变化复活|sessionEpoch/presentation|pure stamp 测试，系统入口未测|
|R9-15|默认 freshness=2秒，拒绝相等截止和坏时钟|WS2FoldCallbackStamp|工程默认，不是平台上界|
|R9-16|observer route 单调不复用，撤路由先于撤 source|FoldTransaction/AXHelpers|实际源码，Mac 未测|
|R9-17|AX 通知触发重读，不直接证明窗口状态|handleAXNotification|实际源码，Mac 未测|
|R9-18|每应用不可变结果独立送回当前巡检批次|Reconcile|接线已改，AX 尚未运行|
|R9-19|下一巡检轮仍等待旧应用读返回，不能声称可强制取消|Reconcile/工单02|明确限制|
|R9-20|安装原生缩高时不跑嵌套 RunLoop|ShadeController|源码已改；fallback 需回归|
|R9-21|首帧 helper 继承调用者隔离，取值后再次复核|EffectFrameAwaiter|新旧严格 Swift 6 测试通过|
|R9-22|stamp/Event 不转换为 T3 Receipt，不开放额外权限|既有 Focus/只读入口|未改变能力准入|
