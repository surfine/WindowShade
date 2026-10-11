// CarPlay 全屏的纯映射（Core/WS2CarPlaySurfaceModel.swift）：会话状态 -> 画什么、写什么。
import Foundation

struct ExtractedIdentity: WS2CarPlayAccessoryIdentity {
    var provenance: WS2CarPlayIdentityProvenance { .extracted }
}

@main struct WS2CarPlaySurfaceModelTests {
    nonisolated(unsafe) static var failures = 0
    static func expect(_ condition: Bool, _ message: String) {
        if condition { print("ok   \(message)") } else { failures += 1; print("FAIL \(message)") }
    }
    typealias S = WS2CarPlaySession
    typealias M = WS2CarPlaySurfaceModel

    static func main() {
        // 还没连：写“连接 iPhone”，不画方块，不给重连
        do {
            let d = M.display(for: S(), hasStarted: false, now: 0)
            expect(d.phase == .waiting && d.title == "连接 iPhone", "never connected says 连接 iPhone")
            expect(!d.showsTiles && !d.offersReconnect, "waiting draws no tiles and offers no reconnect")
        }
        // 连接中
        var s = S()
        let t = s.connect(identity: nil)!
        do {
            let d = M.display(for: s, hasStarted: true, now: 0)
            expect(d.phase == .connecting && !d.showsTiles, "connecting has no tiles")
        }
        // 合成已连接：画方块，并且写明是示意
        s.becameReady(t, at: 1)
        do {
            let d = M.display(for: s, hasStarted: true, now: 1)
            expect(d.phase == .connectedSynthetic && d.showsTiles, "ready synthetic shows abstract tiles")
            expect(d.title == "示意画面" && d.detail == "不是 iPhone 的画面", "synthetic connected is labelled as illustration")
            expect(s.mode == .synthetic, "session stays synthetic")
        }
        // 失败：重连 n/5 与下一次的等待
        let plan = s.ended(t, failed: true, at: 10)
        expect(plan == .retry(attempt: 1, after: 2), "first retry after 2 s")
        let reconnectingPhase = M.display(for: s, hasStarted: true, now: 10)
        do {
            let d = reconnectingPhase
            expect(d.phase == .reconnecting(attempt: 1, of: 5, afterSeconds: 2), "reconnecting 1 of 5, 2 s")
            expect(d.detail == "第 1 次，共 5 次，2 秒后再试", "reconnecting detail wording")
            expect(!d.showsTiles && !d.offersReconnect, "reconnecting draws no tiles")
            let later = M.display(for: s, hasStarted: true, now: 11.2)
            expect(later.phase == .reconnecting(attempt: 1, of: 5, afterSeconds: 1), "remaining rounds up, minimum 1 while waiting")
            let past = M.display(for: s, hasStarted: true, now: 99)
            expect(past.phase == .reconnecting(attempt: 1, of: 5, afterSeconds: 0), "past due shows 0")
        }
        // 放弃
        do {
            var g = S()
            var tk = g.connect(identity: nil)!
            var clock = 0.0
            var delays: [Int] = []
            var p = g.ended(tk, failed: true, at: clock)
            while case .retry(_, let after) = p {
                delays.append(M.reconnectSeconds(due: g.reconnectDueAt, now: clock))
                clock += after
                tk = g.reconnectIfDue(identity: nil, at: clock)!
                p = g.ended(tk, failed: true, at: clock)
            }
            expect(delays == [2, 4, 8, 16, 30], "displayed delays follow the backoff")
            let d = M.display(for: g, hasStarted: true, now: clock)
            expect(d.phase == .gaveUp && d.offersReconnect && d.detail == "试了 5 次，都没连上", "gave up offers reconnect")
        }
        // 正常结束或用户断开：说断了，留在全屏等决定
        var endedDisplay: WS2CarPlaySurfaceDisplay
        do {
            var e = S()
            let tk = e.connect(identity: nil)!
            e.becameReady(tk, at: 0)
            _ = e.ended(tk, failed: false, at: 5)
            let d = M.display(for: e, hasStarted: true, now: 5)
            endedDisplay = d
            expect(d.phase == .disconnected && d.title == "连接断了" && d.offersReconnect, "ended says it dropped and offers reconnect")
        }
        // 缺身份（实况模式没有 Apple 签发的身份）
        var missing: WS2CarPlaySurfaceDisplay
        do {
            var l = S()
            _ = l.connect(identity: ExtractedIdentity(), wantsLive: true)
            let d = M.display(for: l, hasStarted: true, now: 0)
            missing = d
            expect(d.phase == .needsIdentity && !d.showsTiles, "extracted identity never shows tiles")
        }
        // 外部接收器（live）：等画面时说明在等，出画面后整块让开
        var liveWaiting: WS2CarPlaySurfaceDisplay
        var liveVideo: WS2CarPlaySurfaceDisplay
        do {
            var l = S()
            let t = l.connectViaReceiver()!
            l.becameReady(t, at: 0)
            let d = M.display(for: l, hasStarted: true, now: 0, liveVideoStarted: false, phoneName: nil)
            liveWaiting = d
            expect(d.phase == .connectedLive(phoneName: nil) && !d.showsTiles && !d.showsLiveVideo,
                   "receiver ready before first frame says it is waiting for video")
            expect(d.title == "等待 iPhone 的画面" && d.detail == "iPhone 已连上接收器",
                   "receiver waiting wording stays honest")
            let v = M.display(for: l, hasStarted: true, now: 0, liveVideoStarted: true, phoneName: "Aaron 的 iPhone")
            liveVideo = v
            expect(v.phase == .connectedLive(phoneName: "Aaron 的 iPhone") && v.showsLiveVideo && !v.showsTiles,
                   "receiver video phase shows live video and no tiles")
            expect(v.title == "Aaron 的 iPhone" && v.detail == nil, "live video shows the phone name only")
        }
        // 每个状态都有符号和标题，不含实现词
        do {
            let all = [M.display(for: S(), hasStarted: false, now: 0), reconnectingPhase, endedDisplay, missing, liveWaiting, liveVideo]
            let banned = ["AirPlay", "iAP2", "CarPlay", "ticket", "state", "NWConnection"]
            expect(all.allSatisfy { !$0.symbol.isEmpty && !$0.title.isEmpty }, "every display has symbol and title")
            expect(all.allSatisfy { d in banned.allSatisfy { !d.title.contains($0) && !(d.detail ?? "").contains($0) } }, "no implementation words in user strings")
            expect(!M.exitHint.contains("CarPlay"), "exit hint avoids someone else's product name")
        }
        // 安全区：内容让开刘海
        do {
            var settings = WS2CarPlaySettings.standard
            settings.notchHeight = 38
            var n = S(settings: settings)
            _ = n.connect(identity: nil)
            expect(M.contentTopInset(layout: n.layout) == 38 + 24, "content clears the notch safe area plus margin")
            expect(M.contentTopInset(layout: nil) == 24, "no layout still keeps margin")
            expect(M.contentTopInset(layout: WS2CarPlayLayout(notchHeight: .nan)) == 24, "non-finite notch height is treated as zero")
        }
        // 方块：在 0...1 内
        do {
            let tiles = M.tileRects()
            expect(tiles.count == 8, "eight tiles by default")
            expect(tiles.allSatisfy { $0.x >= 0 && $0.y >= 0 && $0.x + $0.width <= 1.0000001 && $0.y + $0.height <= 1.0000001 }, "tiles stay inside the content area")
            expect(M.tileRects(columns: 0).isEmpty, "zero columns draws nothing")
        }
        // 合成脚本
        do {
            expect(WS2CarPlaySyntheticScript(environmentValue: nil) == .connect, "default script connects")
            expect(WS2CarPlaySyntheticScript(environmentValue: "garbage") == .connect, "unknown script falls back to connect")
            expect(WS2CarPlaySyntheticScript(environmentValue: "FAIL") == .fail, "script name is case-insensitive")
            expect(WS2CarPlaySyntheticScript.idle.outcome(attempt: 0) == .nothing, "idle does nothing")
            expect(WS2CarPlaySyntheticScript.fail.outcome(attempt: 7) == .fails, "fail always fails")
            expect([0, 1, 2].map { WS2CarPlaySyntheticScript.flaky.outcome(attempt: $0) } == [.fails, .fails, .becomesReady], "flaky recovers on the third attempt")
        }
        if failures > 0 { print("\(failures) failure(s)"); exit(1) }
        print("all passed")
    }
}
