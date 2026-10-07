# BLEUnlock、Near Lock 与系统认证

2026-10-07 核查官方原始资料，并读取当前 Mac 的 LocalAuthentication 能力。各路线对“附近设备”的信任强度不同；普通 BLE 连通不等于密码学设备认证。

| 路线 | 身份与本次确认从哪里来 | 与 WindowShade 的关系 |
|---|---|---|
| Near Lock | Mac/iPhone 两端 App 建立加密通信；RSSI估距，可增加手机Touch ID／密码确认 | 需要手机端参与，与现阶段不做配套App的约束不同；可借有限扫描、靠近/离开滞回和明确确认体验 |
| Apple Watch 官方解锁 | 已启用的同账号信任关系，安全隔区之间相互认证；每次会话密钥、解锁秘密轮换、系统安全策略 | 优先使用系统已有能力；第三方App不能把自己的BLE连接升级成这套系统信任 |
| 妙控键盘 Touch ID | 键盘硬件身份经苹果证书链证明；安全配对到Mac安全隔区；Mac执行指纹匹配 | 对App来说用系统生物认证接口；不获取指纹，也不模拟键盘来取得Touch ID资格 |

Near Lock [FAQ](https://nearlock.me/faq)明确距离来自蓝牙信号强度和算法，受环境影响；手机App完全退出后无法继续工作。[功能页](https://nearlock.me/features)说明本地数据与通信加密以及手机Touch ID确认，但没有公开完整的凭据存放、challenge/response、防重放或锁屏输入实现。其网页仍举旧系统例子，本轮没有安装运行，不能保证兼容当前系统，也不能凭“AES”替它完成安全审计。

[Apple自动解锁安全说明](https://support.apple.com/guide/security/automatically-unlock-apple-devices-sec6ab47ebfc/web)（页面2026-01-28）描述：启用时交换长期密钥，每次用STS相互认证并协商临时密钥；BLE建链，点对点Wi-Fi判断距离；系统交换、使用并轮换随机32字节解锁秘密，用于解开受保护的解锁记录。Mac/Watch需满足账号与安全条件，手表需解锁；这不是把用户密码作为普通蓝牙数据发回来。

[妙控键盘安全说明](https://support.apple.com/guide/security/magic-keyboard-with-touch-id-secf60513daa/web)说明：键盘不保存模板、不进行匹配。它的PKA硬件和Mac安全隔区以苹果CA为根进行身份认证，配对后用临时密钥加密Touch ID通道。配对意图还需实体操作确认。普通蓝牙配对与这层生物认证安全配对不同。

## 可利用的公开边界与实测

公开 [LAPolicy.deviceOwnerAuthenticationWithCompanion](https://developer.apple.com/documentation/localauthentication/lapolicy/deviceownerauthenticationwithcompanion) 可要求系统完成本次配件认证；`deviceOwnerAuthenticationWithBiometrics` 要求生物认证。它们返回应用认证结果，不能自动当作 loginwindow 已解锁。旧系统Watch策略与新Companion命名及可用条件以本机SDK/系统返回为准，不能声称此策略始终只对应某个指定物理手表。

本轮从既有 `tools/companion-probe/main.swift` 另行编译隔离二进制，仅执行能力查询，没有签名发布包或替换日用App；没有调用 evaluatePolicy、读取钥匙串、采集指纹或输入密码。沙箱内AppKit XPC失败后停止，随后在获准本机会话环境重查：

| 本机 macOS 27.0.0 | 2026-10-07 结果 |
|---|---|
| only-companion | available=false，com.apple.LocalAuthentication / -11 |
| only-biometrics | available=true，Touch ID |

回执在 `.build/ws2-reuse/{companion,biometric}-capabilities.log`。-11只说明当前上下文下配件策略不可用，不能单凭此值判断是未启用、佩戴/距离、账号状态还是调用环境限制。用户随后确认：当前没有开启官方Apple Watch解锁，但开启后可以正常解锁。因此本次-11应记为未启用配置下的能力结果，不能用来证明第三方接口不支持。尚未在开启后重测配件策略，也未完成锁屏现场认证。

## 对当前实现的裁决

1. iPhone BLE能连接但ANCS服务数为0，且自定义Mac服务不出现在iPhone系统蓝牙列表；这是本次服务路径的现场结论，不是否定官方Watch解锁。
2. 官方Watch或Touch ID可用于已有授权服务的本次明确确认。必须使用专用策略、绑定当前请求、取消即失效，不用混合密码回退冒充某一因素。
3. 系统负责锁屏解锁时，WindowShade可在系统确认解锁后恢复自己的窗口效果。若要实现另一路自动代填，仍须满足既定人脸/活体/注视/设备身份/输入目标门槛；这些尚未通过。
4. 不因Near Lock能解锁就删除手机端依赖，也不因妙控键盘能无线传指纹就假设第三方可以注册自己的系统生物认证器。


## BLEUnlock：无需手机 App 的实际路线

用户指出 [ts1/BLEUnlock](https://github.com/ts1/BLEUnlock) 后，补读固定提交 `2eeb35dcaa4e34ac994380e5dc9c0a692a6f7394` 的 `BLE.swift`、`AppDelegate.swift`、`lowlevel.c`。此前“需要手机 App”的结论只适用于 Near Lock，不是无配套 App 解锁的普遍限制。

- [BLE.swift](https://github.com/ts1/BLEUnlock/blob/2eeb35dcaa4e34ac994380e5dc9c0a692a6f7394/BLEUnlock/BLE.swift)：扫描不限定服务，按 CoreBluetooth identifier 选择设备；主动模式连接后每两秒 readRSSI，十秒未读到则退回扫描。被动模式直接使用广播 RSSI。它不要求 ANCS，也没有在这条路径中执行加密 challenge/response。
- 接近/离开分别使用阈值，离开有延迟和失联超时；均值用来平滑离开判断。靠近触发使用单个样本，不能把它写成整条路径都经过稳定窗口。源码也没有验证 didReadRSSI 的 error，本项目不照搬这一点。
- [AppDelegate.swift](https://github.com/ts1/BLEUnlock/blob/2eeb35dcaa4e34ac994380e5dc9c0a692a6f7394/BLEUnlock/AppDelegate.swift)：密码由用户预先输入并保存到 Keychain；靠近后检查锁屏，再以 CGEvent 输入密码和回车。它没有人脸/活体门槛。使用系统屏幕状态检查，并不等于把密码输入原子地绑定到 loginwindow 目标。
- [lowlevel.c](https://github.com/ts1/BLEUnlock/blob/2eeb35dcaa4e34ac994380e5dc9c0a692a6f7394/BLEUnlock/lowlevel.c)：通过 IOPM 用户活动唤醒显示器。这也可与系统 Apple Watch 解锁协作；BLEUnlock 提供只唤醒、不代填的选项。

对本项目的直接启发是将“无手机 App 的在场检测”和“已认证设备因素”分开处理。已经成功的 iPhone BLE 连接足以继续试 readRSSI，ANCS 服务为零不阻断它。本轮在已有隔离探针增加 `--operation rssi`：仅对指定已连接设备采样；错误和无效 RSSI 不计成功；退出/断连/蓝牙状态变化撤销定时读取。没有自动解锁、密码保存或新授权接口。

若采用用户原先要求的多因素真解锁，RSSI 可以提供在场条件，但不得把它标记为通过密码学身份认证。若以后明确改成 BLEUnlock 式“靠近自动代填”，则是另一套产品验收标准，不能悄悄替换本轮契约。

### 本人 iPhone 的 RSSI 实测

2026-10-07，在用户已指定并授权的同一 iPhone 上运行 45 秒；连接成功、21 次有效 RSSI、范围 −62…−43 dBm，退出 0。没有手机配套 App、ANCS 订阅、密码读取或解锁动作。日志 `.build/ws2-reuse/ble-phone-rssi.log` 仅含临时 token 与 RSSI，不含设备名、UUID 或载荷。此次已验证主动接近采样可行；没有进行走远/走近的标注实验，因此不声称测得距离、误触率或阈值准确率。身份仍未证明。
