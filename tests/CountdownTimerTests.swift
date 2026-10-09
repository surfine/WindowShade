import Foundation

@main
struct CountdownTimerTests {
    static func main() {
        var t = TestSuite("TMR1")
        let s = WS2.Duration.second
        let m = WS2.Duration.minute

        t.section("TMR1-01", "开始 10 分钟 → 截止在 605 秒，同时只有一个")
        var a = CountdownTimer()
        t.expect(a.lastMinutes == 10 && a.state == .idle && a.nextWake() == nil, "空闲不排唤醒")
        _ = a.handle(.start(minutes: 10), at: sec(5))
        t.expect(a.state == .running && a.deadline == sec(605) && a.nextWake() == sec(605), "截止 = 开始 + 10 分钟")
        _ = a.handle(.start(minutes: 3), at: sec(6))
        t.expect(a.deadline == sec(605) && a.totalMinutes == 10 && a.lastMinutes == 10, "再开始被拒绝，不改记住的分钟数")
        var bad = CountdownTimer()
        _ = bad.handle(.start(minutes: 0), at: sec(0))
        _ = bad.handle(.start(minutes: 601), at: sec(0))
        t.expect(bad.state == .idle, "分钟数越界不开始")

        t.section("TMR1-02", "合盖 3 分钟：连续时钟照走，剩余少 3 分钟")
        t.expect(a.remaining(at: sec(65)) == 9 * m, "走了 1 分钟剩 9 分钟")
        t.expect(a.remaining(at: sec(245)) == 6 * m, "合盖 3 分钟后少 3 分钟")
        t.expect(a.handle(.tick, at: sec(245)).isEmpty && a.state == .running, "醒来未到点无动作")
        t.expect(abs(a.progress(at: sec(305)) - 0.5) < 1e-9, "进度 0.5")

        t.section("TMR1-03", "到点 60 秒内发现 → 响一次，进入超时")
        var b = CountdownTimer()
        _ = b.handle(.start(minutes: 1), at: sec(0))
        t.expect(b.handle(.tick, at: sec(59)).isEmpty, "未到点不响")
        t.expect(b.handle(.tick, at: sec(60)) == [.chime] && b.state == .done, "到点响一声")
        t.expect(b.handle(.tick, at: sec(61)).isEmpty, "不重复响")
        t.expect(b.overtime(at: sec(103)) == 43 * s && b.remaining(at: sec(103)) == 0 && b.progress(at: sec(103)) == 1, "超时 43 秒，环满")
        t.expect(b.nextWake() == sec(660), "超时结束线排在 10 分钟后")

        t.section("TMR1-04", "晚于 60 秒才发现 → 只显示超时，不响")
        var c = CountdownTimer()
        _ = c.handle(.start(minutes: 1), at: sec(0))
        t.expect(c.handle(.tick, at: sec(120)).contains(.chime), "刚好 60 秒仍响")
        var d = CountdownTimer()
        _ = d.handle(.start(minutes: 1), at: sec(0))
        t.expect(d.handle(.tick, at: sec(121)).isEmpty && d.state == .done, "61 秒才醒来不响")
        t.expect(d.overtime(at: sec(121)) == 61 * s, "醒来直接显示超时")

        t.section("TMR1-05", "超时 10 分钟后自己结束；睡过头直接结束且不响")
        t.expect(b.handle(.tick, at: sec(659)).isEmpty && b.state == .done, "差 1 秒仍在超时")
        t.expect(b.handle(.tick, at: sec(660)) == [.finished] && b.state == .idle && b.deadline == nil, "满 10 分钟结束")
        var e = CountdownTimer()
        _ = e.handle(.start(minutes: 1), at: sec(0))
        t.expect(e.handle(.tick, at: sec(3600)) == [.finished] && e.state == .idle, "睡了一小时：直接结束，不补响")
        t.expect(e.lastMinutes == 1, "结束后仍记得分钟数")

        t.section("TMR1-06", "暂停记剩余，继续后顺延")
        var f = CountdownTimer(lastMinutes: 5)
        _ = f.handle(.start(minutes: 5), at: sec(0))
        _ = f.handle(.pause, at: sec(100))
        t.expect(f.state == .paused && f.remaining(at: sec(100)) == 200 * s && f.nextWake() == nil, "暂停记剩余 200 秒，不排唤醒")
        t.expect(f.remaining(at: sec(5000)) == 200 * s && f.handle(.tick, at: sec(5000)).isEmpty, "暂停多久都不走")
        _ = f.handle(.resume, at: sec(5000))
        t.expect(f.state == .running && f.deadline == sec(5200), "继续后截止顺延")
        t.expect(f.handle(.tick, at: sec(5200)) == [.chime], "继续后到点响")

        t.section("TMR1-07", "结束、倒流、非法事件")
        var g = CountdownTimer()
        _ = g.handle(.start(minutes: 2), at: sec(10))
        t.expect(g.handle(.tick, at: sec(5)).isEmpty && g.deadline == sec(130), "时钟倒流被忽略")
        t.expect(g.handle(.resume, at: sec(11)).isEmpty && g.state == .running, "运行中继续无效")
        t.expect(g.handle(.end, at: sec(12)) == [.finished] && g.state == .idle, "手动结束")
        t.expect(g.handle(.end, at: sec(13)).isEmpty && g.handle(.pause, at: sec(14)).isEmpty, "空闲时结束/暂停无动作")
        _ = g.handle(.start(minutes: 15), at: sec(20))
        t.expect(g.lastMinutes == 15 && g.remaining(at: sec(20)) == 15 * m, "再开一个，记住 15 分钟")
        var h = CountdownTimer()
        _ = h.handle(.start(minutes: 1), at: sec(0))
        _ = h.handle(.tick, at: sec(60))
        t.expect(h.handle(.pause, at: sec(70)).isEmpty && h.state == .done, "超时中不能暂停")
        t.expect(CountdownTimer(lastMinutes: 0).lastMinutes == 10 && CountdownTimer(lastMinutes: 30).lastMinutes == 30, "初值越界回默认")

        t.finish()
    }
}
