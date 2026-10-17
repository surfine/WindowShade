# 设计稿

既有可交互画面稿采用单文件 HTML；2026-10-11 的原生静态补稿采用 Markdown 与实际画面。HTML 可直接打开。做完或改完的稿默认发布成 claude.ai 上的私有页面；已有链接的更新同一个链接。

**先看总稿 [WindowShade 设计系统](WindowShade%20设计系统.html)**（2026-10-08，[线上私有页](https://claude.ai/artifact/Q2XdwfQttwpju6MvzpY93Y)）：把下面十六份收成一套。能玩的刘海模拟器（六层仲裁）、十二条规则、令牌、二十六个零件、十一种交互模式、七条线的表面目录与成熟度、输入统一表、边缘情况总表、宣传片逐幕对照、还没画的用量 / 进度 / 胶囊五态 / 三个住处 / 离开期间，以及怎么分级发布。单张稿仍是各自时刻的画面依据；总稿和单张稿不一致时，以单张稿的画面为准，记进对照账。

书面令牌仍以 [design-system.md](../design-system.md)（2026-09-29 定稿）为准。两边不一致时，片子先照这里的稿做画面，不顺便改设计系统。新表面先过 [design-grammar.md](../design-grammar.md)；对不上的记在那边的对照账，不在这里改数字。

写产品代码、测试、界面、官网、README 或宣传之前，先打开对应的稿。稿是画面，不是源码，不嵌进工程。

| 稿 | 讲什么 | 哪支片子对得上 |
| --- | --- | --- |
| [WindowShade 全景](WindowShade%20全景.html)（[线上](https://claude.ai/artifact/2AQPp5eEoFPBrCobUBxKsp)） | 七条线、刘海听谁的、五种形状、一张输入表 | 概念片和 opus 的总图 |
| [WindowShade 设计规范](WindowShade%20设计规范.html)（[线上](https://claude.ai/artifact/NSQU27GL6xVjhW2UFV9LKn)） | 价值观、三层材质、形状、令牌、各个表面 | 所有片子的表面 |
| [WindowShade 读到的](WindowShade%20读到的.html)（[线上](https://claude.ai/artifact/3SXfR2wyxHBGiBBEHxvjRA)） | 读了什么、为什么读、去了哪里 | 不是镜头；隐私说明 |
| [安静的刘海 动效样片](安静的刘海%20动效样片.html)（[线上](https://claude.ai/artifact/SNQWr7SD1vf5ULX7FUVzZ6)） | 十一根弹簧、卡住开口、收进刘海、欢迎窗口、官网首屏、《一句话》80 秒分镜 | [motion-direction.md](../motion-direction.md)、[film/ws2-opus](../../film/ws2-opus) |
| [从锁屏到窗口](从锁屏到窗口.html)（[线上](https://claude.ai/artifact/UepNxvLrJY5WDRANnjubyH)） | 开盖，认出你，窗口都还在原处 | 概念片第 0 章、opus 的 `lid` |
| [卡住时刘海开口](卡住时刘海开口.html)（[线上](https://claude.ai/artifact/SDXbhwZr8wzwqSFnXD6TnQ)） | 刘海在等什么、开口的节奏 | 概念片前段、opus 的开口、1.0 宣传片若改画面 |
| [收成缩略图](收成缩略图.html)（[线上](https://claude.ai/artifact/TGoNZE1WAAvZLeYDUoLA2N)） | 原地缩成缩略图、排到屏幕边、收进刘海 | 概念片收起、1.0 宣传片的收起 |
| [欢迎使用 WindowShade](欢迎使用%20WindowShade.html)（[线上](https://claude.ai/artifact/GW69BJGFgzQW7WCeRAVxTc)） | 欢迎窗口 | 动效样片里的欢迎、官网 |
| [首次打开 1.0.17 小样](%E9%A6%96%E6%AC%A1%E6%89%93%E5%BC%80%201.0.17%20%E5%B0%8F%E6%A0%B7.html)（[线上](https://claude.ai/artifact/R2h7LCy9eQFF1GgH6kHF8u)） | 1.0.18 首次打开与整个设置的讲解动画：先学双击收起，再一起问辅助功能和屏幕录制（可选），再用一页四段演刘海、窗口浏览、手势与卷轴、菜单栏；升级一页找回授权、一页说新开了什么；每个设置页顶上一条“设备 / 结果”讲解带，行到哪演到哪；末尾是 1.0.18 工作单。**Aaron 10-17 已拍板全部问题** | 取代欢迎窗口现在的三步（Welcome.swift）和各设置页顶部 |
| [1.0.18 新表面 小样](1.0.18%20%E6%96%B0%E8%A1%A8%E9%9D%A2%20%E5%B0%8F%E6%A0%B7.html)（[线上](https://claude.ai/artifact/2p7dHpjTEEf5wGqcobQiTG)） | Dock 预览卡上的红黄绿（关闭 / 最小化 / 进入全屏）、设置侧栏搜索（⌘F、同义词、跳到行并让讲解带演）、正在播放拖完进度 1.5 秒内信本地、DMG 安装窗口（卷帘背景、两种外观通用）、权限文案统一（辅助功能必需、屏幕录制可选）；附五个待定问题和各自的实现范围。**小样，等 Aaron 定稿** | 不是镜头；1.0.18 第 2–5 天实现的画面依据 |
| [1.0.18 宣传片 分镜](1.0.18%20%E5%AE%A3%E4%BC%A0%E7%89%87%20%E5%88%86%E9%95%9C.html)（[线上](https://claude.ai/artifact/9AqXZMBeDGpTztDGJQyhjY)） | 本机 bezelPath 实测刘海（含肩）、现片审片问题、24 拍 58 s 节拍表、关键帧、刘海五个动作样片、声音与验收；五个问题 Aaron 10-18 已定 | 1.0.18 宣传片（promo 工程，改片前先对这张） |
| [为什么不用最小化](为什么不用最小化.html)（[线上](https://claude.ai/artifact/RkLPV8yCJNhuYYoH636TrT)） | 看不见的窗口都在刘海里，和最小化的差别 | 1.0 宣传片的收起故事、概念片第 2 章 |
| [一颗岛](一颗岛.html)（[线上](https://claude.ai/artifact/HH9PdqqsxgfASMkqNw6Uac)） | 岛（紧凑两耳、最小点）与半岛（展开下鼓）、提醒回媒体、内容替换与数字过渡 | 对 Alcove / WWDC23 10194；产品刘海变形；《一句话》与概念片互训 |
| [手边的每一样](手边的每一样.html)（[线上](https://claude.ai/artifact/SAeiZhSezHbSqjXiSzhqDs)） | 一个入口，一套动作，任何输入 | 概念片第 4 章 |
| [看与指挥](看与指挥.html)（[线上](https://claude.ai/artifact/9mbRLt1QGpsKLKip991Xe3)） | 坐在 Mac 前看，躺在沙发上指挥 | 概念片第 5–6 章、opus 的 `draw` / `hold` |
| [指挥模式](指挥模式.html)（[线上](https://claude.ai/artifact/Ku2E7n1xFuXWWjDiF8Ddp1)） | 手里一部 iPhone，指挥一屏的 Codex 和 Claude | 概念片第 6 章、opus 的 `hold` |
| [iPhone 上的遥控器](iPhone%20上的遥控器.html)（[线上](https://claude.ai/artifact/1vJy6AnRnkMqpmp84fE9Q5)） | 一个遥控器碰一下刘海：那一排里走动是遥控模式，走进一个会话是指挥模式；同一次配对、同一套键 | 概念片第 4–6 章；遥控器上遥控与指挥的键位以它为准（2026-10-08 定） |
| [离开就锁](离开就锁.html)（[线上](https://claude.ai/artifact/BPmRiSF26X44bpUqFMAZjs)） | 带着手机走开就锁，走回来就开 | 概念片第 7 章、opus 的 `away` |
| [番茄钟](番茄钟.html)（[线上](https://claude.ai/artifact/5fQkwURyoGwZRrFBp2XnWf)） | 专注时聊天收起来，休息时桌面收起来 | 概念片第 7 章、opus 的 `away` |
| [宽形状画肩](%E5%AE%BD%E5%BD%A2%E7%8A%B6%E7%94%BB%E8%82%A9.html)（[线上](https://claude.ai/artifact/QBrcgHbfyjRfcEepsBMSph)） | 落点、提醒、教学、展开四种宽样子画不画肩；左边肩先收到 0 再长，右边肩一直在；内容绕刘海排与留额头并排。**小样，等 Aaron 用放大镜看，过了再另起实现包** | 对应 [design-system.md](../design-system.md) §5.1 S3 与 §6-3、§6-4 的可选项 |
| [对标 Atoll、Alcove 与 niri](%E5%AF%B9%E6%A0%87%20Atoll%E3%80%81Alcove%20%E4%B8%8E%20niri.html)（[线上](https://claude.ai/artifact/Wk9yzDHA3YFFccYmZUXikC)） | 2026-10-09 对标总账：落后、持平、领先，这轮追四块加卷轴，不取什么，待定事项 | 不是镜头；排期依据 |
| [正在播放](%E6%AD%A3%E5%9C%A8%E6%92%AD%E6%94%BE.html)（[线上](https://claude.ai/artifact/Sg3LLBSJBTT87GD7KtqCcp)） | 两耳封面与真实波形、换歌一瞥、点开成大卡、拖进度、输出设备、取色 | 对 Alcove / Atoll 的播放器 |
| [音量与亮度](%E9%9F%B3%E9%87%8F%E4%B8%8E%E4%BA%AE%E5%BA%A6.html)（[线上](https://claude.ai/artifact/YL7pvC72qRoiWRLqnLQn9e)） | 两耳电平、到头回弹、何时拦键藏系统提示、何时交还系统 | 对系统 HUD 与 Alcove |
| [文件架](%E6%96%87%E4%BB%B6%E6%9E%B6.html)（[线上](https://claude.ai/artifact/TGh15t3EV9FkPjLnzQay4j)） | 文件拖到刘海：暂存、隔空投送、用 App 打开；文件架只记书签 | 对 Atoll 货架、Alcove 将来的托盘 |
| [日历、电量与计时器](%E6%97%A5%E5%8E%86%E7%94%B5%E9%87%8F%E8%AE%A1%E6%97%B6%E5%99%A8.html)（[线上](https://claude.ai/artifact/JnUmLbVvSb9igvSxs4QSYp)） | 快开会、插上电源、低电量、设备连上、通用计时器，谁让谁 | 对两家的小活动 |
| [卷轴](%E5%8D%B7%E8%BD%B4.html)（[线上](https://claude.ai/artifact/SGBdwfP5ZFr7NDMzPJ7Yvs)） | 对 niri：居中三种、并进拆出、跟手概览、和刘海互通 | 对 niri 的滚动平铺 |
| [实时活动晋级](%E5%AE%9E%E6%97%B6%E6%B4%BB%E5%8A%A8%E6%99%8B%E7%BA%A7.html)（[线上](https://claude.ai/artifact/Y1xC2moskAEa2bjHNk2JKb)） | 刘海先量菜单栏空位再长耳朵、悬停不误触、九种活动同一套样子与生命周期、那一排里打字筛选；对照 Bartender、Ice 等菜单栏工具 | 不是镜头；实时活动的统一规格 |
| [进度 · 静态稿](进度.md) | 百分比、项数、确认正在做但总量未知；三条共存，大项数完整短写 | 2026-10-11真实视图合成值基线；源层/仲裁/动势未验，极端数字与完整读屏待补 |
| [用量 · 静态稿](用量.md) | 同一会话格的剩余、低额、到期等待、未知与遮隐 | 真实视图合成额度；账户详情另有候选，未接产品 |
| [用量详情](用量详情.md) | 账户多窗口与当前会话分区，长模型两行末尾省略 | 2026-10-11候选，未接产品 |
| [隐私行](隐私行.md) | 名称、原因与当前值分列，长值收住，展开说明照原字号换行 | 2026-10-11原生行样件，整页/来源/动作未验 |
| [隐私展开](隐私展开.md) | 原稿两列与12号正文，短标签、完整说明 | 2026-10-11候选及真实Row静态组合；整页/来源/动作未验 |
| [隐私内容列](隐私内容列.md) | 41默认登记行的实际组件静态组合；图标缩进待统一，非生产Page | [证据](../design-review/2026-10-11-privacy-composition-and-motion-baseline/README.md) |

补稿状态：**用量**已补[静态稿](用量.md)，长在已有的编程会话实时活动里，范围与规则见 [usage.md](../usage.md)；**进度**已补[静态稿](进度.md)，拷贝、移动、下载、导出、备份这类有起点有终点的事，长在已有的实时活动里，三种量（百分比 / 第 k / n / 不确定弧）在同一排里怎么变是这一张要证明的，来源分层与准入见 [progress-in-notch.md](../progress-in-notch.md)。两份静态稿已过有限准入，后续动势与来源继续过 [design-grammar.md](../design-grammar.md) 的准入。
