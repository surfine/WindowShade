import Cocoa

/// 第28批：静音页（WS2SilentPageView + IslandChip）中英渲染夹具（轻量档）。
/// 真生产视图离屏渲染，只直接设 WSL10n.language 与 englishBundle，不写偏好、不碰相机/输入。
/// 帧：zh 初始页（芯片 + 标题 + 确认块）、en 同页、zh 结果句帧（note 状态行）、en 结果句帧。
@main enum SilentPageLanguagePreview {
    enum Failure: Error { case check(String) }

    final class Background: NSView {
        override func draw(_ rect: NSRect) { NSColor.black.setFill(); rect.fill() }
    }

    @MainActor static func main() async {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let out = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let stringsDir = ProcessInfo.processInfo.environment["WS2_LOCALIZATION_DIR"]
        let enBundle = stringsDir.flatMap { Bundle(url: URL(fileURLWithPath: $0).appendingPathComponent("en.lproj")) }
        do {
            try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
            var frames: [[String: Any]] = []

            // 宿主要活着（页面弱引用它）；探针不 attach runtime，只是静态渲染。
            let silentHost = WS2SilentHost()
            func makePage() -> NSView {
                // 静音页是 NSView 子类，宿主只需黑底。IslandChip 的玻璃样式按黑底画。
                let host = WS2SilentPageView(host: silentHost)
                host.frame = NSRect(x: 14, y: 10, width: 344, height: 168)
                let root = Background(frame: NSRect(x: 0, y: 0, width: 372, height: 196))
                root.wantsLayer = true
                root.layer?.cornerRadius = 18
                root.layer?.cornerCurve = .continuous
                root.addSubview(host)
                return root
            }

            let combos: [(String, WSLanguage)] = [("zh", .zh), ("en", .en)]
            for (lang, wslang) in combos {
                if let enBundle, wslang == .en { WSL10n.englishBundle = enBundle } else { WSL10n.englishBundle = nil }
                WSL10n.language = wslang
                let root = makePage()
                let window = NSWindow(contentRect: root.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.alphaValue = 0
                window.contentView = root
                window.setFrame(NSRect(x: -8000, y: -8000, width: 372, height: 196), display: false)
                root.layoutSubtreeIfNeeded()
                guard !window.isVisible, NSScreen.screens.allSatisfy({ !$0.frame.intersects(window.frame) }) else {
                    throw Failure.check("fixture window escaped")
                }
                var texts: [String] = []
                collect(root, into: &texts)
                frames.append(["name": "\(lang)-silent-initial", "language": lang, "surface": "silent",
                               "labels": texts, "preferencesWritten": false])
                try writePNG(root, to: out.appendingPathComponent("\(lang)-silent-initial.png"))
                // 结果句帧：走生产 note 路径写一行状态。
                if let page = root.subviews.first as? WS2SilentPageView {
                    page.note(WS2SilentCopy.saying("notDone"))
                    root.layoutSubtreeIfNeeded()
                    var texts2: [String] = []
                    collect(root, into: &texts2)
                    frames.append(["name": "\(lang)-silent-notdone", "language": lang, "surface": "silent",
                                   "labels": texts2, "preferencesWritten": false])
                    try writePNG(root, to: out.appendingPathComponent("\(lang)-silent-notdone.png"))
                }
                window.contentView = nil
                window.close()
            }

            let report: [String: Any] = [
                "frames": frames,
                "preferencesWritten": false,
                "fixture": "SilentPageLanguagePreview",
            ]
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                .write(to: out.appendingPathComponent("frames.json"))
            print("PASS silent-page language preview: \(frames.count) frames")
        } catch {
            try? String(describing: error).write(to: out.appendingPathComponent("failure.txt"), atomically: true, encoding: .utf8)
            print("FAIL silent-page language preview: \(error)")
            exit(1)
        }
    }

    @MainActor static func collect(_ view: NSView, into out: inout [String]) {
        if let button = view as? NSButton, !button.title.isEmpty { out.append(button.title) }
        if let field = view as? NSTextField, !field.stringValue.isEmpty { out.append(field.stringValue) }
        view.subviews.forEach { collect($0, into: &out) }
    }

    @MainActor static func writePNG(_ view: NSView, to url: URL) throws {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw Failure.check("bitmap") }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { throw Failure.check("png") }
        try png.write(to: url)
    }
}
