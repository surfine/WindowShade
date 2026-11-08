# 第1份验证记录

实测环境：Swift6.2.1，x86_64-unknown-linux-gnu，Linux6.18.44/glibc2.41。机器与工具原始输出在 `validation/summary.json`。主模型提供的Swift6.4/macOS27是另一台机器，不混用。

## 纯逻辑

|包|独立场景|断言|退出码|原始输出|
|---|---:|---:|---:|---|
|T1|12|32|0|`packages/T1/VALIDATION.txt`|
|L1|14|37|0|`packages/L1/VALIDATION.txt`|
|A1|11|28|0|`packages/A1/VALIDATION.txt`|
|D1|32|87|0|`packages/D1/VALIDATION.txt`|
|D2|8|35|0|`packages/D2/VALIDATION.txt`|
|I1a|6|15|0|`packages/I1a/VALIDATION.txt`|
|I1b|5|8|0|`packages/I1b/VALIDATION.txt`|
|I1c|7|14|0|`packages/I1c/VALIDATION.txt`|
|I1d|7|21|0|`packages/I1d/VALIDATION.txt`|
|I1e|5|26|0|`packages/I1e/VALIDATION.txt`|
|I1f|6|15|0|`packages/I1f/VALIDATION.txt`|
|I9|8|16|0|`packages/I9/VALIDATION.txt`|
|合计|121|334|全部0|不计重复运行|

contracts另有9个场景、24个断言；SecureLogFile另有8个场景、19个断言。合在一起为**138个独立场景、377个断言**。这里只给出本次自己写的测试计数；原有回归、优化重复、暂存重复和词法检查不混入此数字。

所有纯核脚本使用Swift6语言模式、strict-concurrency=complete、warnings-as-errors。12份核心与Contracts及用户ConductorGesture还放在同一swiftc typecheck调用中通过，检查同名/依赖和并发标注。D1额外用 `-O -whole-module-optimization` 编译并重复全部32场景87断言；这不是额外32个新场景。

## 既有回归与安装形状

本轮重新编译并运行上传的ConductorGestureTests和NotchActivityTests，源文件和测试未改。输出分别含 `all conductor gesture tests passed`、`PASS notch activity store`。这些不是引用第一轮的旧通过记录。其断言计数风格不同，本报告不强加统一数字。

`tools/stage.py`实际向新目录写入39个文件，并拒绝覆盖输入repo。暂存后的T1、D1、I1f脚本实际运行通过，确认单包脚本能从repo形状找到共享依赖；不是声称暂存后12套都重跑。另9套已经在交付包布局中通过。

## 日志、清单和辅助工具

日志补丁的12个原文锚点及全部源文件SHA256核验通过；工具实际生成7份新文件。7份分别用 `swiftc -frontend -parse` 通过语法解析。**这个操作不加载macOS SDK，也不做AppKit类型检查。**完整SecureLogFile的Glibc分支另经编译与文件行为测试；Darwin分支没编译。

登记表最终为33类信号、453个保守词法命中。基线核对退出0。负例临时加入未登记URLSession读取，检查器退出1并输出UNREGISTERED，符合期望；这是成功捕获负例，不是假装测试全都退出0。该扫描不是完整数据流、二进制或网络审计。

Schema检查固定304份JSON与30个字段/消息指针，检查器的原始输出在validation/pinned-schema.txt。它不连接CLI，不叫端到端协议测试。

本轮没有动原repo；输入完整性检查在validation/input-integrity.json。文件数量与哈希门禁只能证明处理范围，不能证明应用语义正确。

## 执行过程说明

聚合脚本首次运行时，工具的单次调用时限在12个包及Contracts完成后终止了进程。已完成的每份stdout与退出码保留；随后独立跑完日志测试、组合类型检查与D1优化构建/运行，并据实合并summary.json。没有把被工具中止的聚合调用写成一次完整成功。用户本机可按tests/run-all.sh自行完整重跑，或运行各包命令。

`validation/development/`保留调试阶段输出，包括发现并修正的失败；不计为最终结果，也不删除来制造“从未失败”。这份交付的最终源码与各包最终VALIDATION对应；辅助工具修改未改变已跑过的纯核。

## 未执行

没有Mac App构建、macOS14或27运行、Darwin ACL/第二账户、Face/Touch ID、真实锁屏/解锁、BLE特征/身份、多触点ABI、遥控器坐标/音频、DualSense反馈、助手wire/权限、跨设备认证、网络去向或能耗实测。没有影片源文件/出片/抽帧验收。第1份没有真机探针程序，不用纯核合成事件代替这些证据。

合同待主模型审定，未部署。默认关闭、Foundation通过以及UI尚未接入，都不自动证明整App不会回归。
