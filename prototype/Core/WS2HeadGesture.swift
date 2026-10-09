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

// MARK: - 按显示器记基线的头部朝向
// 思路参考 quietglass DisplayHeadTracking（MIT）：每块屏各记一个回正基线；
// 偏离基线要过迟滞角才算转头；换了耳机（左/右/别的设备）就丢基线重新校准。

enum WS2HeadSource: Hashable, Sendable {
    case left
    case right
    case other(String)
}

enum WS2HeadTurn: Equatable, Sendable {
    case none
    /// 刚（重新）记下基线，这一帧不判方向。
    case calibrated
    case left
    case right
}

struct WS2DisplayHeadTracker: Sendable {
    /// 偏离基线达到这个角度才算一次转向。初始值。
    static let hysteresis: Double = 4

    private struct Baseline: Sendable {
        var yaw: Double
        var source: WS2HeadSource
    }

    /// 键是稳定的显示器编号。
    private var baselines: [UInt32: Baseline] = [:]

    init() {}

    /// 向右为正（与 WS2HeadSample.yaw 一致）。
    mutating func update(display: UInt32, source: WS2HeadSource, yaw: Double) -> WS2HeadTurn {
        guard yaw.isFinite else { return .none }
        guard let base = baselines[display], base.source == source else {
            baselines[display] = Baseline(yaw: yaw, source: source)
            return .calibrated
        }
        let delta = yaw - base.yaw
        if delta >= Self.hysteresis { return .right }
        if delta <= -Self.hysteresis { return .left }
        return .none
    }

    /// 屏幕拔掉后清掉它的基线。
    mutating func forget(display: UInt32) {
        baselines[display] = nil
    }
}
