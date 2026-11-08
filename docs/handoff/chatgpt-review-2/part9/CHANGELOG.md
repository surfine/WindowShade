# 第九份变更

基线 v8，1164 文件；结果 v9，1168 文件。11 处替换、4 处新增，没有删除。以 manifest 的逐文件 SHA256 为准。

## 实际源码变化

增加两个小型现有路径适配文件：Core/WS2FoldCallbackStamp.swift 保存瞬时回调身份与严格 CFBoolean 判断；App/WS2FoldCallbackGuard.swift 将这些规则接到实际锁态、窗口观察、observer 和恢复提示。没有新建第二套窗口状态或 journal。

FoldCompletion 从按窗口批量通知改为事务绑定、整批取出、排队和成功投递复核。ShadeController 在原生/代理两条安装路径绑定本次 token，把 admission 复核扩展到普通窗口实际隐藏前，并移除安装中嵌套 RunLoop 等待。

FoldVerifier 引入 hidden/visible/unknown；旧 Bool initializer 为原 standalone 客户与测试保留，但生产调用改用 typed 初始化且没有 screen-absence quick shortcut。FoldTransaction 统一真实观察、限制同策略最小化重试、保存 unknown 的人工恢复入口。

AX observer 的 refcon 改为本次注册路由；移除先撤路由，旧通知排队后再次核查。Reconcile 每应用产生不可变快照，按批次与事务代次应用；活应用的多次 AX 失败不再仅凭计数清理原生状态。WindowShade.swift 增加相关账与上下文字段，删除不再使用的旧巡检工作队列字段。

EffectFrameAwaiter 使用调用者隔离并验证取帧后的取消、期限与捕获代次。WindowBrowserAppDelegate 只修正完成回调契约注释。tests/duo-integration-check.py 更新为显式 transaction 调用并增加绑定断言；原 Swift DuoCoreTests 不改。

## 集成与兼容注意

完成通知从同步改为主队列异步。false 可能是未知或过期，不等于未发生副作用；客户不能默认重试。即使已准备成功，投递前换代也会降为 false。

unknown 不再跨隐藏策略追加副作用，保留恢复入口。原生 resize 不再嵌套运行循环，较慢应用可能更常使用已有 proxy fallback。实际效果、焦点、Space、锁态与 AX 类型均需 Mac 回归。

完整 T3 自动恢复没有开放；原只读助手与手柄确认边界不变；没有新视频、真实账号、配对、签名或发布。
