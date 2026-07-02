import Cocoa
import ApplicationServices
import ScreenCaptureKit

enum PinnedPreviewError: Error, LocalizedError {
    case noFocusedWindow
    case ownWindow
    case unsupportedWindow
    case noShareableContent
    case noSCWindow
    case noAXGeometry
    case screenRecordingDenied

    var errorDescription: String? {
        switch self {
        case .noFocusedWindow:
            return "没有可置顶预览的当前窗口"
        case .ownWindow:
            return "WindowShade 自己的窗口不能置顶预览"
        case .unsupportedWindow:
            return "此窗口不能置顶预览"
        case .noShareableContent:
            return "无法读取屏幕内容"
        case .noSCWindow:
            return "无法捕获这个窗口"
        case .noAXGeometry:
            return "无法读取窗口位置"
        case .screenRecordingDenied:
            return "需要屏幕录制权限"
        }
    }
}

private final class PinnedPreviewSession {
    let windowID: CGWindowID
    let pid: pid_t
    let bundleIdentifier: String
    let appName: String
    let title: String
    let axWindow: AXUIElement
    let panel: PinnedPreviewPanel
    let contentView: PinnedPreviewContentView
    let capture: WindowStreamCapture

    var scWindow: SCWindow
    var display: SCDisplay?
    var lastKnownFrame: NSRect
    var isInteracting = false
    var isDucked = false
    var watchdog: Timer?
    var globalMouseMonitor: Any?
    var localMouseMonitor: Any?
    var pendingExit: DispatchWorkItem?

    init(windowID: CGWindowID, pid: pid_t, bundleIdentifier: String, appName: String,
         title: String, axWindow: AXUIElement, scWindow: SCWindow, display: SCDisplay?,
         panel: PinnedPreviewPanel, contentView: PinnedPreviewContentView,
         capture: WindowStreamCapture, lastKnownFrame: NSRect) {
        self.windowID = windowID
        self.pid = pid
        self.bundleIdentifier = bundleIdentifier
        self.appName = appName
        self.title = title
        self.axWindow = axWindow
        self.scWindow = scWindow
        self.display = display
        self.panel = panel
        self.contentView = contentView
        self.capture = capture
        self.lastKnownFrame = lastKnownFrame
    }

    func invalidate() {
        watchdog?.invalidate()
        watchdog = nil
        pendingExit?.cancel()
        pendingExit = nil
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
    }
}

private struct PinnedPreviewTarget {
    let windowID: CGWindowID
    let axWindow: AXUIElement
}

struct PinnedPreviewMenuEntry {
    let id: CGWindowID
    let appName: String
    let title: String

    var displayTitle: String {
        let cleanAppName = cleanDisplayTitle(appName)
        let cleanTitle = cleanDisplayTitle(title)
        if cleanTitle.isEmpty { return cleanAppName.isEmpty ? "未命名窗口" : cleanAppName }
        if cleanAppName.isEmpty { return cleanTitle }
        return "\(cleanAppName) — \(cleanTitle)"
    }
}

final class PinnedPreviewController {
    typealias NoticeHandler = (_ message: String, _ log: String?) -> Void

    private let notice: NoticeHandler
    private let sessionsDidChange: () -> Void
    private var sessions: [CGWindowID: PinnedPreviewSession] = [:]
    private var currentTarget: PinnedPreviewTarget?
    private var pointerDuckingTimer: Timer?
    private var lastPointerDuckingID: CGWindowID?
    private var lockedDuckingID: CGWindowID?
    private var activePreviewID: CGWindowID?
    private let excludedBundleIDs: Set<String> = [
        "com.apple.dock",
        "com.apple.controlcenter",
        "com.apple.notificationcenterui",
        "com.apple.systemuiserver",
        "com.apple.WindowManager"
    ]

    init(notice: @escaping NoticeHandler, sessionsDidChange: @escaping () -> Void) {
        self.notice = notice
        self.sessionsDidChange = sessionsDidChange
    }

    var activePreviewCount: Int {
        sessions.count
    }

    func isPreviewing(id: CGWindowID) -> Bool {
        sessions[id] != nil
    }

    func refreshCurrentTarget(reason: String) {
        guard let win = focusedWindow(), let id = windowID(of: win),
              isUsableTarget(win, id: id) else {
            wlog("pin-preview: target unchanged reason=\(reason) no-usable-focused-window")
            return
        }
        if currentTarget?.windowID != id {
            wlog("pin-preview: target changed reason=\(reason) id=\(id) title=\(cleanDisplayTitle(axTitle(win)))")
        }
        currentTarget = PinnedPreviewTarget(windowID: id, axWindow: win)
    }

    func currentTargetMenuTitle() -> String {
        "置顶当前窗口"
    }

    func canPinCurrentTarget() -> Bool {
        guard let target = currentTarget else { return true }
        return sessions[target.windowID] == nil
    }

    func pinCurrentTargetPreview() {
        guard hasAccessibilityPermission() else {
            notice("需要权限", "pin-preview: failed reason=accessibility")
            return
        }
        guard hasScreenRecordingPermission() else {
            notice("需要屏幕录制权限", "pin-preview: failed reason=screen-recording")
            return
        }
        refreshCurrentTarget(reason: "toggle")
        guard let target = currentTarget else {
            notice("没有可置顶预览窗口", "pin-preview: failed reason=no-focused-window")
            return
        }
        if sessions[target.windowID] != nil {
            notice("窗口已置顶", "pin-preview: skipped reason=already-pinned id=\(target.windowID)")
            return
        }
        startPreview(for: target.axWindow, id: target.windowID)
    }

    func stopAllPreviews(reason: String = "manual") {
        for id in Array(sessions.keys) {
            stopPreview(id: id, reason: reason)
        }
    }

    func menuEntries() -> [PinnedPreviewMenuEntry] {
        sessions.values
            .sorted { lhs, rhs in
                let lhsApp = lhs.appName.localizedCaseInsensitiveCompare(rhs.appName)
                if lhsApp == .orderedSame {
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
                return lhsApp == .orderedAscending
            }
            .map { session in
                PinnedPreviewMenuEntry(id: session.windowID,
                                       appName: session.appName,
                                       title: session.title)
            }
    }

    func stopPreviewFromMenu(id: CGWindowID) {
        stopPreview(id: id, reason: "menu-item")
    }

    func stopPreviews(forPID pid: pid_t, reason: String) {
        for id in sessions.filter({ $0.value.pid == pid }).map(\.key) {
            stopPreview(id: id, reason: reason)
        }
    }

    func refreshAll(reason: String) {
        for id in Array(sessions.keys) {
            watchdogTick(id: id, reason: reason)
        }
    }

    private func startPreview(for axWindow: AXUIElement, id: CGWindowID) {
        do {
            try validateAXWindow(axWindow, id: id)
        } catch {
            notice(error.localizedDescription, "pin-preview: failed reason=\(error.localizedDescription)")
            return
        }

        var pid: pid_t = 0
        AXUIElementGetPid(axWindow, &pid)
        let appName = appDisplayName(pid: pid)
        let bundleID = appBundleID(pid: pid)
        let title = cleanDisplayTitle(axTitle(axWindow))

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let content = try await ShareableContentLoader.current()
                guard let scWindow = content.windows.first(where: { $0.windowID == id }) else {
                    throw PinnedPreviewError.noSCWindow
                }
                let display = Self.bestDisplay(for: scWindow, displays: content.displays)
                self.installPreview(id: id, pid: pid, bundleID: bundleID, appName: appName,
                                    title: title, axWindow: axWindow, scWindow: scWindow,
                                    display: display)
            } catch {
                self.notice(error.localizedDescription,
                            "pin-preview: failed reason=\(error.localizedDescription)")
            }
        }
    }

    private func validateAXWindow(_ axWindow: AXUIElement, id: CGWindowID) throws {
        var pid: pid_t = 0
        guard AXUIElementGetPid(axWindow, &pid) == .success, pid > 0 else {
            throw PinnedPreviewError.unsupportedWindow
        }
        guard pid != getpid() else { throw PinnedPreviewError.ownWindow }
        let bundleID = appBundleID(pid: pid)
        guard !excludedBundleIDs.contains(bundleID) else { throw PinnedPreviewError.unsupportedWindow }
        guard axRole(axWindow) == kAXWindowRole as String else { throw PinnedPreviewError.unsupportedWindow }
        guard let size = axSize(axWindow), size.width >= 80, size.height >= 80 else {
            throw PinnedPreviewError.unsupportedWindow
        }
        guard let info = cgWindowInfo(id), sourceInfoIsUsable(info) else {
            throw PinnedPreviewError.unsupportedWindow
        }
    }

    private func isUsableTarget(_ axWindow: AXUIElement, id: CGWindowID) -> Bool {
        do {
            try validateAXWindow(axWindow, id: id)
            return true
        } catch {
            return false
        }
    }

    private func installPreview(id: CGWindowID, pid: pid_t, bundleID: String,
                                appName: String, title: String, axWindow: AXUIElement,
                                scWindow: SCWindow, display: SCDisplay?) {
        guard sessions[id] == nil else { return }
        guard let frame = currentSourceFrame(id: id) ?? Optional(cocoaFrame(fromWindowServerBounds: scWindow.frame)) else {
            notice("无法读取窗口位置", "pin-preview: failed reason=no-frame id=\(id)")
            return
        }

        let capture = WindowStreamCapture()
        let panel = PinnedPreviewPanel(frame: frame)
        let contentView = PinnedPreviewContentView(videoLayer: capture.videoLayer)
        panel.contentView = contentView

        let session = PinnedPreviewSession(windowID: id, pid: pid, bundleIdentifier: bundleID,
                                           appName: appName, title: title, axWindow: axWindow,
                                           scWindow: scWindow, display: display, panel: panel,
                                           contentView: contentView, capture: capture,
                                           lastKnownFrame: frame)
        contentView.onMouseEntered = { [weak self] in
            self?.beginInteraction(id: id)
        }
        contentView.onMouseMoved = { [weak self] in
            self?.beginInteraction(id: id)
        }
        contentView.onMouseExited = { [weak self] in
            self?.scheduleInteractionExitCheck(id: id)
        }
        contentView.onMouseDown = { [weak self] event in
            self?.passThroughInitialClick(id: id, event: event)
        }
        sessions[id] = session
        panel.orderFrontRegardless()
        startWatchdog(for: session)
        updatePointerDuckingTimer()
        sessionsDidChange()
        wlog("pin-preview: start id=\(id) app=\(appName) title=\(title) frame=\(format(frame))")

        Task { @MainActor [weak self] in
            do {
                try await capture.start(window: scWindow, display: display)
                wlog("pin-preview: capture started id=\(id) size=\(Int(frame.width))x\(Int(frame.height))")
            } catch {
                self?.notice("置顶预览失败", "pin-preview: capture failed id=\(id) \(error.localizedDescription)")
                self?.stopPreview(id: id, reason: "capture-failed")
            }
        }
    }

    private func startWatchdog(for session: PinnedPreviewSession) {
        let timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self, weak session] _ in
            guard let session else { return }
            self?.watchdogTick(id: session.windowID, reason: "watchdog")
        }
        timer.tolerance = 0.05
        session.watchdog = timer
    }

    private func watchdogTick(id: CGWindowID, reason: String) {
        guard let session = sessions[id] else { return }
        guard let frame = currentSourceFrame(id: id) else {
            wlog("pin-preview: closed lost source id=\(id)")
            stopPreview(id: id, reason: "lost-source")
            return
        }
        session.lastKnownFrame = frame
        if session.isInteracting { return }
        guard !framesAlmostEqual(session.panel.frame, frame, tolerance: 1.0) else { return }
        let old = session.panel.frame
        session.panel.setFrame(frame, display: true)
        session.capture.updateSize(width: frame.width, height: frame.height, display: session.display)
        updateDucking(activeID: activeInteractionID())
        wlog("pin-preview: frame changed id=\(id) old=\(format(old)) new=\(format(frame)) reason=\(reason)")
    }

    private func beginInteraction(id: CGWindowID) {
        guard let session = sessions[id], !session.isInteracting, !session.isDucked else { return }
        if let activePreviewID, activePreviewID != id {
            guard let active = sessions[activePreviewID],
                  !active.panel.frame.insetBy(dx: -2, dy: -2).contains(NSEvent.mouseLocation) else {
                return
            }
            endInteraction(id: activePreviewID,
                           sourceFrame: currentSourceFrame(id: activePreviewID) ?? active.panel.frame)
            return
        }
        session.pendingExit?.cancel()
        session.pendingExit = nil
        session.isInteracting = true
        activePreviewID = id
        lockedDuckingID = id
        updateDucking(activeID: id)
        session.capture.stop()
        session.panel.alphaValue = 0.02
        session.panel.hasShadow = false
        session.panel.ignoresMouseEvents = true

        let frame = session.panel.frame
        let targetPosition = axPosition(fromCocoaFrame: frame)
        _ = setAXSize(session.axWindow, frame.size)
        setAXPosition(session.axWindow, targetPosition)
        raiseAXWindow(session.axWindow)
        installMouseMonitorsIfNeeded(for: session)
        wlog("pin-preview: enter interact id=\(id) frame=\(format(frame))")
    }

    private func passThroughInitialClick(id: CGWindowID, event: NSEvent) {
        guard let session = sessions[id] else { return }
        let windowPoint = event.locationInWindow
        let screenRect = session.panel.convertToScreen(NSRect(origin: windowPoint, size: .zero))
        let axPoint = CGPoint(x: screenRect.origin.x,
                              y: coordinateBaselineY() - screenRect.origin.y)

        beginInteraction(id: id)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.012) {
            let source = CGEventSource(stateID: .hidSystemState)
            let down = CGEvent(mouseEventSource: source,
                               mouseType: .leftMouseDown,
                               mouseCursorPosition: axPoint,
                               mouseButton: .left)
            down?.setIntegerValueField(.mouseEventClickState, value: Int64(max(event.clickCount, 1)))
            down?.post(tap: .cghidEventTap)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
                let up = CGEvent(mouseEventSource: source,
                                 mouseType: .leftMouseUp,
                                 mouseCursorPosition: axPoint,
                                 mouseButton: .left)
                up?.setIntegerValueField(.mouseEventClickState, value: Int64(max(event.clickCount, 1)))
                up?.post(tap: .cghidEventTap)
            }
        }
        wlog("pin-preview: pass-through click id=\(id) ax=(\(Int(axPoint.x)),\(Int(axPoint.y)))")
    }

    private func scheduleInteractionExitCheck(id: CGWindowID) {
        guard let session = sessions[id], session.isInteracting else { return }
        session.pendingExit?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.finishInteractionIfMouseOutside(id: id)
        }
        session.pendingExit = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    private func finishInteractionIfMouseOutside(id: CGWindowID) {
        guard activePreviewID == id else { return }
        guard let session = sessions[id], session.isInteracting else { return }
        let frame = currentSourceFrame(id: id) ?? session.panel.frame
        if frame.insetBy(dx: -8, dy: -8).contains(NSEvent.mouseLocation) {
            return
        }
        endInteraction(id: id, sourceFrame: frame)
    }

    private func endInteraction(id: CGWindowID, sourceFrame: NSRect) {
        guard let session = sessions[id], session.isInteracting else { return }
        let wasActive = activePreviewID == id
        session.isInteracting = false
        if wasActive {
            activePreviewID = nil
            lockedDuckingID = nil
        }
        session.pendingExit?.cancel()
        session.pendingExit = nil
        removeMouseMonitors(for: session)
        session.lastKnownFrame = sourceFrame
        session.panel.setFrame(sourceFrame, display: true)
        session.panel.ignoresMouseEvents = false
        session.panel.hasShadow = true
        session.panel.level = .floating
        session.panel.orderFrontRegardless()
        if wasActive {
            updateDucking(activeID: nil)
        }
        Task { @MainActor [weak self, weak session] in
            guard let self, let session else { return }
            do {
                try await session.capture.restart(window: session.scWindow, display: session.display,
                                                  width: sourceFrame.width, height: sourceFrame.height)
                session.panel.alphaValue = 1
                wlog("pin-preview: exit interact id=\(id) frame=\(Self.format(sourceFrame))")
                self.sessionsDidChange()
            } catch {
                self.notice("置顶预览恢复失败",
                            "pin-preview: restart failed id=\(id) \(error.localizedDescription)")
                self.stopPreview(id: id, reason: "restart-failed")
            }
        }
    }

    private func installMouseMonitorsIfNeeded(for session: PinnedPreviewSession) {
        guard session.globalMouseMonitor == nil, session.localMouseMonitor == nil else { return }
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        session.globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            DispatchQueue.main.async {
                self?.scheduleInteractionExitCheck(id: session.windowID)
            }
        }
        session.localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.scheduleInteractionExitCheck(id: session.windowID)
            return event
        }
    }

    private func removeMouseMonitors(for session: PinnedPreviewSession) {
        if let monitor = session.globalMouseMonitor {
            NSEvent.removeMonitor(monitor)
            session.globalMouseMonitor = nil
        }
        if let monitor = session.localMouseMonitor {
            NSEvent.removeMonitor(monitor)
            session.localMouseMonitor = nil
        }
    }

    private func activeInteractionID() -> CGWindowID? {
        if let activePreviewID, sessions[activePreviewID]?.isInteracting == true {
            return activePreviewID
        }
        return nil
    }

    private func updatePointerDuckingTimer() {
        if sessions.count > 1 {
            guard pointerDuckingTimer == nil else { return }
            let timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
                self?.pointerDuckingTick()
            }
            timer.tolerance = 0
            pointerDuckingTimer = timer
        } else {
            pointerDuckingTimer?.invalidate()
            pointerDuckingTimer = nil
            lastPointerDuckingID = nil
            lockedDuckingID = nil
            if activeInteractionID() == nil {
                restoreDuckedPreviews(reason: "single-preview")
            }
        }
    }

    private func pointerDuckingTick() {
        if let activeID = activeInteractionID() {
            lockedDuckingID = activeID
            lastPointerDuckingID = activeID
            updateDucking(activeID: activeID)
            return
        }

        let mouse = NSEvent.mouseLocation
        if let lockedID = lockedDuckingID, let locked = sessions[lockedID] {
            if locked.panel.frame.insetBy(dx: -2, dy: -2).contains(mouse) {
                lastPointerDuckingID = lockedID
                updateDucking(activeID: lockedID)
                return
            }
            lockedDuckingID = nil
        }

        guard let hoverID = pointerHoveredPreviewID() else {
            if lastPointerDuckingID != nil {
                lastPointerDuckingID = nil
                lockedDuckingID = nil
                restoreDuckedPreviews(reason: "pointer-outside")
            }
            return
        }

        lockedDuckingID = hoverID
        lastPointerDuckingID = hoverID
        updateDucking(activeID: hoverID)
    }

    private func pointerHoveredPreviewID() -> CGWindowID? {
        let mouse = NSEvent.mouseLocation
        let hits = sessions.filter { _, session in
            !session.isDucked && session.panel.isVisible && session.panel.frame.contains(mouse)
        }
        return hits.min { lhs, rhs in
            lhs.value.panel.orderedIndex < rhs.value.panel.orderedIndex
        }?.key
    }

    private func updateDucking(activeID: CGWindowID?) {
        guard let activeID, let active = sessions[activeID] else {
            restoreDuckedPreviews(reason: "no-active")
            return
        }

        let activeFrame = active.panel.frame
        if active.isDucked {
            restoreDuckedPreview(active, id: activeID, reason: "active")
        }
        active.panel.level = .floating
        active.panel.orderFrontRegardless()
        for (id, session) in sessions where id != activeID {
            let shouldDuck = activeFrame.intersects(session.panel.frame)
            if shouldDuck, !session.isDucked {
                session.isDucked = true
                session.panel.ignoresMouseEvents = true
                session.panel.orderOut(nil)
                wlog("pin-preview: duck id=\(id) active=\(activeID)")
            } else if !shouldDuck, session.isDucked {
                restoreDuckedPreview(session, id: id, reason: "no-overlap")
            }
        }
    }

    private func restoreDuckedPreviews(reason: String) {
        for (id, session) in sessions where session.isDucked {
            restoreDuckedPreview(session, id: id, reason: reason)
        }
    }

    private func restoreDuckedPreview(_ session: PinnedPreviewSession, id: CGWindowID, reason: String) {
        session.isDucked = false
        guard !session.isInteracting else {
            session.panel.ignoresMouseEvents = true
            return
        }
        session.panel.ignoresMouseEvents = false
        session.panel.level = .floating
        session.panel.orderFrontRegardless()
        wlog("pin-preview: unduck id=\(id) reason=\(reason)")
    }

    private func stopPreview(id: CGWindowID, reason: String) {
        guard let session = sessions.removeValue(forKey: id) else { return }
        session.invalidate()
        session.capture.stop()
        session.panel.close()
        if activePreviewID == id { activePreviewID = nil }
        if lockedDuckingID == id { lockedDuckingID = nil }
        if lastPointerDuckingID == id { lastPointerDuckingID = nil }
        restoreDuckedPreviews(reason: "stop-\(id)")
        updatePointerDuckingTimer()
        sessionsDidChange()
        wlog("pin-preview: stop id=\(id) reason=\(reason)")
    }

    private func currentSourceFrame(id: CGWindowID) -> NSRect? {
        guard let info = cgWindowInfo(id), sourceInfoIsUsable(info), let bounds = cgWindowBounds(info) else {
            return nil
        }
        return cocoaFrame(fromWindowServerBounds: bounds)
    }

    private func sourceInfoIsUsable(_ info: [String: Any]) -> Bool {
        let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
        guard layer == 0 else { return false }
        let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
        guard alpha > 0.05 else { return false }
        guard let bounds = cgWindowBounds(info), bounds.width >= 80, bounds.height >= 80 else { return false }
        return true
    }

    private static func bestDisplay(for window: SCWindow, displays: [SCDisplay]) -> SCDisplay? {
        func area(_ display: SCDisplay) -> CGFloat {
            let hit = display.frame.intersection(window.frame)
            return hit.isNull ? 0 : hit.width * hit.height
        }
        return displays.max { area($0) < area($1) }
    }

    private static func format(_ frame: NSRect) -> String {
        "(\(Int(frame.minX)),\(Int(frame.minY)) \(Int(frame.width))x\(Int(frame.height)))"
    }

    private func format(_ frame: NSRect) -> String {
        Self.format(frame)
    }
}
