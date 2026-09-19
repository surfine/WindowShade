// 开发专用 fixture：在进入正式 AppDelegate 的权限、传感器与窗口操作初始化前
// 选择 fake backend。固定测试数据只用于开发和测试，正常启动不会出现。

import Cocoa

final class WindowBrowserFixture {
    private var panel: WindowBrowserPanel?
    private var records: [WindowRecord]
    private var selection: WindowKey?
    private let style: WindowBrowserDisplayStyle
    private let screenRecordingAvailable: Bool

    init() {
        let scenario = ProcessInfo.processInfo.environment["WINDOWSHADE_BROWSER_FIXTURE"] ?? "mixed"
        records = WindowBrowserFixture.makeRecords(scenario: scenario)
        style = scenario == "many" ? .list : .grid
        screenRecordingAvailable = scenario != "nopermission"
        selection = records.first?.key
    }

    func show() {
        // 隔离演示可强制浅色/深色外观，便于不修改系统设置就做视觉检查。
        switch ProcessInfo.processInfo.environment["WINDOWSHADE_BROWSER_FIXTURE_APPEARANCE"] {
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        default: break
        }
        let screen = NSScreen.main ?? NSScreen.screens.first
        let size = ProcessInfo.processInfo.environment["WINDOWSHADE_BROWSER_FIXTURE_SIZE"] == "small"
            ? CGSize(width: 460, height: 340)
            : CGSize(width: 720, height: 560)
        let frame = screen.map {
            NSRect(x: $0.visibleFrame.midX - size.width / 2,
                   y: $0.visibleFrame.midY - size.height / 2,
                   width: size.width, height: size.height)
        } ?? NSRect(x: 200, y: 200, width: size.width, height: size.height)
        let panel = WindowBrowserPanel(mode: .keyboard, frame: frame)
        panel.onCancel = { NSApp.terminate(nil) }
        let content = panel.browserContentView
        content.onActivate = { [weak self] key in self?.select(key) }
        content.onSelect = { [weak self] key in self?.select(key) }
        content.onPrimary = { [weak self] key in
            guard let self else { return }
            self.mutate(key: key) { record in
                record.shadeState = record.shadeState == .folded ? .normal : .folded
            }
        }
        content.onPin = { [weak self] key in
            guard let self else { return }
            self.mutate(key: key) { record in
                record.pinState = record.pinState == .running ? .none : .running
            }
        }
        content.onSearchChanged = { [weak self] _ in self?.render() }
        content.onStyleChanged = { _ in }
        content.onCommit = { [weak self] in self?.render() }
        self.panel = panel
        render()
        panel.presentKeyboardPanel()
        if let autoexit = ProcessInfo.processInfo.environment["WINDOWSHADE_BROWSER_FIXTURE_AUTOEXIT"],
           let seconds = Double(autoexit) {
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
                guard let self else { NSApp.terminate(nil); return }
                // 可选：像用户点分段控件一样切一次风格，验证“点了就换”这条真实路径。
                var clickedStyle = "-"
                if let wanted = ProcessInfo.processInfo.environment["WINDOWSHADE_BROWSER_FIXTURE_STYLE"],
                   let control = panel.browserContentView.interfaceSubviews
                    .compactMap({ $0 as? NSSegmentedControl }).first,
                   let action = control.action {
                    control.selectedSegment = wanted == "list" ? 1 : 0
                    NSApp.sendAction(action, to: control.target, from: control)
                    clickedStyle = wanted
                }
                panel.browserContentView.layout()
                let frames = panel.browserContentView.layoutFrameSummary
                let rendered = panel.browserContentView.renderedLayout
                print("window-browser-fixture: records=\(self.records.count) "
                      + "panel=\(Int(panel.frame.width))x\(Int(panel.frame.height)) "
                      + "style=\(self.style.rawValue) "
                      + "clickedStyle=\(clickedStyle) "
                      + "renderedStyle=\(rendered.style.rawValue) "
                      + "renderedRows=\(rendered.rows) renderedCards=\(rendered.cards) "
                      + "canBecomeKey=\(panel.canBecomeKey) "
                      + "searchVisible=\(panel.browserContentView.searchFieldVisible) "
                      + "searchText=\"\(panel.browserContentView.searchText)\" "
                      + "searchTop=\(Int(frames.search.maxY)) "
                      + "listBottom=\(Int(frames.list.minY)) "
                      + "overlap=\(frames.search.intersects(frames.list)) "
                      + "viewThumbnails=\(panel.browserContentView.cachedThumbnailCount) "
                      + "viewImageBytes=\(panel.browserContentView.cachedThumbnailBytes)")
                NSApp.terminate(nil)
            }
        }
    }

    private func select(_ key: WindowKey) {
        selection = key
        render()
    }

    private func mutate(key: WindowKey, _ body: (inout WindowRecord) -> Void) {
        guard let index = records.firstIndex(where: { $0.key == key }) else { return }
        body(&records[index])
        render()
    }

    private func render() {
        guard let content = panel?.browserContentView else { return }
        let query = content.searchText
        let visible = records.filter { WindowBrowserSearch.matches(query: query, record: $0) }
        let status: String
        if visible.isEmpty {
            status = "没有结果（fixture）"
        } else if !screenRecordingAvailable {
            status = "没有屏幕录制权限，只显示图标与标题（fixture）"
        } else if records.contains(where: { $0.confidence == .provisional }) {
            status = "部分数据待刷新（fixture）"
        } else {
            status = "fixture：按钮只改 fake 状态，不会进入真实 AX 路径"
        }
        content.update(mode: .keyboard, records: visible, selection: selection,
                       style: style, busyKeys: [],
                       screenRecordingAvailable: screenRecordingAvailable,
                       status: status)
        for record in visible {
            if record.title.contains("图像失败") {
                content.applyThumbnail(nil, for: record.key)
            }
        }
    }

    // MARK: 场景数据

    private static func makeRecords(scenario: String) -> [WindowRecord] {
        func key(_ pid: pid_t, _ id: CGWindowID) -> WindowKey {
            WindowKey(application: ApplicationInstanceKey(pid: pid, generation: 1),
                      originalWindowID: id, windowGeneration: 1)
        }
        func record(_ pid: pid_t, _ id: CGWindowID, app: String, title: String,
                    shade: WindowBrowserShadeState = .normal,
                    pin: WindowBrowserPinState = .none,
                    visibility: WindowBrowserSystemVisibility = .onScreen,
                    confidence: WindowBrowserDiscoveryConfidence = .confirmed,
                    capabilities: WindowBrowserCapabilities = .discoveredWindow)
            -> WindowRecord {
            WindowRecord(key: key(pid, id), bundleIdentifier: "fixture.app.\(pid)",
                         appName: app, title: title,
                         logicalFrame: CGRect(x: 100, y: 100, width: 800, height: 600),
                         placementSource: .liveDiscovery,
                         systemVisibility: visibility, shadeState: shade, pinState: pin,
                         capabilities: capabilities, confidence: confidence,
                         metadataRevision: UInt64(id), isMinimized: visibility == .minimized,
                         isOnScreen: visibility == .onScreen,
                         isFoldedOffscreen: shade == .folded,
                         isManaged: shade == .folded || pin == .running)
        }

        if scenario == "empty" { return [] }
        if scenario == "nopermission" {
            // 缺少屏幕录制权限：仍然显示应用图标、标题与状态，图像相关按钮禁用。
            return [
                record(7201, 701, app: "Finder", title: "没有录屏权限的窗口",
                       capabilities: [.activate, .fold, .close, .minimize]),
                record(7202, 702, app: "文本编辑", title: "第二个窗口",
                       capabilities: [.activate, .fold, .close, .minimize])
            ]
        }
        if scenario == "many" {
            return (1...20).map {
                record(7001, CGWindowID(500 + $0), app: "示例应用 \(($0 % 3) + 1)",
                       title: $0 % 4 == 0
                           ? "一个非常长的中英文混合标题 Window \($0) — 用于检查最多两行与截断"
                           : "窗口 \($0)")
            }
        }
        var records: [WindowRecord] = [
            record(7101, 601, app: "Safari", title: "OpenAI",
                   capabilities: [.activate, .fold, .pinPreview, .close, .minimize, .capture]),
            record(7101, 602, app: "Safari", title: "没有可信映射的窗口",
                   confidence: .provisional,
                   capabilities: [.activate]),
            record(7102, 603, app: "Finder", title: "Downloads",
                   capabilities: [.activate, .fold, .pinPreview, .close, .minimize, .capture]),
            record(7103, 604, app: "预览", title: "图像失败：受保护内容",
                   capabilities: [.activate, .close, .minimize]),
            record(7104, 605, app: "文本编辑", title: "未命名",
                   shade: .folded, pin: .none,
                   capabilities: .managedWindow),
            record(7105, 606, app: "终端", title: "恢复中",
                   shade: .restoring,
                   capabilities: .managedWindow),
            record(7106, 607, app: "备忘录", title: "恢复失败（fixture）",
                   shade: .folded, visibility: .offScreen,
                   capabilities: .managedWindow),
            record(7107, 608, app: "照片", title: "置顶预览",
                   pin: .running,
                   capabilities: .discoveredWindow),
            record(7108, 609, app: "音乐", title: "已最小化",
                   visibility: .minimized,
                   capabilities: [.activate, .fold, .pinPreview, .close, .minimize]),
        ]
        if ProcessInfo.processInfo.environment["WINDOWSHADE_BROWSER_FIXTURE"] == "long" {
            records.append(record(7109, 610, app: "超长应用名称的应用",
                                  title: "这是一个非常非常长的窗口标题，用来检查两行截断与可访问性完整标题 — "
                                    + "A very long window title for truncation checks"))
        }
        return records
    }
}
