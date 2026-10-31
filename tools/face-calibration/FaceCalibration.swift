// 刷脸门槛标定工具（命令行）。和 App 走同一条特征管线：同样的 Vision 人脸检测与对齐几何
// （prototype/App/FaceEmbedder.swift）、同一个特征后端（VisionFaceEmbedder）、同一套比对规则（FaceScanGuard.ownerScore）。
// 尾部拟合与门槛选择用的是 prototype/Core/FaceThresholdCalibration.swift，App 的单元测试测的是同一份代码。
//
//   embed     把一个图片目录（FFHQ 128px 缩略图）逐张检测、对齐、取特征，写成一个二进制特征文件（不含图像）
//   calibrate 读特征文件和本人样本（genuine.json），算他人/本人分数，拟合他人分数的尾巴，写 JSON + Markdown 报告
//             和可导入的 calibration.json
//   self-test 合成数据把整条流程跑一遍（不要图片、不要相机）
//
// 所有数据都放 /Users/aaron/Documents/WindowShade-models/ 下，不进 git。见 tools/face-calibration/README.md。
import Accelerate
import AVFoundation
import CoreImage
import CoreVideo
import Foundation
import ImageIO
import Vision

// MARK: - 小工具

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data(("face-calibration: " + message + "\n").utf8))
    exit(code)
}

func iso(_ date: Date = Date()) -> String { ISO8601DateFormatter().string(from: date) }

func formatSci(_ value: Double) -> String { String(format: "%.1e", value) }
func f4(_ value: Double) -> String { String(format: "%.4f", value) }
func pct(_ value: Double?) -> String { value.map { String(format: "%.2f%%", $0 * 100) } ?? "n/a" }

func percentile(_ sorted: [Double], _ p: Double) -> Double {
    guard !sorted.isEmpty else { return .nan }
    return sorted[min(sorted.count - 1, max(0, Int((p * Double(sorted.count - 1)).rounded())))]
}

struct SummaryStats: Codable {
    let count: Int
    let min: Double
    let p1: Double
    let p5: Double
    let median: Double
    let p95: Double
    let p99: Double
    let max: Double
    init(_ values: [Double]) {
        let s = values.filter(\.isFinite).sorted()
        count = s.count
        min = s.first ?? .nan; max = s.last ?? .nan
        p1 = percentile(s, 0.01); p5 = percentile(s, 0.05); median = percentile(s, 0.5)
        p95 = percentile(s, 0.95); p99 = percentile(s, 0.99)
    }
}

// MARK: - 图片 → 特征

enum ImageEmbedding {
    enum Outcome { case vector([Float], faceWidth: Double), rejected(String) }

    static func pixelBuffer(from url: URL) -> CVPixelBuffer? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        var buffer: CVPixelBuffer?
        let attributes = [kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()] as CFDictionary
        guard CVPixelBufferCreate(nil, image.width, image.height, kCVPixelFormatType_32BGRA, attributes, &buffer) == kCVReturnSuccess,
              let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: image.width, height: image.height,
                                      bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return buffer
    }

    /// 和 App（以及 FaceFeaturePrintProbe）同一套：只有一张脸、框宽 ≥ minimumFaceWidth、能算出两眼倾角、特征后端给得出向量。
    static func embed(url: URL, embedder: any FaceEmbedder) -> Outcome {
        guard let buffer = pixelBuffer(from: url) else { return .rejected("unreadable") }
        let request = VNDetectFaceLandmarksRequest()
        do { try VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up).perform([request]) } catch { return .rejected("vision-error") }
        let faces = request.results ?? []
        guard faces.count == 1, let face = faces.first else { return .rejected(faces.isEmpty ? "no-face" : "several-faces") }
        guard face.boundingBox.width >= FaceScanTuning().minimumFaceWidth else { return .rejected("face-too-small") }
        let size = CGSize(width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer))
        let geometry = FaceAlignment.geometry(for: face, imageSize: size, aligned: true)
        guard geometry.eyeLineAngle != nil else { return .rejected("no-eyes") }
        guard let vector = embedder.embed(pixelBuffer: buffer, face: geometry) else { return .rejected("embed-nil(pose/size)") }
        return .vector(vector, faceWidth: Double(face.boundingBox.width))
    }
}

/// 并发写结果的盒子：每个下标只被一个任务写，所以不需要锁。
final class SlotArray<T>: @unchecked Sendable {
    private let pointer: UnsafeMutablePointer<T?>
    let count: Int
    init(count: Int) {
        self.count = count
        pointer = .allocate(capacity: count)
        pointer.initialize(repeating: nil, count: count)
    }
    deinit { pointer.deinitialize(count: count); pointer.deallocate() }
    subscript(index: Int) -> T? {
        get { pointer[index] }
        set { pointer[index] = newValue }
    }
}

struct EmbeddingIndex: Codable {
    var format = 1
    let modelVersion: String
    let dimension: Int
    let count: Int
    let source: String
    let createdAt: String
    let totalImages: Int
    let usable: Int
    let rejected: [String: Int]
    let faceWidth: SummaryStats
    let imageWidthPixels: Int?
    let seconds: Double
    /// 与二进制文件一一对应的相对路径（只有文件名，不含任何图像内容）。
    let files: [String]
}

func listImages(in directory: URL) -> [URL] {
    guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil,
                                                          options: [.skipsHiddenFiles]) else { return [] }
    var urls: [URL] = []
    for case let url as URL in enumerator where ["png", "jpg", "jpeg"].contains(url.pathExtension.lowercased()) { urls.append(url) }
    return urls.sorted { $0.path < $1.path }
}

func runEmbed(images: URL, out: URL, limit: Int?, jobs: Int) {
    guard let embedder = FaceEmbedderBackends.make("vision"), VisionFaceEmbedder.isSupported else {
        fail("Vision feature print revision \(VisionFaceEmbedder.revision) unsupported on this Mac", code: 3)
    }
    var urls = listImages(in: images)
    if let limit { urls = Array(urls.prefix(limit)) }
    guard !urls.isEmpty else { fail("no images under \(images.path)", code: 2) }
    let start = Date()
    let results = SlotArray<ImageEmbedding.Outcome>(count: urls.count)
    let done = ProgressCounter(total: urls.count)
    // concurrentPerform 的并发度由系统定；jobs 只限制同时在飞的块数。
    let chunk = max(1, urls.count / max(1, jobs * 8))
    let blocks = (urls.count + chunk - 1) / chunk
    DispatchQueue.concurrentPerform(iterations: blocks) { block in
        for index in (block * chunk)..<min(urls.count, (block + 1) * chunk) {
            results[index] = autoreleasepool { ImageEmbedding.embed(url: urls[index], embedder: embedder) }
            done.advance()
        }
    }
    var vectors: [Float] = []
    var files: [String] = []
    var rejected: [String: Int] = [:]
    var widths: [Double] = []
    var dimension = 0
    for (index, url) in urls.enumerated() {
        switch results[index] {
        case .vector(let vector, let width)?:
            if dimension == 0 { dimension = vector.count }
            guard vector.count == dimension else { rejected["dimension-mismatch", default: 0] += 1; continue }
            vectors += vector; files.append(url.lastPathComponent); widths.append(width)
        case .rejected(let reason)?: rejected[reason, default: 0] += 1
        case nil: rejected["no-result", default: 0] += 1
        }
    }
    let seconds = Date().timeIntervalSince(start)
    let index = EmbeddingIndex(modelVersion: embedder.modelVersion, dimension: dimension, count: files.count,
                               source: images.path, createdAt: iso(), totalImages: urls.count, usable: files.count,
                               rejected: rejected, faceWidth: SummaryStats(widths),
                               imageWidthPixels: ImageEmbedding.pixelBuffer(from: urls[0]).map { CVPixelBufferGetWidth($0) },
                               seconds: seconds, files: files)
    do {
        try FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
        let binary = vectors.withUnsafeBufferPointer { Data(buffer: $0) }
        try binary.write(to: out.appendingPathExtension("f32"), options: .atomic)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(index).write(to: out.appendingPathExtension("json"), options: .atomic)
    } catch { fail("cannot write embeddings: \(error)") }
    print(String(format: "embed: %d/%d usable (%.1f%%) in %.1f s (%.1f img/s); rejected=%@; model=%@ dim=%d",
                 files.count, urls.count, 100 * Double(files.count) / Double(urls.count), seconds, Double(urls.count) / max(seconds, 1e-9),
                 "\(rejected)", embedder.modelVersion, dimension))
}

final class ProgressCounter: @unchecked Sendable {
    private let queue = DispatchQueue(label: "progress")
    private var count = 0
    private let total: Int
    init(total: Int) { self.total = total }
    func advance() {
        queue.async {
            self.count += 1
            if self.count % 2000 == 0 || self.count == self.total {
                FileHandle.standardError.write(Data("embed: \(self.count)/\(self.total)\n".utf8))
            }
        }
    }
}

// MARK: - 标定

struct CalibrationConfig {
    var enrollees = 2000
    var bootstrapReplicates = 300
    var pooledTailFraction = 0.002
    var aaronTailFraction = 0.02
    var targets: [Double] = [2e-5, 1e-6]
    var seed: UInt64 = 20261031
}

struct TailResult: Codable {
    let targetFAR: Double
    let point: Double?
    let low90: Double?
    let high90: Double?
    let method: String
    let impostorsAboveInSample: Int?
}

struct DistributionReport: Codable {
    let label: String
    let scores: SummaryStats
    let sampleCount: Int
    let enrollees: Int?
    let tailStart: Double?
    let exceedances: Int?
    let xi: Double?
    let sigma: Double?
    let tails: [TailResult]
    let ruleOfThreeFAR: Double
}

struct GenuineReport: Codable {
    let probeCount: Int
    let templateCount: Int
    let templateSource: String
    let scores: SummaryStats
    let perStep: [String: SummaryStats]
}

struct OperatingPoint: Codable {
    let targetFAR: Double
    let threshold: Double
    let basis: String
    let falseRejectRate: Double?
    let falseRejectByStep: [String: Double]?
    let reachable: Bool
}

struct CalibrationReport: Codable {
    let createdAt: String
    let modelVersion: String
    let currentThreshold: Double
    let embeddingSource: String
    let embeddingImages: Int
    let embeddingUsable: Int
    let embeddingRejected: [String: Int]
    let imageWidthPixels: Int?
    let secondsEmbedding: Double
    let pooled: DistributionReport
    let aaron: DistributionReport?
    let genuine: GenuineReport?
    let operatingPoints: [OperatingPoint]
    let provisional: Bool
    let recommendedThreshold: Double?
    let currentThresholdFalseRejectRate: Double?
    let notes: [String]
}

enum Calibrator {
    /// 行主序矩阵，每行一个已 L2 归一化的向量。
    struct Matrix {
        var data: [Float]
        let dimension: Int
        var count: Int { dimension == 0 ? 0 : data.count / dimension }
        func row(_ i: Int) -> [Float] { Array(data[(i * dimension)..<((i + 1) * dimension)]) }
    }

    static func histogramQuantile(_ histogram: [Int], total: Int, fractionAbove: Double) -> Double {
        // 把区间 [-1, 1] 切成 histogram.count 格；返回使“高于它”的比例约为 fractionAbove 的格上沿。
        var above = 0
        let want = Int((Double(total) * fractionAbove).rounded(.up))
        for bin in stride(from: histogram.count - 1, through: 0, by: -1) {
            above += histogram[bin]
            if above >= want { return -1 + 2 * Double(bin) / Double(histogram.count) }
        }
        return -1
    }

    /// 伪登记者 × 全部样本的余弦。vDSP/BLAS 分块做，避免一次占满内存。
    static func forEachScoreBlock(matrix m: Matrix, enrolleeIndices: [Int], body: (_ enrollee: Int, _ scores: UnsafeBufferPointer<Float>) -> Void) {
        let n = m.count, d = m.dimension
        let block = 64
        var scores = [Float](repeating: 0, count: block * n)
        var start = 0
        while start < enrolleeIndices.count {
            let end = min(enrolleeIndices.count, start + block)
            let k = end - start
            var enrollees = [Float](repeating: 0, count: k * d)
            for (row, index) in enrolleeIndices[start..<end].enumerated() {
                enrollees.replaceSubrange((row * d)..<((row + 1) * d), with: m.data[(index * d)..<((index + 1) * d)])
            }
            // C(k×n) = E(k×d) · X(n×d)^T
            cblas_sgemm(CblasRowMajor, CblasNoTrans, CblasTrans, Int32(k), Int32(n), Int32(d), 1, enrollees, Int32(d),
                        m.data, Int32(d), 0, &scores, Int32(n))
            for row in 0..<k {
                let enrollee = enrolleeIndices[start + row]
                scores.withUnsafeBufferPointer { body(enrollee, UnsafeBufferPointer(rebasing: $0[(row * n)..<((row + 1) * n)])) }
            }
            start = end
        }
    }

    static func tail(label: String, targets: [Double], fit: GPDTailFit?, scores: [Double]) -> [TailResult] {
        targets.map { target in
            let choice = FaceThresholdSelection.choose(scores: scores, targetFAR: target, fit: fit)
            return TailResult(targetFAR: target, point: choice?.threshold, low90: nil, high90: nil,
                              method: choice?.method.rawValue ?? "unavailable", impostorsAboveInSample: choice?.impostorsAbove)
        }
    }

    static func run(matrix m: Matrix, modelVersion: String, genuine: FaceGenuineSamples?, config: CalibrationConfig,
                    embeddingIndex: EmbeddingIndex?) -> (CalibrationReport, FaceThresholdCalibration?) {
        var rng = FaceThresholdBootstrap.SplitMix64(seed: config.seed)
        let n = m.count
        var notes: [String] = []

        // ① 伪登记者：随机挑 K 张 FFHQ 脸各自当“一个人的模板”，对其余所有人算分数。
        let k = min(config.enrollees, n)
        var picked = Set<Int>()
        while picked.count < k { picked.insert(Int(rng.next() % UInt64(n))) }
        let enrolleeIndices = picked.sorted()
        var histogram = [Int](repeating: 0, count: 200_000)
        var total = 0
        forEachScoreBlock(matrix: m, enrolleeIndices: enrolleeIndices) { enrollee, scores in
            for (i, s) in scores.enumerated() where i != enrollee && s.isFinite {
                histogram[min(histogram.count - 1, max(0, Int((Double(s) + 1) / 2 * Double(histogram.count))))] += 1
                total += 1
            }
        }
        let location = histogramQuantile(histogram, total: total, fractionAbove: config.pooledTailFraction)
        var groups: [FaceImpostorGroup] = []
        var sampleScores: [Double] = []   // 抽一部分做汇总统计
        forEachScoreBlock(matrix: m, enrolleeIndices: enrolleeIndices) { enrollee, scores in
            var top: [Double] = []
            for (i, s) in scores.enumerated() where i != enrollee && s.isFinite {
                if Double(s) > location { top.append(Double(s)) }
                if i % 97 == 0 { sampleScores.append(Double(s)) }
            }
            top.sort(by: >)
            groups.append(FaceImpostorGroup(topScores: top, totalCount: n - 1))
        }
        let pooledExcesses = groups.flatMap { $0.topScores.map { $0 - location } }
        let pooledFit = FaceTailFit.fit(excesses: pooledExcesses, location: location, sampleCount: total)
        let pooledPoint = FaceThresholdBootstrap.thresholds(groups: groups, location: location, targets: config.targets)
        let pooledCI = FaceThresholdBootstrap.intervals(groups: groups, location: location, targets: config.targets,
                                                        replicates: config.bootstrapReplicates, seed: config.seed)
        let pooledEmpirical: [Int?] = config.targets.map { target in
            guard let p = pooledPoint[config.targets.firstIndex(of: target)!] else { return nil }
            return groups.reduce(0) { $0 + $1.topScores.filter { $0 > p }.count }
        }
        let pooledTails = config.targets.indices.map { i in
            TailResult(targetFAR: config.targets[i], point: pooledPoint[i], low90: pooledCI[i]?.low, high90: pooledCI[i]?.high,
                       method: "GPD(PWM) on pooled pseudo-enrollee tail, cluster bootstrap over enrollees",
                       impostorsAboveInSample: pooledEmpirical[i])
        }
        let pooled = DistributionReport(
            label: "FFHQ vs FFHQ (single-image pseudo-enrollees)", scores: SummaryStats(sampleScores), sampleCount: total,
            enrollees: k, tailStart: location, exceedances: pooledExcesses.count, xi: pooledFit?.xi, sigma: pooledFit?.sigma,
            tails: pooledTails, ruleOfThreeFAR: FaceThresholdSelection.ruleOfThree(sampleCount: n) ?? .nan)

        // ② 本人：用 App 自己的守卫算分数（平均模板与最近一次录入取小）。
        var aaron: DistributionReport?
        var genuineReport: GenuineReport?
        var genuineScores: [Double] = []
        var genuineByStep: [String: [Double]] = [:]
        var aaronScores: [Double] = []
        if let genuine {
            var templates = genuine.templateVectors()
            var probes = genuine.probeVectors()
            var source = "keychain enrolment recorded with the samples"
            if templates.isEmpty {
                let front = probes.enumerated().filter { $0.element.step == "front" }.prefix(10).map(\.offset)
                templates = front.map { probes[$0].vector }
                let drop = Set(front)
                probes = probes.enumerated().filter { !drop.contains($0.offset) }.map(\.element)
                source = "first \(front.count) front-facing frames (no keychain enrolment was recorded)"
                notes.append("No enrolled templates were stored with genuine.json, so the first front-facing frames stand in for the enrolment; the real enrolment may score better or worse.")
            }
            let faceTemplates = templates.enumerated().map {
                FaceTemplate(embedding: $0.element, modelVersion: modelVersion, enrolledAt: Double($0.offset + 1), eyeOpenness: nil)
            }
            let guardian = FaceScanGuard(templates: faceTemplates)
            for probe in probes {
                if let s = guardian.ownerScore(probe.vector, modelVersion: modelVersion) {
                    genuineScores.append(Double(s)); genuineByStep[probe.step, default: []].append(Double(s))
                }
            }
            for i in 0..<n {
                if let s = guardian.ownerScore(m.row(i), modelVersion: modelVersion) { aaronScores.append(Double(s)) }
            }
            genuineReport = GenuineReport(probeCount: genuineScores.count, templateCount: templates.count, templateSource: source,
                                          scores: SummaryStats(genuineScores), perStep: genuineByStep.mapValues(SummaryStats.init))
            let fit = FaceTailFit.fit(scores: aaronScores, tailFraction: config.aaronTailFraction)
            var tails = tail(label: "aaron", targets: config.targets, fit: fit, scores: aaronScores)
            // 非聚类自助：这些分数来自不同的人，对同一份模板近似独立。
            for (i, target) in config.targets.enumerated() {
                var values: [Double] = []
                var local = FaceThresholdBootstrap.SplitMix64(seed: config.seed &+ UInt64(i) &+ 1)
                for _ in 0..<min(config.bootstrapReplicates, 200) {
                    let resample = (0..<aaronScores.count).map { _ in aaronScores[Int(local.next() % UInt64(aaronScores.count))] }
                    if let f = FaceTailFit.fit(scores: resample, tailFraction: config.aaronTailFraction),
                       let c = FaceThresholdSelection.choose(scores: resample, targetFAR: target, fit: f) { values.append(c.threshold) }
                }
                values.sort()
                if values.count >= 20 {
                    tails[i] = TailResult(targetFAR: target, point: tails[i].point, low90: percentile(values, 0.05), high90: percentile(values, 0.95),
                                          method: tails[i].method, impostorsAboveInSample: tails[i].impostorsAboveInSample)
                }
            }
            aaron = DistributionReport(label: "FFHQ vs the recorded enrolment template", scores: SummaryStats(aaronScores),
                                       sampleCount: aaronScores.count, enrollees: 1, tailStart: fit?.location, exceedances: fit?.exceedanceCount,
                                       xi: fit?.xi, sigma: fit?.sigma, tails: tails,
                                       ruleOfThreeFAR: FaceThresholdSelection.ruleOfThree(sampleCount: aaronScores.count) ?? .nan)
        } else {
            notes.append("No genuine samples yet: these numbers are impostor-only and PROVISIONAL. Run `FaceCalibrate record` (app flag --face-calibrate-record) and calibrate again.")
        }

        // ③ 工作点：每个目标取 池化聚类自助的 90% 上界 与 本人点估计 中较大的（偏保守）。
        var operating: [OperatingPoint] = []
        for (i, target) in config.targets.enumerated() {
            var candidates: [(Double, String)] = []
            if let high = pooledTails[i].high90 { candidates.append((high, "pooled bootstrap upper 90% bound")) }
            else if let p = pooledTails[i].point { candidates.append((p, "pooled point estimate")) }
            if let a = aaron?.tails[i].point { candidates.append((a, "enrolment-specific point estimate")) }
            guard let best = candidates.max(by: { $0.0 < $1.0 }) else { continue }
            let frr = genuineScores.isEmpty ? nil : FaceThresholdSelection.falseRejectRate(genuine: genuineScores, threshold: best.0)
            let byStep = genuineByStep.isEmpty ? nil : genuineByStep.compactMapValues { FaceThresholdSelection.falseRejectRate(genuine: $0, threshold: best.0) }
            operating.append(OperatingPoint(targetFAR: target, threshold: best.0, basis: best.1, falseRejectRate: frr,
                                            falseRejectByStep: byStep, reachable: best.0 < 1))
        }
        let current = Double(FaceScanModelProfile.visionFeaturePrint.similarityThreshold)
        let currentFRR = genuineScores.isEmpty ? nil : FaceThresholdSelection.falseRejectRate(genuine: genuineScores, threshold: current)
        let provisional = genuineScores.isEmpty
        notes.append("Direct evidence stops at the rule of three: with \(n) distinct faces a measured zero-false-accept run only demonstrates a false accept rate of about \(formatSci(FaceThresholdSelection.ruleOfThree(sampleCount: n) ?? .nan)) (95% confidence). Anything stricter (2e-5, 1e-6) is an extrapolation of the fitted tail.")
        notes.append("Domain gap: FFHQ is aligned Flickr portraits downsampled to 128 px; the Mac camera gives 640x480 video frames with indoor light, a different pose spread and sensor noise. The impostor scores here are therefore an estimate, not a measurement of the live system.")
        notes.append("Pseudo-enrollees use one FFHQ image as their template; a real enrolment averages several frames of one person, which changes the impostor score distribution somewhat.")
        notes.append("FFHQ faces are pre-aligned and frontal, which tends to make impostors look more alike than random live poses do (conservative for FAR), but it says nothing about look-alikes, relatives or twins.")
        notes.append("The score is Apple's generic Vision image feature print (revision 2) on a face crop, not a face-recognition embedding. The gate also requires the second factor, so the face-only figure is not the end-to-end FAR.")

        let report = CalibrationReport(
            createdAt: iso(), modelVersion: modelVersion, currentThreshold: current, embeddingSource: embeddingIndex?.source ?? "synthetic",
            embeddingImages: embeddingIndex?.totalImages ?? n, embeddingUsable: embeddingIndex?.usable ?? n,
            embeddingRejected: embeddingIndex?.rejected ?? [:], imageWidthPixels: embeddingIndex?.imageWidthPixels,
            secondsEmbedding: embeddingIndex?.seconds ?? 0, pooled: pooled, aaron: aaron, genuine: genuineReport,
            operatingPoints: operating, provisional: provisional,
            recommendedThreshold: operating.first(where: { $0.targetFAR == config.targets.first })?.threshold,
            currentThresholdFalseRejectRate: currentFRR, notes: notes)

        var calibration: FaceThresholdCalibration?
        if let first = operating.first, first.reachable, first.threshold >= Double(FaceThresholdCalibration.minimumThreshold) {
            let strict = operating.count > 1 && operating[1].reachable ? Float(operating[1].threshold) : nil
            calibration = FaceThresholdCalibration(
                modelVersion: modelVersion, threshold: Float(first.threshold), targetFAR: first.targetFAR,
                strictThreshold: strict.map { max($0, Float(first.threshold)) }, strictTargetFAR: strict == nil ? nil : operating[1].targetFAR,
                falseRejectRate: first.falseRejectRate, genuineSampleCount: genuineScores.isEmpty ? nil : genuineScores.count,
                impostorSampleCount: aaronScores.isEmpty ? total : aaronScores.count, calibratedAt: iso(),
                method: (provisional ? "PROVISIONAL (no genuine samples) " : "") + "FFHQ-128 impostor tail, GPD (PWM), \(first.basis)")
        }
        return (report, calibration)
    }
}

// MARK: - 报告

func markdown(_ r: CalibrationReport) -> String {
    var s = "# Face threshold calibration\n\n"
    s += "Generated \(r.createdAt) for model `\(r.modelVersion)`. "
    s += r.provisional ? "**PROVISIONAL: impostor scores only, no genuine samples.**\n\n" : "Genuine samples included.\n\n"
    s += "Embedding set: \(r.embeddingUsable) usable of \(r.embeddingImages) images (source `\(r.embeddingSource)`, width \(r.imageWidthPixels.map(String.init) ?? "?") px, \(String(format: "%.0f", r.secondsEmbedding)) s). Rejected: \(r.embeddingRejected).\n\n"
    s += "## Operating points\n\n| Target FAR | Threshold | Basis | False reject on genuine | Reachable |\n|---|---|---|---|---|\n"
    for o in r.operatingPoints {
        s += "| \(formatSci(o.targetFAR)) | \(f4(o.threshold)) | \(o.basis) | \(pct(o.falseRejectRate)) | \(o.reachable ? "yes" : "no (needs > 1)") |\n"
    }
    s += "\nCurrent placeholder threshold \(f4(r.currentThreshold)): false reject on genuine \(pct(r.currentThresholdFalseRejectRate)).\n\n"
    for d in [r.pooled] + (r.aaron.map { [$0] } ?? []) {
        s += "## Impostor tail: \(d.label)\n\n"
        s += "\(d.sampleCount) scores" + (d.enrollees.map { " over \($0) enrollee(s)" } ?? "") + ". Score summary: min \(f4(d.scores.min)), p50 \(f4(d.scores.median)), p95 \(f4(d.scores.p95)), p99 \(f4(d.scores.p99)), max \(f4(d.scores.max)).\n"
        if let u = d.tailStart, let xi = d.xi, let sigma = d.sigma, let n = d.exceedances {
            s += "GPD tail above \(f4(u)) with \(n) exceedances: xi = \(String(format: "%.3f", xi)), sigma = \(String(format: "%.4f", sigma)). Rule-of-three limit for \(d.label.contains("pooled") ? "distinct faces" : "this sample"): \(formatSci(d.ruleOfThreeFAR)).\n\n"
        }
        s += "| Target FAR | Threshold (point) | 90% interval | Method | Impostors above in sample |\n|---|---|---|---|---|\n"
        for t in d.tails {
            let ci = (t.low90.map(f4) ?? "-") + " to " + (t.high90.map(f4) ?? "-")
            s += "| \(formatSci(t.targetFAR)) | \(t.point.map(f4) ?? "n/a") | \(ci) | \(t.method) | \(t.impostorsAboveInSample.map(String.init) ?? "n/a") |\n"
        }
        s += "\n"
    }
    if let g = r.genuine {
        s += "## Genuine samples\n\n\(g.probeCount) probes against \(g.templateCount) templates (\(g.templateSource)). Score min \(f4(g.scores.min)), p5 \(f4(g.scores.p5)), median \(f4(g.scores.median)), max \(f4(g.scores.max)).\n\n"
        s += "| Step | n | min | p5 | median |\n|---|---|---|---|---|\n"
        for (step, st) in g.perStep.sorted(by: { $0.key < $1.key }) { s += "| \(step) | \(st.count) | \(f4(st.min)) | \(f4(st.p5)) | \(f4(st.median)) |\n" }
        s += "\n"
        for o in r.operatingPoints {
            if let by = o.falseRejectByStep {
                s += "False reject by step at FAR \(formatSci(o.targetFAR)) (threshold \(f4(o.threshold))): " + by.sorted { $0.key < $1.key }.map { "\($0.key) \(pct($0.value))" }.joined(separator: ", ") + "\n\n"
            }
        }
    }
    s += "## Limits\n\n" + r.notes.map { "- \($0)" }.joined(separator: "\n") + "\n"
    return s
}

func writeOutputs(_ report: CalibrationReport, _ calibration: FaceThresholdCalibration?, to directory: URL) {
    do {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(to: directory.appendingPathComponent("calibration-report.json"), options: .atomic)
        try markdown(report).write(to: directory.appendingPathComponent("calibration-report.md"), atomically: true, encoding: .utf8)
        if let calibration, let data = calibration.encoded() {
            let name = report.provisional ? "calibration.provisional.json" : "calibration.json"
            try data.write(to: directory.appendingPathComponent(name), options: .atomic)
            print("wrote \(name): threshold=\(calibration.threshold) targetFAR=\(calibration.targetFAR)")
        } else { print("no importable calibration written (threshold unreachable or no fit)") }
    } catch { fail("cannot write report: \(error)") }
}

func loadMatrix(prefix: URL) -> (Calibrator.Matrix, EmbeddingIndex) {
    guard let indexData = try? Data(contentsOf: prefix.appendingPathExtension("json")),
          let index = try? JSONDecoder().decode(EmbeddingIndex.self, from: indexData),
          let binary = try? Data(contentsOf: prefix.appendingPathExtension("f32")),
          index.dimension > 0, binary.count == index.count * index.dimension * 4 else { fail("cannot read embeddings at \(prefix.path)", code: 2) }
    let floats = binary.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    return (Calibrator.Matrix(data: floats, dimension: index.dimension), index)
}

// MARK: - 自检（合成数据，不要图片、相机）

var selfFailures = 0
func check(_ ok: Bool, _ text: String) { if ok { print("ok   \(text)") } else { selfFailures += 1; print("FAIL \(text)") } }

func selfTest() -> Int32 {
    var rng = FaceThresholdBootstrap.SplitMix64(seed: 5)
    func gauss() -> Float {
        let u1 = max(1e-12, Double(rng.next() >> 11) / 9007199254740992.0), u2 = Double(rng.next() >> 11) / 9007199254740992.0
        return Float(sqrt(-2 * log(u1)) * cos(2 * .pi * u2))
    }
    func normalize(_ v: [Float]) -> [Float] { let n = v.reduce(0) { $0 + $1 * $1 }.squareRoot(); return v.map { $0 / n } }
    let d = 48, n = 4000
    // 真实的 Vision 特征互相都很像（余弦基线很高）：给所有向量加一个共同分量来模拟。
    let common = (0..<d).map { _ in 3 * gauss() }
    func person() -> [Float] { normalize(zip(common, (0..<d).map { _ in gauss() }).map { $0 + $1 }) }
    var data: [Float] = []
    for _ in 0..<n { data += person() }
    let matrix = Calibrator.Matrix(data: data, dimension: d)
    let me = person()
    func noisy(_ amount: Float) -> [Float] { normalize(zip(me, (0..<d).map { _ in gauss() }).map { $0 + amount * $1 / Float(d).squareRoot() * 0.2 }) }
    let version = FaceScanModelProfile.visionFeaturePrintVersion
    let samples = FaceGenuineSamples(
        modelVersion: version, recordedAt: iso(), templates: (0..<4).map { _ in FaceTemplateSet.bytes(noisy(0.3)) },
        probes: (0..<120).map { FaceGenuineSamples.Probe(step: $0 % 2 == 0 ? "front" : "left", embedding: FaceTemplateSet.bytes(noisy(0.5))) })
    var config = CalibrationConfig(); config.enrollees = 200; config.bootstrapReplicates = 60
    config.targets = [2e-5, 1e-6]
    let (report, calibration) = Calibrator.run(matrix: matrix, modelVersion: version, genuine: samples, config: config, embeddingIndex: nil)
    print("info genuine median \(report.genuine?.scores.median ?? .nan) min \(report.genuine?.scores.min ?? .nan); aaron max \(report.aaron?.scores.max ?? .nan); operating \(report.operatingPoints.map { $0.threshold })")
    check(report.pooled.sampleCount == 200 * (n - 1), "pooled pass scored every enrollee against every other face")
    check(report.operatingPoints.count == 2 && report.operatingPoints[0].threshold < report.operatingPoints[1].threshold, "the stricter target needs a higher threshold")
    check((report.genuine?.scores.median ?? 0) > 0.7, "genuine scores are high")
    check((report.operatingPoints[0].falseRejectRate ?? 1) < 0.2, "false reject at 2e-5 is small on a clearly separable synthetic user")
    check((report.aaron?.scores.max ?? 1) < (report.genuine?.scores.median ?? 0), "impostors against the user's template stay below the genuine median")
    check(!report.provisional && calibration != nil, "an importable calibration comes out when genuine samples exist")
    // 比对规则就是 App 的守卫：模板自己对自己是 1。
    let guardian = FaceScanGuard(templates: [FaceTemplate(embedding: me, modelVersion: version, enrolledAt: 1, eyeOpenness: nil)])
    check(abs((guardian.ownerScore(me, modelVersion: version) ?? 0) - 1) < 1e-5, "FaceScanGuard.ownerScore of a template against itself is 1")
    let (provisional, provCalibration) = Calibrator.run(matrix: matrix, modelVersion: version, genuine: nil, config: config, embeddingIndex: nil)
    check(provisional.provisional && provisional.genuine == nil && (provCalibration?.method.hasPrefix("PROVISIONAL") ?? false), "without genuine samples everything is marked provisional")
    check(provisional.notes.contains { $0.contains("rule of three") } && provisional.notes.contains { $0.contains("Domain gap") }, "report states the rule-of-three limit and the domain gap")
    let md = markdown(report)
    check(md.contains("## Operating points") && md.contains("## Limits"), "markdown report renders")
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fc-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: dir) }
    writeOutputs(report, calibration, to: dir)
    let json = try? Data(contentsOf: dir.appendingPathComponent("calibration.json"))
    check(json.flatMap { FaceThresholdCalibration.decode($0) } != nil, "calibration.json passes the same validation the app applies on import")
    // 嵌入真跑一次（合成图不是人脸，应当被拒，不崩）。
    if VisionFaceEmbedder.isSupported, let embedder = FaceEmbedderBackends.make("vision") {
        let blank = dir.appendingPathComponent("blank.png")
        if let context = CGContext(data: nil, width: 128, height: 128, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
           let image = context.makeImage(), let dest = CGImageDestinationCreateWithURL(blank as CFURL, "public.png" as CFString, 1, nil) {
            CGImageDestinationAddImage(dest, image, nil); CGImageDestinationFinalize(dest)
            if case .rejected(let reason) = ImageEmbedding.embed(url: blank, embedder: embedder) { check(reason == "no-face", "a blank image is rejected as no-face") }
            else { check(false, "a blank image must not produce an embedding") }
        }
    }
    return selfFailures == 0 ? 0 : 1
}

// MARK: - main

@main struct FaceCalibrationTool {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        func value(_ flag: String) -> String? { args.firstIndex(of: flag).flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil } }
        let models = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/WindowShade-models", isDirectory: true)
        switch args.first {
        case "self-test":
            let code = selfTest()
            print(code == 0 ? "PASS face-calibration self-test" : "FAIL face-calibration self-test")
            exit(code)
        case "embed":
            let images = URL(fileURLWithPath: value("--images") ?? models.appendingPathComponent("ffhq/thumbnails128x128").path)
            let out = URL(fileURLWithPath: value("--out") ?? models.appendingPathComponent("calibration/ffhq-embeddings").path)
            runEmbed(images: images, out: out, limit: value("--limit").flatMap(Int.init),
                     jobs: value("--jobs").flatMap(Int.init) ?? ProcessInfo.processInfo.activeProcessorCount)
        case "calibrate":
            let dir = URL(fileURLWithPath: value("--out") ?? models.appendingPathComponent("calibration").path, isDirectory: true)
            let prefix = URL(fileURLWithPath: value("--embeddings") ?? dir.appendingPathComponent("ffhq-embeddings").path)
            let genuinePath = value("--genuine") ?? dir.appendingPathComponent("genuine.json").path
            let (matrix, index) = loadMatrix(prefix: prefix)
            let genuine = FileManager.default.contents(atPath: genuinePath).flatMap(FaceGenuineSamples.decode)
            if let genuine, genuine.modelVersion != index.modelVersion { fail("genuine samples were made with model \(genuine.modelVersion), embeddings with \(index.modelVersion)", code: 2) }
            if FileManager.default.fileExists(atPath: genuinePath), genuine == nil { fail("cannot read genuine samples at \(genuinePath)", code: 2) }
            var config = CalibrationConfig()
            if let v = value("--enrollees").flatMap(Int.init) { config.enrollees = v }
            if let v = value("--bootstrap").flatMap(Int.init) { config.bootstrapReplicates = v }
            let start = Date()
            let (report, calibration) = Calibrator.run(matrix: matrix, modelVersion: index.modelVersion, genuine: genuine, config: config, embeddingIndex: index)
            writeOutputs(report, calibration, to: dir)
            print(String(format: "calibrate: %.1f s; provisional=%@; operating points: %@", Date().timeIntervalSince(start), "\(report.provisional)",
                         report.operatingPoints.map { "FAR \(formatSci($0.targetFAR)) -> \(f4($0.threshold)) (FRR \(pct($0.falseRejectRate)))" }.joined(separator: "; ")))
        default:
            print("usage: FaceCalibration self-test | embed [--images DIR] [--out PREFIX] [--limit N] | calibrate [--embeddings PREFIX] [--genuine FILE] [--out DIR] [--enrollees K] [--bootstrap B]")
            exit(64)
        }
    }
}
