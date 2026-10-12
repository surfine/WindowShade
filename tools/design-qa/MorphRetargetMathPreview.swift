import Foundation

#if !swift(>=6.0)
#error("Swift6 required")
#endif

/// 第26批独立数学核对：只链接 `Core/FlickMotion.swift`（纯计算，不碰 CALayer）。
/// 用四阶 Runge–Kutta 数值积分同一条 ODE 与解析解对照；逐项验证反向符号、零行程、下界削减。
/// 这是数学层的独立核对，不冒充真机动画或可见合成验收。
@main enum MorphRetargetMathPreview {
    enum Failure: Error { case check(String) }

    /// RK4 积分 m=1 的 x'' = −2ζω·x' − ω²·x，从 (x, v) 走到时刻 end。
    static func integrate(zeta: Double, omega: Double, x: Double, v: Double,
                          until end: Double, step: Double = 1.0 / 4000) -> (x: Double, v: Double) {
        var x = x, v = v, now = 0.0
        func acceleration(_ position: Double, _ velocity: Double) -> Double {
            -2 * zeta * omega * velocity - omega * omega * position
        }
        while now < end {
            let h = min(step, end - now)
            let k1x = v, k1v = acceleration(x, v)
            let k2x = v + h / 2 * k1v, k2v = acceleration(x + h / 2 * k1x, v + h / 2 * k1v)
            let k3x = v + h / 2 * k2v, k3v = acceleration(x + h / 2 * k2x, v + h / 2 * k2v)
            let k4x = v + h * k3v, k4v = acceleration(x + h * k3x, v + h * k3v)
            x += h / 6 * (k1x + 2 * k2x + 2 * k3x + k4x)
            v += h / 6 * (k1v + 2 * k2v + 2 * k3v + k4v)
            now += h
        }
        return (x, v)
    }

    static func main() {
        let out = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
            var checks = [[String: Any]]()
            func record(_ name: String, _ value: [String: Any]) {
                checks.append(["name": name].merging(value) { a, _ in a })
            }

            // 1) 解析解 vs RK4：欠阻尼（ζ=0.92、0.5）、临界（ζ=1）；朝目标、背离目标、零行程踢，各时刻对照。
            for (name, zeta, response) in [("underdamped-0.92", 0.92, 0.4), ("underdamped-0.5", 0.5, 0.34), ("critical", 1.0, 0.34)] {
                let omega = 2 * Double.pi / response
                let spring = FlickSpring(dampingRatio: zeta, response: response)
                for (caseName, x0, v0) in [("toward", 100.0, -200.0), ("away", 100.0, 200.0),
                                           ("kick", 0.0, 700.0), ("kick-away", 0.0, -700.0)] {
                    for at in [0.02, 0.05, 0.1, 0.2, 0.4] {
                        let analytic = spring.state(displacement: x0, velocity: v0, at: at)
                        let numeric = integrate(zeta: zeta, omega: omega, x: x0, v: v0, until: at)
                        let dx = abs(analytic.x - numeric.x), dv = abs(analytic.v - numeric.v)
                        guard dx < 1e-4 * max(1, abs(x0)), dv < 1e-3 * max(1, abs(x0)) else {
                            throw Failure.check("analytic-vs-rk4 \(name)/\(caseName)/t=\(at): dx=\(dx) dv=\(dv)")
                        }
                        record("analytic-\(name)-\(caseName)", ["t": at, "xError": dx, "vError": dv])
                    }
                }
            }

            // 2) liveVelocity：CASpring 实际系数（25 批记录 mass=1 stiffness=246.7401 damping=28.9027）
            //    换算成 (ζ, response) 后与直接构造的解析解一致；nv 反号 → 物理速度反号，符号=朝目标。
            let stiffness = 246.740_110_027_233_95, damping = 28.902_652_413_026_097
            let w0 = stiffness.squareRoot()
            let zeta = damping / (2 * w0)
            let direct = FlickSpring(dampingRatio: zeta, response: 2 * Double.pi / w0)
            for nv in [1.0, -1.0] {
                let fromActual = MorphRetarget.liveVelocity(
                    of: .init(mass: 1, stiffness: stiffness, damping: damping,
                              from: -100, normalizedVelocity: nv, beginTime: 0, duration: 1), at: 0.1)!
                let fromDirect = direct.state(displacement: -100, velocity: -nv * -100, at: 0.1).v
                guard abs(fromActual - fromDirect) < 1e-9 else { throw Failure.check("liveVelocity mismatch nv=\(nv)") }
                // 符号在 t≈0 检查（ζω·|x0| 的加速度毫秒内就能改写速度）：t=1e-4 时解析速度 ≈ v0，
                // 误差 ~ω²·|x0|·t ≈ 2.5%。物理初速 v0 = −nv·from；from=−100 时 nv=+1 → v0=+100（朝目标）。
                let initial = MorphRetarget.liveVelocity(
                    of: .init(mass: 1, stiffness: stiffness, damping: damping,
                              from: -100, normalizedVelocity: nv, beginTime: 0, duration: 1), at: 0.0001)!
                let expectedV0 = -nv * -100
                guard initial * expectedV0 > 0, abs(initial - expectedV0) < abs(expectedV0) * 0.15 else {
                    throw Failure.check("liveVelocity sign nv=\(nv): \(initial) vs v0=\(expectedV0)")
                }
                record("live-velocity", ["nv": nv, "velocity@0.1": fromActual, "velocity@0.002": initial])
            }

            // 3) handoff 弹簧路径：nv = v/Δ 带符号；物理初速（nv × Δ）恒等于 v，速度连续。
            for (caseName, v, delta) in [("continue", 200.0, 50.0), ("reverse", 200.0, -50.0),
                                         ("reverse-opposite", -200.0, 50.0), ("continue-opposite", -200.0, -50.0)] {
                let axis = MorphRetarget.handoff(remainingTravel: delta, liveVelocity: v, fallbackVelocity: 0,
                                                 response: 0.4, dampingRatio: 0.92, floor: nil)!
                guard axis.kick == nil, abs(axis.initialVelocity - v / delta) < 1e-12 else {
                    throw Failure.check("handoff \(caseName): \(axis)")
                }
                let physical = axis.initialVelocity * delta
                guard abs(physical - v) < 1e-9 else { throw Failure.check("handoff physical \(caseName): \(physical)") }
                record("handoff-\(caseName)", ["v": v, "delta": delta, "nv": axis.initialVelocity])
            }

            // 4) fallback：旧动画不在飞 → 保留调用者初速度，不覆盖甩动手感。
            let fallback = MorphRetarget.handoff(remainingTravel: 90, liveVelocity: nil, fallbackVelocity: -3.5,
                                                 response: 0.4, dampingRatio: 1, floor: nil)!
            guard fallback.kick == nil, fallback.initialVelocity == -3.5 else { throw Failure.check("fallback \(fallback)") }

            // 5) 零行程：没有速度 → 不动；有速度 → kick。首值 0、收尾回 0、时长有限、单调时间。
            guard MorphRetarget.handoff(remainingTravel: 0, liveVelocity: nil, fallbackVelocity: 0,
                                        response: 0.4, dampingRatio: 1, floor: nil) == nil else {
                throw Failure.check("zero-travel at rest should be nil")
            }
            for (caseName, v) in [("kick", 700.0), ("kick-away", -700.0)] {
                let axis = MorphRetarget.handoff(remainingTravel: 0, liveVelocity: v, fallbackVelocity: 0,
                                                 response: 0.4, dampingRatio: 1, floor: nil)!
                guard let kick = axis.kick, axis.initialVelocity == 0 else { throw Failure.check("zero-travel \(caseName)") }
                guard kick.values.first == 0, abs(kick.values.last!) < 1e-9 else { throw Failure.check("kick endpoints \(caseName)") }
                guard kick.times.first == 0, let duration = kick.times.last, duration > 0, duration <= 1.3 else {
                    throw Failure.check("kick duration \(caseName)")
                }
                let peak = kick.values.map(abs).max()!
                // 临界 kick 峰值 = v·response/(2π)/e：700×0.0637/2.718 ≈ 16.4 点，有界。
                let bound = 700 * (0.4 / (2 * Double.pi)) / exp(1) * 1.05
                guard peak < bound, peak > 0 else { throw Failure.check("kick bound \(caseName): \(peak) vs \(bound)") }
                guard kick.times == kick.times.sorted(), Set(kick.times).count == kick.times.count else {
                    throw Failure.check("kick times monotonic \(caseName)")
                }
                record("zero-\(caseName)", ["peak": peak, "duration": kick.times.last!, "samples": kick.values.count])
            }

            // 6) 下界：宽度 target=33.5、floor=−33.5，向内 2000 点/秒会把未削减的 kick 推到 −23：
            //    削幅值保方向，min(values) ≥ floor，仍有负位移（方向没丢），收尾回 0。
            let floored = MorphRetarget.kickKeyframes(velocity: -2000, response: 0.34, dampingRatio: 1, floor: -33.5)!
            guard let clipped = floored.values.min(), clipped >= -33.5 else { throw Failure.check("floor \(String(describing: floored.values.min()))") }
            guard floored.values.contains(where: { $0 < 0 }) else { throw Failure.check("floor direction kept") }
            guard floored.values.first == 0, abs(floored.values.last!) < 1e-9 else { throw Failure.check("floor endpoints") }
            let unclipped = MorphRetarget.kickKeyframes(velocity: -2000, response: 0.34, dampingRatio: 1, floor: nil)!
            guard let rawMin = unclipped.values.min(), rawMin < -33.5 else { throw Failure.check("floor was binding: \(String(describing: unclipped.values.min()))") }
            record("floor-width", ["clipped": clipped, "unclipped": rawMin])

            // 7) 极小行程（0.4 ≤ 0.5 阈值）带速度走 kick；极端速度有上限截断。
            let tiny = MorphRetarget.handoff(remainingTravel: 0.4, liveVelocity: 300, fallbackVelocity: 0,
                                             response: 0.4, dampingRatio: 1, floor: nil)!
            guard tiny.kick != nil else { throw Failure.check("tiny travel should kick") }
            let capped = MorphRetarget.kickKeyframes(velocity: 50000, response: 0.4, dampingRatio: 1, floor: nil)!
            guard let cappedPeak = capped.values.map(abs).max(),
                  cappedPeak < 5000 * (0.4 / (2 * Double.pi)) / exp(1) * 1.05 else {
                throw Failure.check("maxVelocity cap: \(String(describing: capped.values.map(abs).max()))")
            }

            let payload: [String: Any] = [
                "checks": checks,
                "kind": "pure-math-ode-and-handoff",
                "compositorAccepted": false,
                "realSources": 0,
                "globalInputEvents": 0,
                "productEntry": false,
                "mainThread": Thread.isMainThread,
            ]
            try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
                .write(to: out.appendingPathComponent("math.json"))
            print("PASS analytic/RK4, live-velocity, handoff sign, zero-travel kick, floor clipping")
        } catch {
            try? String(describing: error).write(to: out.appendingPathComponent("failure.txt"), atomically: true, encoding: .utf8)
            print("FAIL math probe: \(error)")
            exit(1)
        }
    }
}
