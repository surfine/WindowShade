import Cocoa

private final class Provider: @unchecked Sendable {
    private let condition = NSCondition()
    private var blocked: Set<WindowListCache.Kind> = []
    private var calls: [WindowListCache.Kind: Int] = [:]
    private var values: [WindowListCache.Kind: [[String: Any]]] = [:]
    func set(_ kind: WindowListCache.Kind, _ rows: [[String: Any]], blocked shouldBlock: Bool = false) {
        condition.lock(); defer { condition.unlock() }
        values[kind] = rows
        if shouldBlock { blocked.insert(kind) } else { blocked.remove(kind) }
        condition.broadcast()
    }
    func read(_ kind: WindowListCache.Kind) -> [[String: Any]] {
        condition.lock(); defer { condition.unlock() }
        calls[kind, default: 0] += 1
        condition.broadcast()
        while blocked.contains(kind) { condition.wait() }
        return values[kind] ?? []
    }
    func count(_ kind: WindowListCache.Kind) -> Int {
        condition.lock(); defer { condition.unlock() }
        return calls[kind, default: 0]
    }
    func waitForCall(_ kind: WindowListCache.Kind) {
        condition.lock(); defer { condition.unlock() }
        let deadline = Date().addingTimeInterval(2)
        while calls[kind, default: 0] == 0 {
            precondition(condition.wait(until: deadline), "provider did not start")
        }
    }
}

@main
struct WindowListCacheTests {
    static func row(_ id: UInt32, _ pid: Int32) -> [String: Any] {
        [kCGWindowNumber as String: NSNumber(value: id), kCGWindowOwnerPID as String: NSNumber(value: pid)]
    }
    static func main() {
        // Slow on-screen lookup; all 12 concurrent callers must receive one result.
        let provider = Provider()
        provider.set(.onScreen, [row(1, 10)], blocked: true)
        provider.set(.all, [row(2, 20)])
        let cache = WindowListCache(ttl: 10, provider: provider.read)
        let done = DispatchGroup()
        let started = DispatchGroup()
        for _ in 0..<12 {
            started.enter(); done.enter()
            DispatchQueue.global().async {
                started.leave()
                precondition(cache.onScreenIDs() == [1])
                done.leave()
            }
        }
        precondition(started.wait(timeout: .now() + 2) == .success)
        provider.waitForCall(.onScreen)
        // While onScreen is deliberately blocked, all must finish independently.
        let otherDone = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            precondition(cache.allWindows(ofPID: 20).count == 1)
            otherDone.signal()
        }
        precondition(otherDone.wait(timeout: .now() + 2) == .success, "one kind blocked the other")
        precondition(done.wait(timeout: .now() + 0.15) == .timedOut, "on-screen provider should still be blocked")
        provider.set(.onScreen, [row(1, 10)])
        precondition(done.wait(timeout: .now() + 3) == .success, "not all concurrent waiters woke")
        precondition(provider.count(.onScreen) == 1 && provider.count(.all) == 1)
        precondition(cache.onScreenWindows(ofPID: 10).count == 1 && cache.isOnScreen(1))
        precondition(!cache.isOnScreen(99))

        // The cache must expire, and both the list and its indexes must change together.
        let freshProvider = Provider()
        freshProvider.set(.all, [row(3, 30), row(4, 30), row(5, 50)])
        let expiring = WindowListCache(ttl: 0.1, provider: freshProvider.read)
        precondition(expiring.allWindows().count == 3)
        precondition(expiring.allWindows(ofPID: 30).count == 2)
        precondition(expiring.pidsWithWindows() == [30, 50])
        precondition(freshProvider.count(.all) == 1)
        freshProvider.set(.all, [row(6, 60)])
        Thread.sleep(forTimeInterval: 0.15)
        precondition(expiring.pidsWithWindows() == [60])
        precondition(expiring.allWindows(ofPID: 30).isEmpty)
        precondition(freshProvider.count(.all) == 2)
        print("PASS: WindowListCache — 12 concurrent callers, one refresh, independent kinds, TTL and indexes")
    }
}
