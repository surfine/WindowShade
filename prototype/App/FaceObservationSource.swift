import Cocoa
@preconcurrency import AVFoundation
@preconcurrency import Vision
import CoreML
import Synchronization

struct FaceCameraDescriptor: Sendable, Hashable {
    let id: String
    let name: String
    /// 相机的传输类型（四字码，如 'bltn'、'usb '）；没读到就是 nil。
    var transportType: Int32? = nil
    /// 相机类型的原始值（如内建广角、外接、接续互通）；没读到就是 nil。
    var deviceType: String? = nil

    /// 内建镜头的传输类型 'bltn'。外接显示器的镜头也报 builtInWideAngleCamera，只有传输类型分得开。
    static let builtInTransport: Int32 = 0x626C_746E
    static let builtInWideAngleType = AVCaptureDevice.DeviceType.builtInWideAngleCamera.rawValue

    /// 只有传输类型是 'bltn'、类型是内建广角的才算内建；外接、iPhone（接续互通）、虚拟相机、读不到的一律算外接。
    var cameraClass: FaceCameraClass {
        transportType == Self.builtInTransport && deviceType == Self.builtInWideAngleType ? .builtIn : .external
    }
}

/// 证据里记下帧来自哪类镜头。只分两类：内建，和其余一切。
enum FaceCameraClass: String, Sendable, Equatable {
    case builtIn, external
}

/// 相机准入（ID-03）：刷脸（identity 用途）只接内建镜头；其余用途选相机的规矩不变。
enum FaceCameraAdmission {
    /// 这台相机能不能给 identity 用途开订阅。列表里找不到的一律不认。
    static func admitsIdentity(deviceID: String, among cameras: [FaceCameraDescriptor]) -> Bool {
        cameras.first { $0.id == deviceID }?.cameraClass == .builtIn
    }

    /// 刷脸用哪台相机：设置里指定了就只看那一台（不是内建就拒，不悄悄换别的）；没指定就取第一台内建。
    static func identityCamera(among cameras: [FaceCameraDescriptor], configured: String?) -> FaceCameraDescriptor? {
        if let configured, !configured.isEmpty {
            return cameras.first { $0.id == configured && $0.cameraClass == .builtIn }
        }
        return cameras.first { $0.cameraClass == .builtIn }
    }
}

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
    /// 刷脸实验：算出特征的帧数，和想算却没算出的帧数（脸太偏、没眼睛点、Vision 失败）。只是计数。
    var identityEmbedded: UInt64 = 0
    var identityUnavailable: UInt64 = 0
}

// FaceGeometry（每张脸的框、朝向和刷脸实验用的对齐几何）定义在 FaceEmbedder.swift。

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
    /// 这一帧所有脸的几何，多人帧不再丢。上面的单脸字段仍只在恰好一张脸时填写。
    var faces: [FaceGeometry] = []
    /// 刷脸实验的特征，只发给 `.identity` 用途的订阅者；其余订阅者拿到的永远是 nil。
    var identity: FaceIdentitySample? = nil

    func withoutIdentity() -> FaceObservation {
        var copy = self; copy.identity = nil; return copy
    }
}

/// 一帧里最大那张脸的特征（实验）。只在内存里交给刷脸守卫，不写日志、不落盘。
struct FaceIdentitySample: Sendable, Equatable {
    let modelVersion: String
    /// 对应 `FaceObservation.faces` 的下标。
    let faceIndex: Int
    /// 没算出来（脸太偏、没有眼睛点、Vision 失败）就是 nil。
    let embedding: [Float]?
    /// 画质门（身份线 §3.3，实验）：同一张脸的 Vision faceCaptureQuality，0...1；没跑成就是 nil。
    var captureQuality: Double? = nil
    /// 同一张脸的裁切里抽样的平均亮度（0...1）与近白、近灰占比；没注入采样或像素格式不认就是 nil。
    var brightness: Double? = nil
    var glareRatio: Double? = nil
    /// 否决线索（§3.4）：屏幕/手机边框候选，Vision 的归一化框（原点左下，与脸框同一坐标系）。
    /// 每 3 帧才跑一次（FaceIdentityAnalysis.rectangleInterval），没跑的帧是 nil，跑了没找到是空数组。
    var rectangles: [CGRect]? = nil
}

/// 刷脸实验的画质采样：脸部裁切里抽样的像素（交错 RGB，每像素 3 字节）→ 平均亮度（0...1）与近白、近灰占比。
/// 由刷脸实验注入（生产用 Core 的 FaceCaptureSampling.stats，见 FaceScanExperiment），在相机队列上同步调用；
/// 像素只在这一次调用里活着，不存、不出相机队列、不写日志。
typealias FaceRegionSampler = @Sendable (_ rgb: [UInt8]) -> (brightness: Double, glareRatio: Double)?

/// identity 订阅时相机队列上多做的几件事（身份线 §3.3、§3.4，实验）。
enum FaceIdentityAnalysis {
    /// 矩形检测（屏幕/手机边框）每隔几帧跑一次；与 Core 的 RectangleCadence.interval 一致（测试核对）。
    static let rectangleInterval: UInt64 = 3
    /// 画质请求钉死的修订；换修订分数分布就变，阈值要重标。
    static let captureQualityRevision = VNDetectFaceCaptureQualityRequestRevision3
    /// 脸部裁切每边抽这么多个点（32×32 = 1024 个像素）。
    static let samplingGrid = 32

    static func makeRectangleRequest() -> VNDetectRectanglesRequest {
        let request = VNDetectRectanglesRequest()
        // 手机竖拿约 9:19.5（0.46），放宽到 0.3；最小边占画面短边 0.1。都是起点，待真机标定。
        request.minimumAspectRatio = 0.3
        request.maximumAspectRatio = 1
        request.minimumSize = 0.1
        request.maximumObservations = 4
        return request
    }
}

/// 从像素缓冲区里按网格抽脸部裁切的像素，换成交错 RGB（8 位）。只读、不拷整图、不存。
enum FaceRegionPixels {
    /// `box` 是 Vision 的归一化框（原点左下）；像素缓冲区第 0 行在上（采集方向 .up）。
    /// 认 BGRA 与 420v/420f 双平面；别的格式、框不合法、锁不住缓冲区都返回 nil。
    static func rgbSamples(_ buffer: CVPixelBuffer, box: CGRect, grid: Int = FaceIdentityAnalysis.samplingGrid) -> [UInt8]? {
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        guard grid > 0, width > 0, height > 0,
              [box.minX, box.minY, box.width, box.height].allSatisfy(\.isFinite) else { return nil }
        let clipped = box.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard !clipped.isNull, clipped.width > 0, clipped.height > 0 else { return nil }
        let left = Double(clipped.minX) * Double(width), right = Double(clipped.maxX) * Double(width)
        let top = (1 - Double(clipped.maxY)) * Double(height), bottom = (1 - Double(clipped.minY)) * Double(height)
        func pick(_ index: Int, _ low: Double, _ high: Double, _ limit: Int) -> Int {
            min(limit - 1, max(0, Int(low + (Double(index) + 0.5) * (high - low) / Double(grid))))
        }
        let format = CVPixelBufferGetPixelFormatType(buffer)
        guard CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        var rgb = [UInt8]()
        rgb.reserveCapacity(grid * grid * 3)
        switch format {
        case kCVPixelFormatType_32BGRA:
            guard let base = CVPixelBufferGetBaseAddress(buffer)?.assumingMemoryBound(to: UInt8.self) else { return nil }
            let stride = CVPixelBufferGetBytesPerRow(buffer)
            for row in 0..<grid {
                let y = pick(row, top, bottom, height)
                for column in 0..<grid {
                    let offset = y * stride + pick(column, left, right, width) * 4
                    rgb.append(base[offset + 2]); rgb.append(base[offset + 1]); rgb.append(base[offset])
                }
            }
        case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, kCVPixelFormatType_420YpCbCr8BiPlanarFullRange:
            guard CVPixelBufferGetPlaneCount(buffer) >= 2,
                  let luma = CVPixelBufferGetBaseAddressOfPlane(buffer, 0)?.assumingMemoryBound(to: UInt8.self),
                  let chroma = CVPixelBufferGetBaseAddressOfPlane(buffer, 1)?.assumingMemoryBound(to: UInt8.self)
            else { return nil }
            let lumaStride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
            let chromaStride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 1)
            let chromaWidth = max(1, CVPixelBufferGetWidthOfPlane(buffer, 1))
            let chromaHeight = max(1, CVPixelBufferGetHeightOfPlane(buffer, 1))
            let fullRange = format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            let bt709 = (CVBufferCopyAttachment(buffer, kCVImageBufferYCbCrMatrixKey, nil) as? String)
                == (kCVImageBufferYCbCrMatrix_ITU_R_709_2 as String)
            for row in 0..<grid {
                let y = pick(row, top, bottom, height)
                let cy = min(chromaHeight - 1, y * chromaHeight / height)
                for column in 0..<grid {
                    let x = pick(column, left, right, width)
                    let cx = min(chromaWidth - 1, x * chromaWidth / width)
                    let c = cy * chromaStride + cx * 2
                    let (r, g, b) = Self.rgb(y: luma[y * lumaStride + x], cb: chroma[c], cr: chroma[c + 1],
                                             fullRange: fullRange, bt709: bt709)
                    rgb.append(r); rgb.append(g); rgb.append(b)
                }
            }
        default:
            return nil
        }
        return rgb
    }

    /// YCbCr（8 位）→ RGB。videoRange：Y 16...235、C 16...240；矩阵按缓冲区标注取 BT.709，否则 BT.601。
    static func rgb(y: UInt8, cb: UInt8, cr: UInt8, fullRange: Bool, bt709: Bool) -> (UInt8, UInt8, UInt8) {
        let luma = fullRange ? Double(y) : (Double(y) - 16) * 255 / 219
        let scale = fullRange ? 1.0 : 255.0 / 224
        let u = (Double(cb) - 128) * scale, v = (Double(cr) - 128) * scale
        let (rv, gu, gv, bu) = bt709 ? (1.5748, 0.1873, 0.4681, 1.8556) : (1.402, 0.344136, 0.714136, 1.772)
        func clamp(_ value: Double) -> UInt8 { UInt8(max(0, min(255, value.rounded()))) }
        return (clamp(luma + rv * v), clamp(luma - gu * u - gv * v), clamp(luma + bu * u))
    }
}

enum FaceObservationSourceError: Error {
    case authorizationDenied, unknownDevice, unavailable, interrupted, superseded
    case cameraInUse, invalidLifetime, expired
    /// identity 用途只接内建镜头；外接、iPhone、虚拟相机都在这里被拒。
    case cameraNotAdmitted
    case runtime(String)
}

enum FaceObservationPurpose: Sendable {
    /// identity：刷脸实验，相机队列上额外算一次脸部特征（后端见 FaceEmbedder / FaceEmbedderBackends）。
    /// bystander：有人在看，只要脸框和朝向，帧率单开一档（FaceCameraTuning.bystanderSourceFPS）。
    case geometry, command, securityChallenge, identity, bystander
    var requestedFPS: Double {
        switch self {
        case .geometry: FaceCameraTuning.targetSourceFPS
        case .bystander: FaceCameraTuning.bystanderSourceFPS
        case .identity: 10
        case .command, .securityChallenge: 25
        }
    }
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
    /// 有 `.identity` 订阅者时交给它特征后端，最后一个走了就传 nil。
    func setIdentityEmbedder(_ embedder: (any FaceEmbedder)?)
    /// 同上，画质采样（亮度、反光）；没有 identity 订阅者就是 nil。
    func setIdentitySampler(_ sampler: FaceRegionSampler?)
    func stop()
    func countersSnapshot() async -> FacePipelineCounters
}

extension FaceCaptureWorker {
    func setIdentityEmbedder(_ embedder: (any FaceEmbedder)?) {}
    func setIdentitySampler(_ sampler: FaceRegionSampler?) {}
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
    private let admitIdentity: @MainActor (String) -> Bool
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
         },
         admitIdentity: @escaping @MainActor (String) -> Bool = {
             FaceCameraAdmission.admitsIdentity(deviceID: $0, among: FaceObservationSource.devices())
         }) {
        self.worker = worker; self.clock = clock; self.authorize = authorize; self.admitIdentity = admitIdentity
    }
    func reserve(token: FaceObservationSubscription = .init(id: UUID()), deviceID: String, purpose: FaceObservationPurpose, validFor: Double?,
                 observation: @escaping @MainActor (FaceObservation) -> Void,
                 failure: @escaping @MainActor (Error) -> Void) throws -> FaceObservationSubscription {
        expireConsumers()
        guard !deviceID.isEmpty else { throw FaceObservationSourceError.unknownDevice }
        if purpose == .identity, !admitIdentity(deviceID) { throw FaceObservationSourceError.cameraNotAdmitted }
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
            syncWorkerDemand()
        } catch {
            remove(token)
            throw error
        }
    }
    private var requestedFPS: Double { consumers.values.map { $0.purpose.requestedFPS }.max() ?? FaceCameraTuning.targetSourceFPS }
    private var wantsIdentity: Bool { consumers.values.contains { $0.purpose == .identity } }
    /// 刷脸实验的特征后端；只有存在 `.identity` 订阅者时才交给相机工作队列。
    var identityEmbedder: (any FaceEmbedder)? {
        didSet { if !consumers.isEmpty { syncWorkerDemand() } }
    }
    /// 刷脸实验的画质采样；同样只在有 `.identity` 订阅者时交给相机工作队列。
    var identitySampler: FaceRegionSampler? {
        didSet { if !consumers.isEmpty { syncWorkerDemand() } }
    }
    private func syncWorkerDemand() {
        worker.setRequestedFPS(requestedFPS)
        worker.setIdentityEmbedder(wantsIdentity ? identityEmbedder : nil)
        worker.setIdentitySampler(wantsIdentity ? identitySampler : nil)
    }
    func remove(_ token: FaceObservationSubscription) {
        guard consumers.removeValue(forKey: token) != nil else { return }
        waiters.removeValue(forKey: token)?.resume(throwing: CancellationError())
        if consumers.isEmpty { endCapture() }
        else { syncWorkerDemand(); scheduleExpiry() }
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
            else { syncWorkerDemand(); scheduleExpiry() }
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
            consumer.observation(consumer.purpose == .identity ? observation : observation.withoutIdentity())
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
    /// 刷脸实验的特征后端（整个进程共用一个相机，所以设在共享的 hub 上）。
    var identityEmbedder: (any FaceEmbedder)? {
        get { hub.identityEmbedder }
        set { hub.identityEmbedder = newValue }
    }
    /// 刷脸实验的画质采样（同上，设在共享的 hub 上）。
    var identitySampler: FaceRegionSampler? {
        get { hub.identitySampler }
        set { hub.identitySampler = newValue }
    }
    deinit {
        let hub = hub, tokens = subscriptions
        Task { @MainActor in for token in tokens { hub.remove(token) } }
    }
}

/// @unchecked Sendable is limited to dispatching work; all mutable state is queue-confined.
private final class FaceObservationWorker: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, FaceCaptureWorker, @unchecked Sendable {
    /// F12：utility。主 stage 的推理在神经引擎上，时间不随队列 QoS 变；前后处理的 CPU 部分可以去能效核。
    private let queue = DispatchQueue(label: "WindowShade.face.observations", qos: .utility)
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
    /// F12：同一个 landmarks 请求与连续帧 handler 在会话内复用；退回系统预设或换会话时才重建。只在队列上动。
    private var requests = FaceLandmarkRequestSlot<VNDetectFaceLandmarksRequest, VNSequenceRequestHandler>(
        makeRequest: { pinned in
            let request = VNDetectFaceLandmarksRequest()
            // 钉在神经引擎上（main stage）：默认偶尔退回 GPU/CPU。实测钉住后结果一致（IoU 0.995）、
            // 不占 GPU、延迟低 15–30%。注意这只决定 main stage 用哪个加速器，前处理与后处理仍会用到
            // CPU/GPU，不能写成「整条路不用 CPU/GPU」。连续失败会退回系统预设（见 fallback）。
            if pinned, let ane = FaceLandmarkComputeDevice.ane { request.setComputeDevice(ane, for: .main) }
            return request
        },
        makeHandler: { VNSequenceRequestHandler() })
    /// 刷脸实验：有 `.identity` 订阅者时才有后端、才算特征。只在队列上动。
    private var identityEmbedder: (any FaceEmbedder)?
    /// 刷脸实验的画质：采样（注入）、Vision 画质请求、矩形请求与它的节拍。只在 identity 订阅时用，只在队列上动。
    private var identitySampler: FaceRegionSampler?
    private var captureQualityRequest: VNDetectFaceCaptureQualityRequest?
    private var rectangleRequest: VNDetectRectanglesRequest?
    private var identityFrames: UInt64 = 0
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
                    self.requests.reset()
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
    func setIdentityEmbedder(_ embedder: (any FaceEmbedder)?) {
        queue.async {
            if embedder == nil { self.identityFrames = 0 }
            self.identityEmbedder = embedder
        }
    }
    func setIdentitySampler(_ sampler: FaceRegionSampler?) {
        queue.async { self.identitySampler = sampler }
    }
    func stop() { queue.async { self.tearDown() } }
    private func tearDown() {
        deliver = nil; fail = nil
        identityEmbedder = nil; identitySampler = nil
        captureQualityRequest = nil; rectangleRequest = nil; identityFrames = 0
        requests.reset()
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
        let (request, handler) = requests.acquire(pinned: !fallback.usesDefaultComputeDevice)
        counters.camera.pinsNeuralEngine = !fallback.usesDefaultComputeDevice
        counters.visionStarted &+= 1
        let visionStartedAt = CACurrentMediaTime()
        do { try handler.perform([request], on: buffer, orientation: .up) }
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
        func finite(_ number: NSNumber?) -> Double? { FaceAlignment.finite(number) }
        let embedder = identityEmbedder
        let geometry = faces.prefix(FaceGeometry.maxPerFrame).map {
            FaceAlignment.geometry(for: $0, imageSize: imageSize, aligned: embedder != nil)
        }
        let identity = embedder.flatMap {
            identitySample(faces: geometry, observations: faces, buffer: buffer, handler: handler, embedder: $0)
        }
        deliver?(.init(cameraID: deviceID, generation: token, sequence: sequence,
            observedAt: captured, faceCount: faces.count, yaw: finite(face?.yaw), pitch: finite(face?.pitch),
            leftEyeOpenness: eye(face?.landmarks?.leftEye), rightEyeOpenness: eye(face?.landmarks?.rightEye),
            faceBoundingBox: face?.boundingBox, confidence: face?.confidence,
            mouthLandmarks: face?.landmarks?.outerLips?.normalizedPoints,
            sourceFPS: counters.camera.requestedSourceFPS > 0 ? counters.camera.requestedSourceFPS : nil,
            faces: geometry, identity: identity))
        counters.delivered &+= 1
    }

    /// 只给最大那张脸算特征（守卫也只看最大那张，同样的取法）。同一帧、同一个缓冲区，算完即丢。
    /// 画质也只看这张脸：画质请求用同一个 handler、直接拿 landmarks 的这张脸做输入（不再检测一遍）；
    /// 亮度与反光在这张脸的框里抽样；矩形每 3 帧跑一次。
    private func identitySample(faces: [FaceGeometry], observations: [VNFaceObservation], buffer: CVPixelBuffer,
                                handler: VNSequenceRequestHandler, embedder: any FaceEmbedder) -> FaceIdentitySample? {
        guard let (index, face) = faces.enumerated().max(by: { $0.element.boundingBox.width < $1.element.boundingBox.width })
        else { return nil }
        let embedding = embedder.embed(pixelBuffer: buffer, face: face)
        if embedding == nil { counters.identityUnavailable &+= 1 } else { counters.identityEmbedded &+= 1 }
        var sample = FaceIdentitySample(modelVersion: embedder.modelVersion, faceIndex: index, embedding: embedding)
        if observations.indices.contains(index) {
            sample.captureQuality = captureQuality(of: observations[index], buffer: buffer, handler: handler)
        }
        if let sampler = identitySampler, let rgb = FaceRegionPixels.rgbSamples(buffer, box: face.boundingBox),
           let stats = sampler(rgb), stats.brightness.isFinite, stats.glareRatio.isFinite {
            sample.brightness = stats.brightness
            sample.glareRatio = stats.glareRatio
        }
        if identityFrames % FaceIdentityAnalysis.rectangleInterval == 0 {
            sample.rectangles = rectangles(buffer: buffer, handler: handler)
        }
        identityFrames &+= 1
        return sample
    }

    private func captureQuality(of face: VNFaceObservation, buffer: CVPixelBuffer, handler: VNSequenceRequestHandler) -> Double? {
        let request = captureQualityRequest ?? {
            let made = VNDetectFaceCaptureQualityRequest()
            made.revision = FaceIdentityAnalysis.captureQualityRevision
            return made
        }()
        captureQualityRequest = request
        request.inputFaceObservations = [face]
        defer { request.inputFaceObservations = nil }
        guard (try? handler.perform([request], on: buffer, orientation: .up)) != nil,
              let quality = request.results?.first?.faceCaptureQuality, quality.isFinite else { return nil }
        return min(1, max(0, Double(quality)))
    }

    private func rectangles(buffer: CVPixelBuffer, handler: VNSequenceRequestHandler) -> [CGRect]? {
        let request = rectangleRequest ?? FaceIdentityAnalysis.makeRectangleRequest()
        rectangleRequest = request
        guard (try? handler.perform([request], on: buffer, orientation: .up)) != nil else { return nil }
        return (request.results ?? []).map(\.boundingBox).filter {
            [$0.minX, $0.minY, $0.width, $0.height].allSatisfy(\.isFinite) && $0.width > 0 && $0.height > 0
        }
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


/// F12：一个会话里复用同一个 Vision 请求和连续帧 handler。`pinned` 变了（退回系统预设）或
/// `reset()`（换会话、拆掉）才重建；computeDevice 只在建的时候设一次。不是线程安全的，
/// 由持有者限定在一条队列上用。泛型只为让测试换成替身计数。
struct FaceLandmarkRequestSlot<Request: AnyObject, Handler: AnyObject> {
    private let makeRequest: (_ pinned: Bool) -> Request
    private let makeHandler: () -> Handler
    private var current: (request: Request, handler: Handler, pinned: Bool)?
    /// 建过几次（测试与诊断用）。
    private(set) var builds = 0

    init(makeRequest: @escaping (_ pinned: Bool) -> Request, makeHandler: @escaping () -> Handler) {
        self.makeRequest = makeRequest
        self.makeHandler = makeHandler
    }

    mutating func acquire(pinned: Bool) -> (Request, Handler) {
        if let current, current.pinned == pinned { return (current.request, current.handler) }
        let built = (request: makeRequest(pinned), handler: makeHandler(), pinned: pinned)
        current = built
        builds += 1
        return (built.request, built.handler)
    }

    mutating func reset() { current = nil }
}

/// 神经引擎只查一次（后台队列上第一次用到时）。
private enum FaceLandmarkComputeDevice {
    static let ane: MLComputeDevice? = {
        guard let devices = try? VNDetectFaceLandmarksRequest().supportedComputeStageDevices[.main] else { return nil }
        return devices.first { if case .neuralEngine = $0 { return true } else { return false } }
    }()
}

/// 相机列表缓存：枚举放在后台，主线程只读。
private final class CameraList: Sendable {
    static let shared = CameraList()
    private struct State {
        var cameras: [FaceCameraDescriptor] = []
        var started = false
    }
    private let state = Mutex(State())
    private let queue = DispatchQueue(label: "WindowShade.camera-list", qos: .utility)

    func current() -> [FaceCameraDescriptor] {
        start()
        return state.withLock { $0.cameras }
    }

    func start() {
        let first = state.withLock { state -> Bool in
            let first = !state.started
            state.started = true
            return first
        }
        guard first else { return }
        refresh()
        for name in [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in self?.refresh() }
        }
    }

    private func refresh() {
        queue.async { [weak self] in
            let found = FaceObservationWorker.devices().map {
                FaceCameraDescriptor(id: $0.uniqueID, name: $0.localizedName,
                                     transportType: $0.transportType, deviceType: $0.deviceType.rawValue)
            }
            guard let self else { return }
            self.state.withLock { $0.cameras = found }
        }
    }
}
