// 正在播放大卡（设计稿《正在播放》NP-4）的纯逻辑：几何、进度条按下 / 拖动 / 松手、时间写法、收回条件、
// 输出设备、推送流判坏、两个开关的默认值三态。无权限、无 UI、不起子进程。

import Foundation

@main struct NowPlayingCardTests {
    static func expect(_ condition: Bool, _ message: String) {
        precondition(condition, "断言失败: \(message)")
    }

    static func close(_ a: Double?, _ b: Double, _ message: String, tolerance: Double = 1e-9) {
        expect(a != nil && abs(a! - b) < tolerance, "\(message)（实际 \(String(describing: a))）")
    }

    static func main() {
        testGeometry()
        testEarCover()
        testListHeights()
        testTimeline()
        testText()
        testSeekPolicy()
        testScrub()
        testRetract()
        testOutputs()
        testStreamVerdict()
        testDefaults()
        print("PASS now-playing-card")
    }

    // MARK: 几何

    static func testGeometry() {
        typealias L = NowPlayingCardLayout
        expect(L.width == 420 && L.contentHeight == 142 && L.totalHeight == 175.5, "420 × 175.5（刘海 33.5 + 142）")
        expect(L.bottomRadius == 28, "底角 28")
        expect(L.coverSide == 56 && L.coverCorner == 14, "封面 56，圆角 14（= 28 − 14）")
        expect(L.pausedCoverScale == 0.9, "暂停缩到 0.9")
        let f = L.frames()
        expect(f.cover == CGRect(x: 14, y: 14, width: 56, height: 56), "封面在 (14, 14)")
        expect(f.title.minX == 82 && f.title.minY == 37, "歌名在 (82, 37)")
        expect(f.artist.minX == 82 && f.artist.minY == 55, "歌手在 (82, 55)")
        expect(f.title.maxX == 420 - 14, "歌名右边留 14")
        expect(f.bar.minX == 14 && f.bar.width == 420 - 28, "进度条宽 = 卡宽 − 28")
        expect(f.bar.minY == 80 && f.bar.height == 20, "感应带 80…100")
        expect(f.times.minY == 100, "时间在 100")
        expect(f.play.midX == 210 && f.previous.midX == 210 - 64 && f.next.midX == 210 + 64, "三个键居中")
        expect(f.play.width == 40 && f.previous.width == 32, "播放键 40，上一首 32")
        expect(f.output.maxX == 420 - 14, "输出设备键在右端")
        expect(f.previous.midY == f.play.midY && f.play.midY == f.output.midY, "控制行上下对齐")
        expect(f.play.maxY < L.totalHeight, "控制行在卡里面")
        let narrow = L.frames(cardWidth: 380)
        expect(narrow.bar.width == 352 && narrow.play.midX == 190, "窄屏上宽度跟着卡走")
        // 不同于旧的计时器大卡（440）：这张是 420。
        expect(L.interactionHeight(listDeviceCount: nil, virtualNotch: false) == 142, "真刘海：卡片视图只盖刘海下面 142")
        expect(L.interactionHeight(listDeviceCount: nil, virtualNotch: true) == 175.5, "胶囊：整张都是内容 175.5")
        expect(L.contentFadeLag > 0 && L.contentFadeLag < 0.2 && L.contentFadeIn == 0.18, "内容等形状走到四成再淡入，0.18")
    }

    static func testEarCover() {
        // 本机：刘海 185 × 33.5，耳封面 20，主体 26.6。
        let ear = NowPlayingCardLayout.earCoverFrame(notchWidth: 185, notchHeight: 33.5)
        close(ear.width, 20, "耳封面 20")
        close(ear.minY, 6.75, "上下各 6.75")
        close(ear.minX, (420 - 185) / 2 - 26.6 + 3.3, "在左耳主体里水平居中")
        expect(ear.maxX < 420 / 2 - 185 / 2, "整个在刘海左边")
        let final = NowPlayingCardLayout.frames().cover
        expect(ear.width < final.width && ear.minX > final.minX && ear.minY < final.minY + final.height, "从耳朵长到 56：变大、往左上走")
    }

    static func testListHeights() {
        typealias L = NowPlayingCardLayout
        expect(L.visibleRows(deviceCount: 0) == 1, "至少一行")
        expect(L.visibleRows(deviceCount: 4) == 4 && L.visibleRows(deviceCount: 5) == 5 && L.visibleRows(deviceCount: 9) == 5, "超过 5 行就滚")
        // 稿：4 个设备 = 84 + 4 × 34 + 36 = 256。
        expect(L.listTotalHeight(deviceCount: 4) == 256, "4 个设备总高 256")
        expect(L.listTotalHeight(deviceCount: 12) == 84 + 5 * 34 + 36, "再多也不超过 5 行的高")
        expect(L.interactionHeight(listDeviceCount: 4, virtualNotch: false) == 256 - 33.5, "真刘海：扣掉刘海那一截")
        expect(L.interactionHeight(listDeviceCount: 4, virtualNotch: true) == 256, "胶囊：整张")
        expect(L.interactionHeight(listDeviceCount: 4, virtualNotch: false) <= 480, "不超过岛对内容高度的 480 上限")
        let row0 = L.listRow(0), row2 = L.listRow(2)
        expect(row0.height == 34 && row2.minY - row0.minY == 68 && row0.minX == 14 && row0.width == 392, "每行 34")
        expect(L.listCloseDelay == 0.3, "选完 0.3 秒收列表")
    }

    // MARK: 进度

    static func testTimeline() {
        let line = NowPlayingTimeline(duration: 200, elapsed: 50, stamp: 1000, rate: 1)
        close(line.position(atEpoch: 1000), 50, "此刻就是 elapsed")
        close(line.position(atEpoch: 1010), 60, "播着：随时间往前走")
        close(line.position(atEpoch: 990), 50, "时间倒退不往回走")
        close(line.position(atEpoch: 5000), 200, "不超过时长")
        close(line.fraction(atEpoch: 1050), 0.5, "比例")
        let paused = NowPlayingTimeline(duration: 200, elapsed: 50, stamp: 1000, rate: 0)
        close(paused.position(atEpoch: 1100), 50, "暂停：不动")
        expect(!paused.isMoving && paused.secondsUntilNextTick(atEpoch: 1100) == nil, "暂停不排唤醒")
        let live = NowPlayingTimeline(duration: nil, elapsed: 30, stamp: 1000, rate: 1)
        expect(live.isLive && live.fraction(atEpoch: 1005) == nil, "没有时长 = 直播，没有比例")
        close(live.position(atEpoch: 1005), 35, "直播也写已播放时长")
        expect(NowPlayingTimeline(duration: 0, elapsed: 3, stamp: 0, rate: 1).isLive, "时长 0 当没有时长")
        let dirty = NowPlayingTimeline(duration: .nan, elapsed: .nan, stamp: 0, rate: -1)
        expect(dirty.isLive && dirty.elapsed == 0 && dirty.rate == 1, "脏数据：没有时长、位置 0、速度当 1，不崩")
        let fast = NowPlayingTimeline(duration: 100, elapsed: 10, stamp: 0, rate: 2)
        close(fast.position(atEpoch: 5), 20, "倍速")
        // 下一个整秒：位置 10.25 → 还差 0.75 秒。
        let tick = NowPlayingTimeline(duration: 100, elapsed: 10.25, stamp: 0, rate: 1)
        close(tick.secondsUntilNextTick(atEpoch: 0), 0.75, "下一个整秒")
        close(fast.secondsUntilNextTick(atEpoch: 0), 0.5, "倍速时更早")
        let end = NowPlayingTimeline(duration: 100, elapsed: 100, stamp: 0, rate: 1)
        expect(end.secondsUntilNextTick(atEpoch: 5) == nil, "放完了不排唤醒")
        // 从推送流的现状来。
        let info = NowPlayingInfo(bundleID: "com.apple.Music", title: "T", artist: "A", isPlaying: true, duration: 214, elapsed: 72,
                                  timestamp: 2000, rate: 1)
        let fromInfo = NowPlayingTimeline(info: info, receivedAtEpoch: 9999)
        close(fromInfo.stamp, 2000, "有时间戳用它")
        close(fromInfo.position(atEpoch: 2003), 75, "照时间戳推算")
        let stopped = NowPlayingInfo(bundleID: "x", title: "T", artist: "A", isPlaying: false, duration: 214, elapsed: nil, timestamp: nil, rate: nil)
        let fromStopped = NowPlayingTimeline(info: stopped, receivedAtEpoch: 7)
        expect(fromStopped.rate == 0 && fromStopped.stamp == 7 && fromStopped.elapsed == 0, "暂停且没位置：0，不动，用收到的时刻")
    }

    static func testText() {
        typealias T = NowPlayingCardText
        expect(T.clock(0) == "0:00" && T.clock(72) == "1:12" && T.clock(72.9) == "1:12", "向下取整")
        expect(T.clock(3725) == "1:02:05", "一小时以上")
        expect(T.clock(-5) == "0:00" && T.clock(.nan) == "0:00", "脏数据写 0:00")
        expect(T.remaining(position: 72, duration: 214) == "\u{2212}2:22", "剩余用减号 U+2212，向上取整")
        expect(T.remaining(position: 72.5, duration: 214) == "\u{2212}2:22", "剩余向上取整")
        expect(T.remaining(position: 214, duration: 214) == "\u{2212}0:00", "放完是 −0:00")
        expect(T.remaining(position: 300, duration: 214) == "\u{2212}0:00", "位置超过时长不写负数")
        expect(T.spokenProgress(position: 72, duration: 214) == "已播 1 分 12 秒，剩余 2 分 22 秒", "读屏")
        expect(T.spokenProgress(position: 12, duration: nil) == "直播，已播 12 秒", "直播读屏")
    }

    static func testSeekPolicy() {
        typealias P = NowPlayingCardPolicy
        expect(P.isSeekable(streamHealthy: true, duration: 214, artist: "A"), "推送流健康、有时长：能拖")
        expect(!P.isSeekable(streamHealthy: false, duration: 214, artist: "A"), "退回问音乐 / Spotify：不让跳（条不加粗）")
        expect(!P.isSeekable(streamHealthy: true, duration: nil, artist: "A"), "直播：不能拖")
        expect(!P.isSeekable(streamHealthy: true, duration: 0, artist: "A"), "没有时长：不能拖")
        expect(P.isAdvertisement(duration: 30, artist: "") && !P.isAdvertisement(duration: 30, artist: "A"), "没有歌手且 ≤ 60 秒是广告")
        expect(!P.isSeekable(streamHealthy: true, duration: 30, artist: " "), "广告不让拖")
        expect(P.isSeekable(streamHealthy: true, duration: 61, artist: ""), "没歌手但超过 60 秒的是播客之类：能拖")
        let content = NowPlayingCardContent(title: "歌", artist: "人", isPaused: false, bundleID: "b", timeline: nil, seekable: false)
        expect(content.spoken == "歌，人，正在播放", "读屏：歌名，歌手，正在播放")
        var paused = content; paused.isPaused = true; paused.artist = ""
        expect(paused.spoken == "歌，已暂停", "读屏：没歌手、已暂停")
    }

    // MARK: 进度条

    static func testScrub() {
        var scrub = NowPlayingScrub()
        expect(!scrub.seekable && scrub.barHeight == 4 && !scrub.showsHandCursor, "不让跳时平时 4 高、没有手形")
        expect(!scrub.press(at: 100, trackWidth: 392), "播放器不让跳：不接按下")
        expect(!scrub.isDragging && scrub.barHeight == 4, "不让跳：按了也不加粗")
        scrub.setSeekable(true)
        expect(scrub.showsHandCursor && scrub.barHeight == 4, "能跳：手形，平时 4 高")
        expect(scrub.displayFraction(player: 0.3, now: 0) == 0.3, "没按时画播放器给的")

        // 按下：加粗 8，立刻跳到按下处。
        expect(scrub.press(at: 196, trackWidth: 392), "按下被接住")
        expect(scrub.barHeight == 8 && scrub.isDragging, "按下 8 高")
        close(scrub.displayFraction(player: 0.3, now: 0), 0.5, "按下就跳到按下处")
        // 拖动跟手；播放器的位置变了也不理。
        scrub.drag(to: 98, trackWidth: 392)
        close(scrub.displayFraction(player: 0.9, now: 1), 0.25, "拖动跟手，不理播放器")
        scrub.drag(to: -50, trackWidth: 392)
        close(scrub.displayFraction(player: 0.9, now: 1), 0, "拖出左边停在 0")
        scrub.drag(to: 900, trackWidth: 392)
        close(scrub.displayFraction(player: 0.1, now: 1), 1, "拖出右边停在 1")
        // 松手才真的跳：只有 release 返回秒数。
        scrub.drag(to: 98, trackWidth: 392)
        let seconds = scrub.release(at: 98, trackWidth: 392, duration: 200, now: 10)
        close(seconds, 50, "松手跳到 25% × 200 = 50 秒")
        expect(!scrub.isDragging && scrub.barHeight == 4, "松手变回 4 高")
        close(scrub.displayFraction(player: 0.6, now: 10.5), 0.25, "松手后在目标上再留一会儿，不弹回去")
        close(scrub.displayFraction(player: 0.25, now: 10.5), 0.25, "播放器追上了就用播放器的")
        close(scrub.displayFraction(player: 0.6, now: 11.5), 0.6, "超过 1 秒不再留")
        expect(scrub.holdExpiry(now: 10.5) == 11, "给松手后的保持排一次到点")
        expect(scrub.holdExpiry(now: 12) == nil, "到点后不用再排")
        expect(scrub.release(at: 1, trackWidth: 392, duration: 200, now: 12) == nil, "没按过就松手：什么都不发")

        // 没有时长（直播）：松手不发跳转。
        _ = scrub.press(at: 10, trackWidth: 392)
        expect(scrub.release(at: 10, trackWidth: 392, duration: nil, now: 20) == nil, "没有时长不跳")
        expect(scrub.holdExpiry(now: 20) == nil, "也不留")

        // 拖着的时候播放器变得不能跳了：取消。
        _ = scrub.press(at: 100, trackWidth: 392)
        scrub.setSeekable(false)
        expect(!scrub.isDragging && scrub.barHeight == 4, "中途不让跳了：取消，变回 4 高")
        scrub.setSeekable(true)
        expect(scrub.press(at: 100, trackWidth: 0), "宽度 0 也能按")
        close(scrub.displayFraction(player: 0.5, now: 0), 0, "宽度 0 时位置落在 0，不崩")
    }

    // MARK: 收回

    static func testRetract() {
        typealias C = NowPlayingRetractClock
        expect(C.leaveDelay == 1.5, "指针离开 1.5 秒")
        var clock = C()
        clock.update(now: 0, pointerInside: true, dragging: false, listOpen: false)
        expect(!clock.isArmed && !clock.isDue(now: 100), "指针在里面：不收")
        clock.update(now: 10, pointerInside: false, dragging: false, listOpen: false)
        expect(clock.isArmed && !clock.isDue(now: 11.4), "离开 1.4 秒还没到")
        expect(clock.isDue(now: 11.5), "离开满 1.5 秒收回")
        close(clock.remaining(now: 10.5), 1.0, "还要等 1 秒")
        // 重复通知不重置计时。
        clock.update(now: 11, pointerInside: false, dragging: false, listOpen: false)
        expect(clock.isDue(now: 11.5), "离开期间重复更新不重新数")
        // 回到卡里：取消。
        clock.update(now: 11.2, pointerInside: true, dragging: false, listOpen: false)
        expect(!clock.isArmed && !clock.isDue(now: 99), "回来就取消")
        // 拖动时不算。
        clock.update(now: 20, pointerInside: false, dragging: true, listOpen: false)
        expect(!clock.isArmed && !clock.isDue(now: 99), "拖进度条时不收")
        // 拖完指针还在外面：从松手那一刻起数。
        clock.update(now: 25, pointerInside: false, dragging: false, listOpen: false)
        expect(clock.isArmed && !clock.isDue(now: 26.4) && clock.isDue(now: 26.5), "松手后再数 1.5 秒")
        // 列表开着不算。
        clock.update(now: 30, pointerInside: false, dragging: false, listOpen: true)
        expect(!clock.isArmed && !clock.isDue(now: 99), "开着输出设备列表不收")
        clock.update(now: 40, pointerInside: false, dragging: false, listOpen: false)
        expect(clock.isDue(now: 41.5) && !clock.isDue(now: 41), "列表关上以后再数")
        // 点卡外：岛上不收，岛外收。
        expect(C.shouldRetract(onClickInsideIsland: false), "点卡外收回")
        expect(!C.shouldRetract(onClickInsideIsland: true), "点在岛上（含刘海本身）不收")
    }

    // MARK: 输出设备

    static func route(_ name: String, _ kind: AudioOutputKind, current: Bool = false) -> AudioOutputRoute {
        AudioOutputRoute(id: UInt32(name.count), uid: "uid-" + name, name: name, kind: kind, isCurrent: current)
    }

    static func testOutputs() {
        typealias O = AudioOutputList
        expect(O.kind(transport: .builtIn, name: "MacBook Air扬声器") == .mac, "内建扬声器 = 这台 Mac")
        expect(O.kind(transport: .builtIn, name: "外置耳机") == .headphones, "内建耳机口接的耳机")
        expect(O.kind(transport: .bluetooth, name: "小明的 AirPods Pro") == .headphones, "AirPods 是耳机")
        expect(O.kind(transport: .bluetooth, name: "Beats Studio") == .headphones, "Beats 是耳机")
        expect(O.kind(transport: .bluetooth, name: "客厅的音箱") == .speaker, "蓝牙音箱")
        expect(O.kind(transport: .display, name: "Studio Display") == .speaker, "显示器的扬声器画成音箱")
        expect(O.kind(transport: .airPlay, name: "AirPods 的名字但走隔空播放") == .speaker, "隔空播放的一律音箱")
        expect(AudioOutputKind.mac.symbol == "laptopcomputer" && AudioOutputKind.headphones.symbol == "headphones"
                && AudioOutputKind.speaker.symbol == "hifispeaker.fill", "三种图标")
        let routes = [route("这台 Mac", .mac), route("AirPods Pro", .headphones, current: true), route("Studio Display", .speaker)]
        expect(O.rows(from: routes) == routes, "列表沿用系统顺序，当前那个在原位打勾")
        expect(O.currentKind(in: routes) == .headphones && O.currentSymbol(in: routes) == "headphones", "输出键的图标跟着当前设备")
        expect(O.currentKind(in: [route("a", .mac)]) == nil && O.currentSymbol(in: []) == "hifispeaker.fill", "读不到当前设备时用音箱")
        expect(O.spokenSelection(routes[1]) == "播放到 AirPods Pro", "选定后读屏")
    }

    // MARK: 推送流判坏

    static func testStreamVerdict() {
        typealias V = NowPlayingStreamVerdict
        expect(V.firstLineDeadline == 10 && V.failureWindow == 60 && V.failureLimit == 3, "10 秒、60 秒、3 次")
        expect(!V.isGivenUp(adapterPresent: true, unhealthyFor: 3, recentExits: 0), "启动 3 秒还在观察期：没坏")
        expect(V.isGivenUp(adapterPresent: true, unhealthyFor: 10, recentExits: 0), "10 秒内没有第一行：坏了")
        expect(!V.isGivenUp(adapterPresent: true, unhealthyFor: nil, recentExits: 2), "健康、只退出过 2 次：没坏")
        expect(V.isGivenUp(adapterPresent: true, unhealthyFor: nil, recentExits: 3), "60 秒内退出 3 次：坏了")
        expect(V.isGivenUp(adapterPresent: false, unhealthyFor: nil, recentExits: 0), "包里没有适配器：只有退路可走")
        expect(V.exits(in: [0, 30, 59, 63], now: 62) == 2, "只数最近 60 秒内的（30、59 在；0 太早，63 在未来）")
        expect(V.exits(in: [100], now: 50) == 0, "未来的时间戳不数")
    }

    // MARK: 默认值三态

    static func testDefaults() {
        let name = "com.windowshade.tests.nowplaying-card.\(ProcessInfo.processInfo.processIdentifier)"
        guard let suite = UserDefaults(suiteName: name) else { expect(false, "造不出测试用的 defaults"); return }
        defer { suite.removePersistentDomain(forName: name) }
        typealias D = NotchNowPlayingDefaults
        expect(D.musicKey == "Notch.activities.musicEnabled" && D.streamKey == "Notch.activities.nowPlayingStream", "键名不变")

        // 没设过（nil）：跟 1.0.16 默认值总账走（设计上默认开，真机验过前关）。
        expect(D.state(forKey: D.musicKey, in: suite) == .unset && D.state(forKey: D.streamKey, in: suite) == .unset, "没设过")
        expect(D.musicEnabled(in: suite) == ReleaseDefaults.value(D.musicKey) && D.streamEnabled(in: suite) == ReleaseDefaults.value(D.streamKey), "两个键没设过：跟总账走")
        expect(!D.musicEnabled(in: suite) && !D.streamEnabled(in: suite), "没验过：都是关")
        expect(!D.streamExplicitlyEnabled(in: suite), "没设过不算“显式开过”（离开就锁暂停媒体沿用老行为）")

        // 显式关：保持关。
        suite.set(false, forKey: D.musicKey); suite.set(false, forKey: D.streamKey)
        expect(D.state(forKey: D.musicKey, in: suite) == .off && D.state(forKey: D.streamKey, in: suite) == .off, "显式关")
        expect(!D.musicEnabled(in: suite) && !D.streamEnabled(in: suite), "显式关过的不变")

        // 显式开：开。
        suite.set(true, forKey: D.musicKey); suite.set(true, forKey: D.streamKey)
        expect(D.state(forKey: D.musicKey, in: suite) == .on, "显式开")
        expect(D.musicEnabled(in: suite) && D.streamEnabled(in: suite) && D.streamExplicitlyEnabled(in: suite), "显式开过的还是开")

        // 两个键互不影响；清掉后回到总账的值。
        suite.set(false, forKey: D.musicKey)
        expect(!D.musicEnabled(in: suite) && D.streamEnabled(in: suite), "音乐关了，推送流的开关不受影响（推送流显式开着）")
        suite.removeObject(forKey: D.musicKey)
        expect(D.musicEnabled(in: suite) == ReleaseDefaults.value(D.musicKey), "清掉键 = 回到总账的值")
        // 不是布尔值的脏数据按没设过算。
        suite.set("no", forKey: D.streamKey)
        expect(D.state(forKey: D.streamKey, in: suite) == .unset && D.streamEnabled(in: suite) == ReleaseDefaults.value(D.streamKey), "脏数据按没设过算")
    }
}
