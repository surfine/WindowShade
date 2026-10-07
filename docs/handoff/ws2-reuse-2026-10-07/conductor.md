# 指挥页接入真实 owned 后端

2026-10-07。本轮沿用唯一 `WS2OwnedLaunchController`、`WS2OwnedCodexSession`、`CodexWire` 和默认只读审批策略。没有另建 Runtime、进程控制器或授权账，没有使用真实账号发送助手任务。

## 已接通

原页面只保存 `highlighted`，并不改变后端线程。现在只展示本控制器曾在当前项目实际建立/恢复的会话，选择时发送 `thread/resume`；收到匹配目标的回执后才切换上下文。运行中、存在未应答请求或审批时不切换。列表保留短会话标识以区分同为“已完成”的条目。

页面的模型与思考程度明确标为“下一轮”。新增 `stageConductorModel` / `stageConductorEffort` 接口允许当前轮运行时暂存设置，不发送 `turn/start`、`turn/steer` 或打断当前轮；原助手页的 `canChooseModel` 行为保留。下一次明确发送时使用暂存值。

编辑文本只写入本机内存。点击“采用草稿”冻结连接、当前会话、输入代次、模型、程度、草稿代次和运行轮次；它不发请求。随后点击“发送”才发 `turn/start`；已有运行轮时按钮明确改为“补进本轮”，调用独立的 `addConductorDraftToTurn` → `turn/steer`。两种接口不可互换，不把过期的新轮发送悄悄变为补充。

控制器按实际 request ID 处理接收/拒绝回执，补充回执还必须匹配 `turnId`。回执只清掉自己那一版草稿；等待期间新编辑的文字保留。拒绝、结果未知、错误轮次回执不记成功。停止按钮绑定显示的连接、会话与 turn；`turn/interrupt` 回应仍显示等待，只有匹配的 `turn/completed(status=interrupted)` 才显示“助手已停止”。

切会话时草稿按会话留在内存，不带到新目标；换来又换回也不会恢复旧发送票据。锁屏清掉所有这些草稿、输入资格与可见会话。未新增磁盘存储。

## 改动

- `prototype/App/WS2OwnedLaunchController.swift`：目标绑定、真实会话选择、下一轮配置、采用/明确发送、补充/停止和回执处理。
- `prototype/App/WS2ConductorPage.swift`：同一现有页面增加发送/补进本轮、停止和回执，选择真实会话并取消旧按键预约。
- `prototype/Core/CodexWire.swift`：仅在没有运行轮、待应答请求和审批时允许切换线程；恢复未完成时禁止发轮，阻止重复补充/停止请求。恢复失败撤销预期目标。

`WS2OwnedCodexSession` 和授权宿主未改。写入通道仍复核当前 scope/项目/连接，`read-only`、`on-request`、`approvalsReviewer=user` 及默认拒绝额外权限保持不变。

## 检查

`bash tests/run-conductor-owned-flow-tests.sh` 通过：用独立临时目录内的合成可执行文件，走实际版本检查、配置、账号形状、模型列表、POSIX stdio、Wire 和唯一生产控制器。记录真实 JSON-RPC 请求，验证两条会话恢复、采用不发送、IME/重复/旧连接/旧配置/旧目标及 ABBA 拒绝、运行中改下一轮不发请求、start/steer/interrupt 回执、新编辑保留、拒绝和错误轮次回执、锁屏撤销。它不访问网络或真实账号。

旧 `tests/part7/tests/FlowTests.swift` 回归 **18 场景 / 145 断言通过**，包含额外权限拒绝、目录替换、登录取消及进程回收。既有 `ConductorPageTests` 16 项通过。页面与实际控制器/输入组件通过 Swift 6 严格并发、warnings-as-errors 类型检查（检查夹具只提取既有租约协议声明，不启动界面）。整 App 构建由主模型统一执行。

当前文件和测试产物摘要保存在 `conductor-evidence.json`。

## 边界

- 原生 iPhone Remote 的首次配对、服务 profile、按键/触摸到此控制器的投递由接收器工作包继续接；本轮先完成可被该接收器调用的真实后端操作接口。
- 只控制这个本地控制器实际掌握的 Codex 会话，不假装接管其他终端/Claude/任意项目。第一条会话仍从原助手入口明确建立，不在指挥页虚构空会话。
- 未进行真人 AppKit 手感、原生 Remote、后端真实账号或能耗验收；不能将合成进程协议测试写成这些已完成。
