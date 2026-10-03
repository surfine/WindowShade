# 来源与适用范围

核对日期：2026-10-03。项目事实仅来自上传的 v9 候选及原委托；不是公开仓库当前 HEAD。`code-map.json` 对所列实际源码记录路径、SHA256、行号与符号。外部资料用来解释语言/协议概念，不证明此应用编译或真实设备可用。

## C01　原蓝图
`candidate-repo/docs/blueprint.md`，完整副本在 `original-briefs/blueprint.md`。原七条线、长按 CarPlay、电量全家、单宿主、授权账、能耗和发布边界依据此文件。历史中的时间与设备信息是上传记录，不是本轮运行环境。

## C02　前九份的事实
统一包 `part9/REMAINING.md`、`VALIDATION.md`、`COMPLETION-CONTRACT.md`，以及原 `part7/part8` 已存在的调用链。旧测试数量只作历史，不能自动加成本轮数量。

## C03　实际恢复解析与存储
`prototype/Recovery/Journal.swift` 的 `journalNumber`、`journalID`、`shadeJournalEntries`、`saveShadeJournalEntries`、`recordShadeJournal`、`recordShadeRecoveryIntent`、`journalMatches`。本轮直接检查源码；新的原函数提取测试仅验证编号解析，不证明所有 journal 字段和系统恢复。

## C04　实际 durable 层
`prototype/Recovery/DurableShadeJournal.swift`。它与 UserDefaults 备份一起构成当前持久化路径。不能把文件的 atomic write 与权限设置推导为对同 UID 恶意代码、父目录竞争或任意掉电的完整保证。

## S01　Swift 官方迁移指南
https://github.com/swiftlang/swift-migration-guide/blob/949b5e1be201af4346f60b243e7955bd5849f3f6/Guide.docc/EnableDataRaceSafety.md

通过 GitHub 连接读到该固定版本完整正文。直接 swift/swiftc 的 Swift 6 语言模式由 `-swift-version 6` 指定；Swift 5 模式下的严格并发告警与语言模式须区分。本文只用这一事实解释构建补丁，不复制其完整指南或示例。

## S02　OpenAI 官方 App Server
https://developers.openai.com/codex/app-server/
实际转向 https://learn.chatgpt.com/docs/app-server 。读取日期为核对日。文档给出由具体二进制生成 JSON schema 的方法；当前网页不是上传 0.153.0 的替代品。运行协议仍以随包实际 snapshot 及真实同版本 CLI 核对。

## S03　RFC 6762 §21
https://www.rfc-editor.org/rfc/rfc6762.html

已读 HTML 安全讨论。mDNS 的发现与命名机制不能替代应用层身份验证；不能据此宣布 Mac 原生 Remote/CarPlay 兼容。没有将其写成未经测量的 Bonjour profile。

## S04　NIST SP 800-63B-4
https://pages.nist.gov/800-63-4/sp800-63b.html

已读 HTML 生物认证相关段落。该数字身份体系对生物特征、面部呈现攻击检测和声纹比较有明确约束。引用用于收紧本项目的研究/授权边界，不声称本应用已认证，也不把它说成所有桌面软件的普遍法规。

## 仍未取得的资料或证据
本轮 Mac 工作区连接失败，未取得真实 SDK 编译输出。不能因能访问 Apple 文档网页壳，就写成已读到 AX、GameController 或私有 ABI 的完整契约。相关头文件、系统版本、设备原始消息、许可与运行行为依各工单取得。未复制 SDK、字体、第三方商业媒体、真实密钥或连接凭据。
