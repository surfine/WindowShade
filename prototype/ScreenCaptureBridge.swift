import AVFoundation
import Cocoa
import ScreenCaptureKit

enum ShareableContentLoader {
    static func current() async throws -> SCShareableContent {
        if #available(macOS 14.0, *) {
            return try await SCShareableContent.current
        }

        return try await withCheckedThrowingContinuation { continuation in
            SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) {
                content, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let content {
                    continuation.resume(returning: content)
                } else {
                    continuation.resume(throwing: PinnedPreviewError.noShareableContent)
                }
            }
        }
    }
}

final class WindowStreamCapture: NSObject, SCStreamDelegate, SCStreamOutput {
    let videoLayer = AVSampleBufferDisplayLayer()

    // 菜单缩略图的镜像层：同一批采样帧额外喂给它，实现"复用已在跑的流"的实时缩略图，
    // 不新建 capture、不轮询。弱引用，菜单预览视图销毁后自动断开。
    weak var mirrorLayer: AVSampleBufferDisplayLayer?

    // 交互期主画面全速投递（拖拽/动画需要实时性）；非交互期主画面每 2 帧投 1 帧
    // （≈15fps@30fps 源），镜像层固定每 3 帧投 1 帧（≈10fps）。帧投递全部离开
    // 主线程：macOS 15 走线程安全的 sampleBufferRenderer 直接在后台队列 enqueue，
    // 旧系统降频后回主线程，N 个置顶窗口不再以 30×N 帧/秒的节奏压主线程。
    var isInteractive: Bool {
        get {
            stateLock.lock()
            defer { stateLock.unlock() }
            return _isInteractive
        }
        set {
            stateLock.lock()
            _isInteractive = newValue
            stateLock.unlock()
        }
    }

    private var stream: SCStream?
    private var filter: SCContentFilter?
    private var configuration = SCStreamConfiguration()
    private let stateLock = NSLock()
    private var _isInteractive = false
    private var _isStopped = false
    // 每路 capture 一条串行帧队列：SCStreamOutput 的采样帧在这里做降频与投递，
    // 计数器只在队列内访问，不需要额外同步。
    private let frameQueue = DispatchQueue(label: "WindowShade.pin-frames", qos: .userInteractive)
    private var mainFrameIndex: UInt32 = 0
    private var mirrorFrameIndex: UInt32 = 0

    override init() {
        super.init()
        videoLayer.videoGravity = .resize
        videoLayer.backgroundColor = NSColor.clear.cgColor
    }

    func start(window: SCWindow, display: SCDisplay?) async throws {
        if stream != nil { return }
        let newFilter = SCContentFilter(desktopIndependentWindow: window)
        filter = newFilter
        configure(window: window, display: display)
        try await startStream(filter: newFilter)
    }

    func restart(window: SCWindow, display: SCDisplay?, width: CGFloat, height: CGFloat)
        async throws
    {
        stop()
        if filter == nil {
            filter = SCContentFilter(desktopIndependentWindow: window)
        }
        configure(width: width, height: height, display: display)
        guard let filter else { throw PinnedPreviewError.noSCWindow }
        try await startStream(filter: filter)
    }

    func updateSize(width: CGFloat, height: CGFloat, display: SCDisplay?) {
        configure(width: width, height: height, display: display)
        stream?.updateConfiguration(configuration) { error in
            if let error {
                wlog("pin-preview: capture update failed \(error.localizedDescription)")
            }
        }
    }

    func stop() {
        stateLock.lock()
        _isStopped = true
        stateLock.unlock()
        guard let activeStream = stream else { return }
        stream = nil
        activeStream.stopCapture { error in
            if let error {
                // -3808 = 串流已自行终止（如源窗口关闭后系统停流），再 stop 属预期，静默。
                let nsError = error as NSError
                if nsError.code != -3808 {
                    wlog("pin-preview: capture stop failed \(error.localizedDescription)")
                }
            }
        }
        DispatchQueue.main.async { [videoLayer] in
            if #available(macOS 15.0, *) {
                videoLayer.sampleBufferRenderer.flush(removingDisplayedImage: true) {}
            } else {
                videoLayer.flushAndRemoveImage()
            }
        }
    }

    private func startStream(filter: SCContentFilter) async throws {
        let newStream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try newStream.addStreamOutput(
            self, type: .screen, sampleHandlerQueue: .global(qos: .userInteractive))
        stream = newStream
        stateLock.withLock {
            _isStopped = false
        }
        try await newStream.startCapture()
    }

    private func configure(window: SCWindow, display: SCDisplay?) {
        configureBase(display: display)
        if #available(macOS 14.0, *), let filter {
            let scale = max(1, Int(filter.pointPixelScale))
            configuration.width = max(1, Int(ceil(filter.contentRect.width)) * scale)
            configuration.height = max(1, Int(ceil(filter.contentRect.height)) * scale)
        } else {
            configure(width: window.frame.width, height: window.frame.height, display: display)
        }
    }

    private func configure(width: CGFloat, height: CGFloat, display: SCDisplay?) {
        configureBase(display: display)
        let screen =
            display.flatMap { screenForDisplayID($0.displayID) }
            ?? screenForCocoaFrame(NSRect(x: 0, y: 0, width: width, height: height))
            ?? NSScreen.main
        let scale = screen?.backingScaleFactor ?? 2
        configuration.width = max(1, Int(ceil(width * scale)))
        configuration.height = max(1, Int(ceil(height * scale)))
    }

    private func configureBase(display: SCDisplay?) {
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.colorSpaceName = CGColorSpace.sRGB
        configuration.showsCursor = false
        configuration.queueDepth = 3
        configuration.scalesToFit = true
        if #available(macOS 13.0, *) {
            configuration.capturesAudio = false
        }
        let screen = display.flatMap { screenForDisplayID($0.displayID) } ?? NSScreen.main
        let fps = min(30, screen?.maximumFramesPerSecond ?? 30)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(max(1, fps)))
    }

    func stream(
        _ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard outputType == .screen, sampleBuffer.isValid else { return }
        frameQueue.async { [weak self] in
            guard let self else { return }
            self.stateLock.lock()
            let stopped = self._isStopped
            let interactive = self._isInteractive
            self.stateLock.unlock()
            guard !stopped else { return }
            self.mainFrameIndex &+= 1
            self.mirrorFrameIndex &+= 1
            let deliverMain = interactive || self.mainFrameIndex % 2 == 1
            let deliverMirror = self.mirrorFrameIndex % 3 == 1 && self.mirrorLayer != nil
            guard deliverMain || deliverMirror else { return }
            self.deliver(sampleBuffer, main: deliverMain, mirror: deliverMirror)
        }
    }

    // macOS 15 的 sampleBufferRenderer.enqueue 线程安全，直接在帧队列上投递；
    // 旧系统必须回主线程，但降频后主线程每路最多 ~15fps（镜像 10fps）。
    private func deliver(_ sampleBuffer: CMSampleBuffer, main: Bool, mirror: Bool) {
        if #available(macOS 15.0, *) {
            if main { Self.enqueue(sampleBuffer, into: videoLayer) }
            if mirror, let mirrorLayer { Self.enqueue(sampleBuffer, into: mirrorLayer) }
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if main { Self.enqueue(sampleBuffer, into: self.videoLayer) }
                if mirror, let mirrorLayer = self.mirrorLayer {
                    Self.enqueue(sampleBuffer, into: mirrorLayer)
                }
            }
        }
    }

    private static func enqueue(_ buffer: CMSampleBuffer, into layer: AVSampleBufferDisplayLayer) {
        if #available(macOS 15.0, *) {
            layer.sampleBufferRenderer.enqueue(buffer)
        } else {
            layer.enqueue(buffer)
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        wlog("pin-preview: capture stopped with error \(error.localizedDescription)")
        if self.stream === stream {
            self.stream = nil
        }
    }
}
