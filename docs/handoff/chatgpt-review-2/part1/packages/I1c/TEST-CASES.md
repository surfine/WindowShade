# I1c 输入与预期结果

测试时钟由sec()注入。fixture值全部是测试专用合成ID/摘要/文字，不会请求真实助手或操作系统。下表行范围包含完整输入序列；同一用例内每个expect都是必须保留的行为约束。

|用例|输入情景|预期状态与效果|可执行输入位置|
|---|---|---|---|
|I1c-01|标题栏移动恰好 10 点后抬手|一次点击；大于而非等于十点才拖；重复 up 无点击|`tests/MiddleDragTests.swift:9–12`|
|I1c-02|短拖超阈值但不到提交进度|取消，不变成点击；短拖取消|`tests/MiddleDragTests.swift:13–16`|
|I1c-03|斜拖未形成主方向|原样放行，不猜轴；斜拖灰区；不突然提交|`tests/MiddleDragTests.swift:17–20`|
|I1c-04|锁定水平后垂直晃动|水平轴不翻转；固定主轴|`tests/MiddleDragTests.swift:21–23`|
|I1c-05|同轴往返，回到起点抬手|取消，不补发短按；往返取消|`tests/MiddleDragTests.swift:24–26`|
|I1c-06|四个明确方向大拖|对应既有标题栏/桌面意图；方向映射；标题栏单独意图|`tests/MiddleDragTests.swift:27–33`|
|I1c-07|未知区域/非法坐标/倒流/中途取消|不提交动作；未知区域放行；无效坐标取消；时间倒流|`tests/MiddleDragTests.swift:34–40`|

## 重复执行

`bash tests/run-middle-drag-tests.sh`；可从任意cwd调用完整路径。脚本通过自身路径定位根。FAIL会退出1，编译错误保留非零退出码。当前完整Linux结果见VALIDATION。
