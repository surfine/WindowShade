# 第一轮待确认问题的回答

本份回答区分三种材料：上传的 Mac 采集记录、上传的源码/协议 Schema、这次 Linux 实跑。Mac 记录来自交接方，未由本轮重新采集。Schema 的字段存在不代表通道、信任、沙盒或具体设备已经通过。

## 已有结论

|第一轮问题|目前结论|依据与实施影响|
|---|---|---|
|R08 构建是否能在执行环境跑|交接方的 Mac Seatbelt 环境有 SDK、Sparkle；主模型可安排 `--check`。本轮 Linux 没有它们|`docs/handoff/chatgpt-review-1-verdict.md` 的 R08；`mac-facts-2026-10-03.md:4–13,16–38`。实际脚本还进行 Metal 编译和优化链接，不称仅类型检查。命令见 BuildBaseline|
|R09 版本与最低目标|Mac 采集值为 macOS27.0/26A428、Swift6.4、Xcode27.0/27A266a。源码部署目标仍为14|`mac-facts:4–13` 与 `prototype/build.sh:135–149`。新符号在27存在不证明14存在。纯逻辑本轮在 Swift6.2.1 Linux 跑过|
|R10 派工基线|主模型判定文档已经进 main；DeepSeek 不提交|verdict 的 R10。此处只验证上传字节，不替交接方证明实时Git历史。新代码和快照哈希交给主模型审定|
|R05 D5方向|采用 Swift；旧 Rust 指令作废|verdict 的 R05。Swift 客户端/协议零件不证明已存在可用服务端；D5 探针仍需做|
|R06 代码许可|相关 itsytv-core 文件覆盖许可仍未知，只可独立实现|verdict 的 R06。本份没有复制该项目代码。许可判断不从 README 链接、项目名称或分发形式推导|
|R15 私有触控符号|14个 dlsym 符号在采集机器存在；没有证实结构体 ABI 和回调生命期|`mac-facts:84–100`。MTDeviceRef、MTTouch、MTFrameCallbackFunction 是类型，不拿它们作 dlsym。I2-ABI 仍阻止接真实内存|
|R20 DualSense属性|头文件使用 leftTrigger/rightTrigger；setModeWeapon 与 setModeOff 可按头文件实现；不用 adaptiveTriggers|`mac-facts:40–81`。shouldMonitorBackgroundEvents 受进程统一管理；后台默认关闭的 SDK 注释已采集。扳机和游戏让位仍用 I8-PAD 真机验收|
|R24/25 hooks能力|本机 Codex0.153.0 有相关命令和 trust 帮助；Claude Code2.1.283 帮助含 hook 开关|`mac-facts:102–145`。只证明帮助暴露这些选项，不证明 hook 配置形状/事件/退出行为完全同构。不能加 bypass 选项省去授权|
|R25/27 现有配置|指定 ~/.codex/hooks.json 不存在，采集的 Claude settings 无 hooks；TOML还有历史 hook state|`mac-facts:147–155`。不推导所有项目层都无 hook，也不删除历史 state；真正安装仍需即时扫描、diff和指纹核对|
|R31 App Server字段|已有固定版本的完整 JSON Schema；按下面字段表施工，不按网页猜测|`docs/handoff/reference/codex-app-server-schema-0.153.0/`。`validation/schema-evidence.json`保存每个结论的精确JSON pointer、定位行和SHA256|
|R02 无刷脸的回来流程|单靠手机回来是否能开仍待 Aaron 决定；当前不实现|verdict 的 R02。L1只在配置要求得到满足时发回到场候选，不发系统解锁权限|
|R33 离开倒数文案|从“发现断开”开始约11.5秒；发现耗时和锁态回执另外记录|verdict 的 R33；L1区分读取请求超时、宽限、倒数、OS确认，蓝牙不可用不算设备离开|
|R42 Face Data范围|按交接裁决保留 Aaron 决定，发布前非阻断核对；本份不重新裁决法律适用|verdict 的 R42。R43来源、许可、哈希、计算单元和身份技术证据仍不可跳过|
|R41 授权数据在哪里|现有授权句柄实际存本机文件，不是 Keychain item|`prototype/App/DeviceAuthorizationKey.swift:4–10,44–55,72–83,86–126`。登记表已按实现更正；源注释的 -34018 是历史探针报告，不是本轮实测|

## 固定协议结论

本包实际有 **304** 份 JSON：顶层37、v1目录2、v2目录265。委托写的“39个文件”与递归文件数不符。本份保留全部304份输入的哈希，没有把37/39当作完整目录。Model、Turn等不少对象在 `definitions` 内，并没有独立 `Model.json` 或 `Turn.json` 文件。

下面短路径都相对于固定Schema目录。精确索引见 `validation/schema-evidence.json`。可以运行 `python3 tools/check-pinned-schema.py --repo "$REPO"`；这仅检查版本和字段证据，不连接CLI。

|用途|原始文件及JSON pointer|确定的写法|
|---|---|---|
|能力目录|`v2/ModelListResponse.json#/definitions/Model`|提交使用 `model` 字段；显示使用 `displayName`。`id`可保留作目录记录，但不假定等于wire model|
|推理档位|同文件 `#/definitions/ReasoningEffortOption`、`ReasoningEffort`|supportedReasoningEfforts 是对象数组，取 reasoningEffort；类型为非空字符串，不是固定六档枚举。D2只承认本次真正返回的支持值|
|分页|同文件 `#/properties/nextCursor`|nextCursor非空时继续取。未知字段可以保留或忽略，不变成新能力|
|发新一轮|`v2/TurnStartParams.json#/required`|required为input、threadId；明确选择的model/effort须经当前能力校验。不得借新请求改approvalPolicy或sandboxPolicy绕过宿主|
|补充当前轮|`v2/TurnSteerParams.json#/required`|必须包含 expectedTurnId、input、threadId；不把“当前看见哪个thread”代替具体轮次前置条件|
|中断|`v2/TurnInterruptParams.json#/required`|threadId和turnId都绑定。请求发出与真实中断分开；不能中断别的观察到的会话|
|开始/完成回执|`v2/TurnStartedNotification.json#/definitions/Turn`|Turn要求id、items、status；没有actual model/effort。startedAt/completedAt是Unix秒，durationMs是毫秒。连续时钟截止值由本机另建|
|模型重路由|`v2/ModelReroutedNotification.json#/required`|有fromModel/toModel/threadId/turnId/reason；只证明相应模型变化，不证明effort。无法读回时显示实际档位未确认|
|命令审批|`CommandExecutionRequestApprovalResponse.json#/definitions/CommandExecutionApprovalDecision`|一次同意为accept；decline拒绝但继续turn；cancel同时中断turn。acceptForSession和两种策略修订不由一次确认UI代发|
|文件审批|`FileChangeRequestApprovalResponse.json#/definitions/FileChangeApprovalDecision`|独立类型的accept/decline/cancel；同样不把一次批准扩大为acceptForSession|
|权限扩展|`PermissionsRequestApprovalResponse.json#/required`|响应需要permissions，不是decision；scope默认turn，session是另一个扩大范围的选择。strictAutoReview不因普通批准被关闭|
|消息方向|`ClientRequest.json#/oneOf`、`ServerRequest.json#/oneOf`、`ServerNotification.json#/oneOf`|model/list、turn/start等是客户端请求；三类requestApproval为服务端请求；turn/started等为通知。不能把服务端请求当普通活动通知丢掉id|
|RPC请求id|`RequestId.json#/anyOf`|字符串和Int64都合法，原类型返回。内部WS2.RequestID的Codable不是wire JSON-RPC编码器，D6需显式按原primitive编码|
|审批绑定|`ServerRequest.json#/definitions/CommandExecutionRequestApprovalParams`|服务端RPC id绑定请求；载荷threadId/turnId/itemId及存在时approvalId都纳入实际目标摘要。startedAtMs是服务端时间，不用作本机连续时钟截止|

**交回宿主不是一种通用wire决定。**A1的returnToHost表示WindowShade撤去展示/控制，由宿主已存在的审批路径继续处理。D6只有在已证明宿主能接回时才执行交还；没有该路径时先保留pending并明确不可接管，不伪造 `defer`/`allow`。A2的退出码和空响应如何处理，必须按提供商、事件和版本验证。一次Grant先在现有AuthorizationService消费，再由唯一发送者回复；D1的费用票、随机token或voicePassed都不能替代Grant。

**Schema没有回答：**初始化后的实际可见会话范围、跨进程owned身份、一次请求是否实际执行、hook trust流程、音频来源、遥控服务端兼容性，以及断线后原客户端的继续行为。完整JSON不等于完整端到端验收。

## 尚未有真机结论的探针编号

这些编号用于余下包验收引用。此第1份只交纯逻辑和合同，**不包含下列真机探针程序**，不能拿表格当作已经交付或跑过的探针。

|编号 / 负责包|要取得的证据|通过时下一步|不通过或结果未知时|
|---|---|---|---|
|L2-GATT / L2|原生iPhone/Watch实际服务、特征、read属性、请求与回调时间、加密/身份绑定；每条采样带连接代次|把验证过的读取及disconnect转为L1事件，读取周期和单次超时各自记|该设备标暂不可用；不编UUID、不加手机App、不把RSSI当read成功|
|LOCK-OS / 锁屏后端|明确系统锁请求、真实控制台锁态回执、屏保/息屏对照、重复/失败/延迟|只在实际locked回执后确认本轮自动锁所有权|不宣称已锁定；不显示回来可解锁；现有系统锁功能仍可由用户独立操作|
|L2-RETURN / L2|锁后重连是否同已登记设备、读取新鲜度、RSSI真实采样节奏、旧回调隔离|仅发新的返回身份候选|保持锁定；不执行OS unlock|
|FACE-ID / 身份F1/L3，不是影片F1|模型来源/许可/哈希、检测/匹配/PAD分项、同人异光与他人/照片/视频测试、实际计算单元/延迟|主模型审定威胁模型后接只返回证据的身份服务|保持现有Touch ID/主身份路径；不能把有人或检测到人脸当本人|
|UNLOCK-SECRET / F4/L5|凭据生命周期、跨锁密钥能力、用户清除、超时/睡眠/进程退出、真实系统失败处理|单独批准OS解锁后端，不放宽普通授权账的unlocked条件|不收密码、不把密码放String/日志/助手上下文，不伪装可用|
|I2-ABI / I2|14符号签名、C布局sizeof/align/offsetof、整数宽度、触点单位、生命周期/注销后无回调|受保护adapter把值转换到I1d的毫米模型|停用私有接触源，原输入透传；不要试读未知内存|
|I2-IDENTITY / I2/I3|能否把当前CGEvent可靠关联到特定HID设备；同型号双设备对照|有证据的wheelMouse才进I1a|unknown原样透传，不因接了鼠标就改全部滚动|
|I5-HID / I5a|每代遥控器usage、down/up/clickOnly、触控坐标报告、断线与取消；音频报告另列|按钮输入进I1e；有坐标证据才开指挥轨迹|只启用已证实的按钮；没有触控/音频就明确缺失，不拿键码伪造|
|I5-MAPPING / I5b|映射差分、同型号多设备、用户并行改动、崩溃恢复、重连|仅恢复仍等于本应用最后写入的条目|停止占用该映射，不全表覆盖或无条件reset|
|I8-PAD / I8|left/rightTrigger实际效果、setModeOff、后台开关、游戏让位、断线/锁屏/抢占|映射同一动作；撤租约即清反馈|反馈不可用则关闭反馈；游戏优先，不抢不可恢复输入|
|A2-HOOK / A2a/A2b|两家版本的配置、trust、退出码/空响应/超时、权限事件、project层覆盖|固定provider/version转接表、结构化安装manifest|保留原配置与宿主原审批，禁止绕过trust；本机无hook不是安装成功|
|D5-SERVER / D5a–c|Swift服务端最小配对/协议、对端身份、输入方向、加密重放防护、失联取消|能力逐项公布，按实际回执接D1|独立记录未成立分支，不改Rust或复制许可未知代码|
|D6-OWNERSHIP / D6|初始化、分页、已授权会话绑定、approve方向/原id、断线未知执行、宿主交还|owned会话才显示可执行控制；恢复先snapshot|observed只读；不接管任意终端、不重试不确定的start|
|A4-GRANT / 主模型授权服务|请求hash/purpose/epoch/期限与一次消费；重复及错误目标测试|唯一服务消费成功后发送一次provider答复|普通/高风险/未知风险都不旁路批准；不能仅凭voice Bool放行|
|P1-FS / 日志与存储|macOS编译、Darwin ACL、第二账户、链接/硬链接、轮转、崩溃、旧/tmp日志处置|主模型批准替换logger；记录真实权限证据|停用不安全持久日志，不降权限校验、不删除未知旧文件|
|P1-KEY / 授权存储|句柄三文件权限/ACL/路径替换、指纹变化与一般失败区分、失效删除|确认当前文件存储策略可保留再接审批|不把日志安全检查当授权文件安全验收；由主模型处理该独立边界|
|P2-NET / 隐私页|所有模式和子进程实际网络目的地、音频/输入/令牌去向|同步registry条目与可见说明|不能全局承诺仅更新联网；拒绝未获同意的云转写|
|BASELINE-PWR / 主模型|同设备/显示/电源/构建/签名/负载的成对多轮CPU、唤醒、WindowServer等|按BuildBaseline出实测表|空模板保持未测；不写零能耗或无回归|

私人API失败只关闭该路径；普通输入和既有功能保持原行为。表里的未决点不由DeepSeek自行选择替代产品路线。Aaron尚未决定的单手机返回策略保持关闭。
