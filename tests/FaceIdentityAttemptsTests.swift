// 认出你的次数与节奏（Core/FaceIdentityAttempts.swift）：§3.8 表逐行。
import Foundation

@main
struct FaceIdentityAttemptsTests {
  nonisolated(unsafe) static var failures = 0
  static func expect(_ condition: Bool, _ message: String) {
    if condition { print("ok   \(message)") } else { failures += 1; print("FAIL \(message)") }
  }

  static func main() {
    // 行 1：画质不够，不计
    do {
      var a = FaceIdentityAttempts()
      for _ in 0..<10 {
        expect(a.begin(.screenWake, lockGeneration: 1), "wake starts an attempt")
        let d = a.record(.qualityInsufficient(.tooDark), lockGeneration: 1)
        expect(!d.counted && d.remaining == 3 && !d.lockedOut, "quality failure never counts")
        expect(d.notice == FaceIdentityNotice(primary: "光线太暗", secondary: nil, holdSeconds: 0), "shows the one hint, no hold")
      }
      expect(a.used == 0, "ten quality misses still leave all three tries")
      a.begin(.screenWake, lockGeneration: 1)
      expect(a.record(.qualityInsufficient(nil), lockGeneration: 1).notice == nil, "quality miss without a hint says nothing")
    }

    // 行 2、3、4：认错 / 挑战 / 否决各计 1，说同一句话
    do {
      var a = FaceIdentityAttempts()
      a.begin(.screenWake, lockGeneration: 1)
      let m = a.record(.mismatch, lockGeneration: 1)
      expect(m.counted && m.remaining == 2 && m.notice == .notRecognized, "mismatch counts one and says not recognized")
      expect(m.notice?.holdSeconds == 2.6 && m.notice?.secondary == "用 Touch ID 或密码", "holds 2.6 s and points to system auth")
      a.begin(.spaceKey, lockGeneration: 1)
      let c = a.record(.challengeFailed, lockGeneration: 1)
      expect(c.counted && c.remaining == 1 && c.notice == m.notice, "challenge failure counts and says the same thing")
      var b = FaceIdentityAttempts()
      b.begin(.screenWake, lockGeneration: 1)
      let v = b.record(.vetoCue(label: "deny(bezel)"), lockGeneration: 1)
      expect(v.counted && v.notice == .notRecognized && v.logLabel == "deny(bezel)", "veto counts, same words, label only for the log")
      expect(m.logLabel == nil && c.logLabel == nil, "no label for non-veto failures")
      expect(![m.notice?.primary, m.notice?.secondary].compactMap { $0 }.contains { $0.contains("bezel") || $0.contains("转头") },
             "the notice never says which step failed")
    }

    // 行 5：满 3 次
    do {
      var a = FaceIdentityAttempts()
      for i in 1...3 {
        expect(a.begin(.screenWake, lockGeneration: 4), "attempt \(i) may start")
        let d = a.record(.mismatch, lockGeneration: 4)
        if i < 3 { expect(!d.lockedOut && d.notice == .notRecognized, "attempt \(i) is not the last") }
        else { expect(d.lockedOut && d.remaining == 0 && d.notice == .lockedOut, "third failure locks out: use the password") }
      }
      expect(a.lockedOut && !a.begin(.screenWake, lockGeneration: 4) && !a.begin(.spaceKey, lockGeneration: 4), "no camera after three, wake or space")
      expect(FaceIdentityNotice.lockedOut.secondary == "已试了 3 次", "lockout copy")
      expect(a.begin(.screenWake, lockGeneration: 5) && a.used == 0, "a new lock starts over")
    }

    // 行 6：相机被挡 / 被占用 / 打断，不计，不出现
    do {
      var a = FaceIdentityAttempts()
      a.begin(.screenWake, lockGeneration: 1)
      let blocked = a.record(.cameraUnavailable, lockGeneration: 1)
      expect(!blocked.counted && blocked.notice == nil && blocked.remaining == 3, "blocked camera: no count, nothing shown")
      a.begin(.screenWake, lockGeneration: 1)
      let cut = a.record(.interrupted, lockGeneration: 1)
      expect(!cut.counted && cut.notice == nil && a.used == 0, "interruption does not count")
    }

    // 行 7：空格重试计入同一上限
    do {
      var a = FaceIdentityAttempts()
      a.begin(.screenWake, lockGeneration: 1)
      _ = a.record(.mismatch, lockGeneration: 1)
      expect(a.begin(.spaceKey, lockGeneration: 1), "space retries after a failure")
      expect(!a.begin(.spaceKey, lockGeneration: 1), "space while an attempt is running does nothing")
      _ = a.record(.mismatch, lockGeneration: 1)
      expect(a.begin(.spaceKey, lockGeneration: 1), "second retry")
      let last = a.record(.challengeFailed, lockGeneration: 1)
      expect(last.lockedOut && !a.begin(.spaceKey, lockGeneration: 1), "retries share the cap of three")
    }

    // 同一次锁屏多次亮屏不重置；代次不对的上报不记
    do {
      var a = FaceIdentityAttempts()
      a.begin(.screenWake, lockGeneration: 2)
      _ = a.record(.mismatch, lockGeneration: 2)
      a.begin(.screenWake, lockGeneration: 2)
      expect(a.used == 1 && a.remaining == 2, "re-waking in the same lock keeps the count")
      let stale = a.record(.mismatch, lockGeneration: 1)
      expect(!stale.counted && a.used == 1, "a report from an old lock generation is ignored")
      _ = a.record(.mismatch, lockGeneration: 2)
      let dup = a.record(.mismatch, lockGeneration: 2)
      expect(!dup.counted && a.used == 2, "a duplicate report with no attempt running is ignored")
      var fresh = FaceIdentityAttempts()
      expect(!fresh.record(.mismatch, lockGeneration: 9).counted, "nothing to record before any attempt")
    }

    if failures > 0 { print("\(failures) failure(s)"); exit(1) }
    print("FaceIdentityAttemptsTests passed (counting only, never unlock)")
  }
}
