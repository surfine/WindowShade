import Foundation
import CoreGraphics

@main struct SlideOverMotionTests {
    static func wait(_ gate: DispatchSemaphore) {
        precondition(gate.wait(timeout: .now() + 2) == .success, "writer timed out")
    }
    static func main() {
        // Left/right paths are mirrors; partial opening preserves the grab offset.
        for start: CGFloat in [800, 950, 1200] {
            for delta: CGFloat in [-200, 0, 30, 100, 500] {
                let right = SlideOverMotion.position(start: start, inward: delta, open: 800, parked: 1200)
                let left = SlideOverMotion.position(start: 1000 - start, inward: delta, open: 200, parked: -200)
                precondition(abs(right + left - 1000) < 0.001)
            }
            precondition(SlideOverMotion.position(start: start, inward: 0, open: 800, parked: 1200) == start)
        }
        let justPast = SlideOverMotion.position(start: 800, inward: 0.001, open: 800, parked: 1200)
        let farPast = SlideOverMotion.position(start: 800, inward: 10000, open: 800, parked: 1200)
        precondition(abs(justPast - 800) < 0.001 && farPast > 760 && farPast < justPast)
        precondition(!SlideOverMotion.willHide(position: 1000, velocity: 0, open: 800, parked: 1200))
        precondition(SlideOverMotion.willHide(position: 1001, velocity: 0, open: 800, parked: 1200))
        precondition(SlideOverMotion.willHide(position: 950, velocity: 900, open: 800, parked: 1200))
        precondition(!SlideOverMotion.willHide(position: 1050, velocity: -900, open: 800, parked: 1200))

        let lock = NSLock()
        var values: [CGFloat] = []
        var prepared = false
        let first = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0), second = DispatchSemaphore(value: 0)
        let writer = SlideOverDragWriter(prepare: { lock.lock(); prepared = true; lock.unlock() }, apply: { point in
            lock.lock(); precondition(prepared); values.append(point.x); let count = values.count; lock.unlock()
            if count == 1 { first.signal(); wait(release) } else { second.signal() }
        })
        writer.submit(CGPoint(x: 1, y: 0)); wait(first)
        for n in 2...100 { writer.submit(CGPoint(x: n, y: 0)) }
        release.signal(); wait(second); writer.stopAndWait()
        lock.lock(); precondition(values == [1, 100]); lock.unlock()

        let inFlight = DispatchSemaphore(value: 0), unblock = DispatchSemaphore(value: 0), finished = DispatchSemaphore(value: 0)
        var applied = 0, leftApply = false
        let cancel = SlideOverDragWriter(apply: { _ in
            lock.lock(); applied += 1; lock.unlock()
            inFlight.signal(); wait(unblock)
            lock.lock(); leftApply = true; lock.unlock()
        })
        cancel.submit(.zero); wait(inFlight)
        cancel.submit(CGPoint(x: 100, y: 0))
        cancel.stop {
            lock.lock(); precondition(leftApply && applied == 1); lock.unlock(); finished.signal()
        }
        precondition(finished.wait(timeout: .now()) == .timedOut, "completion cannot overtake an in-flight write")
        cancel.submit(CGPoint(x: 200, y: 0)); unblock.signal(); wait(finished)
        cancel.stopAndWait()
        print("PASS SlideOver: mirrored direct motion, resistance, reversal, coalescing, stop barrier and prepare ordering")
    }
}
