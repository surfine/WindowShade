# 第32批：§9 剩余用户可见表面全量英文（用户："全量英文，兑现承诺"）

第30/31批清掉了设置面板、通知面和欢迎流程；这一批把剩下的**用户可见**表面全部迁进目录：
菜单栏与状态菜单、刘海全部（格子、卡片、活动、筛选、右键、音量亮度、电量）、窗口浏览面板、
启动台、手势教学与 HUD、置顶预览、计时器/番茄钟/正在播放卡、授权确认、带到每张桌面、卷轴、
窗口切换器。防漏网棘轮 **2150 → 1429 行**（第31批终点 2150，本批 −721；剩余占位主要是内部
诊断串、多语言菜单匹配关键词表、QA 探针——不是用户可见文案）。

构建身份：`--check` / `--stage` 退出 0，签名 `Apple Development: openkams@gmail.com (G3TN2MBQ2Q)`，
二进制 sha256 `86da9f96954187dba69d0332f52d4c608f048affabc0db387db16b1371b30caf`（VM 部署一致）。

## 看什么（VM 实拍，构建 86da9f96…）

| 图 | 说明 |
| --- | --- |
| `native/menu-top-en.png` | 状态菜单九项：Roll up the window / Tuck into the notch / Pin Window / Arrange ▸ / Launchpad / Rolled-up windows（灰） / Settings… / About / Quit WindowShade |
| `native/menu-arrange-submenu-en.png` | 整理▸：Slide Over the current window / Picture in Picture / Magic Tiling / Strip overview（灰） / Carry to Every Desktop / Arrange the Bars / Tuck All into the Notch / Choose Window… |

原始 CU 证据：`20261013T133637-53bbeeb8`（顶层菜单）、`20261013T134207-d1b76be8`（整理子菜单）。

## 按中文串判路由的修复（跟第31批同一类，这批又清了三处）

1. **菜单图标跟标题走**：`foldToggleMenuTitle().contains("展开")` 判图标、`pinTitle.contains("取消置顶")`
   判图标、`contextCaption != "当前窗口"` 判提示——英文下全判错。改成
   `foldToggleState()` / `PinnedPreview.currentTargetPinState()` 返回语义状态（含标题+图标），
   菜单只认状态；提示改 `ws2CachedMenuCaption() -> String?`（nil = 没有提示，不再拿"当前窗口"当哨兵）。
2. **传感器状态**：`DuoController.sensorStatus` 原是中文字符串、菜单按 `case "传感器未启动", "角度读取已暂停"`
   判等；新增 `sensorPhase` 枚举（`.notStarted/.connected/.retrying/.paused/.captureFailed`），句子走目录
   （`duo.sensor.*`），菜单按 phase 判。
3. **隔空投送结果**：`text == "已送出"` 判图标；改 `ShareOutcome` 枚举一次给句子和图标。
4. **番茄钟"休息"**：`isRest` 原判 `item.title == "休息"`；来源与判据改查同一个目录键
   `notch.focus.rest`（`WS2AppRuntime` 发布时也走它）。

## 词表补充（copy-guide 英文表新增行）

| 概念 | English |
| --- | --- |
| 整理（菜单/动作） | **Arrange**；整理卷帘条 **Arrange the Bars**；恢复卷帘条原位 **Put the Bars Back** |
| 已收起的窗口 | **Rolled-up windows**；全部展开 **Unroll All** |
| 屏幕开合角度 | **Hinge angle**（等待传感器：waiting for the sensor） |
| 编程会话（刘海格） | **Coding session**；在等你 **waiting**、在跑 **running** |
| 文件架（刘海格/卡） | **File shelf**；文件架空了 **File shelf is empty** |
| 卸载 App | **Uninstall App…**；先不删 **Keep for now**；重试失败项 **Retry the failures** |
| 卷轴动作 | 这一列宽/窄一档 **Wider/Narrower column**；并进左边/右边这一列 **Join the column on the left/right** |
| 音量/亮度/键盘灯 | **Volume / Brightness / Keyboard light** |

刘海句子长度（`NotchSentence.headlineLimit = 8 字形簇`）第一次按语言拆开：中文仍是 8，
英文暂取 24（副句 40）——**这一档是占位，待真机在刘海里实看后定死**（刘海面出厂默认关）。

## 测试与回归

- 目录 **2046 → 2120 键**（本批 +290：menu/pin/duo/notch.*/launchpad.*/gesture.*/magic.*/strip.*/carry/auth/timer/focus/nowPlaying/battery…）。
- **49 个受影响测试 runner 补编 `WSL10n.swift`**（这些套件单独 swiftc 编译生产源，之前没有 WSL10n）；
  启动台三个旧 runner（view/visual-fixture/perf）还漏编 `WS2AppUninstallPlan/Scanner`（HEAD 上就编不过，顺手修）。
- 全部受影响套件重跑：**53/53 PASS**（`run-silent-integration-tests.sh` 不带 `--case` 会打印用法退出，
  r01/r03 实跑 PASS）。
- `check-localizable` PASS（2120 键中英齐全）、copy-lint PASS、隐私登记 730 处 PASS、隐私页生成同步 PASS。
- **顺手修一个既有断言崩**：`PrivacyPaneTests` 要求登记行 subtitle ≤16 字，`app-uninstall` 的
  "删 App 连带它的文件，进废纸篓"（17 字）在 HEAD 上就崩（1.0.16 基线 82681b0 也一样）；
  按生成链同步缩短为"删 App 连文件进废纸篓"（登记表+目录+生成件三处一致）。

## not_run（别当通过）

- **启动台实拍没拿到**：菜单项 "Launchpad" 在截图里是英文（menu-top-en.png），但点击链路三次都没把
  面板打开（CU run 内 50 秒截图新鲜度反复 HALT；点菜单项后 App 日志无 launchpad 记录，点击疑似没到
  菜单）。启动台界面的英文串全部过目录级校验（launchpad.* 78 键），面板英文实际观感待一次专门的
  交互会话。**这不影响翻译本身，但"启动台在英文下好看"没有屏幕证据。**
- 刘海实时活动、音量亮度条、电量闪现、手势教学、授权卡：句子全部走目录并过 `run-localization-tests`
  的逐键英文解析，但对应的**触发路径**（音乐播放、按键、低电量、卡住手势、遥控配对）没有在 VM 里逐个
  演出来——同第31批的口径：目录级 PASS + 代表性表面实拍，不逐句实拍。
- 刘海句长英文档（24/40）待真机定。
- 改动**未提交未推送**。
