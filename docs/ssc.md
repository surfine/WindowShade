# Swift Student Challenge：规则、差距和参赛方案

2026-09-29 查证。Aaron 打算让 WindowShade 参加 Swift Student Challenge（下称 SSC），
方向见 [direction.md](direction.md)。这一页回答三件事：规则怎么说，现在的 WindowShade 哪里对不上，参赛作品该长什么样。

> **Aaron 的定位（2026-09-29）：** 参加 Swift Student Challenge 是让我们“代入角色、入戏”的标准——按 Apple 的价值观和品味去做 WindowShade，
> 不是眼下要准备的一次真实提交。资格和“本人独立完成 / AI 工具”那几条不作为约束（“到了 2027 年哪有人不用 AI 编程的，新的一年有新的做法”）；
> 真要提交时再对照当年条款。下文的规则整理留作参考，第 4 节的价值观对照才是现在要用的。

## 先说结论

- **2027 年的规则还没发布。** 条款页标题仍是 2026 年版，截止日还是 2026-02-28；概览页没有 2027 年的日期；
  Apple 开发者新闻的 RSS 最新一条是 2026-09-18，最后一条 SSC 公告是 2026-02-06 的开放提交。下面的规则都只对 2026 届有效。
- **现在的 WindowShade 不能直接交。** 比赛只收 app playground（.swiftpm），离线评审，三分钟内体验完，全英文。
  WindowShade 是 AppKit 写的菜单栏程序，靠辅助功能、事件监听和屏幕录制控制别的 App，界面全是中文。
- **最大的风险是 AI。** 2026 年规则允许 AI 协助具体任务，但要全部披露，并要求作品由本人独立完成、体现本人的实质贡献和技术理解。
  现有代码大部分由 Claude、Codex、DeepSeek 写成，直接搬进参赛作品风险最高。
- **能交的是一个新写的、自成一体的 playground**：在 iPad 屏幕上画一台带刘海的 MacBook，让评委三分钟里体验“卡住时刘海教你 Mac 的做法”。
  由 Aaron 亲手写，WindowShade 是设计来源和背景故事。
- **题目本身很对路。** 帮 Windows / iPad 用户上手 Mac，对得上评审的“社会影响或包容性”，也对得上 Apple 自己的“Mac does that.”换机叙事。
  差距主要在态度：WindowShade 近来搬了很多别家的做法，这和“教 Mac 的做法”、和 Liquid Glass 的“一眼就熟悉”是反的。

## 1. 规则要点（2026 届；2027 届未公布）

规则原文是英文，下面是忠实转述。需要逐字核对时直接看链接里的原页面。

**来源**

- 条款：https://developer.apple.com/swift-student-challenge/policy/ （标题 “Swift Student Challenge 2026 Terms and Conditions”；旧链接 /terms/ 已经 404）
- 资格与要求：https://developer.apple.com/swift-student-challenge/eligibility/
- 概览：https://developer.apple.com/swift-student-challenge/
- 准备：https://developer.apple.com/swift-student-challenge/get-ready/
- 杰出获奖者：https://developer.apple.com/swift-student-challenge/distinguished-winners/
- 2024、2025 年条款用 Wayback 快照核对（20240205200059、20250220213426）；2026 年条款比对了 2025-11-24、2026-02-04、2026-03-13 和现在的线上版。

### 作品形式

| 项目 | 2026（现行） | 往年变化 |
| --- | --- | --- |
| 格式 | ZIP 包里放一个 app playground（.swiftpm） | 三年一样 |
| 大小 | ZIP 不超过 25 MB | 三年一样 |
| 工具 | 用 Swift Playground 4.6 或 Xcode 26 及以上构建并运行；可以用 Apple Pencil | 2024：Swift Playgrounds 4.4 或 Xcode 15；2025：Swift Playground 4.5 或 Xcode 16 |
| 联网 | 不能依赖网络，资源全放进 ZIP，离线评审；可以用设备端的 Apple Intelligence 框架和其他 Apple 技术 | 设备端 Apple Intelligence 这句是 2026 年新加的 |
| 时长 | 三分钟内能体验完 | 2024、2025 写的是“三分钟内体验完一个互动场景”；“用模板起步”一句在 2025-11 前删掉，“互动场景”到 2026-02 才删掉 |
| 语言 | 条款：全部内容必须是英文 | 2024 条款写 should，2025 起改成 must；资格页至今仍写 should，以条款为准 |
| 数量 | 每人只能交一个 | 三年一样 |

准备页给的新建路径是 Xcode 里 Create New Project > iOS > App Playground，或者 Swift Playground 里 Create New App。
准备页还专门引导参赛者学怎样用 Liquid Glass 做出令人愉悦的应用，并介绍了 Xcode 26 的生成式智能。

以下情形不予考虑（三年基本一致）：评审时运行不起来；需要登录；用分析代码追踪评委；不是本人做的或多人做的；抄袭；
和以前交过的作品几乎一样。2024 年条款还要求作品“完整可用”，2025 年删掉了。

### 参赛资格

- **身份**：不能是全职开发者；要在 Apple 注册为开发者（免费即可）或加入 Apple Developer Program。
- **学籍**（提交时满足其一）：在读，或 90 天内毕业于经认证的学校、官方认可的家庭教育或 Apple Developer Academy；
  正在参加非营利 STEM 组织的课程；高中毕业不满 6 个月、正在等待或已经收到录取。
- **证明**：上传课表或在读证明（PDF、PNG 或 JPEG，要显示姓名、学校和有效日期），并填写校长或院长的联系方式。
- **年龄**：按国家或地区划分，中国大陆 14 岁起。年龄不够的，可以由监护人发邮件到 swiftstudentchallenge@apple.com 申请。
- **排除**：法律禁止的地区无效；Apple 员工、实习生、关联方及其直系亲属和同住者不能参加。
- **获奖次数**：最多 3 次，杰出获奖者只能当一次。2024、2025 年是 4 次。

### 个人完成、原创和 AI

- **个人完成**：作品必须完全由本人独立创作，或在 Swift Playground 模板上完全由本人独立修改。团队作品不予考虑。（2024–2026 措辞基本一致）
- **抄袭**：2024 年条款已经写明抄袭作品不予考虑、可能被禁止以后参赛。2025 年起单独成句，加上“非常重视”，并把**设计层面**的抄袭也算进去。
- **开源和素材**：可以用第三方开源代码、公有领域的图片和声音，但要注明出处、说明为什么用，并遵守许可和版权义务；盗用可能被取消资格或撤销奖项。
- **书面回答**：提交表单上所有必答题，都要交本人写的短文。题目在提交时才能看到，不公开。
- **AI 规则每年都在变**：
  - 2024：条款把“用 AI 工具创作的作品”和团队作品并列为不予考虑，取消资格条款里也写了“用 AI 工具构建”。
  - 2025：条款里没有 AI 文字。Apple DTS 工程师 Quinn 在论坛回答“能不能用 ChatGPT/Claude”时说可以，但要披露，提交表单里有专门的说明
    （提问者的前提是“主要代码由我们自己写”）。存档：https://web.archive.org/web/20250313231922/https://developer.apple.com/forums/thread/774117
  - 2026：条款在 2026-02-04 到 2026-03-13 之间加进一段 AI 条款。AI 可以协助项目里的具体任务，
    “provided that all usage is fully disclosed”；同时要求参赛者通过作品体现本人的实质贡献、对自己 app playground 的技术理解，
    以及解决问题、方案影响、创造力、用户体验与设计、恰当使用工具和技术这些能力。
  - 披露的具体问题在需要登录的提交表单里，没有公开。

### 评审

- **概览页**：获奖者按创新、创意、社会影响**或**包容性上的卓越表现选出，突出一项即可；再从中选出杰出获奖者。
- **条款**：看三样——作品的技术成就、创意、书面回答的内容。评分保密，不给反馈。
- **评审环境**（官方页面没写，来自 Quinn 在论坛的回答）：
  - 2025-02：Xcode 做的 app playground 计划在模拟器里评审。https://developer.apple.com/forums/thread/773530
  - 2026-02：提交表单写着 Xcode 做的 app playground 在 Simulator 里运行，但没写是 iPad 还是 iPhone；他建议两种都适配，
    否则在 Comments 里注明。https://developer.apple.com/forums/thread/815941
  - 2026 届时 Swift Playground 4.6 不支持 iOS 26 SDK，他建议用 Xcode 26 并在模拟器里运行；4.7 在 2026-03-17 发布，已经赶不上。
    https://developer.apple.com/forums/thread/812429
  - 用 Swift Playground 交的作品在 iPad 上还是 Mac 上评审，没有说明。

### 时间线和奖项

- **2026 届**：2025-11-06 宣布开放时间（https://developer.apple.com/hello/november25 ）；2026-02-06 开放（https://developer.apple.com/news/?id=f0xw4t5r ），
  2026-02-28 23:59 PST 截止；2026-05-07 公布，350 名获奖者来自 37 个国家和地区，50 名杰出获奖者受邀参加 WWDC26。
- **往年**：2025 届 2024-10-08 宣布，2025-02-03 到 02-23 提交；2024 届 2024-02-25 截止。
- **2027 届（推断，不是官方消息）**：按往年节奏，大概 2026 年 10–11 月宣布，2027 年 2 月开放约三周；工具版本可能跟到 Swift Playground 4.7 以后或 Xcode 27。
- **奖项**：2024、2025 年条款写最多 350 个奖项，其中 50 个杰出获奖者；2026 年条款不再写名额和奖品。
  杰出获奖者可能受邀到库比蒂诺待三天，含差旅和住宿；未成年人须由一名监护人陪同，Apple 负担这名监护人的费用。

## 2. 和现在的 WindowShade 对不上的地方

### 作品形式：做不到的事

本机 Xcode 27 里只有一个 App Playground 模板，放在 iOS 平台下：`.iOSApplication`，默认 `platforms: [.iOS("16.0")]`，支持 iPad 和 iPhone。
Mac 上的 Swift Playground 本身是 Mac Catalyst 应用。所以参赛作品实际上是一个 iOS App：

- **没有 AppKit，没有辅助功能接口（ApplicationServices），没有 CGEvent 事件监听。** 控制别的 App 的窗口、全局按键钩子都做不到。
- **截取别的 App 窗口做不到。** iOS 27 SDK 里有 ScreenCaptureKit，但 SCWindow、SCRunningApplication、SCDisplay、SCScreenshotManager 这些都标了 iOS 不可用，
  只能通过系统选择器录制本 App 或整块屏幕。
- **没有真刘海。** 评审很可能在 iPad 模拟器里跑，没有刘海；“全屏窗口对准刘海”这类效果无从谈起。刘海只能画在我们自己画的 MacBook 屏幕里。
- **授权不现实。** 就算在 Mac 上找得到办法，让评委三分钟内去系统设置打开辅助功能和屏幕录制，几乎一定会落到“评审时运行不起来”。
- **私有接口和系统设置都碰不到**：`prototype/Private` 里的 SkyLight / Dock 接口、菜单栏图标、刘海浮层、读别的 App 的菜单，全部用不上。

### 个人完成和 AI：如实说风险

- 现有约 180 个 Swift 文件大部分由 AI 起草。规则要求作品“完全由本人独立完成”，又要求本人的实质贡献和技术理解。
  就算全部披露，“大部分代码由 AI 写”也很难说成“AI 协助具体任务”。
- 2026 年的获奖者公开说过用 Claude 学 PencilKit、实现 A* 寻路、把 App 译成 20 种语言，还有一位说技术部分依赖 AI 智能体。
  这说明披露过的 AI 协助可以获奖；但报道同时强调的是学生本人定义问题、做设计、讲得清自己的作品。不能拿来证明 AI 主导的代码也会被接受。
- git 记录里只有 Aaron 一个人类作者，“多人完成”这条不成问题。借用 WindowShade 自己的设计也不算抄袭，因为那是 Aaron 自己的作品。风险只在 AI 生成的比例和能不能讲清楚。
- 规则 2024 年禁止、2025 年沉默、2026 年允许加披露，2027 年还可能再变。

**怎么做**

1. 参赛作品由 Aaron 亲手写，不从 `prototype/` 复制代码。核心逻辑（按键和手势的判断、刘海什么时候开口）要能逐行讲清楚。
2. AI 只用来学习和做边界清楚的具体任务，比如查 API、解释报错、生成测试数据。
3. 从第一天起记 AI 使用日志：日期、工具、问了什么、用了哪些结果。提交时照着日志披露。
4. 书面回答自己写，不让 AI 代写。
5. 2027 条款一公布，就拿这一页逐条对照。

### 其他硬约束

- 全英文。App 现在有上千处中文字符串，参赛作品要从头用英文写，文案按 [copy-guide.md](copy-guide.md) 的六条规则写英文版，并补一张英文词汇表。
- 字体、图片、声音加起来不超过 25 MB。用 SwiftUI 画、SF Symbols 和渐变，很宽裕。
- 不联网、不登录、不加统计。
- WindowShade 已经公开发布，这本身不违规；规则只禁止和以前**交给 SSC** 的作品几乎一样。

### 叙事也要改

- README 和官网首屏还是“收起窗口，留下位置”“A window utility for Mac”，没提换到 Mac 的人，也没提刘海。
  历届获奖作品都先说帮谁、帮什么。
- README 里“We wrote its story”这类说法，放进个人参赛的叙事就不成立了，要改。
- 图标是一张拼好的 .icns，画了圆角、阴影和高光，图案是窗口加红绿灯。怎么做出来的在仓库里查不到；如果用了图像模型，也要披露。

## 3. 参赛作品可以长什么样

两个方案都是：iPad 横屏画一台 MacBook 屏幕，顶上有刘海，下面画一块触控板和一排键帽，给没有键盘的评委用。
刘海是唯一会说话的角色。模拟桌面里的状态全由我们掌握，“按了没反应”是确定的，不需要任何系统权限。

### 方案 A：First Week on Mac（暂名，名字由 Aaron 定）

按来处分两条路，三分钟走完一条。

1. **0:00–0:15 你从哪来。** 刘海变形成一个玻璃胶囊，问：Windows PC / iPad / Just looking。这就是欢迎窗口里那一问。
2. **0:15–1:00 手还记得旧按法。** 模拟的备忘录里有个小任务，比如把地址拷到地图里。
   - Windows 路线：按 ⌃C，什么都没发生，和真 Mac 一样。停 0.8 秒，刘海说 “On Mac, copy is ⌘C”，⌃ 键帽变成 ⌘。按对之后刘海立刻安静。
     一开始就按对的人，刘海一句都不说——这份安静就是设计。
   - iPad 路线：按 ⌘H，App 被藏起来了。刘海说 Home 是点一下刘海，点刘海，主屏幕从刘海里长出来。
3. **1:00–1:50 又卡住一次。** Windows 路线点了绿色按钮，App 进了单独的全屏空间，刘海教怎么让它铺满屏幕；
   iPad 路线在画出来的触控板上三指上推，调度中心铺开，刘海教怎么回到主屏幕。
4. **1:50–2:35 刘海是一扇门。** WindowShade 自己的玩法：收起窗口成卷帘条，停一下看一眼，朝刘海甩一下收进刘海，点刘海放回。
5. **2:35–3:00 回顾。** 一张卡片列出刚学会的几个 Mac 动作，带键帽和键名。最后一句 “The notch only speaks when you're stuck.”

教的是 Apple 真有的做法和 Apple 的官方叫法（依据 [stuck-habits.md](stuck-habits.md) 里引的 Apple 支持文档），不教 WindowShade 从 iPad、Windows 搬来的功能。

### 方案 B：一个人，一个习惯

只讲一个具体的人：比如家里刚从 Windows 换到 Mac 的长辈。三分钟只教一件事——快捷键把 Ctrl 换成 ⌘——做深做透：

- 开场十几秒讲清这个人卡在哪（一句字幕，一张画）。
- 同一个任务里让他连续碰到复制、撤销、关窗、切 App 四处旧习惯，刘海每次只在真没反应时说一句，第二次起只闪一下键帽，自己用对过的不再提。
- 结尾把刘海“认过的习惯”列出来，告诉评委这套规则怎么避免误报（比如终端里的 ⌃C 本来就有用）。

B 的技术面更窄，但每一行都容易讲清楚，书面回答也好写；故事更像历届获奖作品（一个人、一个难处）。
A 更能体现“刘海是入口”和 WindowShade 的原创玩法，但工作量和讲清楚的难度都大。可以先做 B，时间够再加 A 的第 4 步。

### 两个方案共同的做法

- **Liquid Glass 只用在刘海开口和 playground 自己的按钮上**：SwiftUI 的 `glassEffect`、`GlassEffectContainer`、`glassEffectID`（形状变形）、
  `.buttonStyle(.glass)`，都从 iOS 26 起可用。模板默认 iOS 16，要把最低版本提到 iOS 26。模拟桌面里的菜单栏和 Dock 算内容，用普通材质，不用玻璃叠玻璃。
- **手势**：用 DragGesture 的速度加弹簧动画，动画随时能被手打断。模拟器里多指手势难做，每一步都要能只靠点和拖完成；真键盘只当附加。
  宿主 Mac 会先截走 ⌘Tab、⌘Space 这类系统快捷键，哪些键能到 App 里，要先做一次按键探针再定。
- **无障碍从第一行做进去**：VoiceOver 标签和提示、字幕、Dynamic Type；“减少动态效果”时换成淡入淡出，“降低透明度”时玻璃变实色。
- **提交**：用 Xcode 做，以 iPad 横屏为主，iPhone 上也能用；在 iPad 模拟器和 iPad 上的 Swift Playground 都跑一遍；Comments 里写明 iPad、横屏。

### 和 WindowShade 本体的关系

- WindowShade 是这个点子的来历：一个真在用的 Mac 工具，让 Aaron 看到换机的人卡在哪。书面回答里可以讲，但要如实说它大量用了 AI。
- playground 不复用它的代码，只借设计：刘海开口的规则、卷帘、看一眼、甩进刘海。
- 反过来，playground 里想清楚的东西（先问来处、只在卡住时说、教 Apple 的叫法）可以带回 WindowShade。

## 4. Apple 价值观和 Liquid Glass 初衷对照

| 它说了什么 | 我们已经做到的 | 还差的 |
| --- | --- | --- |
| **无障碍**：好技术从一开始就为所有人设计（apple.com/accessibility）。2026 年 SSC 报道的标题就是 “AI meets accessibility”。 | 25 个文件设了 VoiceOver 名称，11 个文件响应“减少动态效果”，跟随“提高对比度”“降低透明度”；手势都有对应的快捷键。 | 自定义多指手势太多（张合、捏合、晃一晃、甩一下、点刘海一二三下）。HIG 建议优先用系统手势，少让人学新手势。参赛作品要把无障碍放在故事中心，不是事后补。 |
| **教育**：Apple 自己有换机页面 “Mac does that.”（apple.com/mac/mac-does-that）和《Mac tips for Windows switchers》（support.apple.com/102323）。 | [stuck-habits.md](stuck-habits.md) 按 Apple 支持文档定了“只在卡住时说”的规则，有来处分流、次数上限和不说话的清单，正是 HIG 推荐的“需要时给提示、在操作中教”。 | 欢迎页第 6 页标题“像 iPad 一样多任务”和“教 Mac 的做法”相矛盾。组合键符号 ⌃⌘⌥ 从不解释，这正是 Windows 用户最陌生的东西。 |
| **包容**：包容要从头做进去，不能事后补；HIG 要求不用没解释的术语。 | [copy-guide.md](copy-guide.md) 的六条规则和固定词汇表，和 HIG Writing、Inclusion 基本一一对应。 | 面向用户的文字里还有 niri、Swish、Rectangle 这些圈内名词。英文没有词汇表，同一个卷帘条叫 bar、strip、thin bar。App 只有中文。 |
| **隐私**：隐私是基本人权。 | 画面只在本机处理，README 写明不上传。 | 参赛作品不联网、不统计，天然满足。 |
| **环境**：Apple 2030 碳中和。 | 常驻耗电在 direction.md 里列为迷失的信号。 | 常驻的事件监听和画面捕获要继续压耗电。 |
| **Liquid Glass：一眼就熟悉**（instantly familiar）。新设计更有表现力，但不丢掉用户熟悉的东西。 | 大部分界面跟随系统外观。 | 这是最大的差距。WindowShade 近来搬了启动台、侧拉、画中画、魔法平铺、niri 卷轴、⌥Tab、晃一晃，还借用了 Apple 的功能名；双击标题栏被改成收起（系统默认是铺满或最小化），⌃⌘C 和 HIG 的标准快捷键“拷贝格式”撞了。对刚换来的人，这些都不是 Mac 的做法。 |
| **Liquid Glass：让内容更突出。** 玻璃是控件和导航那一层，不放进内容层，用得克制，避免玻璃叠玻璃（HIG Materials、WWDC25《Meet Liquid Glass》）。 | 6 个文件用系统玻璃 NSGlassEffectView，预览区用系统材质。 | 大量玻璃边框、手画高光、合盖效果，要按“用得克制”“不叠玻璃”逐个过一遍。合盖效果默认关是对的。 |
| **Liquid Glass：光学质感和只有 Apple 做得到的流动感。** 这指系统材质本身。 | 用的是系统玻璃，没自己画玻璃。 | 第三方该做的是用好系统玻璃（`.glassEffect`、`NSGlassEffectView`），不自己仿。这句话也不能改写成我们的宣传语：Apple 商标准则不允许模仿 Apple 的口号。 |
| **Liquid Glass：高光和个性化**，那句话说的是 Dock、App 图标和小组件：浅色、深色、着色、透明几种外观。 | — | 图标没有分层，画死了圆角、阴影和高光，照搬了窗口和红绿灯。HIG App Icons 要求用 Icon Composer 分层、不自带高光阴影、不照搬界面控件。要重做。 |
| **说话的方式**：HIG Writing 要求清楚、能少就少、少用“我们”、在每种设备上正确描述手势；Apple Style Guide 要求组合键第一次出现时说明。 | copy-guide 已经这么要求。 | README 首屏那段启动台说明又长又密，带着实现细节。“刘海是 Mac 的新入口”替 Apple 的硬件下定义，形态上又像灵动岛；对外可以说得谦逊些，比如“卡住时，刘海帮你一把”。 |

## 5. 要 Aaron 定的

1. **资格**：2027 年 2 月提交时，你是否在读（或毕业 90 天内），且不是全职开发者？在读证明能不能拿到？
2. **方案**：先做方案 B（一个人、一个习惯），还是直接做方案 A（两条路加刘海收纳）？
3. **主线人群**：三分钟只够讲透一条线。先讲从 Windows 来的人，还是从 iPad 来的人？
4. **WindowShade 本体**：参赛准备期间，是否把从 iPad、Windows、niri 搬来的功能改成默认关、不宣传，让本体的说法和参赛作品一致？

## 6. 出处

**SSC 官方**

- 条款：https://developer.apple.com/swift-student-challenge/policy/
- 资格与要求：https://developer.apple.com/swift-student-challenge/eligibility/
- 概览：https://developer.apple.com/swift-student-challenge/
- 准备：https://developer.apple.com/swift-student-challenge/get-ready/
- 杰出获奖者：https://developer.apple.com/swift-student-challenge/distinguished-winners/
- 2026 届开放：https://developer.apple.com/news/?id=f0xw4t5r ；Hello Developer 2025-11：https://developer.apple.com/hello/november25
- 开发者新闻 RSS：https://developer.apple.com/news/rss/news.rss
- 2024、2025 年条款：Wayback 快照 20240205200059、20250220213426（对应 /terms/ 旧地址）

**Apple 论坛（DTS 回答，不是规则）**

- https://web.archive.org/web/20250313231922/https://developer.apple.com/forums/thread/774117 （2025，AI 披露）
- https://developer.apple.com/forums/thread/773530 （2025，模拟器评审）
- https://developer.apple.com/forums/thread/815941 （2026，模拟器与设备）
- https://developer.apple.com/forums/thread/812429 （2026，Swift Playground 4.6 / 4.7）
- https://developer.apple.com/forums/thread/806582 （2026 届时间与书面题目）

**获奖报道**

- 2026：https://www.apple.com/newsroom/2026/05/ai-meets-accessibility-in-this-years-swift-student-challenge/
- 2025：https://www.apple.com/newsroom/2025/05/meet-four-of-this-years-swift-student-challenge-winners/
- 2024：https://www.apple.com/newsroom/2024/05/meet-three-swift-student-challenge-winners-changing-the-future-through-coding/

**Swift Playground**

- https://developer.apple.com/swift-playground/ （Mac 版用 Mac Catalyst 构建）
- https://developer.apple.com/swift-playground/release-notes/ （官方只写到 4.6，2025-01-31；4.7 的日期来自 App Store）

**Liquid Glass 与 HIG**

- https://www.apple.com/newsroom/2025/06/apple-introduces-a-delightful-and-elegant-new-software-design/
- https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass
- https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views
- https://developer.apple.com/design/human-interface-guidelines/materials
- https://developer.apple.com/design/human-interface-guidelines/app-icons
- https://developer.apple.com/design/human-interface-guidelines/writing
- https://developer.apple.com/design/human-interface-guidelines/inclusion
- https://developer.apple.com/design/human-interface-guidelines/keyboards
- https://developer.apple.com/videos/play/wwdc2025/219/ 、https://developer.apple.com/videos/play/wwdc2025/356/

**Apple 价值观与换机**

- https://www.apple.com/accessibility/ 、https://www.apple.com/privacy/ 、https://www.apple.com/diversity/ 、https://www.apple.com/environment/
- https://www.apple.com/mac/mac-does-that/
- https://support.apple.com/en-us/102323 、https://support.apple.com/guide/mac-help/cpmh0038/mac
- 商标准则：https://www.apple.com/legal/intellectual-property/guidelinesfor3rdparties.html

**第三方（没有官方佐证）**

- James Dale 列的 2025 年提交表单栏目（其中一栏建议写明用了哪些 AI 工具）：https://blog.friday.engineering/submitting-swift-tips-for-writing-a-swift-student-challenge-submission/
- MacRumors 称 2026 年奖品含 AirPods Max 2。

**本机证据**：Xcode 27 的 App Playground 模板；iPhoneOS27.0.sdk 里的 SwiftUI、ScreenCaptureKit 接口；SwiftPM 的 PackageDescription 接口。
逐字摘录的纯文本放在这次会话的临时目录里，会被清掉；要核对原文，以上面的链接为准。
