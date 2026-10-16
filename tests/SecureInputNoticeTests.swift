// R17：安全输入说明的时机——没用过快捷键不说，刚开才说，一次安全输入只说一次。纯逻辑。
import Foundation

@main
struct SecureInputNoticeTests {
  static var failures = 0
  static func expect(_ condition: Bool, _ message: String) {
    if condition { print("ok   \(message)") } else { failures += 1; print("FAIL \(message)") }
  }

  static func main() {
    // 没用过快捷键：安全输入怎么开关都不说。
    var idle = SecureInputNoticeGate()
    expect(!idle.sample(secure: false, at: 10), "never used a shortcut: nothing to watch")
    expect(!idle.sample(secure: true, at: 11), "never used a shortcut: Secure Input turning on stays silent")

    // 用过快捷键，之后安全输入从关变开：说一次。
    var gate = SecureInputNoticeGate()
    gate.shortcutUsed(at: 100, secureNow: false)
    expect(!gate.sample(secure: false, at: 101), "armed, Secure Input off: silent")
    expect(gate.sample(secure: true, at: 102), "armed, Secure Input turns on: say it")
    expect(!gate.sample(secure: true, at: 103), "still on: do not repeat")
    expect(!gate.sample(secure: true, at: 150), "much later in the same session: still once")
    // 关掉再开才是新的一次。
    expect(!gate.sample(secure: false, at: 160), "turned off: silent")
    expect(gate.sample(secure: true, at: 170), "turned on again: a new session, say it again")

    // 盯之前就已经开着的：说明快捷键当时是好的，不是“刚开”。
    var already = SecureInputNoticeGate()
    already.shortcutUsed(at: 100, secureNow: true)
    expect(!already.sample(secure: true, at: 101), "already on when we started watching: silent")
    expect(!already.sample(secure: false, at: 102), "then it goes off: silent")
    expect(already.sample(secure: true, at: 103), "and a later turn-on inside the window speaks")

    // 超过盯的时间就不看了；再用一次快捷键续上。
    var lapsed = SecureInputNoticeGate()
    lapsed.shortcutUsed(at: 100, secureNow: false)
    expect(lapsed.isArmed(at: 100 + SecureInputNoticeGate.watchWindow - 1), "armed inside the window")
    expect(!lapsed.isArmed(at: 100 + SecureInputNoticeGate.watchWindow), "not armed once the window is over")
    expect(!lapsed.sample(secure: true, at: 100 + SecureInputNoticeGate.watchWindow + 5), "past the window: silent")
    lapsed.shortcutUsed(at: 400, secureNow: true)
    expect(!lapsed.sample(secure: true, at: 401), "re-armed while a session is on: baseline is on, silent")
    var extended = SecureInputNoticeGate()
    extended.shortcutUsed(at: 100, secureNow: false)
    extended.shortcutUsed(at: 200, secureNow: false)
    expect(extended.sample(secure: true, at: 280), "using a shortcut again extends the window")

    if failures == 0 { print("PASS: Secure Input notice — armed only after shortcut use, once per session") }
    else { print("FAILED \(failures)"); exit(1) }
  }
}
