# 交给 DeepSeek：鼠标、触控板与遥控器

用法和 [deepseek-conductor.md](deepseek-conductor.md) 一样：先贴总则，再一次贴一个工作包，顺序是 I1 → I9（纯逻辑部分）→ I2 → I3 → I5 → I8 → I7；
I4、I6 由主模型做。每个包交回后，先给主模型（Claude）验收，再给下一个。

交出去之前，先提交 `docs/input-devices.md`、`docs/conductor-v2.md`、`docs/copy-guide.md` 和本文件。
DeepSeek 的沙箱是从 git 克隆仓库的，没提交的文件它看不到。

---

## 总则（每个包都贴）

你在 WindowShade 仓库里工作。WindowShade 是 macOS 窗口工具，用 Swift 6 和 AppKit 写，直接用 `swiftc` 编译，没有 Xcode 工程。
这次要做的是“手边的每一样”：

- 普通滚轮鼠标：平滑滚动、滚动方向和触控板分开、⌥ 精细滚动、侧键后退 / 前进、中键操作标题栏；
- 妙控鼠标、妙控板：中键，以及几个不和系统冲突的轻点手势；
- 实体 Siri 遥控器：两种模式，遥控模式（在沙发上操作 Mac）和指挥模式。
- PS5 手柄（DualSense）：操作 Mac，游戏在前台时让开；
- 焦点导航：刘海那一排、启动台、窗口浏览、按窗口切换都能用方向键、遥控器的环、手柄十字键挪焦点。

目标是 WindowShade 2：像 iPadOS 那样一个入口、一套动作、任何输入都能用。**不做配置工具，做体验**：默认值要好到不用改，能改的只有开 / 关和少数几档；不做宏、脚本、Webhook 这类通用自动化。

先读这些，再动手：

1. `docs/input-devices.md`：完整规格，**以它为准**。
2. `AGENTS.md`、`docs/copy-guide.md`：界面文案规则。设备名用“妙控鼠标 / 妙控板 / Siri 遥控器”。
3. `docs/blueprint.md`：十二条硬要求。
4. 已有代码的写法：`prototype/App/TrackpadGestures.swift`（旁听手势）、`prototype/App/HabitKeys.swift`（事件钩子放在自己的线程、回调 O(1)）、
   `prototype/App/PeripheralBatterySource.swift`（IOKit 匹配通知）、`prototype/Private/`（私有接口集中放这里）。

硬规则：

- **默认关，开了才拦截。**任何会改写或吞掉事件的钩子，都只在对应设置打开、并且对应设备连着时安装。
  回调里只做 O(1) 的事：不分配大对象、不做辅助功能查询、不打日志。收到 `tapDisabledByTimeout` 或 `tapDisabledByUserInput` 时，
  退回到不改写的状态，并记一次状态，供设置页显示。
- **点一下照常。**判不准是“点”还是“拖”、是手势还是普通操作时，原样放行。
- **不占系统手势。**妙控鼠标的两指轻点两下、两指左右扫，妙控板的三指拖移、四指扫，一个都不能接管。
- **不拷代码。**Mos（CC BY-NC）、Mac Mouse Fix（MMF License）、GPL 项目的代码一行都不能拷，算法独立写。
  MIT 项目（siri-remote-keyboard、VibeRemote、itsytv-core）的代码可以用，必须在文件头写明来源和版权。沙箱不能联网时，只按规格里写出的事实来写。
- **纯逻辑放 `prototype/Core/`**：只依赖 Foundation，时间由调用方传入。测试照 `tests/ConductorGestureTests.swift` 的写法，
  每个包配一个 `tests/run-xxx-tests.sh`。测行为，不要写复述实现的测试。
- **App 层改动**必须跑 `cd prototype && ./build.sh --check`，它要跑十几分钟。不要跑不带 `--check` 的构建，不签名，不碰 `/Applications`。
- **不提交、不推送、不删文件。**除了本包点名的文件，不改别的；要改别处，先停下说明理由。
- **不许假装成功。**没跑的就写没跑；需要真机的写“需要真机”；不许为了让测试过而放宽断言。

交付报告的格式：

```text
做了什么：（一段话）
改了哪些文件：（列表）
跑了什么检查、结果：（命令 + 末尾输出，原样贴）
规格里哪几行已覆盖、哪几行没覆盖：（逐行）
需要真机 / 主模型决定的：（列表）
```

---

## I1：纯逻辑（Core）

新文件都放 `prototype/Core/`，每个配测试和 run 脚本：

1. **`SmoothScroll.swift`：平滑滚动插值器。**
   - 输入：一格滚轮（方向、时间）。输出：每一帧要发出的连续滚动量。
   - 用临界阻尼弹簧：一格就是把目标往前推一格的距离，帧函数推进位置和速度。
   - 三档“轻 / 中 / 像触控板”，用的是不同的响应时间和每格距离。
   - 必须测到：
     - 同向连续几格时，目标累加，速度连续，没有回弹；
     - 反向一格时立刻转向，不先把上一段滑完；
     - 收敛后输出为 0，并报告“滑完了”，让调用方停掉帧回调；
     - 每帧输出的总和等于目标距离，误差小于 0.5 点；
     - 帧间隔不均匀（掉帧）时，总量也不变。
2. **`InputDeviceKind.swift`：设备分类。**
   - 根据滚动事件的字段（是否连续、有没有动量阶段）和 IOHID 的厂商号、产品号，判断事件来自滚轮鼠标、妙控鼠标还是触控板。
   - 产品号表只放规格里确认过的：Siri 遥控器第三代 `0x0315`；这台 Mac 上的妙控鼠标 `0x0323`。其余的标“待真机确认”，不要猜。
3. **`MiddleDrag.swift`：中键拖动识别。**
   - 按下后，移动超过 10 点才算拖，否则抬起就是点。
   - 拖动分两种情况：在标题栏上，转成和触控板标题栏手势同样的“上推 / 下拉 / 左右”意图；在别处，转成“调度中心 / App 窗口 / 换桌面”意图，并带上跟手的进度（0…1）。
   - 测到：点、短拖、斜拖、来回拖、中途松开回到原处。
4. **`TouchTap.swift`：多点触摸轻点识别。**
   - 输入是一帧帧触点（手指编号、位置毫米、大小、阶段）。输出是三指轻点、四指轻点、妙控鼠标“两指按下”状态。
   - 规则：几乎同时落下（150 毫秒内）、0.25 秒内全部抬起、每根手指位移小于 1.5 毫米、触点大小超过阈值（手掌）的整次作废。
   - 测到：三指轻点、四指轻点、三指拖移（不算）、两指落一指抬（不算）、手掌（不算）、四指里先落三指（算四指，不先报三指）。
5. **`SiriRemoteButtons.swift`：Siri 遥控器按键归一。**
   - 把 HID 用法（`0x0C/0x42`…`0x45` 环、`0x0C/0x80` 中心、`0x01/0x86` 返回、`0x0C/0x60` 电视、`0x0C/0xCD` 播放暂停、
     `0x0C/0xE2` 静音、`0x0C/0xE9`/`0xEA` 音量、`0x0C/0x04` 侧边 Siri）变成带“按下 / 松开 / 按住满 0.5 秒 / 按住满 1 秒”的按键事件。
   - 测到：短按、长按、两键几乎同时、松开丢失（断开时合成取消）。
6. **`RemoteMode.swift`：遥控模式状态机。**
   - 输入是按键事件，输出是规格“Siri 遥控器”表里遥控模式那一列的动作。
   - 按住播放键 1 秒切换到指挥模式，此后的事件交给已有的指挥模式状态机（`ConductorSession`，如果还没有，就留一个接口），不自己处理。

## I2：MultitouchSupport 桥 + 两个轻点手势 + 妙控鼠标中键（App 层）

- 新文件 `prototype/Private/MultitouchBridge.swift`，用 `dlopen` 加载 `/System/Library/PrivateFrameworks/MultitouchSupport.framework`。
  要用的函数：`MTDeviceCreateList`、`MTDeviceGetFamilyID`、`MTDeviceIsBuiltIn`、`MTDeviceGetSensorSurfaceDimensions`、
  `MTRegisterContactFrameCallback`、`MTDeviceStart`、`MTDeviceStop`、`MTUnregisterContactFrameCallback`。
  触点结构体的内存布局按公开的逆向资料来写，并在注释里写明来源；拿不准的字段不要用。
  框架或符号不存在时，整个功能安静关闭，不能崩。
- 回调在框架自己的线程上来：在那里只把触点帧交给 I1 的 `TouchTap`，结果用一次轻量的派发送到主线程。
- 三指轻点：在指针位置合成一次中键点按。四指轻点：打开刘海那一排（找到已有的入口调用，不新写一套）。
  妙控鼠标两指按下时左键按下：改写成中键。这一条需要主动钩子，照总则“默认关”。
- 设备插拔：用 IOKit 匹配通知重新枚举，不轮询。
- 检查：`./build.sh --check`。报告里写清楚 Aaron 在真机上怎么试。

## I3：主动滚动钩子（App 层）

- 新文件 `prototype/App/ScrollTap.swift`。只在“平滑滚动”或“滚动方向分开”开着、并且连着滚轮鼠标时，安装 `CGEvent.tapCreate`（`.cgSessionEventTap`、`.headInsertEventTap`）。
- 只改滚轮来的事件（用 I1 的分类判断）：
  - 方向分开：把数值取反；
  - 平滑滚动：吞掉原事件，交给 I1 插值器，按屏幕刷新逐帧发出连续滚动事件，并带上合适的阶段字段，滑完就停。
- ⌥ 精细：一格一行。侧键 4 / 5：变成后退、前进，规格只说“该 App 的后退、前进”；先用 ⌘[ / ⌘]，并在报告里列出哪些常见 App 不认。
- 让位：检测到 Mos（`com.caldis.Mos`）、Mac Mouse Fix（`com.nuebling.mac-mouse-fix` 及其 helper）、BetterTouchTool、Logi Options+、SteerMouse 在运行，就不装钩子。
  bundle id 拿不准的，在报告里标出来。
- 按 App 例外：前台 App 在例外名单里时原样放行。
- 检查：`./build.sh --check`，加 I1 的测试。

## I5：Siri 遥控器（App 层）

- 新文件 `prototype/App/SiriRemoteSource.swift`：用 IOHIDManager 匹配 Apple 厂商号加遥控器产品号，读按键交给 I1 的 `SiriRemoteButtons`。
- 让系统不再处理遥控器按键：只在遥控模式打开时，用 `hidutil property --matching '{"ProductID":…,"VendorID":…}' --set '{"UserKeyMapping":[…]}'`，
  把这台遥控器的用法映射成“无事件”。每次匹配到设备都重新套上；功能关闭或 App 退出时恢复原样。只作用于这台遥控器，不碰别的键盘。
- 电量：遥控器如果出现在 `AppleDeviceManagementHIDEventService` 里，就交给已有的设备电量那条线；名字写“Siri 遥控器”。
- 触控面（指挥模式要用）和麦克风（`0xFA`）不在这个包里，由主模型做。
- 检查：`./build.sh --check`。报告写清楚：Aaron 要先把遥控器配到 Mac（按住返回加音量加 5 秒，再到系统设置的蓝牙里连接）；
  配到 Mac 后，它会和 Apple TV 解除配对。

## I7：设置与文案（App 层）

- 照 `prototype/App/Preferences.swift` 已有的分组卡片，加两栏：
  - “鼠标与触控板”：平滑滚动（关 / 轻 / 中 / 像触控板）、鼠标和触控板滚动方向各一个、⌥ 精细、侧键后退前进、中键收起窗口、三指轻点是中键、四指轻点打开看不见的窗口、例外的 App；
  - “遥控器”：已连上的 Siri 遥控器、遥控模式开关、iPhone 上的遥控器（链接到指挥模式那一栏）。
- 每一项默认关。被别的工具接管时，副标题写“由 Mos 接管”这样的话。
- `docs/copy-guide.md` 的固定词汇表里补这些词：平滑滚动、滚动方向、中键、遥控模式、Siri 遥控器、iPhone 上的遥控器。
- 把规格“隐私登记”一节的四行，登记进隐私一栏的登记表（没有登记表就在报告里写明）。
- 检查：`./build.sh --check`。

## I8：DualSense（App 层）

- 新文件 `prototype/App/GamepadSource.swift`。只用 GameController 公开接口：`GCController` 的连接与断开通知、`GCDualSenseGamepad`
  （按键、摇杆、`touchpadPrimary` / `touchpadSecondary` / `touchpadButton`、`adaptiveTriggers`）、`GCDeviceLight`、`GCDeviceHaptics`、`GCDeviceBattery`。
  设 `GCController.shouldMonitorBackgroundEvents = true`，WindowShade 在后台也能收到输入。不用私有接口，不用 IOHID 读手柄。
- 纯逻辑放 `prototype/Core/GamepadMapping.swift`，配测试：
  - 摇杆：死区、加速度曲线，输出指针速度；
  - 右摇杆滚动：交给 I1 的平滑滚动；
  - 触控板：一指转指针，两指转滚动；两指在标题栏上转成标题栏手势意图；
  - L2 / R2 换桌面：按下深度 0…1，过 0.6 才换，松开时没过就回原处；
  - 键位表照 `docs/input-devices.md` 的“PS5 手柄”一节。PS 键不占。
- 游戏让开：前台 App 的 `LSApplicationCategoryType` 以 `public.app-category.` 开头并且是游戏类，或者在例外名单里时，不读、不改手柄，也不震动。
- 自适应扳机：只在“换桌面”这个功能开着时，给 L2 / R2 设一道阻力（用公开的 trigger 模式；参数在报告里写清楚）；关掉功能、手柄断开、游戏到前台时，恢复成无阻力。
- 灯条和触感按规格的写法做；触感只在吸附、确认、过那道“咔”时出现，不在每次指针移动时震。
- 每台手柄有自己的“控制这台 Mac”开关，默认关。电量交给设备电量那条线。
- 检查：`./build.sh --check`，加纯逻辑测试。报告里写清楚：这台 Mac 现在没连手柄，Aaron 怎么真机试。

## I9：焦点导航（先纯逻辑，界面由主模型接）

- 新文件 `prototype/Core/FocusNavigator.swift`，配测试。输入：一组可聚焦的格子（位置矩形、能否聚焦、所在分组），以及一个方向（上下左右）。
  输出：下一个焦点。
- 规则照 tvOS 焦点引擎的常识：沿方向找最近、重叠最多的格子；到边上不绕回（可配置为绕回）；分组之间先在组内走，走到头再跨组；
  记住每组上次的焦点，回来时回到那一格。
- 测到：网格、参差不齐的行、空格、只有一格、跨组、回到上次的那一格。
- 界面这一步不做，留给主模型：把它接到刘海那一排、启动台、窗口浏览、按窗口切换上，亮起的格子放大一点、带视差。
