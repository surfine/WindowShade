// 卡住提示的键帽回声（R13）：教学提醒开着时他按对了那一下，提示里新的那排键帽跟着按一下，随后提示提前收回。
// 这里只做“按对时该怎么办”的判定和时间常数（纯逻辑）；画键帽在 App/NotchCoach.swift，收回在 App/Notch.swift。
// 不打勾，不夸。减少动态效果时只换填充，不位移不缩放。

import Foundation

enum CoachEcho {
    /// 按下那一帧：键帽下沉的点数、缩放、填充（白色的不透明度，从 rest 到 pressed）。
    static let sink: Double = 1.5
    static let pressedScale: Double = 0.94
    static let restFill: Double = 0.14
    static let pressedFill: Double = 0.28
    /// 回声之后到提示收回的间隔（原来要等 6.6 秒超时）。
    static let retractDelay: TimeInterval = 0.15
    /// 按下停多久再松开回弹（要比 retractDelay 短，收回时键帽已经弹回去）。
    static let holdBeforeRelease: TimeInterval = 0.06
    /// 提示开口不到这么久、形状还在长时按对：不做回声，直接转退场。
    static let growthWindow: TimeInterval = 0.09

    enum Plan: Equatable {
        /// 键帽回声，之后 retractAfter 秒收回。
        case echo(fillOnly: Bool, retractAfter: TimeInterval)
        /// 形状还在长：直接退场。
        case retractNow
        /// 什么都不做（没有提示、共享屏幕、不是这条规则、不是他自己按的）。
        case none
    }

    /// - Parameters:
    ///   - showingHabitTip: 岛上现在挂着的正是一条卡住提示。
    ///   - sameRule: 按对的规则就是提示讲的那条。
    ///   - byUser: 他自己按的（点提示让刘海代按的不算）。
    ///   - quiet: 共享屏幕等静默状态（卡住提示整句不出，回声也不做）。
    ///   - elapsed: 提示出现到现在的秒数。
    static func plan(showingHabitTip: Bool, sameRule: Bool, byUser: Bool, quiet: Bool,
                     elapsed: TimeInterval, reduceMotion: Bool) -> Plan {
        guard showingHabitTip, sameRule, byUser, !quiet else { return .none }
        if elapsed < growthWindow { return .retractNow }
        return .echo(fillOnly: reduceMotion, retractAfter: retractDelay)
    }
}
