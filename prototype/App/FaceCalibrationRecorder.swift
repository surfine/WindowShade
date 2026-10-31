import Cocoa
@preconcurrency import AVFoundation
@preconcurrency import Vision

/// `--face-calibrate-record`：Aaron 一次性录自己的“本人样本”，给门槛标定用（tools/face-calibration）。
///
/// 只存脸部特征数字（和刷脸实验同一条管线：同样的检测、摆正、裁切、Vision 特征），不存图像、不存裁切图。
/// 点“开始”才开相机；约 60 秒，刘海里依次提示正对、转头、抬低头、远近和换光线。
/// 结果写到 WindowShade-models/calibration/genuine.json（权限 0600），不进 git、不联网。
/// 启动时不弹授权以外的任何东西；点取消或收走卡片就丢弃，什么也不写。

/// 采集队列上的抓取。所有可变状态只在自己的串行队列上读写（没有锁）；对外只通过队列的 async 交互。
final class FaceCalibrationCapture: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    struct Result: Sendable {
        let probes: [FaceGenuineSamples.Probe]
        let rejected: [String: Int]
    }

    /// 两次采样之间至少隔这么久，相邻帧几乎一样的样本没有新信息。
    static let minimumInterval = 0.25
    /// 一步里最多收这么多条，防止一直不动堆出几千条一样的。
    static let maximumPerStep = 60

    private let queue = DispatchQueue(label: "windowshade.face.calibration.capture", qos: .userInitiated)
    private let embedder: any FaceEmbedder
    private let onCount: @Sendable (Int) -> Void
    private var session: AVCaptureSession?
    private var step: String?
    private var lastAccepted = 0.0
    private var probes: [FaceGenuineSamples.Probe] = []
    private var perStep: [String: Int] = [:]
    private var rejected: [String: Int] = [:]

    init(embedder: any FaceEmbedder, onCount: @escaping @Sendable (Int) -> Void) {
        self.embedder = embedder
        self.onCount = onCount
    }

    /// 打开相机（调用方已确认过授权）。失败返回 false。
    func start(deviceID: String) -> Bool {
        queue.sync {
            guard let device = AVCaptureDevice(uniqueID: deviceID),
                  let input = try? AVCaptureDeviceInput(device: device) else { return false }
            let session = AVCaptureSession()
            session.beginConfiguration()
            if session.canSetSessionPreset(.vga640x480) { session.sessionPreset = .vga640x480 }
            let output = AVCaptureVideoDataOutput()
            output.alwaysDiscardsLateVideoFrames = true
            let yuv = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
            if output.availableVideoPixelFormatTypes.contains(yuv) {
                output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: yuv]   // 与 App 的首选格式一致
            }
            guard session.canAddInput(input), session.canAddOutput(output) else { return false }
            session.addInput(input); session.addOutput(output)
            output.setSampleBufferDelegate(self, queue: queue)
            session.commitConfiguration()
            session.startRunning()
            guard session.isRunning else { return false }
            self.session = session
            return true
        }
    }

    /// 当前这一步的标识；nil = 暂停收集（倒数、结束）。
    func setStep(_ id: String?) { queue.async { self.step = id } }

    /// 停相机，把收到的交出来（在主线程回调）。之后这个对象不再用。
    func finish(_ completion: @escaping @Sendable (Result) -> Void) {
        queue.async {
            self.step = nil
            self.session?.stopRunning()
            self.session = nil
            let result = Result(probes: self.probes, rejected: self.rejected)
            self.probes = []
            DispatchQueue.main.async { completion(result) }
        }
    }

    private func reject(_ reason: String) { rejected[reason, default: 0] += 1 }

    func captureOutput(_ output: AVCaptureOutput, didOutput sample: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let step, let buffer = sample.imageBuffer else { return }
        let now = CACurrentMediaTime()
        guard now - lastAccepted >= Self.minimumInterval, perStep[step, default: 0] < Self.maximumPerStep else { return }
        let request = VNDetectFaceLandmarksRequest()
        do { try VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up).perform([request]) }
        catch { reject("vision"); return }
        let faces = request.results ?? []
        guard faces.count == 1, let face = faces.first else { reject(faces.isEmpty ? "no-face" : "several-faces"); return }
        guard face.boundingBox.width >= FaceScanTuning().minimumFaceWidth else { reject("face-too-small"); return }
        let size = CGSize(width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer))
        let geometry = FaceAlignment.geometry(for: face, imageSize: size, aligned: true)
        guard geometry.eyeLineAngle != nil else { reject("no-eyes"); return }
        guard let vector = embedder.embed(pixelBuffer: buffer, face: geometry) else { reject("embed-nil"); return }
        lastAccepted = now
        perStep[step, default: 0] += 1
        probes.append(FaceGenuineSamples.Probe(step: step, embedding: FaceTemplateSet.bytes(vector)))
        onCount(probes.count)
    }
}

@MainActor
enum FaceCalibrationRecorder {
    private static var running: Session?

    static var outputDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["WINDOWSHADE_CALIBRATION_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/WindowShade-models/calibration", isDirectory: true)
    }

    static func run(owner: AppDelegate) {
        let session = Session(island: owner.notch.leases)
        running = session
        session.begin()
    }

    /// 界面一步一句。键必须以字面量出现在 WSL10n.text 里（本地化检查按它找）。
    static func prompt(for step: String) -> String {
        switch step {
        case "front": WSL10n.text("face.calibrate.step.front", zh: "正对镜头，自然表情")
        case "left": WSL10n.text("face.calibrate.step.left", zh: "头慢慢向左转一点")
        case "right": WSL10n.text("face.calibrate.step.right", zh: "头慢慢向右转一点")
        case "up": WSL10n.text("face.calibrate.step.up", zh: "稍微抬头")
        case "down": WSL10n.text("face.calibrate.step.down", zh: "稍微低头")
        case "far": WSL10n.text("face.calibrate.step.far", zh: "靠近一点，再退远一点")
        case "light": WSL10n.text("face.calibrate.step.light", zh: "换个光线：开关台灯，或转向窗户")
        default: ""
        }
    }

    @MainActor
    final class Session {
        enum Phase { case consent, recording, finishing, ended }

        private let island: NotchLeaseHub
        private let plan = FaceCalibrationRecordPlan.standard
        private let embedder = VisionFaceEmbedder()
        private var card: FaceCalibrationView?
        private var capture: FaceCalibrationCapture?
        private var timer: Timer?
        private var startedAt = 0.0
        private var phase = Phase.consent
        private var currentStep: String?
        private var capturedCount = 0
        private var templates: [FaceTemplate] = []

        init(island: NotchLeaseHub) { self.island = island }

        func begin() {
            log("face calibrate record: waiting for consent")
            let card = FaceCalibrationView()
            card.onStart = { [weak self] in self?.consented() }
            card.onCancel = { [weak self] in self?.end("cancelled", wrote: false) }
            guard island.show(card, ownerID: "faceCalibrationRecord", layer: .opened,
                              onDismiss: { [weak self] _ in self?.dismissedByIsland() }) else {
                log("FAIL face calibrate record: island unavailable"); finish(1); return
            }
            self.card = card
            card.showConsent(totalSeconds: Int(plan.totalSeconds))
        }

        private func dismissedByIsland() {
            guard phase != .ended else { return }
            card = nil
            end("dismissed", wrote: false)
        }

        private func consented() {
            guard phase == .consent else { return }
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: startCapture()
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated { granted ? self.startCapture() : self.end("camera denied", wrote: false) }
                    }
                }
            default: end("camera denied", wrote: false)
            }
        }

        private func startCapture() {
            guard phase == .consent else { return }
            guard VisionFaceEmbedder.isSupported,
                  let camera = FaceCameraAdmission.identityCamera(among: FaceObservationSource.devices(), configured: nil) else {
                end("no built-in camera or Vision revision unsupported", wrote: false); return
            }
            // 已登记的模板（和 App 实际比对用的同一份）一并带上；读不到就空着，工具改用正对镜头的头几帧。
            templates = (try? FaceTemplateKeychainStore().load(modelVersion: embedder.modelVersion)) ?? []
            let capture = FaceCalibrationCapture(embedder: embedder) { [weak self] count in
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.countChanged(count) } }
            }
            guard capture.start(deviceID: camera.id) else { end("camera unavailable", wrote: false); return }
            self.capture = capture
            phase = .recording
            startedAt = CACurrentMediaTime()
            let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
            tick()
        }

        private func countChanged(_ count: Int) {
            capturedCount = count
        }

        private func tick() {
            guard phase == .recording else { return }
            switch plan.position(at: CACurrentMediaTime() - startedAt) {
            case .countdown(let remaining):
                card?.showCountdown(remaining: remaining)
            case .step(let index, let remaining):
                let step = plan.steps[index].id
                if step != currentStep {
                    currentStep = step
                    capture?.setStep(step)
                }
                card?.showStep(prompt: FaceCalibrationRecorder.prompt(for: step), remaining: remaining, count: capturedCount)
            case .finished:
                capture?.setStep(nil)
                phase = .finishing
                timer?.invalidate(); timer = nil
                let recordedTemplates = templates, version = embedder.modelVersion
                capture?.finish { result in
                    MainActor.assumeIsolated {
                        self.write(result, templates: recordedTemplates, modelVersion: version)
                    }
                }
            }
        }

        private func write(_ result: FaceCalibrationCapture.Result, templates: [FaceTemplate], modelVersion: String) {
            capture = nil
            let samples = FaceGenuineSamples(
                modelVersion: modelVersion, recordedAt: ISO8601DateFormatter().string(from: Date()),
                templates: templates.map { FaceTemplateSet.bytes($0.embedding) }, probes: result.probes)
            var perStep: [String: Int] = [:]
            for probe in result.probes { perStep[probe.step, default: 0] += 1 }
            let url = FaceCalibrationRecorder.outputDirectory.appendingPathComponent("genuine.json")
            guard result.probes.count >= 30 else {
                log("FAIL face calibrate record: only \(result.probes.count) samples (rejected=\(result.rejected)); nothing written")
                end("too few samples", wrote: false); return
            }
            do {
                try samples.write(to: url)
                log("PASS face calibrate record: \(result.probes.count) samples, \(templates.count) enrolled templates, perStep=\(perStep.sorted { $0.key < $1.key }), rejected=\(result.rejected) -> \(url.path)")
                end("saved", wrote: true)
            } catch {
                log("FAIL face calibrate record: could not write \(url.path): \(error)")
                end("write failed", wrote: false)
            }
        }

        private func end(_ reason: String, wrote: Bool) {
            guard phase != .ended else { return }
            let wasRecording = phase == .recording
            phase = .ended
            timer?.invalidate(); timer = nil
            if wasRecording { capture?.finish { _ in } }   // 取消：丢弃已收的
            capture = nil
            if !wrote { log("face calibrate record: ended without saving (\(reason))") }
            card?.showEnded(saved: wrote)
            let shown = card
            card = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + (wrote ? 3 : 1.2)) {
                MainActor.assumeIsolated {
                    if let shown { self.island.dismiss(ifShowing: shown) }
                    self.finish(wrote ? 0 : 1)
                }
            }
        }

        private func finish(_ code: Int32) {
            FaceCalibrationRecorder.running = nil
            exit(code)
        }

        private func log(_ line: String) {
            print(line)
            fflush(stdout)
            if let path = ProcessInfo.processInfo.environment["WINDOWSHADE_PROBE_OUT"] {
                let data = Data((line + "\n").utf8)
                if let handle = FileHandle(forWritingAtPath: path) {
                    handle.seekToEndOfFile(); handle.write(data); try? handle.close()
                } else { try? data.write(to: URL(fileURLWithPath: path)) }
            }
        }
    }
}

/// 记录卡：说明与同意、倒数、每一步一句、已记录几帧、取消。不显示相机画面。
@MainActor final class FaceCalibrationView: NSView, WS2LeaseContent {
    static let size = NSSize(width: 400, height: 150)
    var inputIsCurrent: (() -> Bool) = { false }
    var interactionSize: NSSize { Self.size }
    var onStart: (() -> Void)?
    var onCancel: (() -> Void)?
    private let icon = NSImageView()
    private let title = NSTextField(labelWithString: WSL10n.text("face.calibrate.title", zh: "记录你的脸（标定）"))
    private let detail = NSTextField(wrappingLabelWithString: "")
    private let progress = NSTextField(labelWithString: "")
    private let startButton = NSButton(title: WSL10n.text("face.calibrate.start", zh: "开始"), target: nil, action: nil)
    private let cancelButton = NSButton(title: WSL10n.text("settings.common.cancel", zh: "取消"), target: nil, action: nil)

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        appearance = NSAppearance(named: .darkAqua)
        icon.image = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: nil)
        icon.contentTintColor = .white
        icon.symbolConfiguration = .init(pointSize: 30, weight: .regular)
        title.textColor = .white
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.lineBreakMode = .byTruncatingTail
        detail.textColor = .white.withAlphaComponent(0.7)
        detail.font = .systemFont(ofSize: 12)
        detail.maximumNumberOfLines = 3
        progress.textColor = .white.withAlphaComponent(0.8)
        progress.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        for button in [startButton, cancelButton] {
            button.isBordered = false
            button.bezelStyle = .inline
            button.contentTintColor = .white.withAlphaComponent(0.85)
            button.target = self
        }
        startButton.action = #selector(startRequest)
        cancelButton.action = #selector(cancelRequest)
        cancelButton.keyEquivalent = "\u{1b}"
        for item in [icon, title, detail, progress, startButton, cancelButton] { addSubview(item) }
        setAccessibilityLabel(WSL10n.text("face.calibrate.title", zh: "记录你的脸（标定）"))
    }
    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        let h = bounds.height, inset: CGFloat = 16
        icon.frame = NSRect(x: inset, y: h - 62, width: 34, height: 34)
        let textX = inset + 46, textWidth = max(0, bounds.width - inset * 2 - 46)
        title.frame = NSRect(x: textX, y: h - 40, width: textWidth, height: 18)
        detail.frame = NSRect(x: textX, y: h - 100, width: textWidth, height: 56)
        progress.frame = NSRect(x: textX, y: 18, width: 160, height: 15)
        cancelButton.frame = NSRect(x: bounds.width - inset - 48, y: 14, width: 48, height: 24)
        startButton.frame = NSRect(x: bounds.width - inset - 48 - 56, y: 14, width: 52, height: 24)
    }

    func showConsent(totalSeconds: Int) {
        detail.stringValue = WSL10n.text("face.calibrate.consent",
                                         zh: "会用相机约 %@ 秒，只记录脸部特征数字，不存画面。", String(totalSeconds))
        progress.stringValue = ""
        startButton.isHidden = false
        needsLayout = true
    }

    func showCountdown(remaining: Int) {
        startButton.isHidden = true
        detail.stringValue = WSL10n.text("face.calibrate.countdown", zh: "%@ 秒后开始，请看向镜头", String(remaining))
        progress.stringValue = ""
        needsLayout = true
    }

    func showStep(prompt: String, remaining: Int, count: Int) {
        startButton.isHidden = true
        detail.stringValue = prompt
        progress.stringValue = WSL10n.text("face.calibrate.progress", zh: "还剩 %@ 秒 · 已记录 %@ 帧", String(remaining), String(count))
        needsLayout = true
    }

    func showEnded(saved: Bool) {
        startButton.isHidden = true
        cancelButton.isHidden = true
        detail.stringValue = saved ? WSL10n.text("face.calibrate.saved", zh: "完成，已保存。可以收工了。")
                                   : WSL10n.text("face.calibrate.notSaved", zh: "没有保存。需要的话请再来一次。")
        progress.stringValue = ""
        needsLayout = true
    }

    func revoke() {
        inputIsCurrent = { false }
        onStart = nil
        onCancel = nil
    }

    @objc private func startRequest() { guard inputIsCurrent() else { return }; onStart?() }
    @objc private func cancelRequest() { guard inputIsCurrent() else { return }; onCancel?() }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}
