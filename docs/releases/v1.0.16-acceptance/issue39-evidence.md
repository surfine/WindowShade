# #39 证据（按住 Option 双击不收起）

被测包：0-B 候选（`.build/release-acceptance-20261012/WindowShade-v1.0.16.zip`，sha256 `47930319…7876f`；来宾二进制 `784ec4b6…0eed4`，Team FVGLY6W6S4，1.0.16(16)）。隔离 VM 内 Computer Use 代跑，原始 PNG/AX/事件/hash 在 QA 盘 `evidence/computer-use-qa/20261012T184702-190877c0`。

| 判据 | 结果 | 证据 |
|---|---|---|
| 普通双击标题栏 → 收起（回归） | pass：正文消失、原位出现卷帘条；journal `id=379 stage=folded hide=hidden` | 本目录 `plain-double-click-folds.png`；run `…190877c0` events b1/b2 |
| **按住 Option 双击 → 不收起**（#39 主判据） | pass：journal 对 `id=379` **零新条目**；窗口未被收起；点击按预期交回系统（系统把窗口缩放铺满，正是修饰键放行的可观察形态） | 本目录 `option-double-click-does-not-fold.png`；events c3–c6（参数 `modifier:["option"]` + `delivery_mode:"foreground"`） |
| 设置行新文案 | pass：卷帘页「双击标题栏收起窗口」副标题＝"三击标题栏会缩放窗口；按住 Option 双击不收起"（截断 + ⓘ 全句） | `settings-line-new-subtitle.png`；中文逐字符核对在 `tests/check-localizable.py` 规则 3 |
| 纯测试 | pass：`TitlebarModifierSkipTests`（修饰键四键放行、无修饰键不放行、噪声位不误判、pending 清理语义） | `titlebar-skip-tests.log`（`tests/run-titlebar-skip-tests.sh`） |
| 编译 | pass：`prototype/build.sh --check` EXIT=0（514 文件、500 键、隐私登记、文案检查） | `/tmp/issue39-build-check.log`（会话内跑，结论已入交接） |

## 未覆盖（如实）

- **蓝牙鼠标三击收不到**（#39 报告的另一半）：属设备不向系统报告连续点击，App 内无法代修；"三击跟着系统动作走"的分支已存在（`handleTitleBarTripleClick`），未在真机蓝牙设备上复验。
- 修饰键组合的实际手感（⌥ 双击后系统缩放）只在 VM 合成输入下观察，未在真机鼠标上体验。
- 两文档同时存在时折叠的可见形态：见 [gate-0B-verification.md](gate-0B-verification.md) 勘误 1（inconclusive，已列入用户真机清单）。

## 实现位置（供复核）

- `prototype/App/EventTapCallback.swift`：tap 线程读到 ⌥/⌘/⇧/⌃ 任一修饰键即放行（不吞、不折叠、不建三击 pending），并异步清掉未完成的三击意图。
- `prototype/App/EventTap.swift`：`clearPendingTitlebarTripleClickForModifierSkip()`——防「普通双击 → ⌥ 第三击（放行）→ 普通第四击」被误配成三击。
- `prototype/App/Preferences.swift` + `Localizable.xcstrings`：三种系统双击动作分支的副标题各追加修饰键出口。
- `docs/copy-guide.md`：第二批英文表加行（hold Option to skip）。
- `tests/TitlebarModifierSkipTests.swift` + `tests/run-titlebar-skip-tests.sh`（新）。
- `tools/design-qa/check-settings-shade-language-preview.py`：逐条记录「副标题被替换」的有意豁免（旧句→新句映射，其余 missing 仍失败）。
