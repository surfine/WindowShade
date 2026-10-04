import Foundation

/// 这三项能不能装监听。装不装由调用方再决定；这里只回答资格。
enum InputFeatureGate: Sendable {
    /// 中键标题栏手势：开关打开才允许装钩子（I4 / D05）。暂停时也不装。
    static func middleDragMayInstall(switchOn: Bool, paused: Bool = false) -> Bool {
        switchOn && !paused
    }

    static func scrollMayInstall(decisionInstalls: Bool, paused: Bool) -> Bool {
        decisionInstalls && !paused
    }

    /// 没有核对记录，或者记录不许可，都不算能读多触点。
    static func touchMayInstall(qualification: MultitouchQualification?, build: String, architecture: String,
                                 sourceDigest: String, switchOn: Bool) -> Bool {
        guard switchOn, let qualification else { return false }
        return qualification.permits(build: build, architecture: architecture, sourceDigest: sourceDigest)
    }

    /// 系统按键还不能改成无事件时，不听遥控器，避免按一次做两件事。
    static func remoteMayInstall(switchOn: Bool, muteMappingVerified: Bool) -> Bool {
        switchOn && muteMappingVerified
    }
}
