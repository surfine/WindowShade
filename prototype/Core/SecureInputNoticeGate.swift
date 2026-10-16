// R17：安全输入（Secure Input）开着时，什么时候在刘海上说一句“快捷键为什么没反应”（纯逻辑，可单测）。
//
// 安全输入一开，系统就不再把按键交给全局快捷键和事件监听，所以“按了没反应”本身没有任何信号可读。
// 能读到的只有两件事：用户刚用过我们的快捷键（说明他在用）、安全输入这一刻开没开。
// 规则：用过快捷键之后的一段时间里盯着安全输入；它从“关”变成“开”，说一次；它一直开着，不再说；
// 关掉再开才算新的一次。没用快捷键的人，开安全输入不会看到任何东西。

import Foundation

struct SecureInputNoticeGate: Equatable {
    /// 最近一次用快捷键之后，盯多久（秒）。
    static let watchWindow: TimeInterval = 120

    private(set) var armedUntil: TimeInterval = -.infinity
    private var wasSecure = false
    private var shownThisSession = false

    func isArmed(at now: TimeInterval) -> Bool { now < armedUntil }

    /// 用户刚用了一次我们的快捷键。secureNow：这一刻安全输入开没开（盯之前先记下基线，
    /// 已经开着的不算“刚开”）。
    mutating func shortcutUsed(at now: TimeInterval, secureNow: Bool) {
        if !isArmed(at: now) {
            wasSecure = secureNow
            shownThisSession = secureNow
        }
        armedUntil = now + Self.watchWindow
    }

    /// 盯着的时候每隔一会儿看一眼。返回 true：现在该说。
    mutating func sample(secure: Bool, at now: TimeInterval) -> Bool {
        guard isArmed(at: now) else { return false }
        guard secure else {
            wasSecure = false
            shownThisSession = false
            return false
        }
        let justTurnedOn = !wasSecure
        wasSecure = true
        guard justTurnedOn, !shownThisSession else { return false }
        shownThisSession = true
        return true
    }
}
