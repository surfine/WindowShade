# L4 · 本地锁屏请求与归属

状态：`POLICY_CORE_TESTED`。这是明确的交付粒度，不是整 App 已通过。尚缺的桥或界面在下面逐项写明。

## 可写路径

- `prototype/Core/SessionLockState.swift`（只能在新暂存分支按补丁或本表施工）。
- `prototype/App/NotchAuthentication.swift`（只能在新暂存分支按补丁或本表施工）。

本包实际新增源码：
- `prototype/Core/WS2LockRequestPolicy.swift`

## 既有符号（上传快照）

- `prototype/Core/SessionLockState.swift:5`：`enum SessionLockState: Equatable {`
- `prototype/App/NotchAuthentication.swift:6`：`@MainActor protocol NotchInteractiveContent: AnyObject { var onCancel: (() -> Void)? { get set } }`
- `prototype/App/NotchAuthentication.swift:73`：`func authorize(_ target: AuthTarget, completion: @escaping (AuthorizationGrant?) -> Void) {`
- `prototype/App/NotchAuthentication.swift:165`：`private func fail(_ message: (AuthTarget) -> String) {`
- `prototype/App/NotchAuthentication.swift:207`：`final class NotchAuthenticationView: NSView, NotchInteractiveContent {`

这些行号不是远程最新 HEAD。`private` 符号只在所属文件的补丁中使用，不跨文件调 private、不扩大可见性来绕开错误。

## 决定表

|情况|执行动作|理由|
|---|---|---|
|windowshade://lock|仅接受无查询、无片段、无用户信息的精确 URL；归类 localLink。|不能把 URL 来源认作已配对 iPhone|
|未知/恶意 URL|忽略且不执行外部 shell；不把 URL 参数转成密码或命令。|限定动作面|
|锁屏后回调|只有匹配 presence request UUID 且 5 秒内的后端确认才记录 ownedLock。|普通系统锁不能取得自动解锁资格|
|确切锁来源不可证明|ownedLock=nil，仍允许用户正常手动解锁。|宁可丢自动恢复资格，不猜来源|
|实际系统锁命令|后端尚未验证；按 P-LOCK 在场探针，不能以盖板动画替代系统锁。|隐私遮罩和 OS 安全状态分开|

表外输入停止相应动作、保留原系统行为并报告，不自行扩大功能。安全失败不得回退到“允许”。

## 常量、文字与来源

5 秒归属关联窗为推荐；该核不操作系统锁，也不自动输入密码。

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
