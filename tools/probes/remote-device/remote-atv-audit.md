# 原生 Remote 接收器完整适配裁决

固定来源：atv-core `8a4ada29bb7cad31e0315c3387b277eb9ab8c988`，以 [session.rs](https://github.com/corvofeng/atv-core/blob/8a4ada29bb7cad31e0315c3387b277eb9ab8c988/crates/atv-core/src/session.rs)、[server.rs](https://github.com/corvofeng/atv-core/blob/8a4ada29bb7cad31e0315c3387b277eb9ab8c988/crates/atv-core/src/server.rs)、[crypto.rs](https://github.com/corvofeng/atv-core/blob/8a4ada29bb7cad31e0315c3387b277eb9ab8c988/crates/atv-core/src/crypto.rs) 为原始依据。Cargo 声明 MIT、固定仓库根 LICENSE 缺失；本工具为原创 Swift，未复制 Rust 源码。

前五轮实机逐步确认了发现、PIN 配对、PairVerify，以及已解密消息的解析边界，但没有形成可用完整会话。用户明确要求停止逐报错补丁；本次先核对完整服务端流程，再整体适配。下面的“采用”表示源码支持且主模型已裁决，不等于已经在用户手机验证。

| 来源位置 | 上游行为 | 本次裁决 |
|---|---|---|
| server:225–300 | 三种发现服务与跨服务身份派生 | 可选 atv-core profile；一次临时 UUID/MAC 关联全部 TXT。MRP/AirPlay 只接入即关闭，记录 unsupported，不提供假认证。 |
| session:572–582 | `_i` 优先、`model` 后备；缺 `_c` 为空 | 显式 appleRemote 模式采用；无行为顶层元数据仍受 OPACK 总预算限制且不用于授权。默认 strict 不变。 |
| session:569–582 | 不按 `_t` 分派 | 本地缺 `_t` 时有 `_x` 为请求、无 `_x` 为事件；显式非法类型继续拒绝。 |
| session:210–246 | 应答 `_t:3/_rT/_c`，事件 `_t:1/_i/_c`，可带 `_x` | 采用生产绑定应答/有界事件接口；事件只能响应本连接最新已验证消息，不绕过撤销/期限。 |
| session:774–809 | systemInfo 可重复，空应答，推两种电源状态 | 采用；探针状态3表示本接收器活跃，不是Mac显示器电源；主动状态不带事务号。 |
| session:584–610 | SID支持 `_sid`/`sid`，回复服务器 SID | 接受缺省服务和 SID；别名冲突/错误服务拒绝。同已验证连接可再次 start 更新SID，旧SID不能stop新会话。 |
| session:611–635 | TVRC独立建立会话，版本回显，推媒体能力 | 采用；缺省1.2，版本字符串有界；能力为0，不宣称控制系统音量。 |
| session:651–667 | touchStart返回`_i:1`，touchStop/Move/tiStop空应答 | 采用；touchStart可独立建立会话。 |
| session:668–708 | interest注册即推当前值 | 采用有界注册/注销及去重；支持五种已知事件，忽略未知订阅名。请求型interest先ack，避免积压事务。 |
| session:709–759 | 媒体/电源/Remote/NowPlaying/应用查询 | 采用只读查询；媒体flags0、NowPlaying空、应用空表且_rT2。 |
| session:726–733 | tiStart返回`_tiE:false` | 采用，明确无文本输入功能。 |
| session:646–661,823–906,953+ | HID应答及输入映射 | 请求/事件都接收，只统计类别，绝不执行映射、音量、窗口或助手动作。 |
| session:908–948 | MediaControlCommand/_mcc，5读音量/6写音量/12字幕 | 维护明确标记的虚拟协议状态，初始0.5/false，不读取或写入系统音量；其他命令拒绝。 |
| session:637–645 | sessionStop终止会话 | 可无字段；有SID必须匹配当前连接最新组合SID，有服务必须匹配。停止后HID不能自行复活，须真实初始化。 |
| session:761–773,811–819 | launch/未知方法可空应答 | 第六轮后主模型裁决：仅probe启用已验证request空_rT0、event忽略的fallback，不投递profile/action；未知方法及_launchApp不代表已实现。strict默认仍拒绝。 |
| session:490–565 | PV-M1就安装cipher、PV-M3未验签 | 不采用。继续真实双端签名、peer公钥、重放、撤销与期限检查；PairSetup本身不解锁输入。 |
| crypto:35–41 | 控制nonce为LE64 counter后补零至12字节 | 独立Python旧oracle误用HAP的zero4+LE64，counter0掩盖问题；现修复并用多包双向计数与错误布局负例验证。 |

工具统一以 `RemoteProfileHandler` 调用 `SessionProfile.Outcome` 并发出应答/事件。真实socket和无网络wire harness共享该路径，避免测试覆盖另一份分派器。所有资源仍有120秒总期限、60秒PIN窗口、8次Companion接入/2个并发连接，以及生产帧、消息和事件预算。媒体状态仅属实验会话，`ready.simulatedMediaState=true` 明示。

尚待真机：整套初始化是否完成、原生列表/连接状态与服务端认证事件是否一致、真实按键/触摸类别及持续输入。离线多包通过不能替代这些证据；也不表示产品已接入系统或助手动作。
