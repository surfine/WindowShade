import Cocoa
@preconcurrency import AVFoundation
@preconcurrency import Vision
import CoreML

struct FaceCameraDescriptor: Sendable, Hashable { let id: String; let name: String }

/// 采集→过滤→Vision→投递的隐私安全计数（R04）。不写图像、特征或相机硬件名。
/// PERF-07 扩充：相机实际选中的格式与帧率、像素格式、Vision 次数与用时、连续失败与退路状态。
struct FacePipelineCounters: Sendable, Equatable {
    var captureReceived: UInt64 = 0
    var warmupSkipped: UInt64 = 0
    var throttled: UInt64 = 0
    var invalidBuffer: UInt64 = 0
    var clockConversionRejected: UInt64 = 0
    var staleFrame: UInt64 = 0
    var visionStarted: UInt64 = 0
    var visionFailed: UInt64 = 0
    var noFace: UInt64 = 0
    var multipleFaces: UInt64 = 0
    var delivered: UInt64 = 0
    /// 相机与 Vision 的代价（PERF-07）。数值与四字码，不含硬件名。
    var camera = FaceCameraReport()
    /// Vision 一次请求的累计与最大用时（毫秒），以及超过预算的次数。
    var visionTotalMs: Double = 0
    var visionMaxMs: Double = 0
    var visionSlow: UInt64 = 0
}

/// Geometry only. Head pose is not gaze; no face is not evidence of departure.
struct FaceObservation: Sendable, Equatable {
    let cameraID: String
    let generation: UInt64
    let sequence: UInt64
    let observedAt: Double
    let faceCount: Int
    let yaw: Double?
    let pitch: Double?
    let leftEyeOpenness: Double?
    let rightEyeOpenness: Double?
    let faceBoundingBox: CGRect?
    let confidence: Float?
}

enum FaceObservationSourceError: Error {
    case authorizationDenied, unknownDevice, unavailable, interrupted, superseded
    case runtime(String)
}

/// Main-actor callback ownership, with capture and Vision confined to one worker queue.
@MainActor final class FaceObservationSource {
    private let worker = FaceObservationWorker()
    private var epoch: UInt64 = 0
    private var callback: ((FaceObservation) -> Void)?
    var onFailure: ((Error) -> Void)?
    static var authorizationStatus: AVAuthorizationStatus { AVCaptureDevice.authorizationStatus(for: .video) }
    /// 菜单用的相机列表：读缓存，不在主线程上问系统（冷启动第一次枚举相机在主线程上要 262–390 ms）。
    /// 缓存在后台填：启动时一次、相机接上或拔掉时再一次；还没填好时是空的（菜单那一项先灰着）。
    static func devices() -> [FaceCameraDescriptor] {
        CameraList.shared.current()
    }

    /// 在后台把相机列表填好，并在相机接上、拔掉时更新。启动时调一次。
    static func startWatchingCameras() { CameraList.shared.start() }
    func requestAuthorization() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }
    func start(deviceID: String, onObservation: @escaping @MainActor (FaceObservation) -> Void) async throws {
        guard Self.authorizationStatus == .authorized else { throw FaceObservationSourceError.authorizationDenied }
        stopCapture()
        let token = epoch
        callback = onObservation
        do {
            try await worker.start(deviceID: deviceID, token: token, deliver: { [weak self] value in
                Task { @MainActor in
                    guard let self, self.epoch == token else { return }
                    self.callback?(value)
                }
            }, fail: { [weak self] error in
                Task { @MainActor in
                    guard let self, self.epoch == token else { return }
                    let handler = self.onFailure
                    self.stop()
                    handler?(error)
                }
            })
            guard epoch == token, !Task.isCancelled else {
                if epoch == token { stopCapture() }
                throw CancellationError()
            }
        } catch {
            if epoch == token { stopCapture() }
            throw error
        }
    }
    private func stopCapture() {
        epoch &+= 1
        callback = nil
        worker.stop()
    }
    func stop() { stopCapture(); onFailure = nil }
    /// 当前会话的管道计数快照（授权成功≠采集成功）。
    func pipelineCounters() async -> FacePipelineCounters {
        await worker.countersSnapshot()
    }
    deinit { worker.stop() }
}

/// @unchecked Sendable is limited to dispatching work; all mutable state is queue-confined.
private final class FaceObservationWorker: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let queue = DispatchQueue(label: "WindowShade.face.observations", qos: .userInitiated)
    private var session: AVCaptureSession?
    private var output: AVCaptureVideoDataOutput?
    private var observers: [NSObjectProtocol] = []
    private var token: UInt64 = 0
    private var sequence: UInt64 = 0
    private var deviceID = ""
    private var startedAt = 0.0
    private var lastSample = 0.0
    private var counters = FacePipelineCounters()
    /// Vision 连续失败的会话级退路（PERF-07）。只在队列上动。
    private var fallback = FaceVisionFallbackPolicy()
    private var deliver: (@Sendable (FaceObservation) -> Void)?
    private var fail: (@Sendable (Error) -> Void)?

    func countersSnapshot() async -> FacePipelineCounters {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: self.counters) }
        }
    }

    static func devices() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
            mediaType: .video, position: .unspecified).devices
    }
    /// 在 activeFormat 支援范围内协商源帧率（PERF-07）。只把固定的 min/max frame duration 设成
    /// 我们真的会处理的那一档；夹不进任何一档就维持相机预设，报表里的 requestedSourceFPS 记 0
    /// 表示「没协商成」，不假装成功。
    static func negotiateFrameRate(device: AVCaptureDevice, into report: inout FaceCameraReport) {
        let format = device.activeFormat
        let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        report.activeFormatWidth = Int(dimensions.width)
        report.activeFormatHeight = Int(dimensions.height)
        let ranges = format.videoSupportedFrameRateRanges
        report.activeFormatMinFPS = ranges.map(\.minFrameRate).min() ?? 0
        report.activeFormatMaxFPS = ranges.map(\.maxFrameRate).max() ?? 0
        let target = FaceCameraTuning.targetSourceFPS
        guard let range = ranges.first(where: { target >= $0.minFrameRate && target <= $0.maxFrameRate })
            ?? ranges.min(by: { $0.maxFrameRate < $1.maxFrameRate })
        else { return }
        let clamped = min(max(target, range.minFrameRate), range.maxFrameRate)
        let timescale = CMTimeScale(clamped.rounded())
        guard timescale > 0 else { return }
        let duration = CMTime(value: 1, timescale: timescale)
        do {
            try device.lockForConfiguration()
            device.activeVideoMinFrameDuration = duration
            device.activeVideoMaxFrameDuration = duration
            device.unlockForConfiguration()
            report.requestedSourceFPS = duration.seconds > 0 ? 1 / duration.seconds : 0
        } catch {
            report.requestedSourceFPS = 0
        }
    }
    func start(deviceID: String, token: UInt64,
               deliver: @escaping @Sendable (FaceObservation) -> Void,
               fail: @escaping @Sendable (Error) -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                self.tearDown()
                do {
                    guard let device = Self.devices().first(where: { $0.uniqueID == deviceID }) else {
                        throw FaceObservationSourceError.unknownDevice
                    }
                    let session = AVCaptureSession()
                    session.beginConfiguration()
                    if session.canSetSessionPreset(.vga640x480) { session.sessionPreset = .vga640x480 }
                    let input = try AVCaptureDeviceInput(device: device)
                    let output = AVCaptureVideoDataOutput()
                    output.alwaysDiscardsLateVideoFrames = true
                    self.counters = FacePipelineCounters()
                    // PERF-07：按相机真正支援的像素格式挑，优先原生双平面 YUV（少一次转换），
                    // 其次 BGRA。都不支援就用系统预设，不硬塞相机不认的格式。
                    let available = output.availableVideoPixelFormatTypes
                    let forced = ProcessInfo.processInfo.environment["WINDOWSHADE_CAMERA_PIXEL_FORMAT"]
                    if let pixelFormat = FaceCameraPixelFormat.preferred(from: available, forced: forced) {
                        output.videoSettings = [
                            kCVPixelBufferPixelFormatTypeKey as String: pixelFormat
                        ]
                        self.counters.camera.pixelFormat = pixelFormat
                    }
                    guard session.canAddInput(input), session.canAddOutput(output) else {
                        session.commitConfiguration()
                        throw FaceObservationSourceError.unavailable
                    }
                    session.addInput(input)
                    session.addOutput(output)
                    // PERF-07：在 activeFormat 支援范围内协商源帧率。只取我们真的会处理的那一档，
                    // 相机不再产出注定被丢掉的帧（解码是实打实的电）。
                    Self.negotiateFrameRate(device: device, into: &self.counters.camera)
                    output.setSampleBufferDelegate(self, queue: self.queue)
                    session.commitConfiguration()
                    self.session = session
                    self.output = output
                    self.deviceID = deviceID
                    self.token = token
                    self.sequence = 0
                    self.lastSample = 0
                    self.fallback = FaceVisionFallbackPolicy()
                    self.deliver = deliver
                    self.fail = fail
                    for name in [AVCaptureSession.runtimeErrorNotification, AVCaptureSession.wasInterruptedNotification] {
                        self.observers.append(NotificationCenter.default.addObserver(forName: name, object: session, queue: nil) { [weak self] note in
                            let description = (note.userInfo?[AVCaptureSessionErrorKey] as? Error)?.localizedDescription
                            self?.queue.async { [weak self] in
                                guard let self, self.token == token else { return }
                                let handler = self.fail
                                self.tearDown()
                                handler?(description.map { FaceObservationSourceError.runtime($0) } ?? FaceObservationSourceError.interrupted)
                            }
                        })
                    }
                    session.startRunning()
                    guard session.isRunning else { throw FaceObservationSourceError.unavailable }
                    self.startedAt = CACurrentMediaTime()
                    continuation.resume()
                } catch {
                    self.tearDown()
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    func stop() { queue.async { self.tearDown() } }
    private func tearDown() {
        deliver = nil; fail = nil
        observers.forEach { NotificationCenter.default.removeObserver($0) }; observers.removeAll()
        output?.setSampleBufferDelegate(nil, queue: nil)
        output = nil
        session?.stopRunning()
        session = nil
    }
    func captureOutput(_ output: AVCaptureOutput, didOutput sample: CMSampleBuffer, from connection: AVCaptureConnection) {
        // This delegate queue also owns session configuration; one Vision request at a time.
        let now = CACurrentMediaTime()
        guard self.output === output else { return }
        counters.captureReceived &+= 1
        if now - startedAt < 0.5 {
            counters.warmupSkipped &+= 1
            return
        }
        if now - lastSample < 1.0 / FaceCameraTuning.targetSourceFPS {
            counters.throttled &+= 1
            return
        }
        guard sample.isValid, let buffer = sample.imageBuffer else {
            counters.invalidBuffer &+= 1
            return
        }
        guard let clock = session?.synchronizationClock else {
            counters.clockConversionRejected &+= 1
            return
        }
        let captured = CMSyncConvertTime(CMSampleBufferGetPresentationTimeStamp(sample), from: clock,
                                          to: CMClockGetHostTimeClock()).seconds
        guard captured.isFinite, captured > 0, now >= captured else {
            counters.clockConversionRejected &+= 1
            return
        }
        if now - captured >= 0.5 {
            counters.staleFrame &+= 1
            return
        }
        lastSample = now
        let request = VNDetectFaceLandmarksRequest()
        // 钉在神经引擎上（main stage）：默认偶尔退回 GPU/CPU。实测钉住后结果一致（IoU 0.995）、
        // 不占 GPU、延迟低 15–30%。注意这只决定 main stage 用哪个加速器，前处理与后处理仍会用到
        // CPU/GPU，不能写成「整条路不用 CPU/GPU」。连续失败会退回系统预设（见下面的 fallback）。
        if !fallback.usesDefaultComputeDevice, let ane = FaceLandmarkComputeDevice.ane {
            request.setComputeDevice(ane, for: .main)
        }
        counters.camera.pinsNeuralEngine = !fallback.usesDefaultComputeDevice
        counters.visionStarted &+= 1
        let visionStartedAt = CACurrentMediaTime()
        do { try VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up).perform([request]) }
        catch {
            counters.visionFailed &+= 1
            // PERF-07：先记类别；连续失败才退路，而退路整个会话只有一次。退路后仍失败就停源报不可用。
            switch fallback.recordFailure(FaceVisionFailureCategory.of(error)) {
            case .keepRunning:
                return
            case .fallBackToDefault:
                counters.camera.pinsNeuralEngine = false
                return
            case .stopUnavailable:
                let handler = fail
                tearDown()
                handler?(
                    FaceObservationSourceError.runtime("Vision 连续失败后退回系统预设仍不可用"))
                return
            }
        }
        let visionMs = (CACurrentMediaTime() - visionStartedAt) * 1000
        counters.visionTotalMs += visionMs
        counters.visionMaxMs = max(counters.visionMaxMs, visionMs)
        if visionMs > FaceCameraTuning.visionBudgetMs { counters.visionSlow &+= 1 }
        fallback.recordSuccess()
        let faces = request.results ?? []
        if faces.isEmpty { counters.noFace &+= 1 }
        else if faces.count > 1 { counters.multipleFaces &+= 1 }
        let face = faces.count == 1 ? faces.first : nil
        sequence &+= 1
        let imageSize = CGSize(width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer))
        func eye(_ region: VNFaceLandmarkRegion2D?) -> Double? {
            guard let region, let face else { return nil }
            return FaceEyeGeometry.openness(region.normalizedPoints,
                scale: CGSize(width: face.boundingBox.width * imageSize.width, height: face.boundingBox.height * imageSize.height))
        }
        func finite(_ number: NSNumber?) -> Double? {
            guard let value = number?.doubleValue, value.isFinite else { return nil }; return value
        }
        deliver?(.init(cameraID: deviceID, generation: token, sequence: sequence,
            observedAt: captured, faceCount: faces.count, yaw: finite(face?.yaw), pitch: finite(face?.pitch),
            leftEyeOpenness: eye(face?.landmarks?.leftEye), rightEyeOpenness: eye(face?.landmarks?.rightEye),
            faceBoundingBox: face?.boundingBox, confidence: face?.confidence))
        counters.delivered &+= 1
    }
}

/// A rotation-independent geometric ratio, not a calibrated open/closed classification.
enum FaceEyeGeometry {
    static func openness(_ points: [CGPoint], scale: CGSize) -> Double? {
        guard points.count >= 4, scale.width.isFinite, scale.height.isFinite,
              scale.width > 0, scale.height > 0,
              points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return nil }
        let pixels = points.map { CGPoint(x: $0.x * scale.width, y: $0.y * scale.height) }
        var longest = 0.0
        var axis = CGPoint.zero
        for a in pixels { for b in pixels {
            let dx = b.x - a.x, dy = b.y - a.y, length = hypot(dx, dy)
            if length > longest { longest = length; axis = CGPoint(x: dx / length, y: dy / length) }
        } }
        guard longest >= 6 else { return nil }
        let perpendicular = pixels.map { -$0.x * axis.y + $0.y * axis.x }
        let ratio = ((perpendicular.max() ?? 0) - (perpendicular.min() ?? 0)) / longest
        return ratio.isFinite ? min(1, max(0, ratio)) : nil
    }
}


/// 神经引擎只查一次（后台队列上第一次用到时）。
private enum FaceLandmarkComputeDevice {
    static let ane: MLComputeDevice? = {
        guard let devices = try? VNDetectFaceLandmarksRequest().supportedComputeStageDevices[.main] else { return nil }
        return devices.first { if case .neuralEngine = $0 { return true } else { return false } }
    }()
}

/// 相机列表缓存：枚举放在后台，主线程只读。
private final class CameraList: @unchecked Sendable {
    static let shared = CameraList()
    private let lock = NSLock()
    private var cameras: [FaceCameraDescriptor] = []
    private var started = false
    private let queue = DispatchQueue(label: "WindowShade.camera-list", qos: .utility)

    func current() -> [FaceCameraDescriptor] {
        start()
        lock.lock(); defer { lock.unlock() }
        return cameras
    }

    func start() {
        lock.lock()
        let first = !started
        started = true
        lock.unlock()
        guard first else { return }
        refresh()
        for name in [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in self?.refresh() }
        }
    }

    private func refresh() {
        queue.async { [weak self] in
            let found = FaceObservationWorker.devices().map { FaceCameraDescriptor(id: $0.uniqueID, name: $0.localizedName) }
            guard let self else { return }
            self.lock.lock(); self.cameras = found; self.lock.unlock()
        }
    }
}
