# A3 · 编程会话原生视图

状态：`VIEW_SOURCE_ONLY`。这是明确的交付粒度，不是整 App 已通过。尚缺的桥或界面在下面逐项写明。

## 可写路径

- `prototype/App/Notch.swift`（只能在新暂存分支按补丁或本表施工）。
- `prototype/App/NotchAuthentication.swift`（只能在新暂存分支按补丁或本表施工）。

本包实际新增源码：
- `prototype/App/WS2AgentSessionView.swift`

## 既有符号（上传快照）

- `prototype/App/Notch.swift:71`：`func authenticationPanel() -> NotchPanel? {`
- `prototype/App/Notch.swift:1431`：`func setInteraction(_ view: (NSView & NotchInteractiveContent)?, animated: Bool = true) {`
- `prototype/App/Notch.swift:1440`：`func setActivities(_ items: [NotchActivity], selected: String?) {`
- `prototype/App/Notch.swift:2176`：`func setAuthentication(_ view: (NSView & NotchInteractiveContent)?) {`
- `prototype/App/Notch.swift:2480`：`func resetInteractions() {`
- `prototype/App/NotchAuthentication.swift:6`：`@MainActor protocol NotchInteractiveContent: AnyObject { var onCancel: (() -> Void)? { get set } }`
- `prototype/App/NotchAuthentication.swift:73`：`func authorize(_ target: AuthTarget, completion: @escaping (AuthorizationGrant?) -> Void) {`
- `prototype/App/NotchAuthentication.swift:165`：`private func fail(_ message: (AuthTarget) -> String) {`
- `prototype/App/NotchAuthentication.swift:207`：`final class NotchAuthenticationView: NSView, NotchInteractiveContent {`

这些行号不是远程最新 HEAD。`private` 符号只在所属文件的补丁中使用，不跨文件调 private、不扩大可见性来绕开错误。

## 决定表

|情况|执行动作|理由|
|---|---|---|
|observed 会话|只显示“打开”；不显示停止/提交/修改模型。|观测终端不等于拥有进程|
|owned 且 running|显示“停止”；动作携带完整 WS2.Context 回宿主复核。|UI 文本不作为会话标识|
|等待审批|列表只显示“等你确认”；审批由 A4 独占最高层。|不能在普通列表里直接 allow|
|租约丢失/锁屏/换屏|先使 inputIsCurrent 返回 false，再 revoke 清空文本和按钮映射。|晚到按钮事件不能操作旧会话|
|安装|WS2AgentSessionView 是完整 NSView；宿主桥和数据订阅尚未写入原 App。|当前状态与实际接线区分|

表外输入停止相应动作、保留原系统行为并报告，不自行扩大功能。安全失败不得回退到“允许”。

## 常量、文字与来源

列表上限 64 来自 A1；摘要可见截断 160 字符为推荐，不截断真实授权目标。

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
