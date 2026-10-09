import Cocoa

// 测试里用不到真实辅助功能：WindowGlide 默认入口依赖的四个函数用桩顶替（实际都经 Ops 注入）。
func axPosition(_ e: AXUIElement) -> CGPoint? { nil }
func axSize(_ e: AXUIElement) -> CGSize? { nil }
func setAXPosition(_ e: AXUIElement, _ p: CGPoint) {}
@discardableResult func setAXSize(_ e: AXUIElement, _ s: CGSize) -> AXError { .success }

// S04：有界等待。WindowListCache 单飞等待 ≤0.5 秒；WindowGlide 取消后不读回、cancelAndWait ≤150 毫秒。

private final class Gate: @unchecked Sendable {
    private let c = NSCondition()
    private var open = false
    private var entered = false
    func block(seconds: TimeInterval) {
        c.lock(); entered = true; c.broadcast()
        let end = Date().addingTimeInterval(seconds)
        while !open, c.wait(until: end) {}
        c.unlock()
    }
    func waitEntered() {
        c.lock(); defer { c.unlock() }
        let end = Date().addingTimeInterval(2)
        while !entered { precondition(c.wait(until: end), "never entered") }
    }
    func release() { c.lock(); open = true; c.broadcast(); c.unlock() }
}

private final class Counter: @unchecked Sendable {
    private let l = NSLock()
    private var n = 0
    func bump() { l.lock(); n += 1; l.unlock() }
    var value: Int { l.lock(); defer { l.unlock() }; return n }
}

private final class Box: @unchecked Sendable {
    var report: WindowGlide.Report?
}

@main
struct BoundedWaitTests {
    static func row(_ id: UInt32) -> [String: Any] {
        [kCGWindowNumber as String: NSNumber(value: id), kCGWindowOwnerPID as String: NSNumber(value: 1)]
    }

    static func elapsed(_ f: () -> Void) -> TimeInterval {
        let t = CFAbsoluteTimeGetCurrent(); f(); return CFAbsoluteTimeGetCurrent() - t
    }

    static func main() {
        // 1) 缓存：第二次刷新卡 5 秒，等待者 ≤0.6 秒拿到旧快照。
        let calls = Counter()
        let gate = Gate()
        let cache = WindowListCache(ttl: 0.01) { _ in
            calls.bump()
            if calls.value == 1 { return [row(7)] }
            gate.block(seconds: 5)
            return [row(9)]
        }
        precondition(cache.onScreenIDs() == [7])
        Thread.sleep(forTimeInterval: 0.05) // 过期
        DispatchQueue.global().async { _ = cache.onScreenIDs() } // 刷新者，卡住
        gate.waitEntered()
        var ids = Set<CGWindowID>()
        let t1 = elapsed { ids = cache.onScreenIDs() }
        precondition(t1 <= 0.6 && t1 >= 0.4, "waiter took \(t1)")
        precondition(ids == [7], "stale snapshot expected, got \(ids)")
        gate.release()

        // 1b) 没有任何快照：返回空。
        let gate2 = Gate()
        let empty = WindowListCache(ttl: 10) { _ in gate2.block(seconds: 5); return [row(1)] }
        DispatchQueue.global().async { _ = empty.onScreenIDs() }
        gate2.waitEntered()
        var emptyIDs: Set<CGWindowID> = [99]
        let t2 = elapsed { emptyIDs = empty.onScreenIDs() }
        precondition(t2 <= 0.6, "empty waiter took \(t2)")
        precondition(emptyIDs.isEmpty)
        gate2.release()

        // 2) Glide：取消后不读回。
        let element = AXUIElementCreateApplication(getpid())
        let path = FlickGlidePath(from: CGRect(x: 0, y: 0, width: 400, height: 300),
                                  to: CGRect(x: 500, y: 300, width: 400, height: 300),
                                  velocity: CGVector(dx: 800, dy: 400))
        let reads = Counter()
        var ops = WindowGlide.Ops()
        ops.setSize = { _, _ in }
        ops.setPosition = { _, _ in Thread.sleep(forTimeInterval: 0.002) }
        ops.readPosition = { _ in reads.bump(); return nil }
        ops.readSize = { _ in reads.bump(); return nil }
        let glide = WindowGlide(id: 1, element: element, path: path, ops: ops)
        let done = DispatchSemaphore(value: 0)
        let box = Box()
        glide.start { r in box.report = r; done.signal() }
        Thread.sleep(forTimeInterval: 0.05)
        glide.cancelAndWait()
        let end = Date().addingTimeInterval(2)
        while done.wait(timeout: .now()) != .success && Date() < end {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        precondition(box.report?.cancelled == true, "should report cancelled")
        precondition(reads.value == 0, "cancelled glide must not read back, reads=\(reads.value)")

        // 3) cancelAndWait 面对阻塞的 set ≤0.2 秒。
        let gate3 = Gate()
        var ops3 = WindowGlide.Ops()
        ops3.setSize = { _, _ in }
        ops3.setPosition = { _, _ in gate3.block(seconds: 5) }
        let g3 = WindowGlide(id: 2, element: element, path: path, ops: ops3)
        g3.start { _ in }
        gate3.waitEntered()
        let t3 = elapsed { g3.cancelAndWait() }
        precondition(t3 <= 0.2, "cancelAndWait took \(t3)")
        gate3.release()
        print("BoundedWaitTests passed (cache waiter \(String(format: "%.2f", t1))s, cancelAndWait \(String(format: "%.3f", t3))s)")
    }
}
