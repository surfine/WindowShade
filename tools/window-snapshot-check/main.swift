// 窗口快照检查：开着、最小化、退到屏外三种状态下窗口画面还拿不拿得到。
//
// 自己开一扇小窗口当靶子（纯色 + 变化的帧号），不激活自己、不切桌面、不碰别的 App 的窗口。
// 隐藏要走激活语义，用不了：第三段改成 deminiaturize 再 orderOut，等价于“不在屏上”。

import Cocoa

/// 变化的帧号，让窗口画面不是一张不变的图。
@MainActor
private final class FrameNumber {
    var value = 0
}

@MainActor
private let frameNumber = FrameNumber()

@MainActor
private final class SnapshotCheck {
    let window: NSWindow
    private var ticker: Timer?
    private(set) var failures = 0

    init() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                          styleMask: [.titled],
                          backing: .buffered,
                          defer: false)
        window.isReleasedWhenClosed = false
        window.title = "WindowSnapshot 检查"
        window.backgroundColor = .systemGreen
        window.contentView = ContentView(text: "0")
        window.center()
        window.orderFrontRegardless()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.bump() }
        }
    }

    private func bump() {
        frameNumber.value += 1
        (window.contentView as? ContentView)?.text = "\(frameNumber.value)"
        window.displayIfNeeded()
    }

    private var id: CGWindowID { CGWindowID(window.windowNumber) }

    private func sample(_ state: String) {
        for quality in [WindowSnapshot.Quality.thumbnail, .full] {
            let began = Date()
            let image = WindowSnapshot.image(id, quality: quality)
            let ms = Int((Date().timeIntervalSince(began) * 1000).rounded())
            if let image {
                let name = quality == .full ? "full" : "thumbnail"
                print("PASS snapshot \(state) \(name): \(image.width)x\(image.height) in \(ms)ms")
            } else {
                failures += 1
                let name = quality == .full ? "full" : "thumbnail"
                print("FAIL snapshot \(state) \(name): nil in \(ms)ms")
            }
        }
    }

    func run() {
        wait(1.0)   // 等窗口真的拿到窗口号并被合成
        sample("onscreen")

        window.miniaturize(nil)
        wait(1.2)
        sample("minimized")

        // 缩图：最长边缩到 320，比例不变。
        if let full = WindowSnapshot.image(id, quality: .full), let small = WindowSnapshot.downscaled(full, maxPixel: 320) {
            let ok = max(small.width, small.height) == 320
                && abs(Double(small.width) / Double(small.height) - Double(full.width) / Double(full.height)) < 0.02
            if !ok { failures += 1 }
            print("\(ok ? "PASS" : "FAIL") snapshot downscale: \(full.width)x\(full.height) → \(small.width)x\(small.height)")
        } else {
            failures += 1
            print("FAIL snapshot downscale: no picture to shrink")
        }

        window.deminiaturize(nil)
        window.orderOut(nil)
        wait(0.5)
        sample("offscreen")

        ticker?.invalidate()
        ticker = nil
        window.close()
        // 不在这里 terminate：那样进程以 0 退出，失败数就丢了（由 main 按失败数退出）。
    }

    /// 让主循环转起来，窗口状态才会真的变过去。
    private func wait(_ seconds: TimeInterval) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: min(deadline, Date().addingTimeInterval(0.02)))
        }
    }
}

/// 纯色背景 + 一行帧号。
@MainActor
private final class ContentView: NSView {
    var text: String
    private let label: NSTextField

    init(text: String) {
        self.text = text
        label = NSTextField(labelWithString: text)
        super.init(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        wantsLayer = true
        layer?.backgroundColor = NSColor.systemGreen.cgColor
        label.textColor = .black
        label.font = .systemFont(ofSize: 64, weight: .bold)
        addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("unused") }

    override func layout() {
        super.layout()
        label.sizeToFit()
        label.frame.origin = NSPoint(x: (bounds.width - label.frame.width) / 2,
                                     y: (bounds.height - label.frame.height) / 2)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.systemGreen.setFill()
        dirtyRect.fill()
        label.stringValue = text
        label.displayIfNeeded()
    }
}

@main
@MainActor
private struct Main {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)   // 绝不激活自己
        guard CGPreflightScreenCaptureAccess() else {
            print("SKIP no screen-recording permission")
            exit(0)
        }
        guard WindowSnapshot.isAvailable else {
            print("SKIP WindowSnapshot unavailable")
            exit(0)
        }
        var failures = 0
        MainActor.assumeIsolated {
            let check = SnapshotCheck()
            check.run()
            failures = check.failures
        }
        exit(failures == 0 ? 0 : 1)
    }
}
