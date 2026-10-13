# 第31批：欢迎流程 + 通知面的英文（真机 VM 实拍）

本批把**欢迎窗口三步**（含舞台上画的那几句）和**刘海通知面**从写死的中文迁进目录，并在隔离 VM 里用
Computer Use 拍下英文下的真实画面。设置面板上一批（`2026-10-13-settings-panel`）没覆盖到的两处也一并补上：
卷帘页的**分组标题**（触发/外观/权限）和"之前常用"分段的第三个名字。

构建身份：`./prototype/build.sh --check` 退出 0；`--stage` 退出 0，签名
`Apple Development: openkams@gmail.com (G3TN2MBQ2Q)`；
`WindowShade.app/Contents/MacOS/WindowShade` sha256 =
`4872143f4a5037938055fa97620d23a91cf0e66bceaafbe2258a9799dad5f918`（本机与 VM 部署副本一致）。
VM：`wsqa-manual`（macOS 26.6.2 / CuaDriver 0.34.0 / Lume 0.6.1），产品界面语言
`WindowShade.InterfaceLanguage = en`。

## 看什么

| 图 | 说明 |
| --- | --- |
| `native/welcome-1-intro-en.png` | 欢迎第 1 步：舞台菜单栏是 `Notes File Edit Window`，迷你窗口是 `Shopping List` / `Mail`，刘海两行是 `On a Mac, Copy is ⌘C` / `Most shortcuts use ⌘ where Windows uses Ctrl`；标题 `Just switched to a Mac? Start at the notch.`、导语、`Skip` / `Continue` 全英文 |
| `native/welcome-2-origin-en.png` | 第 2 步：`What did you use before?`，三个选项 `Windows` / `iPad` / `Always Mac`（第三个名字改短后完整显示），下面一行导语完整 |
| `native/welcome-2-origin-en-BEFORE-FIX-clipped.png` | **同一页修前**（构建 `b04a991c…`）：第三个选项被裁成 `Always used a M…`。保留为缺陷记录 |
| `native/welcome-3-permissions-en.png` | 第 3 步：`Last step: permissions`、`Permissions are ready`、三行 `Accessibility` / `Screen Recording` / `Calendar`，按钮 `Back` / `Get Started` |
| `native/welcome-4-finished.png` | 点 `Get Started` 之后：欢迎窗口收起（流程能走完，没有卡在最后一页） |
| `native/notice-carried-en.png` | 通知面：把受控窗口"带到每张桌面"后，岛上说 `Carried to every desktop`（绿勾，`.done`） |
| `native/settings-rollup-en.png` | 顺带：卷帘页英文（`Triggers` / `Notch` 两组，本批补的分组标题就是这一类） |
| `native/settings-privacy-en.png` | 顺带：隐私页英文 |
| `native/restore-after-unfold.png` | 恢复：受控窗口从卷帘状态展开，回到 prepare 记录的 (437,131 673×439) |

截图来自两次 CU run（原始证据留在 `/Volumes/TiPlus 7100/WindowShade-QA/evidence/computer-use-qa/`）：

- `20261013T120005-7ffee488`——构建 `b04a991c…`，**拍到了第三个选项被裁的缺陷**，因重新构建而正常收尾（CLOSED）；
- `20261013T120624-adae7826`——构建 `4872143f…`，修后全流程、通知、恢复都在这一次里。

## 发现并修掉的东西

1. **第三个选项被裁**（上面那张 BEFORE 图）：英文名字 `Always used a Mac` 比卡片留的宽度长。
   名字统一改成 `Always Mac`（和设置里"之前常用"分段同一个名字），并加 `origin.*` 目录键让
   欢迎选项、设置分段、刘海问来处共用一份显示名（zh 源句仍是 `一直用 Mac`）。
2. **卷帘/窗口浏览页的分组标题**上批漏了：`触发` / `外观` / `权限` 还是裸中文字面量，已走目录
   （`settings.browser.group.*`、`settings.common.group.permissions`），顺手删掉两处畸形嵌套调用
   （`WSL10n.text(键, zh: WSL10n.text(键, zh: …))`，上批合并时留下的）。
3. **"已排除 N 个应用"那一行的连接词**：`、` 和 ` 等` 写死在代码里，英文下会出中文字符，已各给一个目录键。
4. `@unknown default` 分支返回的中文串改成走目录（和 `.notRegistered` 用同一个键）。

## 没做 / 没验的（别把这份当"英语已支持"）

- **通知的两句拒绝文案没有拍到**：`先展开这个窗口，再带到每张桌面`（卷起后 carry）和
  `没有可以带着的窗口`（没有前台窗口时 carry）两次尝试都没复现出条件——第一次卷起受控窗口后焦点落到
  另一扇 TextEdit 窗口（日志 `carry: start id=731`），第二次想点桌面却抬起了 Finder 窗口
  （日志 `carry: start id=731` 之后又一条）。这两句只过了目录级校验（每个键都能在英文下解析、无汉字），
  没有屏幕证据。
- **菜单栏兜底通知**没拍到：`Notch.enabled` 出厂默认关（`ReleaseDefaults` 里 `deviceVerified: false`），
  关着时通知落在状态栏标题、只显示 1.4 秒；预拍窗口太窄，两次都被自动截图错过。本批为了拍岛上那句，
  在 VM 里通过产品自己的"卷帘页 → 收进刘海"开关临时打开过、拍完已关回去（`defaults read … Notch.enabled` → `0`）。
- **刘海问来处那条提示**（`habit.askOrigin.*`）没有触发路径（要等来处推断跑出来），只有编译期与目录校验。
- **§9 的其它表面仍是中文**：菜单栏与状态菜单、刘海实时活动、窗口浏览面板、启动台、手势提示等
  （防漏网棘轮 2180 → 2150 行只是本批这 30 行的量）。
- 本批的 VM 里，受控窗口在卷起前后位置与 prepare 记录一致（(437,131) → 展开回 (437,131)）；
  屏幕坐标与 CU 截图像素不是 1:1，所有点击坐标都是从**当次截图**上量的（见 qa 手册）。
