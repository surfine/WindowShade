# A1 输入与预期结果

测试时钟由sec()注入。fixture值全部是测试专用合成ID/摘要/文字，不会请求真实助手或操作系统。下表行范围包含完整输入序列；同一用例内每个expect都是必须保留的行为约束。

|用例|输入情景|预期状态与效果|可执行输入位置|
|---|---|---|---|
|A1-01|同项目不同会话、不同助手同 ID|三条独立记录；不按目录或显示名合并|`tests/AgentSessionsTests.swift:13–17`|
|A1-02|工具前后、停止|在跑、完成；工具重放不累积；工具幂等；完成归档|`tests/AgentSessionsTests.swift:18–23`|
|A1-03|普通审批新点按|只发授权意图；重复确认和错摘要结果不清请求；旧 down 不能放行；请求唯一授权服务；不重复申请；错目标通知无效；已由服务应答，不再回第二次|`tests/AgentSessionsTests.swift:24–34`|
|A1-04|整数7与字符串7|两次独立审批；返回只否定眼前一件；ID 类型不能转字符串混合；只拒绝当前 ID|`tests/AgentSessionsTests.swift:35–40`|
|A1-05|两分钟期限/更短宿主期限/迟到确认|到点交回，不默许；120秒上限；到期交回；迟到不批准；较短宿主期限优先|`tests/AgentSessionsTests.swift:41–49`|
|A1-06|600秒没事件|信息已久；明确进程退出 → 断开；无消息不是断线；明确退出才断；旧进程不能复活|`tests/AgentSessionsTests.swift:50–55`|
|A1-07|乱序和重连旧 epoch|不更改当前会话，不保留旧审批；重复序号拒绝；重连撤旧审批；旧代次拒绝|`tests/AgentSessionsTests.swift:56–61`|
|A1-08|同请求号换摘要|撤旧请求并交回，不能沿用已确认动作；碰撞不覆盖旧目标|`tests/AgentSessionsTests.swift:62–66`|
|A1-09|锁屏后事件到来|展示为空，敏感摘要清掉，审批交回；锁屏撤销审批；不在锁屏留标题摘要；解锁查询现状，不重播审批|`tests/AgentSessionsTests.swift:67–72`|
|A1-10|超出会话/请求容量|报容量并交回，不能挤掉待审批项目；会话上限；不驱逐已有审批|`tests/AgentSessionsTests.swift:73–80`|
|A1-11|风险类型明确或 shell 未知|高风险/未知不降成普通；明确声明的普通动作；不靠 shell 前缀|`tests/AgentSessionsTests.swift:81–84`|

## 重复执行

`bash tests/run-agent-sessions-tests.sh`；可从任意cwd调用完整路径。脚本通过自身路径定位根。FAIL会退出1，编译错误保留非零退出码。当前完整Linux结果见VALIDATION。
