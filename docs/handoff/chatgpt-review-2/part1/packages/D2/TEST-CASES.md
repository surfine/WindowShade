# D2 输入与预期结果

测试时钟由sec()注入。fixture值全部是测试专用合成ID/摘要/文字，不会请求真实助手或操作系统。下表行范围包含完整输入序列；同一用例内每个expect都是必须保留的行为约束。

|用例|输入情景|预期状态与效果|可执行输入位置|
|---|---|---|---|
|D2-01|真实能力只列四档|只允许原值，无静默降档；逐档原值；四档应受支持；max 不能偷偷等于 xhigh；无原生 ultra 不发送|`tests/ConductorCapabilitiesTests.swift:11–18`|
|D2-02|明确列出的原生 ultra/max|受支持但须费用确认；原生高开销需确认；原生值|`tests/ConductorCapabilitiesTests.swift:19–24`|
|D2-03|Claude 已登记 ultracode + xhigh|工作流程字段；Codex 不借用绑定；显式工作流程；不得声称原生 ultra；Claude 绑定；Codex 不冒充 Claude 工作流|`tests/ConductorCapabilitiesTests.swift:25–32`|
|D2-04|固定四个位置、能力重排/消失/重复|位置稳定或明确不可用；列表重排不移动位置；缺席不移位补空；重复身份拒绝；恰好四槽|`tests/ConductorCapabilitiesTests.swift:33–38`|
|D2-05|审批前开始的按压、30 秒候选边界|都不能确认高费用；不能借先前 down；必须是新的序号；半开 30 秒期限|`tests/ConductorCapabilitiesTests.swift:39–46`|
|D2-06|确认后同绑定消费两次|只第一次成功；精确到期失败；新点按确认；一次性消费；票据到期即不可用|`tests/ConductorCapabilitiesTests.swift:47–52`|
|D2-07|peer/项目/会话/代次/模型/能力/工作流程/草稿/候选任一变化|销毁旧票；错目标后旧票也作废|`tests/ConductorCapabilitiesTests.swift:53–69`|
|D2-08|摘要长度错误、空能力、错误能力版本|拒绝；摘要恰好 32 字节；旧能力不接受新配置；空集合不是任意档位|`tests/ConductorCapabilitiesTests.swift:70–75`|

## 重复执行

`bash tests/run-conductor-capabilities-tests.sh`；可从任意cwd调用完整路径。脚本通过自身路径定位根。FAIL会退出1，编译错误保留非零退出码。当前完整Linux结果见VALIDATION。
