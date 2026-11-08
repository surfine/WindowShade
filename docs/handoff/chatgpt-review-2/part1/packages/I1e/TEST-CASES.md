# I1e 输入与预期结果

测试时钟由sec()注入。fixture值全部是测试专用合成ID/摘要/文字，不会请求真实助手或操作系统。下表行范围包含完整输入序列；同一用例内每个expect都是必须保留的行为约束。

|用例|输入情景|预期状态与效果|可执行输入位置|
|---|---|---|---|
|I1e-01|12 个规定 HID 用法与未知用法|准确映射，未知不猜；HID 映射 \(u)；不捏造电源用法|`tests/SiriRemoteButtonsTests.swift:8–11`|
|I1e-02|100ms 短按、重复 down/up|一对阶段，无重复；按下；重复按下忽略；同一按压编号；松开去重无定时器|`tests/SiriRemoteButtonsTests.swift:12–18`|
|I1e-03|按住跨 0.5 秒和 1 秒|阈值各发一次，up 保留原编号；下一阈值；半秒；一秒；不持续重复 held；长按仍有匹配 up|`tests/SiriRemoteButtonsTests.swift:19–25`|
|I1e-04|两个键重叠按住后断开|各一个 cancel，无伪造 up；丢 up 用取消；重复取消幂等|`tests/SiriRemoteButtonsTests.swift:26–30`|
|I1e-05|up 恰好一秒才到|先补阈值，再 up；非法值与倒流不变状态；事件顺序可消耗 release；非法事件无输出|`tests/SiriRemoteButtonsTests.swift:31–35`|

## 重复执行

`bash tests/run-siri-remote-buttons-tests.sh`；可从任意cwd调用完整路径。脚本通过自身路径定位根。FAIL会退出1，编译错误保留非零退出码。当前完整Linux结果见VALIDATION。
