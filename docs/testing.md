# 测试分层

这份文件回答一件事：**改了什么，就该跑哪一层，跑到什么程度算过。**
构建、签名与发布步骤见 [DEVELOPMENT.md](DEVELOPMENT.md)；修缺陷的顺序与等待见 [fix-process.md](fix-process.md)。

托管 CI 目前不可用，验证一律在本地完成，结果由 `scripts/local-gate.sh` 留在 `.build/gate/`。
**没有留下证据的验证，按没验证算。**

## 分层

| 层 | 测什么 | 命令 | 预算 | 何时跑 |
|---|---|---|---|---|
| L0 编译与静态检查 | Swift 6 严格并发、warnings-as-errors、本地化键、隐私登记、文案禁词 | `scripts/local-gate.sh check` | 约 5 分钟 | 每次推送前 |
| L1 单元 | 状态机、几何、解析、策略；284 个脚本（排除表 25 条后 259 个进门禁；已完结轮次的证据快照在 tests/archive/，不参与自动发现） | `scripts/local-gate.sh unit --jobs 6` | 5–8 分钟 | 每次推送前；改动集中时用 `--only <关键字>` |
| L2 AppKit 离屏 | 设置、经典卷帘条、收起动画、看一眼生命周期、菜单栏遮挡等 13 个套件 | `scripts/local-gate.sh appkit` | 1–3 分钟 | 改窗口、覆盖层、设置界面时 |
| L3 签名探针 | 真机上的收起计时、恢复守卫、标题栏手势、原生标签页、窗口外框 | `cd prototype && ./build.sh --stage`，再 `bash tests/run-glance-probe.sh …` 等 | 5–15 分钟 | 改窗口行为、手势、恢复逻辑时 |
| L4 虚拟机 | 另外两个支持版本上的核心探针：收起计时、恢复守卫、不可最小化、孤儿条、窗口列表 | `tests/vm/run-core-probes.sh lume@<地址>` | 10–90 分钟 | 每周一次、发版前 |
| L5 发布关 | 版本号、Developer ID 签名、公证、包内容与上一版 DR | `scripts/local-gate.sh release --previous <zip>` | 20–40 分钟 | 每次发布 |

## L0：编译与静态检查

`prototype/build.sh --check` 不是类型检查，而是**和发布构建同参数的优化编译加链接**
（`-O -whole-module-optimization`、`-swift-version 6 -strict-concurrency=complete -warnings-as-errors`），
随后跑本地化、隐私登记、隐私页同步和文案 lint。它不签名、不修改 app bundle。

- 需要完整 Xcode（`xcodebuild`、`appintentsmetadataprocessor`、`xcstringstool`、Metal 工具链）。
- 需要 `prototype/Vendor/Sparkle.framework`；缺了会直接失败，不会静默跳过。
- 声纹模型在 `../WindowShade-models/speaker/` 时会被编进包；不在时构建照常通过，但**产物少一个资源**，发版前必须确认。

## L1：单元

`scripts/local-gate.sh unit` 自动发现 `tests/run-*.sh`，按 `tests/gate-excludes.tsv` 排除需要授权、
签名构建、真实窗口或预期非零的脚本。默认 4 路并行，每项硬超时 300 秒。

- 脚本退出 78 表示“本机不能跑”（缺 codex、不是 macOS 等）：门禁记为 skip，打印并计入 `summary.json` 的 `skipped`，不算失败，但末行会写出跳过数，不会悄悄过去。
- 想只跑相关的：`scripts/local-gate.sh unit --only fold`。
- 想知道会跑什么、排除了什么：`scripts/local-gate.sh list`。
- 新增测试脚本如果要进日常门禁，**不要**加进排除表；如果它会弹窗、改用户窗口或需要授权，必须加进排除表并写原因。

排除表不是“失败清单”。排除项要么由更高层覆盖（AppKit、VM、发布关），要么在
[known-failures.md](known-failures.md) 里登记。

## L2：AppKit 离屏

`tests/run-appkit-tests.sh all` 一次编译，按套件分别起进程。它依赖 `rg`（ripgrep）；
没有 `rg` 时源文件清单为空、编译直接失败，属于环境问题，不是代码回归。

## L3：签名探针

先 `cd prototype && ./build.sh --stage`（需要 Apple Development 身份），再按改动选探针：

- 收起/展开与恢复：`bash tests/run-glance-probe.sh --fold-timing`、`--restore-guard`
- 标题栏手势：`bash tests/run-glance-probe.sh --gesture`
- 按住卷帘条切到另一张桌面：窗口应跟过去；私有符号不可用时窗口留在原桌面，日志出现 `method=fallback`
- 原生标签页与外框：`bash tests/run-native-tabs-probe.sh`、`bash tests/run-window-frame-probe.sh`

这些探针会开临时窗口、读辅助功能；失败要保留日志，不要靠删断言变绿。

## L4：虚拟机

两台机器在外置 QA 盘：`wsqa-manual`（macOS 26）与 `wsqa-15`（macOS 15）。
前置：`--stage` 构建、本机跑过一次 `run-glance-probe.sh` 生成夹具、SSH 免密、来宾已授权。
```sh
tests/vm/run-core-probes.sh lume@<wsqa-manual 地址>
tests/vm/run-core-probes.sh lume@<wsqa-15 地址>
```

默认组：`fold-timing restore-guard fold-unminimizable orphan wins browser-more`。
虚拟机只有 2–4 核，计时只看是否跑通，不和本机比；`browser-more` 的 5 秒等待偶发不够，
失败先重跑一次，仍失败记 `inconclusive` 并写入已知失败。

**跑之前先看客体的图形会话有没有锁屏**（2026-11-10 踩到）：

```sh
ssh lume@<地址> 'ioreg -n Root -d1 -a | grep -A1 CGSSessionScreenIsLocked'
```

`true` 时六组会一起红，报 `timeout: fixture window … posErr=-25205`，夹具窗口列出来了但没有位置/尺寸。
这**不是代码回归**，也不是负载问题（负载降到 4 也一样）：锁屏会话里新起的 App 建不出真窗口。
解锁（VM 窗口或 VNC）后重跑即可；重启不会绕过它，自动登录后仍停在锁屏。

`wins` 组的两条（⌥Tab 切换、Dock 图标收起前台 App）在虚拟机上会红着跑完：虚拟机里临时 App 抢不到前台、
Dock 图标的热区也拿不到，探针按设计打成 FAIL 但组 verdict 仍 PASS（verdict 只看有没有抛异常）。
判性质的办法是本机跑同一组：本机 2026-11-10 全项 PASS。虚拟机上的这两条 FAIL 不作为回归，也不要删断言。

## L4b：台前调度门禁的机器前置

`scripts/stage-manager-gate.sh` 六项里有一条（`--second-display-desktops`）要求
**外接屏上至少两张桌面**。缺这一项时门禁判失败，这是有意的：没跑到的边界不能算过关。
发版机因此有一条固定前置——接一块外接屏，并在调度中心给那块屏加一张桌面；换机器先配好，别在发布当天撞到。
不采用「门禁自己建桌面」（要动用户的调度中心状态、走私有 API），也不采用「SKIP 记成不予验证」（等于放水）。
判断记录见 [decisions-2026-11-10.md](decisions-2026-11-10.md) 的 A4。

## L5：发布关

`scripts/local-gate.sh release --previous <上一版 zip>` 依次跑版本号检查、`--release` 构建、
包级门禁。发布关要求工作区干净；**证据目录里的 `summary.json` 要与 tag 指向的提交一致**。
包内资源（尤其 `SpeakerEmbedding.mlmodelc`）按本机模型是否存在显式核对。

## 失败时怎么记

失败项、环境、复现步骤、最后核对日期写进 [known-failures.md](known-failures.md)。
只在 CI 虚拟机上出现、已决定不修的问题也要登记，并写清“为什么暂时不修”和“下次什么时候再看”。
