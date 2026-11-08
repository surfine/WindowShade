# 交给 GPT-6 Pro：解决 iPhone 原生遥控器连接失败

请直接接手下面的问题。你可以访问 GitHub 时，先检出指定分支并阅读实际文件；如果你的环境不能读仓库或运行 macOS 代码，请明确说出缺少的访问能力，基于现有证据给出可执行的定位/修复方案，不要声称已经运行测试。

仓库：https://github.com/surfine/WindowShade
分支：`codex/ws2-remote-gpt6-handoff-20261007`
本说明：`docs/handoff/ws2-reuse-2026-10-07/GPT-6-PRO-PROMPT.md`
日期：2026-10-07。先记录你实际检出的 HEAD；不要从 main 或老交接包顺次套补丁。此前代码基线是 `f6e601f`，本分支是当前完整工作区快照，含此前已有的七个性能文件，未签名、未发布、未替换日用 App。根目录 `.statem/` 的旧任务记录不是本轮最新事实；以本说明、同目录 device-tests 和 evidence 为准。

## 要解决什么

WindowShade 是 macOS App。用户希望用 **iPhone 控制中心自带的 Apple TV 遥控器**连接 Mac 上的接收器，最终用于指挥助手；不安装手机配套 App。本轮先把独立接收器的真实发现、PIN 配对、会话建立与按键/触控输入跑通，再讨论产品接线。实验接收器只计数，没有系统、窗口、音量或助手动作出口。

当前事实是：**真实手机仍连接失败，不能把“完成”“完整兼容”作为前提。** 编译、独立密码学和多包测试通过，但真实输入是零。前任曾逐个补报错、反复让用户输 PIN，用户已经明确不接受这种推进方式，要求重新完整审视 atv-core。请先把协议状态与证据对齐，找出可证伪的原因，再安排少量有明确判据的真机测试。

## 先读这些文件

1. `tools/probes/remote-device/remote-atv-audit.md`：固定上游源码与本地取舍；这是前任的裁决记录，不是不可推翻的协议规范。
2. `tools/probes/remote-device/Handshake.swift`、`RemoteDeviceProbe.swift`：真实连接生命周期、握手切换、拒绝/关闭和限时广播。
3. `prototype/Support/WS2CompanionCrypto.swift`、`WS2PairSetupCrypto.swift`、`WS2PairSetupServer.swift`、`WS2CompanionChannel.swift`、`WS2CompanionPairSetupChannel.swift`；以及 `prototype/Core/WS2CompanionFrame.swift`、`WS2OPACK.swift`。
4. `tools/probes/remote-device/SessionProfile.swift`、`WireTest.swift`、`handshake-interop.py`、`session-interop.py`、`wire-opack.py`：socket 与无网络测试共用 RemoteProfileHandler，但独立客户端构造的流程仍不等于实际 iPhone 流程。
5. 本目录 `device-tests.json` / `device-tests.md` 与 `evidence/` 中第五至第八轮相关日志；最新是 `evidence/iphone-remote-device-final-retry.log`。更早认证/解析进展见同目录其它原始日志。

需要改产品时再读取项目要求的 `docs/blueprint.md`、`docs/handoff/FINAL-HANDOFF.md` 和设计/文案规则；不要为隔离协议问题顺便重写 UI 或其它功能。

## 当前结构及已经做过的修复

- 接收器在 `tools/probes/remote-device/`，使用真实原生 SRP、Ed25519、X25519、ChaCha20-Poly1305；SRP 后端是工具用 OpenSSL，不是生产发行方案。内存 peer repository；每次进程启动身份/PIN 都重新生成，没有 Keychain 持久化。
- 可选 `atv-core` 发现配置按固定源码同时广播 Companion、MRP、AirPlay。后两者仅接受后关闭，不实现媒体协议；最后几轮的 unsupportedConnections 都是 0。
- 已允许同 socket 的一次未认证 PairVerify→PairSetup 回退；替换前增加 generation，防旧回调关闭新握手。M6 后允许 fresh PairVerify；当前实现仍拒绝 enrolled 阶段直接到来的 encrypted frame8。
- OPACK 支持 UUID、原始时间、F 系列字典标签和有界标量引用；未知标签诊断包含 tag/offset。保留帧、节点、深度、容器、UTF-8、重复键等边界；不宣称支持所有 OPACK 变体。
- 生产 Channel 默认 strict；隔离工具显式 appleRemote 模式：`_i` 优先，缺失时取 `model`；缺 `_c` 为空字典；缺 `_t` 时按 `_x` 推断请求/事件；其它有界顶层元数据不参与授权。
- 会话 profile 已实现 systemInfo 空应答和双状态推送、SID 别名、TVRC/touch 独立初始化、订阅初始状态/注销、常见只读查询、HID 请求/事件、stop 后须重新初始化。事件发送绑定当前已验证连接的最新消息，并有数量上限。
- 初期“未知方法立即断连”与上游不一致。最终版仅在显式探针模式，对未知请求回空应答、未知事件忽略，**不调用 deliver/profile/动作入口**，只记录 unhandledMethods 数量；默认生产仍拒绝。它不表示实现了未知功能。
- 媒体状态仅是模拟协议状态，flags=0，不读写系统音量。没有实际执行 `_launchApp` 或 HID 对应动作。

## 真机证据：不要抹掉失败

| 轮次 | 服务端证据 | 手机观察 |
| --- | --- | --- |
| 第四轮 | 配对成功，随后7次 PairVerify 成功；frame8 OPACK unsupportedTag | 无法连接 |
| 第五轮 | UUID/time/F 格式补齐后不再报 unsupportedTag；7次验证后信封 malformed | 无法连接 |
| 第六轮 | 5连接、4次验证；3次完成 systemInfo/sessionStart/TVRC、状态查询和订阅，随后未知方法被旧策略拒绝 | 仍无法连接 |
| 第七轮 | 最终未知方法 fallback 版，120秒0连接，0剩余 listener | 当轮没有收到有效现场反馈；不能据此判协议通过/失败 |
| **第八轮，最新** | **2连接。第一连接 PV→PS→enrolled，随后 frame8 因 state 被拒绝；第二连接 PairVerify 成功，仅 `_systemInfo` 一条，随后关闭。无 sessionStart、TVRC、HID，unhandledMethods=0，退出0 listener** | **出现 PIN 框，但连接失败；重新选择后仍失败** |

最新接收器二进制 SHA-256：`63449b6f8f99ff1eab986e1f14ef39366d236849d2accdb856251d187647b2b4`。二进制不入库；这个值只标识本机该次实测。脱敏原始日志已入库，`evidence/manifest.json` 给出摘要。当前所有测试服务均已关闭，旧 PIN 均已失效。

## 优先审查的疑点（不是已证实根因）

1. **首次配对到控制通道的衔接。** 上游在 PV-M1 后安装 cipher；本地遇 PS 回退会销毁原 verifier/相关会话状态，并要求 PS 后再 fresh PV。真实手机在 M6 后立刻发送 frame8。请追踪该包可能对应的密钥来源、计数器和阶段：初始 PV 派生状态、SRP 后的控制状态还是其它机制。现有证据没有解密鉴别该包，不能认定它使用“Setup 密钥”。
2. **不要把前任的实现选择当成用户硬要求。** “必须 fresh PV”是当前安全设计，是否与合法协议路径等价需要证明；不能仅为了维持旧测试而坚持，也不能直接删验签。固定 atv-core 的 PV-M3 根本没有验证客户端签名，其直接可用不代表可安全接真实动作。应提出有完整身份/密钥绑定依据的实现；若只做隔离兼容对照，必须与生产授权明确隔离，不把未验证流量标成认证输入。
3. **第二连接为何关闭。** 当前 connection-closed 日志不能区分客户端 FIN、传输错误、期限、owner 主动取消。第八轮只有 systemInfo，是否为后台探测、手机是否又开了真正遥控连接，均未知。上游以事务高位推断后台探测仅是其观察，不能直接当我们这轮的事实。
4. **M2/M6 附加元数据。** 固定上游有 `_pwTy`、TLV27、M6 TLV17 等信息，本地不完全一致。配对和后续验证确实已成功，但 UI 接纳条件是否仍依赖这些字段，需要来源或差分实验证据。
5. **测试覆盖的盲区。** 现有独立客户端主动遵循“PS后 fresh PV”，所以它不能证明这就是手机的实际流程。前期另有 nonce oracle 错误：把 HAP 的 zero4+LE64 用在 Companion 上；第0包全零掩盖了错误。现已按固定 crypto.rs 修成 LE64+zero4，并逐包验证非零计数器。不要重复只测首包的错误，也不要让测试只复述本地状态机。

请完整核对 atv-core 的发现→握手→初始化→查询/订阅→应答/推送→输入链。对于每个差异，分清“有线格式必需”“上游宽容行为”“上游安全缺陷”“本地额外限制”。不要只修一个报错便再次让用户试。若需新增诊断，仅记录阶段、帧类型、长度、脱敏字段类型、关闭原因、必要的时间关系或 AEAD 校验是否成功；不记录 PIN、密钥、真实身份或原始载荷。

## 固定上游原始来源

atv-core：`8a4ada29bb7cad31e0315c3387b277eb9ab8c988`
- https://github.com/corvofeng/atv-core/blob/8a4ada29bb7cad31e0315c3387b277eb9ab8c988/crates/atv-core/src/session.rs （特别是认证段、send_response/send_event、handle_control）
- https://github.com/corvofeng/atv-core/blob/8a4ada29bb7cad31e0315c3387b277eb9ab8c988/crates/atv-core/src/crypto.rs
- https://github.com/corvofeng/atv-core/blob/8a4ada29bb7cad31e0315c3387b277eb9ab8c988/crates/atv-core/src/server.rs
- 同提交的 opack.rs、identity.rs。

pyatv：`b277a4c8222ecdcbaab8a24e3e713ca44765adb4`，参照 `pyatv/support/opack.py` 与 `pyatv/protocols/companion/`。源码事实与本机结果优先于这份说明。atv-core Cargo 声明 MIT，但前任未在固定提交根目录找到 LICENSE；现有 Swift 为原创协议实现，不含 Rust 源码。不要未经核实整段搬入产品。

## 已有验收与复现

已通过但不能替代真机：51项工具离线检查；6个真实密码学场景；canonical/model-default两套各51条客户端记录、55条服务端加密记录；7个协议负例；未知 request/event 不进入处理器且之后已知 HID 正常；默认 strict/撤销/过期/重放/旧SID/发送失败等检查。完整 App `prototype/build.sh --check` 退出0，394主Swift源文件加guard，396份源文件与构建快照对照一致；有既有并发警告，未签名未启动。测试摘要与源码哈希见同目录 verification.json、evidence/。

在有 Xcode/Swift 6、OpenSSL 3 的 Mac 上，从仓库根目录运行：

```sh
bash tests/run-companion-channel-tests.sh
bash tools/probes/remote-device/run.sh --build-only
.build/remote-device-probe/RemoteDeviceProbe --self-test

# 独立 Python 客户端需要 srptools==1.0.1、six==1.17.0、cryptography。
# requirements-test.txt只固定了前两者；请在独立venv配置cryptography并记录实际版本。
python3 -m venv .build/remote-interop-venv
.build/remote-interop-venv/bin/pip install --require-hashes -r tools/probes/companion-pairing/requirements-test.txt
.build/remote-interop-venv/bin/pip install cryptography
.build/remote-interop-venv/bin/python tools/probes/remote-device/handshake-interop.py --bridge .build/remote-device-probe/RemoteDeviceProbe
.build/remote-interop-venv/bin/python tools/probes/remote-device/session-interop.py --bridge .build/remote-device-probe/RemoteDeviceProbe

# 仅在操作者已就绪时启动；每次新PIN60秒、服务120秒，结束必须核对0listener。
.build/remote-device-probe/RemoteDeviceProbe --serve 120 --discovery-profile atv-core
```

工具默认 OpenSSL 路径 `/opt/homebrew/opt/openssl@3`，其它环境设置 `WS_SRP_OPENSSL_PREFIX`。不要假设前任 `/tmp/windowshade-srp-research/` 的依赖仍存在。最终本机 App 编译曾用下列已安装 toolchain 名；其它机器先核对，不要照填不存在的版本：

```sh
TOOLCHAINS=com.apple.dt.toolchain.Metal.32023.921.5,com.apple.dt.toolchain.XcodeDefault bash prototype/build.sh --check
```

## 你需要交付的结果

请先给出带源码位置和原始日志依据的根因判断，明确证据缺口与可证伪实验。能运行代码时实施最小而完整的修复，并增加独立客户端对实际手机轨迹的验证。真机前将本机可查的初始化、查询、推送、加密计数与失败分支一次检查完；用户就绪后再开窗口，不让 PIN 在长篇解释或编译中失效。真机结果要同时具备手机观察、服务器阶段/输入计数、当前源码/二进制身份和清理证据。若仍失败，说明关闭的具体原因或尚缺哪一条观测，不再把“编译通过”作为收尾。

不要顺便改其它愿景功能，不签名发版、不替换日用App、不启动真实助手任务。这个分支同时保存相机共享、个人口令、蓝牙在场、指挥页、CarPlay实验和原有性能工作，目的是让快照可复现，不表示那些功能全部验收通过。DeepSeek仅承担早期盘点，余额不足后停止；后续由主模型和原生子代理实现并复核，最终真机失败责任不能被代理自报成功掩盖。
