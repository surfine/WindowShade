# 相对第五份的精确变化

输入是第五份 candidate 的 1140 个文件；第六份修改五个既有文件、新增五个 Swift 文件，候选为 1145 文件。manifest 含全基线哈希及每个 overlay 的旧/新哈希。原输入未改。

## 五处修改

|路径|变更|验证边界|
|---|---|---|
|prototype/App/InteractionCoordinator.swift|exact lease 换页、同步撤销 barrier、屏幕变化中断过渡|本地 Swift 用例及旧 part2 回归|
|prototype/App/WS2IslandCoordinator.swift|不再在申请 lease 前 dismiss；取得后核对 current|语法 parse；Mac SDK/UI 未验|
|prototype/Core/CodexWire.swift|thread/start/resume 和 turn 显式只读、人工审批；model 分页保持 includeHidden=false|5 场景/11 断言；4 条 params 的固定 schema|
|prototype/Support/WS2DuplexProcess.swift|可选 stderr 尾部、直接终止状态、通知到达后的有界收尾|9 场景/27 断言；独立 PROC04 仍 BLOCKED|
|prototype/build.sh|创建 .build 父目录；改正 --check 的说明|bash -n；实际 Mac 构建未验|

## 五份新增

`Core/WS2DiagnosticTail.swift`、`Core/WS2OwnedScope.swift`、`Core/WS2SelectionModel.swift`、`Core/WS2ConnectionBudget.swift`、`Support/WS2ProjectDirectory.swift`。它们提供有界缓存、上下文身份、一次性列表操作及总量预算，不自带真实 Runtime/Listener/原生列表/窗口调用者。

## 明确没有发生的变更

没有新 CLI 界面入口、没有独立进程监督 helper、没有真实 NWListener/OPACK、没有 AX 隐藏恢复端口、没有新手机 App。没有更改授权账规则、更新源、签名配置、原有影片和用户 home。第五份的 SRP 候选和隔离依赖没有升级成已验证能力。

第六份的施工单和源码地图优先解释其覆盖的调用链；未覆盖的功能保留前五份限制。历史 VALIDATION 只记录当时结果，本轮新结果以本份为准，不能将它们相加得出整应用测试通过。
