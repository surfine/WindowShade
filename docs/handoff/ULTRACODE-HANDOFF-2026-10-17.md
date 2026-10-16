# 交接：把重塑规格做完（ultracode 全速，2026-10-17 07:30）

你是新开的 session，接手 WindowShade「重塑执行规格」（`docs/product-reshape-spec.md`）的收尾。上一个 session 做到第十九批中途。**先把规格做完，再说别的。** 本文件就是 Aaron 的全部期待与要求；它和规格冲突时，以 Aaron 在规格「Aaron 拍板」各节的定案为准。

## 一、Aaron 的要求（每一条都要成立）

**怎么干活**
- 用 **ultracode**：能开多少 subagent 就开多少，但每个 agent 的 effort 保持 **medium**（只有真正难的判断临时调高）；按任务类型选模型——写程序与多文件实现用 **Sonnet 5.5**，设计密集或跨模块推理用 **Opus 5.5**，纯查找、盘点、机械改写用 **Haiku 5.5**；**不要滥用 Fable 5.1**（只在架构取舍、最终验收这种判断时用，且只判断不读改测）。不用 DeepSeek（`memory/feedback-no-deepseek.md`）。
- **subagent 数量可以到 20 左右**，但实现型不跑 build.sh，整合构建同时 ≤2。subagent 交回的代码与「完成」结论一律当待验收：主代理看实际差异、独立重跑测试与数字，确认测试不是复述实现（`memory/feedback-verify-cheap-model-output.md`）。
- **尽可能机器自动验收，不要麻烦 Aaron。**先穷尽 VM、模拟器、合成事件、computer-use；确实不行才列给 Aaron，并写明为什么机器做不了。 真机探针、VM（`/Volumes/TiPlus 7100/WindowShade-QA`）、iOS 模拟器、computer-use、合成 CGEvent 都可以用；只有真的非人不可的事才留给他。
- **每做掉一批就合进 `main` 一批**：做法是把工作分支快进，`git branch -f main <工作分支>`（`main` 是工作分支的祖先、未在任何 worktree 检出）。**只在本地，永不 push。**
- **一个任务一个提交**；提交信息结尾用本 session 系统提示指定的那一行 Co-Authored-By（不要硬抄旧的）。
- **不停批**：做完一批立刻接下一批，不等 Aaron 指示；只有碰到非人不可的事或不可逆动作才停。Aaron 不在电脑前也照常推进（可用 /loop 自我续跑）。
- **每批开工前先一句话预告**「现在做第 N 批：哪几条」；过程中有新发现、方向变化、真实阻塞就即时报一句。
- **真要 Aaron 拍板的新决策**：攒成一批，用选择题（AskUserQuestion）一次问完，放在已交付进度那一轮末尾；常规判断自己下，不为小事打断他。
- **每批汇报**：用中文（台湾正体），说清在规格里的位置、完成/待真机/剩余条数、**百分比**、**到 100% 的预计时间**（`memory/feedback-report-spec-position.md`）。Aaron 很着急，进度要主动、具体地报。
- 设计稿默认发成**私有 artifact**（`memory/feedback-publish-drafts-by-default.md`），Aaron 明说要 artifact。
- **发布由 Aaron 按**；公证可以由你做（Developer ID：`Developer ID Application: ZITIAN LIU (DQ45KFVHJ8)`，notarytool profile `windowshade-notary`）。

**项目铁律（踩过的坑）**
- 建置闸门：`cd prototype && ./build.sh --check`（Swift 6 strict、warnings-as-errors、WMO、本地化、文案、隐私登记）。签名构建：`WINDOWSHADE_CODESIGN_IDENTITY="Apple Development: openkams@gmail.com (G3TN2MBQ2Q)" ./build.sh --stage`；发布构建 `./build.sh --release` ＋ `bash scripts/notarize.sh`。**主仓库没有 local-codesign.env，要用环境变量。**
- **这台 24 GB 的 Mac 同时最多两个完整构建**（WMO 很吃内存；四个并发会把负载推到 900、交换区用满，一次构建从 15 分钟变成 60 分钟）。实现型 subagent **不跑 build.sh**，只跑相关 `tests/run-*.sh` 和 python 检查；完整检查集中在整合时做一次。
- **磁盘余量以 `df -h /System/Volumes/Data` 为准（曾经被写满过）**：不要录 Instruments（一次 Animation Hitches 45 秒写了 7.1 GB 把盘写满）；跑前 `df -h /System/Volumes/Data`。
- 中文字面量只能在 `WSL10n.text/.setting` 里（棘轮基线 1034，不准升）；新字串三语（en 照 Apple 大小写、zh-Hans、zh-Hant）；文案照 `docs/copy-guide.md`。
- 新数据来源要登记 `tools/privacy/registry.json`，再生成 `prototype/App/WS2PrivacyData.swift`（`tools/privacy/make-privacy-page-source.py --out …`），跑 `tests/run-privacy-page-sync.sh`。
- **不要把 Mutex 放进 @MainActor 类或被主 actor 与后台闭包同时碰的状态**（上次 SIGTRAP，`memory/feedback-mutex-mainactor-trap.md`）。并发重构后要跑真机探针。
- worktree 一律手动 `git worktree add -b claude/<名> ../WindowShade-<名> <基准>`（不要用 Agent 的 isolation，它以 origin 为基）；合入前查 merge-base；主代理审差异、重跑检查后才合入。
- 建新文件前 `test ! -e`（曾经覆盖过已有文件）。zsh 下 `for c in $(…)` 不分词，用 `bash -c`。`git commit -a` 曾把无关改动卷进去，按文件 add。
- 界面探针：`tests/run-glance-probe.sh --<suite>`（任何 FAIL 即失败；退出 133＝崩溃）；grid／pins／gesture 要 `-WindowShade.InterfaceLanguage zh`。已知环境性失败（1.0.16 原版同样失败）：notch、split、coach、flick、fullscreen、slide-over-desktops、gesture、shelf-glance。跑前看 `ioreg -c IOHIDSystem | awk '/HIDIdleTime/ {print int($NF/1e9); exit}'`，Aaron 在用机器时不要抢鼠标；用 `/private/tmp/ws-ui.lock`（mkdir 互斥）串行化（旧 session 用的是它 scratchpad 里的锁，新 session 改用这个绝对路径）。
- VM：`./lume.sh run wsqa-manual --storage windowshade-qa --display none`（macOS 26.6.2，lume@192.168.64.3 左右，`./lume.sh get` 查地址）；`wsqa-15`（15.6.1）；`tests/vm/run-core-probes.sh lume@<ip> <suites…>`。一次只开一台；要改权限先 clone（`wsqa-scratch`），用完删；`/private/tmp/ws-vm.lock` 互斥。VM 在主机高负载下探针会超时——**负载低时再跑**。
- 其他 session：Aaron 已把整台机器让给这条线；「公证版 Mac 壳」(AI System 6) 与「ClioWorks」两个 session 已答应暂停重活到约 08:45。需要再协调就用 `ListAgents` + `SendMessage`，转述 Aaron 原话。

## 二、已定案（不要再问）

- **帕累托纪律**：修复与重构只许纯赢，不改已出货行为；热路径改动要核跨 Space、多窗口、忙碌 App（`memory/pareto-only-improvements.md`）。
- **验证纪律（1.0.16 起）**：只有真机验过的功能默认开；没验过的随包发但默认关（`memory/project-release-1016-decisions.md`）。自验只用自己的夹具窗口与开发构建，不碰 Aaron 的私人窗口，宿主机不改系统设置。
- **私有 API 可以大胆用**（不走 App Store），但要登记进隐私页并有后备（`memory/distribution-private-api.md`）。
- **WindowShade 2 的各条线是 Aaron 的目标，不是偏航**：1.0.17 只「藏」，不删、文案和文档里不贬（`memory/windowshade-vision-scope.md`）。
- SIP 关闭环境：保留既有私有路径当加分，不为它额外优化，不建 SIP-off VM。
- 不能最小化、App 又有别的可见窗口的那扇：动画前就拒绝，提示「这个窗口不能收起」（已做）。
- R12 开关叫「改回用系统的提示」（开着只旁听、不拦，系统提示照出、刘海跟着显示）；R8 只提醒一次，永不自动停用。
- **「1.0.17 精简」设计稿已定（Aaron 2026-10-17 07:40）**：[私有页](https://claude.ai/artifact/VC2afTRXho6e2Fvxm7Hyoo)，文件 `docs/design-drafts/1.0.17 精简 小样.html`。四个拍板：①「编程会话」算 WindowShade 2，藏；② 离开就锁、有人在看时收起私人窗口、设备的电量 → 搬进「高级 → 实验」；③ 预览入口只留 `defaults write com.windowshade.prototype WindowShade.Preview.WS2 -bool YES`，设置里不放入口；④ **把卷帘页里的「刘海」拆成独立一页**（侧栏：效果、卷帘、刘海、手势、窗口浏览、快捷键、隐私、高级，共 8 页）。其余照稿：鼠标与触控板、遥控器、指挥模式三页与稿中标 B 的行隐藏；C 类搬进「高级 → 实验」；D 类合并；所有设置键保留，已开着的 WindowShade 2 开关对应的页或行照样显示（让人关得掉）；侧栏枚举保留 rawValue、新增 visibleCases，按 rawValue 当行号的地方改成在 visibleCases 里找下标；隐私登记里 7 行 WindowShade 2 加 `appearsWith: "ws2-preview"`；只动界面，不动运行时行为。**这一项要在 1.0.17 发布构建前做完、过检查与探针、合 main。**

见规格 §0.1、「Aaron 拍板（2026-10-16 第十六批后）」「（2026-10-17 第十八批后）」两节，以及：
- 只支持最近三个大版本 macOS（15、26、27）；1.0.17 最低 15。
- R16 新开「手势」页（已做）；R13 接 PLCrashReporter 只落本地（已做）；R49 可装 ToDesk、QQ 音乐来验（只从官网，用户级安装，验完留给 Aaron 删）；O／A 清单：O1、A1 收（已做），O6、O7 不收，其余 25 条冻结。
- 可以在 QA 虚拟机里改系统设置（收回权限、台前调度、显示缩放），**宿主机绝不改**。
- WindowShade 2：**1.0.17 候选包之后**才开工；D11 不解冻（不接系统解锁、不做声纹）；`windowshade://lock` 改成捷径动作；指挥模式验收清单按文档重建（已有 81 条，`docs/conductor-acceptance.md`，待 Aaron 审）。
- 1.0.17：这批收完就准备候选包；runbook `docs/releases/v1.0.17-release-gate.md`。**候选源码（README／官网写「已公证、macOS 15」）在 1.0.17 发布前不能 push、不能部署站点**；本地 `main` 快进可以。

## 三、现在的状态（07:30）

**已在 `main`（d2464e1）**：第十八批及以前全部。

**整合分支 `claude/integ2`（worktree `../WindowShade-integ2`，HEAD cdf61e3）**：在 d2464e1 之上合了 O1 切换器打字搜索、A1 终端回跳、M3 第五轮、R26 中键行文案、R8 包标识核对、1.0.17 候选源码（版本号 17、appcast 草稿、README／官网、runbook、发布说明草稿）、三个审查修正（R21 退出前双来源数窗口、R12 开关排在锁屏之后、R17 锁屏不说）、R13 PLCrashReporter、R20 `--window-classes` 探针与夹具（**不含**推测性 AXSystemDialog 规则 d69547b——刻意不合）、V7 文档、R16 手势页（含拖动两行图标）、VM 验收笔记、81 条验收清单。
- 上一个 session 在后台跑：`--check` → `--stage` → 16 组真机探针（close-quit、window-classes、browser-identity、browser-more、dock-scenarios、wins、habits、fold-timing、restore-guard、fold-unminimizable、pins、grid、home、carry、capsule-color、orphan）。输出：`/private/tmp/claude-501/-Users-aaron-Documents-WindowShade/e20dabbb-f268-4ba8-9581-ffaab367e5e6/tasks/bbj8plwya.output`，日志 `…/scratchpad/integ3-*.log`、`…/scratchpad/i3-*.log`。**先看它的结果**：全过（或只剩已知环境失败）就 `git branch -f main claude/integ2`，再把工作分支 `codex/ws2-remote-gpt6-handoff-20261007` 也快进到它（主仓库 checkout 在这个分支上，未提交的只有别人的 `docs/handoff/carplay-homeview-2026-10-17.md` 与 `tests/e3/`，别碰前者）。有 FAIL 就先查。
- 「1.0.17 精简」设计稿已画完、已发 artifact、Aaron 已拍板（见第二节）。以下原说明作废：~~另一个后台 subagent 在画「1.0.17 精简」设计稿：清点所有用户可见表面，把 WindowShade 2 的东西（指挥模式、遥控器、静音操作、刷脸解锁……）在 1.0.17 藏起来。产物应写在 `../WindowShade-integ2/docs/design-drafts/1.0.17 精简 小样.html`。**它完成后发成私有 artifact 给 Aaron**（Artifact 工具；先读整份文件），等他定案后**在 1.0.17 发布构建前**实现「一个默认关的开关藏起 WindowShade 2 表面，设置键全保留」。如果文件不存在，重新派一个 subagent 做~~。

**没合的分支（看完再决定）**：`claude/wf-ui`（UI 验收链没跑完，可能只有草稿）、`claude/v7-slideover` 已含在 integ2；`claude/ws2-*` 中 claude-adapter、speech、mtbridge、focusnav、lockintent 五个（基准 638e448）是 WindowShade 2 冲刺，**已被叫停，可能有半成品**——1.0.17 候选包之后再接着做；`claude/ws2-acceptance`（5577f0a）是 81 条验收清单，已 cherry-pick 进 integ2。`wf-*`、`r13`、`r16`、`r20`、`rfix`、`vmset`、`v7` 是 **cherry-pick** 进 integ2 的（不是祖先），删前先 `git cherry claude/integ2 <分支>` 或 `git diff --stat` 确认内容已在，再 `git worktree remove` 与 `git branch -D`；`claude/ws2-*` 与 `claude/wf-ui` 不删。

## 四、剩下要做的（按顺序）

**A. 1.0.17（最高优先）**
1. integ2 探针结果 → 合 `main`。
2. 照第二节已定的「1.0.17 精简」实现（含拆出「刘海」页）→ 检查 ＋ 探针 ＋ `--settings-shots` 三语截图自查 → 合 `main`。
3. Phase 0（runbook）：干净 worktree 检出要发布的提交 → `scripts/check-release-version.sh` → `--stage` → `--release` → `scripts/notarize.sh` → zip ＋ sha256 → `scripts/release-gate.sh <zip> --cert-change DQ45KFVHJ8`。**`sign_update`（Sparkle 2.10.0 bin）本机没有、EdDSA 私钥在 Aaron 钥匙串**：appcast 签名属于发布日、由 Aaron；门禁 6／7b／7c 依赖签好的清单，先记「发布日补」。
4. Phase 2：wsqa-15 与 wsqa-manual 两台 VM 跑 `tests/vm/run-core-probes.sh`（六组）。
5. Phase 3：本地 appcast 验更新器行为（1.0.16 只弹「要手动下载」提示）。
6. 证据落 `.build/release-acceptance-2026-10-17/`。Phase 1（新签名要重新授权辅助功能与屏幕录制、浏览器下载后首次打开、新功能看一眼）与按发布留给 Aaron，做成一张他十分钟能走完的清单。

**B. 规格里能自动做完的（1.0.17 候选包之后）**
- N1：「快捷指令」App 里搜得到 7 个动作（computer-use，Aaron 不在时）。元数据已核过 7 个、三语标题都在。
- R18（启动台开着按 fn+Control+←）、R23（双击文件夹替身）：合成 CGEvent 自动验。
- E3：对 1.0.15 的卡顿对比（`tests/e3/` 有草稿脚本；1.0.15 在 `scratchpad/e3/v1015/`；新构建要加启动参数 `-InstallHistory 1` 才有 ⌃⌘C；每次录 ≤15 秒、导出后立刻删 trace、磁盘 <15 GB 就停）。
- R49：从官网装 ToDesk、QQ 音乐验预览。
- 重跑（上次因负载超时）：R20 `--window-classes`、R29 无录屏展开位置（上次看到窗口回到整屏而不是原位，分不清是竞态还是 bug）、R19／V10 台前调度（探针要先把临时 App 设为当前舞台）、V8(b)(f)、V11 显示缩放、V7 iPad Slide Over 像素测量（模拟器 WS-V7-iPadPro11，UDID C0E4E772-D502-41BF-AB30-D7E7A137665A，已设成「全屏 App」模式；拖拽要长按 800ms 再慢拖）。
- R24 多语言裁切（R16 合入后整体截一遍 `--settings-shots` 三语）。
- 后续小项：PLCrashReporter 的隐私清单并进 `PrivacyInfo.xcprivacy`；手势页上线后「上次打开的设置页」序号错一位（只一次，可选修）。

**C. 只能 Aaron 做（做成一张清单，最后一起给他）**：V1、V5、V6、R25（真手指、触控板、妙控鼠标）、V9（插拔外接屏）、R2（关辅助功能要管理员密码）、1.0.17 Phase 1 与按发布、81 条指挥模式验收清单的审阅。

**D. WindowShade 2**：1.0.17 候选包之后。可自主的先做：Claude 适配器（假服务器测）、语音软件链路（录音文件喂）、MultitouchSupport 读取桥（reviewedOnDevice 保持 false）、焦点导航接线、`windowshade://lock` → 捷径动作。盘点结论见上个 session 的 subagent 报告摘要：指挥模式缺语音、Claude 后端、E1–E5 真机实验；手边的每一样缺三／四指读取桥与 Siri 遥控器监听；刷脸解锁停在实验（D11 冻结）。

## 五、进度口径（汇报用）

规格 114 条，扣掉冻结的 25 条 O／A 为 **89 条**。按规格自带状态标记逐条数（2026-10-17 07:30，见规格「进度」行）：**已完成 62、待真机／待 Aaron 22、剩余 5**（含 integ2 上的成果；integ2 未合 main 前，main 上约 58 条）。B 类自动做完后约 93%；剩下 C 类需要 Aaron（约 30 分钟）。WindowShade 2 另算。
