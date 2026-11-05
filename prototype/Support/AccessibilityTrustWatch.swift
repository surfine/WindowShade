// 等辅助功能授权的统一入口：系统在授权或撤销时发 com.apple.accessibility.api（同一条
// NotchLevelObserver 早已在用），收到就马上查一次，并在 0.5、2 秒各补查一次——通知可能比
// 信任状态真正生效早一点点。从系统设置切回本 App 时也查一次（授权完回来的那一下）。
// 万一通知没来也不会漏：5 秒一次的兜底（容差 1.5 秒），授权后最迟几秒生效，和原来手感差不多。
// 原来三处各自 1–3 秒轮询，未授权的整段时间都在空转。
// check 返回 true 表示已经办完，自动停掉；返回 false 继续等。

import Cocoa

@MainActor final class AccessibilityTrustWatch {
    static let notification = Notification.Name("com.apple.accessibility.api")
    static let fallbackInterval: TimeInterval = 5
    static let recheckDelays: [TimeInterval] = [0.5, 2]

    private let check: @MainActor () -> Bool
    private var observer: NSObjectProtocol?
    private var activeObserver: NSObjectProtocol?
    private var timer: Timer?
    private var rechecks: [DispatchWorkItem] = []

    var isRunning: Bool { observer != nil }

    init(check: @escaping @MainActor () -> Bool) {
        self.check = check
    }

    func start() {
        guard observer == nil else { return }
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Self.notification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.notified() }
        }
        activeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.notified() }
        }
        // 计时器回调里不 assumeIsolated：TrackpadGestures 记过的 macOS 27 随机崩，跳一次主 actor 更稳。
        let next = Timer.scheduledTimer(withTimeInterval: Self.fallbackInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.fire() }
        }
        next.tolerance = 1.5
        timer = next
    }

    func stop() {
        if let observer { DistributedNotificationCenter.default().removeObserver(observer) }
        observer = nil
        if let activeObserver { NotificationCenter.default.removeObserver(activeObserver) }
        activeObserver = nil
        timer?.invalidate()
        timer = nil
        rechecks.forEach { $0.cancel() }
        rechecks.removeAll()
    }

    private func fire() {
        guard isRunning else { return }
        if check() { stop() }
    }

    private func notified() {
        fire()
        guard isRunning else { return }
        rechecks.forEach { $0.cancel() }
        rechecks = Self.recheckDelays.map { delay in
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated { self?.fire() }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
            return work
        }
    }
}
