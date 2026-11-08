# WindowShade 2 施工规格审查

日期：2026-10-03。对象：Aaron 提供的 `WindowShade2-review.zip`，不是实时 GitHub HEAD。

## 总体判断

这套提示词现在还不适合让执行模型直接接真实输入和授权。最容易出事的地方是授权绕过、把候选硬件路线写成确定API，以及几个包各自定义相同的会话和输入状态。先修这些边界，T1、菜单和符号等有限任务可以推进；蓝牙身份、多触点私有ABI、遥控服务端和真实系统锁必须通过专门探针。问题不在于功能数量本身，而在于同一功能有几份互相冲突的执行规则。

本报告保留 Aaron 的产品决定：同一刘海入口、统一动作、多种输入、独立分发、允许有退路的私有API、不增加手机/手表App、不新增宏工具和通用自动化平台。未验证能力标为未验证，没有以省事的替代品冒充完成。

## 证据边界

实际读取了总开工文件、五份包提示词、总图、对应功能规格、关键既有接口和上游认证/指挥约束。代码是上传快照；没有读取git历史，也没有改用户源码。源码事实在下表按原包相对路径和行号定位，行号以本次ZIP为准。外部资料查阅截至2026-10-03；[来源表](sources.md)区分读到正文、历史头文件和只取得文档入口。

本次在Linux x86_64、Swift 6.2.1下，以`-swift-version 6`实际编译并运行了原包ConductorGestureTests与NotchActivityTests；两者通过。没有macOS SDK，因此没有运行完整App构建、AppKit、TCC、锁屏、蓝牙、遥控器或手柄测试。24个原创骨架的逐文件结果见[validation.md](validation.md)。上传说明所列Mac17,4/macOS27/Swift6.4是交接方报告，不是本次实测。

“阻断”只阻断相应危险接线，不要求停止互不相关的工作。“需要主模型冻结”表示规格缺决定；“需要真机”表示证据缺失；不混成一句“做不到”。

## 问题表

| 编号 | 程度 | 位置 | 问题 | 修改建议 |
|---|---|---|---|---|
| R01 | 阻断 | `docs/handoff/deepseek-conductor.md`:71 | D1 将短语/声纹两个布尔值直接接到高风险 allow，绕过 A4 授权账和动作目标。 | 改为 requestAuthorization effect；只有主模型权威服务消费正确 purpose+target+epoch 的 grant 后才能发一次决定。声纹可触发附加检查，不能自行签发授权。 |
| R02 | 阻断 | `docs/handoff/deepseek-dynamic-lock.md`:43 | L1 的“需要认脸时”允许在没开刷脸时，以重连+RSSI放行，与“两样都对才代填”冲突。 | 回来条件只产生身份检查候选，不输出解锁许可；F1/L3与锁屏会话策略通过前禁用L5。 |
| R03 | 阻断 | `docs/handoff/deepseek-dynamic-lock.md`:55 | L2把设备信息服务当成可读对象；没有证明原生iPhone/Watch提供可用特征。 | 先列出服务、特征、read属性、实际回调和加密证据；失败只标该路线未成立，不编UUID或偷偷加手机App。 [S04/S11](sources.md) |
| R04 | 阻断 | `docs/handoff/deepseek-dynamic-lock.md`:11 | “系统公开办法”没有具体API；现有LockSpaceBridge只负责窗口附着，不能据此宣布锁屏可用。 | 主模型先提供真实锁适配器、系统状态回执和失败测试；屏保、熄屏、遮罩都不是锁成功证据。 |
| R05 | 阻断 | `docs/handoff/deepseek-conductor.md`:148 | D5保留Rust实现要求；conductor-v2/input-devices已改为Swift优先。 | 统一为Swift方向的协议可行性包；先决定服务器角色/边界和最小证明，不并行造两套。客户端协议零件不等于现成服务端。 [S15/S16](sources.md) |
| R06 | 阻断 | `docs/input-devices.md`:51 | 原规格一处记录无LICENSE，另一处又直接批准拷贝。 | 先固定提交并获得覆盖相关文件的许可文本、版权、依赖清单；本次README的LICENSE链接也未取到。未核清前只独立实现，不宣称项目一定无许可。 [S15](sources.md#s15) |
| R07 | 阻断 | `docs/handoff/START-HERE-deepseek.md`:66 | D1依赖D2的票据、I1的遥控模式和A1/A4审批；第一波写成完全独立会产生互不兼容模型。 | 主模型先冻结公共事件、动作、授权、时钟协议。D2/I1归一层→D1；A1可独立写表，但审批合同先共用。 |
| R08 | 高 | `code/prototype/build.sh`:135 | 说明称--check是类型检查，实际还编译Metal、优化链接并无条件-framework Sparkle；审查包移除了该框架。 | 将--check称完整编译/链接检查；先恢复授权依赖，再测。受限环境只报Foundation检查；不能删链接项制造通过。 |
| R09 | 高 | `code/prototype/build.sh`:142 | 目标仍是macOS14，交接只提供macOS27/Swift6.4真机描述；新API/符号可能破坏旧目标。 | 每API以本机SDK导出签名校验；新API加available/回退；mac14编译目标+mac27真机分别验收。原脚本是否Swift6语言模式另行核实。 |
| R10 | 高 | `docs/handoff/deepseek-conductor.md`:6 | 子提示词要求先提交文档，与总提示词禁止提交冲突；用户dirty改动可能在分派clone中丢失。 | 删除自动提交要求；冻结只读源码/文档快照与哈希，主模型明确包含dirty内容的派工基线。未授权不commit、不stash。 |
| R11 | 高 | `code/prototype/Core/NotchActivities.swift`:89 | 现有kind优先级、容量32/可见3的store不是完整六层仲裁；容量满时不能保证安全提示进入。 | 主模型先建全局交互租约+每屏显示协调；授权不存普通活动槽，普通store只放被仲裁展示数据。 |
| R12 | 高 | `docs/handoff/START-HERE-deepseek.md`:38 | “只改点名文件”与S1相关设置页、T4负一屏、A2打包、D3接协调器等任务缺少明确路径冲突。 | 派工前冻结真实文件/符号允许列表；缺依赖时只报缺口并继续无关纯逻辑，不扩散重构。 |
| R13 | 高 | `docs/handoff/deepseek-input.md`:59 | I1同时混合六种算法和输入模型，作为一个不可分包过大。 | 保留I1编号，内部按I1a..f分六次验收；遥控归一优先，平滑和多触点独立，避免反复全App构建。 |
| R14 | 高 | `docs/handoff/deepseek-input.md`（isContinuous） | continuous/momentum和IOHID VID/PID不能直接提供每个CGEvent的可信物理设备身份。 | 模型增加unknown/confidence；没有可验证关联时原样放行，不能仅凭“接着一个鼠标”修改全部滚动。 |
| R15 | 高 | `docs/handoff/deepseek-input.md`:92 | 私有多触点ABI、callback返回类型/整数宽度/注销签名没固定。 | 历史布局仅作候选；提供C shim尺寸/偏移检查和隔离探针，证实停止回调的生命周期后才解引用。 [S07](sources.md#s07) |
| R16 | 高 | `docs/handoff/deepseek-input.md`:82 | 多指轻点与中键改写没完整规定接触会话和down/up所有权。 | 完整接触组后再判3/4指；中键替换必须在down决定，后续drag/up一致；中途取消/掉线补平衡且不重复原始up。 |
| R17 | 高 | `docs/handoff/deepseek-input.md`:105 | 滚动tap安装条件只覆盖平滑/方向，却包含独立的精细/侧键；无支持证据就合成快捷键可能送错App。 | 按实际启用功能组合计算mask和生命周期；侧键只在已测App动作路由上替换，否则透传。 |
| R18 | 高 | `docs/handoff/deepseek-input.md`:120 | 按VID/PID改映射可能影响同型号多设备，退出还原没涵盖崩溃和用户后来修改。 | 读原值→合并→写入→持有所有权凭据；恢复仅比较匹配自己最后写值的条目；崩溃恢复和重连补写单独测试。 [S06](sources.md#s06) |
| R19 | 高 | `docs/input-devices.md`:144 | 从只读设备枚举、上游README推导触控面和0xFA麦克风已有现成可用路线，证据过强。 | 分别记录枚举、收到报告、解析采样、音频格式、录音许可、端到端可用；未达到后一层不宣布已解决。 |
| R20 | 高 | `docs/handoff/deepseek-input.md`:137 | DualSense属性/后台事件与游戏让位被当作即插即用；既有系统Space桥未证明跟手交互。 | 用leftTrigger/rightTrigger方法，不用adaptiveTriggers；后台开关按进程管理；Space只调用主模型明确支持的离散/交互能力。 [S14](sources.md#s14) |
| R21 | 高 | `docs/handoff/deepseek-conductor.md`:98 | 要求拒绝旧epoch后端消息，但D1事件签名缺乏跨异步关联字段。 | 每条异步事件加peer/session/epoch/commandID/turnID；连接序号由接收方生成；状态切换即撤销旧票。 |
| R22 | 高 | `docs/handoff/deepseek-conductor.md`:104 | 一次确认票未充分绑定最终effort、workflow、草稿/命令摘要和连接代次。 | 把最终执行配置纳入绑定并使用本地截止时刻；发送前重算，消费后不能重复使用；它不等于安全授权grant。 |
| R23 | 高 | `docs/handoff/deepseek-conductor.md`:67 | 模式长按、媒体短按、提交和中断共用键，缺少一套跨模式按下/松开优先级。 | 短按只在release认定，长按只一次，模式切换释放不再发短按；中心select作为独立键补齐。 |
| R24 | 高 | `docs/handoff/deepseek-menu-agents.md`:39 | “放行给原来的流程”容易被实现为PermissionRequest allow，造成App没启动就自动批准。 | 明确输出无决定；宿主自行决定提示或拒绝。allow/deny和退出码按provider/event/version固定测试。 [S02/S03](sources.md) |
| R25 | 高 | `docs/handoff/deepseek-menu-agents.md`:44 | 把两家hook写成同构配置且未固定版本；当前Codex已支持hooks.json，盲改TOML增加损坏风险。 | 首版优先已支持版本的~/.codex/hooks.json；Claude用settings.json。探测宿主版本/已有配置层，不能重复装两份或绕过trust。 [S02/S03](sources.md) |
| R26 | 高 | `docs/handoff/deepseek-menu-agents.md`:38 | socket0600不足以防路径替换、同账户注入和超长帧；socket目录可能超Darwin路径长度。 | 父目录0700，拒绝symlink，核owner/getpeereid，限帧/并发/超时；长路径失败要报告并批准私有短路径方案，不退回公开/tmp或TCP。 |
| R27 | 高 | `docs/handoff/deepseek-menu-agents.md`:45 | “只删自己加的几行”不适合结构化配置，JSON也不能随便插注释标记。 | 外部安装manifest记录对象指纹；结构化合并保留未知项；显示diff后重新比较原文件哈希，变化则重新确认；备份0600。 |
| R28 | 高 | `docs/handoff/deepseek-menu-agents.md`:30 | 风险分类把未知shell/脚本算普通；同名命令、间接联网/文件操作无法靠前缀识别。 | unknown不得自动放行；分类不取代宿主sandbox或approval policy；网络prompt显示host/protocol而不编造shell解释。 |
| R29 | 中 | `docs/handoff/deepseek-menu-agents.md`:31 | 无事件10分钟不等于会话断了；重试与间歇性hooks会制造假状态。 | 加stale/unknown展示，只有明确进程/连接结束才断线；完成、停止一轮、会话关闭分别建模。 |
| R30 | 高 | `docs/handoff/deepseek-menu-agents.md`:53 | 按标题定位可能跳错会话，按PID也要防复用。 | 已绑定窗口ID与进程身份复核；不能证明精确匹配就只激活对应App；标题永不作授权目标。 |
| R31 | 高 | `docs/handoff/deepseek-conductor.md`:162 | JSON-RPC方法名写出但方向、初始化、分页、服务端审批、断线未知执行没有完整合同。 | 按官方App Server协议固定版本；request≠notification≠response，stdio不加LSP头；服务器审批ID原样回应，不自动重试turn/start。 [S05](sources.md#s05) |
| R32 | 高 | `docs/agents-in-notch.md`:1 | “看到终端会话”与“有权控制它”没有统一能力分层。 | 区分observed/read-only和owned/controllable；thread/resume不是接管另一个活动进程，不显示实际不能完成的发送/中断。 |
| R33 | 高 | `docs/handoff/deepseek-dynamic-lock.md`:32 | 2秒超时与5秒读取冲突；约11.5秒锁定只算宽限+倒数，漏检测时间。 | 2秒从具体请求发出开始；分别记录检测、1.5秒宽限、10秒倒数、OS确认。示例可能5+2+1.5+10=18.5秒，非物理离开硬上限。 |
| R34 | 高 | `docs/handoff/deepseek-dynamic-lock.md`:35 | 手机+手表AND、摄像头独立触发、Mac蓝牙关闭/权限丢失的组合未定义。 | 区分away与sensorUnavailable；主模型冻结组合真值表；系统自身失效不当作已证明离开。 |
| R35 | 高 | `docs/handoff/deepseek-dynamic-lock.md`:67 | 本地URL scheme不证明来自iPhone，也不是跨设备传输通道；“从iPhone锁上的”是无证据文案。 | 标外部锁屏请求，不授予动态锁自动解锁来源；来源认证另做通道，当前不扩范围。 |
| R36 | 高 | `docs/handoff/deepseek-dynamic-lock.md`:66 | 现有playPause是toggle，调用暂停可能开始播放；无播放会话所有权就无法安全恢复。 | 只对自己确认正在播放的会话发明确pause；恢复先核同一来源/会话/曲目且用户未改变。否则不联动。 |
| R37 | 高 | `docs/handoff/deepseek-dynamic-lock.md`:38 | 收窗口或音乐步骤卡住会拖住锁屏；重复回调可能多次锁/还原。 | 效果有独立上限和单次sessionID；安全锁不无限等待装饰；恢复仅限本轮拥有且还存活的窗口。 |
| R38 | 高 | `docs/handoff/deepseek-pomodoro-symbols.md`:15 | 计时只说单调时钟但要求休息跨睡眠照走；单个paused会丢掉手动暂停原因。 | 连续时钟+暂停原因集合；锁/睡重复和解除順序单测；自然日从Calendar独立提供。 [S01](sources.md#s01) |
| R39 | 中 | `docs/handoff/deepseek-pomodoro-symbols.md`:42 | Core Animation不等于零能耗；展开mm:ss和紧凑按分钟刷新要求不同。 | 只在可见/有效状态安排下一截止刷新；隐藏移除动画；减少动态效果静态展示；记录CPU和WindowServer而非只主线程。 |
| R40 | 高 | `docs/privacy-page.md`:12 | 远端模型、局域网遥控、转写可让数据离开本机，旧“只有更新联网”承诺不能沿用。 | registry列实际目的地、进程边界、发送内容与开关；网络实测包含子进程和所有启用模式。不能只搜URLSession。 |
| R41 | 高 | `docs/privacy-page.md`:29 | 修日志被安排成后续页面工作，却已有全局可读路径/窗口标题风险说明；新agent事件会放大暴露。 | P1和registry接口作为系统接线前置；0600文件+0700目录、拒绝symlink，环境日志路径同策略；命令/草稿/密钥/生物数据不上日志。 |
| R42 | 高 | `docs/face-unlock.md`:29 | 把不上AppStore当作全部协议限制不适用的充分条件，结论缺少适用协议核对。 | 保留研究目标；由主模型核实际SDK/Developer Program签署文本与模型许可，不凭分发渠道作豁免结论。本次未作法律合规裁定。 [S17](sources.md#s17) |
| R43 | 高 | `docs/face-unlock.md`:32 | 指定ArcFace/ANE不等于导出的模型一定在ANE执行，开摄像头2fps也不能证明活体或本人。 | 记录模型来源/许可/哈希、CoreML实测计算单元与延迟；输入质量、检测、本人匹配、PAD分开，未知不升级。 |
| R44 | 高 | `docs/face-unlock.md`:46 | 密码会话TTL、锁屏保留与授权账锁时撤销的区别未定义；Swift String清空不保证副本消失。 | F4/L5独立威胁模型：谁持解密能力、是否跨锁保留、何时到期/清除、系统失败怎样撤销；普通执行包不得处理密码。 |
| R45 | 高 | `code/prototype/App/AuthorizationService.swift`:28 | 已有授权服务锁屏/睡眠会推进epoch、消费需unlocked；不能拿同一grant绕过锁态执行系统解锁。 | 用approveAgentAction/enrollDevice等既有purpose精确绑定；OS unlock是主模型单独受控适配，不放宽ledger的unlocked检查。 |
| R46 | 中 | `docs/handoff/deepseek-conductor.md`:118 | D3要求开发测试面板，与唯一刘海宿主冲突。 | 现有宿主内DEBUG假输入入口；独立ABI探针只作实验进程且明确不算产品UI完成。 |
| R47 | 中 | `docs/handoff/deepseek-menu-agents.md`:15 | 以缺少更新地址推断开发构建会在错误打包中暴露探针。 | 正式编译开关去除探针，运行参数只是第二道开关；不改变生产更新地址来测试。 |
| R48 | 中 | `docs/handoff/START-HERE-deepseek.md`:30 | 八字/一行与动态模型/项目名、权限风险说明存在冲突。 | 固定状态文案短，动态内容限布局而不是截断语义；安全批准始终展示完整动作/目标/后果。 |
| R49 | 中 | `docs/handoff/deepseek-pomodoro-symbols.md`:31 | 71/39条是快照计数，不应成为新检查结果；macOS27符号可用不代表14可用。 | 逐项扫描真实当前源、保留old/new/fullHelp/key映射；failable符号回退并测最低系统。 |
| R50 | 中 | `docs/performance.md`:441 | 能耗基线引用1.0.15、build16、正在使用/无人输入多种条件，直接比较会失真。 | 冻结相同签名构建/设备/显示器/电源/设置/负载，改前后成对多次测；开新功能也单列增量，未测不写无退步。 |
| R51 | 中 | `code/prototype/App/NotchActivityController.swift`:17 | 现有活动控制器仍有固定计时器；新增deadline调度不能据此声称整个程序已无轮询。 | 增量指标与全局现状分开；主模型统一调度，执行包别各自增加常驻Timer。 |
| R52 | 中 | `docs/handoff/START-HERE-deepseek.md`:99 | “纯逻辑/界面一定不影响已有功能”过于绝对；共享枚举、设置、构建收集都可能回归。 | 逐包列触达的现有测试，核心值类型可Linux测，UI仍需macOS构建和回归，隐藏/默认关闭不等于无回归。 |
| R53 | 低 | `00-先读我-给 ChatGPT.md`:27 | 64个是v3指挥场景；另有96个v4认证场景，且JSON主要是未运行清单，不是可执行套件。 | 报告逐场景状态；既有手势测试只覆盖其中纯逻辑切片，不能升级其余场景。 |

## 调整后的顺序

**先由主模型完成四个短前置。**冻结事件与审批合同；确定全局交互租约/每屏展示接口；修日志并定义隐私registry；记录可复现构建基线。它们是既有主模型职责的接线前提，不是新增大框架。主模型必须提供实际路径/符号，不能再把“复用现有”当作完整接口。

| 轨道 | 顺序与边界 | 为什么 |
|---|---|---|
| 纯逻辑 | T1、I9、A1、L1可在合同冻结后分开做；D2与I1遥控归一完成后再D1 | D1并非独立；L1只能测策略，不能宣布蓝牙可行 |
| I1拆分 | I1a遥控键/模式→D1；I1b设备分类；I1c滚动；I1d中键拖；I1e多触点；I1f统一输出对照 | 每次只改相关Core/测试；编号I1保留，不制造新产品模块 |
| 低风险UI | M1、S1；T1→T2→T4；A1→A3；D1→D3→D4 | 共享Preferences和Notch枚举串行合并；A3/D3假输入不能触发执行 |
| 存在/锁屏 | F1/L3只读身份探针与L2能力探针提前；L1→L2假适配→真实探针→L4 | L2的service/characteristic及锁屏后端是可行性前提；L5永远由主模型 |
| 输入接线 | I7许可/设备生命周期壳先行；I2只读→I2改写，I3，I5a只读HID→I5b映射事务，I8按设备逐一 | 先观察、再改写；第三波仍须Aaron授权，不能把写了设置误当授权 |
| 编程连接 | A2a协议解码/socket假测试→A2b配置差异/恢复；D6假App Server可提前；A4完成后才启用真批准 | 网络/密码学与UI解耦；没有A4只能“去看看” |
| 遥控协议 | D5a版本/许可/服务端可行性→D5b配对与字节解析→D5c真实iPhone；与D6分别验收再A5合流 | 其复杂度不适合一次“写完整服务端”；不引入未授权Rust或上游调试服务器 |

默认一次一个可写包。并行仅限隔离快照、不同可写文件、已经冻结合同；不要同时改main上的Preferences、NotchActivityKind、build.sh。对同一不可验证硬件假设只安排一次主模型探针，不让每个执行包重新探索。第三波接线、实际权限与设备变更仍须Aaron明确同意；1.0.16发布没有获得任何新授权。

## 统一验收，不用测试数量冒充完成

每个包交回：源码差异、需求→测试映射、实际命令/退出码/末尾输出、回滚方式、剩余阻断。纯逻辑测试通过只证明相应模型；编译通过只证明所用SDK能接受类型；探针读到事件只证明数据路径；需要最终用户动作的功能仍要端到端测试。新增测试不能只重抄实现的分支。

验收包含：默认关闭时不读新输入；启用失败能回滚；锁/睡眠/退出/换屏撤销在途租约；合成down/up平衡；未知字段/设备/能力不升级为可信；原快捷键、手势、窗口恢复和签名更新流程不退步。输入和私有ABI探针必须有人看着，不在Aaron离开时运行可能吞输入、改变映射或锁屏的实验。

原包v4认证有96个场景、v3指挥有64个场景。它们是追踪表，不能因本次两个Foundation测试程序通过就整体改成通过。优先挑与本次包有直接关系的场景，保留原ID与未运行状态。

## 交付内容怎么用

先合入[prompt-patches.md](prompt-patches.md)里的总则冲突修正，再发对应`cheatsheets/<ID>.md`。每页是一个边界清楚的施工提示，不是已完成的整功能；源码骨架独立放在`examples/`便于类型检查。协议的精确JSON、私有ABI候选表和共享合同分别在`reference/`，避免在24份小抄里复制出24个版本。
