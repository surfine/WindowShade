
// Appended to Glance.swift by the runner to exercise actual session transitions
// without a screen-capture stream, real window, or AX write.
@MainActor private final class LifecycleCarrySource: GlanceCarrySource {
    let frame = NSRect(x: 100, y: 100, width: 260, height: 30)
    /// The strip can outlive the carried window: a target lookup may start
    /// failing while `carriedStripFrame` still answers.
    var target: GlanceTarget?

    init() {
        target = GlanceTarget(strip: frame, panel: frame, card: frame, picture: frame,
                              backdropArea: nil, cornerRadius: 8, source: .snapshotOnly,
                              snapshot: nil, pid: 123_456, bundleID: "test.lifecycle",
                              accessibilityTitle: "test", staleText: "test")
    }

    func carriedStripFrame(_ id: CGWindowID) -> NSRect? { frame }
    func glanceTarget(forCarried id: CGWindowID) -> GlanceTarget? { target }
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

        // The strip can still be on screen while its carried window is no longer
        // carried: opening must not leave the preparing session and intent alive.
        controller.apply(controller.intent.entered(id, at: 1))
        let stale = controller.sessions[id]
        precondition(stale != nil && stale!.stage == .preparing && !stale!.liveExpected)
        let startup = Task { @MainActor () -> Void in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
        }
        stale!.startupTask = startup
        source.target = nil
        controller.apply(controller.intent.sample(GlancePointerSample(strip: id), at: 10))
        precondition(controller.sessions[id] == nil, "Lost target must end the preparing session")
        precondition(stale!.cancelled, "Lost target must tear the session down")
        precondition(startup.isCancelled, "Lost target must cancel the pending startup")
        precondition(!controller.intent.needsSampling)
        precondition(controller.intent.phase == .idle)
        precondition(controller.intent.blocked.isEmpty)
        precondition(!controller.needsTimer, "Nothing left to sample: the timer must stop")
        // Restore the fixture so later scenarios still see a target.
        source.target = LifecycleCarrySource().target
    }
}

@MainActor private final class StagedOpenCarrySource: GlanceCarrySource {
    let frame = NSRect(x: 100, y: 100, width: 260, height: 30)
    var snapshot: CGImage?
    let source: GlanceTarget.Source = .stream

    func carriedStripFrame(_ id: CGWindowID) -> NSRect? { frame }
    func glanceTarget(forCarried id: CGWindowID) -> GlanceTarget? {
        GlanceTarget(strip: frame, panel: frame, card: frame, picture: frame,
                     backdropArea: nil, cornerRadius: 8, source: source,
                     snapshot: snapshot, pid: 123_456, bundleID: "test.lifecycle",
                     accessibilityTitle: "test", staleText: "收起时的画面")
    }
    func openCarriedWindow(_ id: CGWindowID) {}
}

extension GlanceController {
    /// 打开：能马上显示的截图不该陪实时首帧一起等；没有截图才用有界的首帧等待。
    @MainActor static func verifyOpenStaging() {
        let owner = AppDelegate()
        let controller = GlanceController(owner: owner)
        let source = StagedOpenCarrySource()
        controller.carrySource = source
        let id: CGWindowID = 4_100_001
        var now = 10.0
        controller.clock = { now }
        func install() -> GlanceSession {
            let session = GlanceSession(id: id, preparedAt: 1, stripFrame: source.frame,
                                        liveExpected: true, carried: true)
            session.pid = 123_456
            controller.sessions[id] = session
            return session
        }
        func makeImage() -> CGImage {
            let provider = CGDataProvider(data: Data(count: 4 * 4 * 4) as CFData)!
            return CGImage(width: 4, height: 4, bitsPerComponent: 8, bitsPerPixel: 32,
                           bytesPerRow: 16, space: CGColorSpaceCreateDeviceRGB(),
                           bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                           provider: provider, decode: nil, shouldInterpolate: false,
                           intent: .defaultIntent)!
        }

        // 截图已经在手：照常显示，不排队等实时首帧。
        source.snapshot = makeImage()
        let withSnapshot = install()
        controller.open(id)
        precondition(withSnapshot.stage == .shown,
                     "An available snapshot must show without waiting for a live frame")
        precondition(withSnapshot.showDeadline == nil, "Nothing to wait for when a snapshot is ready")
        precondition(withSnapshot.content?.hasSnapshot == true)
        precondition(controller.diagnostics.opens == 1)
        precondition(controller.isShowing)
        controller.finish(withSnapshot, reason: "test-cleanup")
        precondition(controller.sessions[id] == nil)

        // 没有截图：保留有界的首帧等待；清理时待显示的会话整条都要收掉。
        source.snapshot = nil
        now = 20
        let noSnapshot = install()
        controller.open(id)
        precondition(noSnapshot.stage == .waitingForFrame,
                     "A missing snapshot still waits for the live first frame")
        precondition(noSnapshot.showDeadline == now + GlanceController.firstFrameWait)
        precondition(controller.isShowing, "Waiting for a frame still counts as on screen")
        let startup = Task { @MainActor () -> Void in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
        }
        noSnapshot.startupTask = startup
        controller.close(id)
        precondition(controller.sessions[id] == nil, "Cleanup must remove the waiting session")
        precondition(noSnapshot.cancelled && startup.isCancelled)
        precondition(noSnapshot.panel == nil && noSnapshot.content == nil)
    }
}

@main struct GlanceLifecycleTests {
    @MainActor static func main() {
        _ = NSApplication.shared
        GlanceController.verifyLifecycle()
        GlanceController.verifyOpenStaging()
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
