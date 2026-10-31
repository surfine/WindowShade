import Foundation

// 决定 74：锁屏时用 iPhone 那条 Pair-Verify 连线当第二道——时限、挑战绑在这次锁屏和随机数上、锁着时拒绝一切命令。

@main
struct CompanionLockVerifyTests {
    typealias V = CompanionLockVerify

    static func lockedOpen(at now: Double = 100) -> CompanionLockVerifier {
        var verifier = CompanionLockVerifier()
        verifier.setLocked(true)
        verifier.openWindow(now: now)
        return verifier
    }

    static func main() {
        var t = TestSuite("CompanionLockVerify")

        t.section("CLV-01", "an answered, fresh challenge on a live link is verified")
        var v = lockedOpen()
        let c = v.issue(nonce: 7, now: 100)
        t.expect(c != nil, "challenge issued inside the window")
        t.expect(v.status(now: 100, linkAlive: true) == .presentUnverified, "a live link alone is not verified")
        t.expect(v.answer(nonce: 7, epoch: c!.epoch, now: 101).ok, "answer accepted")
        t.expect(v.status(now: 101, linkAlive: true) == .verified, "verified right after the answer")
        t.expect(v.status(now: 101 + V.freshness, linkAlive: true) == .verified, "still verified at the freshness edge")

        t.section("CLV-02", "freshness: an old proof falls back to presentUnverified")
        t.expect(v.status(now: 101 + V.freshness + 0.01, linkAlive: true) == .presentUnverified, "proof older than freshness")
        t.expect(v.status(now: 101, linkAlive: false) == .presentUnverified, "proof without a live link is not verified")
        t.expect(v.status(now: 50, linkAlive: true) == .presentUnverified, "clock going backwards does not verify")
        t.expect(v.status(now: .nan, linkAlive: true) == .presentUnverified, "NaN clock does not verify")
        t.expect(CompanionLockVerifier().status(now: 1, linkAlive: false) == .absent, "nothing at all is absent")

        t.section("CLV-03", "a challenge answered too late is stale and does not verify")
        var late = lockedOpen()
        let lc = late.issue(nonce: 9, now: 100)!
        t.expect(late.answer(nonce: 9, epoch: lc.epoch, now: 100 + V.freshness + 1).rejection == .stale, "late answer is stale")
        t.expect(late.status(now: 111, linkAlive: true) == .presentUnverified, "stale answer leaves it unverified")

        t.section("CLV-04", "replay: a nonce answers once; unknown nonces never answer")
        var once = lockedOpen()
        let oc = once.issue(nonce: 11, now: 100)!
        t.expect(once.answer(nonce: 11, epoch: oc.epoch, now: 100.5).ok, "first answer")
        t.expect(once.answer(nonce: 11, epoch: oc.epoch, now: 100.6).rejection == .unknownNonce, "second answer with the same nonce")
        t.expect(once.answer(nonce: 12, epoch: oc.epoch, now: 100.6).rejection == .unknownNonce, "nonce never issued")
        var dup = lockedOpen()
        t.expect(dup.issue(nonce: 5, now: 100) != nil && dup.issue(nonce: 5, now: 100) == nil, "duplicate nonce refused")
        t.expect(dup.issue(nonce: 0, now: 100) == nil, "zero nonce refused")

        t.section("CLV-05", "binding to this lock: unlock or re-lock voids challenges and proofs")
        var relock = lockedOpen()
        let rc = relock.issue(nonce: 21, now: 100)!
        relock.setLocked(false); relock.setLocked(true); relock.openWindow(now: 101)
        t.expect(relock.answer(nonce: 21, epoch: rc.epoch, now: 101).rejection == .oldLock, "challenge from the previous lock")
        var proven = lockedOpen()
        let pc = proven.issue(nonce: 22, now: 100)!
        _ = proven.answer(nonce: 22, epoch: pc.epoch, now: 100.2)
        proven.setLocked(false)
        t.expect(proven.status(now: 100.3, linkAlive: true) == .presentUnverified, "unlocked: proof gone")
        proven.setLocked(true)
        t.expect(proven.status(now: 100.4, linkAlive: true) == .presentUnverified, "re-locked: old proof does not carry over")
        var reset = lockedOpen()
        let sc = reset.issue(nonce: 23, now: 100)!
        reset.reset()
        t.expect(reset.locked && reset.answer(nonce: 23, epoch: sc.epoch, now: 100.1).rejection == .oldLock, "reset keeps the lock but voids challenges")

        t.section("CLV-06", "duty cycle: no window, no challenge; the window ends and can be extended")
        var closed = CompanionLockVerifier()
        closed.setLocked(true)
        t.expect(closed.issue(nonce: 1, now: 100) == nil, "locked but no wake: no challenge")
        var unlocked = CompanionLockVerifier()
        t.expect(!unlocked.openWindow(now: 100) && unlocked.issue(nonce: 1, now: 100) == nil, "not locked: no window")
        var w = lockedOpen(at: 100)
        t.expect(w.isWindowOpen(now: 100 + V.window) && !w.isWindowOpen(now: 100.01 + V.window), "window lasts exactly V.window")
        t.expect(w.issue(nonce: 3, now: 100.01 + V.window) == nil, "no challenge after the window")
        w.openWindow(now: 110)
        t.expect(w.isWindowOpen(now: 110 + V.window), "a second wake extends the window")
        w.openWindow(now: 105)
        t.expect(w.isWindowOpen(now: 110 + V.window), "an earlier wake never shortens it")
        var cap = lockedOpen()
        for n in 1...UInt32(V.maximumOutstanding) { _ = cap.issue(nonce: n, now: 100) }
        t.expect(cap.issue(nonce: 99, now: 100) == nil, "outstanding challenges are capped")
        t.expect(cap.issue(nonce: 99, now: 100 + V.freshness + 1) != nil, "expired challenges free their slots")
        cap.withdraw(nonce: 99)
        t.expect(cap.outstandingCount == 0, "withdraw removes a challenge")

        t.section("CLV-07", "locked: every command is refused; only a reply to a challenge counts")
        let commands: [(String, V.Refusal)] = [
            ("_hidC", .input), ("_hidT", .input), ("_touchStart", .input), ("_tiStart", .input),
            ("_mcc", .media), ("MediaControlCommand", .media),
            ("_sessionStart", .session), ("TVRCSessionStart", .session), ("_sessionStop", .session),
            ("_systemInfo", .profile), ("_interest", .profile), ("FetchAttentionState", .profile),
            ("_launchApp", .profile), ("somethingNew", .other),
        ]
        for (method, reason) in commands {
            for kind: UInt64 in [1, 2] {
                t.expect(V.classify(kind: kind, method: method, transaction: 42) == .refuse(reason), "\(method) _t=\(kind) refused as \(reason)")
            }
        }
        t.expect(V.classify(kind: 2, method: V.echoMethod, transaction: 42) == .refuse(.other), "a request for our own echo method is still refused")
        t.expect(V.classify(kind: nil, method: nil, transaction: nil) == .refuse(.other), "empty envelope refused")
        t.expect(V.classify(kind: 3, method: "_hidC", transaction: 42) == .verifyAnswer(nonce: 42), "a reply carries only its transaction")
        t.expect(V.classify(kind: 3, method: nil, transaction: nil) == .refuse(.reply), "reply without transaction")
        t.expect(V.classify(kind: 3, method: nil, transaction: 0) == .refuse(.reply), "reply with zero transaction")
        t.expect(V.classify(kind: 3, method: nil, transaction: UInt64(UInt32.max) + 1) == .refuse(.reply), "reply transaction out of nonce range")

        t.finish()
    }
}

extension Result where Success == Void {
    var ok: Bool { if case .success = self { return true }; return false }
    var rejection: Failure? { if case .failure(let failure) = self { return failure }; return nil }
}
