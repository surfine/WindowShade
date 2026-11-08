# 第五份实际验证记录

环境：Linux x86_64、Swift 6.2.1；Python/cryptography 的实际版本见 `validation/environment.json`。没有 macOS SDK、真实外设、原生 Remote 或真实 Codex/Claude。所有最终编译与运行记录在 validation；开发阶段错误原样留在 validation/development。

## 本次新增测试

|测试|实际结果|证据|边界|
|---|---|---|---|
|Swift 状态/存储/配对编排/窗口计划/输入票据|40 场景、97 断言，0 失败|core-final.txt、core-results.json|MemoryStore 与 FakePairCrypto；无 Keychain/SRP/AX|
|真实 owned 子进程管道|8 场景、26 断言，0 失败|process-final.txt、process-results.json|真实 Python 子进程与管道；未运行助手|
|Python 加密参考|14 个 unittest，0 失败|crypto-final.txt、crypto-reference.json|部分 RFC 中间量与候选编码/AEAD/签名；不是 Swift SRP|

本次新增 Swift 合计 **48 场景、123 断言**。Python 的 14 项独立列出，不混成“137 项加密测试”。管道包括 IO08 的每批次上下文失效复核，并保留了之前 7 场景版本的开发输出；旧输出不是另一次新增成果。

最终可重复入口：
```sh
bash tests/run-core.sh /第四份或第五份/candidate-repo
bash tests/run-process.sh
python3 tests/crypto-reference.py
bash tests/check-foundation.sh /第五份/candidate-repo
bash tests/run-regressions.sh /第五份/candidate-repo /统一交接包
```

## 组合与旧回归

新 Foundation 文件和基线相关共享模型同一次 `swiftc -typecheck`，使用 Swift 6、strict-concurrency=complete、warnings-as-errors，退出 0。完整输入清单见 `validation/commands.json`，输出为 combined-foundation-typecheck.txt。CryptoKit 的条件分支没有在 Linux 被加载。

用**第五份暂存候选**中的 Core 文件重编译第四份测试：72 场景、188 断言通过；原 T1 测试：12 场景、32 断言通过；原 ConductorGestureTests 通过。测试二进制放临时目录，没有向旧输入写 .build。记录为 part4-regression-*、t1-regression-*、gesture-regression-*。这些是重跑的旧用例，不计入本次 48/123。便于重复执行的 check-foundation.sh 与 run-regressions.sh 也实际运行退出 0，输出另存 foundation-script-final.txt / regressions-script-final.txt；再次执行没有增加场景数。未重跑前四份所有测试。

## Mac 源码与外部依赖

14 份 overlay Swift、1 份 Mac 测试和 1 份隔离 SRP adapter，共 **16 份**逐一 `swiftc -frontend -parse` 退出 0，见 syntax-only.json。此操作只做语法解析，不加载 Cocoa/GameController/Network/Security/CryptoKit SDK，不证明整个 App 类型检查成功。

`bash tests/run-mac-crypto.sh` 在本机 Linux 实际返回 **78**，明确 NOT RUN；输出 mac-crypto-not-run.txt。没有把它计为 Mac 测试通过。

隔离 SRP probe 目录实际生成，`swift package dump-package` 成功解析 manifest；保存生成 Package.swift、输入哈希和 dump 输出。**没有实际 resolve、没有 Package.resolved、没有 swift build、没有运行 Swift SRP adapter**。容器此前网络解析失败，未以编造的 lockfile 代替。官方源码通过 Web/GitHub 阅读与本地依赖构建是不同事情。

## 暂存与输入完整性

`tools/stage.py` 校验第四份 **1128 文件**，只向新目录写出第五份 **1140 文件**。本次替换 2 个既有文件，增加 12 个 Swift 文件；另有隔离 adapter 不进入候选。记录见 stage.json 和 manifest.json。

已有输出、错误基线、试图把输出写进基线三个负例，均按预期退出 2；没有覆盖旧目录，也未创建不合格输出。source-map-check 校验 44 份实际源码的记录哈希通过。暂存后所有基线 1128 文件再次校验不变；最初上传 repo 的 1079 个文件逐项与原 ZIP 比较，字节相同，见 base-integrity.json / original-input-integrity.json。

上述数量是源码和处理范围，不是功能或审美评分。候选中含前几份尚未 Mac 编译的源码，不能因为本次 stage 成功就发布。

## 开发过程与未完成

开发阶段修复了 Swift 测试闭包隔离、PairingAttemptWindow 实际接口不一致、配对截止复核和 Wire 换行接缝；原始报错在 development。最终报告不声称开发过程中从无失败。

没有真实 Keychain、完整 Swift PAKE、原生配对、监听服务、实际 CLI 授权、Touch ID、HID/事件 tap、GameController、真实隐藏恢复、能耗、签名或发布结果。剩余的生产调用者见 REMAINING.md；它们仍需写代码，不能全改为“真机待测”。
