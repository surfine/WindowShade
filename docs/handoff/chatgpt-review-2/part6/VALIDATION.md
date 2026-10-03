# 第六份实际验证记录

本轮环境为 Linux x86_64、Swift 6.2.1。完整版本在 `validation/environment.json`。没有 macOS SDK、真实 Codex/Claude、Touch ID、Keychain、GameController、原生 Remote 或实际 AX 窗口操作。用户以前提供的 Mac 记录不属于本轮运行。

## 本次新增 Swift

|测试|独立场景|断言|实际结果|原始证据|
|---|---:|---:|---|---|
|仲裁、Scope、目录身份、选择、连接预算、诊断尾部|42|95|通过|core.txt / core-results.json|
|真实 Python 子进程及非阻塞管道|9|27|通过|process.txt / process-results.json|
|固定 Codex 权限与模型分页请求|5|11|通过|wire.txt / wire-results.json|
|合计|56|133|上述用例通过|tests/TEST-CASES.md|

使用 Swift 6、strict-concurrency=complete、warnings-as-errors。目录测试使用真实临时目录和符号链接；进程测试使用真实本地 Python 子进程，但不是实际助手。其他状态以注入事件测试，不代表系统设备已经运行。完整可重复命令及实际退出码在 `validation/commands-final.json`。

## 独立且真实的未通过要求

`tests/run-exit-probe.sh` 的 PROC04 **返回 2，BLOCKED**。父进程先退出，子孙进程持有描述符并在 0.8 秒后写入，当前通道仍接收了这行迟到输出；本轮记录约 0.815 秒。详见 `exit-inheritance-probe.json`，不要把该现象改名为已处理的 EOF。

这说明当前环境下不能依赖 Foundation 通知在直接子进程退出时即时送达，200ms 收尾只从通知实际送达后计时。子孙进程会自行结束，探针另等待清理。没有实现进程树强杀、唯一 reaper 或可靠跨平台监督 helper。该未通过要求不会因为上表 56 项通过而消失；commands-final 中 expectedExitCode=2 只是记录已知现象，不代表功能通过。

## 其他实际检查

|检查|结果|边界/记录|
|---|---|---|
|25 份 Foundation 候选源码同一次类型检查|退出 0|foundation-typecheck.txt；不包含 Cocoa Island，不加载 Linux 上不活动的 CryptoKit 分支|
|实际编码的 4 条 params 对固定 0.153.0 schema|通过|wire-schema.json；只证明 JSON 结构，不证明实际权限执行和协议时序|
|9 份 overlay Swift 语法解析|全部退出 0|syntax-only.json；`swiftc -frontend -parse` 不是 SDK 类型检查|
|8 份 shell 脚本 bash -n|全部退出 0|bash-syntax.json；不是脚本在 Mac 成功执行|
|readiness 检查器的 18 个 Python 单元测试|通过|readiness-tests.txt；全是工具用合成记录，不是功能验收|
|当前真实能力证据清单|BLOCKED，退出 2|readiness-current.json；源码和实机证据仍缺，不是发布认证|
|Mac 隔离构建入口|NOT RUN，退出 78|mac-check-not-run.txt；明确平台守卫|
|36 份实际源码地图|哈希、行数、符号行检查通过|source-map-check.json|

Python `jsonschema` 的实际版本记录在 environment.json。本轮没有安装 SRP 依赖或做新密码学互测，没有把前五份 Python/SRP 结果当成当前 Swift 实现通过。

## 旧回归是重新运行，但不是新增场景

用第六份候选源码重编译并运行第五份纯逻辑 **40 场景/97 断言**、第五份进程 **8/26**、第二份 **22/86**、第四份 **72/188**、原 T1 **12/32**，以及原 ConductorGestureTests。运行成功输出在 `validation/regressions.txt`；第五份两组另有 regression-part5-*.json。没有重跑前五份的所有测试，也没有将这些旧数加入 56/133。

## 暂存与输入完整性

最终 manifest 对第五份 1140 个文件逐项验证，再修改五个文件、新增五个文件，形成 1145 文件候选。`stage-command.json` 保存最后一次实际暂存命令；`stage.json` 含每项来源与哈希。最终暂存输出逐字节等于本轮测试使用的候选。

已有输出、错误基线和输出位于基线内部三个用例均按预期退出 2；没有覆盖原目标或创建拒绝的输出，见 `stage-negatives.json`。第五份候选的 1140 文件与实际上传 v5 ZIP 内对应文件逐项比较一致，原始上传 ZIP 和 v5 ZIP 的当前 SHA256、CRC 检查记录在 `input-integrity.json`。这些是文件处理证据，不是整应用验收。

## 开发过程与边界

`validation/development/` 保留初始编译报错、修正过程及把继承描述符场景混入主进程测试时的失败输出。该场景已提取为独立探针，而不是删除或放宽阈值。最终源码以 manifest 为准，最终结果以本文件及对应日志为准。

没有新影片、声音、能耗测量、签名或发布；没有向 GitHub 写入，也没有改用户真实 home。仍需编写的生产调用者详见 REMAINING.md。默认关闭不证明整 App 可构建；源码地图、schema 和证据检查器通过不证明身份、权限、窗口效果或用户体验正确。
