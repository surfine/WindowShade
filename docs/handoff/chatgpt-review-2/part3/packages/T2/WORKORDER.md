# T2 · 唯一番茄钟宿主与活动接线

状态：`SDK_CANDIDATE`。这是明确的交付粒度，不是整 App 已通过。尚缺的桥或界面在下面逐项写明。

## 可写路径

- `prototype/WindowShade.swift`（只能在新暂存分支按补丁或本表施工）。
- `prototype/Core/NotchActivities.swift`（只能在新暂存分支按补丁或本表施工）。
- `prototype/App/NotchActivityController.swift`（只能在新暂存分支按补丁或本表施工）。
- `prototype/App/NotchActivityView.swift`（只能在新暂存分支按补丁或本表施工）。
- `prototype/App/Notch.swift`（只能在新暂存分支按补丁或本表施工）。

本包实际新增源码：
- `prototype/App/WS2AppRuntime.swift`

## 既有符号（上传快照）

- `prototype/WindowShade.swift:300`：`func applicationDidFinishLaunching(_ note: Notification) {`
- `prototype/WindowShade.swift:799`：`func applicationWillTerminate(_ note: Notification) {`
- `prototype/Core/NotchActivities.swift:13`：`enum NotchActivityAction: String {`
- `prototype/Core/NotchActivities.swift:18`：`enum NotchActivityKind: String, Codable, Sendable, CaseIterable {`
- `prototype/Core/NotchActivities.swift:38`：`struct NotchActivity: Equatable, Sendable {`
- `prototype/App/NotchActivityController.swift:51`：`func configure() {`
- `prototype/App/NotchActivityController.swift:63`：`private func resume(_ reason: String) { suspensions.remove(reason); configure() }`
- `prototype/App/NotchActivityController.swift:77`：`private func receive(_ items: [NotchSourceSnapshot]) {`
- `prototype/App/NotchActivityController.swift:117`：`func perform(_ action: NotchActivityAction) {`
- `prototype/App/NotchActivityView.swift:6`：`final class NotchActivityView: NSView {`
- `prototype/App/NotchActivityView.swift:44`：`func update(_ activities: [NotchActivity], selected: String?, expanded: Bool) {`
- `prototype/App/NotchActivityView.swift:76`：`override func layout() { super.layout(); layoutContents() }`
- `prototype/App/Notch.swift:71`：`func authenticationPanel() -> NotchPanel? {`
- `prototype/App/Notch.swift:1431`：`func setInteraction(_ view: (NSView & NotchInteractiveContent)?, animated: Bool = true) {`
- `prototype/App/Notch.swift:1440`：`func setActivities(_ items: [NotchActivity], selected: String?) {`
- `prototype/App/Notch.swift:2176`：`func setAuthentication(_ view: (NSView & NotchInteractiveContent)?) {`
- `prototype/App/Notch.swift:2480`：`func resetInteractions() {`

这些行号不是远程最新 HEAD。`private` 符号只在所属文件的补丁中使用，不跨文件调 private、不扩大可见性来绕开错误。

## 决定表

|情况|执行动作|理由|
|---|---|---|
|App 存活期|仅 AppDelegate.ws2Runtime 持有一个 FocusTimerHost；视图只投影。|多视图不得创建重复计时器|
|专注活动排序|新增 focus=85，位于 recording=90 与 airDrop=80 之间。|既有优先级不重排|
|暂停/跳过/结束|既有活动卡按钮发 focusTogglePause、focusSkip、end；只有选中 focus 时转发。|不误停路线或音乐|
|窗口副作用|由 focusWindowEffects 接到主模型 T3；未连接时仅运行计时，设置明确说明。|本包没有窗口所有权，因此不代替 T3 恢复窗口|
|锁、睡眠、会话切换|合并多个锁原因；全部解除后才向纯核发 unlocked；最终启动仍核权威 lockState。|通知不能单独证明安全状态|
|展开秒级显示和圆环|复用第 2 份 FocusTimerCard，按 integration/FOCUS-ADAPTER.md 接入；当前精确补丁仅接通现有紧凑活动卡。|不把未安装的圆环视图写成已接入|

表外输入停止相应动作、保留原系统行为并报告，不自行扩大功能。安全失败不得回退到“允许”。

## 常量、文字与来源

25/5 默认来自 T1；85 为本轮推荐排序值；计时单位为连续时钟纳秒，不能当 Unix 时间戳。

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
