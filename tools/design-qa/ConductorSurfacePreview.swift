import Cocoa

/// 只渲染生产视图；自造输入，不连助手、不读项目、不录音、不批准动作。
@main enum ConductorSurfacePreview {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        var frames: [[String: Any]] = []
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let states: [(String, ConductorNotch)] = [
                ("connected", .connected(project: "设计工作间", provider: .codex, effort: "high")),
                ("models", .models(["Codex · high", "Claude Code · medium", "Codex · low"], selected: 0)),
                ("listening", .listening(source: "iPhone")),
                ("draft", .draft("请检查计时器的比例，再告诉我发现的问题。", header: "草稿 · 给 设计工作间 · Codex · high", uncertain: [3..<6])),
                ("completed", .completed("已完成计时器检查。\n尺寸和层次已对齐。")),
                ("disconnected", .disconnected)]
            for (name, state) in states {
                let view = WS2ConductorView(frame: .zero)
                view.hostScreenWidth = 1440
                view.inputIsCurrent = { true }
                _ = view.render(.connected(project: "设计工作间", provider: .codex, effort: "high"))
                guard view.render(state) else { throw NSError(domain: "NativePreview", code: 1) }
                if name == "listening" { view.updateAudio([0.03, 0.08, 0.18, 0.35, 0.12, 0.04]) }
                try capture(view, size: view.interactionSize, name: name, appearance: appearance, output: output, frames: &frames)
                view.revoke()
            }
            // 构造器只赋值；不调用项目选择、启动、登录、发消息或文件操作。
            let controller = WS2OwnedLaunchController(profileRoot: output.appendingPathComponent("unused-profile"), mayUse: { false })
            let view = WS2OwnedSessionView(controller: controller)
            try capture(view, size: view.interactionSize, name: "owned-session-idle", appearance: appearance, output: output, frames: &frames)
            view.revoke()
        }
        try JSONSerialization.data(withJSONObject: frames, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("frames.json"))
        print("Rendered 14 actual production surfaces; all windows invisible, no runtime or external action.")
    }

    @MainActor private static func capture(_ view: NSView, size: NSSize, name: String, appearance: NSAppearance.Name,
                                          output: URL, frames: inout [[String: Any]]) throws {
        view.frame = NSRect(origin: .zero, size: size)
        // 采用生产黑底根的外观；这里仅拍卡片内容，完整宿主几何由 HostSurfacePreview 验证。
        let container = NotchCanvasView(frame: view.frame)
        container.wantsLayer = true; container.layer?.backgroundColor = NSColor.black.cgColor
        container.addSubview(view)
        let window = NSWindow(contentRect: container.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = container
        window.appearance = NSAppearance(named: appearance)
        container.layoutSubtreeIfNeeded()
        let file = "\(appearance == .aqua ? "light" : "dark")-\(name).png"
        guard let rep = container.bitmapImageRepForCachingDisplay(in: container.bounds) else {
            throw NSError(domain: "NativePreview", code: 2)
        }
        container.cacheDisplay(in: container.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "NativePreview", code: 3)
        }
        try data.write(to: output.appendingPathComponent(file))
        frames.append(["image": file, "width": size.width, "height": size.height, "visibleWindow": window.isVisible,
                       "spoken": view.accessibilityLabel() ?? ""])
        window.close()
    }
}
