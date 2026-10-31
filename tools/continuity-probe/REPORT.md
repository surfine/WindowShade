# 实验 1：从 Apple Continuity 蓝牙广播判断「手机刚解锁过」（2026-10-31，本机 macOS 27.0.1，M5 MacBook Air）

## 结论

**不可行（对「自己的手机、最近解锁」这个需求）。** 卡在两层，且都不是靠写代码能绕开的：

1. **Mac 端读不到那个信号的“归属”**：Nearby Info 里能看出的只有「此刻」的活动级别，而且要确认广播者是 Aaron 自己的 iPhone，必须用 iCloud 账号共享的密钥验证 Auth Tag。这把密钥只在系统的 `sharingd`/`rapportd` 里，第三方进程拿不到（下方实测：`Missing entitlement 'com.apple.CompanionLink'`）。
2. **信号本身没有「N 分钟内解锁过」**：协议里最多有「用户空闲(0x03)」「正在使用、亮屏(0x07)」「最近有交互(0x0B)」「手表在手腕上已解锁(0x0A)」，没有“上次解锁时间”。

「公开可扫描的匿名广播」只能做到“附近有个 Apple 设备此刻亮屏”，任何人都能伪造一份相同内容的广播（Nearby Info 的 Auth Tag 只有同账号设备能验），不能当第二因素。

## 证据

### 协议（公开研究）
- furiousMAC/continuity `messages/nearby_info.md`（最后提交 2023-09-04，<https://github.com/furiousMAC/continuity/blob/master/messages/nearby_info.md>）：类型 0x10，长度 5；首字节高 4 位为状态标志、低 4 位为 Action Code；第二字节数据标志（0x10=带 Auth Tag，0x04=Wi-Fi 开）；之后 3 字节 Auth Tag。Action Code：0x00 未知、0x01 关闭上报、0x03 空闲、0x05 锁屏播放音频、0x07 活跃·亮屏、0x09 亮屏播视频、0x0A 手表在手腕上且已解锁、0x0B 最近有交互、0x0D 驾驶、0x0E 通话。该页自己标注多个标志“not sure”，并且表格示例把 3 写成“Locked Phone”，与列表（Idle User）矛盾。
- Celosia & Cunche, *Discontinued Privacy: Leaks in Apple BLE Continuity Protocols*, PoPETs 2020（<https://crysp.petsymposium.org/popets/2020/popets-2020-0003.pdf>）：Nearby Info 由 iPhone/iPad/MacBook/Watch 持续广播，含 Auth Tag 和 Activity Level；Handoff、Nearby Action、Nearby Info 的 Auth Tag 用 AES-256-GCM 计算（引 Apple iOS Security）；多数广播用 RPA/NRPA 随机地址；测试设备是 iOS 11–12、macOS 10.12–10.13、watchOS 5（2019 年数据）。
- Martin et al., *Handoff All Your Privacy*, PETS 2019（<https://arxiv.org/abs/1904.10600>，本轮只在仓库文档里引用，没重新打开全文）。
- **新鲜度缺口**：以上都是 iOS 12 前后的逆向，没有找到覆盖 iOS 17/18/26 的公开资料。系统里已有 `SFBLEDevice.decryptedActivityLevel` 与 `rpIdentity` 两个属性（见下），暗示新系统对“自己的设备”解出活动级别、对外人可能不再明文——这是从符号推断，不是实测，标为**未验证**。

### 本机实测
| 检查 | 结果 |
| --- | --- |
| `ContinuityProbe --self-test`（解析 + Nearby Info 解码，合成数据） | `self-test ok`，退出 0 |
| 直接从命令行跑扫描 | **崩溃**（SIGABRT, TCC）：`attempted to access privacy-sensitive data without a usage description`——TCC 按“负责进程”（宿主 App）查 `NSBluetoothAlwaysUsageDescription`，裸命令行二进制过不了。 |
| 包成 ad-hoc 签名的 `.app` 用 `open` 启动 | 能启动，但 `CBCentralManager.authorization = 0 (notDetermined)`，没人点“允许”，`didUpdateState` 从未回调，**60 秒内 0 条广播**。这是**权限闸**，不是“附近没有设备”的证据。 |
| `system_profiler SPBluetoothDataType` | 已配对设备只有耳机、鼠标和 1 台未连接设备（后缀 `..1A`）；iPhone/Watch 不在经典蓝牙配对表里（Continuity 靠 iCloud，不是蓝牙配对）。 |
| `/Library/Bluetooth/com.apple.MobileBluetooth.ledevices.paired.db`（IRK/LTK 所在库） | `root:wheel 0640`，`Permission denied`；没有 root（`sudo` 要密码），SIP 为 enabled。**不尝试绕过。** |
| `Sharing.framework` 运行时内省（只读，`dlopen` + 列属性） | `SFBLEDevice` 有 `decryptedActivityLevel`、`rpIdentity`；`SFBLEScanner` 有 `+parseNearbyInfoPtr:end:fields:`、`_btSessionEnsureStarted`。`sharingd` 的授权里有 `com.apple.bluetooth.internal`、`com.apple.bluetooth.system`、`com.apple.rapport.Client`。这些是受限授权，第三方签名拿不到（不关 SIP/AMFI 就不能带）。 |
| `Rapport.framework`：`RPCompanionLinkClient activateWithCompletion` | `RPErrorDomain -71168 kMissingEntitlementErr (Missing entitlement 'com.apple.CompanionLink')`，`activeDevices=0`。系统“伴侣设备”通道对我们关闭。**到此停止。** |

### 该做的两个问题
- **能否不装配套 App 知道“自己设备此刻亮屏/解锁”？** 匿名层面：**可能**（若 macOS 的 CoreBluetooth 把 0x004C 数据交给第三方——本轮因权限闸**没验证**；已知 CoreBluetooth 会过滤部分系统数据）。归属到“自己的设备”：**不能**（需要 iCloud 共享密钥，受限授权）。“N 分钟内解锁过”：协议里没有这个字段，只有当下状态，最多自己在 Mac 上做滑动窗口（看到 0x07/0x0B 后记一个时间戳），而且前提是上一条成立。
- **IRK 路径？** 蓝牙 LE 的 IRK 存在 root 才可读的 `ledevices.paired.db`；而且 iPhone 与 Mac 之间的 Continuity 并不做 LE 配对，没有 IRK 可用，是 iCloud 账号密钥体系。不可达。

## 对 Aaron 的决定（row 66–70）的含义
「脸 + 手机在附近 + 最近解锁」中，“手机在附近”可用已有的 `BLEReadProbe` 一路（Mac 主动连接 + 加密特性，见 `tools/probes`，CoreBluetooth 公开 API，不依赖 Continuity）；“最近解锁”在不装 iPhone 端 App 和不碰受限授权的前提下**拿不到**。可考虑的替代（需 Aaron 定）：
1. 把“最近解锁”降级为“手机连接存活 + 被 Mac 加密读成功”（证明手机在、配对过，不证明刚解锁）。
2. Apple Watch：手表解锁状态在 macOS 上由系统“用 Apple Watch 解锁”（Auto Unlock）承担，我们不能读。
3. 若接受私有授权：需要关 SIP/AMFI 才能带 `com.apple.CompanionLink`，**不建议**，也不能随产品发布。

## 隐私与安全
- 被动扫描会收到周围所有人设备的广播。探针只在内存里累计、设备标识用每次运行随机盐的 SHA-256 取 1 字节输出，不打印名称、不落盘。产品里若做，需同样不记录陌生设备。
- 因为匿名广播可伪造/重放，不能用作放行条件。

## 需要 Aaron 做的事（完成实验）
1. 在 Mac 上跑（弹出“蓝牙”权限时点**允许**，这是系统设置，我没有替你点）：
   ```
   tools/continuity-probe/make-app.sh /tmp/cp
   open -W -o /tmp/cp-out.txt --stderr /tmp/cp-err.txt /tmp/cp/ContinuityProbe.app --args --seconds 60
   cat /tmp/cp-out.txt
   ```
2. 第一次：iPhone 解锁并放在 Mac 旁边；第二次：iPhone 锁屏、屏幕灭；第三次：Apple Watch 抬手/解锁。比较 `NearbyInfo action=` 随之如何变化，以及是否看到任何 `nearby_info_msgs>0`。
3. 如果 `nearby_info_msgs=0` 而 `apple_0x004c_adv>0`，说明 macOS 把 Nearby Info 滤掉了，实验到此结论为“不可行（系统层过滤）”。
4. 输出里设备标识已是随机 1 字节标签，可直接贴回。

## 编译检查
```
tools/continuity-probe/build.sh OUT     # swiftc -O -swift-version 5 ContinuityProbe.swift -o OUT -Xlinker -sectcreate ... -framework CoreBluetooth   exit 0
bash -n build.sh make-app.sh            # exit 0
OUT --self-test                         # self-test ok
```
