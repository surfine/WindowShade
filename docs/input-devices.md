# 鼠标、触控板与遥控器：整合 Mos、Mac Mouse Fix 与 Siri 遥控器

2026-10-03。Aaron：“请你尝试将 Mos 和 Mac Mouse Fix 这两者的功能给整合进来，满足之前‘给 Magic Mouse 和 Magic Trackpad 用户惊喜’的要求，
并且适配 Apple TV Remote（参考 Remote Buddy 和 Itsytv 并且寻找开源实作）。”
随后：“顺便把 PS5（DualSense）手柄纳入适配范围，我们 WindowShade 2 要博采众长，取长补短，自成一体，为 macOS 提供 iPadOS 般的一站式、直觉和简单的体验。”

“之前的要求”指 9 月 25 日那句：“我希望给 Magic Mouse 和 Magic Trackpad 用户一点惊喜，手势可以更完备一些，当然你要避免误触。”

- 设计稿（可交互）：[手边的每一样](https://claude.ai/artifact/SAeiZhSezHbSqjXiSzhqDs)
- 给 DeepSeek 的提示词：[handoff/deepseek-input.md](handoff/deepseek-input.md)
- 相关：[gestures.md](gestures.md)（已有的标题栏手势）、[conductor-v2.md](conductor-v2.md)（指挥模式）、[device-battery.md](device-battery.md)、[privacy-page.md](privacy-page.md)

## 一句话

手边的每一样，用起来都比原来顺手，而且按的都是 WindowShade 那一套动作。
滚轮鼠标像触控板一样顺滑；妙控鼠标和妙控板多出中键和几个不撞车的手势；
Siri 遥控器、iPhone 上的遥控器和 PS5 手柄能在沙发上操作这台 Mac，也能指挥 Codex 和 Claude。

## WindowShade 2：自成一体

像 iPadOS 那样，一个入口、一套动作、任何输入都能用：

| 层 | 是什么 |
| --- | --- |
| 一个入口 | 刘海：看不见的窗口、实时活动、指挥模式、遥控时的焦点都在这里 |
| 一套动作 | 收起窗口、收进刘海、看一眼、侧拉、分屏、画中画、启动台、调度中心、换桌面、指挥模式。设备不同，动作相同 |
| 两种操作方式 | **指着用**（触控板、鼠标、手柄的触控板）：手势和指针；**挪焦点用**（键盘方向键、Siri 遥控器的环、手柄的十字键、iPhone 遥控器的触控区）：像 tvOS 和 iPadOS 的键盘导航，焦点在刘海那一排、启动台、窗口浏览、按窗口切换里移动，亮起的那一格放大一点、带视差 |
| 一样的反馈 | 刘海里的字、同一套弹簧；有触感的设备（触控板、DualSense）在吸附、确认时轻震一下 |

### 取长补短

| 参考 | 取 | 不取 |
| --- | --- | --- |
| Mos | 平滑滚动、轴向独立、按 App 例外 | 通用按键绑定和动作库（变成又一个 BetterTouchTool） |
| Mac Mouse Fix | 按住拖动要跟手、点一下照常 | 一屏参数；收费系统 |
| Remote Buddy | 按场景换键位、屏幕上的菜单 | 100 多个 App 的预设表 |
| Itsytv | Swift 协议零件、文字输入 | — |
| Control Box | 手柄、遥控器按设备分页，每台单独“控制这台 Mac”开关 | 显示器、夜览、音量混音这些不相干的面板 |
| InputConfig、ControllerKeys | DualSense 触控板分一指、两指；陀螺仪；游戏在前台时让开 | 宏、脚本、Webhook |
| iPadOS / tvOS | 焦点导航、指针吸附、一个入口 | — |

原则一句话：**不做配置工具，做体验。**默认值要好到不用改；能改的只有“开 / 关”和少数几档。

## 调研结论

| 项目 | 做什么 | 许可 | 我们怎么用 |
| --- | --- | --- | --- |
| [Mos](https://github.com/Caldis/Mos) | 滚轮平滑滚动（步长、增益、时长，模拟触控板）；垂直、水平分别设平滑和反向；按 App 覆盖；按键绑定与动作库；罗技 HID++ | **CC BY-NC 4.0**（非商业，且不许上 App Store） | **只借思路，不拷代码**：和 MIT 主项目不兼容 |
| [Mac Mouse Fix](https://github.com/noah-nuebling/mac-mouse-fix) | 让普通鼠标像触控板：按住按键拖动切桌面、开调度中心，跟手；平滑滚动带惯性；修饰键滚动（精细、横向、缩放）；按键改写；“Scroll & Navigate”让滚轮像两指滑。3.x 收费 | **MMF License**（自定义：衍生作品要注明来源；不得收费，且必须保留它的付费系统，除非有实质改进） | **只借思路，不拷代码** |
| [Remote Buddy](https://www.iospirit.com/products/remotebuddy/) | 用 Siri 遥控器、iPhone、红外遥控器控制 Mac：100+ App 的预设、网页视频、虚拟鼠标键盘、演示聚光灯 | 商业闭源（24.99 €） | 只看行为：按 App 切换按键含义、屏幕上的菜单 |
| [Itsytv](https://github.com/nickustinov/itsytv-macos) + [itsytv-core](https://github.com/nickustinov/itsytv-core) | 反方向：在 Mac 上遥控 Apple TV。Swift 实现 Companion Link、MRP、配对（SRP、ChaCha20）、OPACK、TLV8、**文字输入会话** | MIT（itsytv-core 的 README 标 MIT，根目录没找到 LICENSE 文件，引用前要核对） | **可以用**：Swift 写的协议零件，做“这台 Mac 冒充一台电视”时省掉 Rust |
| [atv-core](https://github.com/corvofeng/atv-core) | 让 Mac 被 iPhone 控制中心的遥控器当成电视 | 工作区声明 MIT（根目录没有 LICENSE 文件） | 服务端的参考实现；配对验证有洞（见 conductor-v2） |
| [siri-remote-keyboard](https://github.com/JackyLobsterD/siri-remote-keyboard) | 把第三代 Siri 遥控器变成 Mac 键盘：12 个按键的 HID 用法已在真机核实；侧边 Siri 键有干净的按下 / 松开；**`hidutil` 按设备改映射能让系统不再处理遥控器按键**，而 IOHIDManager 照样收到原值；触控面要用私有 MultitouchSupport 才读得到 | MIT | 可以用：按键表、静音系统的做法 |
| [VibeRemote](https://github.com/mmmmmmarcus/VibeRemote) | Siri 遥控器当键盘和麦克风：两代遥控器分别适配；**第二、三代的麦克风在独立的 `0xFA` 音频集合里**；显示遥控器电量 | MIT | 可以用：麦克风桥、电量、两代差异 |
| [Remotastic](https://github.com/lauschue/Remotastic)、[Control Box](https://github.com/whitesticker/controlbox) | Siri 遥控器当指针、滚动、按键映射 | MIT | 参考 |
| [InputConfig](https://github.com/ryleighnewman/InputConfig)、[mac-dualsense](https://github.com/sour4bh/mac-dualsense) | DualSense、Xbox、Switch Pro 等映射成键盘鼠标（GameController 框架） | MIT | 可以用 |
| [ControllerKeys](https://github.com/NSEvent/xbox-controller-mapper) | 300 多种手柄映射；DualSense 触控板、陀螺仪、滑动打字 | PolyForm Noncommercial | 只借思路 |
| [dualsense-controller-mapper](https://github.com/aklmans/dualsense-controller-mapper) | 手柄控制 Mac、vibe coding | Source Available（非开源） | 只借思路 |
| [SiriRemoteForge](https://github.com/HOLODATA-COM/SiriRemoteForge)、[codex-siri-remote-with-pad](https://github.com/alfred-bot-001/codex-siri-remote-with-pad) | 可编程的 Siri 遥控器（按 App 分层、触控面手势、实验性虚拟麦克风）；用遥控器控制 Codex 桌面版 | GPL-3.0 | **只借思路，不拷代码** |

按键用法（siri-remote-keyboard 在第三代 Siri 遥控器上实测的结果）：

| 键 | HID 用法 |
| --- | --- |
| 环上 / 下 / 左 / 右 | `0x0C/0x42` `0x43` `0x44` `0x45` |
| 环中心 | `0x0C/0x80` |
| 返回 | `0x01/0x86` |
| 电视键 | `0x0C/0x60` |
| 播放 / 暂停 | `0x0C/0xCD` |
| 静音 | `0x0C/0xE2` |
| 音量加 / 减 | `0x0C/0xE9` `0xEA` |
| 侧边 Siri 键 | `0x0C/0x04` |

另外两条：Siri 遥控器连到 Mac 后，会和 Apple TV 解除配对；`hidutil` 的映射重启、唤醒、重连后会失效，每次匹配到设备都要重新套上。

**这台 Mac 上实测**（2026-10-03，只读脚本，没有注册回调）：MultitouchSupport 列出 2 台设备。
一台是内建触控板（family 114，表面约 14.3 × 8.5 厘米）；另一台是外接设备（family 112，表面约 5.2 × 9.1 厘米），就是连着的妙控鼠标
（IOKit 里 Apple 产品号 0x0323，电量 100%）。也就是说，读妙控鼠标表面上的手指这条路，在这台 Mac 上走得通。
这台 Mac 现在没有连普通滚轮鼠标和 Siri 遥控器，这两类要 Aaron 接上才能验证。

## 五条原则

1. **默认不接管。**WindowShade 现在对输入只旁听、不拦截。平滑滚动、按键改写必须拦截并改写事件，所以全部默认关闭。
   按设备类型分别开；开了才装主动的事件钩子，回调里只做 O(1) 的事。钩子被系统因超时停掉时，自动退回不改写。
2. **按设备认，不按名字认。**滚轮鼠标、妙控鼠标、妙控板、Siri 遥控器、iPhone 上的遥控器，各有一组设置。
   设备身份照电量那条线的做法：按稳定 ID。滚动事件按 `isContinuous` 等字段分辨来自滚轮还是触控面。
3. **一套动作。**所有设备最后触发的，都是 WindowShade 已有的动作：收起窗口、收进刘海、看一眼、刘海那一排、启动台、调度中心、换桌面、指挥模式。
   不另起一套动作库，不做“打开脚本”这类通用自动化。
4. **让位。**检测到 Mos、Mac Mouse Fix、BetterTouchTool、Logi Options+、SteerMouse 在运行，就把对应功能让给它们，在设置里写明“由 Mos 接管”。
   这和 Dock 手势遇到 Swish 时让位是同一个做法。
5. **许可干净。**Mos、Mac Mouse Fix、GPL 项目都只借思路，算法独立写。MIT 项目的代码可以用，但要带版权声明。

## 按设备

### 普通滚轮鼠标（来自 Mos、Mac Mouse Fix）

| 功能 | 怎么用 | 规则 |
| --- | --- | --- |
| **平滑滚动** | 设置里打开；三档：轻、中、像触控板 | 每一格变成一段带惯性的滑动，用临界阻尼弹簧插值（独立实现）；对方向变化立即响应；按 App 例外（游戏、设计软件默认例外，可改） |
| **滚动方向分开** | 鼠标、触控板各选一个方向 | 系统把两者绑在一起，这里只改滚轮来的事件。这一项对妙控鼠标也有用 |
| 精细滚动 | 按住 ⌥ 滚 | 一格只走一行 |
| 后退 / 前进 | 侧键 4 / 5 | 变成该 App 的后退、前进；不认的 App 原样放行 |
| **标题栏上点中键** | 点一下 | 收起窗口，再点展开（和双击标题栏同一个动作，少按一下） |
| **按住中键拖**（Mac Mouse Fix 的点按拖动） | 在标题栏上：上推收起、下拉铺满、左右半屏，和触控板标题栏手势同一套，有同一块提示浮窗；在别处：上拖调度中心、下拖 App 窗口、左右拖换桌面，跟手 | 换桌面、调度中心照触控板的手势事件一步步合成，所以跟手、有过程；只在按住中键拖过 10 点以后才开始，点一下照常是中键 |

### 妙控鼠标（表面触点，经 MultitouchSupport）

| 功能 | 怎么用 | 规则 |
| --- | --- | --- |
| **中键** | 两根手指都放在表面上时按下 | 点开链接到新标签、关标签；一根手指按下照常是左键。要在按下那一刻改写成中键，所以属于“默认不接管”，开了才拦截 |
| 标题栏上收起 | 两指按下标题栏 | 和滚轮鼠标的中键同一个动作 |
| 滚动方向分开 | 同上 | — |
| 标题栏手势、甩一下收进刘海 | 已有 | 补真机验证（现在写着“没在真机上验证过”） |
| 电量 | 已有 | — |

不碰系统已有的手势：单指轻点两下智能缩放、两指轻点两下调度中心、两指左右扫全屏 App。

### 妙控板（表面触点，经 MultitouchSupport）

| 功能 | 怎么用 | 规则 |
| --- | --- | --- |
| **中键** | 三指轻点 | 系统默认不用三指轻点；“查询与数据检测器”设成三指轻点时让给它，设置里写明 |
| **看不见的窗口** | 四指轻点 | 打开刘海那一排；系统没有用四指轻点 |
| 从 Windows 来的人 | 三指下滑（Windows 里是显示桌面） | 刘海提示一次 Mac 上怎么做（卡住时提示那一套），不改系统手势 |
| 已有的惊喜 | 拐角占一角、捏合撤销、甩一下收进刘海 | 已有 |

轻点只认：所有手指几乎同时落下、0.25 秒内抬起、位移小于 1.5 毫米；手掌（大触点）不算。

### Siri 遥控器（实体，蓝牙连 Mac）

| 键 | 遥控模式（沙发上操作 Mac） | 指挥模式 |
| --- | --- | --- |
| 环 上下左右 | 在刘海那一排、启动台、窗口浏览里挪焦点 | — |
| 环中心 / 点按触控面 | 打开 | 确认 |
| 触控面滑动 | 可选：当指针用 | 画声调、打拍子（原始触点经 MultitouchSupport） |
| 返回 | 退一层；收起展开的刘海 | 取消 |
| 电视键 点一下 / 按住 | 启动台 / 刘海那一排 | 换档位与模型 / 选会话 |
| 播放 / 暂停 | 媒体播放暂停（系统） | 发出去 / 停下 |
| **按住播放键 1 秒** | 换到指挥模式 | 换到遥控模式 |
| 侧边 Siri 键 按住 | 听写到当前输入框 | 说话（**用遥控器自己的麦克风**，`0xFA` 音频集合） |
| 音量、静音 | 系统音量、静音 | 系统音量；静音键管提示音 |
| 电源 | 让显示器睡眠 | 退出指挥模式 |

- 指挥模式最没把握的两件事（拿到原始轨迹、能按住说话）在实体遥控器上都有现成的路：触控面走 MultitouchSupport，麦克风走 `0xFA`。
  所以实体 Siri 遥控器可以先于 iPhone 那条路跑通。
- 遥控器连上、电量低，接进设备电量那条线（“Siri 遥控器电量低”）。
- 设置里写明：配到 Mac 后，它会和 Apple TV 解除配对。

### iPhone 控制中心里的遥控器

同上表的两种模式，键位照 [conductor-v2.md](conductor-v2.md)。协议层改为**优先用 Swift**：
配对、加密、OPACK、TLV8、文字输入会话用 itsytv-core 的零件（MIT）从客户端反过来写服务端，atv-core 只当参考。这样不再需要 Rust 工具链。

### PS5 手柄（DualSense）

全部用 Apple 公开的 GameController 框架（`GCDualSenseGamepad`，macOS 11.3 起）：按键、摇杆、**触控板两个触点的位置**、自适应扳机、灯条、
触感（`GCDeviceHaptics` 接 Core Haptics）、电量（`GCDeviceBattery`）、陀螺仪。要在后台收到输入，设 `GCController.shouldMonitorBackgroundEvents`。不用私有接口。

| 键 | 操作 Mac | 指挥模式 |
| --- | --- | --- |
| 左摇杆 | 指针（死区、加速度，靠近按钮时吸附） | — |
| 右摇杆 | 滚动（走平滑滚动） | — |
| 触控板 一指 / 两指 | 像触控板：指针 / 滚动；两指在标题栏上 = 标题栏手势 | 画声调、打拍子（公开接口直接给坐标） |
| 按下触控板 | 点按；两指按下 = 右键 | 确认 |
| 十字键 | 挪焦点（刘海那一排、启动台、窗口浏览、按窗口切换） | — |
| × | 打开 / 点按 | 确认 |
| ○ | 返回；收起展开的刘海 | 取消 |
| □ | 右键（更多） | 换档位与模型 |
| △ | 看不见的窗口（刘海那一排） | 选会话 |
| L1 / R1 | 按窗口切换：上一扇 / 下一扇 | — |
| L2 / R2 | 换桌面，按到一半有一道“咔”（自适应扳机给阻力，过了那道就换），松开回原处 | R2：发出去 / 停下 |
| Options | 启动台 | 换到操作 Mac |
| 创建 | 截屏（系统的 ⇧⌘5） | — |
| 静音键 按住 | 说话（USB 连接时用手柄的麦克风，蓝牙时用 Mac 的麦克风；要实验） | 说话 |
| PS 键 | **不占**，留给系统 | 不占 |

- **游戏在前台时整个让开**：前台 App 是游戏（App 分类为游戏，或它自己在用 GameController）时，WindowShade 不读、不改手柄。
- 灯条和触感：指挥模式时灯条是指挥模式的粉；录音时变红；电量低时琥珀色。焦点移动轻震一下，半屏吸附、换桌面过了那道“咔”时扳机和手柄各震一下。
- 电量接进设备电量那条线（“手柄电量低”）。
- 每台手柄有自己的“控制这台 Mac”开关，默认关；同时连几台时，只有第一台开着的能操作。

### 反方向：在 Mac 上遥控 Apple TV（Itsytv 的做法）

可选，排在最后。家里的 Apple TV 正在播放时，刘海里多一项实时活动：片名、进度、播放暂停。
展开后可以在 Mac 上打字，填进电视上的输入框。协议用 itsytv-core。

## 隐私登记（进 privacy-page 登记表）

| 行 | 层 |
| --- | --- |
| 滚轮和鼠标按键（开了平滑滚动或改写时才拦截、改写；不存） | 你同意后才读的（辅助功能、输入监控） |
| 妙控鼠标、妙控板表面上的手指位置（开了中键或轻点手势时才读；不存） | 用了系统没公开的方法的（MultitouchSupport） |
| Siri 遥控器的按键、触控面、麦克风（按住 Siri 键时才录；转写后丢弃） | 你同意后才读的 + 系统没公开的方法 |
| 手柄的按键、摇杆、触控板、陀螺仪（“控制这台 Mac”开着时；游戏在前台时不读） | 不用问就能读的（GameController） |
| 遥控器的配对密钥 | 存在这台 Mac 上（钥匙串） |

## 能耗与延迟

- 主动的滚动钩子只在“平滑滚动”或“方向分开”开着、并且连着滚轮鼠标时装上；拔掉鼠标就拆。
- 平滑滚动的插值跟屏幕刷新走，滑完就停，空闲时不留定时器。
- MultitouchSupport 的回调只在对应功能开着时注册；回调里只做轻点和两指按下的判断，不分配内存。
- 目标：回调里耗时 p99 小于 0.2 毫秒（实测前不写进宣传）；空闲 CPU 和唤醒次数不比 1.0.15 高。

## 做的顺序

| 步 | 做什么 | 谁 | 算完成 |
| --- | --- | --- | --- |
| I1 | 纯逻辑：平滑滚动插值器、设备分类、中键拖识别、多点轻点与两指按下识别、Siri 遥控器按键归一（带按下 / 松开）、遥控模式状态机 | DeepSeek | 单测覆盖本页每个表的每一行 |
| I2 | MultitouchSupport 桥（只读触点，放 `Private/`）+ 妙控板三指 / 四指轻点 + 妙控鼠标两指中键 | DeepSeek 写，主模型复核 | `./build.sh --check`；Aaron 真机试 |
| I3 | 主动滚动钩子：平滑滚动、方向分开、⌥ 精细、侧键；让位检测 | DeepSeek 写，主模型复核 | 超时被停时自动退回；接上滚轮鼠标真机试 |
| I4 | 中键：标题栏点按收起，按住拖动接标题栏手势；别处拖动合成调度中心、换桌面手势 | 主模型 | 跟手；不吞普通中键 |
| I5 | Siri 遥控器：IOHIDManager + `hidutil` 静音系统、两种模式、电量 | DeepSeek 写，主模型复核 | Aaron 配一个遥控器真机试 |
| I6 | Siri 遥控器麦克风（`0xFA`）、触控面接指挥模式 | 主模型 | 真机 |
| I7 | 设置：“鼠标与触控板”“遥控器”两栏；copy-guide 补词；隐私登记 | DeepSeek | 文案照 copy-guide |
| I8 | DualSense：操作 Mac、游戏让开、自适应扳机的“咔”、灯条与触感、电量 | DeepSeek 写，主模型复核 | 真机试（这台 Mac 现在没连手柄） |
| I9 | 焦点导航：刘海那一排、启动台、窗口浏览、按窗口切换都能用方向键 / 环 / 十字键挪焦点 | DeepSeek 写纯逻辑，主模型接界面 | 键盘就能验收 |
| I10 | Mac 遥控 Apple TV（实时活动） | 以后 | — |
