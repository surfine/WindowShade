# 第27批收尾：英语适配首批（设置外壳 + 卷帘页 + 高级页）两个卡点关闭

[当前身份与限制](validation.json) · [几何放宽记录](gate2-geometry-drift.md) · [交接与门禁](../../handoff/BATCH27-ENGLISH-HANDOFF-2026-10-12.md) · [第26批](../2026-10-11-fluid-retarget/README.md) · [Continuous 记录](../CONTINUE.md)。

本批交接的两个卡点在本 session 关闭：**卡点 A**（语言切换后设置窗口落到「效果」页）修了生产根因；**卡点 B**（滑杆行「0%」读数两种布局形态）以产品实测形态钉住夹具，生产行几何未动。切换测试 33 条全 PASS，消费者（10 帧 + zh 基线回归 + 519 输入零漂移）passed，全优化构建通过。英语整体目标仍 active——剩余表面见交接 §9，本文不声明"英语已支持"。

## 生产改动

| 文件 | 改动 |
|---|---|
| `prototype/Effects/DuoSettingsWindow.swift` | 卡点 A 根因修复：`refreshLocalizedCopy` 期间挂起侧栏选择事件（`isRebuildingLocalCopy` 哨兵）。`reloadData` 在 `allowsEmptySelection=false` 的 sourceList 上会同步把选中打回第 0 行并触发 `tableViewSelectionDidChange`，把 `currentSection` 拖去 `.effects`——诊断日志实测（`native/switch-tests-debug-run1.log`：`after reloadData selectedRow=0`，哨兵期间恢复为 5）。顺手两处漏网：侧栏 ax 标签「设置侧边栏」、工具栏「切换侧边栏」迁入目录（`settings.shell.sidebar.*`），且 ax 标签随语言重建（原来建表时设一次，reloadData 不更新）。 |
| `prototype/Resources/Localizable.xcstrings` | 目录 371→373 键（+`settings.shell.sidebar.label/toggle`）。 |
| `tools/privacy/registry.json` | 补登 `InterfaceLanguage.swift` 的 4 处 `UserDefaults` 字样（1 注释 + 3 函数注记，signal=settings，与既有同形条目一致）；门 4 首跑因此红过，登记后 PASS。 |

未动：`makeCollapseSettingsRow` 的行几何（见下）。

## 卡点 B 的处置（门 0：先读产品，再钉夹具）

1. **产品真实形态实测**：夹具新增 `product-zh-aqua-900-shade` 帧——真 `DuoSettingsWindow` + `select(section: .shade)`（走产品自己的 `allowHorizontalExpansion`），实测稳定落**形态 L**（控件自然宽 194pt 右对齐贴行右缘，读数无空洞）。观感正常，**不触发"修生产先看图"**（定案 4）。
2. **夹具对齐**：夹具原本绕过 `select()`，布局环境和产品不一致；复刻 `allowHorizontalExpansion`（`expandStacks`）后仍两形态漂（`native/probe-run3-pre-pin.txt`：同 run 内 light-696=C、dark-696=L），证明歧义在行约束本身（labels 与 sliderGroup 同为 defaultLow 时求解器环境敏感）。按交接 §4 方案 1 在夹具里把 labels 的 hugging 压一档（249<250，`pinShadeRowForm`），"谁被拉伸"有唯一解。
3. **稳定性**：连续两跑（run4/run5）四 zh 帧全部稳定形态 L、`group.w=194` 与产品一致（`native/probe-run4-pinned.txt`、`probe-run5-pinned.txt`）。

## 卡点 A 的修复与验收

- 加 `WS2_LANGUAGE_DEBUG` 诊断（交接 §3 的定位步骤一次完成）→ 修复（哨兵 + `select(section:)` 原有的选中行拨回）→ 删诊断 → 复跑 `run-appkit-tests.sh InterfaceLanguageSwitchTests`：**33 ok / 0 FAIL**（`native/switch-tests.log`）。
- 消费者对应检查自然转绿：`rebuild-en-advanced` 无汉字、英文锚点、语言弹窗项、zh 重建与初始一致。

## 证据

- **夹具**：`tools/design-qa/SettingsShadeLanguagePreview.swift` 新增产品真窗口帧（探针已按门 2 删除，输出留档 `native/probe-run*.txt`）。10 帧 PASS：卷帘页 6 + 高级页 3 + 产品窗 1（`native/after/`，frames/renderer/sources 齐全）。
- **before 基线**：`tools/design-qa/run-batch27-before-tree.sh` 改为从 `git archive 2003e53^`（第23–27批入库提交的父提交，与 `.statem` 快照逐字节一致）检出完整源码树重建；修了三个脚本 bug（modulemap/header 未进 `-I`、`cp` 用了仓库根路径、复制品覆盖检出）。基线 10 帧在 `native/before/`。
- **消费者**：`python3 tools/design-qa/check-settings-shade-language-preview.py native/after --baseline native/before` → passed=true（`native/consumer-final.json`）。新增门 0 判据：夹具卷帘页滑杆行 span 必须等于产品实测值（696 档 612、560 档 476；"被拉宽带空段"形态会判红）。
- **切换测试**：`native/switch-tests.log`（33 ok）；根因诊断日志 `native/switch-tests-debug-run1.log`。
- **纯测试**：`bash tests/run-localization-tests.sh` PASS（373 键，`native/localization-tests.log`）。
- **门 3 图片实看**：`zh-light-696-shade.png`、`en-light-696-shade.png` 实际查看，版面无事故，英文行名/说明/分组完整。高级页与产品窗 PNG 黑屏——离屏窗口的 sourceList/材质视图不渲染，run2 起即如此，非本批回归；该两面的验收依据是帧数据（`windowSubtitle`：zh「高级」→ en "Advanced" → zh「高级」；产品窗 subtitle「卷帘」、labels 101 项）。
- **门 4 全优化构建**：`bash prototype/build.sh --check` PASS（514 个 Swift 文件；编译验证通过 + 隐私登记 PASS + 文案检查通过；`native/build-check.log`）。

## 判据放宽（逐条，护栏要求）

见 [gate2-geometry-drift.md](gate2-geometry-drift.md)：两条 wrappingLabel（「需要已绑定身份的蓝牙读回来源」「名单里还没有 App」）的 x/w 对比跳过——基线同一 run 内自身漂移（82/484.5/348.5；94/476），两树几何代码同构，原判据在歧义行上不成立。滑杆行是第三条同类（§4），已按产品实测形态钉住，不在放宽清单里。

## 随批滚动同步（定案 1）

- `README.md`/`README_CN.md`「In development/开发中」各加一条英文界面（注明尚未覆盖全部界面，不写"英语已支持"）。
- `site/`：本批新定的英文词（Roll up、Window browsing 等侧栏名）与官网现有英文文案一致，无词可同步；`npm run build && npm run check` PASS（42 资产），未部署。

## 未覆盖 / 不成立的声明

- 没有签名安装运行产品、没有真机设置窗口切换语言、没有 VoiceOver 实听；组件级重建证据（frames + 切换测试）不等于真机可见效果。
- 高级页/产品窗 PNG 黑屏（离屏材质限制），这两个面的图像证据为 inconclusive，以帧数据为准。
- 英语剩余表面（交接 §9 清单）未开工；「跟随系统」下其它界面的重建路径覆盖未检查。
- before 基线由 `2003e53^` 重建而非原 /tmp 快照（已被系统清空）；快照 15 文件与该提交逐字节一致（2026-10-12 核对），但快照外的文件无法比对。
