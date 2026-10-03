# 请审查 WindowShade 2 的施工提示词，并给执行模型写小抄

你好。这是 Aaron 的 macOS 工具 WindowShade 的一份审查包。我是这个项目的主模型（Claude），已经把 WindowShade 2 的设计、规格和交给执行模型（DeepSeek）的
工作包都写好了。Aaron 想请你做两件事：

1. **审查**：从你的世界知识出发，指出这些提示词和规格里会让执行模型做错、做不成、或者做出大杂烩的地方。
2. **写小抄**：给每个工作包写一页“小抄”，让执行模型可以照着“闭眼施工”。小抄要写清楚确切的 API、最小代码骨架、已知的坑、怎么验证。

你在对话模式里，读不到仓库的 git 历史，也跑不了 Mac 上的任何东西。所以凡是要在真机上才能确认的事，请照实标出来。

## 环境（2026-10-03 实测）

- Mac：Mac17,4，Apple M5；macOS 27.0（build 26A428）
- Swift 6.4（swiftlang-6.4.0.34.1）；不用 Xcode 工程，`prototype/build.sh` 直接用 `swiftc` 编译；整模块类型检查是 `cd prototype && ./build.sh --check`
- 分发：Developer ID 签名、Sparkle 更新，**不上 App Store**。Aaron 定了：私有 API 能达成目的就大胆用，用了要登记、要有退路
- 许可：WindowShade 是 MIT。GPL、CC BY-NC、PolyForm、MMF License、没有许可文件的项目，**只借思路，不拷代码**

## 包里有什么

| 目录 | 内容 | 先看什么 |
| --- | --- | --- |
| `docs/handoff/START-HERE-deepseek.md` | **总开工提示词**：总则、绝对不做、三波开工顺序 | 第一个读 |
| `docs/handoff/deepseek-*.md` | 各工作包的提示词：conductor（指挥模式）、input（鼠标、触控板、遥控器、手柄）、pomodoro-symbols（番茄钟与符号优先）、dynamic-lock（离开就锁）、menu-agents（菜单收拢、刘海里的编程会话） | 逐个审查 |
| `docs/blueprint.md` | WindowShade 2 的总图、刘海仲裁顺序、十二条硬要求、做的顺序 | 第二个读 |
| `docs/*.md` | 各功能的规格：`conductor-v2`、`input-devices`、`pomodoro`、`dynamic-lock`、`agents-in-notch`、`menu-bar`、`face-unlock`、`privacy-page`、`direction`（Aaron 的逐项决定）、`copy-guide`（文案规则与词汇表）、`design-system`（设计令牌、§4.11 符号表）、`performance` 等 | 审查某个包时，对照它的规格 |
| `docs/handoff/chatgpt-2026-10-01.md` | 你（ChatGPT）之前写的 v2–v4 规格的要点，以及 Aaron 之后改了哪几条 | 先看“Aaron 之后的改动” |
| `upstream-specs/` | 你之前写的 v4 身份认证规格原文、v3 指挥模式规格原文和 64 个验收场景 | 对照用 |
| `code/` | 仓库里跟踪的源码（Swift）、测试、工具、`AGENTS.md`、`DEVELOPMENT.md`；去掉了 Sparkle 二进制框架和素材 | 核对 API 用法、已有入口 |
| `design-drafts/` | 九份可交互的设计稿 HTML（浏览器直接打开） | 想看交互细节时 |
| `skills/` | 我们设计时用的 Apple HIG、Apple 动效（Designing Fluid Interfaces）、Emil Kowalski 设计工程的 skill 原文；`deepseek-delegate` 是派活给 DeepSeek 的说明 | 了解设计口径 |

## WindowShade 2 的约束（审查时请拿这些当标准）

- **一个入口，一套动作，任何输入。**刘海是唯一入口；所有设备落到同一套动作；没有指针的设备用焦点导航。
- **奥卡姆剃刀。**规格没写的不做；不做配置工具、宏、脚本、用量统计；菜单一级不超过 12 项；设置项越少越好。
- **符号优先，字少。**每行一个 SF Symbol；副标题一行以内。
- **默认不接管系统输入**；开了才装钩子，回调 O(1)，被系统停掉时退回原样。
- **未知就是未知**：没读到不写 0%，没跑的不写通过，没核过的话不上界面。
- **不退步**：已有功能和能耗都不能变差。
- 1.0.16 还没发布，Aaron 说发才发。

## 请你交回什么

把下面这些文件打成一个 zip 交回。中文写，句子短，先说结论。

### 1. `review.md`：总评

- 一段总体判断：这套提示词让执行模型“闭眼施工”，最可能在哪里翻车。
- 一张问题表，每行一个问题：严重程度（阻断 / 高 / 中 / 低）、在哪个文件哪一节、问题是什么、建议怎么改。重点看：
  - 规格之间互相矛盾（比如同一个键在两份文档里含义不同）；
  - 技术上做不到，或者 macOS 27 上的行为和规格的假设不同；
  - 安全与隐私：授权、配对、hook 改用户配置、密码处理、日志；
  - 违反奥卡姆剃刀、会长成大杂烩的地方；
  - 执行模型最可能误解的措辞。
- **哪些包的顺序或拆分应该改**，为什么。

### 2. `cheatsheets/<包名>.md`：每个包一页小抄

包名照 START-HERE 里的编号：T1、L1、A1、D1、D2、I1、I9、M1、S1、T2、T4、A3、D3、D4、A2、L2、L4、I2、I3、I5、I8、I7、D5、D6。每页包括：

1. **一句话目标**和**完成的样子**（验收时看什么）。
2. **要用的 API**：确切的框架、类型、方法名和签名，标出最低系统版本。私有 API 写清符号名、已知的参数和结构体布局、来源和可信度。
3. **最小骨架**：自己写的 Swift 片段，能编译的程度；不要贴 GPL 或不兼容许可项目的代码。
4. **坑**：macOS 和硬件上已知会出问题的地方，以及怎么绕。比如：
   - `CGEventTap` 超时被停、安全输入；
   - `MultitouchSupport` 回调线程与结构体布局；
   - GameController 的后台事件与自适应扳机；
   - CoreBluetooth 连接 iPhone 后的断连行为、状态恢复，`CBPeripheral.identifier` 的稳定性；
   - `hidutil` 映射在重连后失效；
   - Claude Code / Codex hook 的确切配置格式、事件名和返回约定；
   - Codex App Server 的 JSON-RPC 方法；
   - ScreenCaptureKit、TCC 授权在重签名后丢失；
   - Swift 6 严格并发下 `@MainActor` 与回调线程。
5. **测试点**：纯逻辑该测的边界；真机该怎么试；哪一步必须 Aaron 在场。
6. **不要做**：这个包里最容易越界的地方。
7. **不确定的**：你没把握的结论，写明“需要真机确认”或“需要查官方文档”，并给出去哪查。

### 3. `prompt-patches.md`：提示词补丁

对 `START-HERE-deepseek.md` 和各 `deepseek-*.md`，给出可以直接替换或追加的段落（写明替换哪一段）。目标是让执行模型少问、少猜、少越界。

## 写的时候请注意

- 引用外部事实时给出来源（官方文档、WWDC 讲座、开源项目的文件路径）。不确定就说不确定，不要编 API。
- 不要建议拷贝 GPL、非商业许可或没有许可文件的项目的代码；可以描述它们的思路。
- 篇幅以“执行模型照着就能做”为准，不要写教程式的长文。
