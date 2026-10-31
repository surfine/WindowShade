# 竞品调研 2026-10-31：经得起考验

上一轮是 2026-10-14／15（[竞品深挖](competitive-deep-dive.md)、[功能碾压](dominance.md)、[更新日志里的 know-how](changelog-knowhow.md)）。这一轮只记 10-15 以后新出的事和上一轮漏掉的事，目的是找出会让我们的设计出错的情况，再对到设计稿。画面上的结论在设计稿《[经得起考验](design-drafts/经得起考验.html)》。

四条线并行查，全部一手来源，读取日期都是 2026-10-31：Apple 自己（新闻稿、WWDC26、支持文档）、刘海 App 九家、窗口工具十几家、编程会话 App 五家。取不到的照写取不到，不拿二手描述补。

## 一、Apple：Mac 上的灵动岛

| 事实 | 来源 | 性质 |
| --- | --- | --- |
| 灵动岛来到 Mac，是 Spotlight、实时活动和 Siri 的新家；能接电话、控制音乐、接 AirDrop | [Apple 新闻稿 10-28](https://www.apple.com/newsroom/2026/10/apple-unveils-groundbreaking-macbook-pro-with-proled-xdr-display/) | Apple 说的 |
| 触控屏：轻点两下窗口铺满屏幕，甩一下排进位置；触控自动转成点按；有「更新的系统手势 API」 | 同上 | Apple 说的 |
| iPhone 的实时活动会自动出现在其它 Apple 设备上，包括「macOS 菜单栏」 | [WWDC26 223](https://developer.apple.com/videos/play/wwdc2026/223/) | Apple 说的；和新闻稿说的「岛」怎么对上，没公布 |
| 只绑 PROLED XDR 的 MacBook Pro 14/16；旧刘海机型会不会有，没说 | 新闻稿、[iThinkDifferent](https://www.ithinkdiff.com/dynamic-island-macbook-pro/) | 没公布 |
| Mac 上的尺寸、圆角、多个活动怎么并排、全屏和外接屏怎么办、第三方能不能放内容 | — | 全部没公布 |
| macOS 27 里有药丸形素材：AirPods 连上、专注模式、降噪、低电量、切换音频；Siri 是水滴形 | [MacRumors](https://macrumors.com/2026/10/28/pill-shaped-macos-27-dynamic-island-macbook-pro/)、[9to5Mac](https://9to5mac.com/2026/10/28/on-the-day-of-the-touchscreen-mac-launch-dynamic-island-elements-found-in-macos-27/) | 泄露，未证实 |
| 没有 Face ID，Touch ID 保留 | MacRumors | 报道 |

## 二、刘海 App

没有一家公开回应 10-28 的发布。

| App | 10-01 以后 | 值得记的 |
| --- | --- | --- |
| Boring Notch（GPL-3.0） | v2.8-rc.2（10-10）：跟着当前显示器走、隐藏来源 App 图标 | [#1728](https://github.com/TheBoredTeam/boring.notch/issues/1728) 杀掉 App 后正在播放的辅助进程还在跑；[#1577](https://github.com/TheBoredTeam/boring.notch/issues/1577) 通知镜像和通知中心撞车；[#1637](https://github.com/TheBoredTeam/boring.notch/issues/1637) 内存高 |
| Atoll（GPL-3.0） | 10 月无发布 | [#853](https://github.com/Ebullioscopic/Atoll/issues/853) 耗电是其它 App 加起来的 35 倍；[#877](https://github.com/Ebullioscopic/Atoll/issues/877) 双屏时计时器控件留在内建屏菜单栏；[#898](https://github.com/Ebullioscopic/Atoll/issues/898) 展开后悬停会位移；扩展端口改为只绑本机 |
| NotchNook | 官网连不上；Setapp 页显示为 MacNotch | 用户：M2 Air 很卡、外接屏设置重启后丢、激活时太宽 |
| Alcove、DynamicLake、MediaMate | 更新日志取不到 | DynamicLake 评测：系统更新后小毛病 |
| Droppy | GitHub 发布页 HTTP 451 | 授权从免费转付费的迹象，未证实 |
| 新进场：NotchDodo（9-18）、NotchPop（9-21） | — | 都是「有事才开口」；NotchDodo 摄像头在用时不打开；NotchPop 点一下钉住、⌥Space 关；两家都读编程助手的用量 |

## 三、窗口工具

没有一家宣布支持触控，也没有一家回应 10-28。

| App | 10-01 以后 | 值得记的 |
| --- | --- | --- |
| DockDoor | 1.41.0（10-15）：**标题栏、Dock 图标、菜单栏上的手势**；触控板滑动切换窗口；设置备份 | 和我们的标题栏手势正面重叠；[#1655](https://github.com/ejbills/DockDoor/issues/1655) 点预览后全系统鼠标键盘卡死到强制重启 |
| Rectangle | 2.0.3／2.0.4（10-05／10-20）：叠放窗口轮换、预览跟随「降低透明度」、少写几次辅助功能 | [#1922](https://github.com/rxhanson/Rectangle/issues/1922) Dock 自动隐藏时尺寸算错 |
| AltTab | 11.9.0（10-06）：第一次打开的引导和快捷键教学 | [#6143](https://github.com/lwouis/alt-tab-macos/issues/6143) 跑着时别的 App 的截图浮层慢几十秒 |
| Loop | 无正式发布；预发布有触控板手势 | [#1192](https://github.com/mrkai77/Loop/issues/1192) macOS 27.2 后触发键失效 |
| Paneru | 0.5.2（10-02）：显示器热插拔后重排、修 AX 句柄泄漏 | — |
| Wins、Swish、AeroSpace、Raycast、Magnet、Moom、BTT、WindowMizer | 10 月无可证实的发布 | Swish 官网「Ready for macOS 27」，只为触控板设计 |

## 四、编程会话 App

| App | 10-01 以后 | 值得记的 |
| --- | --- | --- |
| Vibe Island（闭源） | 1.0.53（10-10）、1.0.55（10-23）：卡上写做什么、为什么、终端要接手时写去哪；修复和卸载只动自己写的钩子；80% 额度提醒 | 评测：全局快捷键默认开、覆盖了 shell 的键位；授权会联网 |
| Open Island（GPL-3.0） | 无（最后 v1.2.1，9-15） | [#638](https://github.com/Octane0411/open-vibe-island/issues/638) App 关着时审批像坏了；[#693](https://github.com/Octane0411/open-vibe-island/issues/693) 辅助程序路径没了、事件静默丢失；[#672](https://github.com/Octane0411/open-vibe-island/issues/672)／[#744](https://github.com/Octane0411/open-vibe-island/issues/744) 子代理另起会话；1.1.3 过期的批准点按不改状态 |
| Vibe Notch（原 Claude Island） | — | [#112](https://github.com/farouqaldori/vibe-notch/issues/112) 一夜内存涨到约 64 GB 卡死 macOS |
| Conductor | 0.90 iOS 版（10-02）、0.92 遥控（10-23） | 和我们 iPhone 遥控器同一方向，细节页面没写 |
| Claude Code 本身 | — | 用户报告：钩子连不上时全部拒绝（[46193](https://claudeissues.com/issue/46193-permissionrequest-http-hook-fails-closed-when-endpoint-is-unreachable-contradict)，已关，修没修没证实）；VS Code 扩展里钩子不触发 |

## 五、拿来对我们的代码（2026-10-31，`main` 1e76fdd7）

- 钩子连不上 App：`tools/ws2-hook/main.swift` 任何错误都回 `{}`（没有决定），Claude Code 自己问；审批最多等 119 秒，和刘海的 120 秒租约对齐。**经得起。**
- 子代理：Claude Code 的子代理和主会话共用 `session_id`，钩子按会话编号上报，不会另起一张卡。**经得起，待加验收。**
- 钩子配置：只给用户拷贝，不写 `~/.claude`（`prototype/build.sh` 注释）。**经得起。**辅助程序在 App 包里，App 被搬走或删掉后设置能不能看出来，**待查**。
- 摄像头在用时的刘海：代码里只有刷脸用到摄像头状态，刘海不看。**缺。**
- 指挥页遇到 Claude 没登录：10-31 真跑时 CLI 回 `OAuth session expired`，页面回到就绪，探针看不到原因。**缺。**

## 六、口径

- 每条带来源和读取日期；Apple 说的、报道、泄露、用户报告分开写。
- 竞品的自我宣称只写成宣称。
- 界线照 [竞品深挖](competitive-deep-dive.md) §一：不绕过保护，不搬代码，GPL 只借思路。
- 这一轮没有装任何竞品，没有逆向。
