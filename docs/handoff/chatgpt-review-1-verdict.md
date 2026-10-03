# 主模型对 ChatGPT 第一轮审查的结论

2026-10-03。第一轮审查原件：[chatgpt-review-1/](chatgpt-review-1/)（53 条问题、24 页小抄、3 份参考、合成测试材料、验证记录）。
本机事实：[reference/mac-facts-2026-10-03.md](reference/mac-facts-2026-10-03.md)。Codex App Server 协议：[reference/codex-app-server-schema-0.153.0/](reference/codex-app-server-schema-0.153.0/)。

## 总结论

**接受。**53 条全部作为施工方向采纳，下表的几条有补充。它说得对的地方：

- 授权绕过（R01、R02、R24、R45）是真风险；
- 几个包各自定义同一套会话和输入状态，会互不兼容（R07、R21）；
- 把“候选路线”写成了“确定 API”（R03、R14、R15、R19、R20）。

这些都是我写提示词时的疏漏。

在本机核实过的：

- R08 属实：`./build.sh --check` 会编译 Metal、整模块优化、链接 Sparkle。
- R20 属实：DualSense 没有 `adaptiveTriggers` 属性，是 `leftTrigger` / `rightTrigger`（`GCDualSenseAdaptiveTrigger`），已改正 `deepseek-input.md`。
- 小抄里的私有触控符号，在本机 `dlsym` 全部存在（结构体布局仍待探针）。
- Codex 0.153.0 有 hook 信任机制（`--dangerously-bypass-hook-trust` 的存在说明默认要信任审核），并能导出 App Server 协议的 JSON Schema。
- 本机的 Claude Code 设置里没有 hook，`~/.codex/hooks.json` 也不存在。

## 有补充或保留的

| 编号 | 结论 |
| --- | --- |
| R10 | 已解决：文档已提交到 `main`，DeepSeek 从 `main` 克隆就能看到。规则改成“主模型派工前确认基线已提交；DeepSeek 永不提交” |
| R08 | 接受；补充：DeepSeek 的沙箱就在这台 Mac 上（Seatbelt），有 macOS SDK 和仓库里的 Sparkle，`--check` 能跑 |
| R42 | **保留 Aaron 的决定**：不走 App Store，Face Data 的用途限制不作施工门槛。ChatGPT 的提醒记录在案，作为发布前的非阻断核对项；R43 的技术证据要求（模型来源、许可、哈希、实测计算单元）全部接受 |
| R02 | 接受；“没开刷脸解锁时只靠手机回来就开”仍待 Aaron 定，在他定之前不实现 |
| R05 | 接受：D5 只走 Swift 方向，删掉 Rust 要求 |
| R06 | 接受：itsytv-core 在拿到覆盖相关文件的许可文本前，当作许可未知，只独立实现 |
| R33 | 接受：对外文案改成“断开被发现后约 11.5 秒”，检测时间单独记 |
| 四个主模型前置 | 接受（冻结事件与审批合同、全局交互租约与每屏显示、隐私登记与日志修复、可复现构建基线）。第二轮请 ChatGPT 起草，由主模型审定后冻结 |
