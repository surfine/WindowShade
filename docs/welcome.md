# 欢迎使用 WindowShade

首次打开时出现，菜单里的“欢迎使用 WindowShade…”随时能再打开。1.0.18 按设计稿《首次打开 1.0.17 小样》（第 4 版，提交 943853c）从旧三步重做成
**三页：A1 看一遍再试一下、A2 授权、T 再看四样**；页码点只数这三页。升级上来缺授权的 **U1**（“再打开一次这两项”）是单独一页，不算页码；
**N1**（“这一版新开了这几样”）是另一扇小窗（[WhatsNew1018](../prototype/App/WhatsNew1018.swift)），只在升级后真有默认值变了时弹一次。
设计要求见 [design-system.md](design-system.md) §5.11；讲解动画共用部件见 §5.14。

| 页 | 标题 | 一句话 | 舞台上 |
| --- | --- | --- | --- |
| A1 | 双击标题栏，把窗口收起来。 | 窗口收成一条卷帘条，里面的东西都还在。 | 讲解动画演两轮（双击收起 → 双击展开），然后叠一扇真子窗口轮到他练：双击标题栏收起、再双击展开，出现 ✓ |
| A2 | 让每扇窗口都能收起 | 刚才那扇是 WindowShade 自己的窗口。收起别的 App 的窗口，要打开辅助功能。 | 两行真实授权行：辅助功能（必需）、屏幕录制（可选）。只等辅助功能就能“继续” |
| T | （按段换）窗口可以收进刘海 / 停在 Dock 图标上，看它的所有窗口 / 两指一滑，窗口就排好 / 它在菜单栏里 | 每段一句 | 四段分段（刘海、窗口浏览、手势与卷轴、菜单栏）各带讲解动画，自己往下走；点分段或“继续”一段一段看 |

A1 的“跳过”直接到 T；A2 的“稍后再说”也进 T（算看过）；T 最后一段的“继续”是“开始使用”（关窗口），T 的“跳过”直接关窗口。
页码点给读屏的名字是“第 n 页，共 3 页”。

**三页之前可能多一步：放进“应用程序”文件夹。** 只在从“下载”、磁盘映像等地方直接打开、而且这是带更新器的版本时出现（开发版不问），
不算在三步里、没有页码点。流程和保护见 [update.md](update.md)，文案在 App/UpdaterCopy.swift。这一步 1.0.18 没改。

**启动时走哪条路**（[`LaunchOnboardingRoute`](../prototype/Core/WhatsNew1018Changes.swift)，启动不再带 prompt 弹系统框）：
新装 → A1；升级上来缺辅助功能、这一版没看过 U1 → U1，之后接 N1；升级上来授权都在、有默认值变了、没看过 N1 → N1；
还没看完欢迎窗口的照旧从第一页看起。“升级”认 `InstallHistory` 或认出 1.0.15 及以前的老安装，手动下载装上来的也接得住。
默认值哪些变了、N1 只列哪些，见 [v1.0.18-defaults.md](releases/v1.0.18-defaults.md)。

## A1：先看一遍，再轮到他

- 演示用讲解动画（`ExplainerScenes+Common` 的 `dbl`）演两轮，每轮约 4.1 s，然后停在卷帘条那一帧、轮到他。
  他一动手（双击）演示就停。
- 练习窗口是真子窗口：标题栏双击走 WindowShade 自己的收起，**不要辅助功能**，所以他试的那一下就是真效果。
  状态机见 [`WelcomeFlow.PracticeState`](../prototype/App/WelcomeFlow.swift)（demo → idle → rolled → done；done 后“继续”变主按钮）。
- 左块跟着他的点击亮；演示与练习的动效数值在 §5.14。
- “想要系统原来的双击？按住 Option 再双击。”是 A1 的一行可选说明。

## A2 / U1：授权行

- A2 两行：辅助功能（必需，“找到、移动和收起窗口”）、屏幕录制（可选）。“继续”只等辅助功能；
  屏幕录制读 `CGPreflightScreenCaptureAccess()`，“去授权”调 `CGRequestScreenCaptureAccess()`。带 prompt 的授权请求只在这一页和 U1
  （`requestAccessibilityPrompt()`），启动序列里只读 `AXIsProcessTrusted()`，不再弹系统框。
- 回到这页 10 秒还有一项没好，出现“开关开着却没用？……点‘−’删掉，再回来点‘去授权’”那句；U1 一打开就在。
  标准账户下多一句要管理员密码。
- U1 的进度字：两项都好“权限已就绪”、只差屏幕录制“还差屏幕录制。不开也能用。”、两项都缺“还差 2 项”。
- 授权页在标准账户下多一句“打开时要输入管理员的名字和密码。”；更新日志那条路（装好新版本后授权没了）也落到 U1。

## T：再看四样

- 四段：**刘海**（收进刘海＋放回、刘海教你，两块各演一轮；段下面是“你之前常用哪个？”的一行可选单选——这个答案决定刘海教什么，
  见 [stuck-habits.md](stuck-habits.md)）、**窗口浏览**（Dock 悬停）、**手势与卷轴**（两指滑＋魔法平铺）、**菜单栏**（没有 Dock 图标，收起的窗口和设置都在这里）。
- 自己往下走：一块演完停 0.4 s 演下一块，最后一段演完停住。点分段、指针停在演示块上、按“继续”就停在自己走；
  减少动态效果时不自己走。
- 跳过了授权时，菜单栏一段多一行“还没打开辅助功能，现在只能收起 WindowShade 自己的窗口。”
- “你之前常用哪个？”的存取和接口仍是 `SwitcherOrigin`（见下），1.0.18 只是把问题从原来单独一步挪到刘海一段下面，不选也能继续。

## 给别的模块用的接口

- `SwitcherOrigin.current`：`.windows` / `.ipad` / `.mac` / `.unanswered`。存在 UserDefaults 的 `SwitcherOrigin` 键里；
  没答就是没有这个键，认不出的值当没答。
- `SwitcherOrigin.didChangeNotification`：答案真的变了才发，总在主线程发；`userInfo[SwitcherOrigin.previousKey]` 是原来的 rawValue。
- 消费方：`HabitRules.rules(for:)` 按来处开哪几条卡住提示（[stuck-habits.md](stuck-habits.md)）、`DockClickHide`、`HabitContext`、讲解动画（`ExplainerScenes+Notch`）。
- 单测：`tests/run-switcher-origin-tests.sh`、`tests/run-welcome-flow-tests.sh`（状态机纯逻辑）。

## 验证

`WindowShade --settings-shots <目录>` 把欢迎流程在浅色、深色下各拍一组，全是静帧（讲解带走 `--explainer-frame` 定帧）：

- `onboarding-<外观>-0.png`：放进“应用程序”那一步（按“第一次放进去”摆）。
- `onboarding-<外观>-<页><字母>.png`：三页（A1 / A2 / T），一页多刻时带字母（a、b……）。
- `onboarding-<外观>-u1a.png` / `u1b.png`：U1 的两项都缺 / 只差屏幕录制。
- `onboarding-<外观>-n1.png`：N1 三行都是新开的样子。

`manifest.txt` 记着每张摆的是哪一刻。拍完只 orderOut、不关窗口，不写“看过引导”，也不写“之前常用”。

代码：`prototype/App/WelcomeFlow.swift`（状态机、文案、动效数值，纯逻辑可单测）、`prototype/App/Welcome.swift`（画）；
打开与选路在 `Preferences.swift` 的 `showPermissionOnboardingIfNeeded(force:)`。

## 已知偏差

- **没有刘海的屏上文案仍然叫“刘海”**：全产品现在都这么叫，没有刘海的屏上叫什么还没定（design-system §5.3 / §8 问题 2），
  定之前不在欢迎窗口里单独起第二个名字（copy-guide 规则 2）。讲解动画的迷你桌面画的是带刘海的示意机。
