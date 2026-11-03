# W04　原生批准与外部hook分别接通

负责人：主模型独占授权策略；执行者不改安全决定。合入依赖：W01。

## 实际阅读与修改范围

`prototype/App/AuthorizationService.swift`

`prototype/Core/AuthorizationLedger.swift`

`prototype/App/WS2CodexApprovalHost.swift`

`prototype/App/WS2OwnedCodexSession+Authorization.swift`

`prototype/App/WS2OwnedLaunchController.swift`

`prototype/Core/CodexWire.swift`

`prototype/Support/WS2DuplexProcess.swift`

`docs/agents-in-notch.md`

`docs/handoff/deepseek-menu-agents.md`


## 两种宿主不得混为一条

owned app-server 由应用创建并负责响应，无法处理的审批必须拒绝/取消，不假设另一个UI接棒。外部终端的 hook 则应遵守该provider固定版本和事件阶段的原工具默认处理。App没运行时返回什么要以实际hook协议逐项验证，不能把 `{}` 定成所有场合的自动允许。

保留当前只读入口及默认拒绝提升。额外普通命令的允许路径需要独立明确的本地能力准入，不改变旧入口的静默默认。新的profile由主模型依据实际CLI有效配置审定，不能仅在UI写“只读”却后台打开工具。

## 一次普通命令批准的实线路径

真实request → 精确requestID/连接代次/thread/turn/cwd/完整命令快照 → 原生完整审阅 → 当前授权对象 → 系统认证 → 再核对目标与期限 → `AuthorizationService.consume`成功 → 同一writer一次性发送。UI摘要、设备名称和工具自称低风险不参与是否允许的判定。

请求排队过期、项目换代、锁态未知或认证取消，全部撤销。consume成功后发生断管/部分写入，保留结果未知，不退款式重建grant，不换连接重发accept。writer前与每批写入的当前上下文检查都保留。

文件没有可信diff时拒绝；网络范围和持久规则没有独立可信展示与授权时拒绝。不能把普通命令同意升级为允许整项目写入或未来同名命令。

## hook生产接入

复用既有A1会话与A2配置事务、socket/helper；配置预览、精确旧值比较、原子替换和失败回滚只在用户明确同意后执行。测试用独立临时home。Unix peer UID、socket路径替换、原程序不在、超时与重复request都留样本。

Claude 与 Codex 各自冻结实际版本、hook名称、输入/输出形状。没有读到该版本文档或实测消息时保留旁路，不猜TOML/JSON字段，不全局写用户配置。

## 合格条件

同一请求只consume一次、只接受一次；拒绝/取消/锁中晚回调无allow；两同名命令不同cwd不得共用批准；旧连接回复不影响新会话；命令在终端实际结果与UI一致。所有这些需要真实系统认证与固定CLI，schema和假后端只能覆盖一部分。
