import Foundation

private final class Activity {
    private let lock = NSLock()
    private var pids = Set<pid_t>()
    private var background = 0
    private var peak = 0
    private var backgroundPeak = 0

    func enter(_ pid: pid_t, interactive: Bool) {
        lock.withLock {
            precondition(pids.insert(pid).inserted, "Same PID must never execute concurrently")
            if !interactive { background += 1 }
            peak = max(peak, pids.count)
            backgroundPeak = max(backgroundPeak, background)
            precondition(pids.count <= 3 && background <= 2, "AX work must remain bounded")
        }
    }

    func leave(_ pid: pid_t, interactive: Bool) {
        lock.withLock {
            precondition(pids.remove(pid) != nil)
            if !interactive { background -= 1 }
        }
    }

    func verify() {
        lock.withLock {
            precondition(pids.isEmpty && peak == 3 && backgroundPeak == 2)
        }
    }
}

@main
enum MetadataQueueTests {
    @MainActor
    static func main() async {
        // Bound a regression failure instead of leaving CI hung behind a slow job.
        DispatchQueue.global().asyncAfter(deadline: .now() + 15) {
            fatalError("Metadata queue test timed out")
        }
        let queue = WindowBrowserMetadataQueue()
        let activity = Activity()
        let slow = DispatchSemaphore(value: 0)
        let other = DispatchSemaphore(value: 0)
        let events = AsyncStream<String>.makeStream()
        var iterator = events.stream.makeAsyncIterator()
        var seen = Set<String>()
        func awaitEvent(_ name: String) async {
            while !seen.contains(name), let event = await iterator.next() {
                seen.insert(event)
            }
            precondition(seen.contains(name))
        }
        func submit(_ pid: pid_t, _ name: String, interactive: Bool = false,
                    gate: DispatchSemaphore? = nil) {
            queue.submit(pid: pid, isInteractive: interactive) {
                activity.enter(pid, interactive: interactive)
                events.continuation.yield("\(name)-start")
                if let gate {
                    precondition(gate.wait(timeout: .now() + 10) == .success)
                }
                activity.leave(pid, interactive: interactive)
                events.continuation.yield("\(name)-end")
            }
        }

        submit(1, "slow", gate: slow)
        await awaitEvent("slow-start")
        submit(2, "fast")
        await awaitEvent("fast-end")
        precondition(!seen.contains("slow-end"), "Fast app must not wait for the slow app")
        submit(3, "other", gate: other)
        await awaitEvent("other-start")

        // A request promoted from background to Dock (or recreated after stop)
        // must still wait for its PID, without blocking a different Dock target.
        submit(1, "same-app", interactive: true)
        submit(4, "queued-background")
        submit(5, "dock", interactive: true)
        await awaitEvent("dock-end")
        precondition(!seen.contains("same-app-start") && !seen.contains("queued-background-start"))

        slow.signal()
        other.signal()
        for name in ["slow-end", "other-end", "same-app-end", "queued-background-end"] {
            await awaitEvent(name)
        }
        activity.verify()
        print("PASS: slow-app isolation, two background workers, reserved Dock worker, same-PID cross-queue ordering")
    }
}
