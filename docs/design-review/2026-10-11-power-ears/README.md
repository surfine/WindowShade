修复了电量右耳的截断：82%原来显示成“8…”，100%显示成“1…”。253×33.5的紧凑形状和34点耳宽不变，电量百分比使用独立10点圆体等宽数字、2点内距，按真实字宽完整绘制；通用右耳、个数、进度与其它字号不变。

![修前100%被省略](before-diagnostic/light-plug-hundred.png)

![修后100%完整显示](after/light-plug-hundred.png)

生产原生测量确认，旧绘制给文字留22点，而同一字体的82%宽26.92、100%宽35.04，不能完整放下。修后的实际生产布局函数在0到100的101个有效值上都放得下，100%的10点字宽约29.2，绘制区30点；不删百分号、不扩大刘海、不用“1…”代替电量。

新样件使用合成 BatteryReading 经过实际 Core PowerFlashPolicy 生成 payload，再通过 setCompact 进入实际 NotchPanel／NotchCompactView：0、5、20、21、82、100%的插电，充满和低电量模式，共16帧，8对浅深父外观 PNG 一致。独立消费者读取实际紧凑 payload、private slots 的反射值和生产字体布局函数，核对颜色类别、符号、完整数值、形状与字宽。主模型看过100%、充满、黄色82%与红色20%的实际图。

![充满，满格电池与100%](after/light-full.png)

![低电量模式，黄色82%](after/light-low-power.png)

这里只验证紧凑生产绘制与纯政策结果。没有调用 DeviceBatteryController.start、真实 IOKit 电池来源或 presentPowerFlash；后者会发系统AX播报，因此样件使用 setCompact，未验真实播报、2.6秒定时收回、优先级和硬件事件。自造窗口透明、离屏、不激活，无用户窗口或持久设置变更，不把静态图说成完整电量功能通过。

首次before的插电payload与当前Core一致，是有效截断证据；其中充满／低电量模式的符号是QA误用的别名，那两张不作生产基线。修后全部payload由实际Core生成。首次after入口把不可变 charging 当成可变字段，编译失败；原入口与SHA、日志保留，改为构造参数后终局0，没有为此修改Core字段。

DeepSeek执行既有纯 `run-power-flash-tests.sh` 的桥接revision0退出0，覆盖首次读数／unknown／busy／防抖／IsCharged／低电量模式与设备提醒文案。工人达到上下文上限，is_error/incomplete为true，没有报告或源码改动；主模型核对真实回执及6项当前输入，接手报告，没有重跑套件。它只验证纯逻辑，不替代原生画面。

当前完整优化 `prototype/build.sh --check` 于UTC 2026-10-11T10:09:05.631428 退出0，519项构建来源与518项原生来源均匹配当前文件；Swift6／strict-concurrency／warnings-as-errors参数、本地化、隐私及文案门禁保留。原有警告仍在，签名App执行期未验。整个七线设计目标仍active，设置／窗口及共同刘海其它状态继续推进。
