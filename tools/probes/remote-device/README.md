# iPhone 原生 Remote 隔离接收器

显式启动、最长120秒的实验接收器。用于验证发现→真实配对→PairVerify→完整会话及输入类别，**不驱动窗口、助手、音量或任何系统动作**。完整源码差异和安全裁决见 [remote-atv-audit.md](remote-atv-audit.md)。

```sh
bash tools/probes/remote-device/run.sh --build-only
.build/remote-device-probe/RemoteDeviceProbe --self-test
# 仅由主代理协调真实设备阶段执行：
.build/remote-device-probe/RemoteDeviceProbe --serve 120 --discovery-profile atv-core
```

默认不加 `--discovery-profile atv-core` 时仅广播旧 Companion 实验 profile。atv-core 模式按固定源码同时宣告 Companion、MRP、AirPlay，并关联本次临时身份。MRP/AirPlay连接立即关闭并记录 `unsupported`；并非媒体接收器。三项listener均ready后显示一次随机四位PIN，有效60秒，名称 `WindowShade Remote Probe`。120秒自动关闭全部资源；启动失败也统一清理。

iPhone与Mac同一局域网，在控制中心 Apple TV 遥控器选择该名称；若出现PIN输入框，输入终端本次PIN。用户手机观察与服务端 `verified`/认证类别日志需分别记录，不能将手机显示“连接”或本机DNS-SD解析成功当作输入验收。

每次进程创建新身份，真实 `WS2PeerRepository` 使用内存storage，不读取或写入Keychain。复用生产SRP、PairSetup、PairVerify、AEAD、OPACK及有界TCP。允许尚未验证的PV一次回退到当前有效PIN的PairSetup；M6后同socket必须fresh PairVerify，不继承配对密钥作为输入认证。generation先失效再销毁旧通道，旧回调不能关闭新握手。已verified后禁止重启配对/验证。

协议层显式启用 `appleRemote` 信封模式，默认生产strict未改变。统一handler完成重复systemInfo、独立TVRC/touch/session初始化、别名SID、订阅及初始状态、查询和HID计数。主动事件均绑定最新已验证消息、限额及同一连接。停止后HID不能自行复活；再次明确初始化才恢复。仅本隔离probe启用固定atv源码的未知方法fallback：已验证request回空_rT0、event忽略，两者均不投递到profile或动作入口；_launchApp也只获协议层应答，不执行。默认生产strict仍拒绝未知方法。这个应答不表示该方法已实现。

媒体能力flags为0，应用表为空，文本输入关闭。`_mcc`/`MediaControlCommand`仅维护虚拟音量状态（初始0.5、未静音），支持5读取、6更新和12字幕关闭；不读写Mac音量。`ready`明确输出 `simulatedMediaState:true`。只记录方法类别、次数及失败阶段，不记录按键值、坐标、文本、原始包或密钥。OPACK未知标签错误仅含标签和偏移。

## 离线证据

`--self-test` 不开socket，检查profile语义、发现身份派生和统一资源清理。`--wire-test-json` 为显式固定PIN的无网络测试入口，与真实socket共享握手及分派代码。

```sh
PYTHONPATH=/tmp/windowshade-srp-research/srptools:/tmp/windowshade-srp-research/python-deps \
  python3 tools/probes/remote-device/handshake-interop.py \
  --bridge .build/remote-device-probe/RemoteDeviceProbe
PYTHONPATH=/tmp/windowshade-srp-research/srptools:/tmp/windowshade-srp-research/python-deps \
  python3 tools/probes/remote-device/session-interop.py \
  --bridge .build/remote-device-probe/RemoteDeviceProbe
```

依赖已有固定srptools1.0.1、six1.17.0、cryptography50.0.1。独立Python真实客户端完成SRP/签名验证，并逐个校验完整多包应答、主动事件、内容、顺序及双向nonce。覆盖canonical与model/缺省两条初始化流程，订阅注册/注销/去重、17次请求型interest、所有只读查询、虚拟媒体更新、HID请求和事件、停止及恢复；负例包括错误签名、过期PIN、SetupK输入、重复回退、认证后重启、重放、错误nonce布局、非法主字段、SID冲突/旧SID、错误服务和订阅超限；另验证未知request空应答、未知event静默且不进入profile，后续已知HID仍可处理。

此前Python单包oracle错误使用HAP nonce，counter0没暴露问题；现按固定上游与生产Companion格式修为 `LE64(counter)+zero4`。完整多包测试明确在非零counter拒绝旧布局，避免自证。

OPACK的UUID/rawTime/F字典补全有固定来源支持，但先前实机unsupportedTag未记录具体标签，不能声称已经捕获它。固定参考向量与来源摘要保存在 `tests/fixtures/opack-reference-vectors.json`。本工具仍依赖本机OpenSSL3，仅供隔离验证，不能直接分发为App功能。

第六轮真机已通过systemInfo、sessionStart、TVRC、查询及订阅，之后被未知方法拒绝。根据完整固定源码的fallback行为，本probe改为验证后的协议级兼容应答；未知名称最长128字节、compat连接消息最多2000，继续受AEAD、帧及期限限制。关闭日志只输出 `unhandledMethods` 数量，不输出未知方法名或载荷。
