# 第六份来源与证据范围

查阅日期：2026-10-03。以下只保存定位、简短结论和边界，不打包第三方完整文章或源码。工程默认另见 DECISIONS.md；不能把我们的容量和超时数字说成标准规定。

<a id="s01"></a>

## S01　Swift Evolution SE-0306: Actors

来源：[Swift Evolution SE-0306: Actors](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0306-actors.md)。

定位：Actor reentrancy。Swift 语言设计一手资料，读取 main；不是本次 SDK 构建证据。

用于：Actor 隔离不能替代跨 await 的业务状态复核；本轮同步重入修复另由本地用例支持。

对应：`docs/02-并发仲裁与过期回调.md`。

<a id="s02"></a>

## S02　swift-corelibs-foundation / Process.swift

来源：[swift-corelibs-foundation / Process.swift](https://github.com/swiftlang/swift-corelibs-foundation/blob/main/Sources/Foundation/Process.swift)。

定位：读取文件 920–1080 行，spawn 和 terminate。实现源码观察，main 与本机 Swift 6.2.1 不是已证实相同提交。

用于：该实现的 terminate 向直接 PID 发信号；本包未实现进程树清理。PROC04 的结果来自实际探针，不能把当前上游实现当作 Mac 的运行证明。

对应：`docs/03-进程停止诊断与结果语义.md`。 本次返回的 Git blob SHA：`a0d7569f7b6ea14edaab9ef861eec39ed9150108`。

<a id="s03"></a>

## S03　Codex App Server 官方文档

来源：[Codex App Server 官方文档](https://developers.openai.com/codex/app-server/)。

定位：初始化、线程、turn、审批与通知。当前网址重定向到 https://learn.chatgpt.com/docs/app-server；文档是动态版本。

用于：仅用于理解生命周期。具体请求字段和测试按上传的 codex-app-server-schema-0.153.0 校验，不用动态文档代替固定版本。

对应：`docs/04-本地项目范围与助手权限.md`。

<a id="s04"></a>

## S04　pyatv / OPACK implementation

来源：[pyatv / OPACK implementation](https://github.com/postlund/pyatv/blob/master/pyatv/support/opack.py)。

定位：类型标记、容器、引用表与编解码。开源作者的实现观察，非 Apple 官方规范；其文件说明也指出未覆盖的格式。

用于：只借鉴协议观察和边界，未复制源码；不能由 pyatv 控制 Apple TV 反推 iPhone Remote 接受 Mac 服务端。

对应：`docs/06-配对网络与资源预算.md`。 本次返回的 Git blob SHA：`6b4b13ebc1ccba1a080d0b7a4922012e1281e2c5`。

<a id="s05"></a>

## S05　RFC 8259: JSON

来源：[RFC 8259: JSON](https://www.rfc-editor.org/rfc/rfc8259.html)。

定位：§4 Objects；§9 Parsers。固定 RFC 原文。

用于：重复名字存在互操作差异；解析器可设资源限制。本包对重复键和容量的严格默认属于本项目决定。

对应：`docs/06-配对网络与资源预算.md`。

<a id="s06"></a>

## S06　RFC 6762: Multicast DNS

来源：[RFC 6762: Multicast DNS](https://www.rfc-editor.org/rfc/rfc6762.html)。

定位：协议范围与 Security Considerations。固定 RFC 原文。

用于：发现的名称和服务不直接等价于已认证的 peer。具体 Apple service/TXT 字段仍需设备观察。

对应：`docs/06-配对网络与资源预算.md`。

<a id="s07"></a>

## S07　RFC 5869: HKDF

来源：[RFC 5869: HKDF](https://www.rfc-editor.org/rfc/rfc5869.html)。

定位：§2 与 §3.2 info 的作用。固定 RFC 原文。

用于：上下文分离是派生用途；派生出字节不证明设备身份，也不替代 PAKE、签名或 AEAD 验证。

对应：`docs/06-配对网络与资源预算.md`。

<a id="s08"></a>

## S08　NIST SP 800-63B-4: Authentication and Authenticator Management

来源：[NIST SP 800-63B-4: Authentication and Authenticator Management](https://pages.nist.gov/800-63-4/sp800-63b.html)。

定位：§3.2.3 Use of Biometrics。NIST 官方网络数字身份指南，2025 年第四版；须保留其适用范围。

用于：生物特征存在概率误差；该指南限制其独立使用，并讨论活体/呈现攻击。本文借鉴风险边界，不宣称它是所有 Mac 软件的强制产品规定。

对应：`docs/08-身份信号隐私与安全默认.md`。

## 本地一手证据

候选代码事实以 `code-map.json` 的 SHA256 和行号为准；固定协议证据在 `validation/wire-schema.json`。Linux 进程现象以 `validation/exit-inheritance-probe.json` 为准。它们比泛泛的系统经验更接近本次对象，但均不能推广成 macOS/真实助手的验收结果。

## 没有取得的证据

Apple 部分文档入口只返回了 JavaScript 页面，未取得可核查正文；本轮没有由此确认新的 SDK 签名。macOS API 的可用性和线程约束仍须在实际 SDK 编译、文档与真机中复核。没有原生 Remote 对 Mac 服务端的发现/握手录制，没有实际 Touch ID/Keychain/蓝牙/窗口恢复结果。第三方库源码观察不替代其依赖构建、版本锁定和互测。
