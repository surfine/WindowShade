// WindowShade 2.1 · 屏幕距离和离开就锁、耳机，各看各的。
// 只有眼睛到这块屏、并且持续太近，才提醒。测不到就保持未知，不写成刚好，也不写成 0。
// 耳机连着、头部追踪、RSSI、人走远了，都不是用眼距离，也不取消离开就锁的倒数。
// 头部朝向没有公分。休息不再加一条距离提示。太近时番茄钟继续走。
import Foundation

struct WS2ScreenDistanceInput: Equatable, Sendable {
    enum Eye: Equatable, Sendable {
        case unknown
        /// 眼睛到这块屏，并且已经持续到可以提醒。秒数未知，调用方不要自编一个数再标成和 iPhone 一样。
        case nearSustained
        case notNear
    }

    enum Headphones: Equatable, Sendable {
        case unknown
        case thisMac
        case phone
        case disconnected
    }

    enum Phone: Equatable, Sendable {
        case unknown
        case connected
        case disconnected
    }

    enum Focus: Equatable, Sendable {
        case idle
        case focus
        case rest
    }

    var eye: Eye = .unknown
    var headphones: Headphones = .unknown
    /// 头部追踪只说明头在转。不能换成眼睛到屏幕的公分。
    var headTracking = false
    var phone: Phone = .unknown
    /// RSSI 只是信号强弱。不能写成眼睛距离。
    var rssiNear: Bool?
    /// 人已经走远。不能写成用眼距离，也不能拿来取消离开就锁。
    var personLeft = false
    var focus: Focus = .idle
}

struct WS2ScreenDistanceDecision: Equatable, Sendable {
    enum Reminder: Equatable, Sendable {
        case none
        case tooClose
    }

    /// 眼睛到这块屏写成哪一档。没有公分。未知保持未知，不会变成「刚好」。
    enum EyeWriting: Equatable, Sendable {
        case unknown
        case notNear
        case tooClose
    }

    var reminder: Reminder
    var eyeToThisScreen: EyeWriting
    /// 专注倒计时继续走。太近不暂停番茄钟。
    var focusKeepsRunning: Bool
    /// 耳机、头部追踪、RSSI、人走远了，都不能取消「离开就锁」的倒数。
    var cancelsAwayCountdown: Bool
    var headphonesCountAsEyeDistance: Bool
    var headphonesCountAsPresence: Bool
    /// 永远没有公分。nil 不是 0。头部朝向、RSSI、耳机都写不进这里。
    var centimeters: Double?
}

enum WS2ScreenDistance {
    static func decide(_ input: WS2ScreenDistanceInput) -> WS2ScreenDistanceDecision {
        let eyeToThisScreen: WS2ScreenDistanceDecision.EyeWriting
        switch input.eye {
        case .unknown:
            eyeToThisScreen = .unknown
        case .notNear:
            eyeToThisScreen = .notNear
        case .nearSustained:
            eyeToThisScreen = .tooClose
        }
        let remind = eyeToThisScreen == .tooClose && input.focus != .rest
        return WS2ScreenDistanceDecision(
            reminder: remind ? .tooClose : .none,
            eyeToThisScreen: eyeToThisScreen,
            focusKeepsRunning: input.focus == .focus,
            cancelsAwayCountdown: false,
            headphonesCountAsEyeDistance: false,
            headphonesCountAsPresence: false,
            centimeters: nil
        )
    }
}

enum WS2ScreenDistanceSimulation {
    struct Preview: Equatable, Sendable {
        var line: String
        var cancelsAwayCountdown: Bool
        var centimeters: Double?
    }

    /// 测不到距离。不写成刚好，也不写成 0，也不取消离开倒数。
    static func unknown() -> Preview {
        let decision = WS2ScreenDistance.decide(WS2ScreenDistanceInput())
        let unknown = decision.eyeToThisScreen == .unknown && decision.centimeters == nil && decision.reminder == .none
        return Preview(
            line: unknown ? "未知" : "这次没有做",
            cancelsAwayCountdown: decision.cancelsAwayCountdown,
            centimeters: decision.centimeters)
    }
}
