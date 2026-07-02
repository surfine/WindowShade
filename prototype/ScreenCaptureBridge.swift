import Cocoa
import AVFoundation
import ScreenCaptureKit

enum ShareableContentLoader {
    static func current() async throws -> SCShareableContent {
        if #available(macOS 14.0, *) {
            return try await SCShareableContent.current
        }

        return try await withCheckedThrowingContinuation { continuation in
            SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { content, error in
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

    private var stream: SCStream?
    private var filter: SCContentFilter?
    private var configuration = SCStreamConfiguration()

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

    func restart(window: SCWindow, display: SCDisplay?, width: CGFloat, height: CGFloat) async throws {
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
        guard let activeStream = stream else { return }
        stream = nil
        activeStream.stopCapture { error in
            if let error {
                wlog("pin-preview: capture stop failed \(error.localizedDescription)")
            }
        }
        DispatchQueue.main.async { [videoLayer] in
            videoLayer.flushAndRemoveImage()
        }
    }

    private func startStream(filter: SCContentFilter) async throws {
        let newStream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try newStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .global(qos: .userInteractive))
        stream = newStream
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
        let screen = display.flatMap { screenForDisplayID($0.displayID) }
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

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of outputType: SCStreamOutputType) {
        guard outputType == .screen, sampleBuffer.isValid else { return }
        DispatchQueue.main.async { [weak self] in
            self?.videoLayer.enqueue(sampleBuffer)
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        wlog("pin-preview: capture stopped with error \(error.localizedDescription)")
        if self.stream === stream {
            self.stream = nil
        }
    }
}
