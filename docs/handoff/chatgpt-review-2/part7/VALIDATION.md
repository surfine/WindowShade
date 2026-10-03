# 第七份实际验证

运行环境：Linux x86_64 / Swift 6.2.1 / GCC 14.2.0。实际版本输出见 build-checks.json。Mac 工作区连接实际尝试失败，当前无 macOS SDK、真实 Codex/Claude、真实账号或设备。没有触碰真实用户 home、执行真实模型请求、配对、签名或发布。

## 本次新增

|套件|场景|断言|实际系统与限制|
|---|---:|---:|---|
|core|27|51|真实临时文件权限/链接/保留原编辑；JSON、URL、quit barrier；无 Mac UI|
|native|3|14|真实 posix_spawn 管道、直属进程、组内子孙、信号和回收；Linux|
|flow|18|145|实际候选 controller/session/wire/native 与真实合成后端子进程；无网络/账号/模型服务|
|Swift 合计|48|210|不把旧回归或 Python 加进去|

stage 工具另有 10 个 Python unittest，通过；它们验证的是文件处理拒绝规则，不是应用功能。JSON schema 检查使用实际 flow 管道出站消息：77 个请求、14 个 initialized 通知、1 个拒绝审批 response，全部符合固定 0.153.0 的对应 schema。不是端到端协议兼容认证，更不是实际沙盒证明。

每条新增用例及计数在 core-results/native-results/flow-results.json，完整 argv、退出码、stdout/stderr 在各自 commands.json。fixtures 明确是假后端，不得安装到生产。固定测试私密字符串均是人工合成，不包含真实凭据。

## 旧回归：原测试源码，使用新候选

|旧套件|实际结果|
|---|---|
|part6 Core|42 场景 / 95 断言，通过|
|part6 WireProfile|5 / 11，通过|
|part5 Core|40 / 97，通过|
|part4 Core|72 / 188，通过|
|part2 Core|22 / 86，通过|
|原 T1 FocusTimer|12 / 32，通过|
|part6 Process|9 / 27，通过|
|part5 Process|8 / 26，通过|
|原 ConductorGestureTests|原程序报告全部通过，不重新发明统一计数|

这些是重跑的旧用例，不是本轮新增。regressions-foundation.json 和 regressions-process.json 保留每条实际编译/运行命令；测试二进制在自动清理的临时目录，历史输入未写入 .build。

原 **PROC04** 没有改源文件或放宽判据。本轮结果 OBSERVED_PASS，耗时 0.022857 秒，未收到 0.8 秒后的迟到行。报告的条件仍是小于 0.7 秒的特定 fixture；不是 23ms 保证，也没有证明 Mac、脱离组子孙或宿主崩溃清理。原旧失败报告保留于历史 part6。

## 编译与运行层级

33 份实际 Foundation 候选同一次 Swift 6 / strict-concurrency=complete / warnings-as-errors 类型检查通过。C 模块实际在 Linux 编译并链接进上述测试。16 份变更 Swift 逐一 frontend parse 通过，build.sh 的 bash 语法检查通过。

parse 不加载 Cocoa、Security、GameController、Metal、Sparkle 或 CryptoKit 的实际 SDK。本轮没有整 App Mac 编译、原生显示或 Mac C 分支运行。`run-mac-check.sh` 在 Linux 实际退出 78，输出 NOT RUN；没有计入成功。App/Updater、AppDelegate 正常退出链属于候选源码，纯 quit barrier 测试不能证明实际 NSApplication delegate 顺序。

## 输入与包装

基线的 1145 文件与本次收到的 v6 ZIP 候选逐项比较。stage 只产生新目录，完整输出 1157 文件；新增 12，修改 9，无删除。完整核对和压缩校验记录在 packaging/integrity 文件。哈希和组合成功只证明字节/路径一致，不证明业务可用。

## 开发阶段真实失败

保留 validation/development：最初 StrictJSON 的 Optional 模式语法错误、原生 view 的 Swift 空格语法错误；native fixture 的 Python 环境自动加载导致启动本身约一秒，之后改用同一解释器 -S，未放宽退出判据；最初 fixture 错写了本机不存在的解释器路径，改为 runner 实际解析的路径；schema 捕获 logout 空 params，修改候选并重跑 flow/schema。

一次把 flow/schema/build 连续放进同一工具调用达到调用时限，build 记录仅完成版本采集，保存 interrupted 文件。随后独立重跑 check-build 完整成功；没有把被中止的调用写成完整通过。可重复命令见 README。清理后的临时二进制不随包交付，原始日志保留。

## 尚未验证

真实配置强制/账号登录/模型执行/原生认证与允许审批、AppKit 布局和系统退出、Keychain/SRP/Remote、输入外设、AX 隐藏恢复、全部原入口/设置、能耗、签名发行以及影片均没有本轮运行结果。独立 CODEX_HOME 和 read-only 参数不等于验证过的系统级隔离；版本字符串不证明程序真实性。范围严格依 REMAINING 和 COMPLETION-CONTRACT。
