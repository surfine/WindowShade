import AppIntents
import AppKit

// 规格 N1（已定案：最小切口，5–8 个）：把最常用的 8 个动作交给系统，捷径、Spotlight、Siri 就都能用，不自造 CLI 或 URL scheme。
// 每个动作直接调菜单与全局快捷键用的同一个 action，行为和按快捷键完全一样；名字照固定词汇表、和快捷键设置里那一行一致。
// 标题走单独的 AppIntents 表（Resources/AppIntents.xcstrings，编进包根的 .lproj）：系统在别的进程里读它，
// 找不到 WindowShade 自己放在 Resources/Localization 下的译文。

@MainActor
private func windowShade() throws -> AppDelegate {
    guard let delegate = NSApp.delegate as? AppDelegate else { throw WindowShadeIntentError.notRunning }
    return delegate
}

enum WindowShadeIntentError: Error, CustomLocalizedStringResourceConvertible {
    case notRunning
    case presenceLockOff
    case presenceLockNoDevice
    case presenceLockBusy
    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notRunning: LocalizedStringResource("intent.error.notRunning", table: "AppIntents")
        case .presenceLockOff: LocalizedStringResource("intent.error.presenceLockOff", table: "AppIntents")
        case .presenceLockNoDevice: LocalizedStringResource("intent.error.presenceLockNoDevice", table: "AppIntents")
        case .presenceLockBusy: LocalizedStringResource("intent.error.presenceLockBusy", table: "AppIntents")
        }
    }
}

struct ToggleShadeIntent: AppIntent {
    static let title = LocalizedStringResource("intent.toggleShade.title", table: "AppIntents")
    static let description = IntentDescription(LocalizedStringResource("intent.toggleShade.description", table: "AppIntents"))
    @MainActor func perform() async throws -> some IntentResult { try windowShade().toggleAction(); return .result() }
}

struct UnrollAllIntent: AppIntent {
    static let title = LocalizedStringResource("intent.unrollAll.title", table: "AppIntents")
    static let description = IntentDescription(LocalizedStringResource("intent.unrollAll.description", table: "AppIntents"))
    @MainActor func perform() async throws -> some IntentResult { try windowShade().restoreAll(); return .result() }
}

struct TuckAllIntent: AppIntent {
    static let title = LocalizedStringResource("intent.tuckAll.title", table: "AppIntents")
    static let description = IntentDescription(LocalizedStringResource("intent.tuckAll.description", table: "AppIntents"))
    @MainActor func perform() async throws -> some IntentResult { try windowShade().tuckAllAction(); return .result() }
}

struct ChooseWindowIntent: AppIntent {
    static let title = LocalizedStringResource("intent.chooseWindow.title", table: "AppIntents")
    static let description = IntentDescription(LocalizedStringResource("intent.chooseWindow.description", table: "AppIntents"))
    @MainActor func perform() async throws -> some IntentResult { try windowShade().openWindowBrowserPanel(); return .result() }
}

struct TogglePinIntent: AppIntent {
    static let title = LocalizedStringResource("intent.togglePin.title", table: "AppIntents")
    static let description = IntentDescription(LocalizedStringResource("intent.togglePin.description", table: "AppIntents"))
    @MainActor func perform() async throws -> some IntentResult { try windowShade().togglePinnedPreviewAction(); return .result() }
}

struct SuspendPinsIntent: AppIntent {
    static let title = LocalizedStringResource("intent.suspendPins.title", table: "AppIntents")
    static let description = IntentDescription(LocalizedStringResource("intent.suspendPins.description", table: "AppIntents"))
    @MainActor func perform() async throws -> some IntentResult { try windowShade().toggleSuspendPinnedPreviewsAction(); return .result() }
}

struct OpenLaunchpadIntent: AppIntent {
    static let title = LocalizedStringResource("intent.openLaunchpad.title", table: "AppIntents")
    static let description = IntentDescription(LocalizedStringResource("intent.openLaunchpad.description", table: "AppIntents"))
    @MainActor func perform() async throws -> some IntentResult { try windowShade().toggleLaunchpadAction(); return .result() }
}

/// 锁屏前先把私人 App 收进刘海（WS2 离开就锁的「手动锁一次」）。
/// 只锁屏，不解锁，也不留下「自己锁的」归属；「离开就锁」默认关，没开就告诉用户去打开。
struct LockScreenIntent: AppIntent {
    static let title = LocalizedStringResource("intent.lock.title", table: "AppIntents")
    static let description = IntentDescription(LocalizedStringResource("intent.lock.description", table: "AppIntents"))
    static let openAppWhenRun = true

    @MainActor func perform() async throws -> some IntentResult {
        if !PresenceLockDriver.isEnabled { throw WindowShadeIntentError.presenceLockOff }
        if !PresenceLockDriver.sourceAvailable { throw WindowShadeIntentError.presenceLockNoDevice }
        switch WS2LockIntentBridge.shared.requestLock() {
        case .locked: return .result()
        case .notAvailable: throw WindowShadeIntentError.presenceLockOff
        case .rejected: throw WindowShadeIntentError.presenceLockBusy
        }
    }
}
