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

    // 自适应帧率：普通置顶预览约 15fps，进入交互/拖动提高到 30fps，结束交互
    // 降回 15fps。改动通过 SCStream.updateConfiguration 调整 minimumFrameInterval，
    // 而不是"30fps 源流 + 自己丢一半"——后者只省显示层，不省 WindowServer 的
    // capture 成本。菜单镜像层按源帧率取约 8~10fps 的子集投递。
    // 帧投递全部离开主线程：macOS 15 走线程安全的 sampleBufferRenderer 直接在
    // frameQueue enqueue，旧系统降频后回主线程。
    var isInteractive: Bool {
        get {
            stateLock.lock()
            defer { stateLock.unlock() }
            return _isInteractive
        }
        set {
            stateLock.lock()
            let changed = _isInteractive != newValue
            _isInteractive = newValue
            stateLock.unlock()
            if changed {
                scheduleFrameRateReconfig()
            }
        }
    }

    private var stream: SCStream?
    private var filter: SCContentFilter?
    private var configuration = SCStreamConfiguration()
    private let stateLock = NSLock()
    private var _isInteractive = false
    private var _isStopped = false
    // 流代数：每次 start/restart 自增。异步 stop/flush/帧回调都要确认自己仍属于
    // 当前代数，否则旧流的 flush 会把新流刚显示的画面清掉。
    private var _captureGeneration: UInt64 = 0
    // 当前流的目标帧率（idle 15 / interactive 30）。帧投递与镜像取样的依据。
    private var _streamFPS: Int = 15
    // 帧率重配的 debounce 工作项：鼠标反复进出交互时不能疯狂 updateConfiguration。
    private var frameRateReconfigWorkItem: DispatchWorkItem?
    // 每路 capture 一条串行帧队列：SCStreamOutput 的采样帧在这里做降频与投递，
    // 计数器只在队列内访问，不需要额外同步。
    private let frameQueue = DispatchQueue(label: "WindowShade.pin-frames", qos: .userInteractive)
    private var mirrorFrameIndex: UInt32 = 0
    // 流被系统异常终止（源窗口变化、系统过渡等）时回调；由 PinnedPreviewController
    // 决定刷新 SCWindow、有限次数重启或结束会话。
    var onUnexpectedStop: ((Error) -> Void)?

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
        // 永久停流（stop）与重启走不同路径：restart 不必等"永久关闭"的主线程
        // UI 清理（flush），避免旧 flush 清掉新流的画面；generation 递增使旧的
        // 异步 stopCapture 回调与帧回调全部过期。
        let oldStream = stateLock.withLock {
            _isStopped = true
            _captureGeneration &+= 1
            let old = stream
            stream = nil
            return old
        }
        oldStream?.stopCapture { error in
            if let error {
                let nsError = error as NSError
                if nsError.code != -3808 {
                    wlog("pin-preview: capture stop failed \(error.localizedDescription)")
                }
            }
        }
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
        let generation = _captureGeneration
        let activeStream = stream
        stream = nil
        stateLock.unlock()
        activeStream?.stopCapture { error in
            if let error {
                // -3808 = 串流已自行终止（如源窗口关闭后系统停流），再 stop 属预期，静默。
                let nsError = error as NSError
                if nsError.code != -3808 {
                    wlog("pin-preview: capture stop failed \(error.localizedDescription)")
                }
            }
        }
        DispatchQueue.main.async { [weak self, videoLayer] in
            // 若在 flush 执行前已重启（generation 递增），旧 flush 不应清掉
            // 新流已经开始显示的画面。
            guard let self else { return }
            let currentGeneration = self.stateLock.withLock { self._captureGeneration }
            guard currentGeneration == generation else { return }
            if #available(macOS 15.0, *) {
                videoLayer.sampleBufferRenderer.flush(removingDisplayedImage: true) {}
            } else {
                videoLayer.flushAndRemoveImage()
            }
        }
    }

    private func startStream(filter: SCContentFilter) async throws {
        let newStream = SCStream(filter: filter, configuration: configuration, delegate: self)
        // frameQueue 本身就是串行队列，直接作为 sampleHandlerQueue，回调里不再
        // 二次 dispatch（原来先投 .global(userInteractive) 再 frameQueue.async）。
        try newStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: frameQueue)
        let generation = stateLock.withLock {
            _captureGeneration &+= 1
            let g = _captureGeneration
            stream = newStream
            _isStopped = false
            return g
        }
        do {
            try await newStream.startCapture()
        } catch {
            stateLock.withLock {
                guard stream === newStream else { return }
                stream = nil
                _isStopped = true
            }
            wlog("pin-preview: startCapture failed generation=\(generation) \(error.localizedDescription)")
            throw error
        }
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
        let fps = stateLock.withLock { _streamFPS }
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(max(1, fps)))
    }

    private func scheduleFrameRateReconfig() {
        let work = DispatchWorkItem { [weak self] in
            self?.applyFrameRateReconfig()
        }
        stateLock.lock()
        frameRateReconfigWorkItem?.cancel()
        frameRateReconfigWorkItem = work
        stateLock.unlock()
        // 150ms debounce：鼠标反复进出交互时只重配一次。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private func applyFrameRateReconfig() {
        stateLock.lock()
        frameRateReconfigWorkItem = nil
        let interactive = _isInteractive
        _streamFPS = interactive ? 30 : 15
        let fps = _streamFPS
        stateLock.unlock()
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(max(1, fps)))
        stream?.updateConfiguration(configuration) { error in
            if let error {
                wlog("pin-preview: frame rate reconfig failed \(error.localizedDescription)")
            } else {
                wlog("pin-preview: frame rate \(fps)fps interactive=\(interactive)")
            }
        }
    }

    func stream(
        _ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard outputType == .screen, sampleBuffer.isValid else { return }
        // sampleHandlerQueue 就是 frameQueue（串行），回调直接在这里处理，
        // 不再多一层 frameQueue.async 调度。
        stateLock.lock()
        let stopped = _isStopped
        // 帧必须来自当前流：restart 后旧流晚到的回调会被 stream 身份挡掉。
        let isCurrentStream = self.stream === stream
        let fps = _streamFPS
        stateLock.unlock()
        guard !stopped, isCurrentStream else { return }
        mirrorFrameIndex &+= 1
        // 主画面按源流帧率全量投递（15/30fps 已由流本身自适应）；镜像层取
        // 约 8~10fps 的子集：15fps 源隔帧投（≈8fps），30fps 源每 3 帧投（10fps）。
        let mirrorDivisor: UInt32 = fps >= 30 ? 3 : 2
        let deliverMain = true
        let deliverMirror = mirrorLayer != nil && mirrorFrameIndex % mirrorDivisor == 1
        guard deliverMain || deliverMirror else { return }
        deliver(sampleBuffer, main: deliverMain, mirror: deliverMirror)
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
        stateLock.lock()
        let isCurrent = self.stream === stream
        if isCurrent {
            self.stream = nil
            _isStopped = true
            _captureGeneration &+= 1
        }
        stateLock.unlock()
        // 永久 stop（stop()/restart() 主动停）不走这条路径；只有系统异常终止
        // 才会到这里。
        if isCurrent {
            onUnexpectedStop?(error)
        }
    }
}
