// 代理先动、真窗后到（整合计划第 13–14 步，Aaron 2026-10-31 定）的纯计算：可单测，不碰窗口与 CALayer。
// 手势中代理按手指进度从当前外框长向目标（ProxyFollow），目标处画半透明落点外框；松手代理带速度用弹簧落到目标
// （ProxyMotion）——四个量各走各的弹簧（WWDC18：二维运动拆独立轴），公式即 FlickSpring 的解析解（MorphRetarget
// 也用它算在飞动画的瞬时速度）；落定前被接住或改道从此刻位置与速度接着走（retargeted），位置速度都连续
// （WWDC23 10158：打断用当时的速度作初速度）；真窗口只在落定时写一次外框（ProxyCommitLedger 记账，第二次写
// 被拒）；减少动态效果不平移不缩放，原处淡出目标淡入（ProxyPresentation）。

import CoreGraphics
import Foundation

/// 手势进行中代理跟手：进度 → 代理外框。
enum ProxyFollow {
    /// 走满之后再往前推，代理还能冲过目标多少（目标行程的比例）：橡皮筋，越推越难，永远到不了这个上限。
    static let overshootLimit = 0.12

    /// 手势进度（1 = 松手即执行）换成代理走到全程的几成。ratio 沿用标题栏收起跟手的 0.55：
    /// 走满门槛时代理到 0.55，松手接着走完；继续推到约 1.8 倍门槛，代理就在手指下到达终点。
    /// 过了终点按橡皮筋（FluidMotion.rubberBand，c = 0.55）。往回拉到负进度时停在起点，不往反方向长。
    static func fraction(progress: CGFloat, followRatio: Double) -> Double {
        let raw = max(0, Double(progress)) * followRatio
        guard raw > 1 else { return raw }
        return 1 + FluidMotion.rubberBand(raw - 1, limit: overshootLimit)
    }

    /// from → to 走到 fraction 处的外框（四个量各自线性插值；fraction > 1 时沿同一方向外推一点）。
    static func frame(from: CGRect, to: CGRect, fraction f: Double) -> CGRect {
        let t = CGFloat(f)
        return CGRect(x: from.minX + (to.minX - from.minX) * t,
                      y: from.minY + (to.minY - from.minY) * t,
                      width: max(1, from.width + (to.width - from.width) * t),
                      height: max(1, from.height + (to.height - from.height) * t))
    }

    /// 落点外框的不透明度：认出方向就淡淡出现，走满（松手即执行）时到最深。
    /// 只表示“松手会到这里”，不抢代理本身的戏。
    static let landingFaint: CGFloat = 0.25
    static func landingOpacity(progress: CGFloat) -> CGFloat {
        let p = min(1, max(0, progress))
        return p >= 1 ? 1 : landingFaint + (0.7 - landingFaint) * p
    }
}

/// 代理四个量（x、y、宽、高；AX 坐标 y 向下）的速度，点/秒。
struct ProxyVelocity: Equatable {
    var dx: Double = 0
    var dy: Double = 0
    var dw: Double = 0
    var dh: Double = 0
    static let zero = ProxyVelocity()
}

/// 代理松手后落向目标的整条运动：四个量各走各的弹簧，解析解，任何时刻都能直接取位置和速度。
struct ProxyMotion: Equatable {
    let target: CGRect
    /// 这段运动开始的时刻（秒，和调用者的时钟同一口径，例如 CACurrentMediaTime）。
    let start: Double
    /// 开始时离目标的位移（起点减目标）：x、y、宽、高。
    let displacement: [Double]
    /// 开始时的速度：x、y、宽、高。
    let velocity: [Double]
    let position: FlickSpring
    let size: FlickSpring

    /// 走到离目标不到这么多点、速度也够小，就算落定（和 FlickGlidePath 同口径）。
    static let settleDistance = 0.5
    static let settleSpeed = 20.0
    static let maxDuration = 1.2

    /// limitOvershoot：甩得太猛又离目标近时，位置轴冲过头最多这么多点（FlickGlidePath.maxOvershoot）。
    /// 改道（retargeted）不再削速度：削了速度就不连续了。
    init(from: CGRect, to: CGRect, velocity v: ProxyVelocity, at time: Double,
         position: FlickSpring = .position, size: FlickSpring = .size, limitOvershoot: Double? = FlickGlidePath.maxOvershoot) {
        let x0 = [Double(from.minX - to.minX), Double(from.minY - to.minY),
                  Double(from.width - to.width), Double(from.height - to.height)]
        var v0 = [v.dx, v.dy, v.dw, v.dh]
        if let limit = limitOvershoot {
            v0[0] = position.limitingOvershoot(displacement: x0[0], velocity: v0[0], limit: limit)
            v0[1] = position.limitingOvershoot(displacement: x0[1], velocity: v0[1], limit: limit)
        }
        self.init(target: to, start: time, displacement: x0, velocity: v0, position: position, size: size)
    }

    private init(target: CGRect, start: Double, displacement: [Double], velocity: [Double],
                 position: FlickSpring, size: FlickSpring) {
        self.target = target
        self.start = start
        self.displacement = displacement
        self.velocity = velocity
        self.position = position
        self.size = size
    }

    private func axes(at time: Double) -> [(x: Double, v: Double)] {
        let t = max(0, time - start)
        return (0..<4).map { i in
            (i < 2 ? position : size).state(displacement: displacement[i], velocity: velocity[i], at: t)
        }
    }

    /// time 时刻代理的外框与速度。
    func state(at time: Double) -> (frame: CGRect, velocity: ProxyVelocity) {
        let a = axes(at: time)
        let frame = CGRect(x: target.minX + CGFloat(a[0].x), y: target.minY + CGFloat(a[1].x),
                           width: max(1, target.width + CGFloat(a[2].x)), height: max(1, target.height + CGFloat(a[3].x)))
        return (frame, ProxyVelocity(dx: a[0].v, dy: a[1].v, dw: a[2].v, dh: a[3].v))
    }

    func frame(at time: Double) -> CGRect { state(at: time).frame }

    /// 中途改道：从 time 这一刻的位置和速度出发落向新目标。新运动在 time 的位置、速度和旧运动逐分量相等。
    /// 弹簧可以换（例如改道回原处用不回弹的那根），连续性不受影响：连续的是状态，不是参数。
    func retargeted(to newTarget: CGRect, at time: Double,
                    position: FlickSpring? = nil, size: FlickSpring? = nil) -> ProxyMotion {
        let now = state(at: time)
        let x0 = [Double(now.frame.minX - newTarget.minX), Double(now.frame.minY - newTarget.minY),
                  Double(now.frame.width - newTarget.width), Double(now.frame.height - newTarget.height)]
        let v0 = [now.velocity.dx, now.velocity.dy, now.velocity.dw, now.velocity.dh]
        return ProxyMotion(target: newTarget, start: time, displacement: x0, velocity: v0,
                           position: position ?? self.position, size: size ?? self.size)
    }

    func settled(at time: Double) -> Bool {
        time - start >= Self.maxDuration
            || axes(at: time).allSatisfy { abs($0.x) < Self.settleDistance && abs($0.v) < Self.settleSpeed }
    }

    /// 从 start 起多久落定（秒）。
    var duration: Double {
        var t = start
        while !settled(at: t) { t += 1.0 / 240 }
        return t - start
    }

    /// 从 start 到落定、每 step 秒一个外框，末帧钉在目标上。给 Core Animation 的关键帧用：
    /// 弹簧由系统渲染进程按这些点线性插值播放，主线程忙也不掉帧；曲线本身就是弹簧的解，不套贝塞尔。
    func samples(step: Double = 1.0 / 120) -> (times: [Double], frames: [CGRect]) {
        let total = max(step, duration)
        var times: [Double] = []
        var frames: [CGRect] = []
        var t = 0.0
        while t < total {
            times.append(t)
            frames.append(frame(at: start + t))
            t += step
        }
        times.append(total)
        frames.append(target)
        return (times, frames)
    }
}

/// 手势进行中，代理外框的几个最近位置：松手时估出代理此刻的速度（最小二乘斜率，和 FlickRelease 同一做法）。
struct ProxyTrail {
    private(set) var points: [(time: Double, frame: CGRect)] = []
    static let window = 0.06

    mutating func add(_ frame: CGRect, at time: Double) {
        points.append((time, frame))
        points.removeAll { $0.time < time - 0.25 }
    }

    mutating func reset() { points.removeAll() }

    /// 离 time 最近 60 毫秒里的速度；点不够、或最后一个点已经过去 80 毫秒以上（手停住了）时为零。
    func velocity(at time: Double) -> ProxyVelocity {
        let recent = points.filter { $0.time >= time - Self.window && $0.time <= time + 0.0005 }
        guard recent.count >= 2, let last = recent.last, time - last.time <= 0.08,
              last.time - recent[0].time >= 0.008 else { return .zero }
        func slope(_ value: (CGRect) -> CGFloat) -> Double {
            let t0 = recent[0].time
            let n = Double(recent.count)
            var st = 0.0, sx = 0.0, stt = 0.0, stx = 0.0
            for p in recent {
                let t = p.time - t0, x = Double(value(p.frame))
                st += t; sx += x; stt += t * t; stx += t * x
            }
            let d = n * stt - st * st
            return d > 0 ? (n * stx - st * sx) / d : 0
        }
        return ProxyVelocity(dx: slope(\.minX), dy: slope(\.minY), dw: slope(\.width), dh: slope(\.height))
    }
}

/// 真窗口外框“只写一次”的账：每次提交开一个号，写的时候来登记；同一个号第二次来会被拒绝。
/// 探针按窗口查最近一次提交写了几次（应当恰好是 1；目标就是原处时是 0）。
struct ProxyCommitLedger {
    private var next: UInt64 = 1
    private var writes: [UInt64: Int] = [:]
    private var lastByWindow: [UInt32: UInt64] = [:]

    /// 开一次提交，返回它的号。
    mutating func open(window: UInt32) -> UInt64 {
        let token = next
        next &+= 1
        writes[token] = 0
        lastByWindow[window] = token
        return token
    }

    /// 要写之前登记：这一次提交还没写过才放行。
    mutating func admitWrite(_ token: UInt64) -> Bool {
        guard let count = writes[token], count == 0 else {
            if writes[token] != nil { writes[token, default: 0] += 1 }
            return false
        }
        writes[token] = 1
        return true
    }

    /// 这一次提交实际登记了几次写（被拒绝的也算进去，好让测试看见“想写第二次”）。
    func attempts(_ token: UInt64) -> Int { writes[token] ?? 0 }

    /// 这扇窗最近一次提交登记了几次写。
    func lastAttempts(window: UInt32) -> Int? { lastByWindow[window].map { attempts($0) } }
}

/// 真窗口落定后的几何判断（纯计算）。
enum ProxyLanding {
    /// 窗口外框和目标差在 4 点以内就算到位（和排布的 sameFrame 同一个容差量级）。
    static func arrived(_ frame: CGRect, at target: CGRect, tolerance: CGFloat = 4) -> Bool {
        abs(frame.minX - target.minX) <= tolerance && abs(frame.minY - target.minY) <= tolerance
            && abs(frame.width - target.width) <= tolerance && abs(frame.height - target.height) <= tolerance
    }

    /// App 不肯变成目标大小：按它实际的 size 放进 target 正中，并且不出 area（放不下时贴着 area 的左上）。
    static func centered(_ size: CGSize, in target: CGRect, area: CGRect) -> CGRect {
        var origin = CGPoint(x: target.midX - size.width / 2, y: target.midY - size.height / 2)
        if !area.isEmpty {
            origin.x = min(max(origin.x, area.minX), max(area.minX, area.maxX - size.width))
            origin.y = min(max(origin.y, area.minY), max(area.minY, area.maxY - size.height))
        }
        return CGRect(origin: origin, size: size)
    }
}

/// 代理怎么到新位置：平时滑过去；减少动态效果时原处淡出、目标处淡入（不平移、不缩放）。
enum ProxyPresentation: Equatable {
    case slide
    case dissolve

    static func choose(reduceMotion: Bool) -> ProxyPresentation { reduceMotion ? .dissolve : .slide }
}

/// 代理长什么样：有屏幕录制、截到了窗口，就是窗口的截图（原处盖一张背景）；否则是窗口圆角的描边。
enum ProxyLook: Equatable {
    case snapshot
    case outline

    static func choose(hasSnapshot: Bool) -> ProxyLook { hasSnapshot ? .snapshot : .outline }
}

/// 收起动画（“收起窗口时的动画”）的默认值：第 19 条定为默认开。
/// 只改默认：偏好里没有这个键 → 开；用户明确关过（存着 false）→ 仍然关。
enum FoldAnimationDefault {
    static let enabledWhenUnset = true

    static func resolve(stored: Any?) -> Bool {
        if let value = stored as? Bool { return value }
        if let number = stored as? NSNumber { return number.boolValue }
        return enabledWhenUnset
    }
}
