# 第六份决策账

以下为项目工程决策；容量和超时均不是 Apple 标准或本次测量值。协议事实来源见 sources/REFERENCES.md。标为“仍缺”的项必须写出代码再验收，不能只切开关。

|编号|已定做法|理由|落点|状态|
|---|---|---|---|---|
|R6-001|只在精确 v5 候选上暂存；实际工作区更晚就三方合并|避免旧补丁盖掉用户的新修复|tools/stage.py|已实现并验证|
|R6-002|保留唯一 AppRuntime、Island、Wire 和授权账|同一事件不能由多个宿主竞争消费|工单 01、02|架构边界，真实 Runtime 接线仍缺|
|R6-003|普通页面替换必须携带当前 exact lease|同优先级换页不能成为挤走审批的通用能力|InteractionCoordinator.acquire(replacing:)|已实现并测试|
|R6-004|不得先 dismiss 再申请新租约|申请失败时必须保留原审批|WS2IslandCoordinator.show|候选源码，仅语法检查|
|R6-005|同步 cancellation 中的锁态/禁用仍推进 epoch|不能在 inTransition 中漏掉撤销|InteractionCoordinator.invalidate|已实现并测试|
|R6-006|过渡中 display 变化保守撤销本次交接|缺少完整屏幕快照时不把旧 token 发给新屏幕|InteractionCoordinator.removeDisplay|已实现并测试|
|R6-007|await 后及物理写入前重新核对连接、项目和锁态|内存隔离不等于业务状态仍有效|docs/02、工单 02|约束；部分生产调用者仍缺|
|R6-008|项目只从本地选择器产生，路径不是远端参数|远端不能选定本机任意工作目录|WS2OwnedScope；WS2ProjectDirectory|纯核已实现；本地入口仍缺|
|R6-009|目录身份含 canonicalPath、device、inode|同名目录被替换时使旧上下文失效|WS2ProjectDirectory.read|临时文件系统测试通过|
|R6-010|Scope 只防跨会话错配，不宣传为文件沙盒|检查与使用之间仍可能有文件系统竞争|docs/04|明确限制|
|R6-011|解锁不恢复上一次 active ticket|旧请求不能穿过一次锁屏继续批准|WS2OwnedScope|已实现并测试|
|R6-012|新建和恢复 thread 显式 read-only/on-request/user|不依赖外部宽权限配置|CodexWire|编码和固定 schema 通过|
|R6-013|turn 再显式 readOnly 且 networkAccess=false|会话级配置不能被本次消息省略|CodexWire.startTurn|编码和固定 schema 通过；实际执行未验|
|R6-014|只读不等于只读当前项目，工具网络不等于模型联网|避免权限文案过度承诺|docs/04|产品与安全说明|
|R6-015|旧 thread 恢复必须复核项目关联|ID 合法不能证明它属于本地当前项目|工单 02|仍需实际生产代码|
|R6-016|诊断默认不采集；单次启动显式 opt-in|减少命令、路径和凭据进入内存日志|WS2DuplexProcess.init|通道已实现；设置/UI 未接|
|R6-017|诊断尾部上限 65536 字节；每回调最多读 65536 字节|错误洪水不允许形成无界缓存或长期占用主队列|WS2DiagnosticTail；DuplexProcess|已实现并测试；数字为工程默认|
|R6-018|诊断纯文本转义，不自动导出或发送模型|转义不能当作密钥脱敏|DiagnosticTail.visibleText；工单 03|纯核通过；导出不在本轮实现|
|R6-019|队列接纳、写管道、RPC 回复、turn 最终事件分别显示|避免用传输成功冒充执行成功|docs/03|实际 UI 状态订阅仍缺|
|R6-020|stop 先撤销权限和待批准，再断通道|不让停止期间的新回调继续获准|工单 02、03|完整 Runtime 生命周期仍缺|
|R6-021|200ms 收尾从 Foundation 通知送达时算|当前 Linux 探针不支持从内核退出时刻计时的承诺|DuplexProcess；PROC04|限制已记录，PROC04 仍 BLOCKED|
|R6-022|不对保存的旧 PID 或不自有的进程组盲目强杀|PID 重用及共享终端可能误伤其他任务|工单 03|监督 helper 尚未实现|
|R6-023|新监督端口只由一个所有者负责 wait/reap|不能与 Foundation 争抢退出状态|工单 03|建议设计，尚未实现|
|R6-024|列表使用稳定 ID 和快照 revision|视觉上的第 N 行可能已变成别的项目|WS2SelectionModel|已实现并测试|
|R6-025|一次只保留一张当前 activation 票据，消费一次|重复回调不重复打开项目或提交动作|WS2SelectionModel|已实现并测试|
|R6-026|无效或重复 ID 的列表快照清空选择及旧票据|拒绝看似成功但来源歧义的动作|WS2SelectionModel.replace|已实现并测试|
|R6-027|上下选择跳过禁用行，不循环首尾|默认导航可预测，边界不产生意外跳转|WS2SelectionModel.move|已实现并测试；工程选择|
|R6-028|输入只路由 typed intent，不向任意前台发 Return|避免指挥操作落在密码框、终端或其他应用|工单 04|真实原生 sink 尚未实现|
|R6-029|V1 一个本地启用的手柄，换上下文先 cancel/neutral|减少旧 held state 进入新项目的机会|既有 DeviceActionHost；工单 04|保留 v5 限制，设备未实测|
|R6-030|网络最多总计 8、未认证 2、同一 peer 1 连接|认证前也必须有总量预算|WS2ConnectionBudget|纯核已实现；Listener 未接|
|R6-031|配对 60 秒、验证 10 秒是绝对期限|逐字节慢发不能续命|WS2ConnectionBudget|纯核已实现；时间为工程默认|
|R6-032|单连接待发上限 262144 字节，全局 524288 字节|各连接都合法不代表总内存有界|WS2ConnectionBudget|纯核已实现；真实 writer 记账未接|
|R6-033|Budget.promote 只接本地密码学验证结果|peerID、设备名或一个远端 Boolean 不是证据|工单 05|装配约束，生产 verifier 到 Listener 仍缺|
|R6-034|OPACK 限制深度、对象数、长度及完整帧消费|合法类型也可能造成资源消耗或歧义|工单 05|codec 尚未交付，不把预算核当 codec|
|R6-035|Bonjour 仅提供发现，不赋予任何认证或输入权|服务名、TXT 和网络位置可以不可信|docs/06；工单 05|安全约束，原生 Remote 互操作未知|
|R6-036|保留全局 3 次失败/300 秒冷却，不按 IP 或重开窗重置|延续第五份对低熵 PIN 的失败预算|v5 PairingAttemptWindow/工单 05|继承规则；本轮未复测真实配对|
|R6-037|窗口回执必须来自真实隐藏/恢复结果|列表有条目或动画结束都不足以证明系统状态|工单 06|实际 AX/恢复端口仍缺|
|R6-038|缺失 AX/app 观察记 unknown，不记成功|新事务不能继承旧 helper 的 nil 即成功语义|docs/07；工单 06|明确新端口规则，旧全局函数未改|
|R6-039|窗口完成绑定 run、effect、identity、transactionID|按 windowID 批量完成可能命中新一代请求|工单 06|typed completion 仍需生产改造|
|R6-040|只有本轮确实改变且仍归本轮所有的窗口才自动恢复|用户后来的调整优先于程序旧回执|既有所有权模型；工单 06|模型可复用；真实行为未验|
|R6-041|人脸存在、声纹相似、心率变化不提升为系统解锁权|信号不等于可靠身份凭据，更不代表系统授权|docs/08|风险边界；未采集生物数据|
|R6-042|发布状态按能力逐项，不能用通过数量抵消缺项|让执行模型看见真实障碍|tools/readiness.py|检查器通过 18 个合成测试，不认证产品|
|R6-043|Mac SDK 检查用隔离复制且排除 local-codesign.env|编译检查不应引入签名配置或触碰真实工作区|tests/run-mac-check.sh|Linux 返回 78；Mac 未运行|
|R6-044|不重新发旧样片当新成片，不修改更新源或发布 1.0.16|功能证据、声音授权和发布授权均仍未取得|REMAINING.md|本轮未出片、未发布|
