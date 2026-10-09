// 正在播放“换歌一瞥”（设计稿《正在播放》NP-3）：停多久、什么时候开口、什么时候原地换字、什么时候不一瞥。
// 纯逻辑，无权限、无 UI、不起计时器。

import Foundation

@main struct NowPlayingPeekTests {
    static func expect(_ condition: Bool, _ message: String) {
        precondition(condition, "断言失败: \(message)")
    }

    static func sample(_ title: String, artist: String = "歌手", playing: Bool = true, ad: Bool = false,
                       player: String = "com.apple.Music") -> NowPlayingPeekTracker.Sample {
        .init(player: player, title: title, artist: artist, isPlaying: playing, isAdvertisement: ad)
    }

    static func isOpen(_ decision: NowPlayingPeekTracker.Decision) -> Bool {
        if case .open = decision { return true }
        return false
    }

    static func main() {
        testHold()
        testFirstTrackAndSkips()
        testFiveSkipsOpenOnce()
        testNoPeekConditions()
        testReopenAfterEnd()
        testAdvertisementRule()
        testQueuedBehindOtherAlert()
        print("PASS now-playing-peek")
    }

    static func testHold() {
        expect(NowPlayingPeek.height(notchHeight: 33.5) == 63.5, "高 = 刘海 + 30 = 63.5")
        expect(abs(NowPlayingPeek.hold(title: "", artist: "") - 1.8) < 1e-9, "空 = 1.8 秒")
        expect(abs(NowPlayingPeek.hold(title: "晴天", artist: "周杰伦") - (1.8 + 5 * 0.05)) < 1e-9, "5 个字 = 2.05 秒")
        expect(NowPlayingPeek.hold(title: String(repeating: "长", count: 80), artist: "x") == 4.5, "最长 4.5 秒")
        expect(abs(NowPlayingPeek.hold(title: String(repeating: "a", count: 54), artist: "") - 4.5) < 1e-9, "54 字刚好到顶")
        expect(NowPlayingPeek.spoken(title: "晴天", artist: "") == "晴天" && NowPlayingPeek.spoken(title: "晴天", artist: "周杰伦") == "晴天，周杰伦",
               "读屏念全名")
    }

    static func testFirstTrackAndSkips() {
        var tracker = NowPlayingPeekTracker()
        let gates = NowPlayingPeekTracker.Gates()
        expect(isOpen(tracker.observe(sample("A"), gates: gates, now: 0)), "开始播放的第一首应开口")
        expect(tracker.observe(sample("A"), gates: gates, now: 0.5) == .none, "同一首不再一瞥")
        tracker.dismissed()
        expect(isOpen(tracker.observe(sample("B"), gates: gates, now: 10)), "换歌应开口")
        tracker.dismissed()
        expect(isOpen(tracker.observe(sample("B", player: "com.spotify.client"), gates: gates, now: 20)), "换播放器应开口")
    }

    static func testFiveSkipsOpenOnce() {
        var tracker = NowPlayingPeekTracker()
        let gates = NowPlayingPeekTracker.Gates()
        var opens = 0, replaces = 0
        for index in 0..<5 {
            let title = "曲目\(index)"
            switch tracker.observe(sample(title), gates: gates, now: Double(index) * 0.3) {
            case .open: opens += 1
            case let .replace(hold):
                replaces += 1
                expect(abs(hold - NowPlayingPeek.hold(title: title, artist: "歌手")) < 1e-9, "替换时计时按新字重算")
            case .none: expect(false, "每一次换歌都该有结果")
            }
        }
        expect(opens == 1 && replaces == 4, "1.5 秒内连按 5 次下一首只开一次口（开 \(opens)，原地换 \(replaces)）")
        let last = NowPlayingPeek.hold(title: "曲目4", artist: "歌手")
        expect(tracker.isOpen(at: 1.2 + last - 0.01) && !tracker.isOpen(at: 1.2 + last + 0.01), "计时从最后一次换歌重算")
    }

    static func testNoPeekConditions() {
        let on = NowPlayingPeekTracker.Gates()
        let cases: [(String, NowPlayingPeekTracker.Gates)] = [
            ("那一排或大卡开着", .init(shelfOrCardOpen: true)),
            ("全屏", .init(fullScreen: true)),
            ("锁屏", .init(locked: true)),
            ("别的提醒挂着", .init(otherAlertShowing: true)),
        ]
        for (name, gates) in cases {
            var tracker = NowPlayingPeekTracker()
            _ = tracker.observe(sample("A"), gates: on, now: 0)
            tracker.dismissed()
            expect(tracker.observe(sample("B"), gates: gates, now: 10) == .none, "\(name)：不一瞥")
            expect(tracker.observe(sample("B"), gates: on, now: 11) == .none, "\(name)：事后不补")
            expect(isOpen(tracker.observe(sample("C"), gates: on, now: 12)), "\(name)：下一首照常")
        }
        var tracker = NowPlayingPeekTracker()
        _ = tracker.observe(sample("A"), gates: on, now: 0)
        tracker.dismissed()
        expect(tracker.observe(sample("A", playing: false), gates: on, now: 5) == .none, "暂停：不一瞥")
        expect(tracker.observe(sample("A"), gates: on, now: 30) == .none, "暂停后接着放同一首：不一瞥")
        _ = tracker.observe(sample("B", playing: false), gates: on, now: 40)
        expect(isOpen(tracker.observe(sample("B"), gates: on, now: 41)), "暂停时换歌、再放：一瞥")
        expect(tracker.observe(nil, gates: on, now: 50) == .none, "没有在放：不一瞥")
        expect(!tracker.isOpen, "没有在放：一瞥收掉")
        expect(isOpen(tracker.observe(sample("B"), gates: on, now: 60)), "播放器退出后重新开始：一瞥")
    }

    static func testReopenAfterEnd() {
        var tracker = NowPlayingPeekTracker()
        let gates = NowPlayingPeekTracker.Gates()
        guard case let .open(hold) = tracker.observe(sample("A"), gates: gates, now: 0) else { return expect(false, "开口") }
        expect(isOpen(tracker.observe(sample("B"), gates: gates, now: hold + 0.5)), "收回之后换歌应重新开口")
    }

    static func testAdvertisementRule() {
        var tracker = NowPlayingPeekTracker()
        let gates = NowPlayingPeekTracker.Gates()
        let ad = NowPlayingCardPolicy.isAdvertisement(duration: 30, artist: "")
        expect(ad, "30 秒没歌手是广告")
        expect(tracker.observe(sample("广告", artist: "", ad: ad), gates: gates, now: 0) == .none, "广告：不一瞥")
        expect(!NowPlayingCardPolicy.isAdvertisement(duration: 200, artist: ""), "长曲目没歌手不是广告")
        expect(!NowPlayingCardPolicy.isAdvertisement(duration: 30, artist: "某人"), "有歌手不是广告")
        expect(!NowPlayingCardPolicy.isAdvertisement(duration: nil, artist: ""), "不知道时长不当广告")
        expect(isOpen(tracker.observe(sample("正片", artist: "", ad: false), gates: gates, now: 40)), "广告之后的下一首照常一瞥")
    }

    /// 别的提醒占着：这一瞥排在后面（稿“排在后面”）。占着的收了且仍在放、仍是同一首才补出；超过 4.5 秒放弃。
    static func testQueuedBehindOtherAlert() {
        let free = NowPlayingPeekTracker.Gates()
        let busy = NowPlayingPeekTracker.Gates(otherAlertShowing: true)
        expect(NowPlayingPeek.queueLimit == 4.5, "排队最多等 4.5 秒")

        var tracker = NowPlayingPeekTracker()
        expect(tracker.observe(sample("A"), gates: busy, now: 0) == .none && tracker.hasPending, "占着：不开口，排在后面")
        expect(tracker.retryPending(sample("A"), gates: busy, now: 1) == .none && tracker.hasPending, "占着的还没收：接着等")
        guard case let .open(hold) = tracker.retryPending(sample("A"), gates: free, now: 2.6) else { return expect(false, "收了该补出") }
        expect(abs(hold - NowPlayingPeek.hold(title: "A", artist: "歌手")) < 1e-9, "补出的一瞥照常计时")
        expect(!tracker.hasPending, "补出后不再排着")
        expect(tracker.retryPending(sample("A"), gates: free, now: 3) == .none, "只补一次")

        // 刚好 4.5 秒还算数，超过就放弃，而且事后不再补。
        tracker = NowPlayingPeekTracker()
        _ = tracker.observe(sample("A"), gates: busy, now: 10)
        expect(isOpen(tracker.retryPending(sample("A"), gates: free, now: 14.5)), "4.5 秒整：补出")
        tracker = NowPlayingPeekTracker()
        _ = tracker.observe(sample("A"), gates: busy, now: 10)
        expect(tracker.retryPending(sample("A"), gates: free, now: 14.51) == .none && !tracker.hasPending, "超过 4.5 秒：放弃")
        expect(tracker.retryPending(sample("A"), gates: free, now: 14.6) == .none, "放弃后不补")

        // 占着期间换了歌：排的是新的一首；旧的不补。
        tracker = NowPlayingPeekTracker()
        _ = tracker.observe(sample("A"), gates: busy, now: 0)
        _ = tracker.observe(sample("B"), gates: busy, now: 1)
        expect(tracker.retryPending(sample("A"), gates: free, now: 2) == .none && !tracker.hasPending, "已经不是排队的那一首：放弃")
        tracker = NowPlayingPeekTracker()
        _ = tracker.observe(sample("A"), gates: busy, now: 0)
        _ = tracker.observe(sample("B"), gates: busy, now: 1)
        expect(isOpen(tracker.retryPending(sample("B"), gates: free, now: 2)), "新的一首补出")

        // 暂停、播放器退出、广告：放弃。
        for (name, current) in [("暂停", sample("A", playing: false)), ("播放器退出", nil), ("广告", sample("A", ad: true))] as [(String, NowPlayingPeekTracker.Sample?)] {
            tracker = NowPlayingPeekTracker()
            _ = tracker.observe(sample("A"), gates: busy, now: 0)
            expect(tracker.retryPending(current, gates: free, now: 1) == .none && !tracker.hasPending, "\(name)：放弃")
        }
        // 暂停后在占着期间接着放：observe 看到暂停就清掉，同一首接着放不算换歌。
        tracker = NowPlayingPeekTracker()
        _ = tracker.observe(sample("A"), gates: busy, now: 0)
        _ = tracker.observe(sample("A", playing: false), gates: busy, now: 1)
        expect(!tracker.hasPending, "暂停：不再排着")
        expect(tracker.observe(sample("A"), gates: free, now: 2) == .none, "暂停后接着放同一首：不一瞥")

        // 更硬的场面（大卡、那一排、全屏、锁屏）来了：放弃，不补。
        let hard: [(String, NowPlayingPeekTracker.Gates)] = [
            ("大卡或那一排", .init(shelfOrCardOpen: true)), ("全屏", .init(fullScreen: true)), ("锁屏", .init(locked: true))]
        for (name, gates) in hard {
            tracker = NowPlayingPeekTracker()
            _ = tracker.observe(sample("A"), gates: busy, now: 0)
            expect(tracker.retryPending(sample("A"), gates: gates, now: 1) == .none && !tracker.hasPending, "\(name)：放弃")
            expect(tracker.retryPending(sample("A"), gates: free, now: 2) == .none, "\(name)：事后不补")
        }
        // 硬场面本身挡着的那一首从一开始就不排。
        tracker = NowPlayingPeekTracker()
        _ = tracker.observe(sample("A"), gates: .init(shelfOrCardOpen: true, otherAlertShowing: true), now: 0)
        expect(!tracker.hasPending, "大卡开着又有提醒：不排")

        // 锁屏清场：排着的也不留。
        tracker = NowPlayingPeekTracker()
        _ = tracker.observe(sample("A"), gates: busy, now: 0)
        tracker.cleared()
        expect(!tracker.hasPending && tracker.retryPending(sample("A"), gates: free, now: 1) == .none, "清场后不补")

        // 排着的时候占着的提醒收了，开着的一瞥仍可原地换字。
        tracker = NowPlayingPeekTracker()
        _ = tracker.observe(sample("A"), gates: free, now: 0)
        expect(tracker.observe(sample("B"), gates: free, now: 0.5) != .none, "一瞥开着换歌：原地换")
    }
}
