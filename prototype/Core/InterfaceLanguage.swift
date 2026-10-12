// 界面语言的选择与生效（第27批）。沿用 WSL10n 入口：这里只决定"用哪种语言"，
// 文案查找仍在 WSL10n.text；不另造翻译系统。
//
// 规则（验收契约 english-support-acceptance.md 第27批定案）：
//   - 默认跟随系统：首选语言以 zh 开头（zh、zh-Hans、zh-Hant 都算）用中文，否则用英文。
//   - 用户在设置里可覆盖成 跟随系统 / 简体中文 / English，存 UserDefaults 一个键。
//   - 切换立即生效：写偏好 → 设 WSL10n.language → 主线程发 didChangeNotification，
//     由已显示的界面显式重建（DuoSettingsWindow、状态菜单等各自的观察者）。
//
// 边界：读取只发生在显式调用点（启动、设置里改语言、开关行读当前值），不藏在静态 copy
// 初始化里；QA 夹具直接设 WSL10n.language，不经过这里、不写偏好、不读标准域。
import Foundation

enum InterfaceLanguagePreference: String, CaseIterable, Sendable {
    case system
    case zh
    case en

    /// 存偏好的键。没这个键（或存坏）就是跟随系统。
    static let defaultsKey = "WindowShade.InterfaceLanguage"

    /// 语言变了（设置里改了、或跟随系统下重新解析）。总在主线程发；订阅者是已显示的界面。
    static let didChangeNotification = Notification.Name("WindowShade.InterfaceLanguage.didChange")

    /// 纯解析：偏好明确就照它；跟随系统看首选语言是不是中文，不是就用英文。
    /// 扩展点（2026-10-12 用户定案「繁体留架构余地」）：将来加 zh-Hant 时，把下面
    /// "zh 开头即中文"拆成按文字系统判定（zh-Hant/zh-TW/zh-HK → 繁体，其余 zh* → 简体），
    /// WSLanguage 与设置里的语言行各加一项，目录补译文；现在不要预做。
    static func resolve(_ preference: InterfaceLanguagePreference,
                        systemPreferred: [String]) -> WSLanguage {
        switch preference {
        case .zh: return .zh
        case .en: return .en
        case .system:
            let first = systemPreferred.first?.lowercased() ?? ""
            return first.hasPrefix("zh") ? .zh : .en
        }
    }

    static func resolve(_ preference: InterfaceLanguagePreference) -> WSLanguage {
        resolve(preference, systemPreferred: Locale.preferredLanguages)
    }

    /// 存过的偏好；没存过、存了认不出的值都按跟随系统。
    static func stored(in defaults: UserDefaults) -> InterfaceLanguagePreference {
        defaults.string(forKey: defaultsKey)
            .flatMap(InterfaceLanguagePreference.init(rawValue:)) ?? .system
    }

    /// 只由 main.swift 在产品启动时调用一次：读偏好 + 系统首选语言，定下进程语言。
    /// 不是产品的入口（QA 夹具、测试）不要调用这里。
    static func applyAtLaunch(defaults: UserDefaults = .standard) {
        WSL10n.language = resolve(stored(in: defaults))
    }

    /// 设置里改了语言：写偏好（跟随系统=删键）→ 立即生效 → 通知已显示的界面重建。
    /// QA 夹具不调用这里。
    static func set(_ preference: InterfaceLanguagePreference, in defaults: UserDefaults = .standard) {
        if preference == .system {
            defaults.removeObject(forKey: defaultsKey)
        } else {
            defaults.set(preference.rawValue, forKey: defaultsKey)
        }
        WSL10n.language = resolve(preference)
        if Thread.isMainThread {
            NotificationCenter.default.post(name: didChangeNotification, object: nil)
        } else {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: didChangeNotification, object: nil)
            }
        }
    }
}
