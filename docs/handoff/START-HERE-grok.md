# Grok 开工：WindowShade 2 的剩余工作

把“总则”和下面**一个**工作包整段交给 Grok 4.7。一次一个包，按“开工顺序”走。
每个包交回后，由主模型（Claude Opus 5.5）按文末“复核清单”看差异、复现检查；复核通过才合入、才给下一个包。

现状以 [FINAL-HANDOFF.md](FINAL-HANDOFF.md) 和 [round2-part10/REVIEW-HANDOFF.md](round2-part10/REVIEW-HANDOFF.md) 为准：
W00 的编译门槛已在 `main` 达成（`build.sh --check` 退出 0，严格并发参数没撤），但新二进制没签名、没上真机。
第一波纯逻辑包都在 `prototype/Core/`，大部分**还没接进 App**；这正是本轮要做的主体。

---

## 总则（每次都贴）

你在 WindowShade 仓库（`/Users/aaron/Documents/WindowShade`）里工作。WindowShade 是 macOS 窗口工具，
Swift 6 + AppKit，直接用 `swiftc` 编译，没有 Xcode 工程。我们在做 **WindowShade 2**：
**一个入口（刘海），一套动作，任何输入都能用。**

### 动手前必须读

1. `AGENTS.md`；
2. `docs/handoff/FINAL-HANDOFF.md`（第十份的裁决与边界，覆盖旧派工顺序）；
3. `docs/blueprint.md`：总图、刘海仲裁顺序、十二条硬要求；
4. `docs/copy-guide.md`（第 7 条“一个符号能说清，就不写一句话”、固定词汇表）和 `docs/design-system.md` §4.11 符号表；
5. 你这个包点名的工单（`tests/part10/workorders/Wxx-*.md`）和旧规格（`docs/handoff/deepseek-*.md`）。两者冲突时以工单为准。

### 分支与提交

- 从最新 `main` 拉一个分支：`grok/<包编号>`（例如 `grok/G2-input`）。**只在这个分支上改。**
- 可以在自己的分支上做本地提交（中文提交信息，一个提交一件可核查的事）。
- **不碰 `main`，不合并，不推送，不改 `git config`，不删文件，不改写已有提交历史。**合入由主模型做。
- 工作区里如果有你没做的改动，先停下报告，不要覆盖。

### 怎么做才对

- **接已有的，不另起炉灶。**纯逻辑已经在 `prototype/Core/` 里（`SmoothScroll`、`MiddleDrag`、`TouchTap`、
  `FocusNavigator`、`SiriRemoteButtons`、`RemoteMode`、`PresenceLock`、`DeviceBattery`……），共享类型只用 `WS2` 命名空间里的。
  不要再写第二个同名管理器、第二套 Journal、第二个活动仲裁器（刘海只有 `NotchLeaseHub` 一个）。
- **奥卡姆剃刀。**规格里没写的不做。要加任何设置项、菜单项、窗口、面板，先停下问。
- **不新建窗口或浮层。**新东西长在已有的刘海面板、活动协调器、设置窗口里。菜单一级不超过 12 项。
- **默认不接管。**会拦截或改写系统输入的功能全部默认关；打开才装钩子，回调 O(1)，被系统停掉时退回原样。
- **符号优先，字少。**设置行 = 一个 SF Symbol + 名字，副标题一行以内；刘海里“符号 + 不超过 8 个字”。符号名只用 §4.11 表里有的。
- **未知就是未知。**拿不到的系统事实写“未知”，不改成 `false`/`0`，不用空闭包、恒 `true`、新造 UUID 填平。

### Swift 6 严格并发（这里最容易出事）

`build.sh` 对四条编译命令都加了 `-swift-version 6 -strict-concurrency=complete -warnings-as-errors`。**不许撤，不许绕。**

- **禁止** `@preconcurrency import`（实测它会让错误整个消失，等于关检查）。
- `@unchecked Sendable`、`nonisolated(unsafe)`、`@retroactive` 只在确有锁/串行队列/只读保证时用，**每一处写一行中文理由注释**，说清靠什么保证。
  不许为了过编译成批加。系统类型的担保只加在 `prototype/Support/SendableSystemHandles.swift`。
- 只在主线程用的类标 `@MainActor`；后台队列里要调的纯查询方法标 `nonisolated`；跨队列回主线程的回调类型写成 `@MainActor (…) -> Void`。
- `MainActor.assumeIsolated` 只用在你能指出“这个回调一定在主线程进来”的入口（例如挂在主 run loop 上的 Timer/display link），并在交付报告里列出每一处和依据。
- 部署目标是 macOS 14，用不了 `isolated deinit`。

### 绝对不做

- 不签名、不跑不带 `--check` 的构建、不碰 `/Applications`、不退出或替换正在运行的 WindowShade、不改更新源、不发布。
- 不在真实窗口、真实设备、真实账号上做试验（那是 W01 的事，要 Aaron 指定可以动的窗口）。需要真机的写“需要真机”。
- 不碰登录密码、Touch ID、授权账（`AuthorizationLedger`）、私钥、Keychain 身份，不改批准策略、不把只读会话改成可执行。
- 不调用 `CGEvent` 合成键盘或鼠标，除非包里明确要求。
- 不在真实 home 目录改用户配置；测试用临时目录。
- 不拷 GPL、CC BY-NC、PolyForm、MMF License、没有许可证的代码；MIT 代码可用，文件头写明来源和版权。
- 不假装成功：没跑的写没跑；不为让测试过而放宽断言；不用 `// TODO` 冒充实现；同一失败改两次证据没变，就停下交最小复现。

### 检查（每个包都要跑，原样贴末尾输出）

```sh
cd /Users/aaron/Documents/WindowShade
export CLANG_MODULE_CACHE_PATH=/private/tmp/ws2-clang-cache SWIFT_MODULECACHE_PATH=/private/tmp/ws2-swift-cache

# 1. 整 App 编译（约 8–10 分钟，要等它跑完；成功的最后一行是“==> 编译验证通过”）
(cd prototype && ./build.sh --check)

# 2. 九套回归，每次用全新报告目录（runner 拒绝覆盖）
R="$(mktemp -d /private/tmp/ws2-grok.XXXXXX)"
for s in window-core frame foundation native duo input flow legacy-foundation legacy-process; do
  python3 -B tests/part10/tools/run-final.py --candidate . --handoff tests --suite "$s" --report "$R/$s" > "$R/$s.log" 2>&1
  echo "$s exit=$?"
done

# 3. AppKit 测试（含 WindowFoldEffectsTests）
bash tests/run-appkit-tests.sh all

# 4. 漂移门禁；它会改写 tests/part10/validation/ 下的 JSON，跑完必须还原
python3 -B tests/part10/tests/test-handoff-tools.py --candidate .
git checkout -- tests/part10/validation/
```

- 纯逻辑放 `prototype/Core/`，只依赖 Foundation，时间由调用方传入；测试照 `tests/ConductorGestureTests.swift` 的写法，配一个 `tests/run-xxx-tests.sh`。测行为，不复述实现。
- 漂移门禁报 `unlisted drift: <路径>`，说明你改了第十份 code-map 记录过的文件：把路径加进 `tests/part10/drift.json` 的 `code_map_drift`，
  并在 `tests/part10/DRIFT.md` 写一句改了什么、为什么。**不许改 code-map 的哈希去凑。**
- 已有测试不能变红。用 zsh 时注意：带空格的参数串不会自动拆开，写成逐条命令。

### 交付报告（照这个格式）

```text
分支与提交：（分支名、每个提交的哈希和一句话）
做了什么：（一段话）
改了哪些文件：（列表；新建的单独标出）
入口到效果的调用链：（从用户操作/系统回调到最终状态，逐跳写文件:符号；以及关闭/撤销路径）
并发标注：（每一处 @MainActor 类级标注、@unchecked Sendable、nonisolated(unsafe)、assumeIsolated、@preconcurrency 遵循，各附理由）
跑了什么检查、结果：（四项检查的命令 + 退出码 + 末尾输出，原样贴）
规格里哪几行已覆盖、哪几行没覆盖：（逐行对照工单/旧规格）
新读写的数据：（存哪、谁能读、怎么清；没有就写没有）
需要真机 / 主模型决定的：（列表）
```

---

## 开工顺序

| 顺序 | 包 | 内容 | 对应工单 / 旧规格 | 复核重点 |
| --- | --- | --- | --- | --- |
| 1 | G1 | 菜单收拢、设置符号优先 | W06 菜单部分；`deepseek-menu-agents.md` M1、`deepseek-pomodoro-symbols.md` S1 | 每个旧入口都还找得到；文案 |
| 2 | G2 | 输入纯逻辑接进 App（默认全关） | W05；`deepseek-input.md` I1、I3、I5、I7、I9 | 钩子开关、回调成本、被停掉时回退 |
| 3 | G3 | 指挥页面接真实状态与动作 | W05 指挥部分；`deepseek-conductor.md` D3、D4 | 索引转稳定 ID、草稿、无越权动作 |
| 4 | G4 | 慢 AX 治理 | W03 | 并发、限流、过期结果 |
| 5 | G5 | 电量与实时活动的来源接入 | W06 | 每个来源的真实事实、四态 |
| 6 | G6 | 隐私盘点（只盘点，不迁移） | W10 前半 | 漏登的读写 |
| 7 | G7 | 剩余主线程隔离警告清理 | W00 收尾 | 不改行为、不成批逃逸 |
| 随时 | G8 | 概念片工程 | W11 影片部分；`deepseek-film.md` FILM-F1–F5 | 不碰 App |

**不交给 Grok，由主模型做**（遇到就停下，写进“需要主模型决定”）。
2026-10-04 已裁决的项见 [`MAIN-MODEL-DECISIONS-2026-10-04.md`](MAIN-MODEL-DECISIONS-2026-10-04.md)（含第二轮 D13–D24），按那份执行，不要再问同一题。
仍由主模型亲手做、Grok 只交缺口的：W01 真机（窗口仅 TextEdit）；W02 端口设计复核；W04 授权策略与系统认证；W07 真配对；W08/W09 探针结论；任何发布。
下一包可做 **G8**（只动 `film/ws2-concept`）。G2→G7 合入由主模型抽查后本地做。
已定：指挥页可进租约表但只读／改草稿（D15）；模型槽位先不套用（D16）；枚举进同一 AX 闸门（D18）；新 journal 不写标题（D21）；漏登全补（D22）；G7 能证明线程的继续清（D23）。

---

## G1：菜单收拢、设置符号优先

读：`docs/handoff/deepseek-menu-agents.md` 的 M1、`docs/handoff/deepseek-pomodoro-symbols.md` 的 S1、W06 的“活动与菜单”。
改：`prototype/App/MenuBarController.swift` 及菜单构造相关文件；设置窗口里各行的符号与文案。

- 菜单一级收到 M1 规定的项数（不超过 12），收掉的功能必须仍能从二级菜单、Option 菜单、快捷键或设置里到达。
  交一张“旧入口 → 新位置”对照表，一项不漏（包括 Option 菜单和快捷键）。
- 设置行改成“符号 + 名字 + 至多一行副标题”。只改文案和图标，不改行为、不增删设置项。
- 所有新文案照 copy-guide 自检，用词表里的固定名字。
- 需要截图验收的写“需要主模型看截图”；不要自己启动 App 去点。

## G2：输入纯逻辑接进 App（默认全关）

读：W05、`docs/handoff/deepseek-input.md`（I1、I3、I5、I7、I9 各节）、`prototype/Core/` 里对应的纯逻辑和测试。

- 把已有纯逻辑接到 App：平滑滚动、中键拖、多指轻点、Siri 遥控器按键、遥控模式、焦点导航。**不重写 Core 里的逻辑**；需要改它，先停下说明。
- 每项一个开关，默认关；关着时不装任何钩子（事件 tap、HID 监听都不创建）。打开才装，回调 O(1)，被系统停掉时退回原样，并在设置里显示状态。
- 设置项按 I7 规定，不多加。
- 多触点用到的私有 MultitouchSupport ABI：**不要自己猜结构体布局**。只接主模型已核对过的部分；没核对的，留开关灰掉并在报告里列出。
- I4（中键接标题栏）、I6（遥控器麦克风）不做。
- 必测：开关反复开关不泄漏钩子；钩子被系统停掉后能检测到并退回；关闭状态下零回调。设备行为写“需要真机”。

## G3：指挥页面接真实状态与动作

读：W05 的“接状态，不再做展示样板”、`docs/handoff/deepseek-conductor.md` 的 D3、D4，
现有 `App/WS2ConductorView.swift`、`App/WS2AppRuntime.swift`、`Core/ConductorSession.swift`、`Core/AgentSessions.swift`。

- 指挥页从“展示样板”改成读真实的会话快照；页面里的数组下标在拿到快照时立刻换成稳定的会话 ID 和 revision，执行动作前再核一次。
- 草稿发送时固定当时的文字、模型和 effort；输入法还有未确认的文字时拒绝发送，保留草稿。
- 只接**不需要批准**的动作（切换会话、改模型/effort、写草稿）。任何会执行命令、改文件、联网的动作都不接，留给 W04。
- 复用手柄选模型页已有的 host、lease 和一次性激活，不重写它的 bridge。
- A5（会话与指挥模式合流）的状态设计由主模型定；你遇到需要合流的地方，停下写清楚。

## G4：慢 AX 治理

读：W03 全文、`App/Reconcile.swift`、`Window/AppWindows.swift`、`Window/AXHelpers.swift`、第九份 `MAC-EVIDENCE.md` 里的慢 AX 记录。

- 按 W03：每个 App 同一时刻最多一个在途 AX 读取，全局默认最多 4 个，各 App 轮转；同一 App 没回不重发；
  超时只让结果作废，不宣称调用被取消；一个 App 卡死不拖住别的 App 的结果呈现。
- 回调只更新它自己那次的结果，旧结果不能清掉新状态（沿用已有的代次/stamp，不另造）。
- 不做进程隔离（那要主模型审 IPC）。
- 用纯逻辑把调度规则测住（时间由调用方传入）；真实慢 App 的表现写“需要真机”。

## G5：电量与实时活动的来源接入

读：W06 全文、`Core/DeviceBattery.swift`、`App/DeviceBatteryController.swift`、`App/PeripheralBatterySource.swift`、`Core/NotchActivities.swift`。

- 只接**真实有来源**的设备与组件；每个来源标明它给的是什么事实、多久更新一次、能不能读到。
  每行都要有四态：已连接、断连、陈旧、无数据。没有设备时保持“未知”，不显示假数值。
- 播放、隔空投送、路线、录音等活动只更新同一个活动协调器；正在进行的交互优先，普通更新不能关掉上层页面。
- 锁屏时清掉刘海里可见的敏感内容，解锁后重读当前事实，不补播过期提醒。
- 不把“电量”和“能耗”混为一谈。交一张“来源 → 已接/未接/需要真机”的表。

## G6：隐私盘点（只盘点，不迁移）

读：W10、`docs/handoff/round2-part9/privacy-signals.json`、`docs/handoff/round2-part8/privacy-delta.json`。

- 逐个列出 App 实际的持久读写：UserDefaults 键、文件路径、Keychain 项、日志渠道、恢复日志里的窗口标题。每项写：谁写、谁读、存多久、怎么清、有没有登记。
- 只交盘点表和漏登清单，**不删数据、不改格式、不做迁移**：恢复日志与偏好副本的迁移方案由主模型定。

## G7：剩余主线程隔离警告清理

读：`docs/handoff/round2-part10/evidence/w00-remaining-warnings.txt`（`-warnings-as-errors` 升不上去的 204 处）。

- 目标是让这些警告消失，**行为不变**。按文件分批，一批一个提交；每批跑一遍 `build.sh --check` 和受影响的测试。
- 方法同总则的并发规则。优先把调用方放进正确的隔离域，而不是给被调用方加逃逸。
- 每批在报告里写：清了多少处、用了哪几种写法、新增了哪些执行期线程检查（这些是真机上可能崩的点，主模型要逐个看）。
- 交回时重新生成警告清单，贴新的去重计数。

## G8：概念片工程（不碰 App）

读：`docs/handoff/deepseek-film.md`、W11 的“影片”、`docs/design-drafts/README.md`。工程在 `film/ws2-concept/`。

- 只做 Remotion 工程里的分镜、动画和横竖版布局；需要真机画面的地方留占位，标明要录什么。
- 录真机、配声音、正式渲染、验收观感由主模型做。

---

## 复核清单（主模型用）

每个包交回后，主模型按这张清单复核，不只读总结：

1. **看分支：**`git log main..grok/<包>`、`git diff main...grok/<包> --stat`；确认没碰 `main`、没删文件、没改清单外的文件。
2. **复现四项检查：**用全新报告目录自己跑一遍，对比交付报告里贴的输出。
3. **攻击并发标注：**
   - `git diff main...grok/<包> | grep -E '^\+.*(nonisolated\(unsafe\)|@unchecked Sendable|@retroactive|@preconcurrency|assumeIsolated|@MainActor)'`，逐处核对理由是否成立；
   - 有没有 `@preconcurrency import`，有就直接退回。
4. **查假实现：**
   - 空闭包、恒 `true`、把未知写成 `false`/`0`、`// TODO`；
   - 被放宽的断言：`git diff main...grok/<包> -- tests/`。
5. **查默认值：**新开关是否默认关；关着时是否完全不装钩子。
6. **查文案：**新增的用户可见字符串逐条对 copy-guide 和词汇表。
7. **查漂移登记：**`drift.json` / `DRIFT.md` 里新增的条目理由是否真实。
8. **决定：**通过就由主模型在本地合入 `main`；不通过就把具体问题写回给 Grok，同一个分支继续改。
