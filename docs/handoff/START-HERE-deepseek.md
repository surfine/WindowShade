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
