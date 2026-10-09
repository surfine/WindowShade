import Foundation

/// 启动时把掉到屏幕外的窗口放回来之后，刘海上说的那一句。放回 0 扇窗口不说话。纯逻辑。
enum RescueAnnounce {
    static let detail = "上次意外退出了"

    static func line(restored count: Int) -> NotchSentence.Line? {
        guard count > 0 else { return nil }
        return NotchSentence.compose(headline: "已放回\(count)扇窗口", detail: detail)
    }
}
