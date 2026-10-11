# iPhone 原生 Remote 隔离接收器

显式启动、最长120秒的实验接收器。用于验证发现→真实配对→PairVerify→完整会话及输入类别，**不驱动窗口、助手、音量或任何系统动作**。完整源码差异和安全裁决见 [remote-atv-audit.md](remote-atv-audit.md)。

```sh
bash tools/probes/remote-device/run.sh --build-only
.build/remote-device-probe/RemoteDeviceProbe --self-test
# 仅由主代理协调真实设备阶段执行：
.build/remote-device-probe/RemoteDeviceProbe --serve 120 --discovery-profile atv-core
```

默认不加 `--discovery-profile atv-core` 时仅广播旧 Companion 实验 profile。atv-core 模式按固定源码同时宣告 Companion、MRP、AirPlay，并关联本次临时身份。MRP/AirPlay连接立即关闭并记录 `unsupported`；并非媒体接收器。三项listener均ready后显示一次随机四位PIN，有效60秒，名称 `WindowShade Remote Probe`。PIN 只在 stderr 为交互终端时显示，`ready` JSON 不包含 PIN；若没有私有显示终端，记录 `pinDisplay:unavailable`，不把 PIN 写进报告。120秒自动关闭全部资源；启动失败也统一清理。

iPhone与Mac同一局域网，在控制中心 Apple TV 遥控器选择该名称；若出现PIN输入框，输入终端本次PIN。用户手机观察与服务端 `verified`/认证类别日志需分别记录，不能将手机显示“连接”或本机DNS-SD解析成功当作输入验收。

每次进程创建新身份，真实 `WS2PeerRepository` 使用内存storage，不读取或写入Keychain。复用生产SRP、PairSetup、PairVerify、AEAD、OPACK及有界TCP。允许尚未验证的PV一次回退到当前有效PIN的PairSetup；探针构建会在旧 PV 被替换前保留一个 `initial-pv-main` 候选。完整PS成功并取得同连接的enrollment receipt后，候选可以处理限时的兼容会话并应答，始终为 `identityBound:false`，不能构造生产Message或VerifiedSession。首次记录须在M6后10秒内到达，整轮最长120秒；每次收发继续核对peer/key/revision是否有效。generation先失效再销毁旧通道，旧回调不能关闭新握手。fresh PV重新验签后才进入verified，并使用新密钥与计数器；此前兼容输入不会追认为认证输入。已verified后禁止重启配对/验证。

探针独立解析appleRemote信封，默认生产strict未改变。统一handler完成重复systemInfo、独立TVRC/touch/session初始化、别名SID、订阅及初始状态、查询和有效HID分类。一个输入产生的response与events按顺序整批准入有界队列；容量不足则关闭，不重试已加密记录。停止后HID不能自行复活；再次明确初始化才恢复。仅本隔离probe启用固定atv源码的未知方法fallback：带事务号时回空_rT0，无事务号时静默，均不进入已知功能或动作入口；_launchApp也不执行。这个应答不表示该方法已实现。

媒体能力flags为0，应用表为空，文本输入关闭。`_mcc`/`MediaControlCommand`仅维护虚拟音量状态（初始0.5、未静音），支持5读取、6更新和12字幕关闭；不读写Mac音量。`ready`明确输出 `simulatedMediaState:true`。只记录方法类别、次数及失败阶段，不记录按键值、坐标、文本、原始包或密钥。OPACK未知标签错误仅含标签和偏移。

每条真实 socket 连接都会锁存一次安全的 `connection-closed` 摘要：连接编号、`closeCause`、阶段、单调时钟时间、最后帧类型/长度、队列项/字节、高水位、slice/完整record完成数和最后发送状态。首因只记录一次；后续 Network cancel 不会覆盖它。EOF立即关闭，未发完内容保留在关闭快照里。`content-processed` 只表示本地发送完成，不表示手机已消费。兼容与认证有效输入分别累计；空HID、错误字段、未知code/phase或不完整touch轨迹不能计为有效输入。fresh PV重置profile分类，因此关闭摘要中的 `inputCategories` 只反映当前profile，两个InputCount则保留两阶段总量。

## 离线证据

`--self-test` 不开socket，检查profile语义、发现身份派生和统一资源清理。`--wire-test-json` 为显式固定PIN的无网络测试入口，与真实socket共享握手及分派代码。

默认配置固定为 `current/默认 envelope/compact identifier/无 M6 描述`。各入口可以在进程启动时显式选择一个对照组合，不能在握手中途更换：

```sh
.build/remote-device-probe/RemoteDeviceProbe --wire-test-json \
  --reply-policy upstream-reference --pairing-envelope type1 \
  --identifier-form hyphenated --m6-metadata probe-label
```

`upstream-reference` 按固定上游逐方法选择回复：已知方法除 `_interest` 外均应答，包括HID event；current按request应答。未知方法在两种策略下均按事务号决定。`type1` 只在 M2 外层加 `_pwTy=1`，`probe-label` 是 M6 AEAD 内TLV17的OPACK描述字典，`hyphenated` 只改变本次临时认证标识的字节表示。它们都不是账号、设备证明或授权材料。对应检查是 `test-profile-values.py`、`configuration-interop.py` 与 `reply-policy-interop.py`。

```sh
PYTHONPATH=/tmp/windowshade-srp-research/srptools:/tmp/windowshade-srp-research/python-deps \
  python3 tools/probes/remote-device/handshake-interop.py \
  --bridge .build/remote-device-probe/RemoteDeviceProbe
PYTHONPATH=/tmp/windowshade-srp-research/srptools:/tmp/windowshade-srp-research/python-deps \
  python3 tools/probes/remote-device/session-interop.py \
  --bridge .build/remote-device-probe/RemoteDeviceProbe
```

依赖已有固定srptools1.0.1、six1.17.0、cryptography50.0.1。独立Python客户端完成SRP/签名验证，并逐个校验完整多包应答、主动事件、内容、顺序及双向nonce。覆盖canonical与model/缺省两条初始化流程，订阅注册/注销/去重、17次请求型interest、只读查询、虚拟媒体更新、HID请求和事件、停止及恢复；负例包括错误签名、过期PIN、SetupK输入、重复回退、认证后重启、重放、错误nonce布局、非法主字段、SID冲突/旧SID、错误服务和订阅超限。

`candidate-interop.py` 验证初始PV兼容通道、超过256条连续记录、fresh PV切换、撤销/过期/错key/重放/发送失败。`socket-interop.py` 和 `pipelined-interop.py` 通过 `--loopback-test` 运行真实127.0.0.1 TCP：固定合成PIN、单连接30秒、不广播Bonjour；覆盖完整成功流程、M5与首记录合批、PS未完成的提前输入、错误key关闭诊断。它们均不是手机测试。

编译自动生成 `.build/remote-device-probe/build-manifest.json`，包含实际27个构建输入的前后SHA与二进制SHA。真机前用 `python3 tools/probes/remote-device/build-manifest.py check` 核对，不在PIN窗口编译。2026-10-08执行记录见 [本轮交接](../../../docs/handoff/ws2-reuse-2026-10-08/README.md)。

此前Python单包oracle错误使用HAP nonce，counter0没暴露问题；现按固定上游与生产Companion格式修为 `LE64(counter)+zero4`。完整多包测试明确在非零counter拒绝旧布局，避免自证。

OPACK的UUID/rawTime/F字典补全有固定来源支持，但先前实机unsupportedTag未记录具体标签，不能声称已经捕获它。固定参考向量与来源摘要保存在 `tests/fixtures/opack-reference-vectors.json`。本工具仍依赖本机OpenSSL3，仅供隔离验证，不能直接分发为App功能。

第六轮真机已通过systemInfo、sessionStart、TVRC、查询及订阅，之后被未知方法拒绝。根据完整固定源码的fallback行为，本probe改为验证后的协议级兼容应答；未知名称最长128字节、compat连接消息最多2000，继续受AEAD、帧及期限限制。关闭日志只输出 `unhandledMethods` 数量，不输出未知方法名或载荷。

2026-10-08第10轮真机已进入可操作界面，fresh PV认证通道收到235条有效输入事件，120秒窗口正常结束。initial-PV-main在首连接未匹配；成功不能归因到该候选。完整手机观察、按连接日志与产物身份见[本轮执行记录](../../../docs/handoff/ws2-reuse-2026-10-08/README.md)。
