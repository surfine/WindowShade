# 窗口浏览自动化覆盖对照（T01–T60）

任务书第 18 节要求“至少覆盖以下 60 个断言”。下表的“自动化断言”列给出覆盖该条目的
真实生产逻辑测试；标“未…”的条目说明为什么当前证据不完整。运行方式：

```sh
bash tests/run-window-browser-tests.sh   # 497 项断言
```

离屏回归只编译窗口浏览的生产源文件，不请求权限、不操作用户窗口；控制器级时序
（Dock 悬停真实链路、折叠事务、环境回调）另有只读探针与实机步骤，见
[视觉验收](window-browser-visual-qa.md)。

| 编号 | 要求 | 自动化断言（生产逻辑） | 证据缺口 |
| --- | --- | --- | --- |
| T01 | A、B 同时捕获，A 先完成，B 物理启动仍为一次 | `thumbnailJobAccounting`（firstIsA 循环） | — |
| T02 | B 先完成时 A 仍只启动一次 | `thumbnailJobAccounting`（firstIsA 循环） | — |
| T03 | 十个任务任意完成顺序下并发不超过 2 | `thumbnailJobAccounting`（manyService 固定交替完成顺序） | — |
| T04 | 取消 queued 不启动后端、不误归还额度 | `thumbnailJobAccounting` | — |
| T05 | 取消 running 仍占额度到真实完成 | `thumbnailJobAccounting` | — |
| T06 | 两个 running 遇 invalidateAll，晚到完成归还额度 | `thumbnailJobAccounting` | — |
| T07 | 旧任务失效后同键新 JobID 已入队，旧回调不删新登记 | `thumbnailJobAccounting` | — |
| T08 | 重复完成不重复发布、不重复归还 | `thumbnailJobAccounting`（`duplicateCompletionCount`） | — |
| T09 | 后端永不完成时有界降级，不无限追加任务 | `thumbnailJobAccounting`（注入假时钟 + stallTimeout） | — |
| T10 | 同步缓存回调不导致订阅悬挂 | `thumbnailJobAccounting`（缓存命中路径） | — |
| T11 | 优先级提升不重启运行中的截图 | `thumbnailJobAccounting`（promote） | — |
| T12 | 完成/取消/失败的订阅都能释放 | `thumbnailJobAccounting`（onFinish 计数） | — |
| T13 | 卡片 weak 归零，右键闭包不保活 | `viewOwnershipAndReuse` | — |
| T14 | 列表行 weak 归零 | `viewOwnershipAndReuse` | — |
| T15 | 出视口释放字典、ImageView 与占位层 | `panelAndViews`（离屏图像释放 + `hasThumbnailImage`） | 未逐图层计数 |
| T16 | 数量相同但键不同时清除旧图 | `viewOwnershipAndReuse` | — |
| T17 | 120 条只创建可见 + 有限预取单元 | `panelAndViews`（数量上界）+ 性能对照 | 离屏 AppKit 不创建视口外单元，逐项计数未实测 |
| T18 | 删除一条不重建其他单元，选择与滚动稳定 | `viewOwnershipAndReuse` | — |
| T19 | 旧单元截图返回时单元已复用，不显示到新窗口 | `panelAndViews`（不存在的键不显示） | — |
| T20 | 同一应用图标不重复高成本读取 | `iconCacheSharedAcrossRows`（`loadCount`） | — |
| T21 | 双屏左屏中央不误判为 Dock 边缘 | `dockRegionAndDetectionQueue` | — |
| T22 | 上下排列、负坐标与混合缩放的候选区域归属 | `dockRegionAndDetectionQueue` + `layoutPlan` | 混合缩放无实机样本 |
| T23 | 慢 AX + 快鼠标：最多一个在途 + 一个最新待处理 | `dockRegionAndDetectionQueue`（排队器） | — |
| T24 | AX 通知与鼠标回退共用节流与在途预算 | `dockRegionAndDetectionQueue` | — |
| T25 | 旧指针结果不覆盖新位置 | `dockRegionAndDetectionQueue`（`accepts`） | — |
| T26 | Dock 图标放大只改锚点，不重建数据会话 | `dockSessionDecision` + 控制器接线 | — |
| T27 | Dock 重启后旧观察器结果无效 | `dockRegionAndDetectionQueue`（代数/拓扑核对） | — |
| T28 | 自动隐藏 Dock 未显示时不生成错误卡片 | `dockRegionAndDetectionQueue`（已知区域 + 空隙） | 实机自动隐藏未跑 |
| T29 | 图标到面板的有限走廊 | `geometry` + `layoutPlan`（过渡区域包含锚点且有界） | — |
| T30 | 右键菜单跟踪期间保留锚点 | `contextMenuTracking` | — |
| T31 | 旧 metadata 被拒发布后仍推进最新 pending | `metadataSlots` | — |
| T32 | stop/start 之间旧回调不删新槽 | `metadataSlots` | — |
| T33 | 空列表/部分失败/权限失败/无法确认不混为一谈 | `catalogFailureSemantics` + `actions`/`actionPolicy` | — |
| T34 | 单个应用结果到达不全量重建/全量抓图 | `catalogRevisionIsolation` + `viewOwnershipAndReuse` | — |
| T35 | 选择变化保留其他可见卡片的需求 | `thumbnailJobAccounting`（promote）+ `panelAndViews` 视口集合 | — |
| T36 | 快照过期可更新、失败保留旧图、权限撤销立即清除 | `thumbnails` + `thumbnailJobAccounting`（invalidateAll） | — |
| T37 | 实时流启动后收到取消仍能停掉旧流 | `liveLeaseIdentity`（租约所有权） | 控制器端到端未自动化 |
| T38 | 旧 A 启动失败不能释放 B | `liveLeaseIdentity` | — |
| T39 | A→B→A 不接受第一次 A 的错误状态 | `liveLeaseIdentity` | — |
| T40 | 网格实时视图不挂进隐藏详情区 | `livePreviewMounting` | — |
| T41 | 网格/列表切换只迁移实时视图 | `livePreviewMounting` | — |
| T42 | 元数据/颜色刷新不 remove/add 实时视图 | `livePreviewMounting` | — |
| T43 | 重复启动失败有重试上限，refreshPanel 不无限重试 | `liveLeaseIdentity` + 控制器 `updateLivePreview` 守卫 | — |
| T44 | 释放临时镜像不停止固定预览，旧租约不解除新租约 | `mirrorOwnership` + `liveLeaseIdentity` | — |
| T45 | 折叠前停止临时捕获确认失败时不折叠 | `prepareForFold` 代码路径（单次完成门 + 1.5s 超时） | 控制器级未自动化 |
| T46 | 单窗口不继承 520×460；列表不撑满屏幕 | `layoutPlan` | — |
| T47 | 所有 Dock 方向/边角/窄屏在安全区内 | `layoutPlan` | — |
| T48 | 新截图到达不改变布局 | `layoutPlan`（同参数布局稳定） | — |
| T49 | 网格/列表/菜单/可访问性共享能力判断 | `actionPresentationModel` | — |
| T50 | 已折叠离屏不使用异常警告 | `actionPresentationModel` | — |
| T51 | 浅深色/强调色/减少透明度下所有层颜色正确 | `materialAndMotionPolicy` + `viewDidChangeEffectiveAppearance` 刷新入口 | 实机外观切换未跑 |
| T52 | 减少动态效果时无位移/缩放，操作仍及时 | `materialAndMotionPolicy` + 面板动画入口 | — |
| T53 | 网格四向选择与真实列数一致 | `layoutPlan`（列数与方向键）+ `panelAndViews` | — |
| T54 | 输入法候选、文本左右移动、复制粘贴不被抢走 | `inputMethodPriority`（marked text 时 Return/方向键交还文本系统） | 复制粘贴走系统默认路径，未单独断言 |
| T55 | 按下拖出取消、悬停不改变源窗口焦点 | `panelAndViews`（按下/拖拽/松开）+ 悬停路径无可写 AX 调用 | 悬停不改焦点的实机验证未跑 |
| T56 | 键盘面板延迟激活重试不抢回焦点 | `focusReturnPolicy` + `WindowBrowserPanel.cancelPendingPresentation`/`NSApp.isActive` 守卫 | 控制器级时序未自动化 |
| T57 | 真正聚焦目标才按成功处理 | `activationVerification` | 实机焦点未验证 |
| T58 | 排布先计算与预览，取消不移动窗口 | `placementPlans`（预览不写后端） | — |
| T59 | 验证成功才登记撤销，身份变更不盲目回放 | `placementPlans`（验证失败/用户移动后拒绝） | — |
| T60 | 睡眠/锁屏/权限撤销/显示器拔出/退出释放资源 | `thumbnailJobAccounting`、`mirrorOwnership`、`hundredCyclesReturnToBaseline`、`--window-browser-idle-probe` | 控制器环境回调的实机触发未跑 |
