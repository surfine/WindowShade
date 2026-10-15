# 功能碾压：定义、矩阵、还差什么

2026-10-15。这一份把「功能上碾压所有参考过的竞品」拆成**可以逐格核对的东西**。依据：[scorecard](scorecard.md)（逐领域打分与真机探针）、[竞品深挖](competitive-deep-dive.md)（九份正版件的静态面／呼叫轮廓／函数级）、[更新日志里的 real-world know-how](changelog-knowhow.md)（626 个 release）。

## 一、先把「碾压」定义清楚

**碾压不是「我们自己打分比它高」。** 按现在这张[计分卡](scorecard.md)，至少有三处不能叫碾压：

- **有一行我们落后**：窗口浏览 **92 : Wins 93**。
- **有一行同分**：从 Rectangle / Raycast 换过来 **90 : Rectangle 90**。
- **有几行竞品在做、我们连「行」都没有**——自愈与崩溃上报、设置备份与迁移、同类工具检测、扩展面。

所以「碾压」在这份文档里就是三条可核对的要求：

> **① 每一行严格领先**（同分不算，落后要补）。
> **② 领先要有真机证据**（自己写的探针跑过的算；「手感还要亲手确认」的不算）。
> **③ 比较表要完整**——竞品有的能力我们不能没有「行」；补行之后按 ①② 走。
> **④ 性能与能效要在同口径下对赢**（见[性能与能效](perf-energy.md)）——**不引用对不上的数字**。

## 二、矩阵（逐格）

`我们` 一列是[计分卡](scorecard.md)现在的分；`最强的别家` 取自同一张表。

| 领域 | 我们 | 最强的别家 | 领先？ | 真机证据 | 要变成「碾压」还差什么 |
| --- | :---: | --- | :---: | --- | --- |
| 收起本体 | **92** | WindowMizer 75 | ✓ | thumbnail 13、notch 20、magic 5、pull 4 | 补三条来自 WindowMizer 的边界：**孤儿占位条主动收掉**、**还原串行队列＋深度**、**收起时读 `axToolbarH`**（规格 R10／R11）；**先复现再改**「还原期间压掉 App 的 unhideAllWindows」（R9） |
| 窗口浏览 | **92** | **Wins 93** | **✗ 落后 1** | browser-more 4、wins 7、mc-keys 4 | **唯一落后的一行。** 把 **原生标签页合并**做掉（四家独立印证，规格 R4，含「被拖出来的标签各自成条」）；再把 DockDoor 那 12 条 release 场景逐条上机（[competitive-analysis.md](competitive-analysis.md):33 已列，未上机） |
| 盒盖动画 | **88** | 无同类 | ✓ | duo 套件 | **手感要 Aaron 亲手确认**——确认前按定义不算碾压 |
| 启动台 | **90** | LaunchOS 85 | ✓ | launchpad 13、launchpad-keys 18、home 3 | 真多指没单独测；可考虑 LaunchOS 那条**读系统 SQLite** 的路（规格 R15）作为「顺序与原生一致」的加固 |
| 标题栏手势 | **92** | Swish 85 | ✓ | gesture 31、flick 5、grid 4、magic 5、strip 8、strip-peek 19、dock-gestures 4 | 已领先；可借 Swish 的**九类设置分栈**整理设置面（规格 R16，纯整理不改行为）；**Magic Mouse／罗技滚轮没人上手试过** |
| 甩一下 | **94** | iPadOS 27 | ✓ | flick 5 | 真三指没人上手试过 |
| 刘海 | **88** | Alcove | ✓（分值最低的一行） | notch 20、home 3、coach 6、habits 7、notch-shape 10 | 签名构建重跑 notch／home；**Acclove 级媒体波形**（有意不抄私有绘制，需另定公开路子） |
| 看一眼 | **95** | DockDoor 60 | ✓**最大领先** | pull 4、thumbnail 13、strip-peek 19 | 「刘海那几种 `--shelf-glance` 还没在 build 16 上跑」——补跑 |
| 侧拉 | **93** | iPadOS 27 | ✓ | slide-over 15、slide-over-desktops 5 | 像素级比对要 iPadOS 27 模拟器（约 8 GB，待 Aaron 同意下载）；真触控板、慢 App 没人试 |
| 分屏 | **92** | Swish 85 / iPadOS 27 | ✓ | split 6 | 差 iPadOS「从 Dock 拖出来直接分屏」那一下（我们从启动台拖） |
| 从 Rectangle / Raycast 换过来 | **90** | **Rectangle 90** | **✦ 同分** | rect 5 | **没在装着 Rectangle 的 Mac 上点过一次**——上机一次即可能拉开；顺带把 R8 的**同类工具检测名单**用上 |
| 性能 | **89** | Wins 宣称 <30 MB、CPU ~0.1% | **✦ 口径未对齐** | 60 秒静置实测 | 见[性能与能效](perf-energy.md)：**先查清 30 MB 的口径再谈输赢**；我们 100 MB |
| 价格 / 做法 | **100** | Wins 70 | ✓ | — | 免费 ＋ MIT，这一行没有对手 |

### 竞品有、我们**连行都没有**的（补行清单）

| 缺的「行」 | 谁在做 | 为什么要补 | 规格 |
| --- | --- | --- | --- |
| **稳定性自愈** | DockDoor（5 秒看门狗、事件投递金丝雀）、Wins（`missionControl.tapDisabled` 埋点）、ChainYourMac（官网的 self-healing engine） | 「装了几个月忽然不好用」是这一行的全部内容 | **R1 已做**（事件通道周期体检）＋ R2／R3 |
| **崩溃上报** | WindowMizer 内嵌 PLCrashReporter，带 `hw.model`／`kern.osrelease` | [production-maturity](production-maturity.md) 里那条至今空白 | R13 |
| **设置备份与迁移** | DockDoor（JSON 导出／导入 ＋ 设置搜索能搜到）、OmniWM（`.pre-vN` 备份、forward-only） | 现在是「新增必填项就回默认值」 | R5 |
| **同类工具检测** | **四家**：ChainYourMac（13 项名单）、Alcove／MediaMate（`betterDisplay*`）、Wins | 装着重叠功能的工具是常态 | R8（名单现成） |
| **接管系统 HUD 可退回** | MediaMate（`Disable Hiding Native OSD`） | 接管别人的东西要留退路 | R12 |
| **Secure Input 的可见说明** | OmniWM（菜单栏红锁 ＋ 一行说明） | 用户不知道为什么快捷键没反应 | R17 |
| **扩展 / 自动化面** | OmniWM（`omniwmctl` NDJSON socket）、ChainYourMac（URL scheme ＋ Raycast ＋ CLI）、DynamicLake（Market ＋ plugin） | [niri.md](niri.md):91 现在写的是「不追」——**建议重评**：三家都发了，这是市场期望 | **N1：Apple 的原生答案是 App Intents**（见 [Apple 原生优先](apple-native.md)）——免费得到快捷指令／Spotlight／Siri，**不必自造 CLI 或 URL scheme**。这一条把「要么自造一套、要么放弃」变成第三条路 |

## 三、结论：要做到碾压，先做这四件

1. **窗口浏览那 1 分**（唯一落后行）：原生标签页合并 ＋ DockDoor 那 12 条场景上机。
2. **补四行空白**：自愈（R1 已做一半）、崩溃上报、设置备份与迁移、同类工具检测——**这四行竞品有、我们没有，不补就谈不上碾压**。
3. **把「未上机」清掉**：矩阵里凡是没有真机证据的格子，按 ② 都不算数。优先：盒盖动画的手感确认、刘海在签名构建上的重跑、`--shelf-glance`、Rectangle 换过来的上机。
4. **能效同口径**：先把 Wins 那 30 MB 的口径查清（[性能与能效](perf-energy.md) E2），再决定这一行怎么写。

## 四、这一节的口径与界线

- **分数只作索引，不作结论**：真正的结论在「凭什么 / 还差什么」那一列——它是可核对的事实清单。
- **真机证据按 [Computer Use 验收](computer-use-qa.md)**：工具退出 0、AX 写入成功、日志成功**都不算**；缺证据写 `inconclusive` / `not_run`。
- **不引用对不上的数字**：竞品官网的自我宣称（Wins 的 30 MB、<0.1% CPU）只能写成「它的宣称」。
- **界线不变**（[竞品深挖](competitive-deep-dive.md)§一）：不绕过保护措施；不搬代码；GPL 那几家只借思路。**「碾压」指的是我们自己做出来，不是把别人的东西搬过来。**
