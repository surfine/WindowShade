# 看一眼

指针停在卷帘条上，卷帘条下面挂出一张卡片，按原尺寸显示窗口内容；指针移开，它自己收回去。
单击卡片才真正展开。它回答的是“为什么不用最小化”：最小化、切换窗口、切换桌面
都要去了再回来，看一眼只走单程，看完什么都不用收拾。

## 入口与行为

- 设置 → **卷帘** → **看一眼**，默认打开。关掉后，单击卷帘条恢复成 1.0.14 的小缩略图。
- 指针进入卷帘条就开始准备画面，停够约 0.22 秒才显示；只是路过不显示任何东西。
- 原貌卷帘条不动；卡片挂在它下面、隔 6 点的缝，显示标题栏以下的内容，宽度和位置对齐真窗口；
  超出屏幕可见区域的部分裁掉，上沿不动。卡片和真窗口分得开：一眼看得出这是预览。
- 卡片四个角都用真窗口的圆角：半径从收起时的截图里量（连续曲率，弧线起点按 1.528 倍换算），
  带自己的投影；有画面时不铺底色，不会在角上露出月牙或双层边。
- 被隐藏的 App 临时在原处取消隐藏时，缝和卡片圆角的缺口底下垫一张打开那一刻截的真实背景
  （`FastCapture.composite`），真窗口露不出来；背景截不到就不取消隐藏，只给截图。
- 只有卡片本身算“在画面上”、接单击；缝和投影边距不算。
- 指针从卷帘条移到画面上不会收回；离开两者约 0.16 秒后卷上收回。
- 单击卷帘条：不等计时，马上看一眼。
- 单击画面：真正展开那扇窗。画面留到真窗口回到原处才撤，中间不露出后面的东西。
- 停在卷帘条左侧的红绿灯上不计时：那里另有窗口管理菜单。
- 刚收起的那一下指针还停在卷帘条上：这条先不响应，指针离开一次才恢复悬停。
- 切换 App、换桌面、拖动卷帘条、展开或关闭窗口，都会立刻收回。
- 看一眼不切换当前 App，不抢键盘焦点，不移动、不缩放任何窗口。

## 画面从哪来

macOS 不让别的 App 把窗口画成只剩标题栏，收起时真窗口被藏起来。画面来源取决于
它被藏在哪：

| 真窗口的状态 | 看一眼的画面 |
| --- | --- |
| 挪在屏幕外（Codex 等允许的 App） | 实时画面。指针一进卷帘条就开流，多数时候显示时第一帧已经到了 |
| 整个 App 被隐藏 | 先显示收起时的截图，画面卷下来盖住原处之后，在下面临时取消隐藏、拿实时画面；收回时先藏回去再卷上。只在卷帘条没被拖走、画面能完整盖住真窗口时这样做 |
| 最小化、或上面两种拿不到画面 | 收起时的截图，右下角标明“收起时的画面” |
| 连截图也没有 | 显示“画面暂时看不到” |

实测（2026-09-24，Mac17,4，macOS 27.0）：

- 屏幕录制能以约 30 帧/秒实时抓取挪到 (-32000, -32000) 的窗口，热启动一条流约
  156ms 首帧。
- 最小化或整体隐藏的窗口，一帧也抓不到。
- 多数 AppKit 窗口不能用辅助功能挪出屏幕：日常日志里 Safari 窗口被拉回
  (-2097, -1410)，四个停靠点全部失败后退回最小化；历史日志里没有一次成功挪出。
  所以默认收起策略是“单窗口隐藏整个 App，否则最小化”，现状下多数看一眼只能给截图。
- 从后台进程调用 `NSRunningApplication.unhide()` 不会让别的 App 显示出来（2 秒内
  窗口不回来）。辅助功能取消隐藏（`kAXHidden = false`）23ms 让窗口回到原处，前台
  App 不变；开流后 104ms 首帧；重新隐藏 13ms，前台仍不变。万一某个 App 取消隐藏后
  跑到了前台，看一眼会记下它，之后对它只给截图。
- 别的桌面上的窗口也能抓：Safari、备忘录 86ms 拿到当前画面；最小化的窗口仍是 0 帧。

## 带到每张桌面

给一张桌面只放一个 App、靠触控板切桌面的人用。菜单“带到每张桌面”或 `⌃⌘G`：

- 当前窗口不收起，留在它自己的桌面；别的桌面右上角（菜单栏下面）出现它的卷帘条，
  多条从右往左排。窗口就在眼前时（它的桌面上、没被隐藏或最小化）卷帘条不显示，也不占位置。
- 一行放不下时，余下的窗口进“更多窗口”菜单。选中后，它的卷帘条出现在这一行并打开看一眼，
  不切换桌面。菜单关闭后留出约 1.2 秒供指针移到画面上；到达后按普通悬停规则收回。
  设置中关闭“看一眼”时，菜单选择只显示对应的卷帘条。
- 停在卷帘条上看一眼：整扇窗按比例缩小（最宽占屏幕七成），挂在卷帘条下面、右边对齐。
  画面从那张桌面实时抓过来，不切换桌面、不切换 App。
- 单击卷帘条马上看；单击画面或双击卷帘条：回到那扇窗（系统切到它所在的桌面）。
- 再按一次 `⌃⌘G` 或点卷帘条上的叉：放下。窗口关闭、App 退出或窗口被收起时自动放下。
- 拿不到实时画面（窗口最小化、App 被隐藏）时给带着时留的截图，右下角写“不是实时画面”。

实测：临时 App 把窗口挪到另一张桌面（桌面 6，当前桌面 5 不变），看一眼 273–323ms 出画面、
323–360ms 是实时画面，从另一张桌面每秒 25–30 次更新，前台不变。全屏 App 的桌面上
卷帘条是否出现（`.fullScreenAuxiliary`）尚未在真机验证。

代码：`prototype/App/Carry.swift`（卷帘条面板、`CarryController`），看一眼复用
`GlanceController`（`GlanceTarget` 描述两种来源的画面位置与来源）。

## 收起有多快（与“卡顿”有关）

收起时给窗口截图原来用 ScreenCaptureKit，放在收起途中要 229ms 以上、还会超时退回代理
标题栏；现在先用 `CGWindowListCreateImage`（见 [performance.md](performance.md) 第 12 条）。
同一进程连续收起的中位数：不带动画时，第一眼看到变化 342 → 147ms、卷帘条出现
499 → 328ms；带动画时 591 → 478ms、1015 → 904ms。带动画剩下的大头是动画自己的
实时流启动。

折叠确认在两次正式检查之间每 30ms 看一次 WindowServer 的实时在屏状态，窗口一离开
屏幕就亮出卷帘条（`FoldVerifier.quickObserve`）。

## 代码

| 文件 | 内容 |
| --- | --- |
| `prototype/Core/GlanceIntent.swift` | 指针意图状态机：预热、停留、离开宽限、单击、挡住刚收起的那一条。纯逻辑 |
| `prototype/Overlay/GlancePanel.swift` | 画面面板：卡片（真窗口圆角、投影）、背景垫片、卷下/卷上动画、“收起时的画面”提示 |
| `prototype/Capture/FastCapture.swift` | 快速截图：整窗与“去掉某些窗口后的屏幕区域” |
| `prototype/App/Glance.swift` | 控制器：悬停跟踪、会话、实时流、几何、展开交接、盖住再取消隐藏 |
| `prototype/App/Carry.swift` | 带到每张桌面：卷帘条面板、可见性、回到那扇窗 |
| `prototype/App/GlanceProbe.swift` | 真机探针 `--glance-probe` |

接线：`ShadeController.installOverlay` 挂悬停跟踪；`unshadeReturningElement`、
`forceCleanup`、`removeProxyForAction` 撤掉；`peekHoverPreview` 在开关打开时改走看一眼；
前台 App 与桌面切换时收回。看一眼自己取消隐藏期间，`handleAXNotification` 与
`sourceWindowLooksUserVisible` 不把“App 又显示出来”当作用户唤回。

## 验证

```sh
bash tests/run-glance-tests.sh          # 状态机：路过、停留、菜单交接、宽限、切换、单击、撤销
bash tests/run-appkit-tests.sh CarryControllerTests # 多条排布、菜单、窄屏、来源失效、焦点
cd prototype && ./build.sh --stage      # 签名隔离构建，不碰日常运行的应用
cd .. && bash tests/run-glance-probe.sh # 真机探针：两扇窗的独立临时 App
bash tests/run-glance-probe.sh --single # 单窗口：整体隐藏路径
bash tests/run-glance-probe.sh --carry  # 带到每张桌面（同一张桌面，强制显示卷帘条）
bash tests/run-glance-probe.sh --carry --other-space  # 临时 App 把窗口挪到另一张桌面；不切换你的桌面
```

真机探针会在屏幕上短暂出现测试窗口，只操作它自己启动的临时 App。锁屏时辅助功能
返回的窗口元素不完整，探针会在“fixture window”一步超时，不能当作结果。

2026-09-24 解锁状态下的运行结果（Mac17,4，macOS 27.0）：

```
# --single：整个 App 被隐藏 → 盖住再取消隐藏，实时画面
PASS glance: shown 261ms after the pointer arrived, live picture at 781ms, panel 640x420 under the strip, window unhidden in place fully under cover, frontmost app unchanged
PASS glance: picture keeps updating (30 frames in 1s)
PASS glance: closes 260ms after the pointer leaves; window put away again
PASS glance: click expands in place (window back in 40ms, no gap)

# 默认两扇窗：收起走最小化 → 收起时的截图
PASS glance: shown 259ms after the pointer arrived (snapshot), panel 640x420 under the strip, window still parked, frontmost app unchanged
PASS glance: snapshot labelled as the picture from when it was put away
PASS glance: closes 341ms after the pointer leaves; window put away again
PASS glance: click expands in place (window back in 295ms, no gap)
```

实时那一次在显示期间隔 1.2 秒截了两张屏幕图，临时 App 的计数从 72 走到 101，
真窗口没有从画面和卷帘条之外露出来。“收回”包括 0.16 秒离开宽限和卷上动画。
探针运行期间如果有人切换 App，“前台不变”这一项会失败，需要重跑。

2026-09-25 整合复检补充：用户主动切回临时显示的 App 时，释放看一眼的隐藏所有权并正常展开，不再把 App 藏回去；关闭后立即回入会重新准备已停流的会话；携带窗口被最小化后，点击返回先取消最小化。`bash tests/run-appkit-tests.sh GlanceLifecycleTests` 使用生产控制器和注入的 AX 操作验证这些路径，不操作用户窗口。
