# 第四份验证记录

环境为 Linux x86_64、Swift 6.2.1；Python 测试依赖实际版本见 requirements-tests.txt 和 validation/python-packages.json。本轮没有 macOS SDK、真实外设或成功的 Mac 工作区连接。上传的 Mac 头文件记录属于别的机器。

## 本次实际通过

|工作|结果|原始文件|能证明什么|
|---|---|---|---|
|新纯Swift测试|72个场景，188个断言，0失败|core-tests.txt / core-results.json|本轮Focus、framing、nonce、review、wire、input gate、ownership在所列合成输入下的行为|
|原T1回归，使用第四份FocusTimer|12场景，32断言，通过|t1-regression-compile.json / t1-regression-run.json|旧计时核心行为未被这些用例破坏|
|第二份回归，替换为第四份Wire和InteractionCoordinator|22场景，86断言，通过|part2-regression-compile.json / part2-regression-run.json|这些旧租约/协议边界仍符合对应断言|
|FocusTimerHost组合类型检查|退出0|focus-host-typecheck.json|Foundation宿主与新模型/合同类型关系成立，不包含FocusTimerCard|
|Python加密参考|18个测试，0失败/错误|crypto-reference.txt / crypto-reference.json|独立参考计算和篡改/方向/nonce等合成负例|
|实际编码的一次性accept响应body|1条通过固定JSON schema|approval-schema.json / schema-recheck.json|响应body符合上传的0.153.0 schema，不证明授权或CLI时序|
|源码语法解析|28份输入全部退出0|syntax-only.json|27份overlay Swift和1份Mac测试的语法；不加载SDK、不做AppKit类型检查|
|暂存|输入1119文件；本份修改19、新增9；输出1128|stage.json|精确基线和overlay可组合成一个候选，不代表可构建|
|拒绝覆盖已有输出|按预期退出2|stage-reject-existing.json|暂存工具不会覆盖前一个目标目录|
|拒绝错误基线|按预期退出2，未创建输出|stage-reject-wrong-base.json|不把旧补丁强行覆盖到不匹配的源码|
|输入完整性|原包repo1079文件与zip逐字节相同；第三份候选1119文件未改|original-input-integrity.json / base-integrity.json|原始输入未被本轮编辑|

没有把回归的34个场景重复称为“本次新增”，没有把Python与Swift计数混为一套密码学测试，也没有把前几份历史通过总数加上来。FRM拆包循环按一个场景计，循环里的实际check计入断言。

## 命令

在本包根目录可重复：

```sh
bash tests/run-core.sh
python3 tests/crypto-reference.py
python3 tests/check-approval-schema.py
python3 tools/stage.py --base /第三份/candidate-repo --out /不存在的新目录
```

回归/组合类型检查的完整命令保存在各自json，不需要猜依赖顺序。原回归测试来自同一已上传handoff；本包没有伪造新的测试数量来替代它们。

语法解析命令是 `swiftc -frontend -parse <file>`。**它与 `swiftc -typecheck` 不是一回事。** 本份并未完整编译 WS2CodexApprovalHost、WS2GameControllerBridge、NotchAuthentication、各原生卡片或CryptoKit支持类。

`bash tests/run-mac-crypto.sh` 在本轮Linux执行后明确退出78，输出requires macOS CryptoKit。记录在 mac-crypto-not-run.json，表示没有执行这组密码学测试；不是测试失败后把它算作通过，也不是已完成Mac验证。Python固定向量中的私钥均为人工合成测试字节，测试文件明确禁止用于用户身份。

## 限制与开发过程

最初新核心测试编译时有一处测试fixture的嵌套括号错误，已改为具名中间WireJSON值并重新完整编译/运行。后续发现换输入域需要取消旧held状态，补了DEV-08/09；新增APR-23检查上下文双向控制字符转义，最终计数72/188。没有声称开发过程从未失败。

本份有实际CryptoKit源码，但Python参考通过不能证明Swift实现正确。MacCryptoTests验证的是合成client/server和固定向量，未来即使通过，也不能证明原生Remote互操作。它不测试首次PIN配对/Keychain/网络、真实人的身份或具体设备。

没有真实CLI进程、原生TouchID、完整writer、系统锁/解锁、GameController/HID/多触点、BLE、摄像头/麦克风或能耗测试。没有更改用户home、发起配对、收集生物数据、发布版本或发送远端命令。代码是否最终可发行仍按 REMAINING 和各施工单验收。
