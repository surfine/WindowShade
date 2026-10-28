# 把整个 App 有机整合 · 实现计划（2026-10-29，等 Aaron 点头再动代码）

画面依据：[WindowShade 的一天](../design-drafts/WindowShade%20的一天.html)（第九组）。拍板依据：[AARON-DECISIONS-2026-10-29](AARON-DECISIONS-2026-10-29.md)。
现状来自 2026-10-29 对 `main` 的盘点（行号是 `git show main:` 的行号，动手前重核一次）。

## 思路

整合不是再加功能，而是把五件共用件各收成一处，让现有功能改接上去：

| 共用件 | 应该是 | 现在 |
| --- | --- | --- |
| 一颗刘海（宿主 + 协调器） | 一个协调器按六层出场 | 两套仲裁并存：`NotchLeaseHub`/`InteractionCoordinator`（App/NotchLeases.swift、Core/InteractionCoordinator.swift:123-157）之外，还有 `announceWhenFree` 队列（App/Notch.swift:1415-1440，自带 priority / ttl / 0.6 s 合并，合并默认关 1453）和面板本地的 `alert` / `meter` / `dropState`。认你指示是独立 `EffectPanel`（FaceScanStatusController.swift:41-50），不经租约 |
| 一排 | 一份名单 | 已有：`Notch.mergedRow` 默认开，`tiles()` = 窗口 + `ongoingTiles()`（Notch.swift:2019-2021） |
| 一本放行账 | 审批、认你、Touch ID、配对、声纹同一种一次性请求 | 审批与原生认证已在 authorization 层（WS2CodexApprovalHost.swift:120、WS2HookApprovalHost.swift:80、NotchLeases `beginAuthorization`）；认你不在；声纹没有 |
| 一套手 | 走动 / 走进 / 选择 / 返回 | 遥控四层已有；指挥页只从菜单（WS2AppRuntime.swift:661）和 owned 会话页（302）打开，那一排的会话格不能直接走进 |
| 一个提示音 · 一套弹簧 | 一个「提示音」键；形状只用令牌弹簧 | 三个声音开关：`ShadeSoundEnabled`（番茄钟借用它，WS2AppRuntime.swift:614-615）、`Timer.chimeEnabled`（CountdownTimerHost.swift:104）、`WindowShade.Conductor.Sound`（WS2ConductorSettingsCore.swift:8）；编程会话没有声音。刘海外框已是真弹簧（`NotchCanvasView.Spring` + `Motion.notchSpring`，Motion.swift:112-124），但 Notch.swift:6037 的格子位移用「`calm.response` 当时长 + ease-out」冒充弹簧 |

## 顺序

每块一个提交、独立 worktree、`./build.sh --check` 退出 0；界面行为按 `docs/computer-use-qa.md` 验收，缺证据写 inconclusive。

| # | 做什么 | 为什么在这个位置 | 改哪里 | 验收 |
| --- | --- | --- | --- | --- |
| 1 | **一个协调器**：`announceWhenFree` 队列并进 `NotchLeaseHub` 的第 4 层（短暂提醒），面板本地 `alert` / `meter` / `dropState` 改向协调器申请；会话 bloom 的优先级不再是 0（WS2AppRuntime.swift:225-232） | 两套仲裁时「谁让谁」不可预测，后面每块都依赖它 | Notch.swift:1415-1520、NotchLeases.swift、InteractionCoordinator.swift | `InteractionCoordinator` 单测补「提醒撞上 1–3 层变点并消耗」；现有刘海探针全过 |
| 2 | **拆开 owner `"pomodoro"`**：番茄钟、计时器、日程卡各自一个 owner | 三张卡同名，`show` 会互相顶掉（CountdownTimerCard.swift:318/340、CalendarPresenter.swift:301、WS2AppRuntime.swift:479） | NotchLeases.swift `Owner`、三处调用 | 新单测：计时器卡开着时日程卡出现，计时器挂起后原样回来 |
| 3 | **一张停留时间表**：`Motion.Hold` 收 alert 2.6、coach 6.6、会话完成 4、计时器到点 10、离开期间摘要 8、音量 1.2、回执 0.8、认你 1.2 / 2.2；删掉各文件的重复常量（Contracts.swift:334、PowerFlashPolicy、CalendarPresentation、NotchAlerts、NotchActivities.swift:245 等） | 同一件事一个数，design-system §4.7 才能对得上 | Motion.swift 与各调用点 | `rg` 只剩一处定义；行为不变（帕累托） |
| 4 | **一个「提示音」**：新键管等你、完成、番茄钟、计时器、拍子；旧三键迁移（任一开着即开）；编程会话等你 / 完成补声音。卷帘收起 / 展开的效果声保持自己的一行（它是动作声，不是提醒） | Aaron 10-29 第 1 条；遥控器静音键拨的是它 | ShadeSoundPlayer、CountdownTimerHost、ConductorSoundPlayer、WS2AppRuntime 会话事件、设置行 | 迁移单测（三种旧组合）；设置里只剩一行「提示音」 |
| 5 | **认你搬进刘海宿主**：`FaceScanStatusController` 改为 authorization 层租约，刘海面板经 `LockSpaceBridge` 画在锁屏上；补光圈仍是独立的屏幕边缘层 | face-unlock 硬要求 1；放行账要包含认你 | FaceScanStatusController.swift、FaceScanExperiment.swift:128、Notch 宿主 | 真锁屏开合截图：时钟、头像、密码框不被挡；`.floating` 浮窗不再出现 |
| 6 | **代填与声纹（D11 解冻）**：Touch ID 保护的密码会话、3 次上限、脸 + 手机或手表都对才填；声纹在门槛附近补一道、可用于高风险放行 | Aaron 10-29 第 6 条；依赖 5 | face-unlock F4、声纹模块 | 攻击矩阵五种实测、帧率与耗电不比 1.0.15 差（硬要求 4、6、7）；真机 |
| 7 | **番茄钟收聊天**：`WS2FocusWindowPort.admitted` 从 false 放开（WS2FocusWindowPort.swift:11），设置里去掉「现在只计时」（WS2FocusSettings.swift:48） | 交接表里唯一「代码都在、闸门关着」的一条 | 同左 | 收起 / 放回探针；PrivateAppList 与有人在看、离开就锁共用不冲突 |
| 8 | **那一排的会话格 → 指挥页**；指挥页不依赖遥控模式；返回 = 收起、草稿留着 | Aaron 10-29 第 2、4 条 | NotchActivityController.swift:194-196、WS2AppRuntime.swift:392-427、遥控返回键映射 | 页面探针：从那一排点会话格进页、返回后草稿仍在；遥控未开时页面可用 |
| 9 | **用量进会话卡**：卡底一行，快用完右耳「剩 p%」，恢复时第 4 层提醒一次 | Aaron 10-29 第 7 条 | WS2AgentSessionView、usage 来源 | 假数据单测三档；文案进 xcstrings |
| 10 | **离开期间摘要可点**：每项是那一排的一格，点了走「过去」 | 认你 → 桌面 → 那一排的接口 | AwaySummaryController.swift、Notch.swift:1502 | 探针：锁屏回来点摘要一项，窗口到眼前 |
| 11 | **新表面换皮**：编程会话四态、审批卡（从琥珀点长出）、指挥页四块，照两张 10-29 稿；Notch.swift:6037 的格子位移改用真弹簧 | 画面最后换，前面的接口稳了才不返工 | WS2AgentSessionView、WS2CommandReviewView、WS2ConductorPage、Notch.swift:6037 | 动效样片对照 + 真机帧间隔（perf-ledger 口径）；中途改道测试 |
| 12 | **设置两页与露出**：「遥控器」「指挥模式」两页；验过的表面逐个从 `WindowShade.Preview.WS2` 搬进默认关的开关 | 露出最后做 | SettingsSections.swift:90-139、ReleaseDefaults.swift | 每个表面过《认你、指挥页与露出》的门槛表 |

1–4 是共用件本身，互不依赖，可以并行（各开 worktree）；5→6 串行；7–10 各自独立；11、12 收尾。

## 不做

- 不新增弹簧令牌，不改 §4.6 数字；`FoldSpring` 只给合盖与锁屏覆盖，刘海不用它（之前稿里说「新表面照抄 FoldSpring」不准确，已在稿与 design-grammar 更正）。
- 遥控器连上时不自动打开指挥页（现状保持）。
- 不做独立的用量统计页。
