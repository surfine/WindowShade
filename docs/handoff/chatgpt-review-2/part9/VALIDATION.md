# 第九份实际验证记录

实际环境：Linux x86_64、Swift 6.2.1、GCC 14.2.0。原始版本在 build-commands.json。Mac 工作区连接尝试失败；端点凭据没有写入交付。当前没有 macOS SDK、真实 AX/WindowServer、手柄、真实 CLI 账号、配对或生物数据测试。

## 新增 Swift：57 场景，108 断言

|套件|场景|断言|实际覆盖与限制|
|---|---:|---:|---|
|regression|42|93|真实 FoldVerifier、stamp、CFBoolean 判断、实际 FoldCompletion 文件加明确字段/上下文策略测试宿主；无 AppKit/AX|
|frame|15|15|真实 EffectFrameAwaiter，MainActor/独立 actor/非隔离上下文，取消/取值后失效/有限时钟与期限；无 SCK|
|合计|57|108|不含旧用例、工具测试、源码检查或原缺陷复现|

每例 ID 见 tests/TEST-CASES.md 与 validation/regression-results.json、frame-results.json。实际 swiftc argv、退出码、stdout/stderr 在各自 commands.json。全部使用 Swift 6、strict-concurrency=complete、warnings-as-errors。没有为通过而添加 unchecked Sendable 或降低语言模式。

FoldCompletion 的测试直接编译生产文件，宿主提供其实际字段形状及独立可控的当前上下文检查；它不加载真正 AppDelegate/AuthorizationService/NSView。AXBool 的 CoreFoundation 类型测试使用真实 CFBoolean/数字/字符串，但不是应用的真实 AX 返回值。

## 旧基线缺陷实际复现

reproduce-v8.py 读取精确原 FoldCompletion，唯一源码改动是 Cocoa import 换 Foundation，配合字段宿主。两个旧行为均复现：旧请求的 windowID 批量成功同时确认新请求；同批客户回调重入可以先取消尚未提取的另一回调。记录在 baseline-reproduction.json。这两项不算修复测试，也不是实机复现。

## 原用例在新候选上的回归

|旧套件|本次实际结果|
|---|---|
|part8 input / fold / flow|33/49、21/49、6/27，通过|
|part7 core / native / flow|27/51、3/14、18/145，通过|
|part6 core / Wire|42/95、5/11，通过|
|part5 core|40/97，通过|
|part4 core|72/188，通过|
|part2 core|22/86，通过|
|原 T1 番茄钟|12/32，通过|
|part6 / part5 Process|9/27、8/26，通过|
|原 ConductorGestureTests|原程序报告全部通过，未发明新统一计数|
|原 DuoCoreTests.swift|源码未改，严格 Swift 6 编译及原程序通过；无新统一计数|

数字为场景/断言，不加到新57/108。flow/native/Process 运行了真实本地子进程与管道，其中助手回复与设备桥是测试替身，没有网络模型或用户账号。记录在 validation/regressions 各目录。

原 PROC04 本轮 OBSERVED_PASS，elapsedSeconds=0.02203822499996022，未收到 fixture 中 0.8 秒后的迟到行。它只证明当前 Linux 固定情形符合原小于0.7秒判据，不是22ms承诺，不证明Mac、宿主崩溃或逃逸进程树清理。没有改原 fixture。

## 类型、语法、静态检查

40 份 Foundation 候选同一次严格 Swift 6 typecheck 通过，完整输入列表在 build-boundary.json。条件编译排除的 CryptoKit 等分支不在此证据内。12 份变更 Swift 逐一 frontend parse 通过；parse 不加载 Cocoa、ApplicationServices、GameController、Metal、Sparkle 或私有 SDK，不等于 Mac 类型检查。

check-wiring.py 的24项是文本级接线防回归，不证明线程、SDK或真实窗口行为。候选 duo-integration-check.py 更新了新增 transaction 参数对应字面检查，并增加 native waiter 绑定断言，其余旧检查保留并通过；原 Swift DuoCoreTests 未改。不能把更新后的 Python 文本检查说成“旧静态源码完全未动”。

run-mac-check.sh 本轮 Linux 退出78，stdout明确 NOT RUN，记录 mac-not-run.json。没有整App Mac优化编译、Metal/链接、原生窗口或观察者运行结果。

## 文件工具与输入完整性

18 项文件工具用例通过，是从上一份沿用的暂存保护回归，不是18项新产品测试。真实 stage 实际核对1164文件基线、修改11新增4，生成1168文件候选；逐文件SHA与统一v9一致。已有输出的真实重复尝试按预期退出2，未覆盖候选。证据在 stage.json、stage-existing-output-refused.json、input-and-stage-integrity.json。

原v8上传ZIP共2163个文件，全部与提取基线逐字节比较一致。统一包中的part1至part8与原对应历史文件完全一致。这里只证明输入未改及组合正确，不证明应用语义。最终压缩和逐条manifest校验由tools/verify-package.py提供可重复检查；发布文件的外部压缩核对记录另存于本次校验报告。

## 开发阶段真实失败

development 保留完成通知weak self optional.map的Swift6隔离错误，修为显式绑定后重跑；原EffectFrameAwaiter在严格DuoCore测试中的跨隔离报错，修为继承调用者隔离；旧Python字面检查对新transaction签名报错，改成更明确的检查；新frame测试最初把非Sendable frame作为Task结果跨域返回，随后改为域内检查并仅返回Bool。

这些不是额外成功测试，也没有声称开发中从未失败。最终 regression、frame、duo、组合类型和语法检查均在最终相关源码上重新运行。

## 尚未执行与实际边界

没有 AX 读回、私有隐藏方法、真实 observer 注册/销毁、真实锁屏/Space/多屏、人工恢复、SCK capture graph、AppKit焦点、能耗或签名发布。慢AX仍可能阻塞下一巡检轮；2秒freshness拒绝陈旧结果而不取消IPC。移除嵌套RunLoop可能改变慢应用走proxy的比例。stamp和瞬时Event均不是T3恢复授权，相关真实端口仍缺。
