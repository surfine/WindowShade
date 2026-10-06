import Foundation

/// PERF-05：图像准备移出主线程后的两件事。
/// 一代换：每有新请求进来，旧请求立刻作废，worker 回来后只换入仍属当前代际的结果。
/// 二缓存：键含来源身分、色彩空间、像素尺寸；任一变化都是新键（等于失效），容量有界。
@main struct FoldPrepTests {
    final class Source {}

    static func main() {
        generationTests()
        cacheKeyTests()
        cacheEvictionTests()
        staleResultIsDroppedTests()
        cacheHitInvalidatesInFlightTests()
        print(
            "PASS: fold image prep is generation-checked, cached by source/color/size, and bounded")
    }

    /// 每个目标一条代际线；新请求作废旧请求，只有最新的算数。
    static func generationTests() {
        var policy = FoldPrepPolicy()
        let first = policy.supersede(.primary)
        precondition(policy.isCurrent(.primary, first), "刚发出的请求就是当前代际")
        let second = policy.supersede(.primary)
        precondition(second != first, "每次作废都换一个号")
        precondition(!policy.isCurrent(.primary, first), "旧请求一发新请求就过期")
        precondition(policy.isCurrent(.primary, second))

        // 两条目标互不干扰：背景的新请求不能把主图的在飞请求作废。
        let background = policy.supersede(.background)
        precondition(policy.isCurrent(.primary, second), "另一个目标的代际推进不影响这一路")
        precondition(policy.isCurrent(.background, background))

        policy.reset()
        precondition(!policy.isCurrent(.primary, second), "reset 后没有任何结果还算当前")
        precondition(!policy.isCurrent(.background, background))
        // reset 后再发号也不会撞回旧号。
        let afterReset = policy.supersede(.primary)
        precondition(!policy.isCurrent(.primary, second))
        precondition(policy.isCurrent(.primary, afterReset))
    }

    /// 键的组成：来源身分、色彩空间、像素尺寸。任一变化都必须算未命中。
    static func cacheKeyTests() {
        let cache = FoldImageCache<String>(capacity: 4)
        let a = Source()
        let b = Source()
        let base = FoldImageCache<String>.Key(
            source: ObjectIdentifier(a), colorSpace: "sRGB", width: 800, height: 600)

        precondition(cache.value(for: base) == nil, "没存过就是未命中")
        cache.store("first", for: base)
        precondition(cache.value(for: base) == "first")
        precondition(cache.hits == 1)
        precondition(cache.stores == 1)

        // 同一把键再取：命中，不重存。
        precondition(cache.value(for: base) == "first")
        precondition(cache.hits == 2)
        precondition(cache.stores == 1)

        // 色彩空间变了：新键。
        let p3 = FoldImageCache<String>.Key(
            source: ObjectIdentifier(a), colorSpace: "displayP3", width: 800, height: 600)
        precondition(cache.value(for: p3) == nil, "色彩空间不同就是另一个键")

        // 像素尺寸变了：新键。
        let resized = FoldImageCache<String>.Key(
            source: ObjectIdentifier(a), colorSpace: "sRGB", width: 1600, height: 1200)
        precondition(cache.value(for: resized) == nil, "尺寸不同就是另一个键")

        // 来源变了：新键。
        let other = FoldImageCache<String>.Key(
            source: ObjectIdentifier(b), colorSpace: "sRGB", width: 800, height: 600)
        precondition(cache.value(for: other) == nil, "来源不同就是另一个键")

        // 数值相同但用另一个对象实例：ObjectIdentifier 不同，仍算新键（不会把两个窗口搞混）。
        precondition(
            FoldImageCache<String>.Key(
                source: ObjectIdentifier(Source()), colorSpace: "sRGB", width: 800, height: 600)
                != base)

        cache.removeAll()
        precondition(cache.count == 0)
        precondition(cache.value(for: base) == nil, "清空后连原先命中的键也不在")
    }

    /// 容量有界，超了就按最久未用淘汰。
    static func cacheEvictionTests() {
        let cache = FoldImageCache<Int>(capacity: 2)
        let source = ObjectIdentifier(Source())
        let k1 = FoldImageCache<Int>.Key(
            source: source, colorSpace: "sRGB", width: 1, height: 1)
        let k2 = FoldImageCache<Int>.Key(
            source: source, colorSpace: "sRGB", width: 2, height: 2)
        let k3 = FoldImageCache<Int>.Key(
            source: source, colorSpace: "sRGB", width: 3, height: 3)

        cache.store(1, for: k1)
        cache.store(2, for: k2)
        // 摸一下 k1：它变成最近使用，接下来该淘汰的是 k2。
        precondition(cache.value(for: k1) == 1)
        cache.store(3, for: k3)

        precondition(cache.count <= 2, "缓存占用不得超过容量")
        precondition(cache.evictions == 1)
        precondition(cache.value(for: k1) == 1, "最近用过的还在")
        precondition(cache.value(for: k3) == 3)
        precondition(cache.value(for: k2) == nil, "最久未用的先被淘汰")

        // 大量不同键：占用仍然有界。
        for width in 0..<200 {
            cache.store(
                width,
                for: FoldImageCache<Int>.Key(
                    source: source, colorSpace: "sRGB", width: width + 10, height: 1))
        }
        precondition(cache.count <= 2, "连续新键也不会让缓存无界增长")
    }

    /// 渲染器换入前的那次代际复查：迟到的结果必须丢掉。
    static func staleResultIsDroppedTests() {
        var policy = FoldPrepPolicy()
        // worker 还在准备第一张图。
        let inFlight = policy.supersede(.primary)
        // 用户又换了一张：旧结果一到就该丢。
        _ = policy.supersede(.primary)
        precondition(!policy.isCurrent(.primary, inFlight), "被顶掉的准备结果不得换入")

        var swapped = 0
        if policy.isCurrent(.primary, inFlight) { swapped += 1 }
        precondition(swapped == 0, "晚到的旧图不换入")

        let latest = policy.supersede(.primary)
        if policy.isCurrent(.primary, latest) { swapped += 1 }
        precondition(swapped == 1, "只有当前代际的结果换入")
    }

    /// 命中缓存是同步换入，也必须把还在飞的旧请求作废，否则 worker 回来会覆盖新画面。
    static func cacheHitInvalidatesInFlightTests() {
        var policy = FoldPrepPolicy()
        let inFlight = policy.supersede(.primary)

        // 命中缓存时渲染器做的两件事：推进代际（作废在飞请求）+ 立刻换入。
        let hitToken = policy.supersede(.primary)
        precondition(!policy.isCurrent(.primary, inFlight))
        precondition(policy.isCurrent(.primary, hitToken))

        var swapped: String?
        if policy.isCurrent(.primary, inFlight) { swapped = "stale" }
        if policy.isCurrent(.primary, hitToken) { swapped = "cached" }
        precondition(swapped == "cached", "缓存结果赢过迟到的在飞结果")
    }
}
