// 刘海文案的本地化入口（R19）。简体中文是源语言，英文译文在 prototype/Resources/Localizable.xcstrings。
// 默认只出中文：语言开关关着时 text(...) 原样返回 Swift 里写的中文，所以现有输出逐字不变。
// 打开英文只能由代码显式设置（下一轮界面接上设置后再开）；没有轮询，也不读任何用户设置。
// 译文随 App 编成 Contents/Resources/Localization/en.lproj（build.sh 用 xcstringstool 生成），
// 不放在 App 根目录的 .lproj 里，免得改变系统给这个 App 选的界面语言。
import Foundation

enum WSLanguage: Sendable, Equatable { case zh, en }

private final class WSL10nState: @unchecked Sendable {
    private let lock = NSLock()
    private var languageValue: WSLanguage = .zh
    private var bundleValue: Bundle?
    private var bundleResolved = false

    var language: WSLanguage {
        get { lock.lock(); defer { lock.unlock() }; return languageValue }
        set { lock.lock(); languageValue = newValue; lock.unlock() }
    }

    /// 英文译文所在的目录；没设过就去 App 资源里找一次。
    var englishBundle: Bundle? {
        get {
            lock.lock(); defer { lock.unlock() }
            if !bundleResolved {
                bundleResolved = true
                if let url = Bundle.main.resourceURL?.appendingPathComponent("Localization/en.lproj", isDirectory: true),
                   FileManager.default.fileExists(atPath: url.path) {
                    bundleValue = Bundle(url: url)
                }
            }
            return bundleValue
        }
        set { lock.lock(); bundleValue = newValue; bundleResolved = true; lock.unlock() }
    }
}

enum WSL10n {
    private static let state = WSL10nState()

    /// 当前文案语言。默认中文。
    static var language: WSLanguage {
        get { state.language }
        set { state.language = newValue }
    }

    /// 测试和打包检查用：指定英文译文目录。
    static var englishBundle: Bundle? {
        get { state.englishBundle }
        set { state.englishBundle = newValue }
    }

    /// key 对应的一句。zh 是 Swift 里写的中文源句（文案检查查的就是它），中文时原样返回；
    /// 英文时取译文，译文里的 %@ 按顺序换成 args；缺译文就退回中文，不出空句。
    static func text(_ key: String, zh: String, _ args: CVarArg...) -> String {
        guard language == .en, let bundle = englishBundle else { return zh }
        let template = bundle.localizedString(forKey: key, value: zh, table: "Localizable")
        guard template != zh, !args.isEmpty else { return template }
        return String(format: template, arguments: args)
    }
}
