# WindowShade 2 开源借鉴实施记录

**GPT-6 Pro 接手入口：[可直接复制的完整提示词](GPT-6-PRO-PROMPT.md)。脱敏原始日志与摘要已随仓库保存于 [evidence/](evidence/manifest.json)。**

2026-10-07，工作区分支 `cursor/silent-effect-receipts`，基线 `f6e601f`。本轮交付代码、隔离实验入口和分层证据，**不是七条愿景全部完成，也不是发布候选**。没有签名、发布或替换日用 App；原有七个未提交性能文件保留。

| 工作块 | 当前实际结果 | 尚未完成 |
|---|---|---|
| 无手机 App 的蓝牙在场 | iPhone/Watch 主动采样通过，Max/Pro2 被动广播采样通过；两角色探针及证据过期/撤销模型 | 密码学设备身份；睡眠、换设备、撤销配对的真机矩阵 |
| 系统认证与真解锁 | 核查 BLEUnlock、Near Lock、Apple Watch、Touch ID 的实际路线；本机 Touch ID 能力查询可用 | 合格 ArcFace 权重、本人/注视/抗录像活体、已认证设备及受控锁屏输入；没有密码采集或自动代填 |
| 相机与六口令 | 共用物理相机、按用途帧率/租约/代次；真实嘴部关键点录入工具、模板匹配和跨时段留出评估；候选接入现有静音页 | 本人训练与留出数据、实际准确率/响应延迟、录入界面和新鲜点头确认接线 |
| 遥控与指挥 | 有界 OPACK、真实 Pair-Verify 加密 TCP 往返；真实 SRP 与完整 M1–M6 离线互通；指挥页接入唯一生产控制器，真实会话选择、下一轮配置、采用后明确发送、回执及确认停止 | 原生 iPhone Remote 第六轮已到验签、初始化和订阅，额外请求兼容已修复；最终版第八轮出现PIN框但连接失败，仅完成验签及设备信息交换；控制会话与输入未通过；生产接收器和可发行加密依赖未交付 |
| CarPlay | 固定 PlayPort 独立前端构建及 JVM 17/17 合成协议测试；会话代次、退出全屏与断连接口 | 获准认证材料/硬件、实际接收器与音视频/点击/重连；日常长按没有改变 |
| 日常体验 | 第四活动不挤掉当前选择；旧电量不重置低电提醒；音量/亮度及提醒保存去向登记 | AirPods 三组件真实来源、连续交互及当前构建性能真机验收 |

当前完整 App `prototype/build.sh --check` 已退出0（394个主Swift源文件，未改构建门槛）。编译仍有既有并发警告，不等于运行期、手感或性能通过。

## 入口与证据

- [完整 Remote 协议复核与裁决](../../../tools/probes/remote-device/remote-atv-audit.md)：初始化、订阅、状态推送及安全边界一起核对。
- [本人设备实测](device-tests.md)：iPhone、Watch、两副耳机及两种遥控器，主动/被动信号路径分别记录。
- [蓝牙、模型和口令](identity-and-mouth.md)：实验命令、资格边界和个人留出评估。
- [BLEUnlock 与系统认证核查](unlock-mechanisms.md)：修正“无手机 App 即无路可走”的过宽推断，记录手机 RSSI 实测。
- [相机共享实现](../../../prototype/App/FaceObservationSource.swift)与[生命周期测试](../../../tests/FaceObservationSharingTests.swift)：订阅、取消与失效；若需个人录入，使用 `tools/probes/run-mouth-recording.sh` 的显式入口。
- [遥控传输](remote.md)、[指挥页](conductor.md)、[SRP 选型](srp-options.md)及[原生 SRP 探针](../../../tools/probes/companion-pairing/README.md)：协议测试和生产边界分别记录。
- [CarPlay 无凭据实验](carplay.md)、[日常改动](daily.md)、[上游版本与归属](sources.md)。
- 当前统一检查清单与文件摘要见 [verification.json](verification.json)。模拟对端、真实本机 TCP、本人手机采样和实际 App 验收分开记录。

BLEUnlock 的可用思路是按已选设备采样在场，再在 Mac 端完成动作。其源码以保存的密码模拟输入，不能证明 RSSI 本身是已认证设备因素。本轮借鉴接近采样，没有降低既定真解锁门槛。

DeepSeek 实际承担了前期接线盘点；余额不足后未继续委派。后续由原生子代理分别完成相机、遥控/指挥、CarPlay/日常工作，主模型处理蓝牙实测、口令集成、安全边界、隐私、实际差异与证据验收。没有以代理自报成功代替整包编译或真机资格。
