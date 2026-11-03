# 第二轮：把每个工作包写成“照做就行”的施工单

你好。第一轮你交回的审查很扎实：53 条问题全部被采纳，我（主模型 Claude）的逐条结论在 `repo/docs/handoff/chatgpt-review-1-verdict.md`。
Aaron 想请你再往下走一步。

> **目标：执行模型（DeepSeek）拿到施工单后，不需要做任何判断，照着写、照着测就能完成。**

凡是需要判断的地方，你先替它判断好，写成规则、表格、常量、完整代码和测试用例。
DeepSeek 擅长照规格写代码，不擅长在模糊处做取舍；它是纯文本模型，看不到图片。

这一轮还要加上**概念片（预告片）的工程**：第一轮的包里没有它。

## 这一轮的包里有什么

| 位置 | 内容 |
| --- | --- |
| `repo/` | 仓库当前 `main` 的快照：代码、全部文档、提示词、概念片工程（不含 `node_modules`） |
| `repo/docs/handoff/chatgpt-review-1/` | 你第一轮交回的全部内容（原样） |
| `repo/docs/handoff/chatgpt-review-1-verdict.md` | 我对 53 条的结论；只有 R42 保留 Aaron 的决定，其余都接受 |
| `repo/docs/handoff/reference/mac-facts-2026-10-03.md` | **第一轮你标“需要确认”的事实**，我在 Aaron 的 Mac 上实测采集。包括：<br>• macOS 27.0、Swift 6.4、SDK 版本；<br>• `build.sh` 的真实编译参数；<br>• GameController 头文件摘录（DualSense 扳机的方法签名与最低系统）；<br>• 私有触控框架 14 个符号在本机 `dlsym` 全部存在；<br>• Codex CLI 0.153.0、Claude Code 2.1.283 的版本与 hook 相关帮助；<br>• 本机还没有任何 hook 配置 |
| `repo/docs/handoff/reference/codex-app-server-schema-0.153.0/` | 用本机 `codex app-server generate-json-schema` 导出的**完整协议 JSON Schema**（39 个文件）。D6、A2 请以它为准，不要再按网页猜字段 |
| `repo/film/ws2-concept/` | **概念片工程**：Remotion 4.0.484。<br>• `BRIEF.md`：126 秒，五处 wow，分镜；<br>• `DIGEST.md`：写法规则、弹簧、刘海尺寸；<br>• `reference/`：33 张 video-shotcraft 镜头卡、调好参数的示例源码、审美准则、声音设计，Apache 2.0；<br>• `src/lib/`：shotcraft 的 PageCam、ClipCard 等组件；<br>• `public/footage/`：真机镜头清单与登记表 |
| `repo/docs/handoff/deepseek-film.md` | 概念片的 DeepSeek 工作单（F1–F5） |
| `repo/promo/` | **前作**：1.0.x 的 Remotion 宣传片（56 秒，4K 横竖两版，120 bpm 卡拍，`src/timeline.ts` 一张提示表驱动画面和声音，音乐音效代码生成）。概念片要沿用它的提示表、卡拍、横竖两版和出片脚本；但前作的界面是画的，新片已做的功能必须用真机画面 |
| `skills/` | 设计时用的 skill 原文：Apple HIG、Apple 流体界面、Emil Kowalski、本机动效总纲（motion-doctrine）、video-shotcraft 的 SKILL 与流水线、Remotion 写法 |

## 已经定了、不要再讨论的

- Aaron 的产品决定：一个刘海入口、一套动作、任何输入；不上 App Store，私有 API 可用（要登记、要有退路）；不做手机或手表端 App；奥卡姆剃刀；符号优先、字少；1.0.16 不发布。
- 你第一轮的 53 条结论（R42 除外）。
- 第一轮你提出的四个主模型前置：冻结事件与审批合同、全局交互租约与每屏显示、隐私登记与日志修复、可复现构建基线。**这一轮请你起草它们**，我审定后冻结。

## 请你交回什么

照下面的结构打成 zip。东西多，可以分几次交（“第 1 份 / 第 2 份……”），**按优先级顺序交**：

1. `contracts/`
2. 第一波纯逻辑的 `packages/`
3. `film/` 的 F1–F2
4. 其余包
5. `film/` 的 F3–F5

### 1. `contracts/`：四个前置，写成可以直接冻结的东西

- **`Contracts.swift`**：共享的事件、动作、身份、代次、审批请求和决定、能力票据、时钟注入。
  - 只依赖 Foundation，所有类型 `Sendable`，有完整文档注释；
  - 要求能在 Linux Swift 6 下编译，你那边可以实测。
- **`InteractionLease.md`**：全局交互租约与每屏显示协调。
  - 谁能占刘海、优先级（照 `docs/blueprint.md` 的六层仲裁）、抢占与恢复、锁屏/睡眠/换屏时撤销；
  - 写成状态表加接口签名，并写清它接到现有 `NotchActivities.swift` / `Notch.swift` 的哪几个具体符号上（给文件和行号）。
- **`PrivacyRegistry.md`**：登记表的数据结构和全部条目（照 `docs/privacy-page.md`，加上 A2、D5、D6、L2、I2、I5、I8 新增的读取与数据去向）。
  - 日志修复的精确改法：哪个文件、哪几行、改成什么；
  - 12 处写窗口标题的日志逐条给出替换。
- **`BuildBaseline.md`**：可复现构建与能耗测量的固定条件、命令、记录表格式。

### 2. `packages/<编号>/`：每个包一个文件夹

编号照第一轮：T1、L1、A1、D1、D2、I1a–I1f、I9、M1、S1、T2、T4、A3、D3、D4、A2a、A2b、L2、L4、I2、I3、I5a、I5b、I8、I7、D5a–D5c、D6。每个文件夹里放：

- **`WORKORDER.md`**：可以原样贴给 DeepSeek 的施工单。必须包含：
  - **可写文件清单**：精确路径；
  - **可调用的既有符号**：文件加行号，给签名；
  - **决定表**：把这个包里每个需要判断的地方都列出来，每行写“情况 → 怎么做 → 为什么”。例如：
    - 两个事件同一时刻到达时的顺序；
    - 判不准是点还是拖时怎么办；
    - 设备身份未知时怎么办；
    - 超时多久；
    - 文案具体是哪几个字；
    - 用哪个 SF Symbol；
    - 弹簧用哪一档。

    **DeepSeek 遇到表里没有的情况，就停下来报告，不自己发明。**
  - 常量表：所有数值和出处（规格、实测或你的推荐）。
  - 验收命令：精确命令、预期的退出码、预期输出里必须出现的字样。
  - “不要做”清单。
- **纯逻辑包**（T1、L1、A1、D1、D2、I1a–f、I9）：交**完整实现**加**完整测试**，不是骨架。
  - 写法照仓库的 `tests/ConductorGestureTests.swift`：`@main`、`expect(条件, "说明")`、配 `tests/run-xxx-tests.sh`；
  - 在你那边的 Linux Swift 6 实测通过，把输出放进 `VALIDATION.txt`；
  - DeepSeek 的工作就变成：放进仓库、在 Mac 上跑同样的命令、贴出结果。
  - 每个测试用例写成表：输入序列 → 预期状态与效果，测试代码照表写。
- **App 层包**：交到“填空”程度的代码。
  - 新文件写完整；
  - 改既有文件的，给出精确的插入位置（文件、行号、前后两行原文）和插入内容；
  - 用 AppKit 和私有 API 的地方，给出你确定的写法，并标“需要在 macOS SDK 上编译确认”；
  - 写清 DeepSeek 跑 `./build.sh --check` 失败时，最可能是哪几类错误、各怎么改。
- **真机探针**（L2、I2、I5a、F1/L3 身份、锁屏后端）：给出探针程序的完整代码、Aaron 在场时的操作步骤、要记录的数据表格式，以及每种可能结果分别意味着什么、下一步怎么走（决策树）。

### 3. `film/`：概念片工程

先审 `film/ws2-concept/BRIEF.md`，再把它变成 DeepSeek 照做的施工单。

- **`REVIEW.md`**：先读前作 `repo/promo/`，说清哪些做法沿用、哪些要改；再照本机动效总纲（`skills/motion-doctrine/references/doctrine.md`）和 shotcraft 审美准则，审这份分镜：
  - 哪里会像幻灯片；
  - 五处 wow（刷脸解锁、灵动岛、启动台、vibe coding 伴侣、CarPlay）够不够 wow，怎样更 wow；
  - 节奏、静止占比、衔接、光、文字有什么问题。

  在“真画面”规矩内给出更强的改法：已做的功能必须真机录屏，没做的只能抽象图形，不画假界面、不画 CarPlay 界面、不用 Face ID 图形。改动直接写成新版 `BRIEF.md`。
- **`shots/chN.md`**（第 0–8 章，每章一份）：逐帧施工单。必须包含：
  - **帧表**：每个元素的起止帧、关键帧数值（位置、尺寸、透明度、缩放、颜色）、用哪一档弹簧；
  - 照抄哪个示例文件（`reference/demos/<卡名>/<文件>.tsx`）、改哪些参数、改成多少；卡上“已知坑”的参数原值保留；
  - 刘海在本章每个关键帧的形状和内容；
  - 文案原字；
  - 出口衔接：哪个元素活下来、在第几帧变成下一章的什么；
  - 静止段的起止帧；
  - 主模型抽帧检查的帧号，以及每一帧“应该看到什么”（DeepSeek 看不到图，由主模型对照）。
- **`src/`**：共享组件的完整 TSX，基于 Remotion 4.0.484 API：
  - `Film.tsx`（九章的 `Series`）；
  - `scenes/Stage.tsx`、`scenes/Notch.tsx`（四种形状 + 变形）、`scenes/Footage.tsx`（登记表与占位块）；
  - `scenes/wsSpring.ts`；
  - 一个相机组件。

  你那边如果没法装 Remotion 编译，就标“未编译”。
- **`AUDIO-CUES.md`**：声音提示表，每行写帧号、文件、音量、淡入淡出。
  - 文件从 shotcraft 的 `assets/audio/sfx/<类别>/` 里选，清单见 `film/ws2-concept/reference/sound-design.md`；
  - 先给两首 BGM 候选和理由。
- **`QA.md`**：出片前检查清单，对应本机的 `qc_gate.py`、`carry_flow.py` 和 shotcraft 的终检项，写成主模型能逐项打勾的形式。

### 4. `answers.md`

第一轮你标“需要确认”的问题，哪些已被 `mac-facts` 和 Codex Schema 回答（附结论），哪些仍要真机（附探针编号）。

### 5. `CHANGELOG.md`

与第一轮比改了什么，哪些第一轮的小抄作废，被哪个新文件取代。

## 写的时候

- **先判断，再交代码。**宁可多写一行决定，也不留“视情况而定”。真不知道的，写成探针和决策树，不要写“需要进一步研究”。
- 代码必须是你原创的。不拷 GPL、非商业许可、没有许可文件的项目；可以照搬 video-shotcraft 的示例源码，它是 Apache 2.0，要保留出处注释。
- 引用外部事实给来源；与 `mac-facts` 冲突时以 `mac-facts` 为准。
- 文案照 `repo/docs/copy-guide.md`：一个东西一个名字，界面字少。
- 中文写；句子短；先结论。
