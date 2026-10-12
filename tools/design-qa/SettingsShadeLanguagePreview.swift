import Cocoa

/// 第27批：设置「卷帘」页 + 「高级」页（含语言行）+ 窗口外壳的中英渲染夹具。
/// 用真实生产页面（AppDelegate.makeShadeSettingsPage / DuoSettingsWindow），隐藏窗口离屏渲染；
/// 只直接设 WSL10n.language 与 englishBundle，不写任何持久偏好、不触发权限弹窗。
/// 同进程 zh→en→zh：直接发语言变更通知（见 InterfaceLanguagePreference.didChangeNotification，
/// 这里用原始名以便同一份夹具也能编译到改动前的旧树跑基线）。
@main enum SettingsShadeLanguagePreview {
    enum Failure: Error { case check(String) }

    static let languageDidChange = Notification.Name("WindowShade.InterfaceLanguage.didChange")

    final class Host: NSView { override var isFlipped: Bool { true } }
    final class Background: NSView {
        override func draw(_ rect: NSRect) { NSColor.textBackgroundColor.setFill(); rect.fill() }
    }

    @MainActor static func main() async {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let out = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        probeURL = out.appendingPathComponent("probe.txt")
        try? FileManager.default.removeItem(at: probeURL!)
        let stringsDir = ProcessInfo.processInfo.environment["WS2_LOCALIZATION_DIR"]
        let enBundle = stringsDir.flatMap { Bundle(url: URL(fileURLWithPath: $0).appendingPathComponent("en.lproj")) }
        do {
            try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
            var frames: [[String: Any]] = []

            let appearances: [(String, NSAppearance.Name)] = [("aqua", .aqua), ("darkAqua", .darkAqua)]
            var combos: [(language: String, appearance: NSAppearance.Name, width: CGFloat)] = []
            for (_, appearanceValue) in appearances {
                for language in ["zh", "en"] { combos.append((language, appearanceValue, 696)) }
                combos.append(("zh", appearanceValue, 560))
            }
            for combo in combos {
                let language = combo.language
                let appearance = combo.appearance
                let width = combo.width
                if let enBundle, language == "en" { WSL10n.englishBundle = enBundle } else { WSL10n.englishBundle = nil }
                WSL10n.language = language == "en" ? .en : .zh

                let owner = AppDelegate()
                let page = owner.makeShadeSettingsPage()
                let root = Background(frame: NSRect(x: 0, y: 0, width: width, height: 720))
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
                ])
                let window = NSWindow(contentRect: root.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.alphaValue = 0
                window.contentView = root
                window.setFrame(NSRect(x: -8000, y: -8000, width: width, height: 720), display: false)
                root.layoutSubtreeIfNeeded()
                probeShade(page, tag: "pass1", language: language, appearance: appearance, width: width)
                try await Task.sleep(nanoseconds: 150_000_000)
                probeShade(page, tag: "postSleep", language: language, appearance: appearance, width: width)
                root.layoutSubtreeIfNeeded()
                probeShade(page, tag: "pass2", language: language, appearance: appearance, width: width)
                for pass in 3...6 {
                    root.layoutSubtreeIfNeeded()
                    probeShade(page, tag: "pass\(pass)", language: language, appearance: appearance, width: width)
                }
                guard !window.isVisible, !NSApp.isActive, window.alphaValue == 0,
                      NSScreen.screens.allSatisfy({ !$0.frame.intersects(window.frame) }) else {
                    throw Failure.check("fixture window escaped")
                }
                let name = "\(language)-\(appearanceName(appearance))-\(Int(width))-shade"
                frames.append(frame(named: name, language: language, surface: "shade",
                                    dumped: dump(page, relativeTo: page), width: width))
                try writePNG(root, to: out.appendingPathComponent("\(name).png"))
                window.contentView = nil
                window.close()
            }

            // 「高级」页 + 窗口外壳：真 DuoSettingsWindow，选到高级，同一个窗口做 zh→en→zh 重建。
            if let enBundle {
                WSL10n.englishBundle = enBundle
            }
            WSL10n.language = .zh
            let controller = DuoController()
            controller.isDesignPreview = true
            let settings = DuoSettingsWindow(controller: controller)
            settings.select(section: .advanced)
            try? await Task.sleep(nanoseconds: 300_000_000)
            var advancedFrames: [[String: Any]] = []
            if let content = settings.window?.contentView {
                let dump0 = dump(content, relativeTo: content)
                let title = settings.window?.title ?? ""
                let subtitle = settings.window?.subtitle ?? ""
                advancedFrames.append(frame(named: "zh-aqua-900-advanced", language: "zh", surface: "advanced",
                                            dumped: dump0, width: 900, windowTitle: title, windowSubtitle: subtitle))
                try writePNG(content, to: out.appendingPathComponent("zh-aqua-900-advanced.png"))
                // 同进程切 en：直接改进程语言 + 发通知，走真实观察者重建（不写偏好）。
                WSL10n.language = .en
                NotificationCenter.default.post(name: languageDidChange, object: nil)
                try? await Task.sleep(nanoseconds: 400_000_000)
                if let contentEn = settings.window?.contentView {
                    advancedFrames.append(frame(named: "rebuild-en-advanced", language: "en", surface: "advanced",
                                                dumped: dump(contentEn, relativeTo: contentEn), width: 900,
                                                windowTitle: settings.window?.title ?? "",
                                                windowSubtitle: settings.window?.subtitle ?? ""))
                    try writePNG(contentEn, to: out.appendingPathComponent("rebuild-en-advanced.png"))
                }
                // 切回 zh：重建后应与原来的 zh 完全一致。
                WSL10n.language = .zh
                NotificationCenter.default.post(name: languageDidChange, object: nil)
                try? await Task.sleep(nanoseconds: 400_000_000)
                if let contentZh = settings.window?.contentView {
                    advancedFrames.append(frame(named: "rebuild-zh-advanced", language: "zh", surface: "advanced",
                                                dumped: dump(contentZh, relativeTo: contentZh), width: 900,
                                                windowTitle: settings.window?.title ?? "",
                                                windowSubtitle: settings.window?.subtitle ?? ""))
                    try writePNG(contentZh, to: out.appendingPathComponent("rebuild-zh-advanced.png"))
                }
            }
            frames.append(contentsOf: advancedFrames)

            let report: [String: Any] = [
                "frames": frames,
                "preferencesWritten": false,
                "persistentDefaultsTouched": false,
                "permissionPrompts": 0,
                "permissionReads": systemState(),
                "fixture": "SettingsShadeLanguagePreview",
            ]
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                .write(to: out.appendingPathComponent("frames.json"))
            print("PASS settings-shade-language preview: \(frames.count) frames (zh/en × light/dark × widths + rebuild)")
        } catch {
            try? String(describing: error).write(to: out.appendingPathComponent("failure.txt"), atomically: true, encoding: .utf8)
            print("FAIL settings-shade-language preview: \(error)")
            exit(1)
        }
    }

    static func appearanceName(_ name: NSAppearance.Name) -> String {
        name == .darkAqua ? "dark" : "light"
    }

    /// 诊断用（交付前移除）：把布局收敛情况逐趟写入 out/probe.txt，进程被中途杀掉也留档。
    nonisolated(unsafe) static var probeURL: URL?

    static func appendProbe(_ line: String) {
        guard let url = probeURL else { return }
        let data = Data((line + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            handle.write(data)
        } else {
            try? data.write(to: url)
        }
    }

    @MainActor static func probeShade(_ page: NSView, tag: String, language: String,
                                      appearance: NSAppearance.Name, width: CGFloat) {
        func findGroup(_ v: NSView) -> NSStackView? {
            if let group = v as? NSStackView, group.arrangedSubviews.count == 2,
               group.arrangedSubviews.first is NSSlider { return group }
            for sub in v.subviews { if let hit = findGroup(sub) { return hit } }
            return nil
        }
        var segs: [String] = []
        func findSegs(_ v: NSView) {
            if let seg = v as? NSSegmentedControl {
                segs.append(String(format: "%.1f", seg.convert(seg.bounds, to: page).minX))
            }
            v.subviews.forEach(findSegs)
        }
        findSegs(page)
        var parts = ["tag=\(tag)", "lang=\(language)", "app=\(appearanceName(appearance))", "w=\(Int(width))"]
        if let group = findGroup(page), let slider = group.arrangedSubviews.first as? NSSlider,
           let readout = group.arrangedSubviews.last as? NSTextField {
            let gf = group.convert(group.bounds, to: page)
            let sf = slider.convert(slider.bounds, to: page)
            let rf = readout.convert(readout.bounds, to: page)
            parts.append(String(format: "group.x=%.1f group.w=%.1f slider.x=%.1f readout.x=%.1f",
                                gf.minX, gf.width, sf.minX, rf.minX))
            if let row = group.superview {
                let rof = row.convert(row.bounds, to: page)
                parts.append(String(format: "row.x=%.1f row.w=%.1f", rof.minX, rof.width))
            }
        } else {
            parts.append("sliderGroup=missing")
        }
        parts.append("segs=[\(segs.joined(separator: ","))]")
        appendProbe(parts.joined(separator: " "))
    }

    /// 只记录系统状态的读值（都不弹窗）：辅助功能、屏幕录制预检、日历读权限。
    @MainActor static func systemState() -> [String: Any] {
        [
            "accessibilityTrusted": AXIsProcessTrusted(),
            "screenRecordingPreflight": CGPreflightScreenCaptureAccess(),
            "calendarAccess": CalendarSource.access() == .granted,
        ]
    }

    @MainActor static func frame(named name: String, language: String, surface: String,
                                 dumped: [String: Any], width: CGFloat,
                                 windowTitle: String? = nil, windowSubtitle: String? = nil) -> [String: Any] {
        var out: [String: Any] = ["name": name, "language": language, "surface": surface,
                                  "width": width, "preferencesWritten": false]
        for (key, value) in dumped { out[key] = value }
        if let windowTitle { out["windowTitle"] = windowTitle }
        if let windowSubtitle { out["windowSubtitle"] = windowSubtitle }
        return out
    }

    /// 采集一棵视图树里的可见文字、控件与提示（坐标换成 root 的坐标系）。
    @MainActor static func dump(_ view: NSView, relativeTo root: NSView) -> [String: Any] {
        var labels: [[String: Any]] = []
        var buttons: [[String: Any]] = []
        var toggles: [[String: Any]] = []
        var popups: [[String: Any]] = []
        var segments: [[String: Any]] = []
        var tooltips: [String] = []
        var axLabels: [String] = []
        func box(_ v: NSView) -> [String: Any] {
            let f = v.convert(v.bounds, to: root)
            return ["x": Double(f.minX.rounded(toPlaces: 2)), "y": Double(f.minY.rounded(toPlaces: 2)),
                    "width": Double(f.width.rounded(toPlaces: 2)), "height": Double(f.height.rounded(toPlaces: 2))]
        }
        func visit(_ v: NSView) {
            if let tip = v.toolTip, !tip.isEmpty { tooltips.append(tip) }
            if let ax = v.accessibilityLabel(), !ax.isEmpty { axLabels.append(ax) }
            if let field = v as? NSTextField, !field.stringValue.isEmpty {
                var entry = box(v)
                entry["text"] = field.stringValue
                labels.append(entry)
            }
            if let button = v as? NSButton, !(v is NSSwitch), !button.title.isEmpty {
                var entry = box(v)
                entry["title"] = button.title
                buttons.append(entry)
            }
            if let toggle = v as? NSSwitch {
                var entry = box(v)
                entry["on"] = toggle.state == .on
                entry["enabled"] = toggle.isEnabled
                toggles.append(entry)
            }
            if let popup = v as? NSPopUpButton {
                var entry = box(v)
                entry["items"] = popup.itemArray.map { $0.title }
                entry["selected"] = popup.selectedItem?.title ?? ""
                popups.append(entry)
            }
            let segment = (v as? NSSegmentedControl).map { $0 } ?? (v.superview as? NSSegmentedControl)
            if let segment, segment.superview === v.superview || v is NSSegmentedControl {
                var entry = box(segment)
                entry["labels"] = (0..<segment.segmentCount).map { segment.label(forSegment: $0) ?? "" }
                entry["selected"] = segment.selectedSegment
                segments.append(entry)
            }
            v.subviews.forEach(visit)
        }
        visit(view)
        return ["labels": labels, "buttons": buttons, "toggles": toggles,
                "popups": popups, "segments": segments, "tooltips": tooltips,
                "axLabels": axLabels]
    }

    @MainActor static func writePNG(_ view: NSView, to url: URL) throws {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw Failure.check("bitmap") }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { throw Failure.check("png") }
        try png.write(to: url)
    }
}

private extension CGFloat {
    func rounded(toPlaces places: Int) -> CGFloat {
        let scale = pow(10.0, CGFloat(places))
        return (self * scale).rounded() / scale
    }
}
