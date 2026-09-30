# 安卓与苹果互联：可借鉴的协议和配件协作

2026-10-01。一手资料调研。以下设计尚未成为 WindowShade 的设备认证功能。

## 已核实的两条路线

| 路线 | 已公开的事实 | 对我们的意义 |
| --- | --- | --- |
| 配套 App | OPPO 的部分 iPhone/Mac 协作要求 O+ Connect；接电话、短信还受 Odialer 预装条件限制 | 自己的手机与手表 App 可以承担受控配对和当次确认。厂商未公布其私有协议，不能断言内部用了 ANCS |
| 直接协议互通 | Google Quick Share 与 AirDrop 点对点互传，使用“所有人，10 分钟”；2025-11-20 公告首先覆盖 Pixel 10。三星 2026-03-22 公告首先覆盖 Galaxy S26，并注明能力由 Google 提供、依赖 Wi-Fi 和蓝牙 | 证明互通可以做到系统分享入口里；不证明第三方获得了 Apple Watch 解锁授权 |

依据：[OPPO ColorOS 16 脚注 5/6](https://www.oppo.com/en/coloros16/)、[Google 安全博客原文](https://security.googleblog.com/2025/11/)、[三星公告及版本条件](https://news.samsung.com/us/samsung-airdrop-quick-share-galaxy-s26-series/)。这些是各公告发布时的范围，不是所有型号当前兼容性清单。Google 介绍了 Rust 解析层和 NetSPI 评估，但没有公开完整协议实现；评估结果不能当作我们自己的验证。

## 背后怎样分工

AirDrop 的论文分析显示：BLE 广播触发发现；AWDL 建立 Wi-Fi 直连；DNS-SD 找服务；HTTPS 执行 Discover、Ask、Upload。蓝牙负责轻量发现，大文件走 Wi-Fi。发现到设备、建立传输、确认身份是不同阶段。[PrivateDrop §2，USENIX Security 2021](https://www.usenix.org/system/files/sec21-heinrich.pdf)

Apple 也提供公开的蓝牙服务：[ANCS](https://developer.apple.com/library/archive/documentation/CoreBluetooth/Reference/AppleNotificationCenterServiceSpecification/Specification/Specification.html) 给配件通知访问，[AMS](https://developer.apple.com/library/archive/documentation/CoreBluetooth/Reference/AppleMediaService_Reference/Specification/Specification.html) 给媒体状态与控制，服务都可能动态出现或消失。这些文档没有提供机主认证或 Watch 解锁授权接口；也不能据此认定某安卓厂商的内部实现。

## 论文怎样改变我们的设计

| 原始研究 | 可采用的思路 |
| --- | --- |
| [Stute 等，MobiCom 2018：AWDL 协议分析](https://arxiv.org/abs/1808.03156) | 理解可用时间窗、同步和信道切换；按事件启动连接，不用持续高频扫描来换取“快” |
| [Heinrich 等，USENIX Security 2021：PrivateDrop](https://www.usenix.org/conference/usenixsecurity21/presentation/heinrich) | 手机号/邮箱的哈希仍可能泄露身份；我们不需要通讯录发现，使用受控配对的设备密钥更合适。研究中的低于一秒认证不是本项目成绩 |
| [Martin 等，PETS 2019：Continuity BLE 隐私](https://arxiv.org/abs/1904.10600) | 不广播稳定的个人标识、行为记录或身份模板，不积累陌生设备轨迹 |
| [Stute 等，USENIX Security 2019：AWDL 攻击分析](https://www.usenix.org/conference/usenixsecurity19/presentation/stute) | 设备发现必须视为不可信输入；连接、加密、身份和防重放分别验证 |

以上攻击研究是历史结果，不表示今天所有相关系统仍存在同样漏洞。表中的 WindowShade 选择是我们的设计推论。

## 原生框架接线方向

1. **明确配对一次。** Mac 上用新鲜 Touch ID 确认加入设备；手机/手表一侧也确认。保存批准的设备公钥，允许撤销，设备名称、蓝牙地址和 Wi-Fi 名称均不作密钥。
2. **低功耗连接。** 首选研究 Mac 作为自有 BLE 服务的外设、iPhone 作为后台 central，保留连接与状态恢复。手机后台广告的服务 UUID 会进入仅 iOS 可发现的 overflow 区，因此“Mac 一直扫描手机广告”不能直接作为可靠方案。[Apple 后台规则](https://developer.apple.com/library/archive/documentation/NetworkingInternetWeb/Conceptual/CoreBluetooth_concepts/CoreBluetoothBackgroundProcessingForIOSApps/PerformingTasksWhileYourAppIsInTheBackground.html)
3. **当次认证。** 短挑战可经 GATT 传递，必须有受控配对、消息认证与加密。Network/Bonjour 的 [includePeerToPeer](https://developer.apple.com/documentation/network/nwparameters/includepeertopeer) 加 TLS 可作为另一传输；不能默认手机在后台总能运行网络服务。挑战用 CryptoKit/Security，绑定 32 字节随机 nonce、Mac 会话、用途、交易代次和短期本地单调时限；回应一次消费，睡眠/取消/会话切换即作废。签名并不证明物理距离，也不能单独抵御中继。
4. **手表独立确认。** iPhone↔Watch 用 WatchConnectivity。若要求两个设备因素，Watch 要以自己持有的密钥回应本次交易；不能把手机转发的“手表在旁边”布尔值算第二因素。可达性是通信状态；手表 App 的回应也不自动等于系统腕上检测或密码状态证明。[WCSession.isReachable](https://developer.apple.com/documentation/watchconnectivity/wcsession/isreachable)
5. **配件辅助判断。** AirPods 的连接/音频状态可以作弱环境信息。AirTag 不假定有通用第三方身份接口。RSSI、厂商广播和配件名称不独立授权解锁；设备消失先记“未知”，不立即锁主人。

[Wi-Fi Aware](https://developer.apple.com/documentation/wifiaware) 新框架支持已配对的加密 NAN 通道，但 Apple 当前列出的设备是 iPhone/iPad，不能当作 Mac 的现成方案；[Android 文档](https://developer.android.com/develop/connectivity/wifi/wifi-aware) 同样要求检查硬件、配对和特性支持。采用同一标准也需要真机互通测试。

[Nearby Interaction](https://developer.apple.com/documentation/nearbyinteraction) 可在支持的手机、手表及合作配件间测距，需要 App/token 协作；Mac Catalyst 的精确距离能力返回 false。[iOS 27 的 Bluetooth Channel Sounding 配件配置](https://developer.apple.com/documentation/nearbyinteraction/ninearbyaccessoryconfiguration) 是新的候选路径，仍须核实配件和平台支持，不能推断 Mac、AirPods、AirTag 都可直接使用。

## 实现验收

先跑通已配对 iPhone 的当次加密确认，再加 Watch 独立回应。验证错误密钥、重放、过期、取消、合盖/睡眠、换用户、蓝牙关闭、后台回收、用户强制退出和低电量；记录恢复速度、误提示与能耗。前台成功不能代表后台可靠。设备因素缺失时保留系统密码/Touch ID 恢复；这轮调研没有完成真正的 macOS 解锁或多因素联调。
