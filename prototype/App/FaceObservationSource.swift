import Cocoa
@preconcurrency import AVFoundation
@preconcurrency import Vision
import CoreML

struct FaceCameraDescriptor: Sendable, Hashable { let id: String; let name: String }
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
    private var deliver: (@Sendable (FaceObservation) -> Void)?
    private var fail: (@Sendable (Error) -> Void)?

    static func devices() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
            mediaType: .video, position: .unspecified).devices
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
                    output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                    guard session.canAddInput(input), session.canAddOutput(output) else {
                        session.commitConfiguration()
                        throw FaceObservationSourceError.unavailable
                    }
                    session.addInput(input)
                    session.addOutput(output)
                    output.setSampleBufferDelegate(self, queue: self.queue)
                    session.commitConfiguration()
                    self.session = session
                    self.output = output
                    self.deviceID = deviceID
                    self.token = token
                    self.sequence = 0
                    self.lastSample = 0
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
        guard self.output === output, now - startedAt >= 0.5, now - lastSample >= 0.125,
              sample.isValid, let buffer = sample.imageBuffer, let clock = session?.synchronizationClock else { return }
        let captured = CMSyncConvertTime(CMSampleBufferGetPresentationTimeStamp(sample), from: clock,
                                          to: CMClockGetHostTimeClock()).seconds
        guard captured.isFinite, captured > 0, now >= captured, now - captured < 0.5 else { return }
        lastSample = now
        let request = VNDetectFaceLandmarksRequest()
        // 钉在神经引擎上：默认偶尔退回 GPU/CPU；实测钉住后结果一致（IoU 0.995）、不占 GPU、延迟低 15–30%。没有神经引擎就用默认。
        if let ane = FaceLandmarkComputeDevice.ane { try? request.setComputeDevice(ane, for: .main) }
        do { try VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up).perform([request]) }
        catch { return }
        let faces = request.results ?? []
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
