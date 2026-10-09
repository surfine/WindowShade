// 刷脸实验的阈值标定探针（P-FACE-FP）。和 App 走同一条特征管线：同样的人脸检测与对齐几何
// （prototype/App/FaceEmbedder.swift），同样的后端选择（FaceEmbedderBackends，--backend vision|arcface）。
//
// 相机模式：Aaron 在场、明确授权相机。先录 N 帧当模板（只在内存里），再采同一个人的更多帧，
// 然后按 Enter 换一轮（另一个人，或同一个人换个时间/光线），每轮只打印余弦的汇总统计。
// 不存图像、不打印向量、不写文件；退出即全部丢弃。
// 自检模式（--self-test）：不开相机，只测几何、归一化、统计，并在合成图上真跑一次 Vision 特征。
import AVFoundation
import CoreImage
import Foundation
import Vision

enum ProbeStats {
    /// 最近秩百分位（p 在 0...1）。
    static func percentile(_ sorted: [Float], _ p: Double) -> Float {
        guard !sorted.isEmpty else { return .nan }
        let rank = Int((p * Double(sorted.count)).rounded(.up))
        return sorted[min(max(rank - 1, 0), sorted.count - 1)]
    }

    static func summary(_ values: [Float]) -> String {
        let s = values.sorted()
        guard !s.isEmpty else { return "n=0" }
        func f(_ x: Float) -> String { String(format: "%.4f", x) }
        return "n=\(s.count) min=\(f(s[0])) p5=\(f(percentile(s, 0.05))) median=\(f(percentile(s, 0.5))) p95=\(f(percentile(s, 0.95))) max=\(f(s[s.count - 1]))"
    }

    /// 本人分数的 p5 与他人分数的最大值之间取中点；两者重叠就不给建议。
    static func suggest(genuine: [Float], impostor: [Float]) -> (threshold: Float, margin: Float)? {
        guard !genuine.isEmpty, let worstImpostor = impostor.max() else { return nil }
        let low = percentile(genuine.sorted(), 0.05)
        let margin = low - worstImpostor
        guard margin > 0 else { return nil }
        return ((low + worstImpostor) / 2, margin)
    }

    static func fraction(_ values: [Float], atLeast threshold: Float) -> String {
        guard !values.isEmpty else { return "n/a" }
        return String(format: "%.1f%%", 100 * Double(values.filter { $0 >= threshold }.count) / Double(values.count))
    }
}

/// 守卫的判法：同时比平均模板和最近一次录入，两者都要过阈值，所以有效分数取两者较小者。
func ownerScore(_ embedding: [Float], templates: [[Float]]) -> Float? {
    guard let latest = templates.last, !templates.isEmpty else { return nil }
    var mean = [Float](repeating: 0, count: latest.count)
    for t in templates { for i in mean.indices { mean[i] += t[i] } }
    guard let toMean = FaceScanGuard.cosine(embedding, mean), let toLatest = FaceScanGuard.cosine(embedding, latest)
    else { return nil }
    return min(toMean, toLatest)
}

// MARK: - 相机

final class FrameCollector: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let queue = DispatchQueue(label: "probe.face.featureprint", qos: .userInitiated)
    private let embedder: any FaceEmbedder
    private let lock = NSLock()
    private var wanted = 0
    private var collected: [[Float]] = []
    private var done: DispatchSemaphore?
    private var lastAccepted = 0.0
    private(set) var rejected: [String: Int] = [:]

    init(embedder: any FaceEmbedder) { self.embedder = embedder }

    /// 收满 count 帧或超时就返回（只返回特征，帧本身随即丢弃）。
    func collect(_ count: Int, timeout: Double) -> [[Float]] {
        let semaphore = DispatchSemaphore(value: 0)
        lock.lock(); wanted = count; collected = []; done = semaphore; rejected = [:]; lock.unlock()
        _ = semaphore.wait(timeout: .now() + timeout)
        lock.lock(); defer { lock.unlock() }
        wanted = 0; done = nil
        return collected
    }

    private func reject(_ reason: String) { lock.lock(); rejected[reason, default: 0] += 1; lock.unlock() }

    func captureOutput(_ output: AVCaptureOutput, didOutput sample: CMSampleBuffer, from connection: AVCaptureConnection) {
        lock.lock(); let active = wanted > collected.count; lock.unlock()
        guard active, let buffer = sample.imageBuffer else { return }
        let now = CACurrentMediaTime()
        guard now - lastAccepted >= 0.3 else { return }
        let request = VNDetectFaceLandmarksRequest()
        do { try VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up).perform([request]) }
        catch { reject("vision"); return }
        let faces = request.results ?? []
        guard faces.count == 1, let face = faces.first else { reject(faces.isEmpty ? "no-face" : "several-faces"); return }
        guard face.boundingBox.width >= 0.18 else { reject("face-too-small"); return }
        let size = CGSize(width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer))
        let geometry = FaceAlignment.geometry(for: face, imageSize: size, aligned: true)
        guard geometry.eyeLineAngle != nil else { reject("no-eyes"); return }
        guard let vector = embedder.embed(pixelBuffer: buffer, face: geometry) else {
            reject("embed-nil(pose/size/model)"); return
        }
        lastAccepted = now
        lock.lock()
        collected.append(vector)
        let finished = collected.count >= wanted
        let semaphore = done
        lock.unlock()
        if finished { semaphore?.signal() }
    }
}

func openCamera(id: String?, collector: FrameCollector) -> AVCaptureSession? {
    let devices = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
                                                   mediaType: .video, position: .unspecified).devices
    guard let device = id.flatMap({ wanted in devices.first { $0.uniqueID == wanted } }) ?? devices.first,
          let input = try? AVCaptureDeviceInput(device: device) else { return nil }
    let session = AVCaptureSession()
    session.beginConfiguration()
    if session.canSetSessionPreset(.vga640x480) { session.sessionPreset = .vga640x480 }
    let output = AVCaptureVideoDataOutput()
    output.alwaysDiscardsLateVideoFrames = true
    let yuv = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
    if output.availableVideoPixelFormatTypes.contains(yuv) {
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: yuv]  // 与 App 的首选格式一致
    }
    guard session.canAddInput(input), session.canAddOutput(output) else { return nil }
    session.addInput(input); session.addOutput(output)
    output.setSampleBufferDelegate(collector, queue: collector.queue)
    session.commitConfiguration()
    session.startRunning()
    return session.isRunning ? session : nil
}

func runCamera(backend: String, frames: Int, compare: Int, cameraID: String?) -> Int32 {
    guard let embedder = FaceEmbedderBackends.make(backend) else {
        print("STOP backend \(backend) unavailable in this build/OS (no fallback in the probe)"); return 3
    }
    guard let profile = FaceScanTuning().modelProfiles[embedder.modelVersion] else {
        print("STOP no threshold entry for \(embedder.modelVersion) in FaceScanModelProfile.table"); return 3
    }
    let access = DispatchSemaphore(value: 0)
    var granted = false
    AVCaptureDevice.requestAccess(for: .video) { granted = $0; access.signal() }
    access.wait()
    guard granted else { print("STOP camera permission denied"); return 2 }
    let collector = FrameCollector(embedder: embedder)
    guard let session = openCamera(id: cameraID, collector: collector) else { print("STOP camera unavailable"); return 3 }
    defer { session.stopRunning() }
    let threshold = FaceScanTuning().similarityThreshold(for: embedder.modelVersion) ?? .nan
    print("backend=\(backend) model=\(embedder.modelVersion) current_threshold=\(threshold) calibrated=\(profile.calibrated)")
    print("enroll: look at the camera, one face only, normal distance. collecting \(frames) frames…"); fflush(stdout)
    let templates = collector.collect(frames, timeout: 60)
    print("enroll: \(templates.count)/\(frames) frames; rejected=\(collector.rejected)")
    guard templates.count >= 2 else { print("STOP not enough enrollment frames"); return 2 }
    let enrollSelf = templates.indices.dropFirst().compactMap { i in ownerScore(templates[i], templates: Array(templates[..<i])) }
    print("enroll self-consistency (each frame vs earlier ones): \(ProbeStats.summary(enrollSelf))")

    var genuine: [Float] = [], impostor: [Float] = []
    var label = "same"
    var round = 1
    while true {
        print("round \(round) [\(label)]: collecting \(compare) frames…"); fflush(stdout)
        let probes = collector.collect(compare, timeout: 60)
        let scores = probes.compactMap { ownerScore($0, templates: templates) }
        print("round \(round) [\(label)]: \(ProbeStats.summary(scores)); rejected=\(collector.rejected)")
        print("round \(round) [\(label)]: pass rate at current threshold \(ProbeStats.fraction(scores, atLeast: threshold))")
        if label == "same" { genuine += scores } else { impostor += scores }
        print("next round: type 'same' (same person, e.g. other light/time) or 'other' (a different person) and press Enter; empty Enter finishes")
        fflush(stdout)
        guard let line = readLine()?.trimmingCharacters(in: .whitespaces).lowercased(), !line.isEmpty else { break }
        guard line == "same" || line == "other" else { print("unknown answer, finishing"); break }
        label = line; round += 1
    }

    print("== summary backend=\(backend) model=\(embedder.modelVersion) (score = min(cos to mean template, cos to latest template), the guard needs both)")
    print("same person: \(ProbeStats.summary(genuine))")
    print("other person: \(ProbeStats.summary(impostor))")
    print("at current threshold \(threshold): same accepted \(ProbeStats.fraction(genuine, atLeast: threshold)), other accepted \(ProbeStats.fraction(impostor, atLeast: threshold))")
    if impostor.isEmpty {
        print("suggestion: none — run at least one 'other' round before choosing a threshold")
    } else if let s = ProbeStats.suggest(genuine: genuine, impostor: impostor) {
        print(String(format: "suggestion: threshold=%.4f margin=%.4f (midpoint of same-person p5 and other-person max)", s.threshold, s.margin))
    } else {
        print("suggestion: none — same-person p5 does not clear the other-person max; this pipeline cannot separate these people")
    }
    return 0
}

// MARK: - 自检（不开相机）

var failures = 0
func expect(_ condition: Bool, _ message: String) {
    if condition { print("ok   \(message)") } else { failures += 1; print("FAIL \(message)") }
}

/// 合成一张 640×480 的灰底图：一张不对称的“脸”，整体绕 (320, 240) 转 rotation 弧度（逆时针为正，y 向上）。
func syntheticImage(rotation: CGFloat) -> CIImage? {
    let width = 640, height = 480
    guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    context.setFillColor(gray: 0.5, alpha: 1); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.translateBy(x: 320, y: 240); context.rotate(by: rotation)
    context.setFillColor(red: 0.9, green: 0.75, blue: 0.6, alpha: 1)
    context.fillEllipse(in: CGRect(x: -80, y: -105, width: 160, height: 210))
    context.setFillColor(red: 0.1, green: 0.1, blue: 0.2, alpha: 1)
    context.fillEllipse(in: CGRect(x: -50, y: 20, width: 30, height: 16))   // 左眼
    context.fillEllipse(in: CGRect(x: 20, y: 20, width: 30, height: 16))    // 右眼
    context.setFillColor(red: 0.7, green: 0.2, blue: 0.2, alpha: 1)
    context.fill(CGRect(x: -35, y: -60, width: 70, height: 14))            // 嘴
    context.setFillColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1)
    context.fill(CGRect(x: 40, y: 60, width: 40, height: 40))              // 不对称的记号
    context.setFillColor(red: 0.1, green: 0.6, blue: 0.2, alpha: 1)
    context.fill(CGRect(x: -95, y: -20, width: 18, height: 70))
    return context.makeImage().map { CIImage(cgImage: $0) }
}

func selfTest() -> Int32 {
    expect(VisionFaceEmbedder.modelVersion == FaceScanModelProfile.visionFeaturePrintVersion,
           "embedder model version matches the Core threshold table (\(VisionFaceEmbedder.modelVersion))")
    expect(!FaceScanModelProfile.visionFeaturePrint.calibrated, "the Vision threshold is still marked uncalibrated")
    expect(FaceEmbedderBackends.resolve("no-such-backend")?.name == "vision", "an unknown backend falls back to vision")
    expect(FaceEmbedderBackends.resolve(nil)?.name == "vision", "no backend setting means vision")
    expect(FaceEmbedderBackends.make("vision")?.modelVersion == VisionFaceEmbedder.modelVersion, "the vision backend reports its version")
    for name in FaceEmbedderBackends.names {
        if let e = FaceEmbedderBackends.make(name) {
            expect(FaceScanModelProfile.table[e.modelVersion] != nil, "backend \(name) has a threshold entry")
        } else {
            print("info backend \(name) not present in this build")
        }
    }

    // 眼睛连线角度：点在脸内归一化坐标，框占画面一部分。
    let box = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
    let size = CGSize(width: 640, height: 480)
    let level = FaceAlignment.eyeLineAngle(leftEye: [CGPoint(x: 0.3, y: 0.6)], rightEye: [CGPoint(x: 0.7, y: 0.6)],
                                                boundingBox: box, imageSize: size)
    expect(level.map { abs($0) < 1e-9 } ?? false, "level eyes give angle 0")
    // 画面像素里右眼比左眼高 dy：dx = 0.4*0.5*640 = 128, dy = 0.1*0.5*480 = 24。
    let tilted = FaceAlignment.eyeLineAngle(leftEye: [CGPoint(x: 0.3, y: 0.6)], rightEye: [CGPoint(x: 0.7, y: 0.7)],
                                                 boundingBox: box, imageSize: size)
    expect(tilted.map { abs($0 - atan2(24, 128)) < 1e-9 } ?? false, "tilted eyes give atan2(dy, dx) in pixels, counter-clockwise positive")
    let swapped = FaceAlignment.eyeLineAngle(leftEye: [CGPoint(x: 0.7, y: 0.7)], rightEye: [CGPoint(x: 0.3, y: 0.6)],
                                                  boundingBox: box, imageSize: size)
    expect(swapped == tilted, "eye order (mirrored camera) does not flip the angle")
    expect(FaceAlignment.eyeLineAngle(leftEye: [CGPoint(x: 0.5, y: 0.5)], rightEye: [CGPoint(x: 0.5, y: 0.5)],
                                           boundingBox: box, imageSize: size) == nil, "coincident eyes give no angle")
    expect(FaceAlignment.eyeLineAngle(leftEye: [], rightEye: [CGPoint(x: 0.5, y: 0.5)], boundingBox: box, imageSize: size) == nil,
           "missing eye points give no angle")

    // 裁切几何
    let crop = VisionFaceEmbedder.crop(boundingBox: box, imageSize: size, eyeLineAngle: 0.1)
    expect(crop.map { abs($0.side - 320 * 1.3) < 1e-6 && $0.center == CGPoint(x: 320, y: 240) && $0.angle == 0.1 } ?? false,
           "crop is a 1.3x square around the box centre, sized by the longer side in pixels")
    expect(VisionFaceEmbedder.crop(boundingBox: CGRect(x: 0.5, y: 0.5, width: 0.04, height: 0.04), imageSize: size, eyeLineAngle: 0) == nil,
           "a tiny face gives no crop")
    expect(VisionFaceEmbedder.crop(boundingBox: CGRect(x: CGFloat.nan, y: 0, width: 0.5, height: 0.5), imageSize: size, eyeLineAngle: 0) == nil,
           "a NaN box gives no crop")
    expect(VisionFaceEmbedder.crop(boundingBox: box, imageSize: size, eyeLineAngle: .infinity) == nil, "a non-finite angle gives no crop")
    if let crop {
        let t = VisionFaceEmbedder.transform(for: crop)
        let centre = CGPoint(x: 320, y: 240).applying(t)
        expect(abs(centre.x - 112) < 1e-6 && abs(centre.y - 112) < 1e-6, "the crop centre lands in the middle of the 224 square")
    }

    // 姿态与归一化
    expect(VisionFaceEmbedder.poseAcceptable(yaw: 0.2, pitch: nil), "a slightly turned head is accepted")
    expect(!VisionFaceEmbedder.poseAcceptable(yaw: 0.8, pitch: 0), "a strongly turned head is rejected")
    expect(!VisionFaceEmbedder.poseAcceptable(yaw: .nan, pitch: 0), "a NaN yaw is rejected")
    let embedderUnderTest = VisionFaceEmbedder()
    let level0 = FaceGeometry(boundingBox: box, yaw: 0, pitch: 0)
    expect(level0.eyeLineAngle == nil && embedderUnderTest.modelVersion == VisionFaceEmbedder.modelVersion,
           "geometry without alignment carries no eye angle")
    let unit = VisionFaceEmbedder.l2Normalized([3, 4])
    expect(unit == [0.6, 0.8], "L2 normalisation")
    expect(VisionFaceEmbedder.l2Normalized([0, 0]) == nil && VisionFaceEmbedder.l2Normalized([.nan, 1]) == nil
           && VisionFaceEmbedder.l2Normalized([]) == nil, "zero, NaN and empty vectors are rejected")

    // 统计
    let values: [Float] = (1...100).map { Float($0) / 100 }
    expect(ProbeStats.percentile(values, 0.05) == 0.05 && ProbeStats.percentile(values, 0.5) == 0.5
           && ProbeStats.percentile(values, 0.95) == 0.95, "nearest-rank percentiles")
    let s = ProbeStats.suggest(genuine: [0.95, 0.96, 0.97, 0.98], impostor: [0.80, 0.85])
    expect(s.map { abs($0.threshold - 0.9) < 1e-6 && abs($0.margin - 0.1) < 1e-6 } ?? false, "threshold = midpoint of genuine p5 and impostor max")
    expect(ProbeStats.suggest(genuine: [0.9, 0.95], impostor: [0.93]) == nil, "overlapping distributions give no suggestion")
    expect(ProbeStats.suggest(genuine: [0.9], impostor: []) == nil, "no impostor round gives no suggestion")
    expect(ownerScore([1, 0], templates: [[1, 0], [0, 1]]).map { abs($0 - 0) < 1e-6 } ?? false,
           "the owner score is the lower of mean and latest cosines")

    // 真跑一次 Vision（合成图，不是人脸）：维度、单位长度、确定性、摆正方向。
    guard VisionFaceEmbedder.isSupported else {
        print("SKIP Vision run: featureprint revision \(VisionFaceEmbedder.revision) unsupported here")
        return failures == 0 ? 0 : 1
    }
    let embedder = VisionFaceEmbedder()
    let faceBox = CGRect(x: (320 - 110) / 640.0, y: (240 - 110) / 480.0, width: 220 / 640.0, height: 220 / 480.0)
    let theta = 0.5
    if let upright = syntheticImage(rotation: 0), let rotated = syntheticImage(rotation: CGFloat(theta)),
       let base = VisionFaceEmbedder.crop(boundingBox: faceBox, imageSize: size, eyeLineAngle: 0),
       let a = embedder.embed(image: upright, crop: base), let b = embedder.embed(image: upright, crop: base) {
        let norm = a.reduce(Float(0)) { $0 + $1 * $1 }.squareRoot()
        expect(!a.isEmpty && abs(norm - 1) < 1e-3, "feature print is a unit vector (dimension \(a.count))")
        expect((FaceScanGuard.cosine(a, b) ?? 0) > 0.9999, "the same crop gives the same vector")
        func score(_ angle: Double) -> Float {
            let c = VisionFaceEmbedder.Crop(center: base.center, side: base.side, angle: angle)
            return embedder.embed(image: rotated, crop: c).flatMap { FaceScanGuard.cosine(a, $0) } ?? -1
        }
        // App 走的是 CVPixelBuffer + FaceGeometry 这条入口；渲染同一张图进缓冲区，结果应与上面一致。
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, 640, 480, kCVPixelFormatType_32BGRA,
                            [kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()] as CFDictionary, &buffer)
        if let buffer {
            CIContext().render(upright, to: buffer)
            let level = FaceGeometry(boundingBox: faceBox, yaw: 0, pitch: 0, eyeLineAngle: 0, alignmentPoints: nil)
            let viaBuffer = embedder.embed(pixelBuffer: buffer, face: level)
            expect(viaBuffer.flatMap { FaceScanGuard.cosine(a, $0) }.map { $0 > 0.99 } ?? false,
                   "the pixel-buffer entry matches the image entry")
            expect(embedder.embed(pixelBuffer: buffer, face: FaceGeometry(boundingBox: faceBox, yaw: 0, pitch: 0)) == nil,
                   "no eye angle, no embedding")
            expect(embedder.embed(pixelBuffer: buffer, face: FaceGeometry(boundingBox: faceBox, yaw: 0.9, pitch: 0, eyeLineAngle: 0)) == nil,
                   "a strongly turned head gives no embedding")
        } else {
            expect(false, "pixel buffer for the synthetic image")
        }
        let corrected = score(theta), uncorrected = score(0), wrong = score(-theta)
        print(String(format: "info rotation check: corrected=%.4f uncorrected=%.4f wrong-sign=%.4f", corrected, uncorrected, wrong))
        expect(corrected > uncorrected && corrected > wrong, "undoing the eye-line tilt brings a rotated face back toward upright")
    } else {
        expect(false, "Vision produced a feature print for the synthetic image")
    }
    return failures == 0 ? 0 : 1
}

@main struct FaceFeaturePrintProbe {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        func value(_ flag: String) -> String? { args.firstIndex(of: flag).flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil } }
        if args.contains("--self-test") {
            let code = selfTest()
            print(code == 0 ? "PASS FaceFeaturePrintProbe self-test (no camera)" : "FAIL FaceFeaturePrintProbe self-test")
            exit(code)
        }
        let frames = value("--frames").flatMap(Int.init) ?? 10
        let compare = value("--compare").flatMap(Int.init) ?? 40
        guard (2...50).contains(frames), (5...500).contains(compare) else {
            print("usage: FaceFeaturePrintProbe [--self-test] [--backend vision|arcface] [--frames 2...50] [--compare 5...500] [--camera UNIQUE_ID]"); exit(64)
        }
        let backend = value("--backend") ?? "vision"
        guard FaceEmbedderBackends.names.contains(backend) else {
            print("unknown backend \(backend); choose one of \(FaceEmbedderBackends.names.joined(separator: "|"))"); exit(64)
        }
        exit(runCamera(backend: backend, frames: frames, compare: compare, cameraID: value("--camera")))
    }
}
