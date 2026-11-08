# 租约合同实现补充

Contracts.swift与part1逐字相同；InteractionCoordinator.swift为新增MainActor实现。所有调用要共享一份实例、统一ContinuousClock、实时权威锁态与屏幕集合。cancel闭包必须同步停录音、触点、合成输入和草稿发送，再清视图。它不是AuthorizationGrant。

授权/交互/主动展开为1/2/3层。层4提醒4秒，0.6秒合并但不续第一个截止。层5每屏最多3条ID。锁屏清私密持续状态；被抢占的交互不自动恢复。acquire拒未知owner、错误层、过去期限和不存在的屏幕；抢占后再次读取环境以防cancel期间锁态改变。

原接点沿用part1 InteractionLease.md §4。本包没有把整个Notch控制器改接该协调器，故22场景中的租约测试只证明本实现的规则，不能代替LEASE-01…10宿主集成验收。cancel内再次递归申请返回unavailable，不递归发布新租约；锁态由环境闭包重核。
