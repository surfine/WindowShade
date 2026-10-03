# 第八份决策账

以下容量、交互和超时是本项目选择，不是 Apple 标准或测量成绩。

|编号|决定|落点|状态|
|---|---|---|---|
|R8-001|仅修改精确v7候选，原包只读|base-files、stage|已经实现|
|R8-002|一页一手柄宿主，复用原Runtime/Island/Owned控制器|WS2AppRuntime.openModelPicker|候选接线|
|R8-003|发现时只枚举，显式启用后才安装callback|GameControllerBridge.reconcile/installHandler|候选源码，待SDK/设备|
|R8-004|遇到同进程已有handler拒绝接管|installHandler|候选源码，待共存测试|
|R8-005|不更改全局后台接收开关|GameControllerBridge|候选源码|
|R8-006|当前页、key window和前台同时满足才允许设备动作|ModelPicker.isInputReady|候选源码，待焦点测试|
|R8-007|恢复焦点仅刷新本地UI，不自动重新启用|ModelPicker focusObservers|候选源码|
|R8-008|启用之前的按住不产生新确认|DeviceInputGate/INPUT03|纯核通过|
|R8-009|一次仅启用一个附件，重连不继承名称许可|DeviceActionHost/INPUT18–19|纯核通过|
|R8-010|按下预约具体目标，松开消费一次|VisibleListInput|纯核与受控流程通过|
|R8-011|选择、重选、刷新和换页都撤销未完成确认|VisibleListInput/SelectionModel|纯核通过|
|R8-012|边缘导航是正常无动作，不停用整只设备|VisibleListInput|纯核通过|
|R8-013|prepare回调返回后复查context|DeviceActionHost/INPUT32–33|纯核通过|
|R8-014|模型选择与发送请求分开|chooseModel、IFLOW02–03|真实本地管道+替身后端通过|
|R8-015|模型采用前再次复核实际目录身份|OwnedLaunchController.chooseModel|真实临时目录测试通过|
|R8-016|不为模型页启用运动、触觉或授权|ModelPicker.motionReady、typed sink|候选源码/合成测试|
|R8-017|窗口证据只由原物理路径产生，不使用登记成功|shadeWithEvidence→shade|候选接线|
|R8-018|最后身份、锁态、期限与item incarnation复核在hide前|ShadeController|候选源码，待AX|
|R8-019|先保留原恢复intent，再执行实际隐藏|ShadeController|旧静态顺序检查通过|
|R8-020|发起修改之后的失败/超时不能称未执行|FoldEvidence|21场景纯核通过|
|R8-021|迟到回调按actual transaction匹配，不按windowID泛化|FoldTransaction/FoldExit|候选源码，待实际窗口|
|R8-022|缺少AX事实返回unknown|strictFoldObservation|候选源码，待Mac|
|R8-023|观察重试不做第二次窗口写入|FoldEvidenceAdapter|候选源码/静态核对|
|R8-024|30秒期限、60秒临时通知保留、64项上限为工程值|FoldEvidence/Adapter|计时纯核通过，非实时保证|
|R8-025|临时Event不能转换成T3恢复所有权|docs/05、workorders/04|尚缺生产恢复端口|
|R8-026|不改旧journal，不自动删除CLI独立凭据|本次差异范围|源码检查|
|R8-027|默认不启用额外权限、配对监听或新传感器|既有只读路径及本次装配|候选策略，整机仍待验|
|R8-028|真实SDK/设备失败驱动下一笔修复，不新增平行管理层|COMPLETION-CONTRACT|执行规则|
