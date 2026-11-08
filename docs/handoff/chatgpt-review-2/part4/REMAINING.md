# 第四份之后的真实未完项

本份完成了交接包内的源码增量、决策/施工材料和所列本地验证，**不等于整轮全部功能已经落到实际 App，也不等于可发行**。下表直接取代“其余都是实机测试”的笼统说法。

## 仍要写或接的生产代码

|项目|已经给出|还缺的具体代码/调用者|当前生产状态|
|---|---|---|---|
|D5 首次配对|协议方向、参数观察、分阶段决定、互测向量|SRP Pair-Setup、完整M1–M6、PIN窗/失败计数、Keychain事务|不可用|
|D5 传输|原生Swift Pair-Verify和记录加密候选|OPACK/session消息、Bonjour适配、NWConnection有限写队列、peer store/revision、实际原生Remote兼容|不可用，不能称已配对|
|D6/A4 命令允许|完整review、原生确认交接、真实consume调用、一次性accept编码|owned进程唯一Wire/有界writer/入口、截止任务/锁态取消、真实scope验证|未接生产允许路径|
|A4 文件/网络/持久规则审批|已定拒绝与范围规则|权威diff快照/显示/绑定，独立scope和审批文案|明确不支持|
|Claude 允许路径|协议差异和invocation绑定施工单|实际hook reply生命周期、认证及固定版本输出适配|保留原工具处理|
|I8 手柄|公开GameController候选桥，按钮/运动/反馈接口、默认关闭|唯一实例和设置页列表、真实environment/sink、桌面效果执行器、指挥动作转换|未接生产；不能虚构已连接设备|
|I5 遥控器HID|精确usage解码与设备归属/回滚决定|IOHIDManager回调桥、设备级hidutil runner、真实触点/音频能力|保持关闭|
|I3 鼠标|来源/防环/权限/共存决定|主动CGEventTap来源桥、合成标签、状态清理|保持关闭|
|I2 多触点|ABI边界、旧探针和失败策略|可证实的struct/callback ABI及生产适配器|未知ABI不准入|
|A3/D3 会话/指挥|原生view、单岛展示方法、最新草稿提交意图|live store订阅、用户入口、唯一typed dispatcher、长草稿编辑/轨迹最终layout|展示宿主候选有代码，未闭合真实后端|
|T2/T4 番茄钟|设置、快捷键、工具入口、同一host、活动/圆环|真实隐藏/禁用可见性接线、独立负一屏idle卡片|候选源码，待Mac构建|
|T3 窗口效果|ownership receipt与恢复核对|主模型的实际窗口executor、异步完成事务、提示音效果与能力刷新|只计时，不移动窗口；开关说明未接|

这些缺口不能只通过打开功能开关解决。把必需 callback 设为恒 true/空 closure 也不算接完。

## 实现之外仍需取得的证据

|证据|当前实际状态|验收入口|
|---|---|---|
|整应用Mac SDK/Metal编译|未执行；Mac连接尝试失败，当前Linux无SDK|候选 prototype/build.sh --check|
|CryptoKit实际执行|未执行；Mac脚本在Linux明确退出78|tests/run-mac-crypto.sh|
|原授权账+原生Touch ID回归|未执行|workorders/02、04 的真实环境矩阵|
|GameController/HID/鼠标/遥控器|未做真实设备运行|workorders/03|
|原生Remote首次配对和重连|未执行，且生产配对代码仍缺|workorders/01|
|番茄钟窗口恢复/功耗|未执行实际效果和能耗|workorders/05|
|签名/发行/更新|未执行，用户未授权发布|继续禁止发布1.0.16|

## 从前三份继承，但不在这次五类重点中的未完项

F1/L3 的自有人脸模型、活体与误识率；可靠系统锁/解锁后端；L2/L4 的 BLE 身份和动作归属；S1/M1 的完整设置覆盖与所有旧菜单入口/Option替代的 Mac 回归；D4/I7 实际设备偏好与撤销联动。没有把它们因为没再谈到就标完成。

影片仍是原来已交的两条无声动态分镜；17项真实素材、声音授权/混音、正式Remotion编译和最终观感尚缺。本轮未重新渲染影片，也不把旧样片改名当新成果。
