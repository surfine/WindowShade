import Cocoa

@main enum WindowBrowserGridTitlePreview {
    enum Failure: Error { case check(String) }
    @MainActor static func main() async {
        _ = NSApplication.shared; NSApp.setActivationPolicy(.prohibited)
        let out = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
            let pid = pid_t(Int32.max)
            guard NSRunningApplication(processIdentifier: pid) == nil else { throw Failure.check("synthetic pid") }
            let titles = [("short", "季度报告"), ("cjk", "季度报告 — " + String(repeating: "项目讨论与修改记录", count: 12)),
                          ("ascii", String(repeating: "QuarterlyReport_Review_", count: 12)),
                          ("emoji", "周末 — " + String(repeating: "👩🏽‍💻🇹🇼👨‍👩‍👧‍👦", count: 12))]
            var frames: [[String: Any]] = []
            for parent in [NSAppearance.Name.aqua, .darkAqua] {
                for style in [WindowBrowserAppearanceStyle.paper, .system] {
                    for derived in [false, true] {
                    for (sample, title) in titles {
                        let record = WindowRecord(key: .init(application: .init(pid: pid, generation: 1), originalWindowID: 1, windowGeneration: 1),
                            bundleIdentifier: "qa.synthetic.grid-title", appName: "样件应用", title: title, logicalFrame: nil,
                            placementSource: .liveDiscovery, systemVisibility: .onScreen, shadeState: .normal, pinState: .none,
                            capabilities: .discoveredWindow, confidence: .confirmed, metadataRevision: 1,
                            isMinimized: false, isOnScreen: true, isFoldedOffscreen: false, isManaged: false)
                        let bounds = NSRect(x: 0, y: 0, width: 320, height: 280)
                        let view = WindowBrowserContentView(frame: bounds)
                        view.appearance = NSAppearance(named: parent)
                        #if WINDOWSHADE_SDK_HAS_GLASS
                        let supportsGlass = true
                        #else
                        let supportsGlass = false
                        #endif
                        view.materialOverride = (style, .init(supportsGlass: supportsGlass, reduceTransparency: false, increaseContrast: false, reduceMotion: true))
                        if derived {
                            view.params = WindowBrowserGeometry.derivedParams(base: .standard, titles: [title],
                                hasStatus: false, anyCardStatus: false, mode: .dock, windowCount: 1, dockEdge: .bottom)
                        }
                        let window = NSWindow(contentRect: bounds, styleMask: [.borderless], backing: .buffered, defer: false)
                        window.isReleasedWhenClosed = false; window.alphaValue = 0; window.contentView = view
                        window.setFrame(NSRect(x: -8000, y: -8000, width: 320, height: 280), display: false)
                        view.update(mode: .dock, records: [record], selection: record.key, style: .grid, busyKeys: [], status: "")
                        view.layoutSubtreeIfNeeded(); try await Task.sleep(nanoseconds: 150_000_000); view.layoutSubtreeIfNeeded()
                        var titleField: NSTextField?
                        var cardView: WindowBrowserCardView?
                        func visit(_ v: NSView) {
                            if let card = v as? WindowBrowserCardView, card.titleForTesting == title {
                                cardView = card
                                titleField = card.subviews.compactMap { $0 as? NSTextField }.first { $0.stringValue == title }
                            }
                            v.subviews.forEach(visit)
                        }
                        visit(view)
                        guard let label = titleField, let card = cardView, let font = label.font,
                            !window.isVisible, !NSApp.isActive, window.alphaValue == 0,
                            NSScreen.screens.allSatisfy({ !window.frame.intersects($0.frame) }) else { throw Failure.check("card/host") }
                        let name = "\(parent == .aqua ? "light" : "dark")-\(style.rawValue)-\(sample)\(derived ? "-derived" : "")"
                        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: bounds) else { throw Failure.check("bitmap") }
                        view.cacheDisplay(in: bounds, to: bitmap)
                        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw Failure.check("png") }
                        try png.write(to: out.appendingPathComponent(name + ".png"))
                        frames.append(["name": name, "sample": sample, "derivedParams": derived, "title": label.stringValue, "tooltip": label.toolTip ?? "",
                            "wraps": label.cell?.wraps ?? false, "maxLines": label.maximumNumberOfLines,
                            "lastLineTruncates": label.cell?.truncatesLastVisibleLine ?? false, "breakMode": label.lineBreakMode.rawValue,
                            "font": font.pointSize, "lineHeight": WindowBrowserTypography.lineHeight(font),
                            "titleFrame": ["x": label.frame.minX, "y": label.frame.minY, "width": label.frame.width, "height": label.frame.height],
                            "cardBounds": ["width": card.bounds.width, "height": card.bounds.height],
                            "material": view.materialKind.rawValue, "insideGlass": view.contentIsInsideGlassForDiagnostics,
                            "visible": window.isVisible, "active": NSApp.isActive, "alpha": window.alphaValue])
                        window.contentView = nil; window.close()
                    }
                    }
                }
            }
            try JSONSerialization.data(withJSONObject: ["frames": frames, "controllerStarted": false, "actions": 0], options: [.prettyPrinted, .sortedKeys]).write(to: out.appendingPathComponent("frames.json"))
            print("PASS 32 actual grid title frames, 4 inputs/default+derived params, no controller or actions")
        } catch { fputs("FAIL \(error)\n", stderr); exit(1) }
    }
}
