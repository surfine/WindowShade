import Cocoa

/// Production content/material hosts with value-only records. No controller or panel startup.
@main enum WindowBrowserStatePreview {
    enum Failure: Error { case check(String) }
    struct Sample { let name: String; let mode: WindowBrowserPanelMode; let style: WindowBrowserDisplayStyle
        let width: CGFloat; let height: CGFloat; let count: Int; let busy: Bool; let permission: Bool }
    static func rect(_ r: NSRect) -> [String: Double] {
        ["x": r.minX, "y": r.minY, "width": r.width, "height": r.height]
    }
    @MainActor static func main() async {
        _ = NSApplication.shared; NSApp.setActivationPolicy(.prohibited)
        let out = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
            let pid = pid_t(Int32.max)
            guard NSRunningApplication(processIdentifier: pid) == nil else { throw Failure.check("synthetic PID occupied") }
            let samples: [Sample] = [
                .init(name: "empty", mode: .keyboard, style: .list, width: 456, height: 300, count: 0, busy: false, permission: true),
                .init(name: "no-match", mode: .keyboard, style: .list, width: 456, height: 300, count: 0, busy: false, permission: true),
                .init(name: "one", mode: .dock, style: .grid, width: 320, height: 278, count: 1, busy: false, permission: true),
                .init(name: "many", mode: .dock, style: .grid, width: 660, height: 480, count: 6, busy: false, permission: true),
                .init(name: "long-list", mode: .keyboard, style: .list, width: 540, height: 420, count: 7, busy: false, permission: true),
                .init(name: "busy-list", mode: .keyboard, style: .list, width: 540, height: 420, count: 7, busy: true, permission: true),
                .init(name: "narrow-list", mode: .keyboard, style: .list, width: 320, height: 360, count: 3, busy: false, permission: true),
                .init(name: "busy-unknown", mode: .keyboard, style: .grid, width: 660, height: 430, count: 3, busy: true, permission: true),
                .init(name: "no-permission", mode: .keyboard, style: .list, width: 540, height: 420, count: 3, busy: false, permission: false)
            ]
            var frames: [[String: Any]] = []
            for parent in [NSAppearance.Name.aqua, .darkAqua] {
                for material in [WindowBrowserAppearanceStyle.paper, .system] {
                    for sample in samples {
                        let records: [WindowRecord] = (0..<sample.count).map { index in
                            WindowRecord(key: .init(application: .init(pid: pid, generation: 1), originalWindowID: UInt32(index + 1), windowGeneration: 1),
                                bundleIdentifier: "qa.synthetic.window-browser", appName: "样件应用", title: index == 0 ? "季度报告 — " + String(repeating: "项目讨论与修改记录", count: 12) : "工作窗口 \(index + 1)",
                                logicalFrame: CGRect(x: 0, y: 0, width: 800, height: 600), placementSource: .liveDiscovery,
                                systemVisibility: index == 2 ? .unknown : .onScreen,
                                shadeState: index == 1 ? .folded : (index == 2 ? .unknown : .normal),
                                pinState: index == 1 ? .running : .none, capabilities: .discoveredWindow,
                                confidence: .confirmed, metadataRevision: 1, isMinimized: false, isOnScreen: index != 2,
                                isFoldedOffscreen: index == 1, isManaged: index == 1)
                        }
                        let bounds = NSRect(x: 0, y: 0, width: sample.width, height: sample.height)
                        let view = WindowBrowserContentView(frame: bounds)
                        view.appearance = NSAppearance(named: parent)
                        #if WINDOWSHADE_SDK_HAS_GLASS
                        let supportsGlass = true
                        #else
                        let supportsGlass = false
                        #endif
                        view.materialOverride = (material, .init(supportsGlass: supportsGlass, reduceTransparency: false, increaseContrast: false, reduceMotion: true))
                        var actionCalls = 0
                        view.onActivate = { _ in actionCalls += 1 }; view.onPrimary = { _ in actionCalls += 1 }
                        view.onPin = { _ in actionCalls += 1 }; view.onClose = { _ in actionCalls += 1 }
                        view.onRequestAction = { _, _ in actionCalls += 1 }
                        if sample.name == "no-match" { view.setSearchTextForDiagnostics("不存在的样件") }
                        let selection = records.first?.key
                        let window = NSWindow(contentRect: bounds, styleMask: [.borderless], backing: .buffered, defer: false)
                        window.isReleasedWhenClosed = false; window.alphaValue = 0; window.contentView = view
                        window.setFrame(NSRect(x: -8000, y: -8000, width: sample.width, height: sample.height), display: false)
                        // The real panel attaches its content before the controller updates it.
                        // Otherwise selected rows see nil window and use the key-window color.
                        view.update(mode: sample.mode, records: records, selection: selection, style: sample.style,
                            busyKeys: sample.busy ? Set(records.map(\.key)) : [], screenRecordingAvailable: sample.permission,
                            hasAccessibility: sample.permission, status: sample.permission ? "" : "需要屏幕录制权限才能预览")
                        view.layoutSubtreeIfNeeded()
                        try await Task.sleep(nanoseconds: 150_000_000)
                        view.layoutSubtreeIfNeeded()
                        var labels: [String] = []; var buttons: [[String: Any]] = []; var rows: [[String: Any]] = []
                        func visit(_ v: NSView) {
                            if !v.isHiddenOrHasHiddenAncestor {
                                if let row = v as? WindowBrowserListRowView,
                                   let title = row.subviews.compactMap({ $0 as? NSTextField }).first(where: { $0.stringValue == row.titleForTesting }),
                                   let bar = row.subviews.compactMap({ $0 as? WindowBrowserActionBar }).first {
                                    rows.append(["title": rect(title.frame), "actions": rect(bar.frame), "bounds": rect(row.bounds),
                                        "requiredWidth": bar.requiredWidth, "titleTooltip": title.toolTip ?? "", "barHidden": bar.isHidden,
                                        "status": row.subviews.compactMap({ $0 as? NSTextField }).filter { $0 !== title }.map { ["text": $0.stringValue, "frame": rect($0.frame)] }])
                                }
                                if let field = v as? NSTextField, !field.stringValue.isEmpty { labels.append(field.stringValue) }
                                if let button = v as? NSButton {
                                    buttons.append(["title": button.title, "enabled": button.isEnabled,
                                        "frame": rect(button.convert(button.bounds, to: view))])
                                }
                            }
                            v.subviews.forEach(visit)
                        }
                        visit(view)
                        guard !window.isVisible, !NSApp.isActive, window.alphaValue == 0,
                            NSScreen.screens.allSatisfy({ !window.frame.intersects($0.frame) }), actionCalls == 0 else { throw Failure.check("host/actions") }
                        let name = "\(parent == .aqua ? "light" : "dark")-\(material.rawValue)-\(sample.name)"
                        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw Failure.check("bitmap") }
                        view.cacheDisplay(in: view.bounds, to: bitmap)
                        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw Failure.check("png") }
                        try png.write(to: out.appendingPathComponent(name + ".png"))
                        let layout = view.layoutFrameSummary
                        var frame: [String: Any] = ["name": name, "sample": sample.name, "width": sample.width, "height": sample.height,
                            "records": records.count, "material": view.materialKind.rawValue, "requestedMaterial": material.rawValue,
                            "corner": view.panelCornerRadiusForDiagnostics, "insideGlass": view.contentIsInsideGlassForDiagnostics,
                            "labels": labels, "buttons": buttons, "rows": rows, "actions": actionCalls, "searchVisible": view.searchFieldVisible,
                            "search": rect(layout.search), "list": rect(layout.list), "header": rect(layout.header), "footer": rect(layout.footer),
                            "visibleKeys": view.visibleWindowKeys.map { $0.originalWindowID }, "cachedThumbnails": view.cachedThumbnailCount,
                            "visible": window.isVisible, "active": NSApp.isActive, "alpha": window.alphaValue]
                        if let card = view.debugFirstCardFrames() { frame["firstCard"] = ["bounds": rect(card.bounds), "title": rect(card.titleFrame), "actions": rect(card.actionFrame)] }
                        frames.append(frame)
                        window.contentView = nil; window.close()
                    }
                }
            }
            try JSONSerialization.data(withJSONObject: ["frames": frames, "syntheticPID": pid, "actions": 0, "controllerStarted": false], options: [.prettyPrinted, .sortedKeys]).write(to: out.appendingPathComponent("frames.json"))
            print("PASS 36 production browser content frames; synthetic records; no actions/controller")
        } catch { fputs("FAIL \(error)\n", stderr); exit(1) }
    }
}
