# I2 · 多触点 ABI 准入

状态：`PROBE_AND_QUALIFICATION_ONLY`。这是明确的交付粒度，不是整 App 已通过。尚缺的桥或界面在下面逐项写明。

## 可写路径

- `prototype/App/TrackpadGestures.swift`（只能在新暂存分支按补丁或本表施工）。
- `prototype/Core/ConductorGesture.swift`（只能在新暂存分支按补丁或本表施工）。

本包实际新增源码：
- `prototype/Core/MultitouchQualification.swift`

## 既有符号（上传快照）

- `prototype/App/TrackpadGestures.swift:485`：`private func begin(at location: CGPoint, ownWindow: NSWindow?, windowNumber: Int) {`
- `prototype/App/TrackpadGestures.swift:1068`：`private func perform(_ action: GestureAction, in session: Session) -> Bool {`
- `prototype/Core/ConductorGesture.swift:11`：`struct ConductorPoint: Equatable, Sendable {`
- `prototype/Core/ConductorGesture.swift:17`：`enum ConductorGesture: Equatable, Sendable {`
- `prototype/Core/ConductorGesture.swift:22`：`enum ConductorRejection: Error, Equatable, Sendable {`

这些行号不是远程最新 HEAD。`private` 符号只在所属文件的补丁中使用，不跨文件调 private、不扩大可见性来绕开错误。

## 决定表

|情况|执行动作|理由|
|---|---|---|
|dlsym 有符号|只记 symbolPresent；不得 unsafeBitCast 一个猜的触点结构。|地址存在不证明布局|
|构建号/架构/stride/offset/回调约定任一变化|撤回准入，先重新跑探针和布局核对。|ABI 证明绑定版本|
|未知设备/拔出/触点丢失|生成取消，不补 end，不猜一次点击。|避免留下按下状态|
|多触点证据不全|保持原 TrackpadGestures；不装第二套全局钩子。|避免破坏现有手势|
|回调桥|本份无已验证 ABI，未交可开启的原始触点桥；qualification 仅检查登记数据。|不能用一个真布尔值把假结构包装成安全|

表外输入停止相应动作、保留原系统行为并报告，不自行扩大功能。安全失败不得回退到“允许”。

## 常量、文字与来源

stride 16…1024 仅为登记健全性检查，不是 ABI 规范；P-MT 只能证明符号。

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
