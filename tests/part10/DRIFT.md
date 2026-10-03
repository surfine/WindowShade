# 本仓库相对第十份基线的漂移（逐条原因）

第十份的 `sources/code-map.json` 钉的是统一 v9 候选（1168 个文件）。本仓库是那条线继续往前走的
工作区：先并入第九份，再并入第十份，并在两轮里都按「只有 Mac 才会暴露」的事实改过源码。
所以 code-map 里有 21 条记录的哈希/行数与本仓库不同，另有两条不是「内容变了」而是**路径或存在性**不同。
`tests/part10/drift.json` 把这份清单机器可读化；`test-handoff-tools.py` 的 12/14 项按它判定：
清单外的任何新漂移都会让检查失败，清单本身也必须与实际情况一字不差（多一条少一条都算失败）。

## 路径/存在性不同的两条

| code-map 记录的路径 | 本仓库实际 | 原因 |
| --- | --- | --- |
| `prototype/App/InteractionCoordinator.swift` | `prototype/Core/InteractionCoordinator.swift` | 本仓库把共享仲裁放在 `Core/`（第七、八、九份的 runner 都已按这个事实处理）。两边**内容逐字节相同**，所以只改路径映射，不计入哈希漂移。 |
| `prototype/App/WS2IslandCoordinator.swift` | 不存在 | 单一刘海仲裁器是 `NotchLeaseHub`（`prototype/App/NotchLeases.swift`）。第九、十份都明确不新增第二套岛管理器，这个文件**应该**不存在；检查项把它当「必须缺席」来断言。 |

## 第九份带进来的改动

`prototype/App/FoldCompletion.swift`、`FoldTransaction.swift`、`Reconcile.swift`、`ShadeController.swift`、
`prototype/App/WS2FoldCallbackGuard.swift`（新增）——收起三态、事务绑定完成通知、巡检不可变快照、
AX routeID、首帧隔离、去嵌套 RunLoop；另有主模型按 Mac 实测修掉的 23 处 Swift 6 隔离错误。
证据在 `docs/handoff/chatgpt-review-2/part9/MAC-EVIDENCE.md`。

## 第十份自己的改动 + 主模型补的一处

`prototype/build.sh`、`prototype/Recovery/Journal.swift`（后者与 code-map 一致，未列入漂移）是第十份的实际修复
（四处 swiftc 显式 Swift 6/完整并发检查/警告视为错误、`--check` 不读本机签名配置；`journalID` 精确转换）。
主模型另在 `build.sh` 上补了一处**只有 macOS 才会暴露**的修复：macOS 自带 bash 3.2 在 `set -u` 下展开空数组
会致命，而且有 EXIT trap 时以 0 退出——缺 `Vendor/Sparkle.framework` 时 `--check` 会「什么都不编也返回成功」。
改成 `${arr[@]+"${arr[@]}"}` 形式。这正是第十份 `test-build-entry.py` 在本机暴露出来的。

## 更早几份在这条线上的继续演进

第十份钉的是 v9 候选的快照，本仓库在它之后还保留了第八份及更早的实际接线与修复，所以下面这些文件
哈希不同，内容都属于**已并入并验证过**的工作，不是未审改动：
`WS2AppRuntime.swift`、`WS2CodexApprovalHost.swift`、`WS2GameControllerBridge.swift`、
`WS2OwnedCodexSession+Authorization.swift`、`Core/CodexWire.swift`、`Core/PairingTLV.swift`、
`Native/WS2Child.c`、`Support/WS2DuplexProcess.swift`、`Support/WS2KeychainPeerStorage.swift`、
`Support/WS2LocalLaunchProfile.swift`。

## 文档更长

`docs/blueprint.md`、`docs/handoff/START-HERE-deepseek.md`、`docs/releases/v1.0.16-ledger.md`、
`docs/privacy-page.md` 都随每份接入追加了台账段落，行数比 v9 基线多。

## 复核者要做的判断

这份漂移清单只解释「为什么和 v9 不一样」，**不证明**这些差异都是对的。请逐条按实际 diff 核对：
第九份的三态/事务语义是否真的落地、第十份两处修复是否只是收紧、主模型补的 bash 修复是否不改变
正常构建的参数与签名策略。清单外若出现新的漂移，说明有人绕过了这两条门禁。
