// WindowShade 2.1 · 坐姿。用眼距离和头的朝向各看各的，再并成一条刘海提醒。
// 距离沿用已经分好的观察：未知、不近、持续太近。这里不测公分，不把俯仰换成眼睛到屏幕的距离。
// 持续多久算长时间，Apple 没有公布。这里不设秒数，也不拿 ISO 11226 概述里的 4 秒当阈值。
// 俯仰不是颈屈曲角。这里不输出度数，不诊断，不写已经减轻了颈的负担。
// 耳机连着不是身份，也不是人走远了。这一层不取消离开就锁，不解锁。
import Foundation

struct WS2PostureInput: Equatable, Sendable {
    enum Head: Equatable, Sendable {
        /// 没有头部追踪。朝向未知。
        case noTracking
        /// 耳机连在别的装置上。这台 Mac 没有这串朝向。
        case otherDevice
        case level
        /// 一下子低头，例如看键盘。不是长时间低着。
        case briefDown
        /// 头长时间低着。调用方已经分好。秒数不在这里。
        case sustainedDown
    }

    var eye: WS2ScreenDistanceInput.Eye = .unknown
    var head: Head = .noTracking
    var focus: WS2ScreenDistanceInput.Focus = .idle
    /// 镜头被挡、合盖、没有帧。这一格保持未知，不用耳机或俯仰填上。
    var cameraCovered = false
    /// 连着这台 Mac 的耳机。不是身份，也不是人走远了，不改变这一层。
    var headphonesOnThisMac = false
    /// 人已经走远。不能拿来取消离开就锁，也不改坐姿。
    var personLeft = false
}

struct WS2PostureDecision: Equatable, Sendable {
    enum Reminder: Equatable, Sendable {
        case none
        case eyes
        case posture
        case both
    }

    enum HeadWriting: Equatable, Sendable {
        case unknown
        case level
        case briefDown
        case sustainedDown
    }

    var reminder: Reminder
    var eyeToThisScreen: WS2ScreenDistanceDecision.EyeWriting
    var head: HeadWriting
    /// 给已有刘海的一句候选。nil 就是这一拍不提醒。结构上只有这一句，不会有第二条。
    var notchPhrase: String?
    var focusKeepsRunning: Bool
    /// 专注、休息、空闲都不让番茄钟停下、跳过或结束。
    var stopsFocusTimer: Bool
    var cancelsAwayCountdown: Bool
    var countsAsIdentity: Bool
    var grantsUnlock: Bool
    /// 永远没有公分。nil 不是 0，也不是够远。
    var centimeters: Double?
    /// 永远没有度数。nil 不是 0 度，也不是颈屈曲角。
    var pitchDegrees: Double?
    /// 未知、平视，都不写成坐得正。
    var writesUpright: Bool
    /// 未知、不近，都不写成够远。
    var writesFarEnough: Bool
    var opensWindow: Bool
    var coversDesktop: Bool

    var notchRequestCount: Int { notchPhrase == nil ? 0 : 1 }
}

enum WS2Posture {
    /// 候选，还没进词表。刘海主句不超过 8 个字。
    static let eyesPhrase = "离屏幕近了"
    static let posturePhrase = "头低久了"
    /// 两件一起仍是一句，不是两个弹窗。
    static let bothPhrase = "近了，头低久了"

    static func decide(_ input: WS2PostureInput) -> WS2PostureDecision {
        _ = input.headphonesOnThisMac
        _ = input.personLeft

        let eyeToThisScreen: WS2ScreenDistanceDecision.EyeWriting
        if input.cameraCovered {
            eyeToThisScreen = .unknown
        } else {
            switch input.eye {
            case .unknown:
                eyeToThisScreen = .unknown
            case .notNear:
                eyeToThisScreen = .notNear
            case .nearSustained:
                eyeToThisScreen = .tooClose
            }
        }

        let head: WS2PostureDecision.HeadWriting
        switch input.head {
        case .noTracking, .otherDevice:
            head = .unknown
        case .level:
            head = .level
        case .briefDown:
            head = .briefDown
        case .sustainedDown:
            head = .sustainedDown
        }

        let reminder: WS2PostureDecision.Reminder
        if input.focus == .rest || head == .briefDown {
            reminder = .none
        } else if eyeToThisScreen == .tooClose && head == .sustainedDown {
            reminder = .both
        } else if eyeToThisScreen == .tooClose {
            reminder = .eyes
        } else if head == .sustainedDown {
            reminder = .posture
        } else {
            reminder = .none
        }

        let notchPhrase: String?
        switch reminder {
        case .none:
            notchPhrase = nil
        case .eyes:
            notchPhrase = eyesPhrase
        case .posture:
            notchPhrase = posturePhrase
        case .both:
            notchPhrase = bothPhrase
        }

        return WS2PostureDecision(
            reminder: reminder,
            eyeToThisScreen: eyeToThisScreen,
            head: head,
            notchPhrase: notchPhrase,
            focusKeepsRunning: input.focus == .focus,
            stopsFocusTimer: false,
            cancelsAwayCountdown: false,
            countsAsIdentity: false,
            grantsUnlock: false,
            centimeters: nil,
            pitchDegrees: nil,
            writesUpright: false,
            writesFarEnough: false,
            opensWindow: false,
            coversDesktop: false
        )
    }
}
