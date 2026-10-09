// WindowShade 2.1 · 耳机头动的纯逻辑：弧度转度数、按显示器分开记基线、换耳机重新校准、
// 把相对基线的样本交给 WS2HeadGesture.recognize。不碰 CoreMotion，也不记任何设备名。
import Foundation

enum WS2HeadMotionMath {
    /// CMAttitude 的 pitch 抬头为正；WS2HeadSample 向下为正，所以取反。
    /// CMAttitude 的 yaw 向左（逆时针）为正；WS2HeadSample 向右为正，所以取反。
    /// 符号约定是初始值，未在真机上量过。
    static func degrees(pitchRadians: Double, yawRadians: Double) -> (pitchDown: Double, yaw: Double)? {
        guard pitchRadians.isFinite, yawRadians.isFinite else { return nil }
        return (-pitchRadians * 180 / .pi, -yawRadians * 180 / .pi)
    }
}

struct WS2HeadMotionFeed: Sendable {
    struct Output: Equatable, Sendable {
        var turn: WS2HeadTurn
        var recognition: WS2HeadRecognition?
    }

    /// 只保留这么久的样本。比一次完整动作（最长 0.9 秒加起始停顿）略长。
    static let window: UInt64 = 2 * WS2.Duration.second

    private struct Track: Sendable {
        var basePitch = 0.0
        var baseYaw = 0.0
        var samples: [WS2HeadSample] = []
    }

    private var tracker = WS2DisplayHeadTracker()
    private var tracks: [UInt32: Track] = [:]
    private var lastDisplay: UInt32?

    init() {}

    /// 一帧耳机姿态。`display` 是指针所在显示器，`source` 是当前这副耳机的匿名标记。
    mutating func ingest(display: UInt32, source: WS2HeadSource, pitchRadians: Double,
                         yawRadians: Double, at: WS2.Instant) -> Output {
        guard let deg = WS2HeadMotionMath.degrees(pitchRadians: pitchRadians, yawRadians: yawRadians) else {
            return Output(turn: .none, recognition: nil)
        }
        var track = tracks[display] ?? Track()
        // 指针换了一块屏：那块屏上留着的旧样本不再连续，丢掉；基线保留。
        if let last = lastDisplay, last != display { track.samples.removeAll() }
        lastDisplay = display

        let turn = tracker.update(display: display, source: source, yaw: deg.yaw)
        if turn == .calibrated {
            track.baseYaw = deg.yaw
            track.basePitch = deg.pitchDown
            track.samples.removeAll()
        }
        let sample = WS2HeadSample(at: at, pitchDown: deg.pitchDown - track.basePitch, yaw: deg.yaw - track.baseYaw)
        if let last = track.samples.last, at <= last.at { tracks[display] = track; return Output(turn: turn, recognition: nil) }
        track.samples.append(sample)
        track.samples.removeAll { at.elapsed(since: $0.at) > Self.window }
        // 起点必须在回正带里。
        while let first = track.samples.first,
              abs(first.pitchDown) > WS2HeadGesture.neutral || abs(first.yaw) > WS2HeadGesture.neutral {
            track.samples.removeFirst()
        }
        var recognition: WS2HeadRecognition?
        if turn != .calibrated, track.samples.count >= 4,
           abs(sample.pitchDown) <= WS2HeadGesture.neutral, abs(sample.yaw) <= WS2HeadGesture.neutral,
           let found = WS2HeadGesture.recognize(track.samples) {
            recognition = found
            track.samples.removeAll()
        }
        tracks[display] = track
        return Output(turn: turn, recognition: recognition)
    }

    /// 屏幕拔掉。
    mutating func forget(display: UInt32) {
        tracker.forget(display: display)
        tracks[display] = nil
        if lastDisplay == display { lastDisplay = nil }
    }

    /// 停止采集：全部清掉，下次从重新校准开始。
    mutating func reset() { self = WS2HeadMotionFeed() }
}
