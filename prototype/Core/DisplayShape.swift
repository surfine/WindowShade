// 屏幕的真实形状（设计系统 §3）：刘海底角、肩、屏幕四个角。纯计算，不碰屏幕、不碰窗口，可单测。
//
// 拿形状的顺序（§3.4）：
// - 有没有刘海、刘海主体在哪、多大：公开接口永远说了算（safeAreaInsets + auxiliaryTopLeft/RightArea，
//   这里只收它算好的矩形）。bezelPath 和机型表都只补曲线，不决定有没有刘海。
// - 曲线：① 系统私有的 NSScreen.bezelPath，先过一遍校验（外框和 frame 对得上；刘海的竖边、底边和公开矩形差 ≤1 点；
//   四段角都像连续曲率角；没有刘海的屏上不能有缺口）；② 机型表，按原生面板像素查；③ 都不行就是现版本的几何：
//   底角 10 / 12、不画肩、屏幕直角。
// - 硬件数值按面板像素（px）存，用的时候除以 pxPerPt = 原生面板像素宽 ÷ frame 宽。不用 backingScaleFactor：
//   1710×1107 模式下它是 2，实际是 2880 ÷ 1710 = 1.684。
// 坐标：Cocoa（原点左下、y 向上）。bezelPath 是全局坐标，先和全局 frame 比，再换成屏内坐标量曲线。

import CoreGraphics

// MARK: - 连续曲率角

/// 连续曲率圆角：CALayer.cornerCurve = .continuous 和 SwiftUI 的 RoundedRectangle(style: .continuous) 画的那一条
/// （离线比过，两者渲染逐像素一样，见 tests/DisplayShapeTests.swift）。半径 r 的角沿两条边各占 1.5287·r，
/// 45° 方向上离尖角 0.2915·r（每个轴上）。硬件的顶角、刘海底角、肩都按它描述（§3.1）。
enum ContinuousCorner {
    /// 一个角的起点和三段三次曲线，单位半径：尖角在原点，两条边沿 +x、+y，从 (0, extent) 走到 (extent, 0)。
    /// 数值取自 SwiftUI 的 .continuous 路径（测试里从系统重新取一遍核对）。
    static let start = CGPoint(x: 0, y: 1.52866495)
    static let unit: [(c1: CGPoint, c2: CGPoint, to: CGPoint)] = [
        (CGPoint(x: 0, y: 1.08849001), CGPoint(x: 0, y: 0.86840701), CGPoint(x: 0.07491140, y: 0.63149399)),
        (CGPoint(x: 0.16906001, y: 0.37282401), CGPoint(x: 0.37282401, y: 0.16906001), CGPoint(x: 0.63149399, y: 0.07491140)),
        (CGPoint(x: 0.86840701, y: 0), CGPoint(x: 1.08849001, y: 0), CGPoint(x: 1.52866495, y: 0)),
    ]
    /// 沿每条边占多长（÷ r），= CALayer.cornerCurveExpansionFactor(.continuous)。
    static let extent: CGFloat = 1.52866495
    /// 45° 方向上曲线离尖角多远（每个轴上，÷ r）：中间那段曲线对称，t = 0.5 正好落在对角线上。
    static let inset45: CGFloat = cubic(unit[0].to, unit[1].c1, unit[1].c2, unit[1].to, 0.5).x

    static func cubic(_ p0: CGPoint, _ c1: CGPoint, _ c2: CGPoint, _ p3: CGPoint, _ t: CGFloat) -> CGPoint {
        let s = 1 - t
        let a = s * s * s, b = 3 * s * s * t, c = 3 * s * t * t, d = t * t * t
        return CGPoint(x: a * p0.x + b * c1.x + c * c2.x + d * p3.x, y: a * p0.y + b * c1.y + c * c2.y + d * p3.y)
    }

    /// 半径 r 的角拆成折线（尖角在原点，从 (0, extent·r) 走到 (extent·r, 0)）。
    static func polyline(radius r: CGFloat, samplesPerSegment n: Int = 16) -> [CGPoint] {
        var points = [CGPoint(x: start.x * r, y: start.y * r)]
        var from = start
        for segment in unit {
            for i in 1...n {
                let p = cubic(from, segment.c1, segment.c2, segment.to, CGFloat(i) / CGFloat(n))
                points.append(CGPoint(x: p.x * r, y: p.y * r))
            }
            from = segment.to
        }
        return points
    }

    /// 刘海的左肩（显示区在刘海竖边和屏幕顶边相接处的凸角被切掉的那一小块，是黑的）：
    /// 原点是岛的左上角，往左（−x）、往下（−y）长。overlap：往岛里、往屏幕外各多画一点，和岛之间不留抗锯齿的缝。
    /// 右肩把 x 取反。
    static func leftShoulder(radius r: CGFloat, overlap o: CGFloat) -> [OutlineStep] {
        let e = extent * r
        // 显示区的圆角从顶边 (−e, 0) 弯到竖边 (0, −e)：把单位角倒着走一遍，(a, b) 映射成 (−a·r, −b·r)。
        func map(_ p: CGPoint) -> CGPoint { CGPoint(x: -p.x * r, y: -p.y * r) }
        var steps: [OutlineStep] = [.move(CGPoint(x: o, y: o)), .line(CGPoint(x: -e, y: o)), .line(CGPoint(x: -e, y: 0))]
        let starts = [start, unit[0].to, unit[1].to]
        for index in unit.indices.reversed() {
            let segment = unit[index]
            steps.append(.curve(map(starts[index]), control1: map(segment.c2), control2: map(segment.c1)))
        }
        steps += [.line(CGPoint(x: o, y: -e)), .close]
        return steps
    }
}

// MARK: - 路径

/// 一段路径命令（和 NSBezierPath / CGPath 的元素一一对应）。
enum OutlineStep: Equatable {
    case move(CGPoint)
    case line(CGPoint)
    case quad(CGPoint, control: CGPoint)
    case curve(CGPoint, control1: CGPoint, control2: CGPoint)
    case close
}

enum Outline {
    /// 把路径拆成点：直线每 2 点一个，曲线每段 16 个（弦高不到 0.01 点）；按子路径分组。offset 加到每个点上（换坐标用）。
    static func points(_ steps: [OutlineStep], offset: CGVector = .zero) -> [[CGPoint]] {
        var result: [[CGPoint]] = []
        var current: [CGPoint] = []
        var first: CGPoint?
        func shifted(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x + offset.dx, y: p.y + offset.dy) }
        func lineTo(_ q: CGPoint) {
            guard let p = current.last else { current = [q]; return }
            let steps = max(1, Int((hypot(q.x - p.x, q.y - p.y) / 2).rounded(.up)))
            for i in 1...steps {
                let t = CGFloat(i) / CGFloat(steps)
                current.append(CGPoint(x: p.x + (q.x - p.x) * t, y: p.y + (q.y - p.y) * t))
            }
        }
        for step in steps {
            switch step {
            case .move(let p):
                if !current.isEmpty { result.append(current) }
                current = [shifted(p)]
                first = shifted(p)
            case .line(let p):
                lineTo(shifted(p))
            case .quad(let p, let c):
                guard let p0 = current.last else { current = [shifted(p)]; continue }
                let q = shifted(p), k = shifted(c)
                // 二次曲线升成三次。
                let c1 = CGPoint(x: p0.x + 2 / 3 * (k.x - p0.x), y: p0.y + 2 / 3 * (k.y - p0.y))
                let c2 = CGPoint(x: q.x + 2 / 3 * (k.x - q.x), y: q.y + 2 / 3 * (k.y - q.y))
                for i in 1...16 { current.append(ContinuousCorner.cubic(p0, c1, c2, q, CGFloat(i) / 16)) }
            case .curve(let p, let c1, let c2):
                guard let p0 = current.last else { current = [shifted(p)]; continue }
                let q = shifted(p), k1 = shifted(c1), k2 = shifted(c2)
                for i in 1...16 { current.append(ContinuousCorner.cubic(p0, k1, k2, q, CGFloat(i) / 16)) }
            case .close:
                if let first { lineTo(first) }
                if !current.isEmpty { result.append(current) }
                current = []
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}

// MARK: - 量一个角

/// 一个角量出来的样子（pt）。
struct CornerFit: Equatable {
    /// 最贴合的连续曲率角半径；0 是直角。
    var radius: CGFloat
    /// 45° 方向上路径离尖角多远（每个轴上）：最稳的描述量，验收用它。
    var inset45: CGFloat
    /// 路径上离拟合出的角最远的一点。
    var deviation: CGFloat
}

enum CornerFitter {
    /// vertex：尖角；u、w：两条边离开尖角的方向（单位向量），形状在它们张成的那个象限里。
    /// alongU、alongW：沿两条边各量多远，只量这一个角、不碰旁边的角。量不到（路径不经过这里）返回 nil。
    static func fit(_ lines: [[CGPoint]], vertex: CGPoint, u: CGVector, w: CGVector,
                    alongU: CGFloat, alongW: CGFloat) -> CornerFit? {
        func local(_ p: CGPoint) -> CGPoint {
            let dx = p.x - vertex.x, dy = p.y - vertex.y
            return CGPoint(x: dx * u.dx + dy * u.dy, y: dx * w.dx + dy * w.dy)
        }
        let locals = lines.map { $0.map(local) }
        // 45°：折线和对角线 a = b 的交点里，在量的范围内、离尖角最近的那一个。
        var inset: CGFloat?
        for line in locals {
            for (p, q) in zip(line, line.dropFirst()) {
                let fp = p.x - p.y, fq = q.x - q.y
                guard (fp <= 0 && fq >= 0) || (fp >= 0 && fq <= 0) else { continue }
                let t = fp == fq ? 0 : fp / (fp - fq)
                let x = p.x + t * (q.x - p.x)
                guard x >= -0.5, x <= min(alongU, alongW) else { continue }
                inset = min(inset ?? x, x)
            }
        }
        guard let d45 = inset else { return nil }
        let samples = locals.joined().filter { $0.x >= -0.5 && $0.y >= -0.5 && $0.x <= alongU && $0.y <= alongW }
        guard samples.count >= 4 else { return nil }
        let d = max(0, d45)
        if d < 0.05 {
            return CornerFit(radius: 0, inset45: d, deviation: deviation(samples, radius: 0, alongU: alongU, alongW: alongW))
        }
        // 最大偏差最小的 r：从 45° 内缩估一个起点，在 ±30% 里用黄金分割找。
        let guess = d / ContinuousCorner.inset45
        var lo = guess * 0.7, hi = min(guess * 1.3, min(alongU, alongW) / ContinuousCorner.extent)
        if hi <= lo { hi = lo + 0.01 }
        let golden: CGFloat = 0.618_034
        var a = hi - golden * (hi - lo), b = lo + golden * (hi - lo)
        var fa = deviation(samples, radius: a, alongU: alongU, alongW: alongW)
        var fb = deviation(samples, radius: b, alongU: alongU, alongW: alongW)
        for _ in 0..<24 {
            if fa < fb {
                hi = b; b = a; fb = fa
                a = hi - golden * (hi - lo)
                fa = deviation(samples, radius: a, alongU: alongU, alongW: alongW)
            } else {
                lo = a; a = b; fa = fb
                b = lo + golden * (hi - lo)
                fb = deviation(samples, radius: b, alongU: alongU, alongW: alongW)
            }
        }
        let r = (lo + hi) / 2
        return CornerFit(radius: r, inset45: d, deviation: deviation(samples, radius: r, alongU: alongU, alongW: alongW))
    }

    /// 样本点离“两条直边 + 半径 r 的连续曲率角”最远有多远。
    static func deviation(_ samples: [CGPoint], radius: CGFloat, alongU: CGFloat, alongW: CGFloat) -> CGFloat {
        let e = ContinuousCorner.extent * radius
        let model = [CGPoint(x: 0, y: max(alongW, e) + 1)] + ContinuousCorner.polyline(radius: radius)
            + [CGPoint(x: max(alongU, e) + 1, y: 0)]
        var worst: CGFloat = 0
        for p in samples {
            var nearest = CGFloat.greatestFiniteMagnitude
            for (a, b) in zip(model, model.dropFirst()) {
                nearest = min(nearest, distance(p, a, b))
                if nearest < 0.001 { break }
            }
            worst = max(worst, nearest)
        }
        return worst
    }

    static func distance(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let length = dx * dx + dy * dy
        let t = length == 0 ? 0 : max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / length))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }
}

// MARK: - bezelPath 的校验

/// 刘海的两种曲线（pt）。
struct NotchCurves: Equatable {
    /// 刘海底角（连续曲率角的 r）：岛贴着刘海时的底角 `island.hug`。
    var bottomRadius: CGFloat
    /// 肩：刘海竖边和屏幕顶边相接处、显示区的那个凸角，和底角同一族曲线。
    var shoulderRadius: CGFloat
    /// 肩沿两条边各占多长。
    var shoulderExtent: CGFloat { shoulderRadius * ContinuousCorner.extent }
}

/// 从 bezelPath 读出来、过了校验的形状（pt，屏内坐标）。
struct BezelReading: Equatable {
    /// 刘海主体（两条竖边、底边；顶边是屏幕顶）。只做诊断：位置和大小照旧用公开接口给的矩形。
    var notchBody: CGRect?
    var notchCurves: NotchCurves?
    var topCorner: CGFloat
    var bottomCorner: CGFloat
    /// 刘海四段曲线、屏幕四个角里，路径离拟合出的连续曲率角最远的一点。
    var worstNotch: CGFloat
    var worstCorner: CGFloat
}

enum BezelCheck {
    /// 路径外框和全局 frame 每条边最多差多少（守卫 2）。
    static let frameTolerance: CGFloat = 0.5
    /// 刘海竖边、底边和公开矩形最多差多少（守卫 3）。
    static let notchTolerance: CGFloat = 1
    /// 刘海的四段曲线离连续曲率角最多差多少：本机实测 ≤0.05 点，超过 0.5 点说明不是我们认识的形状。
    static let curveTolerance: CGFloat = 0.5
    /// 屏幕四个角：它们比连续曲率角更方（§3.1），本机约 0.3 点；超过 1 点就不认。
    static let cornerTolerance: CGFloat = 1

    /// 校验并量出形状。frame：这块屏的全局 frame；notch：公开接口给的刘海（屏内坐标，nil 是没有刘海）。
    /// 不通过时 reading 为 nil，problem 说明是哪一条没过（记进诊断）。
    static func read(_ steps: [OutlineStep], frame: CGRect, notch: CGRect?) -> (reading: BezelReading?, problem: String?) {
        guard frame.width > 0, frame.height > 0 else { return (nil, "empty frame") }
        // 守卫 2：路径用全局坐标，外框和全局 frame 对得上，再换成屏内坐标。
        let global = Outline.points(steps)
        let all = global.joined()
        guard let minX = all.map(\.x).min(), let maxX = all.map(\.x).max(),
              let minY = all.map(\.y).min(), let maxY = all.map(\.y).max() else { return (nil, "empty path") }
        let off = max(abs(minX - frame.minX), abs(maxX - frame.maxX), abs(minY - frame.minY), abs(maxY - frame.maxY))
        guard off <= frameTolerance else { return (nil, "bounds off the frame by \(round2(off)) pt") }
        let lines = global.map { $0.map { CGPoint(x: $0.x - frame.minX, y: $0.y - frame.minY) } }
        let points = Array(lines.joined())
        let W = frame.width, H = frame.height

        // 屏幕四个角。
        let zone = min(80, W / 4, H / 4)
        func corner(_ v: CGPoint, _ u: CGVector, _ w: CGVector) -> CornerFit? {
            CornerFitter.fit(lines, vertex: v, u: u, w: w, alongU: zone, alongW: zone)
        }
        guard let tl = corner(CGPoint(x: 0, y: H), CGVector(dx: 1, dy: 0), CGVector(dx: 0, dy: -1)),
              let tr = corner(CGPoint(x: W, y: H), CGVector(dx: -1, dy: 0), CGVector(dx: 0, dy: -1)),
              let bl = corner(CGPoint(x: 0, y: 0), CGVector(dx: 1, dy: 0), CGVector(dx: 0, dy: 1)),
              let br = corner(CGPoint(x: W, y: 0), CGVector(dx: -1, dy: 0), CGVector(dx: 0, dy: 1))
        else { return (nil, "a screen corner is missing") }
        let cornerWorst = max(tl.deviation, tr.deviation, bl.deviation, br.deviation)
        guard cornerWorst <= cornerTolerance else { return (nil, "screen corners are not continuous (\(round2(cornerWorst)) pt)") }
        guard abs(tl.radius - tr.radius) <= 0.5, abs(bl.radius - br.radius) <= 0.5 else {
            return (nil, "screen corners differ left to right")
        }

        // 刘海附近那一段：路径从屏幕顶边往下凹进去的部分。
        let notchZone: CGRect? = notch.map { CGRect(x: $0.minX - 20, y: $0.minY - 5, width: $0.width + 40, height: H - $0.minY + 5) }
        // 守卫 4（以及有刘海时刘海以外的地方）：除了四个角、刘海，路径都得贴着屏幕边，不能有缺口。
        for p in points {
            let onEdge = min(p.x, W - p.x, p.y, H - p.y) <= frameTolerance
            let inCorner = (p.x <= zone || p.x >= W - zone) && (p.y <= zone || p.y >= H - zone)
            let inNotch = notchZone?.contains(p) ?? false
            guard onEdge || inCorner || inNotch else {
                return (nil, notch == nil ? "a notch-like gap on a screen without a notch" : "an unexpected gap at (\(round2(p.x)), \(round2(p.y)))")
            }
        }

        var body: CGRect?
        var curves: NotchCurves?
        var notchWorst: CGFloat = 0
        if let notch, let zoneRect = notchZone {
            // 守卫 3：按几何特征找（两段凹曲线、两条竖边、两段凸曲线、一条底边），不按元素下标。
            let dipped = points.filter { zoneRect.contains($0) && $0.y < H - 0.25 }
            // 底边是一段直线，拆成点后都落在同一个 y 上；它也得是这一段里最低的地方。
            guard let lowest = dipped.map(\.y).min() else { return (nil, "no notch in the path") }
            guard let bottom = dominant(dipped.map(\.y)), bottom - lowest <= 0.1 else { return (nil, "no straight notch bottom") }
            guard abs(bottom - notch.minY) <= notchTolerance else { return (nil, "notch bottom off by \(round2(bottom - notch.minY)) pt") }
            let floor = dipped.filter { abs($0.y - bottom) <= 0.01 }.map(\.x)
            guard let floorMin = floor.min(), let floorMax = floor.max(), floorMax - floorMin >= 10 else {
                return (nil, "no straight notch bottom")
            }
            func side(_ leftHalf: Bool) -> (x: CGFloat, low: CGFloat, high: CGFloat)? {
                let half = dipped.filter { leftHalf ? $0.x < notch.midX : $0.x > notch.midX }
                guard let x = dominant(half.map(\.x)) else { return nil }
                let edge = half.filter { abs($0.x - x) <= 0.01 }.map(\.y)
                guard let low = edge.min(), let high = edge.max(), high - low >= 2 else { return nil }
                return (x, low, high)
            }
            guard let left = side(true), let right = side(false) else { return (nil, "no straight notch sides") }
            guard abs(left.x - notch.minX) <= notchTolerance, abs(right.x - notch.maxX) <= notchTolerance else {
                return (nil, "notch sides off by \(round2(max(abs(left.x - notch.minX), abs(right.x - notch.maxX)))) pt")
            }
            let halfWidth = (right.x - left.x) / 2
            let fits = [
                // 肩：显示区的凸角，尖角在（竖边, 顶边）。
                CornerFitter.fit(lines, vertex: CGPoint(x: left.x, y: H), u: CGVector(dx: -1, dy: 0), w: CGVector(dx: 0, dy: -1),
                                 alongU: 20, alongW: H - left.low),
                CornerFitter.fit(lines, vertex: CGPoint(x: right.x, y: H), u: CGVector(dx: 1, dy: 0), w: CGVector(dx: 0, dy: -1),
                                 alongU: 20, alongW: H - right.low),
                // 底角：刘海主体的凸角，尖角在（竖边, 底边）。
                CornerFitter.fit(lines, vertex: CGPoint(x: left.x, y: bottom), u: CGVector(dx: 1, dy: 0), w: CGVector(dx: 0, dy: 1),
                                 alongU: halfWidth, alongW: left.high - bottom),
                CornerFitter.fit(lines, vertex: CGPoint(x: right.x, y: bottom), u: CGVector(dx: -1, dy: 0), w: CGVector(dx: 0, dy: 1),
                                 alongU: halfWidth, alongW: right.high - bottom),
            ]
            guard let leftShoulder = fits[0], let rightShoulder = fits[1], let leftBottom = fits[2], let rightBottom = fits[3] else {
                return (nil, "a notch curve is missing")
            }
            notchWorst = fits.compactMap { $0?.deviation }.max() ?? 0
            guard notchWorst <= curveTolerance else { return (nil, "notch curves are not continuous (\(round2(notchWorst)) pt)") }
            guard [leftShoulder, rightShoulder, leftBottom, rightBottom].allSatisfy({ $0.inset45 > 0.05 }) else {
                return (nil, "a notch corner is square")
            }
            guard abs(leftShoulder.radius - rightShoulder.radius) <= 0.3, abs(leftBottom.radius - rightBottom.radius) <= 0.3 else {
                return (nil, "notch curves differ left to right")
            }
            let shoulder = (leftShoulder.radius + rightShoulder.radius) / 2
            let bottomRadius = (leftBottom.radius + rightBottom.radius) / 2
            guard (0.5...15).contains(shoulder), (2...30).contains(bottomRadius) else {
                return (nil, "notch curves out of range (shoulder \(round2(shoulder)), bottom \(round2(bottomRadius)))")
            }
            body = CGRect(x: left.x, y: bottom, width: right.x - left.x, height: H - bottom)
            curves = NotchCurves(bottomRadius: bottomRadius, shoulderRadius: shoulder)
        }
        return (BezelReading(notchBody: body, notchCurves: curves,
                             topCorner: (tl.radius + tr.radius) / 2, bottomCorner: (bl.radius + br.radius) / 2,
                             worstNotch: notchWorst, worstCorner: cornerWorst), nil)
    }

    /// 一组数里重复最多的那个值：刘海的竖边、底边是直线，拆成点后都落在同一个 x（y）上；
    /// 曲线上的点各不相同，凑不成多数（差一点点的也不算，免得贴着直边的那段曲线把值带偏）。
    static func dominant(_ values: [CGFloat]) -> CGFloat? {
        var best: (value: CGFloat, count: Int)?
        for v in values {
            let count = values.reduce(0) { abs($1 - v) <= 1e-6 ? $0 + 1 : $0 }
            if count > (best?.count ?? 0) { best = (v, count) }
        }
        return best.flatMap { $0.count >= 3 ? $0.value : nil }
    }

    private static func round2(_ x: CGFloat) -> CGFloat { (x * 100).rounded() / 100 }
}

// MARK: - 机型表

/// 机型表的一行（§3.2）：键是内建屏的原生面板像素，五款互不相同；面板和刘海模组相同的旧代机型共用一行。
/// 数值都是面板像素（px），用时除以 pxPerPt。
struct PanelModel: Equatable {
    var name: String
    var pixels: CGSize
    /// 屏幕顶角，连续曲率角的 r。底角都是直角（天圆地方）。
    var topCorner: CGFloat
    /// 刘海底角、肩；nil 是没有刘海（MacBook Neo：摄像头在一圈均匀的边框里）。
    var notchBottom: CGFloat?
    var notchShoulder: CGFloat?
}

enum PanelTable {
    /// Air 的刘海按本机 Air 15″ 的 bezelPath 拟合（底角 10.71 点、肩 5.06 点 × 1.684），Air 13″ 同一模组；
    /// Pro 按 Apple Design Resources 的图稿，还没在真机上核对；顶角都按图稿。
    static let models: [PanelModel] = [
        PanelModel(name: "MacBook Neo", pixels: CGSize(width: 2408, height: 1506), topCorner: 33.6, notchBottom: nil, notchShoulder: nil),
        PanelModel(name: "MacBook Air 13-inch", pixels: CGSize(width: 2560, height: 1664), topCorner: 34.8, notchBottom: 18.0, notchShoulder: 8.5),
        PanelModel(name: "MacBook Air 15-inch", pixels: CGSize(width: 2880, height: 1864), topCorner: 34.1, notchBottom: 18.0, notchShoulder: 8.5),
        PanelModel(name: "MacBook Pro 14-inch", pixels: CGSize(width: 3024, height: 1964), topCorner: 39.7, notchBottom: 20.6, notchShoulder: 9.8),
        PanelModel(name: "MacBook Pro 16-inch", pixels: CGSize(width: 3456, height: 2234), topCorner: 40.3, notchBottom: 20.6, notchShoulder: 9.8),
    ]

    static func model(pixels: CGSize) -> PanelModel? {
        models.first { abs($0.pixels.width - pixels.width) < 0.5 && abs($0.pixels.height - pixels.height) < 0.5 }
    }
}

// MARK: - 一块屏的形状

enum DisplayShapeSource: String, Equatable {
    case bezel, table, fallback
}

/// 算一块屏的形状要的全部输入（AppKit 那一侧读好，这里只算）。
struct DisplayShapeInput: Equatable {
    /// 全局 frame（Cocoa 坐标）。
    var frame: CGRect
    /// 公开接口给的刘海主体（全局坐标）；nil 是没有刘海。
    var notch: CGRect?
    var isBuiltIn: Bool
    /// CGDisplayRotation，度。
    var rotation: Double = 0
    var mirrored: Bool = false
    /// 带 native 标志的显示模式的像素宽高（原生面板）；拿不到是 nil。
    var nativePixels: CGSize?
    /// 私有的 bezelPath（全局坐标）；没有这个方法、类型不对是 nil。
    var bezel: [OutlineStep]?
}

/// 一块屏的形状（pt，屏内坐标）。所有贴着硬件的表面只从这里拿形状。
struct DisplayShape: Equatable {
    /// 曲线是从哪来的。fallback 时所有表面的几何都和现版本一样。
    var source: DisplayShapeSource
    /// 原生面板像素宽 ÷ frame 宽。
    var pxPerPt: CGFloat?
    /// 刘海主体（公开接口给的，屏内坐标）；nil 是没有刘海。
    var notch: CGRect?
    /// bezelPath 里的刘海主体（屏内坐标，比公开的矩形每边宽 0.125、深 0.24 点）：只给诊断和亲眼校准用，排版不用它。
    var notchOutline: CGRect? = nil
    /// 刘海底角、肩；nil 是不知道（或没有刘海）：岛照现版本画，底角 10 / 12、不画肩。
    var notchCurves: NotchCurves?
    /// 屏幕顶角、底角（连续曲率角的 r）；0 是直角。
    var topCorner: CGFloat
    var bottomCorner: CGFloat
    /// 为什么是这个来源（记进诊断）。
    var note: String

    /// pxPerPt：只用原生面板像素宽 ÷ frame 宽；拿不到、或者算出来不像话时是 nil。
    static func pxPerPt(nativeWidth: CGFloat?, frameWidth: CGFloat) -> CGFloat? {
        guard let nativeWidth, nativeWidth > 0, frameWidth > 0 else { return nil }
        let k = nativeWidth / frameWidth
        return (0.5...4).contains(k) ? k : nil
    }

    static func resolve(_ input: DisplayShapeInput) -> DisplayShape {
        let k = pxPerPt(nativeWidth: input.nativePixels?.width, frameWidth: input.frame.width)
        let notch = input.notch.map { $0.offsetBy(dx: -input.frame.minX, dy: -input.frame.minY) }
        // 守卫 5：旋转过的屏按没有刘海、四角直角处理。镜像时拿不准，同样按直角（刘海仍由公开接口决定）。
        if input.rotation != 0 {
            return DisplayShape(source: .fallback, pxPerPt: k, notch: nil, notchCurves: nil, topCorner: 0, bottomCorner: 0,
                                note: "rotated \(input.rotation)°")
        }
        if input.mirrored {
            return DisplayShape(source: .fallback, pxPerPt: k, notch: notch, notchCurves: nil, topCorner: 0, bottomCorner: 0,
                                note: "mirrored")
        }
        var notes: [String] = []
        // ① bezelPath，过了校验才用。
        if let bezel = input.bezel {
            let check = BezelCheck.read(bezel, frame: input.frame, notch: notch)
            if let reading = check.reading {
                return DisplayShape(source: .bezel, pxPerPt: k, notch: notch, notchOutline: reading.notchBody,
                                    notchCurves: reading.notchCurves, topCorner: reading.topCorner, bottomCorner: reading.bottomCorner,
                                    note: "bezelPath fits within \(round2(max(reading.worstNotch, reading.worstCorner))) pt")
            }
            notes.append("bezelPath refused: \(check.problem ?? "?")")
        } else {
            notes.append("no bezelPath")
        }
        // ② 机型表：只给内建屏，按原生面板像素查。
        if input.isBuiltIn, let pixels = input.nativePixels, let k, let model = PanelTable.model(pixels: pixels) {
            var curves: NotchCurves?
            if notch != nil, let bottom = model.notchBottom, let shoulder = model.notchShoulder {
                curves = NotchCurves(bottomRadius: bottom / k, shoulderRadius: shoulder / k)
            }
            // 表里有刘海、公开接口却说没有：“避开刘海”模式，顶上一条熄灭了，可见区的角实际是直角（§3.5）。
            let avoiding = notch == nil && model.notchBottom != nil
            notes.append("table \(model.name)\(avoiding ? " (notch avoided)" : "")")
            return DisplayShape(source: .table, pxPerPt: k, notch: notch, notchCurves: curves,
                                topCorner: avoiding ? 0 : model.topCorner / k, bottomCorner: 0,
                                note: notes.joined(separator: "; "))
        }
        // ③ 现版本几何。
        notes.append(input.isBuiltIn ? "panel \(input.nativePixels.map { "\(Int($0.width))x\(Int($0.height))" } ?? "unknown") not in the table"
                                     : "external display")
        return DisplayShape(source: .fallback, pxPerPt: k, notch: notch, notchCurves: nil, topCorner: 0, bottomCorner: 0,
                            note: notes.joined(separator: "; "))
    }

    private static func round2(_ x: CGFloat) -> CGFloat { (x * 100).rounded() / 100 }
}

// MARK: - 刘海岛怎么贴合硬件（§5.1）

/// 岛贴着刘海的几条规则。curves 为 nil（不知道硬件形状）时一律等于现版本：底角 10 / 12、不画肩、飞行终点不变。
enum NotchIsland {
    /// 现版本写死的数：第一帧、下巴、悬停、下拉起步的底角 10，紧凑样式 12；下拉圆角上限 22。
    static let legacyHug: CGFloat = 10
    static let legacyCompact: CGFloat = 12
    static let pullCap: CGFloat = 22

    /// `island.hug`：贴着刘海时的底角，= 刘海自己的底角。
    static func hug(_ curves: NotchCurves?) -> CGFloat { curves?.bottomRadius ?? legacyHug }
    /// 紧凑样式两侧的底角：知道硬件时同样是刘海的底角（和刘海读起来是一件事）。
    static func compactRadius(_ curves: NotchCurves?) -> CGFloat { curves?.bottomRadius ?? legacyCompact }
    /// 无刘海胶囊圆角（S4）：优先机型顶角，否则高度一半（真胶囊）；不画肩。
    static func capsuleRadius(height: CGFloat, preferred: CGFloat?) -> CGFloat {
        let half = max(1, height / 2)
        guard let preferred, preferred > 0.5 else { return half }
        return min(preferred, half)
    }
    /// 两指下拉时的底角：从 hug 起，每拉 4 点大 1 点，最大 22。
    static func pullRadius(_ curves: NotchCurves?, extra: CGFloat) -> CGFloat { min(pullCap, hug(curves) + extra / 4) }

    /// S1：紧凑样式两侧。肩从 sideWidth 里扣，主体每侧宽 + 肩 ≤ sideWidth，不占新的菜单栏空位；
    /// 扣完不到 narrowest（图标加两边留白）就不画肩，形状和现版本一样。退回下巴的门槛不在这里，照旧看 sideWidth。
    static func compactSide(sideWidth: CGFloat, narrowest: CGFloat, curves: NotchCurves?) -> (body: CGFloat, shoulders: Bool) {
        guard let e = curves?.shoulderExtent, sideWidth - e >= narrowest else { return (sideWidth, false) }
        return (sideWidth - e, true)
    }

    /// S3：其它比刘海宽的状态，主体不变，肩在顶边往外长 e；肩的外沿要落在量到的空位以内，超了这一侧不画。
    /// offset：主体这一侧比刘海宽出多少（≤0 就是贴着刘海，肩和硬件的肩重合，不占菜单栏）。room：这一侧量到的空位，nil 是没量过。
    static func outwardShoulder(offset: CGFloat, room: CGFloat?, curves: NotchCurves?) -> Bool {
        guard let e = curves?.shoulderExtent else { return false }
        if offset <= 0.01 { return true }
        guard let room else { return false }
        return offset + e <= room + 0.001
    }

    /// 截图飞进刘海的终点：知道硬件时落在刘海正中、高不超过刘海（被摄像头那一块整个挡住）；不知道时照旧在刘海底上 2 点。
    static func tuckTarget(notch: CGRect, curves: NotchCurves?) -> CGRect {
        guard curves != nil else { return CGRect(x: notch.midX - 20, y: notch.minY + 2, width: 40, height: 26) }
        let height = min(26, notch.height)
        let width = 40 * height / 26
        return CGRect(x: notch.midX - width / 2, y: notch.midY - height / 2, width: width, height: height)
    }
}
