import Foundation

/// 手动拨的钟：测试自己决定“现在”是几秒，不真的等。
final class ManualTimerClock: WS2Clock, @unchecked Sendable {
    private let lock = NSLock()
    private var seconds: Double = 0
    func now() -> WS2.Instant { lock.lock(); defer { lock.unlock() }; return sec(seconds) }
    func set(_ value: Double) { lock.lock(); seconds = value; lock.unlock() }
}

@main
struct CountdownTimerHostTests {
    static func main() { MainActor.assumeIsolated { run() } }

    @MainActor
    static func run() {
        var t = TestSuite("TMR2")
        let s = WS2.Duration.second
        let m = WS2.Duration.minute

        /// 一套注入好的宿主：数响了几次，记 onTimeUp / onFinished / 记住的分钟数。
        @MainActor final class Rig {
            let clock = ManualTimerClock()
            var rang = 0, timeUp = 0, finished = 0
            var remembered: [Int] = []
            var muted = false, enabled = true
            var host: CountdownTimerHost!
            init(last: Int = 10) {
                host = CountdownTimerHost(clock: clock, lastMinutes: last,
                                          chime: { [unowned self] in rang += 1 },
                                          isMuted: { [unowned self] in muted },
                                          chimeEnabled: { [unowned self] in enabled },
                                          remember: { [unowned self] in remembered.append($0) })
                host.onTimeUp = { [unowned self] in timeUp += 1 }
                host.onFinished = { [unowned self] in finished += 1 }
            }
            func go(_ seconds: Double) { clock.set(seconds); host.tick() }
        }

        t.section("TMR2-01", "右耳和大卡上的字：9 分 / 0:42 / +0:42 / +3 分")
        t.expect(CountdownTimerText.ear(remaining: 9 * m) == "9 分", "整 9 分钟写“9 分”")
        t.expect(CountdownTimerText.ear(remaining: 8 * m + 1) == "9 分", "不满一分钟向上取整")
        t.expect(CountdownTimerText.ear(remaining: 61 * s) == "2 分", "61 秒还写分钟")
        t.expect(CountdownTimerText.ear(remaining: 60 * s) == "1:00", "最后 60 秒起写秒（和番茄钟同一种写法）")
        t.expect(CountdownTimerText.ear(remaining: 41_200 * WS2.Duration.millisecond) == "0:42", "41.2 秒写“0:42”")
        t.expect(CountdownTimerText.big(remaining: 9 * m + 5 * s) == "9:05", "大卡写 m:ss")
        t.expect(CountdownTimerText.overtime(42 * s) == "+0:42" && CountdownTimerText.overtime(59 * s + 900 * WS2.Duration.millisecond) == "+0:59",
                 "超时不到 1 分钟写“+0:42”")
        t.expect(CountdownTimerText.overtime(3 * m + 20 * s) == "+3 分", "超时满分钟写“+3 分”（向下取整）")
        t.expect(CountdownTimerText.minutesLine(10) == "10 分钟计时器", "次句“10 分钟计时器”")

        t.section("TMR2-02", "选分钟：1/3/5/10/15/30，↑ ↓ 调，回车开始，Esc 取消")
        t.expect(CountdownTimerPicker.presets == [1, 3, 5, 10, 15, 30], "六个预设")
        t.expect(CountdownTimerPicker.step(10, by: 1) == 11 && CountdownTimerPicker.step(10, by: -1) == 9, "↑ 加一分钟，↓ 减一分钟")
        t.expect(CountdownTimerPicker.step(1, by: -1) == 1 && CountdownTimerPicker.step(120, by: 1) == 120, "停在 1 和 120 分钟")
        t.expect(CountdownTimerPicker.initial(last: 0) == 10 && CountdownTimerPicker.initial(last: 25) == 25 && CountdownTimerPicker.initial(last: 999) == 10,
                 "记着上次的分钟数，没有或越界回 10")
        t.expect(CountdownTimerPicker.key(forKeyCode: 126) == .up && CountdownTimerPicker.key(forKeyCode: 125) == .down
                 && CountdownTimerPicker.key(forKeyCode: 36) == .start && CountdownTimerPicker.key(forKeyCode: 76) == .start
                 && CountdownTimerPicker.key(forKeyCode: 53) == .cancel && CountdownTimerPicker.key(forKeyCode: 0) == nil,
                 "键盘就能选、开始、取消")

        t.section("TMR2-03", "到点只响一次，不循环")
        let a = Rig()
        a.host.start(minutes: 1)
        a.go(59)
        t.expect(a.rang == 0 && a.timeUp == 0, "未到点不响")
        a.go(60)
        t.expect(a.rang == 1 && a.timeUp == 1 && a.host.model.state == .done, "到点响一声、鼓一次")
        a.go(61); a.go(75); a.go(200)
        t.expect(a.rang == 1 && a.timeUp == 1, "之后每次醒来都不再响")
        t.expect(CountdownTimerText.ear(for: a.host.model, at: a.clock.now()) == "+2 分", "超时 140 秒右耳“+2 分”")
        a.host.stop()

        t.section("TMR2-04", "系统静音或关了开关：不响，但“时间到”照鼓")
        let b = Rig(); b.muted = true
        b.host.start(minutes: 1); b.go(60)
        t.expect(b.rang == 0 && b.timeUp == 1 && b.host.chimeCount == 0, "系统静音时不响")
        let c = Rig(); c.enabled = false
        c.host.start(minutes: 1); c.go(60)
        t.expect(c.rang == 0 && c.timeUp == 1, "设置里关了不响")
        let d = Rig()
        d.host.start(minutes: 1); d.go(60)
        t.expect(d.rang == 1 && d.host.chimeCount == 1, "默认开着、没静音：响一声")
        b.host.stop(); c.host.stop(); d.host.stop()

        t.section("TMR2-05", "超时 10 分钟后自己结束，右耳收回")
        let e = Rig()
        e.host.start(minutes: 1); e.go(60)
        e.go(659)
        t.expect(e.host.model.state == .done && e.finished == 0, "差 1 秒仍在超时")
        e.go(660)
        t.expect(e.host.model.state == .idle && e.finished == 1, "满 10 分钟结束")
        t.expect(CountdownTimerText.ear(for: e.host.model, at: e.clock.now()).isEmpty, "结束后右耳没有字")
        e.host.stop()

        t.section("TMR2-06", "睡过头醒来：只显示超时，不补响、不补鼓")
        let f = Rig()
        f.host.start(minutes: 1); f.go(200)
        t.expect(f.host.model.state == .done && f.rang == 0 && f.timeUp == 0, "到点 140 秒后才发现，不响也不鼓")
        f.go(5000)
        t.expect(f.host.model.state == .idle && f.finished == 1 && f.rang == 0, "睡了很久：直接结束")
        f.host.stop()

        t.section("TMR2-07", "记住上次的分钟数；只在真的开始时记")
        let g = Rig(last: 10)
        g.host.start(minutes: 15)
        g.host.start(minutes: 3)
        t.expect(g.remembered == [15], "开着时再按开始被拒绝，不改记住的分钟")
        g.host.end()
        g.host.start(minutes: 3)
        t.expect(g.remembered == [15, 3] && g.host.model.lastMinutes == 3, "结束后再开，记住 3")
        g.host.stop()

        t.section("TMR2-08", "暂停 / 继续 / 再来一个 / 结束")
        let h = Rig()
        h.host.start(minutes: 10); h.go(60)
        h.host.togglePause()
        t.expect(h.host.model.state == .paused && h.host.model.remaining(at: h.clock.now()) == 9 * m, "暂停记下剩余 9 分钟")
        t.expect(h.host.nextWake(at: h.clock.now()) == nil, "暂停不排唤醒")
        h.go(600); h.host.togglePause()
        t.expect(h.host.model.state == .running && h.host.model.remaining(at: h.clock.now()) == 9 * m, "暂停多久都不走，继续后还是 9 分钟")
        h.go(600 + 9 * 60)
        t.expect(h.rang == 1 && h.host.model.state == .done, "继续后到点响")
        h.host.again()
        t.expect(h.finished == 1 && h.host.model.state == .running && h.host.model.totalMinutes == 10, "再来一个：结束这一个，同样的分钟数重新开始")
        h.host.end()
        t.expect(h.host.model.state == .idle && h.finished == 2, "结束")
        h.host.stop()

        t.section("TMR2-09", "唤醒：每分钟一次，最后 60 秒每秒一次；大卡开着时每秒；空闲没有")
        let i = Rig()
        t.expect(i.host.nextWake(at: i.clock.now()) == nil, "空闲不排唤醒")
        i.host.start(minutes: 10)
        t.expect(i.host.nextWake(at: sec(0)) == sec(60), "9 分钟以上：下一次在一分钟后（“9 分”换成“8 分”）")
        t.expect(i.host.nextWake(at: sec(30)) == sec(60), "半分钟后换字")
        t.expect(i.host.nextWake(at: sec(545)) == sec(546), "剩 55 秒：1 秒一次")
        i.host.wantsSecondTicks = true
        t.expect(i.host.nextWake(at: sec(30)) == sec(31), "大卡开着：每秒")
        i.host.wantsSecondTicks = false
        i.go(600)
        t.expect(i.host.model.state == .done && i.host.nextWake(at: sec(630)) == sec(631), "超时前 60 秒每秒换字")
        t.expect(i.host.nextWake(at: sec(700)) == sec(720), "超时满一分钟后每分钟换字")
        i.host.stop()

        t.section("TMR2-10", "设置：到时间响一声默认开；上次的分钟数")
        let suiteName = "ws.tmr2.tests.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: suiteName)!
        let saved = CountdownTimerSettings.store
        CountdownTimerSettings.store = suite
        t.expect(CountdownTimerSettings.chimeEnabled && CountdownTimerSettings.lastMinutes == 10, "没设置过：响一声开着，上次是 10 分钟")
        CountdownTimerSettings.chimeEnabled = false
        CountdownTimerSettings.lastMinutes = 25
        t.expect(!CountdownTimerSettings.chimeEnabled && CountdownTimerSettings.lastMinutes == 25, "关掉、记住 25 分钟")
        suite.set(9999, forKey: CountdownTimerSettings.lastMinutesKey)
        t.expect(CountdownTimerSettings.lastMinutes == 10, "存了越界的值就退回 10")
        CountdownTimerSettings.store = saved
        suite.removePersistentDomain(forName: suiteName)

        t.section("TMR2-11", "读屏念的话")
        var spoken = CountdownTimer()
        _ = spoken.handle(.start(minutes: 10), at: sec(0))
        t.expect(CountdownTimerText.spoken(for: spoken, at: sec(60)) == "计时器，还剩 9 分钟", "紧凑读作“计时器，还剩 9 分钟”")
        _ = spoken.handle(.pause, at: sec(60))
        t.expect(CountdownTimerText.spoken(for: spoken, at: sec(90)) == "计时器，已暂停，还剩 9 分钟", "暂停读出来")

        t.finish()
    }
}
