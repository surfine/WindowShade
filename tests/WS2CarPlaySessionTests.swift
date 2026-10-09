// CarPlay 接收端会话生命周期（Core/WS2CarPlaySession.swift）。全部是合成事件，不碰传输与凭据。
import Foundation

struct FakeIdentity: WS2CarPlayAccessoryIdentity {
    var provenance: WS2CarPlayIdentityProvenance
}

@main struct WS2CarPlaySessionTests {
    nonisolated(unsafe) static var failures = 0
    static func expect(_ condition: Bool, _ message: String) {
        if condition { print("ok   \(message)") } else { failures += 1; print("FAIL \(message)") }
    }

    static let apple = FakeIdentity(provenance: .appleIssued)
    typealias S = WS2CarPlaySession

    /// 合成模式连上并就绪。
    static func readyAt(_ now: TimeInterval, _ session: inout S) -> S.Ticket {
        let t = session.connect(identity: nil)!
        session.becameReady(t, at: now)
        return t
    }

    static func main() {
        // 退避序列：2,4,8,16,30，然后放弃
        do {
            var s = S()
            var t = readyAt(0, &s)
            var clock = 5.0
            var delays: [TimeInterval] = []
            var plan = s.ended(t, failed: true, at: clock)
            while case .retry(_, let after) = plan {
                delays.append(after)
                clock += after
                t = s.reconnectIfDue(identity: nil, at: clock)!
                plan = s.ended(t, failed: true, at: clock)
            }
            expect(delays == [2, 4, 8, 16, 30], "backoff 2,4,8,16,30 then stop")
            expect(plan == .gaveUp && s.state == .gaveUp && s.reconnectDueAt == nil, "fifth failed retry gives up")
            expect(s.reconnectIfDue(identity: nil, at: clock + 1000) == nil, "gave up stays down without user action")
            expect(s.connect(identity: nil) != nil && s.reconnectAttempts == 0, "user connect after giving up starts fresh")
        }
        // 没到点不重连
        do {
            var s = S()
            let t = readyAt(0, &s)
            s.ended(t, failed: true, at: 10)
            expect(s.reconnectDueAt == 12, "first retry due 2 s after the loss")
            expect(s.reconnectIfDue(identity: nil, at: 11.9) == nil && s.state == .waitingToReconnect, "not retried early")
            expect(s.reconnectIfDue(identity: nil, at: 12) != nil && s.state == .connecting, "retried when due")
        }
        // 稳定 60 s 清零
        do {
            var s = S()
            var t = readyAt(0, &s)
            s.ended(t, failed: true, at: 1)
            t = s.reconnectIfDue(identity: nil, at: 3)!
            s.becameReady(t, at: 3)
            s.ended(t, failed: true, at: 3 + 59.9)
            expect(s.reconnectAttempts == 2 && s.reconnectDueAt == 3 + 59.9 + 4, "59.9 s of stability does not reset")
            t = s.reconnectIfDue(identity: nil, at: 3 + 59.9 + 4)!
            s.becameReady(t, at: 100)
            s.ended(t, failed: true, at: 160)
            expect(s.reconnectAttempts == 1 && s.reconnectDueAt == 162, "60 s of stability resets to the 2 s step")
            // 不等断开，中途 observe 也能结算
            t = s.reconnectIfDue(identity: nil, at: 162)!
            s.becameReady(t, at: 162)
            s.observe(at: 200)
            expect(s.reconnectAttempts == 1, "observe before 60 s keeps the count")
            s.observe(at: 222)
            expect(s.reconnectAttempts == 0, "observe at 60 s clears the count")
        }
        // 正常结束与主动断开不重连
        do {
            var s = S()
            var t = readyAt(0, &s)
            expect(s.ended(t, failed: false, at: 1) == .none && s.state == .disconnected && s.reconnectDueAt == nil, "clean end does not retry")
            t = readyAt(2, &s)
            s.ended(t, failed: true, at: 3)
            s.disconnect()
            expect(s.state == .disconnected && s.reconnectDueAt == nil && s.reconnectAttempts == 0, "user disconnect cancels the retry")
            expect(s.reconnectIfDue(identity: nil, at: 100) == nil, "no retry after user disconnect")
        }
        // 分辨率与设置：串流中改动等到下次重连
        do {
            let hd = WS2CarPlaySettings(resolution: .init(width: 1920, height: 1080), notchHeight: 40)
            var s = S()
            let t = readyAt(0, &s)
            let first = s.activeSettings
            expect(s.requestSettings(hd) && s.pendingSettings == hd, "new settings are accepted")
            expect(s.activeSettings == first && s.settingsChangePending, "running session keeps its resolution")
            expect(!s.requestSettings(WS2CarPlaySettings(resolution: .init(width: 0, height: 720), notchHeight: 0)) && s.pendingSettings == hd,
                   "invalid resolution is refused")
            s.ended(t, failed: true, at: 10)
            expect(s.activeSettings == first, "waiting for the retry changes nothing yet")
            _ = s.reconnectIfDue(identity: nil, at: 12)
            expect(s.activeSettings == hd && !s.settingsChangePending, "next reconnect uses the new settings")
        }
        // 关键帧：每次显示只请求一次
        do {
            var s = S()
            _ = s.connect(identity: nil)
            expect(!s.enterFullscreen() && s.keyframeRequests == 0, "no keyframe before the session is ready")
            let t = readyAt(0, &s)
            expect(s.enterFullscreen() && s.keyframeRequests == 1, "showing requests one keyframe")
            expect(!s.enterFullscreen() && s.keyframeRequests == 1, "showing again while shown asks nothing")
            s.exitFullscreen()
            expect(s.enterFullscreen() && s.keyframeRequests == 2, "each new show asks once")
            s.ended(t, failed: true, at: 5)
            expect(s.isFullscreen == false, "a lost connection takes the surface down")
        }
        // 帧计数各算各的
        do {
            var s = S()
            let t = readyAt(0, &s)
            for _ in 0..<10 { s.frameReceived(t) }
            expect(s.frames == WS2CarPlayFrameCounters(received: 10, drawn: 0), "hidden frames count as received only")
            s.enterFullscreen()
            for _ in 0..<7 { s.frameReceived(t) }
            for _ in 0..<5 { s.frameDrawn(t) }
            expect(s.frames.received == 17 && s.frames.drawn == 5, "received and drawn move independently")
            let t2 = s.connect(identity: nil)!
            s.frameReceived(t)
            s.frameDrawn(t)
            s.becameReady(t2, at: 1)
            expect(s.frames == WS2CarPlayFrameCounters(), "new connection starts at zero and ignores late frames")
        }
        // 两套边距
        do {
            let layout = WS2CarPlayLayout(notchHeight: 38)
            expect(layout.viewArea == WS2CarPlayInsets(top: 0, left: 0, bottom: 0, right: 0), "view area spans the screen")
            expect(layout.safeArea.top >= 38 && layout.safeArea.top >= layout.viewArea.top, "safe area clears the notch")
            expect(layout.safeArea.left >= layout.viewArea.left && layout.safeArea.bottom >= layout.viewArea.bottom
                   && layout.safeArea.right >= layout.viewArea.right, "safe area stays inside the view area")
            expect(WS2CarPlayLayout(notchHeight: -5).safeArea.top == 0 && WS2CarPlayLayout(notchHeight: .nan).safeArea.top == 0,
                   "nonsense notch height falls back to none")
            var s = S(settings: .init(resolution: .init(width: 1280, height: 720), notchHeight: 32))
            expect(s.layout == nil, "no layout before a session starts")
            _ = s.connect(identity: nil)
            expect(s.layout?.safeArea.top == 32, "layout follows the session's settings")
        }
        // 身份：没有 Apple 签发的身份只能合成
        do {
            var s = S()
            expect(s.connect(identity: nil, wantsLive: true) == nil && s.state == .missingIdentity && s.mode == nil, "live without identity is refused")
            expect(s.connect(identity: FakeIdentity(provenance: .extracted), wantsLive: true) == nil && s.state == .missingIdentity, "extracted identity is refused")
            expect(s.connect(identity: FakeIdentity(provenance: .unknown), wantsLive: true) == nil, "unknown identity is refused")
            s.enterFullscreen()
            expect(!s.isFullscreen && s.becameReadyIsInert(), "refused session never becomes ready")
            let synthetic = s.connect(identity: FakeIdentity(provenance: .extracted))
            expect(synthetic != nil && s.mode == .synthetic, "no identity needed for synthetic mode, and a bad one is never used")
            expect(s.connect(identity: apple, wantsLive: true) != nil && s.mode == .live, "Apple-issued identity allows live")
            // 重连时身份没了：不降级成假的 live
            var r = S()
            let t = r.connect(identity: apple, wantsLive: true)!
            r.becameReady(t, at: 0)
            r.ended(t, failed: true, at: 1)
            expect(r.reconnectIfDue(identity: nil, at: 3) == nil && r.state == .missingIdentity, "identity gone at reconnect stops instead of downgrading")
        }
        // 会话不持有窗口状态
        do {
            let names = Mirror(reflecting: S()).children.compactMap(\.label).map { $0.lowercased() }
            expect(!names.contains { $0.contains("window") || $0.contains("snapshot") || $0.contains("rect") },
                   "session stores no window state")
            var s = S()
            let t = readyAt(0, &s)
            s.enterFullscreen()
            s.exitFullscreen()
            expect(s.state == .ready && s.ticket == t && !s.isFullscreen, "leaving returns to the desktop and keeps the phone connected")
        }
        // 迟到事件
        do {
            var s = S()
            let old = readyAt(0, &s)
            let current = s.connect(identity: nil)!
            s.becameReady(current, at: 1)
            s.enterFullscreen()
            expect(s.ended(old, failed: true, at: 2) == .none && s.state == .ready && s.isFullscreen, "stale end does not hurt the new session")
            s.disconnect()
            s.becameReady(current, at: 3)
            s.ended(current, failed: true, at: 4)
            expect(s.state == .disconnected && s.reconnectDueAt == nil, "events after disconnect are ignored")
        }

        // 验收场景：冷启动
        do {
            var s = S()
            let t = s.connect(identity: nil)!
            expect(s.state == .connecting && s.mode == .synthetic, "cold start: connects in synthetic mode")
            s.becameReady(t, at: 1.5)
            expect(s.enterFullscreen(), "cold start: first show asks for a keyframe")
            for _ in 0..<30 { s.frameReceived(t); s.frameDrawn(t) }
            expect(s.frames.received == 30 && s.frames.drawn == 30 && s.reconnectAttempts == 0, "cold start: first second plays clean")
        }
        // 验收场景：反复重连
        do {
            var s = S()
            var clock = 0.0
            var t = readyAt(clock, &s)
            var cycles = 0
            // 每轮连上后撑过 61 s 再掉线：永远只等 2 s，不会用完次数
            for _ in 0..<20 {
                clock += 61
                guard case .retry(_, let after) = s.ended(t, failed: true, at: clock), after == 2 else { break }
                clock += after
                guard let next = s.reconnectIfDue(identity: nil, at: clock) else { break }
                t = next
                s.becameReady(t, at: clock)
                s.enterFullscreen()
                cycles += 1
            }
            expect(cycles == 20 && s.state == .ready && s.keyframeRequests == 20, "repeated reconnect: 20 stable cycles never exhaust the budget, one keyframe per show")
            // 反复闪断：5 次后放弃，而不是无限重试
            var flaps = 0
            s = S()
            clock = 0
            t = readyAt(clock, &s)
            var plan = s.ended(t, failed: true, at: clock + 1)
            clock += 1
            while case .retry(_, let after) = plan {
                clock += after
                t = s.reconnectIfDue(identity: nil, at: clock)!
                s.becameReady(t, at: clock)
                clock += 1
                plan = s.ended(t, failed: true, at: clock)
                flaps += 1
            }
            expect(flaps == 5 && plan == .gaveUp, "repeated reconnect: rapid flapping stops after 5 attempts")
        }
        // 验收场景：长时间播放
        do {
            var s = S()
            let t = readyAt(0, &s)
            s.enterFullscreen()
            let fps = 30.0
            let total = Int(fps * 3600)
            var inFlight = 0
            for i in 0..<total {
                s.frameReceived(t)
                inFlight += 1
                if i % 1000 == 0 { s.observe(at: Double(i) / fps) }
                if inFlight > 2 { s.frameDrawn(t); inFlight -= 1 }
            }
            while inFlight > 0 { s.frameDrawn(t); inFlight -= 1 }
            expect(s.frames.received == total && s.frames.drawn == total, "long playback: one hour, every received frame drawn")
            expect(s.state == .ready && s.keyframeRequests == 1 && s.reconnectAttempts == 0, "long playback: no extra keyframes or reconnects")
            s.ended(t, failed: true, at: 3600)
            expect(s.reconnectDueAt == 3602, "long playback: a drop after an hour starts again at 2 s")
        }

        if failures > 0 { print("\(failures) FAILED"); exit(1) }
        print("PASS CarPlay session")
    }
}

extension WS2CarPlaySession {
    /// 被拒绝的会话没有票据，任何就绪事件都应无效。
    fileprivate func becameReadyIsInert() -> Bool {
        var copy = self
        copy.becameReady(Ticket(), at: 0)
        return copy.state == .missingIdentity
    }
}
