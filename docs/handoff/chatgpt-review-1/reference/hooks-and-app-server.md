# A2 / D6 协议合同

核对日期2026-10-03。[Claude hooks](../sources.md#s02)、[Codex hooks](../sources.md#s03)、[Codex App Server](../sources.md#s05)。这里是独立编写的最小协议对照，不包含宿主源码。运行前记录 `claude --version` / `codex --version`、可执行文件路径和 schema 哈希。网页与安装版本不一致时停止对应接线，不升级或改权限以求方便。

## A2：事件和响应

| 事件 | 本地语义 | 不能推导 |
|---|---|---|
| SessionStart | 建立/恢复观察记录 | 获得控制终端的权限 |
| PreToolUse | 看见工具请求 | 命令已经执行 |
| PermissionRequest | 宿主请求审批；可能挂起等待 | 所有危险操作都一定经过该事件 |
| PostToolUse | 成功后的事件 | 失败也必定经此事件 |
| PostToolUseFailure（仅版本支持时） | 失败后的事件 | 整个会话已断开 |
| Stop | 一轮停止/待续 | 进程或会话已经关闭 |
| SessionEnd（仅版本支持时） | 结束观察 | 可以把之前未知提交结果改为成功 |

两家分开使用自己的 schema。Claude PermissionRequest 输入不能假定有 `tool_use_id`；用本地请求UUID加provider/session/连接绑定，不仅靠工具名去重。Codex带turn_id时保留；缺失字段不能编造。普通通知不等待用户审批，尽快返回无决定。PermissionRequest 最多等本包规定的120秒，宿主 command timeout 留足进程清理余量；示例125秒是本项目配置值，不是厂商默认值。

无App、用户取消、锁屏、超时、未知版本或未知事件：stdout写 `{}` 和换行，exit0。**这表示不提供决定，绝不表示 allow**。宿主随后按自己的规则提示或拒绝；Claude在没有可交互UI的场景可能直接拒绝。Claude的sandbox网络权限也不一定经过此hook，不能声称覆盖全部授权。[S02/S03](../sources.md)

```json
{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}
```

上面只在A4已消费匹配一次授权后发送。拒绝用 `behavior:"deny"`。本项目不返回 `updatedInput`、`updatedPermissions`、`interrupt`；尤其Codex当前PermissionRequest不接受这些保留字段。日志仅进stderr且脱敏；stdout只能有协议JSON。不要把PreToolUse的`permissionDecision`结构套到PermissionRequest。

## 配置安装只操作用户已确认的对象

Claude常用用户层 `~/.claude/settings.json`；Codex当前支持 `~/.codex/hooks.json`，也支持config.toml中的hooks。Codex会合并配置层并并发执行匹配项，不能靠写高层文件覆盖旧项；也不能同时安装两种格式造成重复。本版先支持已经验证的JSON用户层，发现已有等价项时显示并让用户选择，不暗改项目层配置或trust库。

两份配置样例在 `fixtures/`。只演示PermissionRequest；其它观察事件由每个版本适配器显式列入。`command` 是宿主执行的命令文本，要对绝对路径逐层正确引用；不得插入用户项目名、窗口标题或未经处理的输入。占位路径必须在临时目录测试替换，不可直接写入真实home。

安装流程：解析并保留未知字段→按对象合并→生成diff→用户确认→比较文件仍等于读入哈希→同目录临时文件0600并原子替换。文件已变则撤销本次写入并重新展示，不覆盖他人修改。记录manifest中的对象指纹、原文件哈希与本次对象；不在JSON插注释标记。卸载只删仍与自己安装对象匹配的项，不把整个旧备份覆盖回去。拒绝symlink和非本人所有文件。Codex还要用户通过宿主的hook信任审核；本工具不得替它写信任记录。[S03](../sources.md#s03)

## Unix socket 边界

AF_UNIX流socket，父目录0700，socket0600；使用lstat/fstat与owner校验，accept后用Darwin getpeereid检查同UID。sun_path按本机SDK的实际字节容量校验；包含多字节用户名的长Application Support路径也要测。过长报错，不静默换公开/tmp、TCP或全局可写目录。需要短私有目录时由主模型批准路径和生命周期。

同UID只是一道过滤，**不能证明消息真来自受信CLI**。hook输入均当作不可信描述，不自带授权。每连接有随机代次与本地关联ID，限帧长度、并发、排队数量、读写截止时刻；孤立或重复响应不准匹配到另一会话。崩溃清理前先证实旧socket无人监听且owner符合，不删别的进程的socket。退出不等待不受限的写管道。helper放在prototype递归Swift收集之外，独立编译/嵌套签名属于主模型打包任务。[S10](../sources.md#s10)

## D6：stdio App Server

启动固定且核过身份的 `codex app-server`，不用shell拼命令。stdin/stdout是UTF-8 JSON按换行分帧，**省略 `jsonrpc` 字段**，不加LSP `Content-Length`。stderr单独有界读取。Process仍活着时就持续消费两条输出管道。

首次连接只发一次initialize；等成功响应后再initialized。失败就关闭该连接，不能在同一连接反复初始化。此后才发业务请求。

```json
{"id":1,"method":"initialize","params":{"clientInfo":{"name":"windowshade","title":"WindowShade","version":"review-fixture"}}}
{"method":"initialized","params":{}}
{"id":2,"method":"model/list","params":{"limit":20,"includeHidden":false}}
```

这些是连续三条线，不是一个JSON数组，且第二条要等第一条响应。model/list按nextCursor继续取页，读取`data[].model`作为模型标识，不能假定它等于`data[].id`。能力取`defaultReasoningEffort`及`supportedReasoningEfforts[].reasoningEffort`；保留描述和能力版本。未知effort不硬映射成更高档。

| 方法 | 方向 | 最小关键params / 结果语义 |
|---|---|---|
| thread/start | 客户端请求 | cwd、实际model；结果保存thread.id |
| thread/resume | 客户端请求 | threadId；只恢复可访问线程，不接管另一终端活动进程 |
| turn/start | 客户端请求 | threadId、input数组；需要覆盖时传model和effort |
| turn/steer | 客户端请求 | threadId、expectedTurnId、input；不能在这里悄悄换模型策略 |
| turn/interrupt | 客户端请求 | threadId、turnId；收到响应不等于已看到最终结束 |
| turn/completed | 服务器通知 | 以对应turn最终状态收敛，不靠按钮变灰猜完成 |
| item/commandExecution/requestApproval | 服务器请求 | 原id、threadId、turnId、itemId及具体命令/目标 |
| item/fileChange/requestApproval | 服务器请求 | 原id及当前文件变更目标 |
| serverRequest/resolved | 服务器通知 | 结束对应待审请求，迟到确认作废 |

```json
{"id":3,"method":"thread/start","params":{"cwd":"/tmp/ws-fixture-project","model":"fixture-model"}}
{"id":4,"method":"turn/start","params":{"threadId":"thread-fixture","input":[{"type":"text","text":"只描述当前目录，不修改文件。"}],"model":"fixture-model","effort":"medium"}}
{"id":5,"method":"turn/steer","params":{"threadId":"thread-fixture","expectedTurnId":"turn-fixture","input":[{"type":"text","text":"补充说明：只读。"}]}}
{"id":6,"method":"turn/interrupt","params":{"threadId":"thread-fixture","turnId":"turn-fixture"}}
```

示例model与ID都是合成占位，不是真实模型名称；必须用实际回包替换。turn/start中的覆盖可能影响该线程后续默认配置，D2需要重新读回/维护实际配置，不能只改界面。服务端承认收到请求与已经开始/结束执行分开。断流发生在提交之后而结果之前时标结果未知，不重放提交。

服务端请求ID可能是字符串或数字，保留类型；不与客户端请求ID共用单一字典。只有method存在的消息才走请求/通知分支，response走结果分支。获得匹配一次授权后，命令批准可回复：

```json
{"id":"server-approval-fixture","result":{"decision":"accept"}}
```

这是App Server响应，不能写成hook的`behavior:"allow"`。本版仅使用当前请求的accept/decline/cancel，不用acceptForSession或权限策略扩张。实际availableDecisions和锁定版本schema限制必须满足；拒绝/取消的区别按宿主行为展示。networkApprovalContext含host/protocol时必须让用户看见，不能拿无关命令文案代替。[S05](../sources.md#s05)

## 最低假后端测试集

逐字节/半帧/合帧、空行、UTF-8跨包、单帧超限、总队列超限、EOF半帧、坏JSON、未知字段/枚举；initialize拒绝、重复响应、客户端和服务端同值ID、跨session/epoch迟到响应；模型分页、无对应effort、steer轮次不符；收到start但未收到completed就断线；审批取消与确认同时到达；服务器先resolved再本地确认。测试保留unknown，不能为了绿灯填默认成功。

`D6.swift` 仅是字节分帧边界骨架，尚未实现以上完整协议。`fixtures/`仅为合成线格式材料，不是抓自真实CLI的成功录制。
