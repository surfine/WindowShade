# 第28批：静音流程散句（英语适配第二批）

[当前身份与限制](validation.json) · [copy-guide 英文表](../../copy-guide.md) · [第27批](../2026-10-12-english-settings-shade/README.md) · [Continuous 记录](../CONTINUE.md)。

按交接 §9 建议顺序 ① 迁移的第二个英语表面：静音线 7 个文件的去重中文字面量 137 条全部出表——125 条直迁 `WS2SilentCopy.saying("id")`、9 条活动/用量读回复用既有 `lines` 表 id（`activity.*`/`usage.*`，无新键）、3 处插值并为 2 条 `saying2` 模板（第 %@ 列/页）；`sayings` 新增 127 条，`saying()` 调用点 230 处（另 `saying2()` 3 处），目录 373→**500 键**。中文输出逐字节不变（静音纯测试 2117 条断言全过，含直接断言这些中文句的约 120 条）；英文全链路实测生效。

## 机制（沿用第27批铺好的件）

- `WS2SilentCopy` 新增 `sayings` 表（127 条：状态词、结果句、读回短语、对话包装、超时句）与 `saying(_:)`/`saying2(_:_:)`（后者带一个 `%@`，用于"第 N 列/页"）。中文源句=稳定身份，键 `say.<id>`，进 `check-localizable.py` 规则 3（中文逐字核对）。
- 7 个文件调用点全部迁表：`WS2SilentGates`（结果行/读回 switch）、`WS2SilentHost`（note 对话、预览行、超时句、页面标题与芯片）、`WS2SilentApply`、`WS2SilentExecution`（`notchLine`、台账 waiting 行）、`WS2SilentSecurity`、`WS2SilentDraft`、`WS2SilentProductPort`。迁移后这 7 个文件的代码行**零中文残留**（身份表 `lines`/`sayings` 本身除外）。
- 无一处中文参与逻辑判定（迁移前专项核查：`==`/`switch` 携带中文字面量的 5 行全部是 `switch` 分支里的显示串或对 `notDone` 常量的比较，后者改为与 `WS2SilentCopy.saying("notDone")` 比较，语义不变）。
- 旧 `silent.*` 表里 6 条与 copy-guide 定案冲突的英文对齐（只改 en 值，中文身份不动）：Collapse window→Roll up、Expand window→Unroll、Take a look→Glance、Keep on top→Pin、Stop keeping on top→Unpin、Tuck into notch→Tuck into the notch（Magic Tile 值已一致）。

## §9.4 防漏网棘轮（新）

`tests/check-localizable.py` 新增全仓扫描：`prototype/` 内中文字符串字面量行数不得超过 `tests/localizable-ratchet.json` 冻结的基线（**3406**，本批完成后实测），只许降不许升。后续每迁一个表面调低一次。身份表（`WS2SilentCopy` 267 行）、QA 探针、权限名等占位数仍在其内，逐批甄别消化。

## 判据放宽（逐条，护栏要求）

- **copy-lint 主句 8 字形簇上限**：4 条迁入 `sayings` 的句子是改动前原文（逐字节，出处 `2003e53^` 的 Host/Gates，git diff 为证），不是新写文案；中文本批不许动，故在 `tests/copy-lint.py` 加 `LEGACY_SAYINGS` 明示豁免（`confirmVoid`/`unclear`/`nodOrClick`/`timeout.glance`），将来改写句子时收紧并删除。
- 门 3 实看发现：英文芯片 "Launchpad" 在 344pt 岛宽下轻微贴边——11pt 字号下的既有密度，非本批引入（zh "启动台" 同位同宽），记为观察项不记为失败。

## 证据

- **纯测试**：`run-silent-prep-tests.sh` **2117 ok / 0 FAIL**（含约 120 条直接断言这些中文句——zh 逐字节不变的回归网）；`run-localization-tests.sh` 52 ok（全目录 500 键逐键走 WSL10n 出英文、无汉字）；`check-localizable.py` 500 键 + 棘轮 3406 全过。
- **集成抽查**：`run-silent-integration-tests.sh --case r03`（5 ok：台账/结果行/回执；`native/integration-r03.log`）与 `--case r01`（12 ok：效果端口与完成判定；`native/integration-r01.log`）PASS，真编译产品源。
- **夹具**（新，轻量档）：`tools/design-qa/SilentPageLanguagePreview.swift` + `run-silent-page-language-preview.sh`——真 `WS2SilentPageView`/`IslandChip` 离屏渲染 4 帧（zh/en × 初始/结果句），Swift 6 strict 全生产源编译；帧数据（`native/frames.json`）：en 页 `Silent actions/Launchpad/Windows/Live activities/Usage/Settings/More/Remove cover/Confirm`、结果句 `Didn't happen`，无汉字。
- **门 3 图片实看**：4 张 PNG 全看（zh/en 初始 + en 结果句），版面无事故；"Launchpad" 贴边为既有密度（见放宽节）。
- **门 4**：`bash prototype/build.sh --check`（`native/build-check.log`）：500 键本地化检查、全优化编译、隐私登记、文案检查（含豁免 4 条记录）全过。

## 未覆盖 / 不成立的声明

- 没有真机刘海静音页、没有相机/口令/输入路径的真实触发；夹具是静态渲染，不证明交互与动效。
- `SilentMilestoneProbe`/`SilentCoverProbe`/`WindowBrowser*Probe` 等 QA 探针的中文字符串按 §9 类别②（非用户可见）未迁移，占棘轮位数。
- 隐私（`WS2PrivacyData` 605 行，生成文件——迁移点在生成器与 registry.json）、设置其余页、菜单/状态栏等 §9 剩余表面未开工；英语整体目标仍 active，不写"英语已支持"。
- 英文静音句的真机可读性（岛宽 344pt 下的换行/截断）未在真实设备验证。

## 门 5 收尾附记（2026-10-12 深夜，后继 session）

- [validation.json](validation.json)：binding 照第26/27批公式 `sha256(canonical_json({source_sha256, evidence_sha256}))`（sort_keys + 紧凑分隔符，复算第27批 `b332ab69a03e41c6` 对上后才套用）；本批 binding 覆盖 17 个源文件 + 16 个证据文件（evidence 表不含 validation.json 自身——第27批表内的自引用哈希是绑定时的草稿快照，属既有惯例，本批不沿用）。
- 复跑归档：`silent-prep-tests.log`（2117 ok / 0 FAIL）、`localization-tests.log`（52 ok）、`site-build.log`/`site-check.log`（42 项 exit 0，本地构建检查、**未部署**）——此前纯测试只有口头记录，按"/tmp 不过夜"护栏补留档。其余日志（build-check、fixture、integration r01/r03）批内已归档，未重跑、按原档引用。
- README 双份同步检查：第28批无新官网词条（静音句只出现在刘海/面板，官网与 README 未涉及），README 双版「开发中」小节在27批已加的「English interface」条目下不需逐批更新；判定依据：`grep sayings/silent copy` 与 `site/scripts/content.mjs` 无交集。
- `docs/copy-guide.md` 第二批英文表 10 行核对在档（Didn't happen/Waiting/Rolled up/…）。
- 全部改动未提交（未得指示不提交不推送）；本批不在 1.0.16 基线（82681b0）内，不阻塞发布。
