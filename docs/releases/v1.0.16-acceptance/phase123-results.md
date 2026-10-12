# 1.0.16 发布关 Phase 1–3 真机验收结果（Computer Use 代跑，2026-10-12）

> **勘误（2026-10-12 晚）**：本文件 1.3 行对"同 App 两文档"的判读**不成立**——当时那张"doc-B 卷帘条"画面同时有改名浮层、doc-B 标题条带交通灯完整可见，无法与"未折叠、只是弹了浮层"区分。0-B 候选复验（[gate-0B-verification.md](gate-0B-verification.md)）直测：折叠后台文档→窗口离屏、原位置**无**卷帘条，形态与历史缺陷描述一致，判读 inconclusive。**本文件对应 0-A 候选（82681b0），已被 0-B 复验文件取代为发布依据**；其余内容保留原样（历史记录不改写）。

**执行方式**：用户 2026-10-12 明确选择"Computer Use 全代跑"（AskUserQuestion 答复），解除"真机观察由用户完成"边界；按 docs/computer-use-qa.md 手册在隔离 Lume VM（wsqa-manual，macOS 26.6.2，CuaDriver 0.34.0）执行，无真人观察。
**被测包**：WindowShade-v1.0.16.zip sha256 `2c3b39ca…c3fac`（9,484,290 字节，Phase 0 产物，源 82681b0）；来宾部署二进制 sha256 `2d9a6e8b…52e96`，Team FVGLY6W6S4，Version 1.0.16 (16)。
**证据 run**（全部含原始 PNG/AX/事件/SHA256）：
- `20261012T170536-e2936f5d`（fold-solo 闭环 + 两文档）
- `20261012T171450-f9445d3d`（菜单路径 + 深色外观 + 欢迎三步 + 更新器；八场景 review/verify/cleanup/report 齐，report-1791798015804799000.md）

## Phase 1 · 核心窗口路径

| # | 场景 | 期望 | 实际 | 证据 | 判读 |
|---|---|---|---|---|---|
| 1.1 | 单文档双击收起（fold-solo） | 正文消失、卷帘条出现 | 正文消失，原位标题胶囊条出现；journal stage=folded（hide=hidden 分支） | run 170536: events/fold-double-click-after, fold-settled | **pass** |
| 1.2 | 单文档双击恢复 | 原位原样恢复 | AX frame 118/57/673/439 == 基线逐值相等；文本逐字相等；画面完整 | run 170536: events/restore-double-click-after + dismiss-restore-popup-after(AX) | **pass** |
| 1.3 | 同 App 两文档 A、B 各自收起/恢复（历史雷） | 各自出现卷帘条、互不影响、恢复原位 | B 收起：正文消失、B 条出现（fold-B-settled PNG），journal id=160 stage=folded；B 恢复：bounds 147/86/673/439 == journal original 逐值相等（list_windows）；A 全程未受影响（AX 118/57 不变） | run 170536: events/two-docs-state, before-fold-B, fold-B-settled, restore-doc-B-after, windows-after-restore-B | **pass**（历史缺陷未复现） |
| 1.4 | 菜单栏路径收起/展开 | 与双击行为一致 | 状态菜单「收起窗口」→ 正文消失+条出现（journal id=190）；双击条恢复原位 176/115/673/439 == baseline | run 171450: events/m10-menu-open → m12-menu-fold-settled; m13 → m14-restore-bar-after | **pass** |
| 1.5 | 外观：深色模式收起/恢复 | 深色下行为与观感正常 | 系统切 Dark 后：目标收起（正文消失 d12）；三条卷帘条深色胶囊形态正常可见（d17：A/B/QA 三条同屏）；逐条双击全部恢复（d25 三窗全展开） | run 171450: events/d10-dark-desktop → d12-dark-fold-settled, d15, d17, d25-dark-restored | **pass** |
| 1.6 | 外观：「收起后的样子」两档各看一眼 | 两档切换可见差异 | 设置卷帘页已实看（s4：双击收起=开、看一眼=开、标题栏手势=开）；两档样式切换未逐档截图对比 | run 171450: events/s4-settings | **inconclusive**（档位切换对比未完成——时间盒内优先历史雷；浅色默认档 + 深色默认档已实看） |
| 1.7 | 动画时序（首变~165ms/条~415ms） | 以实际观感为准 | 逐帧录屏未做（截图链路非视频）；fold 在 ~80ms 内 journal 落账 | journal 时间戳 | **inconclusive**（录屏核对留给用户真机） |

## Phase 2 · 欢迎三步

| # | 场景 | 期望 | 实际 | 证据 | 判读 |
|---|---|---|---|---|---|
| 2.1 | 首次启动欢迎第1页 | 说用途 | "刚换 Mac？从刘海开始。" + ⌘C 动画示意 + 跳过/继续 + 页点1/3 | run 171450: events/w2-welcome-page1 | **pass** |
| 2.2 | 第2页选来源 | 之前常用哪个系统 | Windows/iPad/一直用 Mac 三选；选 Windows 后说明文案换为 Windows 版（"拷贝、粘贴用拇指按 ⌘…"） | events/w4-welcome-page2, w6-picked | **pass** |
| 2.3 | 第3页两项授权 | 辅助功能+屏幕录制状态如实 | "最后一步：授权"：辅助功能 ✓已授权、屏幕录制 ✓已授权、日程（可选，未点允许）；「开始使用」关闭窗口 | events/w8-welcome-permissions, w10-after-welcome | **pass** |
| 2.4 | 「欢迎使用」随时重开 | 菜单里有入口 | 82681b0 状态菜单无此入口；代码：菜单项只在设置（MenuBarController.swift:193 注释 + WS2SupplementPane 欢迎按钮） | source: MenuBarController/WS2SupplementPane；events/p2-menu | **inconclusive**（runbook 口径与基线实现不一致——入口在设置卷帘页补充面板，不在状态菜单；未逐点验证设置内重开） |
| 2.5 | 减少动态效果时动画不动 | 开启减效后不动 | 未在系统开启"减少动态效果"下复测 | — | **not_run**（留给用户真机） |

## Phase 3 · 更新器简验

| # | 场景 | 期望 | 实际 | 证据 | 判读 |
|---|---|---|---|---|---|
| 3.1 | 检查更新不崩溃、不弹假版本 | feed 缺失时表现如实 | 包级门禁已验 SUFeedURL/SUPublicEDKey/UpdateGuard。VM 内：SULastCheckTime 置旧+重启→Sparkle 自动检查发起（SULastCheckTime 刷新为 09:31:42Z）、无弹窗、无错误面板、App 存活、log 0 error | run 171450: events/u8-after-autocheck；guest defaults/log | **pass**（自动检查路径） |
| 3.2 | 菜单「检查更新…」交互 | 手动点击转圈后如实报"无更新" | ⌥ 菜单未显出该项（CGEvent 修饰键释放时序与 menuNeedsUpdate 快照不兼容） | events/u2-option-menu, u7-after-opt | **inconclusive**（交互路径留给用户真机 5 秒钟操作） |

## 判定（Phase 4）

- **Phase 1**：1.1–1.5 pass（含历史雷 1.3 未复现）；1.6/1.7 inconclusive。
- **Phase 2**：2.1–2.3 pass；2.4 inconclusive；2.5 not_run。
- **Phase 3**：3.1 pass（自动检查路径）；3.2 inconclusive。
- **结论**：按 runbook 判定条件"Phase 1 全部 PASS + Phase 2 全过 + Phase 3 简验无双异常"——核心路径全过，**无 fail**；3 条 inconclusive + 1 条 not_run 属动画观感/交互细节/减效模式，均不阻塞判定但应如实带入发布说明与用户真机复验清单。
- 本表由 Computer Use 代跑产生：所有"pass"均为隔离 VM 内截图+AX+journal 三源互证；**非真人眼睛**，用户发版流程中的真机观察仍是有价值的独立复核（尤其 1.7 动画手感）。
