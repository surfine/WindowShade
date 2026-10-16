import AppIntents
import AppKit

// 规格 N1（已定案：最小切口）：把最常用的 7 个动作交给系统，捷径、Spotlight、Siri 就都能用，不自造 CLI 或 URL scheme。
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
    var localizedStringResource: LocalizedStringResource {
        LocalizedStringResource("intent.error.notRunning", table: "AppIntents")
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
