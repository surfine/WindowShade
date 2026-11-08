# A2b · 配置预览、备份、写入与回滚

状态：`LINUX_RUNTIME_TESTED`。这是明确的交付粒度，不是整 App 已通过。尚缺的桥或界面在下面逐项写明。

## 可写路径

- `prototype/App/Preferences.swift`（只能在新暂存分支按补丁或本表施工）。

本包实际新增源码：
- `prototype/Support/WS2AtomicConfiguration.swift`
- `prototype/Support/WS2HookConfiguration.swift`

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
|已有 Claude JSON|只修改本 helper 的精确 command 条目；保留第三方 hook 和未知根字段。|不能整块覆盖 hooks|
|命令路径含空格/单引号|用固定单引号 shell 转义；拒绝相对路径、换行、NUL。|配置命令不能受路径内容注入|
|确认后写入|先排他锁、预览原文复核、0600 备份和临时文件、fsync，再 rename。|不覆盖看预览后出现的明显外部修改|
|首次新文件|createNew 使用 link 的不存在约束；目标刚出现就失败，不覆盖。|新建和替换不混成一个不安全分支|
|第三方并发编辑|复核不一致立即停止；备份保留；明确 POSIX rename 不是对不协作写者的原子 CAS。|不夸大并发安全性|
|Codex hook|明确 unsupportedProvider；没有已经核准的配置字段，不能写猜测 TOML。|固定 app-server schema 不证明 hook 配置 schema|

表外输入停止相应动作、保留原系统行为并报告，不自行扩大功能。安全失败不得回退到“允许”。

## 常量、文字与来源

1 MiB 配置上限为推荐；测试只使用临时目录；原生预览确认 UI 仍未接入。

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
