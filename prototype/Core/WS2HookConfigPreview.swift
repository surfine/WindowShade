import Foundation

/// hook 配置只做预览和旧值比较。这个类型不写用户目录，也不把预览当成已经允许。
struct WS2HookConfigPreview: Equatable, Sendable {
    enum Decision: Equatable, Sendable {
        case unchanged
        case wouldReplace
        case refuseWrite
    }

    /// 写用户 home 必须另一次明确同意。这里永远是关。
    static let writesUserHome = false

    static func compare(current: String?, proposed: String?) -> Decision {
        guard writesUserHome == false else { return .refuseWrite }
        guard let proposed else { return .refuseWrite }
        if current == proposed { return .unchanged }
        return .wouldReplace
    }
}
