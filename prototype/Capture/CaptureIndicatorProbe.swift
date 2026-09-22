// 录屏胶囊探针：只捕获 WindowShade 自己开的一扇普通窗口，存下流开始前后几个时刻的
// 单张截图与实时帧，用来看胶囊在不同捕获方式下的真实样子与出现时序。不碰用户窗口。
//
// 用法：WindowShade.app/Contents/MacOS/WindowShade --capture-indicator-probe [输出目录]

import Cocoa
import ScreenCaptureKit
import VideoToolbox

final class CaptureIndicatorProbe {
    private var window: NSWindow?
    private let source = EffectFrameSource()
    private let output: URL
    private var lastShot: CGImage?
    private var lastBefore: CGImage?
    private var rawFrame: CVPixelBuffer?

    /// 帧缓冲来自系统的复用池，要改它先拷一份。
    private static func copy(_ source: CVPixelBuffer) -> CVPixelBuffer? {
        var out: CVPixelBuffer?
        let w = CVPixelBufferGetWidth(source), h = CVPixelBufferGetHeight(source)
        guard CVPixelBufferCreate(nil, w, h, kCVPixelFormatType_32BGRA, nil, &out) == kCVReturnSuccess,
              let out else { return nil }
        CVPixelBufferLockBaseAddress(source, .readOnly); CVPixelBufferLockBaseAddress(out, [])
        defer { CVPixelBufferUnlockBaseAddress(source, .readOnly); CVPixelBufferUnlockBaseAddress(out, []) }
        let srcRow = CVPixelBufferGetBytesPerRow(source), dstRow = CVPixelBufferGetBytesPerRow(out)
        for y in 0..<h {
            memcpy(CVPixelBufferGetBaseAddress(out)! + y * dstRow,
                   CVPixelBufferGetBaseAddress(source)! + y * srcRow, min(srcRow, dstRow))
        }
        return out
    }

    init(output: URL) { self.output = output }

    func run() {
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 300),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Capture indicator probe"
        window.isReleasedWhenClosed = false
        window.center()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        self.window = window
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            await self.capture(window: window)
            exit(0)
        }
    }

    @MainActor private func capture(window: NSWindow) async {
        guard let id = cgWindowID(for: window),
              let content = try? await SCShareableContent.current,
              let scWindow = content.windows.first(where: { $0.windowID == id }) else {
            print("indicator-probe: window missing"); return
        }
        let filter = SCContentFilter(desktopIndependentWindow: scWindow)
        let scale = window.backingScaleFactor
        await shot(filter: filter, scale: scale, name: "shot-before-stream")
        lastBefore = lastShot
        do {
            try await source.start(filter: filter, size: CGSize(width: 480 * scale, height: 330 * scale))
        } catch { print("indicator-probe: stream failed \(error)"); return }
        for (delay, label) in [(0.2, "0.2s"), (1.0, "1.0s")] {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            if let frame = source.frame()?.stillImage() { save(frame, "stream-frame-\(label)") }
            if rawFrame == nil, let buffer = source.frame()?.buffer { rawFrame = Self.copy(buffer) }
            await shot(filter: filter, scale: scale, name: "shot-during-stream-\(label)")
        }
        source.stop()
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        await shot(filter: filter, scale: scale, name: "shot-1s-after-stop")

        // 生产路径：收起动画的流打开修补后，帧里不应再有胶囊。
        let cleaning = EffectFrameSource()
        cleaning.removesCaptureIndicator = true
        do {
            try await cleaning.start(filter: filter, size: CGSize(width: 480 * scale, height: 330 * scale))
        } catch { print("indicator-probe: cleaning stream failed \(error)"); return }
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        if let frame = cleaning.frame() {
            if let image = frame.stillImage() { save(image, "stream-frame-cleaned") }
            // 底片：流开始前那张（没有胶囊），贴回同一帧的原始画面上。
            if let before = lastBefore, let plate = CleanPlate(image: before, scale: scale),
               let raw = rawFrame {
                let restored = CaptureIndicatorRemoval.clean(raw, content: CGRect(x: 0, y: 0,
                    width: CVPixelBufferGetWidth(raw), height: CVPixelBufferGetHeight(raw)),
                    scale: scale, plate: plate)
                var image: CGImage?
                VTCreateCGImageFromCVPixelBuffer(raw, options: nil, imageOut: &image)
                if let image { save(image, "plate-restored(changed=\(restored))") }
            }
        }
        cleaning.stop()
        print("indicator-probe: done output=\(output.path)")
    }

    private func shot(filter: SCContentFilter, scale: CGFloat, name: String) async {
        let config = SCStreamConfiguration()
        config.width = Int(480 * scale); config.height = Int(330 * scale)
        config.showsCursor = false
        if let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) {
            lastShot = image
            save(image, name)
        }
    }

    private func save(_ image: CGImage, _ name: String) {
        let found = CaptureIndicatorRemoval.detect(in: image, scale: window?.backingScaleFactor ?? 2)
        print("indicator-probe: \(name) \(image.width)x\(image.height) capsule="
              + (found.map { "\($0.bounds) purple=\($0.purplePixels)" } ?? "none"))
        let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        try? data?.write(to: output.appendingPathComponent("\(name).png"))
    }
}
