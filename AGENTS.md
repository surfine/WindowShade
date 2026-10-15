> 最终交接入口：先读 [docs/handoff/FINAL-HANDOFF.md](docs/handoff/FINAL-HANDOFF.md)。第十份保留原蓝图全部目标，覆盖旧派工顺序；不覆盖用户在实际工作区的新改动。不要再从第一份顺次套补丁，也不要默认直接在 main 上修改。
>
> 第九、十份并入后的实际状态、本机证据与复核议程见 [docs/handoff/round2-part10/REVIEW-HANDOFF.md](docs/handoff/round2-part10/REVIEW-HANDOFF.md)：**W00 的编译门槛已达成：`main` 上 `prototype/build.sh --check` 退出 0，构建参数没撤；但新二进制没签名、没在真机上跑过，主线程隔离的执行期检查是否会在真机触发仍未知**（详见该文件开头一节）。
>
> 理想 vs 现实的检讨、给 GPT-6 Pro 的自包含审议包与破局落地方案见 [docs/handoff/gpt6-review-2026-10-06/README.md](docs/handoff/gpt6-review-2026-10-06/README.md)：1.0.15（2026-09-26）之后 170 个提交、0 次发布；瓶颈是一个人的验收漏斗加范围比收敛快。
>
> **最近一批未完事项（第27批 英语适配）：接手先读 [docs/handoff/BATCH27-ENGLISH-HANDOFF-2026-10-12.md](docs/handoff/BATCH27-ENGLISH-HANDOFF-2026-10-12.md)**。它是 [设计接手交接（DESIGN-TAKEOVER-2026-10-11.md）](docs/handoff/DESIGN-TAKEOVER-2026-10-11.md) 的延续，不是替代——那里面除英语外的动效/真机验证线同样继续。实现已全部完成并大部分验收通过；剩两个卡点（语言切换后设置窗口落到「效果」页；滑杆行读数两个布局形态）与收尾流水线。**英语已定案为全量完全适配、不留手尾（含官网与 README、随批滚动同步；验收轻量档；英文照 Apple 大小写惯例；繁体不做但留余地；证据过即收尾）**，剩余表面清单与完成标准在交接 §9、两轮问答全部定案在交接开头。交接 §10 是**同日晚间补记**：全史已重写为账号归因 `Aaron <12213433+surfine@users.noreply.github.com>`（旧 SHA 作废，对照表在 .statem/history-design-twentyseventh-round/qa/commit-map-final-2026-10-12.txt）、README 双版已重写、**1.0.16 发布关 Phase 0 已过（候选包 + 包级门禁全 PASS），等用户真机 Phase 1–3 后走发布日流程**（runbook：docs/releases/v1.0.16-release-gate.md）——新 session 的优先顺序在 §10 末尾。

# 项目约定

**接手前先读 [`docs/blueprint.md`](docs/blueprint.md)**：WindowShade 的总图、刘海仲裁顺序、做的顺序和十二条硬要求。
交给 DeepSeek 时，从 [`docs/handoff/START-HERE-deepseek.md`](docs/handoff/START-HERE-deepseek.md) 开始。
交给 Grok 时，从 [`docs/handoff/START-HERE-grok.md`](docs/handoff/START-HERE-grok.md) 开始；2026-10-04 主模型裁决见 [`docs/handoff/MAIN-MODEL-DECISIONS-2026-10-04.md`](docs/handoff/MAIN-MODEL-DECISIONS-2026-10-04.md)。

## 文案（产品与官网共用）

面向用户的每一句文案都按 [`docs/copy-guide.md`](docs/copy-guide.md) 写：说用户遇到的事、不说实现，
一个东西只有一个名字，一句话一件事，术语先用日常说法，能删就删。改动界面文案或官网文案时，
先读那份规则；新增用户可见字符串时用它自检，不要等用户来提醒。

固定词汇表也在那份文件里（收起/展开、卷帘条、置顶、窗口浏览……），菜单、设置、面板、官网必须一致。

## 设计稿

写产品代码、测试、界面、官网、README 或宣传之前，先打开 [`docs/design-drafts/README.md`](docs/design-drafts/README.md)，对上那一张稿。形状、弹簧、开口和收起以稿里的画面为准，不要凭现在画出来的尺寸现编。书面令牌仍是 [`docs/design-system.md`](docs/design-system.md)。稿和令牌不一致时，画面照稿，不顺便改设计系统；对不上的记进 [`docs/design-grammar.md`](docs/design-grammar.md) 的对照账。新表面先过那份文法的准入。稿是画面，不是源码，不嵌进工程。

## 竞品与重塑（2026-10-15，动手前先读这两份）

这一批工作有一整套文档，**入口在这两份**：

- **[北极星：公认范畴下的全面超越](docs/north-star.md)** ——「全世界最好」被定义成什么（不是「别人没有的东西」，是**众人都认可的十一项每一项都赢**），我们已有的结构优势、还缺什么、**四条已定案**（扩展面只做最小切口／录屏当增强不当核心／诊断纯本地永不上网／发布由 Aaron 点头）。
- **[成熟度自评](docs/maturity.md)** —— 我们作为**产品／工程／长期项目**在哪、差多远、怎么补（逐维度带证据，含「工程质量高于多数竞品、出货成熟度低于所有竞品」这句结论）。
- **[重塑执行规格](docs/product-reshape-spec.md)** —— **要动手就执行这一份**。**先读它的 §0.2：那一版只做 6 条；队列只置换、不增长**（冻结区有 74 条，解冻只有两种情形：上一批清空，或它在真机上被撞到）。每条带**依据、现状（文件与行号）、改动要点、验收、风险、依赖**；§1 是执行前提与铁律，§7 是 11 条自纠。

支撑材料（按需回查，不必通读）：[竞品深挖](docs/competitive-deep-dive.md)（机制层 ＋ 函数级证据）、[更新日志里的 real-world know-how](docs/changelog-knowhow.md)（626 个 release 归成 13 个失效家族，逐条标我们暴露在哪）、[功能碾压](docs/dominance.md)（逐格矩阵）、[性能与能效](docs/perf-energy.md)、[Apple 原生优先](docs/apple-native.md)、[现代化](docs/modernization.md)、[竞品包装](docs/competitive-packaging.md)／[官网](docs/competitive-websites.md)。

**一条纪律**：那批文档里**任何要写进文档的数字，都要在本轮用绝对路径、可重复的命令重新数一次**；**断言「没有」的成本比说「有」高一个数量级**——说「有」给一个例子就行，说「没有」要把全表过一遍（§7 的 13 条自纠里有 8 条栽在这）。

## 其它

- 全部文档按「什么时候读」分区的索引见 [`docs/README.md`](docs/README.md)。
- 面向开发者的构建、签名、发布流程见 [`DEVELOPMENT.md`](DEVELOPMENT.md)。
- 面向用户的说明见 [`README_CN.md`](README_CN.md) / [`README.md`](README.md)。

## 技能

- 改 Swift 代码先用 `write-swift`（处理 .swift 文件时会自动加载）；菜单栏、面板、控件等原生界面问题先读 `hig-foundations` / `hig-platforms`，再按它们指向的 hig-* 子技能查具体组件。
- 验收原生界面行为时按 `computer-use-practice` 的观察—输入—复核闭环操作，证据要求见下节。

## Computer Use 验收

涉及原生界面行为的改动，按 [Computer Use 验收手册](docs/computer-use-qa.md) 选择场景并提交对应构建证据。使用隔离 Mac 和受控资料，执行“观察、确认目标、单步操作、等待变化、重新观察、对照预期”；不能把工具退出 0、AX 写入成功或产品日志成功当作可见效果通过。缺证据写 inconclusive / not_run，保留首次失败与恢复记录。不要把历史签名二进制的结果套给当前源码，也不要用 VM 代替真实硬件矩阵。
