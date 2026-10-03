# I9 输入与预期结果

测试时钟由sec()注入。fixture值全部是测试专用合成ID/摘要/文字，不会请求真实助手或操作系统。下表行范围包含完整输入序列；同一用例内每个expect都是必须保留的行为约束。

|用例|输入情景|预期状态与效果|可执行输入位置|
|---|---|---|---|
|I9-01|规则网格左右上下|正确下一格，到边不绕回；向右；向下；边缘保持；向上|`tests/FocusNavigatorTests.swift:14–19`|
|I9-02|参差行含洞、隐藏/禁用/其他屏|只找可见可用本屏格；投影重叠优先于斜向近格|`tests/FocusNavigatorTests.swift:20–22`|
|I9-03|同组尚有右侧目标|不先跳进更近的别组；组内优先|`tests/FocusNavigatorTests.swift:23–25`|
|I9-04|离组再回组|回到该方向上仍可聚焦的记忆格；回到上次 b；记忆格被删除时重算|`tests/FocusNavigatorTests.swift:26–32`|
|I9-05|空、一格、失去旧焦点|none、留原处、按稳定顺序起步；空数组；单格；按位置起步不看输入次序|`tests/FocusNavigatorTests.swift:33–36`|
|I9-06|重复 ID、无效矩形、超容量|报错，不猜一个；重复 ID；非法数值；容量上限|`tests/FocusNavigatorTests.swift:37–41`|
|I9-07|对称距离、不同输入排序|用稳定 ID 决定，不抖动；稳定 tie-break|`tests/FocusNavigatorTests.swift:42–50`|
|I9-08|投影只重叠一点与重叠整边|同组中选重叠更多的格；不把1点和10点重叠当成一样|`tests/FocusNavigatorTests.swift:51–54`|

## 重复执行

`bash tests/run-focus-navigator-tests.sh`；可从任意cwd调用完整路径。脚本通过自身路径定位根。FAIL会退出1，编译错误保留非零退出码。当前完整Linux结果见VALIDATION。
