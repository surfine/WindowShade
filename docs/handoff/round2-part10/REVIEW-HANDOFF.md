# 第十份并入后的复核交接

写给接下来要复核这件事的模型。目标不是重复包里的说明，而是把**现在的真实状态、我自己跑出来的证据、
我做的偏离，以及最值得你去攻击的地方**放在一张纸上。包里第十份带来的通用复核提示在
`docs/handoff/FINAL-HANDOFF.md` 末尾，那份讲原则；这一份讲这台机器上的具体事实。

## 复核之后的最新状态（分支 `w00-swift6-strict`，先读这一节）

**W00 的编译门槛已在分支上达成：`prototype/build.sh --check` 退出 0（「编译验证通过」），四条编译命令的
`-swift-version 6 -strict-concurrency=complete -warnings-as-errors` 一条没撤。** 没有并回 `main`，没推送，
没签名、没跑普通构建（普通构建要签名，未授权），没在真机上运行过新二进制。

本机复跑（每次全新报告目录）：九套 run-final 套件全部退出 0；`tests/run-appkit-tests.sh all` 退出 0
（含 `WindowFoldEffectsTests`）；`tests/part10/tests/test-handoff-tools.py` 16/16。

**原先说的 98 处只是第一批。** region isolation（跨线程传值是否安全）要等类型检查全部通过才跑，
98 处清零后又冒出 420 处。最后的收法，按用到的次数：

| 写法 | 新增处数 | 用在哪 |
| --- | --- | --- |
| `@MainActor`（类、方法、闭包类型） | 82 | `AppDelegate`、各控制器、探针、只在主线程跑的回调类型 |
| `nonisolated(unsafe)` | 28 | 可变全局量、deinit 里要兜底清理的观察者和时钟、两处只读跨线程的值 |
| `@unchecked Sendable` | 23 | 靠锁或串行队列保护的类（捕获、传感器、缓存）和系统句柄 |
| `@retroactive`（系统类型担保） | 8 | `AXUIElement`、`CFMachPort`、ScreenCaptureKit 的快照、过滤器和 `SCStream`，集中在 `prototype/Support/SendableSystemHandles.swift` |
| `@preconcurrency` 遵循 | 12 | 协议本身不隔离、遵循方是主线程类型；执行期会检查线程 |
| 新增 `MainActor.assumeIsolated` | 14 | 已知在主线程的回调入口 |

每一处都写了理由注释；**没有任何 `@preconcurrency import`**（实测它会让错误整个消失，等于关检查）。

**最该攻击的风险：** 把 `AppDelegate`、`PinnedPreviewController`、`DockHoverObserver`、
`WindowBrowserThumbnailBackend` 等标成主线程隔离，加上 `@preconcurrency` 遵循和 `assumeIsolated`，
等于在系统回调入口加了执行期线程检查。哪个回调其实从后台线程进来，App 会直接崩溃，而不是像以前那样
悄悄跑下去。测试里没碰到，但没在真机上跑过，这一点是**未知**。

**剩下的债：** 有一类主线程隔离警告 `-warnings-as-errors` 升不上去（AppKit 的 @preconcurrency 降级诊断），
现在还有 204 处（去重后，最初约 1732 条输出），清单在 `evidence/w00-remaining-warnings.txt`。
主要是 `ActorIsolatedCall` 和 `SendableClosureCaptures`。

**复核议程的结论（七条）：**

1. W00：如上，分支上已收；要不要并回 `main` 等用户定。
2. `build.sh` 是收紧：普通构建仍按「环境变量 → `local-codesign.env`」读签名，只有 `--check` 跳过签名。
3. `Journal.journalID` 与 overlay 一致；另发现 JSON 里的 `1.0` 会被当成窗口 1，没改，记在这里。
4. 漂移清单：本轮改动没被掩盖，但交接提交漏登过 `AGENTS.md`（已补，现共 26 条）。漂移里藏着更早的放宽，
   不是本轮改的：`CodexWire` 初始化期间接受任何不带 id 的通知；`WS2Child.c` 把 EPERM 当成组已空（**已修**，
   见下）；`WS2LocalLaunchProfile` 沿用 App 自己的 PATH，从 Finder 启动可能无效，未经真机验证。
5. 第九份那 23 处 `MainActor.assumeIsolated`：抽查的都在主线程，没逐处证明。
6. `WindowFoldEffectsTests` 的原有断言都在，本机实跑通过，没改软。
7. 三个 part10 适配脚本：负面案例仍被拒绝，没有改成静默通过。

**复核时顺手修的四件（用户批准）：** 漂移清单补登 `AGENTS.md`；`WS2IslandCoordinator` 的理由改成
「本仓库沿用 `NotchLeaseHub`，不为 W08 新建」并在 W08 工单注明；`WS2Child.c` 遇 EPERM 时先用
`proc_listpids(PROC_PGRP_ONLY)` 确认组里只剩已退出的组长才当作已空（实测 macOS 此时确实回 EPERM）；
测试脚本编 C 文件时补上 `-mmacosx-version-min=14.0`。

## 一句话结论（合并当时的状态，已过时，留作对照）

第九、十份都已并入 `main`（本轮提交 `4f276ea`，其上还有第九份的 `af0437c`、`38bb231`；本地提交、
没推送）。**第十份的构建口径改动让整 App 在当前 SDK 下第一次真编译，结果编译不过：98 处诊断。**
这不是合并事故，是第十份把 `-swift-version 6 -strict-concurrency=complete -warnings-as-errors`
一次性打给四条编译命令后必然暴露的存量问题——第十份自己的 VALIDATION 也写明「Mac 整应用未执行」。
所以 W00 没有完成，`main` 现在不产出可运行二进制。复核的第一件事就是判断这条线该怎么收。

## 你接手的东西

| | |
| --- | --- |
| 仓库 | `/Users/aaron/Documents/WindowShade`，分支 `main`，工作区干净 |
| 本轮提交 | `4f276ea 合并第十份：构建口径收紧，恢复日志编号按精确类型解析` |
| 上一轮 | `af0437c`（第九份合并）、`38bb231`（第九份台账） |
| 第十份原件归档 | `docs/handoff/chatgpt-review-2/part10/`（整包） |
| 第十份仓库 runner | `tests/part10/{tools,tests,workorders,docs,execution-plan.json,sources,drift.json,DRIFT.md}` |
| 本轮证据 | `docs/handoff/round2-part10/evidence/` |
| 第九份证据 | `docs/handoff/chatgpt-review-2/part9/MAC-EVIDENCE.md` |

环境（`evidence/toolchain.txt`）：macOS 27.0（26A428）、Xcode 27.0（27A266a）、Swift 6.4
（swiftlang-6.4.0.34.1）、arm64；Sparkle 2.10.0，二进制 sha256 `a4b35bf3…c6008`。

## 我实际跑了什么

| 命令 | 结果 | 证据 |
| --- | --- | --- |
| `python3 tests/part10/tests/test-journal-id.py --candidate . --baseline docs/handoff/chatgpt-review-2/part10/base-sources` | 25/25；旧实现在 NaN 与 2^32 上真的触发陷阱（exit −5），`true`/`1.5` 被当成窗口 1 | `tests/part10/validation/journal-id-tests.json` |
| `python3 tests/part10/tests/test-build-entry.py --candidate .` | 12/12（替身工具链跑真实 shell 控制流，不是 Mac 编译） | `tests/part10/validation/build-entry-tests.json` |
| `python3 tests/part10/tests/test-handoff-tools.py --candidate .` | 16/16（含漂移清单门禁，见下） | `tests/part10/validation/handoff-tool-tests.json` |
| `python3 tests/part10/tests/test-stage.py` | 18/18 | `tests/part10/validation/tools-tests.json` |
| `tests/part10/tools/run-final.py`：window-core / frame / foundation / native / duo / input / flow / legacy-foundation / legacy-process | **九套全 PASSED**（exit 0） | `evidence/run-final-results.txt` |
| `tests/part10/tools/run-final.py --suite mac-build`（隔离副本、真 SDK、真 Sparkle） | **FAILED，exit 1**；`build.sh --check` 报 98 处 | `evidence/mac-build-result.json`、`evidence/swift6-strict-errors.txt` |

第一个有意义的错误（按第十份要求单列）：

```
App/DockClickHide.swift:88:59: error: reference to captured var 'spaces' in concurrently-executing code [#SendableClosureCaptures]
```

## 98 处诊断的分类

完整逐条清单在 `evidence/swift6-strict-errors.txt`。按诊断类别：

| 类别 | 数量 | 主要文件 | 处理方向（我的判断，需你确认） |
| --- | --- | --- | --- |
| `AddPreconcurrencyImport` | 22 | HabitContext、Notch、TrackpadGestures、ShadeController、WindowShade、WindowBrowser/*、Window/* 等 | 编译器给的 fix-it：对 ApplicationServices / CoreFoundation / ObjectiveC 的 import 加 `@preconcurrency`。**要先验证**在 `-warnings-as-errors` 下它是否真的把这类错误降级；若仍然致命，就得逐个改成显式隔离，不能靠抑制。 |
| `MutableGlobalVariable` | 16 | GlobalShortcuts、PreviewRenderer、WindowSnapshotCache、EffectEnvironment、PaperSurfaceStyle、ShadeStripPool、SkyLightBridge、Diagnostics、ChromeProfile、WindowListCache、WindowRegistry、WindowBrowserGeometry/NewWindow、WindowShade | 非隔离的可变全局状态。**必须逐个判断**：真正只在主线程用的标 `@MainActor`（会级联，第九份刚被这个坑过），确属线程安全自管的才 `nonisolated(unsafe)` 并写明理由。 |
| `ConformanceIsolation` | 9 | WindowBrowserCardView、ContentView、ListRowView、Material、SelectionDetailView、WindowPlacement | AppKit 视图/几何类型对 `Sendable` 的隐式 conformance 在新隔离规则下不成立；改为显式 `@MainActor` 隔离而不是伪造 conformance。 |
| `ImplicitStrongCapture` | 7 | NotchWatch、EffectSoakProbe、WindowPlacement | `[weak self]` 与隐式强捕获混用。属**警告升级**为错误；改捕获列表即可，注意别把本该强的引用改弱。 |
| `NoUsage` | 6 | EventTap:183/621、GestureProbe、NotchShelf、Preferences、AXHelpers | `MainActor.assumeIsolated { 有返回值的表达式 }` 丢掉了结果。属警告升级；其中 **EventTap:621 是第九份我自己加的**，需要 `_ =` 或让闭包返回 Void。 |
| `DeprecatedDeclaration` | 4 | UpdaterSystem（SMJobCopyDictionary/Remove/Submit、`init(cString:)`） | 警告升级。属于既有 API 选择，改动要另立工单，别在 W00 里顺手换行为。 |
| `SendableClosureCaptures` | 2 | DockClickHide、WindowBrowserMetadataQueue | 真并发语义问题：闭包捕获了并发执行的 `var`。修法要保证值语义或隔离，不能只加 `@Sendable`。 |
| `NonSendableExitingActor` | 2 | ShareableContentCache | `SCShareableContent` 非 Sendable 却跨隔离边界；需要重新设计缓存的所有权，不是加注解能了事。 |
| `UnnecessaryEffectMarker` | 1 | FaceObservationSource | 警告升级，去掉多余 `try?`/`try`。 |
| 其它（未带类别码） | 29 | 见清单，含 ShareableContentCache 的 SCShareableContent 族（9）、TrackpadGestures 的 `enabledDefaultsKey` 主线程静态属性、Thumbnail/PaperSurfaceStyle 对 `alphaValue`/`level` 的 key path、Welcome 的 `@MainActor` 函数值转换等 | 逐个看，多数是「主线程事实没写出来」。 |

> 判断关键：其中约 20 处（NoUsage / ImplicitStrongCapture / Deprecated / UnnecessaryEffectMarker）是
> **既有 warning 被升格**，不是新发现的并发问题；另外约 70 处才是 Swift 6 语言模式真正新暴露的。
> 别把两类混在一起当成同一件事汇报。

## 复核议程（按优先级）

1. **决定 W00 怎么收。** 三条路：(a) 按上面逐类修到 `build.sh --check` 退出 0，再谈 W01；
   (b) 暂时把 `SWIFT_LANGUAGE_FLAGS` 从四条命令退回，保持 `main` 可构建，把迁移单列；
   (c) 保留参数但在 CI/文档里明确「main 当前不可构建」。第十份明确写了「不能为得到绿色输出撤销这些参数」，
   所以我倾向 (a)，但这是需要你（或用户）拍板的范围问题，不是我该默默替你决定的。
2. **`build.sh`：确认我的两处改动都是收紧而不是放宽。**
   第 43 行附近把 `SPARKLE_FLAGS[@]` 的展开改成 `${arr[@]+"${arr[@]}"}`；四条 swiftc 新增 `SWIFT_LANGUAGE_FLAGS`。
   验证方法：`python3 tests/part10/tests/test-build-entry.py --candidate .`（12/12 覆盖了 `--check` 不读
   `local-codesign.env`、四条命令参数一致、失败传播、临时源文件回收）。请特别看**普通（非 --check）构建**
   的签名读取顺序有没有被我改动——没有，但值得你独立确认。
3. **`Journal.journalID` 的语义边界。** 跑上面的 journal-id 测试并读 `prototype/Recovery/Journal.swift` 41–52 行。
   要确认的是：合法 1…`UInt32.max` 保持原义、`0` 返回 nil、布尔不当数字、小数/NaN/∞/超界返回 nil。
   第十份自己声明这只收紧编号一处，**pid、createdAt、spaceID、坐标、尺寸、alpha 都没动**——这条声明要当真，别把编号安全当成整个恢复文件已校验。
4. **`tests/part10/DRIFT.md` 与 `drift.json` 是否掩盖了未审改动。** 第十份的 `sources/code-map.json` 钉的是 v9 候选，
   本仓库比它新：21 条哈希/行数漂移、1 条路径搬迁（`App/InteractionCoordinator.swift` →
   `Core/InteractionCoordinator.swift`，内容逐字节相同）、1 条「应当不存在」（`App/WS2IslandCoordinator.swift`）。
   我把这份清单做成门禁：清单外的任何新漂移都会失败，清单本身也必须与实际情况完全一致。
   **请逐条打开 diff 核对**，尤其 `WS2AppRuntime.swift`、`WS2CodexApprovalHost.swift`、`Native/WS2Child.c`
   这些不是本轮改的、但和 v9 快照不同的文件。
5. **第九份那 23 处 `MainActor.assumeIsolated` 有没有真的不在主线程的调用点。**
   它们是运行时断言：不在主线程会直接 trap。清单在 `docs/handoff/chatgpt-review-2/part9/MAC-EVIDENCE.md`。
   最值得怀疑的几处：`Effects/WindowFoldEffects.swift` 的释放路径、`App/Reconcile.swift` 的两个批次回调、
   `App/FoldTransaction.swift` 的 schedule 回调。我核对过都来自主线程（含 WindowBrowserAppDelegate 自带的
   `dispatchPrecondition(condition: .onQueue(.main))`），但你是独立复核者。
6. **`tests/WindowFoldEffectsTests.swift` 的改写是否弱化了原断言。** 第九份删除了「只按窗口 ID 报成功」的
   API，我把测试宿主改成「先绑事务再按事务结算」，并把投递改到下一轮主队列 flush 对账；成功用例会装一份
   真实 `folded` 状态并把锁态固定成未锁屏。请确认它仍然覆盖原意（取消只结算一次、反向准备取消、交接保留完成、
   看门狗代次、可重入取消），而不是把断言改软。
7. **`tests/part10` 里我改过的三个脚本**：`tools/stage.py`（macOS `/var` 与 `resolve()`）、
   `tools/run-final.py`（报告路径的 `/var` 规范化、legacy 历史脚本接线、临时目录补 part7）、
   `tests/test-handoff-tools.py`（12/14 项读 `drift.json`）。这三个都是「让第十份的工具在本仓库能跑」的适配，
   请确认没有把失败路径改成静默通过——例如 `external_report` 仍然拒绝已存在目录、符号链接父目录、与输入重叠的路径。

## 我做的偏离（都写在这里，没有藏）

1. **主模型补的 build.sh 修复**：macOS 自带 bash 3.2 在 `set -u` 下展开空数组会致命，而且有 EXIT trap 时
   以 **0** 退出——缺 `Vendor/Sparkle.framework` 时 `--check` 会「什么都不编也返回成功」。这条是第十份的
   `test-build-entry.py` 在本机暴露出来的，改成 `${arr[@]+"${arr[@]}"}` 形式。**这是安全收紧，不是放宽。**
2. **`run-final.py` 的报告路径**：原实现拒绝任何含符号链接的路径，而 macOS 的 `/tmp`、`/var` 就是 Apple
   自己的根级链接，第十份文档推荐的 `mktemp -d /tmp/...` 会被它自己拒掉。按仓库既有做法只规范化
   `/var`、`/tmp`、`/etc` 三个前缀，其余任何一段是符号链接仍然拒绝。
3. **`code-map` 漂移门禁**：见复核议程第 4 条。原始 `code-map.json` 保持第十份的原样，没有改哈希去凑绿。
4. **AGENTS.md 顶部多了一行**指向 `docs/handoff/FINAL-HANDOFF.md`（第十份自带），其中包含
   「新工作只能在隔离分支或副本中进行；是否提交/推送另遵用户授权」。本轮是按用户明确要求把第十份并入
   `main` 并在本地提交、**没有推送**；这条口径与第十份文档的默认不同，如果你认为应当改到隔离分支，
   这是可以回退的一步。

## 明确没做（别以为做了）

- W00 的真实构建**没有修绿**（98 处未动）。
- W01 起的任何真实验收：原窗口收起/恢复、本地只读会话真机、手柄模型页真机、慢 AX、原生允许审批、
  指挥页面、电量/实时活动全入口、配对与接收、完整 CarPlay、系统锁与身份、隐私迁移、能耗、影片、签名发布。
- 第九份工单矩阵的**受控真机观察**（M01…M18）仍未做，需要用户先指定「允许动」的窗口。
- 任何提交以外的外部动作：没有推送、没有打标签、没有签名、没有发布、没有改更新源。

## 需要的用户决定

1. W00 走哪条路（修到绿 / 退回参数 / 保留但标注不可构建）。
2. 受控真机观察允许动哪些窗口（第九份债务，仍在等）。
3. 发布相关一律未授权：不签名、不打标签、不推 Release。

## 复现命令全集

```sh
cd /Users/aaron/Documents/WindowShade
export CLANG_MODULE_CACHE_PATH=/private/tmp/ws2-clang-cache SWIFT_MODULECACHE_PATH=/private/tmp/ws2-swift-cache

# 第十份自检
python3 -B tests/part10/tests/test-journal-id.py --candidate . --baseline docs/handoff/chatgpt-review-2/part10/base-sources
python3 -B tests/part10/tests/test-build-entry.py --candidate . --baseline docs/handoff/chatgpt-review-2/part10/base-sources
python3 -B tests/part10/tests/test-handoff-tools.py --candidate .
python3 -B tests/part10/tests/test-stage.py

# 九套现有套件（每次一个全新报告目录，runner 拒绝覆盖）
R="$(mktemp -d /private/tmp/ws2-final-evidence.XXXXXX)"
for s in window-core frame foundation native duo input flow legacy-foundation legacy-process; do
  python3 -B tests/part10/tools/run-final.py --candidate . --handoff tests --suite "$s" --report "$R/$s"
done

# 真实 Mac 构建（隔离副本 + 本机 Sparkle；当前应看到 FAILED 与 98 处诊断）
python3 -B tests/part10/tools/run-final.py --candidate . --handoff tests --suite mac-build --report "$R/mac-build"

# 直接看整 App 编译
cd prototype && ./build.sh --check
```
