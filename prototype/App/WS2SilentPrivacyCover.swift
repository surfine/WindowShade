// WindowShade 2.1 · 静音「方便遮一下」：逐屏不透明遮罩，按显示器身份对账（R02）。
// 不是系统锁屏，也不宣称 loginwindow 隔离强度。Esc / 刘海清除会撤掉。
// 验证后显示若加入，不得沿用本方便遮挡的清除策略。
import Cocoa

@MainActor
final class WS2SilentPrivacyCoverController {
    struct ExpectedDisplay: Equatable, Sendable {
        var id: CGDirectDisplayID
        var frame: CGRect
        var backingScaleFactor: CGFloat
    }

    struct Observation: Equatable, Sendable {
        var epoch: UInt64
        var expected: [ExpectedDisplay]
        var coveredIDs: [CGDirectDisplayID]
        var unknownDisplayCount: Int

        var requestedScreenCount: Int { expected.count }
        var visibleOverlayCount: Int { coveredIDs.count }
        var overlayCreated: Bool { !coveredIDs.isEmpty }
        var allScreensCovered: Bool {
            !expected.isEmpty
                && unknownDisplayCount == 0
                && Set(coveredIDs) == Set(expected.map(\.id))
        }
        var missingScreens: Bool { !allScreensCovered }
    }

    private struct PanelRecord {
        var panel: NSPanel
        var expected: ExpectedDisplay
    }

    private var records: [CGDirectDisplayID: PanelRecord] = [:]
    private var expectedDisplays: [ExpectedDisplay] = []
    private var epoch: UInt64 = 0
    private var escapeLocal: Any?
    private var escapeGlobal: Any?
    private var screenObserver: NSObjectProtocol?
    /// 刘海「清除遮挡」回调（由宿主接线）；方便遮挡专用，不用于验证后显示。
    var onClearRequested: (() -> Void)?

    var isCovering: Bool { !expectedDisplays.isEmpty }

    var observation: Observation {
        reconcile()
    }

    /// 在当前所有可识别屏上铺不透明黑层；重复请求复用面板，不先全撤。
    @discardableResult
    func coverAllScreens() -> Observation {
        epoch &+= 1
        let snapshot = snapshotExpectedDisplays()
        expectedDisplays = snapshot
        guard !snapshot.isEmpty else {
            tearDownMonitors()
            removeAllPanels()
            return Observation(epoch: epoch, expected: [], coveredIDs: [], unknownDisplayCount: unknownScreenCount())
        }
        var keep = Set<CGDirectDisplayID>()
        for expected in snapshot {
            keep.insert(expected.id)
            if var existing = records[expected.id] {
                if existing.expected.frame != expected.frame
                    || abs(existing.expected.backingScaleFactor - expected.backingScaleFactor) > 0.001 {
                    existing.panel.setFrame(expected.frame, display: true)
                    existing.expected = expected
                    records[expected.id] = existing
                }
                existing.panel.orderFrontRegardless()
            } else {
                let panel = makePanel(matching: expected)
                panel.orderFrontRegardless()
                records[expected.id] = PanelRecord(panel: panel, expected: expected)
            }
        }
        for id in records.keys where !keep.contains(id) {
            if let record = records.removeValue(forKey: id) {
                record.panel.orderOut(nil)
                record.panel.close()
            }
        }
        installMonitors()
        return observation
    }

    func clear() {
        tearDownMonitors()
        expectedDisplays = []
        removeAllPanels()
    }

    /// 供输入路由 / 刘海按钮调用的同一清除入口。
    func requestClear() {
        clear()
        onClearRequested?()
    }

    private func reconcile() -> Observation {
        var covered: [CGDirectDisplayID] = []
        for expected in expectedDisplays {
            guard let record = records[expected.id], record.panel.isVisible else { continue }
            let frame = record.panel.frame
            // 几何对账：允许微小漂移；未知 id 不折成 0。
            if abs(frame.minX - expected.frame.minX) <= 1,
               abs(frame.minY - expected.frame.minY) <= 1,
               abs(frame.width - expected.frame.width) <= 1,
               abs(frame.height - expected.frame.height) <= 1 {
                covered.append(expected.id)
            }
        }
        return Observation(
            epoch: epoch,
            expected: expectedDisplays,
            coveredIDs: covered,
            unknownDisplayCount: unknownScreenCount()
        )
    }

    private func snapshotExpectedDisplays() -> [ExpectedDisplay] {
        var result: [ExpectedDisplay] = []
        for screen in NSScreen.screens {
            guard let id = identifiedDisplayID(for: screen), id != 0 else { continue }
            result.append(ExpectedDisplay(
                id: id,
                frame: screen.frame,
                backingScaleFactor: screen.backingScaleFactor
            ))
        }
        return result
    }

    private func unknownScreenCount() -> Int {
        NSScreen.screens.filter { identifiedDisplayID(for: $0) == nil }.count
    }

    private func removeAllPanels() {
        for record in records.values {
            record.panel.orderOut(nil)
            record.panel.close()
        }
        records.removeAll()
    }

    private func makePanel(matching expected: ExpectedDisplay) -> NSPanel {
        let panel = NSPanel(
            contentRect: expected.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        panel.setFrame(expected.frame, display: false)
        panel.isOpaque = true
        panel.backgroundColor = .black
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.hidesOnDeactivate = false
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 2)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        let view = CoverContentView(frame: NSRect(origin: .zero, size: expected.frame.size))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        view.onEscape = { [weak self] in self?.requestClear() }
        panel.contentView = view
        return panel
    }

    private func identifiedDisplayID(for screen: NSScreen) -> CGDirectDisplayID? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        // 不用 uint32Value 默默折断；拒绝布尔与 0。
        return JournalNumeric.displayID(number)
    }

    private func installMonitors() {
        tearDownMonitors()
        escapeLocal = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            self?.requestClear()
            return nil
        }
        // 仅在遮挡生效期间临时监听：外部前台 App 也能 Esc；clear 时拆除，不长期驻留。
        escapeGlobal = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return }
            DispatchQueue.main.async { self?.requestClear() }
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isCovering else { return }
                // 热插拔：按新集合补画/回收，不宣称系统级隔离。
                _ = self.coverAllScreens()
            }
        }
    }

    private func tearDownMonitors() {
        if let escapeLocal {
            NSEvent.removeMonitor(escapeLocal)
            self.escapeLocal = nil
        }
        if let escapeGlobal {
            NSEvent.removeMonitor(escapeGlobal)
            self.escapeGlobal = nil
        }
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
    }
}

/// 遮罩内容：接受 Esc（面板为 key 时）；点击不穿透。
private final class CoverContentView: NSView {
    var onEscape: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onEscape?()
            return
        }
        super.keyDown(with: event)
    }
}
