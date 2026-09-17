// 只读身份探针：证明“动作执行前按完整身份重新核对、无法确认就拒绝”不是只在
// 假对象里成立，而是在真实 AX 上成立。
//
// 探针只做两件事：
// 1) 用生产 WindowBrowserTargetResolver 读取真实 AX 窗口（自己创建的探针窗口，
//    以及一个其他应用的真实窗口），核对正向解析与全部拒绝分支；
// 2) 把只记录调用的假后端接到生产 WindowBrowserActionCoordinator 上：validate
//    仍走生产解析逻辑，用来确认被拒绝的提交一次都不会到达 perform，而且允许
//    执行时传给 perform 的 key 与提交的 key 逐字段相同（不会被替换成别的窗口）。
//
// 不写任何窗口状态、不移动指针、不改变前台应用、不读取用户窗口内容。探针窗口
// 只在自身进程里短暂显示，结束时随进程退出。

import Cocoa
import ApplicationServices

/// 只记录调用的假后端。validate 委托给生产解析函数；perform 只记账，不执行任何
/// 真实窗口操作，因此“perform 未被调用”可以作为拒绝路径的硬断言。
final class IdentityProbeBackend: WindowBrowserActionBackend {
    private let allocator: WindowIdentityAllocator
    private let queue: DispatchQueue
    private let lock = NSLock()
    private var targets: [WindowKey] = []
    private var actions: [WindowBrowserAction] = []

    init(allocator: WindowIdentityAllocator, queue: DispatchQueue) {
        self.allocator = allocator
        self.queue = queue
    }

    var performedTargets: [WindowKey] {
        lock.lock()
        defer { lock.unlock() }
        return targets
    }

    var performedActions: [WindowBrowserAction] {
        lock.lock()
        defer { lock.unlock() }
        return actions
    }

    var performCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return targets.count
    }

    /// 与生产 WindowBrowserController.validate 相同的判定顺序：先看身份代数是否
    /// 仍然有效，再按完整身份解析真实 AX 窗口。
    func validate(target: WindowKey,
                  completion: @escaping (WindowBrowserTargetValidation) -> Void) {
        queue.async { [self] in
            let validation: WindowBrowserTargetValidation
            if !allocator.isCurrent(target) {
                validation = .gone
            } else if let element = WindowBrowserTargetResolver.enumerate(key: target),
                      WindowBrowserTargetResolver.inspect(element, key: target) != nil {
                validation = .valid
            } else {
                validation = .unverifiable(reason: "无法按完整身份解析窗口")
            }
            DispatchQueue.main.async { completion(validation) }
        }
    }

    func perform(action: WindowBrowserAction, target: WindowKey,
                 completion: @escaping (WindowBrowserActionOutcome) -> Void) {
        lock.lock()
        targets.append(target)
        actions.append(action)
        lock.unlock()
        completion(.completed)
    }
}

final class WindowBrowserIdentityProbe {
    private var window: NSWindow?
    private let allocator = WindowIdentityAllocator()
    private let queue = DispatchQueue(label: "WindowShade.window-browser-identity-probe",
                                      qos: .userInitiated)
    private var checks = 0
    private var failures: [String] = []
    private var liveKey: WindowKey?
    private var fabricatedKey: WindowKey?

    func run() {
        guard hasAccessibilityPermission() else {
            print("identity-probe: no accessibility permission; result=unverified")
            exit(2)
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 240),
                              styleMask: [.titled, .closable], backing: .buffered,
                              defer: false)
        window.title = "WindowShade identity probe"
        window.isReleasedWhenClosed = false
        window.center()
        // 只在窗口层级上短暂置顶，既不激活本进程也不抢 key，避免影响用户当前前台应用。
        window.level = .floating
        window.orderFrontRegardless()
        self.window = window
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.checkProbeWindow()
        }
    }

    // MARK: 真实 AX 身份解析

    private func checkProbeWindow() {
        guard let window, let id = cgWindowID(for: window) else {
            print("identity-probe: own window has no CGWindowID; result=unverified")
            exit(3)
        }
        let pid = getpid()
        let bundle = Bundle.main.bundleIdentifier ?? "com.windowshade.prototype"
        let key = allocator.windowKey(pid: pid, bundleIdentifier: bundle,
                                      originalWindowID: id)
        liveKey = key
        // 一个从未分配过的窗口 ID：不能靠“同一进程的其他窗口”顶替。
        fabricatedKey = WindowKey(application: key.application,
                                  originalWindowID: id &+ 991,
                                  windowGeneration: key.windowGeneration)
        let wrongPIDKey = WindowKey(
            application: ApplicationInstanceKey(pid: pid &+ 1,
                                                generation: key.application.generation),
            originalWindowID: id,
            windowGeneration: key.windowGeneration)
        queue.async { [self] in
            let enumerated = WindowBrowserTargetResolver.enumerate(key: key)
            let inspected = enumerated.flatMap {
                WindowBrowserTargetResolver.inspect($0, key: key, options: [.geometry, .capabilities])
            }
            let wrongWindowIDRejected = enumerated.map {
                WindowBrowserTargetResolver.inspect($0, key: fabricatedKey!) == nil
            } ?? false
            let wrongPIDRejected = enumerated.map {
                WindowBrowserTargetResolver.inspect($0, key: wrongPIDKey) == nil
            } ?? false
            let fabricatedRejected = WindowBrowserTargetResolver.enumerate(key: fabricatedKey!) == nil
            let geometry = inspected?.axSize.map {
                abs($0.width - window.frame.width) <= 2 && abs($0.height - window.frame.height) <= 2
            } ?? false
            DispatchQueue.main.async { [self] in
                record("own window resolved by full identity", inspected != nil)
                record("own window geometry matches NSWindow frame", geometry)
                record("own window reports close capability", inspected?.canClose == true)
                record("element with wrong window ID rejected", wrongWindowIDRejected)
                record("element with wrong pid rejected", wrongPIDRejected)
                record("fabricated window ID never enumerated", fabricatedRejected)
                print("identity-probe: ownWindow element=\(enumerated != nil) "
                      + "inspected=\(inspected != nil) geometryMatch=\(geometry) "
                      + "canClose=\(inspected?.canClose ?? false) "
                      + "wrongWindowID=\(wrongWindowIDRejected ? "rejected" : "accepted") "
                      + "wrongPID=\(wrongPIDRejected ? "rejected" : "accepted") "
                      + "fabricated=\(fabricatedRejected ? "rejected" : "accepted")")
                checkForeignWindow()
            }
        }
    }

    /// 另一个应用的真实窗口：正向解析必须成功，换窗口 ID / 换 PID 必须被拒绝。
    /// 全程只读，找不到合适目标就跳过（不算失败）。
    private func checkForeignWindow() {
        let ownPID = getpid()
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.processIdentifier != ownPID
                && $0.activationPolicy == .regular
                && !($0.bundleIdentifier ?? "").isEmpty
        }
        queue.async { [self] in
            for app in apps {
                let pid = app.processIdentifier
                let bundle = app.bundleIdentifier ?? ""
                for element in appWindows(pid: pid) {
                    guard let id = windowID(of: element), id != 0,
                          axRole(element) == "AXWindow" else { continue }
                    let key = allocator.windowKey(pid: pid, bundleIdentifier: bundle,
                                                  originalWindowID: id)
                    guard WindowBrowserTargetResolver.enumerate(key: key) != nil else { continue }
                    guard let inspected = WindowBrowserTargetResolver.inspect(
                            element, key: key, options: [.geometry]),
                          inspected.axSize != nil else { continue }
                    let other = WindowKey(application: key.application,
                                          originalWindowID: id &+ 991,
                                          windowGeneration: key.windowGeneration)
                    let otherPID = WindowKey(
                        application: ApplicationInstanceKey(pid: pid &+ 1,
                                                            generation: key.application.generation),
                        originalWindowID: id,
                        windowGeneration: key.windowGeneration)
                    let wrongWindowIDRejected =
                        WindowBrowserTargetResolver.inspect(element, key: other) == nil
                    let wrongPIDRejected =
                        WindowBrowserTargetResolver.inspect(element, key: otherPID) == nil
                    DispatchQueue.main.async { [self] in
                        record("foreign window resolved by full identity", true)
                        record("foreign element with wrong window ID rejected",
                               wrongWindowIDRejected)
                        record("foreign element with wrong pid rejected", wrongPIDRejected)
                        print("identity-probe: foreignWindow bundle=\(bundle) id=\(id) "
                              + "wrongWindowID=\(wrongWindowIDRejected ? "rejected" : "accepted") "
                              + "wrongPID=\(wrongPIDRejected ? "rejected" : "accepted")")
                        startCoordinatorChecks()
                    }
                    return
                }
            }
            DispatchQueue.main.async { [self] in
                print("identity-probe: foreignWindow skipped=no-suitable-target")
                startCoordinatorChecks()
            }
        }
    }

    // MARK: 协调器 + 生产解析链

    private func startCoordinatorChecks() {
        let backend = IdentityProbeBackend(allocator: allocator, queue: queue)
        let coordinator = WindowBrowserActionCoordinator(
            backend: backend,
            scheduler: WindowBrowserMainQueueScheduler(),
            timeout: 8.0)
        checkFabricatedSubmission(coordinator: coordinator, backend: backend)
    }

    private func checkFabricatedSubmission(coordinator: WindowBrowserActionCoordinator,
                                           backend: IdentityProbeBackend) {
        coordinator.submit(action: .fold, target: fabricatedKey!) { [self] outcome in
            record("fabricated submission never completes", outcome != .completed)
            record("fabricated submission never reaches perform", backend.performCount == 0)
            print("identity-probe: coordinator fabricatedKey outcome=\(outcome) "
                  + "performCalls=\(backend.performCount)")
            checkLiveSubmission(coordinator: coordinator, backend: backend)
        }
    }

    private func checkLiveSubmission(coordinator: WindowBrowserActionCoordinator,
                                     backend: IdentityProbeBackend) {
        let key = liveKey!
        coordinator.submit(action: .fold, target: key) { [self] outcome in
            let recordedTargets = backend.performedTargets
            let recordedActions = backend.performedActions
            record("live submission completes", outcome == .completed)
            record("perform receives exactly one call", backend.performCount == 1)
            record("perform receives the submitted key unchanged",
                   recordedTargets == [key])
            record("perform receives the submitted action",
                   recordedActions == [.fold])
            print("identity-probe: coordinator liveKey outcome=\(outcome) "
                  + "performCalls=\(backend.performCount) "
                  + "keyUnchanged=\(recordedTargets == [key])")
            closeProbeWindow()
        }
    }

    // MARK: 窗口真的消失后

    private func closeProbeWindow() {
        window?.close()
        let key = liveKey!
        waitForWindowGone(key: key) { [self] gone in
            record("closed probe window disappears from AX", gone)
            queue.async { [self] in
                let enumerated = WindowBrowserTargetResolver.enumerate(key: key) != nil
                DispatchQueue.main.async { [self] in
                    record("closed window is not resolved", !enumerated)
                    print("identity-probe: closedWindow gone=\(gone) "
                          + "enumerate=\(enumerated ? "found" : "none") "
                          + "allocatorStillCurrent=\(allocator.isCurrent(key))")
                    checkRefusalOnGoneWindow()
                }
            }
        }
    }

    /// 窗口消失但目录代数还没结算：validate 必须在真实 AX 上再次核对并拒绝，
    /// 不能凭目录里的旧记录继续执行。
    private func checkRefusalOnGoneWindow() {
        let key = liveKey!
        let backend = IdentityProbeBackend(allocator: allocator, queue: queue)
        let coordinator = WindowBrowserActionCoordinator(
            backend: backend,
            scheduler: WindowBrowserMainQueueScheduler(),
            timeout: 8.0)
        coordinator.submit(action: .fold, target: key) { [self] outcome in
            record("gone window submission never completes", outcome != .completed)
            record("gone window submission never reaches perform", backend.performCount == 0)
            print("identity-probe: coordinator goneWindow outcome=\(outcome) "
                  + "performCalls=\(backend.performCount)")
            checkRegeneratedIdentity(coordinator: coordinator, backend: backend)
        }
    }

    /// A → B → A：同一数字窗口 ID 被复用后，旧代数必须失效，新代数也要按真实 AX
    /// 状态重新核对，两者都不能到达 perform。
    private func checkRegeneratedIdentity(coordinator: WindowBrowserActionCoordinator,
                                          backend: IdentityProbeBackend) {
        let old = liveKey!
        allocator.confirmWindowDestroyed(old)
        let fresh = allocator.windowKey(pid: old.application.pid,
                                        bundleIdentifier: Bundle.main.bundleIdentifier ?? "",
                                        originalWindowID: old.originalWindowID)
        record("regenerated window ID gets a new generation",
               fresh.windowGeneration != old.windowGeneration)
        record("old generation no longer current", !allocator.isCurrent(old))
        coordinator.submit(action: .fold, target: old) { [self] outcome in
            record("stale generation never completes", outcome != .completed)
            record("stale generation never reaches perform", backend.performCount == 0)
            print("identity-probe: coordinator staleGeneration outcome=\(outcome) "
                  + "performCalls=\(backend.performCount)")
            coordinator.submit(action: .fold, target: fresh) { [self] outcome in
                record("regenerated key still re-checks real AX and refuses",
                       outcome != .completed)
                record("regenerated key never reaches perform", backend.performCount == 0)
                print("identity-probe: coordinator regeneratedKey outcome=\(outcome) "
                      + "performCalls=\(backend.performCount)")
                finish()
            }
        }
    }

    // MARK: 工具

    /// 轮询真实系统直到窗口从 AX 里消失，不用固定 sleep 掩盖异步结果。
    private func waitForWindowGone(key: WindowKey, attempt: Int = 0,
                                   completion: @escaping (Bool) -> Void) {
        queue.async { [self] in
            let gone = WindowBrowserTargetResolver.enumerate(key: key) == nil
            DispatchQueue.main.async { [self] in
                if gone || attempt >= 20 {
                    completion(gone)
                    return
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.waitForWindowGone(key: key, attempt: attempt + 1,
                                           completion: completion)
                }
            }
        }
    }

    private func record(_ description: String, _ condition: Bool) {
        checks += 1
        if !condition {
            failures.append(description)
            print("identity-probe: FAIL \(description)")
        }
    }

    private func finish() {
        print("identity-probe: checks=\(checks) failures=\(failures.count) "
              + "result=\(failures.isEmpty ? "pass" : "fail")")
        exit(failures.isEmpty ? 0 : 1)
    }
}
