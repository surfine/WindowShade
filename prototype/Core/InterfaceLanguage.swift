// 界面语言的选择与生效（第27批；繁体第39批）。
// 沿用 WSL10n 入口：这里只决定"用哪种语言"，文案查找仍在 WSL10n.text；不另造翻译系统。
//
// 规则：
//   - 默认跟随系统：首选语言按文字系统分流——zh-Hant / zh-TW / zh-HK / zh-MO 用繁体，
//     其余 zh*（zh、zh-Hans、zh-CN…）用简体，非中文用英文。
//   - 用户在设置里可覆盖成 跟随系统 / 简体中文 / 繁體中文 / English，存偏好一个键。
//   - 切换立即生效：写偏好 → 设 WSL10n.language → 主线程发 didChangeNotification，
//     由已显示的界面显式重建（DuoSettingsWindow、状态菜单等各自的观察者）。
//
// 边界：读取只发生在显式调用点（启动、设置里改语言、开关行读当前值），不藏在静态 copy
// 初始化里；QA 夹具直接设 WSL10n.language，不经过这里、不写偏好、不读标准域。
import Foundation

enum InterfaceLanguagePreference: String, CaseIterable, Sendable {
    case system
    case zh
    case zhHant
    case en

    /// 存偏好的键。没这个键（或存坏）就是跟随系统。
    static let defaultsKey = "WindowShade.InterfaceLanguage"

    /// 语言变了（设置里改了、或跟随系统下重新解析）。总在主线程发；订阅者是已显示的界面。
    static let didChangeNotification = Notification.Name("WindowShade.InterfaceLanguage.didChange")

    /// 纯解析：偏好明确就照它；跟随系统按首选语言的文字系统分流。
    static func resolve(_ preference: InterfaceLanguagePreference,
                        systemPreferred: [String]) -> WSLanguage {
        switch preference {
        case .zh: return .zh
        case .zhHant: return .zhHant
        case .en: return .en
        case .system:
            let first = systemPreferred.first?.lowercased() ?? ""
            return language(forSystemTag: first)
        }
    }

    /// 系统语言标签 → 文案语言。繁体地区（台湾、香港、澳门）与带 Hant 的标签都算繁体。
    static func language(forSystemTag tag: String) -> WSLanguage {
        guard tag.hasPrefix("zh") else { return .en }
        if tag.contains("-hant") || tag.contains("-tw") || tag.contains("-hk") || tag.contains("-mo") {
            return .zhHant
        }
        return .zh
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
