// 正在播放推送流（计划 2-1）的行为测试：解析器、切行缓冲、退路决策与重启间隔。
// 纯 swiftc @main 入口，无权限、无 UI、无网络、不启动子进程。

import Foundation

@main struct NowPlayingStreamTests {
    static func expect(_ condition: Bool, _ message: String) {
        precondition(condition, "断言失败: \(message)")
    }

    static func update(_ result: NowPlayingParse) -> NowPlayingInfo?? {
        if case .update(let info) = result { return .some(info) }
        return nil
    }

    static func main() {
        testPlayingPausedStopped()
        testMissingFields()
        testMalformedLinesIgnored()
        testArtworkNotRetained()
        testDiffMerge()
        testProgress()
        testLineBuffer()
        testFallbackDecision()
        testRestartBackoff()
        print("PASS now-playing-stream")
    }

    static func testPlayingPausedStopped() {
        var parser = NowPlayingStreamParser()
        let playing = #"{"type":"data","diff":false,"payload":{"bundleIdentifier":"com.tidal.desktop","playing":true,"title":"Song","artist":"Band","durationMicros":200000000,"elapsedTimeMicros":50000000,"timestampEpochMicros":1700000000000000,"playbackRate":1}}"#
        guard let first = update(parser.consume(playing)), let info = first else { return expect(false, "播放中的行要给出现状") }
        expect(info.title == "Song" && info.artist == "Band" && info.isPlaying, "播放中：标题、艺人、在放")
        expect(info.bundleID == "com.tidal.desktop", "任何播放器都认，不限 Music/Spotify")
        expect(info.duration == 200 && info.elapsed == 50 && info.timestamp == 1_700_000_000, "微秒换成秒")

        let paused = #"{"type":"data","diff":false,"payload":{"bundleIdentifier":"com.tidal.desktop","playing":false,"title":"Song","artist":"Band"}}"#
        guard let second = update(parser.consume(paused)), let pausedInfo = second else { return expect(false, "暂停的行要给出现状") }
        expect(!pausedInfo.isPlaying && pausedInfo.title == "Song", "暂停：仍有卡片，标为暂停")

        let stopped = #"{"type":"data","diff":false,"payload":{}}"#
        guard let third = update(parser.consume(stopped)) else { return expect(false, "空 payload 是有效行") }
        expect(third == nil, "空 payload：没有播放器，现状为空")
        expect(parser.retainedFieldNames.isEmpty, "非 diff 行整体替换，旧键不残留")
    }

    static func testMissingFields() {
        var parser = NowPlayingStreamParser()
        let noTitle = #"{"type":"data","diff":false,"payload":{"bundleIdentifier":"com.apple.Music","playing":true}}"#
        guard let a = update(parser.consume(noTitle)) else { return expect(false, "缺标题的行仍是有效行") }
        expect(a == nil, "缺标题：当没有播放器")

        let noBundle = #"{"type":"data","diff":false,"payload":{"title":"X","playing":true}}"#
        guard let b = update(parser.consume(noBundle)) else { return expect(false, "缺来源的行仍是有效行") }
        expect(b == nil, "缺来源 App：当没有播放器")

        let minimal = #"{"type":"data","payload":{"bundleIdentifier":"org.videolan.vlc","title":"Clip"}}"#
        guard let c = update(parser.consume(minimal)), let info = c else { return expect(false, "最少字段也要给出现状") }
        expect(info.artist == "" && !info.isPlaying, "缺艺人给空串，缺 playing 当暂停")
        expect(info.duration == nil && info.progress(atEpoch: 0) == nil, "缺时长：没有进度")

        let web = #"{"type":"data","diff":false,"payload":{"bundleIdentifier":"com.apple.WebKit.GPU","parentApplicationBundleIdentifier":"com.apple.Safari","title":"Video","playing":true}}"#
        guard let d = update(parser.consume(web)), let webInfo = d else { return expect(false, "网页播放器要给出现状") }
        expect(webInfo.bundleID == "com.apple.Safari", "网页播放器用宿主 App，点卡片打开浏览器")

        let wrongTypes = #"{"type":"data","diff":false,"payload":{"bundleIdentifier":"a.b","title":"T","playing":"yes","durationMicros":"10","artist":5}}"#
        guard let e = update(parser.consume(wrongTypes)), let typed = e else { return expect(false, "类型不对的键跳过，其余照用") }
        expect(!typed.isPlaying && typed.duration == nil && typed.artist == "", "类型不对的键当缺失")

        let long = String(repeating: "长", count: 400)
        let longLine = #"{"type":"data","diff":false,"payload":{"bundleIdentifier":"a.b","title":""# + long + #""}}"#
        guard let f = update(parser.consume(longLine)), let longInfo = f else { return expect(false, "长标题仍有效") }
        expect(longInfo.title.count == NowPlayingStreamParser.maxTextLength, "标题截到 256 字")
    }

    static func testMalformedLinesIgnored() {
        var parser = NowPlayingStreamParser()
        let good = #"{"type":"data","diff":false,"payload":{"bundleIdentifier":"a.b","title":"Keep","playing":true}}"#
        _ = parser.consume(good)
        for bad in ["", "   ", "not json", "{", "[1,2]", "null",
                    #"{"type":"error","payload":{}}"#, #"{"type":"data","payload":null}"#,
                    #"{"type":"data","payload":[]}"#, #"{"diff":false,"payload":{}}"#] {
            expect(parser.consume(bad) == .ignored, "坏行忽略：\(bad)")
        }
        expect(parser.info?.title == "Keep", "坏行不改变现状")
        let huge = #"{"type":"data","diff":false,"payload":{"title":""# + String(repeating: "x", count: NowPlayingStreamParser.maxLineBytes) + #""}}"#
        expect(parser.consume(huge) == .ignored, "超长行不解析")
        expect(parser.info?.title == "Keep", "超长行不改变现状")
    }

    static func testArtworkNotRetained() {
        var parser = NowPlayingStreamParser()
        let artwork = String(repeating: "QUJD", count: 2000)
        let line = #"{"type":"data","diff":false,"payload":{"bundleIdentifier":"a.b","title":"T","playing":true,"album":"A","artworkMimeType":"image/png","artworkData":""# + artwork + #""}}"#
        guard let result = update(parser.consume(line)), result != nil else { return expect(false, "带封面的行仍给出现状") }
        let kept = parser.retainedFieldNames
        expect(!kept.contains("artworkData") && !kept.contains("artworkMimeType") && !kept.contains("album"), "封面、专辑不进状态")
        expect(kept == ["bundleIdentifier", "title", "playing"], "只留白名单里的键")
    }

    static func testDiffMerge() {
        var parser = NowPlayingStreamParser()
        _ = parser.consume(#"{"type":"data","diff":false,"payload":{"bundleIdentifier":"a.b","title":"One","artist":"X","playing":true}}"#)
        guard let a = update(parser.consume(#"{"type":"data","diff":true,"payload":{"title":"Two"}}"#)), let info = a else { return expect(false, "diff 行叠加") }
        expect(info.title == "Two" && info.artist == "X" && info.isPlaying, "diff 只改变了的键")
        guard let b = update(parser.consume(#"{"type":"data","diff":true,"payload":{"artist":null,"artworkData":"AAAA"}}"#)), let cleared = b else { return expect(false, "diff null") }
        expect(cleared.artist == "" && !parser.retainedFieldNames.contains("artworkData"), "null 删除键；diff 里的封面也不留")
        guard let c = update(parser.consume(#"{"type":"data","diff":true,"payload":{"title":null}}"#)) else { return expect(false, "diff 删标题") }
        expect(c == nil, "标题消失：没有播放器")
    }

    static func testProgress() {
        let playing = NowPlayingInfo(bundleID: "a", title: "t", artist: "", isPlaying: true,
                                     duration: 100, elapsed: 10, timestamp: 1000, rate: 1)
        expect(playing.progress(atEpoch: 1000) == 0.1, "时间戳那一刻")
        expect(playing.progress(atEpoch: 1020) == 0.3, "播放中按经过时间推算")
        expect(playing.progress(atEpoch: 900) == 0.1, "时钟往回走不倒退")
        expect(playing.progress(atEpoch: 5000) == 1, "夹在 1")
        let fast = NowPlayingInfo(bundleID: "a", title: "t", artist: "", isPlaying: true,
                                  duration: 100, elapsed: 10, timestamp: 1000, rate: 2)
        expect(fast.progress(atEpoch: 1010) == 0.3, "倍速按速率推")
        let paused = NowPlayingInfo(bundleID: "a", title: "t", artist: "", isPlaying: false,
                                    duration: 100, elapsed: 10, timestamp: 1000, rate: 0)
        expect(paused.progress(atEpoch: 2000) == 0.1, "暂停不往前走")
        let noTime = NowPlayingInfo(bundleID: "a", title: "t", artist: "", isPlaying: true,
                                    duration: 0, elapsed: 10, timestamp: 1000, rate: 1)
        expect(noTime.progress(atEpoch: 1000) == nil, "时长为 0 没有进度")
    }

    static func testLineBuffer() {
        var buffer = NowPlayingLineBuffer()
        expect(buffer.append(Data("{\"a\":".utf8)).isEmpty, "半行不交出")
        expect(buffer.append(Data("1}\n{\"b\":2}\n{\"c\"".utf8)) == ["{\"a\":1}", "{\"b\":2}"], "跨块拼行、一块多行")
        expect(buffer.append(Data(":3}\n".utf8)) == ["{\"c\":3}"], "剩下的半行下次补齐")
        let big = Data(repeating: 0x78, count: NowPlayingStreamParser.maxLineBytes + 10)
        expect(buffer.append(big).isEmpty, "超长行不交出")
        expect(buffer.append(Data("tail\nok\n".utf8)) == ["ok"], "超长行丢到换行为止，后面的行照常")
    }

    static func testFallbackDecision() {
        typealias P = NotchActivityPollPolicy
        expect(P.musicSource(musicEnabled: false, streamHealthy: true) == .none, "音乐开关关着：不读")
        expect(P.musicSource(musicEnabled: true, streamHealthy: true) == .stream, "推送健康：用推送")
        expect(P.musicSource(musicEnabled: true, streamHealthy: false) == .scripts, "推送挂了：回退 osascript")

        // 推送健康：无论脏不脏、多久没问，都不启动 osascript。
        for dirty in [true, false] {
            for since in [0.0, 31, 3600] {
                expect(!P.shouldAskScripts(source: .stream, hasRunningPlayers: true, dirty: dirty, sinceLastRead: since),
                       "推送健康时不轮询 osascript")
            }
        }
        // 推送挂了：和原来的条件一模一样。
        expect(P.shouldAskScripts(source: .scripts, hasRunningPlayers: true, dirty: true, sinceLastRead: 0), "退路：播放器通知过就问")
        expect(!P.shouldAskScripts(source: .scripts, hasRunningPlayers: true, dirty: false, sinceLastRead: 10), "退路：不脏且未到兜底不问")
        expect(P.shouldAskScripts(source: .scripts, hasRunningPlayers: true, dirty: false, sinceLastRead: 31), "退路：超过 30 秒兜底就问")
        expect(!P.shouldAskScripts(source: .scripts, hasRunningPlayers: false, dirty: true, sinceLastRead: 99), "退路：没有播放器不问")
        expect(!P.shouldAskScripts(source: .none, hasRunningPlayers: true, dirty: true, sinceLastRead: 99), "开关关着不问")

        // 档位：推送挂了照旧（有播放器在跑就进进度档）。
        let scriptsTier = P.tier(hasPlayer: P.hasProgressingPlayer(source: .scripts, streamPlaying: false, hasRunningPlayers: true),
                                 hasRecordingSource: false, hasVisibleCard: false)
        expect(scriptsTier == .progress, "退路：播放器在跑就是进度档，和 PERF-08 一样")
        let streamPaused = P.tier(hasPlayer: P.hasProgressingPlayer(source: .stream, streamPlaying: false, hasRunningPlayers: true),
                                  hasRecordingSource: false, hasVisibleCard: true)
        expect(streamPaused == .source, "推送：暂停时不用 2 秒推进度，退到来源档")
        let streamPlaying = P.tier(hasPlayer: P.hasProgressingPlayer(source: .stream, streamPlaying: true, hasRunningPlayers: false),
                                   hasRecordingSource: false, hasVisibleCard: true)
        expect(streamPlaying == .progress, "推送：在放时进度档只推算进度，不问播放器")
        let off = P.tier(hasPlayer: P.hasProgressingPlayer(source: .none, streamPlaying: true, hasRunningPlayers: true),
                         hasRecordingSource: false, hasVisibleCard: false)
        expect(off == .idle, "开关关着：空闲档")
    }

    static func testRestartBackoff() {
        typealias P = NotchActivityPollPolicy
        expect(P.streamRestartDelay(failures: 0) == nil, "没失败不排重启")
        expect(P.streamRestartDelay(failures: 1) == 1 && P.streamRestartDelay(failures: 2) == 2
               && P.streamRestartDelay(failures: 4) == 8, "按 1、2、4…… 秒退避")
        expect(P.streamRestartDelay(failures: P.streamMaxFailures) == 128, "最后一次 128 秒")
        expect(P.streamRestartDelay(failures: P.streamMaxFailures + 1) == nil, "连续失败太多就停在退路上")
    }
}
