import Cocoa
import ImageIO

/// Actual thumbnail consumer; only owned diagnostic PNGs, no real window discovery or capture.
@main enum WindowBrowserImagePreview {
    enum Failure: Error { case check(String) }
    @MainActor static func box(_ r: NSRect) -> [String: CGFloat] { ["x":r.minX,"y":r.minY,"width":r.width,"height":r.height] }
    @MainActor static func main() async throws {
        _ = NSApplication.shared; NSApp.setActivationPolicy(.prohibited)
        let out = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let fixtureRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/design-window-images/image-fixtures", isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        guard let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: fixtureRoot.appendingPathComponent("manifest.json"))) as? [String: Any],
              let entries = manifest["images"] as? [[String: Any]], entries.count == 5 else { throw Failure.check("own image manifest") }
        let pid = pid_t(Int32.max)
        guard NSRunningApplication(processIdentifier: pid) == nil else { throw Failure.check("synthetic pid") }
        var frames = [[String: Any]]()
        for entry in entries {
            guard let name = entry["name"] as? String, let file = entry["file"] as? String,
                  file == URL(fileURLWithPath: file).lastPathComponent,
                  let w = entry["width"] as? Int, let h = entry["height"] as? Int,
                  let source = CGImageSourceCreateWithURL(fixtureRoot.appendingPathComponent(file) as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil), image.width == w, image.height == h else { throw Failure.check("owned ImageIO decode") }
            for parent in [NSAppearance.Name.aqua, .darkAqua] {
                for material in [WindowBrowserAppearanceStyle.paper, .system] {
                    for hovered in [false, true] {
                    for busy in [false, true] {
                        let title = "设计评审 — " + String(repeating: "当前窗口的长标题与图像比例", count: 8)
                        let record = WindowRecord(key: .init(application: .init(pid: pid, generation: 17), originalWindowID: 17, windowGeneration: 1),
                            bundleIdentifier: "qa.synthetic.images", appName: "样件应用", title: title, logicalFrame: nil,
                            placementSource: .liveDiscovery, systemVisibility: .onScreen, shadeState: .normal, pinState: .none,
                            capabilities: .discoveredWindow, confidence: .confirmed, metadataRevision: 1, isMinimized: false, isOnScreen: true, isFoldedOffscreen: false, isManaged: false)
                        let bounds = NSRect(x: 0, y: 0, width: 320, height: 280)
                        let view = WindowBrowserContentView(frame: bounds)
                        view.appearance = NSAppearance(named: parent)
                        #if WINDOWSHADE_SDK_HAS_GLASS
                        let supportsGlass = true
                        #else
                        let supportsGlass = false
                        #endif
                        view.materialOverride = (material, .init(supportsGlass: supportsGlass, reduceTransparency: false, increaseContrast: false, reduceMotion: true))
                        view.params = WindowBrowserGeometry.derivedParams(base: .standard, titles: [title], hasStatus: false, anyCardStatus: false, mode: .dock, windowCount: 1, dockEdge: .bottom)
                        let window = NSWindow(contentRect: bounds, styleMask: [.borderless], backing: .buffered, defer: false)
                        window.isReleasedWhenClosed = false; window.alphaValue = 0; window.contentView = view
                        window.setFrame(NSRect(x: -8000, y: -8000, width: 320, height: 280), display: false)
                        view.update(mode: .dock, records: [record], selection: nil, style: .grid, busyKeys: busy ? [record.key] : [], status: "")
                        view.applyThumbnail(image, for: record.key, note: "自造比例诊断图")
                        view.layoutSubtreeIfNeeded(); try await Task.sleep(nanoseconds: 300_000_000); view.layoutSubtreeIfNeeded()
                        var card: WindowBrowserCardView?
                        func visit(_ v: NSView) {
                            if let found = v as? WindowBrowserCardView, found.windowKey == record.key { card = found }
                            v.subviews.forEach(visit)
                        }
                        visit(view)
                        guard let card, let geometry = view.debugFirstCardFrames(), view.hasThumbnailImage(for: record.key),
                              let bar = card.subviews.first(where: { $0 is WindowBrowserActionBar }) as? WindowBrowserActionBar,
                              let titleField = card.subviews.compactMap({ $0 as? NSTextField }).first(where: { $0.stringValue == title }),
                              !NSApp.isActive, !window.isVisible, NSScreen.screens.allSatisfy({ !window.frame.intersects($0.frame) }) else { throw Failure.check("actual image card / safe host") }
                        var imageViews = [NSImageView]()
                        func images(_ v: NSView) { if let imageView = v as? NSImageView { imageViews.append(imageView) }; v.subviews.forEach(images) }
                        images(card.thumbnailHost)
                        guard let thumbnail = imageViews.first(where: { $0.image != nil }) else { throw Failure.check("actual native image") }
                        var measurements = geometry
                        var localHoverCallbacks = 0
                        view.onHoverChanged = { key, state in
                            if key == record.key && state { localHoverCallbacks += 1 }
                        }
                        if hovered {
                            guard let event = NSEvent.enterExitEvent(with: .mouseEntered, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil) else { throw Failure.check("local hover event") }
                            card.mouseEntered(with: event) // Receiver only: never posted to NSApp or the system.
                            view.layoutSubtreeIfNeeded(); try await Task.sleep(nanoseconds: 150_000_000)
                            measurements = view.debugFirstCardFrames() ?? geometry
                        }
                        let label = "\(parent == .aqua ? "light" : "dark")-\(material.rawValue)-\(name)-\(hovered ? "hovered" : "plain")" + (busy ? "-busy" : "")
                        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: bounds) else { throw Failure.check("bitmap") }
                        view.cacheDisplay(in: bounds, to: bitmap)
                        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw Failure.check("PNG") }
                        try png.write(to: out.appendingPathComponent(label + ".png"))
                        func currentButtons() -> [[String: Any]] { bar.subviews.compactMap { child in
                            guard let button = child as? NSButton else { return nil }
                            return ["id":button.identifier?.rawValue ?? "", "hidden":button.isHidden, "enabled":button.isEnabled, "frame":box(button.frame), "more":button.toolTip?.hasPrefix("更多操作") ?? false]
                        }
                        }
                        let buttonStates = currentButtons()
                        frames.append(["busy":bar.isBusy, "expectedBusy":busy, "buttons":buttonStates, "name": label, "sample": name, "file": file, "imageWidth": w, "imageHeight": h, "selected": card.isSelected,
                            "expectedHovered": hovered, "hovered": card.isHovering, "localHoverCallbacks": localHoverCallbacks, "globalInputEvents": 0, "material": material.rawValue, "parent": parent.rawValue, "actions": 0,
                            "visible": window.isVisible, "active": NSApp.isActive, "alpha": window.alphaValue,
                            "card": box(measurements.bounds), "picture": box(measurements.thumbnailHostFrame), "title": box(measurements.titleFrame), "bar": box(measurements.actionFrame),
                            "barHidden": bar.isHiddenOrHasHiddenAncestor, "barRequiredWidth": bar.requiredWidth,
                            "titleText": titleField.stringValue, "tooltip": titleField.toolTip ?? "", "wraps": titleField.cell?.wraps ?? false,
                            "thumbnailBounds": box(thumbnail.bounds), "thumbnailFrame": box(thumbnail.frame), "imageScaling": thumbnail.imageScaling.rawValue,
                            "imagePresent": thumbnail.image != nil, "materialHost": view.materialKind.rawValue, "width": bounds.width, "height": bounds.height])
                        if name == "portrait9x16", parent == .aqua, material == .paper, hovered, !busy {
                            let identity = view.cardInstanceIdentifier(for: record.key)
                            for target in ["landscape16x9", "portrait9x16"] {
                                guard let item = entries.first(where: { $0["name"] as? String == target }), let path = item["file"] as? String,
                                      let src = CGImageSourceCreateWithURL(fixtureRoot.appendingPathComponent(path) as CFURL, nil),
                                      let replacement = CGImageSourceCreateImageAtIndex(src, 0, nil) else { throw Failure.check("own reuse image") }
                                view.applyThumbnail(replacement, for: record.key, note: "自造比例诊断图")
                                view.layoutSubtreeIfNeeded(); try await Task.sleep(nanoseconds: 150_000_000)
                                guard identity == view.cardInstanceIdentifier(for: record.key), let m = view.debugFirstCardFrames(),
                                      view.cachedThumbnailImage(for: record.key)?.width == replacement.width else { throw Failure.check("same card image change") }
                                let reuseName = "light-paper-reuse-" + target
                                guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { throw Failure.check("reuse bitmap") }
                                view.cacheDisplay(in: bounds, to: rep)
                                guard let bytes = rep.representation(using: .png, properties: [:]) else { throw Failure.check("reuse PNG") }
                                try bytes.write(to: out.appendingPathComponent(reuseName + ".png"))
                                var f = frames.last! // Fields below are re-read from the same actual card after image change.
                                f["name"] = reuseName; f["sample"] = target; f["file"] = path; f["reuseStage"] = target; f["sameCard"] = true
                                f["imageWidth"] = replacement.width; f["imageHeight"] = replacement.height
                                f["card"] = box(m.bounds); f["picture"] = box(m.thumbnailHostFrame); f["title"] = box(m.titleFrame); f["bar"] = box(m.actionFrame)
                                f["barRequiredWidth"] = bar.requiredWidth; f["buttons"] = currentButtons()
                                f["thumbnailBounds"] = box(thumbnail.bounds); f["thumbnailFrame"] = box(thumbnail.frame)
                                frames.append(f)
                            }
                        }
                        window.close()
                    }
                    }
                }
            }
        }
        try JSONSerialization.data(withJSONObject: ["frames":frames,"realSources":0,"syntheticImages":5], options:[.prettyPrinted,.sortedKeys]).write(to: out.appendingPathComponent("frames.json"))
        print("PASS \(frames.count) actual ImageIO/ContentView thumbnail frames; synthetic pixels only, actions0")
    }
}
