# 第九份：修复旧窗口路径，不再把未知当成功

直接使用统一 v9 的 `candidate-repo/`。本份精确基线为 v8 的 1164 个文件，不是公开仓库当前 HEAD。已有更新的工作区按 `base-sources/`、`overlay/` 和 manifest 三方合并；不要覆盖用户改动，不要重复叠前八份。

本份已经修复实际的 FoldCompletion、FoldTransaction、ShadeController、Reconcile 和 AX 回调路径，并修复 EffectFrameAwaiter 的严格 Swift 6 隔离问题。它没有新建平行窗口管理器，也没有把这些实际代码再留作下一份设计任务。先运行 README 的命令，再做完整 Mac 构建；不要降低 Swift 版本、屏蔽并发错误或删掉 Sparkle 来获得通过。

## 本次已经定下并写入的行为

收起结果分成 hidden、visible、unknown。缺失 AX 属性、类型不对、窗口身份不符或系统锁态未知，都不能报告隐藏成功。一般窗口不以离开当前 on-screen 列表作为隐藏证明。未知时不换另一种方法继续修改窗口，保留原恢复记录和人工恢复入口。

完成通知绑定具体 transaction 和捕获的 waiter tokens，先从账中整批取出，再排队通知。通知真正执行前还要重查当前事务、启动与锁态代次、显示上下文和有效期。布尔 false 包含未知、过期、取消，绝不等于窗口没有被修改或已经恢复。

后台巡检的结果随窗口、进程、事务、隐藏方法、boot、sessionEpoch、presentation 和采样时刻返回；旧结果不能清理新状态。AX observer 使用本次注册的单调 routeID，不能再拿 windowID 直接路由。通知只是核查提示，不直接兑换恢复或授权。

首帧等待显式继承调用者隔离；读取到帧后还会重查取消、捕获代次和期限。不要给帧对象随意加 Sendable 或将所有调用硬搬到 MainActor。

## 执行顺序

1. 在统一候选运行新 regression/frame 和旧 duo、part8 input/fold/flow。每套分别留命令与输出。第七份和更早回归命令也在 README。
2. Mac 上执行隔离的 `tests/run-mac-check.sh`。本轮 Linux 未取得 SDK，纯逻辑通过不能替代这个步骤。先修实际错误，再观察窗口。
3. 按工单 02 验证原收起、手动恢复、连续重收、切换 Space、权限丢失和锁屏。unknown 时恢复入口必须仍在，不能为了界面干净直接删除 journal。
4. 按工单 03 检验浏览器完成通知、首帧和慢窗口。原生 resize 不再通过嵌套 RunLoop 等待；较慢应用可能更常走已有 proxy fallback，需要真实对照。

完整 T3 自动恢复、配对接收、原生允许审批和系统身份后端没有因此完成。剩余的实际代码与证据分列在 REMAINING。保留默认只读助手，不改批准策略，不启用自动窗口效果，不改版本、更新源或签名身份。
