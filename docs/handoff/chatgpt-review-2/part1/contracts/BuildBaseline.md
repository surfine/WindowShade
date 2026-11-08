# 构建和能耗基线合同 v1

本轮交付仅在 Linux Swift 6.2.1 上运行纯代码和文件测试。Aaron 的 Mac 参数来自交接包的 `mac-facts-2026-10-03.md`，不是本轮重新连接真机取得。macOS 27.0 / 26A428、Xcode 27 / 27A266a、Apple Swift 6.4、SDK 27 作为本次目标环境记录；生产最低部署仍按 build.sh 的 macOS 14.0。

## 1. 固定输入和安全范围

上传zip、每个引入的代码文件与原基准都记录 SHA256。仓库工作区不得有未登记改动；DeepSeek只做施工单允许的文件，主模型审查diff后提交。禁止运行没有`--check`的build.sh，禁止启动新App、覆盖正在使用的WindowShade、杀进程、签名、打包发布、改用户hook、设置或权限。1.0.16不发布。

`prototype/build.sh:70–80`会发现prototype目录下Swift源文件；测试@main只能放根目录tests，不能误放prototype。新增Foundation Core自动进App编译；复制旧骨架和新实现到同一目录会重复定义，不得靠删新实现解决。

`build.sh:27`实际用 `-O -whole-module-optimization`；`107`建立临时构建目录，`131–132`先编译Metal，`135–149`为check分支。`142`target是`$ARCH-apple-macosx14.0`，`144`仍链接Sparkle，`146`还编译watchdog。`--check`不是单文件typecheck，不是无Metal/Sparkle依赖的检查。原build没有指定Swift6语言模式，纯套件则显式采用Swift6严格并发；两者都要过，不能把一个替代另一个。

## 2. 在 Mac 的精确执行顺序

以下变量由主模型提供真实路径。不是要求执行模型猜目录。不要执行来源不明的local-codesign.env；原脚本会source它，即使是check，先检查其是否只有环境赋值。

```sh
# 从已确认的仓库根运行；只读记录，不修改Git状态。
mkdir -p "$EVIDENCE"
git rev-parse HEAD > "$EVIDENCE/head.txt"
git status --porcelain=v1 > "$EVIDENCE/status-before.txt"
sw_vers > "$EVIDENCE/os.txt"
xcodebuild -version > "$EVIDENCE/xcode.txt"
xcrun --sdk macosx --show-sdk-path > "$EVIDENCE/sdk-path.txt"
xcrun --sdk macosx --show-sdk-version > "$EVIDENCE/sdk-version.txt"
xcrun swiftc --version > "$EVIDENCE/swift.txt"
uname -m > "$EVIDENCE/arch.txt"
shasum -a 256 prototype/build.sh > "$EVIDENCE/build-sh.sha256"
# 先按本包tests/run-all.sh运行，再按每个工作单在仓库根跑专项测试。
# 完整App构建，仅check。保留退出码，不让tee掩盖失败。
set +e
(cd prototype && bash ./build.sh --check) > "$EVIDENCE/build-check.txt" 2>&1
rc=$?
set -e
printf '%s\n' "$rc" > "$EVIDENCE/build-check.exit"
test "$rc" -eq 0
grep -F '==> 编译验证通过' "$EVIDENCE/build-check.txt"
git status --porcelain=v1 > "$EVIDENCE/status-after.txt"
```

工具链信息读取不代表授权执行应用。没有可运行Mac、没有用户给定仓库、签名配置有可执行命令、Sparkle/Metal缺失，都记录 `BLOCKED` 和原始错误，不能删链接参数、删availability或把target改成本机新系统来蒙混通过。

|错误类|固定处置|
|---|---|
|重复类型/重复@main|检查是否同时装了第一轮骨架、新代码或把tests放进prototype；先给diff，删除本轮误装的重复副本|
|MacSDK符号缺失|比对mac-facts真实头文件、availability与条件编译；保留功能关闭路径，不猜不同框架同名API|
|MainActor/Sendable问题|保持App对象在MainActor，纯类型Sendable；不可全局加unchecked/关闭严格并发来消警告|
|CryptoKit在Linux缺失|不运行现有Mac授权账；本份纯契约传Digest，不自写密码学来凑Linux|
|Metal/Sparkle失败|原样记录依赖版本/命令；按既有构建恢复依赖，由主模型决定，不改产品要求|
|本包测试断言失败|保留失败日志和输入；不能删断言或把预期改成实际错误结果；未覆盖场景停下报告|

## 3. 固定能耗实验

基准候选是 Aaron 确認的1.0.15稳定构建与合并后候选。`performance.md:443–448`的build16历史样本是问题记录，不是1.0.15合格能耗门槛，也不是本轮复测。其日常使用和静置样本不能混作同一条件的前后对照。

固定条件（以下为本轮推荐实验设计，不冒充Apple标准）：同一Mac、同一系统、同一显示器和缩放/亮度、同一供电方式、低电量模式、网络、外设、窗口布局、权限和用户设置；记录充电/电池百分比与温度状态。自动更新关闭，暂停已知同步任务，排除屏幕录制、其他编译和测试工具自己的负载。两构建一次只运行一个，由Aaron明确同意切换，不能由测试脚本杀正在使用的版本。

先固定工作负载，顺序采用A-B-B-A，完整重复至少3轮。每个样本先安静120秒，再采60秒，丢弃top首个累计样本。观察中一旦人工操作、系统更新、屏幕睡眠/唤醒改变条件，该样本标invalid并保留，不挑低值。静置过程禁止caffeinate掩盖本应睡眠的状态。

|场景ID|设置和输入|主要观测|
|---|---|---|
|E0|稳定版本和候选均关全部新功能，未交互|CPU、idlew、内存；原功能是否回退|
|E1|开新功能，但无设备输入、无任务、无展示|各纯模型nextWake应nil；App额外唤醒不能归罪于模型|
|E2|番茄钟紧凑 / 展开 / 暂停各一组|只在文字会变或截止时唤醒；暂停无tick|
|E3|开启离席但设备在场；蓝牙服务不可用另测|读取计划5秒与2秒超时分开；不可用不能忙重试|
|E4|同一滚轮重复输入10秒，再静止60秒|动画显示链接及时停止；余量不丢、不反向跳|
|E5|指挥连接空闲 / 持续任务 / 待审批各一组|空闲无60Hz UI；截止计时只开必要一次性timer|
|E6|锁屏但机器仍醒着|敏感来源与新输入停用；只留已批准锁屏效果依赖|
|E7|隐私页关闭、打开、展开一行再关闭|页面不启动额外来源、不新增周期轮询|

主进程用PID而非可能重复的进程名。先人工核对该PID确为所测构建。本机方法依据performance.md第七节；top字段在当前Mac先确认，输出缺字段不能填0。

```sh
# $PID 必须是已核验的目标；$LABEL 如 E1-A-01。
ps -p "$PID" -o pid=,comm= > "$EVIDENCE/$LABEL-process.txt"
top -pid "$PID" -l 61 -s 1 -stats pid,cpu,idlew,power,mem \
  > "$EVIDENCE/$LABEL-top.txt"
# sample单独采，不与top的能耗窗口叠加，避免采样器污染主测量。
sample "$PID" 10 -file "$EVIDENCE/$LABEL-sample.txt"
```

不要把top的power相对指标写成瓦数。需要绝对能量、系统唤醒或多进程数据时，用该Mac上 `powermetrics --help` / Instruments模板确认可用字段；缺少相关字段就写未测，不猜sampler名，也不为记录而自动sudo。CLI、语音和helper应同时登记各PID，不能只量App掩盖迁移到子进程的能耗。

## 4. 结果格式和接受规则

`baseline/energy-template.csv`是一行一个测量窗口。单位固定：CPU为top单核百分数，idlew为原始top字段（保存系统对该字段的口径），内存为MiB；均保留原始文件。列出每轮中位数、p95和完整值，不只截一张活动监视器图。

推荐统计规则：先比较各配对样本，再报告所有样本。三轮同方向变差或超出基准重复样本自身范围的回退，交主模型阻断合并；不能用“低于1%”这种未经约定的绝对值代替稳定版对照。极小差异且噪声范围重叠，标“不确定，需重复”，不得写成省电已证实。任何空闲连续60Hz、锁屏还采无关音视频、关闭后回调不停止，直接失败，不等待平均能耗掩盖。

本交付包的 `VALIDATION.txt` 只记录实际运行的Linux编译与测试；上述Mac构建、真实网络播放/助手请求、音频、输入、锁屏和能耗表都未填成功值。
