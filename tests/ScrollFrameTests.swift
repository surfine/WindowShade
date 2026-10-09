import Cocoa

@main
struct ScrollFrameTests {
    nonisolated(unsafe) static var failures = 0
    static func expect(_ condition: Bool, _ message: String) {
        if condition { print("ok   \(message)") } else { failures += 1; print("FAIL \(message)") }
    }

    static func main() {
        framesMatchOldImplementation()
        MainActor.assumeIsolated { _ = NSApplication.shared }
        MainActor.assumeIsolated { linkSurvivesConcurrentStop() }
        print(failures == 0 ? "all scroll frame tests passed" : "\(failures) failure(s)")
        if failures > 0 { exit(1) }
    }

    // 旧实现（emitFrame 里在锁内的那段）原样抄在这里当参照。
    struct Legacy {
        var remainderX = 0.0, remainderY = 0.0, began = false
        mutating func frame(_ session: inout ScrollSession, at now: WS2.Instant) -> ScrollFrameAccumulator.Frame? {
            let bg = Int64(NSEvent.Phase.began.rawValue)
            let ch = Int64(NSEvent.Phase.changed.rawValue)
            guard case .smooth(let x, let y, let finished) = session.step(at: now) else { return nil }
            remainderX += x
            remainderY += y
            let wholeX = remainderX.rounded(.towardZero)
            let wholeY = remainderY.rounded(.towardZero)
            remainderX -= wholeX
            remainderY -= wholeY
            let px = Int32(clamping: Int(wholeX))
            let py = Int32(clamping: Int(wholeY))
            let phase = began ? ch : bg
            if px != 0 || py != 0 { began = true }
            let endPhase = finished && began
            if finished { began = false; remainderX = 0; remainderY = 0 }
            return .init(x: px, y: py, phase: phase, finished: finished, endPhase: endPhase)
        }
    }

    static func wheel() -> InputDeviceClassifier.ScrollEvidence {
        InputDeviceClassifier.ScrollEvidence(
            continuous: false, hasMomentum: false,
            device: InputDeviceClassifier.Device(localToken: "wheel", vendorID: 0x046d, productID: 0xc52b, hidClass: .mouse),
            association: .verifiedPerEvent)
    }

    static func framesMatchOldImplementation() {
        var mismatches = 0
        var compared = 0
        var sawEnd = false
        var sawMotion = false
        for preset in [SmoothScroll.Preset.light, .medium, .trackpadLike] {
            var new = ScrollSession(), old = ScrollSession()
            var acc = ScrollFrameAccumulator(), legacy = Legacy()
            let request = ScrollSession.Request(smooth: preset, invertMouse: false, fine: false, sideButtons: false, foregroundExcluded: false)
            var t: UInt64 = 5_000_000_000
            // 输入序列：竖、横、竖+横、连续多格，中途再来一格。
            let inputs: [(Int, Double, Double)] = [(0, 0, 1), (20, 0, -2), (35, 1, 0), (36, 0, 3), (150, 0, 1), (151, 2, 2)]
            var next = 0
            for frame in 0..<600 {
                if next < inputs.count, inputs[next].0 == frame {
                    let sample = ScrollSession.Sample.scroll(wheel(), notchesX: inputs[next].1, notchesY: inputs[next].2, option: false)
                    let at = WS2.Instant(nanoseconds: t)
                    _ = new.handle(sample, request: request, at: at)
                    _ = old.handle(sample, request: request, at: at)
                    next += 1
                }
                t += 8_333_333
                let at = WS2.Instant(nanoseconds: t)
                let a = acc.advance(&new, at: at)
                let b = legacy.frame(&old, at: at)
                compared += 1
                if a != b { mismatches += 1 }
                if a?.endPhase == true { sawEnd = true }
                if let a, a.x != 0 || a.y != 0 { sawMotion = true }
            }
        }
        expect(mismatches == 0 && compared == 1800, "every frame equals the old implementation (\(compared) frames, 3 presets)")
        expect(sawEnd && sawMotion, "the sequences move and reach the end phase")
    }

    @MainActor static func linkSurvivesConcurrentStop() {
        let box = LoopBox()
        let thread = Thread {
            box.set(CFRunLoopGetCurrent())
            while !box.stopped { _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01)) }
        }
        thread.start()
        while box.runLoop == nil { usleep(1000) }
        let runLoop = box.runLoop!
        let screen = NSScreen.screens.first
        let group = DispatchGroup()
        for _ in 0..<400 {
            let link = ScrollFrameLink(owner: nil)
            if let screen { link.attach(screen: screen, runLoop: runLoop) }
            group.enter()
            DispatchQueue.global().async { link.invalidate(); link.invalidate(); group.leave() }
        }
        // 先停后挂：停掉之后再 attach 不能崩。
        let late = ScrollFrameLink(owner: nil)
        late.invalidate()
        if let screen { late.attach(screen: screen, runLoop: runLoop) }
        group.wait()
        box.stop()
        CFRunLoopWakeUp(runLoop)
        expect(true, "attach racing invalidate 400 times does not crash (screen: \(screen != nil ? "yes" : "none, lifecycle only"))")
    }
}

final class LoopBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _runLoop: CFRunLoop?
    private var _stopped = false
    var runLoop: CFRunLoop? { lock.withLock { _runLoop } }
    var stopped: Bool { lock.withLock { _stopped } }
    func set(_ r: CFRunLoop) { lock.withLock { _runLoop = r } }
    func stop() { lock.withLock { _stopped = true } }
}
