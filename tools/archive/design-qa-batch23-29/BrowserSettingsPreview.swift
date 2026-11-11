import Cocoa

// Actual page factory, without app startup, settings actions, or persistent writes.
@main enum BrowserSettingsPreview {
    final class Host: NSView { override var isFlipped: Bool { true } }
    final class Background: NSView {
        override func draw(_ rect: NSRect) { NSColor.textBackgroundColor.setFill(); rect.fill() }
    }
    enum Failure: Error { case check(String) }
    @MainActor static func main() async {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let out = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let defaults = UserDefaults.standard
        let original = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        defer { defaults.setVolatileDomain(original, forName: UserDefaults.argumentDomain) }
        do {
            try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
            var frames: [[String: Any]] = []
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                for trigger in [WindowSwitcherKeys.Trigger.off, .command] {
                    var domain = original
                    domain[WindowSwitcherKeys.defaultsKey] = trigger.rawValue
                    defaults.setVolatileDomain(domain, forName: UserDefaults.argumentDomain)
                    guard WindowSwitcherKeys.trigger == trigger else { throw Failure.check("volatile trigger") }
                    let owner = AppDelegate()
                    let page = owner.makeWindowBrowserSettingsPage()
                    let root = Background(frame: NSRect(x: 0, y: 0, width: 696, height: 600))
                    root.appearance = NSAppearance(named: appearance)
                    let scroll = NSScrollView(frame: root.bounds)
                    scroll.drawsBackground = false
                    scroll.automaticallyAdjustsContentInsets = false
                    scroll.borderType = .noBorder
                    scroll.hasVerticalScroller = true
                    scroll.autohidesScrollers = true
                    root.addSubview(scroll)
                    let host = Host()
                    host.translatesAutoresizingMaskIntoConstraints = false
                    scroll.documentView = host
                    host.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true
                    host.heightAnchor.constraint(greaterThanOrEqualTo: scroll.contentView.heightAnchor).isActive = true
                    page.translatesAutoresizingMaskIntoConstraints = false
                    host.addSubview(page)
                    let preferred = page.widthAnchor.constraint(equalToConstant: settingsContentWidth)
                    preferred.priority = .dragThatCannotResizeWindow
                    NSLayoutConstraint.activate([
                        page.centerXAnchor.constraint(equalTo: host.centerXAnchor),
                        page.leadingAnchor.constraint(greaterThanOrEqualTo: host.leadingAnchor, constant: 28),
                        page.trailingAnchor.constraint(lessThanOrEqualTo: host.trailingAnchor, constant: -28),
                        preferred, page.widthAnchor.constraint(lessThanOrEqualToConstant: settingsContentWidth),
                        page.topAnchor.constraint(equalTo: host.topAnchor, constant: 22),
                        page.bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: -22)
                    ])
                    let window = NSWindow(contentRect: root.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
                    window.isReleasedWhenClosed = false
                    window.alphaValue = 0
                    window.contentView = root
                    window.setFrame(NSRect(x: -8000, y: -8000, width: 696, height: 600), display: false)
                    root.layoutSubtreeIfNeeded()
                    try await Task.sleep(nanoseconds: 150_000_000)
                    root.layoutSubtreeIfNeeded()
                    var labels: [String] = []
                    var toolTips: [String] = []
                    var segments: [Int] = []
                    var labelBounds: [[String: Any]] = []
                    func visit(_ view: NSView) {
                        if let tip = view.toolTip { toolTips.append(tip) }
                        if let label = view as? NSTextField, !label.stringValue.isEmpty {
                            labels.append(label.stringValue)
                            let frame = label.convert(label.bounds, to: page)
                            labelBounds.append(["text": label.stringValue, "x": frame.minX, "width": frame.width,
                                                "height": frame.height, "right": frame.maxX])
                        }
                        if let segment = view as? NSSegmentedControl, segment.segmentCount == 3,
                           segment.label(forSegment: 2) == "⌘Tab" { segments.append(segment.selectedSegment) }
                        view.subviews.forEach(visit)
                    }
                    visit(page)
                    guard !window.isVisible, !NSApp.isActive, window.alphaValue == 0,
                          NSScreen.screens.allSatisfy({ !window.frame.intersects($0.frame) }),
                          page.bounds.width > 600, host.bounds.height > 600,
                          segments == [trigger == .off ? 0 : 2] else { throw Failure.check("host/selection") }
                    for position in ["top", "bottom"] {
                        scroll.contentView.scroll(to: NSPoint(x: 0, y: position == "top" ? 0 : max(0, host.bounds.height - scroll.contentView.bounds.height)))
                        scroll.reflectScrolledClipView(scroll.contentView)
                        root.layoutSubtreeIfNeeded()
                        let parent = appearance == .aqua ? "light" : "dark"
                        let name = "\(parent)-\(trigger.rawValue)-\(position)"
                        guard let bitmap = root.bitmapImageRepForCachingDisplay(in: root.bounds) else { throw Failure.check("bitmap") }
                        root.cacheDisplay(in: root.bounds, to: bitmap)
                        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw Failure.check("png") }
                        try data.write(to: out.appendingPathComponent(name + ".png"))
                        frames.append(["name": name, "trigger": trigger.rawValue, "selected": segments[0],
                                       "pageWidth": page.bounds.width, "pageHeight": page.bounds.height,
                                       "hostHeight": host.bounds.height, "scrollY": scroll.contentView.bounds.minY,
                                       "labels": labels, "toolTips": toolTips, "labelBounds": labelBounds, "visible": window.isVisible,
                                       "active": NSApp.isActive, "alpha": window.alphaValue])
                    }
                    window.contentView = nil
                    window.close()
                    withExtendedLifetime(owner) {}
                }
            }
            defaults.setVolatileDomain(original, forName: UserDefaults.argumentDomain)
            let report: [String: Any] = ["frames": frames, "actionsInvoked": 0, "persistentWrites": 0,
                "permissionQueries": "AXIsProcessTrusted/CGPreflightScreenCaptureAccess only; no requests",
                "argumentDomainRestored": defaults.volatileDomain(forName: UserDefaults.argumentDomain) as NSDictionary == original as NSDictionary]
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: out.appendingPathComponent("frames.json"))
            print("PASS 8 production browser settings frames; no actions; volatile domain restored")
        } catch { fputs("FAIL \(error)\n", stderr); exit(1) }
    }
}
