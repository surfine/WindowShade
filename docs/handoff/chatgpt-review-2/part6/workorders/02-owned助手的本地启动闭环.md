# 工单 02　owned 助手的本地启动闭环

## 目标与文件

让用户在本机明确选择项目后，从现有刘海入口启动、查看并停止一个 owned Codex 会话。禁止自动启动 CLI、修改真实 home 配置或启动第二个平行状态机。修改 `prototype/App/WS2AppRuntime.swift`、`WS2SupplementPane.swift`、`WS2OwnedCodexSession.swift`、`WS2AgentSessionView.swift`、`WS2CodexApprovalHost.swift`。复用 Core/AgentSessions、CodexWire、WS2OwnedScope 与 Support/WS2ProjectDirectory。新增协调文件建议 `prototype/App/WS2OwnedLaunchController.swift`；这是待编写的调用者，本包没有把它计为已实现。

## 强持有关系与唯一实例

AppRuntime 持有一个 LaunchController，后者持有一个 Scope、零或一个 OwnedCodexSession，以及现有 AgentSessions 的入口。Island 由原 Runtime 持有，不由每个 session 创建。所有观察闭包 weak 捕获 owner；stop 先取消业务观察，再断管，最后释放强引用。旧 onEnd 必须比较 connectionID 后才能清空当前 owned 属性。

OwnedCodexSession 的 connectionID 当前在构造时生成。先构造候选 session 但不 start，再用该 connectionID 调 Scope.begin，保存 ticket 和强引用，最后 start。构造失败或 begin 返回 nil 就 stop 候选并返回；不可通过先启动来获得一个 ID。

## 本地入口逐步落地

1. 在现有补充设置页增加“选择项目…”和“启动 Codex”，运行后改为“打开会话”和“停止会话”。初始显示“尚未启动”，不创建假会话行。
2. 目录选择只接受本地目录。读规范路径/设备/inode，保存本地 UUID；显示完整路径供核对，按钮名称用短名称。
3. 在独立预检流程确认实际 executable 路径、可执行文件、版本与固定 0.153.0 协议适配。环境使用明确 allowlist 和本地配置，不把网络载荷当启动参数，不用 shell 拼接。
4. Scope.environment 写入真实 unlocked/enabled。建立 session、Scope ticket、闭包和强引用，再调用 start。
5. 协议处于 initialize/model-list 时显示“正在连接”；Wire.ready 才开放模型选择。只列真实 model 和该项支持的 effort。不要硬编码当前最强模型名称。
6. 收到绑定 thread 后才把它加入 AgentSessions。初始化阶段的 loading 不伪造成一个后端 session。对每条 onEvent 先核对 session.connectionID、Scope ticket 与当前 Wire 的 thread/turn，再更新既有 store。
7. 用户发送草稿经过一次明确动作。线程未就绪、中文 marked text 未提交或模型/effort 未选定时拒绝，保留草稿。

## 三个闭包不能用恒 true

`mayOperate`：当前 instance 与 ticket 相符、用户仍启用、系统已解锁、项目身份未失效。未知锁态返回 false。

`currentContext`：只使用当前后端产生的有效 session key 调 Scope.context。它可在初始化阶段为 nil，审批阶段必须有值。不能提前填一个随机 thread ID 冒充后端事实。

`scopeStillValid(review)`：核对 review 的完整上下文、cwd、项目、当前 thread/turn 与剩余期限。cwd 的规范解析结果必须是用户选择范围内的允许位置；发现符号链接或目录身份变化时先撤销。实际沙盒边界仍由受验证后端负责，路径辅助函数不负责权限隔离。

## 权限与状态决策

Wire 现在对 thread/start、thread/resume 和 turn/start 写明只读起步、on-request、user reviewer。模型返回 completed 通知时读取 status，失败、取消和成功分别显示。不要在 onLocallyWritten 里显示完成。

批准保持完整 review → 原生认证 → consume → 一次性编码 → 同代次 writer。文件、网络和持久规则路径仍明确不支持。当前已有审批列表但未自动绑定可见行时，只能显示待处理并由本地用户打开，不得默认接受或推送到另一处假设存在的原生弹窗。

## 必须同时接的撤销来源

现有 Runtime 的 locked/unknown、sleep、enabled=false、project change、session change、stop 和退出均先调用 Scope.invalidate，再停止 OwnedCodexSession，清当前待处理 UI。解锁不重启进程，用户点启动才创建新代次。后台会话完成不能关闭别的 feature 后来打开的 Island 内容。

## 最小端到端验收

使用用户允许的临时项目和隔离配置，先启动只读无副作用查询；验证真实版本、model/list、thread/start、turn/start、最终状态和停止。然后测试真实取消、锁中晚回调、目录替换、模型列表分页和旧会话回复。最后才测试一条无副作用普通命令的真实人工批准与拒绝。将真正运行样本与本包合成 fixtures 分目录保存；任何一步缺失都不能标为闭环完成。

## 原始 JSON 的额外边界

本轮 WireJSON 仍由 Foundation JSONDecoder 建字典，没有新增重复键预检。开放允许路径前，在完整、限长的原始帧上验证对象键唯一，递归对象都适用，再交既有解码器；不能在字典生成后检查重复。键比较按 JSON 字符串解码值进行，`"id"` 与 `"\u0069d"` 是同一键。仅在同一对象内拒绝重复，两个不同嵌套对象各自使用 id 应允许。不要用正则表达式检查整个 JSON 语法。

至少测试：两次 id；两次 params；转义后相同的 command 键；嵌套对象重复；字符串内出现字面冒号和引号；不同对象复用键；截断输入；超过深度上限。失败时关闭该协议会话并撤销待批准，不从两份值中随意挑一份。本包没有把这个新增预检写成已经实现。
