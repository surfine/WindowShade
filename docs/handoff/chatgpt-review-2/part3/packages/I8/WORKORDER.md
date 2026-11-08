# I8 · 手柄意图映射

状态：`PURE_MAPPING_TESTED`。这是明确的交付粒度，不是整 App 已通过。尚缺的桥或界面在下面逐项写明。

## 可写路径

- `prototype/App/Preferences.swift`（只能在新暂存分支按补丁或本表施工）。

本包实际新增源码：
- `prototype/Core/GamepadMapping.swift`

## 既有符号（上传快照）

- `prototype/App/Preferences.swift:159`：`private func makeSettingsPageRoot() -> (NSView, NSStackView) {`
- `prototype/App/Preferences.swift:186`：`func makeShadeSettingsPage() -> NSView {`
- `prototype/App/Preferences.swift:263`：`func makePermissionsSettingsPage() -> NSView {`
- `prototype/App/Preferences.swift:784`：`func makeShortcutsSettingsPage() -> NSView {`
- `prototype/App/Preferences.swift:941`：`func makeWindowBrowserSettingsPage() -> NSView {`
- `prototype/App/Preferences.swift:1260`：`func configure(current: HotKey?) {`

这些行号不是远程最新 HEAD。`private` 符号只在所属文件的补丁中使用，不跨文件调 private、不扩大可见性来绕开错误。

## 决定表

|情况|执行动作|理由|
|---|---|---|
|初次连接|每次连接默认关闭；未证明稳定设备 ID 前不跨连接继承开启。|不能把另一只同型号手柄视作获准设备|
|摇杆|径向死区+平方响应，合成最大每次 50ms；唤醒不补一整段移动。|斜向不加速，卡顿不跳飞|
|扳机|超过 0.6 触发一次；回到 0.2 以下重新武装；游戏在前台让路。|长按不连翻桌面|
|停用/断连/权限失效|首先发 releaseTriggers，真实 Mac 适配需对左右触发器调用 setModeOff。|不能留下阻力|
|PS 按键|不占用，不映射为助手确认。|保留系统与游戏行为|
|Mac 桥|本份没有 GameController 生产桥；仅 pure mapping 已测试，头文件确证不替代桥实现。|缺源码与缺实测分别列|

表外输入停止相应动作、保留原系统行为并报告，不自行扩大功能。安全失败不得回退到“允许”。

## 常量、文字与来源

deadZone=.15、最大指针1000点/s、滚动800点/s、dt<=.05均为推荐；DualSense方法签名来自mac-facts。

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
