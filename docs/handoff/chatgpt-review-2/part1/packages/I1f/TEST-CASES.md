# I1f 输入与预期结果

测试时钟由sec()注入。fixture值全部是测试专用合成ID/摘要/文字，不会请求真实助手或操作系统。下表行范围包含完整输入序列；同一用例内每个expect都是必须保留的行为约束。

|用例|输入情景|预期状态与效果|可执行输入位置|
|---|---|---|---|
|I1f-01|默认关闭|所有输入不产生系统动作；默认关闭|`tests/RemoteModeTests.swift:8–11`|
|I1f-02|短按电视、中心、音量、电源|固定动作；电源只请求显示器睡眠；等待松手；电视短按启动台；中心是独立确认；不请求睡眠整机|`tests/RemoteModeTests.swift:12–16`|
|I1f-03|电视半秒长按再 up|只开刘海，不再启动台；半秒刘海；长按尾部消耗|`tests/RemoteModeTests.swift:17–20`|
|I1f-04|播放长按切模式，同时另一键按住|两个旧 up 都不能进入新模式；切入指挥；不把旧 release 当提交|`tests/RemoteModeTests.swift:21–25`|
|I1f-05|指挥模式新的完整按压|原样转交，长按切回的尾端不放行；原样交 D1；切回遥控；不能播放媒体|`tests/RemoteModeTests.swift:26–31`|
|I1f-06|关闭、重复、取消|清输入且不补短按；取消无动作；取消后的 up 忽略；关闭撤销 D1 输入|`tests/RemoteModeTests.swift:32–37`|

## 重复执行

`bash tests/run-remote-mode-tests.sh`；可从任意cwd调用完整路径。脚本通过自身路径定位根。FAIL会退出1，编译错误保留非零退出码。当前完整Linux结果见VALIDATION。
