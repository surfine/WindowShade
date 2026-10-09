// 离开期间摘要的 App 一侧（纯逻辑在 Core/AwaySummary.swift）。
//
// 默认关（`Notch.awaySummary.enabled`）。关着时不挂任何通知、不记任何事。
// 开着时全靠事件：锁屏或屏幕睡眠开始记账，解锁或唤醒后等一秒、问一次系统锁态再收账；
// 没有轮询，计时器只在回来那一刻排一次、用完即停。
// 只说不解锁：摘要里的点一下只是展开已有的一排或放回窗口，从不碰系统锁屏和授权。
import Cocoa

@MainActor final class AwaySummaryController {
    nonisolated static let enabledKey = "Notch.awaySummary.enabled"
    nonisolated static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    // MARK: 现状（由刘海和设备电量接上）

    var tuckedCount: () -> Int = { 0 }
    var windowIsCurrent: (UInt32) -> Bool = { _ in false }
    var deviceIsCurrent: (_ deviceID: String, _ part: String?) -> Bool = { _, _ in false }
    /// 把摘要说到刘海上。
    var present: (AwaySummary.Summary) -> Void = { _ in }
    var isUnlocked: () -> Bool = { EffectSecurityBoundary.lockState == .unlocked }
    var now: () -> Double = { Date().timeIntervalSince1970 }

    private var log = AwayLog()
    /// 最近一次交给刘海的摘要，只在内存里：「离开期间」静默指令读它；下一次离开开始、或功能关掉就清。
    private(set) var lastSummary: AwaySummary.Summary?
    private var running = false
    private var settle: Timer?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var distributedObservers: [NSObjectProtocol] = []
    private var defaultsObserver: NSObjectProtocol?

    /// 静默指令读出来的那一句；没有就是「没有」。
    var readout: AwaySummary.Summary? { lastSummary }

    init() {
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refresh()
    }

    /// 读开关，按需开始或停下。
    func refresh() {
        let wanted = Self.isEnabled
        guard wanted != running else { return }
        wanted ? start() : stop()
    }

    private func start() {
        running = true
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            workspaceObservers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.beginAway() }
            })
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            workspaceObservers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleSettle() }
            })
        }
        let distributed = DistributedNotificationCenter.default()
        distributedObservers.append(distributed.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.beginAway() }
        })
        distributedObservers.append(distributed.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleSettle() }
        })
        PresenceAwayNotes.shared.onRecord = { [weak self] note in self?.noteIntrusion(note.line) }
        // 已经锁着时打开的开关：从现在算起，不追溯。
        if !isUnlocked() { beginAway() }
        wlog("away: summary on")
    }

    private func stop() {
        running = false
        let workspace = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach { workspace.removeObserver($0) }
        workspaceObservers.removeAll()
        distributedObservers.forEach { DistributedNotificationCenter.default().removeObserver($0) }
        distributedObservers.removeAll()
        PresenceAwayNotes.shared.onRecord = nil
        settle?.invalidate(); settle = nil
        log.clear()
        lastSummary = nil
        wlog("away: summary off")
    }

    // MARK: 记账（来源在离开期间调；不在离开期间时账本不收）

    func noteIntrusion(_ text: String) { log.noteIntrusion(text, at: now()) }

    func noteLowBattery(deviceID: String, name: String, part: String?, percent: Int) {
        log.noteLowBattery(deviceID: deviceID, name: name, part: part, percent: percent, at: now())
    }

    func noteWindowChange(id: UInt32, app: String) { log.noteWindowChange(id: id, app: app, at: now()) }

    func noteDownloads(_ names: [String]) { log.noteDownloads(names, at: now()) }

    // MARK: 区间

    private func beginAway() {
        guard running else { return }
        if !log.isAway { lastSummary = nil }
        log.begin(at: now())
        settle?.invalidate(); settle = nil
    }

    /// 解锁或唤醒：等一秒让晚到的记录赶上，再问系统锁态。连续几个通知合成一次。
    private func scheduleSettle() {
        guard running, log.isAway else { return }
        settle?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: AwaySummary.settleSeconds, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.finish() }
        }
        timer.tolerance = 0.3
        settle = timer
    }

    private func finish() {
        settle = nil
        let reality = AwayLog.Reality(tuckedCount: tuckedCount(), windowIsCurrent: windowIsCurrent,
                                      deviceIsCurrent: deviceIsCurrent)
        switch log.finish(unlocked: isUnlocked(), at: now(), reality: reality) {
        case .stillAway:
            return
        case .nothing:
            PresenceAwayNotes.shared.clear()
        case .summary(let summary):
            PresenceAwayNotes.shared.clear()
            lastSummary = summary
            present(summary)
            wlog("away: summary shown, \(summary.count) item(s)")
        }
    }
}
