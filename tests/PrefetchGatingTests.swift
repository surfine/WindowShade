import Cocoa

@main
struct PrefetchGatingTests {
    nonisolated(unsafe) static var failures = 0
    static func check(_ ok: Bool, _ msg: String) {
        if !ok { failures += 1; print("FAIL: \(msg)") }
    }

    static func main() {
        // 门控真值表：只有第一下点击，且动画开或对照模式开，才预热。
        for click in 0...3 {
            for anim in [false, true] {
                for disabled in [false, true] {
                    let expected = click == 1 && (anim || disabled)
                    check(TitlebarPrefetchGate.shouldPrefetch(
                        clickState: click, animationEnabled: anim, fastCaptureDisabled: disabled) == expected,
                          "gate click=\(click) anim=\(anim) disabled=\(disabled)")
                }
            }
        }
        check(TitlebarPrefetchGate.bandHeight(profileHeight: nil) == 52, "default band 52")
        check(TitlebarPrefetchGate.bandHeight(profileHeight: 0) == 52, "zero profile -> 52")
        check(TitlebarPrefetchGate.bandHeight(profileHeight: 80) == 80, "profile band")

        // 准入快照：doubleClickInterval 内命中，超过为 nil。
        let cache = WindowListCache(ttl: 0.15, provider: { _ in [] })
        let win: [[String: Any]] = [[kCGWindowNumber as String: 7]]
        check(cache.admissionSnapshot(validFor: 0.5, now: 100) == nil, "no snapshot before record")
        cache.recordAdmissionSnapshot(win, at: 100)
        check(cache.admissionSnapshot(validFor: 0.5, now: 100.3)?.count == 1, "hit within interval")
        check(cache.admissionSnapshot(validFor: 0.5, now: 100.5) == nil, "nil at interval")
        check(cache.admissionSnapshot(validFor: 0.5, now: 101) == nil, "nil after interval")
        check(cache.freshOnScreenWindows() == nil, "generic TTL snapshot untouched")

        // 计数
        let stats = PrefilterStats()
        _ = stats.note(.hit); _ = stats.note(.miss)
        let c = stats.note(.unknown)
        check(c == PrefilterStats.Counts(hit: 1, miss: 1, unknown: 1), "counts")

        if failures == 0 { print("PrefetchGatingTests: all passed") } else { exit(1) }
    }
}
