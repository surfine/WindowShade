# M1 · 菜单收拢与标题缓存

状态：`SDK_CANDIDATE`。这是明确的交付粒度，不是整 App 已通过。尚缺的桥或界面在下面逐项写明。

## 可写路径

- `prototype/App/MenuBarController.swift`（只能在新暂存分支按补丁或本表施工）。
- `prototype/PinnedPreview.swift`（只能在新暂存分支按补丁或本表施工）。

本包没有新增可运行桥源码；提供确定的施工与准入规则，不冒充已实现。

## 既有符号（上传快照）

- `prototype/App/MenuBarController.swift:34`：`func rebuildMenu() {`
- `prototype/PinnedPreview.swift:781`：`private func enforcePanelSpaceInvariant(_ session: PinnedPreviewSession, reason: String) {`

这些行号不是远程最新 HEAD。`private` 符号只在所属文件的补丁中使用，不跨文件调 private、不扩大可见性来绕开错误。

## 决定表

|情况|执行动作|理由|
|---|---|---|
|常驻入口|保持收起、收进刘海、置顶、排列、全部收进刘海、启动台、选择窗口、设置、退出九项；动态窗口段不计入。|沿用 docs/menu-bar.md 的九项决定|
|切换前台应用或缓存超过 3 秒|标题退回“当前窗口”；下次后台解析成功后再显示标题。|宁可不显示具体窗口，不把旧应用的标题当作当前对象|
|普通打开菜单|不做 AX 查询，不枚举摄像头，不加载设备探针。|避免同步 IPC 阻塞菜单|
|按住 Option 打开|关于使用 NSMenuItem.isAlternate；欢迎、更新与开发菜单按 Option 状态出现。|沿用原动作和快捷键；打开后再按 Option 的动态显隐仍需 Mac 测试|
|有 SUFeedURL 的构建|不建立开发子菜单。|防止诊断入口进入发布包|
|旧功能只剩一个入口|保留折叠/置顶全部操作；实时活动、欢迎、锁屏效果迁至 WS2SupplementPane。|不为减少行数删掉功能|

表外输入停止相应动作、保留原系统行为并报告，不自行扩大功能。安全失败不得回退到“允许”。

## 常量、文字与来源

3 秒缓存、80 字符截断是本轮推荐；9 个常驻项来自 menu-bar.md。补丁不改变 AX 目标的实际执行时重查。

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
