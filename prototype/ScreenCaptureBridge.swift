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

    // 菜单/面板缩略图的镜像层：同一批采样帧额外喂给它，实现"复用已在跑的流"的实时
    // 缩略图，不新建 capture、不轮询。弱引用，视图销毁后自动断开。
    //
    // 它在主线程挂接/解除、在帧队列读取，属于跨线程共享状态：读写都走 stateLock，
    // 与帧投递使用同一把锁，避免数据竞争。
    private weak var _mirrorLayer: AVSampleBufferDisplayLayer?
    var mirrorLayer: AVSampleBufferDisplayLayer? {
        get {
            stateLock.lock()
            defer { stateLock.unlock() }
            return _mirrorLayer
        }
        set {
            stateLock.lock()
            _mirrorLayer = newValue
            stateLock.unlock()
        }
    }

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
    /// 置顶预览要拍干净底片；窗口浏览的小预览在意启动速度，只抹平。
    var takesCleanPlate = false
    private var cleanPlate: CleanPlate?
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
    /// 实际投递到显示层的采样帧计数：只用于诊断、性能对照与集成探针。
    private var _deliveredFrameCount: UInt64 = 0
    /// 实际投递到镜像层的采样帧计数（同一批帧的子集）。
    private var _mirroredFrameCount: UInt64 = 0
    /// 带像素的帧：画面没变化时系统也会送来不带图像的状态帧，“已经是实时画面”只看这个。
    private var _pixelFrameCount: UInt64 = 0
    // 普通窗口的临时实时预览配置：初始 8fps、最大 640×400、无音频、无鼠标、
    // queueDepth 2。它不改变原有置顶预览的默认 15/30fps 与分辨率。
    private let isPreviewStream: Bool
    private let previewMaxPixelSize = CGSize(width: 640, height: 400)
    // 流被系统异常终止（源窗口变化、系统过渡等）时回调；由 PinnedPreviewController
    // 决定刷新 SCWindow、有限次数重启或结束会话。
    var onUnexpectedStop: ((Error) -> Void)?

    init(preview: Bool = false) {
        isPreviewStream = preview
        if preview {
            _streamFPS = 8
        }
        super.init()
        videoLayer.videoGravity = .resize
        videoLayer.backgroundColor = NSColor.clear.cgColor
    }

    var deliveredFrameCount: UInt64 {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _deliveredFrameCount
    }

    /// 源流是否真的在运行（已启动且未被 stop/restart/异常终止清空）。
    var isRunning: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return stream != nil && !_isStopped
    }

    var pixelFrameCount: UInt64 {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _pixelFrameCount
    }

    var mirroredFrameCount: UInt64 {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _mirroredFrameCount
    }

    /// 当前配置的目标帧率（普通预览 8；置顶预览 idle 15 / interactive 30）。
    var configuredFrameRate: Int {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _streamFPS
    }

    func start(window: SCWindow, display: SCDisplay?) async throws {
        if stream != nil { return }
        let newFilter = SCContentFilter(desktopIndependentWindow: window)
        filter = newFilter
        configure(window: window, display: display)
        if takesCleanPlate { await takeCleanPlate(filter: newFilter, window: window) }
        try await startStream(filter: newFilter)
    }

    /// 置顶预览开流前拍一张干净底片（此时这扇窗上还没有流，也就没有录屏胶囊），
    /// 之后每帧把胶囊那一块换回底片上的红绿灯。用与流相同的配置，比例一致。
    /// 已经有别的流在捕获这扇窗时底片本身带胶囊，CleanPlate 会拒收，退回抹平。
    private func takeCleanPlate(filter: SCContentFilter, window: SCWindow) async {
        guard let image = try? await SCScreenshotManager.captureImage(
            contentFilter: filter, configuration: configuration) else { return }
        let scale = CGFloat(configuration.width) / max(1, window.frame.width)
        let plate = CleanPlate(image: image, scale: scale)
        stateLock.withLock { cleanPlate = plate }
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
        if let oldStream {
            Task { [oldStream] in
                do {
                    try await oldStream.stopCapture()
                } catch {
                    let nsError = error as NSError
                    if nsError.code != -3808 {
                        wlog("pin-preview: capture stop failed \(error.localizedDescription)")
                    }
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
        stop(completion: nil)
    }

    /// 停止并回报系统调用真实结束；用于新入口在折叠前等待自己创建的临时流停妥。
    /// completion 恰好在主线程调用一次；参数是系统的停止错误（-3808 表示流已自行终止）。
    func stop(completion: ((Error?) -> Void)?) {
        stateLock.lock()
        _isStopped = true
        let generation = _captureGeneration
        let activeStream = stream
        stream = nil
        stateLock.unlock()
        let finish: (Error?) -> Void = { error in
            if let error {
                let nsError = error as NSError
                if nsError.code != -3808 {
                    wlog("pin-preview: capture stop failed \(error.localizedDescription)")
                }
            }
            if let completion { DispatchQueue.main.async { completion(error) } }
        }
        if let activeStream {
            Task { [activeStream] in
                do {
                    try await activeStream.stopCapture()
                    finish(nil)
                } catch {
                    finish(error)
                }
            }
        } else {
            finish(nil)
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
        var pixelWidth = max(1, Int(ceil(width * scale)))
        var pixelHeight = max(1, Int(ceil(height * scale)))
        if isPreviewStream {
            let outputScale = min(previewMaxPixelSize.width / CGFloat(pixelWidth),
                                  previewMaxPixelSize.height / CGFloat(pixelHeight),
                                  1)
            pixelWidth = max(1, Int(ceil(CGFloat(pixelWidth) * outputScale)))
            pixelHeight = max(1, Int(ceil(CGFloat(pixelHeight) * outputScale)))
        }
        configuration.width = pixelWidth
        configuration.height = pixelHeight
    }

    private func configureBase(display: SCDisplay?) {
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.colorSpaceName = CGColorSpace.sRGB
        configuration.showsCursor = false
        configuration.queueDepth = isPreviewStream ? 2 : 3
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
        // 这扇窗正被我们的流捕获，系统在它的红绿灯处画了录屏胶囊：交给画面之前修掉。
        CaptureIndicatorRemoval.clean(sampleBuffer, plate: stateLock.withLock { cleanPlate })
        mirrorFrameIndex &+= 1
        // 主画面按源流帧率全量投递（15/30fps 已由流本身自适应）；镜像层取
        // 约 8~10fps 的子集：15fps 源隔帧投（≈8fps），30fps 源每 3 帧投（10fps）。
        let mirrorDivisor: UInt32 = fps >= 30 ? 3 : 2
        let deliverMain = true
        let deliverMirror = mirrorLayer != nil && mirrorFrameIndex % mirrorDivisor == 1
        guard deliverMain || deliverMirror else { return }
        let carriesPixels = CMSampleBufferGetImageBuffer(sampleBuffer) != nil
        stateLock.lock()
        _deliveredFrameCount &+= 1
        if carriesPixels { _pixelFrameCount &+= 1 }
        if deliverMirror { _mirroredFrameCount &+= 1 }
        stateLock.unlock()
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
