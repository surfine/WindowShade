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
    /// Outer lip points in Vision's face-local normalized coordinates (origin bottom-left).
    /// Geometry only; never an identity template. No image or crop leaves the capture worker.
    var mouthLandmarks: [CGPoint]? = nil
    /// Negotiated physical source rate, not a claim about delivered Vision throughput.
    /// Nil means the camera did not accept a rate; use observedAt deltas to measure delivery.
    var sourceFPS: Double? = nil
}

enum FaceObservationSourceError: Error {
    case authorizationDenied, unknownDevice, unavailable, interrupted, superseded
    case cameraInUse, invalidLifetime, expired
    case runtime(String)
}

enum FaceObservationPurpose: Sendable {
    case geometry, command, securityChallenge
    var requestedFPS: Double { self == .geometry ? FaceCameraTuning.targetSourceFPS : 25 }
}

struct FaceObservationSubscription: Sendable, Hashable {
    fileprivate let id: UUID
}

/// The injectable boundary owns exactly one physical capture. Production state stays on its queue.
protocol FaceCaptureWorker: Sendable {
    func start(deviceID: String, token: UInt64, requestedFPS: Double,
               deliver: @escaping @Sendable (FaceObservation) -> Void,
               fail: @escaping @Sendable (Error) -> Void) async throws
    func setRequestedFPS(_ fps: Double)
    func stop()
    func countersSnapshot() async -> FacePipelineCounters
}

/// One process-wide physical camera, independently cancellable consumers, monotonic leases.
@MainActor final class FaceObservationHub {
    static let shared = FaceObservationHub(worker: FaceObservationWorker())
    private struct Consumer {
        let purpose: FaceObservationPurpose
        let expiresAt: Double?
        let beganAt: Double
        let observation: @MainActor (FaceObservation) -> Void
        let failure: @MainActor (Error) -> Void
        var lastDelivered: Double?
    }
    private let worker: any FaceCaptureWorker
    private let clock: @MainActor () -> Double
    private let authorize: @MainActor () async -> Bool
    private var consumers: [FaceObservationSubscription: Consumer] = [:]
    private var deviceID: String?
    private var generation: UInt64 = 0
    private var startup: Task<Void, Never>?
    private var ready = false
    private var waiters: [FaceObservationSubscription: CheckedContinuation<Void, Error>] = [:]
    private var expiry: Task<Void, Never>?
    private var lastSequence: UInt64 = 0
    private var lastObservedAt: Double?
    init(worker: any FaceCaptureWorker,
         clock: @escaping @MainActor () -> Double = { CACurrentMediaTime() },
         authorize: @escaping @MainActor () async -> Bool = {
             AVCaptureDevice.authorizationStatus(for: .video) == .authorized
         }) {
        self.worker = worker; self.clock = clock; self.authorize = authorize
    }
    func reserve(token: FaceObservationSubscription = .init(id: UUID()), deviceID: String, purpose: FaceObservationPurpose, validFor: Double?,
                 observation: @escaping @MainActor (FaceObservation) -> Void,
                 failure: @escaping @MainActor (Error) -> Void) throws -> FaceObservationSubscription {
        expireConsumers()
        guard !deviceID.isEmpty else { throw FaceObservationSourceError.unknownDevice }
        guard self.deviceID == nil || self.deviceID == deviceID else {
            throw FaceObservationSourceError.cameraInUse
        }
        if let validFor {
            guard validFor.isFinite, validFor > 0, validFor <= 86_400, (clock() + validFor).isFinite else {
                throw FaceObservationSourceError.invalidLifetime
            }
        }
        consumers[token] = Consumer(purpose: purpose, expiresAt: validFor.map { clock() + $0 }, beganAt: clock(),
                                    observation: observation, failure: failure)
        self.deviceID = deviceID
        scheduleExpiry()
        return token
    }
    func activate(_ token: FaceObservationSubscription) async throws {
        try Task.checkCancellation()
        guard consumers[token] != nil else { throw CancellationError() }
        if startup == nil {
            generation &+= 1
            let current = generation
            let device = deviceID!
            startup = Task { [weak self] in
                guard let self else { return }
                do {
                    guard await self.authorize() else { throw FaceObservationSourceError.authorizationDenied }
                    try Task.checkCancellation()
                    guard self.generation == current, !self.consumers.isEmpty else { throw CancellationError() }
                    try await self.worker.start(deviceID: device, token: current, requestedFPS: self.requestedFPS,
                        deliver: { [weak self] value in
                            Task { @MainActor in self?.receive(value, generation: current) }
                        }, fail: { [weak self] error in
                            Task { @MainActor in self?.fail(error, generation: current) }
                        })
                    try Task.checkCancellation()
                    guard self.generation == current else { return }
                    self.ready = true
                    let pending = self.waiters
                    self.waiters.removeAll()
                    for continuation in pending.values { continuation.resume() }
                } catch { self.fail(error, generation: current) }
            }
        }
        let current = generation
        do {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    if Task.isCancelled { continuation.resume(throwing: CancellationError()) }
                    else if ready { continuation.resume() }
                    else { waiters[token] = continuation }
                }
                try Task.checkCancellation()
            } onCancel: {
                Task { @MainActor [weak self] in self?.remove(token) }
            }
            expireConsumers()
            guard generation == current, consumers[token] != nil else { throw CancellationError() }
            worker.setRequestedFPS(requestedFPS)
        } catch {
            remove(token)
            throw error
        }
    }
    private var requestedFPS: Double { consumers.values.map { $0.purpose.requestedFPS }.max() ?? FaceCameraTuning.targetSourceFPS }
    func remove(_ token: FaceObservationSubscription) {
        guard consumers.removeValue(forKey: token) != nil else { return }
        waiters.removeValue(forKey: token)?.resume(throwing: CancellationError())
        if consumers.isEmpty { endCapture() }
        else { worker.setRequestedFPS(requestedFPS); scheduleExpiry() }
    }
    /// Exposed internally for deterministic monotonic-clock tests; production also schedules expiry.
    func expireConsumers() {
        let now = clock()
        let expired = consumers.filter { $0.value.expiresAt.map { $0 <= now } ?? false }
        for (token, _) in expired {
            consumers.removeValue(forKey: token)
            waiters.removeValue(forKey: token)?.resume(throwing: FaceObservationSourceError.expired)
        }
        if !expired.isEmpty {
            if consumers.isEmpty { endCapture() }
            else { worker.setRequestedFPS(requestedFPS); scheduleExpiry() }
            for (_, consumer) in expired { consumer.failure(FaceObservationSourceError.expired) }
        }
    }
    private func scheduleExpiry() {
        expiry?.cancel(); expiry = nil
        guard let deadline = consumers.values.compactMap(\.expiresAt).min() else { return }
        let delay = max(0, deadline - clock())
        expiry = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            self?.expireConsumers()
        }
    }
    private func endCapture() {
        generation &+= 1
        startup?.cancel(); startup = nil; ready = false
        expiry?.cancel(); expiry = nil
        deviceID = nil; lastSequence = 0; lastObservedAt = nil
        worker.stop()
    }
    private func fail(_ error: Error, generation: UInt64) {
        guard generation == self.generation, !consumers.isEmpty else { return }
        let handlers = consumers.values.map(\.failure)
        let pending = waiters
        waiters.removeAll()
        consumers.removeAll(); endCapture()
        for continuation in pending.values { continuation.resume(throwing: error) }
        for handler in handlers { handler(error) }
    }
    private func receive(_ observation: FaceObservation, generation: UInt64) {
        expireConsumers()
        let now = clock()
        guard generation == self.generation, observation.generation == generation,
              observation.cameraID == deviceID, observation.observedAt.isFinite,
              observation.observedAt <= now, now - observation.observedAt < 0.5,
              observation.sequence > lastSequence,
              lastObservedAt.map({ observation.observedAt > $0 }) ?? true else { return }
        lastSequence = observation.sequence; lastObservedAt = observation.observedAt
        // Snapshot IDs, then re-read membership after each callback: a callback may cancel a peer.
        for token in Array(consumers.keys) {
            guard var consumer = consumers[token], observation.observedAt >= consumer.beganAt else { continue }
            if let previous = consumer.lastDelivered,
               observation.observedAt - previous < 1 / consumer.purpose.requestedFPS - 0.001 { continue }
            consumer.lastDelivered = observation.observedAt
            consumers[token] = consumer
            consumer.observation(observation)
        }
    }
    func countersSnapshot() async -> FacePipelineCounters { await worker.countersSnapshot() }
}

/// Compatibility facade. Stopping this owner never stops another owner's subscription.
@MainActor final class FaceObservationSource {
    private let hub: FaceObservationHub
    private var subscriptions: Set<FaceObservationSubscription> = []
    private var legacy: FaceObservationSubscription?
    var onFailure: ((Error) -> Void)?
    init(hub: FaceObservationHub = .shared) { self.hub = hub }
    static var authorizationStatus: AVAuthorizationStatus { AVCaptureDevice.authorizationStatus(for: .video) }
    static func devices() -> [FaceCameraDescriptor] { CameraList.shared.current() }
    static func startWatchingCameras() { CameraList.shared.start() }
    func requestAuthorization() async -> Bool { await AVCaptureDevice.requestAccess(for: .video) }
    /// Explicit leases last at most one day; callers renew by opening a fresh session.
    func subscribe(deviceID: String, purpose: FaceObservationPurpose, validFor: Double = 60,
                   onObservation: @escaping @MainActor (FaceObservation) -> Void,
                   onFailure: @escaping @MainActor (Error) -> Void = { _ in }) async throws -> FaceObservationSubscription {
        try await subscribe(deviceID: deviceID, purpose: purpose, lifetime: validFor,
                            onObservation: onObservation, onFailure: onFailure)
    }
    private func subscribe(deviceID: String, purpose: FaceObservationPurpose, lifetime: Double?,
                           onObservation: @escaping @MainActor (FaceObservation) -> Void,
                           onFailure: @escaping @MainActor (Error) -> Void) async throws -> FaceObservationSubscription {
        try Task.checkCancellation()
        let token = FaceObservationSubscription(id: UUID())
        _ = try hub.reserve(token: token, deviceID: deviceID, purpose: purpose, validFor: lifetime,
                            observation: onObservation, failure: { [weak self] error in
                                self?.subscriptions.remove(token)
                                if self?.legacy == token { self?.legacy = nil }
                                onFailure(error)
                            })
        subscriptions.insert(token)
        do { try await hub.activate(token); return token }
        catch { unsubscribe(token); throw error }
    }
    func unsubscribe(_ token: FaceObservationSubscription) {
        guard subscriptions.remove(token) != nil else { return }
        if legacy == token { legacy = nil }
        hub.remove(token)
    }
    func start(deviceID: String, onObservation: @escaping @MainActor (FaceObservation) -> Void) async throws {
        if let legacy { unsubscribe(legacy) }
        try Task.checkCancellation()
        let token = FaceObservationSubscription(id: UUID())
        _ = try hub.reserve(token: token, deviceID: deviceID, purpose: .geometry, validFor: nil,
                            observation: onObservation, failure: { [weak self] error in
                                guard let self else { return }
                                self.subscriptions.remove(token)
                                if self.legacy == token { self.legacy = nil }
                                self.onFailure?(error)
                            })
        subscriptions.insert(token); legacy = token
        do { try await hub.activate(token) }
        catch { unsubscribe(token); throw error }
    }
    func stop() {
        for token in subscriptions { hub.remove(token) }
        subscriptions.removeAll(); legacy = nil; onFailure = nil
    }
    func pipelineCounters() async -> FacePipelineCounters { await hub.countersSnapshot() }
    deinit {
        let hub = hub, tokens = subscriptions
        Task { @MainActor in for token in tokens { hub.remove(token) } }
    }
}

/// @unchecked Sendable is limited to dispatching work; all mutable state is queue-confined.
private final class FaceObservationWorker: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, FaceCaptureWorker, @unchecked Sendable {
    private let queue = DispatchQueue(label: "WindowShade.face.observations", qos: .userInitiated)
    private var session: AVCaptureSession?
    private var output: AVCaptureVideoDataOutput?
    private var observers: [NSObjectProtocol] = []
    private var token: UInt64 = 0
    private var sequence: UInt64 = 0
    private var deviceID = ""
    private var startedAt = 0.0
    private var lastSample = 0.0
    private var lastCaptured = 0.0
    private var requestedFPS = FaceCameraTuning.targetSourceFPS
    private var device: AVCaptureDevice?
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
    static func negotiateFrameRate(device: AVCaptureDevice, target: Double, into report: inout FaceCameraReport) {
        report.requestedSourceFPS = 0
        let format = device.activeFormat
        let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        report.activeFormatWidth = Int(dimensions.width)
        report.activeFormatHeight = Int(dimensions.height)
        let ranges = format.videoSupportedFrameRateRanges
        report.activeFormatMinFPS = ranges.map(\.minFrameRate).min() ?? 0
        report.activeFormatMaxFPS = ranges.map(\.maxFrameRate).max() ?? 0
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
    func start(deviceID: String, token: UInt64, requestedFPS: Double,
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
                    Self.negotiateFrameRate(device: device, target: requestedFPS, into: &self.counters.camera)
                    self.requestedFPS = requestedFPS
                    self.device = device
                    output.setSampleBufferDelegate(self, queue: self.queue)
                    session.commitConfiguration()
                    self.session = session
                    self.output = output
                    self.deviceID = deviceID
                    self.token = token
                    self.sequence = 0
                    self.lastSample = 0
                    self.lastCaptured = 0
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
    func setRequestedFPS(_ fps: Double) {
        queue.async {
            guard let device = self.device, fps != self.requestedFPS else { return }
            self.requestedFPS = fps
            Self.negotiateFrameRate(device: device, target: fps, into: &self.counters.camera)
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
        device = nil
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
        if now - lastSample < 1.0 / requestedFPS {
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
        if now - captured >= 0.5 || captured <= lastCaptured {
            counters.staleFrame &+= 1
            return
        }
        lastSample = now
        lastCaptured = captured
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
            faceBoundingBox: face?.boundingBox, confidence: face?.confidence,
            mouthLandmarks: face?.landmarks?.outerLips?.normalizedPoints,
            sourceFPS: counters.camera.requestedSourceFPS > 0 ? counters.camera.requestedSourceFPS : nil))
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
