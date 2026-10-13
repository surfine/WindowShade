// 他从哪来：欢迎窗口第二步问“你之前常用哪个？”（Windows / iPad / 一直用 Mac，跳过就是没答），设置里随时能改。
// 卡住时刘海先认哪一套旧习惯，按这个定（规则表见 docs/stuck-habits.md）：答 Windows 开 Windows 那一半，答 iPad 开 iPad 那一半，
// 答“一直用 Mac”两边都不开，没答的只开几条不会误报的。
// 只存在 UserDefaults 里一个字符串；没答就是没有这个键（老用户升级后也是没答）。纯逻辑，不碰界面，可单测。

import Foundation

enum SwitcherOrigin: String, CaseIterable, Sendable {
    case windows
    case ipad
    case mac
    case unanswered

    static let defaultsKey = "SwitcherOrigin"
    /// 答案变了（欢迎窗口里点了、设置里改了、刘海问了之后他点了）。总在主线程发：订阅的都是界面（欢迎窗口、设置）。
    /// 在主线程改的，改完当场发；在别的线程改的（比如卡住判断跑在别处），排到主线程再发。
    /// userInfo 里 `previousKey` 是原来的 rawValue，新的直接读 `SwitcherOrigin.current`。
    static let didChangeNotification = Notification.Name("WindowShade.SwitcherOrigin.didChange")
    static let previousKey = "previous"

    /// 现在的答案，哪个线程都能读、能写。写入时和原来一样就什么都不做（不发通知）。
    static var current: SwitcherOrigin {
        get { stored(in: .standard) }
        set { store(newValue, in: .standard) }
    }

    /// 选项的顺序和欢迎窗口、设置里一样；没答不是一个选项。
    static let answers: [SwitcherOrigin] = [.windows, .ipad, .mac]

    /// 界面上的名字（欢迎窗口的三个选项、设置里的分段控件共用，一个东西只有一个名字）。没答没有名字。
    /// 这里是中文源句（语义身份，测试和路由都查它）；要显示的名字走 `titleText`。
    var title: String? {
        switch self {
        case .windows: return "Windows"
        case .ipad: return "iPad"
        case .mac: return "一直用 Mac"
        case .unanswered: return nil
        }
    }

    /// 按当前语言显示的名字（第31批）：欢迎窗口的选项、设置里的分段、刘海问来处都用它。
    /// 逐 case 写字面量键，检查器才查得到（动态拼键会变成没人引用的孤儿键）。
    var titleText: String? {
        switch self {
        case .windows: return WSL10n.text("origin.windows", zh: "Windows")
        case .ipad: return WSL10n.text("origin.ipad", zh: "iPad")
        case .mac: return WSL10n.text("origin.mac", zh: "一直用 Mac")
        case .unanswered: return nil
        }
    }

    var isAnswered: Bool { self != .unanswered }

    /// 没存过、存了认不出的值（以后删掉的选项、手改坏的偏好）都当没答。
    static func stored(in defaults: UserDefaults) -> SwitcherOrigin {
        defaults.string(forKey: defaultsKey).flatMap(SwitcherOrigin.init(rawValue:)).flatMap { $0.isAnswered ? $0 : nil } ?? .unanswered
    }

    /// 存下答案：没答就删掉这个键。和原来一样时不写、不发通知；变了才在主线程发 `didChangeNotification`。返回变没变。
    @discardableResult
    static func store(_ origin: SwitcherOrigin, in defaults: UserDefaults,
                      center: NotificationCenter = .default) -> Bool {
        let previous = stored(in: defaults)
        guard origin != previous else { return false }
        if origin.isAnswered {
            defaults.set(origin.rawValue, forKey: defaultsKey)
        } else {
            defaults.removeObject(forKey: defaultsKey)
        }
        let info = [previousKey: previous.rawValue]
        if Thread.isMainThread {
            center.post(name: didChangeNotification, object: nil, userInfo: info)
        } else {
            DispatchQueue.main.async { center.post(name: didChangeNotification, object: nil, userInfo: info) }
        }
        return true
    }
}

// MARK: - 没答来处时的推断询问（默认关）

/// 没答来处的人，按了别系统的习惯键两次，刘海问一次“之前常用 Windows？”。只数键位的来处，不记打的字、不记哪个 App。
/// 识别期间不教任何东西；每个来处只问一次；点小叉等于不再问（两个来处一起）。纯逻辑，可单测；存取放在 UserDefaults 一个键里。
struct OriginGuess: Codable, Equatable, Sendable {
    static let defaultsKey = "Notch.originGuess"
    /// 开关，默认关（没有这个键就是关）。
    static let enabledKey = "Notch.originGuess.enabled"
    /// 同一来处识别到这么多次才问。
    static let threshold = 2
    /// 两次识别至少隔这么久（秒）：连按两下 ⌃C 只算一次。
    static let minGap: TimeInterval = 10

    var counts: [String: Int] = [:]
    var lastAt: [String: TimeInterval] = [:]
    /// 已经问过的来处（rawValue）。
    var asked: Set<String> = []
    /// 点过小叉：整个不再问。
    var declined = false

    /// 只有 Windows、iPad 有得问。
    static func isGuessable(_ origin: SwitcherOrigin) -> Bool { origin == .windows || origin == .ipad }

    /// 这个来处还值得继续听（没问过、没被拒绝）。
    func listens(for origin: SwitcherOrigin) -> Bool {
        Self.isGuessable(origin) && !declined && !asked.contains(origin.rawValue)
    }

    /// 识别到一次这个来处的习惯。返回 true 表示现在该问了（次数够了、没问过、没拒绝）。
    /// 问不出去（刘海正忙）时次数留着，下一次识别到再试。
    mutating func note(_ origin: SwitcherOrigin, at now: TimeInterval) -> Bool {
        guard listens(for: origin) else { return false }
        let key = origin.rawValue
        if let last = lastAt[key], now >= last, now - last < Self.minGap { return (counts[key] ?? 0) >= Self.threshold }
        lastAt[key] = now
        counts[key, default: 0] += 1
        return counts[key, default: 0] >= Self.threshold
    }

    /// 问出去了：这个来处不再问。
    mutating func didAsk(_ origin: SwitcherOrigin) { asked.insert(origin.rawValue) }

    /// 点了小叉：不再问。
    mutating func decline() { declined = true }

    // MARK: 存取

    static func load(from defaults: UserDefaults) -> OriginGuess {
        defaults.data(forKey: defaultsKey).flatMap { try? JSONDecoder().decode(OriginGuess.self, from: $0) } ?? OriginGuess()
    }

    func save(to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    static func isEnabled(in defaults: UserDefaults) -> Bool { defaults.bool(forKey: enabledKey) }
}
