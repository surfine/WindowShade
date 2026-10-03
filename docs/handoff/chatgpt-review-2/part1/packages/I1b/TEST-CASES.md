# I1b 输入与预期结果

测试时钟由sec()注入。fixture值全部是测试专用合成ID/摘要/文字，不会请求真实助手或操作系统。下表行范围包含完整输入序列；同一用例内每个expect都是必须保留的行为约束。

|用例|输入情景|预期状态与效果|可执行输入位置|
|---|---|---|---|
|I1b-01|连续/动量字段没有逐事件设备关联|不能据此认出设备；仅枚举不够；字段不能绑定硬件|`tests/InputDeviceKindTests.swift:10–13`|
|I1b-02|逐事件确认为滚轮鼠标|可进入滚轮改写路径；确认的滚轮|`tests/InputDeviceKindTests.swift:14–16`|
|I1b-03|已知 Apple 0323|妙控鼠标，仅方向层使用，不再平滑；0323 条目|`tests/InputDeviceKindTests.swift:17–19`|
|I1b-04|已知 0315 与未知 Apple PID|遥控器或未知，不进滚轮路径；0315 条目；未知 Apple 产品不猜|`tests/InputDeviceKindTests.swift:20–24`|
|I1b-05|确认的触控板和连续未知鼠标|都不做滚轮平滑；触控板让开；连续鼠标未证明是滚轮|`tests/InputDeviceKindTests.swift:25–30`|

## 重复执行

`bash tests/run-input-device-kind-tests.sh`；可从任意cwd调用完整路径。脚本通过自身路径定位根。FAIL会退出1，编译错误保留非零退出码。当前完整Linux结果见VALIDATION。
