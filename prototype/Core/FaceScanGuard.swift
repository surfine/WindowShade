import Foundation

// 刷脸扫描守卫（实验）。思路取自 Glance FaceUnlockCoordinator / FaceRecognitionPipeline（MIT），Swift 自写。
// 只产出“认出主人”的证据，交给授权账本裁决；本类型不放行、不接系统解锁，系统认证始终是出口。
//
// 规则：
// - 每一帧都重查“真的锁着”且锁屏代次没变；会话已不锁的帧连同这次扫描一起丢弃。
// - 帧号用 Hub 透传的 cameraID / generation / sequence，守卫不自己数帧：同一路里同号或更早的帧不再计数；
//   换了相机或代次（相机重开，帧号从头数）就是另一路，攒下的部分匹配清零，证据只绑一路帧。
// - 宽度不到画面 0.18 的脸是路人，不算候选。
// - 主人要同时过“平均模板”和“最近一次录入”两道阈值；模型版本不同的模板不参与。
// - 阈值按模型版本选：登记过的版本用自己的阈值，其余沿用默认 0.6；阈值不合法就一律不认。
// - 一帧非主人就清掉之前攒下的部分匹配。
// - 认错脸要满 2 秒才判失败；2 秒内的多次唤醒只算一次扫描。

struct FaceTemplate: Equatable, Sendable {
    let embedding: [Float]
    let modelVersion: String
    /// 录入序号，越大越新；只用来找“最近一次录入”。新录入接在已有最大值后面递增（FaceTemplateSet.nextEnrollmentSequence），
    /// 不读墙钟，改系统时间改不了谁是最近一次。旧模板里存的是当时的墙钟秒数，照样按大小比较。
    let enrolledAt: Double
    /// 录入那一帧两只眼睁开程度的较小值（实验：随机转头挑战的参照）。旧模板没有，就是 nil。
    var eyeOpenness: Double? = nil
}

struct FaceScanFace: Equatable, Sendable {
    /// 脸宽占画面宽的比例，0...1。
    let widthFraction: Double
    /// 识别模型给出的特征；没算出来就是 nil。
    let embedding: [Float]?
}

struct FaceScanFrame: Equatable, Sendable {
    /// 以下三项由相机 Hub 透传（FaceObservation），守卫不自己编号。
    let cameraID: String
    let generation: UInt64
    let sequence: UInt64
    /// 帧的主机时钟，只用于同一路帧之间比较（认错 2 秒）；不拿去和授权账本的期限比。
    let capturedAt: Double
    /// 产出这帧特征的模型版本。
    let modelVersion: String
    let faces: [FaceScanFace]
}

/// 某个特征模型版本自己的阈值。不同模型的余弦分布不同，一个阈值不能通用。
struct FaceScanModelProfile: Equatable, Sendable {
    let modelVersion: String
    let similarityThreshold: Float
    /// false = 还没用本人与他人样本标定过（见 tools/probes/FaceFeaturePrintProbe.swift）。
    let calibrated: Bool

    /// Apple Vision 图像特征（VNGenerateImageFeaturePrintRequest 第 2 版），输入是摆正、外扩 1.3 倍、
    /// 缩到 224 见方的脸部裁切。版本串写进模板，换修订或换裁切就是另一个版本，旧模板自动不参与。
    static let visionFeaturePrintVersion = "vision-featureprint-r2-crop1.3-224"
    /// UNCALIBRATED：图像特征不是人脸身份特征，不同人的脸裁切余弦也可能很高。0.92 是偏严的占位值，
    /// 宁可认不出也不放宽；真机标定后改这里，并把 calibrated 改成 true。
    static let visionFeaturePrint = FaceScanModelProfile(
        modelVersion: visionFeaturePrintVersion, similarityThreshold: 0.92, calibrated: false)

    /// 按模型版本串查阈值的表。新后端（例如 ArcFace）在这里加一条；没有条目的版本只用默认 0.6，
    /// 刷脸实验启动时会拒绝没有条目的后端。
    static let table: [String: FaceScanModelProfile] = Dictionary(
        uniqueKeysWithValues: [visionFeaturePrint].map { ($0.modelVersion, $0) })
}

struct FaceScanTuning: Equatable, Sendable {
    // 实验参数；相似度阈值尚未经本人和攻击样本标定。
    /// 没登记模型阈值的版本用这个（原先按 ArcFace 类特征定的）。
    var similarityThreshold: Float = 0.6
    /// 按模型版本选阈值；键是精确的版本串。
    var modelProfiles: [String: FaceScanModelProfile] = FaceScanModelProfile.table
    var minimumFaceWidth: Double = 0.18
    var wrongFaceGrace: Double = 2
    var wakeCoalesceWindow: Double = 2
    var requiredConsecutiveMatches: Int = 2

    /// 这个模型版本该用的阈值；不在 (0, 1] 内（含 NaN）就返回 nil，调用方一律不认。
    func similarityThreshold(for modelVersion: String) -> Float? {
        let value = modelProfiles[modelVersion]?.similarityThreshold ?? similarityThreshold
        return value.isFinite && value > 0 && value <= 1 ? value : nil
    }
}

/// 认出主人的证据。只是证据，放行与否由授权账本决定；进账本时以账本收到的时刻为准（IdentityEvidence）。
struct FaceScanEvidence: Equatable, Sendable {
    let scanID: UInt64
    let lockGeneration: UInt64
    let cameraID: String
    let generation: UInt64
    /// 连续认出的首末帧号（同一路）。
    let frames: ClosedRange<UInt64>
    /// 最后一帧的主机时钟，只作日志与同路比较。
    let matchedAt: Double
    let modelVersion: String
}

struct FaceScanGuard {
    enum Wake: Equatable, Sendable { case started(scanID: UInt64), coalesced(scanID: UInt64), notLocked }
    enum Discard: Equatable, Sendable { case noScan, finished, notLocked, duplicateFrame }
    enum Outcome: Equatable, Sendable {
        case discarded(Discard)
        case scanning
        case owner(FaceScanEvidence)
        case failed
    }

    private struct Stream: Equatable {
        let cameraID: String
        let generation: UInt64
    }

    private struct Scan {
        let id: UInt64
        let lockGeneration: UInt64
        let startedAt: Double
        var stream: Stream?
        var lastFrame: UInt64?
        var consecutiveMatches = 0
        var firstMatch: UInt64?
        var firstWrongAt: Double?
        var finished = false
    }

    /// 同一模型版本、同一维度的模板算好的参照：平均模板（各条先归一化）和最近一次录入。
    private struct ReferenceKey: Hashable {
        let modelVersion: String
        let dimension: Int
    }
    private struct Reference {
        let mean: [Float]
        let latest: [Float]
    }

    let tuning: FaceScanTuning
    let templates: [FaceTemplate]
    /// 模板在 init 里定下就不变，平均模板只算这一次，不再每帧重算。
    private let references: [ReferenceKey: Reference]
    private var scan: Scan?
    private var nextScanID: UInt64 = 1

    init(templates: [FaceTemplate], tuning: FaceScanTuning = FaceScanTuning()) {
        self.templates = templates
        self.tuning = tuning
        var groups: [ReferenceKey: [FaceTemplate]] = [:]
        for template in templates {
            groups[ReferenceKey(modelVersion: template.modelVersion, dimension: template.embedding.count), default: []]
                .append(template)
        }
        var references: [ReferenceKey: Reference] = [:]
        for (key, group) in groups {
            guard let latest = group.max(by: { $0.enrolledAt < $1.enrolledAt }),
                  let mean = Self.mean(group.map { Self.normalized($0.embedding) }) else { continue }
            references[key] = Reference(mean: mean, latest: latest.embedding)
        }
        self.references = references
    }

    var isScanning: Bool { scan.map { !$0.finished } ?? false }

    /// 开盖、亮屏等唤醒。2 秒内的连续唤醒并入同一次扫描。
    mutating func wake(at time: Double, lock: SessionLockState, lockGeneration: UInt64) -> Wake {
        guard lock.isReallyLocked, time.isFinite else { scan = nil; return .notLocked }
        if let current = scan, current.lockGeneration == lockGeneration,
           time >= current.startedAt, time - current.startedAt < tuning.wakeCoalesceWindow {
            return .coalesced(scanID: current.id)
        }
        let id = nextScanID
        nextScanID &+= 1
        scan = Scan(id: id, lockGeneration: lockGeneration, startedAt: time)
        return .started(scanID: id)
    }

    /// 每一帧都带上当时的锁态重查；不锁了就丢弃这帧，扫描作废。
    mutating func receive(_ frame: FaceScanFrame, lock: SessionLockState, lockGeneration: UInt64) -> Outcome {
        guard var current = scan else { return .discarded(.noScan) }
        guard lock.isReallyLocked, lockGeneration == current.lockGeneration else {
            scan = nil; return .discarded(.notLocked)
        }
        if current.finished { return .discarded(.finished) }
        let stream = Stream(cameraID: frame.cameraID, generation: frame.generation)
        if current.stream != stream {
            // 另一路帧：帧号从头数，之前那一路的部分匹配不能接上。
            current.stream = stream; current.lastFrame = nil
            current.consecutiveMatches = 0; current.firstMatch = nil
        }
        if let last = current.lastFrame, frame.sequence <= last { scan = current; return .discarded(.duplicateFrame) }
        current.lastFrame = frame.sequence
        defer { scan = current }

        // 路人（脸太窄）不参与；取最大的候选脸。
        let candidates = frame.faces.filter { $0.widthFraction.isFinite && $0.widthFraction >= tuning.minimumFaceWidth }
        guard let face = candidates.max(by: { $0.widthFraction < $1.widthFraction }) else { return .scanning }

        if let embedding = face.embedding, isOwner(embedding, modelVersion: frame.modelVersion) {
            current.consecutiveMatches += 1
            let first = current.firstMatch ?? frame.sequence
            current.firstMatch = first
            guard current.consecutiveMatches >= max(1, tuning.requiredConsecutiveMatches) else { return .scanning }
            current.finished = true
            return .owner(FaceScanEvidence(scanID: current.id, lockGeneration: current.lockGeneration,
                                           cameraID: frame.cameraID, generation: frame.generation,
                                           frames: first...frame.sequence, matchedAt: frame.capturedAt,
                                           modelVersion: frame.modelVersion))
        }
        // 非主人：清掉部分匹配；从第一帧认错起满 2 秒才判失败。
        current.consecutiveMatches = 0; current.firstMatch = nil
        let firstWrong = current.firstWrongAt ?? frame.capturedAt
        current.firstWrongAt = firstWrong
        if frame.capturedAt - firstWrong >= tuning.wrongFaceGrace {
            current.finished = true
            return .failed
        }
        return .scanning
    }

    /// 平均模板和最近一次录入都要过阈值；只用同一模型版本、同一维度的模板（参照在 init 里算好）。
    func isOwner(_ embedding: [Float], modelVersion: String) -> Bool {
        guard let threshold = tuning.similarityThreshold(for: modelVersion),
              let reference = references[ReferenceKey(modelVersion: modelVersion, dimension: embedding.count)],
              let toMean = Self.cosine(embedding, reference.mean), let toLatest = Self.cosine(embedding, reference.latest)
        else { return false }
        return toMean >= threshold && toLatest >= threshold
    }

    static func cosine(_ a: [Float], _ b: [Float]) -> Float? {
        guard a.count == b.count, !a.isEmpty else { return nil }
        var dot: Float = 0, na: Float = 0, nb: Float = 0
        for index in a.indices { dot += a[index] * b[index]; na += a[index] * a[index]; nb += b[index] * b[index] }
        guard na > 0, nb > 0, dot.isFinite, na.isFinite, nb.isFinite else { return nil }
        return dot / (na.squareRoot() * nb.squareRoot())
    }

    private static func normalized(_ v: [Float]) -> [Float] {
        let norm = v.reduce(Float(0)) { $0 + $1 * $1 }.squareRoot()
        return norm > 0 && norm.isFinite ? v.map { $0 / norm } : v
    }

    private static func mean(_ vectors: [[Float]]) -> [Float]? {
        guard let first = vectors.first else { return nil }
        var sum = [Float](repeating: 0, count: first.count)
        for vector in vectors { for index in sum.indices { sum[index] += vector[index] } }
        return sum.map { $0 / Float(vectors.count) }
    }
}
