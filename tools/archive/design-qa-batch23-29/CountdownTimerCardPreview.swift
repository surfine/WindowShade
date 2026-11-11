import Cocoa

/// 只渲染生产计时器卡片，不安装运行时、不响铃、不动用户窗口。
@main enum CountdownTimerCardPreview {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        CountdownTimerSettings.store = UserDefaults(suiteName: "WindowShade.DesignPreview.Countdown")!
        var frames: [[String: Any]] = []
        for appearanceName in [NSAppearance.Name.aqua, .darkAqua] {
            for state in ["picker", "running", "paused", "done", "alert"] {
                let mode: CountdownTimerCard.Mode = state == "picker" ? .picker : state == "alert" ? .alert : .running
                let card = CountdownTimerCard(mode: mode, minutes: 10)
                var model = CountdownTimer()
                _ = model.handle(.start(minutes: 10), at: .zero)
                let now = WS2.Instant(seconds: state == "done" || state == "alert" ? 642 : 60)!
                if state == "paused" { _ = model.handle(.pause, at: now) }
                if state == "done" || state == "alert" { _ = model.handle(.tick, at: now) }
                card.appearance = NSAppearance(named: appearanceName)
                card.render(model, at: now)
                card.frame = NSRect(origin: .zero, size: card.interactionSize)
                let container = NSView(frame: card.frame)
                container.wantsLayer = true
                container.layer?.backgroundColor = NSColor.black.cgColor
                container.addSubview(card)
                let window = NSWindow(contentRect: container.frame, styleMask: .borderless, backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.contentView = container
                window.appearance = card.appearance
                container.layoutSubtreeIfNeeded()
                let name = "\(appearanceName == .aqua ? "light" : "dark")-\(state)"
                guard let rep = container.bitmapImageRepForCachingDisplay(in: container.bounds) else {
                    throw NSError(domain: "CountdownPreview", code: 1)
                }
                container.cacheDisplay(in: container.bounds, to: rep)
                guard let png = rep.representation(using: .png, properties: [:]) else {
                    throw NSError(domain: "CountdownPreview", code: 2)
                }
                try png.write(to: output.appendingPathComponent(name + ".png"))
                frames.append(["image": name + ".png", "width": card.bounds.width, "height": card.bounds.height,
                               "minimumHeight": card.interactionMinimumHeight, "cornerRadius": card.interactionCornerRadius,
                               "spoken": card.accessibilityLabel() ?? "", "visibleWindow": window.isVisible])
                window.close()
            }
        }
        try JSONSerialization.data(withJSONObject: frames, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("frames.json"))
        print("Rendered 10 production timer card frames; no window shown and no timer host started.")
    }
}
