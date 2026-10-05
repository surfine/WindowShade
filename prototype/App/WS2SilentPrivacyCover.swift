// WindowShade 2.1 · 静音「方便遮一下」：逐屏不透明遮罩，观察可见窗口才算回执。
// 不是系统锁屏，也不宣称 loginwindow 隔离强度。Esc 或再次清除会撤掉。
import Cocoa

@MainActor
final class WS2SilentPrivacyCoverController {
    struct Observation: Equatable, Sendable {
        var requestedScreenCount: Int
        var visibleOverlayCount: Int

        var overlayCreated: Bool { visibleOverlayCount > 0 }
        var allScreensCovered: Bool {
            requestedScreenCount > 0 && visibleOverlayCount >= requestedScreenCount
        }
        var missingScreens: Bool {
            requestedScreenCount == 0 || visibleOverlayCount < requestedScreenCount
        }
    }

    private var panels: [CGDirectDisplayID: NSPanel] = [:]
    private var escapeMonitor: Any?

    var observation: Observation {
        let requested = panels.count
        let visible = panels.values.filter(\.isVisible).count
        return Observation(requestedScreenCount: requested, visibleOverlayCount: visible)
    }

    /// 在当前所有屏上铺不透明黑层；返回此刻观察到的可见遮罩数量。
    @discardableResult
    func coverAllScreens() -> Observation {
        clear()
        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            return Observation(requestedScreenCount: 0, visibleOverlayCount: 0)
        }
        for screen in screens {
            let id = displayID(for: screen)
            let panel = makePanel(on: screen)
            panel.orderFrontRegardless()
            panels[id] = panel
        }
        installEscapeMonitor()
        return observation
    }

    func clear() {
        removeEscapeMonitor()
        for panel in panels.values {
            panel.orderOut(nil)
            panel.close()
        }
        panels.removeAll()
    }

    private func makePanel(on screen: NSScreen) -> NSPanel {
        let panel = NSPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        panel.setFrame(screen.frame, display: false)
        panel.isOpaque = true
        panel.backgroundColor = .black
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.hidesOnDeactivate = false
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 2)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        panel.contentView = view
        return panel
    }

    private func displayID(for screen: NSScreen) -> CGDirectDisplayID {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?
            .uint32Value ?? 0
    }

    private func installEscapeMonitor() {
        removeEscapeMonitor()
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            self?.clear()
            return nil
        }
    }

    private func removeEscapeMonitor() {
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
            self.escapeMonitor = nil
        }
    }

}
