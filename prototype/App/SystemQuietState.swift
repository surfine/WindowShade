// 系统此刻要不要更安静：屏幕正被共享或录制（sharing），或系统专注模式开着（focused）。
// 读不到、没授权都是 unknown，一律当作没有（更不安静的那一边不会被猜出来）。
//
// - sharing：CGSIsScreenWatcherPresent / SLSIsScreenWatcherPresent，私有符号，dlsym 找，找不到为 unknown（隐私登记第三层）。
//   为 sharing 时：卡住提示一句不说（HabitGate）；刘海那一排里私人 App 的格子只剩 App 图标（NotchController.tiles）。
// - focused：INFocusStatusCenter.default.focusStatus.isFocused，要用户授权；授权请求只在用户打开相关设置时发起
//   （requestFocusAuthorization），启动时不弹窗，没授权为 unknown。
//   为 focused 时：第 4 层短暂提醒只留次区域的点，不开口；第 1 层放行照常问（InteractionCoordinator）。
//
// 不轮询：只在启动、App 激活、App 启动或退出、锁屏或解锁、换桌面时重算一次，状态变了才发 didChange。
// 默认开，因为它只会让刘海更安静；它不放行、不解锁任何东西。
import Foundation
#if canImport(AppKit)
import AppKit
#endif
#if canImport(Intents)
import Intents
#endif

/// 一项读数：有、没有、读不到。读不到当作没有。
enum QuietReading: Equatable, Sendable {
    case yes, no, unknown
    var isYes: Bool { self == .yes }
}

/// 两项读数合起来该怎么安静。纯值，真值表见 tests/SystemQuietStateTests.swift。
struct SystemQuiet: Equatable, Sendable {
    var sharing: QuietReading = .unknown
    var focused: QuietReading = .unknown

    static let none = SystemQuiet()

    /// 屏幕正被共享或录制。
    var isSharing: Bool { sharing.isYes }
    /// 系统专注模式开着。
    var isFocused: Bool { focused.isYes }
    /// 卡住提示一句不说。
    var silencesStuckHints: Bool { isSharing }
    /// 私人 App 的格子只显示 App 图标。
    var redactsPrivateTiles: Bool { isSharing }
    /// 短暂提醒（第 4 层）只留次区域的点。放行（第 1 层）不受影响。
    var alertsLeaveDotOnly: Bool { isFocused }
}

/// 把探针的结果合成读数。探针返回 nil 表示读不到。
enum SystemQuietReader {
    static func reading(_ probe: () -> Bool?) -> QuietReading {
        switch probe() {
        case .some(true): return .yes
        case .some(false): return .no
        case .none: return .unknown
        }
    }

    static func evaluate(sharing: () -> Bool?, focused: () -> Bool?) -> SystemQuiet {
        SystemQuiet(sharing: reading(sharing), focused: reading(focused))
    }
}

#if canImport(AppKit)
@MainActor
final class SystemQuietState {
    static let shared = SystemQuietState()
    static let didChange = Notification.Name("WindowShade.SystemQuietState.didChange")

    private var current = SystemQuiet.none
    private var started = false
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    private let sharingProbe: @MainActor () -> Bool?
    private let focusProbe: @MainActor () -> Bool?

    init(sharingProbe: @escaping @MainActor () -> Bool? = SystemQuietState.screenWatcherPresent,
         focusProbe: @escaping @MainActor () -> Bool? = SystemQuietState.focusIsOn) {
        self.sharingProbe = sharingProbe
        self.focusProbe = focusProbe
    }

    /// 当前状态。第一次问到时才开始听通知。
    var state: SystemQuiet {
        startIfNeeded()
        return current
    }

    func startIfNeeded() {
        guard !started else { return }
        started = true
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        let names: [(NotificationCenter, Notification.Name)] = [
            (workspace, NSWorkspace.didActivateApplicationNotification),
            (workspace, NSWorkspace.didLaunchApplicationNotification),
            (workspace, NSWorkspace.didTerminateApplicationNotification),
            (workspace, NSWorkspace.activeSpaceDidChangeNotification),
            (distributed, Notification.Name("com.apple.screenIsLocked")),
            (distributed, Notification.Name("com.apple.screenIsUnlocked")),
        ]
        for (center, name) in names {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
            observers.append((center, token))
        }
        recompute()
    }

    func stop() {
        for item in observers { item.center.removeObserver(item.token) }
        observers = []
        started = false
    }

    /// 重算一次；变了才通知。
    @discardableResult
    func recompute() -> SystemQuiet {
        let next = SystemQuietReader.evaluate(sharing: { sharingProbe() }, focused: { focusProbe() })
        guard next != current else { return current }
        current = next
        NotificationCenter.default.post(name: Self.didChange, object: nil)
        return next
    }

    private func refresh() { recompute() }

    /// 设置里“专注模式时更安静”。默认关；关着时不读专注模式，也不会弹授权。
    nonisolated static let focusQuietKey = "Quiet.focusStatus"
    nonisolated static var focusQuietEnabled: Bool {
        UserDefaults.standard.bool(forKey: focusQuietKey)
    }

    /// 设置页拨开关：打开才去请求授权（系统弹窗只会在这时出现），关掉就不再读。
    func setFocusQuiet(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: Self.focusQuietKey)
        if on { requestFocusAuthorization() } else { refresh() }
    }

    /// 用户在设置里打开“专注模式时更安静”之类的开关时才调用；启动时不要调。
    func requestFocusAuthorization() {
        #if canImport(Intents)
        INFocusStatusCenter.default.requestAuthorization { [weak self] _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.refresh() } }
        }
        #endif
    }

    // MARK: 探针

    private typealias WatcherFunction = @convention(c) () -> UInt8
    private static let watcherFunction: WatcherFunction? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY) else { return nil }
        for name in ["CGSIsScreenWatcherPresent", "SLSIsScreenWatcherPresent"] {
            if let symbol = dlsym(handle, name) { return unsafeBitCast(symbol, to: WatcherFunction.self) }
        }
        return nil
    }()

    /// 有没有程序在看着屏幕（共享、录屏）。找不到符号为 nil。
    static func screenWatcherPresent() -> Bool? {
        guard let function = watcherFunction else { return nil }
        return function() != 0
    }

    /// 系统专注模式开着吗。没授权、读不到为 nil。
    static func focusIsOn() -> Bool? {
        #if canImport(Intents)
        guard focusQuietEnabled else { return nil }
        let center = INFocusStatusCenter.default
        guard center.authorizationStatus == .authorized else { return nil }
        return center.focusStatus.isFocused
        #else
        return nil
        #endif
    }
}
#endif
