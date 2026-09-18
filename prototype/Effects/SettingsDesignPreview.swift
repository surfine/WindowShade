import Cocoa
import ScreenCaptureKit
import AVFoundation

/// Records real AppKit events in the isolated component fixture. This makes
/// short enter/exit sequences observable even if an automation click restores
/// the pointer before the next screenshot.
private final class DesignSampleWindow: NSWindow {
    var recordPointerEvents = false
    override func sendEvent(_ event: NSEvent) {
        super.sendEvent(event)
        guard recordPointerEvents,
              [.mouseEntered, .mouseExited, .leftMouseDown, .mouseMoved].contains(event.type) else { return }
        let trackingOwner: String
        if event.type == .mouseEntered || event.type == .mouseExited {
            trackingOwner = event.trackingArea?.owner.map { String(describing: type(of: $0)) } ?? "none"
        } else { trackingOwner = "none" }
        recordDesignPointer("event=\(event.type.rawValue) owner=\(trackingOwner) location=\(event.locationInWindow)")
        if event.type == .leftMouseDown, let contentView {
            func inspect(_ view: NSView) {
                if view is NativeProxyTitleContentView || view is PinnedPreviewContentView {
                    recordDesignPointer("\(type(of: view)) visible=\(view.visibleRect) tracking=\(view.trackingAreas.map { $0.options.rawValue })")
                }
                view.subviews.forEach(inspect)
            }
            inspect(contentView)
        }
    }
}

private func recordDesignPointer(_ message: String) {
    let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(".build/design-review")
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("pointer-events.txt")
    let line = "\(Date().timeIntervalSince1970) \(message)\n"
    guard let data = line.data(using: .utf8) else { return }
    if !FileManager.default.fileExists(atPath: url.path) {
        try? data.write(to: url)
    } else if let file = try? FileHandle(forWritingTo: url) {
        defer { try? file.close() }
        _ = try? file.seekToEnd()
        try? file.write(contentsOf: data)
    }
}

/// Local design review entry point. It uses production views but never starts
/// window capture, sensors, recovery or global event handlers.
final class SettingsDesignPreview: NSObject {
    private let owner: AppDelegate
    private var samples: [NSWindow] = []
    private var paperViews: (NativeProxyTitleContentView, PinnedPreviewContentView)?
    init(owner: AppDelegate) { self.owner = owner }

    func show() {
        owner.showDuoSettings()
        owner.duoController.settingsWindow?.resetReviewLayout()
        let menu = NSMenu()
        let root = NSMenuItem(title: "设计预览", action: nil, keyEquivalent: "")
        let actions = NSMenu(title: "设计预览")
        for (title, selector) in [
            ("浅色", #selector(light)), ("深色", #selector(dark)),
            ("默认尺寸 900 × 680", #selector(normal)),
            ("最小尺寸 820 × 580", #selector(compact)),
            ("宽窗口 1200 × 800", #selector(wide)),
            ("验证纸面阴影生命周期", #selector(checkShadow)),
            ("保存当前窗口截图", #selector(exportImage)),
            ("对照原貌截图边界", #selector(compareCropGeometry)),
            ("显示引导页", #selector(onboarding)),
            ("权限状态样例", #selector(permissionSample)),
            ("纸面组件样例", #selector(paperSample)),
            ("组件状态：移入", #selector(sampleEntered)),
            ("组件状态：移出", #selector(sampleExited)),
            ("退出设计预览", #selector(quit)),
        ] {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
            item.target = self
            actions.addItem(item)
        }
        root.submenu = actions
        menu.addItem(root)
        NSApp.mainMenu = menu
    }

    private func resize(width: CGFloat, height: CGFloat) {
        guard let window = owner.duoController.settingsWindow?.window else { return }
        var frame = window.frame
        frame.size = NSSize(width: width, height: height)
        window.setFrame(frame, display: true)
        window.center()
        owner.duoController.settingsWindow?.resetReviewLayout()
    }
    @objc private func light() { NSApp.appearance = NSAppearance(named: .aqua) }
    @objc private func dark() { NSApp.appearance = NSAppearance(named: .darkAqua) }
    @objc private func normal() { resize(width: 900, height: 680) }
    @objc private func compact() { resize(width: 820, height: 580) }
    @objc private func wide() { resize(width: 1200, height: 800) }
    @objc private func onboarding() { owner.showWelcomeGuide() }
    @objc private func quit() { NSApp.terminate(nil) }

    private func sampleWindow(title: String, size: NSSize) -> NSWindow {
        let window = DesignSampleWindow(contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = title
        window.isReleasedWhenClosed = false
        window.acceptsMouseMovedEvents = true
        let background = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        background.material = .underPageBackground
        background.blendingMode = .withinWindow
        window.contentView = background
        samples.append(window)
        window.center()
        return window
    }

    @objc private func permissionSample() {
        let window = sampleWindow(title: "权限状态样例", size: NSSize(width: 500, height: 170))
        guard let root = window.contentView else { return }
        let card = owner.makePermissionDesignSample()
        root.addSubview(card)
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            card.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            card.centerYAnchor.constraint(equalTo: root.centerYAnchor),
        ])
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func paperSample() {
        let window = sampleWindow(title: "纸面组件样例", size: NSSize(width: 600, height: 360))
        guard let root = window.contentView else { return }
        let strip = NSVisualEffectView(frame: NSRect(x: 24, y: 285, width: 552, height: 36))
        strip.material = .popover
        strip.blendingMode = .behindWindow
        SystemCornerRadius.apply(to: strip, radius: SystemCornerRadius.window,
                                 masksToBounds: true)
        let title = NativeProxyTitleContentView(frame: strip.bounds, appName: "WindowShade",
            windowTitle: "设计预览.swift", appIcon: NSApp.applicationIconImage)
        title.autoresizingMask = [.width, .height]
        strip.addSubview(title)
        root.addSubview(strip)
        let video = AVSampleBufferDisplayLayer()
        video.backgroundColor = NSColor.controlBackgroundColor.cgColor
        let panel = PinnedPreviewContentView(videoLayer: video, title: "WindowShade — 置顶预览")
        panel.frame = NSRect(x: 24, y: 24, width: 552, height: 220)
        panel.onMouseEntered = { recordDesignPointer("pinned entered: title requested visible") }
        panel.onMouseExited = { recordDesignPointer("pinned exited: title requested hidden") }
        panel.onMouseDown = { _ in recordDesignPointer("pinned click passed through title material") }
        root.addSubview(panel)
        paperViews = (title, panel)
        (window as? DesignSampleWindow)?.recordPointerEvents = true
        window.makeKeyAndOrderFront(nil)
    }

    // Component-state controls for snapshot review. These call the production
    // tracking handlers directly; they do not move or inject a system pointer.
    @objc private func sampleEntered() { showPaperState(entered: true) }
    @objc private func sampleExited() { showPaperState(entered: false) }
    private func showPaperState(entered: Bool) {
        guard let (title, panel) = paperViews, let window = panel.window else { return }
        let type: NSEvent.EventType = entered ? .mouseEntered : .mouseExited
        guard let event = NSEvent.enterExitEvent(with: type, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
            context: nil, eventNumber: 0, trackingNumber: 0, userData: nil) else { return }
        if entered {
            title.mouseEntered(with: event)
            panel.mouseEntered(with: event)
        } else {
            title.mouseExited(with: event)
            panel.mouseExited(with: event)
        }
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func checkShadow() {
        let fixture = NSWindow(contentRect: NSRect(x: 250, y: 250, width: 420, height: 80),
            styleMask: .borderless, backing: .buffered, defer: false)
        fixture.isReleasedWhenClosed = false
        fixture.backgroundColor = .controlBackgroundColor
        let original = fixture.frame
        PaperSurfaceStyle.installShadow(on: fixture)
        var failures: [String] = []
        func check(_ condition: Bool, _ label: String) { if !condition { failures.append(label) } }
        check(fixture.frame == original, "install changed source geometry")
        if let shadow = fixture.childWindows?.first {
            check(shadow.ignoresMouseEvents, "shadow intercepts pointer")
            fixture.orderFrontRegardless()
            check(shadow.isVisible, "shadow did not follow show")
            fixture.setFrameOrigin(NSPoint(x: 300, y: 280))
            check(shadow.frame == fixture.frame.insetBy(dx: -24, dy: -24), "shadow did not follow move")
            var resized = fixture.frame
            resized.size.width = 540
            fixture.setFrame(resized, display: true)
            check(shadow.frame == fixture.frame.insetBy(dx: -24, dy: -24), "shadow did not follow resize")
            fixture.alphaValue = 0.02
            check(abs(shadow.alphaValue - fixture.alphaValue) < 0.001, "shadow did not follow interaction transparency")
            fixture.level = .floating
            check(shadow.level == fixture.level, "shadow did not follow window level")
            fixture.alphaValue = 1
            fixture.orderOut(nil)
            check(!shadow.isVisible, "shadow remained after hide")
            fixture.orderFrontRegardless()
            check(shadow.isVisible, "shadow did not return after show")
            PaperSurfaceStyle.removeShadow(from: fixture)
            check(fixture.childWindows?.isEmpty != false && !shadow.isVisible, "shadow leaked after reuse cleanup")
        } else { failures.append("missing shadow") }
        fixture.close()
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/design-review")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let report = failures.isEmpty ? "PASS: geometry, pointer passthrough, show, move, resize, hide, reshow, interaction transparency, level, reuse cleanup\n" : failures.joined(separator: "\n")
        try? report.write(to: directory.appendingPathComponent("shadow-check.txt"), atomically: true, encoding: .utf8)
    }

    /// Compare the same owned window with and without ScreenCaptureKit framing.
    /// This diagnostic never targets another application's window.
    @objc private func compareCropGeometry() {
        guard let window = owner.duoController.settingsWindow?.window else { return }
        let id = CGWindowID(window.windowNumber)
        let size = window.frame.size
        let scale = window.backingScaleFactor
        let chrome = window.frame.maxY - window.convertToScreen(window.contentLayoutRect).maxY
        Task { @MainActor in
            do {
                let content = try await SCShareableContent.current
                guard let target = content.windows.first(where: { $0.windowID == id }) else { return }
                let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                    .appendingPathComponent(".build/design-review/crop")
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                func save(_ image: CGImage, _ name: String) throws {
                    let bitmap = NSBitmapImageRep(cgImage: image)
                    guard let data = bitmap.representation(using: .png, properties: [:]) else { return }
                    try data.write(to: directory.appendingPathComponent(name + ".png"))
                }
                for ignore in [false, true] {
                    let config = SCStreamConfiguration()
                    config.width = Int(size.width * scale)
                    config.height = Int(size.height * scale)
                    config.showsCursor = false
                    config.ignoreShadowsSingleWindow = ignore
                    let image: CGImage
                    if ignore {
                        guard let captured = await self.owner.captureWindow(id: id,
                            axPos: axPosition(fromCocoaFrame: window.frame), size: size) else {
                            throw EffectError.unavailable("production capture failed")
                        }
                        image = captured
                        let alpha = NSBitmapImageRep(cgImage: image).colorAt(x: image.width / 2, y: 0)?.alphaComponent ?? 0
                        guard alpha > 0.95 else { throw EffectError.unavailable("production capture includes framing above content") }
                    } else {
                        image = try await SCScreenshotManager.captureImage(
                            contentFilter: SCContentFilter(desktopIndependentWindow: target), configuration: config)
                    }
                    let name = ignore ? "unframed" : "framed"
                    try save(image, name)
                    if let raw = image.cropping(to: CGRect(x: 0, y: 0, width: image.width,
                                                           height: Int(ceil(chrome * scale)))) {
                        try save(raw, name + "-crop")
                        if let mirrored = mirrorRoundCorners(raw) {
                            try save(mirrored, name + "-mirror")
                            if ignore {
                                let pos = axPosition(fromCocoaFrame: window.frame)
                                let overlay = self.owner.makeScreenshotOverlay(image: mirrored,
                                    axPos: pos, width: size.width, height: chrome, buttons: [], id: id,
                                    windowManagement: .none, trafficLights: .standard)
                                self.samples.append(overlay)
                                overlay.orderFrontRegardless()
                                let overlays = try await SCShareableContent.current
                                if let rendered = overlays.windows.first(where: { $0.windowID == CGWindowID(overlay.windowNumber) }) {
                                    let output = SCStreamConfiguration()
                                    output.width = Int(size.width * scale)
                                    output.height = Int(chrome * scale)
                                    output.ignoreShadowsSingleWindow = true
                                    output.showsCursor = false
                                    let result = try await SCScreenshotManager.captureImage(
                                        contentFilter: SCContentFilter(desktopIndependentWindow: rendered), configuration: output)
                                    try save(result, "actual-overlay")
                                }
                                overlay.orderOut(nil)
                            }
                        }
                    }
                }
                var timings: [Bool: [Double]] = [false: [], true: []]
                for trial in 0..<6 {
                    for ignore in trial.isMultiple(of: 2) ? [false, true] : [true, false] {
                        let config = SCStreamConfiguration()
                        config.width = Int(size.width * scale)
                        config.height = Int(size.height * scale)
                        config.showsCursor = false
                        config.ignoreShadowsSingleWindow = ignore
                        let started = CACurrentMediaTime()
                        _ = try await SCScreenshotManager.captureImage(
                            contentFilter: SCContentFilter(desktopIndependentWindow: target), configuration: config)
                        timings[ignore, default: []].append((CACurrentMediaTime() - started) * 1000)
                    }
                }
                let report = "window=\(size) scale=\(scale) chrome=\(chrome) SCWindow=\(target.frame)\n" +
                    "capture ms framed=\(timings[false] ?? []) unframed=\(timings[true] ?? [])\n"
                try report.write(to: directory.appendingPathComponent("geometry.txt"), atomically: true, encoding: .utf8)
                print("DESIGN crop comparison: " + report)
            } catch { print("DESIGN crop comparison failed: \(error)") }
        }
    }

    @objc private func exportImage() {
        guard let window = NSApp.keyWindow else { return }
        let id = CGWindowID(window.windowNumber)
        let size = window.frame.size
        let scale = window.backingScaleFactor
        let style = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? "dark" : "light"
        Task { @MainActor in
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let ownWindow = content.windows.first(where: { $0.windowID == id }) else { return }
                let config = SCStreamConfiguration()
                config.width = Int(size.width * scale)
                config.height = Int(size.height * scale)
                config.showsCursor = false
                config.ignoreShadowsSingleWindow = true
                let image = try await SCScreenshotManager.captureImage(
                    contentFilter: SCContentFilter(desktopIndependentWindow: ownWindow), configuration: config)
                let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                    .appendingPathComponent(".build/design-review")
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let name = "settings-\(style)-\(Int(size.width))x\(Int(size.height)).png"
                let bitmap = NSBitmapImageRep(cgImage: image)
                try bitmap.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent(name))
            } catch { print("DESIGN screenshot failed: \(error)") }
        }
    }
}
