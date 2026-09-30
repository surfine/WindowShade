// 甩一下标题栏的物理部分（纯计算，不碰窗口，可单测）。
//
// 手感照 iPadOS 26 与 Apple《Designing Fluid Interfaces》：
// - 只看手离开那一刻：离手前还在加速或保持的，是甩；先减速再放下的，是摆。
// - 窗口带着甩出去的速度继续走，用弹簧滑进目标，不在松手处停一下再跳过去。
// - 手离开的信号有好几种（按键松开、手指离开触控板、将来的触摸屏），判定只认“样本 + 离手时刻”。

import CoreGraphics
import Foundation

/// 一个指针位置：事件自带的时间戳（秒）与位置（点，Cocoa 坐标：x 向右、y 向上）。
/// 用事件自己的时间和位置，不用主线程收到它的时刻：机器忙时事件会成串送到，按收到的时刻算速度会乱。
struct FlickSample: Equatable {
    var time: TimeInterval
    var point: CGPoint
}

/// 手是怎么离开的。
enum FlickLiftSource: String, Equatable {
    /// 按键松开（鼠标、按下触控板拖）。松开就是离手。
    case buttonUp = "button-up"
    /// 触控板上的手指全部离开（三指拖移、按下拖）。三指拖移要等系统再发“松开”，那要晚 0.2–0.7 秒。
    case touchLift = "touch-lift"
    /// 没收到手指离开，等到了迟到的松开（三指拖移的特征：松开时点击次数是 0）。只能按最后一次移动算，
    /// 窗口已经停了很久，不再带着速度滑。
    case lateUp = "late-up"
    /// 收不到触摸时的三指拖移：指针在高速中突然停住。手指还在触控板上的人会先减速，
    /// 一帧里从每秒几千点停到零，只可能是手离开了。
    case pointerStopped = "pointer-stopped"
}

enum FlickLift {
    /// 离手前指针停了这么久，就不算“甩着离手”。
    static let stillBeforeLift: TimeInterval = 0.06
    /// 迟到的松开最多等这么久，再晚就不是这一下了。
    static let latestUp: TimeInterval = 1.0
    /// 离手到开始滑超过这么久，窗口停着的时间肉眼看得出，滑的时候不再接着甩出去的速度。
    static let carryWithin: TimeInterval = 0.1

    /// 按离手信号定出“离手时刻”，以及滑的时候要不要接上甩出去的速度。
    /// signal：信号到达的时刻；lastSample：最后一次指针移动的时刻。离手前指针早就停了，返回 nil。
    static func resolve(_ source: FlickLiftSource, signal: TimeInterval,
                        lastSample: TimeInterval) -> (lift: TimeInterval, carry: Bool)? {
        let gap = signal - lastSample
        switch source {
        case .buttonUp:
            guard gap <= stillBeforeLift else { return nil }
            return (signal, true)
        case .touchLift:
            // 手指离开前指针可能已经停在最后一帧：离手时刻按最后一次移动之后一帧算。
            guard gap <= stillBeforeLift else { return nil }
            return (min(signal, lastSample + 0.012), true)
        case .lateUp:
            guard gap <= latestUp else { return nil }
            return (lastSample, gap <= carryWithin)
        case .pointerStopped:
            guard gap <= carryWithin else { return nil }
            return (lastSample, true)
        }
    }

    /// 三指拖移时，手指在触控板边上、朝运动方向离开：那是换个位置接着拖，不是甩。
    /// positions：离开时各手指在触控板上的位置（0–1，左下为原点）；velocity：指针速度（y 向上）。
    static func isRepositioning(_ positions: [CGPoint], velocity: CGVector, margin: CGFloat = 0.08) -> Bool {
        guard !positions.isEmpty else { return false }
        let x = positions.map(\.x).reduce(0, +) / CGFloat(positions.count)
        let y = positions.map(\.y).reduce(0, +) / CGFloat(positions.count)
        if abs(velocity.dx) >= abs(velocity.dy) * 0.5 {
            if velocity.dx < 0, x <= margin { return true }
            if velocity.dx > 0, x >= 1 - margin { return true }
        }
        if abs(velocity.dy) >= abs(velocity.dx) * 0.5 {
            if velocity.dy < 0, y <= margin { return true }
            if velocity.dy > 0, y >= 1 - margin { return true }
        }
        return false
    }
}

/// 离手那一刻：多快、朝哪、是不是甩出去的样子。
struct FlickRelease: Equatable {
    /// 离手时的速度（点/秒，x 向右、y 向上）。
    var velocity: CGVector
    /// 离手前 150 毫秒里的最高速度。
    var peakSpeed: CGFloat

    var speed: CGFloat { hypot(velocity.dx, velocity.dy) }

    /// 甩出去的样子：离手时还保持着这一下最快速度的 65% 以上。
    /// 平常拖窗口，放下之前都会先减速；甩的时候手在最快的时候松开。
    var isThrow: Bool { peakSpeed > 0 && speed >= peakSpeed * 0.65 }

    /// samples 按时间排好。离手速度用离手前 45 毫秒里的点做最小二乘直线拟合（点不够就放宽到 70 毫秒），
    /// 不取头尾两点相减：触控板每一帧的位移都有抖动。
    static func measure(_ samples: [FlickSample], lift: TimeInterval) -> FlickRelease? {
        let upToLift = samples.filter { $0.time <= lift + 0.0005 }
        var window = upToLift.filter { $0.time >= lift - 0.045 }
        if window.count < 3 { window = upToLift.filter { $0.time >= lift - 0.07 } }
        guard window.count >= 3, let first = window.first, let last = window.last,
              last.time - first.time >= 0.012 else { return nil }
        let velocity = slope(window)
        // 最高速度：离手前 150 毫秒里，每一段 45 毫秒取相邻两帧速度的中位数，再取最大。
        // 用中位数：三指拖移的事件里偶尔有一两帧跳一大步（实测算出过每秒近 2 万点），取平均或拟合都会被它
        // 拉高，真正的甩反而被当成“先减速再放下”。
        let recent = upToLift.filter { $0.time >= lift - 0.15 }
        var steps: [(time: TimeInterval, speed: CGFloat)] = []
        for i in recent.indices.dropFirst() {
            let dt = recent[i].time - recent[i - 1].time
            guard dt > 0.002 else { continue }
            steps.append((recent[i].time, hypot(recent[i].point.x - recent[i - 1].point.x,
                                                recent[i].point.y - recent[i - 1].point.y) / CGFloat(dt)))
        }
        var peak: CGFloat = 0
        for end in steps.indices {
            let speeds = steps[...end].filter { $0.time > steps[end].time - 0.045 }.map(\.speed).sorted()
            guard speeds.count >= 3 else { continue }
            peak = max(peak, speeds[speeds.count / 2])
        }
        // 离手速度同样不让一两帧的跳步说了算：拟合和中位数取小的那个。
        if let lastSpeeds = Optional(steps.filter { $0.time > lift - 0.045 }.map(\.speed).sorted()), lastSpeeds.count >= 3 {
            let median = lastSpeeds[lastSpeeds.count / 2]
            let fitted = hypot(velocity.dx, velocity.dy)
            if fitted > median * 1.25, fitted > 0 {
                return FlickRelease(velocity: CGVector(dx: velocity.dx * median / fitted, dy: velocity.dy * median / fitted),
                                    peakSpeed: max(peak, median))
            }
        }
        return FlickRelease(velocity: velocity, peakSpeed: max(peak, hypot(velocity.dx, velocity.dy)))
    }

    private static func slope(_ points: [FlickSample]) -> CGVector {
        let t0 = points[0].time
        let n = CGFloat(points.count)
        var st: CGFloat = 0, sx: CGFloat = 0, sy: CGFloat = 0, stt: CGFloat = 0, stx: CGFloat = 0, sty: CGFloat = 0
        for p in points {
            let t = CGFloat(p.time - t0)
            st += t; sx += p.point.x; sy += p.point.y
            stt += t * t; stx += t * p.point.x; sty += t * p.point.y
        }
        let d = n * stt - st * st
        guard d > 0 else { return .zero }
        return CGVector(dx: (n * stx - st * sx) / d, dy: (n * sty - st * sy) / d)
    }
}

/// 设计系统 §4.6 的弹簧令牌（§6-5 收拢）。第一轮只把现值收进来，参数逐字不变；
/// 对照测试在 tests/MotionTokensTests.swift。dampingRatio = 1 − bounce。
///
/// 放在 Core 这一层（而不是 App/Motion.swift）：只编译 `Core/FlickMotion.swift` 的单测也要能用它，
/// `Motion.Spring` 在 App/Motion.swift 里是这里的同名别名。
struct MotionSpring: Equatable {
    var response: Double
    var dampingRatio: Double
    var bounce: CGFloat

    /// 没有动量的变化：指针停上来、收回、换状态。
    static let calm = MotionSpring(response: 0.34, dampingRatio: 1, bounce: 0)
    /// 尺寸变化；截图飞进刘海（终点是个口子，不回弹）。
    static let settle = MotionSpring(response: 0.38, dampingRatio: 1, bounce: 0)
    /// 展开一排。
    static let expand = MotionSpring(response: 0.4, dampingRatio: 0.92, bounce: 0.08)
    /// 有变化时提醒、教学。
    static let bloom = MotionSpring(response: 0.42, dampingRatio: 0.84, bounce: 0.16)
    /// 拖着窗口到刘海时的落点小岛（`catch` 是保留字，所以叫 catchDrop）。
    static let catchDrop = MotionSpring(response: 0.4, dampingRatio: 0.8, bounce: 0.2)
    /// 甩一下标题栏后的窗口滑行位置；画中画落角沿用同一手感。
    static let glide = MotionSpring(response: 0.42, dampingRatio: 0.88, bounce: 0.12)
    /// 截图从刘海飞出。
    static let flyOut = MotionSpring(response: 0.38, dampingRatio: 0.9, bounce: 0.1)
    /// 刘海下拉松手弹回。
    static let pull = MotionSpring(response: 0.36, dampingRatio: 0.86, bounce: 0.14)
    /// 只给小元素的确认：提示浮窗的终点图标。
    static let pop = MotionSpring(response: 0.3, dampingRatio: 0.75, bounce: 0.25)
    /// 减少动态效果时的岛。
    static let reducedNotch = MotionSpring(response: 0.25, dampingRatio: 1, bounce: 0)
    /// 减少动态效果时的窗口滑行。
    static let reducedWindow = MotionSpring(response: 0.3, dampingRatio: 1, bounce: 0)
}

/// 一维阻尼弹簧，参数用 Apple 的两个说法：dampingRatio（1 = 不过冲，越小越弹）与 response（秒，越小越快）。
/// 解析解：任何时刻都能直接算出位置和速度，所以动画可以按当前时间取值，卡了就跳帧，不会越走越慢。
struct FlickSpring: Equatable {
    var dampingRatio: Double
    var response: Double

    /// 位置沿用 PiP 挪动的手感，带一点落定时的回弹（甩的动作本身带着动量）。
    static let position = FlickSpring(dampingRatio: MotionSpring.glide.dampingRatio, response: MotionSpring.glide.response)
    /// 尺寸不带初速度，不回弹。
    static let size = FlickSpring(dampingRatio: MotionSpring.settle.dampingRatio, response: MotionSpring.settle.response)
    /// 打开了“减少动态效果”：不回弹，快一点落定（HIG：Motion，收紧弹簧、减少回弹）。
    static let calm = FlickSpring(dampingRatio: MotionSpring.reducedWindow.dampingRatio, response: MotionSpring.reducedWindow.response)

    /// t 秒后离目标的位移与速度。x0：起点减目标；v0：初速度（同一坐标轴）。
    func state(displacement x0: Double, velocity v0: Double, at t: Double) -> (x: Double, v: Double) {
        let w0 = 2 * Double.pi / response
        let z = dampingRatio
        if z < 1 {
            let wd = w0 * (1 - z * z).squareRoot()
            let a = x0, b = (v0 + z * w0 * x0) / wd
            let e = exp(-z * w0 * t), c = cos(wd * t), s = sin(wd * t)
            return (e * (a * c + b * s), e * ((b * wd - z * w0 * a) * c - (a * wd + z * w0 * b) * s))
        }
        let k = v0 + w0 * x0
        let e = exp(-w0 * t)
        return ((x0 + k * t) * e, (k - w0 * (x0 + k * t)) * e)
    }

    /// 冲过目标最远多少（点）。x0 为 0 时，任何离开都算冲过。
    func overshoot(displacement x0: Double, velocity v0: Double) -> Double {
        var worst = 0.0
        var t = 0.0
        while t <= 1.2 {
            let x = state(displacement: x0, velocity: v0, at: t).x
            if x0 > 0 { worst = max(worst, -x) } else if x0 < 0 { worst = max(worst, x) } else { worst = max(worst, abs(x)) }
            t += 1.0 / 240
        }
        return worst
    }

    /// 甩得太猛、离目标又近时，窗口会冲过头很远再弹回来。把朝目标方向的初速度降到冲过头不超过 limit。
    /// 背离目标的那部分速度基本不受影响：惯性带着多走一点再回来，一般不会冲过目标。
    func limitingOvershoot(displacement x0: Double, velocity v0: Double, limit: Double) -> Double {
        guard overshoot(displacement: x0, velocity: v0) > limit else { return v0 }
        var low = 0.0, high = 1.0
        for _ in 0..<24 {
            let mid = (low + high) / 2
            if overshoot(displacement: x0, velocity: v0 * mid) > limit { high = mid } else { low = mid }
        }
        return v0 * low
    }
}

/// 窗口从松手处带着速度滑到目标的整条路径（AX 坐标：y 向下）。
/// 位置接上甩出去的速度；尺寸从零速度开始慢慢变；四个量各走各的弹簧（Apple：二维运动拆成独立的轴）。
struct FlickGlidePath: Equatable {
    let from: CGRect
    let to: CGRect
    /// 起步速度（点/秒，AX 坐标 y 向下），已经按冲过头的上限处理过。
    let velocity: CGVector
    let position: FlickSpring
    let size: FlickSpring
    /// 走到离目标不到这么多点、速度也够小，就算落定；剩下的由最后一次校准补齐。
    static let settleDistance = 1.5
    static let settleSpeed = 30.0
    static let maxDuration = 1.0
    static let maxOvershoot = 28.0

    init(from: CGRect, to: CGRect, velocity: CGVector,
         position: FlickSpring = .position, size: FlickSpring = .size) {
        self.from = from
        self.to = to
        self.position = position
        self.size = size
        let vx = position.limitingOvershoot(displacement: Double(from.minX - to.minX), velocity: Double(velocity.dx),
                                            limit: Self.maxOvershoot)
        let vy = position.limitingOvershoot(displacement: Double(from.minY - to.minY), velocity: Double(velocity.dy),
                                            limit: Self.maxOvershoot)
        self.velocity = CGVector(dx: vx, dy: vy)
    }

    private func axes(at t: Double) -> [(x: Double, v: Double)] {
        [position.state(displacement: Double(from.minX - to.minX), velocity: Double(velocity.dx), at: t),
         position.state(displacement: Double(from.minY - to.minY), velocity: Double(velocity.dy), at: t),
         size.state(displacement: Double(from.width - to.width), velocity: 0, at: t),
         size.state(displacement: Double(from.height - to.height), velocity: 0, at: t)]
    }

    func frame(at t: Double) -> CGRect {
        let a = axes(at: t)
        return CGRect(x: to.minX + CGFloat(a[0].x), y: to.minY + CGFloat(a[1].x),
                      width: to.width + CGFloat(a[2].x), height: to.height + CGFloat(a[3].x))
    }

    func settled(at t: Double) -> Bool {
        t >= Self.maxDuration || axes(at: t).allSatisfy { abs($0.x) < Self.settleDistance && abs($0.v) < Self.settleSpeed }
    }

    /// 多久落定（秒）。
    var duration: Double {
        var t = 0.0
        while !settled(at: t) { t += 1.0 / 240 }
        return t
    }
}

/// 橡皮筋和惯性推算（WWDC18「Designing Fluid Interfaces」）。
enum FluidMotion {
    /// 越往外越拉不动，但永远不会撞墙：x·d·c / (d + c·x)，c = 0.55，x 再大也到不了 d。
    static func rubberBand(_ x: Double, limit d: Double) -> Double {
        guard x > 0, d > 0 else { return 0 }
        let c = 0.55
        return x * d * c / (d + c * x)
    }

    /// 橡皮筋在 x 处的斜率（手指动 1 点，东西动几点）：松手时把手指速度换成被拉的东西的速度。
    static func rubberBandSlope(_ x: Double, limit d: Double) -> Double {
        guard d > 0 else { return 0 }
        let c = 0.55
        let base = d + c * max(0, x)
        return c * d * d / (base * base)
    }

    /// 松手后按惯性还会走多远（点）：(v/1000)·r/(1−r)。r 是每毫秒保留的速度：0.998 像普通滚动，0.99 停得快。
    static func projection(velocity: Double, decelerationRate r: Double = 0.998) -> Double {
        velocity / 1000 * r / (1 - r)
    }

    /// 停下来那一段的阻尼弹簧：t 秒时的位置（点）。和官网那段动画同一条公式——
    ///   p(t) = 1 − e^(−ζωt)·(cos(ω_d t) + ((ζω − v₀)/ω_d)·sin(ω_d t))，ω_d = ω√(1−ζ²)，v₀ = v/d，
    ///   x(t) = from + d·p(t)，d = to − from。
    /// ζ=1（临界阻尼）时取极限：p(t) = 1 − e^(−ωt)·(1 + (ω − v₀)t)。
    /// 只按「经过了多少时间」算，不是每帧累加——所以 60Hz / 120Hz 是同一条曲线，掉帧也不走样、不变慢。
    static func spring(_ t: Double, from: Double, to: Double, velocity: Double,
                       zeta: Double, omega: Double) -> Double {
        springState(t, from: from, to: to, velocity: velocity, zeta: zeta, omega: omega).position
    }

    /// 位置和速度一起算：速度用来判断什么时候算停下。
    static func springState(_ t: Double, from: Double, to: Double, velocity: Double,
                            zeta: Double, omega: Double) -> (position: Double, velocity: Double) {
        let d = to - from
        guard d != 0 else { return (from, 0) }
        let v0 = velocity / d
        if abs(zeta - 1) < 0.0001 {
            let e = exp(-omega * t)
            return (from + d * (1 - e * (1 + (omega - v0) * t)),
                    d * e * (v0 + omega * (omega - v0) * t))
        }
        let wd = omega * (1 - zeta * zeta).squareRoot()
        let e = exp(-zeta * omega * t)
        let c = (zeta * omega - v0) / wd
        let wave = cos(wd * t) + c * sin(wd * t)
        return (from + d * (1 - e * wave),
                d * e * (zeta * omega * wave + wd * sin(wd * t) - c * wd * cos(wd * t)))
    }
}
