# 第二回合第1份变更

基线是本次上传的WindowShade2-review-round2.zip。没有修改输入repo，没有提交、签名、安装、启动App、改用户配置或运行真实锁屏。下面“替换”指主模型审定后的交接关系，不表示已经合并进main。

## 与第一轮的替换关系

|第一轮材料|本份替代|状态|
|---|---|---|
|reference/contracts.md及各包自己定义的事件/票据|contracts/Contracts.swift、InteractionLease.md|共享合同草案；主模型审定才冻结，旧同名模型不得混编|
|cheatsheets/T1.md、examples/T1.swift|packages/T1/|完整专注/休息状态、暂停原因、日期与窗口归属效果及测试|
|cheatsheets/L1.md、examples/L1.swift|packages/L1/|完整存在/倒数/实际锁回执/返回候选；没有OS解锁许可|
|cheatsheets/A1.md、examples/A1.swift|packages/A1/|多会话、代次、工具/审批去重、过期、观察/控制边界及测试|
|cheatsheets/D1.md、examples/D1.swift|packages/D1/|轨迹、输入模式、语音草稿、请求回执、费用确认、审批、恢复及测试|
|cheatsheets/D2.md、examples/D2.swift|packages/D2/|动态能力、稳定模型槽、费用票精确绑定，不静默降档|
|cheatsheets/I1.md、examples/I1.swift|packages/I1a–I1f/|旧合并骨架作废；采用下表固定编号，各自测试|
|cheatsheets/I9.md、examples/I9.swift|packages/I9/|完整纯几何导航、组记忆、重叠量、稳定排序和边缘策略|
|prompt-patches.md中P1和四前置的抽象要求|contracts/PrivacyRegistry.md、privacy/*、BuildBaseline.md|日志精确替换、完整文件写入器、结构化清单及实际可跑工具|
|reference/hooks-and-app-server.md的未固定字段示例|answers.md协议表、validation/schema-evidence.json|以0.153.0上传Schema为准；本份没有D6传输实现|
|M1/S1/T2/T4/A3/D3/D4/A2/L2/L4/I2/I3/I5/I8/I7/D5/D6旧小抄|本份没有交这些App包替代实现|保留为历史研究；不得因为本份纯核通过就把旧骨架直接接App|
|第一轮未包含的影片|本份仍不含film|按委托顺序，本份止于四前置和全部第一波纯逻辑；F1–F2/F3–F5未交付|

### I1编号本轮统一

|本轮编号|职责|后续接线|
|---|---|---|
|I1a|SmoothScroll，滚轮平滑|I3|
|I1b|InputDeviceKind，可靠设备分类|I2/I3|
|I1c|MiddleDrag，中键拖动|I3|
|I1d|TouchTap，多指接触组|I2|
|I1e|SiriRemoteButtons，HID按钮阶段|I5a|
|I1f|RemoteMode，遥控/指挥域与取消|I5a/D3|

第一轮review的“调整顺序”段曾把I1a写成遥控键，与当时某些示例排序不一致。该旧段编号不再用于派工；以本表、目录及tools/package-map.json三者一致为准。包职责没有增加另一套产品概念。

## 从建议变成实现

所有纯核采用Foundation、注入时间、显式状态和effects。它们不创建Timer、读取设备、发CLI请求或实际批准动作。App适配的确定接口、优先级、抢占与恢复交给InteractionLease.md；不能把仅有合同写成协调器已经接通。

Token增加独立domain，防不同模型在同boot的首个序号相撞。关闭不重置序号；模型重建使用新boot并撤销旧回调。整数溢出、非法浮点、倒流时间、旧epoch和重复消息有拒绝路径。授权Grant仍来自既有权威服务；WS2.Token和费用确认票不具备授权能力。

L1把传感器不可用与离开分开，把锁请求与OS锁态确认分开。摄像头与手机/手表策略有明确真值与时间窗。返回条件只发独立身份检查；不是一条自动解锁命令。手动锁和外部锁不能冒领为本应用动态锁。

D1区分请求配置、实际回执、下一轮配置。录音必须先收到该来源样本；转写只生成草稿。会话、轮次、请求、摘要、候选、音源都显式绑定。后台状态消息不能遮住正在确认的审批。

日志现在有12处原文锚点和SHA256校验。重新核对，其中11处有标题正文、1处只有标题长度；没有继续重复“12处都泄露正文”的不准确说法。安全日志写入器Linux分支跑过，Darwin及App wrapper尚未在macOS SDK编译。默认位置变更、权限、链接拒绝、轮转及旧/tmp文件处置分开记录。

## 本轮测试实际发现并修正

|问题|修正|保留证据|
|---|---|---|
|滚动反向时先补发旧方向残余|反向先取消pending，不推进旧方向位置|I1a用例、validation/development原失败输出|
|未知Apple产品被当作普通滚轮鼠标|未知Apple PID保留unknown；可靠非Apple HID mouse才进通用滚轮分支|I1b用例与最终输出|
|取消倒数后的60秒冷却未被新的输入重新起算|每次新输入重置连续安静起点|L1用例|
|进程退出后的同代次消息复活会话|disconnected只由更高代次opened恢复|A1用例|
|无效RSSI没有打断靠近连续区间|同代次的NaN等无效值清空连续采样证明|L1-14|
|焦点导航只看有没有重叠，没有比较重叠量|按实际重叠长度，再距离、横向差与稳定ID排序|I9-08|
|不同状态机的boot+serial相同产生令牌碰撞|TokenDomain与各模型固定domain|Contracts C04|
|D1边界原先覆盖不足|增加草稿revision、旧松手、start先于accept、审批显示优先、费用改稿、音源失效等测试|D1 32个场景和-O重复运行|

编译期的测试局部变量重名及throwing autoclosure问题也已修复。没有删除失败断言来获得通过。development目录只作过程证据，最终结果以各包VALIDATION及汇总JSON为准。

## 仍然不能声称完成的部分

合同尚待主模型冻结。12个包完成的是纯逻辑范围，不是Mac App的12项端到端功能。没有补做缺失硬件的模拟证明；触点ABI、GATT身份、遥控语音、手柄反馈、系统锁/解锁、真实助手权限和能耗仍按answers.md探针编号验收。原有64/96场景清单也没有被自动升级为全通过。
