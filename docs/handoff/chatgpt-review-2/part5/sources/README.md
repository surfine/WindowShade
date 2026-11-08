# 来源与证据等级

核对日期：2026-10-03。源码事实以用户上传的第四份候选及本次 overlay 为准。`code-map.json` 为 44 个源文件提供实际 SHA256、符号与行号，`verify-sources.py` 能对本地输入复核。本文的 S 编号供背景/工单引用；没有要求执行模型重新搜一遍才能知道决策。外部网页不随包全文复制。

## 外部一次来源

**S01 · RFC 5054**  
https://www.rfc-editor.org/rfc/rfc5054.html  
用途：SRP 数学背景、公共值处理、标准组、附录算式。已读取正文。局限：它不单独定义 Companion 的整套 Pair-Setup 字节和服务发现；本包的 Python 只对附录 B 的部分中间量做检查，不冒称通过完整 RFC 向量。

**S02 · swift-srp 固定源码修订**  
https://github.com/adam-fowler/swift-srp/commit/1345dfeff4d1bc54fc36257325371df3d1d7a813  
通过 GitHub 连接器核对提交、目录和相关源码。提交日期 2026-08-12。该改动增加 generator proof padding 配置；它不代表所有 HAP 编码都已兼容。此依赖是隔离候选，传递依赖尚未实际 resolve。主工程没有新增第三方依赖或复制其源码。

**S03 · 同一修订的 SRP 实现 API**  
https://github.com/adam-fowler/swift-srp/blob/1345dfeff4d1bc54fc36257325371df3d1d7a813/Sources/SRP/server.swift  
https://github.com/adam-fowler/swift-srp/blob/1345dfeff4d1bc54fc36257325371df3d1d7a813/Sources/SRP/keys.swift  
https://github.com/adam-fowler/swift-srp/blob/1345dfeff4d1bc54fc36257325371df3d1d7a813/Sources/SRP/client.swift  
server blob：`3981a2b6b755799bd7afbb8ba8084d5606b09157`；keys：`819dc29591d3fda9515e6eac52e553905427820c`；client：`ffc250876990ba4f6c3288d4585a8bff63cad497`。已读用于 adapter 的 generateSaltAndVerifier、generateKeys、calculateSharedSecret、SRPKey 和 proof 部分。未据此宣称整个密码学/BigNum 后端恒时或已审计。

**S04 · pyatv 作者维护的协议说明**  
https://pyatv.dev/documentation/protocols/  
用途：Companion 的帧和握手结构观察，区分外层消息与内层 TLV。它是实现者文档，不是 Apple 官方规范，也不是本项目的原生互操作结果。示例有展示长度/正文不一致的地方，必须从实际 bytes 重新算长度；不抄数字冒充证据。

**S05 · pyatv HAP/SRP 源码**  
https://github.com/postlund/pyatv/blob/master/pyatv/auth/hap_srp.py  
本次实际读取 Git blob：`3453bfd1096c483c267a607d2ec29cbd4af4a1dc`。master 链接将来可能变化，复核时按 blob 对比。用途：读取其实际参数、签名输入和派生标签；发现其 M6 路径有未完成的签名核验，不继承该缺口。尝试读取另一仓库中的 srptools/context.py 返回 404，**没有声称已读 srptools 内部实现**。

**S06 · Apple WWDC18 Session 715**  
https://developer.apple.com/videos/play/wwdc2018/715/  
已读官方 transcript。用途：Network.framework 生命周期、回调队列和 contentProcessed 的本地消费含义，支持有界背压设计。它不证明本包的 Network Swift 源码已经用 SDK 编译或实际互通。

**S07 · Apple Keychain 官方入口**  
https://developer.apple.com/documentation/technotes/tn3137-on-mac-keychains  
https://developer.apple.com/documentation/security/ksecusedataprotectionkeychain  
https://developer.apple.com/documentation/security/ksecattraccessiblewhenunlockedthisdeviceonly  
用途：定位 Mac Keychain 模型和候选 API。页面为动态文档，本轮工具只取得部分页面/检索元信息，**未完整读取所有技术说明**；具体部署行为和 SDK 可用性仍由 Mac 编译/签名域测试确认，不伪造本地头文件证明。

**S08 · Apple 非交互认证上下文 API**  
https://developer.apple.com/documentation/localauthentication/lacontext/interactionnotallowed  
https://developer.apple.com/documentation/security/ksecuseauthenticationcontext  
用于说明非交互 Keychain 候选的 API 选择。取得官方 API 元信息，完整实现语义不由网页入口替代真机试验。

**S09 · OpenAI Codex App Server 官方文档**  
https://developers.openai.com/codex/app-server  
本次重定向到 https://learn.chatgpt.com/docs/app-server 。用途：复核 stdio/初始化/thread/turn 概念。真正消息字段仍按用户附件中的 `docs/handoff/reference/codex-app-server-schema-0.153.0`；没有下载最新字段覆盖旧协议，也没有实际运行 CLI。该附件含 304 份 JSON，来源已有冻结记录。

## 本地证据入口

**C-CodexWire**：`prototype/Core/CodexWire.swift`。真实 LF 分帧、pending、thread/turn、请求生成，见 code-map 的对应符号。新 writer 与其兼容边界来自实际读取，不来自网页推测。

**C-PIN**：`prototype/Core/PairingAttemptWindow.swift`。3 次/300 秒/60 秒，优先于第四份不一致的散文说明。

**C-Fold**：`App/Notch.swift`、`App/ShadeController.swift`、`App/FoldCompletion.swift`、`App/FoldTransaction.swift`、`WindowBrowser/WindowBrowserAppDelegate.swift`、`Core/ShadeModels.swift`、`WindowShade.swift`。关于切换入口、先登记后验证、等待器与事务 ID 的结论均来自这些实际文件。

**C-Owners**：`App/WS2AppRuntime.swift`、`App/AuthorizationService.swift`、`App/NotchAuthentication.swift`、`App/WS2IslandCoordinator.swift`、`App/WS2GameControllerBridge.swift`。唯一 owner、认证账、handlerQueue 的接线依据。

## 不混淆三种材料

原始代码是当前行为的证据，不能自动证明行为正确；官方 API 文档是接口依据，不能自动证明本项目调用正确；本包决定是可审查的工程取舍，不能冒充 Apple 的要求或设备实测。P5 文档中的“建议新增”文件是明确待写调用者，overlay 中才是实际交付源码。
