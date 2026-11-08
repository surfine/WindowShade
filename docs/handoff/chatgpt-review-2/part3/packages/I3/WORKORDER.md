# I3 · 主动滚轮桥

状态：`SPEC_WITH_EXISTING_CORE`。这是明确的交付粒度，不是整 App 已通过。尚缺的桥或界面在下面逐项写明。

## 可写路径

- `prototype/App/TrackpadGestures.swift`（只能在新暂存分支按补丁或本表施工）。

本包没有新增可运行桥源码；提供确定的施工与准入规则，不冒充已实现。

## 既有符号（上传快照）

- `prototype/App/TrackpadGestures.swift:485`：`private func begin(at location: CGPoint, ownWindow: NSWindow?, windowNumber: Int) {`
- `prototype/App/TrackpadGestures.swift:1068`：`private func perform(_ action: GestureAction, in session: Session) -> Bool {`

这些行号不是远程最新 HEAD。`private` 符号只在所属文件的补丁中使用，不跨文件调 private、不扩大可见性来绕开错误。

## 决定表

|情况|执行动作|理由|
|---|---|---|
|无法逐事件认定鼠标来源|原样放行，不插值、不吞事件。|continuous 标志、枚举列表均不足以归属来源|
|自己的合成滚动|先核本进程随机 tag，直接放行；绝不再次送插值器。|防止循环合成|
|EventTap 超时/权限取消/锁屏|同步关接管、取消尾巴、放行原始输入；恢复需用户重新启用。|不能卡住系统输入|
|合格鼠标离散滚动|原始事件只吞一次，调用 I1b 的插值输出；曲线空闲停时钟。|避免原事件和合成事件双重滚动|
|其他滚轮工具/游戏在前台|停止接管，清速度和尾巴，显示原因。|工具共存优先|
|生产桥|本份只交资格核与实施规格，未交 EventTap/HID 逐事件归属实现。|这是真正欠源码，不能列成只有实测缺失|

表外输入停止相应动作、保留原系统行为并报告，不自行扩大功能。安全失败不得回退到“允许”。

## 常量、文字与来源

重用 I1b 参数；source、tap、权限、前台、用户意图每一条件均须成立。

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
