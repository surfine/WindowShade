import Cocoa

/// Only our temporary fixture child and an alpha-zero, unshown Canvas. No product entry or sources.
@main enum OwnedScrollPreview {
    enum Failure: Error { case check(String) }
    @MainActor static func until(_ name: String, _ test: () -> Bool) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + 8
        while !test(), ProcessInfo.processInfo.systemUptime < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
        guard test() else { throw Failure.check(name) }
    }
    @MainActor static func texts(_ view: NSView) -> [NSTextView] {
        (view as? NSTextView).map { [$0] } ?? view.subviews.flatMap { texts($0) }
    }
    @MainActor static func main() async throws {
        _ = NSApplication.shared; NSApp.setActivationPolicy(.prohibited)
        let out = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let tempBase = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
        let temp = tempBase.appendingPathComponent("owned-scroll-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let backend = temp.appendingPathComponent("synthetic-codex.py")
        let original = try String(contentsOfFile: "tests/fixtures/conductor-backend.py", encoding: .utf8)
        let anchor = "        emit({\"method\": \"turn/started\", \"params\": {\"threadId\": thread, \"turn\": {\"id\": turn}}})"
        guard original.components(separatedBy: anchor).count == 2 else { throw Failure.check("fixture anchor") }
        let delta = """

        if text == 'hold scroll-preview':
            import threading
            def stream(own_thread, own_turn):
                last = 0
                signal = pathlib.Path(__file__).parent / 'stage.txt'
                while last < 5:
                    try:
                        stage = int(signal.read_text())
                    except (FileNotFoundError, ValueError):
                        stage = 0
                    if stage > last:
                        last += 1
                        value = ''.join(f'第 {last} 段 · 第 {i:02d} 行：回看前文时应留在这里，新的内容继续接在末尾。\\n' for i in range(1, 41)) + f'结束标记-{last}\\n'
                        emit({'method': 'item/agentMessage/delta', 'params': {'threadId': own_thread, 'turnId': own_turn, 'delta': value}})
                    time.sleep(0.01)
            threading.Thread(target=stream, args=(thread, turn), daemon=True).start()
"""
        let augmented = original.replacingOccurrences(of: anchor, with: anchor + delta)
        try augmented.write(to: backend, atomically: true, encoding: .utf8)
        try augmented.write(to: out.appendingPathComponent("synthetic-backend.py"), atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: backend.path)
        var frames = [[String: Any]](); var children = [WS2OwnedLaunchController](); var windows = [NSWindow]()
        var report: [String: Any] = ["synthetic": true, "actionsOnRealSources": 0, "temporaryRoot": temp.path]
        func write() throws {
            report["frames"] = frames
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: out.appendingPathComponent("frames.json"))
        }
        do {
            for parent in [NSAppearance.Name.aqua, .darkAqua] {
                let label = parent == .aqua ? "light" : "dark"
                try "0".write(to: temp.appendingPathComponent("stage.txt"), atomically: true, encoding: .utf8)
                let project = temp.appendingPathComponent(label + "-project", isDirectory: true)
                try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
                let controller = WS2OwnedLaunchController(profileRoot: temp.appendingPathComponent(label + "-profile"), mayUse: { true })
                children.append(controller)
                guard controller.selectProject(project), controller.selectExecutable(backend), controller.launch(consent: true) else { throw Failure.check("synthetic launch") }
                try await until("ready") { controller.phase == .ready }
                guard controller.chooseModel("fixture-a"), controller.chooseEffort("medium") else { throw Failure.check("fixture model") }
                let view = WS2OwnedSessionView(controller: controller)
                view.inputIsCurrent = { true }; view.onCancel = {}; view.openModelPicker = {}; view.openConductorPage = {}
                controller.onChange = { [weak view] in view?.scheduleRender() }
                let canvas = NotchCanvasView(frame: NSRect(x: 0, y: 0, width: 620, height: 513.5))
                let window = NSWindow(contentRect: canvas.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
                windows.append(window); window.isReleasedWhenClosed = false; window.alphaValue = 0
                window.appearance = NSAppearance(named: parent); window.contentView = canvas
                window.setFrame(NSRect(x: -8000, y: -8000, width: 620, height: 513.5), display: false)
                canvas.setAuthentication(view)
                func layout() {
                    let height = min(480, view.interactionSize.height)
                    let box = NSRect(x: 0, y: 0, width: 620, height: height + 33.5)
                    canvas.frame = box
                    let content = NotchCanvasView.Content(tiles: [], dots: 0, dotsChanged: false, dotsY: 0, compact: nil, compactSlots: nil, alert: nil, hint: nil, notchHeight: 33.5)
                    canvas.morph(to: box, style: .init(cornerRadius: 24, allCorners: false, fill: .black, border: 0.5), content: content, spring: nil) {}
                    canvas.placeAuthentication(in: NSRect(x: 0, y: 0, width: 620, height: height))
                    canvas.layoutSubtreeIfNeeded()
                }
                view.render(); layout()
                guard let text = texts(view).first(where: { !$0.isEditable }), let scroll = text.enclosingScrollView else { throw Failure.check("real reply text/scroll") }
                func position() -> [String: Any] {
                    let clip = scroll.contentView.bounds
                    return ["origin": clip.minY, "visibleHeight": clip.height, "documentHeight": text.bounds.height, "gap": text.bounds.maxY - clip.maxY, "characters": text.string.count, "textWidth": text.bounds.width, "containerWidth": text.textContainer?.containerSize.width ?? -1, "lineHeight": text.font.map { text.layoutManager?.defaultLineHeight(for: $0) ?? -1 } ?? -1]
                }
                func capture(_ stage: String, before: [String: Any] = [:]) throws {
                    let name = label + "-" + stage
                    guard !window.isVisible, !NSApp.isActive, !NSScreen.screens.contains(where: { $0.frame.intersects(window.frame) }) else { throw Failure.check("hidden offscreen") }
                    guard let rep = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds) else { throw Failure.check("bitmap") }
                    canvas.cacheDisplay(in: canvas.bounds, to: rep)
                    guard let data = rep.representation(using: .png, properties: [:]) else { throw Failure.check("png") }
                    try data.write(to: out.appendingPathComponent(name + ".png"))
                    guard let input = texts(view).first(where: { $0.isEditable }), let inputScroll = input.enclosingScrollView else { throw Failure.check("own composer") }
                    let draftMetrics: [String: Any] = ["matchesController": input.string == controller.draft, "characters": input.string.count, "fontSize": input.font?.pointSize ?? -1, "height": inputScroll.bounds.height, "radius": inputScroll.layer?.cornerRadius ?? -1, "border": inputScroll.borderType.rawValue, "paddingX": input.textContainerInset.width, "paddingY": input.textContainerInset.height, "linePadding": input.textContainer?.lineFragmentPadding ?? -1, "background": input.drawsBackground, "replyBackground": text.drawsBackground, "replyBorder": scroll.borderType.rawValue, "replyHeight": scroll.bounds.height]
                    frames.append(["draft": draftMetrics, "name": name, "stage": stage, "before": before, "after": position(), "sameView": true, "parent": label, "visible": window.isVisible, "active": NSApp.isActive, "alpha": window.alphaValue, "height": canvas.bounds.height, "dark": canvas.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua, "outputHidden": scroll.isHiddenOrHasHiddenAncestor, "phase": String(describing: controller.phase)])
                }
                guard controller.send("hold scroll-preview", hasMarkedText: false) else { throw Failure.check("send fixture") }
                try await until("running") { controller.phase == .running }
                try await Task.sleep(nanoseconds: 100_000_000); layout(); try capture("empty")
                let ownDraft="等这一轮完成后，请先检查长标题。\n保留回看位置，再整理可复现步骤。\n这是本机样件草稿，尚未发送。"
                guard controller.editDraft(ownDraft) else { throw Failure.check("own draft") }
                try await until("draft render") { texts(view).contains { $0.string == ownDraft } }
                for stage in 1...5 {
                    switch stage {
                    case 2: text.scrollToEndOfDocument(nil)
                    case 3: scroll.contentView.scroll(to: NSPoint(x: 0, y: 0)); scroll.reflectScrolledClipView(scroll.contentView)
                    case 4, 5:
                        let gap: CGFloat = stage == 4 ? 30 : 20
                        scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, text.bounds.maxY - scroll.contentView.bounds.height - gap)))
                        scroll.reflectScrolledClipView(scroll.contentView)
                    default: break
                    }
                    let before = position()
                    try String(stage).write(to: temp.appendingPathComponent("stage.txt"), atomically: true, encoding: .utf8)
                    try await until("delta \(stage)") { controller.text.contains("结束标记-\(stage)") }
                    try await until("view scheduled render \(stage)") { text.string == controller.text }
                    try await Task.sleep(nanoseconds: 80_000_000); layout()
                    try capture(["", "initial", "bottom", "top", "outside-threshold", "inside-threshold"][stage], before: before)
                }
                view.revoke(); controller.onChange = nil; canvas.setAuthentication(nil); window.close()
                controller.stop(clearPrivate: true)
                try await until("child reaped") { !controller.isBusy }
            }
            report["childrenReaped"] = children.allSatisfy { !$0.isBusy }
            guard temp.deletingLastPathComponent() == tempBase else { throw Failure.check("cleanup boundary") }
            try FileManager.default.removeItem(at: temp)
            report["temporaryRemoved"] = true; try write()
            print("PASS \(frames.count) real same-view streaming reply captures; child reaped; own temporary root removed")
        } catch {
            for c in children { c.onChange = nil; c.stop(clearPrivate: true) }
            for c in children { try? await until("failure reap") { !c.isBusy } }
            windows.forEach { $0.close() }
            report["failure"] = String(describing: error); report["childrenReaped"] = children.allSatisfy { !$0.isBusy }; report["temporaryRemoved"] = false
            try write(); print("FAILED: \(error); own temporary data preserved"); exit(1)
        }
    }
}
