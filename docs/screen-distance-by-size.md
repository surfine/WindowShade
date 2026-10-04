# 屏幕距离按尺寸的类比推论

2026-10-04。这些数是类比推论，不是已经做出来的功能，也不是 Apple 对 Mac 的官方屏幕距离。没有改 App，没有在这台 Mac 上测量。

Mac 用户手册写：看 Mac 太近，没有提示。见 [screen-distance.md](screen-distance.md)。那篇写明不编一个英寸数去冒充官方阈值。本文的英寸和公分都标成推论。1 吋 = 2.54 公分，用来把公式结果换成公分。12 吋换成 30.48 公分，是公制换算；繁体 iPhone 手册写的 30 公分仍以那篇为准，本文不另造第三个官方厘米数。

## 两个数

| 名字 | 在问什么 | 手机上 Apple 怎么写 |
| --- | --- | --- |
| 视网膜设计观看距离 | 在这个距离上，像素对眼睛的张角小到大约 1 角分，像素连成一片 | iPhone 4 发表会口述：大约 300 ppi，拿在大约 10 到 12 吋。新闻稿只写 326 ppi 和 “a normal distance”，没有英吋 |
| 贴太近该提醒的距离 | 拿得太近、而且持续一段时间，请你拿远一点 | 屏幕距离：低于 **12 吋**。支持文章说的是眼疲劳和近视风险，没有写 ppi，没有写视网膜 |

人机界面指南里的观看距离是第三件事：给内容尺寸用的习惯，不是警报。见下节。

## 12 吋和 iPhone 的视网膜距离

两数靠近。它们不是同一条规格。

iPhone 4 的面板是 326 ppi。按下面的 1 角分公式，像素张角等于 1 角分的距离是 **10.5 吋（26.8 公分）**。Steve Jobs 在 WWDC 2010 说的是大约 300 ppi、大约 10 到 12 吋，并说 326 ppi “comfortably over that limit”。10.5 吋落在他口头的 10 到 12 吋里面。他说的「大约 300」不等于 326。按公式，10 吋对应约 344 ppi，12 吋对应约 287 ppi，都不是 326。

屏幕距离是 2023 年的功能，阈值写死 12 吋。支持文章讲长时间贴着看会增加眼疲劳和近视风险，没有把这条线和 2010 年的视网膜定义接在一起。

下面三件事说明提醒线没有跟着「这块屏的视网膜距离」走：

- iPhone 16 的规格是 460 ppi。公式给出 **7.5 吋（19.0 公分）**。屏幕距离仍是 12 吋。密度高了，提醒线没有跟着近。
- iPad（第 3 代）规格是 264 ppi。公式给出 **13.0 吋（33.1 公分）**。2012 年新闻稿只写 “a normal distance”，没有英吋。现场报道写预期观看距离大约 15 吋（见来源；没有 Apple 发布的逐字稿）。15 吋对不上 13.0 吋。在 15 吋上，1 角分只需要约 229 ppi；264 ppi 更密，所以「15 吋分不清像素」可以成立，但 15 不是公式算出的那个距离。屏幕距离对 iPad 用的仍是和 iPhone 一样的 12 吋，见 [screen-distance.md](screen-distance.md)。12 既不是 13.0，也不是报道里的 15。
- 指南里 iPhone 的观看距离是不超过一两英尺，下限碰巧靠近 12 吋。那是内容该做多大，不是屏幕距离的触发条件。

所以：12 吋是 Jobs 那句话的远端，也是后来健康功能的阈值。和「326 ppi、约 10 到 12 吋」挨着，Apple 没有写它们是同一个数。后来的手机把这两数拉开了。

## 公式

常用的视网膜算法：在设计观看距离上，一个像素对眼睛的张角小于约 1 角分（1/60 度），20/20 视力就分不清这个像素。

一个像素的边长是 1/ppi 吋。距离 d 吋时，张角 θ 满足 tan θ = (1/ppi) / d。令 θ = 1 角分：

d（吋）= 1 / (ppi × tan(1′))

1 角分的正切和它的弧度几乎一样。1′ = π/10800 弧度，10800/π ≈ 3437.75。本文把常数写成 **3438**：

ppi ≈ 3438 / d　　d ≈ 3438 / ppi

公分 = 吋 × 2.54。表里的吋和公分都按这个式子四舍五入到小数点后一位。

Apple 没有公布这条式子。下面用官方写过的 ppi 和距离去对。对不上就写对不上。

| 出处 | Apple 写下的距离 | 用来除的 ppi | 公式 | 对得上吗 |
| --- | --- | --- | --- | --- |
| [WWDC 2010 口述](https://nonstrict.eu/wwdcindex/wwdc2010/keynote/)（转写，不是新闻稿） | 大约 300 ppi，大约 10 到 12 吋 | 规格上的面板是 326，不是 300 | 326 → 10.5 吋；300 → 11.5 吋 | 10.5 落在 10–12 里。300 不等于 326 |
| [iPhone 4 新闻稿](https://www.apple.com/newsroom/2010/06/07Apple-Presents-iPhone-4/) | “a normal distance”，没有英吋 | 326 | 10.5 吋 | 新闻稿没有英吋。对不上，也证不了 |
| [iPad 新闻稿](https://www.apple.com/newsroom/2012/03/07Apple-Launches-New-iPad/)（2012-03-07） | “a normal distance”，没有英吋 | [规格 264](https://support.apple.com/en-us/111992) | 13.0 吋 | 新闻稿没有英吋 |
| iPad 现场报道 | The Verge 写 Schiller 说明预期在 15 吋观看。MacStories 另写 iPhone 约 10 吋、iPad 约 15 吋，引号只罩住 “Retina Display” 那半句 | 264 | 13.0 吋。15 吋对应约 229 ppi | **对不上。** 差大约 2 吋。15 不当公式的输入 |
| [MacBook Pro 新闻稿](https://www.apple.com/newsroom/2012/06/11Apple-Introduces-All-New-MacBook-Pro-with-Retina-Display/)（2012-06-11） | “a normal viewing distance”，没有英吋 | 新闻稿写 220 | 15.6 吋 | 英吋**未知**。不把 15.6 写成 Apple 说过的距离 |
| [iMac 5K 新闻稿](https://www.apple.com/newsroom/2014/10/16Apple-Introduces-27-inch-iMac-with-Retina-5K-Display/)（2014-10-16） | 没写观看距离，没写 ppi。写了 5120×2880 | 见下节，Studio Display 规格写 218 | 218 → 15.8 吋 | 观看距离**未知** |
| [屏幕距离](https://support.apple.com/en-us/105007) | 12 吋，不按机型改 | iPhone 16 是 [460](https://www.apple.com/iphone-16/specs/) | 460 → 7.5 吋 | **对不上。** 提醒线不跟 ppi |

另有一套更严的算法：把眼睛算成大约 50 周/度，12 吋要大约 477 ppi 才分不清线对。这是 Raymond Soneira 对 Jobs 口述的反驳（[Wired](https://www.wired.com/2010/06/iphone-4-retina/)），不是 Apple 的 300 ppi。[DisplayMate](https://www.displaymate.com/iPad_ShootOut_1.htm) 把 Apple 这套对应到 20/20、1 角分，并写 326 ppi 从大约 10.5 吋起才够。那是第三方核对，不是 Apple 的式子。本文的类比不用 477。

## 类比规则

规则写死，再算数。

手机上，只在最初那代大致成立的前提是：贴太近的线，等于这块屏的视网膜设计观看距离。电脑每一档用同一条：

**眼睛到这块屏，近于该面板的 1 角分距离，就算贴太近。**

d = 3438 / ppi

ppi 用 Apple 技术规格印出来的整数。对角线用规格里的实际对角线（商品名叫 14 吋的，规格写 14.2 吋）。不按对角线把阈值拉远：像素一样大，类比距离就一样。14 吋和 16 吋 MacBook Pro 都是 254 ppi，两条线相同。

不把 326 ppi 强行对齐到 12 吋再放大。那一放大约是 12 / 10.5 ≈ 1.14。Apple 没有公布这个倍数，而且 iPhone 16 已经说明提醒线不跟 ppi 走。本文不加这成四。

桌面那一档另算，不并进这条线。见下节。

## 各档推论

查阅日期 2026-10-04。商品名里的 12、13、14、15、16、27 吋，Apple 都有过对应面板。12 吋和 15 吋不是从别的尺寸外推。

| 档 | 类比的贴太近线（近于这个数） | ppi | 公式 | 面板 |
| --- | --- | --- | --- | --- |
| 12 吋笔记本 | **38.6 公分（15.2 吋）** | 226 | 3438/226 | [MacBook（Retina, 12-inch, Early 2015）](https://support.apple.com/en-us/112442)：12 吋对角线，2304×1440，226 ppi。这一档用这一页 |
| 13 吋笔记本 | **39.0 公分（15.3 吋）** | 224 | 3438/224 | 当前 [13 吋 MacBook Air](https://www.apple.com/macbook-air/specs/)：商品名 13 吋，规格对角线 13.6 吋，2560×1664，224 ppi |
| 13 吋，上一代 | **38.5 公分（15.1 吋）** | 227 | 3438/227 | [13 吋 MacBook Pro](https://support.apple.com/en-us/111997)（13.3 吋，到 2020 年的 M1）：2560×1600，227 ppi。和 224 差 0.5 公分，两数都留 |
| 14 吋笔记本 | **34.4 公分（13.5 吋）** | 254 | 3438/254 | 当前 [14 吋 MacBook Pro](https://www.apple.com/macbook-pro/specs/)：规格对角线 14.2 吋，3024×1964，254 ppi。没有 14.0 吋这块面板 |
| 15 吋笔记本 | **39.0 公分（15.3 吋）** | 224 | 3438/224 | 当前 [15 吋 MacBook Air](https://www.apple.com/macbook-air/specs/)（2023 年起）：规格对角线 15.3 吋，2880×1864，224 ppi |
| 15 吋，上一代 | **39.7 公分（15.6 吋）** | 220 | 3438/220 | [15 吋 MacBook Pro](https://support.apple.com/en-us/112576)（2012 年起，15.4 吋）：2880×1800。新闻稿写 220 ppi，规格页同样写 220 |
| 16 吋笔记本 | **34.4 公分（13.5 吋）** | 254 | 3438/254 | 当前 [16 吋 MacBook Pro](https://www.apple.com/macbook-pro/specs/)：规格对角线 16.2 吋，3456×2234，254 ppi。和 14 吋同一密度，同一条线 |
| 27 吋显示器 | **40.1 公分（15.8 吋）** | 218 | 3438/218 | [Studio Display](https://support.apple.com/en-us/111890)：27 吋，5120×2880，规格写 218 ppi。2014 年 27 吋 iMac Retina 5K 新闻稿是同一分辨率，没印 ppi。5120×2880 的对角线约 5874 像素，除以 27 吋约 217.6，四舍五入即 218 |

254 ppi 的 14 吋、16 吋，线在 34.4 公分。224 到 226 ppi 的 12、13、15 吋，线在大约 39 公分。密度更高，像素更小，要贴得更近才分得清像素，所以提醒的类比线更近。不按「屏幕更大就该更远」去改。

24 吋 iMac 的规格也写 218 ppi（[支持页](https://support.apple.com/en-us/121556)，对角线实际约 23.5 吋）。同一密度，类比距离和 27 吋相同。24 吋不单列一档。

没有一档因为缺少 Apple 的 ppi 而标未知。Apple 没写过的，是这些面板的观看距离英吋，以及 Mac 的屏幕距离阈值。那两格仍是未知。

## 和桌面距离并排

公式给出的线大约 34 到 40 公分。人坐在桌前常用的距离是大约 **50 到 100 公分**（这次对照用的范围，不是在这台 Mac 上量的，也不是 Apple 公布的数）。[macOS 人机界面指南](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos) 写坐在桌前大约 1 到 3 英尺，约 30 到 91 公分。两段都比「贴太近」宽。

| | 1 角分类比线 | 桌面大约 50–100 公分 | 指南的 1–3 英尺 |
| --- | --- | --- | --- |
| 落在哪 | 34.4–40.1 公分（13.5–15.8 吋） | 比上面每一档都远。最近端 50 公分，仍比 27 吋那条线远约 10 公分，比 14/16 吋那条线远约 16 公分 | 大约 30–91 公分。下限靠近手机的 12 吋，上限是坐远 |
| 拿来做什么 | **类比的贴太近线用这列。** 近于它，才叫贴太近 | **不拿来当提醒阈值。** 这是坐着工作的距离。拿 50 公分当「贴太近」，人正常坐在桌前就会被提醒 | **不拿来当提醒阈值。** 指南自己写的是内容尺寸和人机，见 [screen-distance.md](screen-distance.md) |
| 不拿来做什么 | 不写成「建议把屏幕摆在这里」。坐到 50–100 公分时像素张角更小，更分不清，那是平常观看 | 不写成视网膜距离 | 不写成屏幕距离的触发条件 |

14 吋和 16 吋的 34.4 公分，已经短于一手臂支在桌上的常见距离。人正常坐着不会碰到这条线。会碰到的是把脸凑到大约 34 公分以内。27 吋的 40.1 公分同样短于 50 公分。两条都留下：提醒用 1 角分那条；50–100 公分只说明「平常坐得更远」。

## 指南里的观看距离

给内容用，单位是英尺，没有 ppi。

| 平台 | 指南原意 | URL |
| --- | --- | --- |
| iPhone | 拿在手里时，观看距离多半不超过一两英尺 | https://developer.apple.com/design/human-interface-guidelines/designing-for-ios |
| iPad | 多半在大约 3 英尺以内 | https://developer.apple.com/design/human-interface-guidelines/designing-for-ipados |
| Mac | 坐在桌前，大约 1 到 3 英尺 | https://developer.apple.com/design/human-interface-guidelines/designing-for-macos |

一两英尺的下限和 12 吋同一数量级。指南没有把这个下限写成屏幕距离。

## 来源

| 页面 | URL |
| --- | --- |
| 屏幕距离考据（Mac 没有官方英吋阈值） | [screen-distance.md](screen-distance.md) |
| 什么是屏幕距离 | https://support.apple.com/en-us/105007 |
| Mac 上打开屏幕距离（看 Mac 太近没有提示） | https://support.apple.com/guide/mac-help/turn-on-screen-distance-mchle20721bd/mac |
| iPhone 4 新闻稿 | https://www.apple.com/newsroom/2010/06/07Apple-Presents-iPhone-4/ |
| iPhone 4 规格，326 ppi | https://support.apple.com/en-us/112562 |
| WWDC 2010 口述转写（大约 300 ppi，10 到 12 吋） | https://nonstrict.eu/wwdcindex/wwdc2010/keynote/ |
| 同一场口述的另一份转写 | https://singjupost.com/steve-jobs-introduces-iphone-4-facetime-at-wwdc-2010-full-transcript/ |
| Soneira：12 吋约 477 ppi（更严，本文不用） | https://www.wired.com/2010/06/iphone-4-retina/ |
| DisplayMate：326 ppi 与约 10.5 吋（第三方，不是 Apple 的式子） | https://www.displaymate.com/iPad_ShootOut_1.htm |
| iPad 新闻稿（2012-03-07） | https://www.apple.com/newsroom/2012/03/07Apple-Launches-New-iPad/ |
| iPad（第 3 代）规格，264 ppi | https://support.apple.com/en-us/111992 |
| The Verge：现场报道，iPad 预期 15 吋 | https://www.theverge.com/2012/3/7/2850299/ipad-3-retina-display |
| MacStories：现场报道，10 吋与 15 吋 | https://www.macstories.net/news/this-is-the-new-ipad-our-overview/ |
| MacBook Pro Retina 新闻稿，220 ppi，正常观看距离无英吋 | https://www.apple.com/newsroom/2012/06/11Apple-Introduces-All-New-MacBook-Pro-with-Retina-Display/ |
| 15 吋 MacBook Pro 规格，220 ppi | https://support.apple.com/en-us/112576 |
| 13 吋 MacBook Pro 规格，227 ppi | https://support.apple.com/en-us/111997 |
| 12 吋 MacBook 规格，226 ppi | https://support.apple.com/en-us/112442 |
| MacBook Air 规格，13.6 吋与 15.3 吋，224 ppi | https://www.apple.com/macbook-air/specs/ |
| MacBook Pro 规格，14.2 吋与 16.2 吋，254 ppi | https://www.apple.com/macbook-pro/specs/ |
| iMac Retina 5K 新闻稿，5120×2880，无 ppi、无距离 | https://www.apple.com/newsroom/2014/10/16Apple-Introduces-27-inch-iMac-with-Retina-5K-Display/ |
| Studio Display 规格，218 ppi | https://support.apple.com/en-us/111890 |
| 24 吋 iMac 规格，同样 218 ppi | https://support.apple.com/en-us/121556 |
| iPhone 16 规格，460 ppi | https://www.apple.com/iphone-16/specs/ |
| 指南，iPhone / iPad / Mac | 见上表 |

## 本文没有做的

没有改 App，没有改 [screen-distance.md](screen-distance.md) 里「不编一个英寸数」那句。没有把上表写进界面。Mac 上现在测不到眼睛到屏幕的距离，推论不能变成提示文案里的英吋。
