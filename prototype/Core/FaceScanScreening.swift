import Foundation

// 锁屏后认出你：每一帧进比对之前先筛一遍（身份线 §3.3、§3.4、§3.8）。纯逻辑，实验，默认关。
//
// 顺序：否决线索 → 画质门 → 交给守卫比对。
// - 否决线索（屏幕/手机边框、反光，见 FaceLivenessCues）一旦锁存，这一次就判失败，计 1 次。只能否决，从不放行。
// - 画质不过的帧不进比对，也不计次数；到时没认出，按“画质不够”收（FaceIdentityAttempts 里不计次）。
// - 反光只由否决线索判一次：画质门不再看反光比，免得同一个量走两条路。
// - 认出主人只产出证据（IdentityEvidence），交给授权账本 record：证据只能给某个用途加门槛，
//   自己换不来授权，也不接系统解锁；系统认证永远是出路。

/// 一帧里筛选要用的量。脸框与矩形在同一个归一化坐标系里（Vision：0...1，原点左下）。
struct FaceScreenFrame: Equatable, Sendable {
    var faceCount: Int
    /// 最大那张脸的框；没有脸就是 nil。
    var largestFace: FaceCueRect?
    var yaw: Double?
    var pitch: Double?
    /// Vision 的 faceCaptureQuality（最大那张脸），0...1。
    var captureQuality: Double?
    /// 最大那张脸的裁切里抽样的平均亮度与近白、近灰占比（FaceCaptureSampling）。
    var brightness: Double?
    var glareRatio: Double?
    /// 这一帧跑了矩形检测才有值（每 3 帧一次）；没跑就是 nil。
    var rectangles: [FaceCueRect]?
}

struct FaceScanScreening {
    enum Decision: Equatable, Sendable {
        /// 否决线索锁存：这一次判失败。
        case veto(FaceVetoReason)
        /// 画质不过：这一帧不进比对。带刘海上现在该说的那条提示（已过回滞；可能还没有）。
        case qualityInsufficient(FaceQualityHint?)
        /// 交给守卫比对。
        case proceed

        /// 这一帧若就此结束这一次，记成什么。否决计 1 次；画质不够不计；proceed 交给守卫，没有事件。
        var event: FaceIdentityEvent? {
            switch self {
            case .veto(let reason): .vetoCue(label: "deny(\(reason.rawValue))")
            case .qualityInsufficient(let hint): .qualityInsufficient(hint)
            case .proceed: nil
            }
        }
    }

    private var gate: FaceQualityGate
    private(set) var cues = FaceVetoCues()
    private var lastCenter: (x: Double, y: Double)?
    /// 刘海上现在该说的那条提示（画质门已过回滞）；这一次到时没认出时用它收尾。
    private(set) var hint: FaceQualityHint?
    /// 这一次里有没有哪一帧过了画质门。
    private(set) var qualityPassed = false

    init(tuning: FaceQualityTuning = .scan) {
        gate = FaceQualityGate(mode: .scan, tuning: tuning)
    }

    /// 新的一次（新的亮屏、新的扫描）：清空线索、回滞与位移。
    mutating func reset() {
        gate.reset(); cues.reset(); lastCenter = nil; hint = nil; qualityPassed = false
    }

    /// `time` 只在同一路帧之间比较（回滞、连续通过），用帧的主机时钟即可。
    mutating func screen(_ frame: FaceScreenFrame, at time: Double) -> Decision {
        let face = frame.largestFace.flatMap { $0.area > 0 ? $0 : nil }
        if case .veto(let reason) = cues.observe(FaceCueFrame(face: face, glareFraction: frame.glareRatio,
                                                                rectangles: frame.rectangles)) {
            return .veto(reason)
        }
        var center: (x: Double, y: Double)?
        if let face { center = (face.x + face.width / 2, face.y + face.height / 2) }
        let sample = FaceQualitySample(
            faceCount: face == nil ? 0 : max(1, frame.faceCount),
            faceWidth: face?.width ?? 0,
            yaw: frame.yaw, pitch: frame.pitch, eyeOpenness: nil,
            captureQuality: frame.captureQuality, brightness: frame.brightness,
            glareRatio: nil,   // 反光由否决线索判，见文件头
            centerOffset: center.map { hypot($0.x - 0.5, $0.y - 0.5) },
            motion: center.flatMap { now in lastCenter.map { hypot(now.x - $0.x, now.y - $0.y) } })
        lastCenter = center
        let verdict = gate.evaluate(sample, at: time)
        hint = verdict.hint
        guard verdict.passed else { return .qualityInsufficient(verdict.hint) }
        qualityPassed = true
        return .proceed
    }

    /// 挑战阶段：转头本来就会让画质门不过（偏航、位移），这里只看否决线索；锁存沿用比对阶段攒下的。
    mutating func screenVetoOnly(_ frame: FaceScreenFrame) -> Decision {
        let face = frame.largestFace.flatMap { $0.area > 0 ? $0 : nil }
        if case .veto(let reason) = cues.observe(FaceCueFrame(face: face, glareFraction: frame.glareRatio,
                                                                rectangles: frame.rectangles)) {
            return .veto(reason)
        }
        return .proceed
    }
}

extension IdentityEvidence {
    /// 守卫的证据 → 进授权账的证据。
    /// - `cameraClass` 来自相机准入（只有 'bltn' 内建广角才是 .builtIn）。
    /// - 阈值有没有标定，查守卫用的同一张阈值表；查不到就是没标定。
    /// - `through`：挑战做完时最后一帧的帧号（同一路帧）；比守卫的末帧新才往后延。
    init(scan: FaceScanEvidence, cameraClass: CameraClass, tuning: FaceScanTuning, cues: Set<Cue>,
         through lastFrame: UInt64? = nil) {
        let upper = max(scan.frames.upperBound, lastFrame ?? scan.frames.upperBound)
        self.init(scanID: scan.scanID, cameraID: scan.cameraID, generation: scan.generation,
                  frames: scan.frames.lowerBound...upper, cameraClass: cameraClass, modelVersion: scan.modelVersion,
                  thresholdCalibrated: tuning.modelProfiles[scan.modelVersion]?.calibrated ?? false, cues: cues)
    }
}

extension NoseParallaxSample {
    /// 从对齐点取一个鼻子视差样本（确认线索，只记录）。`alignment` 的顺序同 FaceGeometry.alignmentPoints：
    /// 画面左眼中心、画面右眼中心、鼻子中心……；点不够、不有限、两眼几乎重合或没有偏航角给 nil。
    init?(yaw: Double?, alignment: [CGPoint]?) {
        guard let yaw, yaw.isFinite, let points = alignment, points.count >= 3 else { return nil }
        let left = points[0], right = points[1], nose = points[2]
        let values: [CGFloat] = [left.x, left.y, right.x, right.y, nose.x, nose.y]
        guard values.allSatisfy({ $0.isFinite }) else { return nil }
        let spacing = Double(hypot(right.x - left.x, right.y - left.y))
        guard spacing > 1e-6 else { return nil }
        let offset = (Double(nose.x) - Double(left.x + right.x) / 2) / spacing
        self.init(yaw: yaw, noseOffset: offset)
    }
}
