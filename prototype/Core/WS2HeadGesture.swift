// WindowShade 2.1 · 头动确认。只识别一次完整的点头或摇头。
// 角度是初始门槛，不是测得的最佳值。低头看键盘、探一下，都不算同意。
import Foundation

struct WS2HeadSample: Equatable, Sendable {
    var at: WS2.Instant
    /// 向下为正，单位度。0 是回正。
    var pitchDown: Double
    /// 向右为正，单位度。0 是回正。
    var yaw: Double
}

struct WS2HeadRecognition: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case nod
        case shake
    }

    var kind: Kind
    /// 离开回正的第一帧。不早于预览 displayedAt，这次点头才算确认。
    var startedAt: WS2.Instant
}

enum WS2HeadGesture {
    /// 回正带。初始值。
    static let neutral: Double = 8
    /// 下点要超过的角度。初始值。
    static let dip: Double = 18
    /// 左右摆要超过的角度。初始值。
    static let shake: Double = 20

    static func recognize(_ samples: [WS2HeadSample]) -> WS2HeadRecognition? {
        guard let first = samples.first, inNeutral(first) else { return nil }
        if let nod = nod(samples) { return nod }
        return shake(samples)
    }

    /// 点头才确认已经展示的那一笔。摇头、以及开始得太早的点头，都不算。
    static func confirms(_ recognition: WS2HeadRecognition, displayedAt: WS2.Instant) -> Bool {
        recognition.kind == .nod && recognition.startedAt >= displayedAt
    }

    private static func inNeutral(_ sample: WS2HeadSample) -> Bool {
        abs(sample.pitchDown) <= neutral && abs(sample.yaw) <= neutral
    }

    private static func nod(_ samples: [WS2HeadSample]) -> WS2HeadRecognition? {
        var started: WS2.Instant?
        var dipped = false
        for sample in samples {
            if abs(sample.yaw) > neutral { return nil }
            if started == nil {
                if sample.pitchDown > neutral { started = sample.at }
                continue
            }
            if sample.pitchDown >= dip { dipped = true }
            if dipped, sample.pitchDown <= neutral, let started {
                return WS2HeadRecognition(kind: .nod, startedAt: started)
            }
        }
        return nil
    }

    private static func shake(_ samples: [WS2HeadSample]) -> WS2HeadRecognition? {
        var started: WS2.Instant?
        var swung = false
        var sign = 0.0
        for sample in samples {
            if sample.pitchDown >= dip { return nil }
            if started == nil {
                if abs(sample.yaw) > neutral {
                    started = sample.at
                    sign = sample.yaw
                }
                continue
            }
            if sample.yaw * sign < 0 { return nil }
            if abs(sample.yaw) >= shake { swung = true }
            if swung, abs(sample.yaw) <= neutral, let started {
                return WS2HeadRecognition(kind: .shake, startedAt: started)
            }
        }
        return nil
    }
}
