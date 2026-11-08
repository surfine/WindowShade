# I7 · 输入偏好与准入联动

状态：`ELIGIBILITY_CORE_TESTED`。这是明确的交付粒度，不是整 App 已通过。尚缺的桥或界面在下面逐项写明。

## 可写路径

- `prototype/App/Preferences.swift`（只能在新暂存分支按补丁或本表施工）。
- `prototype/App/GlobalShortcuts.swift`（只能在新暂存分支按补丁或本表施工）。

本包实际新增源码：
- `prototype/Core/WS2InputEligibility.swift`

## 既有符号（上传快照）

- `prototype/App/Preferences.swift:159`：`private func makeSettingsPageRoot() -> (NSView, NSStackView) {`
- `prototype/App/Preferences.swift:186`：`func makeShadeSettingsPage() -> NSView {`
- `prototype/App/Preferences.swift:263`：`func makePermissionsSettingsPage() -> NSView {`
- `prototype/App/Preferences.swift:784`：`func makeShortcutsSettingsPage() -> NSView {`
- `prototype/App/Preferences.swift:941`：`func makeWindowBrowserSettingsPage() -> NSView {`
- `prototype/App/Preferences.swift:1260`：`func configure(current: HotKey?) {`
- `prototype/App/GlobalShortcuts.swift:9`：`enum GlobalShortcut: String, CaseIterable {`
- `prototype/App/GlobalShortcuts.swift:142`：`func factoryHotKey(for history: InstallHistory) -> HotKey? {`
- `prototype/App/GlobalShortcuts.swift:145`：`func key(_ code: Int) -> HotKey { HotKey(keyCode: UInt32(code), modifiers: controlCommand) }`

这些行号不是远程最新 HEAD。`private` 符号只在所属文件的补丁中使用，不跨文件调 private、不扩大可见性来绕开错误。

## 决定表

|情况|执行动作|理由|
|---|---|---|
|打开设置开关|保存意图，重新计算 enabled/device/permitted/unlocked/source/tap/competitor/exclusion。|单一开关不能绕过权限|
|关任意开关|先撤租约，再停止钩子，清插值和按钮按住，最后写持久化。|切换期间不能再发输入|
|已有同类工具|显示“由某工具接管”；不偷偷关闭别人。|保留工具共存|
|来源不确定|显示“来源尚未确认”，允许原始系统输入。|默认放行|
|偏好编辑器|WS2SupplementPane只展示禁用状态；真实偏好页与 bridge 联动仍未接。|不把设置原型当成功能|

表外输入停止相应动作、保留原系统行为并报告，不自行扩大功能。安全失败不得回退到“允许”。

## 常量、文字与来源

默认全 false，tapHealthy 初值 true 仅状态字段，其他条件仍阻断；数值由资格核测试覆盖。

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
