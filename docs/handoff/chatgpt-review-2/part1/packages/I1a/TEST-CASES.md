# I1a 输入与预期结果

测试时钟由sec()注入。fixture值全部是测试专用合成ID/摘要/文字，不会请求真实助手或操作系统。下表行范围包含完整输入序列；同一用例内每个expect都是必须保留的行为约束。

|用例|输入情景|预期状态与效果|可执行输入位置|
|---|---|---|---|
|I1a-01|三个档位各一格，持续到收敛|总量等于每格点数，闲时零输出；各档总量保留；停机后不继续排帧|`tests/SmoothScrollTests.swift:8–14`|
|I1a-02|同向连加三格|目标累加、速度不断、不越过目标；同刻加格保留速度；同向不回弹|`tests/SmoothScrollTests.swift:15–21`|
|I1a-03|运动中反向|本次不再发旧方向量，下一帧立即反向；反向输入不能先补旧方向；后续立即反向；显式取消也守恒|`tests/SmoothScrollTests.swift:22–27`|
|I1a-04|同一轨迹采用均匀帧与掉帧|解析解位置一致；掉帧不丢总量|`tests/SmoothScrollTests.swift:28–33`|
|I1a-05|NaN/无穷/超量/倒流|拒绝且不改已有位置；非法数值拒绝；无效输入原状态保留|`tests/SmoothScrollTests.swift:34–37`|
|I1a-06|固定种子 1000 次混合正反滚动和掉帧|每步守恒、有限、不越界；1000 次轨迹性质检查|`tests/SmoothScrollTests.swift:38–48`|

## 重复执行

`bash tests/run-smooth-scroll-tests.sh`；可从任意cwd调用完整路径。脚本通过自身路径定位根。FAIL会退出1，编译错误保留非零退出码。当前完整Linux结果见VALIDATION。
