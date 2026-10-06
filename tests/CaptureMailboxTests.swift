import Foundation

/// PERF-04：旧系统呈现用的最新一帧邮箱。
/// 硬条件：占用有界（最多一待呈现帧 + 一消费任务）；连续 stop/start 后旧会话的
/// 投递为零；没有首帧也不会凭空搬运。
@main struct CaptureMailboxTests {
    final class ManualQueue: @unchecked Sendable {
        private var tasks: [@Sendable () -> Void] = []
        func schedule(_ work: @escaping @Sendable () -> Void) { tasks.append(work) }
        var count: Int { tasks.count }
        func drainOne() { if !tasks.isEmpty { tasks.removeFirst()() } }
        func drain() { while !tasks.isEmpty { tasks.removeFirst()() } }
    }

    final class Sink<T>: @unchecked Sendable {
        var values: [T] = []
        func append(_ value: T) { values.append(value) }
    }

    static func main() {
        boundedBackpressureTests()
        overwriteKeepsNewestTests()
        stopInvalidatesQueuedTests()
        sessionBoundaryTests()
        consumerChainTests()
        print("PASS: mailbox occupancy is bounded, newest frame wins, stop/start invalidates old sessions")
    }

    static func boundedBackpressureTests() {
        let queue = ManualQueue()
        let seen = Sink<Int>()
        let mailbox = LatestFrameMailbox<Int>(schedule: queue.schedule)
        mailbox.setConsume { seen.append($0) }
        mailbox.start()
        // 主线程被拖住：1000 帧全都压进来，队列一个都不跑。
        for frame in 1...1000 { mailbox.receive(frame) }
        precondition(mailbox.pendingCount == 1, "At most one frame waits")
        precondition(mailbox.peakPending == 1, "peak occupancy stays at one")
        precondition(mailbox.scheduled == 1, "At most one consumer task is queued")
        precondition(queue.count == 1)
        precondition(mailbox.overwritten == 999, "Newer frames overwrite the stale one")
        precondition(seen.values.isEmpty, "Nothing is delivered while the consumer is stuck")
        queue.drain()
        precondition(seen.values == [1000], "Only the newest frame is presented")
        precondition(mailbox.delivered == 1)
        precondition(mailbox.pendingCount == 0)
    }

    static func overwriteKeepsNewestTests() {
        let queue = ManualQueue()
        let seen = Sink<String>()
        let mailbox = LatestFrameMailbox<String>(schedule: queue.schedule)
        mailbox.setConsume { seen.append($0) }
        mailbox.start()
        mailbox.receive("a")
        mailbox.receive("b")
        mailbox.receive("c")
        queue.drain()
        precondition(seen.values == ["c"], "Old frames are dropped, not queued")
        precondition(mailbox.overwritten == 2)
    }

    static func stopInvalidatesQueuedTests() {
        let queue = ManualQueue()
        let seen = Sink<Int>()
        let mailbox = LatestFrameMailbox<Int>(schedule: queue.schedule)
        mailbox.setConsume { seen.append($0) }
        mailbox.start()
        mailbox.receive(1)
        precondition(queue.count == 1)
        mailbox.stop()
        queue.drain()
        precondition(seen.values.isEmpty, "A stopped session must not present its last frame")
        precondition(mailbox.delivered == 0)
        // 停止后到达的帧不再被接收。
        mailbox.receive(2)
        precondition(mailbox.pendingCount == 0)
        precondition(queue.count == 0)
    }

    static func sessionBoundaryTests() {
        let queue = ManualQueue()
        let seen = Sink<Int>()
        let mailbox = LatestFrameMailbox<Int>(schedule: queue.schedule)
        mailbox.setConsume { seen.append($0) }
        // 连续 stop/start：旧会话排队的任务一律作废。
        for frame in 0..<50 {
            mailbox.start()
            mailbox.receive(frame)
            mailbox.stop()
        }
        queue.drain()
        precondition(seen.values.isEmpty, "Frames from old sessions are never delivered")

        mailbox.start()
        mailbox.receive(999)
        queue.drain()
        precondition(seen.values == [999])

        mailbox.stop()
        mailbox.start()
        mailbox.receive(1000)
        queue.drain()
        precondition(seen.values == [999, 1000])
        mailbox.stop()
        mailbox.start()
        mailbox.receive(1001)
        queue.drain()
        precondition(seen.values == [999, 1000, 1001])
    }

    static func consumerChainTests() {
        final class Sink: @unchecked Sendable {
            var seen: [Int] = []
            var injected = false
        }
        let queue = ManualQueue()
        let sink = Sink()
        let mailbox = LatestFrameMailbox<Int>(schedule: queue.schedule)
        mailbox.setConsume { frame in
            sink.seen.append(frame)
            // 消费期间又来一帧：仍由同一条消费链继续，不新增并发。
            if !sink.injected {
                sink.injected = true
                mailbox.receive(99)
            }
        }
        mailbox.start()
        mailbox.receive(1)
        queue.drain()
        precondition(sink.seen == [1, 99], "A frame arriving during consume continues the same chain")
        precondition(mailbox.delivered == 2)
        precondition(mailbox.scheduled == 2, "The chain reschedules itself, never runs two at once")
        precondition(queue.count == 0)
    }
}
