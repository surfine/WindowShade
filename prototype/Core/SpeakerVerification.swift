import Accelerate
import CoreML
import Foundation
import Synchronization

/// 本机说话人比对（D11 ②，决定 76/78/80）：WeSpeaker ResNet34（VoxCeleb）转成 Core ML，一段声音出 256 维特征，
/// 跟登记的特征比余弦。登记只存特征数字，不存录音；比对的声音只活在内存里。
/// 只加不减：它只能把「脸差一点」往上抬，单独不放行（闸门的规则在 FaceAutofill.decide，这里不碰）。

// MARK: - 数学

enum SpeakerMath {
    static func norm(_ v: [Float]) -> Float {
        var sum: Float = 0
        vDSP_svesq(v, 1, &sum, vDSP_Length(v.count))
        return sum.squareRoot()
    }

    /// L2 归一化；零向量或含非有限数返回 nil。
    static func normalized(_ v: [Float]) -> [Float]? {
        guard !v.isEmpty, v.allSatisfy(\.isFinite) else { return nil }
        let n = norm(v)
        guard n > 1e-8 else { return nil }
        var out = v
        var divisor = n
        vDSP_vsdiv(v, 1, &divisor, &out, 1, vDSP_Length(v.count))
        return out
    }

    /// 余弦相似度；长度不同、零向量、含非有限数返回 nil。
    static func cosine(_ a: [Float], _ b: [Float]) -> Float? {
        guard a.count == b.count, let x = normalized(a), let y = normalized(b) else { return nil }
        var dot: Float = 0
        vDSP_dotpr(x, 1, y, 1, &dot, vDSP_Length(x.count))
        return dot
    }

    /// 逐个归一化后取平均、再归一化。
    static func meanNormalized(_ vectors: [[Float]]) -> [Float]? {
        guard let first = vectors.first, vectors.allSatisfy({ $0.count == first.count }) else { return nil }
        var sum = [Float](repeating: 0, count: first.count)
        for v in vectors {
            guard let n = normalized(v) else { return nil }
            vDSP_vadd(sum, 1, n, 1, &sum, 1, vDSP_Length(n.count))
        }
        return normalized(sum)
    }
}

// MARK: - 阈值（暂定，要在真机上标定）

enum SpeakerVerification {
    static let modelVersion = "wespeaker-resnet34-vox-fp16-300f-v1"
    static let embeddingSize = 256
    /// 暂定的余弦门槛。模型卡给的 EER 是 VoxCeleb1-O 的**长句**成绩（不是这里念三个词的短句）；
    /// 短句、麦克风、噪声下的实际误识/拒识要在真机上量过再改这个数。取偏严是为了失败即关：宁可拒绝本人，也不放过别人。
    /// 没标定之前它只用来抬「脸差一点」的分数，永远不单独放行。
    static let provisionalCosineThreshold: Float = 0.55
    /// 登记的三句彼此至少要有多像，才当作同一个人在念（挡住中途换人或噪声）。暂定。
    static let provisionalEnrolmentConsistency: Float = 0.35
    static let enrolmentUtterances = 3
    /// 去掉静音后至少要有这么多样本（≈1.2 s）才比；更短的声音信息不够，按用不了。
    static let minimumSpeechSamples = 19_200
    /// 一轮最多处理这么多样本（12 s），超出的丢掉。
    static let maximumSamples = 16_000 * 12
}

// MARK: - 模型

protocol SpeakerEmbedder: Sendable {
    /// `window`：300 × 80 的 CMN 后 fbank，按行排。返回 256 维特征（没归一化）；跑不了返回 nil。
    func embedding(window: [Float]) -> [Float]?
}

/// Core ML 实现。模型是编译好的 `.mlmodelc`（build.sh 从 WindowShade-models 编进 Resources）。
/// MLModel 的 prediction 官方说线程安全；这里再串行化，免得并发把 ANE 挤爆。
final class CoreMLSpeakerEmbedder: SpeakerEmbedder, @unchecked Sendable {
    private let model: MLModel
    private let gate = Mutex(())

    init?(compiledModelURL: URL) {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuAndNeuralEngine
        guard let model = try? MLModel(contentsOf: compiledModelURL, configuration: configuration) else { return nil }
        self.model = model
    }

    func embedding(window: [Float]) -> [Float]? {
        let frames = SpeakerFbank.modelFrames, bins = SpeakerFbank.melBins
        guard window.count == frames * bins,
              let input = try? MLMultiArray(shape: [1, NSNumber(value: frames), NSNumber(value: bins)], dataType: .float32) else { return nil }
        window.withUnsafeBufferPointer { src in
            input.dataPointer.copyMemory(from: src.baseAddress!, byteCount: window.count * MemoryLayout<Float>.size)
        }
        let output: MLFeatureProvider? = gate.withLock { _ in
            try? model.prediction(from: MLDictionaryFeatureProvider(dictionary: ["fbank": MLFeatureValue(multiArray: input)]))
        }
        guard let array = output?.featureValue(for: "embedding")?.multiArrayValue,
              array.count == SpeakerVerification.embeddingSize else { return nil }
        return (0..<array.count).map { array[$0].floatValue }
    }
}

// MARK: - 一段声音 → 一个特征

enum SpeakerEmbedding {
    /// `pcm`：16 kHz 单声道 [-1, 1]。去头尾静音、不够长就不比（nil）、多窗口取平均。
    static func embed(pcm: [Float], using embedder: any SpeakerEmbedder) -> [Float]? {
        guard pcm.count <= SpeakerVerification.maximumSamples * 4 else { return nil }
        let clipped = Array(pcm.prefix(SpeakerVerification.maximumSamples))
        let speech = SpeakerSpeechTrim.trim(clipped)
        guard speech.count >= SpeakerVerification.minimumSpeechSamples else { return nil }
        let frames = SpeakerFbank.frameCount(samples: speech.count)
        let features = SpeakerFbank.cmn(SpeakerFbank.logMel(pcm: speech), frames: frames)
        let windows = SpeakerFbank.windows(cmnFeatures: features, frames: frames)
        guard !windows.isEmpty else { return nil }
        var embeddings: [[Float]] = []
        for window in windows {
            guard let e = embedder.embedding(window: window), e.count == SpeakerVerification.embeddingSize else { return nil }
            embeddings.append(e)
        }
        return SpeakerMath.meanNormalized(embeddings)
    }
}

// MARK: - 登记的特征

/// 登记下来的声音特征：只有数字，没有录音。编码：4 字节魔数 + 版本字符串长度(1) + 版本 + 维数(2, LE) + 句数(1) + Float32 LE。
struct SpeakerTemplate: Equatable, Sendable {
    let modelVersion: String
    let utterances: Int
    /// 已归一化。
    let embedding: [Float]

    init?(modelVersion: String = SpeakerVerification.modelVersion, utterances: Int, embedding: [Float]) {
        guard utterances > 0, utterances <= 255, modelVersion.utf8.count < 200,
              embedding.count == SpeakerVerification.embeddingSize, let n = SpeakerMath.normalized(embedding) else { return nil }
        self.modelVersion = modelVersion
        self.utterances = utterances
        // 已经是单位长度就原样存，编码/解码来回不会再漂一个 ulp。
        self.embedding = abs(SpeakerMath.norm(embedding) - 1) < 1e-5 ? embedding : n
    }

    private static let magic: [UInt8] = Array("WSV1".utf8)

    func encoded() -> Data {
        var data = Data(Self.magic)
        let version = Array(modelVersion.utf8)
        data.append(UInt8(version.count)); data.append(contentsOf: version)
        let dim = UInt16(embedding.count)
        data.append(UInt8(dim & 0xFF)); data.append(UInt8(dim >> 8))
        data.append(UInt8(utterances))
        for value in embedding {
            let bits = value.bitPattern
            for shift in stride(from: 0, to: 32, by: 8) { data.append(UInt8((bits >> UInt32(shift)) & 0xFF)) }
        }
        return data
    }

    /// 读不懂（魔数、长度、维数、版本不对，或有非有限数）就返回 nil，整份作废，不猜。
    static func decode(_ data: Data, expectedVersion: String = SpeakerVerification.modelVersion) -> SpeakerTemplate? {
        let bytes = [UInt8](data)
        guard bytes.count >= 5, Array(bytes[0..<4]) == magic else { return nil }
        let versionLength = Int(bytes[4])
        var cursor = 5
        guard bytes.count >= cursor + versionLength + 3 else { return nil }
        guard let version = String(bytes: bytes[cursor..<cursor + versionLength], encoding: .utf8), version == expectedVersion else { return nil }
        cursor += versionLength
        let dim = Int(bytes[cursor]) | Int(bytes[cursor + 1]) << 8
        let utterances = Int(bytes[cursor + 2])
        cursor += 3
        guard dim == SpeakerVerification.embeddingSize, bytes.count == cursor + dim * 4 else { return nil }
        var values = [Float](); values.reserveCapacity(dim)
        for i in 0..<dim {
            let o = cursor + i * 4
            let bits = UInt32(bytes[o]) | UInt32(bytes[o + 1]) << 8 | UInt32(bytes[o + 2]) << 16 | UInt32(bytes[o + 3]) << 24
            values.append(Float(bitPattern: bits))
        }
        return SpeakerTemplate(modelVersion: version, utterances: utterances, embedding: values)
    }
}

/// 登记特征的存放处。真实现在钥匙串（App/VoiceprintKeychainStore.swift）；存不了就报错，不退回文件。
protocol SpeakerTemplateStoring: Sendable {
    func load() -> SpeakerTemplate?
    func save(_ template: SpeakerTemplate) -> Bool
    func delete() -> Bool
}

// MARK: - 比对

/// 说话人比对的真实现。没有模型或没有登记，`isAvailable` 为 false，上层因此不开麦克风、闸门按用不了处理（失败即关）。
final class CoreMLSpeakerVerifier: SpeakerVerifier, @unchecked Sendable {
    private let embedder: any SpeakerEmbedder
    private let store: any SpeakerTemplateStoring
    let threshold: Float
    private let cache = Mutex<SpeakerTemplate?>(nil)

    init(embedder: any SpeakerEmbedder, store: any SpeakerTemplateStoring,
         threshold: Float = SpeakerVerification.provisionalCosineThreshold) {
        self.embedder = embedder
        self.store = store
        self.threshold = threshold
        refresh()
    }

    /// 登记或删除之后调用，重新读一次。
    func refresh() {
        let template = store.load()
        cache.withLock { $0 = template }
    }

    private var template: SpeakerTemplate? { cache.withLock { $0 } }

    var isEnrolled: Bool { template != nil }
    var isAvailable: Bool { template != nil }

    /// 余弦分数；用不了返回 nil。分数只给判断用，不写日志。
    func score(sample: [Float]) -> Float? {
        guard let template, let embedding = SpeakerEmbedding.embed(pcm: sample, using: embedder) else { return nil }
        return SpeakerMath.cosine(embedding, template.embedding)
    }

    func verify(sample: [Float], purpose: VoiceprintPurpose) -> SpeakerVerdict {
        guard let score = score(sample: sample), score.isFinite else { return .unavailable }
        return score >= threshold ? .sameSpeaker : .differentSpeaker
    }
}

// MARK: - 登记

/// 登记三句：每句念对了字（识别结果跟随机短语一致）、声音够长、三句彼此够像，才做出登记特征。
struct SpeakerEnrolment {
    enum Rejection: String, Equatable, Sendable {
        case wrongPhrase = "wrong-phrase"
        case tooShort = "too-short"
        case modelUnavailable = "model-unavailable"
        case inconsistent = "inconsistent"
    }
    enum Step: Equatable, Sendable {
        case accepted(remaining: Int)
        case complete(SpeakerTemplate)
        case rejected(Rejection)
    }

    private let embedder: any SpeakerEmbedder
    private let consistency: Float
    private var embeddings: [[Float]] = []

    init(embedder: any SpeakerEmbedder, consistency: Float = SpeakerVerification.provisionalEnrolmentConsistency) {
        self.embedder = embedder
        self.consistency = consistency
    }

    var collected: Int { embeddings.count }

    /// 交一句。`heard` 是本机识别听到的字；`sample` 是这句的声音（用完即丢）。
    mutating func add(expected: String, heard: String, sample: [Float]) -> Step {
        guard VoiceprintPhrase.matches(expected: expected, heard: heard) else { return .rejected(.wrongPhrase) }
        guard SpeakerSpeechTrim.trim(sample).count >= SpeakerVerification.minimumSpeechSamples else { return .rejected(.tooShort) }
        guard let embedding = SpeakerEmbedding.embed(pcm: sample, using: embedder) else { return .rejected(.modelUnavailable) }
        for previous in embeddings {
            guard let c = SpeakerMath.cosine(previous, embedding), c >= consistency else { return .rejected(.inconsistent) }
        }
        embeddings.append(embedding)
        if embeddings.count < SpeakerVerification.enrolmentUtterances {
            return .accepted(remaining: SpeakerVerification.enrolmentUtterances - embeddings.count)
        }
        guard let mean = SpeakerMath.meanNormalized(embeddings),
              let template = SpeakerTemplate(utterances: embeddings.count, embedding: mean) else { return .rejected(.modelUnavailable) }
        return .complete(template)
    }
}
