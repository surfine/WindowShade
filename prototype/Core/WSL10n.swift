// 刘海文案的本地化入口（R19）。简体中文是源语言，英文译文在 prototype/Resources/Localizable.xcstrings。
// 默认只出中文：语言开关关着时 text(...) 原样返回 Swift 里写的中文，所以现有输出逐字不变。
// 进程语言由 InterfaceLanguage 在启动时与用户切换时显式设置（第27批）；这里不读任何用户设置、
// 不轮询，也不接受 macOS 给的 .lproj 选择。
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
    /// 带占位符的源句必须带 args：zh 一路也做替换，免得“%@的说明”原样漏给读屏。
    static func text(_ key: String, zh: String, _ args: CVarArg...) -> String {
        let template: String
        switch (language, englishBundle) {
        case (.en, .some(let bundle)):
            template = bundle.localizedString(forKey: key, value: zh, table: "Localizable")
        default:
            template = zh
        }
        guard template != zh, !args.isEmpty else {
            guard !args.isEmpty else { return template }
            return String(format: zh, arguments: args)
        }
        return String(format: template, arguments: args)
    }

    /// 设置行的文案对（第27批）：key 是目录键，zh 是中文源句——它是这一行的**语义身份**，
    /// 图标与短副标题的路由都以 zh 查表，显示才走 .shown 出当前语言。
    /// 迁移后中文时 .shown 与 zh 逐字节相同。
    static func setting(_ key: String, zh: String) -> SettingsText {
        SettingsText(key: key, zh: zh)
    }

    /// 带占位符的设置行（如"由 %@ 接管"）：zh 仍是语义身份，.shown 按当前语言替换 args。
    static func setting(_ key: String, zh: String, _ args: CVarArg...) -> SettingsText {
        SettingsText(key: key, zh: zh, formatArgs: args)
    }
}

/// 见 `WSL10n.setting(_:zh:)`：zh 是稳定身份，shown 是当前语言的显示文本。
struct SettingsText: Equatable {
    let key: String
    let zh: String
    var formatArgs: [CVarArg] = []
    var shown: String {
        let template = WSL10n.text(key, zh: zh)
        guard !formatArgs.isEmpty else { return template }
        return String(format: template, arguments: formatArgs)
    }

    /// 身份是 key + zh 源句；格式化参数不影响"这是哪一行"。
    static func == (lhs: SettingsText, rhs: SettingsText) -> Bool {
        lhs.key == rhs.key && lhs.zh == rhs.zh
    }
}
