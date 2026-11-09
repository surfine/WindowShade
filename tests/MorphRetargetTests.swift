// 岛形变接力（C04）：旧弹簧还在飞时的实时速度、剩余行程的归一化初速度、近零行程的 kick。
// 纯计算，不碰窗口与图层。
import Foundation

@main
struct MorphRetargetTests {
    /// 一条标准轴：mass 1、response 0.5、dampingRatio 0.8，从 +10 往回走。
    static func axis(normalizedVelocity: Double = 0.5, begin: Double = 0, duration: Double = 1,
                     from: Double = 10) -> MorphRetarget.OldAxis {
        let response = 0.5
        let w0 = 2 * Double.pi / response
        let mass = 1.0
        let stiffness = w0 * w0 * mass
        let damping = 0.8 * 2 * (mass * stiffness).squareRoot()
        return MorphRetarget.OldAxis(mass: mass, stiffness: stiffness, damping: damping,
                                     from: from, normalizedVelocity: normalizedVelocity,
                                     beginTime: begin, duration: duration)
    }

    static func main() {
        var t = TestSuite("C04")

        t.section("C04-01", "liveVelocity：没开始／已结束／参数异常都不算在飞")
        t.expect(MorphRetarget.liveVelocity(of: axis(begin: 1), at: 0.5) == nil, "还没开始 → nil")
        t.expect(MorphRetarget.liveVelocity(of: axis(), at: 1.0) == nil, "已过 duration → nil")
        t.expect(MorphRetarget.liveVelocity(of: axis(), at: 1.2) == nil, "迟到很久 → nil")
        var broken = axis()
        broken.mass = 0
        t.expect(MorphRetarget.liveVelocity(of: broken, at: 0.1) == nil, "mass 0 → nil")
        broken = axis()
        broken.stiffness = -1
        t.expect(MorphRetarget.liveVelocity(of: broken, at: 0.1) == nil, "stiffness < 0 → nil")

        t.section("C04-02", "liveVelocity：t=0 就是 -归一化速度×from，之后仍朝目标收")
        let v0 = MorphRetarget.liveVelocity(of: axis(normalizedVelocity: 0.5, from: 10), at: 0)
        t.expect(v0 != nil && abs(v0! - (-5)) < 1e-9, "t=0 是 -5 点/秒（实际 \(String(describing: v0))）")
        let later = MorphRetarget.liveVelocity(of: axis(normalizedVelocity: 0.5, from: 10), at: 0.25)
        t.expect(later != nil && later! < 0, "0.25 秒时还朝目标走（负速度）")

        t.section("C04-03", "liveVelocity：过阻尼也按临界语义算，仍是有限值")
        var over = axis()
        over.damping *= 4
        let overdamped = MorphRetarget.liveVelocity(of: over, at: 0.1)
        t.expect(overdamped != nil && overdamped!.isFinite, "过阻尼速度有限")

        t.section("C04-04", "handoff：剩余行程折算成归一化初速度")
        let plain = MorphRetarget.handoff(remainingTravel: 10, liveVelocity: -5, fallbackVelocity: 0,
                                          response: 0.4, dampingRatio: 0.8, floor: nil)
        t.expect(plain != nil && abs(plain!.initialVelocity - (-0.5)) < 1e-12, "v/Δ = -0.5")
        t.expect(plain?.kick == nil, "还有行程，走弹簧")
        let fallback = MorphRetarget.handoff(remainingTravel: 10, liveVelocity: nil, fallbackVelocity: 0.3,
                                             response: 0.4, dampingRatio: 0.8, floor: nil)
        t.expect(fallback != nil && abs(fallback!.initialVelocity - 0.3) < 1e-12, "没有旧动画时保留调用者初速度")
        t.expect(MorphRetarget.handoff(remainingTravel: 0, liveVelocity: nil, fallbackVelocity: 0,
                                       response: 0.4, dampingRatio: 0.8, floor: nil) == nil,
                 "行程为 0 且没有速度 → nil")

        t.section("C04-05", "handoff：剩余行程近零但还有速度，交给 kick；首点是当前位移")
        let small = MorphRetarget.handoff(remainingTravel: 0.2, liveVelocity: -100, fallbackVelocity: 0,
                                          response: 0.4, dampingRatio: 0.8, floor: nil)
        t.expect(small != nil && small!.kick != nil, "0.2 点 + 100 点/秒 → kick")
        t.expect(small?.initialVelocity == 0, "kick 路径不再叠加初速度")
        if let kick = small?.kick {
            t.expect(kick.values.count == kick.times.count, "values/times 等长")
            t.expect(kick.values.first == -0.2, "首点 = -Δ（位置连续）")
            t.expect(kick.values.last == 0, "收尾钉回 0")
        }

        t.section("C04-06", "kickKeyframes：零速度没有曲线；采样单调、收尾为 0、最多 40 帧")
        t.expect(MorphRetarget.kickKeyframes(velocity: 0, response: 0.4, dampingRatio: 0.8) == nil, "v=0 → nil")
        let keys = MorphRetarget.kickKeyframes(velocity: 800, start: 5, response: 0.4, dampingRatio: 0.8)
        t.expect(keys != nil, "有曲线")
        if let keys {
            t.expect(keys.values.count >= 2 && keys.values.count == keys.times.count, "点成对")
            t.expect(keys.values.first == 5, "首点 = start")
            t.expect(keys.values.last == 0, "末点 = 0")
            t.expect(keys.times[0] == 0, "第一个采样在 0（位置连续）")
            t.expect(keys.times.last! > 0, "最后一个采样在 0 之后")
            t.expect(zip(keys.times, keys.times.dropFirst()).allSatisfy { $0 < $1 }, "时间严格递增")
            t.expect(keys.values.count <= 40, "最多 40 帧")
        }

        t.section("C04-07", "kickKeyframes：floor 把速度削到不越界，方向不变")
        let floored = MorphRetarget.kickKeyframes(velocity: -800, start: 5, response: 0.4, dampingRatio: 0.8, floor: 0)
        t.expect(floored != nil, "有曲线")
        if let floored {
            t.expect(floored.values.allSatisfy { $0 >= -1e-9 }, "所有采样不跌破 0")
            t.expect(floored.values.first == 5, "起点不变")
        }

        t.section("C04-08", "limitingFloor：冲过下界时把速度压小，不改变符号")
        let spring = FlickSpring(dampingRatio: 1, response: 0.4)
        let limited = MorphRetarget.limitingFloor(spring: spring, displacement: 5, velocity: -2000, floor: 0)
        t.expect(limited <= 0 && limited > -2000, "负速度被削小（实际 \(limited)）")
        var t0 = 0.0
        var lowest = Double.greatestFiniteMagnitude
        while t0 <= 1.2 {
            lowest = min(lowest, spring.state(displacement: 5, velocity: limited, at: t0).x)
            t0 += 1.0 / 240
        }
        t.expect(lowest >= -1e-6, "削过的速度不跌破 floor（最低 \(lowest)）")

        t.finish()
    }
}
