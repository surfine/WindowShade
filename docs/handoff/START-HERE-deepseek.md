# DeepSeek 开工：WindowShade 2

把本文的“总则”和下面某一个工作包，整段交给 DeepSeek。**一次一个包**，按“开工顺序”走。
每个包交回后，主模型（Claude）先看差异、复现检查，验收过了再给下一个。

---

## 总则（每次都贴）

你在 WindowShade 仓库的 `main` 上工作。WindowShade 是 macOS 窗口工具，用 Swift 6 和 AppKit 写，直接用 `swiftc` 编译，没有 Xcode 工程。
我们在做 **WindowShade 2**。动手前必须先读：

1. `AGENTS.md`；
2. `docs/blueprint.md`：总图、刘海仲裁顺序、十二条硬要求；
3. `docs/copy-guide.md`（尤其第 7 条“一个符号能说清，就不写一句话”）和 `docs/design-system.md` §4.11 的符号表；
4. 你这个包对应的规格文件（包里写了是哪份）。

### WindowShade 2 是什么

像 iPadOS 那样：**一个入口，一套动作，任何输入都能用。**

- **一个入口**：刘海。看不见的窗口、实时活动（音乐、番茄钟、编程会话）、指挥模式、遥控时的焦点，都在这里。
- **一套动作**：收起窗口、收进刘海、看一眼、侧拉、分屏、画中画、启动台、调度中心、换桌面、指挥模式。设备不同，动作相同。
- **任何输入**：触控板、鼠标、键盘、Siri 遥控器、iPhone 上的遥控器、PS5 手柄。没有指针的设备，就用焦点导航。

### 怎么做才对

- **奥卡姆剃刀。**规格里没写的不做。要加任何设置项、菜单项、窗口、面板，先停下问。
- **不做配置工具，做体验。**默认值要好到不用改；能改的只有开 / 关和少数几档。不做宏、脚本、Webhook、用量统计、通用动作库。
- **符号优先，字少。**每个设置行一个 SF Symbol 加名字，副标题一行以内；刘海里是“符号 + 不超过 8 个字”。符号名只用 §4.11 表里核对过的。
- **一个东西一个名字**，照 copy-guide 的词汇表。
- **不新建窗口或浮层。**一切新东西都长在已有的刘海面板、活动协调器、设置窗口里。菜单一级不超过 12 项。
- **默认不接管。**会拦截、改写系统输入的功能，全部默认关；开了才装钩子，回调 O(1)，被系统停掉时退回原样。

### 绝对不做

- 不提交、不推送、不改 `git config`、不删文件。
- 不改规格没点名的文件；需要改，先停下说明。
- 不拷 GPL、CC BY-NC、PolyForm、MMF License、没有许可文件的项目的代码。MIT 项目的代码可以用，但要在文件头写明来源和版权。
- 不调用 `CGEvent` 去合成键盘或鼠标，除非你的包明确要求。
- 不碰登录密码、Touch ID、授权账、私钥：那些是主模型的事。
- 不在真实的 home 目录里改用户配置文件；测试用临时目录。
- 不跑不带 `--check` 的构建，不签名，不碰 `/Applications`，不退出或替换正在运行的 WindowShade。
- 不假装成功：没跑的写没跑，需要真机的写“需要真机”，不为了让测试过而放宽断言，不用 `// TODO` 冒充实现。

### 检查

- 纯逻辑放 `prototype/Core/`，只依赖 Foundation，时间由调用方传入。测试照 `tests/ConductorGestureTests.swift` 的写法，并配一个 `tests/run-xxx-tests.sh`。测行为，不复述实现。
- App 层改动跑 `cd prototype && ./build.sh --check`，它要跑十几分钟，要等它跑完。
- 已有测试不能变红。

### 交付报告

```text
做了什么：（一段话）
改了哪些文件：（列表）
跑了什么检查、结果：（命令 + 末尾输出，原样贴）
规格里哪几行已覆盖、哪几行没覆盖：（逐行）
需要真机 / 主模型决定的：（列表）
```

---

## 开工顺序

> **2026-10-03 更新：第一波已完成。**ChatGPT 第二轮交回了 T1、L1、A1、D1、D2、I1a–I1f、I9 的完整实现与测试，以及共享合同 `prototype/Core/Contracts.swift`。主模型已在 Mac（macOS 27、Swift 6.4）上跑通全部测试（121 个用例、334 条断言），并放进 `main`。
> 原件和逐包施工单在 [chatgpt-review-2/part1/](chatgpt-review-2/part1/)。往后派工以那里的 `packages/<编号>/WORKORDER.md` 为准；共享类型只用 `WS2` 命名空间里的，不另造。
> 下面的表保留作历史对照：第一波不再派给 DeepSeek，第二、三波等 ChatGPT 第二轮后续几份交回再派。

> **2026-10-03 晚更新：第二份也已接入。**第二回合第 2 份（协调器实现、D5a/D6/L2 纯核、S1 设置补丁、T2 番茄钟宿主与卡片、5 个真机探针、九章概念片）已进 `main`，
> 原件在 [chatgpt-review-2/part2/](chatgpt-review-2/part2/)。主模型在本机复核并修了三处它自己没跑出来的问题：
> `src/scenes/wsSpring.ts` 的元组展开过不了 `tsc`；S1 补丁在 Swift 6 严格并发下有两处隔离错误；协调器接入时撤销顺序会让收尾回调拿不到主人。
> 现在：纯核 22 场景/86 断言、合同 9 用例/24 断言、租约宿主 8 场景全过，`./build.sh --check` 通过，概念片横竖两版在本机渲染。
>
> **还没做的（等 ChatGPT 再交或等 Aaron 上机）：** M1 菜单收拢、T3/T4 番茄钟接线与设置两项、A3/D3 刘海视图、A2a/A2b agent hook、
> L2 的 BLE 生产来源、I2/I3/I5/I8 的输入接管、D5b/D6 真实协议与 CLI 通道、F1/L3 人脸与系统锁、概念片 17 项真机素材。
> 其中要 Aaron 在场上机的部分见 [part2/REMAINING.md](chatgpt-review-2/part2/REMAINING.md) 与 `tools/probes/RESULTS-2026-10-03.md`。

> **2026-10-03 深夜更新：第三份也合完了。**统一接手包里的第三份（M1 菜单收拢与异步标题缓存、S1 原生补充页、T2 唯一宿主、
> A3/D3 原生视图、A2 socket 与配置事务、D6 resume 与进程管道、D5 配对限流与 TLV、I8 手柄映射、I5 HID 写入事务、
> 多触点准入、输入资格、锁来源策略）已逐处合并进 `main`，原件在 [chatgpt-review-2/part3/](chatgpt-review-2/part3/)。
> **第三份的 Darwin 分支第一次在 Mac 上跑，第一次真编译**，修掉四处它自己看不到的问题：根级 `/var` 是 Apple 的符号链接导致父目录遍历拒绝一切临时路径；
> `WS2ProcessChannel` 关第二次 FileHandle 抛 ObjC 异常打掉进程、关了以后还读 fileDescriptor；测试把证据写向包布局的 `validation/`。
> 现在：第三份纯核 55 场景/147 断言、第二份 22 场景/86 断言、`tools/ws2-hook` 四个拒绝 fixture 全过；`./build.sh --check` 与八套 AppKit 回归见台账。
>
> 番茄钟的 T4 随后补上：专注时长两档、快捷键（默认不占键）、负一屏卡片暂停/继续；只有「专注时把聊天收进刘海」仍等 T3 的私人 App 名单。
> 仍然没做完的：A3/D3 的宿主与租约桥、D4/I7 真实偏好联动、A2 接 A1/A4 的允许路径、L4 系统锁后端、
> I3 主动事件桥、I5 usage 桥、I8 GameController 桥、D5 真实配对与加密传输、影片 17 项真机素材与声音。逐包状态见
> [part3/integration/package-status.json](chatgpt-review-2/part3/integration/package-status.json) 与
> [part3/integration/MAC-ACCEPTANCE.md](chatgpt-review-2/part3/integration/MAC-ACCEPTANCE.md)。

> **2026-10-03 夜：第四份（接宿主）也合完了。**配对加密的服务端 Pair-Verify 与分方向记录加密、
> 命令审批 review 与一次性 accept 编码、手柄候选桥、输入准入、番茄钟 pending/active 分离与设置/快捷键/工具/卡片、
> 共享岛的内容尺寸与摄像头避让都进了 `main`；原件在 [chatgpt-review-2/part4/](chatgpt-review-2/part4/)。
> 这一份的代码此前只做过语法解析，**这次第一次在 Mac 上真编译、真跑**，修掉三处它自己看不到的问题：
> `PairingTLV.encode` 假定 Data 从 0 开始索引，而 CryptoKit 的 `rawRepresentation` 是切片，真机一跑就崩；
> 手柄扳机方法在 SDK 27 里的 Swift 名字是 `setModeFeedbackWithStartPosition(_:resistiveStrength:)`；
> 共享岛接上以后 `cancelLease` 的 switch 少了两个新主人。
> 证据：第四份纯核 72 场景/188 断言、CryptoKit 向量、Python 参考 18 例、审批 schema 1 例、
> 隐私登记表 458 点 + 隐私页数据同源，`./build.sh --check` 与八套 AppKit 回归全过。
>
> 第四份自己列出的未完项没有因为“代码合进来了”就算完成：owned Codex 进程与 writer、首次 Pair-Setup、
> Keychain、HID/鼠标/手柄的生产桥、会话与指挥的 live store 订阅、T3 窗口效果都还没有接；
> 逐项见 [part4/REMAINING.md](chatgpt-review-2/part4/REMAINING.md)。

> **2026-10-03 夜（后半）：第五、六份也合完了。**第五份的进程/身份/窗口中间层与第六份的
> 精确增量（仲裁修正、Scope/Selection/Budget、诊断尾部）都进 `main`，原件在
> [part5/](chatgpt-review-2/part5/) 与 [part6/](chatgpt-review-2/part6/)。
> 按第六份的顺序交回的第一条独立闭环已经**真机跑通**：`tests/run-owned-codex-phase1.sh`
> 用本机 `/opt/homebrew/bin/codex` 0.153.0 走完 initialize → model/list（2 个模型）→ thread/start →
> turn/start → turn/completed → stop，全程 `approvalsSeen=0`（没有发过一条 allow）。
> 真机还抓出三处只有 Mac 才会暴露的问题：CryptoKit 的 Ed25519 签名带随机量（不能拿自己产出的 M6
> 与确定性向量逐字节比，改按“对端能验证”验收）；按线程屏蔽 SIGPIPE 在多线程进程里挡不住（改进程级忽略，
> EPIPE 仍如实返回）；0.153.0 在初始化阶段就发 `remoteControl/status/changed`，Wire 原来把 ready 之前
> 的任何通知当协议错误并自关，现在通知在未关闭状态都收，只有审批请求要求 ready。
>
> 番茄钟的窗口效果按工单 06 改成「串行计划 + 真实端口」：`WS2FocusWindowPort` 逐窗收起/放回、
> 先登记等待器再动作、按身份与 revision 复核；`WS2FocusWindowPort.admitted` 仍是 false，
> 真机时序表没跑完之前只计时、不动窗口，设置里也显示不可用。
>
> swift-srp 依赖按你批准的方式做了隔离准入：resolve 成功（swift-srp 1345dfe…、big-num 2.0.3、
> swift-crypto 4.5.2、swift-asn1 1.7.3），Mac 上 Swift 6 严格并发编译通过，四个包的许可都是
> Apache-2.0 / MIT，证据在 [part5-mac-probe/](chatgpt-review-2/part5-mac-probe/)。
> **首次配对仍未准入**：没做固定向量互测（HAP 变体的补零与 proof 布局要逐字节对 `srp_reference.py`），
> 也没有实例工厂与原生 Remote 互操作。

> **2026-10-03 深夜：第七份已并入。**它把本地助手流程真正接通（唯一 `WS2OwnedLaunchController`、
> `WS2OwnedSessionView`、严格 JSON、退出屏障、版本预检、独立 HOME/CODEX_HOME 的启动配置），
> 进程通道改成自有 posix_spawn + waitid 的原生监督端口（`prototype/Native/WS2Child.c`）。
> 原件在 [part7/](chatgpt-review-2/part7/)，这台 Mac 上的全部结果写在
> [part7/MAC-EVIDENCE.md](chatgpt-review-2/part7/MAC-EVIDENCE.md)。
>
> 真机跑通：第七份 core 27/51、native 3/14、flow 18/145；旧回归与 PROC04 全过；整 App 类型检查与八套 AppKit 全过；
> **真实 CLI** 走通版本 → 独立配置 → `config/read` 投影 → 账号边界（隔离 profile 里未登录），
> 并列出 5 个真实模型。又抓到 6 处只有 Mac 才会暴露的问题（`addchdir_np` 弃用、退出后 `getpgid` ESRCH、
> 空组 `kill(-pgid)` 回 EPERM 导致永不回收、Swift 6 异步迭代、隔离 PATH 缺 node、
> 真实 `config/read` 的 hooks 形状），全部按证据修掉。
>
> 仍没做：真实登录后的查询、Touch ID 允许路径、原生界面实测、脱离组子孙的全树安全、配对/设备/窗口/能耗/影片与发布。

> **2026-10-03 深夜（后段）：第八份已并入。**它做了两条实际接线：手柄 → 当前可见模型列表
> （`WS2VisibleListInput`、`WS2DeviceActionContracts`、`WS2ModelPickerView`、唯一 Runtime host，
> 按下预约目标/松开采用/重选失焦断连撤销），以及原 Notch 收起的**实际事务证据**
> （`WS2FoldEvidence` + `WS2FoldEvidenceAdapter`，`hide` 前复核项目条目的窗口/期限/锁态并按实际
> foldTransaction 关联）。原件在 [part8/](chatgpt-review-2/part8/)，本机结果在
> [part8/MAC-EVIDENCE.md](chatgpt-review-2/part8/MAC-EVIDENCE.md)。
>
> 真机跑通：input 33/49、fold 21/49、flow 6/27；check-build 37 份类型检查；check-wiring 三项；
> test-tools 18 项；旧回归全过；整 App 类型检查与八套 AppKit 全过；隐私登记表 466 点。
> 又修了 4 处只有 Mac 才会暴露的问题（脚本仍按 App/ 找共享仲裁、stage.py 把 macOS 的 `/var`
> 当不可信链接、`resolve()` 与 `absolute()` 混用让「输出在输入内」失配、证据适配器在非隔离上下文读锁态），
> 并给单岛补上 `inputHandle(for:)`。
>
> 仍没做：真实手柄与 GameController 实测、AppKit 焦点/布局实测、真实 AX 收起恢复、完整 T3、
> Touch ID 允许路径、配对与原生 Remote、能耗、影片与发布。自动窗口效果仍然关闭（`admitted=false`）。

> **2026-10-03 深夜（再后段）：第九份已并入。**它把原窗口收起的**未知状态**这条老问题收干净：
> 收起结果分 hidden / visible / unknown，缺 AX 属性、类型不符、身份不符、锁态未知都不算隐藏成功，
> unknown 不换策略继续写、保留原 journal 与人工恢复入口；完成通知绑定具体 transaction 与捕获的
> waiter tokens，先整批取出再排队，投递前重查事务、启动与锁态代次、显示上下文与有效期；
> 后台巡检按每应用不可变快照 + 批次/事务代次应用；AX observer 按本次注册的单调 routeID 路由；
> `EffectFrameAwaiter` 继承调用者隔离；原生 resize 去掉安装中的嵌套 RunLoop。原件在
> [part9/](chatgpt-review-2/part9/)，本机结果在 [part9/MAC-EVIDENCE.md](chatgpt-review-2/part9/MAC-EVIDENCE.md)。
>
> 真机跑通：regression 42/93、frame 15/15；check-build 40 份类型检查 + 43 份语法；check-wiring 24 项；
> test-tools 18 项；旧回归 duo 三套 + part8 input 33/49、fold 21/49、flow 6/27 + part7 core 27/51、
> native 3/14、flow 18/145 + legacy 两批全过；part2–part6 各 runner、PROC04（0.086s）、Mac 配对加密全过；
> 整 App 类型检查与八套 AppKit 全过；隐私登记表 466 点、页面数据同源。
>
> 这一份在 Mac 上修掉 23 处它自己看不到的 Swift 6 隔离错误（`FoldCompletion` 变成 `@MainActor`
> 后，非隔离调用点读 `lockState`/`sessionEpoch` 或调用等待器结算的那些地方，全部按仓库既有写法
> `MainActor.assumeIsolated` 显式声明在主线程上；逐点见 MAC-EVIDENCE）。还改了四处仓库入口差异
> （check-build 找 `Core/InteractionCoordinator.swift`、stage.py 的 `/var` 与 `resolve()`、
> run-previous 的 legacy history、`WindowFoldEffectsTests` 改到「绑事务再结算」的新 API）。
>
> 仍没做：受控真机观察（工单 02/03 那部分，等 Aaron 指定可动窗口，动手前再确认一次）；
> 真实 AX 收起/恢复与人工恢复、慢 AX 与强制取消、真实 SCK capture graph、完整 T3、
> Touch ID 允许端到端、配对接收、系统身份后端、能耗、影片、签名与发布。
> 自动窗口效果仍然关闭（`WS2FocusWindowPort.admitted=false`）。


**第一波：纯逻辑。**互不依赖，最安全，可以并行派。

| 包 | 内容 | 在哪份提示词 |
| --- | --- | --- |
| T1 | 番茄钟计时 | deepseek-pomodoro-symbols.md |
| L1 | 离开就锁的在场状态机 | deepseek-dynamic-lock.md |
| A1 | 编程会话表与批准请求 | deepseek-menu-agents.md |
| D1 | 指挥模式状态机 | deepseek-conductor.md |
| D2 | 后端能力与确认票据 | deepseek-conductor.md |
| I1 | 平滑滚动、设备分类、中键拖、多指轻点、Siri 遥控器按键、遥控模式 | deepseek-input.md |
| I9 | 焦点导航（纯逻辑部分） | deepseek-input.md |

**第二波：界面，低风险。**

| 包 | 内容 | 在哪份提示词 |
| --- | --- | --- |
| M1 | 菜单从 24 项收到 9 项 | deepseek-menu-agents.md |
| S1 | 设置改成符号优先 | deepseek-pomodoro-symbols.md |
| T2、T4 | 刘海里的番茄钟、设置两项 | deepseek-pomodoro-symbols.md |
| A3 | 刘海里的编程会话 | deepseek-menu-agents.md |
| D3、D4 | 刘海里的指挥活动与测试面板、指挥模式设置 | deepseek-conductor.md |

**第三波：接系统。**每个都要主模型复核，还要 Aaron 上真机试。

| 包 | 内容 | 在哪份提示词 |
| --- | --- | --- |
| A2 | `ws-hook` 与改配置文件（高风险） | deepseek-menu-agents.md |
| L2、L4 | 蓝牙监视；倒数、收起、远程锁 | deepseek-dynamic-lock.md |
| I2、I3、I5、I8、I7 | 触点、滚动钩子、Siri 遥控器、手柄、设置 | deepseek-input.md |
| D5、D6 | 遥控协议、Codex 适配器 | deepseek-conductor.md |

**随时可做，不碰 App：概念片。**F1 → F5，见 [deepseek-film.md](deepseek-film.md)；Remotion 工程在 `film/ws2-concept/`，派活时用 setup 把主仓库的 `node_modules` 链接进去。录真机画面、渲染、验收、配声音由主模型做。

**不交给 DeepSeek，由主模型做**：刷脸解锁核心（face-unlock.md F2–F5）、L3 身份实验、L5 回来就开的代填密码、A4 批准接授权账、A5 会话与指挥模式合流、I4 中键接标题栏手势、I6 遥控器麦克风、T3 番茄钟接收进刘海、语音与声纹。

**做之前先确认 1.0.16 的事。**1.0.16 还没发布，Aaron 说发才发。第一波、第二波不影响已有功能，可以先做。第三波要等 Aaron 说可以动输入和系统那一层。
