// 屏幕形状（Core/DisplayShape.swift）：连续曲率角、bezelPath 的校验、机型表与换算、岛贴合硬件的几条规则。
// 纯计算，不碰屏幕、不开窗口。只有“CALayer 和 SwiftUI 的 .continuous 是不是同一条”要在内存里画两张图比一比（§3.3）。
import AppKit
import QuartzCore
import SwiftUI

@main
struct DisplayShapeTests {
    static var failures = 0
    static func expect(_ condition: Bool, _ message: String) {
        if condition { print("ok   \(message)") } else { failures += 1; print("FAIL \(message)") }
    }
    static func near(_ a: CGFloat, _ b: CGFloat, _ tolerance: CGFloat) -> Bool { abs(a - b) <= tolerance }
    static func near(_ a: CGRect?, _ b: CGRect, _ tolerance: CGFloat) -> Bool {
        guard let a else { return false }
        return near(a.minX, b.minX, tolerance) && near(a.minY, b.minY, tolerance)
            && near(a.width, b.width, tolerance) && near(a.height, b.height, tolerance)
    }
    static func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

    /// 本机（Mac17,4，MacBook Air 15″ M5，macOS 27，1710×1107 模式）读到的 NSScreen.bezelPath，全局坐标，43 个元素，逐字照抄。
    static let air15: [OutlineStep] = [
        .move(p(0.0003648604987354972, 1068.397070220522)),
        .curve(p(0.04469541109509837, 1077.8877992883583), control1: p(0.0003648604987354972, 1069.3596300500612), control2: p(-0.007023564600658316, 1074.2980608069868)),
        .curve(p(0.5951330809999374, 1088.6459295904824), control1: p(0.10195570561540045, 1081.9634364936626), control2: p(0.23494735740448905, 1085.6381610636306)),
        .curve(p(2.4311567181993006, 1095.971360922772), control1: p(0.955318804595386, 1091.6555456409994), control2: p(1.5353101748978002, 1093.9538650804366)),
        .curve(p(5.920340471388029, 1101.0779163332254), control1: p(3.310379305027164, 1097.9556013391348), control2: p(4.496221533479872, 1099.6553231110659)),
        .curve(p(11.025742215069156, 1104.5697360603447), control1: p(7.344459409296187, 1102.5023570790502), control2: p(9.041950075881914, 1103.6884672720716)),
        .curve(p(18.351365701118123, 1106.4043270598308), control1: p(13.044629373478514, 1105.4639375142735), control2: p(15.340582473115141, 1106.044059945128)),
        .curve(p(29.105218433285813, 1106.9548891120435), control1: p(21.356607610296553, 1106.7645941745336), control2: p(25.030501990970127, 1106.897615878424)),
        .curve(p(38.593803367182325, 1106.9992296800067), control1: p(32.694145925316356, 1107.0066197746673), control2: p(37.63330810426112, 1106.9992296800067)),
        .line(p(755.2562611581834, 1106.9992296800067)),
        .curve(p(758.3206104681569, 1106.8514277867955), control1: p(756.4513389180104, 1106.9992296800067), control2: p(757.4487763064284, 1107.0195524403234)),
        .curve(p(760.8862410839215, 1105.5119731295672), control1: p(759.2663288808794, 1106.666675420281), control2: p(760.1492456802569, 1106.249135071959)),
        .curve(p(762.2253931331867, 1102.9439152350192), control1: p(761.6250835938607, 1104.7729636635102), control2: p(762.0425296119764, 1103.8916948752374)),
        .curve(p(762.3750087414494, 1099.8807209982133), control1: p(762.3953269104727, 1102.0737315887372), control2: p(762.3750087414494, 1101.0760688095604)),
        .line(p(762.3750087414494, 1088.8288344333316)),
        .curve(p(762.6908639144485, 1082.3366362740212), control1: p(762.3750087414494, 1086.2958794884214), control2: p(762.3325252971279, 1084.1823124154985)),
        .curve(p(765.5261720463409, 1076.8975266038422), control1: p(763.0787562321667, 1080.332073097342), control2: p(763.963520137819, 1078.4605316245525)),
        .curve(p(770.9659000257695, 1074.0597302541835), control1: p(767.0906710611375, 1075.3326740594666), control2: p(768.9599426112842, 1074.4495577475284)),
        .curve(p(777.4547843693122, 1073.7438037074442), control1: p(772.8111591943433, 1073.7013106631457), control2: p(774.9242487727697, 1073.7438037074442)),
        .line(p(932.5452156306877, 1073.7438037074442)),
        .curve(p(939.0340999742303, 1074.0597302541835), control1: p(935.0757512272301, 1073.7438037074442), control2: p(937.1906879119315, 1073.7013106631457)),
        .curve(p(944.4738279536589, 1076.8975266038422), control1: p(941.0400573887157, 1074.4495577475284), control2: p(942.9093289388622, 1075.3326740594666)),
        .curve(p(947.3109831918262, 1082.3366362740212), control1: p(946.0383269684555, 1078.4605316245525), control2: p(946.9212437678333, 1080.332073097342)),
        .curve(p(947.6249912585503, 1088.8288344333316), control1: p(947.6674747028717, 1084.1823124154985), control2: p(947.6249912585503, 1086.2958794884214)),
        .line(p(947.6249912585504, 1099.8807209982133)),
        .curve(p(947.7746068668132, 1102.9439152350192), control1: p(947.6249912585504, 1101.0760688095604), control2: p(947.6065201958019, 1102.0737315887372)),
        .curve(p(949.1137589160783, 1105.5119731295672), control1: p(947.9574703880232, 1103.8916948752374), control2: p(948.374916406139, 1104.7729636635102)),
        .curve(p(951.6812366381178, 1106.8514277867955), control1: p(949.8507543197428, 1106.249135071959), control2: p(950.7336711191203, 1106.666675420281)),
        .curve(p(954.7437388418165, 1106.9992296800067), control1: p(952.5512236935713, 1107.0195524403234), control2: p(953.5486610819894, 1106.9992296800067)),
        .line(p(1671.4061966328177, 1106.9992296800067)),
        .curve(p(1680.894781566714, 1106.9548891120435), control1: p(1672.3685390020134, 1106.9992296800067), control2: p(1677.3058540746836, 1107.0066197746673)),
        .curve(p(1691.6504814051564, 1106.4043270598308), control1: p(1684.9694980090296, 1106.897615878424), control2: p(1688.6433923897034, 1106.7645941745336)),
        .curve(p(1698.9742577849308, 1104.5697360603447), control1: p(1694.6594175268847, 1106.044059945128), control2: p(1696.9572177327962, 1105.4639375142735)),
        .curve(p(1704.0796595286117, 1101.0779163332254), control1: p(1700.9580499241179, 1103.6884672720716), control2: p(1702.6573876969787, 1102.5023570790502)),
        .curve(p(1707.5706903880753, 1095.971360922772), control1: p(1705.50377846652, 1099.6553231110659), control2: p(1706.6914678012474, 1097.9556013391348)),
        .curve(p(1709.404866919, 1088.6459295904824), control1: p(1708.4646898251021, 1093.9538650804366), control2: p(1709.0446811954043, 1091.6555456409994)),
        .curve(p(1709.955304588905, 1077.8877992883583), control1: p(1709.7650526425957, 1085.6381610636306), control2: p(1709.8980442943846, 1081.9634364936626)),
        .curve(p(1709.9996351395014, 1068.397070220522), control1: p(1710.0070235646008, 1074.2980608069868), control2: p(1709.9996351395014, 1069.3596300500612)),
        .line(p(1709.9996351395014, 2.2737367544323206e-13)),
        .line(p(0.0003648604987354972, 2.2737367544323206e-13)),
        .line(p(0.0003648604987354972, 1068.397070220522)),
        .close,
        .move(p(0.0003648604987354972, 1068.397070220522))
    ]
    static let air15Frame = CGRect(x: 0, y: 0, width: 1710, height: 1107)
    /// 同一时刻公开接口给的刘海：auxiliaryTopLeftArea.maxX 到 auxiliaryTopRightArea.minX，高 safeAreaInsets.top。
    static let air15Notch = CGRect(x: 762.5, y: 1073.5, width: 185, height: 33.5)
    /// 本机外接的 Studio Display：bezelPath 就是 frame（全局坐标在主屏左上方）。
    static let studioFrame = CGRect(x: -435, y: 1107, width: 2560, height: 1440)
    static let studio: [OutlineStep] = [
        .move(p(-435, 2547)), .line(p(2125, 2547)), .line(p(2125, 1107)), .line(p(-435, 1107)), .close, .move(p(-435, 2547)),
    ]

    static func main() {
        continuousCorner()
        thisMac()
        guards()
        table()
        notchless()
        island()
        if failures == 0 {
            print("PASS: display shape — the continuous corner is the system's (constants, expansion, CALayer = SwiftUI when drawn), this Mac's bezelPath reads as a notch with continuous bottom corners and shoulders that match the table, in global and shifted coordinates; each guard refuses a bad path and falls back to the table, then to today's geometry; the table keys on native panel pixels and converts with native width ÷ frame width; notchless screens (Neo, external, notch avoided, rotated, mirrored) have no notch curves; and the island rules keep today's geometry when the shape is unknown, keep the compact sides and the chin threshold, and only grow shoulders into measured room")
        } else {
            print("FAILED \(failures)")
            exit(1)
        }
    }

    // MARK: - 连续曲率角就是系统那一条

    static func continuousCorner() {
        // 常数和 SwiftUI 的 .continuous 路径逐项一致（尖角在原点那个角：从 (0, 1.5287r) 走到 (1.5287r, 0)）。
        let r: CGFloat = 10
        var steps: [(kind: String, points: [CGPoint])] = []
        RoundedRectangle(cornerRadius: r, style: .continuous).path(in: CGRect(x: 0, y: 0, width: 1000, height: 1000)).forEach { element in
            switch element {
            case .move(let a): steps.append(("move", [a]))
            case .line(let a): steps.append(("line", [a]))
            case .curve(let a, let c1, let c2): steps.append(("curve", [a, c1, c2]))
            case .quadCurve(let a, let c): steps.append(("quad", [a, c]))
            case .closeSubpath: steps.append(("close", []))
            }
        }
        let startIndex = steps.firstIndex { $0.kind == "line" && near($0.points[0].x, 0, 1e-6) && near($0.points[0].y, ContinuousCorner.extent * r, 1e-3) }
        var worst: CGFloat = .greatestFiniteMagnitude
        if let i = startIndex, i + 3 < steps.count {
            worst = 0
            for (k, segment) in ContinuousCorner.unit.enumerated() {
                let s = steps[i + 1 + k]
                guard s.kind == "curve" else { worst = .greatestFiniteMagnitude; break }
                let ours = [segment.to, segment.c1, segment.c2]
                for (a, b) in zip(s.points, ours) { worst = max(worst, abs(a.x / r - b.x), abs(a.y / r - b.y)) }
            }
        }
        expect(worst < 1e-5, "the corner's three curves are SwiftUI's .continuous ones (worst \(worst) of r)")
        let expansion = CALayer.cornerCurveExpansionFactor(.continuous)
        expect(near(expansion, ContinuousCorner.extent, 1e-5), "a continuous corner runs 1.5287 r along each edge, as CALayer says (\(expansion))")
        expect(near(ContinuousCorner.inset45, 0.29151, 0.0001), "and passes the 45° line 0.2915 r from the corner on each axis (\(ContinuousCorner.inset45))")

        // CALayer 的 .continuous 和 SwiftUI 的是同一条：画进同一种位图，逐行比覆盖的像素，差 ≤0.1 px（§7.1）。
        for radius in [CGFloat(8.52), 18.0, 34.1, 40.3, 100] {
            let size = Int(max(400, radius * 6))
            let rect = CGRect(x: 0, y: 0, width: size, height: size)
            let layer = CALayer()
            layer.frame = rect
            layer.backgroundColor = NSColor.black.cgColor
            layer.cornerRadius = radius
            layer.cornerCurve = .continuous
            let a = bitmap(size) { layer.render(in: $0) }
            let b = bitmap(size) {
                $0.addPath(RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: rect).cgPath)
                $0.fillPath()
            }
            // 我们自己的常数画出来也一样（肩就是拿这几段曲线画的）。
            let c = bitmap(size) { context in
                context.move(to: CGPoint(x: 0, y: CGFloat(size)))
                context.addLine(to: CGPoint(x: 0, y: ContinuousCorner.extent * radius))
                for segment in ContinuousCorner.unit {
                    context.addCurve(to: CGPoint(x: segment.to.x * radius, y: segment.to.y * radius),
                                     control1: CGPoint(x: segment.c1.x * radius, y: segment.c1.y * radius),
                                     control2: CGPoint(x: segment.c2.x * radius, y: segment.c2.y * radius))
                }
                context.addLine(to: CGPoint(x: CGFloat(size), y: 0))
                context.addLine(to: CGPoint(x: CGFloat(size), y: CGFloat(size)))
                context.closePath()
                context.fillPath()
            }
            let zone = Int((radius * 1.6).rounded(.up))
            let layerVsSwiftUI = rowDifference(a, b, zone: zone), oursVsSwiftUI = rowDifference(c, b, zone: zone)
            expect(layerVsSwiftUI <= 0.1 && oursVsSwiftUI <= 0.1,
                   "r \(radius) px: CALayer and SwiftUI draw the same corner (\(layerVsSwiftUI) px), and so do our constants (\(oursVsSwiftUI) px)")
        }

        // 左肩：从顶边 (−e, 0) 弯到竖边 (0, −e)，45° 上离尖角 0.2915 r；往岛里、往屏幕外各多画 overlap。
        let shoulder = ContinuousCorner.leftShoulder(radius: 5, overlap: 1)
        let points = Outline.points(shoulder).joined()
        let e = 5 * ContinuousCorner.extent
        let xs = points.map(\.x), ys = points.map(\.y)
        expect(near(xs.min()!, -e, 1e-6) && near(xs.max()!, 1, 1e-6) && near(ys.min()!, -e, 1e-6) && near(ys.max()!, 1, 1e-6),
               "a shoulder spans e = 1.5287 r along the top edge and down the side, plus the overlap (\(xs.min()!)…\(xs.max()!))")
        let onDiagonal = points.filter { abs($0.x - $0.y) < 0.02 && $0.x < 0 }.map(\.x).max() ?? 0
        expect(near(onDiagonal, -5 * ContinuousCorner.inset45, 0.02), "and its curve bows in toward the corner, 0.2915 r from it (\(onDiagonal))")
    }

    static func bitmap(_ size: Int, draw: (CGContext) -> Void) -> [UInt8] {
        let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.black.cgColor)
        draw(context)
        let data = context.data!.bindMemory(to: UInt8.self, capacity: size * size * 4)
        return (0..<(size * size)).map { data[$0 * 4 + 3] }
    }

    /// 两张图在原点那个角上，逐行覆盖的像素（按透明度加起来）最多差多少。
    static func rowDifference(_ a: [UInt8], _ b: [UInt8], zone: Int) -> CGFloat {
        let size = Int(Double(a.count).squareRoot())
        var worst: CGFloat = 0
        // 位图在内存里从最上一行存起：用户坐标 y = 0 那个角在最后几行。
        for row in (size - min(zone, size))..<size {
            var sa: CGFloat = 0, sb: CGFloat = 0
            for x in 0..<min(zone, size) {
                sa += CGFloat(a[row * size + x]) / 255
                sb += CGFloat(b[row * size + x]) / 255
            }
            worst = max(worst, abs(sa - sb))
        }
        return worst
    }

    // MARK: - 本机的 bezelPath

    static func thisMac() {
        let check = BezelCheck.read(air15, frame: air15Frame, notch: air15Notch)
        let reading = check.reading
        expect(reading != nil, "this Mac's bezelPath passes every guard (\(check.problem ?? "ok"))")
        guard let reading, let curves = reading.notchCurves else { return }
        // 竖边在 762.375、947.625，底边 1073.744：比公开的矩形每边宽 0.125、深 0.24（§3.1）。
        expect(near(reading.notchBody, CGRect(x: 762.375, y: 1073.744, width: 185.25, height: 33.256), 0.01),
               "it finds the notch by its shape: sides at 762.375 and 947.625, bottom at 1073.744 (\(reading.notchBody.map { "\($0)" } ?? "-"))")
        let k: CGFloat = 2880.0 / 1710
        expect(near(curves.bottomRadius, 10.71, 0.05), "the notch's bottom corners are continuous with r 10.71 pt (\(curves.bottomRadius))")
        expect(near(curves.shoulderRadius, 5.06, 0.05), "its shoulders are continuous with r 5.06 pt (\(curves.shoulderRadius))")
        expect(reading.worstNotch * k <= 0.3, "all four notch curves sit within 0.3 panel px of that corner (\(reading.worstNotch * k) px)")
        // 顶角比连续曲率角更方（§3.1），拟合出的 r 比图稿的 20.25 点大一点；最远偏 0.17 点 = 0.29 面板像素。
        expect(near(reading.topCorner, 20.7, 0.3) && reading.worstCorner * k <= 0.5,
               "the screen's top corners fit a continuous r of about 20.7 pt, within 0.5 panel px (\(reading.topCorner), off by at most \(reading.worstCorner * k) px)")
        expect(reading.bottomCorner == 0, "and its bottom corners are square (\(reading.bottomCorner))")

        // 表是按这台机器的 bezelPath 定的：两者差不到 0.1 pt。
        let air = PanelTable.model(pixels: CGSize(width: 2880, height: 1864))!
        expect(near(air.notchBottom! / k, curves.bottomRadius, 0.1) && near(air.notchShoulder! / k, curves.shoulderRadius, 0.1),
               "the table agrees with it (bottom \(air.notchBottom! / k), shoulder \(air.notchShoulder! / k))")

        let input = DisplayShapeInput(frame: air15Frame, notch: air15Notch, isBuiltIn: true,
                                      nativePixels: CGSize(width: 2880, height: 1864), bezel: air15)
        let shape = DisplayShape.resolve(input)
        expect(shape.source == .bezel && shape.notchCurves == curves && near(shape.pxPerPt ?? 0, 1.6842, 0.0001),
               "so the shape comes from bezelPath, with pxPerPt 2880 ÷ 1710 = 1.684, not the backing scale 2 (\(shape.source), \(shape.pxPerPt ?? 0))")
        expect(shape.notch == air15Notch, "and the notch's place and size still come from the public rect (\(shape.notch.map { "\($0)" } ?? "-"))")

        // 全局坐标：屏不在原点时（外接屏设为主屏），换成屏内坐标后量出来一样。
        let dx: CGFloat = 1000, dy: CGFloat = -500
        let moved = air15.map { shift($0, dx, dy) }
        let movedShape = DisplayShape.resolve(DisplayShapeInput(
            frame: air15Frame.offsetBy(dx: dx, dy: dy), notch: air15Notch.offsetBy(dx: dx, dy: dy), isBuiltIn: true,
            nativePixels: CGSize(width: 2880, height: 1864), bezel: moved))
        let movedCurves = movedShape.notchCurves
        expect(movedShape.source == .bezel && movedShape.notch == air15Notch
               && near(movedCurves?.bottomRadius ?? 0, curves.bottomRadius, 0.001) && near(movedCurves?.shoulderRadius ?? 0, curves.shoulderRadius, 0.001),
               "with the built-in screen away from the origin, the path is read in its own coordinates and gives the same shape (\(movedShape.note), \(movedCurves.map { "\($0)" } ?? "-"))")

        // 外接的 Studio Display：路径就是 frame，四个直角，没有刘海。
        let studioShape = DisplayShape.resolve(DisplayShapeInput(frame: studioFrame, notch: nil, isBuiltIn: false,
                                                                 nativePixels: CGSize(width: 5120, height: 2880), bezel: studio))
        expect(studioShape.source == .bezel && studioShape.notch == nil && studioShape.notchCurves == nil
               && studioShape.topCorner == 0 && studioShape.bottomCorner == 0,
               "an external Studio Display (at −435, 1107) is square with no notch (\(studioShape.note))")
    }

    static func shift(_ step: OutlineStep, _ dx: CGFloat, _ dy: CGFloat) -> OutlineStep {
        func m(_ q: CGPoint) -> CGPoint { CGPoint(x: q.x + dx, y: q.y + dy) }
        switch step {
        case .move(let a): return .move(m(a))
        case .line(let a): return .line(m(a))
        case .quad(let a, let c): return .quad(m(a), control: m(c))
        case .curve(let a, let c1, let c2): return .curve(m(a), control1: m(c1), control2: m(c2))
        case .close: return .close
        }
    }

    // MARK: - 守卫：任何一条不满足就退到机型表

    static func guards() {
        let native = CGSize(width: 2880, height: 1864)
        func resolve(_ bezel: [OutlineStep]?, frame: CGRect = air15Frame, notch: CGRect? = air15Notch,
                     rotation: Double = 0, mirrored: Bool = false) -> DisplayShape {
            DisplayShape.resolve(DisplayShapeInput(frame: frame, notch: notch, isBuiltIn: true, rotation: rotation,
                                                   mirrored: mirrored, nativePixels: native, bezel: bezel))
        }
        let table = resolve(nil)
        expect(table.source == .table && near(table.notchCurves?.bottomRadius ?? 0, 18.0 / (2880.0 / 1710), 0.001),
               "without bezelPath (macOS 14 / 15), the curves come from the table (\(table.note))")

        // 守卫 2：外框和 frame 差 1 点。
        let off = resolve(air15, frame: air15Frame.offsetBy(dx: 1, dy: 0), notch: air15Notch.offsetBy(dx: 1, dy: 0))
        expect(off.source == .table && off.note.contains("bounds"), "a path 1 pt off the frame is refused (\(off.note))")

        // 守卫 3：公开接口说有刘海，路径里没有。
        let plain: [OutlineStep] = [.move(p(0, 1107)), .line(p(1710, 1107)), .line(p(1710, 0)), .line(p(0, 0)), .close]
        let noNotch = resolve(plain)
        expect(noNotch.source == .table && noNotch.note.contains("no notch"), "a path without the notch the public API reports is refused (\(noNotch.note))")

        // 守卫 3：竖边和公开矩形差 2 点。
        let wide = resolve(air15, notch: air15Notch.insetBy(dx: -2, dy: 0))
        expect(wide.source == .table && wide.note.contains("sides off"), "a notch whose sides are 2 pt off the public rect is refused (\(wide.note))")

        // 守卫 4：公开接口说没有刘海（“避开刘海”模式的样子），路径里却有缺口。
        let gap = resolve(air15, notch: nil)
        expect(gap.source == .table && gap.note.contains("gap") && gap.notchCurves == nil && gap.topCorner == 0,
               "a gap in the path of a screen the public API calls notchless is refused; the notch-avoiding mode gets square corners (\(gap.note))")

        // 曲线不是我们认识的样子：左肩换成一刀斜切。
        var chamfer = air15
        if let first = chamfer.firstIndex(where: { if case .line(let a) = $0 { return near(a.x, 755.256, 0.01) } else { return false } }) {
            // 肩的四段曲线（755.26, 1107）→（762.375, 1099.88）换成一条直线。
            chamfer.replaceSubrange((first + 1)...(first + 4), with: [.line(p(762.3750087414494, 1099.8807209982133))])
        }
        let cut = resolve(chamfer)
        expect(cut.source == .table && cut.note.contains("not continuous"), "a shoulder cut straight instead of curved is refused (\(cut.note))")

        // 守卫 5：旋转过的屏；镜像时拿不准。
        let turned = resolve(air15, rotation: 90)
        expect(turned.source == .fallback && turned.notch == nil && turned.notchCurves == nil && turned.topCorner == 0,
               "a rotated screen has no notch and square corners (\(turned.note))")
        let mirrored = resolve(air15, mirrored: true)
        expect(mirrored.source == .fallback && mirrored.notchCurves == nil && mirrored.topCorner == 0 && mirrored.notch == air15Notch,
               "a mirrored screen keeps the public notch but draws no curves (\(mirrored.note))")

        // 表里也没有：现版本几何。
        let unknown = DisplayShape.resolve(DisplayShapeInput(frame: air15Frame, notch: air15Notch, isBuiltIn: true,
                                                             nativePixels: CGSize(width: 3200, height: 2000), bezel: nil))
        expect(unknown.source == .fallback && unknown.notchCurves == nil && unknown.notch == air15Notch,
               "a notched panel the table does not know falls back to today's geometry (\(unknown.note))")
        let noMode = DisplayShape.resolve(DisplayShapeInput(frame: air15Frame, notch: air15Notch, isBuiltIn: true, nativePixels: nil, bezel: nil))
        expect(noMode.source == .fallback && noMode.pxPerPt == nil, "without the native display mode there is no pxPerPt and no table")
    }

    // MARK: - 机型表与换算

    static func table() {
        let keys: [(CGFloat, CGFloat, String)] = [(2408, 1506, "Neo"), (2560, 1664, "Air 13"), (2880, 1864, "Air 15"),
                                                  (3024, 1964, "Pro 14"), (3456, 2234, "Pro 16")]
        for (w, h, name) in keys {
            let model = PanelTable.model(pixels: CGSize(width: w, height: h))
            expect(model != nil && model!.name.contains(name.components(separatedBy: " ")[0]),
                   "\(Int(w))×\(Int(h)) px finds the \(name) row (\(model?.name ?? "-"))")
        }
        expect(Set(PanelTable.models.map { "\($0.pixels)" }).count == PanelTable.models.count, "the five keys are all different")
        expect(PanelTable.model(pixels: CGSize(width: 1920, height: 1080)) == nil && PanelTable.model(pixels: CGSize(width: 2880, height: 1800)) == nil,
               "an unknown panel is not in the table")
        expect(PanelTable.models.allSatisfy { ($0.notchBottom == nil) == ($0.notchShoulder == nil) }, "every row has both notch curves or neither")

        // pxPerPt = 原生面板像素宽 ÷ frame 宽，不是 backingScaleFactor。
        expect(near(DisplayShape.pxPerPt(nativeWidth: 2880, frameWidth: 1710)!, 1.6842, 0.0001), "1710 wide on a 2880 px panel is 1.684 px per pt, not 2")
        expect(DisplayShape.pxPerPt(nativeWidth: 2880, frameWidth: 1440) == 2, "1440 wide is exactly 2")
        expect(DisplayShape.pxPerPt(nativeWidth: nil, frameWidth: 1440) == nil && DisplayShape.pxPerPt(nativeWidth: 2880, frameWidth: 0) == nil,
               "no native width or no frame: no pxPerPt")

        // 换算：Air 15 在 1710 和 1440 两个模式下，Pro 14 在默认的 1512。
        func shape(_ px: CGSize, _ frame: CGSize, notch: Bool = true) -> DisplayShape {
            let f = CGRect(origin: .zero, size: frame)
            let n = notch ? CGRect(x: frame.width / 2 - 90, y: frame.height - 32, width: 180, height: 32) : nil
            return DisplayShape.resolve(DisplayShapeInput(frame: f, notch: n, isBuiltIn: true, nativePixels: px, bezel: nil))
        }
        let air1710 = shape(CGSize(width: 2880, height: 1864), CGSize(width: 1710, height: 1107))
        expect(near(air1710.notchCurves!.bottomRadius, 10.69, 0.01) && near(air1710.notchCurves!.shoulderRadius, 5.05, 0.01)
               && near(air1710.topCorner, 20.25, 0.01),
               "Air 15 at 1710×1107: bottom 10.69, shoulder 5.05, screen top 20.25 pt")
        let air1440 = shape(CGSize(width: 2880, height: 1864), CGSize(width: 1440, height: 932))
        expect(near(air1440.notchCurves!.bottomRadius, 9.0, 0.001) && near(air1440.notchCurves!.shoulderRadius, 4.25, 0.001)
               && near(air1440.topCorner, 17.05, 0.001),
               "at 1440×932 (2×): bottom 9.0, shoulder 4.25, screen top 17.05 pt")
        let pro = shape(CGSize(width: 3024, height: 1964), CGSize(width: 1512, height: 982))
        expect(near(pro.notchCurves!.bottomRadius, 10.3, 0.001) && near(pro.notchCurves!.shoulderRadius, 4.9, 0.001)
               && near(pro.topCorner, 19.85, 0.001),
               "Pro 14 at 1512×982: bottom 10.3, shoulder 4.9, screen top 19.85 pt")
        let external = DisplayShape.resolve(DisplayShapeInput(frame: CGRect(x: 0, y: 0, width: 1728, height: 1117), notch: nil,
                                                              isBuiltIn: false, nativePixels: CGSize(width: 3456, height: 2234), bezel: nil))
        expect(external.source == .fallback && external.topCorner == 0,
               "the table is only for built-in screens: an external panel of the same size stays square (\(external.note))")
    }

    // MARK: - 没有刘海的屏

    static func notchless() {
        // MacBook Neo（Mac17,5）：天圆地方，没有刘海。
        let neo = DisplayShape.resolve(DisplayShapeInput(frame: CGRect(x: 0, y: 0, width: 1408, height: 881), notch: nil, isBuiltIn: true,
                                                         nativePixels: CGSize(width: 2408, height: 1506), bezel: nil))
        expect(neo.source == .table && neo.notch == nil && neo.notchCurves == nil && near(neo.topCorner, 33.6 / (2408.0 / 1408), 0.001)
               && neo.bottomCorner == 0,
               "MacBook Neo (Mac17,5): rounded top corners (\(neo.topCorner) pt), square bottom, no notch")
        let neo2x = DisplayShape.resolve(DisplayShapeInput(frame: CGRect(x: 0, y: 0, width: 1204, height: 753), notch: nil, isBuiltIn: true,
                                                           nativePixels: CGSize(width: 2408, height: 1506), bezel: nil))
        expect(near(neo2x.topCorner, 16.8, 0.001), "and 16.8 pt at 1204×753")
        // 公开接口说 Neo 有刘海（不该发生）：刘海照公开接口，表里没有它的曲线，岛按现版本画。
        let odd = DisplayShape.resolve(DisplayShapeInput(frame: CGRect(x: 0, y: 0, width: 1408, height: 881),
                                                         notch: CGRect(x: 614, y: 849, width: 180, height: 32), isBuiltIn: true,
                                                         nativePixels: CGSize(width: 2408, height: 1506), bezel: nil))
        expect(odd.notch != nil && odd.notchCurves == nil, "if the public API ever reports a notch on a Neo, it is kept but drawn with today's corners")

        // Neo 的 bezelPath 如果长这样（顶上两个连续曲率角、底下直角、没有缺口）：读出来的角和画进去的一样。
        let frame = CGRect(x: 0, y: 0, width: 1408, height: 881)
        let r = neo.topCorner
        var steps: [OutlineStep] = [.move(p(0, 0)), .line(p(0, 881 - ContinuousCorner.extent * r))]
        // 单位角从 (0, e) 走到 (e, 0)：映射成从 V + e·w 走到 V + e·u。左上角 u = +x、w = −y；右上角 u = −y、w = −x。
        func corner(_ v: CGPoint, _ u: CGVector, _ w: CGVector) -> [OutlineStep] {
            func m(_ q: CGPoint) -> CGPoint { CGPoint(x: v.x + (q.x * u.dx + q.y * w.dx) * r, y: v.y + (q.x * u.dy + q.y * w.dy) * r) }
            return ContinuousCorner.unit.map { .curve(m($0.to), control1: m($0.c1), control2: m($0.c2)) }
        }
        steps += corner(p(0, 881), CGVector(dx: 1, dy: 0), CGVector(dx: 0, dy: -1))
        steps += [.line(p(1408 - ContinuousCorner.extent * r, 881))]
        steps += corner(p(1408, 881), CGVector(dx: 0, dy: -1), CGVector(dx: -1, dy: 0))
        steps += [.line(p(1408, 0)), .close]
        let neoBezel = DisplayShape.resolve(DisplayShapeInput(frame: frame, notch: nil, isBuiltIn: true,
                                                              nativePixels: CGSize(width: 2408, height: 1506), bezel: steps))
        expect(neoBezel.source == .bezel && near(neoBezel.topCorner, r, 0.02) && neoBezel.bottomCorner == 0 && neoBezel.notchCurves == nil,
               "a Neo-like bezelPath reads back as r \(neoBezel.topCorner) pt on top, square below (\(neoBezel.note))")

        // 外接屏：不是内建屏、没有 bezelPath，四角直角。
        let external = DisplayShape.resolve(DisplayShapeInput(frame: studioFrame, notch: nil, isBuiltIn: false,
                                                              nativePixels: CGSize(width: 5120, height: 2880), bezel: nil))
        expect(external.source == .fallback && external.topCorner == 0 && external.bottomCorner == 0 && external.notchCurves == nil,
               "an external display without bezelPath is square (\(external.note))")
        // “避开刘海”模式：公开接口说没有刘海，面板还是 Air 15 那块。
        let avoided = DisplayShape.resolve(DisplayShapeInput(frame: CGRect(x: 0, y: 0, width: 1710, height: 1068), notch: nil, isBuiltIn: true,
                                                             nativePixels: CGSize(width: 2880, height: 1864), bezel: nil))
        expect(avoided.source == .table && avoided.notchCurves == nil && avoided.topCorner == 0,
               "the notch-avoiding mode (1710×1068) has no notch and square visible corners (\(avoided.note))")
    }

    // MARK: - 岛贴合硬件的规则（§5.1）

    static func island() {
        // 不知道硬件形状：一律等于现版本。
        expect(NotchIsland.hug(nil) == 10 && NotchIsland.compactRadius(nil) == 12, "unknown shape: first frame, chin, hover 10; compact 12, as today")
        expect(NotchIsland.capsuleRadius(height: 12, preferred: nil) == 6
               && NotchIsland.capsuleRadius(height: 24, preferred: 33.6) == 12
               && NotchIsland.capsuleRadius(height: 80, preferred: 33.6) == 33.6,
               "capsule: half-height when no preferred; never exceed half; prefer machine topCorner when smaller")
        var samePull = true
        for extra in stride(from: CGFloat(0), through: 120, by: 0.5) where NotchIsland.pullRadius(nil, extra: extra) != min(22, 10 + extra / 4) {
            samePull = false
        }
        expect(samePull, "unknown shape: the pull radius is still min(22, 10 + pull / 4) at every distance")
        var sameSides = true
        for side in stride(from: CGFloat(0), through: 40, by: 0.25) where NotchIsland.compactSide(sideWidth: side, narrowest: 26, curves: nil) != (side, false) {
            sameSides = false
        }
        expect(sameSides && !NotchIsland.outwardShoulder(offset: 0, room: 34, curves: nil),
               "unknown shape: the compact sides are as wide as today and no shoulder is ever drawn")
        expect(NotchIsland.tuckTarget(notch: air15Notch, curves: nil) == CGRect(x: 835, y: 1075.5, width: 40, height: 26),
               "unknown shape: a tucked window still flies to 40×26, 2 pt above the notch's bottom")

        // 本机 1710 模式：底角 10.71、肩 5.06（e = 7.73）。
        let air = NotchCurves(bottomRadius: 10.71, shoulderRadius: 5.06)
        let e = air.shoulderExtent
        expect(near(e, 7.735, 0.001), "a 5.06 pt shoulder runs 7.73 pt along each edge (\(e))")
        expect(NotchIsland.hug(air) == 10.71 && NotchIsland.compactRadius(air) == 10.71 && NotchIsland.pullRadius(air, extra: 0) == 10.71
               && NotchIsland.pullRadius(air, extra: 200) == 22,
               "known shape: the island hugs the notch with its own 10.71 pt corners, and a pull still stops at 22")

        // S1：空位从 0 扫到 40 点。紧凑样式的外沿不超过现版本；画肩时主体每侧不少于 26；退回下巴的门槛不变（这里不改 sideWidth）。
        var outerOK = true, minimumOK = true
        var withShoulders: [CGFloat] = []
        for room in stride(from: CGFloat(0), through: 40, by: 0.25) {
            let side = min(34, room.rounded(.down))
            let fit = NotchIsland.compactSide(sideWidth: side, narrowest: 26, curves: air)
            if fit.body + (fit.shoulders ? e : 0) > side + 1e-9 { outerOK = false }
            if fit.shoulders && fit.body < 26 { minimumOK = false }
            if !fit.shoulders && fit.body != side { minimumOK = false }
            if fit.shoulders { withShoulders.append(side) }
        }
        expect(outerOK, "S1: body + shoulder never reaches past today's compact sides, for any room from 0 to 40 pt")
        expect(minimumOK, "S1: with a shoulder the body keeps at least 26 pt a side; without one it is exactly today's")
        expect(Set(withShoulders) == [34], "S1: at 1710 only the full 34 pt sides make room for a shoulder (body \(34 - e))")
        let air2x = NotchCurves(bottomRadius: 9.0, shoulderRadius: 4.25)
        expect(NotchIsland.compactSide(sideWidth: 33, narrowest: 26, curves: air2x).shoulders
               && !NotchIsland.compactSide(sideWidth: 32, narrowest: 26, curves: air2x).shoulders,
               "S1: at 1440 (shoulder e 6.50) 33 pt sides have room for one and 32 do not")

        // S3：比刘海宽的其它状态，肩往外长 e，外沿要在量到的空位以内。
        expect(NotchIsland.outwardShoulder(offset: 0, room: nil, curves: air), "S3: at the notch's own width the shoulder sits on the hardware one and needs no room")
        expect(NotchIsland.outwardShoulder(offset: 5, room: 34, curves: air) && !NotchIsland.outwardShoulder(offset: 5, room: 12, curves: air)
               && NotchIsland.outwardShoulder(offset: 5, room: 13, curves: air),
               "S3: hovering (+5) grows a shoulder only where 5 + 7.73 pt of menu bar is free")
        expect(NotchIsland.outwardShoulder(offset: 20, room: 34, curves: air) && !NotchIsland.outwardShoulder(offset: 5, room: nil, curves: air),
               "S3: a full pull (+20) fits in 34 pt; with no measurement there is no shoulder")
        // 紧凑样式上悬停不走 S3（外沿 34 + 5 + e 超出量过的 34 点）：Notch.swift 让它沿用 S1，主体 +5、肩的外沿 = 现版本悬停的 39 点。
        expect(!NotchIsland.outwardShoulder(offset: 39, room: 34, curves: air),
               "S3: an outward shoulder beyond the compact sides plus 5 (39) would reach past the measured 34 pt, so hovering there keeps the S1 shape instead")

        // 截图飞进刘海：落在刘海正中，高不超过刘海。
        let target = NotchIsland.tuckTarget(notch: air15Notch, curves: air)
        expect(near(target.midX, air15Notch.midX, 1e-9) && near(target.midY, air15Notch.midY, 1e-9) && target.height <= air15Notch.height
               && air15Notch.contains(target),
               "known shape: a tucked window flies into the middle of the notch, no taller than it (\(target))")
        let shallow = CGRect(x: 0, y: 0, width: 150, height: 20)
        expect(NotchIsland.tuckTarget(notch: shallow, curves: air).height == 20, "and shrinks to fit a shallower notch")
    }
}
