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
        expect(dockPanel.isExcludedFromWindowsMenu && keyboardPanel.isExcludedFromWindowsMenu,
               "temporary panels stay out of the Window menu")
        let contentForA11y = WindowBrowserContentView(frame: NSRect(x: 0, y: 0, width: 640, height: 520))
        expect(contentForA11y.accessibilityLabel() == "窗口浏览面板",
               "the panel content view exposes an accessibility label")
        let searchField = contentForA11y.subviews.compactMap { $0 as? NSSearchField }.first
        expect(searchField?.accessibilityLabel() == "搜索窗口",
               "the search field exposes an accessibility label")

        // 41. 点击卡片按钮不会额外触发主体激活。
        let card = WindowBrowserCardView(frame: NSRect(x: 0, y: 0, width: 224, height: 236))
        var activated = 0
        var primary = 0
        card.onActivate = { activated += 1 }
        card.onPrimary = { primary += 1 }
        card.configure(record: sampleRecord(), selected: false, busy: false,
                       params: .standard)
        card.layout()
        guard let primaryButton = card.subviews.compactMap({ $0 as? NSButton })
            .first(where: { $0.title == "折叠" || $0.title == "展开" }) else {
            expect(false, "card must expose a primary action button")
            return
        }
        primaryButton.performClick(nil)
        expect(primary == 1, "primary button triggers the primary action")
        expect(activated == 0, "button click must not bubble into card activation")
        expect(primaryButton.frame.height >= 28,
               "action buttons keep the ~28pt hit area from the layout parameters")
        expect(card.bounds.contains(primaryButton.frame),
               "action buttons stay inside the card bounds")
        if let thumbnail = card.subviews.first(where: { $0 is NSImageView })?.frame {
            expect(thumbnail.height <= WindowBrowserLayoutParams.standard.imageMaxHeight + 0.5,
                   "card image area never exceeds the configured maximum height")
        }
        if let event = NSEvent.mouseEvent(with: .leftMouseDown,
                                          location: NSPoint(x: 10, y: 10),
                                          modifierFlags: [], timestamp: 0, windowNumber: 0,
                                          context: nil, eventNumber: 0, clickCount: 1,
                                          pressure: 1) {
            card.mouseDown(with: event)
            expect(activated == 1, "card body click activates the window")
        }

        // 无变化的刷新不应重建卡片内容（可访问性动作/图层样式），有变化才重建。
        let unchanged = sampleRecord()
        card.configure(record: unchanged, selected: false, busy: false, params: .standard)
        primaryButton.title = "手工标记"
        card.configure(record: unchanged, selected: false, busy: false, params: .standard)
        expect(primaryButton.title == "手工标记",
               "an unchanged record skips card reconfiguration")
        var changed = unchanged
        changed.title = "标题已变"
        card.configure(record: changed, selected: false, busy: false, params: .standard)
        expect(primaryButton.title != "手工标记",
               "a changed record reconfigures the card")
        let accessibilityActions = card.accessibilityCustomActions() ?? []
        expect(accessibilityActions.contains { $0.name == "关闭窗口" },
               "cards expose an explicit accessibility close action")
        expect(accessibilityActions.contains { $0.name == "激活或展开窗口" },
               "cards expose an explicit accessibility activate action")

        // 列表风格：选中项预览栏出现，唯一一路实时画面挂到预览栏而不是每一行。
        let content = WindowBrowserContentView(frame: NSRect(x: 0, y: 0, width: 720, height: 520))
        let many = (1...20).map { index -> WindowRecord in
            var record = sampleRecord()
            record = WindowRecord(key: WindowKey(
                application: ApplicationInstanceKey(pid: 5001, generation: 1),
                originalWindowID: CGWindowID(900 + index), windowGeneration: 1),
                bundleIdentifier: record.bundleIdentifier, appName: record.appName,
                title: "窗口 \(index)", logicalFrame: record.logicalFrame,
                placementSource: record.placementSource,
                systemVisibility: record.systemVisibility,
                shadeState: record.shadeState, pinState: record.pinState,
                capabilities: record.capabilities, confidence: record.confidence,
                metadataRevision: UInt64(index), isMinimized: false,
                isOnScreen: true, isFoldedOffscreen: false, isManaged: false)
            return record
        }
        let selected = many[3]
        content.update(mode: .keyboard, records: many, selection: selected.key,
                       style: .list, busyKeys: [], status: "")
        content.layout()
        expect(content.selectionPaneIsVisible,
               "list style shows the selected-item preview pane")
        var restoringRecord = selected
        restoringRecord.shadeState = .restoring
        expect(WindowBrowserCardViewStatus.text(restoringRecord).contains("正在展开"),
               "a restoring window is labelled as restoring, not as open")
        let live = NSView(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
        content.setLivePreview(live, for: selected.key)
        expect(live.superview != nil,
               "the single live preview attaches to the selected list item")
        content.update(mode: .keyboard, records: many, selection: selected.key,
                       style: .grid, busyKeys: [], status: "")
        content.layout()
        expect(!content.selectionPaneIsVisible,
               "grid style does not keep the separate list preview pane")

        // 搜索框不能被列表压住：键盘面板里列表必须从搜索框下方开始。
        // 曾经列表底边按 footerHeight + 固定值算，而搜索框占得更靠上，重叠 8pt
        // （真实截图与 bug 报告：搜索框和窗口缩略图列表重叠）。
        for size in [CGSize(width: 640, height: 520), CGSize(width: 460, height: 340)] {
            for layoutStyle in [WindowBrowserDisplayStyle.grid, .list] {
                let layoutContent = WindowBrowserContentView(
                    frame: NSRect(origin: .zero, size: size))
                layoutContent.update(mode: .keyboard, records: many,
                                     selection: selected.key, style: layoutStyle,
                                     busyKeys: [], status: "")
                layoutContent.layout()
                let frames = layoutContent.layoutFrameSummary
                let label = "\(layoutStyle.rawValue) \(Int(size.width))x\(Int(size.height))"
                expect(frames.search.height > 0,
                       "keyboard panel keeps a visible search field (\(label))")
                expect(!frames.search.intersects(frames.list),
                       "search field must not overlap the list (\(label))")
                // 容器是左下原点：列表要在搜索框上方，即列表底边不低于搜索框顶边。
                expect(frames.list.minY >= frames.search.maxY,
                       "the list starts above the search field (\(label))")
                expect(frames.search.minY >= WindowBrowserLayoutParams.standard.footerHeight,
                       "the search field stays above the footer status line (\(label))")
            }
        }

        // 系统字号变大时底部状态行更高，搜索框与列表必须跟着让位，不能重新叠上。
        var largeTextParams = WindowBrowserLayoutParams.standard
        largeTextParams.footerHeight += 10
        largeTextParams.headerHeight += 8
        let largeTextContent = WindowBrowserContentView(
            frame: NSRect(x: 0, y: 0, width: 640, height: 520))
        largeTextContent.params = largeTextParams
        largeTextContent.update(mode: .keyboard, records: many, selection: selected.key,
                                style: .grid, busyKeys: [], status: "")
        largeTextContent.layout()
        let largeFrames = largeTextContent.layoutFrameSummary
        expect(!largeFrames.search.intersects(largeFrames.list),
               "a taller footer pushes the search field and list apart instead of overlapping")

        // Dock 面板没有搜索框，列表可以使用到状态行上方的空间。
        let dockContent = WindowBrowserContentView(
            frame: NSRect(x: 0, y: 0, width: 520, height: 460))
        dockContent.update(mode: .dock, records: many, selection: nil,
                           style: .grid, busyKeys: [], status: "")
        dockContent.layout()
        let dockFrames = dockContent.layoutFrameSummary
        expect(dockFrames.search == .zero,
               "dock panel keeps the search field out of the layout")
        expect(dockFrames.list.minY >= WindowBrowserLayoutParams.standard.footerHeight,
               "dock panel's list stays above the footer status line")

        // 风格切换：点“列表/缩略图”必须当场重排，不能等下一次刷新。
        // 真实 bug：按钮已高亮“列表”，内容仍是缩略图网格。
        let switchContent = WindowBrowserContentView(
            frame: NSRect(x: 0, y: 0, width: 640, height: 520))
        switchContent.update(mode: .keyboard, records: many, selection: selected.key,
                             style: .grid, busyKeys: [], status: "")
        switchContent.layout()
        expect(switchContent.renderedLayout.style == .grid,
               "the panel starts in the style it was asked for")
        var reportedStyles: [WindowBrowserDisplayStyle] = []
        switchContent.onStyleChanged = { reportedStyles.append($0) }
        if let control = switchContent.subviews.compactMap({ $0 as? NSSegmentedControl }).first,
           let action = control.action {
            control.selectedSegment = 1
            NSApp.sendAction(action, to: control.target, from: control)
            expect(reportedStyles == [.list], "the style control reports the new style")
            expect(switchContent.renderedLayout.style == .list,
                   "clicking 列表 switches the rendered layout immediately")
            expect(switchContent.renderedLayout.cards == 0
                    && switchContent.renderedLayout.rows == many.count,
                   "list style renders one row per window instead of cards")
            switchContent.layout()
            expect(switchContent.selectionPaneIsVisible,
                   "list style shows the selected-item pane after the switch")
            control.selectedSegment = 0
            NSApp.sendAction(action, to: control.target, from: control)
            expect(switchContent.renderedLayout.style == .grid
                    && switchContent.renderedLayout.cards == many.count,
                   "switching back to 缩略图 rebuilds the cards immediately")
        } else {
            expect(false, "the panel must expose a style control")
        }

        // 视口：长列表只请求可见（含向下预取）的项目，滚动后集合随之变化。
        var capturedViewport: [[WindowKey]] = []
        content.onVisibleKeysChanged = { capturedViewport.append($0) }
        content.update(mode: .keyboard, records: many, selection: selected.key,
                       style: .list, busyKeys: [], status: "")
        content.layout()
        let topVisible = content.visibleWindowKeys
        expect(!topVisible.isEmpty && topVisible.count < many.count,
               "a long list requests only a bounded viewport subset")
        expect(topVisible.contains(many[0].key),
               "the first visible row is inside the viewport subset")
        content.scrollDocument(toY: 400)
        let scrolled = content.visibleWindowKeys
        expect(!scrolled.isEmpty && scrolled != topVisible,
               "scrolling changes the requested viewport subset")
        expect(!capturedViewport.isEmpty,
               "viewport changes are reported to the controller")

        // 视图内存边界：滚动过的屏不长期驻留缩略图，只保留视口 + 选中项。
        for record in many {
            content.applyThumbnail(makeImage(width: 8, height: 8), for: record.key)
        }
        expect(content.cachedThumbnailCount == many.count,
               "thumbnails can be applied for every record")
        content.scrollDocument(toY: 0)
        content.layout()
        expect(content.cachedThumbnailCount < many.count,
               "off-screen thumbnails are dropped from the view")
        expect(content.cachedThumbnailCount <= content.visibleWindowKeys.count + 1,
               "the view keeps at most the viewport (plus the selected item)")

        // 实时不可用时回退到快照/图标：实时视图只覆盖在静态图之上。
        let fallbackKey = many[0].key
        content.update(mode: .keyboard, records: many, selection: fallbackKey,
                       style: .grid, busyKeys: [], status: "")
        content.layout()
        content.scrollDocument(toY: 0)
        content.applyThumbnail(makeImage(width: 8, height: 8), for: fallbackKey)
        let overlay = NSView(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
        content.setLivePreview(overlay, for: fallbackKey)
        expect(overlay.superview != nil, "live preview attaches above the card")
        content.setLivePreview(nil, for: fallbackKey)
        expect(overlay.superview == nil, "releasing the live preview detaches it")
        expect(content.cachedThumbnailCount >= 1,
               "the cached snapshot stays available as the fallback")

        // 方向键选择滚出视口时，选中项必须被滚回可见区域。
        content.update(mode: .keyboard, records: many, selection: many[0].key,
                       style: .list, busyKeys: [], status: "")
        content.layout()
        content.scrollDocument(toY: 0)
        let deepKey = many[many.count - 1].key
        expect(!content.visibleWindowKeys.contains(deepKey),
               "the last row starts outside the viewport")
        content.select(deepKey)
        expect(content.visibleWindowKeys.contains(deepKey),
               "selecting an off-screen row scrolls it into view")
        // 搜索/删除导致选中项变化（update 路径）同样滚入视口；
        // 但用户自己滚走、选中项未变时不能被刷新强行拉回。
        content.scrollDocument(toY: 0)
        content.update(mode: .keyboard, records: many, selection: many[0].key,
                       style: .list, busyKeys: [], status: "")
        content.layout()
        content.update(mode: .keyboard, records: many, selection: deepKey,
                       style: .list, busyKeys: [], status: "")
        content.layout()
        expect(content.visibleWindowKeys.contains(deepKey),
               "selection changed by update (search/deletion) is scrolled into view")
        content.scrollDocument(toY: 0)
        content.update(mode: .keyboard, records: many, selection: deepKey,
                       style: .list, busyKeys: [], status: "")
        content.layout()
        expect(!content.visibleWindowKeys.contains(deepKey),
               "a manual scroll away is not undone by a refresh with the same selection")

        // 规模回归：200 个窗口时视口与视图内存仍然有界。
        let huge = (1...200).map { index -> WindowRecord in
            var record = many[0]
            record = WindowRecord(key: WindowKey(
                application: ApplicationInstanceKey(pid: 5001, generation: 1),
                originalWindowID: CGWindowID(3000 + index), windowGeneration: 1),
                bundleIdentifier: record.bundleIdentifier, appName: record.appName,
                title: "窗口 \(index)", logicalFrame: record.logicalFrame,
                placementSource: record.placementSource,
                systemVisibility: record.systemVisibility,
                shadeState: record.shadeState, pinState: record.pinState,
                capabilities: record.capabilities, confidence: record.confidence,
                metadataRevision: UInt64(index), isMinimized: false,
                isOnScreen: true, isFoldedOffscreen: false, isManaged: false)
            return record
        }
        content.update(mode: .keyboard, records: huge, selection: huge[0].key,
                       style: .list, busyKeys: [], status: "")
        content.layout()
        content.scrollDocument(toY: 0)
        for record in huge {
            content.applyThumbnail(makeImage(width: 8, height: 8), for: record.key)
        }
        content.scrollDocument(toY: 0)
        expect(content.visibleWindowKeys.count < huge.count,
               "200 windows still produce a bounded viewport subset")
        expect(content.cachedThumbnailCount <= content.visibleWindowKeys.count + 1,
               "200 windows keep view-side thumbnail memory bounded")
        expect(content.cachedThumbnailBytes > 0
               && content.cachedThumbnailBytes < 20 * 1024 * 1024,
               "view-side image bytes stay observable and bounded")

        // 列表行的可访问性：按钮带窗口名，图标不作为独立元素。
        let row = WindowBrowserListRowView(frame: NSRect(x: 0, y: 0, width: 420, height: 56))
        row.configure(record: sampleRecord(), selected: false, busy: false, params: .standard)
        row.layout()
        let rowButtons = row.subviews.compactMap { $0 as? NSButton }
        expect(rowButtons.count == 2, "list rows expose two action buttons")
        expect(rowButtons.allSatisfy { ($0.accessibilityLabel() ?? "").contains("示例窗口") },
               "row buttons name the target window for VoiceOver")
        expect(row.subviews.compactMap { $0 as? NSImageView }
            .allSatisfy { !$0.isAccessibilityElement() },
               "row icons are not separate accessibility elements")
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
