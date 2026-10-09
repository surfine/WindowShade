import Cocoa

/// 离开就锁的在场信号来源（手机、手表）。只发 PresenceLock 认得的连接、断开、读回事件。
///
/// 这一版不带任何来源：tools/probes/RESULTS-2026-10-03.md 里 P-BLE 没上机跑过，
/// tools/probes/DECISIONS.md 定了「身份绑定协议完成前不开自动在场锁」。来源准入后从这里接入。
@MainActor protocol PresenceSource: AnyObject {
    func start(emit: @escaping @MainActor ([PresenceLock.Event]) -> Void)
    /// 唤醒后蓝牙栈恢复了再重连；reducer 在唤醒一秒后发。
    func restart()
    func stop()
}

/// 只锁，不解锁。和苹果菜单里「锁定屏幕」是同一件事。
enum PresenceScreenLock {
    static func lock() -> Bool {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login",
                                  RTLD_NOW | RTLD_LOCAL),
              let symbol = dlsym(handle, "SACLockScreenImmediate") else { return false }
        typealias LockNow = @convention(c) () -> Int32
        _ = unsafeBitCast(symbol, to: LockNow.self)()
        return true
    }
}

/// 锁屏前把私人 App 的在屏窗口收进刘海。和「有人在看」（BystanderTuck）走同一条收进刘海的路、
/// 用同一个账本挑窗口，只是不在刘海里说「有人在看」——马上就锁屏了。
/// 名单为空、刘海关着、没有辅助功能权限时什么都不做。收进去的不自动放回，回来后在刘海那一排里拿。
@MainActor enum PresencePrivateTuck {
    static func tuck() -> Int { tuck(list: .shared, owner: NSApp.delegate as? AppDelegate) }

    static func tuck(list: PrivateAppList, owner: AppDelegate?) -> Int {
        guard !list.isEmpty, NotchController.isEnabled, AXIsProcessTrusted(),
              let owner, owner.notch.isAvailable else { return 0 }
        let candidates = BystanderTuckLedger().toTuck(onScreenCandidates(owner: owner)) { list.contains(bundleID: $0) }
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
            count += 1
        }
        return count
    }

    /// 在屏、正常层级、不透明的窗口里，没被收起、没被卷起、不在侧边栏的（和 BystanderTuck 同一套条件）。
    private static func onScreenCandidates(owner: AppDelegate) -> [BystanderTuckLedger.Candidate] {
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

/// 合盖效果开着时，锁屏前先让桌面折进刘海。
/// 合盖效果（DuoController）现在只跟着盖子的角度走，还没有「不合盖、直接折一次」的入口，
/// 所以这里一律返回 false：照旧直接锁。入口接上后在这里调用它，返回 true，驱动就等 0.35 秒再锁。
@MainActor enum PresenceLockFold {
    static func begin() -> Bool { false }
}

/// 离开就锁的暂停与续播。只暂停正在放的，只续播自己暂停的那一个（账本见 PresenceMediaLedger）。
///
/// - 推送式正在播放开着、App 里带着适配器时，先用适配器读一次在不在放，再按「暂停」「播放」
///   （MediaRemote 的 1 和 0，不用来回切换的 2，免得把停着的歌放起来）；任何播放器都行。
/// - 否则只对 Music、Spotify，而且只在已经允许过自动化时，用固定脚本「在放才暂停」「停着才播放」；
///   不弹自动化授权。
/// - osascript 和 perl 都是阻塞调用（最多等 2.5 秒），放在自己的串行队列上；账本也只在这条队列上读写，
///   所以暂停一定先于续播。只在锁屏前和解开后各跑一次，不定时问。
final class PresenceMediaControl: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.windowshade.presence.media", qos: .utility)
    /// 只在 `queue` 上读写。
    private var ledger = PresenceMediaLedger()

    func pause(_ token: WS2.Token) { queue.async { self.pauseNow(token) } }
    func resume(_ token: WS2.Token) { queue.async { self.resumeNow(token) } }

    private func pauseNow(_ token: WS2.Token) {
        if let adapter = Self.streamAdapter() {
            guard let now = Self.streamNowPlaying(adapter), now.playing else { return }
            if Self.streamSend(Self.mrPause, adapter: adapter) {
                ledger.recordPaused(.init(token: token, route: .stream, bundleID: now.bundleID))
            }
            return
        }
        for id in Self.runningPlayers() where Self.automationAllowed(id) {
            if Self.script(id, mode: "pause") == "done" {
                ledger.recordPaused(.init(token: token, route: .script, bundleID: id))
                return
            }
        }
    }

    private func resumeNow(_ token: WS2.Token) {
        guard let entry = ledger.takeResume(for: token) else { return }
        switch entry.route {
        case .stream:
            guard let adapter = Self.streamAdapter(), let now = Self.streamNowPlaying(adapter),
                  PresenceMediaLedger.shouldResume(entry, nowBundleID: now.bundleID, nowPlaying: now.playing) else { return }
            _ = Self.streamSend(Self.mrPlay, adapter: adapter)
        case .script:
            guard Self.runningPlayers().contains(entry.bundleID), Self.automationAllowed(entry.bundleID) else { return }
            _ = Self.script(entry.bundleID, mode: "resume")
        }
    }

    // MARK: 推送式正在播放的适配器

    private static let mrPlay = "0"
    private static let mrPause = "1"

    private static func streamAdapter() -> NowPlayingStream.Adapter? {
        NowPlayingStream.isExplicitlyEnabled ? NowPlayingStream.locateAdapter() : nil
    }

    private static func streamNowPlaying(_ adapter: NowPlayingStream.Adapter) -> (bundleID: String, playing: Bool)? {
        run("/usr/bin/perl", [adapter.script.path, adapter.framework.path, "get", "--no-artwork"])
            .flatMap(PresenceMediaLedger.nowPlaying(fromGetOutput:))
    }

    private static func streamSend(_ command: String, adapter: NowPlayingStream.Adapter) -> Bool {
        run("/usr/bin/perl", [adapter.script.path, adapter.framework.path, "send", command]) != nil
    }

    // MARK: Music、Spotify

    private static func runningPlayers() -> [String] {
        ["com.apple.Music", "com.spotify.client"].filter {
            !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty
        }
    }

    /// 只看已经给过的自动化授权，不弹窗。
    private static func automationAllowed(_ id: String) -> Bool {
        var target = AEAddressDesc()
        let result = id.utf8CString.withUnsafeBufferPointer {
            AECreateDesc(DescType(typeApplicationBundleID), $0.baseAddress, $0.count - 1, &target)
        }
        guard result == noErr else { return false }
        defer { AEDisposeDesc(&target) }
        return AEDeterminePermissionToAutomateTarget(&target, typeWildCard, typeWildCard, false) == noErr
    }

    /// 固定脚本加参数：「在放才暂停」「停着才播放」，做了返回 done。不读歌名。
    private static func script(_ id: String, mode: String) -> String? {
        let source = #"""
        function run(argv) {
          var a = Application(argv[0]);
          if (!a.running()) return '';
          var s = String(a.playerState());
          if (argv[1] === 'pause' && s === 'playing') { a.pause(); return 'done'; }
          if (argv[1] === 'resume' && s === 'paused') { a.play(); return 'done'; }
          return '';
        }
        """#
        return run("/usr/bin/osascript", ["-l", "JavaScript", "-e", source, id, mode])
            .map { String(decoding: $0, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    /// 跑一个子进程，最多等 2.5 秒；没退出就结束它。退出码不是 0 返回 nil。
    private static func run(_ executable: String, _ arguments: [String]) -> Data? {
        let task = Process()
        let out = Pipe()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = arguments
        task.standardOutput = out
        task.standardError = FileHandle.nullDevice
        task.standardInput = FileHandle.nullDevice
        let finished = DispatchSemaphore(value: 0)
        task.terminationHandler = { _ in finished.signal() }
        do { try task.run() } catch { return nil }
        if finished.wait(timeout: .now() + 2.5) == .timedOut {
            task.terminate()
            return nil
        }
        guard task.terminationStatus == 0 else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        return data.count <= 64 * 1024 ? data : nil
    }
}

/// 「离开期间」那几行，在内存里等摘要来读；摘要说出去后清掉。
@MainActor final class PresenceAwayNotes {
    static let shared = PresenceAwayNotes()
    private(set) var log = PresenceAwayLog()
    /// 「离开期间」摘要（App/AwaySummaryController.swift）开着时挂在这里，记下就转一份。
    var onRecord: ((PresenceLock.AwayNote) -> Void)?
    func record(_ note: PresenceLock.AwayNote) {
        log.record(note)
        onRecord?(note)
    }
    func clear() { log.clear() }
    var lines: [String] { log.lines }
}

/// 离开就锁的 App 驱动：把睡眠、唤醒、锁屏、解锁和在场信号喂给 PresenceLock，再执行它要的事。
///
/// 默认关（`Presence.lock.enabled`）。关着时不挂任何通知、不排计时器。
/// 开着时全靠事件：只在 reducer 给出期限时排一次性计时器（倒数时每秒一次），没有期限就停。
/// 锁屏只走「锁定屏幕」；走回来从不自动解锁，解锁永远是系统自己的密码或 Touch ID。
@MainActor final class PresenceLockDriver {
    nonisolated static let defaultsKey = "Presence.lock.enabled"
    nonisolated static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: defaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: defaultsKey) }
    }
    /// 有没有能认出你手机的来源。这一版没有。
    nonisolated static var sourceAvailable: Bool { false }

    private weak var notch: NotchController?
    private let source: PresenceSource?
    private let readLockState: () -> SessionLockState
    private let lockScreen: () -> Bool
    private let tuckPrivate: @MainActor () -> Int
    private let foldDesktop: @MainActor () -> Bool
    private let media: PresenceMediaControl
    private let clock = WS2ContinuousClock()
    private var model = PresenceLock(bootID: UUID())
    private var glue = PresenceLockGlue()
    private var running = false
    private var timer: Timer?
    private var defaultsObserver: NSObjectProtocol?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var distributedObservers: [NSObjectProtocol] = []

    init(notch: NotchController?, source: PresenceSource? = nil,
         readLockState: @escaping () -> SessionLockState = { EffectSecurityBoundary.lockState },
         lockScreen: @escaping () -> Bool = PresenceScreenLock.lock,
         tuckPrivate: @escaping @MainActor () -> Int = PresencePrivateTuck.tuck,
         foldDesktop: @escaping @MainActor () -> Bool = PresenceLockFold.begin,
         media: PresenceMediaControl = PresenceMediaControl()) {
        self.notch = notch
        self.source = source
        self.readLockState = readLockState
        self.lockScreen = lockScreen
        self.tuckPrivate = tuckPrivate
        self.foldDesktop = foldDesktop
        self.media = media
        defaultsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification,
                                                                  object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refresh()
    }

    /// 读开关，按需开始或停下。
    func refresh() {
        let wanted = Self.isEnabled
        guard wanted != running else { return }
        if wanted { start() } else { stop() }
    }

    /// App 退出时调。
    func shutdown() {
        stop()
        if let defaultsObserver { NotificationCenter.default.removeObserver(defaultsObserver) }
        defaultsObserver = nil
    }

    // MARK: 开始、停下

    private func start() {
        running = true
        glue.reset()
        wlog("presence: leave-to-lock on, source \(source == nil ? "none" : "attached")")
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification,
                     NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            workspaceObservers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    switch name {
                    case NSWorkspace.willSleepNotification: self?.feed([.sleep])
                    case NSWorkspace.didWakeNotification: self?.feed([.wake])
                    default: self?.recheck(hint: nil) // 切换用户：重读，不猜
                    }
                }
            })
        }
        for (name, locked) in [("com.apple.screenIsLocked", true), ("com.apple.screenIsUnlocked", false)] {
            distributedObservers.append(DistributedNotificationCenter.default().addObserver(
                forName: .init(name), object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.recheck(hint: locked) }
                })
        }
        feed([.enable])
        recheck(hint: nil)
        source?.start(emit: { [weak self] events in self?.feed(events) })
        // windowshade://lock 只在开着时认。
        WS2URLHandler.shared.lockScreen = { [weak self] in self?.lockFromLink() }
    }

    private func stop() {
        guard running else { return }
        feed([.disable])
        running = false
        WS2URLHandler.shared.lockScreen = nil
        source?.stop()
        timer?.invalidate(); timer = nil
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        distributedObservers.forEach { DistributedNotificationCenter.default().removeObserver($0) }
        workspaceObservers = []; distributedObservers = []
        glue.reset()
        wlog("presence: leave-to-lock off")
    }

    // MARK: 喂 reducer

    private func recheck(hint: Bool?) {
        guard running else { return }
        let observed = readLockState()
        feed(PresenceLockGlue.lockEvents(observed: observed, hint: hint, phase: model.phase, reducer: model.lockState))
        // 通知和读数对不上：先记成未知，半秒后不带方向再读一次。
        if PresenceLockGlue.mismatch(observed: observed, hint: hint) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                MainActor.assumeIsolated { self?.recheck(hint: nil) }
            }
        }
    }

    private func feed(_ events: [PresenceLock.Event]) {
        guard running, !events.isEmpty else { return }
        var pending = events
        // 读锁态、锁屏失败、结束返回尝试会带出后续事件；最多再走几轮，不无限递归。
        for _ in 0 ..< 4 where !pending.isEmpty {
            let now = clock.now()
            let effects = model.handleBatch(pending, at: now)
            glue.track(phase: model.phase, at: now)
            pending = apply(glue.commands(for: effects))
        }
        schedule()
    }

    private func apply(_ commands: [PresenceLockGlue.Command]) -> [PresenceLock.Event] {
        var followUps: [PresenceLock.Event] = []
        for command in commands {
            switch command {
            case .show(let line):
                notch?.announceWhenFree(key: "presence.lock", text: line.text, detail: line.detail,
                                        symbol: line.symbol, priority: 10, ttl: 1.5)
            case .countdown(let line, let seconds, let speak):
                // 同一个 key、同一句主句：刘海还挂着上一秒时原位只换右边的数字，不排队、不重播进场。
                // 刘海不念；读屏只在开始、剩 5 秒、剩 3 秒各念一次（刘海关着也念）。
                notch?.announceWhenFree(key: "presence.lock", text: line.text, detail: line.detail,
                                        symbol: line.symbol, priority: 10, ttl: 1.5, hold: 1.5,
                                        ear: "\(seconds)", speaks: false)
                if let speak {
                    NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                                         userInfo: [.announcement: speak,
                                                    .priority: NSAccessibilityPriorityLevel.high.rawValue])
                }
            case .scheduleCommit(let token):
                DispatchQueue.main.async { [weak self] in
                    MainActor.assumeIsolated { self?.feed([.commitLock(token)]) }
                }
            case .tuckPrivate(let token):
                let count = tuckPrivate()
                wlog("presence: tucked \(count) private windows, token \(token.serial)")
            case .pauseMedia(let token):
                media.pause(token)
            case .resumeMedia(let token):
                media.resume(token)
            case .lock(let token):
                if foldDesktop() {
                    // 桌面正折进刘海：0.35 秒后再锁，回执期限（3 秒）留得下。
                    wlog("presence: folding the desktop, then locking, token \(token.serial)")
                    DispatchQueue.main.asyncAfter(deadline: .now() + PresenceLockGlue.foldLead) { [weak self] in
                        MainActor.assumeIsolated { self?.lockAfterFold(token) }
                    }
                } else if !lockNow(token) {
                    followUps.append(.lockFailed(token))
                }
            case .recheckLockState:
                followUps += PresenceLockGlue.lockEvents(observed: readLockState(), phase: model.phase,
                                                         reducer: model.lockState)
            case .restartSource:
                source?.restart()
            case .recordAway(let note):
                PresenceAwayNotes.shared.record(note)
                wlog("presence: away note recorded")
            case .finishReturn(let attempt):
                followUps.append(.returnAttemptFinished(attempt))
            case .log(let text):
                wlog("presence: \(text)")
            }
        }
        return followUps
    }

    /// 锁屏；失败时把这次暂停的歌续上（什么都没锁，不该让你的歌停着）。
    private func lockNow(_ token: WS2.Token) -> Bool {
        wlog("presence: locking the screen, token \(token.serial)")
        if lockScreen() { return true }
        media.resume(token)
        return false
    }

    /// 折完再锁：这 0.35 秒里被取消（碰了键盘、手机回来、关掉开关）就不锁。
    private func lockAfterFold(_ token: WS2.Token) {
        guard running, case .awaitingReceipt(let expected) = model.phase, expected == token else {
            // 没锁：这次暂停的歌续上（账本只认这个令牌，续过就忘）。
            media.resume(token)
            return
        }
        if !lockNow(token) { feed([.lockFailed(token)]) }
    }

    /// windowshade://lock：先收私人 App，再锁屏。不经过 reducer 的请求，所以锁上后只记成手动锁，
    /// 不留「自己锁的」归属：回来不会自动解锁，也不会替你续播。
    private func lockFromLink() {
        guard running else { return }
        let count = tuckPrivate()
        wlog("presence: lock from link, tucked \(count) private windows")
        if !lockScreen() { wlog("presence: lock from link failed") }
    }

    // MARK: 计时

    /// 只排一次性计时器；reducer 没有期限时不排。
    private func schedule() {
        timer?.invalidate(); timer = nil
        guard running, let delay = PresenceLockGlue.delay(until: model.nextWake, now: clock.now(),
                                                          phase: model.phase) else { return }
        let timer = Timer(timeInterval: max(0, delay), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.fire() }
        }
        timer.tolerance = min(0.1, max(0.02, delay * 0.1))
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func fire() {
        timer = nil
        guard running else { return }
        let phase = model.phase
        let idle: Double? = PresenceLockGlue.watchesInput(phase)
            ? CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
            : nil
        var events = glue.inputEvents(idleSeconds: idle, phase: phase, at: clock.now())
        if case .awaitingReceipt = phase {
            // 锁屏通知没来：到期前再读一次真实锁态。
            events += PresenceLockGlue.lockEvents(observed: readLockState(), phase: phase, reducer: model.lockState)
        }
        events.append(.tick)
        feed(events)
    }
}
