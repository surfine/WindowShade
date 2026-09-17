import Cocoa
import AVFoundation

/// Offscreen AppKit component regression: no global event injection, capture,
/// permissions, or interaction with the user's windows.
@main
enum PaperSurfaceTests {
    static func main() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 360),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 360))
        root.clipsToBounds = true
        window.contentView = root
        // 先把窗口真正上屏再断言 visibleRect：紧跟多个 GUI 进程之后，WindowServer
        // 尚未提交窗口时 visibleRect 可能仍是空的，会让本回归假失败。
        window.orderFrontRegardless()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        let video = AVSampleBufferDisplayLayer()
        let preview = PinnedPreviewContentView(videoLayer: video, title: "Test preview")
        preview.frame = NSRect(x: 24, y: 24, width: 552, height: 220)
        root.addSubview(preview)
        root.layoutSubtreeIfNeeded()
        preview.updateTrackingAreas()

        precondition(preview.visibleRect == preview.bounds, "hover region escaped preview bounds")
        guard let tracking = preview.trackingAreas.first,
              let owner = tracking.owner as? PinnedPreviewContentView,
              let title = preview.subviews.first(where: { $0 is NSVisualEffectView })
                as? NSVisualEffectView else {
            fatalError("missing production tracking owner or title")
        }
        // 离屏回归里这个窗口不在合成器里（实测 occlusionState 不含 .visible），
        // 材质视图不会自己变成 layer-backed，而没有 layer 时第一次 alpha 动画
        // 会被丢掉：实测 alpha 一直停在 0。真实面板是合成出来的，材质显示时就
        // 有 layer。这里显式开启 layer，混合模式仍保留生产用的 behindWindow，
        // 覆盖的仍是 mouseEntered → setTitleVisible 这条真实代码路径。
        title.wantsLayer = true
        precondition(owner === preview && tracking.options.contains(.mouseEnteredAndExited))
        precondition(title.alphaValue == 0, "idle title obscures preview")

        var entered = 0
        var exited = 0
        var clicked = 0
        preview.onMouseEntered = { entered += 1 }
        preview.onMouseExited = { exited += 1 }
        preview.onMouseDown = { _ in clicked += 1 }
        func event(_ type: NSEvent.EventType) -> NSEvent {
            NSEvent.enterExitEvent(with: type, location: NSPoint(x: 80, y: 230),
                modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)!
        }
        func finishTransition() {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.2))
        }

        // Deliver the same tracking-owner callbacks AppKit dispatches, without
        // posting an event to the system or synthesizing a physical pointer.
        owner.mouseEntered(with: event(.mouseEntered))
        finishTransition()
        precondition(entered == 1 && title.alphaValue > 0.99, "enter did not reveal title")

        let point = NSPoint(x: preview.frame.midX, y: preview.frame.maxY - 12)
        guard let hit = root.hitTest(point) else { fatalError("missing title-area hit target") }
        precondition(hit === preview, "title material intercepted preview click")
        let click = NSEvent.mouseEvent(with: .leftMouseDown, location: point,
            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
            context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        hit.mouseDown(with: click)
        precondition(clicked == 1, "preview click callback was lost")

        owner.mouseExited(with: event(.mouseExited))
        finishTransition()
        precondition(exited == 1 && title.alphaValue < 0.01, "exit left title visible")
        preview.frame.size = NSSize(width: 300, height: 160)
        root.layoutSubtreeIfNeeded()
        preview.updateTrackingAreas()
        precondition(preview.visibleRect == preview.bounds, "resize expanded hover region")
        precondition(video.frame == preview.bounds, "video did not follow preview resize")
        window.close()
        print("PASS: bounded hover region, idle title hidden, enter/reveal, title click passthrough, exit/hide, resize")
    }
}
