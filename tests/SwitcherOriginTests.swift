// 从哪来（欢迎窗口第二步、设置里的“之前常用”）的存取和通知：纯逻辑，用单独的偏好域，不碰用户的设置。
import Foundation

@main
struct SwitcherOriginTests {
    static var failures = 0
    static func expect(_ condition: Bool, _ message: String) {
        if condition { print("ok   \(message)") } else { failures += 1; print("FAIL \(message)") }
    }

    static func main() {
        let suite = "WindowShade.SwitcherOriginTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let center = NotificationCenter()
        var posted: [String?] = []
        let token = center.addObserver(forName: SwitcherOrigin.didChangeNotification, object: nil, queue: nil) { note in
            posted.append(note.userInfo?[SwitcherOrigin.previousKey] as? String)
        }
        defer { center.removeObserver(token) }

        // 新装、老用户升级：没有这个键，就是没答。
        expect(SwitcherOrigin.stored(in: defaults) == .unanswered, "nothing stored reads as unanswered")

        // 答了 Windows：存下来、发一次通知，通知里带着原来的“没答”。
        expect(SwitcherOrigin.store(.windows, in: defaults, center: center), "answering Windows counts as a change")
        expect(SwitcherOrigin.stored(in: defaults) == .windows, "Windows reads back")
        expect(defaults.string(forKey: SwitcherOrigin.defaultsKey) == "windows", "stored under the documented key and raw value")
        expect(posted == ["unanswered"], "one notification carrying the previous answer (got \(posted))")

        // 再点一次同一个：不写、不发通知（设置页重建、欢迎窗口重开时不会连发）。
        expect(!SwitcherOrigin.store(.windows, in: defaults, center: center), "picking the same answer again is not a change")
        expect(posted.count == 1, "no notification when nothing changed")

        // 设置里改成 iPad、再改成一直用 Mac：每次都通知，previous 跟着走。
        SwitcherOrigin.store(.ipad, in: defaults, center: center)
        SwitcherOrigin.store(.mac, in: defaults, center: center)
        expect(SwitcherOrigin.stored(in: defaults) == .mac, "the last answer wins")
        expect(posted == ["unanswered", "windows", "ipad"], "each change reports what it replaced (got \(posted))")

        // 退回没答：删掉键，而不是存一个“unanswered”。
        expect(SwitcherOrigin.store(.unanswered, in: defaults, center: center), "going back to unanswered is a change")
        expect(defaults.object(forKey: SwitcherOrigin.defaultsKey) == nil, "unanswered removes the key")
        expect(posted.last == "mac", "the notification says it was Mac before")

        // 在别的线程改（卡住判断不一定跑在主线程）：存是当场存，通知排到主线程发，订阅它的界面不会在后台被改。
        var threads: [Bool] = []
        let threadToken = center.addObserver(forName: SwitcherOrigin.didChangeNotification, object: nil, queue: nil) { _ in
            threads.append(Thread.isMainThread)
        }
        let before = posted.count
        let writer = Thread { SwitcherOrigin.store(.windows, in: defaults, center: center) }
        writer.start()
        let deadline = Date().addingTimeInterval(2)
        while threads.isEmpty, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        expect(SwitcherOrigin.stored(in: defaults) == .windows, "an off-main write is stored")
        expect(threads == [true], "an off-main write notifies once, on the main thread (got \(threads))")
        expect(posted.count == before + 1 && posted.last == "unanswered", "the off-main notification still carries the previous answer")
        center.removeObserver(threadToken)
        SwitcherOrigin.store(.unanswered, in: defaults, center: center)

        // 认不出的值（以后删掉的选项、手改坏的偏好）当没答；字面写着 unanswered 也一样。
        defaults.set("linux", forKey: SwitcherOrigin.defaultsKey)
        expect(SwitcherOrigin.stored(in: defaults) == .unanswered, "an unknown stored value reads as unanswered")
        defaults.set("unanswered", forKey: SwitcherOrigin.defaultsKey)
        expect(SwitcherOrigin.stored(in: defaults) == .unanswered, "a literal unanswered reads as unanswered")
        defaults.set(3, forKey: SwitcherOrigin.defaultsKey)
        expect(SwitcherOrigin.stored(in: defaults) == .unanswered, "a non-string value reads as unanswered")

        // 界面上的三个选项：顺序、名字固定；没答不是选项、没有名字。
        expect(SwitcherOrigin.answers == [.windows, .ipad, .mac], "the three answers in on-screen order")
        expect(SwitcherOrigin.answers.map(\.title) == ["Windows", "iPad", "一直用 Mac"], "one name per answer, shared by welcome and settings")
        expect(SwitcherOrigin.unanswered.title == nil && !SwitcherOrigin.unanswered.isAnswered, "unanswered has no label")

        if failures == 0 { print("PASS: switcher origin — defaults round trip, unanswered = no key, unknown values, change-only notifications with the previous answer, always on the main thread, shared labels") }
        else { print("FAILED \(failures)"); exit(1) }
    }
}
