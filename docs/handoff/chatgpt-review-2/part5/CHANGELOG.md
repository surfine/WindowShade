# 第五份增量与更正

## 新增源码

Core：有界输出队列 WS2BoundedOutbox；一次性语义输入票据 WS2SemanticInputRouter；跨番茄钟阶段的串行窗口事务 WS2FocusEffectPlan。

Support：双向非阻塞子进程 WS2DuplexProcess；单快照持久身份 WS2PeerRepository 与 Mac Keychain 适配器；首次配对消息编排 WS2PairSetupServer；签名/AEAD 层 WS2PairSetupCrypto；有限 TCP 传输 WS2CompanionTCPTransport；单工窗口效果执行宿主 WS2FocusEffectExecutor。

App：WS2OwnedCodexSession 持有一个 Wire/进程/审批宿主/截止任务；WS2DeviceActionHost 持有一个 GameController 桥并向受约束的语义 sink 路由。

替换第四份两个文件：WS2CodexApprovalHost 增加共用 Wire 的生命周期方法；WS2GameControllerBridge 增加独立 motionReady，未接窗口动作时不启动摇杆运动循环。详细数量以 manifest 为准。

## 纠正旧说明和容易误接的接口

C01：第四份配对 prose 的 5 次失败/60 秒冷却与 PairingAttemptWindow 不符。本份统一为代码已有的 3 次失败/300 秒冷却，PIN 窗仍为 60 秒。不是把失败上限放宽。

C02：CodexWire.drain 已经为消息加了 LF。新进程通道的 admit 接收未终止消息，admitWireFrames 才接旧 Wire 的完整帧并规范化一次换行。不能在两层各加一次。

C03：第四份 WS2Clock 是带自身起点的单调钟，不能将它的 deadline 与进程 uptime 秒数直接比较。新的 owned session 把同一个 clock 传入 writer。

C04：tuckAll 是用户动作的切换入口，第二次可放回上一批，且默认按指针所在屏筛选。不得用于番茄钟的确定性“收起这些窗口”命令。

C05：Notch.finishTuck 的成员登记早于最终折叠验证。FoldCompletion 已有等待器，但 Bool 回调、30 秒兜底和按窗口批量结算不足以自动成为新的所有权回执。施工单规定所需事务绑定。

C06：Pair-Verify 候选不等于首次配对可用；服务端与客户端也不是可交换的角色。首次配对的内层编排、密码学实现、协议封装、原生互操作分别验收。

C07：参考 pyatv 文件的 M6 处理存在未验证签名的 TODO。本包没有继承这一信任缺口，M5 输入必须验证签名；未来控制端也必须验证 M6。

C08：外部 swift-srp 的 padGeneratorForProof 只改变一个哈希输入。A/B/S 的补零及 K 是原始 bytes 还是 hex 字符串还必须独立核对；不能仅改一个布尔值就宣布兼容。

C09：revoke 在内存里成功不代表磁盘已撤销。新仓库先持久化再发布 revision；失败停用远端功能并显式报告“撤销未保存”。没有把多项 Keychain 调用说成跨进程事务。

C10：写入全部 bytes、Network.contentProcessed、JSON schema 合格均不等于远端已执行。允许消息一旦结果不明，不跨连接重放，也不把新授权账消费回来。

前四份历史文档原样留在合并包的 part1–part4 中。对本份所列接口与更正以第五份为准；其他既有合同不因没有重抄就作废。
