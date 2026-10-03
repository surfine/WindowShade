# 第八份实际验证记录

环境为Linux x86_64、Swift6.2.1、GCC14.2.0；原始版本在validation/build-checks.json。Mac工作区本轮实际连接失败，端点凭据没有保留到交付包。没有macOS SDK、真实GameController、AX窗口、真实CLI账号或模型服务。

## 本次新增Swift

|套件|场景|断言|实际执行范围|
|---|---:|---:|---|
|input|33|49|实际DeviceActionHost、VisibleListInput、旧Gate/Router/Selection；桥是明确的测试替身|
|fold|21|49|实际FoldEvidence；没有AX/WindowServer，合成身份与注入时钟|
|flow|6|27|实际Controller/Session/Wire/Native管道和真实Python子进程；后端与手柄为替身|
|合计|60|125|不包括旧回归、Python和静态检查|

input包含发现未启用、neutral、边缘导航、按A后改行/重选/刷新/失焦、锁态、断连重插、双设备、重复释放、错误按钮和同步撤销。flow的IFLOW02没有因选择模型产生thread/turn；IFLOW03实际发送使用所选模型且一次；IFLOW06真实重命名并重建目录，生产chooseModel拒绝旧身份。它们不证明真实模型/设备行为。

每例结果在validation/*-results.json，实际argv、编译/运行退出码、stdout/stderr在*-commands.json。Swift使用-swift-version 6、-strict-concurrency=complete、-warnings-as-errors。测试用固定模型、登录信息和私密字符串都是合成值，没有用户账号凭据。

## 原用例使用新候选重跑

|旧用例|本次结果|
|---|---|
|part7 core|27场景/51断言，通过|
|part7 flow|18/145，通过|
|part7 native|3/14，通过|
|part6 core与Wire|42/95与5/11，通过|
|part5 core|40/97，通过|
|part4 core|72/188，通过|
|part2 core|22/86，通过|
|原T1番茄钟|12/32，通过|
|part6、part5管道|9/27与8/26，通过|
|原ConductorGestureTests|原程序全部通过，不重造统一计数|

输出分别在validation/regressions/part7和legacy。这些是旧用例重跑，不计入新增60/125。没有宣称把历史每一份所有测试全跑完。

原PROC04在新候选上OBSERVED_PASS，约0.02213秒，未收到fixture中0.8秒后的迟到行。该判据容忍小于0.7秒，只证明本机固定例，不是延迟保证，也不证明Mac、宿主崩溃或脱离组进程树清理。

一次将part7 core/flow/native放在同一容器批次达到外层调用时限。core与flow已完成，整个批次明确记录INTERRUPTED；native随后独立重跑通过。batch-interruption.json保留此事实，没有把被中止的批次写成单次完整成功。

## 类型、语法和静态层级

37份Foundation候选同一次类型检查通过。16份本轮变更Swift逐一frontend parse通过，其中包括实际Mac视图、GameController桥、Fold/Notch源文件。后者只做语法，不加载Cocoa、GameController、ApplicationServices、私有SDK或Metal，不是Mac类型检查。

check-wiring的14项为明确的文本级接线防回归，不能证明SDK、线程或硬件正确。原duo-integration-check.py退出0，检查恢复intent/隐藏/动画等源码顺序，也不证明真实窗口恢复。

run-mac-check.sh本轮在Linux实际退出78，输出NOT RUN。没有整App优化构建、Metal/链接或原生界面运行结果。候选可能仍有目标SDK的签名/隔离/类型问题，下一步必须按真实编译错误修。

## 文件工具、暂存和输入完整性

18个Python工具测试通过，涵盖精确基线、哈希/文件集、目录/链接、重复清单、路径越界及已有输出拒绝；这些是文件工具测试，不是产品功能。

tools/stage.py实际把完整1157文件基线暂存到全新目录，输出1164文件，与本轮统一候选逐文件哈希相同。修改11、新增7（其中Swift新增5）。用户上传v7 ZIP里的2048个文件逐项核对，包含1157份候选；原基线和历史part1至part7未修改。记录在input-and-stage-integrity.json。哈希只证明字节，不证明程序可用。

本包overlay、base-sources、manifest和源码索引提供精确合并依据。stage不是同UID恶意文件竞争下的安全沙盒，也不是对任意更晚分支的合并器。

## 开发过程和未执行

保留development/input-initial-compile.json中测试fixture遗漏Item.enabled参数的初次编译错误及最初语法记录。修正测试后重跑。最终折叠用例增加极大时间导致deadline不推进的拒绝检查，21场景最终为49断言。最终源码语法和组合检查在该改动后重跑。

没有本轮Mac界面截图、输入法/VoiceOver实际验收、手柄共存、AX隐藏/恢复、真实允许审批、SRP/Keychain/Remote、BLE/人脸/系统锁、功耗、签名发布或新影片。T3完整恢复生产端口仍缺；新窗口Event不能作为其所有权回执。
