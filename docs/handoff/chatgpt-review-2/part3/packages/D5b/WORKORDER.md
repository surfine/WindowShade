# D5b · 配对验证与密码学边界

状态：`TLV_ONLY_NO_TRANSPORT`。这是明确的交付粒度，不是整 App 已通过。尚缺的桥或界面在下面逐项写明。

## 可写路径

- `prototype/Core/AuthorizationModels.swift`（只能在新暂存分支按补丁或本表施工）。
- `prototype/App/AuthorizationService.swift`（只能在新暂存分支按补丁或本表施工）。

本包实际新增源码：
- `prototype/Core/PairingTLV.swift`

## 既有符号（上传快照）

- `prototype/Core/AuthorizationModels.swift:50`：`struct AuthTarget: Equatable, Sendable {`
- `prototype/Core/AuthorizationModels.swift:61`：`static func setting(_ key: String, from: Bool, to: Bool) -> AuthTarget {`
- `prototype/Core/AuthorizationModels.swift:70`：`static func deviceKey(publicKeyRaw: [UInt8]) -> AuthTarget {`
- `prototype/App/AuthorizationService.swift:28`：`func consume(_ grant: AuthorizationGrant, purpose: AuthPurpose, currentTarget: AuthTarget) -> AuthFailure? {`

这些行号不是远程最新 HEAD。`private` 符号只在所属文件的补丁中使用，不跨文件调 private、不扩大可见性来绕开错误。

## 决定表

|情况|执行动作|理由|
|---|---|---|
|TLV碎片|只允许同类型相邻且前段长度255的续段；重复独立字段拒绝。|消除多义编码|
|PIN正确|仍不等于 pair verify 成功；必须绑定登记公钥、角色、完整握手和连接代次。|PIN不是长期身份|
|数据加密|真实实现必须分方向 HKDF 密钥、单调 nonce、认证帧头、长度上限、验 MAC 后分发。|禁止在解密认证前解析为动作|
|重放/nonce耗尽/公钥变化|关闭连接、清会话密钥和当前输入；重新通过受控配对。|不能带着旧输入状态换身份|
|源码事实|本份仅交 TLV 编解码与决定表，没有 SRP/PairVerify/Keychain/AEAD生产实现。|不把普通 TLV 或 CryptoKit API名当作完成密码学|

表外输入停止相应动作、保留原系统行为并报告，不自行扩大功能。安全失败不得回退到“允许”。

## 常量、文字与来源

64 KiB TLV上限为推荐；Apple CryptoKit资料仅说明原语，不证明控制中心私有协议互操作。

项目事实按原包 `docs/handoff/reference/mac-facts-2026-10-03.md` 与固定 schema；外部来源见根 `SOURCES.md`。普通状态文字直接使用源码。新界面使用 SF Symbols；缺符号时保留文字，不以空白按钮上线。

## 精确补丁与接线

本份实际修改原文件的包：查看根 `patches/edits.json`（原文件 SHA256、起始行、唯一旧片段、新片段）与 `patches/diffs/`（前后 3 行）。使用统一 stage 工具按次序组合，不直接用 `patches/files/` 覆盖前两份改动。未在 edits 中出现的宿主改动尚未完成，不能声称已经安装。

## 验收命令

在第三份根执行 `bash tests/run-core.sh`，成功退出 0，末行含 `PASS part3 core`。只有 `validation/core-results.json` 里列出的场景属于实际测试；此命令不证明每个 App 包的功能已运行。

在统一交接根执行 `python3 tools/stage-all.py --repo /原repo绝对路径 --out /全新暂存路径`，成功退出 0，输出 `PASS STAGED_ALL`。它只处理文件，不启动 App。

Mac 分支执行 `cd /全新暂存路径/prototype && ./build.sh --check`；预期退出 0，编译诊断为零。此处预期不等于已测。没有 Mac SDK 时状态保持 `NOT_RUN`；不能拿 `swiftc -frontend -parse` 代替。

常见错误：新增 enum case 时补穷尽 switch；找不到共享类型时查重复或缺文件；actor 错误把回调按原源的队列合同送主线程，不能任意加 `@unchecked Sendable`；SDK 不存在的方法回看固定头文件，禁止猜 selector；框架链接错误只补实际用到的框架。详见 `integration/MAC-ACCEPTANCE.md`。

## 不要做

不改真实 home；不自动启动 CLI；不改系统键盘；不对未知触点 ABI 解引用；不提交、签名或发布；不把探针、禁用设置页、纯核测试或通用加密原语称为生产桥已完成。
