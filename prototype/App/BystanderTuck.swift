// WindowShade 2.1 · 有人在看（默认关）：旁人正对屏幕时，把私人 App 的窗口沿原路收进刘海；
// 只剩你一个人、持续 1.5 秒才放回（收得快，放得慢）。看不到脸不算放回。
// 判断在 Core 的 BystanderPolicy / BystanderCameraGate / BystanderTuckLedger；这里只接线。
// 相机只在键盘鼠标停手满 30 秒后才开、一有输入就关，每秒 2 帧；锁屏、睡眠、切换用户时停。
// 不认人，不存图，不写日志；不碰系统解锁。
import Cocoa

/// 把私人 App 的在屏窗口收进刘海、再放回。只放回自己收的，用户自己收的不替用户拿出来。
@MainActor
final class BystanderTuck {
    private let ownerProvider: @MainActor () -> AppDelegate?
    private let list: PrivateAppList
    private var ledger = BystanderTuckLedger()
    /// 用户在刘海提醒上点了一下：全部放回之后，由守卫记下“亲手放回”。
    var onUserReleased: (() -> Void)?

    init(list: PrivateAppList = .shared,
         ownerProvider: @escaping @MainActor () -> AppDelegate? = { NSApp.delegate as? AppDelegate }) {
        self.list = list
        self.ownerProvider = ownerProvider
    }

    var hasTucked: Bool { !ledger.isEmpty }

    /// 收起：当前所有屏上私人 App 的标准窗口，走现成的收进刘海路径（从原处飞进刘海）。返回收了几扇。
    @discardableResult
    func tuckPrivateWindows() -> Int {
        guard !list.isEmpty, NotchController.isEnabled, AXIsProcessTrusted(),
              let owner = ownerProvider(), owner.notch.isAvailable else { return 0 }
        let candidates = ledger.toTuck(onScreenCandidates(owner: owner)) { [list] in list.contains(bundleID: $0) }
        guard !candidates.isEmpty else { return 0 }
        let pids = candidates.reduce(into: [pid_t]()) { if !$0.contains($1.pid) { $0.append($1.pid) } }
        let elements = Dictionary(uniqueKeysWithValues: zip(pids, concurrentAppWindows(pids)))
        var count = 0
        for candidate in candidates {
            guard let element = elements[candidate.pid]?.first(where: { windowID(of: $0) == candidate.id }),
                  axSubrole(element) == kAXStandardWindowSubrole as String,
                  !axBoolAttribute(element, "AXFullScreen"),
                  let position = axPosition(element), let size = axSize(element),
                  size.width > 1, size.height > 1 else { continue }
            let frame = CGRect(origin: position, size: size)
            owner.notch.tuck(element, id: candidate.id, pid: candidate.pid, landed: frame, home: frame, velocity: .zero)
            ledger.recordTucked(candidate)
            count += 1
        }
        if count > 0 { announce(owner: owner) }
        return count
    }

    /// 放回自己收的、还在刘海里而且还是原来那个进程的窗口。
    func releaseOurs(reason: String) {
        guard !ledger.isEmpty else { return }
        guard let owner = ownerProvider() else { ledger = BystanderTuckLedger(); return }
        let notch = owner.notch
        for id in ledger.takeReleases(tuckedPID: { notch.tuckedPID(of: $0) }) {
            notch.release(id, reason: "bystander \(reason)")
        }
    }

    // MARK: - 内部

    /// 刘海提醒：符号 eye，主句“有人在看”，副句“私人窗口已收起”。点一下全部放回。
    private func announce(owner: AppDelegate) {
        owner.notch.announceWhenFree(
            key: "bystander.tuck", text: "有人在看", detail: "私人窗口已收起", tone: .info, symbol: "eye",
            priority: 6, ttl: 5, hold: 4.5,
            onClick: { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.releaseOurs(reason: "user")
                    self.onUserReleased?()
                }
            })
    }

    /// 在屏、正常层级、不透明的窗口里，没被收起、没被卷起、不在侧边栏的。名单里有没有交给账本判断。
    private func onScreenCandidates(owner: AppDelegate) -> [BystanderTuckLedger.Candidate] {
        let own = getpid()
        let infos = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        var bundles: [pid_t: String?] = [:]
        var result: [BystanderTuckLedger.Candidate] = []
        for info in infos {
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  ((info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1) > 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != own,
                  let number = info[kCGWindowNumber as String] as? NSNumber,
                  let bounds = cgWindowBounds(info), bounds.width >= 40, bounds.height >= 40 else { continue }
            let id = CGWindowID(number.uint32Value)
            guard owner.shaded[id] == nil, !owner.slideOver.isSlideOver(id), !owner.notch.isTucked(id) else { continue }
            let bundleID: String?
            if let known = bundles[pid] {
                bundleID = known
            } else {
                bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
                bundles[pid] = bundleID
            }
            result.append(.init(id: id, pid: pid, bundleID: bundleID))
        }
        return result
    }
}

/// 有人在看的守卫（默认关）：管相机什么时候开、每帧交给策略、按结论收起或放回。
/// 只在设置开着（或开发者用环境变量指定镜头）、私人 App 名单不空、已授权相机、没锁屏、
/// 而且键盘鼠标停手满 30 秒时才开相机；一有输入就关。授权提示只在用户刚打开开关那一下出现。
@MainActor
final class BystanderGuard {
    static let cameraEnvironmentKey = "WINDOWSHADE_BYSTANDER_CAMERA"
    /// 一次租约的上限（一天）；到期由失败回调重开一次，不轮询。
    private static let leaseSeconds: Double = 86_400
    /// kCGAnyInputEventType：键盘、鼠标、触控板任一输入。
    private static let anyInput = CGEventType(rawValue: ~0)!

    private let environmentCamera: String?
    private let list: PrivateAppList
    private let tuck: BystanderTuck
    private let source = FaceObservationSource()
    private var policy = BystanderPolicy()
    private var task: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    /// 等停手满 30 秒的一次性定时器；开相机、停用、挂起时都撤掉。
    private var idleTimer: Timer?
    private var epoch: UInt64 = 0
    /// 睡眠、屏幕睡了、切到别的用户。
    private var suspended = false
    /// 收到了锁屏通知、还没收到解锁通知。和锁屏状态任一说锁着就算锁着。
    private var lockedByNotice = false
    // 只在主线程写；deinit 里移除时已没有别的引用。
    nonisolated(unsafe) private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    /// 开关没开、环境变量也没指定镜头就返回 nil：默认关。环境变量只是开发者覆盖。
    static func configured(environment: [String: String] = ProcessInfo.processInfo.environment,
                           list: PrivateAppList = .shared) -> BystanderGuard? {
        let camera = environment[cameraEnvironmentKey]?.trimmingCharacters(in: .whitespaces)
        let hasOverride = camera?.isEmpty == false
        guard hasOverride || BystanderCameraPick.isEnabled else { return nil }
        return BystanderGuard(environmentCamera: hasOverride ? camera : nil, list: list)
    }

    private init(environmentCamera: String?, list: PrivateAppList) {
        self.environmentCamera = environmentCamera
        self.list = list
        self.tuck = BystanderTuck(list: list)
        tuck.onUserReleased = { [weak self] in
            MainActor.assumeIsolated { self?.userReleased() }
        }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification] {
            observers.append((workspace, workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.setSuspended(true) }
            }))
        }
        for name in [NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            observers.append((workspace, workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.setSuspended(false) }
            }))
        }
        // 锁屏通知一到就停，不等锁屏状态跟上；解锁后再按条件看。
        let distributed = DistributedNotificationCenter.default()
        for (name, locked) in [("com.apple.screenIsLocked", true), ("com.apple.screenIsUnlocked", false)] {
            observers.append((distributed, distributed.addObserver(forName: .init(name), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.setLocked(locked) }
            }))
        }
        // 名单变了：空了就停相机，有了再看停手够不够。
        observers.append((NotificationCenter.default, NotificationCenter.default.addObserver(
            forName: PrivateAppList.didChange, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.evaluate() }
            }))
    }

    deinit { for (center, observer) in observers { center.removeObserver(observer) } }

    var isRunning: Bool { task != nil }

    /// 还没问过用户就弹一次系统授权；问过就什么也不做。只由「打开开关」那一下调用。
    func requestAccessIfNeeded() async {
        guard FaceObservationSource.authorizationStatus == .notDetermined else { return }
        _ = await source.requestAuthorization()
    }

    /// 关掉开关：停相机、撤定时器、放回自己收的窗口。
    func shutDown() {
        cancelIdleTimer()
        stopCamera()
        tuck.releaseOurs(reason: "off")
        policy = BystanderPolicy()
    }

    /// 按现在的条件决定：开相机、等停手、还是关着。
    func evaluate() {
        let facts = BystanderCameraGate.Facts(
            enabled: environmentCamera != nil || BystanderCameraPick.isEnabled,
            hasPrivateApps: !list.isEmpty,
            cameraAuthorized: FaceObservationSource.authorizationStatus == .authorized,
            unlocked: !lockedByNotice && AuthorizationService.shared.lockState() == .unlocked,
            suspended: suspended,
            idleSeconds: Self.idleSeconds())
        switch BystanderCameraGate.verdict(facts) {
        case .off:
            cancelIdleTimer()
            stopCamera()
        case .waitForIdle(let seconds):
            stopCamera()
            scheduleIdleCheck(after: seconds)
        case .run:
            cancelIdleTimer()
            startCamera()
        }
    }

    // MARK: - 内部

    private static func idleSeconds() -> Double {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
    }

    private func setSuspended(_ value: Bool) {
        suspended = value
        evaluate()
    }

    private func setLocked(_ value: Bool) {
        lockedByNotice = value
        evaluate()
    }

    /// 一次性定时器，带容差；不是轮询：到点只读一次空闲秒数，够了就开相机，不够就按差额再排一次。
    private func scheduleIdleCheck(after seconds: Double) {
        cancelIdleTimer()
        let timer = Timer(timeInterval: seconds, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.idleTimer = nil
                self?.evaluate()
            }
        }
        timer.tolerance = min(5, max(0.5, seconds * 0.2))
        RunLoop.main.add(timer, forMode: .common)
        idleTimer = timer
    }

    private func cancelIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = nil
    }

    private func chosenCamera() -> String? {
        BystanderCameraPick.resolve(
            environmentCamera: environmentCamera,
            settingEnabled: BystanderCameraPick.isEnabled,
            available: FaceObservationSource.devices().map(\.id))
    }

    private func startCamera(retrying: Bool = false) {
        guard task == nil else { return }
        guard let camera = chosenCamera() else {
            // 镜头列表是系统异步给的，刚启动时可能还空着：隔一秒只再试一次，不轮询。
            guard !retrying, retryTask == nil else { return }
            retryTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(1), clock: .suspending)
                guard !Task.isCancelled, let self else { return }
                self.retryTask = nil
                self.startCamera(retrying: true)
            }
            return
        }
        epoch &+= 1
        let current = epoch
        task = Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await self.source.subscribe(deviceID: camera, purpose: .bystander, validFor: Self.leaseSeconds,
                    onObservation: { [weak self] frame in
                        guard let self, self.epoch == current else { return }
                        self.consume(frame)
                    }, onFailure: { [weak self] error in
                        guard let self, self.epoch == current else { return }
                        self.stopCamera()
                        // 租约到期重开一次；其它失败（相机被占、被打断）就停，等下次条件变化。
                        if case FaceObservationSourceError.expired = error { self.evaluate() }
                    })
            } catch {
                if self.epoch == current { self.stopCamera() }
            }
        }
    }

    /// 停相机，轨迹作废。收起的窗口不动：停了不等于人走了，用户随时可以点刘海放回。
    private func stopCamera() {
        guard task != nil || retryTask != nil else { return }
        epoch &+= 1
        retryTask?.cancel(); retryTask = nil
        task?.cancel(); task = nil
        source.stop()
        policy.forgetTracks()
    }

    private func consume(_ frame: FaceObservation) {
        // 锁了、或者你又动了键盘鼠标：关相机，按条件重排。
        guard !lockedByNotice, !suspended, AuthorizationService.shared.lockState() == .unlocked,
              Self.idleSeconds() >= BystanderCameraGate.idleThreshold else { evaluate(); return }
        let faces = frame.faces.map { BystanderFace(box: $0.boundingBox, yaw: $0.yaw, pitch: $0.pitch) }
        switch policy.observe(faces, at: frame.observedAt) {
        case .cover: tuck.tuckPrivateWindows()
        case .clear: tuck.releaseOurs(reason: "alone")
        case .none: break
        }
    }

    /// 点一下刘海（不只是 4.5 秒提醒）：这次收进去的整批放回，并记下“亲手放回”。没有自己收的就返回 false。
    func releaseForUser() -> Bool {
        guard tuck.hasTucked else { return false }
        tuck.releaseOurs(reason: "user")
        userReleased()
        return true
    }

    /// 用户在刘海上点了一下、全部放回：记下来，正在看的人和接下来一小段时间都先不再收。
    private func userReleased() {
        policy.userCleared(at: CACurrentMediaTime())
    }
}
