# 遥控接收：已落地的协议链与剩余缺口

2026-10-07。此次新增的是可以从真实 TCP 接收、验签、解密并解释受限 OPACK 的链路，**原生 iPhone Remote → 指挥真实助手的完整目标仍未完成**。没有更改 Runtime、日常开关、配对账户、授权账或用户配置，也没有发真实助手任务。

## 代码与入口

- `prototype/Core/WS2OPACK.swift`：原创受限格式实现。整帧 64 KiB，单字符串/字节串 16 KiB，深度 16、总节点 4096、每容器 128 项；拒绝重复键、非法 UTF-8、未知标签、无终止符、无效引用和尾随字节。引用表只在单消息内存在，支持标量引用、UUID、原始时间位值及F0–FF字典标签；容器引用及超出本地预算的宽引用仍不纳入。未知标签诊断只含标签和偏移，不记录载荷。
- `prototype/Support/WS2CompanionChannel.swift`：将现有 Pair-Verify 接到外层帧。只接受 `5/M1 → 6/M3 → 8/加密事件`，M2/M4 外层为 type 6；已有客户端公钥签名验证保留。M4 未成功排入发送队列，不进入 active；任何错误、撤销、重放或超时关闭并销毁会话密钥。只投递调用者明确列入允许名单的事件；不产生授权票据。
- `WS2CompanionChannel.attach`：真实 accepted `NWConnection` 的现有 transport 回调装配；延续 10 秒绝对握手期限，active 最长到通道创建后的 120 秒，任意字节不续期。此短期限用于当前隔离接收链，不声称已经实现长期 Remote 会话。
- `tools/probes/companion-channel/run.sh --loopback-self-test`：显式运行真实本机回环 listener 与独立合成客户端。普通 App 不监听或宣告任何新服务。

## 来源与许可

采用 pyatv **0.18.0 / `b277a4c8222ecdcbaab8a24e3e713ca44765adb4`** 的公开格式观察补齐计划中缺失的 OPACK 接线：

- [OPACK 格式源码](https://github.com/postlund/pyatv/blob/b277a4c8222ecdcbaab8a24e3e713ca44765adb4/pyatv/support/opack.py)：标签、长度、引用和容器格式。
- [握手封装](https://github.com/postlund/pyatv/blob/b277a4c8222ecdcbaab8a24e3e713ca44765adb4/pyatv/protocols/companion/auth.py)、[帧类型](https://github.com/postlund/pyatv/blob/b277a4c8222ecdcbaab8a24e3e713ca44765adb4/pyatv/protocols/companion/connection.py)：`_pd`、`_auTy=4`、PV_Start/PV_Next 和加密消息外层。
- [MIT 许可，Copyright (c) 2020 Pierre Ståhl](https://github.com/postlund/pyatv/blob/b277a4c8222ecdcbaab8a24e3e713ca44765adb4/LICENSE.md)。没有将其实现源码或依赖并入 App；Swift 实现原创。仅在临时目录运行固定版本参考编码器，生成并核验 13 个独立格式向量；来源及参考文件 SHA-256 随 `tests/fixtures/opack-reference-vectors.json` 保存。

参考实现的宽引用编码/解码宽度存在不一致，容器引用也未形成可信对照，因此这里只接受最多两字节索引、只登记标量，不宣称全 OPACK 兼容。不拷 atv-core 的认证结论，也没有用网络连通替代客户端签名。

## 验收

执行 `bash tests/run-companion-channel-tests.sh`，Swift 6 严格并发、warnings-as-errors 编译。覆盖独立参考向量、引用作用域、长字节串/UTF-8、容器和深度预算、重复键、每个截断位置；协议覆盖错签名、撤销、重放、未知方法、断连、握手前/后明文、M2/M4 发送失败、握手超时、会话超时、认证后非法 OPACK。测试不打开网络。

真实回环自测使用独立客户端验证服务端签名，再完成服务端客户端验签、加密事件和重放拒绝。初次受沙箱本地端口限制返回 `Operation not permitted`；使用同一二进制在获准回环环境运行后通过。没有把被限制的那次记为通过，也没有使用假 socket 替代。

实际终端输出及当前源码摘要见 `remote-evidence.json`。未运行整 App 构建（由主模型统一执行），未使用真 iPhone，未测原生发现或首次 PIN 配对。

## 下一步必须补齐

1. 现有 `WS2PairSetupServer`/SRP 工厂、Keychain 本地初始化/撤销/Touch ID 配对批准与唯一 listener owner 仍需接合；此次只验证**已登记合成公钥的 Pair-Verify**。
2. Bonjour profile、`_systemInfo`/session 握手、请求应答与 `_hidC`/`_hidT` 原生事件实测缺失。当前只解析事件信封，未知方法失败关闭，不能拿 `_fixture` 作兼容证据。
3. 后续同轮已完成指挥页到唯一 owned 控制器的会话选择、采用/发送、补充/停止及回执接线，见 [conductor.md](conductor.md)。原生 Remote 输入到这些操作接口仍待接收器串接；没有把合成加密事件直接转成授权。
4. 跨目标旧输入、原生按键按下/松开、睡眠/锁屏/撤销与 listener 全连接关闭，以及人机 p95 和能耗，需要上述生产接线后验收。当前没有借此放开授权门槛。

## 完整会话复核后的生产边界

原生Remote现场两次已通过真实PairVerify，但分别被OPACK未知格式、消息信封结构拒绝。第五轮后暂停逐错真机重试，重新对照固定atv-core完整会话；最新实测见device-tests。

生产Channel默认仍为strict。隔离Remote接收器可显式选appleRemote，规范化有源码依据的顶层model方法别名、缺省空内容，以及缺少消息类型时按事务字段区分请求/事件；方法名按上游_i优先、model后备；兼容模式忽略有界的其它顶层元数据，不将它们接入授权或动作。错误主字段类型仍拒绝，默认strict模式仍拒绝未知方法和字段。隔离探针可显式启用与上游一致的无动作fallback：未知请求空应答、未知事件忽略，均不进入profile或动作回调；这不表示实现了未知功能。兼容模式整连接最多2000条消息。方法名和客户端元数据从不成为认证身份。

新增服务器状态事件接口绑定本连接最新一条已验证消息，事件名有独立允许名单，每次触发最多32条、整连接最多2048条；撤销、过期、关闭、跨连接、过旧触发和发送失败均拒绝。应答仍必须匹配本连接未消费的事务，只能发一次。完整会话与查询由隔离工具profile负责，不直接触发App动作。

复核发现旧独立Python握手客户端把主通道nonce写成HAP排列；第0包全零使错误未被此前6个场景发现。生产WS2CompanionCounter的LE64后接4零字节与固定atv-core一致。新的验收必须覆盖非零计数器上的多次请求、应答、主动推送，而不能只用首包成功证明会话兼容。
