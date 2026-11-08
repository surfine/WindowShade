# L2 · 在场检测蓝牙来源

状态：`PROBE_AND_DEADLINE_CORE`。这是明确的交付粒度，不是整 App 已通过。尚缺的桥或界面在下面逐项写明。

## 可写路径

- `prototype/App/DeviceBatteryController.swift`（只能在新暂存分支按补丁或本表施工）。
- `prototype/Core/SessionLockState.swift`（只能在新暂存分支按补丁或本表施工）。

本包没有新增可运行桥源码；提供确定的施工与准入规则，不冒充已实现。

## 既有符号（上传快照）

- `prototype/App/DeviceBatteryController.swift:9`：`@MainActor final class DeviceBatteryController {`
- `prototype/App/DeviceBatteryController.swift:42`：`func start() {`
- `prototype/App/DeviceBatteryController.swift:48`：`func stop() { source.stop() }`
- `prototype/Core/SessionLockState.swift:5`：`enum SessionLockState: Equatable {`

这些行号不是远程最新 HEAD。`private` 符号只在所属文件的补丁中使用，不跨文件调 private、不扩大可见性来绕开错误。

## 决定表

|情况|执行动作|理由|
|---|---|---|
|发现设备名字/RSSI|仅记录候选，不能设为 trusted 或已认证在场。|名称和信号强度不绑定身份|
|特征读取发起|每 5 秒最多一个，单次 outstanding 读取 2 秒超时；serial 对齐回调。|不是距离上次成功超过 2 秒就锁|
|没有可读取且可绑定的特征|标 unavailable；保持在场功能关闭。|iPhone 并不因曾被发现就具有可读服务|
|读回来自错设备/旧连接|丢弃；重新连接提升 epoch。|不得把旧回调归给新设备|
|探针只有电量|只证明电量读回，不升级为密码学心跳。|限制证据解释|

表外输入停止相应动作、保留原系统行为并报告，不自行扩大功能。安全失败不得回退到“允许”。

## 常量、文字与来源

5s/2s/发现6s来自已修订工作单；主程序来源和身份绑定仍未实现，按 P-BLE 决策树准入。

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
