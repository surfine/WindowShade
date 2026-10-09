// 离开就锁（R07B）：折叠→锁的时间表（含退回直接锁）、解锁后只放回这一次自己收的窗口。纯逻辑。
import CoreGraphics
import Foundation

@main
struct PresenceTuckLedgerTests {
    static func token(_ n: UInt64) -> WS2.Token { WS2.Token(bootID: fixtureBoot, serial: n, domain: .presenceLock) }
    static func cand(_ id: CGWindowID, _ pid: Int32) -> BystanderTuckLedger.Candidate { .init(id: id, pid: pid, bundleID: "x") }

    @MainActor static func main() {
        var t = TestSuite("presence-tuck-ledger")

        t.section("R07B-1", "折叠→锁：接受折叠等 0.35 秒，没接受马上锁，任何情况不超过 0.5 秒")
        t.expect(PresenceFoldPlan.lockDelay(foldAccepted: true) == 0.35, "接受折叠：0.35 秒后锁")
        t.expect(PresenceFoldPlan.lockDelay(foldAccepted: false) == 0, "没接受（ScreenCaptureKit 起不来、效果关着）：直接锁")
        t.expect(PresenceFoldPlan.lockDelay(foldAccepted: true, lead: 2) == PresenceFoldPlan.maxLockDelay, "再长的折叠也封顶 0.5 秒")
        t.expect(PresenceFoldPlan.lockDelay(foldAccepted: true, lead: .nan) == 0 && PresenceFoldPlan.lockDelay(foldAccepted: true, lead: -1) == 0,
                 "坏数值退回直接锁")
        t.expect(PresenceFoldPlan.lockDelay(foldAccepted: true) < Double(PresenceLock.lockReceiptTimeout) / Double(WS2.Duration.second),
                 "在锁屏回执期限之内")

        t.section("R07B-2", "解锁后只放回这一次自己收的")
        var ledger = PresenceTuckLedger()
        ledger.recordTucked(cand(1, 10))
        t.expect(ledger.isEmpty, "没开始一次锁屏就不记账")
        ledger.begin(token: token(1))
        ledger.recordTucked(cand(1, 10)); ledger.recordTucked(cand(2, 20)); ledger.recordTucked(cand(3, 30))
        // 窗口 1 还在刘海、同进程；2 被用户拿出来了；3 的进程换了。
        let tucked: [CGWindowID: Int32] = [1: 10, 3: 99]
        t.expect(ledger.takeRestores(for: token(2), tuckedPID: { tucked[$0] }) == [], "令牌不是这一次的：不放回")
        t.expect(ledger.takeRestores(for: token(1), tuckedPID: { tucked[$0] }) == [1], "只放回还在刘海里且同一进程的")
        t.expect(ledger.takeRestores(for: token(1), tuckedPID: { tucked[$0] }) == [] && ledger.isEmpty, "放回一次就忘，不放回第二次")

        t.section("R07B-3", "新的一次锁屏覆盖没放回的旧账；用户自己收的不在账里")
        ledger.begin(token: token(3))
        ledger.recordTucked(cand(5, 50))
        ledger.begin(token: token(4))
        ledger.recordTucked(cand(6, 60))
        let both: [CGWindowID: Int32] = [5: 50, 6: 60, 7: 70]
        t.expect(ledger.takeRestores(for: token(3), tuckedPID: { both[$0] }) == [], "旧令牌作废")
        ledger.begin(token: token(5))
        ledger.recordTucked(cand(6, 60))
        t.expect(ledger.takeRestores(for: token(5), tuckedPID: { both[$0] }) == [6], "用户自己收的 7 不在账里，不替他拿出来")
        ledger.begin(token: token(6)); ledger.recordTucked(cand(6, 60)); ledger.forget()
        t.expect(ledger.takeRestores(for: token(6), tuckedPID: { both[$0] }) == [], "forget 后什么都不放回")

        t.finish()
    }
}
