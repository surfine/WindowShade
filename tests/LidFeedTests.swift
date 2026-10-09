// 铰链读数在 lid 队列上消化（F05）：不接硬件，直接往 LidFeed 里喂合成读数。
// 要证明的：
// - 每一份读数都照喂 LidGesture（基线学习的语义不变），结果和单线程直接喂完全一致；
// - 盖子静止 3 秒，主线程回调 0 次；
// - phase 一变立刻回主线程；进度变了才回；有人要每份读数（设置窗口、锁屏覆盖层）时每份都回；
// - 屏熄 / 屏亮和读数在同一条队列上串行；
// - 读数源已经停了（token 失效）的投递被丢掉，丢掉之后下一份读数会补投，不会漏掉阶段变化。
import Foundation

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var snapshots: [LidSnapshot] = []
    private var threads: [Bool] = []
    func add(_ snapshot: LidSnapshot) {
        lock.withLock {
            snapshots.append(snapshot)
            threads.append(Thread.isMainThread)
        }
    }
    var all: [LidSnapshot] { lock.withLock { snapshots } }
    var count: Int { lock.withLock { snapshots.count } }
    var allOnMain: Bool { lock.withLock { threads.allSatisfy { $0 } } }
}

final class Switch: @unchecked Sendable {
    private let lock = NSLock()
    private var on = true
    var value: Bool { get { lock.withLock { on } } set { lock.withLock { on = newValue } } }
}

@main
struct LidFeedTests {
    nonisolated(unsafe) static var failures = 0
    static func expect(_ condition: Bool, _ message: String) {
        if condition { print("ok   \(message)") } else { failures += 1; print("FAIL \(message)") }
    }

    /// 让队列上排着的活和随后 async 到主线程的回调都跑完。
    static func settle(_ queue: DispatchQueue) {
        queue.sync {}
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
    }

    static func reading(_ angle: Double, _ time: Double) -> LidAngleSource.Reading {
        LidAngleSource.Reading(angle: angle, time: time, readMilliseconds: 0)
    }

    /// 一段「稳在 100° 然后往下合」的角度序列，时间按 10Hz 走。
    static func closingScript() -> [(Double, Double)] {
        var script: [(Double, Double)] = []
        var t = 0.0
        for _ in 0..<30 { script.append((100, t)); t += 0.1 }          // 静止 3 秒
        for angle in stride(from: 99.0, through: 60.0, by: -3) { script.append((angle, t)); t += 0.1 }
        return script
    }

    static func main() {
        let queue = DispatchQueue(label: "test.lid")

        // 1. 盖子静止 3 秒：主线程回调 0 次，但读数一份都没落下。
        do {
            let feed = LidFeed(queue: queue)
            let counter = Counter()
            feed.setHandler { counter.add($0) }
            for i in 0..<30 {
                queue.async { feed.ingest(reading(100, Double(i) * 0.1), token: 1) }
            }
            settle(queue)
            expect(counter.count == 0, "盖子静止 3 秒，主线程回调 \(counter.count) 次（应为 0）")
            let snap = feed.snapshot()
            expect(snap.angle == 100 && snap.readingTime > 0, "静止时对外的角度和读数时间仍然每份都更新")
            expect(snap.baseline == 100, "基线照常学到静止角度")
        }

        // 2. 结果和单线程直接喂完全一致（每一份读数都喂了，语义不变）。
        do {
            let feed = LidFeed(queue: queue)
            let counter = Counter()
            feed.setHandler { counter.add($0) }
            var reference = LidGesture()
            for (angle, time) in closingScript() {
                reference.feed(angle, at: time)
                queue.async { feed.ingest(reading(angle, time), token: 1) }
            }
            settle(queue)
            let snap = feed.snapshot()
            expect(snap.phase == reference.phase && snap.progress == reference.progress
                   && snap.baseline == reference.baseline && snap.restBeforeClose == reference.restBeforeClose,
                   "和直接喂 LidGesture 的结果一致（phase \(snap.phase)，progress \(String(format: "%.2f", snap.progress))）")
            expect(counter.allOnMain, "回调都在主线程")
            expect(counter.all.first?.phase == .following, "第一次回调就是 phase 变成 following")
            expect(counter.all.dropFirst().allSatisfy { $0.phase == .following }, "之后每次回调都带着新的进度")
            let progresses = counter.all.map(\.progress)
            expect(zip(progresses, progresses.dropFirst()).allSatisfy { $0 != $1 }, "回调只在进度变了的时候来，没有重复值")
            expect(counter.last?.progress == snap.progress, "最后一次回调就是当前进度")
        }

        // 3. phase 一变立刻回调：这一份读数一到就投递，不等下一份、不攒批。
        do {
            let feed = LidFeed(queue: queue)
            let counter = Counter()
            feed.setHandler { counter.add($0) }
            for i in 0..<12 { queue.async { feed.ingest(reading(100, Double(i) * 0.1), token: 1) } }
            queue.async { feed.ingest(reading(99, 1.2), token: 1) }
            queue.async { feed.ingest(reading(90, 1.3), token: 1) }
            settle(queue)
            expect(counter.count == 0, "还没跌到触发点，不回调")
            queue.async { feed.ingest(reading(84, 1.4), token: 1) }   // 基线 100，跌 16° 且还在往下
            let started = Date()
            var arrived: TimeInterval?
            while Date().timeIntervalSince(started) < 1 {
                RunLoop.main.run(until: Date().addingTimeInterval(0.005))
                if counter.count > 0 { arrived = Date().timeIntervalSince(started); break }
            }
            expect(arrived != nil && arrived! < 0.1, "phase 变成 following 的回调立刻到（\(arrived.map { String(format: "%.0f", $0 * 1000) } ?? "-") ms）")
            expect(counter.all.first?.phase == .following, "回调里的 phase 是 following")
        }

        // 4. 有人要每份读数：静止也每份都回（设置窗口开着、锁屏覆盖层在读进度）。
        do {
            let feed = LidFeed(queue: queue)
            let counter = Counter()
            feed.setHandler { counter.add($0) }
            feed.setDemand(true)
            for i in 0..<10 { queue.async { feed.ingest(reading(100, Double(i) * 0.1), token: 1) } }
            settle(queue)
            expect(counter.count == 10, "要每份读数时静止也每份都回（\(counter.count)/10）")
            feed.setDemand(false)
            for i in 10..<20 { queue.async { feed.ingest(reading(100, Double(i) * 0.1), token: 1) } }
            settle(queue)
            expect(counter.count == 10, "不要了之后又安静下来")
        }

        // 5. displayOff / displayOn 和读数在同一条队列上，顺序固定。
        do {
            let feed = LidFeed(queue: queue)
            let counter = Counter()
            feed.setHandler { counter.add($0) }
            var reference = LidGesture()
            var script = closingScript()
            script.append((20, 4.2))
            for (angle, time) in script {
                reference.feed(angle, at: time)
                queue.async { feed.ingest(reading(angle, time), token: 1) }
            }
            reference.displayOff()
            feed.displayOff()
            // 屏熄之后来的读数在 dark 里不动进度。
            reference.feed(10, at: 4.3)
            queue.async { feed.ingest(reading(10, 4.3), token: 1) }
            let startedBox = Counter()
            let startedFlag = Switch()
            let expectedStart = reference.displayOn(at: 5.0)
            feed.displayOn(at: 5.0) { started in
                startedFlag.value = started
                startedBox.add(LidSnapshot())
            }
            reference.feed(30, at: 5.1)
            queue.async { feed.ingest(reading(30, 5.1), token: 1) }
            settle(queue)
            expect(startedBox.count == 1 && startedFlag.value == expectedStart && expectedStart,
                   "displayOn 的结果在主线程交回，并且和直接调用一致")
            let snap = feed.snapshot()
            expect(snap.phase == reference.phase && snap.progress == reference.progress
                   && snap.restBeforeClose == reference.restBeforeClose,
                   "屏熄 / 屏亮夹在读数中间，结果和顺序直接调用一致（phase \(snap.phase)，restBeforeClose \(snap.restBeforeClose.map { String(format: "%.0f", $0) } ?? "-")）")
            expect(counter.all.contains { $0.phase == .following }, "熄屏之后的读数仍会把变化带回主线程")
        }

        // 6. token 失效（读数源已经停了）的投递被丢掉；丢掉之后下一份读数补投，不漏阶段变化。
        do {
            let valid = Switch()
            let feed = LidFeed(queue: queue, accepts: { _ in valid.value })
            let counter = Counter()
            feed.setHandler { counter.add($0) }
            for i in 0..<12 { queue.async { feed.ingest(reading(100, Double(i) * 0.1), token: 1) } }
            valid.value = false
            queue.async { feed.ingest(reading(84, 1.2), token: 1) }
            settle(queue)
            expect(counter.count == 0, "token 失效后的投递被丢掉，主线程不会收到过期的读数")
            valid.value = true
            queue.async { feed.ingest(reading(84, 1.3), token: 2) }
            settle(queue)
            expect(counter.count == 1 && counter.all.first?.phase == .following, "重新有效之后第一份读数补投了被丢掉的阶段变化")
        }

        // 7. 接上真实的读数源（有传感器的机器上）：读数走 lid 队列直达 LidFeed，不再每份都 async 到主线程。
        do {
            let source = LidAngleSource()
            let feed = LidFeed(source: source)
            let counter = Counter()
            feed.setHandler { counter.add($0) }
            source.onQueueReading = { [feed] reading, token in feed.ingest(reading, token: token) }
            let mainReadings = Counter()
            source.onReading = { _ in mainReadings.add(LidSnapshot()) }
            source.start()
            RunLoop.main.run(until: Date().addingTimeInterval(2.5))
            source.stop()
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
            let snap = feed.snapshot()
            if snap.readingTime > 0 {
                expect(mainReadings.count == 0, "接了 onQueueReading 之后，读数源不再把每份读数 async 到主线程")
                expect(snap.angle.map { (0...180).contains($0) } == true, "读数直达 LidFeed（角度 \(snap.angle.map { String(format: "%.0f", $0) } ?? "-")°）")
                expect(counter.count <= 1, "盖子没动，主线程回调 \(counter.count) 次")
            } else {
                print("SKIP: 这台机器 2.5 秒内没有铰链读数，跳过读数源直连那一项")
            }
        }

        if failures == 0 { print("PASS: 铰链读数在 lid 队列消化，只在有变化时回主线程") }
        else { print("FAILED \(failures)"); exit(1) }
    }
}

extension Counter {
    var last: LidSnapshot? { all.last }
}
