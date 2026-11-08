# D6：Codex固定协议模拟核

## 本次交付状态

假消息流通过；9条输出对固定schema通过。未实现真实Process/stdio生命周期、thread/resume、完整服务器事件投影和授权允许应答；不称完整D6完成。

源码与记录：CodexWire.swift、tests/Part2CoreTests.swift、validation/codex-outbound.ndjson。下面只授权在审查分支施工，不授权修改真实home、设备配对或生产用户配置。

## 可写文件

- `prototype/Core/CodexWire.swift`

## 已有符号

上传schema v1 InitializeParams、v2 ModelListParams、ThreadStartParams、TurnStartParams、TurnSteerParams、TurnInterruptParams；AgentSessions.receive(_:)。行号对应上传快照。先核实际签名；不为了穿透private改成public。

## 决定表

|情况|动作|原因|
|---|---|---|
|本包明确规则|初始化完成→发initialized→拉模型分页→允许thread/start；active turn不明→不start/steer；超时→不自动重发；reply整数7与字符串7分开；拒绝恰好一次；allow留给A4授权服务。|避免执行模型补出隐含行为|
|锁态未知、锁屏、睡眠、失去会话|先撤代次和输入，再清私密视图|不等动画结束才停|
|同一事件重复、异步晚回调|核上下文/序号/租约，过期丢弃|不能复活旧操作|
|SDK签名或私有ABI对不上|保留诊断，停该包，不unsafeBitCast猜签名|类型检查与设备证据分开|
|表外情形|停止该动作并报告输入、当前状态、缺失条件|不自主扩展产品|

## 常量与文案

1MiB帧、4MiB单次chunk、64pending、128approval、512模型、4096已答ID、30秒请求期限均为本次保守边界。 符号/文案以源码和对照表为准；默认不安装设备钩子，不发布系统动作。

## 验收

本包根目录 `bash tests/run-core.sh` 预期0，末行含`PASS part2 core`。它覆盖L2/D5a/D6和共享租约；**不覆盖S1/T2的AppKit行为**。T2 host单独Swift6 typecheck记录在validation/focus-host-typecheck.txt。

`python tools/stage.py --repo 原repo绝对路径 --out 全新目录` 预期0且含`PASS STAGED_NEW_DIRECTORY`。不能把out选为原repo或已存在目录。AppKit包在审查分支合入、补齐明确列出的宿主接点后执行 `cd prototype && ./build.sh --check`；本轮没有跑过。失败先核文件收集路径、framework、MainActor回调、enum新增case的穷尽switch。不得把编译失败简单改成@unchecked Sendable。

## 不要做

不把探针塞进App源码收集路径；不新建第二个@main进App；不为演示伪造后端成功；不把本包未实现项勾成完成。运行前保留输入哈希；暂存和编译输出不是生产验收。
