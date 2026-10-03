# 来源与证据状态

查阅日期：2026-10-03。仅列实际使用的第一手材料；不附整份网页、讲稿或第三方实现。网页当前内容不等于已安装软件版本。未取得的内容与待真机项单独说明。

<a id="s01"></a>
## S01 · Swift 时钟

来源：[Swift 时钟](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0329-clock-instant-duration.md)。

Swift 官方 SE-0329；已读正文。ContinuousClock 在系统睡眠时继续前进，SuspendingClock 不包含睡眠时间。该提案随 Swift 5.7 实现；本工程统一最低 macOS 14。自然日统计另用 Calendar，不用连续时钟判断日期。

涉及：T1、L1、D1、D2。

<a id="s02"></a>
## S02 · Claude Code hooks

来源：[Claude Code hooks](https://code.claude.com/docs/en/hooks)。

Anthropic 官方；已读 PermissionRequest、配置、输入输出及生命周期部分。采用本次文档的最小 allow/deny/no-decision 子集。CLI 安装版本未核，不能据网页断言 Aaron 的版本支持全部事件。

涉及：A1、A2、A3、D1。

<a id="s03"></a>
## S03 · Codex hooks

来源：[Codex hooks](https://learn.chatgpt.com/docs/hooks)。

OpenAI 官方文档，官方开发者站入口跳转至此；已读正文。当前文档有 hooks.json、配置层合并、trust 审查与 PermissionRequest。不要继续沿用“Codex 没有该 hook”的旧假设，也不能绕过用户对 hook 命令的信任审核。

涉及：A1、A2。

<a id="s04"></a>
## S04 · Core Bluetooth 后台与状态恢复

来源：[Core Bluetooth 后台与状态恢复](https://developer.apple.com/library/archive/documentation/NetworkingInternetWeb/Conceptual/CoreBluetooth_concepts/CoreBluetoothBackgroundProcessingForIOSApps/PerformingTasksWhileYourAppIsInTheBackground.html)。

Apple 历史官方文档，标题和适用范围明确是 iOS；已读正文。只能说明该平台设计，不能据此声称 macOS App 会被自动重新拉起。对原生 iPhone/Watch 是否有可持续读取的特征，本材料没有给出保证。

涉及：L1、L2。

<a id="s05"></a>
## S05 · Codex App Server

来源：[Codex App Server](https://learn.chatgpt.com/docs/app-server)。

OpenAI 官方文档，developers.openai.com/codex/app-server/ 跳转至此；已读初始化、模型、线程、轮次、审批部分。方法和 JSON 在 reference 中逐项列出。实现必须锁定实际 CLI 版本及其 schema，不能把未来网页字段强塞给旧二进制。

涉及：D2、D6、A4。

<a id="s06"></a>
## S06 · hidutil 用户键映射

来源：[hidutil 用户键映射](https://developer.apple.com/library/archive/technotes/tn2450/_index.html)。

Apple TN2450，历史官方正文已读。例子使用 HIDKeyboardModifierMappingSrc/Dst，映射受 HID 服务生命周期影响。文档不等于验证了特定 Siri 遥控器的全部 usage、麦克风或按设备隔离行为。

涉及：I5、I7。

<a id="s07"></a>
## S07 · MultitouchSupport 历史头文件

来源：[MultitouchSupport 历史头文件](https://github.com/calftrail/TrackMagic/blob/master/MultitouchSupport.h)。

原作者公开的历史逆向头文件，已读；不是 Apple 官方 ABI。文件年代旧，注册/注销 callback 声明有不一致，当前 ABI 可信度低。没有复制实现；本包只记录接口事实与自行推导的候选布局。不能作为 MIT 可复制源码使用。

涉及：I2；详见 reference/private-abi.md。

<a id="s08"></a>
## S08 · AppKit 菜单、符号和控件

来源：[AppKit 菜单、符号和控件](https://developer.apple.com/documentation/appkit/nsmenuitem)。

Apple 官方 API 入口及可见搜索描述；NSMenuItem alternate 属性可查。文档网页部分依赖 JavaScript，未取得所有符号的完整 SDK 声明。本次另核原包现有 AppKit 用法；M1/S1/T2/A3/D3 仍须 Apple SDK 编译，不伪称已验证最低版本全部签名。

涉及：M1、S1、T2、T4、A3、D3、D4、I9。

<a id="s09"></a>
## S09 · ScreenCaptureKit

来源：[ScreenCaptureKit](https://developer.apple.com/videos/play/wwdc2022/10156/)。

Apple WWDC22，已读讲稿。框架用于屏幕内容捕获；不能推出可捕获所有受保护界面，更不能把捕获或遮罩等同于系统锁。A3 首轮文本活动不需要新开全屏捕获。

涉及：L4、A3、隐私审查。

<a id="s10"></a>
## S10 · 签名身份与嵌套代码

来源：[签名身份与嵌套代码](https://developer.apple.com/library/archive/technotes/tn2206/_index.html)。

Apple TN2206，历史官方正文已读。Designated Requirement 用于识别代码身份，嵌套可执行文件应按规则打包与签名。不同子系统有各自策略；没有据此承诺重签后 TCC 一定保留或一定清空。

涉及：A2、签名和 TCC 回归。

<a id="s11"></a>
## S11 · CBPeripheral 特征读取

来源：[CBPeripheral 特征读取](https://developer.apple.com/documentation/corebluetooth/cbperipheral/readvalue(for:)-91hhp)。

Apple 官方 API 入口；网页只取得 JavaScript 壳，未在 Apple SDK 编译。准确调用对象是 CBCharacteristic；完整声明在本机 CoreBluetooth swiftinterface 或 Xcode Quick Help 复核。L2 必须以真实 discovery 回包核 read 属性。

涉及：L2。

<a id="s12"></a>
## S12 · CGEvent tap

来源：[CGEvent tap](https://developer.apple.com/documentation/coregraphics/cgevent/tapcreate(tap:place:options:eventsofinterest:callback:userinfo:))。

Apple 官方 API 入口，网页正文未完整取得；对照了原包 HabitKeys 既有 tap 代码。callback、tapDisabled 状态和权限必须在 Apple SDK/真机验证。事件元数据本身不证明某个物理设备的可信身份。

涉及：I1、I2、I3、I7。

<a id="s13"></a>
## S13 · 安全输入

来源：[安全输入](https://developer.apple.com/library/archive/technotes/tn2150/_index.html)。

Apple TN2150，历史官方正文已读。Secure Event Input 是受保护输入机制，不能把无法收到输入当作应当绕过的错误。当前系统下哪些事件继续可见，应按设备和事件类型实测。

涉及：I2、I3、I7。

<a id="s14"></a>
## S14 · GameController 与 DualSense 扳机

来源：[GameController 与 DualSense 扳机](https://developer.apple.com/videos/play/wwdc2021/10081/)。

Apple WWDC21，已读讲稿和示例。GCDualSenseGamepad 的 leftTrigger/rightTrigger 使用 setModeFeedbackWithStartPosition(_:resistiveStrength:) 等方法。本包代码为原创，未复制演示实现；USB/蓝牙、后台、游戏让位、触控按下语义仍待真机。

涉及：I8。

<a id="s15"></a>
## S15 · itsytv-core 的角色与许可状态

来源：[itsytv-core 的角色与许可状态](https://github.com/nickustinov/itsytv-core)。

上游 README 已读；它是 Swift Apple TV 客户端，不是已经完成的遥控服务端。README 声明 MIT，但本次点击 LICENSE 链接失败，未取得许可全文，未锁定相关实现提交。不能断言它没有许可，也不能因此批准复制。

涉及：D5；先核固定提交的许可与依赖。

<a id="s16"></a>
## S16 · atv-core 服务端方向

来源：[atv-core 服务端方向](https://github.com/corvofeng/atv-core)。

上游 README 已读，Rust 服务端方向用于理解角色与消息流。原包指定提交 e14f8ca2a54745bb9bc7014aa48fd75a9d4bae25 的页面本次未成功取得，故未核该提交接口及许可覆盖。没有拷贝源码，也不引入其调试 Web 服务或证书放宽步骤。

涉及：D5。

<a id="s17"></a>
## S17 · Apple 协议核查入口

来源：[Apple 协议核查入口](https://developer.apple.com/support/terms/)。

Apple 官方协议索引已读；没有读取 Aaron 实际签署版本，不作法律合规裁定。“不上 App Store”不能替代适用 SDK/Developer Program 协议与模型许可的核查。

涉及：F2–F5 范围外风险记录。

## 上传快照

源码、产品要求与内部接口以原包相对路径定位。`validation/input-manifest.json` 记录参与清单的文件哈希，只表示输入版本，不表示清单每一文件都做了逐行审查。本报告不是 GitHub 最新分支审查。原包声明的真机环境保留为交接方记录，不升级成本次实测。
