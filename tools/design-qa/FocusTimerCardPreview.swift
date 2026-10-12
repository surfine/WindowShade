import Cocoa

/// 离屏画面样件：真实 FocusTimer / Host / Card，不开启刘海、不动窗口、不执行计时效果。
@main enum FocusTimerCardPreview {
    struct Clock: WS2Clock { func now() -> WS2.Instant { .zero } }

    @MainActor static func main() throws {
        _ = NSApplication.shared
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let calendar = FocusTimer.CalendarSample(today: "2026-10-11", deadlineDay: "2026-10-11")
        var metadata: [[String: Any]] = []
        for appearanceName in [NSAppearance.Name.aqua, .darkAqua] {
            for state in ["idle", "focus", "paused", "rest"] {
                var model = FocusTimer(bootID: UUID(), tuckChatEnabled: false)
                if state != "idle" { _ = model.handle(.start, at: .zero, calendar: calendar) }
                if state == "paused" { _ = model.handle(.pause, at: WS2.Instant(seconds: 378)!, calendar: calendar) }
                if state == "rest" { _ = model.handle(.tick, at: WS2.Instant(seconds: 1500)!, calendar: calendar) }
                let now = WS2.Instant(seconds: state == "rest" ? 1560 : 378)!
                let host = FocusTimerHost(model: model, clock: Clock(), calendarSample: { _, _ in calendar }, effects: { _ in })
                let card = FocusTimerCard(host: host)
                card.appearance = NSAppearance(named: appearanceName)
                card.render(model, at: now)
                card.frame = NSRect(origin: .zero, size: card.interactionSize)
                let container = NSView(frame: card.frame)
                container.wantsLayer = true
                container.layer?.backgroundColor = NSColor.black.cgColor
                container.addSubview(card)
                // 不 orderFront；窗口仅提供 AppKit 布局/绘制上下文，不出现在用户桌面。
                let window = NSWindow(contentRect: container.frame, styleMask: .borderless, backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.appearance = card.appearance
                window.contentView = container
                container.layoutSubtreeIfNeeded()
                let name = "\(appearanceName == .aqua ? "light" : "dark")-\(state)"
                guard let rep = container.bitmapImageRepForCachingDisplay(in: container.bounds) else {
                    throw NSError(domain: "FocusPreview", code: 1)
                }
                container.cacheDisplay(in: container.bounds, to: rep)
                guard let png = rep.representation(using: .png, properties: [:]) else {
                    throw NSError(domain: "FocusPreview", code: 2)
                }
                try png.write(to: output.appendingPathComponent(name + ".png"))
                metadata.append(["image": name + ".png", "width": card.bounds.width, "height": card.bounds.height,
                                 "spoken": card.accessibilityLabel() ?? "", "visibleWindow": window.isVisible])
                host.stop()
                window.close()
            }
        }
        let data = try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: output.appendingPathComponent("frames.json"))
        print("Rendered 8 native card frames; no window was shown. This is not a live notch acceptance test.")
    }
}
