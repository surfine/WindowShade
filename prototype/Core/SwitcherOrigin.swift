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
    var title: String? {
        switch self {
        case .windows: return "Windows"
        case .ipad: return "iPad"
        case .mac: return "一直用 Mac"
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
