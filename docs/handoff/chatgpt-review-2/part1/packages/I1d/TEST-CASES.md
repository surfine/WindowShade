# I1d 输入与预期结果

测试时钟由sec()注入。fixture值全部是测试专用合成ID/摘要/文字，不会请求真实助手或操作系统。下表行范围包含完整输入序列；同一用例内每个expect都是必须保留的行为约束。

|用例|输入情景|预期状态与效果|可执行输入位置|
|---|---|---|---|
|I1d-01|三指与四指同时落下，200ms 全抬起|各仅一次轻点；三/四指完整组；空帧不重复|`tests/TouchTapTests.swift:11–16`|
|I1d-02|先三指，100ms 加第四指|不预报三指，最终四指；先落三指不触发；第四指入组；最终四指|`tests/TouchTapTests.swift:17–22`|
|I1d-03|三指移动达到 1.5mm 或掌面|整组失效；拖移/掌面拒绝；失效后不复活|`tests/TouchTapTests.swift:23–28`|
|I1d-04|两指落下一指抬起、快照静默丢点|都不算三指；部分抬手不结束整组；丢点不冒充 ended|`tests/TouchTapTests.swift:29–34`|
|I1d-05|150ms/250ms 精确边界与超时|边界接受，超出拒绝；250ms 包含边界；迟到第四指拒绝|`tests/TouchTapTests.swift:35–39`|
|I1d-06|妙控鼠标两指持续 3 秒|仍为两指按下，不套轻点时限；持续弦键；抬起解除|`tests/TouchTapTests.swift:40–43`|
|I1d-07|重复编号、超上限、序号重放、取消|不产出轻点；触点编号去重；固定容量；序号不能重用；取消后先等全空帧|`tests/TouchTapTests.swift:44–52`|

## 重复执行

`bash tests/run-touch-tap-tests.sh`；可从任意cwd调用完整路径。脚本通过自身路径定位根。FAIL会退出1，编译错误保留非零退出码。当前完整Linux结果见VALIDATION。
