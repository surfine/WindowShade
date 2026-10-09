// 来处推断询问：两次才问、点击写入、小叉后不再问、每个来处一次（纯逻辑，用单独的偏好域）。
import Foundation

@main
struct OriginGuessTests {
    static var failures = 0
    static func expect(_ condition: Bool, _ message: String) {
        if condition { print("ok   \(message)") } else { failures += 1; print("FAIL \(message)") }
    }

    static func main() {
        // 两次才问；间隔太近的不算第二次。
        var g = OriginGuess()
        expect(!g.note(.windows, at: 100), "first Windows habit does not ask")
        expect(!g.note(.windows, at: 102), "a second press within the gap is not a second recognition")
        expect(g.note(.windows, at: 120), "second recognition asks")
        expect(!g.note(.mac, at: 200) && !g.note(.unanswered, at: 200), "only Windows and iPad can be asked")

        // 每个来处只问一次；两个来处各算各的。
        g.didAsk(.windows)
        expect(!g.note(.windows, at: 400), "Windows is not asked twice")
        expect(!g.note(.ipad, at: 400), "iPad counts on its own")
        expect(g.note(.ipad, at: 500), "iPad asks at its own second recognition")
        g.didAsk(.ipad)
        expect(!g.note(.ipad, at: 900) && !g.note(.ipad, at: 1000), "iPad asked once only")

        // 问不出去（刘海忙）：次数留着，下一次识别到再试。
        var busy = OriginGuess()
        _ = busy.note(.ipad, at: 0)
        expect(busy.note(.ipad, at: 50), "asks at the second recognition")
        expect(busy.note(.ipad, at: 100), "not shown (not marked asked): the next recognition asks again")

        // 小叉：整个不再问。
        var closed = OriginGuess()
        _ = closed.note(.windows, at: 0)
        closed.decline()
        expect(!closed.note(.windows, at: 50), "no question after the close button")
        expect(!closed.note(.ipad, at: 50) && !closed.note(.ipad, at: 100), "the close button also silences the other origin")
        expect(!closed.listens(for: .windows) && !closed.listens(for: .ipad), "nothing left to listen for")

        // 存取：单独的偏好域；默认关。
        let suite = "WindowShade.OriginGuessTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        expect(!OriginGuess.isEnabled(in: defaults), "off by default")
        expect(OriginGuess.load(from: defaults) == OriginGuess(), "nothing stored reads as empty")
        var saved = OriginGuess()
        _ = saved.note(.windows, at: 5)
        saved.didAsk(.ipad)
        saved.save(to: defaults)
        expect(OriginGuess.load(from: defaults) == saved, "round-trips through defaults")
        defaults.set(Data("not json".utf8), forKey: OriginGuess.defaultsKey)
        expect(OriginGuess.load(from: defaults) == OriginGuess(), "garbage reads as empty")

        // 点击写入来处（走 SwitcherOrigin 的存取）。
        expect(SwitcherOrigin.store(.windows, in: defaults, center: NotificationCenter()), "tap writes the origin")
        expect(SwitcherOrigin.stored(in: defaults) == .windows, "origin reads back")

        // 只认键位：哪些规则算哪个来处。
        expect(HabitRule.copy.guessedOrigin == .windows && HabitRule.closeWindow.guessedOrigin == .windows, "⌃C and ⌥F4 point to Windows")
        expect(HabitRule.menuBar.guessedOrigin == .ipad, "menu bar key points to iPad")
        expect(HabitRule.trash.guessedOrigin == nil && HabitRule.hideApp.guessedOrigin == nil && HabitRule.lineEnds.guessedOrigin == nil,
               "keys Mac users also press are not counted")

        if failures > 0 { print("\(failures) failure(s)"); exit(1) }
        print("all passed")
    }
}
