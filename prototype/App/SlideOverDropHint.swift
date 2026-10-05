import Cocoa

/// 标题栏拖窗的显式落点。内缩避开系统平铺，短暂停留避免抢走普通甩动。
@MainActor
final class SlideOverDropHint {
    struct Target {
        let side: SlideOverController.Side
        let screen: NSScreen
        let rect: CGRect
    }
    private var candidate: (id: CGWindowID, target: Target)?
    private var armed = false
    private var armTask: DispatchWorkItem?
    private var panel: NSPanel?
    private var serial: UInt64 = 0

    static func target(at point: CGPoint) -> Target? {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) else { return nil }
        let visible = screen.visibleFrame
        // 拖动中每个事件都会问一次：先看指针在不在那一小块里，在了才去比对相邻的屏。
        for side in [SlideOverController.Side.left, .right] {
            let rect = CGRect(x: side == .left ? screen.frame.minX + 8 : screen.frame.maxX - 80,
                              y: visible.midY - 110, width: 72, height: 220)
            if rect.contains(point), SlideOverController.neighborFree(side, screen) {
                return Target(side: side, screen: screen, rect: rect)
            }
        }
        return nil
    }

    func isTracking(_ id: CGWindowID) -> Bool { candidate?.id == id }
    var isArmed: Bool { armed }

    func update(id: CGWindowID, at point: CGPoint) {
        guard let target = Self.target(at: point) else { cancel(); return }
        if let old = candidate, old.id == id, old.target.side == target.side,
           old.target.screen == target.screen { return }
        cancel()
        candidate = (id, target)
        show(target, armed: false)
        let request = serial
        let task = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.serial == request, self.candidate?.id == id else { return }
                self.armed = true
                self.show(target, armed: true)
            }
        }
        armTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: task)
    }

    func take(id: CGWindowID, at point: CGPoint) -> Target? {
        defer { cancel() }
        guard armed, let candidate, candidate.id == id, candidate.target.rect.contains(point),
              SlideOverController.neighborFree(candidate.target.side, candidate.target.screen) else { return nil }
        return candidate.target
    }

    func cancel() {
        // 拖动中没碰到落点时每个事件都会走到这里：没东西可收就不去打扰 WindowServer。
        guard candidate != nil || armTask != nil || panel?.isVisible == true else { return }
        serial &+= 1
        armTask?.cancel(); armTask = nil
        candidate = nil; armed = false
        panel?.orderOut(nil)
        ghost?.orderOut(nil)
    }

    private var ghost: NSPanel?

    /// 屏幕边上出现那一小片玻璃和箭头（和收起后留下的一样）；停够了，窗口将要落下的地方出现一个带边框的虚影，
    /// 松手它就滑过去（iPadOS 拖到边上时窗口预览会变成侧拉的样子）。
    private func show(_ target: Target, armed: Bool) {
        let panel: NSPanel
        if let existing = self.panel { panel = existing } else {
            panel = Self.overlay()
            panel.hasShadow = true
            panel.contentView = SlideOverDropView()
            self.panel = panel
        }
        let tab = NSSize(width: 20, height: 104)
        let x = target.side == .left ? target.screen.frame.minX : target.screen.frame.maxX - tab.width
        panel.setFrame(NSRect(x: x, y: target.rect.midY - tab.height / 2, width: tab.width, height: tab.height), display: true)
        let view = panel.contentView as! SlideOverDropView
        view.side = target.side; view.armed = armed; view.needsDisplay = true
        panel.orderFrontRegardless()
        guard armed, let id = candidate?.id, let destination = destination(of: id, target: target) else {
            ghost?.orderOut(nil)
            return
        }
        let ghost = self.ghost ?? Self.overlay()
        if ghost.contentView == nil {
            let host = SlideOverRingHost(frame: .zero)
            host.ring.fillsWindow = true
            ghost.contentView = host
        }
        self.ghost = ghost
        let t = SlideOverChrome.thickness + 26
        ghost.setFrame(destination.insetBy(dx: -t, dy: -t), display: true)
        (ghost.contentView as? SlideOverRingHost)?.ring.dark =
            NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        ghost.alphaValue = 0
        ghost.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Motion.fadeDuration
            ghost.animator().alphaValue = 1
        }
    }

    /// 这扇窗口侧拉后会落在哪（Cocoa 坐标）：和进入侧拉时算的一样。
    private func destination(of id: CGWindowID, target: Target) -> NSRect? {
        guard let info = cgWindowInfo(id), let bounds = cgWindowBounds(info) else { return nil }
        let frame = SlideOverController.dockedFrame(width: min(bounds.width, target.screen.visibleFrame.width * 0.4),
                                                    height: bounds.height, side: target.side, on: target.screen)
        return cocoaFrame(fromAXPosition: frame.origin, size: frame.size)
    }

    private static func overlay() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear
        panel.hasShadow = false; panel.level = .floating
        panel.ignoresMouseEvents = true; panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.animationBehavior = .none
        return panel
    }
}

private final class SlideOverDropView: NSView {
    var side = SlideOverController.Side.left
    var armed = false
    override func draw(_ dirtyRect: NSRect) {
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        SlideOverEdgeTab.draw(in: bounds, side: side, highlighted: armed, dark: dark)
    }
}
