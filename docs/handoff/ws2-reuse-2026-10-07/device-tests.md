# 本人设备实测

2026-10-07。用户明确指定 iPhone、Apple Watch、AirPods Max、AirPods Pro 2，以及实体 Siri Remote 和 iPhone 控制中心遥控器；确认自定义名称 Headset=Max、Earbuds=Pro2。只操作这些目标，不把邻近同类设备当本人身份。

| 设备 | 当前实际结果 | 结论范围 |
|---|---|---|
| iPhone | 45秒主动连接，21次RSSI，−62…−43 dBm | 无手机App的主动在场采样通过 |
| Apple Watch | 45秒主动连接，21次RSSI，−52…−47 dBm | 主动在场采样通过；未开启官方Watch解锁进行本次认证 |
| AirPods Max | BLE连接成功，主动RSSI不可用；45秒被动广播41次，−51…−46 dBm | 被动在场采样通过 |
| AirPods Pro 2 | 同名出现2个CoreBluetooth候选ID，已测其一连接成功但主动RSSI不可用；45秒被动广播80次，−63…−39 dBm | 被动在场采样通过；保留各run token，不把同名等同设备认证 |
| 实体 Siri Remote | BLE扫描未见匹配名称；GameController枚举0个控制器 | 本次未建立输入链；没有重置或改变它与Apple TV的配对，不据此断言硬件不支持 |
| iPhone 控制中心遥控器 | 最终版第八轮出现PIN框但连接失败；配对和一次验签成功，仅systemInfo | 未进入遥控会话，0按键；关闭原因未确定 |

耳机还通过已知本机地址调用旧 IOBluetooth 只读接口30秒：两者均报告 connected，但无有效数值。系统 system_profiler 单次曾报告 Max −46 dBm；不把这一快照当连续采样。没有录音、切换音频输出、读取通知、输入密码或驱动App动作。

## 复现入口

`bash tools/probes/run-ble-evidence.sh --check` 编译隔离探针，包含蓝牙用途说明。随后显式选择一种方式；每次45秒自动清理退出：

```sh
# 主动模式：操作者从本地私有选择清单选本人设备，不在报告里贴UUID
.build/ws2-reuse/ble-probe --role central --target '<本人设备UUID>' --operation rssi
# 被动模式：使用本机已确认的名称；名称只是筛选，不是认证因素
.build/ws2-reuse/ble-probe --role central --operation passive-rssi --match-name '<本人耳机名称>'
```

广播数据不记录载荷，只记临时run token与RSSI。详细统计及日志摘要见 [device-tests.json](device-tests.json)。`tools/probes/game-controller` 只枚举/观察当前控制器；`tools/probes/remote-device` 是独立限时实验服务，临时身份/PIN不写Keychain，接收到认证事件也只计数。

这些结果没有走近/走远标签，不证明米数、解锁阈值、抗伪装身份、佩戴状态或用户在场；也没有完成睡眠、撤销配对、关蓝牙等真机矩阵。BLEUnlock 提供的在场方案可行，既定系统解锁门槛仍保留。

## 原生 Remote 第二轮对照

首轮只有 Companion 服务，本机解析成功但120秒0连接；用户手机屏幕观察尚未回报。随后核对固定 atv-core `8a4ada29bb7cad31e0315c3387b277eb9ab8c988`，补可选三服务发现配置以及有来源证据的会话应答。第二版严格Swift6编译和37项离线检查通过，命令见JSON及工具README。**第二轮已运行：本机MRP解析成功，8次真实连接；用户确认手机显示已连接并按键。服务端仍无认证输入：在Pair-Verify阶段收到Pair-Setup开始帧3，被状态机拒绝。发现已推进到连接，配对和按键传递尚未通过。退出时listener=0。下一步修同连接握手切换后再测。** MRP/AirPlay辅助端口只接受后立即关闭并记录unsupported，不冒充媒体协议。

## 同连接握手修复与第三轮

第二轮手机实际触发 PV开始→同连接PS开始，原探针未允许该切换。已仅在隔离接收器内补一次未认证回退；切换先撤销旧代次再销毁旧密码学通道，防旧回调关闭新握手。M6后允许同连接重新Pair-Verify，已验证后禁止重启配对；不继承Setup密钥作为输入资格。

修复版严格编译、原37项离线检查和6个独立真实密码学场景通过。主模型复核并实跑完整客户端：PV→PS M1–M6→freshPV双方验签→加密请求/应答；错误签名、过期、重复回退、Setup密钥输入及验证后重启拒绝。当前二进制SHA和场景JSON见device-tests.json。未改生产Channel或密码学实现。

第三轮120秒三服务已实际开启，但0新连接、0认证事件，结束时0listener；手机反馈待回，不能声称本轮握手已在真机通过。第三轮PIN已过期，等待操作者就绪后再开新窗口。

## 第四轮：验签通过，消息解析阻断

用户就绪后再次开启120秒实验。真实PairSetup成功；手机先以Setup密钥发输入帧，被既定门槛拒绝，随后7次重连均通过独立PairVerify。每次验签后首个加密frame8均解码为unsupportedTag并关闭；旧诊断没有tag数值，尚不能确定缺哪一种格式。用户报“无法连接或找不到设备”，没有收到认证输入、没有App动作，结束时0listener。后续只补固定来源证明的格式并增加tag/offset诊断，完成回归后再测。

## 第五轮与执行方向纠正

OPACK补全版开启120秒，8连接，其中7次通过PairVerify；不再报unsupportedTag，改为消息信封malformed，仍没有任何认证输入。用户仍报无法连接或找不到设备，结束0listener。用户指出不能逐个补错误、让人反复试错；停止真机重试，先完整重审固定atv-core发现/握手/初始化/应答/订阅/HID源码，将明确的兼容差异一次整合并走完整离线加密会话，再协调真机。

## 第六轮：会话已建立，额外请求被本地策略切断

完整profile版真实接收5连接、4次PairVerify成功；其中3次通过systemInfo、sessionStart、TVRCSessionStart、状态查询和订阅，另一连接只有后台systemInfo。随后未在方法表中的请求触发unsupportedMethod，手机仍无法连接，未收到HID。结束0listener。

该断连来自本地额外限制；固定atv-core对未知请求会回空应答、对无事务事件不应答。本地随后将这一行为限于显式实验profile：仍须真实认证和有界消息；未知方法只空应答/忽略，绝不进入profile或动作回调。默认生产仍拒绝。未知协议方法不因此被宣称为已实现的功能。

## 第七轮：最终修复版未收到连接

未知请求兼容修复后的最终二进制已通过全App编译，以及主代理独立复跑的51离线检查、6真实密码学场景、两套51/55多包流程、7协议负例和未知方法不进入动作入口的用例。操作者确认就绪后开启120秒，3服务ready，但0连接、0输入，结束0listener。手机本轮观察待回；PIN已过期。无连接不能证明最终协议通过或失败，下一次先确认手机是否出现当前PIN输入框，再协调新的窗口。

## 第八轮：出现PIN框，但未进入遥控会话

用户要求再测，核对最终二进制未变后开启120秒。手机明确反馈“出现PIN框，但连接失败”。服务端2连接：第一连接真实配对完成，随后frame8因仍需fresh PairVerify而关闭；第二连接验签成功，只完成systemInfo后关闭，无sessionStart、TVRC或HID。没有未知方法被忽略，退出0listener。不能据此确定第二连接关闭的发起者/原因，可能涉及首次配对到控制会话的衔接，尚无根因结论。同窗口请求重新选择时未在到期前收到新连接；PIN已过期。

操作者随后确认：重新选择后仍然连接失败；不把本次失败归因为未操作。
