# 应用内更新

应用内更新由 Sparkle 2 负责查新版、验签、下载和交换，WindowShade 在前后加了三道自己的关：授权不丢、坏包不会让人没了 App、第一次打开时引导移进“应用程序”。
2026-09-29 的设计稿（含当时的推理和出处）归档在 [archive/2026-11-11/update-design-2026-09-29.md](archive/2026-11-11/update-design-2026-09-29.md)，
那份稿子里的文件名和若干决定已被实现取代，以本页和代码为准。

## 现状

- **代码位置**：App 一侧是 `prototype/App/Updater*.swift`（`UpdaterSparkle.swift` 是唯一接 Sparkle 的一层，`UpdaterSystem.swift` 放 DR、备份、换回、launchd），
  纯逻辑是 `prototype/Core/Update*.swift`，看护（guard app）是 `prototype/Watchdog/`（`main.swift` 和它自己的一份菜单栏图标 `GuardIcon.swift`）。
  看护只编 `Watchdog/` 下的两个文件，加上 `Core/UpdateVersion.swift`、`UpdateModels.swift`、`UpdateDecisions.swift`、`WSL10n.swift`、`PrivacyPaneName.swift`、`InterfaceLanguage.swift`
  和 `App/UpdaterSystem.swift`、`App/UpdaterCopy.swift`（清单见 `prototype/build.sh`）。
- **Sparkle**：2.10.0，放在 `prototype/Vendor/Sparkle.framework`，已删 XPCServices。每次构建从 `Vendor/` 重新放一份进包，再裁掉 `Headers`、`PrivateHeaders`、`Modules`，
  本地化只留 `Base`、`zh_CN`。升级流程见 [DEVELOPMENT.md](DEVELOPMENT.md)。
- **更新清单**：`site/public/appcast.xml`（Apple 芯片）与 `site/public/appcast-intel.xml`（Intel 实验版）。`--stage` 和 `--release` 构建把 `SUFeedURL` 写进 Info.plist，
  日常 `./build.sh` 出来的开发版不写，更新器不启动。清单条目照 [DEVELOPMENT.md](DEVELOPMENT.md) 的发布流程手工维护，没有生成清单的脚本。
- **签名与公证**：从 1.0.17 起发布包用 Developer ID 签名并公证（步骤见 [DEVELOPMENT.md](DEVELOPMENT.md) 的发布一节）。Developer ID 的 DR 与更早的开发证书不同，
  所以 1.0.17 是“换证书的一版”：清单条目标 `sparkle:informationalUpdate` 配 `belowVersion`，旧版只提示、手动下载一次，并要重新授权。
  之后各版回到“DR 与上一版逐字相同”，由 `scripts/release-gate.sh` 核对（换证书时用它的 `--cert-change <Team ID>`）。
- **部署目标**：macOS 15.0（`prototype/build.sh`）。
- **测试**：`tests/UpdateTests.swift` 由 `tests/run-update-tests.sh` 跑；`tests/run-update-integration.sh` 是集成测试；发布关是 `scripts/release-gate.sh`。

## 实现细节

- **看护等旧版**：第一段（旧版还开着）用 DispatchSource 的进程源（即 kqueue `NOTE_EXIT`）等旧 pid，用 `Update/` 目录的文件源等日志变化，
  不轮询；后面几段各有上限（最多约三分钟），仍每 0.5 秒看一次安装任务和日志。
- **否决后看护不自己走**：旧版还开着时，日志变成 `cancelled` 或 `refused`，看护不退出；App 确认 Sparkle 的安装任务没了才 `SMJobRemove` 它，
  删不掉就一直留着。旧版在 `cancelled` / `refused` 时退出，看护照样等安装任务结束：没装上就安静退出（他自己退的，不重开旧版），
  顺手丢掉 `.partial`、放回另存的日志；装上了，`refused` 直接换回，`cancelled` 补做 DR 比对和试跑，不过就换回。
- **补关不盖新版的状态**：看护补完关只把 `started`、`gating`、`cancelled` 改成 `approved`；新版同时写下的 `launched`、`healthy` 不动。
  新版在 `launched` 或 `approved` 时都会做 10 秒后的自查、写 `healthy`。补关里只有“通过”和“试跑偶发超时”放行，其余结论都换回。
- **换回没做成**：终态 `restoreFailed`（备份缺失、SHA-256 或 DR 不对、交换失败）。撤掉 `refused.json` 里这一条，打开装着的那一版；
  它读到 `restoreFailed` 就照常运行，说一次“没能换回 1.0.16，还在用 1.0.17。”（按钮 **好** / 反馈问题），然后清掉日志和备份。
  新版在 `main` 里要交出去换回之前，先看备份文件在、名字对得上 from 那一版；不对就直接走这条，不交出去，免得“启动→退出”循环。
- **位置判断拆成两行**：“不在‘应用程序’里（含被系统挪走、只读卷）”给 **移到“应用程序”**；在“应用程序”里但卷不支持交换、或和缓存不在同一个卷
  （home 在外接磁盘上），移过去也没用，所以不进欢迎窗口，更新小窗说“这台 Mac 上没法在菜单里更新 WindowShade。到下载页下载新版，
  拖进“应用程序”文件夹替换原来那一份。”，按钮 **打开下载页** / 稍后再说。
- **移到“应用程序”的两条保护**：那里已有的一份不比自己旧，就打开它，不移（欢迎窗口和更新小窗都这样）；那里已有的包签名要求和自己不同，不替换，
  按“没能移过去”处理。标准账户放进 `~/Applications` 时，`/Applications` 里的旧版不动，副句也不说“会换成这一版”。
- **签名变了而换回**：旧版说的是“这一版要手动安装。装好后，要重新打开辅助功能和屏幕录制。”（按钮 **打开下载页** / 稍后再说），
  不说“没能正常打开”。
- **下载中退出**：Sparkle 的安装任务已经提交（解包已开始、消息还没到）时，按“解包到结论”那一段处理：挂起退出、否决、确认任务没了再放行。
- **Sparkle 在关里或过关后报错、收掉会话**：不再停在 gating / approved。关里的直接按否决收尾；过关后的每 3 秒看一次安装任务，没了、
  或 30 秒还没让 App 退出，就删掉任务、按否决收尾，说“没能更新到 1.0.17，稍后再试。”。
- **落盘**：更新日志、`refused.json`、`backup.json` 每次写都 `F_FULLFSYNC` 后再改名、再同步目录，“先写 restoring 再交换”在掉电后也成立。
- **`--write-sample-state` / `--read-state`**（`App/UpdaterLaunch.swift`）：样例是停车日志（照 `Recovery/Journal.swift` 的字段）、
  这一版偏好的快照、一份更新日志；读的一方检查救回窗口要用的字段、`schemaVersion` 不超过自己认得的、偏好同名键的类型没变。
  只碰给定目录，偏好只读。改停车日志字段时要同步那里的样例。
- **`--stage`**：`main.swift`、`WindowShade.swift` 里没接齐更新器入口时打警告（不停下，别的验证也用 `--stage`），这样的包不能发布；
  接齐了就试跑 `--self-check`，5 秒内返回 0 且输出 `build=N`，否则停下。
- **接线位置**：`main.swift` 的 `UpdateLaunch.handleEarlyArguments()` 和 `UpdateLaunch.recordLaunch()`，
  `WindowShade.swift` 的 `start()`、`applicationShouldTerminate()`、`applicationWillTerminate()`，菜单、设置、欢迎窗口。
  前两处缺了就不能发布。

设计时的推理、验收清单、文案与出处仍在归档稿里，只作背景，不当作现行规则。
