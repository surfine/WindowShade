# 第30批：设置面板收拾（鼠标与触控板页 + 遥控器页迁移；副标题截断修复；防漏网判据修正）

2026-10-13。承接 issue #40 的口径：设置面板在英文模式下是"壳英文、身中文"，最显眼的乱就在这几页。

## 改了什么

### 1. 鼠标与触控板页 / 遥控器页整体迁进目录（`App/WS2InputSettingsPane.swift`）

- 两页 66 行裸中文字面量 → 5 行（其余 72 条字符串进目录，`Localizable.xcstrings` 500 → **572 键**，中英齐全）。
- 行构建器从本文件自建（16 字**硬截**、只有 tooltip、无 ⓘ）换成共享机制
  `WS2SettingsCopy.content(name:subtitle:detail:symbol:)`：行内一句状态、ⓘ 里给完整解释，
  与卷帘/高级页同一套渲染与截断规则（词边界而非劈字）。
- 新增 `content(…detail:)` 重载：行内短句与 ⓘ 详情分开，且只出一个 ⓘ。
- 状态串是 Core 状态机的中文源句（`InputStatusCopy` 等），按源句**逐条映射**到目录键（语义身份不变）；
  出现未映射的新状态时原样透出并留日志，不在这里悄悄造键。

### 2. 副标题截断修复（`Preferences.swift` + `WS2SettingsInfo.swift` + 目录）

- 现象：1.0.16 里「双击标题栏收起窗口」的副标题被截成"三击标题栏会缩放窗口；按住 Op"。
- 根因：`line()` 对中文在**没有短句条目**时硬截前 16 字；#39 加长的句子正好越线。
- 修法（按既有机制）：全文（两句：系统三击做什么 / 怎么临时跳过）留在目录里当副标题，
  行内改由 `short` 表给回原来的短句（"三击标题栏会缩放窗口"），于是**行内与 1.0.16 之前逐字相同**、
  多出一个 ⓘ 承载"按住 Option 双击不收起"。英文同理（`shortEn` 三条）。

### 3. 防漏网判据修正（`tests/check-localizable.py` + `localizable-ratchet.json`）

- 旧口径把 `WSL10n.text/setting(zh:)` 里的**身份源句**也算成"漏网"，于是"把行迁进目录"反而让计数上涨
  （本页实测：裸字面量 66 → 5，旧口径总数却 +38）。
- 新口径只数**没走目录的裸中文字面量**——这才是它要防的东西。判据是**收紧**（量更准），不是放宽。
- 基线重冻：同口径批前 ≈3200 → 本批 **3142**（只许降不许升照旧）。

### 6. 行的名与说明统一走 SettingsText（修掉英文被 16 字硬截）

英文副标题一度显示成 "Unpin every pin…"：行的*名*来自 Swift 常量（`GlobalShortcut.title`）、
*说明*传的是 String，于是整行走了旧的中文路径（**16 字硬截 + 只有 tooltip、没有 ⓘ**）。
处理：`GlobalShortcut` 加 `titleText: SettingsText`（逐 case 的目录键 + 中文源句），
快捷键页/窗口浏览页的行改走 SettingsText 重载，权限行加 SettingsText 重载；
英文改走 34 字词边界预算并配 `shortEn` 短句（本批补 52 条），行内不再劈字、ⓘ 承载全文。

## 证据

- 改前（1.0.16 正式版，英文模式，隔离 VM 实拍）：`native/before-01-pointer-zh.png`（鼠标与触控板页整页中文）、
  `before-02-privacy-zh.png`、`before-03-shortcuts-zh.png`（同一 run `20261013T080514-bb694ef1`）。
- 改后：`native/after-01-pointer-en.png`（鼠标与触控板页全英文 + 每行 ⓘ）、
  `after-02-shortcuts-en.png`（快捷键页英文短句不再截断，状态/按钮全英文，带符号行有图标）。
- 编译与检查：`native/build-check.log`（stage 构建 EXIT=0）、`build-check-full.log`（`--check` 全 PASS）。
- 纯检查：`python3 tests/check-localizable.py`（572 键、源句一致、棘轮 3142）、`python3 tests/copy-lint.py` 通过。
- 编译：`prototype/build.sh --check` EXIT=0（见下"验证"节）。
- 改后实拍：见同目录 `native/`（VM 内 zh/en 两页各一张）。

### 4. 设置面板全量英文化（用户 2026-10-13 追加："请你全量迁移至英文"）

在本节之前已迁移：窗口外壳、卷帘页、高级页、静音短句（第27/28批）、鼠标与触控板页、遥控器页（上文）。
本节再迁：

| 表面 | 内容 |
| --- | --- |
| 快捷键页 | 页头、5 个分组名、~30 行副标题、录制/清除/未设置/请按快捷键…、拒绝提示；**40 条快捷键名**（`GlobalShortcuts.swift` 的 `title` 改为按目录出） |
| 窗口浏览页 | 页头、5 个分组名、全部行名与副标题、排除名单摘要、排除弹窗三句 |
| 效果页 | `DuoSettingsWindow.swift`：分组名、桌面开合/收起动画/预览三项、预览对象/样式/进度、展开/收起标签、暂停按钮、屏幕录制权限行（~23 条） |
| 私人 App | 名单行的名与副标题、添加…/完成/移除/添加、空态、常见分组（`PrivateAppListSettings.swift`） |
| 有人在看 | `BystanderTuckRow` 的名/副标题/空态改为按目录出（`BystanderPolicy.swift`） |
| 更新段 | `UpdaterCopy.swift` 全文（菜单、小窗、进行中、结果与原因、设置四项、搬运三段、授权两段，共 58 条，含 14 个带参数句与"上次检查"的日期词） |
| 隐私页面板与模型 | `WS2PrivacyPane.swift`/`WS2PrivacyModel.swift`：页头、再读一次/显示技术细节/导出…、展开里的七个开关名、详情列标签（读到的/为什么/去了哪里/什么时候读/开关/合起来能看出什么/接口）、导出弹窗、值串（锁屏状态、自动检查、已开启/未开启、有刘海/没有刘海、N 块屏、音乐播放中、没有 App 在录音、没有连着的配件、N 个…） |

目录从 **572 → 1014 键**；防漏网裸字面量 3142 → **2713 行**。

一处按语义改的判据：详情列的短标签原来是 `title == "什么时候读"` 这种**拿中文字符串当判据**，
现在按身份（目录键的 zh 源句）比较、显示走目录，英文模式下不会失效。

### 5. 看护也随语言（用户要求，不留缺口）

`UpdaterCopy.swift` 是 App 与看护共用的文案文件，而看护按 build.sh 的约定只能依赖 Foundation/AppKit 和彼此。
处理：`build.sh` 把 `Core/WSL10n.swift`、`Core/InterfaceLanguage.swift` 加进看护源集合（两者都只依赖 Foundation），
把编好的 `Localization/en.lproj` 一并拷进看护包，看护入口按同一套规则解析语言（读产品偏好域
`WindowShade.InterfaceLanguage` + 系统首选语言）。看护新读的这处偏好已登记进 `tools/privacy/registry.json`
（`signal: settings`），隐私登记检查 730 处全 PASS。

## 未覆盖 / 不属于本批

- **隐私页数据行：已完成（520/520）**：65 条登记项的 8 个字段与 4 个分组标题全部译出，
  写进 `registry.json` 的 `signal["en"][field]`；生成器按条目级英文出 `WSL10n.text`，
  缺 en 时逐字节回退中文（现无缺）。目录 1014 → **1408 键**，防漏网裸字面量 2712 → **2317 行**。
  展开详情、分组标题、权限行、页头引导句全部英文（见 `native/after-03`、`after-04`）。：页面正文 65 条登记项的文案（label/subtitle/reads/purpose/destination/activation/toggle/combined 共 **520 条**）
  来自生成文件 `WS2PrivacyData.swift`，迁移点是 `tools/privacy/registry.json`（6515 行）＋
  生成器 `tools/privacy/make-privacy-page-source.py`（135 行）＋同步测试 `tests/run-privacy-page-sync.sh`。
  已量化为独立一批：registry 加 `*_en` 字段 → 生成器在有条目时emit `WSL10n.text` → 520 条译文入库。
  在这一批之前，英文模式下的隐私页是"壳英文 + 数据行中文"。
- **通知面**：`quietNotice` 的 66 个调用点（刘海提示句）仍是中文，而且 `noticeTone(_:)`
  与 `message.contains("权限")` 是**拿中文句子判语气和跳转**——英文模式下这两处会判错。
  按 §9.3，这一批要把语气/是否需要权限改为调用点显式传入的语义值，再逐句进目录。
- **欢迎流程**：窗口标题与授权页/进度/日程行（~15 条）仍是中文；已在 `Preferences.swift` 里逐条定位。
- `WS2SettingsInfo.swift` 的身份表：`short` 表 68 条是这些行的短句来源（zh 侧无需改动）；
  `shortEn` 只覆盖了卷帘页的 26 条，其余行的英文靠"词边界截断 + ⓘ 全文"呈现，可再补短句。
- 未做真机验证；VM 内 Computer Use 实拍只证明渲染与语言切换，不代表真实触控板/手柄设备行为。
- **设置面板之外**（属 §9 其余表面）：刘海通知的 66 处 `quietNotice` 句子仍是中文，且
  `noticeTone(_:)`/`message.contains("权限")` 按中文句子判语气与跳转——英文模式下会判错，需要按语义改判据；
  欢迎窗口的标题与授权页/进度/日程行（~15 条）仍是中文。两者不在本批范围。
