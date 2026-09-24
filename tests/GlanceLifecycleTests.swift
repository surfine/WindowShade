
// Appended to Glance.swift by the runner to exercise actual session transitions
// without a screen-capture stream, real window, or AX write.
@MainActor private final class LifecycleCarrySource: GlanceCarrySource {
    let frame = NSRect(x: 100, y: 100, width: 260, height: 30)
    func carriedStripFrame(_ id: CGWindowID) -> NSRect? { frame }
    func glanceTarget(forCarried id: CGWindowID) -> GlanceTarget? {
        GlanceTarget(strip: frame, panel: frame, card: frame, picture: frame,
                     backdropArea: nil, cornerRadius: 8, source: .snapshotOnly,
                     snapshot: nil, pid: 123_456, bundleID: "test.lifecycle",
                     accessibilityTitle: "test", staleText: "test")
    }
    func openCarriedWindow(_ id: CGWindowID) {}
}

extension GlanceController {
    @MainActor static func verifyLifecycle() {
        let owner = AppDelegate()
        let controller = GlanceController(owner: owner)
        let source = LifecycleCarrySource()
        controller.carrySource = source
        controller.clock = { 10 }
        let id: CGWindowID = 4_000_001
        func install() -> GlanceSession {
            let session = GlanceSession(id: id, preparedAt: 1, stripFrame: source.frame,
                                        liveExpected: true, carried: false)
            session.pid = 123_456
            session.viaUnhide = true
            controller.sessions[id] = session
            return session
        }

        // Leaving a hidden-app glance stops its capture. Reentering must not
        // retain its historical first-frame flag or the already-hidden source.
        let stopped = install()
        stopped.stage = .closing
        stopped.frontmostBeforeUnhide = 999
        stopped.unhideAt = 1
        stopped.unhiddenAt = 2
        stopped.firstFrameAt = 3
        stopped.rehiddenAt = 4
        controller.prepare(id)
        let replacement = controller.sessions[id]!
        precondition(replacement !== stopped && stopped.cancelled)
        precondition(replacement.stage == .preparing && !replacement.hasLiveFrame)
        precondition(replacement.frontmostBeforeUnhide == nil && replacement.rehiddenAt == nil)
        // A delayed completion from the old animation cannot remove this one.
        controller.finish(stopped, reason: "old-animation-completion")
        precondition(controller.sessions[id] === replacement)
        controller.finish(replacement, reason: "test-cleanup")

        // An ordinary stream that is merely rolling up can still be reused.
        let rolling = install()
        rolling.viaUnhide = false
        rolling.stage = .closing
        controller.prepare(id)
        precondition(controller.sessions[id] === rolling && rolling.stage == .shown)
        controller.finish(rolling, reason: "test-cleanup")

        // Switching to an unrelated app does not transfer ownership. Switching
        // to the temporarily revealed app clears the hold BEFORE restoring it.
        let active = install()
        active.stage = .shown
        active.frontmostBeforeUnhide = 999
        active.unhideAt = 1
        active.unhiddenAt = 2
        controller.revealHoldUntil[id] = 100
        _ = controller.intent.clicked(id, at: 1)
        var restored: [CGWindowID] = []
        controller.takeOverUnhiddenSessions(for: 888) { restored.append($0) }
        precondition(restored.isEmpty && controller.sessions[id] === active)
        controller.takeOverUnhiddenSessions(for: active.pid) { restoredID in
            precondition(!controller.holdsReveal(restoredID))
            precondition(controller.sessions[restoredID] == nil)
            restored.append(restoredID)
        }
        precondition(restored == [id] && active.cancelled && active.rehiddenAt == nil)
        precondition(!controller.intent.needsSampling)
        controller.cancelAll(reason: "frontmost-app")
        controller.takeOverUnhiddenSessions(for: active.pid) { restored.append($0) }
        precondition(restored == [id], "User takeover restores exactly once")

        // A source not yet temporarily revealed has no ownership to transfer.
        let preparing = install()
        controller.takeOverUnhiddenSessions(for: preparing.pid) { restored.append($0) }
        precondition(controller.sessions[id] === preparing && restored == [id])
        controller.finish(preparing, reason: "test-cleanup")
    }
}

@main struct GlanceLifecycleTests {
    @MainActor static func main() {
        GlanceController.verifyLifecycle()
        let element = AXUIElementCreateApplication(getpid())
        var events: [String] = []
        let opened = CarryController.restoreForOpening(element,
            isMinimized: { _ in true },
            unminimize: { _ in events.append("unminimize"); return .success },
            bringForward: { events.append("front") })
        precondition(opened && events == ["unminimize", "front"])
        events = []
        let failed = CarryController.restoreForOpening(element,
            isMinimized: { _ in true },
            unminimize: { _ in events.append("unminimize"); return .cannotComplete },
            bringForward: { events.append("front") })
        precondition(!failed && events == ["unminimize"], "Do not focus another window after failed restoration")
        events = []
        let visible = CarryController.restoreForOpening(element,
            isMinimized: { _ in false },
            unminimize: { _ in preconditionFailure("No AX write needed for a visible window") },
            bringForward: { events.append("front") })
        precondition(visible && events == ["front"])
        print("GlanceLifecycleTests passed")
    }
}
