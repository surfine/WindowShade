# 来源、固定版本和可推出的范围

检索日期为 2026-10-03。网络上可变页面只用于本次核查；运行协议优先使用上传的固定 schema。原仓库和源码的精确行号见 `FILE-MAP.md`，字节见 manifest。以下缩写在各决定表中复用。

## U1：用户上传的委托及工程事实

`WindowShade2-review-round2.zip` 的先读我、repo/docs/pomodoro.md、repo/docs/handoff/reference/mac-facts-2026-10-03.md，以及上一份 candidate-repo 和 MAC-ACCEPTANCE.md。它们确定“不开发手机/手表 App”“新代码 Swift”“复用授权账和刘海”“T3 主模型负责”等产品边界。上传的 Mac SDK 摘录属于用户机器证据，不能写成这一轮自己运行结果。

## S1：固定 Codex app-server 0.153.0 schema

候选目录 `docs/handoff/reference/codex-app-server-schema-0.153.0/`。本次实读 CommandExecutionRequestApprovalParams/Response、FileChangeRequestApprovalParams/Response 和现有 CodexWire。响应 schema 副本在 reference/，SHA256 在 validation/approval-schema.json。

可证明字段、必填项和可编码枚举；不能证明实际 CLI 版本、时序、用户许可或 native UI 的存在。网页文档的新版字段不能悄悄替换固定目录。

## S2：公开 Swift 协议实现，仅取协议观察

仓库 https://github.com/nickustinov/itsytv-core ，固定提交 `052d9a9a0416d577119316ea813aa3b822b408e5`。

本次通过 GitHub connector 读取：

|相对路径|本次用途|
|---|---|
|Package.swift|确认包的客户端定位和依赖；没有把这个包加入我们的工程|
|Sources/ItsytvCore/Protocol/CompanionFrame.swift|4 字节帧头、字节序、类型值|
|Sources/ItsytvCore/Crypto/CompanionCrypto.swift|main channel 的方向密钥、nonce 和 AAD 布局|
|Sources/ItsytvCore/Crypto/CryptoHelpers.swift|SHA512 HKDF、短标签 proof nonce|
|Sources/ItsytvCore/Crypto/PairVerify.swift|客户端验证服务端的签名材料与密钥域分离|
|Sources/ItsytvCore/Crypto/PairSetup.swift|SRP 参数和 proof 编码差异；发现不能原样依赖其 M6 验证逻辑|

固定 blob 查看地址为 `https://github.com/nickustinov/itsytv-core/blob/052d9a9a0416d577119316ea813aa3b822b408e5/` 加上述路径。**这些是第三方公开实现，不是 Apple 的协议规范或兼容承诺。** 我们的服务端方向属于据此构造的候选实现，尚未用原生 Remote 验证。未审定该仓库全部许可证；交付包不含该库源码、不 vendor、不通过重命名冒充原创。本轮 Swift 文件为独立实现。

## S3：AEAD 安全条件

RFC 8439，尤其 §2.8 和 §4：https://www.rfc-editor.org/rfc/rfc8439.html 。用于 nonce 不可重复、AAD 与认证失败的解释；不用于证明 Companion 的私有 wire 格式。数据方向、拼接顺序来自 S2，算法执行来自 CryptoKit / Python cryptography。

## S4：OpenAI 官方 app-server 说明

https://developers.openai.com/codex/app-server/ （本次跳转 https://learn.chatgpt.com/docs/app-server）。用于独立宿主需要负责初始化、线程/轮次和审批的背景。具体测试仍使用 S1，不声称采用了网页当前所有功能或更新 CLI。

## S5：Anthropic 官方 hooks 说明

https://code.claude.com/docs/en/hooks ，本次重点读取 PermissionRequest input/decision control 和 PreToolUse decision control。两者字段不通用；PermissionRequest 当前文档不提供 tool_use_id。本文只给出必要区分和新调用者需求，不把文档样例当实际 hook 已安装证据。

## S6：Apple 公开 GameController 接口

https://developer.apple.com/documentation/gamecontroller/gccontroller/shouldmonitorbackgroundevents

https://developer.apple.com/documentation/gamecontroller/gcdualsensegamepad/lefttrigger

https://developer.apple.com/documentation/gamecontroller/gcdualsensegamepad/righttrigger

https://developer.apple.com/documentation/gamecontroller/gcdualsenseadaptivetrigger

结合 U1 中实际 SDK 头文件确认 setModeOff、setModeFeedback 等名字；没有使用不存在的 adaptiveTriggers 属性。SDK 声明可用不等于蓝牙/USB 模式下的实际手柄反馈已经通过。

## E1：本轮自己的证据

`validation/` 原始命令/输出、`fixtures/companion-crypto-vectors.json` 合成向量、测试源码、manifest 与 patch。标记了 Linux、Python 和语法检查边界。一次通过只证明相应输入下的行为，不证明完整安全性、系统功耗或互操作性。所有门限中未注明规范/旧合同的数值均为本轮设计决定。
