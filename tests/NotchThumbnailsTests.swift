// 刘海那排格子上的缩略图（App/NotchThumbnails.swift）：一次抓几张、多久重抓、作废后丢结果。
//
// 独立测试：只编 Core/NotchThumbnailPolicy.swift、App/NotchThumbnails.swift、本文件和 support 里的替身
// （tests/support/NotchThumbnailsShim.swift）。抓图是假的、按需卡住，时间是自己拨的，所以不用等真的 10 秒。
// 结果都从 DispatchQueue.main 交回，主线程上一边等一边抽 RunLoop（同 SwitcherOriginTests 的办法）。
import Cocoa
import CoreGraphics
import Foundation

/// 假的“截图”：记录谁进去了、同时有几个在途，默认卡在一道门上等测试放行。
private final class CaptureProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let gate = DispatchSemaphore(value: 0)
    private var concurrent = 0
    private var _peak = 0
    private var _entries: [CGWindowID] = []
    private var _counts: [CGWindowID: Int] = [:]
    private var _stills: [(CGWindowID, NotchThumbnailPolicy.StillQuality)] = []
    /// 谁先进 capture 的，按顺序（"tile3" / "still9"），用来看 still 有没有插到排队的格子图前面。
    private var _order: [String] = []
    private var _neverReturnNil: Set<CGWindowID> = []
    private var _gated = true

    /// 每张图都不一样宽，方便验证“换了新图”还是“保留了旧图”。
    private var pictures: [CGWindowID: CGImage] = [:]

    func gateEverything(_ on: Bool) { lock.withLock { _gated = on } }

    func openOne() { gate.signal() }
    func openAll() { for _ in 0..<64 { gate.signal() } }

    var order: [String] { lock.withLock { _order } }
    var peak: Int { lock.withLock { _peak } }
    /// still 抓过哪几扇、什么画质。
    var stills: [(CGWindowID, NotchThumbnailPolicy.StillQuality)] { lock.withLock { _stills } }
    func count(_ id: CGWindowID) -> Int { lock.withLock { _counts[id] ?? 0 } }
    var total: Int { lock.withLock { _entries.count } }

    /// 这个 id 每次抓到的图（同一张一直用，方便按 === 比较）。
    func picture(_ id: CGWindowID) -> CGImage {
        lock.withLock {
            if let existing = pictures[id] { return existing }
            let made = makeImage(side: 4 + Int(id % 5))
            pictures[id] = made
            return made
        }
    }

    func enter(_ id: CGWindowID) {
        lock.withLock {
            concurrent += 1
            _peak = max(_peak, concurrent)
            _entries.append(id)
            _counts[id, default: 0] += 1
            _order.append("tile\(id)")
        }
        if lock.withLock({ _gated }) { gate.wait() }
        lock.withLock { concurrent -= 1 }
    }

    func capture(_ id: CGWindowID) -> CGImage? {
        enter(id)
        // 标记过“这次给 nil”的 id 这一次不给图。
        if lock.withLock({ _neverReturnNil.remove(id) != nil }) { return nil }
        return picture(id)
    }

    func captureStill(_ id: CGWindowID, _ quality: NotchThumbnailPolicy.StillQuality) -> CGImage? {
        lock.withLock {
            _stills.append((id, quality))
            _order.append("still\(id)")
        }
        return picture(id)
    }

    /// 下一次这个 id 的抓图返回 nil（模拟窗口没了、受保护、动画中间）。
    func failOnce(_ id: CGWindowID) { lock.withLock { _ = _neverReturnNil.insert(id) } }

    var stillCount: Int { lock.withLock { _stills.count } }
}

/// 一张小图（默认 4×4）。
private func makeImage(side: Int = 4) -> CGImage {
    let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 0.9, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: side, height: side))
    return context.makeImage()!
}

@main
@MainActor
struct NotchThumbnailsTests {
    static var failures = 0
    static func expect(_ condition: Bool, _ message: String) {
        if condition { print("ok   \(message)") } else { failures += 1; print("FAIL \(message)") }
    }

    /// 一边抽主线程的 RunLoop（结果都从 DispatchQueue.main 交回）一边等到条件成立。
    @discardableResult
    static func spin(upTo seconds: TimeInterval = 5, until condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition() {
            if Date() >= deadline { return false }
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        return true
    }

    /// 拨表用的：测试自己给 NotchThumbnails 一个“现在几点”。
    private final class Clock { var time: CFAbsoluteTime = 1000 }

    private static func make(_ probe: CaptureProbe, _ clock: Clock = Clock(),
                             permitted: Bool = true) -> (NotchThumbnails, Clock) {
        let thumbnails = NotchThumbnails()
        thumbnails.capture = { probe.capture($0) }
        thumbnails.captureStill = { probe.captureStill($0, $1) }
        thumbnails.now = { clock.time }
        thumbnails.permitted = { permitted }
        return (thumbnails, clock)
    }

    static func main() {
        deliversEachRequestedImage()
        freshnessWindow()
        backwardsClockRefreshes()
        atMostTwoCapturesAtOnce()
        noDuplicateCaptureForIdInFlight()
        invalidateDropsLateResults()
        pruneKeepsGivenIds()
        withoutPermission()
        nilCaptureKeepsPreviousPicture()
        stillRunsBeforeQueuedTiles()

        print(failures == 0
              ? "all notch thumbnail tests passed"
              : "\(failures) failure(s)")
        if failures > 0 { exit(1) }
    }

    // 1. request([1,2])：每个 id 抓一次，各交回一张图，都在主线程上；之后 image(id) 拿得到。
    static func deliversEachRequestedImage() {
        let probe = CaptureProbe()
        probe.gateEverything(false)
        let (thumbnails, _) = make(probe)
        var delivered: [(CGWindowID, CGImage, Bool)] = []
        thumbnails.onImage = { id, picture in delivered.append((id, picture, Thread.isMainThread)) }

        thumbnails.request([1, 2])
        expect(spin { delivered.count == 2 }, "both images come back")
        expect(Set(delivered.map(\.0)) == [1, 2], "each requested id is captured once and delivered (got \(delivered.map(\.0).sorted()))")
        expect(delivered.allSatisfy(\.2), "images are delivered on the main thread")
        expect(probe.count(1) == 1 && probe.count(2) == 1, "one capture per id (got \(probe.count(1)), \(probe.count(2)))")
        expect(delivered.first(where: { $0.0 == 1 })?.1 === probe.picture(1),
               "the delivered image is the captured one")
        expect(thumbnails.image(1) === probe.picture(1) && thumbnails.image(2) === probe.picture(2),
               "image(id) hands it back afterwards")
    }

    // 2. 10 秒内重 request 不再抓；表拨过 10 秒再抓。
    static func freshnessWindow() {
        let probe = CaptureProbe()
        probe.gateEverything(false)
        let (thumbnails, clock) = make(probe)
        var delivered = 0
        thumbnails.onImage = { _, _ in delivered += 1 }

        thumbnails.request([1, 2])
        expect(spin { delivered == 2 }, "first request delivers")
        expect(probe.total == 2, "first request captures both")

        clock.time += 9.9
        thumbnails.request([1])
        expect(spin(upTo: 0.5) { probe.count(1) > 1 } == false && probe.count(1) == 1,
               "within the TTL nothing is captured again")

        clock.time += 0.2  // 累计 10.1 秒，超过 TTL
        thumbnails.request([1])
        expect(spin { probe.count(1) == 2 }, "past the TTL it captures again")
        expect(spin { delivered == 3 }, "and delivers the fresh one")
    }

    // 2b. 表往回拨（手动改时间、唤醒后校时）：缓存时间晚于此刻，算不新鲜，重抓。
    static func backwardsClockRefreshes() {
        let probe = CaptureProbe()
        probe.gateEverything(false)
        let (thumbnails, clock) = make(probe)
        var delivered = 0
        thumbnails.onImage = { _, _ in delivered += 1 }

        thumbnails.request([1])
        expect(spin { delivered == 1 }, "the first picture arrives")
        expect(probe.count(1) == 1, "captured once")

        clock.time -= 5  // 表往回拨：现在早于缓存时刻
        thumbnails.request([1])
        expect(spin { probe.count(1) == 2 },
               "a backwards clock makes the cached picture stale (got \(probe.count(1)))")
        expect(spin { delivered == 2 }, "and the recaptured picture is delivered")
    }

    // 3. 同时最多 2 张在途：6 个 id 一起要，最多两张同时进 capture。
    static func atMostTwoCapturesAtOnce() {
        let probe = CaptureProbe()  // 默认卡住所有抓图
        let (thumbnails, _) = make(probe)
        var delivered = 0
        thumbnails.onImage = { _, _ in delivered += 1 }

        thumbnails.request([1, 2, 3, 4, 5, 6])
        expect(spin { probe.peak == NotchThumbnailPolicy.maxInFlight },
               "two captures run at once (got \(probe.peak))")
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        expect(probe.total == 2, "with two busy, the other four wait (got \(probe.total))")
        expect(probe.peak == 2, "never more than \(NotchThumbnailPolicy.maxInFlight) in flight")

        probe.openAll()
        expect(spin { delivered == 6 }, "all six finish once unblocked (got \(delivered))")
        expect(probe.peak <= NotchThumbnailPolicy.maxInFlight, "still never more than two at once (peak \(probe.peak))")
        expect(thumbnails.image(6) != nil, "and every tile has a picture")
    }

    // 4. 一个 id 还在路上时再要一次，不会抓第二遍。
    static func noDuplicateCaptureForIdInFlight() {
        let probe = CaptureProbe()
        let (thumbnails, _) = make(probe)
        var delivered = 0
        thumbnails.onImage = { _, _ in delivered += 1 }

        thumbnails.request([1])
        expect(spin { probe.count(1) == 1 }, "the first capture starts")
        thumbnails.request([1])
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        expect(probe.count(1) == 1, "asking again while it is in flight does not start a second capture")
        expect(delivered == 0, "nothing delivered while it is still blocked")

        probe.openAll()
        expect(spin { delivered == 1 }, "the one capture delivers once")
        expect(probe.count(1) == 1, "exactly one capture in all")
    }

    // 5. 在途时 invalidate()：晚到的结果丢掉；之后再要，会重新抓。
    static func invalidateDropsLateResults() {
        let probe = CaptureProbe()
        let (thumbnails, _) = make(probe)
        var delivered: [CGWindowID] = []
        thumbnails.onImage = { id, _ in delivered.append(id) }

        thumbnails.request([1, 2])
        expect(spin { probe.count(1) == 1 && probe.count(2) == 1 },
               "both captures are in flight and blocked")
        expect(delivered.isEmpty, "nothing delivered yet")

        thumbnails.invalidate()
        probe.openAll()  // 晚到的结果现在回来
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        expect(delivered.isEmpty, "results that were in flight are dropped (no onImage)")
        expect(thumbnails.image(1) == nil && thumbnails.image(2) == nil, "and nothing is cached")

        thumbnails.request([1])
        expect(spin { delivered == [1] }, "a later request captures again and delivers")
        expect(thumbnails.image(1) != nil, "the new picture is in")
        expect(probe.count(1) == 2, "the new request really did capture again (got \(probe.count(1)))")
    }

    // 6. prune(keeping:)：只留还在的那几格。
    static func pruneKeepsGivenIds() {
        let probe = CaptureProbe()
        probe.gateEverything(false)
        let (thumbnails, _) = make(probe)
        var delivered = 0
        thumbnails.onImage = { _, _ in delivered += 1 }

        thumbnails.request([1, 2, 3])
        expect(spin { delivered == 3 }, "three pictures in")
        thumbnails.prune(keeping: [1, 3])
        expect(thumbnails.image(1) != nil && thumbnails.image(3) != nil && thumbnails.image(2) == nil,
               "prune keeps only the given ids")
        thumbnails.prune(keeping: [])
        expect(thumbnails.image(1) == nil && thumbnails.image(3) == nil, "pruning to nothing empties the row")
    }

    // 7. 没有屏幕录制权限：一张都不抓；still 立刻拿 nil。
    static func withoutPermission() {
        let probe = CaptureProbe()
        probe.gateEverything(false)
        let (thumbnails, _) = make(probe, permitted: false)
        var delivered = 0
        thumbnails.onImage = { _, _ in delivered += 1 }

        thumbnails.request([1, 2, 3])
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        expect(probe.total == 0, "without screen recording permission no capture is started (got \(probe.total))")
        expect(delivered == 0, "and nothing is delivered")

        var stillArrived = false
        var still: CGImage?
        var onMain = false
        thumbnails.still(1, quality: .full) { picture in
            still = picture; onMain = Thread.isMainThread; stillArrived = true
        }
        expect(spin { stillArrived }, "still() replies without waiting for any capture")
        expect(still == nil, "without permission a still is nil")
        expect(onMain, "the nil still is handed back on the main thread")
        expect(probe.stillCount == 0, "and it never asked for a picture")
    }

    // 8. 抓不到（窗口没了）时保留上一张，这条结果不 onImage。
    static func nilCaptureKeepsPreviousPicture() {
        let probe = CaptureProbe()
        probe.gateEverything(false)
        let (thumbnails, clock) = make(probe)
        var delivered: [CGWindowID] = []
        var mainThread = true
        thumbnails.onImage = { id, _ in delivered.append(id); mainThread = mainThread && Thread.isMainThread }

        thumbnails.request([5])
        expect(spin { delivered == [5] }, "the first picture arrives")
        let first = thumbnails.image(5)
        expect(first != nil, "and it is cached")

        clock.time += 30  // 不新鲜了，下次一定会重抓
        probe.failOnce(5)
        thumbnails.request([5])
        expect(spin { probe.count(5) == 2 }, "it does capture again (got \(probe.count(5)))")
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        expect(delivered == [5], "a failed capture is not delivered (got \(delivered.map(String.init)))")
        expect(thumbnails.image(5) === first, "the previous picture is kept unchanged")
        expect(mainThread, "deliveries stayed on the main thread")
    }

    // 9. 格子图都堵在门上时插进来的 still：它先做完，先交回主线程；在途仍然最多 2。
    //
    // 这里靠 OperationQueue 的 queuePriority（still 是 .veryHigh，格子图是默认）挑选下一个开跑的操作。
    // 做法是只放行一张、让一个槽空出来：队列这时只有 still 是高优先，所以它进；它不堵门，当场做完。
    // 于是“still 比还排着队的几张格子图先交回”是确定的。下面同时断言 still 确实排在了前两个格子图之后、
    // 剩下的格子图之前，并在最后放完，验证峰值没超。
    static func stillRunsBeforeQueuedTiles() {
        let probe = CaptureProbe()  // 格子图全堵住
        let (thumbnails, _) = make(probe)
        var tiles: [CGWindowID] = []
        var stillArrived = false
        var still: CGImage?
        thumbnails.onImage = { id, _ in tiles.append(id) }

        thumbnails.request([1, 2, 3, 4, 5, 6])
        expect(spin { probe.total == 2 }, "two tiles occupy both slots, blocked (got \(probe.total))")

        thumbnails.still(9, quality: .full) { picture in
            still = picture
            stillArrived = true
            // 这一刻：still 自己刚跑完；只有刚放行的那一张格子图可能已经交回。
            expect(tiles.count <= 1, "the still is handed back before the queued tiles (tiles so far: \(tiles))")
            expect(probe.stillCount == 1, "the still ran exactly once")
            expect(probe.count(9) == 0, "the still does not go through the tile capture path")
        }

        probe.openOne()  // 空出一个槽：队列该挑 high 优先的 still，而不是还排着的格子图
        expect(spin { stillArrived }, "the still completes while tiles are still queued")
        expect(still != nil, "the still comes back with a picture (nil means it never ran)")
        // 谁先进 capture 的顺序：先占住两个槽的格子图（这两张谁先不定），再是 still，然后才是排队的格子图。
        // 只要求 still 落在前两个之后、排队那几张之前 —— 不受先开哪两张的影响。
        let order = probe.order
        let stillAt = order.firstIndex(of: "still9")
        expect(stillAt == 2 || stillAt == 3,
               "the still was picked over the queued tiles, right after the two busy slots (order \(order))")
        expect(order.prefix(2).allSatisfy { $0.hasPrefix("tile") },
               "the still did not preempt a tile that already occupied a slot (order \(order))")
        expect(stillAt != nil && order[(stillAt! + 1)...].filter { $0.hasPrefix("tile") }.count <= 4,
               "at most the freed slot's tile ran alongside the still (order \(order))")
        expect(probe.stills.map(\.0) == [9], "the still was captured exactly once")
        expect(tiles.count <= 1, "no tile past the first slot finished before the still (got \(tiles.count))")

        probe.openAll()
        expect(spin { tiles.count == 6 }, "all six tiles finish afterwards (got \(tiles.count))")
        expect(probe.peak <= NotchThumbnailPolicy.maxInFlight, "the still shared the two-slot budget (peak \(probe.peak))")
    }
}
