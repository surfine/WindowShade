import Cocoa

/// 实际刘海宿主与生产视图；面板位于屏幕外，不激活应用、不连接助手或访问用户文件。
@main enum HostSurfacePreview {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        var frames: [[String: Any]] = []
        var checks: [[String: Any]] = []
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            for name in ["model-picker-idle", "conductor-page-idle", "sessions-empty", "sessions-mixed", "sessions-long", "conductor-connected", "owned-session-idle"] {
                let controller = WS2OwnedLaunchController(profileRoot: output.appendingPathComponent("unused-profile"), mayUse: { false })
                let view: NSView & WS2LeaseContent
                switch name {
                case "model-picker-idle":
                    let picker = WS2ModelPickerView(controller: controller)
                    picker.hostScreenWidth = 1440
                    picker.renderDevices([])
                    view = picker
                case "conductor-page-idle":
                    let page = WS2ConductorPageView(controller: controller)
                    page.renderDevices([])
                    view = page
                case "conductor-connected":
                    let card = WS2ConductorView(frame: .zero)
                    card.hostScreenWidth = 1440
                    _ = card.render(.connected(project: "设计工作间", provider: .codex, effort: "high"))
                    view = card
                case "owned-session-idle":
                    view = WS2OwnedSessionView(controller: controller)
                default:
                    let list = WS2AgentSessionView(frame: .zero)
                    list.render(name == "sessions-empty" ? [] : sessions(long: name == "sessions-long"))
                    view = list
                }
                let panel = NotchPanel(notch: NSRect(x: -8000, y: 866.5, width: 185, height: 33.5), virtual: false)
                panel.isReleasedWhenClosed = false
                panel.appearance = NSAppearance(named: appearance)
                panel.setInteraction(view, animated: false)
                guard let canvas = panel.contentView else { throw NSError(domain: "HostPreview", code: 1) }
                canvas.layoutSubtreeIfNeeded()
                guard NSScreen.screens.allSatisfy({ !$0.frame.intersects(panel.frame) }) else {
                    panel.close()
                    throw NSError(domain: "HostPreview", code: 4)
                }
                let inheritedDark = view.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                checks.append(["state": name, "parent": appearance.rawValue, "darkContent": inheritedDark])
                let file = "\(appearance == .aqua ? "light" : "dark")-\(name).png"
                guard let rep = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds) else { throw NSError(domain: "HostPreview", code: 2) }
                canvas.cacheDisplay(in: canvas.bounds, to: rep)
                guard let data = rep.representation(using: .png, properties: [:]) else { throw NSError(domain: "HostPreview", code: 3) }
                try data.write(to: output.appendingPathComponent(file))
                frames.append(["image": file, "width": canvas.bounds.width, "height": canvas.bounds.height,
                               "contentWidth": view.bounds.width, "contentHeight": view.bounds.height,
                               "visibleWindow": panel.isVisible, "intersectsScreen": false, "activeApplication": NSApp.isActive,
                               "darkContent": inheritedDark])
                view.revoke()
                panel.setInteraction(nil, animated: false)
                panel.close()
            }
        }
        for (file, value) in [("frames.json", frames), ("appearance-checks.json", checks)] {
            try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
                .write(to: output.appendingPathComponent(file))
        }
        let behavior = verifySessionActions()
        try JSONSerialization.data(withJSONObject: behavior, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("session-action-checks.json"))
        print("Rendered \(frames.count) actual hosted production views; dark content: \(checks.filter { $0["darkContent"] as? Bool == true }.count)/\(checks.count).")
        print("Session action checks: \(behavior.filter { $0["pass"] as? Bool == true }.count)/\(behavior.count).")
        if behavior.contains(where: { $0["pass"] as? Bool != true }) { exit(1) }
        if ProcessInfo.processInfo.environment["WINDOWSHADE_PREVIEW_REQUIRE_DARK"] == "1",
           checks.contains(where: { $0["darkContent"] as? Bool != true }) { exit(1) }
    }

    @MainActor private static func verifySessionActions() -> [[String: Any]] {
        var checks: [[String: Any]] = []
        func check(_ name: String, _ value: Bool) { checks.append(["name": name, "pass": value]) }
        func buttons(_ view: NSView) -> [NSButton] {
            (view as? NSButton).map { [$0] } ?? view.subviews.flatMap { buttons($0) }
        }
        let list = WS2AgentSessionView(frame: .zero)
        var fresh = false
        var opened: [WS2.Context] = [], stopped: [WS2.Context] = []
        list.inputIsCurrent = { fresh }
        list.open = { opened.append($0) }; list.stop = { stopped.append($0) }
        let values = sessions(long: false)
        list.render(values)
        let actions = buttons(list)
        check("four opens; only owned running can stop", actions.filter { $0.title == "打开" }.count == 4 && actions.filter { $0.title == "停止" }.count == 1)
        let open = actions.first { $0.title == "打开" }!
        let stop = actions.first { $0.title == "停止" }!
        open.performClick(nil); stop.performClick(nil)
        check("revoked input cannot invoke actions", opened.isEmpty && stopped.isEmpty)
        fresh = true
        open.performClick(nil); stop.performClick(nil)
        check("open carries exact observed context", opened == [values[0].context])
        check("stop carries exact owned running context", stopped == [values[1].context])
        list.render([])
        open.performClick(nil)
        check("old removed row cannot act", opened.count == 1 && buttons(list).isEmpty)
        list.render(Array(repeating: values, count: 20).flatMap { $0 })
        check("list bounded at 64 rows", buttons(list).filter { $0.title == "打开" }.count == 64)
        let old = buttons(list).first!
        list.revoke(); old.performClick(nil)
        check("revoke clears bindings and visible actions", opened.count == 1 && stopped.count == 1 && buttons(list).isEmpty)
        return checks
    }

    private static func sessions(long: Bool) -> [AgentSessions.Session] {
        let states: [(WS2.Provider, AgentSessions.Control, AgentSessions.Status, String)] = [
            (.codex, .observed, .running, "正在检查计时器的比例"),
            (.claudeCode, .owned, .running, "正在整理项目里的图片"),
            (.codex, .observed, .waiting, "等待你确认联网操作"),
            (.claudeCode, .owned, .completed, "已完成界面检查")]
        return states.enumerated().map { index, value in
            let context = WS2.Context(peerID: "fixture", projectID: "设计工作间", session: .init(provider: value.0, id: "fixture-\(index)"), epoch: 1)
            return .init(context: context, control: value.1, status: value.2,
                         summary: long ? String(repeating: "这是一句用于检查换行与动作位置的自造文字。", count: 16) : value.3,
                         turnID: nil, tools: [], lastUpdate: .init(nanoseconds: 0))
        }
    }
}
