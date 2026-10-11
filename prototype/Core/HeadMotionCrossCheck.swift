// 身份线 §3.4 第 4 条 · AirPods 转头交叉核对（纯逻辑）。
// 挑战窗口里，镜头看到的转头和耳机陀螺仪的转头要同向、同时。虚拟相机和录像只能伪造镜头那一半。
// 只能否决，从不放行：结论最多让证据记一笔 crossModal；挑战本身没过时，它说什么都放行不了。
// 没戴耳机（耳机这一路没数据、没覆盖挑战那几秒）就不参与，不扣分。
// 不碰 CoreMotion、Vision，也不记任何设备名；尚未接进挑战流程。
import Foundation

/// 一路 yaw 的一个样本。镜头一路是 Vision 原始 yaw（弧度）；
/// 耳机一路是 `WS2HeadMotionMath.degrees` 换算后的度数（约定向右为正）。
struct HeadMotionYawSample: Equatable, Sendable {
    var at: WS2.Instant
    var yaw: Double
}

enum HeadMotionCrossCheck {
    enum Mismatch: Equatable, Sendable {
        /// 镜头里转够了头，耳机几乎没动。
        case headStill
        /// 两边转的方向相反。
        case oppositeDirection
        /// 方向一致，但两边开始转的时刻差太多。
        case timing
    }

    enum Verdict: Equatable, Sendable {
        /// 没戴耳机、耳机数据断续或没覆盖转头那几秒、镜头里没转够：不参与。
        case notParticipating
        case agree
        case disagree(Mismatch)
    }

    /// 镜头 yaw 乘这个符号后，应与耳机 yaw（向右为正）同号。
    /// 占位值，未在真机上量过（还有 `WS2HeadMotionFeed.swift` 的耳机符号、`FaceGestureTracker.swift` 的左右判定）。
    /// 用 `tools/probes/head-motion-crosscheck/run.sh` 量完再改，并把 `signMeasured` 改成 true；量之前不要接进挑战。
    static let cameraToHeadSign: Double = 1
    static let signMeasured = false

    /// 两边“转到一半”的时刻最多差这么多。计划写 0.3 s，需真机标定。
    static let maximumOnsetLag: UInt64 = 300 * WS2.Duration.millisecond
    /// 镜头里至少转这么多（弧度）才核对；与 `OwnerTurnChallenge` 的转到位门槛一致。
    static let minimumCameraSwing = 0.25
    /// 镜头转够了而耳机不到这么多度，算耳机没动。
    static let minimumHeadSwing = 8.0
    /// 耳机相邻两个样本最多隔这么久，否则当作断续、不参与。
    static let maximumHeadGap: UInt64 = 300 * WS2.Duration.millisecond

    /// 计划里的接口：nil = 不参与，true = 一致，false = 不一致（只能用来否决）。
    static func agree(camera: [HeadMotionYawSample], head: [HeadMotionYawSample]) -> Bool? {
        switch verdict(camera: camera, head: head) {
        case .notParticipating: return nil
        case .agree: return true
        case .disagree: return false
        }
    }

    /// 交叉核对只能把“过”改成“不过”，永远不能把“不过”改成“过”。
    static func admits(challengePassed: Bool, verdict: Verdict) -> Bool {
        guard challengePassed else { return false }
        if case .disagree = verdict { return false }
        return true
    }

    /// 证据里的 crossModal：只有挑战过了且两边一致才记。
    static func crossModal(challengePassed: Bool, verdict: Verdict) -> Bool {
        challengePassed && verdict == .agree
    }

    static func verdict(camera rawCamera: [HeadMotionYawSample], head rawHead: [HeadMotionYawSample]) -> Verdict {
        let camera = cleaned(rawCamera)
        let head = cleaned(rawHead)
        guard let cameraSwing = swing(camera, wrapDegrees: false),
              abs(cameraSwing.peak) >= minimumCameraSwing else { return .notParticipating }
        let direction: Double = cameraSwing.peak * cameraToHeadSign > 0 ? 1 : -1
        let onset = cameraSwing.onset

        // 耳机这一路要从镜头开始转之前就在、一直跟到转完之后，且中间不断。
        let windowStart = camera[0].at.nanoseconds >= maximumOnsetLag
            ? WS2.Instant(nanoseconds: camera[0].at.nanoseconds - maximumOnsetLag) : .zero
        let windowEnd = camera[camera.count - 1].at.adding(maximumOnsetLag)
        let inWindow = head.filter { $0.at >= windowStart && $0.at <= windowEnd }
        guard let first = inWindow.first, let last = inWindow.last,
              first.at <= camera[0].at, last.at >= onset.adding(maximumOnsetLag) else { return .notParticipating }
        for (a, b) in zip(inWindow, inWindow.dropFirst()) where b.at.elapsed(since: a.at) > maximumHeadGap {
            return .notParticipating
        }

        guard let headSwing = swing(inWindow, wrapDegrees: true) else { return .notParticipating }
        guard abs(headSwing.peak) >= minimumHeadSwing else { return .disagree(.headStill) }
        guard headSwing.peak * direction > 0 else { return .disagree(.oppositeDirection) }
        let lag = max(headSwing.onset.elapsed(since: onset), onset.elapsed(since: headSwing.onset))
        guard lag <= maximumOnsetLag else { return .disagree(.timing) }
        return .agree
    }

    // MARK: -

    /// 丢掉非有限值，按时间排序，同一时刻只留第一个。
    private static func cleaned(_ samples: [HeadMotionYawSample]) -> [HeadMotionYawSample] {
        var sorted = samples.filter { $0.yaw.isFinite }
        sorted.sort { $0.at < $1.at }
        var out: [HeadMotionYawSample] = []
        out.reserveCapacity(sorted.count)
        for s in sorted where out.last?.at != s.at { out.append(s) }
        return out
    }

    /// 相对第一个样本的最大偏转（带符号），以及第一次转到这一偏转一半的时刻。
    /// 用“转到一半”而不是峰值时刻比时差：挑战要转到位再停住，峰值落在停住那段的哪一帧是噪声。
    private static func swing(_ samples: [HeadMotionYawSample], wrapDegrees: Bool) -> (peak: Double, onset: WS2.Instant)? {
        guard let base = samples.first?.yaw, samples.count >= 2 else { return nil }
        func delta(_ yaw: Double) -> Double {
            var d = yaw - base
            if wrapDegrees {
                // 耳机 yaw 在 ±180° 处回绕。
                d = d.truncatingRemainder(dividingBy: 360)
                if d > 180 { d -= 360 } else if d <= -180 { d += 360 }
            }
            return d
        }
        var peak = 0.0
        for s in samples {
            let d = delta(s.yaw)
            if abs(d) > abs(peak) { peak = d }
        }
        guard peak != 0 else { return (0, samples[0].at) }
        let half = abs(peak) / 2
        let sign: Double = peak > 0 ? 1 : -1
        guard let onset = samples.first(where: { delta($0.yaw) * sign >= half }) else { return nil }
        return (peak, onset.at)
    }
}
