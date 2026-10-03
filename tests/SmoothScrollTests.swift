import Foundation

@main
struct SmoothScrollTests {
    static func main() {
        var t = TestSuite("I1a")

        t.section("I1a-01", "三个档位各一格，持续到收敛 → 总量等于每格点数，闲时零输出")
        for preset in [SmoothScroll.Preset.light, .medium, .trackpadLike] {
            var s = SmoothScroll(preset: preset); var sum = s.add(notches: 1, at: sec(0))!.delta
            for i in 1...600 { sum += s.step(at: sec(Double(i)/120))!.delta }
            t.expect(abs(sum - preset.pointsPerNotch) < 0.0001 && s.isFinished, "各档总量保留")
            t.expect(s.step(at: sec(10)) == .init(delta: 0, finished: true), "停机后不继续排帧")
        }
        t.section("I1a-02", "同向连加三格 → 目标累加、速度不断、不越过目标")
        var a = SmoothScroll(); _ = a.add(notches: 1, at: sec(0)); _ = a.step(at: sec(0.02))
        let velocity = a.velocity; _ = a.add(notches: 2, at: sec(0.02))
        t.expect(a.target == 108 && a.velocity == velocity, "同刻加格保留速度")
        var noOvershoot = true
        for i in 3...300 { _ = a.step(at: sec(Double(i)/100)); noOvershoot = noOvershoot && a.position <= a.target }
        t.expect(noOvershoot && abs(a.position - 108) < 0.0001, "同向不回弹")
        t.section("I1a-03", "运动中反向 → 本次不再发旧方向量，下一帧立即反向")
        var b = SmoothScroll(); _ = b.add(notches: 3, at: sec(0)); _ = b.step(at: sec(0.02))
        let reverse = b.add(notches: -1, at: sec(0.03))!
        t.expect(reverse.delta <= 0, "反向输入不能先补旧方向")
        t.expect(b.step(at: sec(0.04))!.delta < 0, "后续立即反向")
        t.expect(abs(b.totalInput - b.position - b.pending - b.cancelledResidual) < 0.0001, "显式取消也守恒")
        t.section("I1a-04", "同一轨迹采用均匀帧与掉帧 → 解析解位置一致")
        var c = SmoothScroll(), d = SmoothScroll()
        _ = c.add(notches: 2, at: sec(0)); _ = d.add(notches: 2, at: sec(0))
        for i in 1...120 { _ = c.step(at: sec(Double(i)/120)) }
        for x in [0.001,0.014,0.18,0.6,1.0] { _ = d.step(at: sec(x)) }
        t.expect(abs(c.position-d.position) < 1e-8 && abs(c.velocity-d.velocity) < 1e-8, "掉帧不丢总量")
        t.section("I1a-05", "NaN/无穷/超量/倒流 → 拒绝且不改已有位置")
        let before = d.position
        t.expect(d.add(notches: .nan, at: sec(2)) == nil && d.add(notches: .infinity, at: sec(2)) == nil, "非法数值拒绝")
        t.expect(d.add(notches: 121, at: sec(2)) == nil && d.step(at: sec(0)) == nil && d.position == before, "无效输入原状态保留")
        t.section("I1a-06", "固定种子 1000 次混合正反滚动和掉帧 → 每步守恒、有限、不越界")
        var random = DeterministicRandom(), e = SmoothScroll(); var now = 0.0; var good = true
        for _ in 0..<1000 {
            now += 0.001 + random.unit()*0.03
            let n = random.unit() > 0.5 ? 1.0 : -1.0
            _ = e.add(notches: n, at: sec(now)); _ = e.step(at: sec(now+0.001)); now += 0.001
            good = good && e.position.isFinite && e.velocity.isFinite && abs(e.totalInput-e.position-e.pending-e.cancelledResidual) < 1e-6
        }
        _ = e.cancel()
        t.expect(good && e.isFinished, "1000 次轨迹性质检查")

        t.finish()
    }
}
