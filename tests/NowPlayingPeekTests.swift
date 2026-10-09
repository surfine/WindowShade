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
}
