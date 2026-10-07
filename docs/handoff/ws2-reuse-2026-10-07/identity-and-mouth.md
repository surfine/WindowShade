# 蓝牙身份与个人口令：实验入口及资格边界

2026-10-07。当前没有可验证的手机身份凭证、合格的 ArcFace 权重、注视或抗录像活体证据。因此没有接入密码采集、向焦点打字或系统自动解锁。既有系统确认继续有效。

## 蓝牙两角色

`tools/probes/BLEReadProbe.swift` 可独立编译；不启动 App。必须显式提供 `--role central|peripheral`，45 秒退出。本轮已在用户指定的 iPhone 18 Pro（Aaron's Phone）与 Apple Watch Series 9 在场时做隔离发现；iPhone已连接。

```sh
bash tools/probes/run-ble-evidence.sh --check
# 实测需由操作者明确选定自己的设备 UUID；探针不会把扫描 UUID 写入日志
.build/ws2-reuse/ble-probe --role central --target '<已知本机设备UUID>' --service '<服务UUID>' --characteristic '<特性UUID>' --operation notify
# 或 --operation read；不发送 ANCS Control Point 请求，不记录通知内容
# 无服务依赖的主动在场采样：
.build/ws2-reuse/ble-probe --role central --target '<已知本机设备UUID>' --operation rssi
.build/ws2-reuse/ble-probe --role peripheral
```

外设角色只广播 WindowShade 自有测试服务和要求加密的只读／通知特性，不模拟 Apple 认证服务。系统 iPhone 没有承诺会主动订阅此服务；在不装配套 App 的约束下，没有接入就记 inconclusive。读／订阅成功也只写 `identity_unproven`。日志设备标签每次运行随机加盐，不可跨次关联。

`WS2DeviceEvidenceSession` 将代次、设备、采样时间、过期及撤销绑定。旧连接不能更新或清除新连接；弱证据不能刷新旧的强证据时间。它不产生设备认证因素。探针单次只连一个指定设备，不自动重连；服务移除、断连、无线关闭清除连接资格。

| 现场用例 | 本轮结论 |
|---|---|
| 指定手机 | 真实BLE连接成功；45秒21次RSSI采样通过；ANCS过滤服务发现回调返回0；未进入受保护访问 |
| Mac作为外设 | 加密测试服务广播成功；用户确认iPhone系统蓝牙列表未出现，0次读/订阅 |
| 未配对／换设备、撤销配对 | 未取得受保护访问，未配对；不将名称匹配当身份通过 |
| 手机锁屏、蓝牙关闭、Mac睡眠、后台重连 | not_run：需要真实系统现场 |
| 旧代次、撤销、过期、时钟倒退 | 合成核心测试通过 |
| 受保护特性访问是否足以成为第二因素 | 不成立：Apple文档未提供本应用所需当次身份验证接口 |

[Apple ANCS 规范](https://developer.apple.com/library/archive/documentation/CoreBluetooth/Reference/AppleNotificationCenterServiceSpecification/Specification/Specification.html)说明访问需授权、服务会动态出现或移除，未承诺这等于第三方解锁身份凭证。下一步转向系统LocalAuthentication配件认证边界，见 [BLEUnlock与系统认证核查](unlock-mechanisms.md)，不降低解锁门槛。

## 模型与真正解锁

[Glance b97f521](https://github.com/jonnyoo/glance/tree/b97f521397ec1197ba17768ba797cae1e628848d) 的 MIT 代码与 ArcFace 权重分开核查。[InsightFace](https://github.com/deepinsight/insightface#license) 的代码 MIT，发布的预训练模型限定非商业研究。没有下载或将其纳入发行。Glance 源码承认录像重放的缺口；其向当前焦点发按键的路径不能作为锁屏目标确认。

QuietGlass 的 SFace 仅为独立对照候选，不替换 ArcFace 产品决定。SFace 权重文件的 Apache 声明、训练数据资格、当前用户识别效果是不同问题，不能互相替代。相机关键点也不是人脸身份、注视或活体结果。

## 六口令实验

新增 `WS2MouthTemplates`：嘴部关键点平移／宽度归一化、带真实帧时间的有界动态时间规整、距离阈值和第二候选间隔。仅六条已有目录命令；不读麦克风、不接云端、不生成任意文本。`WS2SilentPhrases.seenWord` 保留兼容旧规格测试，生产实验不消费该字符串占位接口。

工具分两步：`tools/probes/run-mouth-recording.sh`显式选相机导出单个本机录入，`tools/probes/mouth-profile.sh` 建档或评估：

```sh
bash tools/probes/mouth-profile.sh build mandarin /tmp/new-profile.json /path/to/training-recordings.json
bash tools/probes/mouth-profile.sh evaluate /tmp/new-profile.json /tmp/new-report.json /path/to/holdout-recordings.json
```

末尾可传多个记录文件，输出不覆盖已有文件。每个时段使用新的 session UUID；同一录入时段的数据不能同时做训练和留出。普通话、粤语、吴语独立档案。JSON含个人嘴部关键点，应由用户自行选择本机保存位置；App 不自动写出图像或录入。

打开静音页之前，显式给隔离运行实例设置 `WINDOWSHADE_MOUTH_PROFILE` 和 `WINDOWSHADE_MOUTH_CAMERA` 才启动实验；日常未配置不增加相机读取。60秒订阅、关页／失效取消、旧页代次拒绝。实验候选只展示在现有静音页，必须点击确认；不伪造点头票据，也不执行窗口写动作。候选5秒过期，超过0.5秒无新帧不能确认。新鲜点头接线和个人录入界面未交付。

本轮合成测试证明格式拒绝、跨时段隔离、方言拒绝和匹配边界，不证明真实识别率。实际六口令混淆矩阵、无命令误触发及端到端延迟 **not_run**：尚无真实个人录入／留出集。评估报告的 captureDurations 是采集片段时长，不冒充响应延迟。阈值只是实验初值，未校准前不宣传中文唇读可用。

真实设备诊断日志：`.build/ws2-reuse/ble-phone-services.log`、`ble-accessory.log`。可选 `--selection-file` 将候选名称/本机UUID写入新建0600私有文件，仅供本次操作者选定目标；该文件不提交、不用于身份认证。普通日志仍只记每次随机加盐标签。
