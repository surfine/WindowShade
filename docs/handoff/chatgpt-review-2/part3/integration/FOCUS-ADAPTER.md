# 专注适配的已交与未交

本份精确补丁安装一个 WS2AppRuntime，复用 NotchActivityController 和 ActivityCard，不创建第二个面板。菜单与卷帘设置页都发到同一 host。原始 T1 只保留一份；第2份 FocusTimerHost 同样只保留一份。

尚未写完的源码必须继续由主模型施工：50分钟预设及 idle-only 配置迁移、focusStart 的全局热键分派和 recorderRow、圆环卡在展开区域的实际安装、展开/隐藏对 host.presentation 的切换、T3 窗口所有权效果桥。不能把这些写成仅剩“跑一下测试”。

接线次序固定：先给 T1 增加 idle-only configure(preset:tuckChatEnabled:) 并保持 day/completedToday；添运行中配置不改变deadline的测试；再接偏好保存；再补快捷键 ID36（更晚代码已使用时停）；最后接既有 NotchPanel 的展开高度与 FocusTimerCard。卡片不得另持有计时模型。T3 未接时保留明确不可用说明，不能开启“自动收起聊天窗口”。

锁态通知只维护多个暂停原因；启动以及恢复之前使用 AuthorizationService.shared.lockState() 的系统状态。出现 unknown 按锁定处理。本份宿主仅为候选，需要主模型检查其与 NotchActivityController 各自观察者的回调次序。
