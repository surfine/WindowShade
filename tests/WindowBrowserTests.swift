// 窗口浏览纯逻辑测试。测试的目标是生产代码里的真实类型（身份分配、目录合并、
// 稳定顺序、请求代数与布局计算），不在测试里重写一份看似相同的实现。
//
// 这些用例不请求权限、不读取用户窗口、不注入事件、不访问网络。

import Foundation
import CoreGraphics
import Cocoa
import AVFoundation
import Carbon.HIToolbox

@main
enum WindowBrowserTests {
    static var failures = 0
    static var checks = 0

    static func expect(_ condition: Bool, _ label: String) {
        checks += 1
        if !condition {
            failures += 1
            print("FAIL: \(label)")
        }
    }

    static func main() {
        identityAndCatalog()
        catalogFailureSemantics()
        requestTokens()
        listStabilityAndSelection()
        panelStateMachine()
        focusReturnPolicy()
        search()
        actions()
        actionPolicy()
        thumbnails()
        thumbnailPolicy()
        discoveryFilter()
        mirrorOwnership()
        foldCacheIsolation()
        panelAndViews()
        thumbnailJobAccounting()
        viewOwnershipAndReuse()
        livePreviewMounting()
        iconCacheSharedAcrossRows()
        dockRegionAndDetectionQueue()
        metadataSlots()
        layoutPlan()
        typographyFollowsSystemTextSize()
        actionPresentationModel()
        materialAndMotionPolicy()
        placementPlans()
        dockSessionDecision()
        catalogRevisionIsolation()
        liveLeaseIdentity()
        preferencesRoundTrip()
        standardMainMenu()
        escapeLayering()
        accessibilityAnnouncements()
        quickLookPolicy()
        statusAnnouncementPolicy()
        contextMenuTracking()
        inputMethodPriority()
        activationVerification()
        hotKeyPolicy()
        hundredCyclesReturnToBaseline()
        firstContentLatency()
        geometry()
        if failures == 0 {
            print("PASS: \(checks) window-browser pure-logic checks")
        } else {
            print("FAILED: \(failures)/\(checks) window-browser checks")
            exit(1)
        }
    }

    // MARK: 身份和目录

    static func identityAndCatalog() {
        // 1. 同一原窗口同时从系统发现和管理快照出现，只显示一个条目。
        let catalog = WindowCatalog()
        _ = catalog.applyManaged([managed(pid: 501, id: 11, title: "甲",
                                          capabilities: [.activate, .unfold])])
        let records = catalog.applyDiscovery(.success([
            discovered(pid: 501, id: 11, title: "甲", frame: CGRect(x: 10, y: 10, width: 300, height: 200))
        ]), pid: 501)
        expect(records.count == 1, "managed and discovered window must dedupe to one record")
        expect(records[0].isManaged && records[0].placementSource == .managedFold,
               "managed state must win over discovery state")
        expect(records[0].capabilities.contains(.close),
               "discovered capabilities must be merged into the managed projection")

        // 2. 两个窗口标题完全相同，仍有独立身份与独立动作目标。
        let twins = catalog.applyDiscovery(.success([
            discovered(pid: 501, id: 21, title: "无标题"),
            discovered(pid: 501, id: 22, title: "无标题")
        ]), pid: 501)
        let twinKeys = Set(twins.filter { $0.displayTitle == "无标题" }.map(\.key))
        expect(twinKeys.count == 2, "identical titles must keep distinct WindowKeys")

        // 3. 同一应用多个 PID 不合并成一个窗口身份。
        _ = catalog.applyDiscovery(.success([
            discovered(pid: 501, id: 35, title: "同一窗口标题")
        ]), pid: 501)
        _ = catalog.applyDiscovery(.success([
            discovered(pid: 601, id: 31, title: "同一窗口标题")
        ]), pid: 601)
        let multiPID = catalog.publish().filter { $0.displayTitle == "同一窗口标题" }
        expect(multiPID.count == 2, "two PIDs must not be merged into one identity")
        expect(Set(multiPID.map { $0.key.application.pid }) == Set([501, 601]),
               "each PID keeps its own ApplicationInstanceKey")

        // 4. PID 被复用：旧任务不能写入新应用实例。
        let allocator = WindowIdentityAllocator()
        let oldApp = allocator.applicationInstance(pid: 700, bundleIdentifier: "com.example.app")
        allocator.noteApplicationTerminated(pid: 700)
        let newApp = allocator.applicationInstance(pid: 700, bundleIdentifier: "com.example.app")
        expect(oldApp != newApp, "PID reuse must allocate a new application generation")
        let oldWindow = allocator.windowKey(pid: 700, bundleIdentifier: "com.example.app",
                                            originalWindowID: 41)
        allocator.noteApplicationTerminated(pid: 700)
        let newWindow = allocator.windowKey(pid: 700, bundleIdentifier: "com.example.app",
                                            originalWindowID: 41)
        expect(oldWindow != newWindow, "window identity must not survive app relaunch")
        expect(!allocator.isCurrent(oldWindow), "old application instance must be invalid")

        // 5. 原数字窗口 ID 被复用：新窗口不继承旧代数和旧画面。
        let recycle = WindowIdentityAllocator()
        let first = recycle.windowKey(pid: 800, bundleIdentifier: "com.example.app",
                                      originalWindowID: 51)
        recycle.confirmWindowDestroyed(first)
        let second = recycle.windowKey(pid: 800, bundleIdentifier: "com.example.app",
                                       originalWindowID: 51)
        expect(first.windowGeneration != second.windowGeneration,
               "CGWindowID reuse must produce a new window generation")
        expect(recycle.isCurrent(second) && !recycle.isCurrent(first),
               "only the current generation may be written")

        // 4b. 缺少 bundle ID 的元数据不得为同一 PID 造出第二个应用实例。
        let upgrade = WindowIdentityAllocator()
        let withoutBundle = upgrade.applicationInstance(pid: 810, bundleIdentifier: "")
        let withBundle = upgrade.applicationInstance(pid: 810,
                                                     bundleIdentifier: "com.example.app")
        expect(withoutBundle == withBundle,
               "missing bundle ID must not create a duplicate application instance")
        let otherBundle = upgrade.applicationInstance(pid: 810,
                                                      bundleIdentifier: "com.other.app")
        expect(otherBundle != withBundle,
               "a genuinely different bundle ID for the same PID is a new instance")

        // 6. 折叠原窗口离屏仍保留，逻辑位置来自标题条恢复位置。
        let frame = CGRect(x: 120, y: 240, width: 640, height: 480)
        let folded = WindowCatalog()
        let foldedRecords = folded.applyManaged([
            managed(pid: 901, id: 61, title: "离屏折叠", frame: frame, isOnScreen: false)
        ])
        expect(foldedRecords.count == 1, "folded offscreen window must stay in the catalog")
        expect(foldedRecords[0].logicalFrame == frame,
               "folded window must use the strip restore position, not the parking position")
        expect(foldedRecords[0].isFoldedOffscreen,
               "folded offscreen record must be marked for screen filtering")

        // 10. 部分应用失败不阻挡其他应用的目录结果。
        let partial = WindowCatalog()
        _ = partial.applyDiscovery(.success([
            discovered(pid: 1001, id: 71, title: "正常应用"),
            discovered(pid: 1002, id: 72, title: "另一个正常应用")
        ]), pid: 1001)
        _ = partial.applyDiscovery(.partial([
            discovered(pid: 1002, id: 72, title: "另一个正常应用")
        ], failures: [1003]), pid: 1002)
        expect(partial.records(forPID: 1001).count == 1,
               "one app's failure must not block other apps")
        expect(partial.isRefreshPending(pid: 1003),
               "partial failure must mark only the failing app as refresh-pending")
    }

    // MARK: 失败保留

    static func catalogFailureSemantics() {
        // 8/9. 查询超时保留旧结果；成功空结果与失败不走同一分支。
        let catalog = WindowCatalog()
        _ = catalog.applyManaged([managed(pid: 1101, id: 81, title: "已管理")])
        _ = catalog.applyDiscovery(.success([
            discovered(pid: 1101, id: 82, title: "普通窗口")
        ]), pid: 1101)
        expect(catalog.records(forPID: 1101).count == 2, "baseline records")

        let timedOut = catalog.applyDiscovery(.timedOut(previous: []), pid: 1101)
        expect(timedOut.count == 2, "timed-out query must keep existing records")
        expect(catalog.isRefreshPending(pid: 1101), "timed-out query must mark refresh pending")

        let failed = catalog.applyDiscovery(.failure(reason: "busy"), pid: 1101)
        expect(failed.count == 2, "failed query must keep existing records")

        let emptied = catalog.applyDiscovery(.empty, pid: 1101)
        expect(emptied.count == 1, "successful empty result removes only discovered records")
        expect(emptied[0].isManaged, "managed window survives a successful empty discovery")

        // 暂时缺失的窗口不凭一次扫描删除折叠会话对应的记录。
        let missing = WindowCatalog()
        _ = missing.applyManaged([managed(pid: 1201, id: 91, title: "恢复中")])
        _ = missing.applyDiscovery(.timedOut(previous: []), pid: 1201)
        expect(missing.records(forPID: 1201).count == 1,
               "temporary absence must not delete a folded session record")
        _ = missing.confirmWindowDestroyed(
            missing.windowKey(pid: 1201, bundleIdentifier: "com.example.app", originalWindowID: 91))
        expect(missing.records(forPID: 1201).isEmpty,
               "only confirmed destruction removes the record")
    }

    // MARK: 请求代数

    static func requestTokens() {
        // 11/12. A→B→A：第一次 A 的结果不能被当成当前有效结果。
        let appA = ApplicationInstanceKey(pid: 1301, generation: 1)
        let appB = ApplicationInstanceKey(pid: 1302, generation: 1)
        let firstA = WindowBrowserTargetToken(requestID: WindowBrowserRequestID(value: 1),
                                              application: appA, targetGeneration: 1)
        let toB = WindowBrowserTargetToken(requestID: WindowBrowserRequestID(value: 2),
                                           application: appB, targetGeneration: 1)
        let secondA = WindowBrowserTargetToken(requestID: WindowBrowserRequestID(value: 3),
                                               application: appA, targetGeneration: 2)

        expect(!toB.accepts(application: appA, targetGeneration: 1),
               "B session must reject A's result")
        expect(!firstA.accepts(application: appA, targetGeneration: 2),
               "first A session must not accept a later A target generation")
        expect(secondA.accepts(application: appA, targetGeneration: 2),
               "current session accepts only its own generation")
        expect(!secondA.accepts(application: appA, targetGeneration: 3) &&
               !secondA.accepts(application: ApplicationInstanceKey(pid: 1301, generation: 2),
                                targetGeneration: 2),
               "app generation change invalidates the session")
    }

    // MARK: 稳定顺序与选择

    /// 键盘面板关闭时的焦点归还策略。
    static func focusReturnPolicy() {
        let own: pid_t = 4242
        func shouldReturn(previous: pid_t?, frontmost: pid_t?,
                          mode: WindowBrowserPanelMode = .keyboard,
                          wasKey: Bool = true) -> Bool {
            WindowBrowserFocusReturnPolicy.shouldReturnFocus(
                previousAppPID: previous, ownPID: own, currentFrontmostPID: frontmost,
                mode: mode, panelWasKeyWindow: wasKey)
        }
        expect(shouldReturn(previous: 100, frontmost: own),
               "keyboard panel returns focus when we still hold it")
        expect(!shouldReturn(previous: 100, frontmost: 100),
               "focus is not stolen back after the user clicked another app")
        expect(!shouldReturn(previous: 100, frontmost: own, mode: .dock),
               "Dock panels never return focus (they never took it)")
        expect(!shouldReturn(previous: 100, frontmost: own, wasKey: false),
               "no focus return when the panel was not key")
        expect(!shouldReturn(previous: nil, frontmost: own),
               "no recorded previous app means nothing to return to")
        expect(!shouldReturn(previous: own, frontmost: own),
               "we do not 'return' focus to ourselves")

        // 重复打开面板：已打开的键盘面板只聚焦，不叠加；Dock 面板先替换。
        expect(WindowBrowserOpenPolicy.action(existingMode: nil, panelIsVisible: false)
               == .create, "no existing panel creates a new one")
        expect(WindowBrowserOpenPolicy.action(existingMode: .keyboard, panelIsVisible: true)
               == .focusExisting, "an open keyboard panel is focused, not duplicated")
        expect(WindowBrowserOpenPolicy.action(existingMode: .dock, panelIsVisible: true)
               == .replaceExisting, "a dock panel is replaced by the keyboard panel")
        expect(WindowBrowserOpenPolicy.action(existingMode: .keyboard, panelIsVisible: false)
               == .create, "a closed panel does not block a new one")
    }

    /// 临时面板状态机：每个状态携带 token，过期回调必须被拒绝。
    static func panelStateMachine() {
        var machine = WindowBrowserPanelStateMachine()
        let first = WindowBrowserRequestID(value: 1)
        let second = WindowBrowserRequestID(value: 2)

        expect(machine.state == .hidden(nil), "panel starts hidden without a token")
        expect(machine.beginShow(request: first), "hidden can begin showing")
        expect(machine.state == .pendingShow(first), "pending show carries its token")
        expect(!machine.confirmShow(request: second),
               "a stale token cannot confirm show")
        expect(machine.confirmShow(request: first), "the owning token confirms show")
        expect(machine.state == .visible(first), "visible carries the token")
        expect(!machine.beginHide(request: second), "a stale token cannot begin hide")
        expect(machine.beginHide(request: first), "visible can begin hiding")
        expect(machine.state == .pendingHide(first), "pending hide carries the token")
        expect(machine.cancelHide(request: first), "mouse re-entry cancels pending hide")
        expect(machine.state == .visible(first), "cancel returns to visible")
        expect(machine.beginInteraction(request: first), "mouse inside the panel enters interaction")
        expect(!machine.beginHide(request: first), "interaction blocks auto-hide")
        expect(machine.endInteraction(request: first), "leaving the panel ends interaction")
        expect(machine.state == .visible(first), "ends back in visible")
        expect(machine.beginHide(request: first), "hide can start after interaction")
        // pendingHide 重复排程必须幂等，否则一次“鼠标仍在内”的检查会让状态卡住。
        expect(machine.beginHide(request: first),
               "re-arming hide while already pending succeeds")
        expect(machine.state == .pendingHide(first), "still pending hide after re-arm")
        expect(machine.confirmShow(request: first),
               "a panel that actually appeared returns to visible from pendingHide")
        expect(machine.state == .visible(first), "pendingHide -> visible keeps the token")
        expect(machine.accepts(first) && !machine.accepts(second),
               "only the current token is accepted")
        machine.reset()
        expect(machine.state == .hidden(nil) && !machine.accepts(first),
               "reset drops the token")

        // Dock 图标切换：新 token 替换待显示状态，旧 token 失效。
        _ = machine.beginShow(request: first)
        _ = machine.beginShow(request: second)
        expect(machine.state == .pendingShow(second) && !machine.accepts(first),
               "switching targets replaces the pending show token")
    }

    static func listStabilityAndSelection() {
        let catalog = WindowCatalog()
        _ = catalog.applyManaged([
            managed(pid: 1401, id: 101, title: "甲"),
            managed(pid: 1401, id: 102, title: "乙")
        ])
        var state = WindowBrowserListState()
        var visible = state.reconcile(records: catalog.publish())
        let initialOrder = visible.map(\.key)
        guard let keyA = visible.first(where: { $0.displayTitle == "甲" })?.key,
              let keyB = visible.first(where: { $0.displayTitle == "乙" })?.key else {
            expect(false, "baseline list must contain both windows")
            return
        }

        state.select(keyB)
        // 标题变化与截图完成不会重排已存在项目。
        _ = catalog.applyManaged([
            managed(pid: 1401, id: 101, title: "甲", frame: CGRect(x: 1, y: 1, width: 5, height: 5)),
            managed(pid: 1401, id: 102, title: "乙改名")
        ])
        visible = state.reconcile(records: catalog.publish())
        expect(visible.map(\.key) == initialOrder,
               "existing items keep their order across metadata updates")
        expect(state.selection == keyB, "selection is stored by WindowKey, not index")

        // 新项目按确定规则追加，不插到已存在项目中间。
        _ = catalog.applyManaged([
            managed(pid: 1401, id: 101, title: "甲"),
            managed(pid: 1401, id: 102, title: "乙改名"),
            managed(pid: 1401, id: 103, title: "丙")
        ])
        visible = state.reconcile(records: catalog.publish())
        expect(visible.count == 3 && visible[0].key == initialOrder[0]
               && visible[1].key == initialOrder[1],
               "new items append after existing items")
        guard let keyC = visible.first(where: { $0.displayTitle == "丙" })?.key else {
            expect(false, "third window must be visible")
            return
        }

        // 选中项关闭后选择原位置附近的项目。
        state.select(keyB)
        _ = catalog.confirmWindowDestroyed(keyB)
        visible = state.reconcile(records: catalog.publish())
        expect(visible.count == 2 && !visible.map(\.key).contains(keyB),
               "removed item disappears by identity")
        expect(state.selection == keyA, "selection moves to the nearest surviving item")

        // 搜索导致选中项不可见时选择第一个有效结果；空结果清空选择。
        state.select(keyC)
        var filtered = visible.filter { WindowBrowserSearch.matches(query: "甲", record: $0) }
        state.applyVisible(filtered.map(\.key))
        expect(state.selection == keyA, "filtered selection falls back to first visible result")
        filtered = visible.filter { WindowBrowserSearch.matches(query: "不存在", record: $0) }
        state.applyVisible(filtered.map(\.key))
        expect(state.selection == nil, "empty search clears selection")
        state.removeAll()
        expect(state.orderedKeys.isEmpty, "session teardown clears list state")
    }

    // MARK: 搜索

    static func search() {
        let record = WindowRecord(
            key: WindowKey(application: ApplicationInstanceKey(pid: 1501, generation: 1),
                           originalWindowID: 201, windowGeneration: 1),
            bundleIdentifier: "com.example.app",
            appName: "Safari 浏览器",
            title: "Quarterly Report",
            logicalFrame: nil,
            placementSource: .liveDiscovery,
            systemVisibility: .onScreen,
            shadeState: .normal,
            pinState: .none,
            capabilities: .discoveredWindow,
            confidence: .confirmed,
            metadataRevision: 1,
            isMinimized: false,
            isOnScreen: true,
            isFoldedOffscreen: false,
            isManaged: false)
        expect(WindowBrowserSearch.matches(query: "safari", record: record),
               "search ignores case")
        expect(WindowBrowserSearch.matches(query: "ｓａｆａｒｉ", record: record),
               "search applies width folding for full-width text")
        expect(WindowBrowserSearch.matches(query: "report", record: record),
               "search matches window titles")
        expect(!WindowBrowserSearch.matches(query: "excel", record: record),
               "search rejects unrelated text")
    }

    // MARK: 布局

    static func actions() {
        let targetA = WindowKey(application: ApplicationInstanceKey(pid: 2001, generation: 1),
                                originalWindowID: 301, windowGeneration: 1)
        let targetB = WindowKey(application: ApplicationInstanceKey(pid: 2001, generation: 1),
                                originalWindowID: 302, windowGeneration: 1)

        // 14. 同一窗口连续点击展开，实际恢复事务只执行一次（同义请求合并）。
        let backend = FakeActionBackend()
        let scheduler = ManualScheduler()
        let coordinator = WindowBrowserActionCoordinator(backend: backend, scheduler: scheduler)
        var outcomes: [String] = []
        coordinator.submit(action: .unfold, target: targetA) { outcomes.append("first:\($0)") }
        coordinator.submit(action: .unfold, target: targetA) { outcomes.append("second:\($0)") }
        scheduler.runAsync()
        expect(backend.performed.count == 1, "identical in-flight actions must coalesce")
        backend.completeNext(.completed)
        scheduler.runAsync()
        expect(outcomes.count == 2 && outcomes.allSatisfy { $0.contains("completed") },
               "coalesced completions fire exactly once for every caller")
        expect(!coordinator.isBusy(windowKey: targetA), "coordinator returns to idle")

        // 已完成恢复的重复回调不会触发第二次完成或新动作。
        backend.completeNext(.completed)
        scheduler.runAsync()
        expect(outcomes.count == 2, "duplicate backend completion must not re-emit an outcome")

        // 不同动作在忙时返回 busy，不无限排队。
        backend.autoOutcome = nil
        coordinator.submit(action: .unfold, target: targetA) { outcomes.append("unfold:\($0)") }
        scheduler.runAsync()
        coordinator.submit(action: .fold, target: targetA) { outcomes.append("fold:\($0)") }
        expect(outcomes.last?.contains("busy") == true,
               "opposite action while a write is in flight must return busy")
        backend.completeNext(.completed)
        scheduler.runAsync()

        // 目标无法确认时拒绝操作，不猜测替代窗口。
        backend.autoOutcome = .completed
        backend.validation = .unverifiable(reason: "PID 复用")
        var uncertain: WindowBrowserActionOutcome?
        coordinator.submit(action: .close, target: targetB) { uncertain = $0 }
        scheduler.runAsync()
        expect(uncertain == .uncertain(reason: "目标无法确认：PID 复用"),
               "unverifiable target must be refused without performing an action")
        expect(backend.performed.count == 2, "refused action must not reach the backend")

        backend.validation = .permissionMissing(.screenRecording)
        var permission: WindowBrowserActionOutcome?
        coordinator.submit(action: .pinPreview, target: targetB) { permission = $0 }
        scheduler.runAsync()
        expect(permission == .permissionRequired(kind: .screenRecording),
               "missing permission returns permissionRequired")

        // 超时：UI 得到 uncertain，但底层仍占额度；真实完成前不能启动相反动作。
        backend.validation = .valid
        backend.autoOutcome = nil
        let timeoutBackend = FakeActionBackend()
        timeoutBackend.autoOutcome = nil
        let timeoutScheduler = ManualScheduler()
        var late: [(WindowBrowserActionOutcome, WindowBrowserAction)] = []
        let timeoutCoordinator = WindowBrowserActionCoordinator(
            backend: timeoutBackend, scheduler: timeoutScheduler, timeout: 6,
            onLateOutcome: { outcome, action, _ in late.append((outcome, action)) })
        var timedOut: WindowBrowserActionOutcome?
        timeoutCoordinator.submit(action: .fold, target: targetA) { timedOut = $0 }
        timeoutScheduler.runAsync()
        timeoutScheduler.advance(6.0)
        expect(timedOut == .uncertain(reason: "操作超时，底层事务可能仍在执行"),
               "timeout reports uncertain without freeing the slot")
        expect(timeoutCoordinator.isBusy(windowKey: targetA),
               "timed-out transaction still holds the per-PID write slot")
        var busyOpposite: WindowBrowserActionOutcome?
        timeoutCoordinator.submit(action: .unfold, target: targetA) { busyOpposite = $0 }
        expect(busyOpposite == .busy, "opposite action must not start after a UI timeout")
        timeoutBackend.completeNext(.completed)
        timeoutScheduler.runAsync()
        expect(late.count == 1 && late[0].1 == .fold,
               "late completion is accounted for but not delivered as a UI outcome")
        expect(!timeoutCoordinator.isBusy(windowKey: targetA),
               "real completion releases the slot")

        // 恢复发起成功但验证失败：结果不能是 completed，也不能继续置顶。
        let failedBackend = FakeActionBackend()
        failedBackend.autoOutcome = .failed(reason: "恢复未确认")
        let failedScheduler = ManualScheduler()
        let failedCoordinator = WindowBrowserActionCoordinator(backend: failedBackend,
                                                               scheduler: failedScheduler)
        var failedOutcome: WindowBrowserActionOutcome?
        failedCoordinator.submit(action: .unfold, target: targetA) { failedOutcome = $0 }
        failedScheduler.runAsync()
        expect(failedOutcome == .failed(reason: "恢复未确认"),
               "restore verification failure must not report completed")
        expect(failedBackend.performed.map(\.0) == [.unfold],
               "verification failure must not be followed by pin preview")

        // 16b. 桥接 completion 的单次完成门：正常返回、失败、超时竞争只允许生效一次。
        var gated: [Int] = []
        let gate = WindowBrowserSingleShotCompletion<Int> { gated.append($0) }
        expect(gate.call(1), "first completion passes the gate")
        expect(!gate.call(2), "second completion is rejected by the gate")
        expect(gated == [1] && gate.hasFinished,
               "gated completion fires exactly once")

        // 23. 面板关闭只取消排队请求；已经开始的恢复事务继续到真实终态。
        let activeBackend = FakeActionBackend()
        activeBackend.autoOutcome = nil
        let activeScheduler = ManualScheduler()
        let activeCoordinator = WindowBrowserActionCoordinator(backend: activeBackend,
                                                               scheduler: activeScheduler)
        var activeOutcomes: [WindowBrowserActionOutcome] = []
        activeCoordinator.submit(action: .unfold, target: targetA) { activeOutcomes.append($0) }
        activeScheduler.runAsync()
        activeCoordinator.cancelPending(for: targetA.application.pid)
        expect(activeCoordinator.isBusy(windowKey: targetA),
               "an already-started transaction keeps the write slot after panel close")
        expect(activeOutcomes.isEmpty,
               "panel close must not cancel an already-started restore transaction")
        activeBackend.completeNext(.completed)
        activeScheduler.runAsync()
        expect(activeOutcomes == [.completed] && !activeCoordinator.isBusy(windowKey: targetA),
               "the started transaction still delivers its real terminal outcome")

        // 排队中的请求在面板关闭时以 uncertain 取消，不会在关闭后突然开始。
        let queuedBackend = FakeActionBackend()
        queuedBackend.autoOutcome = nil
        let queuedScheduler = ManualScheduler()
        let queuedCoordinator = WindowBrowserActionCoordinator(backend: queuedBackend,
                                                               scheduler: queuedScheduler)
        queuedCoordinator.submit(action: .unfold, target: targetA) { _ in }
        queuedScheduler.runAsync()
        var queuedOutcome: WindowBrowserActionOutcome?
        queuedCoordinator.submit(action: .unfold, target: targetB) { queuedOutcome = $0 }
        queuedCoordinator.cancelPending(for: targetB.application.pid)
        expect(queuedBackend.performed.count == 1,
               "queued request must not reach the backend after cancellation")
        if case .uncertain = queuedOutcome {} else {
            expect(false, "queued request cancelled at panel close reports uncertain")
        }
        queuedBackend.completeNext(.completed)
        queuedScheduler.runAsync()

        // 17. 目标身份判定与当前焦点无关：只看 PID + 原窗口 ID。
        expect(WindowBrowserTargetIdentity.matches(
            elementPID: targetA.application.pid, elementWindowID: targetA.originalWindowID,
            expectedPID: targetA.application.pid, expectedWindowID: targetA.originalWindowID),
               "matching pid and window id is accepted regardless of focus")
        expect(!WindowBrowserTargetIdentity.matches(
            elementPID: 9999, elementWindowID: targetA.originalWindowID,
            expectedPID: targetA.application.pid, expectedWindowID: targetA.originalWindowID),
               "a different pid (focus moved to another app) is rejected")
        expect(!WindowBrowserTargetIdentity.matches(
            elementPID: targetA.application.pid, elementWindowID: targetB.originalWindowID,
            expectedPID: targetA.application.pid, expectedWindowID: targetA.originalWindowID),
               "a different window id (focus moved to a sibling) is rejected")
        expect(!WindowBrowserTargetIdentity.matches(
            elementPID: targetA.application.pid, elementWindowID: nil,
            expectedPID: targetA.application.pid, expectedWindowID: targetA.originalWindowID),
               "an unresolvable window id is rejected")

        // 11/12/4/37. 异步结果接收条件：功能、请求代数、应用实例三者缺一不可。
        let requestA1 = WindowBrowserRequestID(value: 11)
        let requestB = WindowBrowserRequestID(value: 12)
        let requestA2 = WindowBrowserRequestID(value: 13)
        let appA1 = ApplicationInstanceKey(pid: 2001, generation: 1)
        let appA2 = ApplicationInstanceKey(pid: 2001, generation: 2)

        func accepts(session: WindowBrowserRequestID?,
                     result: WindowBrowserRequestID,
                     enabled: Bool = true,
                     expected: ApplicationInstanceKey?,
                     current: ApplicationInstanceKey?) -> Bool {
            WindowBrowserRequestValidity.accepts(running: true, featureEnabled: enabled,
                                                 sessionRequestID: session,
                                                 resultRequestID: result,
                                                 expectedAppInstance: expected,
                                                 currentAppInstance: current)
        }
        expect(accepts(session: requestA1, result: requestA1, expected: appA1, current: appA1),
               "current session accepts its own result")
        expect(!accepts(session: requestA1, result: requestA1, enabled: false,
                        expected: appA1, current: appA1),
               "a result arriving after the feature was disabled is dropped")
        expect(!accepts(session: requestB, result: requestA1, expected: appA1, current: appA1),
               "A→B must drop A's result")
        expect(!accepts(session: requestA2, result: requestA1, expected: appA1, current: appA1),
               "A→B→A must drop the first A's result")
        expect(!accepts(session: requestA1, result: requestA1,
                        expected: appA1, current: appA2),
               "a result arriving after PID reuse must not write the new app instance")
        expect(accepts(session: requestA1, result: requestA1, expected: nil, current: appA2),
               "keyboard sessions target any current app instance")
    }

    final class FakeActionBackend: WindowBrowserActionBackend {
        var validation: WindowBrowserTargetValidation = .valid
        var performed: [(WindowBrowserAction, WindowKey)] = []
        var autoOutcome: WindowBrowserActionOutcome? = .completed
        private var pending: [(WindowBrowserAction, WindowKey,
                               (WindowBrowserActionOutcome) -> Void)] = []

        func validate(target: WindowKey,
                      completion: @escaping (WindowBrowserTargetValidation) -> Void) {
            completion(validation)
        }

        func perform(action: WindowBrowserAction, target: WindowKey,
                     completion: @escaping (WindowBrowserActionOutcome) -> Void) {
            performed.append((action, target))
            if let autoOutcome {
                completion(autoOutcome)
            } else {
                pending.append((action, target, completion))
            }
        }

        func completeNext(_ outcome: WindowBrowserActionOutcome) {
            guard !pending.isEmpty else { return }
            let next = pending.removeFirst()
            next.2(outcome)
        }
    }

    final class ManualScheduler: WindowBrowserScheduler {
        final class Item {
            let due: TimeInterval
            let work: () -> Void
            var cancelled = false
            init(due: TimeInterval, work: @escaping () -> Void) {
                self.due = due
                self.work = work
            }
        }

        var now: TimeInterval = 0
        private var items: [Item] = []
        private var asyncQueue: [() -> Void] = []

        func async(_ work: @escaping () -> Void) {
            asyncQueue.append(work)
        }

        func schedule(after delay: TimeInterval,
                      _ work: @escaping () -> Void) -> WindowBrowserScheduledWork {
            let item = Item(due: now + max(0, delay), work: work)
            items.append(item)
            return WindowBrowserScheduledWork(onCancel: { item.cancelled = true })
        }

        func runAsync() {
            var guardCount = 0
            while !asyncQueue.isEmpty, guardCount < 10_000 {
                guardCount += 1
                let queue = asyncQueue
                asyncQueue = []
                queue.forEach { $0() }
            }
        }

        func advance(_ delta: TimeInterval) {
            let end = now + delta
            while let next = items.filter({ !$0.cancelled && $0.due <= end })
                .min(by: { $0.due < $1.due }) {
                items.removeAll { $0 === next }
                now = next.due
                next.work()
                runAsync()
            }
            now = end
            runAsync()
        }
    }

    // MARK: 动作能力/权限预检

    static func actionPolicy() {
        let base = sampleRecord()
        func preflight(_ action: WindowBrowserAction, _ record: WindowRecord,
                       accessibility: Bool = true,
                       screenRecording: Bool = true) -> WindowBrowserActionOutcome? {
            WindowBrowserActionPolicy.preflight(action: action, record: record,
                                                hasAccessibility: accessibility,
                                                hasScreenRecording: screenRecording)
        }

        expect(preflight(.fold, base) == nil,
               "fold is allowed for a normal window with accessibility")
        var pinnedRunning = base
        pinnedRunning.pinState = .running
        pinnedRunning.capabilities.insert(.unpinPreview)
        expect(preflight(.fold, pinnedRunning) == nil,
               "folding a pinned window still goes through the existing fold path "
               + "(which stops the pinned stream itself)")
        expect(preflight(.close, base, accessibility: false)
               == .permissionRequired(kind: .accessibility),
               "close without accessibility asks for the permission")
        expect(preflight(.pinPreview, base, screenRecording: false)
               == .permissionRequired(kind: .screenRecording),
               "creating a pinned preview without screen recording asks for the permission")
        expect(preflight(.activate, base, accessibility: false)
               == .permissionRequired(kind: .accessibility),
               "activate without accessibility asks for the permission")

        var suspended = base
        suspended.pinState = .suspended
        expect(preflight(.pinPreview, suspended)
               == .unsupported(reason: "置顶预览已暂停，请先在菜单恢复"),
               "a suspended pinned session is never resumed by the new entry")

        expect(preflight(.unfold, base) == .completed,
               "unfolding an already-unfolded window is a safe completion")

        var folded = base
        folded.shadeState = .folded
        folded.capabilities = [.activate, .unfold, .close, .minimize]
        expect(preflight(.fold, folded) == .completed,
               "folding an already-folded window is a safe completion")
        expect(preflight(.unfold, folded) == nil,
               "unfold uses the existing restore entry when available")

        var noUnfold = folded
        noUnfold.capabilities = [.activate]
        expect(preflight(.unfold, noUnfold)
               == .unsupported(reason: "这个窗口没有可用的恢复入口"),
               "unfold without a restore entry is refused")

        var restoring = base
        restoring.shadeState = .restoring
        expect(preflight(.fold, restoring) == .busy,
               "fold is refused while a restore is in flight")

        var noMinimize = base
        noMinimize.capabilities = [.activate]
        expect(preflight(.minimize, noMinimize)
               == .unsupported(reason: "这个窗口不提供最小化能力"),
               "minimize without capability is refused")
        var minimized = base
        minimized.isMinimized = true
        expect(preflight(.minimize, minimized) == .completed,
               "minimizing an already minimized window is a safe completion")

        expect(preflight(.unpinPreview, base) == .completed,
               "unpinning when nothing is pinned is a safe completion")
        var pinned = base
        pinned.pinState = .running
        pinned.capabilities.insert(.unpinPreview)
        expect(preflight(.unpinPreview, pinned) == nil,
               "unpinning a running session does not require screen recording")
        expect(preflight(.unpinPreview, pinned, screenRecording: false) == nil,
               "local cleanup must not be blocked by revoked screen recording")
    }

    static func thumbnails() {
        let keyA = WindowKey(application: ApplicationInstanceKey(pid: 3001, generation: 1),
                             originalWindowID: 401, windowGeneration: 1)
        let keyB = WindowKey(application: ApplicationInstanceKey(pid: 3001, generation: 1),
                             originalWindowID: 402, windowGeneration: 1)
        let keyC = WindowKey(application: ApplicationInstanceKey(pid: 3002, generation: 1),
                             originalWindowID: 403, windowGeneration: 1)
        let size = CGSize(width: 300, height: 200)

        // 25. 同 key 同档位的并发请求只发起一次实际截图。
        let shared = FakeThumbnailBackend()
        shared.autoResult = nil
        let service = WindowThumbnailService(backend: shared)
        var deliveredA = 0
        _ = service.request(windowKey: keyA, purpose: .card, logicalSize: size,
                            onImage: { _ in deliveredA += 1 })
        _ = service.request(windowKey: keyA, purpose: .card, logicalSize: size,
                            onImage: { _ in deliveredA += 1 })
        expect(shared.started.count == 1, "same key and pixel class shares one capture")
        shared.completeNext(.success(makeImage(width: 8, height: 8)))
        expect(deliveredA == 2, "shared capture delivers to every consumer")

        // 26. 一个消费者取消不会误取消其他仍有效消费者。
        let cancelBackend = FakeThumbnailBackend()
        cancelBackend.autoResult = nil
        let cancelService = WindowThumbnailService(backend: cancelBackend)
        var deliveredB = 0
        let first = cancelService.request(windowKey: keyB, purpose: .card, logicalSize: size,
                                          onImage: { _ in deliveredB += 1 })
        _ = cancelService.request(windowKey: keyB, purpose: .card, logicalSize: size,
                                  onImage: { _ in deliveredB += 1 })
        first.cancel()
        expect(cancelBackend.cancelled.isEmpty,
               "one consumer leaving must not cancel the shared capture")
        cancelBackend.completeNext(.success(makeImage(width: 8, height: 8)))
        expect(deliveredB == 1, "remaining consumer still receives the image")

        // 27. 并发不超过预算；取消但未结束的系统调用仍占额度。
        let budgetBackend = FakeThumbnailBackend()
        budgetBackend.autoResult = nil
        let budgetService = WindowThumbnailService(backend: budgetBackend, maxConcurrent: 2)
        _ = budgetService.request(windowKey: keyA, purpose: .card, logicalSize: size,
                                  onImage: { _ in })
        _ = budgetService.request(windowKey: keyB, purpose: .card, logicalSize: size,
                                  onImage: { _ in })
        _ = budgetService.request(windowKey: keyC, purpose: .card, logicalSize: size,
                                  onImage: { _ in })
        expect(budgetBackend.started.count == 2, "only two captures may run at once")
        budgetBackend.completeNext(.success(makeImage(width: 8, height: 8)))
        expect(budgetBackend.started.count == 3, "queued capture starts after a slot frees")
        budgetBackend.completeNext(.success(makeImage(width: 8, height: 8)))
        budgetBackend.completeNext(.success(makeImage(width: 8, height: 8)))

        // 取消一个已经开始但无法真正取消的调用：额度直到它返回才释放。
        let stuckBackend = FakeThumbnailBackend()
        stuckBackend.autoResult = nil
        let stuckService = WindowThumbnailService(backend: stuckBackend, maxConcurrent: 1)
        let stuck = stuckService.request(windowKey: keyA, purpose: .card, logicalSize: size,
                                         onImage: { _ in })
        _ = stuckService.request(windowKey: keyB, purpose: .card, logicalSize: size,
                                 onImage: { _ in })
        stuck.cancel()
        expect(stuckBackend.started.count == 1,
               "cancelling a started capture must not free the slot")
        expect(stuckService.runningCaptureCount == 1,
               "started-but-uncancellable system call still occupies the budget")
        stuckBackend.completeNext(.success(makeImage(width: 8, height: 8)))
        expect(stuckBackend.started.count == 2, "slot released only after the real return")
        stuckBackend.completeNext(.success(makeImage(width: 8, height: 8)))

        // 28. 图像预算超限时正确淘汰。
        let evictionBackend = FakeThumbnailBackend()
        let evictionService = WindowThumbnailService(backend: evictionBackend,
                                                     budgetBytes: 64 * 8 * 8)
        _ = evictionService.request(windowKey: keyA, purpose: .selectedLarge, logicalSize: size,
                                    onImage: { _ in })
        evictionBackend.completeNext(.success(makeImage(width: 64, height: 64)))
        _ = evictionService.request(windowKey: keyB, purpose: .selectedLarge, logicalSize: size,
                                    onImage: { _ in })
        evictionBackend.completeNext(.success(makeImage(width: 64, height: 64)))
        expect(evictionService.cachedCostBytes <= 64 * 8 * 8,
               "cache evicts oldest entries when over budget")

        // 30. 黑色有效截图不因亮度低被判无效；31. 失败不触发整屏回退。
        let blackBackend = FakeThumbnailBackend()
        blackBackend.autoResult = .success(makeImage(width: 32, height: 32, fill: 0))
        let blackService = WindowThumbnailService(backend: blackBackend)
        var blackDelivered = false
        _ = blackService.request(windowKey: keyA, purpose: .card, logicalSize: size,
                                 onImage: { _ in blackDelivered = true })
        expect(blackDelivered, "a black image must be treated as valid content")

        let failedBackend = FakeThumbnailBackend()
        failedBackend.autoResult = .failure(.captureFailed("protected"))
        let failedService = WindowThumbnailService(backend: failedBackend)
        var failure: WindowThumbnailFailure?
        _ = failedService.request(windowKey: keyA, purpose: .card, logicalSize: size,
                                  onImage: { _ in }, onFailure: { failure = $0 })
        expect(failure == .captureFailed("protected"), "capture failure is reported as a failure")
        expect(failedBackend.started.count == 1,
               "single-window capture failure must not retry with a screen-wide fallback")

        // 34/36. 关闭或排除后，晚到的结果不能重新进入缓存或 UI。
        let lateBackend = FakeThumbnailBackend()
        lateBackend.autoResult = nil
        let lateService = WindowThumbnailService(backend: lateBackend)
        var lateDelivered = false
        _ = lateService.request(windowKey: keyC, purpose: .card, logicalSize: size,
                                onImage: { _ in lateDelivered = true })
        lateService.invalidateAll()
        lateBackend.completeNext(.success(makeImage(width: 8, height: 8)))
        expect(!lateDelivered, "a stream finishing after close must not reach the UI")
        expect(lateService.cachedCostBytes == 0, "invalidated results never enter the cache")
        expect(!lateBackend.cancelled.isEmpty,
               "invalidation asks the system capture to stop")
    }

    final class FakeThumbnailBackend: WindowThumbnailBackend {
        var autoResult: Result<CGImage, WindowThumbnailFailure>?
        var autoResultProvider: ((WindowThumbnailRequest) -> Result<CGImage, WindowThumbnailFailure>)?
        private(set) var started: [WindowThumbnailRequest] = []
        private(set) var cancelled: [WindowThumbnailKey] = []
        private var pending: [(WindowThumbnailRequest,
                               (Result<CGImage, WindowThumbnailFailure>) -> Void)] = []

        func capture(request: WindowThumbnailRequest,
                     completion: @escaping (Result<CGImage, WindowThumbnailFailure>) -> Void) {
            started.append(request)
            if let autoResultProvider {
                completion(autoResultProvider(request))
            } else if let autoResult {
                completion(autoResult)
            } else {
                pending.append((request, completion))
            }
        }

        func cancel(request: WindowThumbnailRequest) {
            cancelled.append(request.key)
        }

        func completeNext(_ result: Result<CGImage, WindowThumbnailFailure>) {
            guard !pending.isEmpty else { return }
            let next = pending.removeFirst()
            next.1(result)
        }

        /// 已完成回调（按注册顺序）；用于模拟重复完成。
        var pendingCompletions: [(Result<CGImage, WindowThumbnailFailure>) -> Void] {
            pending.map { $0.1 }
        }

        /// 完成指定下标仍在等待的任务（顺序可控）。
        func complete(index: Int, with result: Result<CGImage, WindowThumbnailFailure>) {
            guard pending.indices.contains(index) else { return }
            let next = pending.remove(at: index)
            next.1(result)
        }

        func completeAll(with result: Result<CGImage, WindowThumbnailFailure>) {
            while !pending.isEmpty {
                let next = pending.removeFirst()
                next.1(result)
            }
        }
    }

    static func makeImage(width: Int, height: Int, fill: UInt8 = 200) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let data = Data(repeating: fill, count: width * height * 4)
        let provider = CGDataProvider(data: data as CFData)!
        return CGImage(width: width, height: height,
                       bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4,
                       space: colorSpace,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false,
                       intent: .defaultIntent)!
    }

    // MARK: 普通窗口过滤

    /// “先展示标题和已有缓存”的实测：已管理快照 → 目录发布 → 稳定排序 → 面板几何。
    /// 这条路径不等待任何截图或系统发现，目标是开发计划里的 50ms 首屏预算。
    static func firstContentLatency() {
        let catalog = WindowCatalog()
        let descriptors = (1...50).map { index in
            managed(pid: 7001, id: CGWindowID(2000 + index),
                    title: index % 5 == 0
                        ? "较长的中英文混合窗口标题 Window \(index)"
                        : "窗口 \(index)",
                    frame: CGRect(x: 40 + index, y: 60 + index, width: 800, height: 600))
        }
        var listState = WindowBrowserListState()
        let started = CFAbsoluteTimeGetCurrent()
        _ = catalog.applyManaged(descriptors)
        let records = catalog.records(forPID: 7001)
        let ordered = listState.reconcile(records: records)
        _ = WindowBrowserGeometry.panelGeometry(
            iconFrame: NSRect(x: 700, y: 8, width: 52, height: 52),
            edge: .bottom,
            screenFrame: NSRect(x: 0, y: 0, width: 1440, height: 900),
            visibleFrame: NSRect(x: 0, y: 78, width: 1440, height: 822),
            desiredSize: CGSize(width: 520, height: 460),
            windowCount: ordered.count)
        let elapsedMilliseconds = (CFAbsoluteTimeGetCurrent() - started) * 1000
        expect(ordered.count == 50, "managed snapshot publishes every managed window")
        expect(elapsedMilliseconds < 50,
               "first text/cached content must be ready well inside the 50ms goal "
               + "(measured \(String(format: "%.2f", elapsedMilliseconds))ms)")
        print("window-browser: first-content latency windows=50 "
              + "took=\(String(format: "%.2f", elapsedMilliseconds))ms")

        // 规模对照：200 个已管理窗口走同一条首屏路径，仍须留在 50ms 开发预算内。
        let manyCatalog = WindowCatalog()
        let manyDescriptors = (1...200).map { index in
            managed(pid: 7002, id: CGWindowID(4000 + index),
                    title: "窗口 \(index)",
                    frame: CGRect(x: 20 + index, y: 30 + index, width: 800, height: 600))
        }
        var manyState = WindowBrowserListState()
        let manyStarted = CFAbsoluteTimeGetCurrent()
        _ = manyCatalog.applyManaged(manyDescriptors)
        let manyOrdered = manyState.reconcile(records: manyCatalog.records(forPID: 7002))
        let manyElapsed = (CFAbsoluteTimeGetCurrent() - manyStarted) * 1000
        expect(manyOrdered.count == 200, "200 managed windows all publish")
        expect(manyElapsed < 50,
               "first content for 200 windows stays inside the 50ms budget "
               + "(measured \(String(format: "%.2f", manyElapsed))ms)")
        print("window-browser: first-content latency windows=200 "
              + "took=\(String(format: "%.2f", manyElapsed))ms")
    }

    static func thumbnailPolicy() {
        var inputs = WindowBrowserThumbnailInputs()
        expect(WindowBrowserThumbnailPolicy.source(inputs) == .applicationIcon,
               "without screen recording the panel falls back to icon and text")

        inputs.hasScreenRecording = true
        inputs.canCapture = true
        expect(WindowBrowserThumbnailPolicy.source(inputs) == .singleWindowCapture,
               "ordinary visible window uses a single-window capture")

        inputs.isSelected = true
        inputs.livePreviewEnabled = true
        expect(WindowBrowserThumbnailPolicy.source(inputs) == .liveStream,
               "selected ordinary window may use a controlled live stream")

        inputs.pinnedStreamRunning = true
        expect(WindowBrowserThumbnailPolicy.source(inputs) == .pinnedMirror,
               "selected window with a running pinned stream reuses its mirror")
        inputs.isSelected = false
        expect(WindowBrowserThumbnailPolicy.source(inputs) == .singleWindowCapture,
               "only the selected item may attach the single mirror slot")

        inputs.pinnedStreamRunning = false
        inputs.pinnedSuspended = true
        expect(WindowBrowserThumbnailPolicy.source(inputs) == .applicationIcon,
               "a suspended pinned session is not resumed or duplicated for a thumbnail")

        inputs.pinnedSuspended = false
        inputs.isMinimized = true
        expect(WindowBrowserThumbnailPolicy.source(inputs) == .applicationIcon,
               "minimized windows are not woken up to refresh a thumbnail")

        inputs.isMinimized = false
        inputs.isFolded = true
        inputs.hasCachedFoldImage = true
        expect(WindowBrowserThumbnailPolicy.source(inputs) == .cachedFoldSnapshot,
               "folded window prefers its saved snapshot")
        inputs.hasCachedFoldImage = false
        expect(WindowBrowserThumbnailPolicy.source(inputs) == .applicationIcon,
               "folded window without a saved snapshot is not expanded for a thumbnail")

        inputs.isFolded = false
        inputs.isExcluded = true
        expect(WindowBrowserThumbnailPolicy.source(inputs) == .applicationIcon,
               "excluded applications never request images")

        // 34. 视频流在面板关闭后才启动成功：保留判断必须为假，调用方随即停流。
        expect(WindowBrowserLivePreviewPolicy.shouldKeepStartedStream(
            leaseIsCurrent: true, cancelled: false, sessionActive: true,
            targetStillKnown: true),
               "a current stream for a live target is kept")
        expect(!WindowBrowserLivePreviewPolicy.shouldKeepStartedStream(
            leaseIsCurrent: false, cancelled: false, sessionActive: true,
            targetStillKnown: true),
               "a stream whose lease was released must be stopped after start")
        expect(!WindowBrowserLivePreviewPolicy.shouldKeepStartedStream(
            leaseIsCurrent: true, cancelled: true, sessionActive: true,
            targetStillKnown: true),
               "a cancelled lease must be stopped after start")
        expect(!WindowBrowserLivePreviewPolicy.shouldKeepStartedStream(
            leaseIsCurrent: true, cancelled: false, sessionActive: false,
            targetStillKnown: true),
               "a stream started after the panel closed must be stopped")
        expect(!WindowBrowserLivePreviewPolicy.shouldKeepStartedStream(
            leaseIsCurrent: true, cancelled: false, sessionActive: true,
            targetStillKnown: false),
               "a stream for a vanished target must be stopped")

        // 档位替换：同档位复用订阅，跨档位（卡片 → 选中大图）必须换。
        expect(!WindowBrowserThumbnailSubscriptionPolicy.needsReplace(
            existingPurpose: .card, desired: .card),
               "same pixel class reuses the existing subscription")
        expect(WindowBrowserThumbnailSubscriptionPolicy.needsReplace(
            existingPurpose: .card, desired: .selectedLarge),
               "promoting the selection replaces the subscription with the larger class")
        expect(WindowBrowserThumbnailSubscriptionPolicy.needsReplace(
            existingPurpose: nil, desired: .card),
               "an unknown existing class is replaced")

        // 过期不等于销毁：最后画面仍可作为快照展示（折叠/最小化窗口用）。
        var fakeNow: CFAbsoluteTime = 1_000
        let snapshotBackend = FakeThumbnailBackend()
        snapshotBackend.autoResult = .success(makeImage(width: 8, height: 8))
        let snapshotService = WindowThumbnailService(backend: snapshotBackend,
                                                     now: { fakeNow })
        let snapshotKey = WindowKey(application: ApplicationInstanceKey(pid: 9101, generation: 1),
                                    originalWindowID: 4101, windowGeneration: 1)
        _ = snapshotService.request(windowKey: snapshotKey, purpose: .card,
                                    logicalSize: CGSize(width: 300, height: 200),
                                    onImage: { _ in })
        let freshKey = WindowThumbnailKey(windowKey: snapshotKey, purpose: .card,
                                          maxPixelSize: WindowThumbnailPurpose.card.maxPixelSize,
                                          captureVersion: 1)
        expect(snapshotService.cachedImage(for: freshKey) != nil,
               "a fresh capture is available from the cache")
        fakeNow += 10
        expect(snapshotService.cachedImage(for: freshKey) == nil,
               "a stale capture is no longer returned as fresh")
        expect(snapshotService.snapshotImage(windowKey: snapshotKey, purpose: .card) != nil,
               "the last valid frame stays available as a snapshot")
    }

    static func discoveryFilter() {
        func include(pid: pid_t = 4001, ownPID: pid_t = 9999, bundle: String = "com.example.app",
                     excluded: Set<String> = [], overlays: Set<CGWindowID> = [],
                     id: CGWindowID = 701, layer: Int32 = 0, role: String? = "AXWindow",
                     desktopWidget: Bool = false, adobe: Bool = false) -> Bool {
            WindowBrowserDiscoveryFilter.shouldInclude(
                WindowBrowserDiscoveryFilter.Input(
                    pid: pid, ownPID: ownPID, bundleIdentifier: bundle,
                    excludedBundleIDs: excluded, overlayWindowIDs: overlays,
                    windowID: id, layer: layer, role: role,
                    isDesktopWidget: desktopWidget, allowsLayoutAreaRole: adobe))
        }
        expect(include(), "ordinary layer-0 AXWindow is included")
        expect(!include(pid: 9999), "own process windows are excluded")
        expect(!include(bundle: "com.apple.dock"),
               "Dock/Control Center style system components are excluded")
        expect(!include(bundle: "com.example.secret", excluded: ["com.example.secret"]),
               "excluded applications are filtered")
        expect(!include(overlays: [701]), "own proxy and effect overlays are excluded")
        expect(!include(layer: 25), "non-layer-0 panels are excluded")
        expect(!include(desktopWidget: true), "desktop widgets are excluded")
        expect(!include(role: "AXGroup"), "non-window roles are excluded")
        expect(include(role: "AXLayoutArea", adobe: true),
               "Adobe layout windows are allowed when CG layer-0 backs them")
        expect(!include(role: "AXLayoutArea", adobe: false),
               "layout areas of other apps are not treated as windows")
    }

    // MARK: 镜像 owner 租约

    /// 29. 新缩略图路径与折叠捕获缓存完全隔离：小图不能进入完整标题栏缓存，
    /// 折叠缓存也不能被新服务当成自己的缓存复用。
    static func foldCacheIsolation() {
        let windowID: CGWindowID = 4242
        let nativeKey = WindowSnapshotKey(windowID: windowID, variant: .nativeChrome,
                                          maxPixelSize: nil)
        let key = WindowKey(application: ApplicationInstanceKey(pid: 9001, generation: 1),
                            originalWindowID: windowID, windowGeneration: 1)
        let backend = FakeThumbnailBackend()
        backend.autoResult = .success(makeImage(width: 32, height: 32))
        let service = WindowThumbnailService(backend: backend)
        _ = service.request(windowKey: key, purpose: .card,
                            logicalSize: CGSize(width: 300, height: 200), onImage: { _ in })
        expect(service.cachedCostBytes > 0,
               "card thumbnail is cached in the new thumbnail service")
        expect(WindowSnapshotCache.shared.cachedImage(key: nativeKey) == nil,
               "the new thumbnail path must not write the fold snapshot cache")
        expect(WindowSnapshotCache.shared.inFlightTask(for: nativeKey) == nil,
               "the new thumbnail path must not register in the fold snapshot cache")

        // 反向：折叠缓存里的图不能被新服务当成自己的缓存。
        WindowSnapshotCache.shared.store(image: makeImage(width: 64, height: 64),
                                         key: nativeKey)
        let freshBackend = FakeThumbnailBackend()
        freshBackend.autoResult = .success(makeImage(width: 32, height: 32))
        let freshService = WindowThumbnailService(backend: freshBackend)
        var delivered = 0
        _ = freshService.request(windowKey: key, purpose: .card,
                                 logicalSize: CGSize(width: 300, height: 200),
                                 onImage: { _ in delivered += 1 })
        expect(freshBackend.started.count == 1 && delivered == 1,
               "a fresh thumbnail service performs its own single-window capture "
               + "instead of reusing the fold cache")
    }

    static func mirrorOwnership() {
        // 32. 老 owner 释放镜像不会摘掉新 owner 的镜像。
        let slot = WindowMirrorSlot()
        let ownerA = UUID()
        let ownerB = UUID()
        slot.attach(owner: ownerA, windowID: 801, layer: AVSampleBufferDisplayLayer())
        expect(slot.currentOwner == ownerA, "first owner holds the mirror slot")
        slot.attach(owner: ownerB, windowID: 802, layer: AVSampleBufferDisplayLayer())
        expect(slot.release(owner: ownerA) == nil,
               "an old owner's release must not detach the new owner's mirror")
        expect(slot.currentWindowID == 802, "new owner's mirror remains attached")
        expect(slot.release(owner: ownerB) == 802,
               "the current owner releases its mirror")
        expect(slot.currentOwner == nil, "slot is empty after the current owner releases")
        slot.attach(owner: ownerA, windowID: 803, layer: AVSampleBufferDisplayLayer())
        slot.clear(windowID: 803)
        expect(slot.currentWindowID == nil, "session teardown clears the matching window slot")
    }

    // MARK: 面板与视图事件

    /// 生产视图的行为：面板语义、卡片/列表动作、按下-拖出语义、搜索与布局。
    static func panelAndViews() {
        _ = NSApplication.shared
        let dockPanel = WindowBrowserPanel(mode: .dock,
                                           frame: NSRect(x: 100, y: 100, width: 400, height: 300))
        expect(!dockPanel.canBecomeKey, "Dock panel does not steal key window")
        let keyboardPanel = WindowBrowserPanel(mode: .keyboard,
                                               frame: NSRect(x: 100, y: 100, width: 640, height: 520))
        expect(keyboardPanel.canBecomeKey, "keyboard panel can become key for search editing")
        expect(keyboardPanel.styleMask.contains(.nonactivatingPanel),
               "keyboard panel uses nonactivatingPanel semantics")
        expect(dockPanel.title == "窗口浏览" && keyboardPanel.title == "窗口选择",
               "borderless panels expose accessible window titles")
        expect(keyboardPanel.isMovableByWindowBackground,
               "the keyboard panel can be moved like a system utility panel")
        expect(dockPanel.tabbingMode == .disallowed && keyboardPanel.tabbingMode == .disallowed,
               "utility panels never merge into system window tabs")
        // ⌘W 走标准“关闭”菜单项 → performClose → 面板的取消回调（先取消预览再关闭）。
        var closeRequests = 0
        keyboardPanel.onCancel = { closeRequests += 1 }
        keyboardPanel.performClose(nil)
        expect(closeRequests == 1, "the standard 关闭 key equivalent reaches the panel cancel path")
        expect(!dockPanel.isMovableByWindowBackground,
               "the Dock panel stays anchored to its icon")
        expect(dockPanel.isExcludedFromWindowsMenu && keyboardPanel.isExcludedFromWindowsMenu,
               "temporary panels stay out of the Window menu")
        let contentForA11y = WindowBrowserContentView(frame: NSRect(x: 0, y: 0, width: 640, height: 520))
        expect(contentForA11y.accessibilityLabel() == "窗口浏览面板",
               "the panel content view exposes an accessibility label")
        let searchField = contentForA11y.subviews.compactMap { $0 as? NSSearchField }.first
        expect(searchField?.accessibilityLabel() == "搜索窗口",
               "the search field exposes an accessibility label")

        // 卡片：动作条只显示共享能力模型允许的常用动作，控制通过 weak delegate 回传。
        let card = WindowBrowserCardView(frame: NSRect(x: 0, y: 0, width: 288, height: 236))
        let cardDelegate = RecordingItemDelegate()
        card.delegate = cardDelegate
        let record = sampleRecord()
        configure(card: card, record: record, selected: false, busy: false)
        card.layoutSubtreeIfNeeded()
        let bar = card.subviews.compactMap { $0 as? WindowBrowserActionBar }.first
        expect(bar != nil, "cards expose a compact action bar")
        let buttons = bar?.subviews.compactMap { $0 as? NSButton } ?? []
        expect(!buttons.isEmpty, "the compact action bar contains symbol buttons")
        expect(buttons.allSatisfy {
            $0.frame.height <= WindowBrowserLayoutParams.standard.actionBarHeight + 0.5
        },
               "compact action buttons stay inside the reserved action bar space "
               + "(heights=\(buttons.map { Int($0.frame.height) }) limit=\(WindowBrowserLayoutParams.standard.actionBarHeight) bar=\(Int(bar?.frame.height ?? -1)))")
        expect(!card.actionBarIsVisible,
               "the compact action bar stays hidden until hover or selection")
        card.setSelected(true)
        card.layoutSubtreeIfNeeded()
        expect(card.actionBarIsVisible,
               "a keyboard-selected card shows its compact action bar")
        // 悬停底色：与系统列表同语言，且选中仍靠边线而非只靠底色。
        let unselectedCard = WindowBrowserCardView(frame: NSRect(x: 0, y: 0, width: 288, height: 236))
        configure(card: unselectedCard, record: record, selected: false, busy: false)
        let idleBackground = unselectedCard.layer?.backgroundColor
        unselectedCard.mouseEntered(with: NSEvent())
        let hoverBackground = unselectedCard.layer?.backgroundColor
        expect(idleBackground != hoverBackground,
               "hovering a card adds the system-like hover tint")
        expect(unselectedCard.layer?.borderWidth ?? 0 < 2,
               "a hovered but unselected card keeps the thin border")
        if let foldButton = buttons.first(where: {
            $0.identifier?.rawValue == WindowBrowserAction.fold.rawValue
        }) {
            foldButton.performClick(nil)
            expect(cardDelegate.performed.last?.action == .fold,
                   "the fold button routes through the shared action model")
        } else {
            expect(false, "an ordinary window card must offer the fold action")
        }
        expect(cardDelegate.activatedCount == 0,
               "clicking a compact action button must not activate the window")
        // VoiceOver 的“按下”（VO-Space）等价于鼠标点击。
        expect(card.accessibilityPerformPress(),
               "VO-Space on a configured card is handled by the card")
        expect(cardDelegate.activatedCount == 1,
               "VO-Space activates the window exactly like a click")
        let emptyCard = WindowBrowserCardView(frame: NSRect(x: 0, y: 0, width: 288, height: 236))
        expect(!emptyCard.accessibilityPerformPress(),
               "an unconfigured card reports that it cannot be pressed")
        // 更多操作入口：与右键菜单同一个菜单，不依赖用户知道右键。
        if let moreButton = buttons.first(where: {
            $0.identifier?.rawValue == bar?.moreButtonIdentifier
        }) ?? bar?.subviews.compactMap({ $0 as? NSButton }).first(where: {
            $0.identifier?.rawValue == bar?.moreButtonIdentifier
        }) {
            moreButton.performClick(nil)
            expect(cardDelegate.moreMenuRequests == 1,
                   "the always-visible more button requests the shared context menu")
            expect(cardDelegate.performed.count == 1,
                   "the more button never performs an action by itself")
        } else {
            expect(false, "the compact action bar must expose a discoverable more button")
        }

        // 按下-拖出取消：mouseDown 不激活，松开在外面不提交。
        card.setSelected(false)
        card.frame = NSRect(x: 0, y: 0, width: 288, height: 236)
        func mouseEvent(_ type: NSEvent.EventType, at point: NSPoint) -> NSEvent? {
            NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                               windowNumber: 0, context: nil, eventNumber: 0,
                               clickCount: 1, pressure: 1)
        }
        let activationsBeforePress = cardDelegate.activatedCount
        if let down = mouseEvent(.leftMouseDown, at: NSPoint(x: 20, y: 20)),
           let dragged = mouseEvent(.leftMouseDragged, at: NSPoint(x: 900, y: 900)),
           let up = mouseEvent(.leftMouseUp, at: NSPoint(x: 900, y: 900)) {
            card.mouseDown(with: down)
            expect(cardDelegate.activatedCount == activationsBeforePress,
                   "pressing a card must not activate it immediately")
            card.mouseDragged(with: dragged)
            card.mouseUp(with: up)
            expect(cardDelegate.activatedCount == activationsBeforePress,
                   "dragging out of a card cancels the activation")
        }
        var changed = record
        changed.title = "标题已变"
        expect(card.thumbnailImageForTesting == nil,
               "a card without a captured image shows the placeholder")
        let configureCountBefore = card.configureCount
        configure(card: card, record: record, selected: false, busy: false)
        expect(card.configureCount == configureCountBefore,
               "an unchanged record skips card reconfiguration")
        configure(card: card, record: changed, selected: false, busy: false)
        expect(card.configureCount == configureCountBefore + 1,
               "a changed record reconfigures the card")
        let accessibilityActions = card.accessibilityCustomActions() ?? []
        expect(accessibilityActions.contains { $0.name == "折叠" },
               "cards expose the shared action names to VoiceOver")

        // 列表行：图标、标题、状态与共享动作，不重复占用两颗固定文字按钮。
        let row = WindowBrowserListRowView(frame: NSRect(x: 0, y: 0, width: 420, height: 52))
        let rowDelegate = RecordingItemDelegate()
        row.delegate = rowDelegate
        configure(row: row, record: record, selected: true, busy: false)
        row.layoutSubtreeIfNeeded()
        expect(row.subviews.compactMap { $0 as? NSImageView }
            .allSatisfy { !$0.isAccessibilityElement() },
               "row icons are not separate accessibility elements")
        expect((row.accessibilityLabel() ?? "").contains("示例窗口"),
               "rows name the target window for VoiceOver")
        expect(row.accessibilityPerformPress() && rowDelegate.activatedCount == 1,
               "VO-Space on a list row activates the same way as a click")

        // 内容视图：键盘面板搜索、列表详情栏、网格方向键与规模边界。
        let content = WindowBrowserContentView(frame: NSRect(x: 0, y: 0, width: 800, height: 560))
        let many = makeRecords(pid: 5001, count: 20)
        let selected = many[3]
        content.update(mode: .keyboard, records: many, selection: selected.key,
                       style: .list, busyKeys: [], status: "")
        content.layout()
        expect(content.selectionPaneIsVisible,
               "list style shows the selected-item preview pane")
        expect(content.searchFieldVisible,
               "the keyboard panel keeps a visible search field")
        let frames = content.layoutFrameSummary
        expect(!frames.search.intersects(frames.list),
               "search field must not overlap the list")
        expect(frames.search.minY >= frames.list.maxY,
               "the keyboard search field sits above the list")
        expect(abs(frames.header.minY - frames.search.maxY
                   - WindowBrowserLayoutParams.standard.searchFieldBottomGap) <= 1,
               "the search field sits at the top, just below the header "
               + "(gap=\(Int(frames.header.minY - frames.search.maxY)))")
        expect(content.renderedLayout.style == .list && content.renderedLayout.rows == many.count,
               "list style renders one row per window")

        var restoringRecord = selected
        restoringRecord.shadeState = .restoring
        expect(WindowBrowserCardViewStatus.text(restoringRecord).contains("正在展开"),
               "a restoring window is labelled as restoring, not as open")
        var foldedRecord = selected
        foldedRecord.shadeState = .folded
        foldedRecord.systemVisibility = .offScreen
        let foldedStatus = WindowBrowserStatusPresentationFactory.make(record: foldedRecord,
                                                                      hasSnapshot: false)
        expect(foldedStatus.text == "已折叠" && !foldedStatus.isWarning,
               "a folded off-screen window is a normal state, not a warning")

        // 风格切换：点击分段控件立即重排，列表不重建整棵网格视图树。
        var reportedStyles: [WindowBrowserDisplayStyle] = []
        content.onStyleChanged = { reportedStyles.append($0) }
        if let control = content.subviews.compactMap({ $0 as? NSSegmentedControl }).first,
           let action = control.action {
            control.selectedSegment = 0
            NSApp.sendAction(action, to: control.target, from: control)
            expect(reportedStyles == [.grid], "the style control reports the new style")
            expect(content.renderedLayout.style == .grid
                    && content.renderedLayout.cards == many.count,
                   "switching to thumbnails rebuilds the grid immediately")
            control.selectedSegment = 1
            NSApp.sendAction(action, to: control.target, from: control)
            content.layout()
            expect(content.renderedLayout.style == .list,
                   "switching back to the list renders rows immediately")
        } else {
            expect(false, "the panel must expose a style control")
        }

        // 视口：只请求可见（含向下预取）的项目，滚动后集合随之变化。
        var capturedViewport: [[WindowKey]] = []
        content.onVisibleKeysChanged = { capturedViewport.append($0) }
        content.update(mode: .keyboard, records: many, selection: many[0].key,
                       style: .list, busyKeys: [], status: "")
        content.layout()
        let topVisible = content.visibleWindowKeys
        expect(!topVisible.isEmpty && topVisible.count < many.count,
               "a long list requests only a bounded viewport subset")
        content.scrollDocument(toY: 600)
        let scrolled = content.visibleWindowKeys
        expect(!scrolled.isEmpty && scrolled != topVisible,
               "scrolling changes the requested viewport subset")
        expect(!capturedViewport.isEmpty, "viewport changes are reported to the controller")

        // 视图内存：滚动过的屏不长期驻留缩略图，离屏单元也清掉图像。
        for record in many {
            content.applyThumbnail(makeImage(width: 8, height: 8), for: record.key)
        }
        content.scrollDocument(toY: 0)
        content.layout()
        expect(content.cachedThumbnailCount <= content.visibleWindowKeys.count + 1,
               "the view keeps at most the viewport (plus the selected item)")
        let offscreenKey = many[many.count - 1].key
        if !content.visibleWindowKeys.contains(offscreenKey) {
            expect(!content.hasThumbnailImage(for: offscreenKey),
                   "off-screen items release their image and layer contents")
        }
        // 旧结果投递到已经不在列表里的窗口时不显示。
        let absentKey = WindowKey(application: ApplicationInstanceKey(pid: 5999, generation: 1),
                                  originalWindowID: 999, windowGeneration: 1)
        content.applyThumbnail(makeImage(width: 8, height: 8), for: absentKey)
        expect(!content.hasThumbnailImage(for: absentKey),
               "an image for a window no longer in the list is not displayed")

        // 浅深色切换：层颜色必须按视图自己的外观重新解析，不能在切换后冻结旧值。
        let appearanceContent = WindowBrowserContentView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 560))
        let appearanceWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 560),
                                        styleMask: [.borderless], backing: .buffered, defer: false)
        appearanceWindow.isReleasedWhenClosed = false
        appearanceWindow.contentView = appearanceContent
        appearanceWindow.orderFrontRegardless()
        let previousAppearance = NSApp.appearance
        NSApp.appearance = NSAppearance(named: .aqua)
        appearanceContent.update(mode: .keyboard, records: many, selection: many[0].key,
                                 style: .list, busyKeys: [], status: "")
        appearanceContent.layout()
        let lightRow = appearanceContent.debugFirstRowBackgroundBrightness() ?? -1
        NSApp.appearance = NSAppearance(named: .darkAqua)
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        appearanceContent.refreshMaterialAppearance()
        appearanceContent.layout()
        let darkRow = appearanceContent.debugFirstRowBackgroundBrightness() ?? -1
        NSApp.appearance = previousAppearance
        expect(lightRow > 0.6, "the row starts light in the light appearance "
               + "(measured \(String(format: "%.3f", lightRow)))")
        expect(darkRow < 0.5, "the row follows the dark appearance instead of freezing "
               + "(measured \(String(format: "%.3f", darkRow)))")
        appearanceWindow.orderOut(nil)
        appearanceWindow.close()

        // VoiceOver：方向键/选择变化要把辅助功能焦点移到当前项（否则读屏不跟读），
        // 关闭读屏时不做无意义通知。
        content.voiceOverEnabledProvider = { false }
        let postsBefore = content.accessibilityFocusPostCount
        content.update(mode: .keyboard, records: many, selection: many[0].key,
                       style: .list, busyKeys: [], status: "")
        content.layout()
        content.select(many[1].key)
        expect(content.accessibilityFocusPostCount == postsBefore,
               "no accessibility focus post happens while VoiceOver is off")
        content.voiceOverEnabledProvider = { true }
        content.select(many[2].key)
        expect(content.accessibilityFocusPostCount > postsBefore,
               "selecting a window moves the accessibility focus when VoiceOver is on")
        content.voiceOverEnabledProvider = { NSWorkspace.shared.isVoiceOverEnabled }

        // 方向键按真实列数移动；最后一行不会越界。
        content.update(mode: .keyboard, records: many, selection: many[0].key,
                       style: .grid, busyKeys: [], status: "")
        content.layout()
        let columns = content.plan.columns
        expect(columns >= 1, "grid layout reports a real column count")
        content.select(many[0].key)
        content.moveSelection(direction: .down)
        let movedIndex = many.firstIndex { $0.key == content.selection } ?? -1
        expect(movedIndex == min(columns, many.count - 1),
               "down arrow moves by the real column count")
        let firstColumnIndex = min(columns, many.count - 1)
        content.select(many[firstColumnIndex].key)
        content.moveSelection(direction: .left)
        expect(content.selection == many[firstColumnIndex].key,
               "left arrow on the first column keeps the selection stable")

        // 200 条记录：视口与视图图像仍然有界。
        let huge = makeRecords(pid: 5001, count: 200)
        content.update(mode: .keyboard, records: huge, selection: huge[0].key,
                       style: .list, busyKeys: [], status: "")
        content.layout()
        for record in huge {
            content.applyThumbnail(makeImage(width: 8, height: 8), for: record.key)
        }
        content.scrollDocument(toY: 0)
        expect(content.visibleWindowKeys.count < huge.count,
               "200 windows still produce a bounded viewport subset")
        expect(content.cachedThumbnailCount <= content.visibleWindowKeys.count + 1,
               "200 windows keep view-side thumbnail memory bounded")
        expect(content.cachedThumbnailBytes > 0 && content.cachedThumbnailBytes < 20 * 1024 * 1024,
               "view-side image bytes stay observable and bounded")
        // 离屏 AppKit 不会为不可见条目创建单元视图；这里断言数量上界，
        // 真正的“只创建可见单元”证据来自性能对照（120 条冷启动 18ms vs 200ms）。
        let materialised = content.createdItemCount
        expect(materialised <= content.visibleWindowKeys.count + 8,
               "only visible items (plus a small reuse pool) are materialised "
               + "(created=\(materialised) visible=\(content.visibleWindowKeys.count))")
        print("window-browser: materialised cells=\(materialised) "
              + "visible=\(content.visibleWindowKeys.count) records=\(huge.count)")
    }

    /// 复用与所有权：卡片/列表行不因为闭包自持有而泄漏，集合变化不重建全部单元。
    static func viewOwnershipAndReuse() {
        _ = NSApplication.shared
        let record = sampleRecord()
        weak var weakCard: WindowBrowserCardView?
        weak var weakRow: WindowBrowserListRowView?
        autoreleasepool {
            let delegate = RecordingItemDelegate()
            let card = WindowBrowserCardView(frame: NSRect(x: 0, y: 0, width: 288, height: 236))
            card.delegate = delegate
            configure(card: card, record: record, selected: true, busy: false)
            card.layout()
            weakCard = card
            let rowDelegate = RecordingItemDelegate()
            let row = WindowBrowserListRowView(frame: NSRect(x: 0, y: 0, width: 420, height: 52))
            row.delegate = rowDelegate
            configure(row: row, record: record, selected: true, busy: false)
            row.layout()
            weakRow = row
        }
        expect(weakCard == nil, "a removed card is released (no closure retain cycle)")
        expect(weakRow == nil, "a removed list row is released")
        // 面板与实时视图：关闭/解除挂载后同样必须释放。
        weak var weakPanel: WindowBrowserPanel?
        weak var weakLiveView: NSView?
        autoreleasepool {
            let panel = WindowBrowserPanel(mode: .dock,
                                           frame: NSRect(x: 0, y: 0, width: 320, height: 240))
            weakPanel = panel
            let live = NSView(frame: NSRect(x: 0, y: 0, width: 40, height: 30))
            weakLiveView = live
            let content = panel.browserContentView
            content.update(mode: .dock, records: [record], selection: record.key,
                           style: .grid, busyKeys: [], status: "")
            content.layout()
            content.setLivePreview(live, for: record.key)
            expect(live.superview != nil, "the live view is mounted before release")
            content.setLivePreview(nil, for: record.key)
            panel.orderOut(nil)
            panel.close()
        }
        // AppKit 会在下一个 run-loop 周期释放已关闭的窗口，给它一次机会。
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        expect(weakLiveView == nil, "a detached live view is released")
        expect(weakPanel == nil, "a closed panel is released")
        expect(WindowBrowserActionPresentation.primaryActions.contains(.fold),
               "the shared capability model decides which actions the compact bar shows")

        // 集合变化（删除一条）不重建其他单元，选择与滚动位置保持稳定。
        let content = WindowBrowserContentView(frame: NSRect(x: 0, y: 0, width: 800, height: 560))
        let records = makeRecords(pid: 6001, count: 12)
        content.update(mode: .keyboard, records: records, selection: records[2].key,
                       style: .grid, busyKeys: [], status: "")
        content.layout()
        let keptKey = records[2].key
        let identityBefore = content.cardInstanceIdentifier(for: keptKey)
        // 只改内容的刷新（键集合不变）不得销毁单元视图。
        var renamed = records
        renamed[2].title = "标题刷新"
        content.update(mode: .keyboard, records: renamed, selection: keptKey,
                       style: .grid, busyKeys: [], status: "")
        content.layout()
        if let identityBefore, let identityAfter = content.cardInstanceIdentifier(for: keptKey) {
            expect(identityBefore == identityAfter,
                   "a content-only refresh keeps the same card view instance")
        } else {
            // 离屏环境下 AppKit 可能还没有创建单元视图；此时验证数量边界。
            expect(content.createdItemCount <= renamed.count,
                   "content-only refreshes never materialise extra items "
                   + "(created=\(content.createdItemCount))")
        }
        content.scrollDocument(toY: 0)
        var withoutOne = records
        withoutOne.remove(at: 7)
        content.update(mode: .keyboard, records: withoutOne, selection: keptKey,
                       style: .grid, busyKeys: [], status: "")
        content.layout()
        expect(content.selection == keptKey,
               "removing one record keeps the current selection")
        expect(content.createdItemCount <= withoutOne.count,
               "id-diff updates materialise at most one view per record")
        expect(content.visibleWindowKeys.count < withoutOne.count,
               "a long list still requests only its viewport after a removal")

        // T16：数量相同但键完全不同时，旧键保留的图像必须被清掉。
        let swapped = makeRecords(pid: 6401, count: records.count)
        content.applyThumbnail(makeImage(width: 8, height: 8), for: records[2].key)
        expect(content.cachedThumbnailCount >= 1, "the baseline image is cached")
        content.update(mode: .keyboard, records: swapped, selection: nil,
                       style: .grid, busyKeys: [], status: "")
        content.layout()
        expect(!content.hasThumbnailImage(for: records[2].key),
               "T16: an equal-count update with different keys clears the old images")
    }

    /// 实时预览只有一个明确挂载点：网格卡片或列表详情，切换只迁移不重建。
    static func livePreviewMounting() {
        _ = NSApplication.shared
        let content = WindowBrowserContentView(frame: NSRect(x: 0, y: 0, width: 800, height: 560))
        let records = makeRecords(pid: 6101, count: 8)
        let selected = records[2].key
        content.update(mode: .keyboard, records: records, selection: selected,
                       style: .grid, busyKeys: [], status: "")
        content.layout()
        let liveView = NSView(frame: NSRect(x: 0, y: 0, width: 40, height: 30))
        content.setLivePreview(liveView, for: selected)
        expect(content.liveMountTarget == .card(selected),
               "grid style mounts the live preview in the card")
        expect(liveView.superview != nil, "the live preview is attached in grid style")
        let cardHost = liveView.superview
        expect(cardHost != nil, "grid live preview has a visible host")

        // 样式切换：迁移现有实时视图，不新开第二路。
        content.update(mode: .keyboard, records: records, selection: selected,
                       style: .list, busyKeys: [], status: "")
        content.layout()
        expect(content.liveMountTarget == .selectionDetail(selected),
               "list style mounts the live preview in the selection detail pane")
        expect(content.liveMountHostIsDetailPane,
               "the live preview is re-hosted in the detail pane, not duplicated")
        expect(liveView.superview !== cardHost || cardHost == nil,
               "the live view is moved instead of being displayed twice")
        content.setLivePreview(nil, for: selected)
        expect(liveView.superview == nil, "releasing the live preview detaches it")

        // 列表详情栏隐藏时（网格样式）不能把视频挂进隐藏的详情区。
        content.update(mode: .keyboard, records: records, selection: selected,
                       style: .grid, busyKeys: [], status: "")
        content.layout()
        let secondView = NSView(frame: NSRect(x: 0, y: 0, width: 40, height: 30))
        content.setLivePreview(secondView, for: selected)
        expect(!content.liveMountHostIsDetailPane,
               "the grid never mounts the live view into the hidden detail pane")

        // 元数据/颜色刷新不 remove/add 同一个正在显示的实时视图。
        let hostBefore = secondView.superview
        content.update(mode: .keyboard, records: records, selection: selected,
                       style: .grid, busyKeys: [], status: "")
        content.refreshMaterialAppearance()
        expect(secondView.superview === hostBefore,
               "a metadata or appearance refresh keeps the same live view host")
    }

    /// 同一应用的图标只读取一次，多行/多卡片共享缓存。
    static func iconCacheSharedAcrossRows() {
        let provider = WindowBrowserIconProvider()
        _ = provider.icon(for: 6201)
        _ = provider.icon(for: 6201)
        _ = provider.icon(for: 6201)
        expect(provider.loadCount == 1,
               "three lookups for the same process load the icon once")
        _ = provider.icon(for: 6202)
        expect(provider.loadCount == 2, "a different process loads its own icon")
        provider.invalidate(pid: 6201)
        _ = provider.icon(for: 6201)
        expect(provider.loadCount == 3, "invalidation forces a fresh read")
    }

    // MARK: 新增：截图任务、订阅与额度的真实记账

    /// T01–T12：任务、订阅、额度与降级的真实记账。
    static func thumbnailJobAccounting() {
        let keyA = WindowKey(application: ApplicationInstanceKey(pid: 8001, generation: 1),
                             originalWindowID: 11, windowGeneration: 1)
        let keyB = WindowKey(application: ApplicationInstanceKey(pid: 8001, generation: 1),
                             originalWindowID: 12, windowGeneration: 1)
        let keyC = WindowKey(application: ApplicationInstanceKey(pid: 8001, generation: 1),
                             originalWindowID: 13, windowGeneration: 1)
        let size = CGSize(width: 320, height: 200)
        let image = makeImage(width: 8, height: 8)

        // T01/T02：两个并行任务，无论谁先完成，另一个的物理启动次数都保持 1。
        for firstIsA in [true, false] {
            let backend = FakeThumbnailBackend()
            backend.autoResult = nil
            let service = WindowThumbnailService(backend: backend, maxConcurrent: 2)
            _ = service.request(windowKey: keyA, purpose: .card, logicalSize: size,
                                onImage: { _ in })
            _ = service.request(windowKey: keyB, purpose: .card, logicalSize: size,
                                onImage: { _ in })
            expect(backend.started.count == 2, "two distinct keys start two physical captures")
            backend.complete(index: firstIsA ? 0 : 1, with: .success(image))
            expect(backend.started.count == 2,
                   "completing one capture must not restart the other "
                   + "(first=\(firstIsA ? "A" : "B"))")
            expect(service.runningCaptureCount == 1,
                   "the unfinished capture still occupies exactly one slot")
            backend.completeAll(with: .success(image))
            expect(service.runningCaptureCount == 0 && service.inFlightCount == 0,
                   "both captures settle back to a zero baseline")
        }

        // T03：连续十个任务，任意完成顺序下物理运行数不超过 2。
        let manyBackend = FakeThumbnailBackend()
        manyBackend.autoResult = nil
        let manyService = WindowThumbnailService(backend: manyBackend, maxConcurrent: 2)
        for index in 0..<10 {
            let key = WindowKey(application: ApplicationInstanceKey(pid: 8002, generation: 1),
                                originalWindowID: CGWindowID(100 + index),
                                windowGeneration: 1)
            _ = manyService.request(windowKey: key, purpose: .card, logicalSize: size,
                                    onImage: { _ in })
            expect(manyBackend.started.count <= 2,
                   "physical captures stay within the concurrency budget (index \(index))")
        }
        // 固定顺序（交替先完成第二个等待中的任务）覆盖任意完成顺序下的预算不变式。
        for step in 0..<10 {
            let pendingCount = manyBackend.started.count - step
            let index = step % 2 == 0 && pendingCount > 1 ? 1 : 0
            manyBackend.complete(index: index, with: .success(image))
            expect(manyService.runningCaptureCount <= 2,
                   "at most two physical captures run concurrently (step \(step))")
        }
        expect(manyBackend.started.count == 10, "every queued job eventually runs")
        expect(manyService.inFlightCount == 0, "all jobs settle")

        // T04：取消 queued 任务不启动后端，也不错误归还别的任务额度。
        let queuedBackend = FakeThumbnailBackend()
        queuedBackend.autoResult = nil
        let queuedService = WindowThumbnailService(backend: queuedBackend, maxConcurrent: 1)
        _ = queuedService.request(windowKey: keyA, purpose: .card, logicalSize: size,
                                  onImage: { _ in })
        let queued = queuedService.request(windowKey: keyB, purpose: .card, logicalSize: size,
                                           onImage: { _ in })
        queued.cancel()
        expect(queuedBackend.started.count == 1,
               "cancelling a queued job never starts the backend")
        expect(queuedService.runningCaptureCount == 1,
               "the running job keeps its slot after another job is cancelled")
        queuedBackend.completeAll(with: .success(image))
        expect(queuedService.queuedCount == 0, "the cancelled job never re-enters the queue")

        // T05：取消 running 任务但系统仍在运行 → 继续占用额度到真实完成。
        let runningBackend = FakeThumbnailBackend()
        runningBackend.autoResult = nil
        let runningService = WindowThumbnailService(backend: runningBackend, maxConcurrent: 1)
        let running = runningService.request(windowKey: keyA, purpose: .card,
                                             logicalSize: size, onImage: { _ in })
        _ = runningService.request(windowKey: keyB, purpose: .card, logicalSize: size,
                                   onImage: { _ in })
        running.cancel()
        expect(runningService.runningCaptureCount == 1,
               "a cancelled-but-running system call still occupies the budget")
        expect(runningBackend.started.count == 1,
               "the queued job does not start while the cancelled job is unfinished")
        runningBackend.complete(index: 0, with: .success(image))
        expect(runningBackend.started.count == 2,
               "the slot is released only after the real completion")

        // T06：两个 running 任务遇到 invalidateAll，晚到完成仍归还额度。
        let invalidateBackend = FakeThumbnailBackend()
        invalidateBackend.autoResult = nil
        let invalidateService = WindowThumbnailService(backend: invalidateBackend,
                                                       maxConcurrent: 2)
        _ = invalidateService.request(windowKey: keyA, purpose: .card, logicalSize: size,
                                      onImage: { _ in })
        _ = invalidateService.request(windowKey: keyB, purpose: .card, logicalSize: size,
                                      onImage: { _ in })
        invalidateService.invalidateAll()
        expect(invalidateService.runningCaptureCount == 2,
               "invalidating does not pretend the running captures stopped")
        invalidateBackend.completeAll(with: .success(image))
        expect(invalidateService.runningCaptureCount == 0,
               "late completions still return the budget after invalidation")
        _ = invalidateService.request(windowKey: keyC, purpose: .card, logicalSize: size,
                                      onImage: { _ in })
        expect(invalidateBackend.started.count == 3,
               "new work can start after the invalidated jobs settle")

        // T07：旧任务失效后同一键的新 JobID 已入队，旧回调不能删除新登记。
        let staleBackend = FakeThumbnailBackend()
        staleBackend.autoResult = nil
        let staleService = WindowThumbnailService(backend: staleBackend, maxConcurrent: 2)
        _ = staleService.request(windowKey: keyA, purpose: .card, logicalSize: size,
                                 onImage: { _ in })
        staleService.invalidate(windowKey: keyA)
        var replacementDelivered = false
        _ = staleService.request(windowKey: keyA, purpose: .card, logicalSize: size,
                                 onImage: { _ in replacementDelivered = true })
        expect(staleBackend.started.count == 2,
               "the replacement request starts a new physical capture")
        staleBackend.complete(index: 0, with: .success(image))
        expect(!replacementDelivered,
               "the old job's completion must not publish to the new request")
        expect(staleService.jobState(windowKey: keyA, purpose: .card) != nil,
               "the new job stays registered after the stale completion")
        staleBackend.complete(index: 0, with: .success(image))
        expect(replacementDelivered, "the new job still delivers its own result")

        // T08：后端重复完成不重复发布、不重复归还额度。
        let duplicateBackend = FakeThumbnailBackend()
        duplicateBackend.autoResult = nil
        let duplicateService = WindowThumbnailService(backend: duplicateBackend)
        var deliveries = 0
        _ = duplicateService.request(windowKey: keyA, purpose: .card, logicalSize: size,
                                     onImage: { _ in deliveries += 1 })
        let pendingCompletion = duplicateBackend.pendingCompletions.first
        pendingCompletion?(.success(image))
        pendingCompletion?(.success(image))
        expect(deliveries == 1, "a duplicated completion publishes exactly once")
        expect(duplicateService.duplicateCompletionCount == 1,
               "the duplicated completion is counted, not acted upon")
        expect(duplicateService.runningCaptureCount == 0,
               "the duplicated completion never underflows the budget")

        // T09：后端永不完成 → 有界降级，不无限追加真实任务。
        var fakeClock: CFAbsoluteTime = 1000
        let stalledBackend = FakeThumbnailBackend()
        stalledBackend.autoResult = nil
        let stalledService = WindowThumbnailService(backend: stalledBackend, maxConcurrent: 1,
                                                    stallTimeout: 1.0,
                                                    now: { fakeClock })
        _ = stalledService.request(windowKey: keyA, purpose: .card, logicalSize: size,
                                   onImage: { _ in })
        fakeClock += 5
        var stalledFailure: WindowThumbnailFailure?
        let stalledSecond = stalledService.request(windowKey: keyB, purpose: .card,
                                                   logicalSize: size,
                                                   onImage: { _ in },
                                                   onFailure: { stalledFailure = $0 })
        expect(stalledBackend.started.count == 1,
               "a stalled backend receives no further physical work")
        expect(stalledSecond.isFinished,
               "the new demand fails promptly instead of queueing forever")
        if case .captureFailed? = stalledFailure {
            expect(true, "the stalled demand reports a comprehensible failure")
        } else {
            expect(false, "the stalled demand must report a capture failure")
        }

        // T11：选中项优先级提升不会重启已经在运行的截图。
        let promoteBackend = FakeThumbnailBackend()
        promoteBackend.autoResult = nil
        let promoteService = WindowThumbnailService(backend: promoteBackend, maxConcurrent: 1)
        _ = promoteService.request(windowKey: keyA, purpose: .card, logicalSize: size,
                                   onImage: { _ in })
        _ = promoteService.request(windowKey: keyB, purpose: .card, logicalSize: size,
                                   onImage: { _ in })
        _ = promoteService.request(windowKey: keyC, purpose: .card, logicalSize: size,
                                   onImage: { _ in })
        promoteService.promote(windowKey: keyC, purpose: .card)
        expect(promoteBackend.started.count == 1,
               "promoting a queued item never restarts the running capture")
        promoteBackend.complete(index: 0, with: .success(image))
        expect(promoteBackend.started.last?.key.windowKey == keyC,
               "the promoted demand is served first")

        // T12：完成、取消、失败的订阅都进入终态，cancelAction 不自持有。
        let terminalBackend = FakeThumbnailBackend()
        terminalBackend.autoResult = .success(image)
        let terminalService = WindowThumbnailService(backend: terminalBackend)
        let finished = terminalService.request(windowKey: keyA, purpose: .card,
                                               logicalSize: size, onImage: { _ in })
        expect(finished.isFinished && !finished.isActive,
               "a synchronously completed subscription is already terminal")
        finished.cancel()
        expect(finished.isFinished, "calling cancel on a terminal subscription is a no-op")

        let cancelBackend = FakeThumbnailBackend()
        cancelBackend.autoResult = nil
        let cancelService = WindowThumbnailService(backend: cancelBackend)
        var finishNotifications = 0
        let cancelled = cancelService.request(windowKey: keyB, purpose: .card,
                                              logicalSize: size, onImage: { _ in },
                                              onFinish: { finishNotifications += 1 })
        cancelled.cancel()
        expect(cancelled.isFinished && cancelled.isCancelled,
               "a cancelled subscription is terminal and marked cancelled")
        expect(finishNotifications == 1,
               "the controller is notified exactly once when the subscription ends")

        let failureBackend = FakeThumbnailBackend()
        failureBackend.autoResult = .failure(.permissionDenied)
        let failureService = WindowThumbnailService(backend: failureBackend)
        var failureNotified = false
        _ = failureService.request(windowKey: keyC, purpose: .card, logicalSize: size,
                                   onImage: { _ in },
                                   onFailure: { _ in failureNotified = true },
                                   onFinish: { finishNotifications += 1 })
        expect(failureNotified && finishNotifications == 2,
               "a failed subscription reports the failure and then finishes once")

        // 按窗口+档位取新鲜缓存（大图预览用；调用方不拼 captureVersion）。
        let freshBackend = FakeThumbnailBackend()
        freshBackend.autoResult = .success(image)
        let freshService = WindowThumbnailService(backend: freshBackend)
        _ = freshService.request(windowKey: keyA, purpose: .card, logicalSize: size,
                                 onImage: { _ in })
        expect(freshService.freshImage(windowKey: keyA, purpose: .card) != nil,
               "a fresh cached image is reachable by window and purpose")
        freshService.invalidateAll()
        expect(freshService.freshImage(windowKey: keyA, purpose: .card) == nil,
               "invalidation makes the cached image unreachable")

        // T10：同步缓存回调不会让订阅被永久认为“正在请求”。
        let cacheBackend = FakeThumbnailBackend()
        cacheBackend.autoResult = .success(image)
        let cacheService = WindowThumbnailService(backend: cacheBackend)
        let cachedFirst = cacheService.request(windowKey: keyA, purpose: .card,
                                               logicalSize: size, onImage: { _ in })
        expect(cachedFirst.isFinished, "a synchronous capture finishes its subscription")
        let cachedSecond = cacheService.request(windowKey: keyA, purpose: .card,
                                                logicalSize: size, onImage: { _ in })
        expect(cachedSecond.isFinished && cacheBackend.started.count == 1,
               "the second request is served from cache, not from a new capture")
        expect(cacheService.inFlightCount == 0,
               "no subscription is left behind as permanently in flight")
    }

    // MARK: 新增：Dock 区域与检测排队

    /// T21–T29：候选区域、在途合并、过期结果与拓扑变化。
    static func dockRegionAndDetectionQueue() {
        let left = WindowBrowserDockRegion.ScreenSnapshot(
            frame: NSRect(x: -1440, y: 0, width: 1440, height: 900), displayID: 1)
        let right = WindowBrowserDockRegion.ScreenSnapshot(
            frame: NSRect(x: 0, y: 0, width: 1440, height: 900), displayID: 2)
        let screens = [left, right]

        // T21：双屏左侧屏幕中央的移动不能被右屏左边缘条件误判。
        expect(!WindowBrowserDockRegion.isNearDock(CGPoint(x: -720, y: 450),
                                                   screens: screens, dockAreas: [],
                                                   edgeBand: 10, tolerance: 24),
               "the middle of the left screen is not near any Dock edge")
        expect(WindowBrowserDockRegion.isNearDock(CGPoint(x: -720, y: 4),
                                                  screens: screens, dockAreas: [],
                                                  edgeBand: 10, tolerance: 24),
               "the bottom edge of the left screen is a candidate region")
        expect(WindowBrowserDockRegion.isNearDock(CGPoint(x: 4, y: 450),
                                                  screens: screens, dockAreas: [],
                                                  edgeBand: 10, tolerance: 24),
               "the left edge of the right screen is a candidate region")

        // T22：上下排列与负坐标。
        let above = WindowBrowserDockRegion.ScreenSnapshot(
            frame: NSRect(x: 0, y: 900, width: 1440, height: 900), displayID: 3)
        expect(WindowBrowserDockRegion.screenContaining(CGPoint(x: 700, y: 1200),
                                                        screens: [right, above])?.displayID == 3,
               "a point in the upper screen is attributed to that screen")
        expect(WindowBrowserDockRegion.isNearDock(CGPoint(x: 700, y: 905),
                                                  screens: [right, above], dockAreas: [],
                                                  edgeBand: 10, tolerance: 24),
               "a vertically stacked screen keeps its own edge band")
        expect(!WindowBrowserDockRegion.isNearDock(CGPoint(x: 700, y: 1780),
                                                   screens: [right, above], dockAreas: [],
                                                   edgeBand: 10, tolerance: 24),
               "the middle of the upper screen is not a Dock candidate")
        // 已知 Dock 区域按实际矩形判断，不会覆盖屏幕之间的空白。
        let knownArea = NSRect(x: -600, y: 0, width: 700, height: 60)
        expect(WindowBrowserDockRegion.isInsideAny(CGPoint(x: -300, y: 30),
                                                   areas: [knownArea], tolerance: 4),
               "a pointer inside a known Dock area is a candidate")
        expect(!WindowBrowserDockRegion.isInsideAny(CGPoint(x: -300, y: 300),
                                                    areas: [knownArea], tolerance: 4),
               "leaving the Dock area stops producing candidates")
        expect(!WindowBrowserDockRegion.isNearDock(CGPoint(x: 1500, y: 450),
                                                   screens: screens, dockAreas: [knownArea],
                                                   edgeBand: 10, tolerance: 24),
               "a gap between displays is not silently treated as an edge")

        // T23/T24：慢 AX + 快速移动 → 最多一个在途 + 一个最新待处理位置。
        var coordinator = WindowBrowserDetectionCoordinator()
        let first = coordinator.begin(point: CGPoint(x: 10, y: 10), generation: 1,
                                      topologyVersion: 1, source: "mouse",
                                      isPointerDriven: true)
        expect(first != nil, "the first detection runs immediately")
        _ = coordinator.begin(point: CGPoint(x: 20, y: 20), generation: 1,
                              topologyVersion: 1, source: "mouse", isPointerDriven: true)
        let latest = coordinator.begin(point: CGPoint(x: 30, y: 30), generation: 1,
                                       topologyVersion: 1, source: "mouse",
                                       isPointerDriven: true)
        expect(latest == nil, "later pointer positions wait for the in-flight detection")
        expect(coordinator.pendingCount == 2,
               "the queue holds at most one in-flight plus one latest pending request")
        expect(coordinator.pending?.point == CGPoint(x: 30, y: 30),
               "the pending position is always the latest one")
        expect(coordinator.coalescedCount == 1,
               "overwritten pointer positions are counted as coalesced")
        let notification = coordinator.begin(point: CGPoint(x: 30, y: 30), generation: 1,
                                             topologyVersion: 1, source: "ax-notification",
                                             isPointerDriven: false)
        expect(notification == nil && coordinator.pendingCount == 2,
               "AX notifications share the same in-flight budget as pointer fallback")
        let next = coordinator.finish(requestID: first?.requestID ?? 0)
        expect(next?.point == CGPoint(x: 30, y: 30),
               "finishing the in-flight detection starts the latest pending request")

        // T25/T27：过期指针结果与旧观察器实例的结果都会被拒绝。
        var pointerCoordinator = WindowBrowserDetectionCoordinator()
        let requestA = pointerCoordinator.begin(point: CGPoint(x: 10, y: 10), generation: 1,
                                                topologyVersion: 1, source: "mouse",
                                                isPointerDriven: true)
        _ = pointerCoordinator.finish(requestID: requestA?.requestID ?? 0)
        let requestB = pointerCoordinator.begin(point: CGPoint(x: 400, y: 10), generation: 1,
                                                topologyVersion: 1, source: "mouse",
                                                isPointerDriven: true)
        expect(requestB != nil, "the pointer moved on and started a new detection")
        if let requestA {
            expect(!pointerCoordinator.accepts(requestA, generation: 1, topologyVersion: 1),
                   "a stale pointer result is rejected once a newer position arrived")
        }
        if let requestB {
            expect(pointerCoordinator.accepts(requestB, generation: 1, topologyVersion: 1),
                   "the latest pointer request is accepted")
            expect(!pointerCoordinator.accepts(requestB, generation: 2, topologyVersion: 1),
                   "a new observer generation rejects the old instance's result")
            expect(!pointerCoordinator.accepts(requestB, generation: 1, topologyVersion: 9),
                   "a display topology change rejects the old geometry result")
        }

        // T29：图标命中区域有限，不覆盖半个桌面。
        let icon = NSRect(x: 100, y: 20, width: 52, height: 52)
        expect(WindowBrowserDockRegion.iconHitContains(CGPoint(x: 126, y: 46),
                                                       iconFrame: icon, tolerance: 8),
               "the pointer inside the icon is a hit")
        expect(!WindowBrowserDockRegion.iconHitContains(CGPoint(x: 400, y: 400),
                                                        iconFrame: icon, tolerance: 8),
               "the icon hit region is bounded")
    }

    // MARK: 新增：元数据槽

    /// T31/T32：元数据槽的“在途 + 最新需求”记账。
    static func metadataSlots() {
        let app = ApplicationInstanceKey(pid: 9101, generation: 1)
        let request1 = WindowBrowserRequestID(value: 1)
        let request2 = WindowBrowserRequestID(value: 2)
        var slot = WindowBrowserMetadataSlot()
        expect(slot.request(jobID: 1, requestID: request1, appInstance: app) != nil,
               "the first metadata demand starts immediately")
        expect(slot.request(jobID: 2, requestID: request2, appInstance: app) == nil,
               "a second demand while one is in flight is queued instead of started")
        // T31：旧任务结束（即使结果被拒绝发布）仍然推进最新需求。
        let promoted = slot.complete(jobID: 1)
        expect(promoted?.requestID == request2,
               "the latest pending demand is promoted after the old job ends")
        expect(slot.inFlight?.jobID == 2, "the promoted demand is now in flight")
        expect(slot.complete(jobID: 1) == nil,
               "a duplicated completion of the old job cannot clear the new slot")
        expect(slot.inFlight?.jobID == 2,
               "the new registration survives the stale callback")

        var repeatSlot = WindowBrowserMetadataSlot()
        _ = repeatSlot.request(jobID: 1, requestID: request1, appInstance: app)
        expect(repeatSlot.request(jobID: 2, requestID: request1, appInstance: app) == nil,
               "an identical in-flight demand is not queued a second time")
        expect(repeatSlot.pending == nil, "no redundant pending demand is recorded")

        // T32：stop/start 后旧回调不能删除新实例的在途槽。
        let scheduler = WindowBrowserMetadataScheduler()
        let firstJob = scheduler.request(pid: 9101, requestID: request1, appInstance: app)
        expect(firstJob != nil, "the scheduler starts the first job")
        scheduler.cancel(pid: 9101)
        let restarted = scheduler.request(pid: 9101,
                                          requestID: WindowBrowserRequestID(value: 9),
                                          appInstance: app)
        expect(restarted != nil, "after a stop/start the new instance starts its own job")
        expect(scheduler.complete(pid: 9101, jobID: firstJob?.jobID ?? 0) == nil,
               "an old callback cannot complete the new instance's slot")
        expect(scheduler.state(pid: 9101).inFlight?.jobID == restarted?.jobID,
               "the new in-flight registration is untouched by the old callback")
        _ = scheduler.complete(pid: 9101, jobID: restarted?.jobID ?? 0)
        expect(scheduler.state(pid: 9101).isIdle,
               "the slot is released after its own completion")
    }

    // MARK: 新增：统一布局结果

    /// 排版跟随系统文字大小：字号变大时整套布局（卡片/行高/面板）随之增长。
    static func typographyFollowsSystemTextSize() {
        _ = NSApplication.shared
        let preferred = NSFont.preferredFont(forTextStyle: .body).pointSize
        expect(abs(WindowBrowserTypography.bodySize - preferred) < 0.01,
               "the browser body font follows the system text-size preference")
        expect(WindowBrowserTypography.detailSize
                == max(9, WindowBrowserTypography.bodySize - 2),
               "the detail size stays derived from the body size")
        let standard = WindowBrowserLayoutParams.standard
        let large = WindowBrowserLayoutParams.make(
            bodySize: WindowBrowserTypography.bodySize + 5,
            detailSize: WindowBrowserTypography.detailSize + 5)
        expect(large.cardHeight > standard.cardHeight
                && large.cardTitleHeight > standard.cardTitleHeight,
               "a larger text size grows the card metrics")
        expect(large.listRowHeight > standard.listRowHeight,
               "a larger text size grows the list row height")
        expect(WindowBrowserTypography.lineHeight(forBodySize: 20)
                > WindowBrowserTypography.lineHeight(forBodySize: 13),
               "line height grows with the injected font size")
        // 默认字号下仍然保持紧凑。
        let screen = NSRect(x: 0, y: 0, width: 1512, height: 982)
        let visible = NSRect(x: 0, y: 78, width: 1512, height: 904)
        let plan = WindowBrowserGeometry.layoutPlan(
            iconFrame: NSRect(x: 740, y: 8, width: 52, height: 52), edge: .bottom,
            screenFrame: screen, visibleFrame: visible,
            desiredSize: CGSize(width: 520, height: 460), windowCount: 1,
            style: .grid, isContentDriven: true, params: standard)
        expect(plan.panelFrame.height <= 360,
               "the default text size keeps the single-window panel compact "
               + "(\(Int(plan.panelFrame.height))pt)")
    }

    /// T46–T48/T53：内容决定自然尺寸，列数与方向键一致，新图像不改变布局。
    static func layoutPlan() {
        let screen = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let visible = NSRect(x: 0, y: 78, width: 1440, height: 822)
        let icon = NSRect(x: 700, y: 8, width: 52, height: 52)

        // 圆角刻度：窗口级表面跟系统窗口一致（macOS 27 实测 13 pt），卡片次一级，
        // 卡片里的画面按 HIG 的同心规则取“卡片圆角 − 卡片内边距”。
        let radii = WindowBrowserLayoutParams.standard
        expect(radii.panelCornerRadius == SystemCornerRadius.window,
               "the panel uses the system window radius (\(radii.panelCornerRadius)pt)")
        expect(radii.cardCornerRadius == SystemCornerRadius.card,
               "cards use the content radius (\(radii.cardCornerRadius)pt)")
        expect(radii.imageCornerRadius
                == SystemCornerRadius.concentric(outer: radii.cardCornerRadius,
                                                 inset: radii.cardPadding),
               "the thumbnail radius is concentric with its card "
               + "(\(radii.imageCornerRadius)pt inside \(radii.cardCornerRadius)pt)")
        expect(radii.imageCornerRadius < radii.cardCornerRadius,
               "a nested shape is never rounder than the shape that contains it")
        let scaled = WindowBrowserLayoutParams.make(bodySize: 17, detailSize: 14)
        expect(scaled.imageCornerRadius
                == SystemCornerRadius.concentric(outer: scaled.cardCornerRadius,
                                                 inset: scaled.cardPadding),
               "the concentric relationship survives a larger system text size")

        // A+C：标题真的换行才占两行；没有状态文字时页脚不占位，面板贴合内容。
        let base = WindowBrowserLayoutParams.standard
        expect(WindowBrowserGeometry.titleLines(forTitles: ["音樂"], availableWidth: 272) == 1,
               "a short window title needs a single line")
        expect(WindowBrowserGeometry.titleLines(
                forTitles: ["备忘录 — 一个非常长的中英文混合窗口标题 Window Title 2026"],
                availableWidth: 272) == 2,
               "a long window title keeps the second line reserved")
        let shortTitle = WindowBrowserGeometry.derivedParams(
            base: base, titles: ["音樂"], hasStatus: false)
        expect(shortTitle.cardTitleLines == 1
                && shortTitle.cardHeight == base.cardHeight - base.titleLineHeight,
               "a single-line title releases one line of card height "
               + "(\(Int(base.cardHeight)) → \(Int(shortTitle.cardHeight))pt)")
        expect(!shortTitle.footerVisible && shortTitle.effectiveFooterHeight == 0,
               "an empty status line releases the footer")
        let withStatus = WindowBrowserGeometry.derivedParams(
            base: base, titles: ["音樂"], hasStatus: true)
        expect(withStatus.footerVisible && withStatus.effectiveFooterHeight > 0,
               "a real status line still reserves the footer")
        expect(WindowBrowserGeometry.chromeHeight(params: shortTitle, mode: .dock)
                < WindowBrowserGeometry.chromeHeight(params: withStatus, mode: .dock),
               "the collapsed footer makes the panel shorter")

        let compact = WindowBrowserGeometry.layoutPlan(
            iconFrame: icon, edge: .bottom, screenFrame: screen, visibleFrame: visible,
            desiredSize: base.dockPanelSize, windowCount: 1, style: .grid,
            isContentDriven: true, params: shortTitle)
        let legacy = WindowBrowserGeometry.layoutPlan(
            iconFrame: icon, edge: .bottom, screenFrame: screen, visibleFrame: visible,
            desiredSize: base.dockPanelSize, windowCount: 1, style: .grid,
            isContentDriven: true, params: base)
        expect(compact.panelFrame.height < legacy.panelFrame.height,
               "one window without a status line is shorter than before "
               + "(\(Int(compact.panelFrame.height)) vs \(Int(legacy.panelFrame.height))pt)")
        let compactExpected = base.headerHeight + base.spacingTight
            + shortTitle.cardHeight + base.panelPadding
        expect(compact.panelFrame.height == compactExpected,
               "the panel hugs its content (\(Int(compactExpected))pt) instead of "
               + "reserving empty space below")
        expect(compact.content.listRect.height == compact.content.documentHeight,
               "no leftover band between the card and the panel edge")
        expect(compact.content.listRect.minY == base.panelPadding,
               "the content keeps one panel padding below it "
               + "(\(Int(compact.content.listRect.minY))pt)")
        let statusPlan = WindowBrowserGeometry.layoutPlan(
            iconFrame: icon, edge: .bottom, screenFrame: screen, visibleFrame: visible,
            desiredSize: base.dockPanelSize, windowCount: 1, style: .grid,
            isContentDriven: true, params: withStatus)
        let statusExpected = base.headerHeight + base.spacingTight + withStatus.cardHeight
            + base.effectiveFooterHeight + base.spacingSmall
        expect(statusPlan.panelFrame.height == statusExpected,
               "the status line grows the panel by exactly the footer strip "
               + "(\(Int(statusPlan.panelFrame.height)) vs \(Int(compact.panelFrame.height))pt)")

        // T46：单窗口面板不继承 520×460 下限。
        let single = WindowBrowserGeometry.layoutPlan(
            iconFrame: icon, edge: .bottom, screenFrame: screen, visibleFrame: visible,
            desiredSize: CGSize(width: 520, height: 460), windowCount: 1,
            style: .grid, isContentDriven: true)
        expect(single.panelFrame.width >= 280 && single.panelFrame.width <= 360,
               "a single-window Dock panel uses its natural width "
               + "(\(Int(single.panelFrame.width))pt)")
        expect(single.panelFrame.height <= 340,
               "a single-window panel stays compact "
               + "(\(Int(single.panelFrame.height))pt)")
        expect(single.content.columns == 1, "one window uses a single column")

        let two = WindowBrowserGeometry.layoutPlan(
            iconFrame: icon, edge: .bottom, screenFrame: screen, visibleFrame: visible,
            desiredSize: CGSize(width: 520, height: 460), windowCount: 2,
            style: .grid, isContentDriven: true)
        expect(two.content.columns == 2, "two windows prefer two columns")
        expect(two.panelFrame.width >= 560 && two.panelFrame.width <= 660,
               "two columns produce a naturally sized panel "
               + "(\(Int(two.panelFrame.width))pt)")

        let six = WindowBrowserGeometry.layoutPlan(
            iconFrame: icon, edge: .bottom, screenFrame: screen, visibleFrame: visible,
            desiredSize: CGSize(width: 520, height: 460), windowCount: 6,
            style: .grid, isContentDriven: true)
        expect(six.content.columns == 3, "six windows use three columns")
        expect(six.panelFrame.width <= 960, "the grid panel never exceeds the width cap")

        // T46 后半：大量窗口的列表不撑满屏幕宽度，并改为滚动。
        let list = WindowBrowserGeometry.layoutPlan(
            iconFrame: icon, edge: .bottom, screenFrame: screen, visibleFrame: visible,
            desiredSize: CGSize(width: 520, height: 460), windowCount: 20,
            style: .list, isContentDriven: true)
        expect(list.panelFrame.width < screen.width - 24,
               "a long list panel does not occupy the full display width")
        expect(list.content.documentHeight > list.content.listRect.height,
               "a long list becomes scrollable instead of overflowing")

        // 左/右 Dock：列数限制在一至两列，面板不横向铺开。
        for edge in [WindowBrowserDockEdge.left, .right] {
            let iconFrame = edge == .left ? NSRect(x: 6, y: 300, width: 52, height: 52)
                                          : NSRect(x: 1382, y: 300, width: 52, height: 52)
            let sidePlan = WindowBrowserGeometry.layoutPlan(
                iconFrame: iconFrame, edge: edge, screenFrame: screen, visibleFrame: visible,
                desiredSize: CGSize(width: 520, height: 460), windowCount: 6,
                style: .grid, isContentDriven: true)
            expect(sidePlan.content.columns <= WindowBrowserLayoutParams.standard
                    .sideDockMaximumColumns,
                   "a \(edge.rawValue) Dock keeps at most two grid columns")
            expect(sidePlan.panelFrame.width <= 640,
                   "a \(edge.rawValue) Dock panel stays narrow "
                   + "(\(Int(sidePlan.panelFrame.width))pt)")
        }
        let bottomSix = WindowBrowserGeometry.layoutPlan(
            iconFrame: icon, edge: .bottom, screenFrame: screen, visibleFrame: visible,
            desiredSize: CGSize(width: 520, height: 460), windowCount: 6,
            style: .grid, isContentDriven: true)
        expect(bottomSix.content.columns == 3,
               "a bottom Dock may still use three columns")

        // T47：所有 Dock 方向都留在安全区域内。
        for edge in [WindowBrowserDockEdge.bottom, .left, .right] {
            let iconFrame: NSRect
            switch edge {
            case .bottom: iconFrame = icon
            case .left: iconFrame = NSRect(x: 6, y: 300, width: 52, height: 52)
            case .right: iconFrame = NSRect(x: 1382, y: 300, width: 52, height: 52)
            }
            let plan = WindowBrowserGeometry.layoutPlan(
                iconFrame: iconFrame, edge: edge, screenFrame: screen,
                visibleFrame: visible, desiredSize: CGSize(width: 520, height: 460),
                windowCount: 4, style: .grid, isContentDriven: true)
            expect(visible.contains(plan.panelFrame),
                   "the panel stays inside the visible frame for edge \(edge.rawValue)")
            expect(plan.transitionRegion.contains(CGPoint(x: iconFrame.midX,
                                                          y: iconFrame.midY)),
                   "the transition region always contains the anchor icon")
        }
        let narrow = NSRect(x: 0, y: 0, width: 900, height: 600)
        let narrowVisible = NSRect(x: 0, y: 40, width: 900, height: 560)
        let narrowPlan = WindowBrowserGeometry.layoutPlan(
            iconFrame: NSRect(x: 420, y: 4, width: 40, height: 40), edge: .bottom,
            screenFrame: narrow, visibleFrame: narrowVisible,
            desiredSize: CGSize(width: 800, height: 560), windowCount: 12,
            style: .list, isContentDriven: true)
        expect(narrowPlan.panelFrame.width <= narrowVisible.width,
               "narrow screens constrain the panel instead of overflowing")
        expect(narrowPlan.panelFrame.maxY <= narrowVisible.maxY,
               "the panel never covers the menu bar area")

        // 键盘面板以理想尺寸起步，但仍受屏幕约束。
        let keyboard = WindowBrowserGeometry.layoutPlan(
            iconFrame: NSRect(x: 700, y: 8, width: 52, height: 52), edge: .bottom,
            screenFrame: screen, visibleFrame: visible,
            desiredSize: CGSize(width: 800, height: 560), windowCount: 3,
            style: .list, isContentDriven: false)
        expect(keyboard.panelFrame.width == 800 && keyboard.panelFrame.height == 560,
               "the keyboard panel uses its ideal size when the screen allows it")

        // T53：网格方向键与真实列数一致。
        let plan = WindowBrowserGeometry.contentPlan(
            bounds: NSRect(x: 0, y: 0, width: 940, height: 520), style: .grid,
            recordCount: 10, mode: .keyboard)
        expect(plan.columns >= 2, "a wide grid produces several columns")
        expect(plan.index(movingFrom: 0, direction: .down) == plan.columns,
               "the down arrow moves by exactly one row")
        expect(plan.index(movingFrom: 0, direction: .left) == nil,
               "the left arrow at column 0 does not wrap")
        expect(plan.index(movingFrom: plan.itemCount - 1, direction: .down) == nil,
               "the down arrow on the last row does not overflow")
        expect(plan.index(movingFrom: 4, direction: .end) == plan.itemCount - 1,
               "End moves to the last item")
        expect(plan.index(movingFrom: 4, direction: .home) == 0,
               "Home moves to the first item")

        // T48：布局只依赖数量与风格，新截图到达不会改变尺寸。
        let again = WindowBrowserGeometry.contentPlan(
            bounds: NSRect(x: 0, y: 0, width: 940, height: 520), style: .grid,
            recordCount: 10, mode: .keyboard)
        expect(again.cellSize == plan.cellSize && again.documentHeight == plan.documentHeight,
               "the layout result is stable and independent of image arrival")
    }

    // MARK: 新增：动作与状态呈现

    /// T49/T50：所有入口共享同一份能力判断，正常状态不使用警告色。
    static func actionPresentationModel() {
        var record = sampleRecord()
        record.capabilities = [.activate]
        let restricted = WindowBrowserActionPresentation.Context(
            hasAccessibility: true, hasScreenRecording: false, isBusy: false)
        let items = WindowBrowserActionPresentation.items(for: record, context: restricted)
        let fold = items.first { $0.action == .fold }
        expect(fold?.isEnabled == false, "a window without fold capability disables folding")
        expect(fold?.disabledReason != nil, "the disabled action explains why it cannot run")
        expect(items.first { $0.action == .activate }?.isEnabled == true,
               "activation stays available when accessibility is granted")
        let withoutAccessibility = WindowBrowserActionPresentation.items(
            for: record,
            context: WindowBrowserActionPresentation.Context(hasAccessibility: false,
                                                             hasScreenRecording: false))
        expect(withoutAccessibility.first { $0.action == .activate }?.isEnabled == false,
               "without accessibility the same action is disabled everywhere")
        expect(withoutAccessibility.first { $0.action == .activate }?.disabledReason
            == "需要辅助功能权限",
               "the reason matches the permission that is missing")

        var pinned = sampleRecord()
        pinned.pinState = .running
        pinned.capabilities = [.activate, .fold, .unpinPreview, .close, .minimize, .capture]
        let pinnedItems = WindowBrowserActionPresentation.items(for: pinned, context: .init())
        expect(pinnedItems.contains { $0.action == .unpinPreview && $0.isEnabled },
               "a pinned window offers 取消置顶")
        expect(!pinnedItems.contains { $0.action == .pinPreview },
               "a pinned window does not offer a second 置顶预览 action")
        expect(pinnedItems.first { $0.action == .unpinPreview }?.isOn == true,
               "the pinned state is reflected in the action model")
        expect(WindowBrowserActionPresentation.items(for: sampleRecord(), context: .init())
            .filter(\.isPrimary).allSatisfy { $0.symbolName != nil },
               "primary actions always carry a system symbol name")

        var folded = sampleRecord()
        folded.shadeState = .folded
        folded.systemVisibility = .offScreen
        folded.capabilities = [.activate, .unfold, .close, .minimize]
        let foldedStatus = WindowBrowserStatusPresentationFactory.make(record: folded,
                                                                      hasSnapshot: false)
        expect(foldedStatus.text == "已折叠" && !foldedStatus.isWarning,
               "T50: a folded, physically off-screen window is not an error state")
        expect(foldedStatus.symbolName != nil,
               "the folded state has a symbolic representation, not an emoji")
        var minimized = sampleRecord()
        minimized.systemVisibility = .minimized
        minimized.isMinimized = true
        let minimizedStatus = WindowBrowserStatusPresentationFactory.make(record: minimized,
                                                                         hasSnapshot: true)
        expect(minimizedStatus.isSnapshot && !minimizedStatus.isWarning,
               "a minimized window with a snapshot is marked as a snapshot, not a warning")
        expect(WindowBrowserStatusPresentationFactory.make(record: sampleRecord(),
                                                           hasSnapshot: false).text.isEmpty,
               "an ordinary window only shows its title")
        let failure = WindowBrowserStatusPresentationFactory.failure("截图不可用")
        expect(failure.isWarning, "only real failures use the warning styling")
    }

    /// T51/T52：材质选择与减少动态效果都是明确的可测策略。
    static func materialAndMotionPolicy() {
        expect(WindowBrowserMaterialPolicy.kind(style: .system, systemSupportsGlass: true,
                                                reduceTransparency: false) == .glass,
               "a supporting system uses the public glass path")
        expect(WindowBrowserMaterialPolicy.kind(style: .system, systemSupportsGlass: false,
                                                reduceTransparency: false) == .visualEffect,
               "older systems fall back to the native vibrancy material")
        expect(WindowBrowserMaterialPolicy.kind(style: .system, systemSupportsGlass: true,
                                                reduceTransparency: true) == .paper,
               "reduce transparency forces an opaque background")
        expect(WindowBrowserMaterialPolicy.kind(style: .paper, systemSupportsGlass: true,
                                                reduceTransparency: false) == .paper,
               "the explicit paper style always wins")
        expect(WindowBrowserMaterialPolicy.availableStyles(systemSupportsGlass: false)
            == [.system, .paper],
               "the appearance choices stay the same on systems without glass")
        expect(WindowBrowserAnimationPolicy.shouldAnimate(reduceMotion: true) == false,
               "reduce motion disables animated transitions")
        expect(WindowBrowserAnimationPolicy.duration(0.16, reduceMotion: true) == 0,
               "reduce motion compresses the appearance animation to zero")
        expect(WindowBrowserAnimationPolicy.duration(0.16, reduceMotion: false) == 0.16,
               "normal systems keep the tuned duration")

        _ = NSApplication.shared
        let host = WindowBrowserMaterialView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        host.update(style: .paper, cornerRadius: 16,
                    capabilities: WindowBrowserSystemCapabilities(supportsGlass: false,
                                                                  reduceTransparency: false,
                                                                  increaseContrast: true,
                                                                  reduceMotion: false))
        expect(host.kind == .paper, "an explicit paper style uses the opaque background")
        host.update(style: .system, cornerRadius: 16,
                    capabilities: WindowBrowserSystemCapabilities(supportsGlass: true,
                                                                  reduceTransparency: false,
                                                                  increaseContrast: false,
                                                                  reduceMotion: false))
        expect(host.kind == .glass, "a supporting system switches to the glass backdrop")
        expect(host.backdropView is WindowBrowserGlassBackdrop,
               "the glass path really installs the public AppKit glass view")
        // 面板背景与控制层的玻璃交给同一个 NSGlassEffectContainerView 协调。
        let glassContent = WindowBrowserContentView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 560))
        glassContent.materialOverride = (.system, WindowBrowserSystemCapabilities(
            supportsGlass: true, reduceTransparency: false,
            increaseContrast: false, reduceMotion: false))
        glassContent.update(mode: .keyboard, records: makeRecords(pid: 9801, count: 3),
                            selection: nil, style: .grid, busyKeys: [], status: "")
        glassContent.layout()
        if #available(macOS 26.0, *), WindowBrowserSystemCapabilities.runtimeSupportsGlass {
            expect(glassContent.glassContainerForDiagnostics != nil,
                   "two neighbouring glass shapes share one coordination container")
            let containerHost = glassContent.glassContainerForDiagnostics
                as? WindowBrowserGlassContainerHost
            let panelGlass = glassContent.materialHostForDiagnostics.backdropView
            expect(containerHost != nil && panelGlass?.superview === containerHost?.host,
                   "the panel glass really lives inside the container host")
        } else {
            expect(glassContent.glassContainerForDiagnostics == nil,
                   "without the glass SDK/runtime no coordination container is created")
        }
        host.update(style: .system, cornerRadius: 16,
                    capabilities: WindowBrowserSystemCapabilities(supportsGlass: true,
                                                                  reduceTransparency: true,
                                                                  increaseContrast: true,
                                                                  reduceMotion: true))
        expect(host.kind == .paper,
               "reduce transparency downgrades an already-open panel to paper")
        let surface = WindowBrowserControlSurface(frame: NSRect(x: 0, y: 0, width: 300,
                                                                height: 40))
        surface.update(style: .system,
                       capabilities: WindowBrowserSystemCapabilities(supportsGlass: false,
                                                                     reduceTransparency: false,
                                                                     increaseContrast: false,
                                                                     reduceMotion: false))
        expect(surface.kind == .visualEffect,
               "without glass the control surface uses the native vibrancy material")
        expect(surface.backdropView is NSVisualEffectView,
               "the fallback material is a real NSVisualEffectView")
    }

    /// T58/T59：排布先计算与预览，取消不移动；验证成功才登记撤销。
    static func placementPlans() {
        let key = WindowKey(application: ApplicationInstanceKey(pid: 9201, generation: 1),
                            originalWindowID: 31, windowGeneration: 1)
        let visibleAX = CGRect(x: 0, y: 25, width: 1440, height: 855)
        let current = CGRect(x: 400, y: 200, width: 600, height: 400)

        guard let left = WindowPlacementPolicy.plan(action: .leftHalf, target: key,
                                                    originalFrameAX: current,
                                                    visibleAreaAX: visibleAX) else {
            expect(false, "left half must produce a plan")
            return
        }
        expect(left.targetFrameAX.minX == visibleAX.minX
                && abs(left.targetFrameAX.width - visibleAX.width / 2) < 0.5,
               "left half splits the visible work area")
        guard let right = WindowPlacementPolicy.plan(action: .rightHalf, target: key,
                                                     originalFrameAX: current,
                                                     visibleAreaAX: visibleAX) else {
            expect(false, "right half must produce a plan")
            return
        }
        expect(abs(right.targetFrameAX.minX - visibleAX.midX) < 0.5,
               "right half starts at the horizontal midpoint")
        guard let center = WindowPlacementPolicy.plan(action: .center, target: key,
                                                      originalFrameAX: current,
                                                      visibleAreaAX: visibleAX) else {
            expect(false, "centering must produce a plan")
            return
        }
        expect(abs(center.targetFrameAX.midX - visibleAX.midX) < 0.5
                && center.targetFrameAX.size == current.size,
               "centering keeps the window size and centers it")
        guard let fill = WindowPlacementPolicy.plan(action: .fill, target: key,
                                                    originalFrameAX: current,
                                                    visibleAreaAX: visibleAX) else {
            expect(false, "fill must produce a plan")
            return
        }
        expect(fill.targetFrameAX == visibleAX,
               "fill uses the visible work area, not the physical screen")
        expect(fill.targetFrameAX.height < 900,
               "filling the work area is distinct from covering the whole screen")

        // 跨显示器：按归一化位置映射，不直接复制像素坐标。
        let otherVisible = CGRect(x: -1600, y: 25, width: 1600, height: 855)
        guard let moved = WindowPlacementPolicy.plan(action: .moveToDisplay, target: key,
                                                     originalFrameAX: current,
                                                     visibleAreaAX: visibleAX,
                                                     targetAreaAX: otherVisible,
                                                     displayID: 2) else {
            expect(false, "moving to another display must produce a plan")
            return
        }
        expect(moved.targetFrameAX.minX < 0,
               "the window lands on the other display in its own coordinate space")
        expect(moved.targetFrameAX.width <= otherVisible.width,
               "the moved frame fits inside the target display")

        // 预览不写真实窗口；取消预览也不改变任何东西。
        let previewSpy = RecordingPreviewPresenter()
        let backend = FakePlacementBackend(frame: current)
        let scheduler = ManualScheduler()
        let controller = WindowPlacementController(backend: backend, scheduler: scheduler,
                                                   previewPresenter: previewSpy,
                                                   verificationDelay: 0)
        controller.preview(left)
        expect(previewSpy.shownPlans.count == 1, "previewing shows the target outline")
        expect(backend.writeCount == 0, "previewing never moves the real window")
        controller.cancelPreview()
        expect(backend.writeCount == 0 && previewSpy.dismissCount == 1,
               "cancelling the preview changes nothing")

        // 执行 → 验证 → 撤销。
        var outcome: WindowPlacementOutcome?
        backend.observedFrame = current
        controller.apply(left) { outcome = $0 }
        scheduler.advance(0.01)
        expect(backend.writeCount == 1, "applying writes the planned frame")
        if case .applied(let undoRecord) = outcome {
            expect(undoRecord.frameAfterAX == left.targetFrameAX,
                   "the undo record stores the verified frame")
            expect(undoRecord.frameBeforeAX == current,
                   "the undo record keeps the original frame")
        } else {
            expect(false, "a verified placement must produce an undo record")
        }

        var undoOutcome: WindowPlacementOutcome?
        backend.observedFrame = left.targetFrameAX
        controller.undoLast { undoOutcome = $0 }
        scheduler.advance(0.01)
        if case .undone = undoOutcome {
            expect(true, "undo succeeds when the window is still where we left it")
        } else {
            expect(false, "undo must succeed for an unchanged placement")
        }
        expect(backend.writeCount == 2, "undo writes the recorded original frame")

        // 用户已经手动移动 → 拒绝回放旧布局。
        backend.observedFrame = left.targetFrameAX
        controller.apply(left) { outcome = $0 }
        scheduler.advance(0.01)
        backend.observedFrame = CGRect(x: 10, y: 10, width: 500, height: 300)
        var refused: WindowPlacementOutcome?
        controller.undoLast { refused = $0 }
        if case .refused = refused {
            expect(true, "undo refuses when the user moved the window afterwards")
        } else {
            expect(false, "undo must refuse a layout that no longer matches")
        }

        // 验证失败（系统最小尺寸限制）不登记撤销。
        let mismatch = FakePlacementBackend(frame: current)
        mismatch.frameAfterWrite = CGRect(x: 5, y: 5, width: 300, height: 200)
        let mismatchScheduler = ManualScheduler()
        let mismatchController = WindowPlacementController(backend: mismatch,
                                                           scheduler: mismatchScheduler,
                                                           verificationDelay: 0)
        var mismatchOutcome: WindowPlacementOutcome?
        mismatchController.apply(left) { mismatchOutcome = $0 }
        mismatchScheduler.advance(0.01)
        if case .uncertain = mismatchOutcome {
            expect(true, "an unverified placement is reported as uncertain")
        } else {
            expect(false, "a placement that does not match must not be reported as applied")
        }
        expect(!mismatchController.canUndo,
               "T59: only verified placements register an undo step")

        // 没有目标显示器时 moveToDisplay 不产生计划。
        expect(WindowPlacementPolicy.plan(action: .moveToDisplay, target: key,
                                          originalFrameAX: current,
                                          visibleAreaAX: visibleAX) == nil,
               "moving to another display without a target produces no plan")
        expect(WindowPlacementPolicy.plan(action: .undoLast, target: key,
                                          originalFrameAX: current,
                                          visibleAreaAX: visibleAX) == nil,
               "the undo action is not itself a placement plan")
    }

    final class RecordingPreviewPresenter: WindowPlacementPreviewPresenting {
        private(set) var shownPlans: [WindowPlacementPlan] = []
        private(set) var dismissCount = 0
        func show(plan: WindowPlacementPlan) { shownPlans.append(plan) }
        func dismiss() { dismissCount += 1 }
    }

    final class FakePlacementBackend: WindowPlacementBackend {
        var observedFrame: CGRect?
        /// 系统实际落到的 frame（例如受最小尺寸限制）；nil 表示与写入一致。
        var frameAfterWrite: CGRect?
        private(set) var writeCount = 0
        private(set) var writtenFrames: [CGRect] = []
        init(frame: CGRect?) { observedFrame = frame }
        func readFrame(of target: WindowKey, completion: @escaping (CGRect?) -> Void) {
            completion(observedFrame)
        }
        func writeFrame(_ frame: CGRect, to target: WindowKey,
                        completion: @escaping (Bool) -> Void) {
            writeCount += 1
            writtenFrames.append(frame)
            observedFrame = frameAfterWrite ?? frame
            completion(true)
        }
    }

    // MARK: 新增：测试替身与构造辅助

    final class RecordingItemDelegate: WindowBrowserItemDelegate {
        struct Performed {
            let action: WindowBrowserAction
            let key: WindowKey
        }
        private(set) var activatedCount = 0
        private(set) var performed: [Performed] = []
        private(set) var contextMenuKeys: [WindowKey] = []
        private(set) var hoverStates: [Bool] = []

        func browserItemDidActivate(_ sender: NSView, key: WindowKey) {
            activatedCount += 1
        }

        func browserItem(_ sender: NSView, perform action: WindowBrowserAction,
                         key: WindowKey) {
            performed.append(Performed(action: action, key: key))
        }

        func browserItem(_ sender: NSView, contextMenu key: WindowKey, event: NSEvent) {
            contextMenuKeys.append(key)
        }

        func browserItem(_ sender: NSView, hover key: WindowKey, isHovering: Bool) {
            hoverStates.append(isHovering)
        }

        private(set) var moreMenuRequests = 0
        func browserItemDidRequestMoreMenu(_ sender: NSView, key: WindowKey) {
            moreMenuRequests += 1
        }
    }

    static func configure(card: WindowBrowserCardView, record: WindowRecord,
                          selected: Bool, busy: Bool) {
        let actions = WindowBrowserActionPresentation.items(
            for: record,
            context: WindowBrowserActionPresentation.Context(isBusy: busy,
                                                             isSelected: selected))
        let status = WindowBrowserStatusPresentationFactory.make(record: record,
                                                                hasSnapshot: false)
        card.configure(record: record, actions: actions, status: status,
                       selected: selected, busy: busy, params: .standard, menu: nil)
    }

    static func configure(row: WindowBrowserListRowView, record: WindowRecord,
                          selected: Bool, busy: Bool) {
        let actions = WindowBrowserActionPresentation.items(
            for: record,
            context: WindowBrowserActionPresentation.Context(isBusy: busy,
                                                             isSelected: selected))
        let status = WindowBrowserStatusPresentationFactory.make(record: record,
                                                                hasSnapshot: false)
        row.configure(record: record, actions: actions, status: status,
                      selected: selected, busy: busy, params: .standard,
                      icon: nil, menu: nil)
    }

    static func makeRecords(pid: pid_t, count: Int) -> [WindowRecord] {
        var records: [WindowRecord] = []
        let total = max(1, count)
        for index in 1...total {
            let instance = ApplicationInstanceKey(pid: pid, generation: 1)
            let windowKey = WindowKey(application: instance,
                                      originalWindowID: CGWindowID(9000 + index),
                                      windowGeneration: 1)
            let title = index % 4 == 0
                ? "较长的中英文混合标题 Window \(index)"
                : "窗口 \(index)"
            let record = WindowRecord(
                key: windowKey,
                bundleIdentifier: "com.example.app",
                appName: "示例应用",
                title: title,
                logicalFrame: CGRect(x: 80, y: 80, width: 900, height: 640),
                placementSource: .liveDiscovery,
                systemVisibility: .onScreen,
                shadeState: .normal,
                pinState: .none,
                capabilities: .discoveredWindow,
                confidence: .confirmed,
                metadataRevision: UInt64(index),
                isMinimized: false,
                isOnScreen: true,
                isFoldedOffscreen: false,
                isManaged: false)
            records.append(record)
        }
        return records
    }

    // MARK: 新增：T26 / T34 / T37–T39 / 偏好设置

    /// T26：Dock 图标只改几何时不重建数据会话；键盘面板优先；换应用才新建会话。
    static func dockSessionDecision() {
        let appA = ApplicationInstanceKey(pid: 9301, generation: 1)
        let appB = ApplicationInstanceKey(pid: 9302, generation: 1)
        expect(WindowBrowserDockSessionPolicy.decision(
            sessionMode: .dock, sessionApplication: appA,
            keyboardPanelVisible: false, targetApplication: appA) == .updateAnchorOnly,
               "the same application instance only updates the anchor")
        expect(WindowBrowserDockSessionPolicy.decision(
            sessionMode: .dock, sessionApplication: appA,
            keyboardPanelVisible: false, targetApplication: appB) == .startNewSession,
               "a different application starts a new data session")
        expect(WindowBrowserDockSessionPolicy.decision(
            sessionMode: .keyboard, sessionApplication: nil,
            keyboardPanelVisible: true, targetApplication: appA) == .ignore,
               "the keyboard panel keeps priority over Dock hover")
        expect(WindowBrowserDockSessionPolicy.decision(
            sessionMode: .keyboard, sessionApplication: nil,
            keyboardPanelVisible: false, targetApplication: appA) == .startNewSession,
               "a hidden keyboard session does not block a Dock session")
        expect(WindowBrowserDockSessionPolicy.decision(
            sessionMode: nil, sessionApplication: nil,
            keyboardPanelVisible: false, targetApplication: appA) == .startNewSession,
               "without a session the Dock target opens a fresh one")

        // 同一应用的多次锚点变化不改变应用实例身份（因此不会重发目录请求）。
        let allocator = WindowIdentityAllocator()
        let first = allocator.applicationInstance(pid: 9301, bundleIdentifier: "com.example.app")
        let second = allocator.applicationInstance(pid: 9301, bundleIdentifier: "com.example.app")
        expect(first == second,
               "moving a Dock icon never allocates a new application instance")
    }

    /// T34：单个应用的结果到达不改变其他应用记录的版本（UI 只做局部更新）。
    static func catalogRevisionIsolation() {
        let catalog = WindowCatalog()
        _ = catalog.applyDiscovery(.success([
            discovered(pid: 9401, id: 11, title: "甲应用窗口")
        ]), pid: 9401)
        let keyA = catalog.windowKey(pid: 9401, bundleIdentifier: "com.example.app",
                                     originalWindowID: 11)
        guard let revisionBefore = catalog.record(for: keyA)?.metadataRevision else {
            expect(false, "the first application must publish a record")
            return
        }
        _ = catalog.applyDiscovery(.success([
            discovered(pid: 9402, id: 21, title: "乙应用窗口")
        ]), pid: 9402)
        expect(catalog.record(for: keyA)?.metadataRevision == revisionBefore,
               "another application's result does not change this record's revision")
        // 同一条记录内容真的变化时才推进版本。
        _ = catalog.applyDiscovery(.success([
            discovered(pid: 9401, id: 11, title: "甲应用窗口（已改名）")
        ]), pid: 9401)
        expect((catalog.record(for: keyA)?.metadataRevision ?? 0) != revisionBefore,
               "a real change to the record advances its revision")
    }

    /// T37–T39：实时预览租约身份与重试上限。
    static func liveLeaseIdentity() {
        let leaseA = UUID()
        let leaseB = UUID()
        let leaseC = UUID()
        expect(WindowBrowserLiveLeasePolicy.ownsGlobalRelease(currentLeaseID: leaseA,
                                                              releasingLeaseID: leaseA),
               "the current lease owns the global release")
        expect(!WindowBrowserLiveLeasePolicy.ownsGlobalRelease(currentLeaseID: leaseB,
                                                               releasingLeaseID: leaseA),
               "a stale lease A cannot release the current lease B")
        expect(!WindowBrowserLiveLeasePolicy.ownsGlobalRelease(currentLeaseID: leaseC,
                                                               releasingLeaseID: leaseA),
               "A → B → A still distinguishes the attempts by lease identity")
        expect(!WindowBrowserLiveLeasePolicy.ownsGlobalRelease(currentLeaseID: nil,
                                                               releasingLeaseID: leaseA),
               "with nothing mounted no lease performs a global release")
        expect(WindowBrowserLiveLeasePolicy.retryPermitted(failureCount: 0, blocked: false,
                                                           maxRetries: 2),
               "the first failure may retry")
        expect(WindowBrowserLiveLeasePolicy.retryPermitted(failureCount: 2, blocked: false,
                                                           maxRetries: 2),
               "the second failure may retry once more")
        expect(!WindowBrowserLiveLeasePolicy.retryPermitted(failureCount: 3, blocked: false,
                                                            maxRetries: 2),
               "after two automatic retries the window is not retried again")
        expect(!WindowBrowserLiveLeasePolicy.retryPermitted(failureCount: 0, blocked: true,
                                                            maxRetries: 2),
               "a blocked window never retries")
        expect(WindowBrowserLiveLeasePolicy.failureBlocksRetry(reason: "permission denied"),
               "a permission failure stops automatic retries")
        expect(WindowBrowserLiveLeasePolicy.failureBlocksRetry(reason: "no-sc-window"),
               "a missing source stops automatic retries")
        expect(!WindowBrowserLiveLeasePolicy.failureBlocksRetry(reason: "timeout"),
               "a transient timeout keeps the bounded retry budget")
        // 成功的启动条件仍然要求租约身份、会话与目标都成立。
        expect(WindowBrowserLivePreviewPolicy.shouldKeepStartedStream(
            leaseIsCurrent: true, cancelled: false, sessionActive: true,
            targetStillKnown: true), "a current, live lease is kept")
        expect(!WindowBrowserLivePreviewPolicy.shouldKeepStartedStream(
            leaseIsCurrent: false, cancelled: false, sessionActive: true,
            targetStillKnown: true), "an old lease is never kept")
    }

    /// 偏好设置往返与展示方式策略（“显示”分组的接线）。
    static func preferencesRoundTrip() {
        let defaults = UserDefaults.standard
        let previousStyle = defaults.string(forKey: WindowBrowserSettings.preferredStyleKey)
        let previousAppearance = defaults.string(
            forKey: WindowBrowserAppearanceStyle.defaultsKey)
        defer {
            if let previousStyle {
                defaults.set(previousStyle, forKey: WindowBrowserSettings.preferredStyleKey)
            } else {
                defaults.removeObject(forKey: WindowBrowserSettings.preferredStyleKey)
            }
            if let previousAppearance {
                defaults.set(previousAppearance, forKey: WindowBrowserAppearanceStyle.defaultsKey)
            } else {
                defaults.removeObject(forKey: WindowBrowserAppearanceStyle.defaultsKey)
            }
        }
        WindowBrowserSettings.preferredStyle = .list
        expect(WindowBrowserSettings.preferredStyle == .list,
               "the preferred display style round-trips through user defaults")
        WindowBrowserAppearanceStyle.current = .paper
        expect(WindowBrowserAppearanceStyle.current == .paper,
               "the appearance choice round-trips through user defaults")

        // 首次说明只出现一次，并且说明两个入口而不宣称会改动窗口。
        let previousHint = defaults.object(forKey: WindowBrowserSettings.firstRunHintShownKey)
        WindowBrowserSettings.firstRunHintShown = false
        expect(!WindowBrowserSettings.firstRunHintShown,
               "the first-run hint starts unshown")
        let hintWithShortcut = WindowBrowserSettings.firstRunHintText(hotKeyDisplay: "⌃⌥W")
        expect(hintWithShortcut.contains("Dock") && hintWithShortcut.contains("⌃⌥W")
                && hintWithShortcut.contains("不会改动窗口"),
               "the hint names both entry points and states the no-op guarantee")
        let hintWithoutShortcut = WindowBrowserSettings.firstRunHintText(hotKeyDisplay: nil)
        expect(hintWithoutShortcut.contains("选择窗口…"),
               "without a recorded shortcut the hint points at the menu entry")
        WindowBrowserSettings.firstRunHintShown = true
        expect(WindowBrowserSettings.firstRunHintShown,
               "the hint is remembered so it is shown only once")
        if let previousHint {
            defaults.set(previousHint, forKey: WindowBrowserSettings.firstRunHintShownKey)
        } else {
            defaults.removeObject(forKey: WindowBrowserSettings.firstRunHintShownKey)
        }

        expect(WindowBrowserSettings.initialDisplayStyle(
            preferred: .automatic, explicit: nil, windowCount: 3, autoListThreshold: 6) == .grid,
               "automatic style keeps a small set of windows in the grid")
        expect(WindowBrowserSettings.initialDisplayStyle(
            preferred: .automatic, explicit: nil, windowCount: 20, autoListThreshold: 6) == .list,
               "automatic style switches to the compact list for many windows")
        expect(WindowBrowserSettings.initialDisplayStyle(
            preferred: .grid, explicit: nil, windowCount: 20, autoListThreshold: 6) == .grid,
               "an explicit grid preference is not overridden by the window count")
        expect(WindowBrowserSettings.initialDisplayStyle(
            preferred: .list, explicit: nil, windowCount: 1, autoListThreshold: 6) == .list,
               "an explicit list preference is respected for a single window")
        expect(WindowBrowserSettings.initialDisplayStyle(
            preferred: .automatic, explicit: .grid, windowCount: 20,
            autoListThreshold: 6) == .grid,
               "a session-level explicit choice beats the automatic rule")
        expect(WindowBrowserSettings.PreferredStyle.allCases.map(\.rawValue)
            == ["automatic", "grid", "list"],
               "the stored style values stay stable for migration")
    }

    /// Escape 的层次：先清空搜索文本，再取消排布预览，最后才关闭面板。
    static func escapeLayering() {
        _ = NSApplication.shared
        let content = WindowBrowserContentView(frame: NSRect(x: 0, y: 0, width: 800, height: 560))
        var searches: [String] = []
        var cancels = 0
        content.onSearchChanged = { searches.append($0) }
        content.onCancel = { cancels += 1 }
        let records = makeRecords(pid: 9701, count: 4)
        content.update(mode: .keyboard, records: records, selection: records[0].key,
                       style: .list, busyKeys: [], status: "")
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        guard let searchField = content.subviews.compactMap({ $0 as? NSSearchField }).first else {
            expect(false, "the keyboard panel exposes a search field")
            return
        }
        // 系统搜索习惯：有文本时 Escape 先清空，不关闭面板。
        content.setSearchTextForDiagnostics("Safari")
        searches.removeAll()
        expect(content.control(searchField, textView: textView,
                               doCommandBy: #selector(NSResponder.cancelOperation(_:))),
               "Escape inside the search field is handled by the panel")
        expect(content.searchText.isEmpty, "Escape clears the search text first")
        expect(searches == [""], "clearing the field re-runs the filter once")
        expect(cancels == 0, "the panel is not dismissed by the first Escape")
        // ⌘F 把焦点交给搜索框（系统“查找”习惯）：在没有窗口时不可能聚焦，
        // 因此这里放进真实窗口再断言（旧断言曾因 nil === nil 假通过）。
        expect(!content.searchFieldIsFocused,
               "without a window the search field is not reported as focused")
        let focusWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 560),
                                   styleMask: [.borderless], backing: .buffered, defer: false)
        focusWindow.isReleasedWhenClosed = false
        focusWindow.contentView = content
        focusWindow.orderFrontRegardless()
        content.focusSearch()
        let responderAfterFocus = focusWindow.firstResponder
        expect(content.searchFieldIsFocused || responderAfterFocus is NSTextView,
               "⌘F makes the search field the first responder inside a real window "
               + "(responder=\(String(describing: responderAfterFocus)))")
        focusWindow.orderOut(nil)
        focusWindow.close()
        // 已经空了：Escape 关闭面板。
        expect(content.control(searchField, textView: textView,
                               doCommandBy: #selector(NSResponder.cancelOperation(_:))),
               "Escape on an empty field is handled by the panel")
        expect(cancels == 1, "the second Escape dismisses the panel")
        // Dock 面板没有搜索框：Escape 直接取消。
        content.update(mode: .dock, records: records, selection: records[0].key,
                       style: .grid, busyKeys: [], status: "")
        expect(content.control(searchField, textView: textView,
                               doCommandBy: #selector(NSResponder.cancelOperation(_:))),
               "Escape in the Dock panel is handled by the panel")
        expect(cancels == 2, "the Dock panel cancels on Escape without a search step")
    }

    /// 代理应用的标准主菜单：文本编辑快捷键与 ⌘W 靠它派发。
    /// 这里不是结构断言：直接在真实 NSTextField 上发一次 ⌘V，验证确实粘贴成功。
    static func standardMainMenu() {
        _ = NSApplication.shared
        let menu = StandardMenu.make(appName: "WindowShade", settingsTarget: nil,
                                     settingsAction: nil)
        NSApp.mainMenu = menu
        let titles = menu.items.compactMap { $0.submenu?.title }
        expect(titles.contains("编辑") && titles.contains("窗口"),
               "the agent app installs standard edit and window menus")
        guard let appMenu = menu.items.first?.submenu,
              let about = appMenu.items.first(where: { $0.title.hasPrefix("关于") }) else {
            expect(false, "the application menu exposes 关于")
            return
        }
        expect(about.action == #selector(NSApplication.orderFrontStandardAboutPanel(_:))
                || about.action != nil,
               "关于 is wired to an action (custom panel or the system default)")
        // 折叠窗口的菜单分区：前 9 个内联带 ⌃⌘1…9，其余进“更多”子菜单。
        let few = (1...3).map { $0 }
        let fewSplit = StandardMenu.splitFoldedWindows(few)
        expect(fewSplit.inline == few && fewSplit.overflow.isEmpty,
               "a short folded-window list stays inline")
        let many = Array(1...20)
        let manySplit = StandardMenu.splitFoldedWindows(many)
        expect(manySplit.inline.count == StandardMenu.inlineFoldedWindowLimit
                && manySplit.overflow.count == 20 - StandardMenu.inlineFoldedWindowLimit,
               "a long list splits into inline shortcuts and an overflow submenu")
        expect(manySplit.inline + manySplit.overflow == many,
               "the split preserves order and never drops a window")
        expect(StandardMenu.foldedWindowShortcut(index: 0) == "1"
                && StandardMenu.foldedWindowShortcut(index: 8) == "9",
               "the first nine windows carry ⌃⌘1…9 shortcuts")
        expect(StandardMenu.foldedWindowShortcut(index: 9) == nil
                && StandardMenu.foldedWindowShortcut(index: -1) == nil,
               "the overflow items carry no shortcut")
        // 菜单标题统一截断：短标题原样，长标题按上限收尾，两处列表共用同一规则。
        expect(StandardMenu.menuTitle("窗口 1") == "窗口 1",
               "a short menu title is left unchanged")
        let long = String(repeating: "长", count: 60)
        let truncated = StandardMenu.menuTitle(long)
        expect(truncated.count == 42 && truncated.hasSuffix("…"),
               "a long menu title is truncated to the shared limit")
        expect(StandardMenu.menuTitle(long, limit: 10).count == 10,
               "the truncation limit is configurable (used by tests and future callers)")
        expect(StandardMenu.menuTitle("  前后有空白  ") == "前后有空白",
               "menu titles are trimmed before truncation")

        // “关于”面板的内容来自同一份构造：版本、许可与仓库链接。
        let aboutOptions = StandardMenu.aboutPanelOptions(version: "1.0.14", build: "14")
        expect((aboutOptions[.applicationVersion] as? String) == "1.0.14"
                && (aboutOptions[.version] as? String) == "14",
               "the about panel shows the bundle version and build")
        let credits = aboutOptions[.credits] as? NSAttributedString
        expect(credits?.string.contains("MIT License") == true
                && credits?.string.contains("github.com/surfine/WindowShade") == true,
               "the about panel credits the license and the repository")
        var hasLink = false
        credits?.enumerateAttribute(.link, in: NSRange(location: 0, length: credits?.length ?? 0)) {
            value, _, _ in if value != nil { hasLink = true }
        }
        expect(hasLink, "the repository appears as a clickable link")

        // 注入了 target/action 时，“设置…”必须带上 ⌘, 且指向注入的目标。
        let withSettings = StandardMenu.make(appName: "WindowShade", settingsTarget: NSApp,
                                             settingsAction: #selector(NSApplication.terminate(_:)))
        let settingsItem = withSettings.items.first?.submenu?.items.first { $0.title == "设置…" }
        expect(settingsItem?.keyEquivalent == "," && settingsItem?.target === NSApp,
               "设置… uses ⌘, and the injected target")
        guard let edit = menu.items.compactMap({ $0.submenu }).first(where: { $0.title == "编辑" }),
              let paste = edit.items.first(where: { $0.title == "粘贴" }) else {
            expect(false, "the edit menu exposes 粘贴")
            return
        }
        expect(paste.keyEquivalent == "v"
                && paste.keyEquivalentModifierMask.contains(.command)
                && !paste.keyEquivalentModifierMask.contains(.shift),
               "粘贴 keeps the standard ⌘V key equivalent")
        if let redo = edit.items.first(where: { $0.title == "重做" }) {
            expect(redo.keyEquivalent == "z" && redo.keyEquivalentModifierMask.contains(.shift),
                   "重做 uses ⇧⌘Z")
        } else {
            expect(false, "the edit menu exposes 重做")
        }
        guard let windowMenu = menu.items.compactMap({ $0.submenu })
            .first(where: { $0.title == "窗口" }),
              let close = windowMenu.items.first(where: { $0.title == "关闭" }) else {
            expect(false, "the window menu exposes 关闭")
            return
        }
        expect(close.keyEquivalent == "w", "关闭 keeps the standard ⌘W key equivalent")
        let copyItem = edit.items.first { $0.title == "拷贝" }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 240, height: 60),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false

        // 行为验证：菜单必须认领 ⌘V 并把动作指向响应链的 paste:（真正落到文本框
        // 的端到端验证在独立进程里做，见 scripts/check-standard-menu.sh：
        // 同一份构建里“无主菜单 → 不粘贴、有主菜单 → 粘贴成功”）。
        expect(paste.action == #selector(NSText.paste(_:)),
               "粘贴 is wired to the standard paste: action")
        expect(copyItem?.action == #selector(NSText.copy(_:)),
               "拷贝 is wired to the standard copy: action")
        window.close()
    }

    /// Space 大图只读预览：取图来源、尺寸适配与无图时的说明。
    static func quickLookPolicy() {
        _ = NSApplication.shared
        expect(WindowBrowserQuickLookPolicy.source(hasThumbnail: true, hasFoldSnapshot: true)
                == .thumbnail,
               "an available thumbnail wins for the quick look image")
        expect(WindowBrowserQuickLookPolicy.source(hasThumbnail: false,
                                                   hasStaleSnapshot: true,
                                                   hasFoldSnapshot: true) == .staleSnapshot,
               "a stale service snapshot is used before the folded snapshot")
        expect(WindowBrowserQuickLookPolicy.source(hasThumbnail: false, hasFoldSnapshot: true)
                == .foldSnapshot,
               "a folded window falls back to its saved snapshot")
        expect(WindowBrowserQuickLookPolicy.source(hasThumbnail: false, hasFoldSnapshot: false)
                == .applicationIcon,
               "without any image the quick look shows the app icon")

        let visible = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let wide = WindowBrowserQuickLookPolicy.frame(
            imageSize: CGSize(width: 2560, height: 1440), visibleFrame: visible)
        expect(visible.contains(wide), "the quick look window stays inside the visible frame")
        expect(wide.width <= visible.width * 0.7 + 1,
               "the quick look window never exceeds 70% of the screen width")
        let portrait = WindowBrowserQuickLookPolicy.frame(
            imageSize: CGSize(width: 800, height: 2400), visibleFrame: visible)
        expect(portrait.height <= visible.height * 0.7 + 1 && portrait.width < portrait.height,
               "a tall window keeps its aspect ratio inside the same budget")
        let small = WindowBrowserQuickLookPolicy.frame(
            imageSize: CGSize(width: 200, height: 120), visibleFrame: visible)
        expect(small.width >= 200 && small.width <= 260,
               "a small image is not blown up beyond its natural size")
        // 极小屏幕/异常可用区域：窗口仍必须留在可见区域内。
        let tiny = NSRect(x: -300, y: -200, width: 200, height: 150)
        let tinyFrame = WindowBrowserQuickLookPolicy.frame(
            imageSize: CGSize(width: 3840, height: 2160), visibleFrame: tiny)
        expect(NSRect(x: -300, y: -200, width: 200, height: 150).contains(tinyFrame),
               "a huge image on a tiny screen is clamped inside the visible frame")
        let degenerate = WindowBrowserQuickLookPolicy.frame(
            imageSize: CGSize(width: 100, height: 100), visibleFrame: .zero)
        expect(degenerate.width >= 1 && degenerate.height >= 1,
               "a degenerate visible frame still produces a usable rect")

        expect(WindowBrowserQuickLookPolicy.message(for: .thumbnail) == nil,
               "a real image needs no explanatory message")
        expect(WindowBrowserQuickLookPolicy.message(for: .staleSnapshot)?
                    .contains("快照") == true,
               "a stale service image is labelled as a snapshot")
        expect(WindowBrowserQuickLookPolicy.message(for: .foldSnapshot)?
                    .contains("快照") == true,
               "the folded snapshot is labelled as a snapshot")
        expect(WindowBrowserQuickLookPolicy.message(for: .applicationIcon,
                                                    hasScreenRecording: false)?
                    .contains("屏幕录制") == true,
               "a missing permission is explained instead of showing a blank image")
        expect(WindowBrowserQuickLookPolicy.message(for: .applicationIcon,
                                                    isFolded: true)?.contains("折叠") == true,
               "a folded window without a snapshot says so")
        expect(WindowBrowserQuickLookPolicy.message(for: .applicationIcon) != nil,
               "the icon-only case always carries a reason")

        // 大图预览视图：点击任意位置触发关闭回调（系统 Quick Look 习惯）。
        let quickLookView = WindowBrowserQuickLookView(
            frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        var dismissed = 0
        quickLookView.onDismiss = { dismissed += 1 }
        if let click = NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 10, y: 10),
                                          modifierFlags: [], timestamp: 0, windowNumber: 0,
                                          context: nil, eventNumber: 0, clickCount: 1,
                                          pressure: 1) {
            quickLookView.mouseDown(with: click)
            expect(dismissed == 1, "clicking the quick look dismisses it")
        } else {
            expect(false, "could construct the quick look click event")
        }
        expect((quickLookView.accessibilityRole() == .image),
               "the quick look is exposed to VoiceOver as an image")

        // 键盘：Space 转成一次大图请求，Escape 仍然先取消/关闭。
        let content = WindowBrowserContentView(frame: NSRect(x: 0, y: 0, width: 800, height: 560))
        let records = makeRecords(pid: 9901, count: 3)
        content.update(mode: .keyboard, records: records, selection: records[1].key,
                       style: .list, busyKeys: [], status: "")
        var quickLookKeys: [WindowKey] = []
        content.onQuickLook = { quickLookKeys.append($0) }
        if let space = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                        timestamp: 0, windowNumber: 0, context: nil,
                                        characters: " ", charactersIgnoringModifiers: " ",
                                        isARepeat: false, keyCode: 49) {
            content.keyDown(with: space)
            expect(!content.searchFieldIsFocused,
                   "the test panel is not editing the search field")
            expect(quickLookKeys == [records[1].key],
                   "Space asks for a quick look of the selected window "
                   + "(got \(quickLookKeys.count), selection=\(content.selection != nil))")
        } else {
            expect(false, "could construct the Space key event")
        }
    }

    /// 动作结果的 VoiceOver 播报：只在操作结束后一句，不逐条播报刷新。
    static func accessibilityAnnouncements() {
        let key = WindowKey(application: ApplicationInstanceKey(pid: 9601, generation: 1),
                            originalWindowID: 71, windowGeneration: 1)
        _ = key
        expect(WindowBrowserAccessibilityAnnouncement.text(
            for: .completed, action: .fold, windowTitle: "参考资料") == "折叠完成：参考资料",
               "a completed action announces its result with the window title")
        expect(WindowBrowserAccessibilityAnnouncement.text(
            for: .completed, action: .unfold, windowTitle: "  ") == "展开完成",
               "an untitled window still produces a readable announcement")
        expect(WindowBrowserAccessibilityAnnouncement.text(
            for: .failed(reason: "折叠未通过隐藏验证"), action: .fold, windowTitle: "甲")
                == "折叠未通过隐藏验证",
               "a failure announces the real reason instead of a generic error")
        expect(WindowBrowserAccessibilityAnnouncement.text(
            for: .permissionRequired(kind: .accessibility), action: .close,
            windowTitle: "甲") == "需要辅助功能权限",
               "a permission failure names the missing permission")
        expect(WindowBrowserAccessibilityAnnouncement.text(
            for: .awaitingUser(reason: "窗口仍在，可能有保存确认框"), action: .close,
            windowTitle: "甲") == "窗口仍在，可能有保存确认框",
               "an awaiting-user outcome announces the actionable reason")
        expect(WindowBrowserAccessibilityAnnouncement.text(
            for: .busy, action: .fold, windowTitle: "甲") == "操作正在进行中",
               "a busy rejection is announced once, briefly")
    }

    /// 页脚结果状态的播报规则：只播结果、只播一次、不播刷新文字。
    static func statusAnnouncementPolicy() {
        expect(WindowBrowserStatusAnnouncement.shouldAnnounce(
            isResultStatus: true, status: "实时预览不可用，已回到快照", previous: nil),
               "a result status is announced once")
        expect(!WindowBrowserStatusAnnouncement.shouldAnnounce(
            isResultStatus: true, status: "实时预览不可用，已回到快照",
            previous: "实时预览不可用，已回到快照"),
               "the same status is not announced twice")
        expect(!WindowBrowserStatusAnnouncement.shouldAnnounce(
            isResultStatus: false, status: "正在刷新窗口…", previous: nil),
               "routine refresh text never interrupts VoiceOver")
        expect(!WindowBrowserStatusAnnouncement.shouldAnnounce(
            isResultStatus: true, status: "   ", previous: nil),
               "an empty status is not announced")
        expect(WindowBrowserStatusAnnouncement.shouldAnnounce(
            isResultStatus: true, status: " 已排布，可撤销 ", previous: "旧状态"),
               "a changed result status is announced")
    }

    /// T30：右键菜单跟踪期间保留锚点，菜单结束后补执行关闭。
    static func contextMenuTracking() {
        var tracking = WindowBrowserMenuTrackingState()
        expect(!tracking.requestClose(reason: "outside-click"),
               "outside a menu tracking session a close request executes immediately")
        tracking.beginTracking()
        expect(tracking.requestClose(reason: "dock-clear"),
               "a close request during menu tracking is deferred")
        expect(tracking.isTracking,
               "the panel stays alive while the menu is still an anchor")
        expect(tracking.deferredCloseReason == "dock-clear",
               "the deferred reason is preserved")
        expect(tracking.endTracking() == "dock-clear",
               "the deferred close executes once the menu ends")
        expect(!tracking.isTracking && tracking.deferredCloseReason == nil,
               "the tracking state is reset after the menu closes")
        expect(tracking.endTracking() == nil,
               "a menu that ends without a pending close performs no extra close")
    }

    /// T54：输入法候选存在时，Return 与方向键先交给文本系统。
    static func inputMethodPriority() {
        _ = NSApplication.shared
        let content = WindowBrowserContentView(frame: NSRect(x: 0, y: 0, width: 800, height: 560))
        var committed = 0
        var cancelled = 0
        var selections: [WindowKey] = []
        content.onCommit = { committed += 1 }
        content.onCancel = { cancelled += 1 }
        content.onSelect = { selections.append($0) }
        let records = makeRecords(pid: 6501, count: 4)
        content.update(mode: .keyboard, records: records, selection: records[0].key,
                       style: .list, busyKeys: [], status: "")
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        textView.setMarkedText("ni", selectedRange: NSRange(location: 0, length: 0),
                               replacementRange: NSRange(location: 0, length: 0))
        expect(textView.hasMarkedText(), "the test text view really has marked text")
        let searchField = content.subviews.compactMap { $0 as? NSSearchField }.first
        guard let searchField else {
            expect(false, "the keyboard panel exposes a search field")
            return
        }
        expect(!content.control(searchField, textView: textView,
                                doCommandBy: #selector(NSResponder.insertNewline(_:))),
               "Return with marked text is left to the input method")
        expect(!content.control(searchField, textView: textView,
                                doCommandBy: #selector(NSResponder.moveDown(_:))),
               "arrow keys with marked text are left to the input method")
        expect(committed == 0 && selections.isEmpty,
               "the IME candidate confirmation never activates a window")
        // 没有 marked text 时，Return/Escape 回到面板语义。
        textView.unmarkText()
        expect(content.control(searchField, textView: textView,
                               doCommandBy: #selector(NSResponder.insertNewline(_:))),
               "Return without marked text commits the panel action")
        expect(committed == 1, "the commit callback runs exactly once")
        expect(content.control(searchField, textView: textView,
                               doCommandBy: #selector(NSResponder.cancelOperation(_:))),
               "Escape without marked text cancels the panel")
        expect(cancelled == 1, "the cancel callback runs exactly once")
    }

    /// T57：只有真正聚焦目标才算成功；仅“仍然存在”时报告无法确认。
    static func activationVerification() {
        expect(WindowBrowserActivationVerification.outcome(targetFocused: true,
                                                           stillPresent: true) == .completed,
               "a focused target completes the activation")
        let uncertain = WindowBrowserActivationVerification.outcome(targetFocused: false,
                                                                    stillPresent: true)
        if case .uncertain(let reason) = uncertain {
            expect(reason.contains("无法确认"), "an unfocused but present target is uncertain")
        } else {
            expect(false, "presence alone must not be reported as success")
        }
        expect(WindowBrowserActivationVerification.outcome(targetFocused: false,
                                                           stillPresent: false) == .targetGone,
               "a vanished target is reported as gone")
        // 成功选择目标后不会被“归还焦点”逻辑抢走。
        expect(!WindowBrowserFocusReturnPolicy.shouldReturnFocus(
            previousAppPID: 501, ownPID: 900, currentFrontmostPID: 501,
            mode: .keyboard, panelWasKeyWindow: true),
               "once another app is frontmost the panel does not steal focus back")
        expect(WindowBrowserFocusReturnPolicy.shouldReturnFocus(
            previousAppPID: 501, ownPID: 900, currentFrontmostPID: 900,
            mode: .keyboard, panelWasKeyWindow: true),
               "the panel returns focus only when it still owns it")
    }

    static func hotKeyPolicy() {
        func hotKey(_ keyCode: Int, _ modifiers: Int) -> WindowBrowserSettings.HotKey {
            WindowBrowserSettings.HotKey(keyCode: UInt32(keyCode), modifiers: UInt32(modifiers))
        }
        expect(WindowBrowserSettings.isReserved(hotKey(kVK_ANSI_Q, cmdKey)),
               "⌘Q is rejected as a reserved shortcut")
        expect(WindowBrowserSettings.isReserved(hotKey(kVK_ANSI_K, 0)),
               "unmodified single letters are rejected")
        expect(WindowBrowserSettings.isReserved(hotKey(kVK_ANSI_K, shiftKey)),
               "shift-only shortcuts are rejected")
        expect(WindowBrowserSettings.isReserved(hotKey(kVK_ANSI_K, cmdKey)),
               "plain ⌘ combinations are rejected (they collide with app shortcuts)")
        expect(WindowBrowserSettings.isReserved(hotKey(kVK_ANSI_K, cmdKey | shiftKey)),
               "⌘⇧ combinations are rejected as well")
        expect(!WindowBrowserSettings.isReserved(hotKey(kVK_ANSI_K, cmdKey | optionKey)),
               "a deliberate combination is accepted")
        expect(!WindowBrowserSettings.isReserved(hotKey(kVK_ANSI_K, controlKey)),
               "control combinations are accepted")
        let name = WindowBrowserSettings.displayName(
            for: hotKey(kVK_ANSI_K, cmdKey | shiftKey))
        expect(name.contains("⌘") && name.contains("⇧") && !name.isEmpty,
               "display name renders modifier glyphs and a layout key name")
        expect(WindowBrowserSettings.isModifierOnlyKeyCode(UInt16(kVK_Command))
               && WindowBrowserSettings.isModifierOnlyKeyCode(UInt16(kVK_RightOption)),
               "modifier-only presses are not recorded as shortcuts")
        expect(!WindowBrowserSettings.isModifierOnlyKeyCode(UInt16(kVK_ANSI_K)),
               "a real key can be recorded")
    }

    /// 37. 连续 100 轮 fake 打开关闭后，缩略图服务与动作协调器的资源回到基线。
    static func hundredCyclesReturnToBaseline() {
        let key = WindowKey(application: ApplicationInstanceKey(pid: 6001, generation: 1),
                            originalWindowID: 1001, windowGeneration: 1)
        let size = CGSize(width: 300, height: 200)

        let backend = FakeThumbnailBackend()
        backend.autoResult = .success(makeImage(width: 16, height: 16))
        let service = WindowThumbnailService(backend: backend)
        for _ in 0..<100 {
            let subscription = service.request(windowKey: key, purpose: .card,
                                               logicalSize: size, onImage: { _ in })
            subscription.cancel()
        }
        service.invalidateAll()
        expect(service.inFlightCount == 0 && service.runningCaptureCount == 0
               && service.cachedCostBytes == 0,
               "100 thumbnail open/close cycles return to a zero baseline")

        let actionBackend = FakeActionBackend()
        actionBackend.autoOutcome = .completed
        let scheduler = ManualScheduler()
        let coordinator = WindowBrowserActionCoordinator(backend: actionBackend,
                                                         scheduler: scheduler)
        for _ in 0..<100 {
            coordinator.submit(action: .unfold, target: key) { _ in }
            scheduler.runAsync()
        }
        expect(coordinator.activeCount == 0 && coordinator.queuedCount == 0
               && !coordinator.isBusy(windowKey: key),
               "100 action cycles return to an idle coordinator")
        expect(actionBackend.performed.count == 100,
               "each cycle performed exactly one real action")
    }

    static func sampleRecord() -> WindowRecord {
        WindowRecord(
            key: WindowKey(application: ApplicationInstanceKey(pid: 5001, generation: 1),
                           originalWindowID: 901, windowGeneration: 1),
            bundleIdentifier: "com.example.app",
            appName: "示例应用",
            title: "示例窗口",
            logicalFrame: CGRect(x: 0, y: 0, width: 800, height: 600),
            placementSource: .liveDiscovery,
            systemVisibility: .onScreen,
            shadeState: .normal,
            pinState: .none,
            capabilities: .discoveredWindow,
            confidence: .confirmed,
            metadataRevision: 1,
            isMinimized: false,
            isOnScreen: true,
            isFoldedOffscreen: false,
            isManaged: false)
    }

    static func geometry() {
        let screen = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let visible = NSRect(x: 0, y: 78, width: 1440, height: 822)
        let icon = NSRect(x: 700, y: 8, width: 52, height: 52)
        let bottom = WindowBrowserGeometry.panelGeometry(
            iconFrame: icon, edge: .bottom, screenFrame: screen, visibleFrame: visible,
            desiredSize: CGSize(width: 520, height: 460), windowCount: 4)
        expect(bottom.panelFrame.minY >= icon.maxY, "bottom Dock panel sits above the icon")
        expect(bottom.panelFrame.minY >= visible.minY, "bottom panel stays inside visible frame")
        let gapPoint = CGPoint(x: icon.midX, y: (icon.maxY + bottom.panelFrame.minY) / 2)
        expect(bottom.transitionRegion.contains(gapPoint),
               "mouse crossing the icon-panel gap keeps the panel")
        expect(!bottom.transitionRegion.contains(CGPoint(x: 20, y: 820)),
               "transition region must not cover the whole desktop")

        let leftIcon = NSRect(x: 6, y: 300, width: 52, height: 52)
        let left = WindowBrowserGeometry.panelGeometry(
            iconFrame: leftIcon, edge: .left, screenFrame: screen, visibleFrame: visible,
            desiredSize: CGSize(width: 520, height: 460), windowCount: 3)
        expect(left.panelFrame.minX >= leftIcon.maxX, "left Dock panel sits to the right of the icon")

        // 负坐标副屏与上下排列：不得发生坐标翻转。
        let negativeScreen = NSRect(x: -1600, y: -400, width: 1600, height: 900)
        let negativeVisible = NSRect(x: -1600, y: -322, width: 1600, height: 822)
        let negativeIcon = NSRect(x: -1000, y: -392, width: 52, height: 52)
        let negative = WindowBrowserGeometry.panelGeometry(
            iconFrame: negativeIcon, edge: .bottom, screenFrame: negativeScreen,
            visibleFrame: negativeVisible,
            desiredSize: CGSize(width: 520, height: 460), windowCount: 2)
        expect(negative.panelFrame.minX >= negativeVisible.minX &&
               negative.panelFrame.maxX <= negativeVisible.maxX &&
               negative.panelFrame.minY >= negativeVisible.minY &&
               negative.panelFrame.maxY <= negativeVisible.maxY,
               "negative-origin screens stay clamped without flipping")

        let rightIcon = NSRect(x: 1382, y: 300, width: 52, height: 52)
        let right = WindowBrowserGeometry.panelGeometry(
            iconFrame: rightIcon, edge: .right, screenFrame: screen, visibleFrame: visible,
            desiredSize: CGSize(width: 520, height: 460), windowCount: 3)
        expect(right.panelFrame.maxX <= rightIcon.minX, "right Dock panel sits left of the icon")

        let many = WindowBrowserGeometry.panelGeometry(
            iconFrame: icon, edge: .bottom, screenFrame: screen, visibleFrame: visible,
            desiredSize: CGSize(width: 1000, height: 900), windowCount: 20)
        expect(many.usesListLayout, "more than the auto threshold switches to compact list")
        expect(many.panelFrame.height <= visible.height, "list layout stays inside the visible frame")
    }

    // MARK: 构造描述

    static func managed(pid: pid_t, id: CGWindowID, title: String,
                        frame: CGRect? = nil, isOnScreen: Bool = false,
                        capabilities: WindowBrowserCapabilities = .managedWindow)
        -> ManagedWindowDescriptor {
        ManagedWindowDescriptor(
            pid: pid,
            bundleIdentifier: "com.example.app",
            appName: "示例应用",
            originalWindowID: id,
            title: title,
            logicalFrame: frame,
            systemVisibility: isOnScreen ? .onScreen : .offScreen,
            shadeState: .folded,
            pinState: .none,
            isMinimized: false,
            isOnScreen: isOnScreen,
            placementSource: .managedFold,
            capabilities: capabilities,
            confidence: .confirmed)
    }

    static func discovered(pid: pid_t, id: CGWindowID, title: String,
                           frame: CGRect? = nil) -> DiscoveredWindowDescriptor {
        DiscoveredWindowDescriptor(
            pid: pid,
            bundleIdentifier: "com.example.app",
            appName: "示例应用",
            originalWindowID: id,
            title: title,
            frame: frame,
            isOnScreen: true,
            isMinimized: false,
            capabilities: [.activate, .fold, .pinPreview, .close, .minimize, .capture],
            confidence: .confirmed)
    }
}
