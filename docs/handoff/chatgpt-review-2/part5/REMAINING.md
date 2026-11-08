# 第五份后仍缺什么

本份完成了候选中间层代码、详细工作单与列明的本地测试；不等于五条路径已在实际 App 全部可用。以下缺口不能只靠开启功能开关或跑现有测试解决。

|路径|本次推进|仍需编写/接入的生产调用者|系统/设备证据|
|---|---|---|---|
|首次配对|M1/M3/M5 编排、全局失败状态、M5/M6 签名加密候选、独立参考|SRP 依赖最终准入与实例工厂；安全的可观察 PIN 界面；完整相反实现互测|Mac SDK、Swift SRP 实际运行、原生 Remote|
|持久身份|单快照仓库、版本/撤销墓碑、Keychain 候选|显式首次配置/错误恢复；同标识重配 token；墓碑清理和容量管理 UI|真实签名域、锁中、OSStatus、失败写入|
|网络|accepted TCP 有界传输/截止/关闭|唯一 NWListener owner、总连接配额、受限 OPACK/session、真实 Bonjour/profile、验证后路由|原生发现/握手/重连/撤销互操作|
|owned Codex|真实管道、每批 write gate、唯一 Wire/审批宿主组合|AppRuntime 强所有者和本地启动入口；真实项目/scope store、权限变更回调、session UI 状态订阅|真实 CLI、Touch ID、锁中回调与许可|
|生产输入|GameController 的唯一 host、语义票据、motionReady|实际列表选择 sink、Runtime/设置页、桌面运动 sink；HID/鼠标/私有多触点桥仍缺|GameController/设备插拔/反馈/共存|
|窗口效果|阶段计划、实际结果合同、串行 executor|Fold 事务 typed completion、身份/revision 来源、具体 AX/恢复端口、目标选择与计时接线|隐藏/恢复实测、手动干预、锁/睡眠、journal 回归|

## 不要遗漏的细节

进程通道现在将 stderr 丢弃，无诊断读取，也无 SIGKILL 升级或子进程树清理；它要求调用者显式 stop。PeerRepository 不提供跨进程 CAS、备份防回滚和无限设备管理。TCP transport 不提供协议解释和总容量。FocusEffectExecutor 没有跨重启保存本轮 receipt。这些都没有因为已经有候选类就被宣布完成。

可先交付不依赖硬件的 owned CLI 可观察闭环，再逐项放开能力。若其他待验证模块阻断 Mac 编译，先在隔离 target 修编译或明确排除实验文件；不能注释掉类型检查、降低 Swift 版本来掩盖错误。

## 继承的未完项

F1/L3 自有人脸模型/活体/误识率、可靠系统锁解锁后端、BLE 身份和动作归属、其他设置与菜单回归、原有设备偏好撤销，仍遵循前四份清单。影片仍只有以前两条无声动态分镜，17 项真机素材、声音授权/混音和正式构建/观感未完成；本次没有制作新影片或重复计为新成果。用户没有授权发布、改更新源或真实 home 配置。
