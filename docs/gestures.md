# 标题栏手势

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。


> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
指针停在标题栏上，两指往上一推，窗口像卷帘一样收起来；往下一拉，窗口铺满菜单栏和 Dock

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
之间的屏幕。上下是一架尺寸梯子，方向和卷帘一致：卷帘条 ⇄ 原来大小 ⇄ 铺满屏幕，往下一格变大，

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
往上一格变小。左右滑占半屏，张开把这块屏上的窗口排好（魔法平铺）、捏合放回。拖着标题栏晃一晃，别的窗口收进刘海。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
鼠标滚轮也能用。手指移动时，窗口旁边出现

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
一块和系统音量提示同款的小浮窗，告诉你松手会做什么、还差多少。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。


> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
## 为谁做

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。


> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
- WindowShade 被 Newlearner 频道介绍时（2026-07，读者来稿），定位是“展开”和“离开桌面”

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
  之间的中间态：临时看一眼后面的窗口，不关闭、不隐藏、不最小化。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
- 同一频道作者 2023 年写过自己的窗口管理方案（MBP ASS 聊聊系列一）：窗口很难铺满菜单栏和

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
  Dock 之间、双击标题栏不知道会缩放成什么样、最小化的窗口要去调度中心一个个找；用 Magnet

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
  拖拽吸附、Raycast 快捷键铺满和半屏、DockMate 找隐藏窗口。他最怀念的是 HyperDock 的

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
  “光标放在 App 顶栏滚动，即可铺满全屏 / 缩小”，并说没找到别的软件能做到。他用罗技鼠标。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
- 另一类用户主要用触控板，一张桌面只放一个 App，不需要置顶；更在意响应速度，以及收起能否比最小化少走一步。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。


> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
所以标题栏手势要同时照顾触控板和鼠标滚轮：上下滑就是“收起 / 铺满 / 还原”，滚轮也一样；

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
铺满用屏幕可用区域（菜单栏到 Dock 之间），结果每次都一样。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。


> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
## 手势

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。


> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
| 在哪 | 手势 | 做什么 |

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
| --- | --- | --- |

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
| 标题栏 | 往上滑 | 收起窗口；窗口是用手势铺满的，先撤销那次铺满 |

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
| 标题栏 | 往下滑 | 铺满屏幕（已经铺满时不做事） |

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
| 标题栏 | 左滑 / 右滑 | 左半屏 / 右半屏（指针在标签页、地址栏上时让给 App） |

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
| 标题栏 | 左滑或右滑走满，再往上或往下拐 | 占那一侧的上角或下角（左上角、左下角、右上角、右下角） |

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
| 标题栏 | 朝同一边接着滑（右边同理） | 左边这架梯子：左半屏 → 左三分之二 → 左三分之一 → 移到左边的屏幕（落在交界那一半）；左边没有屏幕就回到左半屏 |

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
| 标题栏 | 三分之一宽时往里滑 | 一格一格走：左三分之一 → 中间三分之一 → 右三分之一 |

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
| 标题栏 | 已经在上半或下半一行（四角）时左右滑 | 在这一行里走同一架梯子：左上角 → 左上三分之二 → 左上六分之一，六分之一再往里一格一格走（中上、右上）。这就是网格 |

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
| 标题栏 | 已经是六分之一时，左右滑再往上或往下拐 | 在这一列里上下走三行：左上六分之一往上拐 → 左上九分之一，往下拐一格一格走到左中、左下九分之一，再往下回到左下六分之一。这是九等分 |

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
| 标题栏 | 拖着标题栏快速甩一下（鼠标、触控板都行） | 和滑动同一架梯子：往上收起（铺满的先还原），往下铺满，左右走左右梯子，往四个角占那一角 |

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
| 标题栏 | 两指张开 | 魔法平铺：这扇当主角，这块屏上别的窗口按各自要的地方排在旁边，聊天放侧拉；只有它一扇时就是铺满 |

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
| 卷轴里的窗口的标题栏 | 两指左右滑 | 整条卷轴跟着手指走，松手按惯性停在某一列的边上 |

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
| 卷轴里的窗口的标题栏 | 两指往下拉 / 往上推 | 这一列宽一档 / 窄一档（⅓ ⇄ ½ ⇄ ⅔ ⇄ 整屏）；最窄再往上推是收起 |

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
| 卷轴里的窗口的标题栏 | 两指张开 | 卷轴概览：整条卷轴缩小铺在这块屏上，点哪扇就把它那列滑出来（Esc 或点空白处收起） |

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
| 标题栏 | 拖着标题栏晃一晃 | 别的窗口收进刘海（刘海关着时收成卷帘条）；它们还收着时再晃一下，放回来 |

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
| 标题栏 | 两指捏合 | 撤销上次排布；没有可撤销的，浮窗写“没有可撤销的排布” |

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
| 标题栏 | 轻点两下 | 铺满 ⇄ 还原，一下到位 |

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
| 卷帘条 | 往下拉一点 | 看一眼：卡片跟着手指卷下来，没拉满就松手，停在看一眼，指针移开收回 |

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
| 卷帘条 | 往下拉满、轻点两下 | 展开窗口 |

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
| 卷帘条 | 用力按（Force Touch 触控板） | 按住期间看一眼，松手收回 |

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。


> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
所有手势都是先把指针停在标题栏（或卷帘条）上，再做；指针停在哪，就作用在哪扇窗。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
张开和捏合就是看照片时放大、缩小的那个动作：两根手指放上去，往外分开是张开，往里收拢是捏合。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。


> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
**方向跟内容走。** 在标题栏上滚动，就像在滚动窗口本身：内容往上走，窗口收起；往下走，

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
窗口放下来。触控板开着自然滚动（系统默认）时，内容方向就是手指方向。关了自然滚动的鼠标，

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
滚轮往上推是内容往下走，也就是铺满——和 HyperDock 的“往上滚铺满”一致。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。


> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
**轻点两下。** 就是系统的“智能缩放”：触控板两指、Magic Mouse 单指轻点两下（系统设置里

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
默认打开）。在标题栏上，普通窗口一下铺满，用手势铺满的窗口一下还原——和照片、网页里智能

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
缩放“放大到合适、再点回去”同义。在卷帘条上是展开。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。


> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
**Magic Mouse。** 单指滑动发出的事件和触控板两指滑动是同一种，上下左右、尺寸梯子照常用。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
它没有张合，所以“铺满 ⇄ 还原”靠上下滑或单指轻点两下；它没有触感，走满时靠浮窗变色提示。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。


> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
**拐弯占角。** 左右滑先要走满（浮窗变蓝），再朝上或朝下走满一小段（44 点，比走满略短）才换成角；

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
走满之前就往上下偏，仍按上下算（收起、铺满），不会半路变成角。拐弯从走满那一刻重新计量，那之后的一段要以上下为主（上下至少是左右的 1.2 倍）：手指划长了带出的弧线、一路斜着划下去，都不算拐弯；小幅的上下抖动也不算；拐回来就是

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
半屏；往回拉，进度退回，松手不做事。标签页、地址栏上左右归 App，那里也不拐弯。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。


> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
**左右也是一架梯子。** 朝同一边接着推：半屏 → 三分之二 → 三分之一，再推就移到那边的屏幕、落在

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
紧挨交界的那一半，像把窗口从屏幕边上推了过去；那边没有屏幕，就回到半屏。顺序和 Rectangle 连按

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
一样，换过来的人不用重学。手势、键盘（左半屏 / 右半屏的快捷键）、甩一下都走这一个规则；拐弯仍然占四角。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
撤销、换屏排回都照常。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。


> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
**甩一下标题栏。** iPadOS 26 可以拖住窗口顶部快速甩到一边来排；Mac 上没有。这里用指针拖着标题栏

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
快速甩出去松手，按离手那一刻的方向走同一架梯子，窗口带着甩出去的速度滑进位置。方向没有照搬 iPad 的

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
“往上全屏”：WindowShade 里往上一直是收起，同一个标题栏不能有两套相反的规则。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。


> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
- **什么时候算离手。** 按键松开就是离手。三指拖移不一样：手指离开触控板后，系统要再等 0.2–0.7 秒才发

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
  “松开”（2026-09-26 实测 222、693 毫秒；这一下的点击次数是 0，按下触控板拖是 1），好让人把手指挪回来

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
  接着拖。等它就太晚了，所以同时听触控板的触摸流（张合用的那个只读监听），手指全部离开的那一刻就判。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
  触摸流没收到时，退一步用迟到的“松开”，按最后一次移动算，窗口已经停了那么久，就从静止开始滑。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
- **甩还是摆。** 离手速度用离手前 45 毫秒的点做最小二乘拟合（触控板每帧的位移有抖动）。甩的时候手在最快时

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
  松开；平常拖窗口，放下之前都会先减速。所以要求离手速度至少是这一下最快速度的 65%，而且每秒不少于 1400 点。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
  有了这一条，门槛比原来的每秒 1800 点低，也不会把“快快拖过去、慢慢放下”当成甩。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
- **方向宽容一点。** 手臂甩出去自然带弧线，iPadOS 26 也把“往左上甩”当成左半屏。离水平或竖直 30° 以内都算直的，

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
  明显朝着角落（30°–60°）才占那一角。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
- **换手接着拖不算。** 三指拖移时手指在触控板边上、朝运动方向离开，那是换个位置接着拖；判定跳过，

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
  系统的拖动照常继续。手指离开后又放回来接着拖，已经开始的滑动立刻停下，交还给拖动。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
- **滑进去，而不是跳过去。** 跨进程的 SkyLight 移动在开着 SIP 的系统上无效，只能用辅助功能接口：在自己的队列上

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
  逐帧设位置（每秒 120 次），尺寸要 App 重新排版，每秒最多改 60 次；改一次超过 12 毫秒的 App（Electron 一类实测 30–80 毫秒）在刚松手时一次改到位，之后只挪位置。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
  位置接上甩出去的速度，用阻尼 0.88、响应 0.42 秒的弹簧；尺寸从零速度开始、不回弹；甩得猛又离目标近时，

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
  冲过头不超过 28 点。每帧按当前时间取值，卡了就跳帧，落点和时长不变；最后按“尺寸、位置各两遍”校准。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
  探针实测：左半屏那次计划 496 毫秒、实际 514 毫秒，边走边改尺寸；左右换边尺寸不变，接近每秒 120 帧。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
- **随时可以抓住。** 滑到一半又按住它，窗口停在当下的位置，交给这一次拖动。撤销回到按住标题栏之前的样子。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
- **其它条件照旧**：窗口确实跟着指针动了（按比例看：至少走了指针一半的路、方向一致；甩得快时窗口会落后

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
  一两帧），离手处没贴着屏幕边（那是系统的拖边平铺）。按下时只查这一扇窗的外框、在后台把辅助功能窗口查好；

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
  拖动中只记事件自带的时间和位置（机器忙时事件会成串送到，按收到的时刻算速度会乱），不拖慢别的 App。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
- **触摸屏。** 判定只认“一串带时间的位置 + 离手时刻”，不认输入设备。触摸流里分得出直接触摸（触摸屏一类）

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
  和触控板的间接触摸，日志会记下来；将来的触摸屏 Mac 上，手指离开屏幕就是离手，同一套判定和滑行直接可用，

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
  只剩门槛要按真机手感再调。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。


> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
**用力按卷帘条。** Force Touch 触控板上用力按到第二段，卷帘条下面挂出看一眼的实时画面；按着一直在，

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
松手就收回，和系统里用力点按预览文件是同一个习惯。只看自己卷帘条上的压感事件，别的 App 不碰；

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
这一下松手不算单击，也不算双击的第二下；按着拖动是在挪卷帘条，画面马上收回。看一眼在设置里关掉时

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
不接。压感事件没法用公开 API 合成，这一项只能在真触控板上验证。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。


> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
**窗口跟手。** 认出“收起”或“展开”之后，动的不只是提示浮窗，窗口本身也跟着手指走：

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
在标题栏上往上推，窗口就在手指下往上卷，卷走的地方露出后面的桌面；在卷帘条上往下拉，

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
窗口从卷帘条那里放下来。松手才真的收起或展开，接着卷完；过了门槛又往回拉、或换了方向，

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
窗口退回原样，真窗口从头到尾没被碰过。走满门槛时窗口卷到 0.55，继续推到约 1.8 倍门槛就

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
完全收起。做法是用收起动画的盖板：先盖上一张和窗口一样的画面（背后垫着窗口后面的真实桌面），

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
进度交给手指，松手后才在盖板下面藏起或恢复真窗口。盖板晚于手指出现、或滚轮一格一格跳时，

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
显示值用 40 毫秒的指数跟随追上去，不会一下跳过去。手指一落到标题栏（或卷帘条）上就开始准备盖板，以 0 进度盖上，看起来和窗口一样；认出是左右滑、张合或滚轮就撤掉。盖板不等全系统窗口清单：画面先用快速截图，背景用快速合成，实时流在后台接上。实测从确认标题栏到盖板可以跟手，收起约 140 毫秒、展开约 100 毫秒（原来机器忙时收起要 300–490 毫秒）。这是手指的直接反馈，不看“收起窗口时的

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
动画”开关；打开减少动态效果、暂停效果或桌面开合时不跟，只有提示浮窗。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。


> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
**换屏后排回去。** 内屏、外屏切换时，系统只挪窗口、不改排法。用手势或轻点两下排过的窗口

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
（铺满、左半、右半），换屏后按原来的排法排到它现在所在的屏幕上；系统先自己挪窗口，所以等

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
1.5 秒再看。只处理“只是被系统挪过或按新屏幕缩小过”的窗口：尺寸没变，或者缩小后贴着屏幕边；

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
尺寸被人手改过的不动。重排后撤销仍然可用，排之前的样子按两块屏幕的比例换算过去。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
只有显示器本身变了（接上、拔下、分辨率、排列）才排：外接屏上的菜单栏时隐时现、Dock 高度差一点，

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
系统也会发“屏幕参数变了”（实测一台接 Studio Display 的 Mac 每隔几秒一次），那时去排，铺满的窗口

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
会跟着菜单栏上下跳。键盘、手势、窗口浏览排过的窗口（铺满、半屏、四角）都算。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。


> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
**连划不连走。** 刚执行完的 0.6 秒里，同一扇窗朝同一个方向再划一下不接：Magic Mouse 上

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
常见的连划几下，不会在梯子上连走两格（本想还原，结果又收起了）。换个手势照常接；窗口还在

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
收起、展开的动画里时，什么手势都不接。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。


> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
**鼠标滚轮。** 一串滚动（间隔不到 0.3 秒）算一次手势；第一格落在标题栏或卷帘条上才接，

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
之后每格在浮窗里推进三分之一，像音量一格一格地涨；停下 0.3 秒结算，滚满三格才执行，

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
两格以内什么都不做。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。


> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
和 Swish 不同的地方，都是有意的：

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。


> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
| 手势 | Swish | WindowShade | 为什么 |

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
| --- | --- | --- | --- |

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
| 上滑 | 最大化 | 收起窗口 | 卷帘往上卷 |

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
| 下滑 | 最小化 | 铺满屏幕 | 帘子放下来；收起就是为了不用最小化 |

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
| 捏合 | 关闭窗口 | 撤销上次排布 | 不放一个撤不回来的手势 |

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。


> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
四角用“滑到半屏，再往上或往下拐”来选；已经占三分之一的窗口，再往同一边推就移到相邻的屏幕。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。


> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
**网格不另起一套。** 从 Rectangle、Magnet、Swish 换过来的人要的六等分（3×2），在这里就是“在一行里走梯子”：

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
窗口已经在上半或下半一行（比如左上角）时，左右滑不再跳成整高的半屏，而是在这一行里走同一架梯子——

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
左上角 → 左上三分之二 → 左上六分之一；六分之一再往里滑，一格一格走到中上、右上，走到头再推就移到

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
相邻屏幕的同一行。整高的三分之一也一样一格一格走（左 → 中间 → 右）。拐弯仍然只占四角，不改原来的手感。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
键盘同一个规则：窗口在左上角时按左半屏的快捷键就是左上三分之二。换屏排回、撤销对网格里的每一格都照常。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
九等分（3×3）也不另起一套，走的是“拐弯”：窗口已经是六分之一（一行里三分之一宽）时，左右滑一下再往上或往下拐，

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
就在这一列里按三行走——上面那一行往上拐是上面的九分之一，往下拐一格一格走到中间、下面的九分之一，再往下回到下面那一行。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
九分之一左右滑也一格一格走，走到屏幕边：旁边有屏幕就移过去、落在同一行，没有就停在原地。只有三分之一宽的格子会变成九分之一，

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
别的宽度拐弯仍然只占四角。单纯上下滑仍然是收起、铺满，不因为九等分改意思。键盘也一样：按了左右键紧接着按上下键就是拐弯。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。


> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
**魔法平铺：排一次，不是一直平铺。** 两指张开（或菜单里的“魔法平铺”、自己录的快捷键）把这块屏上的窗口一次排整齐，

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
之后窗口照常随手挪；捏合排过的任何一扇，整批回到原处。原来写的“不追自动平铺”指的是 AeroSpace 那种一直管着的平铺，

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
这一条仍然不做；Aaron 要的是一下排好、比例自己定，所以补上。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。


> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
- 谁当主角：看 App 要多大地方。浏览器、写代码、做设计、剪视频、表格要地方；写作、笔记、PDF、邮件、终端是参考；

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
  访达、日历、音乐这类要得少；微信、QQ、信息、飞书、钉钉、企业微信、Slack、Telegram 这类聊天放侧拉。没见过的 App

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
  按它自己写的类别算。张开手势落在哪扇上，哪扇就是主角；快捷键和菜单按上面的规则挑，最前面那扇加一点分。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
- 比例自己定：主角和旁边一列各要多少地方一比，落到 5:5、6:4、7:3 三档之一（两个浏览器 5:5，浏览器配写作 6:4，

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
  浏览器配访达 7:3）；旁边一列不到 420 点宽就退一档。主角在左还是在右跟着它现在在哪一边，少挪窗口。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
- 竖着放的屏幕上下分：主角在上（原来在下半就在下），参考在另一半横着排开。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
- 旁边一列放得下几扇就放几扇（每扇至少 280 点高，竖屏时至少 360 点宽），按原来的上下次序；多出来的收进刘海。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
- 改不了大小的窗口放在它那一格正中；对话框、浮动面板、全屏的窗口不动。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。


> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
**卷轴：放不下时接成一条（niri 的做法）。** 魔法平铺放不下的窗口不再收进刘海，而是每扇一列、按 App 要的宽度

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
（要地方的 ⅔、参考 ½、轻的 ⅓）接在右边，停在屏幕外、只露一条边——像展开一幅手卷，一段一段往后看。谁都不变窄。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。


> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
- 手指在卷轴里任何一扇的标题栏上左右滑，整条卷轴跟着手指走（两头越往外越拉不动），松手按惯性停在最近的列边上。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
  挪窗口放在每个 App 自己的后台队列上，只挪最新的位置：慢 App 跟不上时跳过中间几帧，不拖慢手指、不拖慢别的 App。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
- 上下还是那架“变大一级、变小一级”的梯子，只是细了：往下拉这一列宽一档，往上推窄一档，最窄再往上推收起。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
- 左半屏、右半屏的快捷键走到左边、右边那一列，把它滑出来、焦点给它；点到（或 ⌘Tab 到）只露一条边的窗口，它自己滑出来。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
  手指滑完停下后，原来有焦点的那扇要是滑出了屏幕，焦点交给停在屏幕上的第一列（niri 也是这样），卷轴不会又被拉回去。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
- 卷轴开着时新开的窗口接在当前这列右边、自己一列，别的列不变窄；关掉、最小化、收起、侧拉、被人拖走的窗口让出位置。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
- 捏合卷轴里任何一扇，整条放回原处（新接进来的也回到它刚出现时的样子）。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
- 张开卷轴里任何一扇是**卷轴概览**：整条缩小铺在这块屏上，点哪扇就把它那列滑出来；←→ 换列、回车去、Esc 或点空白处收起，

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
  窗口一扇不动。还没有菜单项和快捷键，鼠标暂时打不开它。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
- 指针停在屏幕边露出来的那一条上，看一眼停在外面那一列此刻的样子，离开那一条就收回。卡片只供看、不接点击，

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
  要那一列就单击那一条本身。跟着看一眼的开关。窗口之间不留缝（默认）时，那一条常被挨着的那一列盖住，这时不出卡片；

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
  细节见 [niri 对照](niri.md)。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
- 只有屏幕左右两边都空着（没挨着别的显示器）才接成卷轴：macOS 不让窗口整个离开屏幕，停在外面的窗口会被系统挪到

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
  旁边那块屏上。有一边挨着显示器、或者竖着放的屏幕，放不下的照旧收进刘海。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
  竖着放的屏幕不改成上下卷：macOS 让有标题栏的窗口上沿留在屏幕里，滑出上沿的那几扇没处停，一条卷轴会断成两截。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。


> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
**窗口之间留缝。** 设置 → 卷帘 → 排布：不留（默认）、窄（8 点）、宽（16 点）。半屏、四角、网格、铺满、魔法平铺、卷轴、

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
窗口浏览里的排布都照同一条规则：贴着屏幕边让出一整道缝，挨着别的窗口让出半道，两扇之间合起来正好一道。认“这扇窗现在在哪一格”

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
时也按它算，梯子照常往下走。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。


> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
**移到另一块屏幕。** 菜单里有，快捷键自己录。按原来的排法放到下一块屏幕上（半屏还是半屏、铺满还是铺满，没排过的按相对位置和大小），

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
按系统里屏幕的顺序转一圈。上下摆的显示器也行——左右梯子走到头换屏只走得到左右两边。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。


> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
**晃一晃（Windows 的 Aero Shake）。** 拖着标题栏左右来回晃三下，这块屏上别的窗口飞进刘海，只留手里这扇；

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
它们还收着时，拖着同一扇再晃一下，全部放回原处。刘海关着时收成卷帘条。晃过的这一下拖动不再当成甩一下。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
和手里这扇同属一个 App、又不能最小化的窗口（没有黄色按钮的那种）收不走，会安全地退回原样、留在原处。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。


> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
**拉一点就是看一眼。** 在卷帘条上两指往下拉：拉一点，看一眼的卡片跟着手指卷下来，窗口此刻还收着；

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
没拉满就松手，停在看一眼（指针移开就收回）；拉满松手才真的展开，画面留到窗口回到原处再撤。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
被隐藏的 App 要等卡片整张盖住原处，才在下面临时显示它拿实时画面，所以拉着的时候先给收起时的画面。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
看一眼关着、或者卷帘条下面放不下卡片时，照旧让窗口跟着手指放下来。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。


> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
## 键盘：同一架梯子

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。


> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
**快捷键默认不占（1.0.16 起，docs/direction.md 最后一张表）。** 新装的 WindowShade 一个全局快捷键都不占，⌃⌘1…9 也不占：

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
Windows 的 Win+Ctrl+← 到了 Mac 上正是 ⌃⌘←，一装上就撞上左半屏；⌃⌘ 这一组也容易撞上别的 App。要用的人在设置 → 快捷键里

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
自己录，菜单和设置里每个动作都还在、都能录。想要 ⌃⌘ 方向键这四个的，在设置 → 快捷键 → 更多排法 → 方向键换成字母里

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
点“方向键”一下就换上（见下面“从 Swish 换过来”）。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。


> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
- **老用户升级照旧。** 从 1.0.15 及以前升级上来的，没改过的那几个照他原来在用的：⌃⌘C、⌃⌘0、⌃⌘P、⌃⌘G、四个 ⌃⌘ 方向键和

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
  ⌃⌘1…9；自己改过、清掉过的照他改的。“恢复默认”对他也是回到这一套，不会清空。用过 1.0.16 测试版的另外留着 ⌃⌘S、L、M、N、H。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
- **怎么认新装还是升级。** 启动的第一步认一次（在声音迁移、清理收起记录之前，那两步会写或删下面的键），存进 `InstallHistory`

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
  （0 新装、1 升级、2 用过测试版），以后照存的。看以前的版本留下的设置：最可靠的是 `ShadeSoundMigrationVersion`，

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
  从第一版起每次启动都写；另外是欢迎窗口看过了（`ShadeOnboardingShown`，点红色按钮关掉的没有）、收起过窗口（`ShadeJournalEntries`，

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
  记录空了会删掉）、改过外观、声音、双击的设置、改过任何一个快捷键（`GlobalShortcut.` 开头）；测试版认 `GlobalShortcut.newDefaultsChecked.1.0.16`。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
  万一认晚了（这一次启动已经写过声音迁移版本号），新装的会被当成升级、照 1.0.15 占着那一组，不会反过来让老用户丢快捷键。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
  不往各个快捷键里抄值：没改过的仍然跟着“他这一版的默认”走。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
- 逻辑在 `App/GlobalShortcuts.swift`（`InstallHistory`、`factoryHotKey(for:)`），单测 `bash tests/run-quiet-defaults-tests.sh`。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。


> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
方向键走的是同一架梯子，一下到位，浮窗照样出现、说明做了什么。下表是升级上来的人手上的组合，新装的在同一处录自己的：

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。


> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
| 快捷键（升级上来的） | 名字 | 做什么 |

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
| --- | --- | --- |

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
| ⌃⌘↓ | 变大一级 | 卷帘条展开；原来大小的窗口铺满屏幕 |

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
| ⌃⌘↑ | 变小一级 | 铺满的窗口撤销那次铺满；原来大小的窗口收起 |

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
| ⌃⌘← / ⌃⌘→ | 左半屏 / 右半屏 | 占屏幕可用区域的一半 |

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。


> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
对象是最前面那扇窗；指针停在卷帘条上时是那条。键盘也能拐弯：按 ⌃⌘← 之后 0.8 秒内再按 ⌃⌘↓，

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
窗口占左下角（⌃⌘↑ 是左上角，右边同理），和手势“左右走满再往上下拐”一样；隔久了就是普通的变大、变小一级。刚用 ⌃⌘↑ 收起一扇，焦点会落到别的窗口上，

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
10 秒内紧接着按 ⌃⌘↓，放下来的是刚收起的那扇，不会去铺满另一扇。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。


> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
别家的 ↑ 通常是最大化。这里的 ↑ 是让开：和在标题栏上往上推同向，WindowShade 的底色是让开。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
四个快捷键在设置 → 快捷键 → 排布当前窗口里录、改键或关掉；⌃⌘ 方向键在 Xcode 里是前进、后退，

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
两边都要用的人可以换一组。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。


> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
**一本账。** 键盘、手势、窗口浏览排过的窗口记在同一处：用哪种方式排的，捏合或 ⌃⌘↑ 都能撤回；

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
换了显示器，都会按原来的排法（铺满、半屏、三分、四角、网格）排回去。窗口被人手挪过、改过尺寸，这条记录就作废，

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
不拿旧位置覆盖人的新安排。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。


> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
**改不了大小的窗口。** 计算器、一些设置窗口不能改尺寸：排的时候保持原尺寸，放在目标区域正中，不缩在

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
左上角；甩一下时替身也按原尺寸滑过去，不先拉伸再跳回。有最小、最大尺寸的窗口长不到目标大小时，也放在正中。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。


> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
**拖边改大小不算拖标题栏。** 从窗口顶边往上拉改高度时，按下的位置也在标题栏那一带：窗口大小一变就认定是在

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
改大小，这一下不出刘海的落点小岛、不出侧拉提示，也不会被当成甩一下收起。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。


> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
拖到屏幕边缘吸附不做：macOS 15 起系统自带，再做一套只会两边打架。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。


> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
## 从 Rectangle、Raycast 换过来

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。


> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
设置 → 快捷键 → **更多排法**，点“用 Rectangle 的快捷键”旁边的**换上**：装过 Rectangle 的，照它现在的设置

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
（偏好设置里改过、清掉的都算；只有它导出的 RectangleConfig.json 的，照那份）；没装过的，用它首次打开时推荐的那一套。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
Rectangle 还开着时这些组合归它：刘海上说一声，退出 Rectangle 后自动接过来。我们自己别的动作用着同一个组合的，

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
让给 Rectangle 的那一个，并说出是哪几个。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。


> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
| Rectangle（推荐那套） | 这里叫 | Raycast 命令 |

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
| --- | --- | --- |

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
| ⌃⌥← / ⌃⌥→ | 左半屏 / 右半屏（连按照样 ½ → ⅔ → ⅓，和 Rectangle 一样） | Left Half / Right Half |

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
| ⌃⌥↑ / ⌃⌥↓ | 上半屏 / 下半屏 | Top Half / Bottom Half |

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
| ⌃⌥U / I / J / K | 左上角 / 右上角 / 左下角 / 右下角 | Top Left Quarter …… |

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
| ⌃⌥D / F / G | 左三分之一 / 中间三分之一 / 右三分之一 | First / Center / Last Third |

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
| ⌃⌥E / T | 左三分之二 / 右三分之二 | First / Last Two Thirds |

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
| ⌃⌥↩ | 铺满屏幕 | Maximize |

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
| ⌃⌥⇧↑ | 高度占满 | Maximize Height |

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
| ⌃⌥= / ⌃⌥- | 大一点 / 小一点（四边各 30 点） | Make Larger / Make Smaller |

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
| ⌃⌥C | 居中 | Center |

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
| ⌃⌥⌫ | 撤销上次排布 | Restore |

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
| ⌃⌥⌘→ / ⌃⌥⌘← | 移到另一块屏幕 / 移到上一块屏幕 | Next / Previous Display |

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。


> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
没换之前这些动作都不占快捷键，一直用 WindowShade 的人什么都不变。Raycast 的窗口命令没有默认快捷键、设置也读不到，

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
名字一一对应，照着录就行。排出来的每一格都进同一本账：捏合、⌃⌘↑、“撤销上次排布”都能撤回。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。


> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
## 从 Swish 换过来

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。


> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
**方向键换成字母。** 设置 → 快捷键 → 更多排法 → **方向键换成字母**，点 WASD、IJKL 或 HJKL：变小一级、变大一级、

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
左半屏、右半屏这四个方向一下换成 ⌃⌥ 加字母（WASD 是 ⌃⌥W 变小一级、⌃⌥S 变大一级、⌃⌥A 左半屏、⌃⌥D 右半屏；

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
IJKL 是 I 上、K 下、J 左、L 右；HJKL 照 Vim，K 上、J 下、H 左、L 右）。点“方向键”，换回换之前的样子。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
四个方向是自己录的（设置页上一格都没选中）时点“方向键”，换成 ⌃⌘ 方向键，刘海上说“再点一次换回原来的”；

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
再点一次，自己录的就回来。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
和 Swish 一样的是哪几个键、哪个键是哪个方向；方向的意思跟着这里的手势走：往上是变小、让开（见上面和 Swish 的对照表）。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。


> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
- 修饰键用 ⌃⌥，不沿用 ⌃⌘：⌃⌘W、⌃⌘D 系统在用（关窗、查词），⌃⌘S、⌃⌘L 在用过 1.0.16 测试版的人手上是侧拉和启动台。Swish 用它自己的

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
  “超级修饰键”，系统热键用不了 fn 这类键，所以不照搬。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
- Dvorak：系统热键认的是键在键盘上的位置，不认当前布局打出来的字母。Swish 的 Dvorak 那套（,AOE，居中是 Q）

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
  在 Dvorak 布局下正是 WASD 那几个位置，所以不另设一格；设置页按当前键盘布局显示键名，用 Dvorak 的人看到的就是 ,AOE，

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
  AZERTY 上是 ZQSD。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
- 撞车：别的动作已经在用的组合，它们先来的算数：那个方向不换，刘海上说出是谁占着（比如换上 Rectangle 的快捷键后

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
  ⌃⌥D 是左三分之一，WASD 的右半屏就不换）。被别的 App 占着、注册不上的，退回原来的组合；原来的组合已经换给了

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
  另一个方向（IJKL 和 HJKL 互换 J、K）时，那个方向也跟着不换，刘海上说它想要的组合留给了谁——哪个方向都不会被关掉。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
  换完以后自己又录过的方向，换回来时听自己的。这一点和“用 Rectangle 的快捷键”相反：那边是整套照搬 Rectangle，撞上的让给它。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
- 恢复默认会把这笔账一起清掉。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
- 没做：Swish 的居中键（⌫ 或 X）。它在 Swish 里是“居中并还原大小”，这里居中和撤销上次排布是两个动作，

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
  需要的在更多排法里各录一个。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。


> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
**再点一下 Dock 图标：让开这个 App。** 点 Dock 上最前面那个 App 的图标、它在这张桌面上有窗口露着时，它让开（和 ⌘H 一样），

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
再点一下回来（详见 [窗口浏览](window-browser.md)）。1.0.16 起按 docs/direction.md 最后一张表加了两条：

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。


> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
- **有看不见的窗口就不让开。** 这个 App 还有最小化的窗口、在别的桌面上的窗口（全屏 App 的那张也算）、整扇在所有屏幕外面的窗口时，

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
  他点图标多半是在找窗口（Word 开着两份，一份缩进了程序坞），让开会连眼前这份也藏掉。这时不让开；有最小化的，

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
  把辅助功能列出来的第一扇还原到前面，一次一扇，不一下全放出来。在别的桌面上、在屏幕外的不去搬，

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
  只是不让开。WindowShade 自己收着的窗口（卷帘条、收进刘海、侧拉、画中画）不算看不见，也不会被这里还原。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
  屏幕外的要 App 自己（辅助功能）说它是一扇标准窗口才算：不少 App 把画面用的辅助窗口停在屏幕外面，算上它，

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
  这个 App 的图标就永远点了没反应。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
  桌面归属用 SkyLight 的私有接口查，查不到就不判“在别的桌面”；只查不在屏上的那几扇。最小化的、屏幕外那扇是不是标准窗口，

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
  在后台问 App，只在有这种窗口时才问。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
  分类是纯逻辑（`Core/DockClickGuard.swift`，单测 `bash tests/run-quiet-defaults-tests.sh`）。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
- **换机的人默认关。** 没动过这个开关时：欢迎窗口里答了 Windows 或 iPad 的默认关（这正是 Windows 任务栏的行为）；

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
  一直用 Mac、没答的默认开；用过 1.0.16 测试版的（这个开关当时默认开着）照旧开着。设置 → 窗口浏览 → 触发里随时能改（键 `Dock.clickToHide`）。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。


> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
**Dock 图标上两指上下滑。** 设置 → 窗口浏览 → 触发 → **在 Dock 图标上两指上下滑**，默认关。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。


> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
| 在哪 | 手势 | 做什么 |

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
| --- | --- | --- |

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
| Dock 上的 App 图标 | 两指往上滑 | 这个 App 的所有窗口（系统的 App 窗口，最小化的也在里面）；让开了的 App 先回来 |

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
| Dock 上的 App 图标 | 两指往下滑 | 让开这个 App（和 ⌘H、再点一下 Dock 图标是同一件事）；点一下图标就回来 |

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。


> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
- 只认明显的一下：上下走够 56 点（和标题栏手势走满一样长）、上下至少是左右的两倍、1.5 秒以内；上下来回抖、

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
  慢慢挪的不算。触控板两指、Magic Mouse 单指都行，鼠标滚轮不算。松手那一刻才下结论，没有浮窗。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
- 和 Swish 不同：Swish 往下滑是把窗口最小化，这里是让开整个 App，不往 Dock 里塞缩略图，回来只要点一下图标。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
  捏合退出 App、左右滑轮换窗口没做：退出撤不回来；一扇一扇挑窗口有“按窗口切换”。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
- 只旁听，不拦截：Dock 自己不理图标上的滚动。开着程序坞的隐藏选项 scroll-to-open（图标上往上滚铺开窗口）时让给它；

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
  Swish 在运行时也让给它：确实在 App 图标上滑了才在刘海上说，一次运行只说一次（空白处、分隔线、废纸篓上滑不说）。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
  没在运行的 App 不理，不替你打开。只认 Dock 那一排里的 App 图标：父级必须正是 Dock 下面第一条列表

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
  （AppleScript 里的 `list 1 of process "Dock"`），打开的叠放里的格子、文件夹、废纸篓都不算。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
- 开着时每个滚动事件进来只看一眼相位；一下滑动开始时指针落在屏幕底边、左右边那一带，才查一次窗口表，看接这个滚动的

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
  是不是 Dock 自己的窗口；松手、认准是上下滑之后，才在后台队列问 Dock 指针下是哪个图标。不开计时器，不轮询。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
- 停在图标上时窗口浏览可能正开着这个 App 的面板：先收掉，再做。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
- 还没在真触控板、Magic Mouse 上确认过；真机探针 `--dock-gestures` 已写好（只在临时 App 自己的 Dock 图标上滑，

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
  “铺开所有窗口”那一步只记下不真的铺开），还没跑。打开的叠放要动用户自己的 Dock，探针不做，只打印一行 `MANUAL`

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
  留给人手试：把“应用程序”叠放以网格打开，在正在运行的 App 格子上快速上下滑，什么都不该发生。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。


> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
**菜单栏上的手势不做。** Swish 在菜单栏上往下滑是把窗口全部最小化、往上滑放回来、轻点两下取消吸附。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
有刘海的 Mac 上这块地方已经归刘海：两指在刘海上往上推是全部收进刘海、往下拉是拿回来，方向正好和 Swish 反着；

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
同一条菜单栏，左边一种意思、中间另一种，只会让人记混。菜单栏上的滚动也常被 Ice、Bartender 这类整理菜单栏的工具

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
用来显示藏起来的图标。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。


> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
出处（2026-09-28 读取）：[Swish 官网](https://highlyopinionated.co/swish/)（“Arrow, WASD, IJKL and Dvorak hotkeys”，

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
Dock 与菜单栏手势）；[Swish 更新记录](https://highlyopinionated.co/swish/changelog)：1.7 方向快捷键（方向键或 WASD，

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
⌫ 或 X 居中）、1.7.1 Dvorak（,AOE + Q）、1.8.1 Vim（HJKL）、1.2 菜单栏手势（轻点两下取消吸附、往下滑最小化、往上滑放回）。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
Dock 图标上往下滑最小化、往上滑恢复、捏合退出，见 [少数派的介绍](https://sspai.com/post/55285)（官网只列了手势名，没写 Dock 上各是什么）。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
程序坞的 scroll-to-open 见 [macos-defaults.com](https://macos-defaults.com/dock/scroll-to-open.html)。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。


> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
## 分屏（Split View）

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。


> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
两扇窗口刚好左右拼满一块屏（半屏 + 半屏、魔法平铺的 6:4……）时，中间出现一根小竖条（竖着放的屏幕上下拼满时是横条），

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
和 iPadOS 一样：拖它，两扇一起变；松手按速度吸到三分之一、一半、三分之二；推到屏幕边，被推过去的那一扇让开进侧拉，

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
靠它被推去的那一边，另一扇铺满。两扇都能撤销回拖之前的样子。怎么拼出两半，照 iPadOS 26 的做法：先把一扇甩到一边、

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
再把另一扇甩到另一边；或者从启动台把 App 拖到半屏。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。


> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
不止两扇：四角、三分、网格、魔法平铺带侧栏，排好的窗口之间每条缝都有一根把手，拖它，这条缝两边的窗口一起变

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
（Swish 的“拖分隔线同时调多扇”，这里对每一种排法都成立）。松手吸到六分之一、四分之一、三分之一、一半……里离得最近、

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
而且每扇都不窄于 240 点的那一格；只有两扇拼满一块屏时，推到边上才让一扇进侧拉。四角时竖缝和横缝在正中交叉，

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
两根把手各自挪到较长那一段的中点，不叠在一起。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。


> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
只认最前面那一层排好的窗口：有别的窗口浮在它们前面、其中一扇收起了、侧拉了、在卷轴里，把手都收起来。设置 → 卷帘 → 排布 →

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
**分屏把手**可以关。平时两秒看一次窗口表、有竖条时半秒一次，切 App、排窗口、换桌面时立刻看一次，只问 WindowServer，不问各个 App。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。


> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
## 和 App 自己的手势共存

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。


> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
所有输入都是旁听，不拦截（见下面“为什么只旁听”）：App 照常收到这些滑动。所以规则是

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
**指针下的控件自己用的方向，归它；我们只接它不用的**。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。


> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
- 能滚动的内容（网页、列表、表格、文本）：整下手势都归 App。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
- 自己用左右滑的控件：左右归 App，上下和张合仍归我们。Safari 的标签页实测是

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
  `AXRadioButton/AXTabButton`，当前标签那个宽胶囊里嵌着地址栏（`AXTextField`），左右滑是

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
  切换标签；同类的还有标签组、文本框、搜索框、滑块。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
- 一下手势一开始认出的方向如果归 App，这一整下都不接：斜着切 Safari 标签、手指往上飘，

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
  也不会被认成“上滑收起”。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
- 判定用辅助功能查询，是在手势开始后异步做的；查完之前浮窗不出现，查完按已经走过的位移

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
  更新动作；首次越过方向门槛的意图会保留。即使确认前手指已经转向，也不会把原本的切标签

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
  手势改判成收起窗口。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
- 探针里用真 Safari 做过只读核对：标签按钮上的元素链是

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
  `AXImage < AXTabButton < AXOpaqueProviderList < AXGroup < AXToolbar`，左右判给 Safari。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。


> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
## 提示浮窗

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。


> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
照本机实测的系统音量浮窗做（2026-09-24，Mac17,4，macOS 27.0）：浮窗由 MenuBarAgent 画，

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
窗口层级 101，窗口 352×153（含阴影边距），里面是一条约 290×63 的玻璃胶囊；上面一行标题，

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
下面一条两端带图标的进度条；挂在菜单栏里对应图标的正下方，图标同时亮起；最后一次按键后

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
约 1.5 秒消失；窗口本身没有位移或透明度动画。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。


> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
手势浮窗用同样的尺寸和结构，材质跟系统一致（macOS 26 起是玻璃；旧系统是 HUD 材质；

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
减少透明度时不透明）。位置不同：音量键没有来源，所以系统把浮窗放在菜单栏；手势有明确的

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
来源，浮窗挂在那条标题栏下面 10 点、以指针为中心（卷帘条则挂在卷帘条下面），和系统音量

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
浮窗在同一层级，盖得住卷帘条和看一眼的卡片。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。


> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
- 进度条跟手指 1:1 走，不做插值。走满时进度条变成强调色，终点图标弹一下（弹簧：response

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
  0.3 秒、阻尼比 0.6），同时向 Force Touch 触控板请求一次轻触感。后台 App 的触感能否在真机上

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
  触发还没确认。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
- 左滑时终点图标放在左边、从右往左填：填充方向永远和手指同向。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
- 两端图标：起点是窗口现在的样子，终点是松手后的样子。收起用自绘的“淡轮廓 + 顶上一条实心

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
  卷帘条”，排布用和窗口浏览同一套图标。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
- 出现 0.12 秒淡入；执行后停 0.45 秒再 0.2 秒淡出；取消时进度条退回、0.15 秒淡出。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
  减少动态效果时去掉弹跳。执行后给 VoiceOver 播报动作名。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
- 浮窗不接鼠标、不抢焦点、不进 ⌘Tab 和窗口循环。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。


> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
## 怎么判定

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。


> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
- **方向**：手指走 10 点以后才认方向；换方向要比原方向多走 1.25 倍，免得在 45° 附近来回跳；

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
  往回拉到起点附近，浮窗消失，松手不做事。方向已换算掉“自然滚动”设置，跟手指走。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
- **执行**：沿方向走满 56 点是“松手即执行”。松手时按速度投射落点（Apple《Designing Fluid

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
  Interfaces》的指数衰减形式，减速率 0.99，即速度 × 0.099 秒），只看最后 50 毫秒的速度：

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
  快速一甩走了 18 点以上就算数；过了门槛又往回甩，照样取消。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
- **张合**：累计缩放 0.22 走满，0.03 以内不认，至少 0.08 才可能执行。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
- **区域**：先用 WindowServer 的窗口表粗判——指针下最上面的是别的 App 的普通窗口，离上沿

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
  160 点以内；再用辅助功能确认——指针下不是网页、列表、表格、文本这类本来就能滚动的内容，

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
  而且落在双击收起用的同一套标题栏高度里。确认之前不显示、不执行。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
- 换桌面、关掉设置时，进行中的手势直接取消。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。


> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
## 为什么只旁听

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。


> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
两指滚动每秒上百个事件。主动的事件钩子（event tap）要在回调里决定放行还是吞掉，回调一旦

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
被主线程上别的活卡住，全系统的滚动都会跟着卡。手势这里只旁听：两指滑动用被动的全局事件

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
监听，系统把事件副本异步送来，原事件照常送到目标 App，WindowShade 再忙也拖不慢别人。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。


> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
张开和捏合不一样：被动的全局监听根本收不到。实测（2026-09-24）同时开着两种监听、正常用

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
触控板 90 秒，被动监听收到 0 个张合类事件，只读事件监听（listen-only tap）收到 5983 个触控板

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
手势事件，其中有张合。所以张合改用只读事件监听：它同样不拦截、不改事件，系统也不会等它的

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
回调；它跑在自己的线程上（手指一放上触控板，这一类事件每秒约 60 个），回调里只认出张合，

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
再转给主线程，不做辅助功能查询。只读监听需要辅助功能授权，授权晚于启动时每 3 秒再试一次。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。


> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
代价是吞不掉事件：标题栏上的这几下滚动，目标 App 也会收到。绝大多数 App 的标题栏和工具栏

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
收到滚动不做事；能滚动的地方（比如标签多时 Safari 能横向滚动的标签栏）会被辅助功能确认

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
认出来，不当作手势。卷帘条是 WindowShade 自己的窗口，用本地监听，手势期间把事件吞掉。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。


> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
Swish 也在标题栏上认两指手势，两边同时响应会对同一下滑动各做一件事。所以 Swish 在运行时，

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
标题栏上的手势交给它，设置里会写明；卷帘条上的下拉照常。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。


> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
## 设置

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。


> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
设置 → **卷帘** → 触发 → **标题栏手势**，默认打开。键盘上的四个排布快捷键在设置 → **快捷键** →

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
排布当前窗口，新装的默认不占，各自可以录、改键或关掉；更多排法里的 **方向键换成字母** 一下把这四个换成 WASD / IJKL / HJKL，

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
点“方向键”换成 ⌃⌘ 方向键。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
Dock 图标上的两指上下滑在设置 → **窗口浏览** → 触发，默认关（键 `Dock.swipeGestures`）；同一组里的“再点一下 Dock 图标，

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
让开这个 App”对换机的人默认关（键 `Dock.clickToHide`）。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。


> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
## 代码

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。


> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
| 文件 | 内容 |

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
| --- | --- |

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
| `prototype/Core/TrackpadGesture.swift` | 识别状态机：方向、进度、门槛、速度投射、张合。纯逻辑 |

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
| `prototype/Overlay/GestureHUD.swift` | 提示浮窗：玻璃胶囊、进度条、两端图标、弹跳与淡入淡出 |

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
| `prototype/App/TrackpadGestures.swift` | 控制器：事件监听、区域判定、执行（收起、展开、排布与撤销） |

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
| `prototype/App/GestureProbe.swift` | 真机探针 `--gesture` |

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
| `prototype/Core/DirectionKeys.swift` | 方向键换成字母：四套键位、撞车时谁先来算谁、换回来的账。纯逻辑 |

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
| `prototype/App/DirectionKeyPresets.swift` | 设置里点一下时读写快捷键、重新注册、刘海上说换了什么 |

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
| `prototype/Core/DockSwipeTrack.swift` | Dock 图标上的上下滑：走多远、多直、多久才算，Dock 那一带的粗筛。纯逻辑 |

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
| `prototype/App/DockSwipe.swift` | Dock 图标上的两指上下滑：被动监听、问 Dock 是哪个图标、让开或铺开这个 App 的窗口 |

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
| `prototype/App/DockSwipeProbe.swift` | 真机探针 `--dock-gestures`：只在临时 App 自己的 Dock 图标上滑 |

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
| `prototype/App/GlobalShortcuts.swift` | 全局快捷键的读写、查冲突；`InstallHistory`：新装还是升级，决定没动过的快捷键是什么 |

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
| `prototype/Core/DockClickGuard.swift` | 再点一下 Dock 图标：有看不见的窗口时不让开的分类、换机的人默认关。纯逻辑 |

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
| `prototype/App/DockClickHide.swift` | 再点一下 Dock 图标：被动监听、查窗口表和桌面、让开或把最小化的一扇还原 |

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
| `prototype/App/QuietDefaultsProbe.swift` | 真机探针 `--quiet-defaults`：只读，打印认成了新装还是升级、用着哪些快捷键、让开这个 App 开不开 |

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。


> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
## 验证

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。


> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
```sh

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
bash tests/run-gesture-tests.sh                   # 识别状态机：方向、门槛、甩动、尺寸梯子、控件归属、张合

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
bash tests/run-rectangle-keymap-tests.sh          # Rectangle 键位、方向键换成字母（四套键位、撞车、换回来）

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
bash tests/run-dock-swipe-tests.sh                # Dock 图标上的上下滑：门槛、直不直、多久、Dock 那一带

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
bash tests/run-quiet-defaults-tests.sh            # 快捷键默认不占、升级照旧；再点一下 Dock 图标的守卫和默认值

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
cd prototype && ./build.sh --stage                # 签名隔离构建

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
cd .. && bash tests/run-glance-probe.sh --gesture # 真机探针：独立临时 App，解锁状态下运行

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
bash tests/run-glance-probe.sh --dock-gestures    # 真机探针：临时 App 自己的 Dock 图标上下滑（Dock 要露在屏幕上）

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
```

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。


> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
真机探针把合成的两指滚动事件直接交给手势控制器：不动用户的指针、不影响别的 App，但走真实的

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
事件解析、标题栏确认、浮窗和窗口操作。张合事件没法用公开 API 合成，探针直接调用张合入口——

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
所以第一版探针全过，真机上的张合却从没生效：输入那一层被绕过了。现在张合的输入来自只读

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
事件监听，这一层要在真触控板上确认。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
加 `--shots` 会在 `.build/glance-tests/` 下截浮窗所在的一小块区域。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。


> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
2026-09-24 解锁状态下的结果（Mac17,4，macOS 27.0；临时 App 两扇窗，收起走最小化；第一行是对用户正开着的 Safari 做的只读检查）：

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。


> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
```

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
PASS gesture: Safari tab under the pointer keeps left/right for tab switching (chain: AXImage < AXTabButton < AXOpaqueProviderList < AXGroup < AXToolbar)

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
PASS gesture: swiping in the window's content does nothing

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
PASS gesture: pinching with nothing to undo says so and leaves the window alone

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
PASS gesture: right swipe → right half; HUD 290x63, top 14pt below the title bar, armed before release

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
PASS gesture: pinch undoes the placement (window back where it was)

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
PASS gesture: spread fills the screen, pinch puts it back

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
PASS gesture: pulling down on the title bar fills; pushing up on the filled window puts it back (not rolled up)

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
PASS gesture: a quick second push in the same direction is ignored (no double step on the ladder)

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
PASS gesture: mouse wheel — 2 notches do nothing, 3 notches down fill, 3 notches up put it back

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
PASS gesture: double tap (smart zoom) fills, and again puts it back

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
PASS gesture: after a screen change a filled window the system squeezed fills again; one resized by hand is left alone

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
PASS gesture: the window itself follows the fingers (69% rolled at the threshold); pulling back rolls it back untouched

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
PASS gesture: swipe up rolls the window up (strip 439–1024ms after release)

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
PASS gesture: pulling down on the strip unrolls the window under the fingers (41% rolled mid-gesture)

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
PASS gesture: pulling down on the strip expands it

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
PASS gesture: double tap on the strip expands it

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
```

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。


> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
松手到卷帘条出现 439–1024ms，是最小化路径本身的收起耗时（见 [看一眼说明](glance.md) 的“收起有多快”），

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
手势只在松手那一刻调用和双击相同的收起入口。浮窗截图核对过：未走满时白色进度、终点图标半透明；

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
走满后进度和终点图标变成强调色。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。


> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
探针第一次跑就抓到一个问题：标题栏上面其实常盖着不接鼠标的透明大窗（Dock 层级 20、截图工具

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
层级 24），只看窗口表会以为指针落在它们上面。现在直接用系统投递事件时带的目标窗口号

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
（`NSEvent.windowNumber`，实测就是指针下真正接收滚动的那扇窗），合成事件才退回实时窗口表。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。


> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
真触控板上已确认（2026-09-24/25 用户实机，日志核对）：左右半屏、下拉铺满、上推还原、捏合撤销、

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
上滑收起、卷帘条下拉展开、Safari 标签上左右滑让给 Safari、两指轻点两下铺满与还原。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
还没在真设备上确认的：Magic Mouse（这台 Mac 当时没连）、后台 App 的触感。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。


> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
实机还抓到一个问题：上滑收起后指针正好停在卷帘条绿色按钮的位置，0.55 秒后被当成“悬停绿色

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
按钮”，转发给真窗口弹系统窗口管理菜单，窗口随即被展开。双击收起时指针多在标题栏中间，很少

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
撞上；手势收起时指针停在哪都有可能。现在卷帘条出现那一刻指针就在绿色按钮上的话，先离开一次，

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
悬停转发才恢复；指针从别处移过来、按下绿色按钮不受影响（`NativeProxyOverlayWindow`）。

> 2026-10-03：鼠标、妙控鼠标、妙控板、Siri 遥控器的新一轮设计（整合 Mos、Mac Mouse Fix 的思路）见 [input-devices.md](input-devices.md)。
