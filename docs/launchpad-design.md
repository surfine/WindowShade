# 启动台设计记录

2026-09-27，针对 R26–R29。目标是让找 App、整理主屏幕、把 App 放到窗口位置形成连续操作，同时保留 Mac 的键盘与辅助功能习惯。

## 参考如何落到产品

| 原始来源 | 本项目的取舍与实现 |
| --- | --- |
| [WWDC 2018：Designing Fluid Interfaces](https://developer.apple.com/videos/play/wwdc2018/803/) | 拖动跟随指针，松手后才落定；手势取消回到原页。文件夹从原图标展开、回到入口，连续切换不会把上一入口永久藏住。 |
| [WWDC 2025：Meet Liquid Glass](https://developer.apple.com/videos/play/wwdc2025/219/) 与 [HIG Materials](https://developer.apple.com/design/human-interface-guidelines/materials) | 搜索、完成和标题控件使用系统材质；图标内容区使用磨砂背景，不把所有内容都堆成玻璃。macOS 26 使用系统玻璃，旧系统使用 NSVisualEffectView。 |
| [WWDC 2023：Design dynamic Live Activities](https://developer.apple.com/videos/play/wwdc2023/10194/) | 形状和信息量跟随当前任务。主屏幕、文件夹、分类展开各自只呈现需要的内容；开始打开应用不冒充窗口已经放好。 |
| [HIG Motion](https://developer.apple.com/design/human-interface-guidelines/motion) | 减少动态效果时停止抖动和滑动弹簧；减少透明度或提高对比度时，文件夹与分类背景使用实色并加强边界。 |
| [HIG Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility) 与 [Drag and drop](https://developer.apple.com/design/human-interface-guidelines/drag-and-drop) | 提供资料库方向键导航、Return 打开、翻页键；辅助功能树暴露实际搜索表、翻页、完成和关闭文件夹入口。中文输入组词时不抢走命令。 |
| [Chan Karunamuni 的手电筒原始演示](https://x.com/chan_k/status/1835729051178451013) | 观察了窄光束与宽光束的直接反馈。应用到启动台的是“预览对应真实动作”：拖放目标说明窗口将去哪里，编辑预览可撤回，不能边拖边永久改变排列。 |
| [Chan 的 Dynamic Island 原始演示](https://x.com/chan_k/status/1570795751764295682) 与 [Apple 的设计介绍](https://developer.apple.com/news/?id=mis6swzt) | 以同一个对象连续变形来维持身份。启动台文件夹保持入口与展开对象的对应关系；快速关闭、再打开也必须成立。 |

上述实现是针对鼠标和键盘的设计推导，不是照搬 iPhone 动画参数。作者原始视频来自其公开主页链接；HIG 的正文通过 Apple 官方 DocC 数据核对。

## Face ID / Apple Pay 的启发与边界

[Apple Pay 的官方操作说明](https://support.apple.com/guide/iphone/make-purchases-with-apple-pay-iphbd4cf42b4/ios)区分用户发起、身份确认和完成。对窗口操作的启发是区分拖放意图、应用启动和窗口可用：等待真实窗口后才排布；用户重新打开启动台或再次发起操作，过期结果不能再移动窗口；原显示器消失时停止排布。

这里研究的是反馈与状态之间的关系。没有在本机执行支付，也没有逐帧实测 iPhone Face ID / Apple Pay 动画，因此不把它们的精确曲线或时长写成已验证依据。

## 完整性先于装饰

- 拖出文件夹只是预览；Esc 或启动台关闭会恢复拿起前的布局。
- 应用扫描晚于拖动结束返回时，按新目录校对刚完成的布局，不用旧快照覆盖用户操作。
- 重复应用路径只保留一次；重复或空文件夹编号确定性修复，保留已有有效编号与排列。
- 图标在后台分批绘制，最多四个并行工作项。尺寸或缩放变化后，旧任务不能覆盖新图。缓存按最近使用顺序控制在 32 MiB 预算内；这不是整个应用的内存上限。
- App 资料库覆盖完整应用目录；从主屏幕移除不会卸载应用。首次排列将工具类应用收进“其他”。
- 主屏幕壁纸在后台解码并模糊（照 macOS 15 启动台）；用户壁纸读不到时退到系统的 `DefaultDesktop.heic`，都用同一套缩略图选项，两条都失败才不铺图，全程不联网。
- 顶部的搜索框与页码点是各自独立的控件：搜索框平时在顶端、是平面磨砂；资料库时才扩成较大的玻璃样式，页码点单独摆在图标区下方。
- 负一屏只放本机实时数据：实时时钟、当月日历、正在运行的 App；不读日历事件，也不模拟第三方小组件。
- 迟到的 Spotlight 失败回调不能把已经收起的界面重新弹出来：每次 show / hide 都推进一个导航代次，只有回调仍属于当前这次导航、且界面确实不在显示时才恢复。

## 验证口径

模型测试检查目录、文件夹编号和排列完整性，也检查落点区域（含只有传入刘海矩形时才算 notch）。AppKit 测试检查真实视图中的停留合并、边缘翻页、取消、连续开合、扫描交错、键盘导航、辅助功能结构、材质回退与过期图像结果，以及负一屏的命中安全、顶栏/页码点的位置与编辑时隐藏。

生产构建的启动台探针使用临时应用窗口检查半屏和侧拉，并检查用户保存的排列未被改写。辅助功能结构检查不等于完整 VoiceOver 人工体验；程序化手势检查也不代替真实多指触控体验，主屏幕键盘操作（含负一屏）也尚未单独覆盖。打开 `Spotlight.app` 在本机因 launchd 失败，已改为读取系统设置里 Spotlight 的快捷键（`com.apple.symbolichotkeys` 第 64 项）再发送同一组按键；快捷键关着或没有辅助功能权限时留在 App 内的搜索。macOS 14/15 回退需要对应系统另行实机验收。
