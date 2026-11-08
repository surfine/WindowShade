# 指挥模式（WindowShade 2）验收清单：重建稿

> **状态：未经 Aaron 审阅。** 审阅通过前，它不是验收标准；本文由仓库文档推出，不是原件。

## 为什么重建

`docs/conductor-v2.md`、`docs/blueprint.md` 第 5 行和 `docs/conductor.md` 都以 v3 的 `CONDUCTOR-ACCEPTANCE.json`（“64 个场景”）作为 WindowShade 2 的发布门槛（W7：“64 个场景逐项有真实结果”）。原文件在 `~/Downloads/WindowShade-Authentication-MFA-Handoff-v4.zip` 的 `prior-v3/` 里，这个压缩包已经找不到：`mdfind -name CONDUCTOR-ACCEPTANCE`、`mdfind -name MFA-Handoff` 无结果，`~/Downloads` 里的 52 个 zip 逐个列过目录，没有 `CONDUCTOR-ACCEPTANCE` 或 `prior-v3/`。Aaron 同意按仓库文档重建。

## 它不是什么

- **不是原 64 条的还原。** 仓库里只残留了一小段原编号线索：`docs/conductor.md:38-39` 与 `tests/ConductorGestureTests.swift` 提到 C-011…C-022（识别器）和 C-023（轨迹里带 Select 不算确认）、C-024（选择域切换）、C-025（模型槽位），日志 `docs/handoff/chatgpt-review-1/validation/conductor.log` 里能看到 C-011…C-022 的断言名。其余原编号和原文不可考，所以本文用新编号（X/P/S/T/M/D/A/R/V/E/B + 序号），只在 `v3 原 ID 线索` 一栏标可对上的。
- **v3 的 C0–C6 分组只能推出两段**：C0 = 两个阻断实验（`docs/conductor.md:9-16`，对应本文 X 组），C2 = 识别器（`docs/conductor.md:18`，对应 T 组）。C1、C3–C6 的含义文档里没有，所以其余分组按工作流划分，不冒充 v3 的阶段名。
- **旧 C-024（档位/模型两个选择域切换）已作废**：2026-10-08 起没有模式切换，只有层，去掉了两个域（`docs/conductor-v2.md:24`）。它的位置由 M03（模型位置）与 S01–S05（层）取代。
- **数量以文档能支撑的为准**：文档能推出 **81** 条可验证行为，不是 64。没有凑数，也没有删到 64。其中 6 条标了“推断”，列在文末。

## 依据的文档

- `docs/conductor-v2.md`
- `docs/conductor.md`
- `docs/blueprint.md（第 5 行）`
- `docs/handoff/deepseek-conductor.md`
- docs/handoff/ws2-reuse-2026-10-08/CLAUDE-HANDOFF.md
- docs/handoff/ws2-reuse-2026-10-07/README.md、conductor.md、remote.md、device-tests.md
- `docs/handoff/FINAL-HANDOFF.md（WindowShade 2 各部分，指挥模式一行与 W05 工单）`
- `docs/copy-guide.md（固定词汇：指挥模式、遥控模式、Siri 遥控器、iPhone 上的遥控器）`
- `docs/input-devices.md`
- 代码与测试：`prototype/Core/ConductorSession.swift`、`ConductorGesture.swift`、`ConductorCapabilities.swift`、`prototype/App/WS2Conductor*.swift`、`WS2RemoteHost.swift`；`tests/Conductor*Tests.swift`、`RemoteHostLifecycleTests`、`RemoteLayerHostTests`、`RemoteModeTests`、`SiriRemoteButtonsTests`、`CompanionChannelTests`

## 读法

- “已有单测”只表示**纯逻辑**已有断言（合成输入、假后端、注入时钟）。它不等于该场景通过：`需要 iPhone / 实体 Siri 遥控器 / 麦克风与本人 / 额度` 的场景，真实结果仍要在真机或真实后端上取得，缺证据写 inconclusive 或 not_run，不拿单测顶替（AGENTS.md “Computer Use 验收”同此口径）。
- `单测覆盖` 取值：完整 = 该场景的逻辑部分已有断言；部分 = 只有一部分；无 = 没找到对应单测。这是对测试文件名与断言文字的对照，不是重跑结果。
- 来源一栏是 `文件:行号`，以我读到的当前行号为准；标“推断”的来源要么是既有测试的行为，要么是对文档的合理延伸，**需要 Aaron 确认是否保留**。

## 统计

共 **81** 条。

| 分组 | 前缀 | 条数 | 说明 |
| --- | --- | ---: | --- |
| 真机实验与第二输入来源 | X | 6 | v3 的 C0（阻断实验）；本文把 v2 的 E1–E5 放这里 |
| 配对与连接 | P | 8 | 推断为 v3 配对/连接相关阶段，原编号未保留 |
| 选会话、层与键位 | S | 12 | v2 把“档位 / 模型”两个域改成层，旧场景 C-024 作废 |
| 档位（声调与拍子） | T | 12 | v3 C2：识别器，原 ID C-011…C-022 |
| 确认与模型位置 | M | 5 | 原 ID C-023…C-025 一带 |
| 草稿与语音 | D | 8 |  |
| 发送与审批 | A | 9 |  |
| 异常与恢复 | R | 7 |  |
| 隐私与安全 | V | 7 |  |
| 能耗与性能 | E | 3 |  |
| 后端适配器与发布资格 | B | 4 | W5/W7 |

按“需要”（一条可有多项，所以总和大于条数）：

| 需要 | 条数 |
| --- | ---: |
| 自动可测 | 60 |
| 需要 iPhone | 47 |
| 需要实体 Siri 遥控器 | 1 |
| 需要麦克风与本人 | 8 |
| 需要额度 | 11 |
| 只需自动可测（不含任何真机/额度） | 27 |

单测覆盖：完整 40、部分 27、无 14。

## X · 真机实验与第二输入来源

*v3 的 C0（阻断实验）；本文把 v2 的 E1–E5 放这里*

### X01 E1：空闲态能否导出连续触摸坐标与时间，采样率多少

- **前置**：iPhone 已能连上这台 Mac 的遥控接收器；遥控器停在空闲态（没走进会话）
- **步骤**：1. 在触控区连续画线、点按、滑动各数次；2. 对照接收器导出的原始 touch(begin/move/end/cancel) 流
- **预期可见结果**：每次接触都有 begin…end，坐标连续；能报出采样间隔分布（p50/p95）。做不成就记“先改协议层，指挥模式暂停”。
- **需要的证据**：接收器事件日志（仅计数、时间戳、坐标范围，不含个人内容）＋ 采样率统计；真机记录一份
- **需要**：需要 iPhone
- **来源**：`docs/conductor-v2.md:113`；`docs/conductor.md:13`；`docs/handoff/ws2-reuse-2026-10-08/CLAUDE-HANDOFF.md:117（_hidT 不带时间戳，E1 采样率仍要自己记）`
- **单测覆盖**：部分（CompanionHIDMapTests.swift（只覆盖按键/触控字段映射，不覆盖采样率））

### X02 E2：电视键、静音、电源、侧边按钮各发什么事件，有没有按下/松开

- **前置**：同 X01
- **步骤**：1. 逐个按下并保持 1 秒再松开：电视键、静音、电源、侧边按钮；2. 再各点按一次
- **预期可见结果**：每个键记录 down/up 阶段或“只有 click”。收不到的键改走触控（往上滑 = 返回）；侧边按钮没有阶段就“点一下开始、再点一下停”。
- **需要的证据**：按键事件表（键 × 阶段 × 是否有 up），附真机日志
- **需要**：需要 iPhone
- **来源**：`docs/conductor-v2.md:114`；`docs/handoff/ws2-reuse-2026-10-08/CLAUDE-HANDOFF.md:116（_hidC / _hBtS 事实）`
- **单测覆盖**：部分（CompanionHIDMapTests.swift、SiriRemoteButtonsTests.swift（实体遥控器的 HID 映射））

### X03 E3：Mac 能否发起输入框会话，让 iPhone 弹出键盘

- **前置**：同 X01，草稿已展开
- **步骤**：1. 草稿展开后观察 iPhone 是否弹出键盘；2. 在键盘里打字、用键盘听写
- **预期可见结果**：弹出键盘且能改字；否则记“草稿只能说或在 Mac 上改”。
- **需要的证据**：真机录屏或截图＋接收器日志
- **需要**：需要 iPhone
- **来源**：`docs/conductor-v2.md:115`
- **单测覆盖**：无（没找到）

### X04 E4：iPhone 开着遥控器时，连续互通麦克风还能不能录；锁屏、解锁时呢

- **前置**：iPhone 与这台 Mac 已开连续互通麦克风；遥控器已连上
- **步骤**：1. 按住侧边按钮说一句；2. 锁屏后再试；3. 解锁后再试
- **预期可见结果**：分别记录能录/不能录；不能录就改用 Mac 麦克风或键盘听写。
- **需要的证据**：每种状态一条采集结果（有无音频样本、来源名）
- **需要**：需要 iPhone、需要麦克风与本人
- **来源**：`docs/conductor-v2.md:116`；`docs/conductor.md:14`
- **单测覆盖**：无（没找到）

### X05 E5：触控区坐标范围、y 方向、多指、边缘

- **前置**：同 X01
- **步骤**：1. 沿四条边和四角各画一笔；2. 两指同时滑；3. 从边缘外滑入
- **预期可见结果**：记录实际范围、y 是否向下、多指如何上报；按实测改归一化。
- **需要的证据**：坐标范围表＋多指/边缘日志
- **需要**：需要 iPhone
- **来源**：`docs/conductor-v2.md:117`；`docs/handoff/ws2-reuse-2026-10-08/CLAUDE-HANDOFF.md:117（_cx/_cy 在 1000×1000）`
- **单测覆盖**：部分（ConductorGestureTests.swift（只用合成轨迹，含 y 向下翻转））

### X06 实体 Siri 遥控器作为第二个输入来源（触控面与侧键麦克风）

- **前置**：一只实体 Siri 遥控器已与这台 Mac 配对；遥控模式开着
- **步骤**：1. 在触控面画一个二声；2. 按键依次点一遍；3. 按住侧键说一句
- **预期可见结果**：触控面轨迹经 MultitouchSupport 进入识别器；12 个键各映射正确；麦克风走 0xFA。当前记录是“本次未建立输入链”，所以不能写通过。
- **需要的证据**：GameController / HID 枚举日志＋同 T 组的刘海截图
- **需要**：需要实体 Siri 遥控器、需要麦克风与本人
- **来源**：`docs/conductor-v2.md:125`；`docs/input-devices.md:138（触控面经 MultitouchSupport）`；`docs/input-devices.md:146`；`docs/handoff/ws2-reuse-2026-10-07/device-tests.md（实体 Siri Remote 一行）`
- **单测覆盖**：部分（SiriRemoteButtonsTests.swift（12 个 HID 用法映射、短按/长按/取消，不含真机））

## P · 配对与连接

*推断为 v3 配对/连接相关阶段，原编号未保留*

### P01 默认关闭，总开关与指挥子项的关系

- **前置**：全新设置，遥控模式总开关关
- **步骤**：1. 启动应用，观察是否宣告/监听；2. 打开遥控模式总开关，再打开其下“指挥模式”；3. 关掉总开关
- **预期可见结果**：关着时没有 listener、不读钥匙串、不宣告；总开关打开才宣告、连接、听；指挥模式打开后刘海那一排才出现会话格；总开关关掉全停并断开已连接的 iPhone。
- **需要的证据**：监听端口检查（lsof/netstat）＋应用日志；设置页截图
- **需要**：自动可测
- **来源**：`docs/conductor-v2.md:66`；`docs/handoff/deepseek-conductor.md:144（开关默认关）`
- **单测覆盖**：完整（RemoteHostLifecycleTests.swift（L01、L02）、RemoteModeTests.swift（默认关闭）、RemoteLayerHostTests.swift（指挥模式关着没有会话格））

### P02 设置页：指挥模式一栏

- **前置**：遥控模式总开关开
- **步骤**：1. 打开设置 → 遥控模式 → 指挥模式；2. 看开关、已配对 iPhone 列表、四个模型位置、提示音
- **预期可见结果**：有开关、可逐台撤销的 iPhone 列表、四个模型位置、提示音开关；副标题与文案照 copy-guide 的固定词汇（指挥模式、档位）。
- **需要的证据**：设置页截图（中文/英文）＋ 文案对照 copy-guide 的自检记录
- **需要**：自动可测
- **来源**：`docs/handoff/deepseek-conductor.md:138-144`；`docs/conductor-v2.md:156（W3）`；`docs/copy-guide.md:101`
- **单测覆盖**：无（无专用单测（设置页在 WS2ConductorSettings.swift，构建检查覆盖编译））

### P03 第一次配对：选这台 Mac，输四位数，Touch ID 确认

- **前置**：iPhone 与 Mac 同一网络；遥控模式开；iPhone 从没配过
- **步骤**：1. iPhone 控制中心遥控器 → 选这台 Mac；2. 刘海显示四位数，在 iPhone 上输入；3. Mac 上 Touch ID 确认“允许这台 iPhone 遥控”
- **预期可见结果**：刘海写“在 iPhone 上输入 4 8 1 6”（数字随机）；输对后弹 Touch ID；通过后 iPhone 连上；配一次，遥控和指挥都能用。当前记录：原生 iPhone Remote 最终版出现 PIN 框但没进控制会话，所以此场景尚无真机通过。
- **需要的证据**：真机配对录屏＋接收器日志（日志里不得有配对码和设备名）；钥匙串中出现该 peer
- **需要**：需要 iPhone
- **来源**：`docs/conductor-v2.md:67`；`docs/handoff/ws2-reuse-2026-10-08/CLAUDE-HANDOFF.md:9-11（第 10 轮真机输入已通过，但主应用未接）`
- **单测覆盖**：部分（RemoteHostLifecycleTests.swift（L04、L04b）、CompanionChannelTests.swift、WS2PureSRPTests.swift）

### P04 配对要等 Touch ID 回执；取消、拒绝或晚到的成功都不入库

- **前置**：配对码已显示
- **步骤**：1. 不做 Touch ID，让它超时；2. 做 Touch ID 然后点取消；3. 取消之后让晚到的成功回执到达；4. 拒绝 Touch ID
- **预期可见结果**：回执之前钥匙串里什么都没写；取消、拒绝、晚到的成功都不会配成；回执只能用于它对应的那台 iPhone 且用一次。
- **需要的证据**：钥匙串前后对比＋日志里 `late success ignored` 一类记录
- **需要**：自动可测
- **来源**：`docs/conductor-v2.md:67`；tests/RemoteHostLifecycleTests.swift L03–L05（既有断言依据）
- **单测覆盖**：完整（RemoteHostLifecycleTests.swift（L03、L04、L05））
- **推断**：v2:67 只写“输对后 Touch ID 确认”；“晚到成功不算”来自 RemoteHostLifecycleTests L05 的既有行为

### P05 配对码防暴力：随机、60 秒有效、错 3 次停 5 分钟

- **前置**：配对窗口打开
- **步骤**：1. 等 60 秒后输入正确码；2. 连续输错 3 次；3. 5 分钟内再试
- **预期可见结果**：码随机（不用 1111）、60 秒失效；错 3 次后 5 分钟内拒绝；PIN 和密钥不写日志。
- **需要的证据**：测试输出（失败次数、冷却时长）＋日志检索无 PIN
- **需要**：自动可测
- **来源**：`docs/conductor-v2.md:67`；`docs/handoff/deepseek-conductor.md:157`
- **单测覆盖**：部分（RemoteHostLifecycleTests.swift（L04：配对码显示 60 秒窗口、不进日志））

### P06 连上：只认配过对且验过签名的那台，验签之后才说

- **前置**：已配对的 iPhone；遥控模式开
- **步骤**：1. 打开 iPhone 遥控器连接；2. 观察刘海
- **预期可见结果**：验签通过后才出现“iPhone 已连接”，左耳是遥控器符号；验签前不显示、不说连上。
- **需要的证据**：刘海录屏＋接收器日志顺序（验签事件先于 UI 事件）
- **需要**：需要 iPhone
- **来源**：`docs/conductor-v2.md:68`
- **单测覆盖**：部分（RemoteHostLifecycleTests.swift（L04、L06）、CompanionChannelTests.swift）

### P07 没配过的 iPhone 验签失败：没连上，也没有任何输入进来

- **前置**：遥控模式开；另一台没配过的 iPhone
- **步骤**：1. 陌生 iPhone 选这台 Mac 并发起连接
- **预期可见结果**：不连上；没有指挥引擎被拉起；没有配对窗口被它打开。
- **需要的证据**：日志（not connected）＋ 无输入事件
- **需要**：自动可测、需要 iPhone
- **来源**：`docs/conductor-v2.md:68`；`docs/handoff/deepseek-conductor.md:158`
- **单测覆盖**：完整（RemoteHostLifecycleTests.swift（L08）、CompanionChannelTests.swift）

### P08 “选择电视”列表里是这台 Mac 的名字，且只在遥控模式开着时出现

- **前置**：同 P01
- **步骤**：1. 遥控模式关着时在 iPhone 上看列表；2. 打开遥控模式后再看
- **预期可见结果**：关着时找不到；开着时出现且名字是这台 Mac 的名字。
- **需要的证据**：iPhone 截图（两种状态）
- **需要**：需要 iPhone
- **来源**：`docs/conductor-v2.md:31`
- **单测覆盖**：无（没找到）

## S · 选会话、层与键位

*v2 把“档位 / 模型”两个域改成层，旧场景 C-024 作废*

### S01 展开那一排，走进编程会话

- **前置**：已连上；指挥模式开；至少有一个接得上的编程会话
- **步骤**：1. 触控区往下滑，展开刘海那一排；2. 左右滑到会话格；3. 点一下
- **预期可见结果**：刘海写“指挥棒 · 项目 · Claude · high”一类连上状态（无“指挥 ·”前缀）；左耳换成指挥棒；侧边键按住也能同时走进并开始听。
- **需要的证据**：刘海录屏＋ RemoteMode/ConductorSession 日志的层变化
- **需要**：自动可测、需要 iPhone
- **来源**：`docs/conductor-v2.md:69`；`docs/conductor-v2.md:34`
- **单测覆盖**：完整（RemoteLayerHostTests.swift（M09）、RemoteModeTests.swift（I1f））

### S02 那一排只列接得上的会话；等你的先落焦点；“新开一个”写明是新的

- **前置**：同时有跑着的、等审批的、已完成的会话
- **步骤**：1. 展开那一排，看会话格顺序与初始焦点
- **预期可见结果**：竖线右边只列接得上的会话；有等你的，焦点先落在它上面；新开的格子明写“新开一个”。
- **需要的证据**：刘海截图＋会话列表快照
- **需要**：自动可测
- **来源**：`docs/conductor-v2.md:69`
- **单测覆盖**：部分（ConductorPageTests.swift（会话列表按快照排序、修订号）——不含“等你的先落焦点”）

### S03 不看前台窗口、不动光标、不合成键鼠、不往前台窗口发东西

- **前置**：前台是任意其他 App
- **步骤**：1. 全程用遥控器走完选会话、画档位、说话、发送；2. 观察光标与前台 App
- **预期可见结果**：光标不动、前台窗口不变、没有 CGEvent 键鼠合成。
- **需要的证据**：静态检查：conductor 代码路径无 CGEvent 调用（rg）＋ 真机录屏光标位置
- **需要**：自动可测、需要 iPhone
- **来源**：`docs/conductor-v2.md:12`；`docs/handoff/deepseek-conductor.md:44`
- **单测覆盖**：无（没找到）

### S04 换会话：电视键点一下回到那一排，草稿留在原会话

- **前置**：在会话里且有未发草稿
- **步骤**：1. 电视键点一下；2. 在那一排换另一个会话；3. 再换回来
- **预期可见结果**：回到那一排；草稿、在跑的任务和在途命令留在原会话；换来换回不恢复旧发送票据；草稿不被带到新目标。
- **需要的证据**：日志（returnToRow 效果）＋ 草稿归属检查
- **需要**：自动可测
- **来源**：`docs/conductor-v2.md:35`；`docs/conductor-v2.md:71`；`docs/handoff/ws2-reuse-2026-10-07/conductor.md:15（切会话时草稿按会话留在内存）`
- **单测覆盖**：完整（ConductorSessionTests.swift、ConductorOwnedFlowTests.swift、RemoteLayerHostTests.swift）

### S05 返回 / 往上滑：取消眼前这一件，没有了就退一层

- **前置**：分别处于模型位置、候选、审批、草稿、会话中
- **步骤**：1. 在每种状态下按返回；再试往上滑
- **预期可见结果**：依次取消：模型位置 → 候选 → 审批（= 不允许）→ 草稿（按两次才丢）；都没有就回到那一排；往上滑与返回同义。
- **需要的证据**：每种状态一段刘海录屏＋状态机日志
- **需要**：自动可测、需要 iPhone
- **来源**：`docs/conductor-v2.md:38`；`docs/conductor-v2.md:25`；`docs/handoff/deepseek-conductor.md:96`
- **单测覆盖**：完整（ConductorSessionTests.swift、RemoteModeTests.swift（返回退一层））

### S06 电视键按住 ≥ 0.5 秒：启动台；松开不再补短按

- **前置**：任意层
- **步骤**：1. 按住电视键 1 秒后松开；2. 短按电视键
- **预期可见结果**：按住半秒打开启动台，松开不重复、不回到那一排；不到半秒松开是点一下。没有按下/松开事件的键不接启动台。
- **需要的证据**：刘海录屏＋事件日志
- **需要**：自动可测、需要 iPhone
- **来源**：`docs/conductor-v2.md:36`；`docs/handoff/deepseek-conductor.md:89`
- **单测覆盖**：完整（RemoteModeTests.swift、SiriRemoteButtonsTests.swift、ConductorSessionTests.swift、RemoteLayerHostTests.swift）

### S07 电源键 = 收工：全部收回刘海，不睡眠 Mac，后端任务照跑

- **前置**：会话里有一个正在跑的任务
- **步骤**：1. 按电源键
- **预期可见结果**：刘海写“收工 · 任务还在跑”；画面收回；Mac 不睡眠；不发 interrupt；会话、草稿都留着。
- **需要的证据**：刘海录屏＋ `pmset -g log` 无睡眠＋后端任务仍在跑的证据
- **需要**：自动可测、需要 iPhone
- **来源**：`docs/conductor-v2.md:41`；`docs/conductor-v2.md:83`；`docs/handoff/deepseek-conductor.md:101`
- **单测覆盖**：完整（ConductorSessionTests.swift、RemoteModeTests.swift（电源收工不请求睡眠）、RemoteLayerHostTests.swift）

### S08 静音键只管 Mac 上的提示音

- **前置**：遥控已连上
- **步骤**：1. 按静音键；2. 再按一次；3. 画一个声调听反馈
- **预期可见结果**：刘海写“提示音已关 / 已开”；不改系统静音；关着时一声都不响。
- **需要的证据**：刘海截图＋系统静音状态不变＋音频输出监测
- **需要**：自动可测、需要 iPhone
- **来源**：`docs/conductor-v2.md:40`；`docs/conductor-v2.md:94`
- **单测覆盖**：完整（ConductorSoundTests.swift（开关）、RemoteModeTests.swift（静音只管提示音））

### S09 iPhone 音量键照常调 Mac 音量；不调档、不放行

- **前置**：遥控已连上；会话里有候选或审批
- **步骤**：1. 按 iPhone 音量加减
- **预期可见结果**：Mac 音量变化；档位、候选、审批都不动。会话里也一样。
- **需要的证据**：Mac 音量读数前后对比＋状态机无变化
- **需要**：自动可测、需要 iPhone
- **来源**：`docs/conductor-v2.md:42`；`docs/handoff/ws2-reuse-2026-10-08/CLAUDE-HANDOFF.md:119（需通告 MediaControlFlags 0x0100 音量键才可用；探针仍为 0）`
- **单测覆盖**：部分（RemoteModeTests.swift、RemoteLayerHostTests.swift（音量、提示音、播放暂停每层一样））

### S10 本机在用时遥控让着；一排 10 秒没有输入自动收回

- **前置**：遥控已连上；第 1 层展开着
- **步骤**：1. 等 10 秒不动；2. 展开后动一下键盘或鼠标；3. 把指针移进刘海
- **预期可见结果**：10 秒无遥控输入自动收回第 0 层，不放回窗口；刚用过键盘/指针（2 秒内）遥控让着；指针在刘海里时那一排归指针；两个时间常量都标“暂定”。
- **需要的证据**：注入时钟的单测输出＋一次真机观察
- **需要**：自动可测
- **来源**：tests/RemoteLayerHostTests.swift（常量 10 秒、2 秒，文案“暂定”）
- **单测覆盖**：完整（RemoteLayerHostTests.swift）
- **推断**：v2 没规定 10 秒/2 秒，行为来自 RemoteLayerHostTests 与 WS2RemoteHost 现有实现，要 Aaron 确认是否进验收

### S11 指挥交互优先于音乐等持续活动与短暂提醒；被打断的活动原样回来；减少动态效果只淡入淡出

- **前置**：音乐在播；指挥模式在画声调
- **步骤**：1. 来一个短暂提醒；2. 画完后看音乐活动；3. 打开“减少动态效果”再走一遍
- **预期可见结果**：画、录音、审批期间不被音乐和提醒挤掉；结束后被打断的活动原样回来、不补播；减少动态效果时只淡入淡出；指挥态用已有刘海面板，不新开窗口或浮层。
- **需要的证据**：录屏＋活动协调器日志
- **需要**：自动可测、需要 iPhone
- **来源**：`docs/handoff/deepseek-conductor.md:125-126`；`docs/handoff/deepseek-conductor.md:129`
- **单测覆盖**：无（没找到）

### S12 坐在 Mac 前不用遥控器：刘海里看会话在跑、等你、完成，能批准，点一下到那扇终端

- **前置**：Claude Code 的 hook 已按设置页预览配置好；有一个在跑的会话
- **步骤**：1. 看刘海里的会话状态；2. 点一下一个会话；3. 在刘海里批准一次普通审批
- **预期可见结果**：状态实时；点一下到对应终端；批准走已有授权链路。指挥模式走进的正是这些会话。
- **需要的证据**：录屏＋hook 事件日志
- **需要**：自动可测、需要额度
- **来源**：`docs/conductor-v2.md:121`；`docs/agents-in-notch.md`
- **单测覆盖**：无（未核对（另有会话活动测试，如 SessionActivityTests.swift，不在本次范围））

## T · 档位（声调与拍子）

*v3 C2：识别器，原 ID C-011…C-022*

### T01 四个声调选档位：一声 low、二声 medium、三声 high、四声 xhigh

- **v3 原 ID 线索**：C-011…C-014
- **前置**：已走进会话；后端支持四档
- **步骤**：1. 依次画 → ↗ ˇ ↘ 各一笔，抬手
- **预期可见结果**：分别设为下一轮 low/medium/high/xhigh；四声不会得到 max；y 轴向下的原始坐标先翻转，二声不会变成四声；自然抖动不改档。
- **需要的证据**：识别器测试输出＋真机每个声调 5 次的命中表
- **需要**：自动可测、需要 iPhone
- **来源**：`docs/conductor-v2.md:51-54`；`docs/conductor.md:25-28`
- **单测覆盖**：完整（ConductorGestureTests.swift、ConductorSessionTests.swift（声调 n））

### T02 一到四拍选 low…xhigh

- **v3 原 ID 线索**：C-020 一带
- **前置**：同 T01
- **步骤**：1. 触控区点落并回弹 1、2、3、4 拍
- **预期可见结果**：对应 low/medium/high/xhigh；每拍落下 ≥ 0.12、回弹 ≥ 落差 40%；拍点间隔 0.15–1.1 秒。
- **需要的证据**：识别器测试输出＋真机命中表
- **需要**：自动可测、需要 iPhone
- **来源**：`docs/conductor-v2.md:55`；`docs/conductor.md:29`
- **单测覆盖**：完整（ConductorGestureTests.swift、ConductorSessionTests.swift（n 拍））

### T03 五拍 = max、六拍 = ultra，只来自完整的五/六拍

- **v3 原 ID 线索**：C-018, C-019
- **前置**：同 T01
- **步骤**：1. 打五拍后抬手；2. 打六拍后抬手；3. 第六拍中途抬手；4. 打七拍
- **预期可见结果**：五拍 → max 候选；六拍 → ultra 候选；第六拍中途抬手被拒、不当五拍；七拍拒识不钳成六拍；候选都需 M01 的点一下确认。
- **需要的证据**：识别器测试输出
- **需要**：自动可测
- **来源**：`docs/conductor-v2.md:56-57`；`docs/conductor.md:30`
- **单测覆盖**：完整（ConductorGestureTests.swift、ConductorSessionTests.swift）

### T04 画的过程中只亮已完成的拍，抬手才判定，不先切档

- **v3 原 ID 线索**：C-018/019 预览
- **前置**：同 T01
- **步骤**：1. 打五拍，看刘海上的拍点；2. 在第四拍后停住
- **预期可见结果**：刘海 ●●●●○○ 只亮已完成的拍，标题“抬手才判定”；第四拍只亮第四个点，档位仍是原值；判定后写“三声 · high”和“项目 · 助手”，不再画拍点。
- **需要的证据**：刘海录屏逐拍截图＋测试输出
- **需要**：自动可测、需要 iPhone
- **来源**：`docs/conductor-v2.md:60`；`docs/conductor-v2.md:72-73`；`docs/conductor.md:21`
- **单测覆盖**：完整（ConductorViewModelTests.swift、ConductorSessionTests.swift、ConductorGestureTests.swift（beatPreview））

### T05 拒识：太小、太短、太长、竖滑、从右往左、折返、碎折线、斜率夹中、最后一拍没回弹、二义（窄 V）、非法坐标

- **v3 原 ID 线索**：C-015, C-016, C-017, C-020, C-021, C-022
- **前置**：同 T01
- **步骤**：1. 逐种画出这些笔画并抬手
- **预期可见结果**：一律“没认出”，不猜最近的档位：< 触控区 15%、< 0.12 秒、整句 > 6 秒、竖直、右往左或折返、斜率在两档之间、碎折线、拍点间隔不在 0.15–1.1 秒、超过六拍、声调与拍子两种解释都成立、NaN/越界、时间倒流。
- **需要的证据**：识别器测试输出（每种拒识一条）＋真机复现表
- **需要**：自动可测、需要 iPhone
- **来源**：`docs/conductor.md:32-34`
- **单测覆盖**：完整（ConductorGestureTests.swift、ConductorSessionTests.swift（非法坐标、2048 点、6 秒未抬手））

### T06 速度不改变档位

- **v3 原 ID 线索**：C-021
- **前置**：同 T01
- **步骤**：1. 快、慢各画一遍五拍和三声
- **预期可见结果**：快慢档位一致（拍点间隔仍在 0.15–1.1 秒之内）。
- **需要的证据**：测试输出
- **需要**：自动可测
- **来源**：`docs/conductor-v2.md:60`；`docs/conductor.md:34`
- **单测覆盖**：完整（ConductorGestureTests.swift）

### T07 没认出：刘海写“没认出，保持 high”，不猜

- **前置**：当前档位 high
- **步骤**：1. 画一笔夹在两档之间的斜线
- **预期可见结果**：刘海“没认出，保持 high”；档位不变；回一声低闷的“咚”。
- **需要的证据**：刘海截图＋测试输出
- **需要**：自动可测、需要 iPhone
- **来源**：`docs/conductor-v2.md:102`；`docs/conductor-v2.md:94`
- **单测覆盖**：完整（ConductorSessionTests.swift、ConductorSoundTests.swift、ConductorGestureTests.swift）

### T08 后端不支持的档位：“这个模型没有 xhigh，保持 high”，不降档

- **前置**：当前模型的能力列表里没有 xhigh
- **步骤**：1. 画四声
- **预期可见结果**：刘海写“这个模型没有 xhigh，保持 high”；档位不变；不静默降档、不猜近似值。
- **需要的证据**：测试输出＋刘海截图
- **需要**：自动可测
- **来源**：`docs/conductor-v2.md:73`；`docs/handoff/deepseek-conductor.md:86`
- **单测覆盖**：完整（ConductorSessionTests.swift、ConductorCapabilitiesTests.swift）

### T09 ultra 的含义由后端能力决定；绝不默默降档、绝不发不支持的值

- **前置**：分别用三种后端：有原生 ultra / Claude 绑定了 ultracode / 都没有
- **步骤**：1. 各画六拍并确认
- **预期可见结果**：原生：按原生值；Claude：刘海“ultracode · xhigh · 工作流程开启”；都没有：“没有 ultra，保持原设置”。不发 effort=ultra 给不支持的后端，不在提示词里追加 ultrathink；Codex 不借用 Claude 的绑定。
- **需要的证据**：能力映射测试输出＋实际发出的请求字段记录
- **需要**：自动可测、需要额度
- **来源**：`docs/conductor-v2.md:57`；`docs/handoff/deepseek-conductor.md:110-113`
- **单测覆盖**：部分（ConductorCapabilitiesTests.swift、ConductorSessionTests.swift）

### T10 任务在跑时画手势只改下一轮，不打断这一轮

- **前置**：一个轮次正在跑
- **步骤**：1. 跑着时画一个四声
- **预期可见结果**：刘海“这一轮 high · 下一轮 xhigh”；当前轮不被打断；不发 turn/start、turn/steer、turn/interrupt。
- **需要的证据**：刘海截图＋协议记录无新请求
- **需要**：自动可测
- **来源**：`docs/conductor-v2.md:79`；`docs/handoff/deepseek-conductor.md:95`；`docs/handoff/ws2-reuse-2026-10-07/conductor.md:9`
- **单测覆盖**：完整（ConductorSessionTests.swift、ConductorOwnedFlowTests.swift（running permits next-turn effort））

### T11 提示音：每拍轻敲、认出回同走向短音、没认出一声“咚”，跟系统音量

- **前置**：提示音开
- **步骤**：1. 打三拍；2. 画一声到四声；3. 画一笔无效的
- **预期可见结果**：每完成一拍敲一下；一声平、二声升、三声先降后升、四声降；没认出低闷的“咚”；不削波；音量随系统。
- **需要的证据**：合成波形测试＋真机听感记录
- **需要**：自动可测、需要 iPhone
- **来源**：`docs/conductor-v2.md:94`
- **单测覆盖**：部分（ConductorSoundTests.swift）

### T12 真实遥控器轨迹回放后重新校阈值

- **前置**：有一批真实 iPhone 触控轨迹记录
- **步骤**：1. 用真实轨迹回放识别器；2. 统计每档误判/漏判
- **预期可见结果**：阈值（斜率、15%、0.12 秒、拍点间隔等）基于真实数据确认或调整；现有测试用合成轨迹。
- **需要的证据**：回放报告（命中矩阵、误判样本）
- **需要**：需要 iPhone
- **来源**：`docs/conductor.md:36`
- **单测覆盖**：部分（ConductorGestureTests.swift（只含合成轨迹））

## M · 确认与模型位置

*原 ID C-023…C-025 一带*

### M01 max/ultra 要“新的一下”点按确认；画完附带的那一下不算

- **v3 原 ID 线索**：C-023
- **前置**：已出现 max 或 ultra 候选
- **步骤**：1. 画完五拍抬手时手指带出的那一下；2. 候选出现前就按着中心、之后松开；3. 之后新点一下
- **预期可见结果**：前两者都不算确认；新的一下才生效，且只管下一次提交；轨迹里带 Select 不算确认。
- **需要的证据**：测试输出＋刘海“五拍 · max　点一下确认”截图
- **需要**：自动可测、需要 iPhone
- **来源**：`docs/conductor-v2.md:33`；`docs/conductor-v2.md:74`；`docs/conductor.md:39`
- **单测覆盖**：完整（ConductorSessionTests.swift、ConductorCapabilitiesTests.swift）

### M02 确认票据：绑定对象、一次性、30 秒期限，变了就作废

- **前置**：已出现候选
- **步骤**：1. 换会话 / 重连 / 超时 / 换模型 / 改草稿后再确认；2. 对同一票据消费两次
- **预期可见结果**：票据绑定 peer、项目、会话、模型、能力版本、草稿摘要、候选；任一项变化、重连、超时即作废；只第一次消费成功；max 下换模型要重新确认。
- **需要的证据**：测试输出（每项一条）
- **需要**：自动可测
- **来源**：`docs/conductor-v2.md:74`；`docs/handoff/deepseek-conductor.md:114-115`；`docs/handoff/deepseek-conductor.md:87`
- **单测覆盖**：完整（ConductorCapabilitiesTests.swift、ConductorSessionTests.swift）

### M03 往下滑展开四个模型位置，左右挪、点一下选中、往上滑或返回关掉

- **v3 原 ID 线索**：C-025
- **前置**：已在会话里
- **步骤**：1. 触控区往下滑；2. 往右滑一格，再点一下；3. 往上滑
- **预期可见结果**：展开后焦点落在当前模型；横线不当一声；点一下选中只改下一轮，档位不变；右边到头不绕回；空位不移位补足；往上滑/返回只关模型位置，不选、不退出会话；审批来了收起。
- **需要的证据**：刘海录屏＋测试输出
- **需要**：自动可测、需要 iPhone
- **来源**：`docs/conductor-v2.md:34`；`docs/conductor-v2.md:70`；`docs/conductor.md:40`
- **单测覆盖**：完整（ConductorSessionTests.swift、ConductorViewModelTests.swift（模型位置最多四个））

### M04 四个模型位置来自设置，不随后端列表排序变；缺失写“位置 2 的模型不可用”

- **前置**：设置里已填四个位置
- **步骤**：1. 让后端列表重排；2. 让其中一个模型消失；3. 重复身份
- **预期可见结果**：位置固定；缺失明说不可用且不补位；重复身份被拒。
- **需要的证据**：测试输出
- **需要**：自动可测
- **来源**：`docs/conductor-v2.md:59`；`docs/handoff/deepseek-conductor.md:116`
- **单测覆盖**：完整（ConductorCapabilitiesTests.swift、ConductorPageTests.swift（列表顺序随快照、缺失模型不替换））

### M05 竖滑不和画档位撞车

- **前置**：已在会话里
- **步骤**：1. 单向往下滑；2. 往上滑；3. 画一个落下又回弹一点的半拍
- **预期可见结果**：往下滑只开模型位置，不报“没认出”、不改档；半拍仍是没认出，不开模型位置；斜线（四声）归档位。
- **需要的证据**：测试输出
- **需要**：自动可测
- **来源**：`docs/conductor-v2.md:34`；`docs/conductor.md:32`
- **单测覆盖**：完整（ConductorSessionTests.swift）

## D · 草稿与语音


### D01 按住侧边按钮说话：真收到声音才画波形，来源写清

- **前置**：已在会话里；麦克风可用
- **步骤**：1. 按住侧边按钮说一句；2. 观察刘海
- **预期可见结果**：没有样本前不画波形，写“没有收到声音”；收到样本后画波形，副句“来源 · 松开出草稿”（如 iPhone 麦克风）。
- **需要的证据**：刘海录屏＋采集日志（样本到达时间）
- **需要**：需要 iPhone、需要麦克风与本人
- **来源**：`docs/conductor-v2.md:39`；`docs/conductor-v2.md:75`；`docs/handoff/deepseek-conductor.md:90`
- **单测覆盖**：部分（ConductorSessionTests.swift（侧键无源/有源无样本/有样本）、ConductorViewModelTests.swift（波形 20 根柱、RMS））

### D02 松开出草稿，不发送；没把握的词划线

- **前置**：D01 已完成一次说话
- **步骤**：1. 松开侧边按钮；2. 观察草稿三行
- **预期可见结果**：出草稿三行：给谁 / 全文 / 怎么发出去；没把握的词有下划线；人手一改就清掉；转写只成草稿，不自动提交。
- **需要的证据**：刘海截图＋转写与草稿日志
- **需要**：需要 iPhone、需要麦克风与本人
- **来源**：`docs/conductor-v2.md:76`；`docs/conductor-v2.md:39`
- **单测覆盖**：部分（ConductorViewModelTests.swift、ConductorSessionTests.swift）

### D03 音源中途断了：停止，草稿留着，不自动换麦克风

- **前置**：正在录音
- **步骤**：1. 录音时让 iPhone 麦克风中断（锁屏/断连）
- **预期可见结果**：停止采集；已有草稿保留；不换别的麦克风；音源丢失后晚到的转写不覆盖原草稿。
- **需要的证据**：采集日志＋草稿前后对比
- **需要**：需要 iPhone、需要麦克风与本人
- **来源**：`docs/conductor-v2.md:75`；`docs/conductor-v2.md:103`
- **单测覆盖**：部分（ConductorSessionTests.swift）

### D04 麦克风没声音：写“没有收到声音”，分清“安静”和“没回调”

- **前置**：按住侧边按钮但不说话 / 麦克风回调不来
- **步骤**：1. 安静按住；2. 让采集回调不到达
- **预期可见结果**：两种情况分别可区分；都不画假波形、不自动提交。
- **需要的证据**：日志中两种状态的区分字段
- **需要**：需要 iPhone、需要麦克风与本人
- **来源**：`docs/conductor-v2.md:103`
- **单测覆盖**：部分（ConductorViewModelTests.swift（等声音不画波形）、ConductorSessionTests.swift）

### D05 侧边按钮没有按下/松开阶段时：点一下开始、再点一下停，最长 60 秒

- **前置**：E2 结论是侧键只有 click
- **步骤**：1. 点一下开始说话；2. 再点一下；3. 不点第二下等 60 秒
- **预期可见结果**：第二下停止并等转写；60 秒自动停一次；仍不自动提交。
- **需要的证据**：测试输出＋真机一次
- **需要**：自动可测、需要 iPhone
- **来源**：`docs/conductor-v2.md:39`；`docs/conductor-v2.md:114`；`docs/handoff/deepseek-conductor.md:90-91`
- **单测覆盖**：完整（ConductorSessionTests.swift（clickOnly））

### D06 iPhone 键盘改草稿，随打随变；可用键盘听写

- **前置**：草稿已展开；E3 结论为可行
- **步骤**：1. 弹出键盘改字；2. 用键盘听写
- **预期可见结果**：草稿随打随变；改过后旧转写不再覆盖；不改变发送确认。
- **需要的证据**：录屏
- **需要**：需要 iPhone
- **来源**：`docs/conductor-v2.md:43`；`docs/conductor-v2.md:115`
- **单测覆盖**：部分（ConductorSessionTests.swift（editDraft））

### D07 录音期间手动编辑，旧转写随后完成不覆盖手动内容

- **前置**：正在录音，已有草稿
- **步骤**：1. 录音时编辑草稿；2. 转写完成
- **预期可见结果**：草稿保持手动版本；旧结果被版本号丢弃。
- **需要的证据**：测试输出
- **需要**：自动可测、需要 iPhone
- **来源**：`docs/conductor-v2.md:76`；tests/ConductorSessionTests.swift（断言“草稿版本防旧结果覆盖”）
- **单测覆盖**：完整（ConductorSessionTests.swift）
- **推断**：v2 没单列此情形，来自会话测试既有断言与“人手一改就清掉”的草稿规则

### D08 返回按两次才丢草稿

- **前置**：有未发草稿
- **步骤**：1. 按一次返回；2. 再按一次
- **预期可见结果**：第一次刘海“再按一次返回丢掉草稿”，不丢；第二次才丢；有候选时先取消候选。
- **需要的证据**：刘海截图＋测试输出
- **需要**：自动可测、需要 iPhone
- **来源**：`docs/conductor-v2.md:38`；`docs/conductor-v2.md:76`；`docs/handoff/deepseek-conductor.md:96`
- **单测覆盖**：完整（ConductorSessionTests.swift）

## A · 发送与审批


### A01 播放键发出去：发出去了 → 后端接受了（读回档位）→ 开始跑

- **前置**：有草稿；后端空闲
- **步骤**：1. 按播放键；2. 观察三段文案
- **预期可见结果**：三件事分三次说：“发出去了”“Claude 接受了 · high”“开始跑了”；读不回实际档位写“实际档位还没确认”；后端改档位如实显示。
- **需要的证据**：刘海录屏＋后端 turn/start 请求与回执记录
- **需要**：需要 iPhone、需要额度
- **来源**：`docs/conductor-v2.md:77`；`docs/conductor-v2.md:37`；`docs/handoff/deepseek-conductor.md:94`
- **单测覆盖**：部分（ConductorSessionTests.swift、ConductorOwnedFlowTests.swift（假后端，真实 stdio））

### A02 采用草稿与发送分开；同一草稿不会提交两次

- **前置**：草稿已写好
- **步骤**：1. 采用草稿；2. 快速重复按播放键；3. 重发 up 事件
- **预期可见结果**：采用不发请求；发送才发 turn/start；重复按键、重复 up、重发事件不产生第二次提交；等回执期间新编辑的字保留；同一 commandID 只提交一次。
- **需要的证据**：协议记录里 turn/start 只出现一次
- **需要**：自动可测
- **来源**：`docs/handoff/ws2-reuse-2026-10-07/conductor.md:11`；`docs/handoff/deepseek-conductor.md:102`
- **单测覆盖**：完整（ConductorOwnedFlowTests.swift、ConductorSessionTests.swift、ConductorPageTests.swift）

### A03 补一句：任务在跑时有草稿，播放键补进这一轮

- **前置**：一个轮次正在跑，说一句新话
- **步骤**：1. 按播放键
- **预期可见结果**：发 turn/steer 且带当前 turnID；收到对应回执才写“已补进这一轮”；错轮回执不清草稿；不静默把新轮发送变成补充。
- **需要的证据**：协议记录＋刘海截图
- **需要**：自动可测、需要额度
- **来源**：`docs/conductor-v2.md:78`；`docs/conductor-v2.md:37`；`docs/handoff/deepseek-conductor.md:92-93`；`docs/handoff/ws2-reuse-2026-10-07/conductor.md:11-13`
- **单测覆盖**：完整（ConductorSessionTests.swift、ConductorOwnedFlowTests.swift）

### A04 停下：没草稿时播放键请求停下，后端真停了才写已停止

- **前置**：一个轮次正在跑，没草稿
- **步骤**：1. 按播放键
- **预期可见结果**：先“正在停止…”；interrupt RPC 返回不算；收到真实的终止通知才写“已停止”；旧的停止不能打到后来的轮次。
- **需要的证据**：协议记录里 turn/completed(interrupted) 与刘海文案的先后
- **需要**：自动可测、需要额度
- **来源**：`docs/conductor-v2.md:81`；`docs/conductor-v2.md:37`；`docs/handoff/deepseek-conductor.md:92-93`；`docs/handoff/ws2-reuse-2026-10-07/conductor.md:13`
- **单测覆盖**：完整（ConductorSessionTests.swift、ConductorOwnedFlowTests.swift）

### A05 后端明确拒绝：保留草稿，不自动重试

- **前置**：后端会返回拒绝
- **步骤**：1. 发送一次会被拒的草稿
- **预期可见结果**：草稿原样保留；没有自动重发；用户再按才是新的提交（新 commandID）。
- **需要的证据**：协议记录＋草稿对比
- **需要**：自动可测
- **来源**：`docs/conductor-v2.md:101`；`docs/handoff/deepseek-conductor.md:171`
- **单测覆盖**：完整（ConductorSessionTests.swift、ConductorOwnedFlowTests.swift）
- **推断**：v2/D6 只写“不重发可能已执行的提交”；“拒绝后保留草稿”来自会话与拥有流程测试的既有断言

### A06 普通审批：点一下 = 允许这一次，返回 = 不允许；出现前那一下不算

- **前置**：一个读文件/跑测试/改工作区文件的审批出现
- **步骤**：1. 审批前按下、审批后松开；2. 审批出现后点一下；3. 另一次改按返回
- **预期可见结果**：前者不确认；后者允许一次且绑定请求号/命令/范围；返回 = 不允许、草稿不动；遥控器上没有“始终允许”。
- **需要的证据**：授权账记录＋刘海截图
- **需要**：自动可测、需要 iPhone、需要额度
- **来源**：`docs/conductor-v2.md:87`；`docs/conductor-v2.md:91`；`docs/handoff/deepseek-conductor.md:97`
- **单测覆盖**：部分（ConductorSessionTests.swift、AuthorizationLedgerTests.swift）

### A07 高风险审批：配对的 iPhone + 声纹 + 随机短语三样都对才放行，或到 Mac 前按 Touch ID

- **前置**：出现推送/删除/联网/改工作区外文件/关安全设置之一的审批；声纹已录入
- **步骤**：1. 点一下；2. 按住侧边按钮念刘海给的短语；3. 分别试：声纹错、短语错、都对、改用 Touch ID
- **预期可见结果**：三项都对才放行；任何一项错就不允许并给出 Touch ID 出路；声纹不单独放行；短语随机、有期限。
- **需要的证据**：刘海录屏＋授权账（附加证据 ≠ allow）＋声纹/短语判定日志
- **需要**：自动可测、需要麦克风与本人、需要 iPhone
- **来源**：`docs/conductor-v2.md:88-90`；`docs/conductor-v2.md:19`；`docs/handoff/deepseek-conductor.md:97-98`
- **单测覆盖**：部分（ConductorSessionTests.swift（voiceCheck 分支））

### A08 每次放行绑定请求号、命令、范围，走授权账，用一次作废

- **前置**：任一审批
- **步骤**：1. 放行后重放同一放行；2. 改命令后再用旧放行
- **预期可见结果**：重放、换命令、换范围都失败；放行用一次作废。审批期限到期交回宿主，不降级自动批准。
- **需要的证据**：授权账测试输出
- **需要**：自动可测
- **来源**：`docs/conductor-v2.md:91`；`docs/handoff/deepseek-conductor.md:97-98`
- **单测覆盖**：部分（AuthorizationLedgerTests.swift、ConductorSessionTests.swift（挑战超时、审批到期））

### A09 完成：“完成 · 改了 3 个文件”，点一下看摘要，在 Mac 上开原来的 diff，不触发 review

- **前置**：一个轮次完成
- **步骤**：1. 看刘海；2. 点一下；3. 看 Mac 上打开的内容
- **预期可见结果**：折起来一行、点一下展开全文；在 Mac 上用原来的 diff 查看方式；看 diff 不触发 review。
- **需要的证据**：刘海录屏＋ diff 查看器被打开的证据
- **需要**：需要 iPhone、需要额度
- **来源**：`docs/conductor-v2.md:82`
- **单测覆盖**：部分（ConductorViewModelTests.swift（完成折起来一行）——只覆盖折叠）

## R · 异常与恢复


### R01 遥控器关了或 Wi-Fi 断：刘海“遥控器断开了”，一切未确认的东西取消

- **前置**：会话里有画到一半的手势、候选、录音和未发草稿
- **步骤**：1. 在 iPhone 上退出遥控器，或断 Wi-Fi；2. 重连
- **预期可见结果**：手势、候选、录音取消；后端任务照跑；草稿保留；重连只显示现状，不自动提交；重连 epoch 变化后旧 epoch 的回执一律丢弃。
- **需要的证据**：刘海截图＋状态机日志（epoch）
- **需要**：自动可测、需要 iPhone
- **来源**：`docs/conductor-v2.md:100`；`docs/handoff/deepseek-conductor.md:100`
- **单测覆盖**：完整（ConductorSessionTests.swift、RemoteHostLifecycleTests.swift）

### R02 后端断了：“连不上 Claude”，草稿留着，不重发可能已执行的提交

- **前置**：有一个已发送但未回执的提交
- **步骤**：1. 断开后端进程/连接
- **预期可见结果**：刘海说连不上谁；草稿留着；先查询状态，不重发。
- **需要的证据**：协议记录无第二次 turn/start
- **需要**：自动可测、需要额度
- **来源**：`docs/conductor-v2.md:101`
- **单测覆盖**：完整（ConductorSessionTests.swift）

### R03 命令 15 秒无回执：查询状态，不重发；证实未执行后仍要人工再按

- **前置**：提交已发出
- **步骤**：1. 让后端 15 秒不回执；2. 之后让查询返回“未执行 / 在跑 / 已完成”
- **预期可见结果**：进入未知态；未知期拒绝二次发送；查询结果证明未执行后也不自动发；新的人为提交另建 commandID；断线重连先查询。
- **需要的证据**：协议记录（查询请求、无重发）
- **需要**：自动可测
- **来源**：`docs/handoff/deepseek-conductor.md:171`；`docs/conductor-v2.md:101`；`docs/conductor-v2.md:100`
- **单测覆盖**：完整（ConductorSessionTests.swift）

### R04 Mac 锁屏：清项目名与草稿，输入作废，解锁后不自动发

- **前置**：会话里有草稿、手势画到一半
- **步骤**：1. 锁屏；2. 解锁
- **预期可见结果**：刘海不显示项目名和草稿；取消手势、候选、采集；解锁后回到第 0 层，等重连，不自动提交；旧回调不能复活内容。
- **需要的证据**：状态机日志＋锁屏期间刘海截图
- **需要**：自动可测、需要 iPhone
- **来源**：`docs/conductor-v2.md:106`；`docs/handoff/deepseek-conductor.md:99`
- **单测覆盖**：完整（ConductorSessionTests.swift、RemoteHostLifecycleTests.swift（L07）、ConductorOwnedFlowTests.swift（锁屏撤销））

### R05 配对被撤销：立刻断开，刘海“这台 iPhone 不能再遥控了”

- **前置**：一台已连接的 iPhone
- **步骤**：1. 在设置里撤销它（或移除）
- **预期可见结果**：立刻断开；撤销后它不能再通过验签；后端任务不停。
- **需要的证据**：日志＋再次连接被拒的记录
- **需要**：自动可测、需要 iPhone
- **来源**：`docs/conductor-v2.md:107`；`docs/conductor-v2.md:67`
- **单测覆盖**：完整（RemoteHostLifecycleTests.swift（L09）、ConductorSessionTests.swift）

### R06 另一台 iPhone 也在指挥：同一时间只有一台能发

- **前置**：两台已配对 iPhone
- **步骤**：1. 第一台连上后，第二台连上并操作
- **预期可见结果**：第二台被告知“另一台 iPhone 正在指挥”并被关闭；它的输入不产生任何动作；有效会话配置不变。
- **需要的证据**：日志（operator 切换）
- **需要**：自动可测、需要 iPhone
- **来源**：`docs/conductor-v2.md:105`
- **单测覆盖**：完整（RemoteHostLifecycleTests.swift（L06）、ConductorSessionTests.swift（other-peer））

### R07 审批挑战超时或风险未知：不降级自动批准，交回主认证

- **前置**：高风险审批已出现
- **步骤**：1. 不念短语等超时；2. 来一个无法判定风险的审批
- **预期可见结果**：挑战超时请求 Touch ID；未知风险不自动批准。
- **需要的证据**：状态机日志
- **需要**：自动可测
- **来源**：`docs/conductor-v2.md:88-89`；`docs/handoff/deepseek-conductor.md:97-98`
- **单测覆盖**：完整（ConductorSessionTests.swift）
- **推断**：v2/D1 只规定“念短语、两项都过才允许、给 Touch ID 出路”；超时与未知风险行为来自会话测试既有断言

## V · 隐私与安全


### V01 隐私登记四项并如实存放

- **前置**：指挥模式开
- **步骤**：1. 打开隐私页；2. 检查钥匙串与磁盘
- **预期可见结果**：登记：遥控器触摸轨迹（只在遥控模式开着时，不存）；按住侧边按钮的声音（转写后丢弃，不写日志）；声纹模板（加密存本机）；配对密钥（钥匙串）。登记与实际存放一致。
- **需要的证据**：隐私页截图＋磁盘/钥匙串检查脚本输出
- **需要**：自动可测
- **来源**：`docs/conductor-v2.md:143`；`docs/handoff/deepseek-conductor.md:145`
- **单测覆盖**：无（没找到）

### V02 声音与轨迹不落盘、不进日志

- **前置**：完整走一遍说话、画档位、发送
- **步骤**：1. 事后检索应用日志与临时目录
- **预期可见结果**：找不到音频样本、转写原文、触摸坐标；日志里没有 PIN、密钥、原始包。
- **需要的证据**：日志与文件系统检索结果
- **需要**：自动可测、需要 iPhone、需要麦克风与本人
- **来源**：`docs/conductor-v2.md:143`；`docs/handoff/ws2-reuse-2026-10-08/CLAUDE-HANDOFF.md:73`
- **单测覆盖**：部分（RemoteHostLifecycleTests.swift（配对码、名字不进日志））

### V03 协议层不接收 shell 字符串、项目路径、模型密钥；它崩了不影响 WindowShade 找回窗口

- **前置**：接收器运行中
- **步骤**：1. 向接收器发畸形/越权消息；2. 强行结束接收器
- **预期可见结果**：畸形消息被拒；接收器退出后窗口找回照常。
- **需要的证据**：协议负例测试输出＋进程崩溃后找回窗口的验证
- **需要**：自动可测
- **来源**：`docs/conductor-v2.md:139`
- **单测覆盖**：部分（CompanionChannelTests.swift（畸形 OPACK、未知方法））

### V04 未知设备、重放、错签名都被拒

- **前置**：接收器开着
- **步骤**：1. 用未登记公钥、旧消息重放、错误签名分别连接
- **预期可见结果**：全部被拒并关闭连接；不产生授权票据。
- **需要的证据**：测试输出（每类一条）
- **需要**：自动可测
- **来源**：`docs/conductor-v2.md:157`；`docs/handoff/deepseek-conductor.md:158`
- **单测覆盖**：完整（CompanionChannelTests.swift、CompanionTransportTests.swift）

### V05 遥控输入不能绕过 Touch ID 或 agent 审批；手机认证 ≠ 对任意目标的授权

- **前置**：遥控已连上
- **步骤**：1. 用遥控输入尝试：盲发回车、绕过审批、候选输入抵达动作出口
- **预期可见结果**：都不发生；候选兼容输入不抵达动作出口；撤销即时阻止后续收发。
- **需要的证据**：拒绝路径测试＋日志
- **需要**：自动可测
- **来源**：`docs/handoff/ws2-reuse-2026-10-08/CLAUDE-HANDOFF.md:98-102`
- **单测覆盖**：部分（CompanionChannelTests.swift、AuthorizationLedgerTests.swift）

### V06 调试端口与 inspector 默认关闭

- **前置**：发布版构建
- **步骤**：1. 检查监听端口
- **预期可见结果**：没有调试端口；协议层不执行命令，只报事件。
- **需要的证据**：端口扫描输出
- **需要**：自动可测
- **来源**：`docs/handoff/deepseek-conductor.md:159`
- **单测覆盖**：无（没找到）

### V07 测试面板与合成输入只在开发版带启动参数才出现

- **前置**：发布版与开发版各一份
- **步骤**：1. 启动发布版；2. 启动开发版带参数
- **预期可见结果**：发布版里没有；开发版带参数才有。
- **需要的证据**：两份构建的启动对比截图
- **需要**：自动可测
- **来源**：`docs/handoff/deepseek-conductor.md:130-131`
- **单测覆盖**：无（没找到）

## E · 能耗与性能


### E01 只在遥控模式开着时宣告和监听；没连时不轮询

- **前置**：遥控模式关 / 开但无 iPhone 连接
- **步骤**：1. 分别静置 5 分钟，抓空闲唤醒数
- **预期可见结果**：关着：无 listener、无定时器；开着没连：只有宣告/监听，不轮询。
- **需要的证据**：powermetrics/Activity Monitor 空闲唤醒记录＋ L02 单测输出
- **需要**：自动可测
- **来源**：`docs/conductor-v2.md:147`；`docs/conductor-v2.md:66`
- **单测覆盖**：部分（RemoteHostLifecycleTests.swift（L02 quiet, no timers））

### E02 延迟：Mac 收到输入到刘海有反应 p95 ≤ 50 ms，抬手到结果 p95 ≤ 100 ms

- **前置**：遥控已连上
- **步骤**：1. 各 100 次连续测量
- **预期可见结果**：两个 p95 达标才能写进宣传，实测前不写。
- **需要的证据**：延迟直方图与 p95 数值
- **需要**：需要 iPhone
- **来源**：`docs/conductor-v2.md:147`
- **单测覆盖**：无（没找到）

### E03 长会话能耗与资源：高频触控、错误事件下内存与队列有界

- **前置**：遥控已连上，持续 30 分钟以上
- **步骤**：1. 持续高频滑动；2. 注入大量错误事件
- **预期可见结果**：内存不增长、发送队列有界、退出有期限；诊断输出有界。
- **需要的证据**：内存/队列曲线＋能耗读数
- **需要**：自动可测、需要 iPhone
- **来源**：`docs/conductor-v2.md:160（W7 能耗）`；`docs/handoff/ws2-reuse-2026-10-08/CLAUDE-HANDOFF.md:73-77（C1：NET-09）`
- **单测覆盖**：部分（CompanionTransportTests.swift（队列 16 项 / 262144 字节上限））

## B · 后端适配器与发布资格

*W5/W7*

### B01 Codex 适配器在假服务器上：成功、拒绝、超时、中断、审批、断线

- **前置**：tests/fixtures 里有假服务器脚本
- **步骤**：1. 跑适配器测试
- **预期可见结果**：按 initialize → model/list → thread/start|resume → turn/start|steer|interrupt 走通；字段名无官方依据的标“待对照官方文档”；不启动真实 Codex 进程。
- **需要的证据**：测试输出
- **需要**：自动可测
- **来源**：`docs/handoff/deepseek-conductor.md:166-172`；`docs/conductor-v2.md:136`
- **单测覆盖**：完整（ConductorOwnedFlowTests.swift（合成 codex 可执行文件，真实 stdio））

### B02 一次真实的 Codex 只读任务

- **前置**：Codex 账号可用，只读审批策略
- **步骤**：1. 走完选会话 → 草稿 → 发送 → 完成
- **预期可见结果**：真实 model/list 档位出现在位置里；任务按只读完成；审批策略保持 read-only / on-request / 用户审批。
- **需要的证据**：真实协议记录＋刘海录屏
- **需要**：需要 iPhone、需要额度
- **来源**：`docs/conductor-v2.md:158`；`docs/handoff/ws2-reuse-2026-10-07/conductor.md:23`
- **单测覆盖**：无（没找到）

### B03 Claude 适配器：持续会话，ultracode 绑定与档位读回

- **前置**：Claude 账号可用
- **步骤**：1. 走完一次发送、补一句、停下、审批
- **预期可见结果**：档位读回与请求一致或如实显示差异；六拍按 B 档位映射；其余同 A 组。
- **需要的证据**：真实协议/SDK 记录
- **需要**：需要 iPhone、需要额度
- **来源**：`docs/conductor-v2.md:136`；`docs/conductor-v2.md:160`
- **单测覆盖**：无（没找到）

### B04 发布资格：独立攻防审查

- **前置**：W1–W6 完成
- **步骤**：1. 由另一个模型/人按协议层与授权路径做攻防
- **预期可见结果**：没有未处理的越权/绕过发现。
- **需要的证据**：攻防报告与处置记录
- **需要**：需要额度
- **来源**：`docs/conductor-v2.md:160`
- **单测覆盖**：无（没找到）
- **推断**：v2 W7 只写“发布资格（独立攻防、能耗）”，攻防范围没有展开；这条是占位

## 标为推断的场景

- **P04** 配对要等 Touch ID 回执；取消、拒绝或晚到的成功都不入库：v2:67 只写“输对后 Touch ID 确认”；“晚到成功不算”来自 RemoteHostLifecycleTests L05 的既有行为
- **S10** 本机在用时遥控让着；一排 10 秒没有输入自动收回：v2 没规定 10 秒/2 秒，行为来自 RemoteLayerHostTests 与 WS2RemoteHost 现有实现，要 Aaron 确认是否进验收
- **D07** 录音期间手动编辑，旧转写随后完成不覆盖手动内容：v2 没单列此情形，来自会话测试既有断言与“人手一改就清掉”的草稿规则
- **A05** 后端明确拒绝：保留草稿，不自动重试：v2/D6 只写“不重发可能已执行的提交”；“拒绝后保留草稿”来自会话与拥有流程测试的既有断言
- **R07** 审批挑战超时或风险未知：不降级自动批准，交回主认证：v2/D1 只规定“念短语、两项都过才允许、给 Touch ID 出路”；超时与未知风险行为来自会话测试既有断言
- **B04** 发布资格：独立攻防审查：v2 W7 只写“发布资格（独立攻防、能耗）”，攻防范围没有展开；这条是占位

## 没有场景的东西（文档提到，但不够写成验收）

- 声纹录入与误识/拒识率：`docs/conductor-v2.md:19`、`docs/conductor-v2.md:159`（W6）只说“真机”，没有指标；A07 只验放行逻辑。
- 提示音的主观手感、刘海动效的帧级验收：归设计验收，不在这份清单里。
- 原生 iPhone Remote 在主应用里的完整闭环：`docs/handoff/ws2-reuse-2026-10-08/CLAUDE-HANDOFF.md:98-104`（C3）自己就写“本轮 235 条输入不能替代其验收”，已拆进 P03、S01、X01–X02 等真机场景。

