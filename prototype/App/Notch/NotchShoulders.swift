// // 刘海的两个肩：比刘海面板低一层的窄条窗口，形状随岛同参数弹簧长出/缩回。

import Cocoa
import ApplicationServices

/// 刘海的两个肩（设计系统 §5.1）：刘海竖边和屏幕顶边相接处，显示区那个往外弯的凸角。硬件上被切掉的那一小块是边框，
/// 没有像素；岛比刘海宽时，照着它在岛的两个上角各画一小块黑的，看起来是刘海自己长宽了，而不是贴了一块直角的黑片。
///
/// - 单独一层窗口，不接指针（S2）：肩底下的菜单栏照常能点，刘海面板的命中范围也不因肩变大。
///   窗口盖着这块屏最上面一窄条（和肩一样高），比刘海面板低一层、比菜单栏高一层。
/// - 肩的形状固定（硬件那一条连续曲率角），尖角钉在岛的上角：位置和大小（从尖角缩放）各挂一段和岛同参数、
///   同一个 transaction 的叠加弹簧，宽度变、半路打断都贴着岛走。状态变了就跟着同一条弹簧缩到 0 或长出来；
///   只是量到的空位变了就淡入淡出（S5）。
/// - 肩不描边：岛的细边在竖边上就到头了，不会拐到屏幕顶边上留一条亮线。
@MainActor
final class NotchShoulders: NSPanel {
    /// 探针用：窗口外框、接不接指针、两个肩的尖角（屏幕坐标，模型值）和大小、肩沿每条边多长、是不是正在长出或缩回。
    struct Probe {
        var frame: NSRect
        var ignoresMouse: Bool
        var leading: (corner: NSPoint, scale: CGFloat)
        var trailing: (corner: NSPoint, scale: CGFloat)
        var extent: CGFloat
        var resizing: Bool
    }

    /// 往岛里、往屏幕外各多画 1 点：和岛之间不留抗锯齿的缝（多出来的被岛盖着、被窗口裁掉）。
    private static let overlap: CGFloat = 1
    private let leading = CAShapeLayer()
    private let trailing = CAShapeLayer()
    private var radius: CGFloat = 0
    private var placed = false
    /// 两个肩现在的目标大小（模型值，动画的终点）。
    private(set) var scales: (leading: CGFloat, trailing: CGFloat) = (0, 0)

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 1, height: 1), styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 2)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        hidesOnDeactivate = false
        animationBehavior = .none
        // 只是岛的一部分外形，没有内容：VoiceOver 不把它当成一扇窗。
        setAccessibilityElement(false)
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
        host.wantsLayer = true
        contentView = host
        for layer in [leading, trailing] {
            layer.fillColor = NSColor.black.cgColor
            layer.transform = CATransform3DMakeScale(0, 0, 1)
            host.layer?.addSublayer(layer)
        }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// 盖住这块屏最上面一窄条；radius：硬件肩的连续曲率角半径（点）。
    func fit(screen: NSRect, top: CGFloat, radius: CGFloat) {
        let e = radius * ContinuousCorner.extent
        let height = ceil(e + 2)
        let frame = NSRect(x: screen.minX, y: top - height, width: screen.width, height: height)
        if self.frame != frame {
            setFrame(frame, display: false)
            // 肩的位置按窗口里的坐标记：窗口挪了，下一次直接放到位。
            placed = false
        }
        guard radius != self.radius else { return }
        self.radius = radius
        let o = Self.overlap
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (layer, sign) in [(leading, CGFloat(1)), (trailing, CGFloat(-1))] {
            // 左肩原样，右肩把 x 取反；图层的尖角（路径的原点）就是锚点，缩放从尖角开始。
            func m(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * sign, y: p.y) }
            let path = CGMutablePath()
            for step in ContinuousCorner.leftShoulder(radius: radius, overlap: o) {
                switch step {
                case .move(let p): path.move(to: m(p))
                case .line(let p): path.addLine(to: m(p))
                case .quad(let p, let c): path.addQuadCurve(to: m(p), control: m(c))
                case .curve(let p, let c1, let c2): path.addCurve(to: m(p), control1: m(c1), control2: m(c2))
                case .close: path.closeSubpath()
                }
            }
            layer.path = path
            let box = sign > 0 ? CGRect(x: -e, y: -e, width: e + o, height: e + o) : CGRect(x: -o, y: -e, width: e + o, height: e + o)
            layer.bounds = box
            layer.anchorPoint = CGPoint(x: -box.minX / box.width, y: -box.minY / box.height)
        }
        CATransaction.commit()
    }

    /// 两个肩的尖角挪到岛的两个上角（屏幕坐标），各长出 scale（0…1）。调用方在岛的 transaction 里调用。
    /// snap：这一侧的肩本来就看不出来（和硬件的肩重合、岛没画），要收掉就直接收掉，不先亮出来再缩。
    func place(leading a: NSPoint, trailing b: NSPoint, scale: (leading: CGFloat, trailing: CGFloat),
               snap: (leading: Bool, trailing: Bool) = (false, false), spring: NotchCanvasView.Spring?, fade: Bool) {
        let origin = frame.origin
        let first = !placed
        placed = true
        move(leading, to: NSPoint(x: a.x - origin.x, y: a.y - origin.y), from: scales.leading, to: scale.leading,
             snap: snap.leading, spring: spring, first: first, fade: fade)
        move(trailing, to: NSPoint(x: b.x - origin.x, y: b.y - origin.y), from: scales.trailing, to: scale.trailing,
             snap: snap.trailing, spring: spring, first: first, fade: fade)
        scales = scale
    }

    /// 岛停稳了：肩换成目标大小，不动画（只有终点和硬件的肩重合、一路没长的那一侧会变，看不出来）。
    func settle(_ scale: (leading: CGFloat, trailing: CGFloat)) {
        guard scale != scales else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        leading.transform = CATransform3DMakeScale(scale.leading, scale.leading, 1)
        trailing.transform = CATransform3DMakeScale(scale.trailing, scale.trailing, 1)
        CATransaction.commit()
        scales = scale
    }

    private func move(_ layer: CAShapeLayer, to point: NSPoint, from old: CGFloat, to new: CGFloat, snap: Bool,
                      spring: NotchCanvasView.Spring?, first: Bool, fade: Bool) {
        let presented = layer.presentation()?.position ?? layer.position
        for key in layer.animationKeys() ?? [] where key.hasPrefix("shoulder") {
            layer.removeAnimation(forKey: key)
        }
        layer.position = point
        layer.transform = CATransform3DMakeScale(new, new, 1)
        guard !first else { return }
        if snap {
            for name in layer.animationKeys() ?? [] where name.hasSuffix(".transform.scale") { layer.removeAnimation(forKey: name) }
        }
        let key = "shoulder"
        guard let spring else {
            // 跟手的时候（岛没有弹簧、立刻到位）：位置跟着到；肩长出、收掉仍走一段不回弹的弹簧，不在一帧里跳没。
            // 减少动态效果：肩和岛一起直接到位，不留一段缩放动画。
            if old != new, !snap, !Motion.reduced {
                animate(layer, "transform.scale", from: old - new, zero: 0,
                        spring: NotchCanvasView.Spring(response: Motion.Spring.calm.response,
                                                       bounce: Motion.Spring.calm.bounce), key: key)
            }
            return
        }
        if presented != point {
            animate(layer, "position", from: NSValue(point: NSPoint(x: presented.x - point.x, y: presented.y - point.y)),
                    zero: NSValue(point: .zero), spring: spring, key: key)
        }
        if snap { return }
        if fade, old == 0, new > 0 {
            // 只是空位变了才长出来的：在终点淡入，不从 0 长（时长走 `calm` / `reducedNotch`）。
            let appear = CABasicAnimation(keyPath: "opacity")
            appear.fromValue = 0
            appear.toValue = 1
            appear.duration = Motion.fadeDuration
            layer.add(appear, forKey: "\(key).fade")
            return
        }
        if old != new { animate(layer, "transform.scale", from: old - new, zero: 0, spring: spring, key: key) }
        if fade, old > 0, new == 0 {
            // 只是空位变了才收掉的：一边跟着缩，一边在 0.1 秒里淡掉。
            let settle = CASpringAnimation(perceptualDuration: spring.response, bounce: spring.bounce).settlingDuration
            let vanish = CAKeyframeAnimation(keyPath: "opacity")
            vanish.values = [1, 0, 0]
            vanish.keyTimes = [0, NSNumber(value: min(1, 0.1 / max(settle, 0.1))), 1]
            vanish.duration = settle
            layer.add(vanish, forKey: "\(key).fade")
        }
    }

    /// 和岛一样的叠加弹簧：模型值已经是终点，动画从“旧值减新值”回到 0。
    private func animate(_ layer: CALayer, _ keyPath: String, from: Any, zero: Any, spring: NotchCanvasView.Spring, key: String) {
        let animation = CASpringAnimation(perceptualDuration: spring.response, bounce: spring.bounce)
        animation.keyPath = keyPath
        animation.isAdditive = true
        animation.fromValue = from
        animation.toValue = zero
        animation.initialVelocity = spring.initialVelocity
        animation.duration = animation.settlingDuration
        layer.add(animation, forKey: "\(key).\(keyPath)")
    }

    /// 平时（岛不画的时候）肩也不画。
    func setBare(_ bare: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        leading.opacity = bare ? 0 : 1
        trailing.opacity = bare ? 0 : 1
        CATransaction.commit()
    }

    /// 岛鼓一下时，两条竖边各往外挪这一帧宽度的一半。samples 是弹簧解，点与点之间线性插值。
    func pulse(widthSamples: [Double], keyTimes: [NSNumber], duration: CFTimeInterval) {
        for (layer, sign) in [(leading, -1.0), (trailing, 1.0)] {
            let move = CAKeyframeAnimation(keyPath: "position.x")
            move.isAdditive = true
            move.calculationMode = .linear
            move.values = widthSamples.map { NSNumber(value: sign * $0 / 2) }
            move.keyTimes = keyTimes
            move.duration = duration
            layer.add(move, forKey: "pulse.x")
        }
    }

    /// 探针用：两个肩的尖角（模型值）正好在 leading、trailing 上，窗口顶边贴着它们，不接指针。
    func attached(leading a: NSPoint, trailing b: NSPoint) -> Bool {
        let o = frame.origin
        func at(_ layer: CALayer, _ p: NSPoint) -> Bool {
            abs(layer.position.x + o.x - p.x) < 0.01 && abs(layer.position.y + o.y - p.y) < 0.01
        }
        return ignoresMouseEvents && abs(frame.maxY - a.y) < 0.01 && at(leading, a) && at(trailing, b)
    }

    var probe: Probe {
        let o = frame.origin
        let resizing = [leading, trailing].contains { ($0.animationKeys() ?? []).contains { $0.hasSuffix(".transform.scale") } }
        return Probe(frame: frame, ignoresMouse: ignoresMouseEvents,
                     leading: (NSPoint(x: leading.position.x + o.x, y: leading.position.y + o.y), scales.leading),
                     trailing: (NSPoint(x: trailing.position.x + o.x, y: trailing.position.y + o.y), scales.trailing),
                     extent: radius * ContinuousCorner.extent, resizing: resizing)
    }
}

