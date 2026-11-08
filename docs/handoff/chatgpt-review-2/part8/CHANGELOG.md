# 第八份变更

1157文件v7基线 → 1164文件v8候选。本轮修改11个既有Swift，新增5个Swift和2个候选文档/数据登记，无删除。旧base-sources只为三方比对，不纳入App编译。

输入：新增跨平台合同与实际可见列表sink、原生模型页和Runtime装配；桥在显式启用后才安装handler。按下预约目标、松开采用、重选/失焦/断连撤销。实际chooseModel在采用前复核目录；发送仍是另一动作，原只读默认不变。

窗口：原Notch.finishTuck进入新证据调用，hide前检查本次项目条目/窗口/期限/锁态，完成关联实际foldTransaction。旧延迟验证/rollback/reveal/清理增加事务核对，界面区分pending和unknown。新观察缺失不成功，保留旧journal；完整T3强身份与持久恢复仍缺。

|操作|实际路径|
|---|---|
|add|`docs/handoff/round2-part8/README.md`|
|add|`docs/handoff/round2-part8/privacy-delta.json`|
|replace|`prototype/App/FoldExit.swift`|
|replace|`prototype/App/FoldTransaction.swift`|
|replace|`prototype/App/Notch.swift`|
|replace|`prototype/App/ShadeController.swift`|
|replace|`prototype/App/WS2AppRuntime.swift`|
|replace|`prototype/App/WS2DeviceActionHost.swift`|
|add|`prototype/App/WS2FoldEvidenceAdapter.swift`|
|replace|`prototype/App/WS2GameControllerBridge.swift`|
|replace|`prototype/App/WS2IslandCoordinator.swift`|
|add|`prototype/App/WS2ModelPickerView.swift`|
|replace|`prototype/App/WS2OwnedLaunchController.swift`|
|replace|`prototype/App/WS2OwnedSessionView.swift`|
|add|`prototype/Core/WS2DeviceActionContracts.swift`|
|add|`prototype/Core/WS2FoldEvidence.swift`|
|add|`prototype/Core/WS2VisibleListInput.swift`|
|replace|`prototype/WindowShade.swift`|

没有新增CLI协议字段、密码学依赖、网络监听、摄像头/麦克风、授权允许入口、发布版本、签名或新影片。详细source/build/runtime见VALIDATION与REMAINING。
