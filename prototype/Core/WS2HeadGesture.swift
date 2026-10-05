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
    /// 相邻样本最长间隔。再长就是缺帧，不当成一个动作。
    static let maxGap: UInt64 = 400 * WS2.Duration.millisecond
    /// 离开回正之前至少停这么久。探一下不算。
    static let minDwell: UInt64 = 80 * WS2.Duration.millisecond
    /// 离开回正到回来，最短和最长。太快或太慢都不是点头、摇头。
    static let minGesture: UInt64 = 80 * WS2.Duration.millisecond
    static let maxGesture: UInt64 = 900 * WS2.Duration.millisecond

    static func recognize(_ samples: [WS2HeadSample]) -> WS2HeadRecognition? {
        guard samples.count >= 4, samples.allSatisfy(finite), strictlyIncreasing(samples) else { return nil }
        guard let first = samples.first, inNeutral(first) else { return nil }
        if let nod = nod(samples) { return nod }
        return shake(samples)
    }

    /// 点头才确认已经展示的那一笔。摇头、以及开始得太早的点头，都不算。
    static func confirms(_ recognition: WS2HeadRecognition, displayedAt: WS2.Instant) -> Bool {
        recognition.kind == .nod && recognition.startedAt >= displayedAt
    }

    private static func finite(_ sample: WS2HeadSample) -> Bool {
        sample.pitchDown.isFinite && sample.yaw.isFinite
    }

    private static func strictlyIncreasing(_ samples: [WS2HeadSample]) -> Bool {
        for pair in zip(samples, samples.dropFirst()) {
            if pair.1.at <= pair.0.at { return false }
            if pair.1.at.elapsed(since: pair.0.at) > maxGap { return false }
        }
        return true
    }

    private static func inNeutral(_ sample: WS2HeadSample) -> Bool {
        abs(sample.pitchDown) <= neutral && abs(sample.yaw) <= neutral
    }

    private static func nod(_ samples: [WS2HeadSample]) -> WS2HeadRecognition? {
        var started: WS2.Instant?
        var dipped = false
        var returned = false
        for sample in samples {
            if abs(sample.yaw) > neutral { return nil }
            if started == nil {
                if sample.pitchDown > neutral {
                    guard let first = samples.first, sample.at.elapsed(since: first.at) >= minDwell else { return nil }
                    started = sample.at
                }
                continue
            }
            if sample.pitchDown < -neutral { return nil }
            if sample.pitchDown >= dip { dipped = true }
            if dipped, inNeutral(sample), let started {
                if !returned {
                    if sample.at.elapsed(since: started) < minGesture || sample.at.elapsed(since: started) > maxGesture {
                        return nil
                    }
                    returned = true
                }
            } else if returned, sample.pitchDown > neutral {
                return nil
            }
        }
        guard returned, let started else { return nil }
        return WS2HeadRecognition(kind: .nod, startedAt: started)
    }

    private static func shake(_ samples: [WS2HeadSample]) -> WS2HeadRecognition? {
        var started: WS2.Instant?
        var positive = false
        var negative = false
        var returned = false
        for sample in samples {
            if sample.pitchDown >= dip { return nil }
            if started == nil {
                if abs(sample.yaw) > neutral {
                    guard let first = samples.first, sample.at.elapsed(since: first.at) >= minDwell else { return nil }
                    started = sample.at
                }
                continue
            }
            if sample.yaw >= shake { positive = true }
            if sample.yaw <= -shake { negative = true }
            if positive, negative, inNeutral(sample), let started {
                if !returned {
                    if sample.at.elapsed(since: started) < minGesture || sample.at.elapsed(since: started) > maxGesture {
                        return nil
                    }
                    returned = true
                }
            } else if returned, abs(sample.yaw) > neutral {
                return nil
            }
        }
        guard returned, positive, negative, let started else { return nil }
        return WS2HeadRecognition(kind: .shake, startedAt: started)
    }
}
