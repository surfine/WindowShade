# 给 Claude：WindowShade 原生 Remote 后续实现交接

日期：2026-10-08。用户最新要求：“算了，不等了，请你撰写一份 handoff 文档，把未竟事项交给 Claude 来实现。”本次交接停止 Codex 的继续实现；不再启动手机窗口。请接手现有代码，交付可检查的实现和证据，不再从头规划或重复做一轮交接材料。

## 先读结论，避免退回旧问题

**iPhone 控制中心自带的 Apple TV 遥控器已经在独立接收器上真机连通，并收到认证后的有效输入；它还没有成为主应用可用的遥控功能。**

第10轮用户确认“已进入，已按键和滑动”。第二条连接完成 fresh Pair-Verify，收到263条认证消息、235条有效输入事件：3次按下、3次松开、22次触控开始、185次移动、22次结束。120秒窗口结束，首因 `owner-stop`；发送队列清空，37个完整记录完成发送，进程退出0，OS级检查无残留监听。

第一条连接仍有未解问题：PV→PS→enrolled后的首frame8长5222字节，`initial-pv-main` 候选在rx0处 **AEAD失败**，随后 `protocol-reject`。手机自行新建第二条连接并成功。不要再说“手机必然使用initial-PV key”或“已证明使用Setup key”，不要把首frame8叫作HID。现有成功来自fresh PV认证路径，不能归因到单一修复。

第9轮是零连接，不评价协议成败。第10轮是用户明确要求重来后的同配置补样，不是严格控制变量实验。主应用最终 `prototype/build.sh --check` 退出0，但没有签名、安装、运行或发布这份主应用。

## 实际工作区，比旧交接包优先

- 本机目录：`/Users/aaron/Documents/WindowShade`。
- 分支：`codex/ws2-remote-gpt6-handoff-20261007`。
- 交接时HEAD：`4accf310d505041f5d4458e204c62e55e022a900`。
- **修复和新增测试大部分未提交，也未推送。只clone这个HEAD拿不到本轮成果。** 在本机以完整dirty工作区继续；若换机器，先取得包含新增文件的工作区副本和本目录证据，不能只拿Git diff或旧ZIP。
- 根 `.statem/` 的既有dirty记录不是本轮事实来源，不覆盖或清理。本轮记录在 `.build/luna-statem/`，已到 `handoff`；持久证据在本目录 `evidence/`。
- 真机二进制：`.build/remote-device-probe/RemoteDeviceProbe`；SHA256：`98e0efa4735430a97a24047fdebf92698b8d9dca5b6509798db8cb7efa6290fe`。
- 编译前后27个输入与二进制绑定见 [manifest](evidence/probe-build-manifest.json)。接手若已变动，以当前文件重验，不覆盖用户后来改动来“恢复”这个哈希。
- 第10轮配置：`current / default envelope / compact identifier / no M6 metadata`；发现参数 `--discovery-profile atv-core`。旧进程和PIN均已失效。

先执行只读盘点：

```sh
cd /Users/aaron/Documents/WindowShade
git status --short --branch
git rev-parse HEAD
git diff --check
python3 tools/probes/remote-device/build-manifest.py check
```

manifest失败仅表示输入或产物发生变化；查明差异并建立新基线，不reset、不checkout覆盖、不清理untracked。

## 最少阅读入口

1. [本轮结果](README.md)、[真机结果](evidence/live-10-result.json)、[真机原始日志](evidence/live-10.jsonl)、[清理证据](evidence/live-10-cleanup.json)。
2. [逐项矩阵](test-matrix.json)：`CHARACTERIZED`是部分覆盖或行为刻画，不能读成PASS；`NOT_APPLICABLE`不是必须补造的功能。
3. [探针README](../../../tools/probes/remote-device/README.md)及下表中的实际源码。
4. 产品整合前读 [blueprint](../../blueprint.md)、[总交接](../FINAL-HANDOFF.md)、[input-devices](../../input-devices.md)、[conductor-v2](../../conductor-v2.md)。总交接中的旧提交号、待验结论是历史，不覆盖本轮事实。
5. 做界面、文案时再读 [设计稿入口](../../design-drafts/README.md)、[copy-guide](../../copy-guide.md)，按“手边的每一样／指挥模式”对应稿实现，沿用现有宿主。

## 代码地图与已经做好的东西

路径以仓库根为准。

| 文件／目录 | 当前职责与接手注意 |
|---|---|
| `tools/probes/remote-device/Handshake.swift` | 隔离握手、generation、candidate激活、fresh PV、有效输入分级、整批应答。主代理实现的核心，不要另写第五套状态机 |
| `SessionProfile.swift` | 纯profile：逐方法完整response/events、SID、订阅、虚拟媒体状态、有效HID分类；无系统动作 |
| `RemoteDeviceProbe.swift` | 显式120秒owner、内存身份、Bonjour、最多8次接受／2条并发连接、关闭日志与PIN显示 |
| `ProbeConfiguration.swift` | 启动即冻结的策略、M2/M6和ID表示开关；不是生产授权能力 |
| `WireTest.swift`、`NativeLoopback.swift` | 可控时钟无网络入口、仅127.0.0.1真实TCP入口；固定PIN只属于合成测试 |
| `prototype/Support/WS2CompanionCrypto.swift` | 既有严格PV/VerifiedSession；`WS2_PROBE_DIAGNOSTICS`下才有candidate，不可把候选当生产会话 |
| `WS2PairSetupServer.swift`、`WS2CompanionPairSetupChannel.swift` | PS成功之后的同连接receipt；M2可选 `_pwTy=1`，默认不变 |
| `WS2PairSetupCrypto.swift` | 可选M6 TLV17描述，默认无；PS签名和AEAD保持校验 |
| `WS2CompanionTCPTransport.swift` | outcome整批准入、首因锁存、slice/record完成、高水位和期限；队列16项／262144字节，EOF立即关闭不排空 |
| `prototype/Support/WS2CompanionChannel.swift` | 既有生产严格Message/response/event绑定路径；本轮未替换这条生产通路 |
| `prototype/App/WS2InputController.swift`、`WS2InputPreferences.swift`、`WS2InputSettingsPane.swift` | 主应用输入整合的调查入口；须先读真实调用关系，不能因文件存在就算已接通 |
| `prototype/Core/WS2InputEligibility.swift`、`WS2DeviceInputGate.swift`、`WS2SemanticInputRouter.swift`、`RemoteInputRouter.swift`、`RemoteSessionGate.swift` | 复用现有资格、会话、语义输入入口，避免探针直接发系统事件 |

新增测试入口：`candidate-interop.py`、`configuration-interop.py`、`reply-policy-interop.py`、`test-profile-values.py`、`ProfileValueTests.swift`、`socket-interop.py`、`pipelined-interop.py`、`tests/CompanionTransportTests.swift`及其runner。`build-manifest.py`已接入探针构建脚本。

## 未竟事项：按这个顺序交代码

以下为接续实施顺序，区别于旧矩阵中所有建议的简单堆叠。**不要把研究第一连接的未知key当作一切产品化工作的前置条件；已验过的fresh PV路径应保住。**

### C1：让诊断本身有界，并补关键故障证据

`report()`当前在主线程同步写stdout。真机使用普通文件，尚未证明管道消费者阻塞时不会卡住接收与期限处理。为诊断实现有界输出策略，保留每连接首因与关键终态；超预算可以聚合/丢弃普通信息，但必须可观测，不能无界排队或无限重试。不要打印PIN、密钥、原始包、按键值、坐标或文本。

在现有测试上补最影响可靠性的缺口：

- `NET-09`：高频合法触控、慢／停读日志消费者、大量错误事件，证明内存和退出期限有界。
- `NET-07`：并发／总接受上限、辅助服务接入、拒绝后合法连接。当前incoming/denied只有聚合值，不等于逐次完整接入证据。
- `NET-02`：真正的原生RST，不能把注入NWError写成原生RST。
- `NET-04`：profile多输出加密与队列容量13+3／14+3边界贯通，检查不部分准入、不重用nonce。

验收：完整输出对照、单次关闭首因、输入资格、OS清理与当前源码／二进制绑定；通过后只因新变化重跑相关检查，不把几十项重复检查当进展。

### C2：整理产品可复用的严格会话与类型化输入桥

从成功路径提取必要的会话/profile能力，通过现有生产认证与输入资格接口接入。先交一个默认关闭、可明确打开与关闭的主应用接收生命周期，以及严格认证后的类型化输入观察入口；不要把整个实验CLI、固定PIN、loopback、候选兼容资格复制进App。

必须保持：

- 完整PS与fresh PV签名、peer key/revision/current检查；撤销即时阻止后续收发。
- `VerifiedSession`只来自严格验签。候选AEAD不能提供系统、窗口或助手操作资格，不能追认早期兼容输入。
- 明确启用、配对显示、取消、锁屏／切用户／睡眠／关闭功能、断连与资源清理走现有owner和输入gate。资格不能由名字、IP、systemInfo描述ID推断。
- 沿用已有peer存储与生命周期设计，调查后接线；不能直接把内存探针当持久配对成品，也不要未经设计迁移Keychain数据。
- 先核对 `WS2CompanionChannel.Message` 的构造与event绑定约束；profile输出不能绕过旧消息／跨连接／撤销检查。

验收：接入点有实际调用链和有意义的拒绝测试；默认关闭无监听；显式打开／关闭无残留；严格输入可到达App观察入口，未授权／候选输入绝不到达动作出口。完成这个小闭环再扩大，不先重做整套设置页。

### C3：接既有语义动作并做最小用户闭环

依据 `input-devices.md`、`conductor-v2.md` 和现有输入映射，选择已有资格规则覆盖的最小动作闭环，将已认证、有效的按钮／触控转换到现有语义路由。先完成实现、模拟消费者与回滚路径，再安排用户真机验收。

这一步是尚未完成的产品能力，**本轮235条输入不能替代其验收**。手机认证不等于对任意目标的一次性授权；不盲发回车，不借遥控输入绕过Touch ID或agent审批，不接未授权助手执行。设计确需用户选择时只问影响结果的决定，其余常规接线自行完成。真实运行主应用／替换日常App／产生外部动作的具体授权按当时任务确认，不继承一次120秒探针就绪为永久授权。

验收：至少一个用户能完成的动作闭环、可见反馈、取消／焦点变化／锁屏／断连后无残留动作，且原窗口与其他输入路径不退化。动作范围由既有产品规格决定，不能用虚拟音量或常量成功替代真实效果。

### C4：第一连接未知key——保留为独立研究项

当前证据只排除本次固定 `initial-pv-main/rx0/既有AAD` 假设，不证明某种替代key。先从固定来源和测试夹具形成可证伪假设，在离线完整客户端里验证，再决定是否值得新增真机诊断。

不得每包扫描key/nonce、回退counter或捕获持久化秘密。原始PV-M3在PS后补完、沿用key升级资格、同IP抢占均**未采用**，不因旧工单提过就实现。若没有新证据需要这些路径，保留NOT_APPLICABLE，不牺牲已通过fresh PV路径去迎合它们。

**2026-10-08 补（借鉴台账，见 [oss-borrowing-2026-10-08.md](../oss-borrowing-2026-10-08.md)）**：

- C4 仍无答案。atv-core（8a4ada2 `session.rs#L527-531`、`#L310-313`）在答 PV-M1 时就装 ClientEncrypt-main，counter 0、帧头当 AAD 解第一帧——正是我们已排除的 `initial-pv-main`；它解不开也直接断开，靠手机重连。PlayPort / DiPlay / LIVI 不碰 Companion 协议。
- 可直接用于 C2/C3 的事实（atv-core 无 LICENSE 文件，只把事实重写进我们的代码）：
  - 按键 `_hidC`：5 返回、6 确认、7 电视键、8/9 音量、10 Siri、14 播放 / 暂停、18 静音、19 电源（iOS 26/27 控制中心复用 18/19）；`_hBtS` 1 按下、2 松开，松开才算；电视键按住要保留按下阶段。
  - 触控 `_hidT`：`_tPh` 1 开始、4 结束、其余为移动；`_cx/_cy` 在 1000×1000；移动 <60 算点、≥150 算滑，按主轴判方向。不带时间戳，E1 采样率仍要自己记。
  - 连接：`_systemInfo` 的 `_x` 高位为后台探测，给 1 秒；普通 2.5 秒；验签后 3 秒不开会话就断——用于 C1 / NET-07 的名额回收。
  - 音量：生产路径通告 `MediaControlFlags` / `_mcF` 0x0100 才让 iPhone 音量键可用；静音时 GetVolume 返回 0。探针仍保持 0（`SessionProfile.swift:98-99,157`）。
- 不取：不验 M3、固定 PIN、UUID 派生私钥、同 IP 踢旧连接、播放键多击加 300 ms、电源键 `pmset displaysleepnow`（我们的电源是收工）。

### C5：剩余边界按改动风险补齐

[矩阵](test-matrix.json)保留具体缺口：原生SRP错误PIN／proof和表示边界、PV transcript分量替换、key/revision变更、跨连接candidate、期限两侧、错误AAD、counter耗尽、OPACK预算／重复键／非法引用、TLV重复／重排、元数据单变量。复用现有fixture和runner，优先补受本次改动影响的不变量；无需为填满旧清单强行添加无关功能或增加手机测试次数。

## 验证命令与证据边界

接手先检查已有证据哈希，不要无条件全部重跑。更改密码学、传输或profile后按风险选择：

```sh
bash tools/probes/remote-device/run.sh --build-only
.build/remote-device-probe/RemoteDeviceProbe --self-test
python3 tools/probes/remote-device/test-profile-values.py
bash tests/run-companion-channel-tests.sh
bash tests/run-companion-transport-tests.sh --controlled
.build/companion-transport/companion-transport --loopback
```

独立Python客户端使用现有本机依赖（路径可能在换机器后失效，先检查；不要把缺依赖写成产品失败）：

```sh
export PYTHONPATH=/tmp/windowshade-srp-research/srptools:/tmp/windowshade-srp-research/python-deps
python3 tools/probes/remote-device/handshake-interop.py --bridge .build/remote-device-probe/RemoteDeviceProbe
python3 tools/probes/remote-device/session-interop.py --bridge .build/remote-device-probe/RemoteDeviceProbe
python3 tools/probes/remote-device/candidate-interop.py .build/remote-device-probe/RemoteDeviceProbe
python3 tools/probes/remote-device/configuration-interop.py .build/remote-device-probe/RemoteDeviceProbe
python3 tools/probes/remote-device/reply-policy-interop.py .build/remote-device-probe/RemoteDeviceProbe
python3 tools/probes/remote-device/socket-interop.py .build/remote-device-probe/RemoteDeviceProbe
python3 tools/probes/remote-device/pipelined-interop.py .build/remote-device-probe/RemoteDeviceProbe
```

依赖版本为srptools1.0.1、six1.17.0、cryptography50.0.1；OpenSSL使用本机 `/opt/homebrew/opt/openssl@3`。loopback只绑定127.0.0.1，不广播。沙箱EPERM是执行权限问题，不能改成假socket测试来报通过。

共享代码改动后的主应用检查沿用：

```sh
TOOLCHAINS=com.apple.dt.toolchain.Metal.32023.921.5,com.apple.dt.toolchain.XcodeDefault bash prototype/build.sh --check
```

工具链标识是本机历史命令，不保证别台机器存在。保留 `-O -whole-module-optimization` 等原构建门槛，不为求绿删参数。完整App检查本轮耗时较长；提前完成，避免在用户手机就绪后才开始等待。探针必须预先编译、冻结，现场不改代码。此次主App后台构建与手机窗口重叠，不应当作以后现场流程的范例。

历史通过数与所有实际命令见 [checks.json](evidence/checks.json)及 [本轮结果](README.md)。PS固定向量中的SRP是known-key test double，不能据此声称真实错误PIN联调已经通过。

## 真机与交付规则

先完成能在本机完成的工作，给出具体、已冻结的待测结果，再协调手机就绪。**用户这次已经要求转交Claude，不自动沿用之前的就绪答复启动新窗口。** 每次新进程身份重建、PIN更新；不在持久日志或文档写PIN。

真机结果必须同时包含：手机观察、源／产物／配置、按连接的阶段与身份资格、有效输入分类、首个关闭原因、退出码和PID级清理。零连接只记缺样本。若仍失败，要给新增事实，不只是再申请一次PIN。

下一次交付应是实现文件、相关验证结果与仍存在的具体缺口。提交／推送／签名／发版未在本次交接中执行或授权；不覆盖当前dirty工作区，不把用户根 `.statem/` 记录混入自己的提交。StateM如用自定义state目录，runbook放在同目录，避免command门禁按旧spec父目录读错receipt；状态转移仍只用 `statem goto`。

本轮核心密码学、整合和最终验收由Codex主代理负责；原生协作完成profile矩阵、transport及TCP客户端，经主代理实际验收。DeepSeek此前余额不足，本轮未调用；这些检查不能归功于未执行的委派。

## 全项目未竟事项的边界

此文细化的是当前Remote工作线，不能把它当作WindowShade 2七条线或1.0.16发版全部完成。若Claude接手整个项目，沿用 [blueprint](../../blueprint.md)和 [LANDING.md的T1–T13](../gpt6-review-2026-10-06/LANDING.md)，核对现有ledger后再推进，不另外发明一份完成率。

历史发布裁定将CarPlay、指挥模式、全设备电量、系统／刷脸解锁等移出1.0.16，不能因遥控探针通过又塞回该版本。本轮未重新审计那些产品线的全部源码或发布状态。正式发布走既有Developer ID＋公证、真实升级／坏包拒收／恢复的独立验收；发版前同步README中英文、官网及中文页，运行 `npm run site:check`。具体缺口以当前ledger和可核对证据为准，不能把2026-10-06的历史数字冒充最新事实。
