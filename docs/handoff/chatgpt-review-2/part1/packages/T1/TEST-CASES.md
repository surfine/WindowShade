# T1 输入与预期结果

测试时钟由sec()注入。fixture值全部是测试专用合成ID/摘要/文字，不会请求真实助手或操作系统。下表行范围包含完整输入序列；同一用例内每个expect都是必须保留的行为约束。

|用例|输入情景|预期状态与效果|可执行输入位置|
|---|---|---|---|
|T1-01|空闲开始 25+5|截止时刻 1500 秒，聊天收起一次；空闲不排刷新；开始不是累计 tick；重复开始无重复窗口动作|`tests/FocusTimerTests.swift:9–14`|
|T1-02|紧凑/展开/隐藏|分别排分钟、秒、截止唤醒；紧凑整分钟；展开一秒；隐藏只有到点；18 分原文；最后一分钟秒数；秒显示与截止对齐|`tests/FocusTimerTests.swift:15–21`|
|T1-03|专注自然到点再休息到点|计数一次，不自动下一轮；完整专注才计数；真实到点提示音；休息完空闲；重复 tick 无补发|`tests/FocusTimerTests.swift:22–28`|
|T1-04|手动暂停叠加锁屏|单独继续不解除锁屏暂停；暂停原因独立；暂停不醒来；正确顺延剩余时间|`tests/FocusTimerTests.swift:29–38`|
|T1-05|睡眠叠加锁屏，先唤醒后解锁|最后一个原因解除才计时；唤醒不能解锁；睡眠期间无扣秒|`tests/FocusTimerTests.swift:39–45`|
|T1-06|休息睡两小时|已结束，不补播开始或结束音；休息不因睡眠冻结|`tests/FocusTimerTests.swift:46–51`|
|T1-07|专注到点同刻锁屏|结算次数，但不收全桌面、不响铃；已完成专注仍计数；锁屏先于可见效果|`tests/FocusTimerTests.swift:52–57`|
|T1-08|专注跳过和主动结束|都不增加完成数；跳过不算完成；结束清理；明确结束优先于同刻自然结束|`tests/FocusTimerTests.swift:58–65`|
|T1-09|休息关掉收起的窗口|计时继续，恢复只发一次；只撤销本轮窗口归属；重复关闭无动作|`tests/FocusTimerTests.swift:66–71`|
|T1-10|旧日期的 deadline 晚到新日期|不记到今天，不闪过已过去的休息；晚到不补播|`tests/FocusTimerTests.swift:72–76`|
|T1-11|50+10，关闭聊天收起|3000 秒专注、600 秒休息；关闭选项不收聊天；十分钟休息|`tests/FocusTimerTests.swift:77–81`|
|T1-12|时间倒流/无效日期/锁屏开始|拒绝，不启动第二轮；拒绝倒流；锁着不开始；日期不可伪空|`tests/FocusTimerTests.swift:82–88`|

## 重复执行

`bash tests/run-focus-timer-tests.sh`；可从任意cwd调用完整路径。脚本通过自身路径定位根。FAIL会退出1，编译错误保留非零退出码。当前完整Linux结果见VALIDATION。
