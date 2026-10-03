# 交给 DeepSeek：指挥模式（WindowShade 2）

用法：先把总则和一个工作包整段贴给 DeepSeek，一次只给一个包，按 D1 → D6 的顺序做。
每个包做完，把它交回的差异和检查输出给主模型（Claude）验收，验收过了再给下一个。

**先提交，再交出去。**DeepSeek 的沙箱是从 git 克隆仓库的，没提交的文件它看不到。
要先提交的文件：`docs/conductor-v2.md`、`docs/blueprint.md`、`docs/copy-guide.md` 和本文件。如果不想提交，就把 `docs/conductor-v2.md` 全文贴在总则后面。

---

## 总则（每个包都贴）

你在 WindowShade 仓库里工作。WindowShade 是一个 macOS 窗口工具（Swift 6，AppKit，不用 Xcode 工程，用 `swiftc` 直接编）。
你要做的是 WindowShade 2 的主角“指挥模式”中的一块。指挥模式的意思是：用户打开 iPhone 控制中心里的 Apple TV 遥控器，选中这台 Mac，
然后这样操作：

- 在触控区画声调（一声 → low、二声 ↗ medium、三声 ˇ high、四声 ↘ xhigh）或打拍子（一到四拍同上；五拍 max；六拍 ultra），选 Codex / Claude 的思考档位；
- 点电视键，在“档位 / 模型”两个选择域之间切换；按住电视键选会话；
- 按住 iPhone 侧边按钮说话，松开得到草稿；
- 按播放键把草稿发出去，或者请求停下。

Mac 的刘海即时显示每一步。

先读这些，再动手：

1. `docs/conductor-v2.md`：完整交互规格，包括键位、手势、全流程、放行、出岔子、结构。**以它为准。**
2. `AGENTS.md` 和 `docs/copy-guide.md`：界面文案规则。功能名叫“指挥模式”，effort 在界面上叫“档位”。
3. `prototype/Core/ConductorGesture.swift` 和 `tests/ConductorGestureTests.swift`：已有的识别器和测试写法。
4. `docs/blueprint.md`：十二条硬要求，尤其是“一个宿主，一个协调器”“状态来自数据”“未知就是未知”。

硬规则：

- **不动已有行为。**除了本包点名的文件，不改别的文件。要改别处，先停下，写清理由。
- **纯逻辑放 `prototype/Core/`**，只依赖 Foundation，不碰 AppKit，不读系统时钟（时间由调用方传入），不开线程。
- **测试照 `tests/ConductorGestureTests.swift` 的写法。**用 `@main` 结构体和 `expect(条件, "说明")`，配一个 `tests/run-xxx-tests.sh`，
  用 `swiftc -swift-version 6 -parse-as-library 源文件… 测试文件 -o .build/xxx/xxx` 编译后运行。
  测试要测行为（规格里的一行一行），不要写只复述实现的测试。
- **App 层代码**改完必须跑 `cd prototype && ./build.sh --check`，它是整模块类型检查，可能要十几分钟。不许跑不带 `--check` 的构建，不签名，不碰 `/Applications`。
- **不提交、不推送**，不改 `git config`，不删任何文件。
- **不联网就能做完的才做。**需要真 iPhone、真遥控器、真模型请求的事一律不做，在报告里写“需要真机 / 真实后端”。
- **不许假装成功。**测试没跑就写没跑，失败就贴失败输出；不许为了让测试过而放宽断言；不许用 `// TODO` 冒充实现。
- **不动光标，不合成按键。**指挥模式的任何代码都不调用 `CGEvent` 去发送键盘或鼠标事件，不往前台窗口发东西。
- **注释和界面字符串用简体中文**，照现有文件的口气；不加英文 UI 文案。

交付时用这个格式报告：

```text
做了什么：（一段话）
改了哪些文件：（列表）
跑了什么检查、结果：（命令 + 末尾输出，原样贴）
规格里哪几行已覆盖、哪几行没覆盖：（逐行）
需要真机 / 真实后端 / 主模型决定的：（列表）
```

---

## D1：指挥会话状态机（纯逻辑）

新文件：`prototype/Core/ConductorSession.swift`、`tests/ConductorSessionTests.swift`、`tests/run-conductor-session-tests.sh`
（编译时带上 `prototype/Core/ConductorGesture.swift`）。

写一个纯值类型状态机：`reduce(state, event, now) -> (state, [effect])`。

**输入事件：**
- 连接：`connected(peerID, epoch)`、`disconnected`、`revoked`。
- 触摸：`touch(begin / move / end / cancel, point)`；坐标 0…1，y 向上。
- 按钮：`button(id, phase)`。id 为 `tv / playPause / back / mute / power / side`，phase 为 `down / up / cancel`。
  另外还有 `buttonClickOnly(id)`，用于 E2 实验发现没有阶段的情况。
- 后端回执：`backendAccepted(config)`、`backendRejected(reason)`、`turnStarted(turnID)`、`turnFinished(summary)`、`turnInterrupted`、
  `approvalRequested(id, command, risk: normal / high)`、`actualConfig(config)`。
- 语音：`audioSamplesArrived`、`transcriptReady(text)`、`audioSourceLost`；声纹结果 `voiceCheck(phraseOK, voiceprintOK)`。
- 环境：`macLocked`、`macUnlocked`、`settingsTurnedOff`、`timeout(token)`。

**输出效果（effect），只描述要做的事，不执行：**
`showNotch(ConductorNotch)`、`playSound(kind)`、`stageConfig`、`submitDraft(commandID, sessionID, config, text)`、`steer(turnID, text)`、
`interrupt(turnID)`、`respondApproval(id, allow)`、`startCapture`、`stopCapture`、`requestTouchID(purpose)`、`disconnect`。

`ConductorNotch` 是一个枚举，每个 case 对应 `docs/conductor-v2.md`“全流程”和“出岔子”里刘海那一列的一种状态，带上要显示的数据。
它也要能给出那一列的中文文案，**一字不差**。

**必须测到的行为（每条至少一个测试）：**

1. 画的过程中只给拍数预览，不改档位；抬手后才判定。五拍画到第四拍时，档位仍是原值。
2. 档位域：low–xhigh 被后端支持时，设为下一轮；不支持时，显示“这个模型没有 xhigh，保持 high”，档位不变。
3. max/ultra 只来自完整的五拍、六拍，变成待确认，必须新的一下点按才生效；画完附带的那一下不算。确认只管下一次提交；换会话、重连、超时都作废。
4. 模型域：一到四（声调或拍子）对应四个模型位置；五拍、六拍拒绝。
5. 电视键点一下换域；按住（down 之后 0.5 秒没 up）打开会话列表，列表里上下滑动改选中项，点一下选定。
6. 侧边按钮 down 开始采集；up 停止并等转写；没收到 `audioSamplesArrived` 时不进“在听”状态（刘海不画波形）。
   只有 `buttonClickOnly` 时，第一下开始、第二下停，60 秒自动停。
7. 播放键：有草稿且没在跑时提交；在跑且有草稿时补一句（`steer`，带当前 turnID）；在跑且没草稿时请求停下，
   先显示“正在停止”，收到 `turnInterrupted` 才显示“已停止”。
8. 提交分三步显示：发出去了 → 后端接受（显示读回的实际档位）→ 开始跑。读不回实际档位时显示“实际档位还没确认”。
9. 在跑时画手势只改下一轮，刘海显示“这一轮 high · 下一轮 xhigh”。
10. 返回键依次取消：列表、待确认候选、审批（等于不允许）、草稿。草稿要按两次才丢，第一次显示“再按一次返回丢掉草稿”。
11. 普通审批：审批出现后的点按 = 允许；出现前的点按不算。高风险审批：点按后要求念短语，必须 `voiceCheck` 两项都过才允许；
    否则不允许，并给出 `requestTouchID` 的出路。没有“始终允许”。
12. Mac 锁屏：取消手势、候选、采集；刘海不显示项目名和草稿；解锁后不自动提交。
13. 断开或撤销：取消一切未确认的东西；后端任务不停。重连 epoch 变化后，旧 epoch 的回执一律丢弃。
14. 电源键：退出指挥模式，发出 `disconnect`，不发 `interrupt`。
15. 同一个 commandID 不会提交两次（重复的 up、重发的事件都不行）。

---

## D2：后端能力与确认票据（纯逻辑）

新文件：`prototype/Core/ConductorCapabilities.swift`、测试和 run 脚本。

- 输入一个后端的能力描述：`provider (codex / claude)`、`modelID`、`supportedEfforts`（从 Codex 的 `model/list` 来）、`nativeUltra`、
  `ultracodeBinding`（用户是否把六拍绑到 Claude 的 ultracode）、`capabilityRevision`。
- 输出：某个手势意图能不能提交、实际会发什么，以及刘海上怎么写。例如“ultracode · xhigh · 工作流程开启”“Codex 没有 ultra，保持 high”。
  **绝不默默降档，绝不发 `effort=ultra` 给不支持的后端，绝不在提示词里追加 ultrathink。**
- 高开销确认票据：绑定 peerID、projectID、sessionID、modelID、capabilityRevision、candidateID，只能用一次；
  任何一项变化、超时（调用方给时间）、重连都会作废。
- 四个模型位置：保存 provider + modelID，不随列表排序变化；某个位置的模型不见了，就显示“位置 2 的模型不可用”。

---

## D3：刘海里的指挥活动 + 合成输入测试面板（App 层）

要先读 `prototype/Core/NotchActivities.swift`、`prototype/App/NotchActivityView.swift`、`prototype/App/NotchActivityController.swift`、
`prototype/App/Notch.swift`（较大，只读和活动相关的部分），再接手 D1 的 `ConductorNotch`。

- 在已有的活动协调器里新增指挥模式这一类活动。**不新建窗口或浮层**，都画在已有的刘海面板里。
  指挥模式的交互状态（画、录音、审批）优先级高于音乐等持续活动，也高于短暂提醒。被打断的活动结束后要原样回来，不补播。
- 画每种 `ConductorNotch`：轨迹（最近的点，有界抽样）、六个拍点、选择域的标签、草稿文字（没把握的词加下划线）、波形
  （只在 `audioSamplesArrived` 后画）、会话列表、审批、四位配对码。
- 形状用已有的动效常量（找 `Motion` 相关文件），不新造弹簧参数；“减少动态效果”打开时只淡入淡出。
- 测试面板：加一个只在开发版、带启动参数才出现的面板（照仓库里已有 probe 的入口方式，例如 `App/ProbeEntries.swift`）。
  面板里按钮模拟每个按键的 down / up，用一块区域画轨迹喂给 D1 的状态机，并能模拟后端回执。**发布版里不出现。**
- 检查：`cd prototype && ./build.sh --check` 通过；D1 和 D2 的测试仍然通过。在报告里列出每种状态在测试面板里怎么触发。

---

## D4：设置 → 指挥模式（App 层）

- 先读 `prototype/App/Preferences.swift`，照它的分组卡片和行的写法加一栏“指挥模式”。内容：
  - 总开关，关掉就停止宣告、断开；
  - 已配对的 iPhone 列表，每台可以“撤销”；
  - 四个模型位置；
  - 提示音开关。
- 副标题照 copy-guide 写，示例：“用 iPhone 控制中心里的遥控器画声调、打拍子，指挥 Codex 和 Claude”。
- 开关默认关。这一步只存设置，不接协议层。
- 如果仓库里已有信号登记表（见 `docs/privacy-page.md` P3），就把规格“隐私登记”一节的四项登记进去；没有就在报告里写明。
- 检查：`./build.sh --check`。

---

## D5：atv-core 分支（Rust，只在沙箱里有 `cargo` 且能取依赖时做）

上游是 `corvofeng/atv-core`，固定提交 `e14f8ca2a54745bb9bc7014aa48fd75a9d4bae25`，MIT 许可。放进 `control/remote-host/`，保留版权声明。

- 空闲态导出原始触摸事件。要放在光标加速、方向判断、合成点击之前，带 begin / move / end / cancel、绝对坐标、顺序号和接收时间。
  注意上游的 Moved 是增量，Ended 是相对起点的总位移，不能重复累加。
- 按钮保留线上的按下 / 松开阶段。上游的 `on_button` 只在松开时触发。线上没有阶段的按钮，标成 `clickOnly`。
- 配对：不再用固定的 PIN 1111，改成随机四位数，由调用方显示；60 秒有效，错 3 次停 5 分钟；PIN 和密钥不写日志。
- **Pair Verify 必须验证客户端签名，并对上登记过的长期公钥**（上游 M3 没验就发了 Verified）。未知设备、重放、错签名都要拒绝，并写测试证明。
- 调试端口和 inspector 默认关闭。协议层不执行任何命令，只往外报事件。
- 没有 `cargo` 或取不到依赖：不要写一堆没编译过的 Rust，直接停下报告。

---

## D6：Codex App Server 适配器（只做假服务器上的部分）

- 新文件放 `prototype/App/` 或 `prototype/Conductor/`。不确定放哪里时，先看 `prototype/build.sh` 怎么收集源文件，别让第二个 `main` 被编进主程序。
- 走 JSON-RPC over stdio，按顺序：`initialize` / `initialized`、`model/list`（读 `supportedReasoningEfforts`）、`thread/start` / `thread/resume`、
  `turn/start`、`turn/steer`（带 expectedTurnId）、`turn/interrupt`、审批请求与应答。
- 写一个假服务器脚本（放 `tests/fixtures/`），回放成功、拒绝、超时、中断、审批、断线几种情况，用它测适配器。
  **字段名凡是没有官方文档依据的，都标“待对照官方文档”，不要编。**
- 超时后不自动重发可能已执行的提交，要先查状态。
- 真实的 Codex 进程一律不启动。
